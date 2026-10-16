import Foundation

enum CommunityPostOperationPhase: String, Codable, Equatable, Sendable {
    case draftReady
    case uploadingAttachments
    /// Written durably before the non-idempotent create request is sent.
    case creatingPost
    case createResultUnknown
    case postCreated
}

struct CommunityPostOperationAttachment: Codable, Equatable, Sendable {
    let id: String
    let contentType: String
    let byteCount: Int64
    var assetID: String?
}

struct CommunityPostOperationRecord: Codable, Equatable, Sendable {
    let operationID: UUID
    let memberID: String
    var boardKey: CommunityPostBoardKey
    var title: String
    var content: String
    var runID: String?
    var phase: CommunityPostOperationPhase
    var postID: String?
    var attachmentVersion: Int64?
    var attachments: [CommunityPostOperationAttachment]

    var hasAmbiguousCreate: Bool {
        postID == nil && (phase == .creatingPost || phase == .createResultUnknown)
    }
}

protocol CommunityPostOperationPersisting: Sendable {
    func load(memberID: String) throws -> CommunityPostOperationRecord?
    func attachmentData(memberID: String, operationID: UUID, attachmentID: String) throws -> Data
    func save(_ record: CommunityPostOperationRecord, attachmentData: [String: Data]) throws
    func remove(memberID: String, operationID: UUID) throws
}

enum CommunityPostOperationStoreError: Error, Equatable {
    case invalidMemberID
    case invalidRecord
    case operationAlreadyExists
    case operationNotFound
    case attachmentNotFound
    case storageUnavailable
}

/// Stores one unfinished remote community post per authenticated member. The journal
/// lives under Application Support rather than the purgeable temporary-directory
/// attachment cache. A `creatingPost` journal is intentionally considered ambiguous
/// after relaunch because the current create API has no idempotency or lookup key.
final class FileCommunityPostOperationStore: CommunityPostOperationPersisting, @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            let bundleID = Bundle.main.bundleIdentifier ?? "com.movtorun.mov"
            self.rootURL = applicationSupport
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("CommunityPostOperations", isDirectory: true)
        }
    }

    func load(memberID: String) throws -> CommunityPostOperationRecord? {
        try withLock {
            let folder = try memberFolder(memberID)
            let manifest = folder.appendingPathComponent("operation.json")
            guard fileManager.fileExists(atPath: manifest.path) else { return nil }
            do {
                let data = try Data(contentsOf: manifest, options: .mappedIfSafe)
                let record = try JSONDecoder().decode(CommunityPostOperationRecord.self, from: data)
                guard record.memberID == memberID, Self.isValid(record) else {
                    throw CommunityPostOperationStoreError.invalidRecord
                }
                return record
            } catch let error as CommunityPostOperationStoreError {
                throw error
            } catch {
                throw CommunityPostOperationStoreError.storageUnavailable
            }
        }
    }

    func attachmentData(memberID: String, operationID: UUID, attachmentID: String) throws -> Data {
        try withLock {
            let record = try loadUnlocked(memberID: memberID)
            guard let record, record.operationID == operationID,
                  let attachment = record.attachments.first(where: { $0.id == attachmentID }) else {
                throw CommunityPostOperationStoreError.attachmentNotFound
            }
            let url = attachmentURL(for: attachment, memberID: memberID)
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard Int64(data.count) == attachment.byteCount,
                      MediaUploadPolicy.signatureMatches(MediaUploadFile(contentType: attachment.contentType, data: data)) else {
                    throw CommunityPostOperationStoreError.invalidRecord
                }
                return data
            } catch let error as CommunityPostOperationStoreError {
                throw error
            } catch {
                throw CommunityPostOperationStoreError.attachmentNotFound
            }
        }
    }

    func save(_ record: CommunityPostOperationRecord, attachmentData: [String: Data]) throws {
        try withLock {
            guard Self.isValid(record) else { throw CommunityPostOperationStoreError.invalidRecord }
            let folder = try memberFolder(record.memberID)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                if let existing = try loadUnlocked(memberID: record.memberID), existing.operationID != record.operationID {
                    throw CommunityPostOperationStoreError.operationAlreadyExists
                }

                for attachment in record.attachments {
                    let url = attachmentURL(for: attachment, memberID: record.memberID)
                    if let data = attachmentData[attachment.id] {
                        guard Int64(data.count) == attachment.byteCount,
                              MediaUploadPolicy.signatureMatches(MediaUploadFile(contentType: attachment.contentType, data: data)) else {
                            throw CommunityPostOperationStoreError.invalidRecord
                        }
                        try data.write(to: url, options: .atomic)
                    } else {
                        guard fileManager.fileExists(atPath: url.path),
                              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                              size == Int(attachment.byteCount) else {
                            throw CommunityPostOperationStoreError.attachmentNotFound
                        }
                    }
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let encoded = try encoder.encode(record)
                try encoded.write(to: folder.appendingPathComponent("operation.json"), options: .atomic)

                let keep = Set(record.attachments.map(Self.fileName(for:)))
                for url in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                where url.lastPathComponent != "operation.json" && !keep.contains(url.lastPathComponent) {
                    try? fileManager.removeItem(at: url)
                }
            } catch let error as CommunityPostOperationStoreError {
                throw error
            } catch {
                throw CommunityPostOperationStoreError.storageUnavailable
            }
        }
    }

    func remove(memberID: String, operationID: UUID) throws {
        try withLock {
            let folder = try memberFolder(memberID)
            guard let record = try loadUnlocked(memberID: memberID) else { return }
            guard record.operationID == operationID else { throw CommunityPostOperationStoreError.operationAlreadyExists }
            do { try fileManager.removeItem(at: folder) }
            catch { throw CommunityPostOperationStoreError.storageUnavailable }
        }
    }

    private func loadUnlocked(memberID: String) throws -> CommunityPostOperationRecord? {
        let folder = try memberFolder(memberID)
        let manifest = folder.appendingPathComponent("operation.json")
        guard fileManager.fileExists(atPath: manifest.path) else { return nil }
        do {
            let data = try Data(contentsOf: manifest, options: .mappedIfSafe)
            let record = try JSONDecoder().decode(CommunityPostOperationRecord.self, from: data)
            guard record.memberID == memberID, Self.isValid(record) else {
                throw CommunityPostOperationStoreError.invalidRecord
            }
            return record
        } catch let error as CommunityPostOperationStoreError {
            throw error
        } catch {
            throw CommunityPostOperationStoreError.storageUnavailable
        }
    }

    private func memberFolder(_ memberID: String) throws -> URL {
        guard AuthSessionSnapshot.isCanonicalMemberID(memberID) else {
            throw CommunityPostOperationStoreError.invalidMemberID
        }
        return rootURL.appendingPathComponent("member-\(memberID)", isDirectory: true)
    }

    private func attachmentURL(for attachment: CommunityPostOperationAttachment, memberID: String) -> URL {
        let ext = attachment.contentType == "image/png" ? "png" : "jpg"
        return rootURL.appendingPathComponent("member-\(memberID)", isDirectory: true)
            .appendingPathComponent("attachment-\(attachment.id.lowercased())")
            .appendingPathExtension(ext)
    }

    private static func fileName(for attachment: CommunityPostOperationAttachment) -> String {
        "attachment-\(attachment.id.lowercased())" + (attachment.contentType == "image/png" ? ".png" : ".jpg")
    }

    private static func isValid(_ record: CommunityPostOperationRecord) -> Bool {
        guard AuthSessionSnapshot.isCanonicalMemberID(record.memberID),
              !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.title.count <= 60, record.content.count <= 2_000,
              record.attachments.count <= MediaUploadPolicy.postMaximumItems,
              Set(record.attachments.map(\.id)).count == record.attachments.count,
              record.attachments.allSatisfy({
                  UUID(uuidString: $0.id) != nil && $0.byteCount > 0
                      && $0.byteCount <= MediaUploadPolicy.postPhotoUploadMaximumBytes
                      && ($0.contentType == "image/jpeg" || $0.contentType == "image/png")
                      && ($0.assetID.map { UUID(uuidString: $0) != nil } ?? true)
              }) else { return false }
        guard record.attachments.reduce(Int64(0), { $0 + $1.byteCount }) <= MediaUploadPolicy.postBatchMaximumBytes else {
            return false
        }
        if let postID = record.postID, !isCanonicalPostID(postID) { return false }
        if record.boardKey == .runningVerification,
           record.runID.map(isCanonicalPostID) != true {
            return false
        }
        return record.attachmentVersion.map { $0 >= 0 } ?? true
    }

    private static func isCanonicalPostID(_ value: String) -> Bool {
        guard value.utf8.allSatisfy({ (48...57).contains($0) }), let parsed = Int64(value), parsed > 0 else {
            return false
        }
        return String(parsed) == value
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

struct MemberBoundAccessTokenProvider: AccessTokenProviding {
    let sessionStore: any AuthSessionStoring
    let memberID: String

    func accessToken() async throws -> String? {
        guard !Task.isCancelled,
              let snapshot = try sessionStore.loadSnapshot(), snapshot.memberID == memberID else {
            throw AuthSessionFailure.memberIdentityChanged
        }
        return snapshot.accessToken
    }
}

enum CommunityPostPublishingFailure: Error, Equatable, Sendable {
    case accountScopeChanged
    case operationRecordUnavailable
    case recoveryRequired
}

enum CommunityPostPublishStage: Sendable {
    case uploadingAttachments
    case creatingPost
    case updatingPost
    case attaching
    case verifying
}

struct CommunityPostPublishResult: Equatable, Sendable {
    let snapshot: CommunityPostSnapshot
    let operation: CommunityPostOperationRecord
}

struct CommunityPostPublishingService: Sendable {
    private let mediaClient: MediaUploadClient
    private let communityClient: CommunityMediaClient
    private let operationStore: any CommunityPostOperationPersisting
    private let sessionStore: any AuthSessionStoring

    func recover(memberID: String) throws -> (CommunityPostOperationRecord, [String: Data])? {
        guard let record = try operationStore.load(memberID: memberID) else { return nil }
        var data: [String: Data] = [:]
        for attachment in record.attachments {
            data[attachment.id] = try operationStore.attachmentData(
                memberID: memberID, operationID: record.operationID, attachmentID: attachment.id
            )
        }
        return (record, data)
    }

    func publish(
        record initialRecord: CommunityPostOperationRecord,
        attachmentData initialAttachmentData: [String: Data],
        isScopeCurrent: @escaping @Sendable () async -> Bool,
        onStage: @escaping @Sendable (CommunityPostPublishStage) async -> Void = { _ in }
    ) async throws -> CommunityPostPublishResult {
        try await requireCurrentScope(isScopeCurrent)
        guard !initialRecord.hasAmbiguousCreate else { throw CommunityPostPublishingFailure.recoveryRequired }

        var record = initialRecord
        try operationStore.save(record, attachmentData: initialAttachmentData)
        try await requireCurrentScope(isScopeCurrent)

        let boundTokens = MemberBoundAccessTokenProvider(sessionStore: sessionStore, memberID: record.memberID)
        let mediaClient = mediaClient.scoped(to: boundTokens)
        let communityClient = communityClient.scoped(to: boundTokens)

        let missing = record.attachments.filter { $0.assetID == nil }
        if !missing.isEmpty {
            await onStage(.uploadingAttachments)
            try await requireCurrentScope(isScopeCurrent)
            record.phase = .uploadingAttachments
            try operationStore.save(record, attachmentData: [:])
            try await requireCurrentScope(isScopeCurrent)
            let files = try missing.map { attachment -> MediaUploadFile in
                guard let data = initialAttachmentData[attachment.id]
                    ?? (try? operationStore.attachmentData(memberID: record.memberID,
                                                          operationID: record.operationID,
                                                          attachmentID: attachment.id)) else {
                    throw CommunityPostOperationStoreError.attachmentNotFound
                }
                return MediaUploadFile(contentType: attachment.contentType, data: data)
            }
            let ready = try await mediaClient.upload(files, purpose: .postAttachment)
            for (attachment, item) in zip(missing, ready.items) {
                guard let index = record.attachments.firstIndex(where: { $0.id == attachment.id }) else {
                    throw CommunityPostOperationStoreError.invalidRecord
                }
                record.attachments[index].assetID = item.assetID
            }
            // These assets belong to the captured member even if the view scope
            // changed while the response was in flight. Keep the mapping recoverable.
            try operationStore.save(record, attachmentData: [:])
            try await requireCurrentScope(isScopeCurrent)
        }

        let post: CommunityPostSnapshot
        if let postID = record.postID {
            await onStage(.updatingPost)
            try await requireCurrentScope(isScopeCurrent)
            post = try await communityClient.updatePost(postID: postID, title: record.title, content: record.content)
            record.attachmentVersion = post.attachmentVersion
            record.phase = .postCreated
            try operationStore.save(record, attachmentData: [:])
            try await requireCurrentScope(isScopeCurrent)
        } else {
            guard !record.hasAmbiguousCreate else { throw CommunityPostPublishingFailure.recoveryRequired }
            await onStage(.creatingPost)
            try await requireCurrentScope(isScopeCurrent)
            record.phase = .creatingPost
            // If this write fails, no non-idempotent POST is sent.
            try operationStore.save(record, attachmentData: [:])
            try await requireCurrentScope(isScopeCurrent)
            do {
                post = try await communityClient.createPost(board: record.boardKey, title: record.title,
                                                            content: record.content, runID: record.runID)
            } catch let failure as CommunityMediaFailure {
                if failure == .postCreationResultUnknown {
                    record.phase = .createResultUnknown
                } else {
                    record.phase = .draftReady
                }
                try? operationStore.save(record, attachmentData: [:])
                throw failure
            }
            record.postID = post.postID
            record.attachmentVersion = post.attachmentVersion
            record.phase = .postCreated
            do { try operationStore.save(record, attachmentData: [:]) }
            catch { throw CommunityMediaFailure.postCreationResultUnknown }
            // The reply is durably associated with the original member before this
            // check; a late reply can never be applied to the newly selected account.
            try await requireCurrentScope(isScopeCurrent)
        }

        guard let postID = record.postID,
              record.attachments.allSatisfy({ $0.assetID != nil }) else {
            throw CommunityPostOperationStoreError.invalidRecord
        }
        await onStage(.attaching)
        try await requireCurrentScope(isScopeCurrent)
        let assetIDs = record.attachments.compactMap(\.assetID)
        let updated = try await communityClient.replaceAttachments(
            postID: postID, expectedVersion: record.attachmentVersion ?? post.attachmentVersion,
            assetIDs: assetIDs
        )
        record.attachmentVersion = updated.attachmentVersion
        record.phase = .postCreated
        try operationStore.save(record, attachmentData: [:])
        try await requireCurrentScope(isScopeCurrent)

        await onStage(.verifying)
        try await requireCurrentScope(isScopeCurrent)
        for attachment in updated.attachments {
            _ = try await communityClient.readAttachment(postID: postID, attachment: attachment)
            try await requireCurrentScope(isScopeCurrent)
        }
        return CommunityPostPublishResult(snapshot: updated, operation: record)
    }

    func removeCompletedOperation(_ record: CommunityPostOperationRecord) throws {
        guard record.postID != nil, record.phase == .postCreated else {
            throw CommunityPostOperationStoreError.invalidRecord
        }
        try operationStore.remove(memberID: record.memberID, operationID: record.operationID)
    }

    init(mediaClient: MediaUploadClient, communityClient: CommunityMediaClient,
         operationStore: any CommunityPostOperationPersisting, sessionStore: any AuthSessionStoring) {
        self.mediaClient = mediaClient
        self.communityClient = communityClient
        self.operationStore = operationStore
        self.sessionStore = sessionStore
    }

    private func requireCurrentScope(_ isCurrent: @Sendable () async -> Bool) async throws {
        guard !Task.isCancelled, await isCurrent() else {
            throw CommunityPostPublishingFailure.accountScopeChanged
        }
    }
}
