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
    /// Stable within the process for every persistence instance that shares storage.
    var drainOwnershipKey: String { get }
    /// A missing file is an empty outbox. Existing unreadable or corrupt data must throw.
    func load() throws -> [RunUploadOutboxEntry]
    /// Read, transform, and atomically replace one current snapshot under a storage-wide lock.
    func transact<Result>(
        _ update: ([RunUploadOutboxEntry]) throws -> RunUploadOutboxMutation<Result>
    ) throws -> Result
}

/// Narrow persistence seam for the local run lifecycle. Enqueueing never starts a drain.
protocol RunUploadEnqueueing: Sendable {
    func enqueueRunUpload(_ payload: RunUploadPayload, ownerID: String) async throws
}

/// Withdrawal removes only queued payloads assigned to the withdrawn member.
protocol RunUploadOwnerScopedClearing: Sendable {
    func clearRunUploads(ownerID: String) async throws
}

/// App-triggered upload boundary. The expected owner is captured from the authenticated
/// identity provider and checked against the uploader session before any request is sent.
protocol RunUploadDraining: Sendable {
    func drain(ownerID: String) async throws -> RunUploadDrainReport
}

struct RunUploadOutboxMutation<Result> {
    let entries: [RunUploadOutboxEntry]
    let result: Result
}

private final class OutboxPathLockRegistry: @unchecked Sendable {
    private let registryLock = NSLock()
    private var locks: [String: NSRecursiveLock] = [:]

    func lock(for path: String) -> NSRecursiveLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[path] { return existing }
        let created = NSRecursiveLock()
        locks[path] = created
        return created
    }
}

private actor RunUploadDrainOwnershipRegistry {
    static let shared = RunUploadDrainOwnershipRegistry()
    private var ownedPaths = Set<String>()

    func acquire(_ key: String) -> Bool {
        ownedPaths.insert(key).inserted
    }

    func release(_ key: String) {
        ownedPaths.remove(key)
    }
}

final class FileRunUploadOutboxPersistence: RunUploadOutboxPersisting, @unchecked Sendable {
    private struct StoredOutbox: Codable {
        let version: Int
        let entries: [RunUploadOutboxEntry]
    }

    private static let pathLockRegistry = OutboxPathLockRegistry()
    private let fileURL: URL
    private let lock: NSRecursiveLock

    var drainOwnershipKey: String { fileURL.path }

    init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        self.lock = Self.pathLockRegistry.lock(for: self.fileURL.path)
    }

    func load() throws -> [RunUploadOutboxEntry] {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    func transact<Result>(
        _ update: ([RunUploadOutboxEntry]) throws -> RunUploadOutboxMutation<Result>
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        let current = try loadUnlocked()
        let mutation = try update(current)
        if mutation.entries != current {
            try saveUnlocked(mutation.entries)
        }
        return mutation.result
    }

    private func loadUnlocked() throws -> [RunUploadOutboxEntry] {
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

    private func saveUnlocked(_ entries: [RunUploadOutboxEntry]) throws {
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
    private let drainOwnershipKey: String
    private var isDraining = false

    init(
        persistence: any RunUploadOutboxPersisting,
        sessionProvider: any RunUploadSessionProviding,
        uploader: any RunUploading
    ) throws {
        self.persistence = persistence
        self.sessionProvider = sessionProvider
        self.uploader = uploader
        self.drainOwnershipKey = persistence.drainOwnershipKey
        _ = try persistence.load()
    }

    /// Returns true when a new durable item was written, false for an identical duplicate.
    @discardableResult
    func enqueue(_ payload: RunUploadPayload, ownerID: String) throws -> Bool {
        guard Self.isValidOwnerID(ownerID) else { throw RunUploadOutboxFailure.invalidOwnerID }

        return try persistence.transact { current in
            if let existing = current.first(where: {
                $0.envelope.ownerID == ownerID && $0.envelope.payload.clientRunID == payload.clientRunID
            }) {
                guard existing.envelope.payload == payload else {
                    throw RunUploadOutboxFailure.duplicateClientRunIDConflict
                }
                return RunUploadOutboxMutation(entries: current, result: false)
            }

            let envelope = RunUploadEnvelope(ownerID: ownerID, payload: payload)
            let next = current + [RunUploadOutboxEntry(envelope: envelope, state: .pending)]
            return RunUploadOutboxMutation(entries: next, result: true)
        }
    }

    func snapshot() throws -> [RunUploadOutboxEntry] { try persistence.load() }

    /// Manual only: this actor has no timer, background task, or automatic retry trigger.
    func drain() async throws -> RunUploadDrainReport {
        try await performDrain(expectedOwnerID: nil)
    }

    /// Manual app boundary that pins the authenticated identity observed by RunStore.
    func drain(ownerID: String) async throws -> RunUploadDrainReport {
        guard Self.isValidOwnerID(ownerID) else {
            return Self.report(stop: .sessionUnavailable)
        }
        return try await performDrain(expectedOwnerID: ownerID)
    }

    private func performDrain(expectedOwnerID: String?) async throws -> RunUploadDrainReport {
        guard !isDraining else {
            return Self.report(stop: .busy)
        }
        isDraining = true
        defer { isDraining = false }

        guard await RunUploadDrainOwnershipRegistry.shared.acquire(drainOwnershipKey) else {
            return Self.report(stop: .busy)
        }
        do {
            let report = try await drainOwnedPath(expectedOwnerID: expectedOwnerID)
            await RunUploadDrainOwnershipRegistry.shared.release(drainOwnershipKey)
            return report
        } catch {
            await RunUploadDrainOwnershipRegistry.shared.release(drainOwnershipKey)
            throw error
        }
    }

    private func drainOwnedPath(expectedOwnerID: String?) async throws -> RunUploadDrainReport {
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
        guard expectedOwnerID == nil || initialSession.ownerID == expectedOwnerID else {
            return Self.report(uploaded: 0, deleted: 0, terminal: 0, stop: .ownerMismatch)
        }

        let initialEntries = try persistence.load()
        terminalCount = initialEntries.reduce(into: 0) { count, entry in
            guard entry.envelope.ownerID == initialSession.ownerID else { return }
            if case .terminal = entry.state { count += 1 }
        }
        let eligibleKeys = initialEntries.compactMap { entry -> (String, UUID)? in
            guard entry.state == .pending, entry.envelope.ownerID == initialSession.ownerID else { return nil }
            return (entry.envelope.ownerID, entry.envelope.payload.clientRunID)
        }
        if eligibleKeys.isEmpty {
            let hasPendingForOtherOwner = initialEntries.contains { $0.state == .pending }
            let stop: RunUploadDrainStopReason = hasPendingForOtherOwner ? .ownerMismatch : .finished
            return Self.report(uploaded: 0, deleted: 0, terminal: terminalCount, stop: stop)
        }

        for (ownerID, clientRunID) in eligibleKeys {
            if Task.isCancelled {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
            }
            let latestEntries = try persistence.load()
            guard let entry = latestEntries.first(where: {
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
            if Task.isCancelled {
                return Self.report(uploaded: uploadedCount, deleted: deletedCount, terminal: terminalCount, stop: .cancelled)
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
        try persistence.transact { current in
            let next = current.filter {
                !($0.envelope.ownerID == ownerID && $0.envelope.payload.clientRunID == clientRunID)
            }
            return RunUploadOutboxMutation(entries: next, result: ())
        }
    }

    private func markTerminal(ownerID: String, clientRunID: UUID, code: String) throws {
        try persistence.transact { current in
            let next = current.map { entry -> RunUploadOutboxEntry in
                guard entry.envelope.ownerID == ownerID,
                      entry.envelope.payload.clientRunID == clientRunID else { return entry }
                return RunUploadOutboxEntry(envelope: entry.envelope, state: .terminal(code: code))
            }
            return RunUploadOutboxMutation(entries: next, result: ())
        }
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

extension RunUploadOutbox: RunUploadEnqueueing, RunUploadOwnerScopedClearing {
    func enqueueRunUpload(_ payload: RunUploadPayload, ownerID: String) async throws {
        _ = try enqueue(payload, ownerID: ownerID)
    }

    func clearRunUploads(ownerID: String) async throws {
        guard Self.isValidOwnerID(ownerID) else { throw RunUploadOutboxFailure.invalidOwnerID }
        try persistence.transact { current in
            let next = current.filter { $0.envelope.ownerID != ownerID }
            return RunUploadOutboxMutation(entries: next, result: ())
        }
    }
}

extension RunUploadOutbox: RunUploadDraining {}
