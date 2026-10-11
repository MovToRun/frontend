import Foundation

struct RunUploadEnvelope: Codable, Equatable, Sendable {
    /// Stable account identity captured when this payload is enqueued.
    let ownerID: String
    /// Immutable measured payload. Editing metadata later must not mutate a queued retry.
    let payload: RunUploadPayload
}

struct RunUploadOutboxEntry: Codable, Equatable, Sendable {
    enum State: Codable, Equatable, Sendable {
        case pending
        case terminal(code: String)
    }

    let envelope: RunUploadEnvelope
    let state: State
}

enum RunUploadOutboxPersistenceFailure: Error, Equatable, Sendable {
    case unreadable
    case corrupt
    case unsupportedVersion
    case writeFailed
}

protocol RunUploadOutboxPersisting: Sendable {
    /// A missing file is an empty outbox. Existing unreadable or corrupt data must throw.
    func load() throws -> [RunUploadOutboxEntry]
    /// Replace the complete outbox atomically or throw without changing the prior value.
    func saveAtomically(_ entries: [RunUploadOutboxEntry]) throws
}

final class FileRunUploadOutboxPersistence: RunUploadOutboxPersisting, @unchecked Sendable {
    private struct StoredOutbox: Codable {
        let version: Int
        let entries: [RunUploadOutboxEntry]
    }

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> [RunUploadOutboxEntry] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RunUploadOutboxPersistenceFailure.unreadable
        }

        do {
            let stored = try JSONDecoder().decode(StoredOutbox.self, from: data)
            guard stored.version == 1 else { throw RunUploadOutboxPersistenceFailure.unsupportedVersion }
            return stored.entries
        } catch let failure as RunUploadOutboxPersistenceFailure {
            throw failure
        } catch {
            throw RunUploadOutboxPersistenceFailure.corrupt
        }
    }

    func saveAtomically(_ entries: [RunUploadOutboxEntry]) throws {
        lock.lock()
        defer { lock.unlock() }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(StoredOutbox(version: 1, entries: entries))
        } catch {
            throw RunUploadOutboxPersistenceFailure.writeFailed
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RunUploadOutboxPersistenceFailure.writeFailed
        }
    }
}

enum RunUploadDrainStopReason: Equatable, Sendable {
    case finished
    case busy
    case sessionUnavailable
    case ownerMismatch
    case accountChanged
    case cancelled
    case retryLater(clientRunID: UUID, code: String)
}

struct RunUploadDrainReport: Equatable, Sendable {
    let uploadedCount: Int
    let deletedCount: Int
    let terminalCount: Int
    let stopReason: RunUploadDrainStopReason
}

enum RunUploadOutboxFailure: Error, Equatable, Sendable {
    case invalidOwnerID
    case duplicateClientRunIDConflict
}

actor RunUploadOutbox {
    private let persistence: any RunUploadOutboxPersisting
    private let sessionProvider: any RunUploadSessionProviding
    private let uploader: any RunUploading
    private var entries: [RunUploadOutboxEntry]
    private var isDraining = false

    init(
        persistence: any RunUploadOutboxPersisting,
        sessionProvider: any RunUploadSessionProviding,
        uploader: any RunUploading
    ) throws {
        self.persistence = persistence
        self.sessionProvider = sessionProvider
        self.uploader = uploader
        self.entries = try persistence.load()
    }

    /// Returns true when a new durable item was written, false for an identical duplicate.
    @discardableResult
    func enqueue(_ payload: RunUploadPayload, ownerID: String) throws -> Bool {
        guard Self.isValidOwnerID(ownerID) else { throw RunUploadOutboxFailure.invalidOwnerID }

        let envelope = RunUploadEnvelope(ownerID: ownerID, payload: payload)
        if let existing = entries.first(where: {
            $0.envelope.ownerID == ownerID && $0.envelope.payload.clientRunID == payload.clientRunID
        }) {
            guard existing.envelope.payload == payload else {
                throw RunUploadOutboxFailure.duplicateClientRunIDConflict
            }
            return false
        }

        let next = entries + [RunUploadOutboxEntry(envelope: envelope, state: .pending)]
        try persistence.saveAtomically(next)
        entries = next
        return true
    }

    func snapshot() -> [RunUploadOutboxEntry] { entries }

    /// Manual only: this actor has no timer, background task, or automatic retry trigger.
    func drain() async throws -> RunUploadDrainReport {
        guard !isDraining else {
            return Self.report(stop: .busy)
        }
        isDraining = true
        defer { isDraining = false }

        var uploadedCount = 0
        var deletedCount = 0
        var terminalCount = 0

        let initialSession: RunUploadSession?
        do {
            initialSession = try await sessionProvider.currentSession()
        } catch is CancellationError {
            return Self.report(uploaded: 0, deleted: 0, terminal: 0, stop: .cancelled)
        } catch {
            return Self.report(uploaded: 0, deleted: 0, terminal: 0, stop: .sessionUnavailable)
        }
        guard let initialSession, Self.isValidSession(initialSession) else {
            return Self.report(uploaded: 0, deleted: 0, terminal: 0, stop: .sessionUnavailable)
        }

        let eligibleKeys = entries.compactMap { entry -> (String, UUID)? in
            guard entry.state == .pending, entry.envelope.ownerID == initialSession.ownerID else { return nil }
            return (entry.envelope.ownerID, entry.envelope.payload.clientRunID)
        }
        if eligibleKeys.isEmpty {
            let hasPendingForOtherOwner = entries.contains { $0.state == .pending }
            let stop: RunUploadDrainStopReason = hasPendingForOtherOwner ? .ownerMismatch : .finished
            return Self.report(uploaded: 0, deleted: 0, terminal: 0, stop: stop)
        }

        for (ownerID, clientRunID) in eligibleKeys {
            if Task.isCancelled {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            }
            guard let entry = entries.first(where: {
                $0.envelope.ownerID == ownerID && $0.envelope.payload.clientRunID == clientRunID
            }), entry.state == .pending else { continue }

            let session: RunUploadSession?
            do {
                session = try await sessionProvider.currentSession()
            } catch is CancellationError {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            } catch {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .sessionUnavailable)
            }
            guard let session, Self.isValidSession(session) else {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .sessionUnavailable)
            }
            guard session.ownerID == ownerID else {
                let stop: RunUploadDrainStopReason = uploadedCount + deletedCount + terminalCount == 0 ? .ownerMismatch : .accountChanged
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: stop)
            }

            let delivery: RunUploadDelivery
            do {
                delivery = try await uploader.upload(entry.envelope.payload, session: session)
            } catch is CancellationError {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            } catch {
                return Self.report(
                    uploaded: uploadedCount,
                    deleted: deletedCount,
                    terminal: terminalCount,
                    stop: .retryLater(clientRunID: clientRunID, code: "TRANSPORT")
                )
            }

            if Task.isCancelled {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            }

            let sessionAfterDelivery: RunUploadSession?
            do {
                sessionAfterDelivery = try await sessionProvider.currentSession()
            } catch is CancellationError {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            } catch {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .accountChanged)
            }
            guard let sessionAfterDelivery, Self.isValidSession(sessionAfterDelivery), sessionAfterDelivery.ownerID == ownerID else {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .accountChanged)
            }

            switch delivery {
            case .accepted:
                try remove(ownerID: ownerID, clientRunID: clientRunID)
                uploadedCount += 1
            case .alreadyDeleted:
                try remove(ownerID: ownerID, clientRunID: clientRunID)
                deletedCount += 1
            case .terminal(let code):
                try markTerminal(ownerID: ownerID, clientRunID: clientRunID, code: code)
                terminalCount += 1
            case .retryLater(let code):
                return Self.report(
                    uploaded: uploadedCount,
                    deleted: deletedCount,
                    terminal: terminalCount,
                    stop: .retryLater(clientRunID: clientRunID, code: code)
                )
            }
        }

        return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .finished)
    }

    private func remove(ownerID: String, clientRunID: UUID) throws {
        let next = entries.filter {
            !($0.envelope.ownerID == ownerID && $0.envelope.payload.clientRunID == clientRunID)
        }
        try persistence.saveAtomically(next)
        entries = next
    }

    private func markTerminal(ownerID: String, clientRunID: UUID, code: String) throws {
        let next = entries.map { entry -> RunUploadOutboxEntry in
            guard entry.envelope.ownerID == ownerID,
                  entry.envelope.payload.clientRunID == clientRunID else { return entry }
            return RunUploadOutboxEntry(envelope: entry.envelope, state: .terminal(code: code))
        }
        try persistence.saveAtomically(next)
        entries = next
    }

    private static func isValidOwnerID(_ ownerID: String) -> Bool {
        !ownerID.isEmpty && ownerID.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isValidSession(_ session: RunUploadSession) -> Bool {
        isValidOwnerID(session.ownerID)
            && !session.accessToken.isEmpty
            && session.accessToken.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }

    private static func report(
        uploaded: Int = 0,
        deleted: Int = 0,
        terminal: Int = 0,
        stop: RunUploadDrainStopReason
    ) -> RunUploadDrainReport {
        RunUploadDrainReport(uploadedCount: uploaded, deletedCount: deleted, terminalCount: terminal, stopReason: stop)
    }
}
