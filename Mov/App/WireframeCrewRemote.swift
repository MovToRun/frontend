import Observation
import SwiftUI

enum WireframeCrewLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor @Observable final class WireframeCrewRemoteFlow {
    private let service: (any CrewServing)?
    private var readIDs: [String: UUID] = [:]
    private var mutationID: UUID?
    private(set) var writeBlockedKeys: Set<String> = []
    private(set) var accountScopeID: String?
    private(set) var isMutating = false
    private(set) var mutationMessage = ""
    private(set) var mutationError = false
    var myCrewsState: WireframeCrewLoadState = .idle
    var recruitmentState: WireframeCrewLoadState = .idle
    var detailState: WireframeCrewLoadState = .idle
    var boardsState: WireframeCrewLoadState = .idle
    var postsState: WireframeCrewLoadState = .idle
    var pendingState: WireframeCrewLoadState = .idle
    var myCrews: [BackendCrew] = []
    var recruitmentPosts: [BackendCrewPost] = []
    var submittedApplications: [BackendCrewApplication] = []
    var pendingApplications: [BackendCrewApplication] = []
    var boards: [BackendCrewBoard] = []
    var posts: [BackendCrewPost] = []
    var selectedCrew: BackendCrew?
    var selectedCrewID: String?
    var selectedBoardID: String?
    var selectedApplication: BackendCrewApplication?
    var selectedPost: BackendCrewPost?
    var searchText = ""
    var postDraftTitle = ""
    var postDraftContent = ""
    var showingPostComposer = false

    init(service: (any CrewServing)?) { self.service = service }

    var isAvailable: Bool { service != nil }
    var isManager: Bool { selectedCrew?.role == "OWNER" || selectedCrew?.role == "OPERATOR" }
    var selectedBoard: BackendCrewBoard? { boards.first { $0.boardId == selectedBoardID } }
    var selectedApplicationForCrew: BackendCrewApplication? {
        submittedApplications.last { $0.crewId == selectedCrewID && $0.status == "PENDING" }
    }
    var pendingApplicationCount: Int { submittedApplications.filter { $0.status == "PENDING" }.count }
    func isWriteBlocked(_ key: String) -> Bool { writeBlockedKeys.contains(key) }

    func setAccountScope(_ scopeID: String) {
        guard accountScopeID != scopeID else { return }
        accountScopeID = scopeID
        readIDs.removeAll()
        myCrewsState = .idle; recruitmentState = .idle; detailState = .idle
        boardsState = .idle; postsState = .idle; pendingState = .idle
        myCrews = []; recruitmentPosts = []; submittedApplications = []
        pendingApplications = []; boards = []; posts = []
        selectedCrew = nil; selectedCrewID = nil; selectedBoardID = nil
        selectedApplication = nil; selectedPost = nil
        writeBlockedKeys.removeAll()
        isMutating = false; mutationID = nil; mutationMessage = ""; mutationError = false
    }

    func loadOverview() async {
        await loadMyCrews()
        await loadRecruitmentPosts()
    }

    func loadMyCrews() async {
        guard let service else { return }
        let requestID = beginRead("my-crews", state: .loading)
        do {
            let value = try await service.fetchMyCrews()
            guard isCurrentRead("my-crews", id: requestID), !Task.isCancelled else { return }
            myCrews = value.filter { $0.status == "ACTIVE" }
            myCrewsState = .loaded
        } catch {
            guard isCurrentRead("my-crews", id: requestID), !Task.isCancelled else { return }
            myCrewsState = .failed(message(for: error))
        }
    }

    func loadRecruitmentPosts() async {
        guard let service else { return }
        let requestID = beginRead("recruitment", state: .loading)
        do {
            let page = try await service.fetchRecruitmentPosts(cursor: nil, size: 20)
            guard isCurrentRead("recruitment", id: requestID), !Task.isCancelled else { return }
            recruitmentPosts = page.items
            recruitmentState = .loaded
        } catch {
            guard isCurrentRead("recruitment", id: requestID), !Task.isCancelled else { return }
            recruitmentState = .failed(message(for: error))
        }
    }

    func selectCrew(_ id: String) { selectedCrewID = id; selectedCrew = nil; selectedBoardID = nil; boards = []; posts = [] }

    func loadCrewDetail() async {
        guard let service, let id = selectedCrewID else { return }
        let requestID = beginRead("crew-detail", state: .loading)
        do {
            let value = try await service.fetchCrew(id: id)
            guard isCurrentRead("crew-detail", id: requestID), !Task.isCancelled else { return }
            selectedCrew = value; detailState = .loaded
        } catch {
            guard isCurrentRead("crew-detail", id: requestID), !Task.isCancelled else { return }
            detailState = .failed(message(for: error))
        }
    }

    func loadBoards() async {
        guard let service, let id = selectedCrewID else { return }
        let requestID = beginRead("boards", state: .loading)
        do {
            let value = try await service.fetchBoards(crewID: id)
            guard isCurrentRead("boards", id: requestID), !Task.isCancelled else { return }
            boards = value.filter { $0.status == "ACTIVE" }
            if !boards.contains(where: { $0.boardId == selectedBoardID }) { selectedBoardID = boards.first?.boardId }
            boardsState = .loaded
        } catch {
            guard isCurrentRead("boards", id: requestID), !Task.isCancelled else { return }
            boardsState = .failed(message(for: error))
        }
    }

    func loadPosts() async {
        guard let service, let crewID = selectedCrewID, let boardID = selectedBoardID else {
            posts = []; postsState = .loaded; return
        }
        let requestID = beginRead("posts", state: .loading)
        do {
            let page = try await service.fetchPosts(crewID: crewID, boardID: boardID, cursor: nil, size: 20)
            guard isCurrentRead("posts", id: requestID), !Task.isCancelled else { return }
            posts = page.items; postsState = .loaded
        } catch {
            guard isCurrentRead("posts", id: requestID), !Task.isCancelled else { return }
            postsState = .failed(message(for: error))
        }
    }

    func loadPendingApplications() async {
        guard let service, let crewID = selectedCrewID else { return }
        let requestID = beginRead("pending", state: .loading)
        do {
            let value = try await service.fetchPendingApplications(crewID: crewID)
            guard isCurrentRead("pending", id: requestID), !Task.isCancelled else { return }
            pendingApplications = value; pendingState = .loaded
        } catch {
            guard isCurrentRead("pending", id: requestID), !Task.isCancelled else { return }
            pendingState = .failed(message(for: error))
        }
    }

    func submitApplication(note: String?) async -> Bool {
        guard let service, let crewID = selectedCrewID, !isMutating, !isWriteBlocked("apply|\(crewID)") else { return false }
        let requestScopeID = accountScopeID
        guard selectedCrew?.status == "ACTIVE" else { mutationMessage = "크루 상태를 확인한 뒤 다시 시도해 주세요."; mutationError = true; return false }
        let succeeded = await performMutation(key: "apply|\(crewID)", unknownMessage: "신청 결과를 확인하지 못했어요. 중복 신청을 막기 위해 다시 보내지 않았어요.") {
            let result = try await service.apply(crewID: crewID, note: note, grade: nil)
            guard self.accountScopeID == requestScopeID, self.selectedCrewID == crewID else { return }
            self.submittedApplications.removeAll { $0.crewId == crewID && $0.status == "PENDING" }
            self.submittedApplications.append(result)
            self.mutationMessage = "가입 신청을 보냈어요."
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func cancelApplication(_ application: BackendCrewApplication) async -> Bool {
        guard let service, !isMutating, application.status == "PENDING", !isWriteBlocked("cancel|\(application.id)") else { return false }
        let crewID = application.crewId
        let requestScopeID = accountScopeID
        let succeeded = await performMutation(key: "cancel|\(application.id)", unknownMessage: "취소 결과를 확인하지 못했어요. 신청 상태를 다시 확인해야 해요.") {
            try await service.cancelApplication(crewID: crewID, applicationID: application.id)
            guard self.accountScopeID == requestScopeID else { return }
            self.submittedApplications.removeAll { $0.id == application.id }
            self.mutationMessage = "가입 신청을 취소했어요."
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func reviewApplication(approve: Bool) async -> Bool {
        guard let service, let crewID = selectedCrewID, let application = selectedApplication,
              !isMutating, application.status == "PENDING", !isWriteBlocked("review|\(application.id)") else { return false }
        let requestScopeID = accountScopeID
        guard isManager else { mutationMessage = "크루장·운영자만 신청을 처리할 수 있어요."; mutationError = true; return false }
        let succeeded = await performMutation(key: "review|\(application.id)", unknownMessage: "처리 결과를 확인하지 못했어요. 같은 신청을 다시 처리하지 않았어요.") {
            let result = try await service.decide(crewID: crewID, applicationID: application.id, approve: approve)
            guard self.accountScopeID == requestScopeID else { return }
            self.selectedApplication = result
            self.pendingApplications.removeAll { $0.id == result.id }
            self.mutationMessage = approve ? "가입 신청을 승인했어요." : "가입 신청을 거절했어요."
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func createPost(title: String, content: String) async -> Bool {
        guard let service, let crewID = selectedCrewID, let boardID = selectedBoardID, !isMutating, !isWriteBlocked("post|\(boardID)") else { return false }
        let requestScopeID = accountScopeID
        guard selectedCrew?.role != nil else { mutationMessage = "크루 멤버 권한을 확인할 수 없어요."; mutationError = true; return false }
        let succeeded = await performMutation(key: "post|\(boardID)", unknownMessage: "게시 결과를 확인하지 못했어요. 글을 다시 보내지 않았어요.") {
            let result = try await service.createPost(crewID: crewID, boardID: boardID, title: title, content: content)
            guard self.accountScopeID == requestScopeID else { return }
            self.posts.insert(result, at: 0)
            self.mutationMessage = "게시글을 등록했어요."
            self.showingPostComposer = false
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func clearMutationMessage() { mutationMessage = ""; mutationError = false }

    private func beginRead(_ key: String, state: WireframeCrewLoadState) -> UUID {
        let id = UUID(); readIDs[key] = id
        switch key {
        case "my-crews": myCrewsState = state
        case "recruitment": recruitmentState = state
        case "crew-detail": detailState = state
        case "boards": boardsState = state
        case "posts": postsState = state
        case "pending": pendingState = state
        default: break
        }
        return id
    }

    private func isCurrentRead(_ key: String, id: UUID) -> Bool { readIDs[key] == id }

    private func performMutation(key: String, unknownMessage: String, operation: () async throws -> Void) async -> Bool {
        guard !isMutating else { return false }
        let id = UUID(); mutationID = id; isMutating = true; mutationMessage = ""; mutationError = false
        defer { if mutationID == id { isMutating = false; mutationID = nil } }
        do { try await operation(); return true }
        catch {
            guard mutationID == id else { return false }
            if let failure = error as? CrewClientFailure {
                switch failure {
                case .applicationResultUnknown, .mutationResultUnknown:
                    writeBlockedKeys.insert(key)
                    mutationMessage = unknownMessage; mutationError = true
                case .forbidden:
                    mutationMessage = "이 작업을 처리할 권한이 없어요."; mutationError = true
                case .conflict:
                    mutationMessage = "상태가 바뀌었어요. 목록을 새로고침해 주세요."; mutationError = true
                default:
                    mutationMessage = message(for: error); mutationError = true
                }
            } else {
                mutationMessage = message(for: error); mutationError = true
            }
            return false
        }
    }

    private func message(for error: Error) -> String {
        guard let failure = error as? CrewClientFailure else { return "요청을 완료하지 못했어요. 연결 상태를 확인해 주세요." }
        return switch failure {
        case .accessTokenUnavailable, .unauthenticated: "로그인 후 다시 시도해 주세요."
        case .sessionChanged: "계정이 바뀌어 이전 계정의 결과를 표시하지 않았어요."
        case .forbidden: "이 화면을 볼 권한이 없어요."
        case .notFound: "크루나 게시글을 찾을 수 없어요."
        case .validationFailed: "입력 내용을 확인해 주세요."
        case .conflict: "상태가 바뀌었어요. 새로고침해 주세요."
        case .tooManyRequests(_): "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case .serviceUnavailable(_), .serverFailure(_), .transport(_): "연결이 불안정해요. 읽기 작업은 다시 시도할 수 있어요."
        case .applicationResultUnknown: "신청 결과를 확인하지 못했어요. 중복 신청을 막기 위해 다시 보내지 않았어요."
        case .mutationResultUnknown: "처리 결과를 확인하지 못했어요. 같은 요청을 자동으로 다시 보내지 않았어요."
        case .invalidRequest, .invalidResponse: "서버 응답을 확인하지 못했어요."
        case .cancelled: "요청을 취소했어요."
        }
    }
}

#if DEBUG
actor WireframeCrewServiceFixture: CrewServing {
    private let manager: Bool
    private let nonMember: Bool
    private var failMyCrewsOnce: Bool
    private let delayedWrites: Bool
    private var nextApplicationID = 601
    private var pendingApplications: [BackendCrewApplication]

    init(arguments: [String]) {
        manager = arguments.contains("-wire-crew-fixture-manager")
        nonMember = arguments.contains("-wire-crew-fixture-non-member")
        failMyCrewsOnce = arguments.contains("-wire-crew-fixture-fail-my-crews-once")
        delayedWrites = arguments.contains("-wire-crew-fixture-delay-writes")
        pendingApplications = [
            BackendCrewApplication(applicationId: "301", crewId: "101", memberId: "202", note: "주말에 함께 달리고 싶어요.", grade: nil, status: "PENDING", createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z"),
            BackendCrewApplication(applicationId: "302", crewId: "101", memberId: "203", note: nil, grade: nil, status: "PENDING", createdAt: "2026-10-17T11:00:00Z", updatedAt: "2026-10-17T11:00:00Z")
        ]
    }

    private func crew(role: String?) -> BackendCrew {
        BackendCrew(crewId: "101", name: "모브 새벽 크루", introduction: "아침을 여는 러너들이 함께 달려요.", joinGuide: "처음 오신 분도 편하게 인사해 주세요.", capacity: 20, memberCount: 3, status: "ACTIVE", role: role)
    }

    private func recruitmentPost() -> BackendCrewPost {
        BackendCrewPost(postId: "401", crewId: "101", crewName: "모브 새벽 크루", boardId: "502", boardName: "모집", boardKind: "RECRUITMENT", authorMemberId: "201", authorNickname: "크루장", title: "새벽 러닝 멤버 모집", content: "매주 토요일 아침에 함께 달려요.", createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z")
    }

    func fetchMyCrews() async throws -> [BackendCrew] {
        if failMyCrewsOnce {
            failMyCrewsOnce = false
            throw CrewClientFailure.serviceUnavailable(code: "TEMPORARY")
        }
        return nonMember ? [] : [crew(role: manager ? "OWNER" : "MEMBER")]
    }
    func fetchCrew(id: String) async throws -> BackendCrew {
        guard id == "101" else { throw CrewClientFailure.notFound }
        return crew(role: manager ? "OWNER" : nonMember ? nil : "MEMBER")
    }
    func fetchMembers(crewID: String) async throws -> [BackendCrewMember] { [] }
    func fetchRecruitmentPosts(cursor: String?, size: Int) async throws -> BackendCrewPage<BackendCrewPost> {
        BackendCrewPage(items: [recruitmentPost()], nextCursor: nil)
    }
    func apply(crewID: String, note: String?, grade: String?) async throws -> BackendCrewApplication {
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let id = String(nextApplicationID); nextApplicationID += 1
        let now = "2026-10-17T12:00:00Z"
        let application = BackendCrewApplication(applicationId: id, crewId: crewID, memberId: "204", note: note, grade: grade, status: "PENDING", createdAt: now, updatedAt: now)
        pendingApplications.append(application)
        return application
    }
    func fetchPendingApplications(crewID: String) async throws -> [BackendCrewApplication] {
        guard manager else { throw CrewClientFailure.forbidden }
        return pendingApplications.filter { $0.crewId == crewID && $0.status == "PENDING" }
    }
    func decide(crewID: String, applicationID: String, approve: Bool) async throws -> BackendCrewApplication {
        guard manager, let index = pendingApplications.firstIndex(where: { $0.id == applicationID }) else {
            if !manager { throw CrewClientFailure.forbidden }
            throw CrewClientFailure.notFound
        }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let old = pendingApplications[index]
        let result = BackendCrewApplication(applicationId: old.id, crewId: old.crewId, memberId: old.memberId, note: old.note, grade: old.grade, status: approve ? "APPROVED" : "REJECTED", createdAt: old.createdAt, updatedAt: "2026-10-17T12:00:00Z")
        pendingApplications[index] = result
        return result
    }
    func cancelApplication(crewID: String, applicationID: String) async throws {
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        pendingApplications.removeAll { $0.crewId == crewID && $0.id == applicationID }
    }
    func fetchBoards(crewID: String) async throws -> [BackendCrewBoard] {
        [BackendCrewBoard(boardId: "501", crewId: crewID, name: "러닝 일정", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z")]
    }
    func fetchPosts(crewID: String, boardID: String, cursor: String?, size: Int) async throws -> BackendCrewPage<BackendCrewPost> {
        let post = BackendCrewPost(postId: "601", crewId: crewID, crewName: "모브 새벽 크루", boardId: boardID, boardName: "러닝 일정", boardKind: "INTERNAL", authorMemberId: "202", authorNickname: "RunMate", title: "토요일 일정", content: "오전 8시에 만나요.", createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z")
        return BackendCrewPage(items: [post], nextCursor: nil)
    }
    func fetchPost(crewID: String, boardID: String, postID: String) async throws -> BackendCrewPost { try await fetchPosts(crewID: crewID, boardID: boardID, cursor: nil, size: 1).items[0] }
    func createPost(crewID: String, boardID: String, title: String, content: String) async throws -> BackendCrewPost {
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        return BackendCrewPost(postId: UUID().uuidString, crewId: crewID, crewName: "모브 새벽 크루", boardId: boardID, boardName: "러닝 일정", boardKind: "INTERNAL", authorMemberId: "202", authorNickname: "RunMate", title: title, content: content, createdAt: "2026-10-17T12:00:00Z", updatedAt: "2026-10-17T12:00:00Z")
    }
}
#endif
