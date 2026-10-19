import Foundation
import XCTest
@testable import MovNetworking

private struct CrewSessionStub: RunUploadSessionProviding {
    let value: RunUploadSession?
    func currentSession() async throws -> RunUploadSession? { value }
}

private actor MutableCrewSession: RunUploadSessionProviding {
    private var value: RunUploadSession?
    init(_ value: RunUploadSession?) { self.value = value }
    func currentSession() async throws -> RunUploadSession? { value }
    func set(_ value: RunUploadSession?) { self.value = value }
}

private struct CrewRecordedRequest: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
    let queryItems: [URLQueryItem]
}

private actor CrewRecordingTransport: APIResponseSending {
    private var responses: [APIClientResponse]
    private var requests: [CrewRecordedRequest] = []

    init(_ responses: [APIClientResponse]) { self.responses = responses }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        requests.append(CrewRecordedRequest(path: path, method: method, body: body, headers: headers, queryItems: queryItems))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func capturedRequests() -> [CrewRecordedRequest] { requests }
}

private actor CrewSwitchingTransport: APIResponseSending {
    private let session: MutableCrewSession
    private let response: APIClientResponse
    private var requests: [CrewRecordedRequest] = []

    init(session: MutableCrewSession, response: APIClientResponse) {
        self.session = session
        self.response = response
    }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        requests.append(CrewRecordedRequest(path: path, method: method, body: body, headers: headers, queryItems: queryItems))
        await session.set(RunUploadSession(ownerID: "202", accessToken: "member-b-token"))
        return response
    }

    func capturedRequests() -> [CrewRecordedRequest] { requests }
}

final class CrewClientTests: XCTestCase {
    private let crew = #"{"crewId":"101","name":"모브 새벽 크루","introduction":"아침 러닝","joinGuide":"편하게 인사해요","capacity":20,"memberCount":3,"status":"ACTIVE","role":"MEMBER"}"#
    private let application = #"{"applicationId":"301","crewId":"101","memberId":"202","note":"같이 달리고 싶어요","grade":null,"status":"PENDING","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:00:00Z"}"#
    private let post = #"{"postId":"401","crewId":"101","crewName":"모브 새벽 크루","boardId":"501","boardName":"러닝 일정","boardKind":"INTERNAL","authorMemberId":"202","authorNickname":"RunMate","title":"토요일 일정","content":"오전 8시에 만나요.","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:00:00Z"}"#

    private func makeClient(_ token: String? = "member-a-token", ownerID: String = "202") throws -> CrewClient {
        let configuration = try APIClientConfiguration(environment: .development,
                                                        baseURLString: "https://api-dev.example.invalid/api/v1/",
                                                        requestTimeout: 4, resourceTimeout: 9)
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [MockURLProtocol.self]
        let api = APIClient(configuration: configuration, session: URLSession(configuration: urlConfiguration))
        let session = token.map { RunUploadSession(ownerID: ownerID, accessToken: $0) }
        return CrewClient(apiClient: api, sessionProvider: CrewSessionStub(value: session))
    }

    func testMyCrewsUsesAuthenticatedNoStoreAndDecodesServerRole() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("[\(crew)]".utf8))

        let result = try await makeClient().fetchMyCrews()

        XCTAssertEqual(result.map(\.id), ["101"])
        XCTAssertEqual(result.first?.role, "MEMBER")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/crews/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer member-a-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testRecruitmentSearchUsesOnlyTheContractedPublicFeedAndOpaqueCursor() async throws {
        let body = #"{"items":[{"postId":"401","crewId":"101","crewName":"모브 새벽 크루","boardId":"501","boardName":"모집","boardKind":"RECRUITMENT","authorMemberId":"202","authorNickname":"RunMate","title":"새 멤버 모집","content":"함께 달려요.","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:00:00Z"}],"nextCursor":"opaque-cursor"}"#
        MockURLProtocol.respond(statusCode: 200, data: Data(body.utf8))

        let page = try await makeClient().fetchRecruitmentPosts(cursor: "opaque-cursor/2?", size: 7)

        XCTAssertEqual(page.items.map(\.crewId), ["101"])
        XCTAssertEqual(page.nextCursor, "opaque-cursor")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/community/boards/crew-recruitment/posts")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "size" })?.value, "7")
        XCTAssertEqual(query?.first(where: { $0.name == "cursor" })?.value, "opaque-cursor/2?")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testCrewDirectoryAndMyApplicationPagesUseBE117RoutesAndIDs() async throws {
        let directoryPage = #"{"items":[{"crewId":"101","name":"모브 새벽 크루","introduction":"아침 러닝","joinGuide":"편하게 인사해요","capacity":20,"memberCount":3,"status":"ACTIVE","role":null}],"nextCursor":"101"}"#
        let myApplicationPage = #"{"items":[{"applicationId":"301","crewId":"101","crewName":"모브 새벽 크루","note":"같이 달리고 싶어요","grade":null,"status":"PENDING","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:00:00Z"}],"nextCursor":"301"}"#
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 200, data: Data(directoryPage.utf8)),
            APIClientResponse(statusCode: 200, data: Data(myApplicationPage.utf8))
        ])
        let client = try makeRecordingClient(transport)

        let crews = try await client.searchCrews(query: "새벽 러닝", cursor: "105", size: 7)
        let applications = try await client.fetchMyPendingApplications(cursor: "302", size: 9)

        XCTAssertEqual(crews.items.map(\.id), ["101"])
        XCTAssertEqual(crews.nextCursor, "101")
        XCTAssertEqual(applications.items.map(\.id), ["301"])
        XCTAssertEqual(applications.items.first?.crewName, "모브 새벽 크루")
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), ["crews", "crews/me/applications"])
        XCTAssertEqual(requests.map(\.method), ["GET", "GET"])
        XCTAssertEqual(requests[0].queryItems.first(where: { $0.name == "q" })?.value, "새벽 러닝")
        XCTAssertEqual(requests[0].queryItems.first(where: { $0.name == "cursor" })?.value, "105")
        XCTAssertEqual(requests[0].queryItems.first(where: { $0.name == "size" })?.value, "7")
        XCTAssertEqual(requests[1].queryItems.first(where: { $0.name == "cursor" })?.value, "302")
        XCTAssertEqual(requests[1].queryItems.first(where: { $0.name == "size" })?.value, "9")
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
    }

    func testCrewInformationUpdateSendsFullReplacementIncludingExplicitNulls() async throws {
        let updated = #"{"crewId":"101","name":"새벽 러닝 크루","introduction":null,"joinGuide":null,"capacity":20,"memberCount":3,"status":"ACTIVE","role":"OWNER"}"#
        let transport = CrewRecordingTransport([APIClientResponse(statusCode: 200, data: Data(updated.utf8))])
        let result = try await makeRecordingClient(transport).updateCrew(
            crewID: "101", name: "새벽 러닝 크루", introduction: nil, joinGuide: nil
        )

        XCTAssertEqual(result.name, "새벽 러닝 크루")
        let captured = await transport.capturedRequests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.path, "crews/101")
        XCTAssertEqual(request.method, "PUT")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["name", "introduction", "joinGuide"]))
        XCTAssertEqual(json["name"] as? String, "새벽 러닝 크루")
        XCTAssertTrue(json["introduction"] is NSNull)
        XCTAssertTrue(json["joinGuide"] is NSNull)
    }

    func testDirectoryPageAndInformationMutationRejectInvalidContractsBeforeRetry() async throws {
        let transport = CrewRecordingTransport([APIClientResponse(statusCode: 403, data: Data(#"{"code":"FORBIDDEN"}"#.utf8))])
        let client = try makeRecordingClient(transport)
        do {
            _ = try await client.searchCrews(query: "a", cursor: "opaque", size: 20)
            XCTFail("The contract cursor is a positive numeric resource ID")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        do {
            _ = try await client.searchCrews(query: String(repeating: "a", count: 31), cursor: nil, size: 20)
            XCTFail("Search input is limited to 30 graphemes by the API contract")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        do {
            _ = try await client.updateCrew(crewID: "101", name: "변경", introduction: nil, joinGuide: nil)
            XCTFail("Non-manager updates must keep the server's forbidden response")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .forbidden)
        }
        let captured = await transport.capturedRequests()
        XCTAssertEqual(captured.count, 1)
    }

    func testApplicationSubmissionUsesContractBodyAndOneAttemptOnUnknownOutcome() async throws {
        let transport = CrewRecordingTransport([APIClientResponse(statusCode: 201, data: Data(application.utf8))])
        let submitted = try await makeRecordingClient(transport).apply(crewID: "101", note: "같이 달리고 싶어요", grade: nil)
        XCTAssertEqual(submitted.id, "301")

        let successfulRequests = await transport.capturedRequests()
        let request = try XCTUnwrap(successfulRequests.first)
        XCTAssertEqual(request.path, "crews/101/applications")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Authorization"], "Bearer member-a-token")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let requestBody = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(json["note"] as? String, "같이 달리고 싶어요")
        XCTAssertNil(json["grade"] as? String)

        MockURLProtocol.reset()
        MockURLProtocol.fail(with: .timedOut)
        do {
            _ = try await makeClient().apply(crewID: "101", note: nil, grade: nil)
            XCTFail("A create with an ambiguous transport failure must not be retried or reported as rejected")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .applicationResultUnknown)
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testPendingApprovalAndCancellationUseOnlyContractedRoutes() async throws {
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 200, data: Data("[\(application)]".utf8)),
            APIClientResponse(statusCode: 200, data: Data(application.replacingOccurrences(of: "PENDING", with: "APPROVED").utf8)),
            APIClientResponse(statusCode: 200, data: Data(application.replacingOccurrences(of: "PENDING", with: "REJECTED").utf8)),
            APIClientResponse(statusCode: 204, data: Data())
        ])
        let client = try makeRecordingClient(transport)

        let pending = try await client.fetchPendingApplications(crewID: "101")
        let approved = try await client.decide(crewID: "101", applicationID: "301", approve: true)
        let rejected = try await client.decide(crewID: "101", applicationID: "301", approve: false)
        XCTAssertEqual(pending.map(\.id), ["301"])
        XCTAssertEqual(approved.status, "APPROVED")
        XCTAssertEqual(rejected.status, "REJECTED")
        try await client.cancelApplication(crewID: "101", applicationID: "301")

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), [
            "crews/101/applications",
            "crews/101/applications/301/approve",
            "crews/101/applications/301/reject",
            "crews/101/applications/301"
        ])
        XCTAssertEqual(requests.map(\.method), ["GET", "POST", "POST", "DELETE"])
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" && $0.headers["Authorization"] == "Bearer member-a-token" })
        XCTAssertTrue(requests.dropFirst().allSatisfy { $0.body == nil })
    }

    func testCrewBoardListAndPostsKeepStableCrewAndBoardIDs() async throws {
        let board = #"{"boardId":"501","crewId":"101","name":"러닝 일정","kind":"INTERNAL","status":"ACTIVE","createdAt":"2026-10-17T10:00:00Z"}"#
        let page = #"{"items":[{"postId":"401","crewId":"101","crewName":"모브 새벽 크루","boardId":"501","boardName":"러닝 일정","boardKind":"INTERNAL","authorMemberId":"202","authorNickname":"RunMate","title":"토요일 일정","content":"오전 8시에 만나요.","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:00:00Z"}],"nextCursor":null}"#
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 200, data: Data("[\(board)]".utf8)),
            APIClientResponse(statusCode: 200, data: Data(page.utf8)),
            APIClientResponse(statusCode: 200, data: Data(post.utf8))
        ])
        let client = try makeRecordingClient(transport)

        let boards = try await client.fetchBoards(crewID: "101")
        let posts = try await client.fetchPosts(crewID: "101", boardID: "501", size: 10)
        let detail = try await client.fetchPost(crewID: "101", boardID: "501", postID: "401")
        XCTAssertEqual(boards.first?.id, "501")
        XCTAssertEqual(posts.items.first?.id, "401")
        XCTAssertEqual(detail.title, "토요일 일정")
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), [
            "crews/101/boards",
            "crews/101/boards/501/posts",
            "crews/101/boards/501/posts/401"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
    }

    func testPostEditAndDeleteUseConfirmedCrewBoardControllerRoutes() async throws {
        let edited = #"{"postId":"401","crewId":"101","crewName":"모브 새벽 크루","boardId":"501","boardName":"러닝 일정","boardKind":"INTERNAL","authorMemberId":"202","authorNickname":"RunMate","title":"수정된 일정","content":"오전 9시에 만나요.","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T12:00:00Z"}"#
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 200, data: Data(edited.utf8)),
            APIClientResponse(statusCode: 204, data: Data())
        ])
        let client = try makeRecordingClient(transport)

        let result = try await client.updatePost(crewID: "101", boardID: "501", postID: "401", title: "수정된 일정", content: "오전 9시에 만나요.")
        XCTAssertEqual(result.title, "수정된 일정")
        try await client.deletePost(crewID: "101", boardID: "501", postID: "401")

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.map(\.path), [
            "crews/101/boards/501/posts/401",
            "crews/101/boards/501/posts/401"
        ])
        XCTAssertEqual(requests.map(\.method), ["PATCH", "DELETE"])
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
        let requestBody = try XCTUnwrap(requests[0].body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["title", "content"]))
        XCTAssertEqual(json["title"] as? String, "수정된 일정")
        XCTAssertEqual(json["content"] as? String, "오전 9시에 만나요.")
        XCTAssertNil(requests[1].body)
    }

    func testPostMutationRejectsNoncanonicalIDsAndUnknownUpdateResponse() async throws {
        let wrongPost = post.replacingOccurrences(of: #""postId":"401""#, with: #""postId":"402""#)
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 200, data: Data(wrongPost.utf8)),
            APIClientResponse(statusCode: 202, data: Data(#"{"accepted":true}"#.utf8)),
            APIClientResponse(statusCode: 200, data: Data())
        ])
        let client = try makeRecordingClient(transport)

        do {
            _ = try await client.updatePost(crewID: "101", boardID: "501", postID: "../401", title: "수정", content: "본문")
            XCTFail("The endpoint requires canonical resource IDs")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        do {
            _ = try await client.updatePost(crewID: "101", boardID: "501", postID: "401", title: "수정", content: "본문")
            XCTFail("A response for another post cannot be accepted after a mutation")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .mutationResultUnknown)
        }
        do {
            _ = try await client.updatePost(crewID: "101", boardID: "501", postID: "401", title: "수정", content: "본문")
            XCTFail("An unexpected successful PATCH status may have applied the edit")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .mutationResultUnknown)
        }
        do {
            try await client.deletePost(crewID: "101", boardID: "501", postID: "401")
            XCTFail("An unexpected successful DELETE status may have applied the delete")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .mutationResultUnknown)
        }
        do {
            try await client.deletePost(crewID: "101", boardID: "501", postID: "0401")
            XCTFail("Leading-zero IDs are not canonical")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.method), ["PATCH", "PATCH", "DELETE"])
    }

    func testEveryCrewMutationClassifiesUnexpected2xxAsUnknown() async throws {
        typealias Mutation = (CrewClient) async throws -> Void
        let board = #"{"boardId":"501","crewId":"101","name":"러닝 일정","kind":"INTERNAL","status":"ACTIVE","createdAt":"2026-10-17T10:00:00Z"}"#
        let approvedApplication = application.replacingOccurrences(of: "PENDING", with: "APPROVED")
        let mutations: [(String, APIClientResponse, CrewClientFailure, Mutation)] = [
            ("create crew", .init(statusCode: 200, data: Data(crew.utf8)), .mutationResultUnknown,
             { _ = try await $0.createCrew(name: "새 크루", introduction: nil, joinGuide: nil) }),
            ("update crew", .init(statusCode: 201, data: Data(crew.utf8)), .mutationResultUnknown,
             { _ = try await $0.updateCrew(crewID: "101", name: "수정", introduction: nil, joinGuide: nil) }),
            ("apply", .init(statusCode: 200, data: Data(application.utf8)), .applicationResultUnknown,
             { _ = try await $0.apply(crewID: "101", note: nil) }),
            ("approve/reject", .init(statusCode: 201, data: Data(approvedApplication.utf8)), .mutationResultUnknown,
             { _ = try await $0.decide(crewID: "101", applicationID: "301", approve: true) }),
            ("cancel application", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.cancelApplication(crewID: "101", applicationID: "301") }),
            ("create board", .init(statusCode: 200, data: Data(board.utf8)), .mutationResultUnknown,
             { _ = try await $0.createBoard(crewID: "101", name: "새 게시판") }),
            ("rename board", .init(statusCode: 201, data: Data(board.utf8)), .mutationResultUnknown,
             { _ = try await $0.renameBoard(crewID: "101", boardID: "501", name: "수정 게시판") }),
            ("archive board", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.archiveBoard(crewID: "101", boardID: "501") }),
            ("restore board", .init(statusCode: 201, data: Data(board.utf8)), .mutationResultUnknown,
             { _ = try await $0.restoreBoard(crewID: "101", boardID: "501") }),
            ("create post", .init(statusCode: 200, data: Data(post.utf8)), .mutationResultUnknown,
             { _ = try await $0.createPost(crewID: "101", boardID: "501", title: "제목", content: "내용") }),
            ("update post", .init(statusCode: 201, data: Data(post.utf8)), .mutationResultUnknown,
             { _ = try await $0.updatePost(crewID: "101", boardID: "501", postID: "401", title: "제목", content: "내용") }),
            ("delete post", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.deletePost(crewID: "101", boardID: "501", postID: "401") }),
            ("update member role", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.updateMemberRole(crewID: "101", memberID: "202", role: "OPERATOR") }),
            ("remove member", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.removeMember(crewID: "101", memberID: "202") }),
            ("release rejoin restriction", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.releaseRejoinRestriction(crewID: "101", memberID: "202") }),
            ("transfer ownership", .init(statusCode: 200, data: Data()), .mutationResultUnknown,
             { try await $0.transferOwnership(crewID: "101", memberID: "202") })
        ]

        for (name, response, expectedFailure, mutation) in mutations {
            let transport = CrewRecordingTransport([response])
            do {
                try await mutation(makeRecordingClient(transport))
                XCTFail("\(name): an out-of-contract 2xx response must not be treated as confirmed success")
            } catch let failure as CrewClientFailure {
                XCTAssertEqual(failure, expectedFailure, "\(name)")
            }
            let requests = await transport.capturedRequests()
            XCTAssertEqual(requests.count, 1, "\(name): an unknown outcome must not issue an automatic second write")
        }
    }

    func testEveryDecodedCrewMutationClassifiesMalformedSuccessBodyAsUnknown() async throws {
        typealias Mutation = (CrewClient) async throws -> Void
        let mutations: [(String, Int, CrewClientFailure, Mutation)] = [
            ("create crew", 201, .mutationResultUnknown,
             { _ = try await $0.createCrew(name: "새 크루", introduction: nil, joinGuide: nil) }),
            ("update crew", 200, .mutationResultUnknown,
             { _ = try await $0.updateCrew(crewID: "101", name: "수정", introduction: nil, joinGuide: nil) }),
            ("apply", 201, .applicationResultUnknown,
             { _ = try await $0.apply(crewID: "101", note: nil) }),
            ("approve/reject", 200, .mutationResultUnknown,
             { _ = try await $0.decide(crewID: "101", applicationID: "301", approve: true) }),
            ("create board", 201, .mutationResultUnknown,
             { _ = try await $0.createBoard(crewID: "101", name: "새 게시판") }),
            ("rename board", 200, .mutationResultUnknown,
             { _ = try await $0.renameBoard(crewID: "101", boardID: "501", name: "수정 게시판") }),
            ("restore board", 200, .mutationResultUnknown,
             { _ = try await $0.restoreBoard(crewID: "101", boardID: "501") }),
            ("create post", 201, .mutationResultUnknown,
             { _ = try await $0.createPost(crewID: "101", boardID: "501", title: "제목", content: "내용") }),
            ("update post", 200, .mutationResultUnknown,
             { _ = try await $0.updatePost(crewID: "101", boardID: "501", postID: "401", title: "제목", content: "내용") })
        ]

        for (name, statusCode, expectedFailure, mutation) in mutations {
            let transport = CrewRecordingTransport([
                APIClientResponse(statusCode: statusCode, data: Data("not-json".utf8))
            ])
            do {
                try await mutation(makeRecordingClient(transport))
                XCTFail("\(name): a malformed success body must be classified as an unknown mutation outcome")
            } catch let failure as CrewClientFailure {
                XCTAssertEqual(failure, expectedFailure, "\(name)")
            }
            let requests = await transport.capturedRequests()
            XCTAssertEqual(requests.count, 1, "\(name): malformed success must not be retried automatically")
        }
    }

    func testSessionChangeWhileResponseIsInFlightDiscardsOldAccountData() async throws {
        let session = MutableCrewSession(RunUploadSession(ownerID: "101", accessToken: "member-a-token"))
        let transport = CrewSwitchingTransport(session: session, response: APIClientResponse(statusCode: 200, data: Data("[\(crew)]".utf8)))
        let client = CrewClient(apiClient: transport, sessionProvider: session)

        do {
            _ = try await client.fetchMyCrews()
            XCTFail("A response captured under a previous member must be discarded")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .sessionChanged)
        }
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer member-a-token")
    }

    func testForbiddenResponseAndInvalidIDsFailClosedWithoutSending() async throws {
        let transport = CrewRecordingTransport([APIClientResponse(statusCode: 403, data: Data(#"{"code":"FORBIDDEN"}"#.utf8))])
        let client = try makeRecordingClient(transport)
        do {
            _ = try await client.fetchPendingApplications(crewID: "101")
            XCTFail("A non-manager must not receive the protected queue")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .forbidden)
        }
        do {
            _ = try await client.fetchCrew(id: "../me")
            XCTFail("Path components must not be interpolated into endpoint IDs")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testFailedReadCanBeRetriedExplicitlyWithoutAutomaticDuplicateRequest() async throws {
        let transport = CrewRecordingTransport([
            APIClientResponse(statusCode: 503, data: Data(#"{"code":"SERVICE_UNAVAILABLE"}"#.utf8)),
            APIClientResponse(statusCode: 200, data: Data("[\(crew)]".utf8))
        ])
        let client = try makeRecordingClient(transport)

        do {
            _ = try await client.fetchMyCrews()
            XCTFail("The unavailable response should be surfaced to the caller")
        } catch let failure as CrewClientFailure {
            XCTAssertEqual(failure, .serviceUnavailable(code: "SERVICE_UNAVAILABLE"))
        }

        let retry = try await client.fetchMyCrews()
        XCTAssertEqual(retry.map(\.id), ["101"])
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2, "Only the explicit second call should issue another read")
        XCTAssertTrue(requests.allSatisfy { $0.method == "GET" && $0.path == "crews/me" })
    }

    private func makeRecordingClient(_ transport: any APIResponseSending) throws -> CrewClient {
        CrewClient(apiClient: transport,
                   sessionProvider: CrewSessionStub(value: RunUploadSession(ownerID: "202", accessToken: "member-a-token")))
    }
}
