import Foundation
import XCTest
@testable import MovNetworking

private struct ProgressTokenStub: AccessTokenProviding {
    let value: String?
    func accessToken() async throws -> String? { value }
}

private func makeProgressGoalsClient(token: String? = "fixture-progress-token") throws -> ProgressGoalsClient {
    let configuration = try APIClientConfiguration(
        environment: .development,
        baseURLString: "https://api-dev.example.invalid/api/v1/",
        requestTimeout: 4,
        resourceTimeout: 9
    )
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    return ProgressGoalsClient(
        apiClient: APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration)),
        tokenProvider: ProgressTokenStub(value: token)
    )
}

private let progressBody = Data("""
{"grade":"SPROUT","gradeAchievedAt":"2026-10-06T07:41:12+09:00","window":{"fromDate":"2026-07-09","toDate":"2026-10-06","distanceMeters":12400,"activityDays":8},"nextGrade":{"grade":"PASSION","requiredDistanceMeters":30000,"requiredActivityDays":10,"remainingDistanceMeters":17600,"remainingActivityDays":2},"total":{"distanceMeters":48200,"seconds":17350,"activityDays":31,"runCount":40}}
""".utf8)

private let weeklyGoalBody = Data("""
{"weekStartDate":"2026-10-05","weekEndDate":"2026-10-11","version":3,"distance":{"goalMeters":20000,"doneMeters":12400,"remainingMeters":7600,"achieved":false},"time":{"goalSeconds":7200,"doneSeconds":7350,"remainingSeconds":0,"achieved":true}}
""".utf8)

final class ProgressGoalsReadTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testProgressSummaryMapsPinnedDTOAndUsesAuthenticatedRead() async throws {
        MockURLProtocol.respond(statusCode: 200, data: progressBody)
        let value = try await makeProgressGoalsClient().fetchProgress()
        let request = try XCTUnwrap(MockURLProtocol.requests.first)

        XCTAssertEqual(value.grade, "SPROUT")
        XCTAssertEqual(value.gradeAchievedAt, ISO8601DateFormatter().date(from: "2026-10-06T07:41:12+09:00"))
        XCTAssertEqual(value.window.distanceMeters, 12_400)
        XCTAssertEqual(value.window.activityDays, 8)
        XCTAssertEqual(value.nextGrade?.remainingActivityDays, 2)
        XCTAssertEqual(value.total.distanceMeters, 48_200)
        XCTAssertEqual(value.total.seconds, 17_350)
        XCTAssertEqual(value.total.runCount, 40)
        XCTAssertEqual(request.url?.path, "/api/v1/progress")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-progress-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testWeeklyGoalKeepsDistanceAndTimeAxesIndependentAndAllowsOverage() async throws {
        MockURLProtocol.respond(statusCode: 200, data: weeklyGoalBody)
        let value = try await makeProgressGoalsClient().fetchWeeklyGoal()
        let request = try XCTUnwrap(MockURLProtocol.requests.first)

        XCTAssertEqual(value.weekStartDate, "2026-10-05")
        XCTAssertEqual(value.weekEndDate, "2026-10-11")
        XCTAssertEqual(value.distance, BackendWeeklyGoalAxis(goal: 20_000, done: 12_400, remaining: 7_600, achieved: false))
        XCTAssertEqual(value.time, BackendWeeklyGoalAxis(goal: 7_200, done: 7_350, remaining: 0, achieved: true))
        XCTAssertEqual(request.url?.path, "/api/v1/goals/weekly")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody, "Read-only goal integration must not issue a write")
    }

    func testUnsetGoalsRetainActualWeeklyTotalsInsteadOfInventingZero() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"weekStartDate":"2026-10-05","weekEndDate":"2026-10-11","version":0,"distance":{"goalMeters":null,"doneMeters":8400,"remainingMeters":null,"achieved":false},"time":{"goalSeconds":null,"doneSeconds":1860,"remainingSeconds":null,"achieved":false}}
        """.utf8))
        let value = try await makeProgressGoalsClient().fetchWeeklyGoal()

        XCTAssertNil(value.distance.goal)
        XCTAssertNil(value.distance.remaining)
        XCTAssertEqual(value.distance.done, 8_400)
        XCTAssertFalse(value.distance.achieved)
        XCTAssertNil(value.time.goal)
        XCTAssertEqual(value.time.done, 1_860)
    }

    func testMissingNullableWeeklyFieldsAreNotMistakenForUnsetGoals() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"weekStartDate":"2026-10-05","weekEndDate":"2026-10-11","version":1,"distance":{"doneMeters":8400,"remainingMeters":null,"achieved":false},"time":{"goalSeconds":null,"doneSeconds":1860,"remainingSeconds":null,"achieved":false}}
        """.utf8))
        do {
            _ = try await makeProgressGoalsClient().fetchWeeklyGoal()
            XCTFail("Missing nullable fields must fail closed instead of being treated as an unset goal")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testDailyProgressPreservesKSTDatesAndBuildsEncodedInclusiveRangeQuery() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"items":[{"date":"2026-10-05","validDistanceMeters":6100,"validSeconds":2150,"runCount":1,"activityDay":true},{"date":"2026-10-06","validDistanceMeters":900,"validSeconds":240,"runCount":2,"activityDay":false}]}
        """.utf8))
        let range = try BackendDailyProgressRange(fromDate: "2026-10-05", toDate: "2026-10-11")
        let value = try await makeProgressGoalsClient().fetchDaily(range: range)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/v1/progress/daily")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "from", value: "2026-10-05"), URLQueryItem(name: "to", value: "2026-10-11")])
        XCTAssertEqual(value.days.map(\.date), ["2026-10-05", "2026-10-06"])
        XCTAssertEqual(value.distanceMeters, 7_000)
        XCTAssertEqual(value.seconds, 2_390)
        XCTAssertEqual(value.runCount, 3)
    }

    func testRejectsMissingNullableFieldsMalformedDatesAndImpossibleGoalProgress() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"grade":"NONE","window":{"fromDate":"2026-07-09","toDate":"2026-10-06","distanceMeters":0,"activityDays":0},"gradeAchievedAt":null,"nextGrade":null,"total":{"distanceMeters":0,"seconds":0,"activityDays":0,"runCount":0}}
        """.utf8))
        do {
            _ = try await makeProgressGoalsClient().fetchProgress()
            XCTFail("Missing nullable contract fields must be rejected")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"weekStartDate":"2026-10-05","weekEndDate":"2026-10-11","version":1,"distance":{"goalMeters":20000,"doneMeters":12000,"remainingMeters":7000,"achieved":false},"time":{"goalSeconds":null,"doneSeconds":0,"remainingSeconds":null,"achieved":false}}
        """.utf8))
        do {
            _ = try await makeProgressGoalsClient().fetchWeeklyGoal()
            XCTFail("Goal remaining must match the goal and actual done total")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testDailyRejectsOutOfRangeOrUnsortedRowsAndInvalidRangeIsRejectedLocally() async throws {
        XCTAssertThrowsError(try BackendDailyProgressRange(fromDate: "2026-10-11", toDate: "2026-10-05")) {
            XCTAssertEqual($0 as? ProgressGoalsFailure, .invalidDateRange)
        }
        MockURLProtocol.respond(statusCode: 200, data: Data("""
        {"items":[{"date":"2026-10-06","validDistanceMeters":1000,"validSeconds":240,"runCount":1,"activityDay":true},{"date":"2026-10-05","validDistanceMeters":1000,"validSeconds":240,"runCount":1,"activityDay":true}]}
        """.utf8))
        let range = try BackendDailyProgressRange(fromDate: "2026-10-05", toDate: "2026-10-11")
        do {
            _ = try await makeProgressGoalsClient().fetchDaily(range: range)
            XCTFail("The backend's date-ordered contract must be enforced")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testMissingTokenStopsBeforeNetworkAndServiceFailureRemainsTyped() async throws {
        do {
            _ = try await makeProgressGoalsClient(token: nil).fetchWeeklyGoal()
            XCTFail("A missing access token must fail before any request")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .accessTokenUnavailable)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)

        MockURLProtocol.respond(statusCode: 503, data: Data("{\"code\":\"PROGRESS_UNAVAILABLE\",\"requestId\":\"req-progress-1\"}".utf8))
        do {
            _ = try await makeProgressGoalsClient().fetchProgress()
            XCTFail("Service outage must not produce an empty success")
        } catch let failure as ProgressGoalsFailure {
            XCTAssertEqual(failure, .serviceUnavailable(requestID: "req-progress-1"))
            XCTAssertTrue(failure.userMessage.contains("다시 시도"))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }
}
