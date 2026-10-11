import Foundation
import XCTest
@testable import MovNetworking

final class RunRecordsReadTests: XCTestCase {
    private let clientRunID = "0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11"

    private func makeClient(_ token: String? = "run-test-token", attempts: Int = 1) throws -> RunRecordsClient {
        let configuration = try APIClientConfiguration(
            environment: .development,
            baseURLString: "https://api-dev.example.invalid/api/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        return RunRecordsClient(
            apiClient: APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration)),
            tokenProvider: RunTokenProvider(value: token),
            retryPolicy: RunRecordsRetryPolicy(maximumAttempts: attempts, delayNanoseconds: 0)
        )
    }

    private func summary(id: String = "104", pointReward: String = #"{"status":"SETTLED","pointsAwarded":0}"#) -> String {
        #"{"id":"\#(id)","clientRunId":"\#(clientRunID)","version":3,"startedAt":"2026-10-05T23:50:00+09:00","endedAt":"2026-10-06T00:30:00+09:00","runDate":"2026-10-05","elapsedSeconds":2400,"movingSeconds":2280,"distanceMeters":6400,"verdict":"VALID","verdictReason":null,"validDistanceMeters":6100,"validSeconds":2150,"paceSecondsPerKm":352,"title":"밤 러닝","memo":null,"pointReward":\#(pointReward),"createdAt":"2026-10-06T00:31:02+09:00","updatedAt":"2026-10-06T00:31:02+09:00"}"#
    }

    func testListUsesItemsWrapperAndPreservesOpaqueCursorAndKSTValues() async throws {
        let body = #"{"items":[\#(summary())],"nextCursor":"opaque_cursor-7"}"#
        MockURLProtocol.respond(statusCode: 200, data: Data(body.utf8))
        let page = try await makeClient().fetchRuns(size: 1)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "opaque_cursor-7")
        XCTAssertEqual(page.items[0].runDate, "2026-10-05")
        XCTAssertEqual(page.items[0].distanceMeters, 6_400)
        XCTAssertEqual(page.items[0].validDistanceMeters, 6_100)
        XCTAssertEqual(page.items[0].movingSeconds, 2_280)
        XCTAssertEqual(page.items[0].validSeconds, 2_150)
        XCTAssertEqual(page.items[0].pointReward, BackendRunPointReward(status: .settled, pointsAwarded: 0))

        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[],"nextCursor":null}"#.utf8))
        _ = try await makeClient().fetchRuns(cursor: page.nextCursor, size: 1)
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/api/v1/runs")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "cursor", value: "opaque_cursor-7"), URLQueryItem(name: "size", value: "1")])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer run-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testDetailDecodesFlattenedSummaryPointPrecisionPauseAndJudgement() async throws {
        let summaryFields=String(summary(id:"a-104").dropFirst().dropLast())
        let body = #"{\#(summaryFields),"points":[{"recordedAt":"2026-10-05T23:55:00.123+09:00","latitude":37.5,"longitude":127.0,"accuracyMeters":4.5,"altitudeMeters":12.25,"speedMetersPerSecond":2.3}],"pauses":[{"startedAt":"2026-10-06T00:00:00+09:00","endedAt":"2026-10-06T00:01:00+09:00"}],"judgement":{"algorithmVersion":"v1","exclusions":[{"reason":"VEHICLE","startedAt":"2026-10-05T23:58:00.125+09:00","endedAt":"2026-10-05T23:59:00.125+09:00","distanceMeters":9876543210,"seconds":60}],"inaccuratePoints":2,"jumpPoints":1}}"#
        MockURLProtocol.respond(statusCode: 200, data: Data(body.utf8))
        let detail = try await makeClient().fetchRun(id: "a-104")

        XCTAssertEqual(detail.summary.id, "a-104")
        XCTAssertEqual(detail.points.count, 1)
        XCTAssertEqual(detail.points[0].latitude, 37.5)
        XCTAssertEqual(detail.points[0].accuracyMeters, 4.5)
        XCTAssertEqual(detail.pauses.count, 1)
        XCTAssertEqual(detail.judgement?.exclusions.first?.distanceMeters, 9_876_543_210)
        XCTAssertEqual(detail.judgement?.algorithmVersion, "v1")
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/api/v1/runs/a-104")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testRejectsInvalidCursorPageSizeRunIDAndRewardWithoutSendingRequests() async throws {
        MockURLProtocol.reset()
        let client = try makeClient()
        do { _ = try await client.fetchRuns(size: 0); XCTFail("Expected invalid page size") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidPageSize) }
        do { _ = try await client.fetchRun(id: "../other"); XCTFail("Expected invalid run ID") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testUnauthorizedAndMissingTokenStayFailuresRatherThanEmptyPages() async throws {
        MockURLProtocol.respond(statusCode: 401, data: Data(#"{"code":"UNAUTHENTICATED"}"#.utf8))
        do {
            _ = try await makeClient(attempts: 1).fetchRuns()
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .unauthenticated)
        }
        do {
            _ = try await makeClient(nil).fetchRuns()
            XCTFail("Expected missing token failure")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .accessTokenUnavailable)
        }
    }

    func testMalformedWrapperAndPointRewardAreRejected() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"runs":[],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("Expected wrapper mismatch") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }

        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[\#(summary(pointReward:#"{"status":"SETTLED","pointsAwarded":null}"#))],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("Expected invalid settled reward") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }

        let missingNullable=summary().replacingOccurrences(of:",\"pointReward\":{\"status\":\"SETTLED\",\"pointsAwarded\":0},",with:",")
        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[\#(missingNullable)],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("The API contract requires nullable fields to be explicit") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }
    }

    func testLoaderAppendsPagesWithoutParsingCursorAndStopsCursorLoop() async {
        let item = Self.makeSummary()
        let reader = SequencedRunRecordsReader(pages: [
            BackendRunPage(items: [item], nextCursor: "opaque-A"),
            BackendRunPage(items: [item], nextCursor: "opaque-A")
        ])
        let loader = RunRecordsLoader(client: reader, pageSize: 1)
        await loader.load()
        await loader.loadNextPage()

        let state = await loader.state
        XCTAssertEqual(state, .failedLoadingMore(BackendRunSnapshot(items: [item], nextCursor: "opaque-A"), .paginationLoop))
        let passedCursors = await reader.passedCursors
        XCTAssertEqual(passedCursors, [nil, "opaque-A"])
    }

    func testStaleRunDetailResponseCannotReplaceTheNewSelection() async {
        let gate = RunReadGate()
        let reader = ControlledRunDetailReader(gate: gate)
        let loader = RunRecordsLoader(client: reader)
        let stale = Task { await loader.loadDetail(runID: "older") }
        await gate.waitUntilEntered()
        await loader.loadDetail(runID: "newer")
        await gate.release()
        await stale.value

        let detailState = await loader.detailState
        XCTAssertEqual(detailState, .loaded(Self.makeDetail(id: "newer")))
    }

    fileprivate static func makeSummary(id: String = "104") -> BackendRunSummary {
        BackendRunSummary(
            id: id, clientRunID: UUID(uuidString: "0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!, version: 3,
            startedAt: Date(timeIntervalSince1970: 1_791_213_000), endedAt: Date(timeIntervalSince1970: 1_791_215_400),
            runDate: "2026-10-05", elapsedSeconds: 2_400, movingSeconds: 2_280, distanceMeters: 6_400,
            verdict: "VALID", verdictReason: nil, validDistanceMeters: 6_100, validSeconds: 2_150,
            paceSecondsPerKm: 352, title: "밤 러닝", memo: nil, createdAt: Date(timeIntervalSince1970: 1_791_215_462),
            updatedAt: Date(timeIntervalSince1970: 1_791_215_462), pointReward: nil
        )
    }

    fileprivate static func makeDetail(id: String) -> BackendRunDetail {
        BackendRunDetail(summary: makeSummary(id: id), points: [], pauses: [], judgement: nil)
    }
}

private struct RunTokenProvider: AccessTokenProviding {
    let value: String?
    func accessToken() async throws -> String? { value }
}

private actor SequencedRunRecordsReader: RunRecordsReading {
    private var pages: [BackendRunPage]
    private(set) var passedCursors: [String?] = []

    init(pages: [BackendRunPage]) { self.pages = pages }
    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage {
        passedCursors.append(cursor)
        return pages.removeFirst()
    }
    func fetchRun(id: String) async throws -> BackendRunDetail { RunRecordsReadTests.makeDetail(id: id) }
}

private actor RunReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation in
            if entered { continuation.resume() }
            else { self.continuation = continuation }
        }
    }
    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }
    func release() {
        entered = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ControlledRunDetailReader: RunRecordsReading {
    let gate: RunReadGate
    init(gate: RunReadGate) { self.gate = gate }

    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage { BackendRunPage(items: [], nextCursor: nil) }
    func fetchRun(id: String) async throws -> BackendRunDetail {
        if id == "older" { await gate.wait() }
        return RunRecordsReadTests.makeDetail(id: id)
    }
}
