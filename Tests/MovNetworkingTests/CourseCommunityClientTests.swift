import Foundation
import XCTest
@testable import MovNetworking

private struct CourseTestToken: AccessTokenProviding {
    func accessToken() async throws -> String? { "course-test-token" }
}

private struct CourseCall: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
    let query: [URLQueryItem]
}

private actor CourseResponseTransport: APIResponseSending {
    private var responses: [APIClientResponse]
    private var calls: [CourseCall] = []

    init(_ responses: [APIClientResponse]) { self.responses = responses }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        calls.append(CourseCall(path: path, method: method, body: body, headers: headers, query: queryItems))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func capturedCalls() -> [CourseCall] { calls }
}

final class CourseCommunityClientTests: XCTestCase {
    func testCertificationUsesSelfScopedRequestAndNoStore() async throws {
        let transport = CourseResponseTransport([APIClientResponse(statusCode: 200, data: Data(#"{"applicationId":"41","status":"PENDING","applicationReason":"runner","evidenceUrls":["https://example.org/a"],"reviews":[]}"#.utf8))])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())

        let application = try await client.fetchMyCertification()
        let calls = await transport.capturedCalls()

        XCTAssertEqual(application?.status, .pending)
        XCTAssertEqual(calls.first?.path, "course-certifications/me")
        XCTAssertEqual(calls.first?.method, "GET")
        XCTAssertEqual(calls.first?.headers["Cache-Control"], "no-store")
        XCTAssertEqual(calls.first?.headers["Authorization"], "Bearer course-test-token")
    }

    func testCertificationSubmissionEncodesOnlyAgreedFieldsAndValidatesEvidence() async throws {
        let body = Data(#"{"applicationId":"42","status":"PENDING","applicationReason":"runner","evidenceUrls":["https://example.org/a"],"reviews":[]}"#.utf8)
        let transport = CourseResponseTransport([APIClientResponse(statusCode: 201, data: body)])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())

        _ = try await client.submitCertification(reason: " runner ", evidenceURLs: ["https://example.org/a"])
        let call = await transport.capturedCalls().first
        let payload = try XCTUnwrap(call?.body).jsonObject()
        XCTAssertEqual(call?.path, "course-certifications/me")
        XCTAssertEqual(call?.method, "POST")
        XCTAssertEqual(Set(payload.keys), Set(["applicationReason", "evidenceUrls"]))
        XCTAssertEqual(payload["applicationReason"] as? String, "runner")
        XCTAssertEqual(payload["evidenceUrls"] as? [String], ["https://example.org/a"])

        let invalidTransport = CourseResponseTransport([])
        let invalidClient = CommunityCourseClient(apiClient: invalidTransport, tokenProvider: CourseTestToken())
        do {
            _ = try await invalidClient.submitCertification(reason: "reason", evidenceURLs: ["http://example.org/a"])
            XCTFail("Non-HTTPS evidence must be rejected before sending")
        } catch let failure as CommunityCourseFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        let invalidCalls = await invalidTransport.capturedCalls()
        XCTAssertTrue(invalidCalls.isEmpty)
    }

    func testOperatorQueueUsesPendingCursorAndDecisionRequiresServiceContract() async throws {
        let queue = Data(#"{"items":[],"nextCursor":"cursor-a"}"#.utf8)
        let decision = Data(#"{"applicationId":"41","status":"APPROVED","applicationReason":"runner","evidenceUrls":null,"reviews":[]}"#.utf8)
        let transport = CourseResponseTransport([
            APIClientResponse(statusCode: 200, data: queue),
            APIClientResponse(statusCode: 200, data: decision)
        ])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())
        _ = try await client.fetchOperatorQueue(cursor: "cursor-a", size: 10)
        _ = try await client.decideOperatorApplication(id: "41", action: "APPROVE", reason: "확인 자료를 검토했어요.")
        let calls = await transport.capturedCalls()

        XCTAssertEqual(calls[0].path, "operations/course-certifications")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: calls[0].query.compactMap { item in item.value.map { (item.name, $0) } }), ["status": "PENDING", "size": "10", "cursor": "cursor-a"])
        XCTAssertEqual(calls[1].path, "operations/course-certifications/41")
        XCTAssertEqual(calls[1].method, "PATCH")
        XCTAssertEqual(try XCTUnwrap(calls[1].body).jsonObject()["action"] as? String, "APPROVE")

        do {
            _ = try await client.decideOperatorApplication(id: "41", action: "REVOKE", reason: "no")
            XCTFail("Member-facing operator action must not infer revoke behavior")
        } catch let failure as CommunityCourseFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
    }

    func testCourseDraftPublishAndFollowSendOnlyMaskedCourseFieldsAndScalarProgress() async throws {
        let draft = Data(#"{"courseId":"901","status":"DRAFT","startMaskMeters":300,"endMaskMeters":250}"#.utf8)
        let adjustedDraft = Data(#"{"courseId":"901","status":"DRAFT","startMaskMeters":450,"endMaskMeters":250}"#.utf8)
        let course = Data(#"{"courseId":"901","routeVersion":1,"runDate":"2026-10-18","distanceMeters":4820,"runningSeconds":1808,"paceSecondsPerKm":375,"routeSegments":[[{"latitude":37.56,"longitude":126.97,"elapsedSeconds":0},{"latitude":37.57,"longitude":126.98,"elapsedSeconds":400}]]}"#.utf8)
        let follow = Data(#"{"sessionId":"700","courseId":"901","routeVersion":1,"progressMeters":0,"elapsedSeconds":0,"courseAvailable":true,"course":null,"comparison":null}"#.utf8)
        let comparison = Data(#"{"courseId":"901","routeVersion":1,"runId":"505","courseDistanceMeters":4820,"courseRunningSeconds":1808,"coursePaceSecondsPerKm":375,"runDistanceMeters":5000,"runRunningSeconds":1900,"runPaceSecondsPerKm":380,"distanceDeltaMeters":180,"runningSecondsDelta":92,"paceSecondsPerKmDelta":5}"#.utf8)
        let transport = CourseResponseTransport([
            APIClientResponse(statusCode: 201, data: draft),
            APIClientResponse(statusCode: 200, data: adjustedDraft),
            APIClientResponse(statusCode: 201, data: course),
            APIClientResponse(statusCode: 201, data: follow),
            APIClientResponse(statusCode: 204, data: Data()),
            APIClientResponse(statusCode: 200, data: comparison)
        ])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())
        _ = try await client.createCourseDraft(runID: 505, startMaskMeters: 300, endMaskMeters: 250)
        _ = try await client.adjustCourseDraft(id: "901", startMaskMeters: 450, endMaskMeters: 250)
        _ = try await client.publishCourse(id: "901")
        let sessionKey = UUID(uuidString: "A382BBA8-468D-447E-88EF-54A0A451951F")!
        let runKey = UUID(uuidString: "AC52B9F3-3A59-41A5-82F5-F5619D9D90DD")!
        _ = try await client.createFollowSession(courseID: "901", clientSessionID: sessionKey, clientRunID: runKey, routeVersion: 1)
        try await client.updateFollowProgress(id: "700", routeVersion: 1, progressMeters: 250, elapsedSeconds: 80)
        let result = try await client.compareFollowRun(id: "700", routeVersion: 1, runID: "505")
        let calls = await transport.capturedCalls()

        XCTAssertEqual(result.distanceDeltaMeters, 180)
        XCTAssertEqual(calls[0].path, "courses/me")
        XCTAssertEqual(Set(try XCTUnwrap(calls[0].body).jsonObject().keys), Set(["runId", "startMaskMeters", "endMaskMeters"]))
        XCTAssertEqual(calls[1].path, "courses/me/901")
        XCTAssertEqual(calls[1].method, "PATCH")
        XCTAssertEqual(try XCTUnwrap(calls[1].body).jsonObject()["startMaskMeters"] as? Int, 450)
        XCTAssertEqual(try XCTUnwrap(calls[2].body).jsonObject()["publicConsent"] as? Bool, true)
        XCTAssertEqual(calls[3].path, "courses/901/follow-sessions")
        XCTAssertEqual(try XCTUnwrap(calls[3].body).jsonObject()["clientSessionId"] as? String, sessionKey.uuidString)
        let progress = try XCTUnwrap(calls[4].body).jsonObject()
        XCTAssertEqual(Set(progress.keys), Set(["routeVersion", "progressMeters", "elapsedSeconds"]))
        XCTAssertNil(progress["latitude"])
        XCTAssertEqual(calls[5].path, "course-follow-sessions/700/comparison")
        XCTAssertEqual(try XCTUnwrap(calls[5].body).jsonObject()["runId"] as? Int, 505)
    }

    func testCreateFollowSessionSameClientIDsAreReusableAcrossRetry() async throws {
        let payload = Data(#"{"sessionId":"700","courseId":"901","routeVersion":1,"progressMeters":0,"elapsedSeconds":0,"courseAvailable":true,"course":null,"comparison":null}"#.utf8)
        let transport = CourseResponseTransport([
            APIClientResponse(statusCode: 201, data: payload), APIClientResponse(statusCode: 200, data: payload)
        ])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())
        let sessionKey = UUID()
        let runKey = UUID()
        _ = try await client.createFollowSession(courseID: "901", clientSessionID: sessionKey, clientRunID: runKey, routeVersion: 1)
        _ = try await client.createFollowSession(courseID: "901", clientSessionID: sessionKey, clientRunID: runKey, routeVersion: 1)
        let calls = await transport.capturedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].body, calls[1].body)
    }

    func testFollowValidationAndHTTPFailureMapping() async throws {
        let transport = CourseResponseTransport([APIClientResponse(statusCode: 403, data: Data())])
        let client = CommunityCourseClient(apiClient: transport, tokenProvider: CourseTestToken())
        do {
            _ = try await client.fetchOperatorQueue(cursor: nil, size: 20)
            XCTFail("Operator access must remain backend-authorized")
        } catch let failure as CommunityCourseFailure { XCTAssertEqual(failure, .forbidden) }

        do {
            try await client.updateFollowProgress(id: "700", routeVersion: 1, progressMeters: -1, elapsedSeconds: 0)
            XCTFail("Negative scalar progress must be rejected")
        } catch let failure as CommunityCourseFailure { XCTAssertEqual(failure, .invalidRequest) }
        let calls = await transport.capturedCalls()
        XCTAssertEqual(calls.count, 1)
    }
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}
