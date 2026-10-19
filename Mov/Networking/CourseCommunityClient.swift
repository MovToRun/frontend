import Foundation

enum CommunityCertificationStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case withdrawn = "WITHDRAWN"
}

struct CommunityCertificationReview: Codable, Equatable, Sendable {
    let fromStatus: String
    let toStatus: String
    let reason: String
    let occurredAt: String
    let retainUntil: String?
}

struct CommunityCertificationApplication: Codable, Equatable, Sendable, Identifiable {
    let applicationId: String
    let applicantMemberId: String?
    let status: CommunityCertificationStatus
    let applicationReason: String?
    let submittedAt: String?
    let updatedAt: String?
    let evidenceUrls: [String]?
    let reviews: [CommunityCertificationReview]?

    var id: String { applicationId }
}

struct CommunityCertificationPage: Codable, Equatable, Sendable {
    let items: [CommunityCertificationApplication]
    let nextCursor: String?
}

struct BackendCommunityRoutePoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let elapsedSeconds: Int64
}

struct BackendCommunityCourseSummary: Codable, Equatable, Sendable, Identifiable {
    let courseId: String
    let routeVersion: Int64
    let runDate: String
    let distanceMeters: Int64
    let runningSeconds: Int64
    let paceSecondsPerKm: Int64?

    var id: String { courseId }
}

struct BackendCommunityCourse: Codable, Equatable, Sendable, Identifiable {
    let courseId: String
    let routeVersion: Int64
    let runDate: String
    let distanceMeters: Int64
    let runningSeconds: Int64
    let paceSecondsPerKm: Int64?
    let routeSegments: [[BackendCommunityRoutePoint]]

    var id: String { courseId }
}

struct BackendCommunityCoursePage: Codable, Equatable, Sendable {
    let items: [BackendCommunityCourseSummary]
    let nextCursor: String?
}

struct BackendCommunityCourseDraft: Codable, Equatable, Sendable {
    let courseId: String
    let status: String
    let startMaskMeters: Int64
    let endMaskMeters: Int64
}

struct BackendCourseFollowComparison: Codable, Equatable, Sendable {
    let runId: String
    let validDistanceMeters: Int64
    let validSeconds: Int64
    let paceSecondsPerKm: Int64?
    let distanceDeltaMeters: Int64
    let secondsDelta: Int64
    let paceDeltaSecondsPerKm: Int64?
}

struct BackendCourseFollowSession: Codable, Equatable, Sendable, Identifiable {
    let sessionId: String
    let status: String
    let routeVersion: Int64
    let progressMeters: Int64
    let elapsedSeconds: Int64
    let runId: String?
    let courseAvailable: Bool
    let course: BackendCommunityCourse?
    let comparison: BackendCourseFollowComparison?

    var id: String { sessionId }
}

enum CommunityCourseFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case forbidden
    case notFound
    case conflict
    case invalidRequest
    case resultUnknown
    case invalidResponse
    case serverFailure(Int)
    case transport(URLError.Code)
    case cancelled
}

protocol CommunityCourseServing: Sendable {
    func fetchMyCertification() async throws -> CommunityCertificationApplication?
    func submitCertification(reason: String, evidenceURLs: [String]) async throws -> CommunityCertificationApplication
    func withdrawCertification() async throws
    func fetchOperatorQueue(cursor: String?, size: Int) async throws -> CommunityCertificationPage
    func fetchOperatorApplication(id: String) async throws -> CommunityCertificationApplication
    func decideOperatorApplication(id: String, action: String, reason: String) async throws -> CommunityCertificationApplication
    func listCourses(cursor: String?, size: Int) async throws -> BackendCommunityCoursePage
    func fetchCourse(id: String) async throws -> BackendCommunityCourse
    func createCourseDraft(runID: Int64, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft
    func adjustCourseDraft(id: String, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft
    func publishCourse(id: String) async throws -> BackendCommunityCourse
    func unpublishCourse(id: String) async throws
    func createFollowSession(courseID: String, clientSessionID: UUID, clientRunID: UUID, routeVersion: Int64) async throws -> BackendCourseFollowSession
    func fetchFollowSession(id: String) async throws -> BackendCourseFollowSession
    func updateFollowProgress(id: String, routeVersion: Int64, progressMeters: Int64, elapsedSeconds: Int64) async throws
    func compareFollowRun(id: String, routeVersion: Int64, runID: String) async throws -> BackendCourseFollowComparison
}

struct CommunityCourseClient: CommunityCourseServing, Sendable {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding

    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func fetchMyCertification() async throws -> CommunityCertificationApplication? {
        let response = try await send(path: "course-certifications/me")
        if response.statusCode == 404 { return nil }
        try require(response, statuses: [200])
        return try decode(CommunityCertificationApplication.self, from: response.data)
    }

    func submitCertification(reason: String, evidenceURLs: [String]) async throws -> CommunityCertificationApplication {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...300).contains(reason.count), (1...5).contains(evidenceURLs.count),
              evidenceURLs.allSatisfy(Self.isPublicHTTPSURL) else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "course-certifications/me", method: "POST", body: try encode(CertificationRequest(applicationReason: reason, evidenceUrls: evidenceURLs)))
        try require(response, statuses: [201])
        return try decode(CommunityCertificationApplication.self, from: response.data)
    }

    func withdrawCertification() async throws {
        try require(try await send(path: "course-certifications/me", method: "DELETE"), statuses: [204])
    }

    func fetchOperatorQueue(cursor: String? = nil, size: Int = 20) async throws -> CommunityCertificationPage {
        guard (1...50).contains(size) else { throw CommunityCourseFailure.invalidRequest }
        var query = [URLQueryItem(name: "status", value: "PENDING"), URLQueryItem(name: "size", value: String(size))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response = try await send(path: "operations/course-certifications", query: query)
        try require(response, statuses: [200])
        return try decode(CommunityCertificationPage.self, from: response.data)
    }

    func fetchOperatorApplication(id: String) async throws -> CommunityCertificationApplication {
        let response = try await send(path: "operations/course-certifications/\(Self.pathComponent(id))")
        try require(response, statuses: [200])
        return try decode(CommunityCertificationApplication.self, from: response.data)
    }

    func decideOperatorApplication(id: String, action: String, reason: String) async throws -> CommunityCertificationApplication {
        guard ["APPROVE", "REJECT"].contains(action), (1...300).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw CommunityCourseFailure.invalidRequest
        }
        let response = try await send(path: "operations/course-certifications/\(Self.pathComponent(id))", method: "PATCH", body: try encode(OperatorDecisionRequest(action: action, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))))
        try require(response, statuses: [200])
        return try decode(CommunityCertificationApplication.self, from: response.data)
    }

    func listCourses(cursor: String? = nil, size: Int = 20) async throws -> BackendCommunityCoursePage {
        guard (1...50).contains(size) else { throw CommunityCourseFailure.invalidRequest }
        var query = [URLQueryItem(name: "size", value: String(size))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response = try await send(path: "courses", query: query)
        try require(response, statuses: [200])
        return try decode(BackendCommunityCoursePage.self, from: response.data)
    }

    func fetchCourse(id: String) async throws -> BackendCommunityCourse {
        let response = try await send(path: "courses/\(Self.pathComponent(id))")
        try require(response, statuses: [200])
        return try decode(BackendCommunityCourse.self, from: response.data)
    }

    func createCourseDraft(runID: Int64, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft {
        guard runID > 0, startMaskMeters >= 0, endMaskMeters >= 0 else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "courses/me", method: "POST", body: try encode(CreateCourseRequest(runId: runID, startMaskMeters: startMaskMeters, endMaskMeters: endMaskMeters)))
        if (500..<600).contains(response.statusCode) { throw CommunityCourseFailure.resultUnknown }
        try require(response, statuses: [201])
        return try decode(BackendCommunityCourseDraft.self, from: response.data)
    }

    func adjustCourseDraft(id: String, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft {
        guard startMaskMeters >= 0, endMaskMeters >= 0 else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "courses/me/\(Self.pathComponent(id))", method: "PATCH", body: try encode(AdjustCourseRequest(startMaskMeters: startMaskMeters, endMaskMeters: endMaskMeters)))
        try require(response, statuses: [200])
        return try decode(BackendCommunityCourseDraft.self, from: response.data)
    }

    func publishCourse(id: String) async throws -> BackendCommunityCourse {
        let response = try await send(path: "courses/me/\(Self.pathComponent(id))/publish", method: "POST", body: try encode(PublishCourseRequest(publicConsent: true)))
        if (500..<600).contains(response.statusCode) { throw CommunityCourseFailure.resultUnknown }
        try require(response, statuses: [200, 201])
        return try decode(BackendCommunityCourse.self, from: response.data)
    }

    func unpublishCourse(id: String) async throws {
        try require(try await send(path: "courses/me/\(Self.pathComponent(id))", method: "DELETE"), statuses: [200, 204])
    }

    func createFollowSession(courseID: String, clientSessionID: UUID, clientRunID: UUID, routeVersion: Int64) async throws -> BackendCourseFollowSession {
        guard routeVersion > 0 else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "courses/\(Self.pathComponent(courseID))/follow-sessions", method: "POST", body: try encode(CreateFollowRequest(clientSessionId: clientSessionID, clientRunId: clientRunID, routeVersion: routeVersion)))
        try require(response, statuses: [200, 201])
        return try decode(BackendCourseFollowSession.self, from: response.data)
    }

    func fetchFollowSession(id: String) async throws -> BackendCourseFollowSession {
        let response = try await send(path: "course-follow-sessions/\(Self.pathComponent(id))")
        try require(response, statuses: [200])
        return try decode(BackendCourseFollowSession.self, from: response.data)
    }

    func updateFollowProgress(id: String, routeVersion: Int64, progressMeters: Int64, elapsedSeconds: Int64) async throws {
        guard routeVersion > 0, progressMeters >= 0, elapsedSeconds >= 0 else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "course-follow-sessions/\(Self.pathComponent(id))/progress", method: "PUT", body: try encode(FollowProgressRequest(routeVersion: routeVersion, progressMeters: progressMeters, elapsedSeconds: elapsedSeconds)))
        try require(response, statuses: [200, 204])
    }

    func compareFollowRun(id: String, routeVersion: Int64, runID: String) async throws -> BackendCourseFollowComparison {
        guard routeVersion > 0, Int64(runID) != nil, Int64(runID)! > 0 else { throw CommunityCourseFailure.invalidRequest }
        let response = try await send(path: "course-follow-sessions/\(Self.pathComponent(id))/comparison", method: "POST", body: try encode(FollowComparisonRequest(routeVersion: routeVersion, runId: Int64(runID)!)))
        try require(response, statuses: [200, 201])
        let session = try decode(BackendCourseFollowSession.self, from: response.data)
        guard let comparison = session.comparison else { throw CommunityCourseFailure.invalidResponse }
        return comparison
    }

    private func send(path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> APIClientResponse {
        let token: String?
        do { token = try await tokenProvider.accessToken() }
        catch is CancellationError { throw CommunityCourseFailure.cancelled }
        catch { throw CommunityCourseFailure.accessTokenUnavailable }
        guard let token, !token.isEmpty else { throw CommunityCourseFailure.accessTokenUnavailable }
        do {
            return try await apiClient.sendResponse(path: path, method: method, body: body, headers: [
                "Authorization": "Bearer \(token)", "Accept": "application/json", "Cache-Control": "no-store",
                "Content-Type": "application/json"
            ], queryItems: query)
        } catch is CancellationError { throw CommunityCourseFailure.cancelled }
        catch let error as APIClientError {
            if case .transport(let code) = error { throw CommunityCourseFailure.transport(code) }
            if case .cancelled = error { throw CommunityCourseFailure.cancelled }
            throw CommunityCourseFailure.resultUnknown
        } catch let error as URLError { throw CommunityCourseFailure.transport(error.code) }
        catch { throw CommunityCourseFailure.resultUnknown }
    }

    private func require(_ response: APIClientResponse, statuses: [Int]) throws {
        guard !statuses.contains(response.statusCode) else { return }
        switch response.statusCode {
        case 401: throw CommunityCourseFailure.unauthenticated
        case 403: throw CommunityCourseFailure.forbidden
        case 404: throw CommunityCourseFailure.notFound
        case 409: throw CommunityCourseFailure.conflict
        case 400, 422: throw CommunityCourseFailure.invalidRequest
        case 500...599: throw CommunityCourseFailure.serverFailure(response.statusCode)
        default: throw CommunityCourseFailure.invalidResponse
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CommunityCourseFailure.invalidResponse }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do { return try encoder.encode(value) }
        catch { throw CommunityCourseFailure.invalidRequest }
    }

    private static func isPublicHTTPSURL(_ value: String) -> Bool {
        guard value.count <= 2_048, let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https", let host = components.host,
              !host.isEmpty, components.user == nil, components.password == nil,
              components.fragment == nil else { return false }
        return true
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }

    private struct CertificationRequest: Encodable { let applicationReason: String; let evidenceUrls: [String] }
    private struct OperatorDecisionRequest: Encodable { let action: String; let reason: String }
    private struct CreateCourseRequest: Encodable { let runId: Int64; let startMaskMeters: Int64; let endMaskMeters: Int64 }
    private struct AdjustCourseRequest: Encodable { let startMaskMeters: Int64; let endMaskMeters: Int64 }
    private struct PublishCourseRequest: Encodable { let publicConsent: Bool }
    private struct CreateFollowRequest: Encodable { let clientSessionId: UUID; let clientRunId: UUID; let routeVersion: Int64 }
    private struct FollowProgressRequest: Encodable { let routeVersion: Int64; let progressMeters: Int64; let elapsedSeconds: Int64 }
    private struct FollowComparisonRequest: Encodable { let routeVersion: Int64; let runId: Int64 }
}
