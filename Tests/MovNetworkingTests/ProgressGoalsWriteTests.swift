import Foundation
import XCTest
@testable import MovNetworking

private struct WeeklyGoalWriteTokenStub: AccessTokenProviding {
    func accessToken() async throws -> String? { "fixture-weekly-goal-token" }
}

private actor WeeklyGoalWriteInMemoryTransport: APIResponseSending {
    struct Request: Sendable {
        let path: String
        let method: String
        let body: Data?
        let headers: [String: String]
    }

    private var responses: [APIClientResponse]
    private var requests: [Request] = []

    init(responses: [APIClientResponse]) { self.responses = responses }

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        requests.append(Request(path: path, method: method, body: body, headers: headers))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [Request] { requests }
}

private func makeWeeklyGoalWriteClient(transport: any APIResponseSending, maximumAttempts: Int = 1) -> ProgressGoalsClient {
    ProgressGoalsClient(
        apiClient: transport,
        tokenProvider: WeeklyGoalWriteTokenStub(),
        retryPolicy: ProgressGoalsRetryPolicy(maximumAttempts: maximumAttempts, delayNanoseconds: 0)
    )
}

private func response(statusCode: Int, data: Data) -> APIClientResponse {
    APIClientResponse(statusCode: statusCode, data: data, requestID: nil)
}

private func weeklyStatusResponse(version: Int64, distance: Int64?, time: Int64?) throws -> Data {
    let doneMeters: Int64 = 12_400
    let doneSeconds: Int64 = 3_900
    let distanceAxis: [String: Any] = [
        "goalMeters": distance.map { $0 as Any } ?? NSNull(),
        "doneMeters": doneMeters,
        "remainingMeters": distance.map { max(0, $0 - doneMeters) as Any } ?? NSNull(),
        "achieved": distance.map { doneMeters >= $0 } ?? false
    ]
    let timeAxis: [String: Any] = [
        "goalSeconds": time.map { $0 as Any } ?? NSNull(),
        "doneSeconds": doneSeconds,
        "remainingSeconds": time.map { max(0, $0 - doneSeconds) as Any } ?? NSNull(),
        "achieved": time.map { doneSeconds >= $0 } ?? false
    ]
    return try JSONSerialization.data(withJSONObject: [
        "weekStartDate": "2026-10-05",
        "weekEndDate": "2026-10-11",
        "version": version,
        "distance": distanceAxis,
        "time": timeAxis
    ], options: [.sortedKeys])
}

final class ProgressGoalsWriteTests: XCTestCase {
    func testPutSendsCompleteDesiredStateForUnsetAndEachIndependentAxis() async throws {
        let cases: [(String, Int64?, Int64?)] = [
            ("unset", nil, nil),
            ("distance only", 25_000, nil),
            ("time only", nil, 7_200),
            ("both", 25_000, 7_200)
        ]
        let transport = WeeklyGoalWriteInMemoryTransport(responses: try cases.enumerated().map { index, item in
            response(statusCode: 200, data: try weeklyStatusResponse(version: Int64(index + 1), distance: item.1, time: item.2))
        })
        let client = makeWeeklyGoalWriteClient(transport: transport)

        for (index, item) in cases.enumerated() {
            let status = try await client.saveWeeklyGoal(version: Int64(index), distanceGoalMeters: item.1, timeGoalSeconds: item.2)
            let observedRequests = await transport.recordedRequests()
            let request = try XCTUnwrap(observedRequests.last)
            let body = try XCTUnwrap(request.body)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(request.path, "goals/weekly")
            XCTAssertEqual(request.method, "PUT")
            XCTAssertEqual(request.headers["Authorization"], "Bearer fixture-weekly-goal-token")
            XCTAssertEqual(request.headers["Accept"], "application/json")
            XCTAssertEqual(request.headers["Content-Type"], "application/json")
            XCTAssertEqual(request.headers["Cache-Control"], "no-store")
            XCTAssertEqual((payload["version"] as? NSNumber)?.int64Value, Int64(index))
            XCTAssertTrue(payload.keys.contains("distanceGoalMeters"), "A nil axis is explicitly null in the full desired state")
            XCTAssertTrue(payload.keys.contains("timeGoalSeconds"), "A nil axis is explicitly null in the full desired state")
            assertOptionalInteger(payload["distanceGoalMeters"], equals: item.1)
            assertOptionalInteger(payload["timeGoalSeconds"], equals: item.2)
            XCTAssertEqual(status.version, Int64(index + 1))
            XCTAssertEqual(status.distance.goal, item.1)
            XCTAssertEqual(status.time.goal, item.2)
        }
        let requestCount = await transport.recordedRequests().count
        XCTAssertEqual(requestCount, cases.count)
    }

    func testPutAcceptsContractBoundariesAndRejectsOutOfRangeOrWrongStepBeforeTransport() async throws {
        let responses = try [
            response(statusCode: 200, data: weeklyStatusResponse(version: 1, distance: 1_000, time: 600)),
            response(statusCode: 200, data: weeklyStatusResponse(version: 2, distance: 500_000, time: 360_000))
        ]
        let transport = WeeklyGoalWriteInMemoryTransport(responses: responses)
        let client = makeWeeklyGoalWriteClient(transport: transport)
        for (index, values) in [(Int64(1_000), Int64(600)), (Int64(500_000), Int64(360_000))].enumerated() {
            _ = try await client.saveWeeklyGoal(version: Int64(index), distanceGoalMeters: values.0, timeGoalSeconds: values.1)
        }

        for (distance, time) in [(Int64(999), nil), (Int64(500_001), nil), (Int64(12_500), nil), (nil, Int64(599)), (nil, Int64(360_600)), (nil, Int64(7_100))] {
            do {
                _ = try await client.saveWeeklyGoal(version: 0, distanceGoalMeters: distance, timeGoalSeconds: time)
                XCTFail("Out of range or non-step goal values must be rejected locally")
            } catch let failure as ProgressGoalsFailure {
                XCTAssertEqual(failure, .invalidWeeklyGoalDraft)
            }
        }
        let requestCount = await transport.recordedRequests().count
        XCTAssertEqual(requestCount, 2, "Invalid drafts must not issue a request")
    }

    func testPutMapsConflictAndValidationErrorsAndNeverRetriesWrites() async throws {
        let cases: [(Int, String, ProgressGoalsFailure)] = [
            (409, "goal-conflict", .weeklyGoalVersionConflict(requestID: "goal-conflict")),
            (400, "goal-invalid", .weeklyGoalValidationFailed(requestID: "goal-invalid")),
            (503, "goal-outage", .serviceUnavailable(requestID: "goal-outage"))
        ]
        let transport = WeeklyGoalWriteInMemoryTransport(responses: cases.map { code, requestID, _ in
            let problemCode = code == 409 ? "VERSION_CONFLICT" : code == 400 ? "VALIDATION_FAILED" : "SERVICE_UNAVAILABLE"
            return response(statusCode: code, data: Data("{\"code\":\"\(problemCode)\",\"requestId\":\"\(requestID)\"}".utf8))
        })
        let client = makeWeeklyGoalWriteClient(transport: transport, maximumAttempts: 2)
        for (index, item) in cases.enumerated() {
            let (statusCode, _, expected) = item
            do {
                _ = try await client.saveWeeklyGoal(version: 3, distanceGoalMeters: 30_000, timeGoalSeconds: 7_200)
                XCTFail("The failed PUT must surface its status")
            } catch let failure as ProgressGoalsFailure {
                XCTAssertEqual(failure, expected)
            }
            let requestCount = await transport.recordedRequests().count
            XCTAssertEqual(requestCount, index + 1, "A write must not replay after an ambiguous outcome (HTTP \(statusCode))")
        }
    }

    private func assertOptionalInteger(_ raw: Any?, equals expected: Int64?, file: StaticString = #filePath, line: UInt = #line) {
        guard let expected else {
            XCTAssertTrue(raw is NSNull, "nil must be encoded as explicit JSON null", file: file, line: line)
            return
        }
        XCTAssertEqual((raw as? NSNumber)?.int64Value, expected, file: file, line: line)
    }
}
