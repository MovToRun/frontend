import Foundation
import XCTest
@testable import MovNetworking

final class CommunityPostOperationStoreTests: XCTestCase {
    private let memberID = "123"
    private let attachmentID = "A0000000-0000-4000-8000-000000000001"
    private let assetID = "B0000000-0000-4000-8000-000000000001"
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])

    func testJournalAndAttachmentSurviveNewStoreInstanceAndRemainMemberScoped() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = FileCommunityPostOperationStore(rootURL: root)
        let record = makeRecord(phase: .postCreated, postID: "42", attachmentVersion: 3,
                                attachments: [makeAttachment(assetID: assetID)])
        try original.save(record, attachmentData: [attachmentID: jpeg])

        let restarted = FileCommunityPostOperationStore(rootURL: root)
        let restored = try XCTUnwrap(try restarted.load(memberID: memberID))
        let restoredBytes = try restarted.attachmentData(memberID: memberID, operationID: record.operationID,
                                                          attachmentID: attachmentID)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(restoredBytes, jpeg)
        XCTAssertNil(try restarted.load(memberID: "456"))
    }

    func testCreatingPostJournalIsAmbiguousAfterRestart() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = makeRecord(phase: .creatingPost, postID: nil, attachmentVersion: nil, attachments: [])
        try FileCommunityPostOperationStore(rootURL: root).save(record, attachmentData: [:])

        let restarted = FileCommunityPostOperationStore(rootURL: root)
        let restored = try XCTUnwrap(try restarted.load(memberID: memberID))

        XCTAssertTrue(restored.hasAmbiguousCreate)
        XCTAssertEqual(restored.phase, .creatingPost)
    }

    func testLeaseAndCreateTransitionAreSharedAcrossIndependentStoreInstances() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = FileCommunityPostOperationStore(rootURL: root)
        let second = FileCommunityPostOperationStore(rootURL: root)
        let record = makeRecord(phase: .draftReady, postID: nil, attachmentVersion: nil, attachments: [])
        try first.save(record, attachmentData: [:])

        let firstLease = try first.acquireExecutionLease(memberID: memberID, operationID: record.operationID)
        XCTAssertThrowsError(try second.acquireExecutionLease(memberID: memberID, operationID: record.operationID)) {
            XCTAssertEqual($0 as? CommunityPostOperationStoreError, .operationInProgress)
        }
        XCTAssertThrowsError(try second.save(record, attachmentData: [:])) {
            XCTAssertEqual($0 as? CommunityPostOperationStoreError, .operationInProgress)
        }

        try first.releaseExecutionLease(firstLease)
        let secondLease = try second.acquireExecutionLease(memberID: memberID, operationID: record.operationID)
        XCTAssertThrowsError(try first.releaseExecutionLease(firstLease)) {
            XCTAssertEqual($0 as? CommunityPostOperationStoreError, .executionLeaseInvalid)
        }
        try second.transitionToCreatingPost(record, lease: secondLease)
        XCTAssertEqual(try second.load(memberID: memberID)?.phase, .creatingPost)
        XCTAssertThrowsError(try second.transitionToCreatingPost(record, lease: secondLease)) {
            XCTAssertEqual($0 as? CommunityPostOperationStoreError, .recoveryRequired)
        }
        try second.releaseExecutionLease(secondLease)
    }

    func testCompletedOperationLedgerRetainsOlderIDsAfterNewOperationAndRestart() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCommunityPostOperationStore(rootURL: root)
        let first = makeRecord(phase: .postCreated, postID: "42", attachmentVersion: 1, attachments: [])
        try store.save(first, attachmentData: [:])
        try store.markCompleted(first)

        // The previous version encoded a single completed ID. Verify that adding a
        // second completion migrates that marker instead of replacing its history.
        let legacyMarker = try JSONSerialization.data(withJSONObject: ["operationID": first.operationID.uuidString])
        let markerURL = root.appendingPathComponent("member-\(memberID)", isDirectory: true)
            .appendingPathComponent("completed.json")
        try legacyMarker.write(to: markerURL, options: .atomic)

        let second = makeRecord(phase: .postCreated, postID: "43", attachmentVersion: 1, attachments: [])
        try store.save(second, attachmentData: [:])
        try store.markCompleted(second)

        let restarted = FileCommunityPostOperationStore(rootURL: root)
        XCTAssertNil(try restarted.load(memberID: memberID))
        for completed in [first, second] {
            XCTAssertThrowsError(try restarted.acquireExecutionLease(memberID: memberID, operationID: completed.operationID)) {
                XCTAssertEqual($0 as? CommunityPostOperationStoreError, .operationAlreadyCompleted)
            }
            XCTAssertThrowsError(try restarted.save(completed, attachmentData: [:])) {
                XCTAssertEqual($0 as? CommunityPostOperationStoreError, .operationAlreadyCompleted)
            }
        }
        let third = makeRecord(phase: .draftReady, postID: nil, attachmentVersion: nil, attachments: [])
        XCTAssertNoThrow(try restarted.save(third, attachmentData: [:]))
    }

    func testRemovingLaterDraftDoesNotEraseCompletedOperationHistory() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCommunityPostOperationStore(rootURL: root)
        let first = makeRecord(phase: .postCreated, postID: "42", attachmentVersion: 1, attachments: [])
        try store.save(first, attachmentData: [:])
        try store.markCompleted(first)

        let second = makeRecord(phase: .draftReady, postID: nil, attachmentVersion: nil, attachments: [])
        try store.save(second, attachmentData: [:])
        try store.remove(memberID: memberID, operationID: second.operationID)

        let restarted = FileCommunityPostOperationStore(rootURL: root)
        XCTAssertThrowsError(try restarted.acquireExecutionLease(memberID: memberID, operationID: first.operationID)) {
            XCTAssertEqual($0 as? CommunityPostOperationStoreError, .operationAlreadyCompleted)
        }
    }

    private func makeAttachment(assetID: String?) -> CommunityPostOperationAttachment {
        CommunityPostOperationAttachment(id: attachmentID, contentType: "image/jpeg",
                                         byteCount: Int64(jpeg.count), assetID: assetID)
    }

    private func makeRecord(phase: CommunityPostOperationPhase, postID: String?, attachmentVersion: Int64?,
                            attachments: [CommunityPostOperationAttachment]) -> CommunityPostOperationRecord {
        CommunityPostOperationRecord(operationID: UUID(), memberID: memberID, boardKey: .free,
                                     title: "Morning run", content: "Short update", runID: nil,
                                     phase: phase, postID: postID, attachmentVersion: attachmentVersion,
                                     attachments: attachments)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("community-operation-\(UUID())", isDirectory: true)
    }
}

final class CommunityPostDraftAccountBindingTests: XCTestCase {
    func testPreviewDraftFromOldMemberCannotPublishUnderNewMember() {
        let binding = CommunityPostDraftAccountBinding(memberID: "123", accountScopeID: "old-scope")

        XCTAssertFalse(binding.permitsPublish(memberID: "456", accountScopeID: "new-scope"))
    }

    func testBindingRejectsSameMemberAfterAccountScopeRotation() {
        let binding = CommunityPostDraftAccountBinding(memberID: "123", accountScopeID: "first-login")

        XCTAssertFalse(binding.permitsPublish(memberID: "123", accountScopeID: "second-login"))
    }

    func testBindingAllowsOnlyCapturedMemberAndScope() {
        let binding = CommunityPostDraftAccountBinding(memberID: "123", accountScopeID: "scope")

        XCTAssertTrue(binding.permitsPublish(memberID: "123", accountScopeID: "scope"))
        XCTAssertFalse(CommunityPostDraftAccountBinding(memberID: nil, accountScopeID: "scope")
            .permitsPublish(memberID: "123", accountScopeID: "scope"))
    }
}

final class CommunityPostPublishingServiceTests: XCTestCase {
    private let memberID = "123"

    func testAccountSwitchAndCancellationIgnoreLateCreateReplyButPersistItsKnownPostID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-late-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let operationStore = FileCommunityPostOperationStore(rootURL: root)
        let sessionStore = MutableCommunitySessionStore(snapshot: try makeSession(memberID: "123"))
        let api = GatedCommunityAPI()
        let service = makeService(api: api, store: operationStore, sessionStore: sessionStore)
        let record = makeRecord(memberID: "123", phase: .draftReady, postID: nil, attachments: [])
        let scope = MutableCommunityScope()
        let operation = Task {
            try await service.publish(record: record, attachmentData: [:], isScopeCurrent: { await scope.isCurrent() })
        }

        await api.waitForFirstRequest()
        try sessionStore.replaceAtomically(with: try makeSession(memberID: "456"))
        await scope.setCurrent(false)
        operation.cancel()
        await api.resumeFirst(with: .init(statusCode: 201, data: post(id: "42", version: 0)))

        do {
            _ = try await operation.value
            XCTFail("a late response from the previous account must not complete the active operation")
        } catch let failure as CommunityPostPublishingFailure {
            XCTAssertEqual(failure, .accountScopeChanged)
        } catch { XCTFail("unexpected error: \(error)") }

        let requests = await api.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].path, "community/boards/free/posts")
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer access-123")
        let recovered = try XCTUnwrap(try operationStore.load(memberID: "123"))
        XCTAssertEqual(recovered.phase, .postCreated)
        XCTAssertEqual(recovered.postID, "42")
        XCTAssertNil(try operationStore.load(memberID: "456"))
    }

    func testTwoSceneServicesShareLeaseAndOnlyOneCanSendCreatePost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-scenes-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = FileCommunityPostOperationStore(rootURL: root)
        let secondStore = FileCommunityPostOperationStore(rootURL: root)
        let record = makeRecord(memberID: memberID, phase: .draftReady, postID: nil, attachments: [])
        try firstStore.save(record, attachmentData: [:])

        let api = GatedCommunityAPI(steps: [
            .init(path: "community/posts/42/attachments", method: "PUT",
                  response: .init(statusCode: 200, data: attachmentSet(version: 1, assetID: nil)))
        ], gateFirstRequest: true)
        let sessionStore = MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID))
        let firstService = makeService(api: api, store: firstStore, sessionStore: sessionStore)
        let secondService = makeService(api: api, store: secondStore, sessionStore: sessionStore)
        let firstTask = Task {
            try await firstService.publish(record: record, attachmentData: [:], isScopeCurrent: { true })
        }

        await api.waitForFirstRequest()
        do {
            _ = try await secondService.publish(record: record, attachmentData: [:], isScopeCurrent: { true })
            XCTFail("the second scene must not start a parallel create request")
        } catch let failure as CommunityPostOperationStoreError {
            XCTAssertEqual(failure, .operationInProgress)
        } catch { XCTFail("unexpected error: \(error)") }
        let whileBlocked = await api.recordedRequests()
        XCTAssertEqual(whileBlocked.count, 1)
        XCTAssertEqual(whileBlocked.first?.method, "POST")

        await api.resumeFirst(with: .init(statusCode: 201, data: post(id: "42", version: 0)))
        let result = try await firstTask.value
        XCTAssertEqual(result.snapshot.postID, "42")
        try firstService.removeCompletedOperation(result.operation)

        do {
            _ = try await secondService.publish(record: record, attachmentData: [:], isScopeCurrent: { true })
            XCTFail("a stale operation from another scene must not resurrect the completed create")
        } catch let failure as CommunityPostOperationStoreError {
            XCTAssertEqual(failure, .operationAlreadyCompleted)
        } catch { XCTFail("unexpected error: \(error)") }
        let finalRequests = await api.recordedRequests()
        XCTAssertEqual(finalRequests.map(\.method), ["POST", "PUT"])
    }

    func testStaleFirstOperationAfterSecondCompletionAndRestartCannotAcquireLeaseOrPost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-completed-ledger-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = FileCommunityPostOperationStore(rootURL: root)
        let staleFirst = makeRecord(memberID: memberID, phase: .draftReady, postID: nil, attachments: [])

        var completedFirst = staleFirst
        completedFirst.phase = .postCreated
        completedFirst.postID = "42"
        try firstStore.save(completedFirst, attachmentData: [:])
        try firstStore.markCompleted(completedFirst)

        let completedSecond = makeRecord(memberID: memberID, phase: .postCreated, postID: "43", attachments: [])
        try firstStore.save(completedSecond, attachmentData: [:])
        try firstStore.markCompleted(completedSecond)

        let restartedStore = FileCommunityPostOperationStore(rootURL: root)
        let api = GatedCommunityAPI(steps: [
            .init(path: "never-a-community-route", method: "GET", response: .init(statusCode: 200, data: Data()))
        ])
        let service = makeService(api: api, store: restartedStore,
                                  sessionStore: MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID)))
        do {
            _ = try await service.publish(record: staleFirst, attachmentData: [:], isScopeCurrent: { true })
            XCTFail("the first completed operation must stay retired after a second operation completes and the store restarts")
        } catch let failure as CommunityPostOperationStoreError {
            XCTAssertEqual(failure, .operationAlreadyCompleted)
        } catch { XCTFail("unexpected error: \(error)") }

        let requests = await api.recordedRequests()
        XCTAssertTrue(requests.isEmpty, "a stale operation must fail before it can send another create POST")
    }

    func testKnownPostIDAndAttachmentsResumeWithoutCreatingAnotherPostAfterRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-resume-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = FileCommunityPostOperationStore(rootURL: root)
        let record = makeRecord(memberID: memberID, phase: .postCreated, postID: "42", attachments: [
            CommunityPostOperationAttachment(id: "A0000000-0000-4000-8000-000000000001",
                                              contentType: "image/jpeg", byteCount: 5,
                                              assetID: "B0000000-0000-4000-8000-000000000001")
        ])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])
        try firstStore.save(record, attachmentData: [record.attachments[0].id: jpeg])

        // A new instance models process restart. The durable attachment bytes and post ID
        // are read back before the operation resumes.
        let restartedStore = FileCommunityPostOperationStore(rootURL: root)
        let recovered = try XCTUnwrap(try CommunityPostPublishingService(
            mediaClient: MediaUploadClient(apiClient: EmptyCommunityAPI(), tokenProvider: TestCommunityTokenProvider()),
            communityClient: CommunityMediaClient(apiClient: EmptyCommunityAPI(), tokenProvider: TestCommunityTokenProvider()),
            operationStore: restartedStore, sessionStore: MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID))
        ).recover(memberID: memberID))
        XCTAssertEqual(recovered.0.postID, "42")
        XCTAssertEqual(recovered.1[record.attachments[0].id], jpeg)

        let api = GatedCommunityAPI(steps: [
            .init(path: "community/posts/42", method: "PATCH", response: .init(statusCode: 200, data: post(id: "42", version: 0))),
            .init(path: "community/posts/42/attachments", method: "PUT", response: .init(statusCode: 200, data: attachmentSet(version: 1, assetID: record.attachments[0].assetID!))),
            .init(path: "community/posts/42/attachments/\(record.attachments[0].assetID!.lowercased())", method: "GET", response: .init(statusCode: 200, data: jpeg))
        ])
        let sessionStore = MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID))
        let service = makeService(api: api, store: restartedStore, sessionStore: sessionStore)
        let result = try await service.publish(record: recovered.0, attachmentData: recovered.1, isScopeCurrent: { true })

        XCTAssertEqual(result.snapshot.postID, "42")
        let requests = await api.recordedRequests()
        XCTAssertEqual(requests.map(\.method), ["PATCH", "PUT", "GET"])
        try service.removeCompletedOperation(result.operation)
        XCTAssertNil(try restartedStore.load(memberID: memberID))
    }

    func testAmbiguousCreateRecoveredAfterRestartIsBlockedWithoutAnotherRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-unknown-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCommunityPostOperationStore(rootURL: root)
        let record = makeRecord(memberID: memberID, phase: .creatingPost, postID: nil, attachments: [])
        try store.save(record, attachmentData: [:])
        let restartedStore = FileCommunityPostOperationStore(rootURL: root)
        let api = GatedCommunityAPI()
        let service = makeService(api: api, store: restartedStore,
                                  sessionStore: MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID)))
        let recovered = try XCTUnwrap(try service.recover(memberID: memberID))

        do {
            _ = try await service.publish(record: recovered.0, attachmentData: recovered.1, isScopeCurrent: { true })
            XCTFail("an ambiguous create must remain blocked after process restart")
        } catch let failure as CommunityPostPublishingFailure {
            XCTAssertEqual(failure, .recoveryRequired)
        } catch { XCTFail("unexpected error: \(error)") }
        let requests = await api.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testJournalWriteFailureStopsBeforeNonIdempotentPost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-fail-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = FileCommunityPostOperationStore(rootURL: root)
        let failing = FailingCommunityOperationStore(base: base, failOnSave: 1)
        let api = GatedCommunityAPI()
        let service = makeService(api: api, store: failing,
                                  sessionStore: MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID)))
        do {
            _ = try await service.publish(record: makeRecord(memberID: memberID, phase: .draftReady,
                                                              postID: nil, attachments: []), attachmentData: [:], isScopeCurrent: { true })
            XCTFail("the request must not be sent unless the recovery journal is durable")
        } catch is CommunityPostOperationStoreError {
            // Expected local persistence failure.
        } catch { XCTFail("unexpected error: \(error)") }
        let requests = await api.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testPostCreatedStateSaveFailureLeavesRecoveryMarkerAndNeverReplaysCreate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("community-save-late-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = FileCommunityPostOperationStore(rootURL: root)
        let failing = FailingCommunityOperationStore(base: base, failOnSave: 3)
        let api = GatedCommunityAPI(steps: [
            .init(path: "community/boards/free/posts", method: "POST", response: .init(statusCode: 201, data: post(id: "42", version: 0)))
        ])
        let sessionStore = MutableCommunitySessionStore(snapshot: try makeSession(memberID: memberID))
        let service = makeService(api: api, store: failing, sessionStore: sessionStore)
        do {
            _ = try await service.publish(record: makeRecord(memberID: memberID, phase: .draftReady,
                                                              postID: nil, attachments: []), attachmentData: [:], isScopeCurrent: { true })
            XCTFail("failure to persist the returned post ID must be reported as unknown")
        } catch let failure as CommunityMediaFailure {
            XCTAssertEqual(failure, .postCreationResultUnknown)
            XCTAssertFalse(failure.canManuallyRetry)
        } catch { XCTFail("unexpected error: \(error)") }

        let recovered = try XCTUnwrap(try base.load(memberID: memberID))
        XCTAssertTrue(recovered.hasAmbiguousCreate)
        XCTAssertEqual(recovered.phase, .creatingPost)
        let requests = await api.recordedRequests()
        XCTAssertEqual(requests.map(\.method), ["POST"])
    }

    func testBoundTokenProviderRefusesToReturnNextMembersToken() async throws {
        let store = MutableCommunitySessionStore(snapshot: try makeSession(memberID: "123"))
        let provider = MemberBoundAccessTokenProvider(sessionStore: store, memberID: "123")
        let original = try await provider.accessToken()
        XCTAssertEqual(original, "access-123")
        try store.replaceAtomically(with: makeSession(memberID: "456"))
        do {
            _ = try await provider.accessToken()
            XCTFail("a bound provider must never return a different member's token")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .memberIdentityChanged)
        } catch { XCTFail("unexpected error: \(error)") }
    }

    private func makeService(api: any APIResponseSending, store: any CommunityPostOperationPersisting,
                             sessionStore: any AuthSessionStoring) -> CommunityPostPublishingService {
        CommunityPostPublishingService(
            mediaClient: MediaUploadClient(apiClient: api, tokenProvider: TestCommunityTokenProvider()),
            communityClient: CommunityMediaClient(apiClient: api, tokenProvider: TestCommunityTokenProvider()),
            operationStore: store, sessionStore: sessionStore
        )
    }

    private func makeRecord(memberID: String, phase: CommunityPostOperationPhase, postID: String?,
                            attachments: [CommunityPostOperationAttachment]) -> CommunityPostOperationRecord {
        CommunityPostOperationRecord(operationID: UUID(), memberID: memberID, boardKey: .free,
                                     title: "Morning run", content: "Short update", runID: nil,
                                     phase: phase, postID: postID, attachmentVersion: nil, attachments: attachments)
    }

    private func makeSession(memberID: String) throws -> AuthSessionSnapshot {
        try AuthSessionSnapshot(accessToken: "access-\(memberID)", refreshToken: "refresh-\(memberID)", memberID: memberID)
    }

    private func post(id: String, version: Int) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "postId": id, "boardKey": "free", "title": "Morning run", "content": "Short update",
            "attachmentVersion": version, "attachments": []
        ])
    }

    private func attachmentSet(version: Int, assetID: String?) -> Data {
        let items: [[String: Any]] = assetID.map { [
            ["assetId": $0, "kind": "PHOTO", "contentType": "image/jpeg", "bytes": 5,
             "widthPixels": 1, "heightPixels": 1, "position": 0]
        ] } ?? []
        return try! JSONSerialization.data(withJSONObject: ["attachmentVersion": version, "items": items])
    }
}

private struct TestCommunityTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "unscoped-test-token" }
}

private final class MutableCommunitySessionStore: AuthSessionStoring, @unchecked Sendable {
    let mutationCoordinator = AuthSessionMutationCoordinator()
    private let lock = NSLock()
    private var snapshot: AuthSessionSnapshot?

    init(snapshot: AuthSessionSnapshot?) { self.snapshot = snapshot }
    func loadSnapshot() throws -> AuthSessionSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }
    func replaceAtomically(with snapshot: AuthSessionSnapshot?) throws {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }
}

private actor MutableCommunityScope {
    private var current = true
    func isCurrent() -> Bool { current }
    func setCurrent(_ value: Bool) { current = value }
}

private actor GatedCommunityAPI: APIResponseSending {
    struct Step: Sendable {
        let path: String
        let method: String
        let response: APIClientResponse?
        var transportFailure = false
        init(path: String, method: String, response: APIClientResponse?, transportFailure: Bool = false) {
            self.path = path; self.method = method; self.response = response; self.transportFailure = transportFailure
        }
    }
    struct Request: Sendable {
        let path: String
        let method: String
        let headers: [String: String]
    }
    private var steps: [Step]
    private let gateFirst: Bool
    private var requests: [Request] = []
    private var responseContinuation: CheckedContinuation<APIClientResponse, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(steps: [Step] = [], gateFirstRequest: Bool = false) {
        self.steps = steps; self.gateFirst = gateFirstRequest || steps.isEmpty
    }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String],
                      queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        requests.append(Request(path: path, method: method, headers: headers))
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        if gateFirst && requests.count == 1 {
            return try await withCheckedThrowingContinuation { responseContinuation = $0 }
        }
        guard !steps.isEmpty else { throw APIClientError.unexpectedResponse }
        let step = steps.removeFirst()
        guard step.path == path, step.method == method, queryItems.isEmpty else { throw APIClientError.unexpectedResponse }
        if step.transportFailure { throw APIClientError.transport(.timedOut) }
        guard let response = step.response else { throw APIClientError.unexpectedResponse }
        return response
    }

    func waitForFirstRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeFirst(with response: APIClientResponse) {
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
    }

    func recordedRequests() -> [Request] { requests }
}

private final class FailingCommunityOperationStore: CommunityPostOperationPersisting, @unchecked Sendable {
    private let base: FileCommunityPostOperationStore
    private let failOnSave: Int
    private let lock = NSLock()
    private var saveCount = 0

    init(base: FileCommunityPostOperationStore, failOnSave: Int) {
        self.base = base; self.failOnSave = failOnSave
    }
    func load(memberID: String) throws -> CommunityPostOperationRecord? { try base.load(memberID: memberID) }
    func attachmentData(memberID: String, operationID: UUID, attachmentID: String) throws -> Data {
        try base.attachmentData(memberID: memberID, operationID: operationID, attachmentID: attachmentID)
    }
    func save(_ record: CommunityPostOperationRecord, attachmentData: [String: Data], lease: CommunityPostOperationLease?) throws {
        lock.lock(); saveCount += 1; let shouldFail = saveCount == failOnSave; lock.unlock()
        if shouldFail { throw CommunityPostOperationStoreError.storageUnavailable }
        try base.save(record, attachmentData: attachmentData, lease: lease)
    }
    func acquireExecutionLease(memberID: String, operationID: UUID) throws -> CommunityPostOperationLease {
        try base.acquireExecutionLease(memberID: memberID, operationID: operationID)
    }
    func releaseExecutionLease(_ lease: CommunityPostOperationLease) throws { try base.releaseExecutionLease(lease) }
    func transitionToCreatingPost(_ record: CommunityPostOperationRecord, lease: CommunityPostOperationLease) throws {
        lock.lock(); saveCount += 1; let shouldFail = saveCount == failOnSave; lock.unlock()
        if shouldFail { throw CommunityPostOperationStoreError.storageUnavailable }
        try base.transitionToCreatingPost(record, lease: lease)
    }
    func markCompleted(_ record: CommunityPostOperationRecord) throws { try base.markCompleted(record) }
    func remove(memberID: String, operationID: UUID) throws { try base.remove(memberID: memberID, operationID: operationID) }
}

private struct EmptyCommunityAPI: APIResponseSending {
    func sendResponse(path: String, method: String, body: Data?, headers: [String: String],
                      queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        throw APIClientError.unexpectedResponse
    }
}
