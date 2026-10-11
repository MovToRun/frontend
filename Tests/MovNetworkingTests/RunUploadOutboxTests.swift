import Foundation
import XCTest
@testable import MovNetworking

private final class MemoryOutboxPersistence: RunUploadOutboxPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RunUploadOutboxEntry] = []
    private var shouldFailNextSave = false

    func load() throws -> [RunUploadOutboxEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func saveAtomically(_ entries: [RunUploadOutboxEntry]) throws {
        lock.lock(); defer { lock.unlock() }
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw RunUploadOutboxPersistenceFailure.writeFailed
        }
        stored = entries
    }

    func failNextSave() {
        lock.lock(); defer { lock.unlock() }
        shouldFailNextSave = true
    }
}

private actor MutableUploadSessionProvider: RunUploadSessionProviding {
    private var session: RunUploadSession?

    init(_ session: RunUploadSession?) { self.session = session }
    func currentSession() async throws -> RunUploadSession? { session }
    func set(_ session: RunUploadSession?) { self.session = session }
}

private actor RecordingRunUploader: RunUploading {
    private var deliveries: [RunUploadDelivery]
    private var recorded: [(RunUploadPayload, RunUploadSession)] = []
    private let afterUpload: (@Sendable () async -> Void)?
    private let delayNanoseconds: UInt64

    init(
        deliveries: [RunUploadDelivery] = [.accepted],
        delayNanoseconds: UInt64 = 0,
        afterUpload: (@Sendable () async -> Void)? = nil
    ) {
        self.deliveries = deliveries
        self.delayNanoseconds = delayNanoseconds
        self.afterUpload = afterUpload
    }

    func upload(_ payload: RunUploadPayload, session: RunUploadSession) async throws -> RunUploadDelivery {
        recorded.append((payload, session))
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        await afterUpload?()
        guard !deliveries.isEmpty else { return .accepted }
        return deliveries.removeFirst()
    }

    func requests() -> [(RunUploadPayload, RunUploadSession)] { recorded }
}

private struct FixedRunUploadTransport: APIResponseSending {
    let response: APIClientResponse

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        response
    }
}

private struct CapturedUploadRequest: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
}

private actor CapturingUploadTransport: APIResponseSending {
    private let response: APIClientResponse
    private var captured: CapturedUploadRequest?

    init(response: APIClientResponse) { self.response = response }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        captured = CapturedUploadRequest(path: path, method: method, body: body, headers: headers)
        return response
    }

    func request() -> CapturedUploadRequest? { captured }
}

private struct LostResponseTransport: APIResponseSending {
    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        throw URLError(.timedOut)
    }
}

final class RunUploadOutboxTests: XCTestCase {
    private let userA = RunUploadSession(ownerID: "member-A", accessToken: "token-A")
    private let userB = RunUploadSession(ownerID: "member-B", accessToken: "token-B")

    private func payload(_ id: UUID = UUID()) -> RunUploadPayload {
        RunUploadPayload(
            clientRunID: id,
            startedAt: Date(timeIntervalSince1970: 1_791_233_400.125),
            endedAt: Date(timeIntervalSince1970: 1_791_235_800.875),
            movingSeconds: 2_280,
            distanceMeters: 6_400,
            title: "Evening run",
            memo: "fixture only",
            points: [RunUploadPoint(
                recordedAt: Date(timeIntervalSince1970: 1_791_233_401.234),
                latitude: 37.5,
                longitude: 127,
                accuracyMeters: 4.5,
                altitudeMeters: 12.25,
                speedMetersPerSecond: 2.3
            )],
            pauses: [RunUploadPause(
                startedAt: Date(timeIntervalSince1970: 1_791_234_000),
                endedAt: Date(timeIntervalSince1970: 1_791_234_060)
            )]
        )
    }

    private func makeOutbox(
        _ persistence: any RunUploadOutboxPersisting = MemoryOutboxPersistence(),
        session: any RunUploadSessionProviding,
        uploader: any RunUploading
    ) throws -> RunUploadOutbox {
        try RunUploadOutbox(persistence: persistence, sessionProvider: session, uploader: uploader)
    }

    func testUploadClientBuildsBackendPostBodyAndDoesNotSendLocalOwnerID() async throws {
        let expected = payload()
        let response = APIClientResponse(statusCode: 201, data: Data(), requestID: "req-1")
        let transport = CapturingUploadTransport(response: response)
        let client = RunUploadClient(apiClient: transport)
        let result = try await client.upload(expected, session: userA)
        XCTAssertEqual(result, .accepted)

        let capturedRequest = await transport.request()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.path, "runs")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Authorization"], "Bearer token-A")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any]
        XCTAssertEqual(body?["clientRunId"] as? String, expected.clientRunID.uuidString)
        XCTAssertEqual(body?["movingSeconds"] as? Int, expected.movingSeconds)
        XCTAssertEqual(body?["distanceMeters"] as? Int, expected.distanceMeters)
        XCTAssertEqual((body?["points"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((body?["pauses"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(body?["ownerID"])
        XCTAssertNil(body?["ownerId"])
        XCTAssertTrue((body?["startedAt"] as? String)?.hasSuffix("Z") == true)
    }

    func testUploadClientMapsSuccessDeletedConflictPermanentFutureAndLostResponse() async throws {
        let clientID = UUID()
        let testPayload = payload(clientID)
        func client(_ status: Int, _ code: String?) -> RunUploadClient {
            let data = code.map { Data(#"{"code":"\#($0)"}"#.utf8) } ?? Data()
            return RunUploadClient(apiClient: FixedRunUploadTransport(
                response: APIClientResponse(statusCode: status, data: data, requestID: nil)
            ))
        }

        let success = try await client(200, nil).upload(testPayload, session: userA)
        let deleted = try await client(410, "RUN_DELETED").upload(testPayload, session: userA)
        let conflict = try await client(409, "CLIENT_RUN_ID_CONFLICT").upload(testPayload, session: userA)
        let tooLarge = try await client(413, "PAYLOAD_TOO_LARGE").upload(testPayload, session: userA)
        let future = try await client(422, "RUN_IN_FUTURE").upload(testPayload, session: userA)
        XCTAssertEqual(success, .accepted)
        XCTAssertEqual(deleted, .alreadyDeleted)
        XCTAssertEqual(conflict, .terminal(code: "CLIENT_RUN_ID_CONFLICT"))
        XCTAssertEqual(tooLarge, .terminal(code: "PAYLOAD_TOO_LARGE"))
        XCTAssertEqual(future, .retryLater(code: "RUN_IN_FUTURE"))
        let lost = RunUploadClient(apiClient: LostResponseTransport())
        let lostResponse = try await lost.upload(testPayload, session: userA)
        XCTAssertEqual(lostResponse, .retryLater(code: "TRANSPORT"))
    }

    func testEnqueuePersistenceFailurePreventsAnyUpload() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let uploader = RecordingRunUploader()
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        persistence.failNextSave()

        do {
            _ = try await outbox.enqueue(payload(), ownerID: userA.ownerID)
            XCTFail("Expected enqueue persistence failure")
        } catch {
            XCTAssertEqual(error as? RunUploadOutboxPersistenceFailure, .writeFailed)
        }
        let entries = await outbox.snapshot()
        XCTAssertTrue(entries.isEmpty)
        let report = try await outbox.drain()
        XCTAssertEqual(report.stopReason, .finished)
        let requests = await uploader.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDuplicateEnqueueIsIdempotentAndDifferentPayloadWithSameOwnerIDIsRejected() async throws {
        let persistence = MemoryOutboxPersistence()
        let outbox = try makeOutbox(persistence, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let original = payload(UUID())
        let firstEnqueue = try await outbox.enqueue(original, ownerID: userA.ownerID)
        let duplicateEnqueue = try await outbox.enqueue(original, ownerID: userA.ownerID)
        XCTAssertTrue(firstEnqueue)
        XCTAssertFalse(duplicateEnqueue)

        let changed = RunUploadPayload(
            clientRunID: original.clientRunID,
            startedAt: original.startedAt,
            endedAt: original.endedAt,
            movingSeconds: original.movingSeconds,
            distanceMeters: original.distanceMeters + 1,
            points: original.points,
            pauses: original.pauses
        )
        do {
            _ = try await outbox.enqueue(changed, ownerID: userA.ownerID)
            XCTFail("Expected local duplicate id conflict")
        } catch {
            XCTAssertEqual(error as? RunUploadOutboxFailure, .duplicateClientRunIDConflict)
        }
        let entries = await outbox.snapshot()
        XCTAssertEqual(entries.count, 1)
    }

    func testAccountSwitchAndLogoutNeverSendAnotherMembersPendingRecord() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let uploader = RecordingRunUploader()
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        await session.set(nil)
        let loggedOutReport = try await outbox.drain()
        XCTAssertEqual(loggedOutReport.stopReason, .sessionUnavailable)
        await session.set(userB)
        let otherMemberReport = try await outbox.drain()
        XCTAssertEqual(otherMemberReport.stopReason, .ownerMismatch)
        let requests = await uploader.requests()
        let entries = await outbox.snapshot()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(entries.map(\.envelope.payload.clientRunID), [fixture.clientRunID])
    }

    func testAccountSwitchDuringRequestKeepsAcknowledgedItemForOriginalOwner() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let userB = self.userB
        let uploader = RecordingRunUploader(afterUpload: { await session.set(userB) })
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let report = try await outbox.drain()
        XCTAssertEqual(report.stopReason, .accountChanged)
        let requests = await uploader.requests()
        let entries = await outbox.snapshot()
        XCTAssertEqual(requests.map(\.1.ownerID), [userA.ownerID])
        XCTAssertEqual(entries.map(\.envelope.payload.clientRunID), [fixture.clientRunID])
    }

    func testSuccessThenAckPersistenceFailureRestartsWithSameClientRunID() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let payload = self.payload()
        let uploader = RecordingRunUploader(afterUpload: { persistence.failNextSave() })
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        try await outbox.enqueue(payload, ownerID: userA.ownerID)

        do {
            _ = try await outbox.drain()
            XCTFail("Ack persistence failure should be surfaced")
        } catch {
            XCTAssertEqual(error as? RunUploadOutboxPersistenceFailure, .writeFailed)
        }
        XCTAssertEqual(try persistence.load().first?.envelope.payload.clientRunID, payload.clientRunID)

        let recovered = try makeOutbox(persistence, session: session, uploader: RecordingRunUploader())
        let report = try await recovered.drain()
        XCTAssertEqual(report.uploadedCount, 1)
        XCTAssertEqual(report.stopReason, .finished)
        XCTAssertTrue(try persistence.load().isEmpty)
    }

    func testLostResponseStaysPendingUntilManualReplayWithExactSamePayload() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let fixture = payload()
        let uploader = RecordingRunUploader(deliveries: [.retryLater(code: "TRANSPORT"), .accepted])
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let firstReport = try await outbox.drain()
        XCTAssertEqual(firstReport.stopReason, .retryLater(clientRunID: fixture.clientRunID, code: "TRANSPORT"))
        let afterLostResponse = await outbox.snapshot()
        XCTAssertEqual(afterLostResponse.first?.state, .pending)
        let firstRequests = await uploader.requests()
        XCTAssertEqual(firstRequests.map(\.0), [fixture])

        let replayReport = try await outbox.drain()
        XCTAssertEqual(replayReport.uploadedCount, 1)
        let replayedRequests = await uploader.requests()
        XCTAssertEqual(replayedRequests.map(\.0), [fixture, fixture])
        XCTAssertEqual(replayedRequests.map(\.1), [userA, userA])
        let afterReplay = await outbox.snapshot()
        XCTAssertTrue(afterReplay.isEmpty)
    }

    func test410RemovesEntryAndPermanentPayloadErrorIsTerminal() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let deleted = payload()
        let invalid = payload()
        let uploader = RecordingRunUploader(deliveries: [.alreadyDeleted, .terminal(code: "CLIENT_RUN_ID_CONFLICT")])
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        try await outbox.enqueue(deleted, ownerID: userA.ownerID)
        try await outbox.enqueue(invalid, ownerID: userA.ownerID)

        let report = try await outbox.drain()
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.terminalCount, 1)
        let entries = await outbox.snapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.state, .terminal(code: "CLIENT_RUN_ID_CONFLICT"))
        let secondReport = try await outbox.drain()
        XCTAssertEqual(secondReport.stopReason, .finished)
        let requests = await uploader.requests()
        XCTAssertEqual(requests.count, 2)
    }

    func testAtomicFileStoreRecoversAfterRestartAndDoesNotReplaceCorruptData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("run-outbox.json")
        let store = FileRunUploadOutboxPersistence(fileURL: file)
        let fixture = payload()
        let first = try makeOutbox(store, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        try await first.enqueue(fixture, ownerID: userA.ownerID)
        let restarted = try makeOutbox(store, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let restartedEntries = await restarted.snapshot()
        XCTAssertEqual(restartedEntries.first?.envelope.payload, fixture)

        let corruptFile = directory.appendingPathComponent("corrupt.json")
        try Data("not-json".utf8).write(to: corruptFile)
        let corruptStore = FileRunUploadOutboxPersistence(fileURL: corruptFile)
        XCTAssertThrowsError(try corruptStore.load())
        XCTAssertEqual(try Data(contentsOf: corruptFile), Data("not-json".utf8))
        XCTAssertThrowsError(try RunUploadOutbox(
            persistence: corruptStore,
            sessionProvider: MutableUploadSessionProvider(userA),
            uploader: RecordingRunUploader()
        ))
    }

    func testConcurrentDrainIsGuardedAndCancellationLeavesEntryPending() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = MutableUploadSessionProvider(userA)
        let uploader = RecordingRunUploader(delayNanoseconds: 150_000_000)
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let firstDrain = Task { try await outbox.drain() }
        try await Task.sleep(nanoseconds: 20_000_000)
        let secondReport = try await outbox.drain()
        XCTAssertEqual(secondReport.stopReason, .busy)
        let firstReport = try await firstDrain.value
        XCTAssertEqual(firstReport.uploadedCount, 1)
        let requests = await uploader.requests()
        XCTAssertEqual(requests.count, 1)

        try await outbox.enqueue(payload(), ownerID: userA.ownerID)
        let cancelled = Task { try await outbox.drain() }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelled.cancel()
        let cancellationReport = try await cancelled.value
        XCTAssertEqual(cancellationReport.stopReason, .cancelled)
        let entries = await outbox.snapshot()
        XCTAssertEqual(entries.filter { $0.state == .pending }.count, 1)
    }
}
