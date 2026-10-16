import Foundation
import XCTest
@testable import MovNetworking

private final class MemoryOutboxPersistence: RunUploadOutboxPersisting, @unchecked Sendable {
    let drainOwnershipKey = "memory-outbox-\(UUID().uuidString)"
    private let lock = NSLock()
    private var stored: [RunUploadOutboxEntry] = []
    private var shouldFailNextSave = false

    func load() throws -> [RunUploadOutboxEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func transact<Result>(
        _ update: ([RunUploadOutboxEntry]) throws -> RunUploadOutboxMutation<Result>
    ) throws -> Result {
        lock.lock(); defer { lock.unlock() }
        let mutation = try update(stored)
        guard mutation.entries != stored else { return mutation.result }
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw RunUploadOutboxPersistenceFailure.writeFailed
        }
        stored = mutation.entries
        return mutation.result
    }

    func failNextSave() {
        lock.lock(); defer { lock.unlock() }
        shouldFailNextSave = true
    }
}

private final class FailNextFileOutboxTransactionPersistence: RunUploadOutboxPersisting, @unchecked Sendable {
    private let file: FileRunUploadOutboxPersistence
    private let lock = NSLock()
    private var shouldFailNextTransaction = false

    init(fileURL: URL) { file = FileRunUploadOutboxPersistence(fileURL: fileURL) }
    var drainOwnershipKey: String { file.drainOwnershipKey }

    func load() throws -> [RunUploadOutboxEntry] { try file.load() }

    func transact<Result>(
        _ update: ([RunUploadOutboxEntry]) throws -> RunUploadOutboxMutation<Result>
    ) throws -> Result {
        lock.lock()
        let shouldFail = shouldFailNextTransaction
        shouldFailNextTransaction = false
        lock.unlock()
        if shouldFail { throw RunUploadOutboxPersistenceFailure.writeFailed }
        return try file.transact(update)
    }

    func failNextTransaction() {
        lock.lock(); defer { lock.unlock() }
        shouldFailNextTransaction = true
    }
}

private actor MutableUploadSessionProvider: RunUploadSessionProviding {
    private var session: RunUploadSession?

    init(_ session: RunUploadSession?) { self.session = session }
    func currentSession() async throws -> RunUploadSession? { session }
    func set(_ session: RunUploadSession?) { self.session = session }
}

private actor CancellationIgnoringUploadSessionProvider: RunUploadSessionProviding {
    private let session: RunUploadSession
    private var callCount = 0
    private var secondCallStarted: CheckedContinuation<Void, Never>?
    private var secondCallResult: CheckedContinuation<RunUploadSession?, Never>?

    init(session: RunUploadSession) { self.session = session }

    func currentSession() async throws -> RunUploadSession? {
        callCount += 1
        guard callCount == 2 else { return session }
        return await withCheckedContinuation { continuation in
            secondCallResult = continuation
            secondCallStarted?.resume()
            secondCallStarted = nil
        }
    }

    func waitForSecondCall() async {
        guard callCount < 2 else { return }
        await withCheckedContinuation { continuation in
            secondCallStarted = continuation
        }
    }

    func resumeSecondCall() {
        secondCallResult?.resume(returning: session)
        secondCallResult = nil
    }
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

private actor GatedRunUploader: RunUploading {
    private var payloads: [RunUploadPayload] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var deliveryContinuation: CheckedContinuation<RunUploadDelivery, Never>?

    func upload(_ payload: RunUploadPayload, session: RunUploadSession) async throws -> RunUploadDelivery {
        payloads.append(payload)
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { deliveryContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard payloads.isEmpty else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resume(_ delivery: RunUploadDelivery) {
        deliveryContinuation?.resume(returning: delivery)
        deliveryContinuation = nil
    }

    func submittedPayloads() -> [RunUploadPayload] { payloads }
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

private enum LocalEnqueueAttempt: Equatable, Sendable {
    case inserted
    case duplicate
    case conflict
}

private actor AsyncStartBarrier {
    private let participantCount: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func arriveAndWait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            arrivals += 1
            if arrivals == participantCount {
                let readyWaiters = waiters
                waiters.removeAll(keepingCapacity: false)
                readyWaiters.forEach { $0.resume() }
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private func enqueueAttempt(
    _ outbox: RunUploadOutbox,
    payload: RunUploadPayload,
    ownerID: String
) async throws -> LocalEnqueueAttempt {
    do {
        return try await outbox.enqueue(payload, ownerID: ownerID) ? .inserted : .duplicate
    } catch RunUploadOutboxFailure.duplicateClientRunIDConflict {
        return .conflict
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

    private func summaryResponseData(for payload:RunUploadPayload)throws->Data {
        let timestamp=ISO8601DateFormatter()
        timestamp.timeZone=TimeZone(identifier:"Asia/Seoul")
        timestamp.formatOptions=[.withInternetDateTime,.withFractionalSeconds,.withColonSeparatorInTimeZone]
        let date=DateFormatter();date.locale=Locale(identifier:"en_US_POSIX");date.calendar=Calendar(identifier:.gregorian);date.timeZone=TimeZone(identifier:"Asia/Seoul");date.dateFormat="yyyy-MM-dd"
        let distance=payload.distanceMeters
        let moving=payload.movingSeconds
        let elapsed=max(moving,Int(payload.endedAt.timeIntervalSince(payload.startedAt)))
        let body:[String:Any]=[
            "id":"server-\(payload.clientRunID.uuidString)","clientRunId":payload.clientRunID.uuidString,"version":1,
            "startedAt":timestamp.string(from:payload.startedAt),"endedAt":timestamp.string(from:payload.endedAt),
            "runDate":date.string(from:payload.startedAt),"elapsedSeconds":elapsed,"movingSeconds":moving,
            "distanceMeters":distance,"verdict":"VALID","verdictReason":NSNull(),
            "validDistanceMeters":distance,"validSeconds":moving,"paceSecondsPerKm":356,
            "title":payload.title.map{$0 as Any} ?? NSNull(),"memo":payload.memo.map{$0 as Any} ?? NSNull(),
            "createdAt":timestamp.string(from:payload.endedAt),"updatedAt":timestamp.string(from:payload.endedAt),"pointReward":NSNull()
        ]
        return try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys])
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
        let response = APIClientResponse(statusCode: 201, data: try summaryResponseData(for:expected), requestID: "req-1")
        let transport = CapturingUploadTransport(response: response)
        let client = RunUploadClient(apiClient: transport)
        let result = try await client.upload(expected, session: userA)
        guard case .acceptedSummary(let summary)=result else {return XCTFail("A valid success body returns its authoritative run summary")}
        XCTAssertEqual(summary.clientRunID,expected.clientRunID)
        XCTAssertEqual(summary.distanceMeters,Int64(expected.distanceMeters))
        XCTAssertEqual(summary.verdict,"VALID")

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
        func client(_ status: Int, _ code: String?, _ responseData:Data?=nil) -> RunUploadClient {
            let data = responseData ?? (code.map { Data(#"{"code":"\#($0)"}"#.utf8) } ?? Data())
            return RunUploadClient(apiClient: FixedRunUploadTransport(
                response: APIClientResponse(statusCode: status, data: data, requestID: nil)
            ))
        }

        let success = try await client(200, nil,try summaryResponseData(for:testPayload)).upload(testPayload, session: userA)
        let malformedSuccess = try await client(200,nil,Data()).upload(testPayload,session:userA)
        let deleted = try await client(410, "RUN_DELETED").upload(testPayload, session: userA)
        let conflict = try await client(409, "CLIENT_RUN_ID_CONFLICT").upload(testPayload, session: userA)
        let tooLarge = try await client(413, "PAYLOAD_TOO_LARGE").upload(testPayload, session: userA)
        let future = try await client(422, "RUN_IN_FUTURE").upload(testPayload, session: userA)
        guard case .acceptedSummary(let summary)=success else {return XCTFail("Success includes the authoritative server judgement summary")}
        XCTAssertEqual(summary.clientRunID,testPayload.clientRunID)
        XCTAssertEqual(malformedSuccess,.retryLater(code:"INVALID_ACK"))
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
        let entries = try await outbox.snapshot()
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
        let entries = try await outbox.snapshot()
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
        let entries = try await outbox.snapshot()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(entries.map(\.envelope.payload.clientRunID), [fixture.clientRunID])
    }

    func testAppExpectedOwnerMustMatchOutboxSessionBeforeSending() async throws {
        let persistence = MemoryOutboxPersistence()
        let uploader = RecordingRunUploader()
        let outbox = try makeOutbox(persistence, session: MutableUploadSessionProvider(userA), uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let mismatchedReport = try await outbox.drain(ownerID: userB.ownerID)
        XCTAssertEqual(mismatchedReport.stopReason, .ownerMismatch)
        let requestsAfterMismatch = await uploader.requests()
        XCTAssertTrue(requestsAfterMismatch.isEmpty, "A stale session for another member must not upload from the app boundary")
        let entriesAfterMismatch = try await outbox.snapshot()
        XCTAssertEqual(entriesAfterMismatch.map(\.envelope.payload.clientRunID), [fixture.clientRunID])

        let matchingReport = try await outbox.drain(ownerID: userA.ownerID)
        XCTAssertEqual(matchingReport.stopReason, .finished)
        let requestsAfterMatch = await uploader.requests()
        XCTAssertEqual(requestsAfterMatch.map(\.0.clientRunID), [fixture.clientRunID])
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
        let entries = try await outbox.snapshot()
        XCTAssertEqual(requests.map(\.1.ownerID), [userA.ownerID])
        XCTAssertEqual(entries.map(\.envelope.payload.clientRunID), [fixture.clientRunID])
    }

    func testCancellationWhileSessionProviderIgnoresCancellationCannotStartUpload() async throws {
        let persistence = MemoryOutboxPersistence()
        let session = CancellationIgnoringUploadSessionProvider(session: userA)
        let uploader = RecordingRunUploader()
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let drainTask = Task { try await outbox.drain() }
        await session.waitForSecondCall()
        drainTask.cancel()
        await session.resumeSecondCall()

        let report = try await drainTask.value
        XCTAssertEqual(report.stopReason, .cancelled)
        XCTAssertEqual(report.uploadedCount, 0)
        let requests = await uploader.requests()
        let entries = try await outbox.snapshot()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(entries.map(\.envelope.payload.clientRunID), [fixture.clientRunID])
    }

    func testSuccessThenAckPersistenceFailureRestartsWithSameClientRunID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("outbox.json")
        let persistence = FailNextFileOutboxTransactionPersistence(fileURL: file)
        let session = MutableUploadSessionProvider(userA)
        let payload = self.payload()
        let uploader = RecordingRunUploader(afterUpload: { persistence.failNextTransaction() })
        let outbox = try makeOutbox(persistence, session: session, uploader: uploader)
        try await outbox.enqueue(payload, ownerID: userA.ownerID)

        do {
            _ = try await outbox.drain()
            XCTFail("Ack persistence failure should be surfaced")
        } catch {
            XCTAssertEqual(error as? RunUploadOutboxPersistenceFailure, .writeFailed)
        }
        XCTAssertEqual(try persistence.load().first?.envelope.payload.clientRunID, payload.clientRunID)
        let acceptedRequests = await uploader.requests()
        XCTAssertEqual(acceptedRequests.map(\.0), [payload], "The first accepted POST is followed by a failed local ack write")

        let retryUploader = RecordingRunUploader()
        let restartedPersistence = FileRunUploadOutboxPersistence(fileURL: file)
        let recovered = try makeOutbox(restartedPersistence, session: session, uploader: retryUploader)
        let report = try await recovered.drain()
        XCTAssertEqual(report.uploadedCount, 1)
        XCTAssertEqual(report.stopReason, .finished)
        let retriedRequests = await retryUploader.requests()
        XCTAssertEqual(retriedRequests.map(\.0), [payload], "Ack failure recovery is at-least-once with the identical payload and clientRunID")
        XCTAssertEqual(retriedRequests.first?.0.clientRunID, payload.clientRunID)
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
        let afterLostResponse = try await outbox.snapshot()
        XCTAssertEqual(afterLostResponse.first?.state, .pending)
        let firstRequests = await uploader.requests()
        XCTAssertEqual(firstRequests.map(\.0), [fixture])

        let replayReport = try await outbox.drain()
        XCTAssertEqual(replayReport.uploadedCount, 1)
        let replayedRequests = await uploader.requests()
        XCTAssertEqual(replayedRequests.map(\.0), [fixture, fixture])
        XCTAssertEqual(replayedRequests.map(\.1), [userA, userA])
        let afterReplay = try await outbox.snapshot()
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
        let entries = try await outbox.snapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.state, .terminal(code: "CLIENT_RUN_ID_CONFLICT"))
        let secondReport = try await outbox.drain()
        XCTAssertEqual(secondReport.terminalCount, 1)
        XCTAssertEqual(secondReport.stopReason, .finished)
        let requests = await uploader.requests()
        XCTAssertEqual(requests.count, 2)
    }

    func testTerminalEntryIsReportedAgainOnSecondDrainFromSameFileWithoutRetransmission() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("run-outbox.json")
        let persistence = FileRunUploadOutboxPersistence(fileURL: file)
        let uploader = RecordingRunUploader(deliveries: [.terminal(code: "CLIENT_RUN_ID_CONFLICT")])
        let outbox = try makeOutbox(persistence, session: MutableUploadSessionProvider(userA), uploader: uploader)
        let fixture = payload()
        try await outbox.enqueue(fixture, ownerID: userA.ownerID)

        let initial = try await outbox.drain(ownerID: userA.ownerID)
        let repeated = try await outbox.drain(ownerID: userA.ownerID)

        XCTAssertEqual(initial.terminalCount, 1)
        XCTAssertEqual(repeated.terminalCount, 1)
        XCTAssertEqual(repeated.stopReason, .finished)
        let requests = await uploader.requests()
        XCTAssertEqual(requests.map(\.0), [fixture], "Terminal entries are reported again but never automatically uploaded again")
        XCTAssertEqual(try persistence.load().first?.state, .terminal(code: "CLIENT_RUN_ID_CONFLICT"))
    }

    func testTerminalEntryIsReportedAfterRestartWithoutRetransmission() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("run-outbox.json")
        let fixture = payload()
        let firstUploader = RecordingRunUploader(deliveries: [.terminal(code: "PAYLOAD_TOO_LARGE")])
        let first = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userA),
            uploader: firstUploader
        )
        try await first.enqueue(fixture, ownerID: userA.ownerID)
        let initialReport = try await first.drain(ownerID: userA.ownerID)
        XCTAssertEqual(initialReport.terminalCount, 1)

        let restartedUploader = RecordingRunUploader()
        let restarted = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userA),
            uploader: restartedUploader
        )
        let report = try await restarted.drain(ownerID: userA.ownerID)

        XCTAssertEqual(report.terminalCount, 1)
        XCTAssertEqual(report.stopReason, .finished)
        let restartedRequests = await restartedUploader.requests()
        XCTAssertTrue(restartedRequests.isEmpty)
        let restartedEntries = try await restarted.snapshot()
        XCTAssertEqual(restartedEntries.first?.state, .terminal(code: "PAYLOAD_TOO_LARGE"))
    }

    func testCurrentOwnerTerminalIsReportedAlongsidePendingSuccessAndExcludesOtherOwnerTerminal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("run-outbox.json")
        let terminalA = payload()
        let terminalB = payload()
        let pendingA = payload()

        let terminalWriterA = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userA),
            uploader: RecordingRunUploader(deliveries: [.terminal(code: "INVALID_A")])
        )
        try await terminalWriterA.enqueue(terminalA, ownerID: userA.ownerID)
        let reportA = try await terminalWriterA.drain(ownerID: userA.ownerID)
        XCTAssertEqual(reportA.terminalCount, 1)

        let terminalWriterB = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userB),
            uploader: RecordingRunUploader(deliveries: [.terminal(code: "INVALID_B")])
        )
        try await terminalWriterB.enqueue(terminalB, ownerID: userB.ownerID)
        let reportB = try await terminalWriterB.drain(ownerID: userB.ownerID)
        XCTAssertEqual(reportB.terminalCount, 1)

        let currentUploader = RecordingRunUploader()
        let currentOwnerOutbox = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userA),
            uploader: currentUploader
        )
        try await currentOwnerOutbox.enqueue(pendingA, ownerID: userA.ownerID)
        let report = try await currentOwnerOutbox.drain(ownerID: userA.ownerID)

        XCTAssertEqual(report.uploadedCount, 1)
        XCTAssertEqual(report.terminalCount, 1, "Only member A's persisted terminal entry contributes to member A's result")
        XCTAssertEqual(report.stopReason, .finished)
        let currentRequests = await currentUploader.requests()
        XCTAssertEqual(currentRequests.map(\.0), [pendingA])
        let entries = try await currentOwnerOutbox.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.envelope.ownerID == userA.ownerID && $0.envelope.payload.clientRunID == terminalA.clientRunID && $0.state == .terminal(code: "INVALID_A") })
        XCTAssertTrue(entries.contains { $0.envelope.ownerID == userB.ownerID && $0.envelope.payload.clientRunID == terminalB.clientRunID && $0.state == .terminal(code: "INVALID_B") })
    }

    func testOtherOwnersTerminalEntryDoesNotAffectCurrentOwnerReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("run-outbox.json")
        let fixture = payload()
        let writerB = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userB),
            uploader: RecordingRunUploader(deliveries: [.terminal(code: "INVALID_B")])
        )
        try await writerB.enqueue(fixture, ownerID: userB.ownerID)
        let writerReport = try await writerB.drain(ownerID: userB.ownerID)
        XCTAssertEqual(writerReport.terminalCount, 1)

        let currentOwnerUploader = RecordingRunUploader()
        let currentOwnerOutbox = try makeOutbox(
            FileRunUploadOutboxPersistence(fileURL: file),
            session: MutableUploadSessionProvider(userA),
            uploader: currentOwnerUploader
        )
        let report = try await currentOwnerOutbox.drain(ownerID: userA.ownerID)

        XCTAssertEqual(report.terminalCount, 0)
        XCTAssertEqual(report.stopReason, .finished)
        let currentOwnerRequests = await currentOwnerUploader.requests()
        XCTAssertTrue(currentOwnerRequests.isEmpty)
        let remaining = try await currentOwnerOutbox.snapshot()
        XCTAssertEqual(remaining.first?.state, .terminal(code: "INVALID_B"))
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
        let restartedEntries = try await restarted.snapshot()
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

    func testSeparateOutboxActorsSharePathTransactionsWithoutLostEntriesOrDuplicateIDOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("shared-outbox.json")
        let storeA = FileRunUploadOutboxPersistence(fileURL: fileURL)
        let storeB = FileRunUploadOutboxPersistence(fileURL: fileURL)
        let outboxA = try makeOutbox(storeA, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let outboxB = try makeOutbox(storeB, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let first = payload()
        let second = payload()
        let ownerID = userA.ownerID

        async let firstInsert = enqueueAttempt(outboxA, payload: first, ownerID: ownerID)
        async let secondInsert = enqueueAttempt(outboxB, payload: second, ownerID: ownerID)
        let firstResult = try await firstInsert
        let secondResult = try await secondInsert
        XCTAssertEqual(firstResult, .inserted)
        XCTAssertEqual(secondResult, .inserted)

        let collisionID = UUID()
        let collisionA = payload(collisionID)
        let collisionB = RunUploadPayload(
            clientRunID: collisionID,
            startedAt: collisionA.startedAt,
            endedAt: collisionA.endedAt,
            movingSeconds: collisionA.movingSeconds,
            distanceMeters: collisionA.distanceMeters + 1,
            points: collisionA.points,
            pauses: collisionA.pauses
        )
        let firstCollisionResult = try await enqueueAttempt(outboxA, payload: collisionA, ownerID: ownerID)
        let laterCollisionResult = try await enqueueAttempt(outboxB, payload: collisionB, ownerID: ownerID)
        XCTAssertEqual(firstCollisionResult, .inserted)
        XCTAssertEqual(laterCollisionResult, .conflict)

        let stored = try storeA.load()
        let expectedEntries = [
            RunUploadOutboxEntry(envelope: RunUploadEnvelope(ownerID: ownerID, payload: first), state: .pending),
            RunUploadOutboxEntry(envelope: RunUploadEnvelope(ownerID: ownerID, payload: second), state: .pending),
            RunUploadOutboxEntry(envelope: RunUploadEnvelope(ownerID: ownerID, payload: collisionA), state: .pending)
        ].sorted { $0.envelope.payload.clientRunID.uuidString < $1.envelope.payload.clientRunID.uuidString }
        let actualEntries = stored.sorted {
            $0.envelope.payload.clientRunID.uuidString < $1.envelope.payload.clientRunID.uuidString
        }
        XCTAssertEqual(stored.count, expectedEntries.count)
        XCTAssertEqual(actualEntries, expectedEntries)
    }

    func testConcurrentDuplicateIDConflictAcrossSeparateOutboxesPreservesTheWinner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("shared-outbox.json")
        let storeA = FileRunUploadOutboxPersistence(fileURL: fileURL)
        let storeB = FileRunUploadOutboxPersistence(fileURL: fileURL)
        let outboxA = try makeOutbox(storeA, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let outboxB = try makeOutbox(storeB, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())
        let ownerID = userA.ownerID
        let collisionID = UUID()
        let payloadA = payload(collisionID)
        let payloadB = RunUploadPayload(
            clientRunID: collisionID,
            startedAt: payloadA.startedAt,
            endedAt: payloadA.endedAt,
            movingSeconds: payloadA.movingSeconds,
            distanceMeters: payloadA.distanceMeters + 1,
            points: payloadA.points,
            pauses: payloadA.pauses
        )
        let startBarrier = AsyncStartBarrier(participantCount: 2)

        async let resultA: LocalEnqueueAttempt = {
            await startBarrier.arriveAndWait()
            return try await enqueueAttempt(outboxA, payload: payloadA, ownerID: ownerID)
        }()
        async let resultB: LocalEnqueueAttempt = {
            await startBarrier.arriveAndWait()
            return try await enqueueAttempt(outboxB, payload: payloadB, ownerID: ownerID)
        }()
        let (attemptA, attemptB) = try await (resultA, resultB)
        let attempts = [attemptA, attemptB]
        XCTAssertEqual(attempts.filter { $0 == .inserted }.count, 1)
        XCTAssertEqual(attempts.filter { $0 == .conflict }.count, 1)

        let winningPayload = attemptA == .inserted ? payloadA : payloadB
        let expectedEntry = RunUploadOutboxEntry(
            envelope: RunUploadEnvelope(ownerID: ownerID, payload: winningPayload),
            state: .pending
        )
        XCTAssertEqual(try storeA.load(), [expectedEntry])
    }

    func testActualFileWriteFailureDoesNotCommitTheEnqueue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockedDirectory = directory.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lockedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lockedDirectory.path) }
        let outboxFile = lockedDirectory.appendingPathComponent("outbox.json")
        let store = FileRunUploadOutboxPersistence(fileURL: outboxFile)
        let outbox = try makeOutbox(store, session: MutableUploadSessionProvider(userA), uploader: RecordingRunUploader())

        do {
            _ = try await outbox.enqueue(payload(), ownerID: userA.ownerID)
            XCTFail("Expected the actual file write to fail")
        } catch {
            XCTAssertEqual(error as? RunUploadOutboxPersistenceFailure, .writeFailed)
        }
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outboxFile.path))
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
        let entries = try await outbox.snapshot()
        XCTAssertEqual(entries.filter { $0.state == .pending }.count, 1)
    }

    func testSeparateOutboxInstancesCannotDrainTheSameFileConcurrently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("outbox.json")
        let firstPersistence = FileRunUploadOutboxPersistence(fileURL: file)
        let secondPersistence = FileRunUploadOutboxPersistence(fileURL: file)
        let uploader = GatedRunUploader()
        let first = try makeOutbox(firstPersistence, session: MutableUploadSessionProvider(userA), uploader: uploader)
        let second = try makeOutbox(secondPersistence, session: MutableUploadSessionProvider(userA), uploader: uploader)
        let fixture = payload()
        try await first.enqueue(fixture, ownerID: userA.ownerID)

        let firstDrain = Task { try await first.drain() }
        await uploader.waitUntilStarted()
        let secondReport = try await second.drain()
        XCTAssertEqual(secondReport.stopReason, .busy)
        let submittedWhileFirstIsGated = await uploader.submittedPayloads()
        XCTAssertEqual(submittedWhileFirstIsGated, [fixture], "The shared path must have only one in-flight uploader")

        await uploader.resume(.accepted)
        let firstReport = try await firstDrain.value
        XCTAssertEqual(firstReport.uploadedCount, 1)
        XCTAssertEqual(firstReport.stopReason, .finished)
        let submittedAfterRelease = await uploader.submittedPayloads()
        XCTAssertEqual(submittedAfterRelease, [fixture], "Two instances must not POST the same pending payload concurrently")
        XCTAssertTrue(try firstPersistence.load().isEmpty)
    }
}
