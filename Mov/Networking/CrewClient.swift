import Foundation

struct BackendCrew: Codable, Equatable, Sendable, Identifiable {
    let crewId: String
    let name: String
    let introduction: String?
    let joinGuide: String?
    let capacity: Int
    let memberCount: Int
    let status: String
    let role: String?

    var id: String { crewId }
}

struct BackendCrewMember: Codable, Equatable, Sendable, Identifiable {
    let memberId: String
    let role: String
    let joinedAt: String

    var id: String { memberId }
}

struct BackendCrewRejoinRestriction: Codable, Equatable, Sendable, Identifiable {
    let memberId: String
    let createdAt: String

    var id: String { memberId }
}

struct BackendCrewApplication: Codable, Equatable, Sendable, Identifiable {
    let applicationId: String
    let crewId: String
    let memberId: String
    let note: String?
    let grade: String?
    let status: String
    let createdAt: String
    let updatedAt: String

    var id: String { applicationId }
}

struct BackendCrewBoard: Codable, Equatable, Sendable, Identifiable {
    let boardId: String
    let crewId: String
    let name: String
    let kind: String
    let status: String
    let createdAt: String

    var id: String { boardId }
}

struct BackendCrewPost: Codable, Equatable, Sendable, Identifiable {
    let postId: String
    let crewId: String
    let crewName: String
    let boardId: String
    let boardName: String
    let boardKind: String
    let authorMemberId: String?
    let authorNickname: String
    let title: String
    let content: String
    let createdAt: String
    let updatedAt: String

    var id: String { postId }
}

struct BackendCrewComment: Codable, Equatable, Sendable, Identifiable {
    let commentId: String
    let postId: String
    let parentId: String?
    let rootId: String
    let authorMemberId: String?
    let authorNickname: String
    let content: String
    let deleted: Bool
    let mentionedMemberIds: [String]
    let createdAt: String
    let deletedAt: String?

    var id: String { commentId }
}

struct BackendCrewPage<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let items: [Item]
    let nextCursor: String?
}

enum CrewClientFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case sessionChanged
    case unauthenticated
    case forbidden
    case notFound
    case validationFailed
    case conflict(code: String?)
    case tooManyRequests(retryAfter: String?)
    case serviceUnavailable(code: String?)
    case serverFailure(statusCode: Int)
    case applicationResultUnknown
    case mutationResultUnknown
    case invalidRequest
    case invalidResponse
    case transport(URLError.Code)
    case cancelled

    var canRetryRead: Bool {
        switch self {
        case .serviceUnavailable, .serverFailure, .transport:
            true
        default:
            false
        }
    }
}

protocol CrewServing: Sendable {
    func createCrew(name: String, introduction: String?, joinGuide: String?) async throws -> BackendCrew
    func fetchMyCrews() async throws -> [BackendCrew]
    func fetchCrew(id: String) async throws -> BackendCrew
    func fetchMembers(crewID: String) async throws -> [BackendCrewMember]
    func updateMemberRole(crewID: String, memberID: String, role: String) async throws
    func removeMember(crewID: String, memberID: String) async throws
    func fetchRejoinRestrictions(crewID: String) async throws -> [BackendCrewRejoinRestriction]
    func releaseRejoinRestriction(crewID: String, memberID: String) async throws
    func transferOwnership(crewID: String, memberID: String) async throws
    func fetchRecruitmentPosts(cursor: String?, size: Int) async throws -> BackendCrewPage<BackendCrewPost>
    func apply(crewID: String, note: String?, grade: String?) async throws -> BackendCrewApplication
    func fetchPendingApplications(crewID: String) async throws -> [BackendCrewApplication]
    func decide(crewID: String, applicationID: String, approve: Bool) async throws -> BackendCrewApplication
    func cancelApplication(crewID: String, applicationID: String) async throws
    func fetchBoards(crewID: String) async throws -> [BackendCrewBoard]
    func createBoard(crewID: String, name: String, kind: String) async throws -> BackendCrewBoard
    func renameBoard(crewID: String, boardID: String, name: String) async throws -> BackendCrewBoard
    func archiveBoard(crewID: String, boardID: String) async throws
    func restoreBoard(crewID: String, boardID: String) async throws -> BackendCrewBoard
    func fetchPosts(crewID: String, boardID: String, cursor: String?, size: Int) async throws -> BackendCrewPage<BackendCrewPost>
    func fetchPost(crewID: String, boardID: String, postID: String) async throws -> BackendCrewPost
    func createPost(crewID: String, boardID: String, title: String, content: String) async throws -> BackendCrewPost
    func updatePost(crewID: String, boardID: String, postID: String, title: String, content: String) async throws -> BackendCrewPost
    func deletePost(crewID: String, boardID: String, postID: String) async throws
    func currentMemberID() async throws -> String
}

struct CrewClient: CrewServing, Sendable {
    private let apiClient: any APIResponseSending
    private let sessionProvider: any RunUploadSessionProviding

    init(apiClient: any APIResponseSending, sessionProvider: any RunUploadSessionProviding) {
        self.apiClient = apiClient
        self.sessionProvider = sessionProvider
    }

    func createCrew(name: String, introduction: String?, joinGuide: String?) async throws -> BackendCrew {
        guard !Task.isCancelled else { throw CrewClientFailure.cancelled }
        let body = try Self.encode(CreateCrewRequest(name: name, introduction: introduction, joinGuide: joinGuide))
        let response: APIClientResponse
        do {
            response = try await send(path: "crews", method: "POST", body: body)
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled: throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
        guard response.statusCode == 201 else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.mutationResultUnknown }
            throw Self.mapFailure(response)
        }
        do {
            let crew = try Self.decode(BackendCrew.self, from: response.data)
            guard Self.isValid(crew), crew.role == "OWNER" else { throw CrewClientFailure.mutationResultUnknown }
            return crew
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
    }

    func fetchMyCrews() async throws -> [BackendCrew] {
        let response = try await send(path: "crews/me", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        return try Self.decode([BackendCrew].self, from: response.data)
    }

    func fetchCrew(id: String) async throws -> BackendCrew {
        guard Self.isResourceID(id) else { throw CrewClientFailure.invalidRequest }
        let response = try await send(path: "crews/\(id)", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let crew = try Self.decode(BackendCrew.self, from: response.data)
        guard crew.crewId == id, Self.isValid(crew) else { throw CrewClientFailure.invalidResponse }
        return crew
    }

    func fetchMembers(crewID: String) async throws -> [BackendCrewMember] {
        guard Self.isResourceID(crewID) else { throw CrewClientFailure.invalidRequest }
        let response = try await send(path: "crews/\(crewID)/members", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let members = try Self.decode([BackendCrewMember].self, from: response.data)
        guard members.allSatisfy(Self.isValid) else { throw CrewClientFailure.invalidResponse }
        return members
    }

    func updateMemberRole(crewID: String, memberID: String, role: String) async throws {
        guard ["OPERATOR", "MEMBER"].contains(role) else { throw CrewClientFailure.invalidRequest }
        try await sendNoContentMutation(
            path: "crews/\(crewID)/members/\(memberID)/role",
            method: "PATCH",
            crewID: crewID,
            memberID: memberID,
            body: try Self.encode(RoleRequest(role: role))
        )
    }

    func removeMember(crewID: String, memberID: String) async throws {
        try await sendNoContentMutation(
            path: "crews/\(crewID)/members/\(memberID)", method: "DELETE", crewID: crewID, memberID: memberID
        )
    }

    func fetchRejoinRestrictions(crewID: String) async throws -> [BackendCrewRejoinRestriction] {
        guard Self.isResourceID(crewID) else { throw CrewClientFailure.invalidRequest }
        let response = try await send(path: "crews/\(crewID)/rejoin-restrictions", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let restrictions = try Self.decode([BackendCrewRejoinRestriction].self, from: response.data)
        guard restrictions.allSatisfy({ Self.isResourceID($0.memberId) && !$0.createdAt.isEmpty }) else {
            throw CrewClientFailure.invalidResponse
        }
        return restrictions
    }

    func releaseRejoinRestriction(crewID: String, memberID: String) async throws {
        try await sendNoContentMutation(
            path: "crews/\(crewID)/members/\(memberID)/rejoin-restriction",
            method: "DELETE", crewID: crewID, memberID: memberID
        )
    }

    func transferOwnership(crewID: String, memberID: String) async throws {
        guard Self.isResourceID(memberID), let numericID = Int64(memberID) else { throw CrewClientFailure.invalidRequest }
        try await sendNoContentMutation(
            path: "crews/\(crewID)/ownership-transfer",
            method: "POST", crewID: crewID, memberID: memberID,
            body: try Self.encode(TransferRequest(memberId: numericID))
        )
    }

    func fetchRecruitmentPosts(cursor: String? = nil, size: Int = 20) async throws -> BackendCrewPage<BackendCrewPost> {
        guard Self.isValidPage(cursor: cursor, size: size) else { throw CrewClientFailure.invalidRequest }
        var query = [URLQueryItem(name: "size", value: String(size))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response = try await send(path: "community/boards/crew-recruitment/posts", method: "GET", queryItems: query)
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let page = try Self.decode(BackendCrewPage<BackendCrewPost>.self, from: response.data)
        guard page.items.allSatisfy(Self.isValidRecruitmentPost) else { throw CrewClientFailure.invalidResponse }
        return page
    }

    func apply(crewID: String, note: String?, grade: String? = nil) async throws -> BackendCrewApplication {
        guard !Task.isCancelled else { throw CrewClientFailure.cancelled }
        guard Self.isResourceID(crewID) else { throw CrewClientFailure.invalidRequest }
        let body = try Self.encode(ApplyRequest(note: note, grade: grade))
        let response: APIClientResponse
        do {
            response = try await send(path: "crews/\(crewID)/applications", method: "POST", body: body)
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled:
                throw CrewClientFailure.applicationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.applicationResultUnknown
        }
        guard response.statusCode == 201 else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.applicationResultUnknown }
            throw Self.mapFailure(response)
        }
        do {
            let application = try Self.decode(BackendCrewApplication.self, from: response.data)
            guard Self.isValid(application), application.crewId == crewID else {
                throw CrewClientFailure.applicationResultUnknown
            }
            return application
        } catch {
            throw CrewClientFailure.applicationResultUnknown
        }
    }

    func fetchPendingApplications(crewID: String) async throws -> [BackendCrewApplication] {
        guard Self.isResourceID(crewID) else { throw CrewClientFailure.invalidRequest }
        let response = try await send(path: "crews/\(crewID)/applications", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let applications = try Self.decode([BackendCrewApplication].self, from: response.data)
        guard applications.allSatisfy({ Self.isValid($0) && $0.crewId == crewID && $0.status == "PENDING" }) else {
            throw CrewClientFailure.invalidResponse
        }
        return applications
    }

    func decide(crewID: String, applicationID: String, approve: Bool) async throws -> BackendCrewApplication {
        guard !Task.isCancelled else { throw CrewClientFailure.cancelled }
        guard Self.isResourceID(crewID), Self.isResourceID(applicationID) else { throw CrewClientFailure.invalidRequest }
        let action = approve ? "approve" : "reject"
        let response: APIClientResponse
        do {
            response = try await send(path: "crews/\(crewID)/applications/\(applicationID)/\(action)", method: "POST")
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled:
                throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
        guard response.statusCode == 200 else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.mutationResultUnknown }
            throw Self.mapFailure(response)
        }
        do {
            let application = try Self.decode(BackendCrewApplication.self, from: response.data)
            guard Self.isValid(application), application.crewId == crewID, application.applicationId == applicationID else {
                throw CrewClientFailure.mutationResultUnknown
            }
            return application
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
    }

    func cancelApplication(crewID: String, applicationID: String) async throws {
        guard !Task.isCancelled else { throw CrewClientFailure.cancelled }
        guard Self.isResourceID(crewID), Self.isResourceID(applicationID) else { throw CrewClientFailure.invalidRequest }
        let response: APIClientResponse
        do {
            response = try await send(path: "crews/\(crewID)/applications/\(applicationID)", method: "DELETE")
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled:
                throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
        guard response.statusCode == 204 else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.mutationResultUnknown }
            throw Self.mapFailure(response)
        }
    }

    func fetchBoards(crewID: String) async throws -> [BackendCrewBoard] {
        guard Self.isResourceID(crewID) else { throw CrewClientFailure.invalidRequest }
        let response = try await send(path: "crews/\(crewID)/boards", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let boards = try Self.decode([BackendCrewBoard].self, from: response.data)
        guard boards.allSatisfy({ Self.isValid($0) && $0.crewId == crewID }) else { throw CrewClientFailure.invalidResponse }
        return boards
    }

    func createBoard(crewID: String, name: String, kind: String = "INTERNAL") async throws -> BackendCrewBoard {
        guard Self.isResourceID(crewID), ["INTERNAL", "RECRUITMENT"].contains(kind) else { throw CrewClientFailure.invalidRequest }
        let board: BackendCrewBoard = try await sendDecodedMutation(
            path: "crews/\(crewID)/boards", method: "POST", expectedStatus: 201,
            body: try Self.encode(CreateBoardRequest(name: name, kind: kind)), crewID: crewID
        )
        return board
    }

    func renameBoard(crewID: String, boardID: String, name: String) async throws -> BackendCrewBoard {
        guard Self.isResourceID(boardID) else { throw CrewClientFailure.invalidRequest }
        return try await sendDecodedMutation(
            path: "crews/\(crewID)/boards/\(boardID)", method: "PATCH", expectedStatus: 200,
            body: try Self.encode(RenameBoardRequest(name: name)), crewID: crewID, boardID: boardID
        )
    }

    func archiveBoard(crewID: String, boardID: String) async throws {
        try await sendNoContentMutation(path: "crews/\(crewID)/boards/\(boardID)", method: "DELETE", crewID: crewID, boardID: boardID)
    }

    func restoreBoard(crewID: String, boardID: String) async throws -> BackendCrewBoard {
        guard Self.isResourceID(boardID) else { throw CrewClientFailure.invalidRequest }
        return try await sendDecodedMutation(
            path: "crews/\(crewID)/boards/\(boardID)/restore", method: "POST", expectedStatus: 200,
            crewID: crewID, boardID: boardID
        )
    }

    func fetchPosts(crewID: String, boardID: String, cursor: String? = nil, size: Int = 20) async throws -> BackendCrewPage<BackendCrewPost> {
        guard Self.isResourceID(crewID), Self.isResourceID(boardID), Self.isValidPage(cursor: cursor, size: size) else {
            throw CrewClientFailure.invalidRequest
        }
        var query = [URLQueryItem(name: "size", value: String(size))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response = try await send(path: "crews/\(crewID)/boards/\(boardID)/posts", method: "GET", queryItems: query)
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let page = try Self.decode(BackendCrewPage<BackendCrewPost>.self, from: response.data)
        guard page.items.allSatisfy({ Self.isValid($0) && $0.crewId == crewID && $0.boardId == boardID }) else {
            throw CrewClientFailure.invalidResponse
        }
        return page
    }

    func fetchPost(crewID: String, boardID: String, postID: String) async throws -> BackendCrewPost {
        guard Self.isResourceID(crewID), Self.isResourceID(boardID), Self.isResourceID(postID) else {
            throw CrewClientFailure.invalidRequest
        }
        let response = try await send(path: "crews/\(crewID)/boards/\(boardID)/posts/\(postID)", method: "GET")
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        let post = try Self.decode(BackendCrewPost.self, from: response.data)
        guard Self.isValid(post), post.crewId == crewID, post.boardId == boardID else { throw CrewClientFailure.invalidResponse }
        return post
    }

    func currentMemberID() async throws -> String {
        do {
            guard let session = try await sessionProvider.currentSession(), Self.isValid(session) else {
                throw CrewClientFailure.accessTokenUnavailable
            }
            return session.ownerID
        } catch let failure as CrewClientFailure {
            throw failure
        } catch {
            throw CrewClientFailure.accessTokenUnavailable
        }
    }

    func createPost(crewID: String, boardID: String, title: String, content: String) async throws -> BackendCrewPost {
        guard !Task.isCancelled else { throw CrewClientFailure.cancelled }
        guard Self.isResourceID(crewID), Self.isResourceID(boardID) else { throw CrewClientFailure.invalidRequest }
        let body = try Self.encode(PostRequest(title: title, content: content))
        let response: APIClientResponse
        do {
            response = try await send(path: "crews/\(crewID)/boards/\(boardID)/posts", method: "POST", body: body)
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled:
                throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
        guard response.statusCode == 201 else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.mutationResultUnknown }
            throw Self.mapFailure(response)
        }
        do {
            let post = try Self.decode(BackendCrewPost.self, from: response.data)
            guard Self.isValid(post), post.crewId == crewID, post.boardId == boardID else { throw CrewClientFailure.mutationResultUnknown }
            return post
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
    }

    func updatePost(crewID: String, boardID: String, postID: String, title: String, content: String) async throws -> BackendCrewPost {
        guard Self.isResourceID(crewID), Self.isResourceID(boardID), Self.isResourceID(postID) else {
            throw CrewClientFailure.invalidRequest
        }
        let request = try Self.encode(PostRequest(title: title, content: content))
        let response: APIClientResponse
        do {
            response = try await send(
                path: "crews/\(crewID)/boards/\(boardID)/posts/\(postID)",
                method: "PATCH", body: request
            )
        } catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled: throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
        guard response.statusCode == 200 else {
            if (200..<300).contains(response.statusCode) || (500..<600).contains(response.statusCode) {
                throw CrewClientFailure.mutationResultUnknown
            }
            throw Self.mapFailure(response)
        }
        do {
            let post = try Self.decode(BackendCrewPost.self, from: response.data)
            guard Self.isValid(post), post.crewId == crewID, post.boardId == boardID, post.postId == postID else {
                throw CrewClientFailure.mutationResultUnknown
            }
            return post
        } catch {
            throw CrewClientFailure.mutationResultUnknown
        }
    }

    func deletePost(crewID: String, boardID: String, postID: String) async throws {
        try await sendNoContentMutation(
            path: "crews/\(crewID)/boards/\(boardID)/posts/\(postID)", method: "DELETE",
            crewID: crewID, boardID: boardID, postID: postID
        )
    }

    private func sendNoContentMutation(
        path: String,
        method: String,
        crewID: String,
        memberID: String? = nil,
        boardID: String? = nil,
        postID: String? = nil,
        body: Data? = nil
    ) async throws {
        guard !Task.isCancelled,
              Self.isResourceID(crewID),
              memberID.map(Self.isResourceID) ?? true,
              boardID.map(Self.isResourceID) ?? true,
              postID.map(Self.isResourceID) ?? true else { throw CrewClientFailure.invalidRequest }
        let response: APIClientResponse
        do { response = try await send(path: path, method: method, body: body) }
        catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled: throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch { throw CrewClientFailure.mutationResultUnknown }
        guard response.statusCode == 204 else {
            if (200..<300).contains(response.statusCode) || (500..<600).contains(response.statusCode) {
                throw CrewClientFailure.mutationResultUnknown
            }
            throw Self.mapFailure(response)
        }
    }

    private func sendDecodedMutation<T: Decodable & Sendable>(
        path: String,
        method: String,
        expectedStatus: Int,
        body: Data? = nil,
        crewID: String,
        boardID: String? = nil
    ) async throws -> T {
        guard !Task.isCancelled, Self.isResourceID(crewID), boardID.map(Self.isResourceID) ?? true else {
            throw CrewClientFailure.invalidRequest
        }
        let response: APIClientResponse
        do { response = try await send(path: path, method: method, body: body) }
        catch let failure as CrewClientFailure {
            switch failure {
            case .transport, .invalidResponse, .cancelled: throw CrewClientFailure.mutationResultUnknown
            default: throw failure
            }
        } catch { throw CrewClientFailure.mutationResultUnknown }
        guard response.statusCode == expectedStatus else {
            if (500..<600).contains(response.statusCode) { throw CrewClientFailure.mutationResultUnknown }
            throw Self.mapFailure(response)
        }
        do {
            let value = try Self.decode(T.self, from: response.data)
            guard let board = value as? BackendCrewBoard,
                  Self.isValid(board), board.crewId == crewID,
                  boardID.map({ board.boardId == $0 }) ?? true else { throw CrewClientFailure.mutationResultUnknown }
            return value
        } catch { throw CrewClientFailure.mutationResultUnknown }
    }

    private func send(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> APIClientResponse {
        let session: RunUploadSession
        do {
            try Task.checkCancellation()
            guard let value = try await sessionProvider.currentSession(), Self.isValid(value) else {
                throw CrewClientFailure.accessTokenUnavailable
            }
            try Task.checkCancellation()
            session = value
        } catch let failure as CrewClientFailure {
            throw failure
        } catch is CancellationError {
            throw CrewClientFailure.cancelled
        } catch let failure as APIClientError where failure == .cancelled {
            throw CrewClientFailure.cancelled
        } catch {
            throw CrewClientFailure.accessTokenUnavailable
        }

        var headers = [
            "Authorization": "Bearer \(session.accessToken)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]
        if body != nil { headers["Content-Type"] = "application/json" }

        do {
            let response = try await apiClient.sendResponse(path: path, method: method, body: body, headers: headers, queryItems: queryItems)
            try Task.checkCancellation()
            try await ensureSameMember(as: session.ownerID)
            return response
        } catch let failure as CrewClientFailure {
            throw failure
        } catch is CancellationError {
            throw CrewClientFailure.cancelled
        } catch let failure as APIClientError {
            if failure == .cancelled { throw CrewClientFailure.cancelled }
            try await ensureSameMember(as: session.ownerID)
            if case .transport(let code) = failure { throw CrewClientFailure.transport(code) }
            throw CrewClientFailure.invalidResponse
        } catch let failure as URLError {
            if failure.code == .cancelled { throw CrewClientFailure.cancelled }
            try await ensureSameMember(as: session.ownerID)
            throw CrewClientFailure.transport(failure.code)
        } catch {
            try await ensureSameMember(as: session.ownerID)
            throw CrewClientFailure.transport(.unknown)
        }
    }

    private func ensureSameMember(as expectedMemberID: String) async throws {
        do {
            try Task.checkCancellation()
            guard let current = try await sessionProvider.currentSession(),
                  Self.isValid(current), current.ownerID == expectedMemberID else {
                throw CrewClientFailure.sessionChanged
            }
            try Task.checkCancellation()
        } catch let failure as CrewClientFailure {
            throw failure
        } catch is CancellationError {
            throw CrewClientFailure.cancelled
        } catch {
            throw CrewClientFailure.sessionChanged
        }
    }

    private static func mapFailure(_ response: APIClientResponse) -> CrewClientFailure {
        let problem = try? JSONDecoder().decode(ProblemResponse.self, from: response.data)
        switch response.statusCode {
        case 401: return .unauthenticated
        case 403: return .forbidden
        case 404: return .notFound
        case 400, 422: return .validationFailed
        case 409: return .conflict(code: problem?.code)
        case 429: return .tooManyRequests(retryAfter: problem?.retryAfter)
        case 503: return .serviceUnavailable(code: problem?.code)
        case 500...599: return .serverFailure(statusCode: response.statusCode)
        default: return .invalidResponse
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CrewClientFailure.invalidResponse }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do { return try encoder.encode(value) }
        catch { throw CrewClientFailure.invalidRequest }
    }

    private static func isValidPage(cursor: String?, size: Int) -> Bool {
        (1...50).contains(size) && (cursor?.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ?? true)
    }

    private static func isResourceID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int64(value), number > 0 else { return false }
        return String(number) == value
    }

    private static func isValid(_ session: RunUploadSession) -> Bool {
        isResourceID(session.ownerID) && !session.accessToken.isEmpty && session.accessToken.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
        }
    }

    private static func isValid(_ crew: BackendCrew) -> Bool {
        isResourceID(crew.crewId) && !crew.name.isEmpty && crew.name.count <= 30
            && (crew.introduction?.count ?? 0) <= 300 && (crew.joinGuide?.count ?? 0) <= 500
            && crew.capacity == 20 && (0...crew.capacity).contains(crew.memberCount)
            && ["ACTIVE", "ARCHIVED"].contains(crew.status)
            && (crew.role.map { ["OWNER", "OPERATOR", "MEMBER"].contains($0) } ?? true)
    }

    private static func isValid(_ member: BackendCrewMember) -> Bool {
        isResourceID(member.memberId) && ["OWNER", "OPERATOR", "MEMBER"].contains(member.role) && !member.joinedAt.isEmpty
    }

    private static func isValid(_ application: BackendCrewApplication) -> Bool {
        isResourceID(application.applicationId) && isResourceID(application.crewId) && isResourceID(application.memberId)
            && (application.note?.count ?? 0) <= 300 && !application.createdAt.isEmpty && !application.updatedAt.isEmpty
            && ["PENDING", "APPROVED", "REJECTED", "CANCELLED"].contains(application.status)
    }

    private static func isValid(_ board: BackendCrewBoard) -> Bool {
        isResourceID(board.boardId) && isResourceID(board.crewId) && !board.name.isEmpty
            && ["INTERNAL", "RECRUITMENT"].contains(board.kind) && ["ACTIVE", "ARCHIVED"].contains(board.status)
            && !board.createdAt.isEmpty
    }

    private static func isValid(_ post: BackendCrewPost) -> Bool {
        isResourceID(post.postId) && isResourceID(post.crewId) && isResourceID(post.boardId)
            && !post.crewName.isEmpty && !post.boardName.isEmpty && !post.authorNickname.isEmpty
            && ["INTERNAL", "RECRUITMENT"].contains(post.boardKind)
            && (post.authorMemberId.map(isResourceID) ?? true) && !post.title.isEmpty && !post.createdAt.isEmpty && !post.updatedAt.isEmpty
    }

    private static func isValidRecruitmentPost(_ post: BackendCrewPost) -> Bool {
        isValid(post) && post.boardKind == "RECRUITMENT"
    }

    private struct ApplyRequest: Encodable {
        let note: String?
        let grade: String?
    }

    private struct CreateCrewRequest: Encodable { let name: String; let introduction: String?; let joinGuide: String? }
    private struct RoleRequest: Encodable { let role: String }
    private struct TransferRequest: Encodable { let memberId: Int64 }
    private struct CreateBoardRequest: Encodable { let name: String; let kind: String }
    private struct RenameBoardRequest: Encodable { let name: String }

    private struct PostRequest: Encodable {
        let title: String
        let content: String
    }

    private struct ProblemResponse: Decodable {
        let code: String?
        let retryAfter: String?
    }
}
