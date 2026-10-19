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
    var membersState: WireframeCrewLoadState = .idle
    var restrictionsState: WireframeCrewLoadState = .idle
    var myCrews: [BackendCrew] = []
    var recruitmentPosts: [BackendCrewPost] = []
    var submittedApplications: [BackendCrewApplication] = []
    var pendingApplications: [BackendCrewApplication] = []
    var members: [BackendCrewMember] = []
    var rejoinRestrictions: [BackendCrewRejoinRestriction] = []
    var boards: [BackendCrewBoard] = []
    var posts: [BackendCrewPost] = []
    var selectedCrew: BackendCrew?
    var selectedCrewID: String?
    var selectedBoardID: String?
    var selectedApplication: BackendCrewApplication?
    var selectedMemberID: String?
    var selectedPost: BackendCrewPost?
    private(set) var viewerMemberID: String?
    var searchText = ""
    var postDraftTitle = ""
    var postDraftContent = ""
    var editingPostID: String?
    var showingPostComposer = false
    var boardDraftName = ""
    var boardDraftID: String?

    init(service: (any CrewServing)?) { self.service = service }

    var isAvailable: Bool { service != nil }
    var isManager: Bool { selectedCrew?.role == "OWNER" || selectedCrew?.role == "OPERATOR" }
    var selectedBoard: BackendCrewBoard? { boards.first { $0.boardId == selectedBoardID } }
    var canCreatePostOnSelectedBoard: Bool {
        selectedCrew?.role != nil && selectedBoard != nil && (selectedBoard?.kind != "RECRUITMENT" || isManager)
    }
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
        membersState = .idle; restrictionsState = .idle
        myCrews = []; recruitmentPosts = []; submittedApplications = []
        pendingApplications = []; members = []; rejoinRestrictions = []; boards = []; posts = []
        selectedCrew = nil; selectedCrewID = nil; selectedBoardID = nil
        selectedApplication = nil; selectedMemberID = nil; selectedPost = nil
        viewerMemberID = nil; editingPostID = nil; postDraftTitle = ""; postDraftContent = ""
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

    func loadMembers() async {
        guard let service, let crewID = selectedCrewID else { return }
        let requestID = beginRead("members", state: .loading)
        do {
            let value = try await service.fetchMembers(crewID: crewID)
            guard isCurrentRead("members", id: requestID), !Task.isCancelled else { return }
            members = value.sorted { lhs, rhs in
                let order = ["OWNER": 0, "OPERATOR": 1, "MEMBER": 2]
                if order[lhs.role, default: 3] != order[rhs.role, default: 3] {
                    return order[lhs.role, default: 3] < order[rhs.role, default: 3]
                }
                return Int64(lhs.memberId, radix: 10) ?? 0 < Int64(rhs.memberId, radix: 10) ?? 0
            }
            membersState = .loaded
        } catch {
            guard isCurrentRead("members", id: requestID), !Task.isCancelled else { return }
            membersState = .failed(message(for: error))
        }
    }

    func loadRejoinRestrictions() async {
        guard let service, let crewID = selectedCrewID, selectedCrew?.role == "OWNER" else {
            rejoinRestrictions = []; restrictionsState = .loaded; return
        }
        let requestID = beginRead("restrictions", state: .loading)
        do {
            let value = try await service.fetchRejoinRestrictions(crewID: crewID)
            guard isCurrentRead("restrictions", id: requestID), !Task.isCancelled else { return }
            rejoinRestrictions = value; restrictionsState = .loaded
        } catch {
            guard isCurrentRead("restrictions", id: requestID), !Task.isCancelled else { return }
            restrictionsState = .failed(message(for: error))
        }
    }

    func loadBoards() async {
        guard let service, let id = selectedCrewID else { return }
        let requestID = beginRead("boards", state: .loading)
        do {
            let value = try await service.fetchBoards(crewID: id)
            guard isCurrentRead("boards", id: requestID), !Task.isCancelled else { return }
            boards = value
            let active = value.filter { $0.status == "ACTIVE" }
            if !active.contains(where: { $0.boardId == selectedBoardID }) { selectedBoardID = active.first?.boardId }
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
            let memberID = try await service.currentMemberID()
            guard isCurrentRead("posts", id: requestID), !Task.isCancelled else { return }
            let page = try await service.fetchPosts(crewID: crewID, boardID: boardID, cursor: nil, size: 20)
            guard isCurrentRead("posts", id: requestID), !Task.isCancelled else { return }
            let currentMemberID = try await service.currentMemberID()
            guard isCurrentRead("posts", id: requestID), !Task.isCancelled else { return }
            guard currentMemberID == memberID else { throw CrewClientFailure.sessionChanged }
            viewerMemberID = memberID
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
        guard selectedBoard?.kind != "RECRUITMENT" || isManager else { mutationMessage = "모집 게시판에는 크루장·운영자만 글을 쓸 수 있어요."; mutationError = true; return false }
        let succeeded = await performMutation(key: "post|\(boardID)", unknownMessage: "게시 결과를 확인하지 못했어요. 글을 다시 보내지 않았어요.") {
            let result = try await service.createPost(crewID: crewID, boardID: boardID, title: title, content: content)
            guard self.accountScopeID == requestScopeID else { return }
            self.posts.insert(result, at: 0)
            self.mutationMessage = "게시글을 등록했어요."
            self.showingPostComposer = false
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func canEditPost(_ post: BackendCrewPost) -> Bool {
        guard let viewerMemberID else { return false }
        guard post.authorMemberId == viewerMemberID else { return false }
        return post.boardKind != "RECRUITMENT" || isManager
    }

    func canDeletePost(_ post: BackendCrewPost) -> Bool {
        (viewerMemberID != nil && post.authorMemberId == viewerMemberID) || isManager
    }

    func postUpdateWriteKey(for post: BackendCrewPost) -> String {
        "post-update|\(post.crewId)|\(post.boardId)|\(post.id)"
    }

    func postDeleteWriteKey(for post: BackendCrewPost) -> String {
        "post-delete|\(post.crewId)|\(post.boardId)|\(post.id)"
    }

    func beginPostEditing(_ post: BackendCrewPost) {
        guard canEditPost(post), selectedCrewID == post.crewId, selectedBoardID == post.boardId else { return }
        postDraftTitle = post.title
        postDraftContent = post.content
        editingPostID = post.id
        clearMutationMessage()
    }

    func postDraftIsDirty(for post: BackendCrewPost) -> Bool {
        editingPostID == post.id && (postDraftTitle != post.title || postDraftContent != post.content)
    }

    func cancelPostEditing() {
        editingPostID = nil
        postDraftTitle = ""
        postDraftContent = ""
        clearMutationMessage()
    }

    func closePostDetail() {
        selectedPost = nil
        editingPostID = nil
        postDraftTitle = ""
        postDraftContent = ""
    }

    func updatePost(_ post: BackendCrewPost, title: String, content: String) async -> Bool {
        guard let service, let crewID = selectedCrewID, let boardID = selectedBoardID,
              crewID == post.crewId, boardID == post.boardId, editingPostID == post.id,
              !isMutating else { return false }
        guard canEditPost(post) else {
            mutationMessage = "글 작성자만 게시글을 수정할 수 있어요."; mutationError = true
            return false
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 60,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.count <= 2_000 else {
            mutationMessage = "제목은 60자, 내용은 2,000자까지 입력해 주세요."; mutationError = true
            return false
        }
        let key = postUpdateWriteKey(for: post)
        guard !isWriteBlocked(key) else { return false }
        let scope = accountScopeID
        let succeeded = await performMutation(key: key, unknownMessage: "수정 결과를 확인하지 못했어요. 중복 수정을 막기 위해 다시 보내지 않았어요.") {
            let result = try await service.updatePost(crewID: crewID, boardID: boardID, postID: post.id, title: title, content: content)
            guard self.accountScopeID == scope,
                  self.selectedCrewID == crewID, self.selectedBoardID == boardID else { return }
            if let index = self.posts.firstIndex(where: { $0.id == post.id }) { self.posts[index] = result }
            if self.selectedPost?.id == post.id {
                self.selectedPost = result
                self.editingPostID = nil
                self.postDraftTitle = ""
                self.postDraftContent = ""
            }
            self.mutationMessage = "게시글을 수정했어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID && selectedBoardID == boardID
    }

    func deletePost(_ post: BackendCrewPost) async -> Bool {
        guard let service, let crewID = selectedCrewID, let boardID = selectedBoardID,
              crewID == post.crewId, boardID == post.boardId, selectedPost?.id == post.id,
              !isMutating else { return false }
        guard canDeletePost(post) else {
            mutationMessage = "글 작성자 또는 크루장·운영자만 삭제할 수 있어요."; mutationError = true
            return false
        }
        let key = postDeleteWriteKey(for: post)
        guard !isWriteBlocked(key) else { return false }
        let scope = accountScopeID
        let succeeded = await performMutation(key: key, unknownMessage: "삭제 결과를 확인하지 못했어요. 중복 삭제를 막기 위해 다시 보내지 않았어요.") {
            try await service.deletePost(crewID: crewID, boardID: boardID, postID: post.id)
            guard self.accountScopeID == scope,
                  self.selectedCrewID == crewID, self.selectedBoardID == boardID else { return }
            self.posts.removeAll { $0.id == post.id }
            if self.selectedPost?.id == post.id {
                self.selectedPost = nil
                self.editingPostID = nil
            }
            self.mutationMessage = "게시글을 삭제했어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID && selectedBoardID == boardID
    }

    func createCrew(name: String, introduction: String?, joinGuide: String?) async -> Bool {
        guard let service, !isMutating, !isWriteBlocked("create-crew") else { return false }
        let requestScopeID = accountScopeID
        let succeeded = await performMutation(key: "create-crew", unknownMessage: "크루 생성 결과를 확인하지 못했어요. 중복 생성을 막기 위해 다시 보내지 않았어요.") {
            let result = try await service.createCrew(name: name, introduction: introduction, joinGuide: joinGuide)
            guard self.accountScopeID == requestScopeID else { return }
            self.myCrews.removeAll { $0.id == result.id }
            self.myCrews.insert(result, at: 0)
            self.myCrewsState = .loaded
            self.selectedCrewID = result.id
            self.selectedCrew = result
            self.detailState = .loaded
            self.selectedBoardID = nil
            self.boards = []; self.members = []; self.posts = []
            self.mutationMessage = "크루를 만들었어요."
        }
        return succeeded && accountScopeID == requestScopeID
    }

    func beginBoardDraft(_ board: BackendCrewBoard? = nil) {
        boardDraftID = board?.id
        boardDraftName = board?.name ?? ""
        clearMutationMessage()
    }

    func saveBoardDraft() async -> Bool {
        guard let service, let crewID = selectedCrewID, isManager, !isMutating else { return false }
        let name = boardDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { mutationMessage = "게시판 이름을 입력해 주세요. 60자까지 적을 수 있어요."; mutationError = true; return false }
        let boardID = boardDraftID
        let scope = accountScopeID
        let key = boardID.map { "board-rename|\(crewID)|\($0)" } ?? "board-create|\(crewID)"
        let succeeded = await performMutation(key: key, unknownMessage: "게시판 변경 결과를 확인하지 못했어요. 중복 요청을 막기 위해 다시 보내지 않았어요.") {
            let result: BackendCrewBoard
            if let boardID { result = try await service.renameBoard(crewID: crewID, boardID: boardID, name: name) }
            else { result = try await service.createBoard(crewID: crewID, name: name, kind: "INTERNAL") }
            guard self.accountScopeID == scope, self.selectedCrewID == crewID else { return }
            self.replaceBoard(result)
            self.mutationMessage = boardID == nil ? "게시판을 추가했어요." : "게시판 이름을 저장했어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    func archiveBoard(_ board: BackendCrewBoard) async -> Bool {
        guard let service, let crewID = selectedCrewID, isManager, board.crewId == crewID,
              board.status == "ACTIVE", !isMutating else { return false }
        let scope = accountScopeID
        let key = "board-archive|\(crewID)|\(board.id)"
        let succeeded = await performMutation(key: key, unknownMessage: "게시판 보관 결과를 확인하지 못했어요. 중복 요청을 막기 위해 다시 보내지 않았어요.") {
            try await service.archiveBoard(crewID: crewID, boardID: board.id)
            guard self.accountScopeID == scope, self.selectedCrewID == crewID,
                  let index = self.boards.firstIndex(where: { $0.id == board.id }) else { return }
            self.boards[index] = BackendCrewBoard(boardId: board.id, crewId: board.crewId, name: board.name, kind: board.kind, status: "ARCHIVED", createdAt: board.createdAt)
            if self.selectedBoardID == board.id { self.selectedBoardID = self.boards.first(where: { $0.status == "ACTIVE" })?.id }
            self.posts = []; self.postsState = .idle
            self.mutationMessage = "게시판을 보관했어요. 기존 글은 보존돼요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    func restoreBoard(_ board: BackendCrewBoard) async -> Bool {
        guard let service, let crewID = selectedCrewID, isManager, board.crewId == crewID,
              board.status == "ARCHIVED", !isMutating else { return false }
        let scope = accountScopeID
        let key = "board-restore|\(crewID)|\(board.id)"
        let succeeded = await performMutation(key: key, unknownMessage: "게시판 복원 결과를 확인하지 못했어요. 중복 요청을 막기 위해 다시 보내지 않았어요.") {
            let result = try await service.restoreBoard(crewID: crewID, boardID: board.id)
            guard self.accountScopeID == scope, self.selectedCrewID == crewID else { return }
            self.replaceBoard(result)
            self.mutationMessage = "게시판을 복원했어요. 작성글도 다시 볼 수 있어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    func canChangeRole(of member: BackendCrewMember) -> Bool {
        selectedCrew?.role == "OWNER" && member.role != "OWNER"
    }

    func canRemove(_ member: BackendCrewMember) -> Bool {
        guard member.role != "OWNER" else { return false }
        if selectedCrew?.role == "OWNER" { return true }
        return selectedCrew?.role == "OPERATOR" && member.role == "MEMBER"
    }

    func changeRole(of member: BackendCrewMember) async -> Bool {
        guard let service, let crewID = selectedCrewID, canChangeRole(of: member), !isMutating else { return false }
        let newRole = member.role == "OPERATOR" ? "MEMBER" : "OPERATOR"
        let scope = accountScopeID
        let key = "member-role|\(crewID)|\(member.id)"
        let succeeded = await performMutation(key: key, unknownMessage: "권한 변경 결과를 확인하지 못했어요. 중복 요청을 막기 위해 다시 보내지 않았어요.") {
            try await service.updateMemberRole(crewID: crewID, memberID: member.id, role: newRole)
            guard self.accountScopeID == scope, self.selectedCrewID == crewID,
                  let index = self.members.firstIndex(where: { $0.id == member.id }) else { return }
            self.members[index] = BackendCrewMember(memberId: member.id, role: newRole, joinedAt: member.joinedAt)
            self.mutationMessage = newRole == "OPERATOR" ? "운영자로 지정했어요." : "운영자 권한을 해제했어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    func removeMember(_ member: BackendCrewMember) async -> Bool {
        guard let service, let crewID = selectedCrewID, canRemove(member), !isMutating else { return false }
        let scope = accountScopeID
        let key = "member-remove|\(crewID)|\(member.id)"
        let succeeded = await performMutation(key: key, unknownMessage: "멤버 내보내기 결과를 확인하지 못했어요. 중복 요청을 막기 위해 다시 보내지 않았어요.") {
            try await service.removeMember(crewID: crewID, memberID: member.id)
            guard self.accountScopeID == scope, self.selectedCrewID == crewID else { return }
            self.members.removeAll { $0.id == member.id }
            if let crew = self.selectedCrew {
                self.selectedCrew = BackendCrew(crewId: crew.id, name: crew.name, introduction: crew.introduction, joinGuide: crew.joinGuide, capacity: crew.capacity, memberCount: max(0, crew.memberCount - 1), status: crew.status, role: crew.role)
            }
            self.mutationMessage = "멤버를 내보냈어요."
        }
        if succeeded && accountScopeID == scope { await loadRejoinRestrictions() }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    func releaseRejoinRestriction(for restriction: BackendCrewRejoinRestriction) async -> Bool {
        guard let service, let crewID = selectedCrewID, selectedCrew?.role == "OWNER", !isMutating else { return false }
        let scope = accountScopeID
        let key = "restriction-release|\(crewID)|\(restriction.memberId)"
        let succeeded = await performMutation(key: key, unknownMessage: "재가입 제한 해제 결과를 확인하지 못했어요. 같은 요청을 자동으로 다시 보내지 않았어요.") {
            try await service.releaseRejoinRestriction(crewID: crewID, memberID: restriction.memberId)
            guard self.accountScopeID == scope, self.selectedCrewID == crewID else { return }
            self.rejoinRestrictions.removeAll { $0.id == restriction.id }
            self.mutationMessage = "재가입 제한을 해제했어요."
        }
        return succeeded && accountScopeID == scope && selectedCrewID == crewID
    }

    private func replaceBoard(_ board: BackendCrewBoard) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) { boards[index] = board }
        else { boards.append(board) }
        if board.status == "ACTIVE", selectedBoardID == nil { selectedBoardID = board.id }
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
        case "members": membersState = state
        case "restrictions": restrictionsState = state
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
    private let operatorRole: Bool
    private let nonMember: Bool
    private var failMyCrewsOnce: Bool
    private let delayedWrites: Bool
    private let delayedPostWrites: Bool
    private let accountSwitchDuringRead: Bool
    private let postAuthorOther: Bool
    private var failPostUpdateOnce: Bool
    private var failPostDeleteOnce: Bool
    private var myCrewsReadCount = 0
    private var nextApplicationID = 601
    private var nextCrewID = 102
    private var nextBoardID = 504
    private var nextPostID = 602
    private var pendingApplications: [BackendCrewApplication]
    private var posts: [BackendCrewPost] = []
    private var members = [
        BackendCrewMember(memberId: "201", role: "OWNER", joinedAt: "2026-10-01T09:00:00Z"),
        BackendCrewMember(memberId: "202", role: "MEMBER", joinedAt: "2026-10-02T09:00:00Z"),
        BackendCrewMember(memberId: "203", role: "MEMBER", joinedAt: "2026-10-03T09:00:00Z")
    ]
    private var boards: [BackendCrewBoard] = [
        BackendCrewBoard(boardId: "501", crewId: "101", name: "러닝 일정", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
        BackendCrewBoard(boardId: "502", crewId: "101", name: "모집", kind: "RECRUITMENT", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
        BackendCrewBoard(boardId: "503", crewId: "101", name: "지난 기록", kind: "INTERNAL", status: "ARCHIVED", createdAt: "2026-10-17T10:00:00Z")
    ]
    private var restrictions: [BackendCrewRejoinRestriction] = []
    private var createdCrews: [BackendCrew] = []
    private var fillBoardCapacity = false

    init(arguments: [String]) {
        manager = arguments.contains("-wire-crew-fixture-manager")
        operatorRole = arguments.contains("-wire-crew-fixture-operator")
        nonMember = arguments.contains("-wire-crew-fixture-non-member")
        failMyCrewsOnce = arguments.contains("-wire-crew-fixture-fail-my-crews-once")
        delayedWrites = arguments.contains("-wire-crew-fixture-delay-writes")
        delayedPostWrites = arguments.contains("-wire-crew-fixture-delay-post-writes")
        accountSwitchDuringRead = arguments.contains("-wire-crew-fixture-account-switch-during-read")
        postAuthorOther = arguments.contains("-wire-crew-fixture-post-author-other")
        failPostUpdateOnce = arguments.contains("-wire-crew-fixture-fail-post-update-once")
        failPostDeleteOnce = arguments.contains("-wire-crew-fixture-fail-post-delete-once")
        fillBoardCapacity = arguments.contains("-wire-crew-fixture-full-boards")
        pendingApplications = [
            BackendCrewApplication(applicationId: "301", crewId: "101", memberId: "202", note: "주말에 함께 달리고 싶어요.", grade: nil, status: "PENDING", createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z"),
            BackendCrewApplication(applicationId: "302", crewId: "101", memberId: "203", note: nil, grade: nil, status: "PENDING", createdAt: "2026-10-17T11:00:00Z", updatedAt: "2026-10-17T11:00:00Z")
        ]
        if fillBoardCapacity {
            boards = [
                BackendCrewBoard(boardId: "501", crewId: "101", name: "러닝 일정", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
                BackendCrewBoard(boardId: "502", crewId: "101", name: "모집", kind: "RECRUITMENT", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
                BackendCrewBoard(boardId: "504", crewId: "101", name: "토요 달리기", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
                BackendCrewBoard(boardId: "505", crewId: "101", name: "기록 나눔", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
                BackendCrewBoard(boardId: "506", crewId: "101", name: "자유 게시판", kind: "INTERNAL", status: "ACTIVE", createdAt: "2026-10-17T10:00:00Z"),
                BackendCrewBoard(boardId: "503", crewId: "101", name: "지난 기록", kind: "INTERNAL", status: "ARCHIVED", createdAt: "2026-10-17T10:00:00Z")
            ]
            nextBoardID = 507
        }
    }

    private func crew(role: String?, id: String = "101", name: String = "모브 새벽 크루", memberCount: Int = 3) -> BackendCrew {
        BackendCrew(crewId: id, name: name, introduction: "아침을 여는 러너들이 함께 달려요.", joinGuide: "처음 오신 분도 편하게 인사해 주세요.", capacity: 20, memberCount: memberCount, status: "ACTIVE", role: role)
    }

    private var currentRole: String? { manager ? "OWNER" : operatorRole ? "OPERATOR" : nonMember ? nil : "MEMBER" }
    private var currentMemberIDValue: String? { currentRole == nil ? nil : manager ? "201" : "202" }

    private func defaultPost(crewID: String, boardID: String) -> BackendCrewPost {
        let board = boards.first { $0.id == boardID && $0.crewId == crewID }
        return BackendCrewPost(postId: "601", crewId: crewID, crewName: "모브 새벽 크루", boardId: boardID,
            boardName: board?.name ?? "러닝 일정", boardKind: board?.kind ?? "INTERNAL",
            authorMemberId: postAuthorOther ? "203" : "202", authorNickname: postAuthorOther ? "PaceSetter" : "RunMate", title: "토요일 일정", content: "오전 8시에 만나요.",
            createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z")
    }

    func createCrew(name: String, introduction: String?, joinGuide: String?) async throws -> BackendCrew {
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let id = String(nextCrewID); nextCrewID += 1
        let created = BackendCrew(crewId: id, name: name, introduction: introduction, joinGuide: joinGuide, capacity: 20, memberCount: 1, status: "ACTIVE", role: "OWNER")
        createdCrews.append(created)
        return created
    }

    private func recruitmentPost() -> BackendCrewPost {
        BackendCrewPost(postId: "401", crewId: "101", crewName: "모브 새벽 크루", boardId: "502", boardName: "모집", boardKind: "RECRUITMENT", authorMemberId: "201", authorNickname: "크루장", title: "새벽 러닝 멤버 모집", content: "매주 토요일 아침에 함께 달려요.", createdAt: "2026-10-17T10:00:00Z", updatedAt: "2026-10-17T10:00:00Z")
    }

    func fetchMyCrews() async throws -> [BackendCrew] {
        myCrewsReadCount += 1
        if accountSwitchDuringRead && myCrewsReadCount == 1 {
            await Task.detached { try? await Task.sleep(for: .seconds(10)) }.value
            return [crew(role: "OWNER", name: "계정 A 전용 크루")]
        }
        if accountSwitchDuringRead { return [crew(role: "OWNER", name: "계정 B 전용 크루")] }
        if failMyCrewsOnce {
            failMyCrewsOnce = false
            throw CrewClientFailure.serviceUnavailable(code: "TEMPORARY")
        }
        return nonMember ? [] : [crew(role: currentRole)] + createdCrews
    }
    func fetchCrew(id: String) async throws -> BackendCrew {
        if let created = createdCrews.first(where: { $0.id == id }) { return created }
        guard id == "101" else { throw CrewClientFailure.notFound }
        return crew(role: currentRole)
    }
    func fetchMembers(crewID: String) async throws -> [BackendCrewMember] { members }
    func updateMemberRole(crewID: String, memberID: String, role: String) async throws {
        guard manager, let index = members.firstIndex(where: { $0.id == memberID }), members[index].role != "OWNER" else { throw CrewClientFailure.forbidden }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        members[index] = BackendCrewMember(memberId: memberID, role: role, joinedAt: members[index].joinedAt)
    }
    func removeMember(crewID: String, memberID: String) async throws {
        guard let index = members.firstIndex(where: { $0.id == memberID }), members[index].role != "OWNER",
              manager || (operatorRole && members[index].role == "MEMBER") else { throw CrewClientFailure.forbidden }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        members.remove(at: index)
        restrictions.removeAll { $0.memberId == memberID }
        restrictions.append(BackendCrewRejoinRestriction(memberId: memberID, createdAt: "2026-10-17T12:00:00Z"))
    }
    func fetchRejoinRestrictions(crewID: String) async throws -> [BackendCrewRejoinRestriction] {
        guard manager else { throw CrewClientFailure.forbidden }
        return restrictions
    }
    func releaseRejoinRestriction(crewID: String, memberID: String) async throws {
        guard manager else { throw CrewClientFailure.forbidden }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        restrictions.removeAll { $0.memberId == memberID }
    }
    func transferOwnership(crewID: String, memberID: String) async throws {
        guard manager, members.contains(where: { $0.id == memberID && $0.role != "OWNER" }) else { throw CrewClientFailure.forbidden }
        members = members.map { member in
            BackendCrewMember(memberId: member.id, role: member.id == memberID ? "OWNER" : member.id == "201" ? "OPERATOR" : member.role, joinedAt: member.joinedAt)
        }
    }
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
        guard manager || operatorRole else { throw CrewClientFailure.forbidden }
        return pendingApplications.filter { $0.crewId == crewID && $0.status == "PENDING" }
    }
    func decide(crewID: String, applicationID: String, approve: Bool) async throws -> BackendCrewApplication {
        guard manager || operatorRole, let index = pendingApplications.firstIndex(where: { $0.id == applicationID }) else {
            if !manager && !operatorRole { throw CrewClientFailure.forbidden }
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
        guard !nonMember else { throw CrewClientFailure.forbidden }
        return boards.filter { $0.crewId == crewID && (currentRole == "OWNER" || currentRole == "OPERATOR" || $0.status == "ACTIVE") }
    }
    func createBoard(crewID: String, name: String, kind: String) async throws -> BackendCrewBoard {
        guard manager || operatorRole else { throw CrewClientFailure.forbidden }
        guard boards.filter({ $0.status == "ACTIVE" }).count < 5 else { throw CrewClientFailure.validationFailed }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let board = BackendCrewBoard(boardId: String(nextBoardID), crewId: crewID, name: name, kind: kind, status: "ACTIVE", createdAt: "2026-10-17T12:00:00Z")
        nextBoardID += 1; boards.append(board); return board
    }
    func renameBoard(crewID: String, boardID: String, name: String) async throws -> BackendCrewBoard {
        guard manager || operatorRole, let index = boards.firstIndex(where: { $0.id == boardID && $0.crewId == crewID && $0.status == "ACTIVE" }) else { throw CrewClientFailure.forbidden }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let old = boards[index]
        let board = BackendCrewBoard(boardId: old.id, crewId: old.crewId, name: name, kind: old.kind, status: old.status, createdAt: old.createdAt)
        boards[index] = board; return board
    }
    func archiveBoard(crewID: String, boardID: String) async throws {
        guard manager || operatorRole, let index = boards.firstIndex(where: { $0.id == boardID && $0.crewId == crewID }) else { throw CrewClientFailure.forbidden }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let old = boards[index]
        boards[index] = BackendCrewBoard(boardId: old.id, crewId: old.crewId, name: old.name, kind: old.kind, status: "ARCHIVED", createdAt: old.createdAt)
    }
    func restoreBoard(crewID: String, boardID: String) async throws -> BackendCrewBoard {
        guard manager || operatorRole, let index = boards.firstIndex(where: { $0.id == boardID && $0.crewId == crewID && $0.status == "ARCHIVED" }) else { throw CrewClientFailure.forbidden }
        guard boards.filter({ $0.status == "ACTIVE" }).count < 5 else { throw CrewClientFailure.validationFailed }
        if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let old = boards[index]
        let board = BackendCrewBoard(boardId: old.id, crewId: old.crewId, name: old.name, kind: old.kind, status: "ACTIVE", createdAt: old.createdAt)
        boards[index] = board; return board
    }
    func fetchPosts(crewID: String, boardID: String, cursor: String?, size: Int) async throws -> BackendCrewPage<BackendCrewPost> {
        guard !nonMember else { throw CrewClientFailure.forbidden }
        if !posts.contains(where: { $0.crewId == crewID && $0.boardId == boardID }) {
            posts.append(defaultPost(crewID: crewID, boardID: boardID))
        }
        return BackendCrewPage(items: posts.filter { $0.crewId == crewID && $0.boardId == boardID }, nextCursor: nil)
    }

    func fetchPost(crewID: String, boardID: String, postID: String) async throws -> BackendCrewPost {
        _ = try await fetchPosts(crewID: crewID, boardID: boardID, cursor: nil, size: 20)
        guard let post = posts.first(where: { $0.id == postID && $0.crewId == crewID && $0.boardId == boardID }) else {
            throw CrewClientFailure.notFound
        }
        return post
    }

    func currentMemberID() async throws -> String {
        guard let currentMemberIDValue else { throw CrewClientFailure.accessTokenUnavailable }
        return currentMemberIDValue
    }

    func createPost(crewID: String, boardID: String, title: String, content: String) async throws -> BackendCrewPost {
        guard let memberID = currentMemberIDValue,
              let board = boards.first(where: { $0.id == boardID && $0.crewId == crewID && $0.status == "ACTIVE" }) else {
            throw CrewClientFailure.notFound
        }
        if board.kind == "RECRUITMENT" && !manager && !operatorRole { throw CrewClientFailure.forbidden }
        if delayedPostWrites { try await Task.sleep(for: .milliseconds(6500)) }
        else if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let post = BackendCrewPost(postId: String(nextPostID), crewId: crewID, crewName: "모브 새벽 크루", boardId: boardID,
            boardName: board.name, boardKind: board.kind, authorMemberId: memberID,
            authorNickname: manager ? "크루장" : "RunMate", title: title, content: content,
            createdAt: "2026-10-17T12:00:00Z", updatedAt: "2026-10-17T12:00:00Z")
        nextPostID += 1
        posts.insert(post, at: 0)
        return post
    }

    func updatePost(crewID: String, boardID: String, postID: String, title: String, content: String) async throws -> BackendCrewPost {
        guard let memberID = currentMemberIDValue,
              let board = boards.first(where: { $0.id == boardID && $0.crewId == crewID && $0.status == "ACTIVE" }),
              let index = posts.firstIndex(where: { $0.id == postID && $0.crewId == crewID && $0.boardId == boardID }) else {
            throw CrewClientFailure.notFound
        }
        if board.kind == "RECRUITMENT" && !manager && !operatorRole { throw CrewClientFailure.forbidden }
        guard posts[index].authorMemberId == memberID else { throw CrewClientFailure.forbidden }
        if failPostUpdateOnce {
            failPostUpdateOnce = false
            throw CrewClientFailure.conflict(code: "POST_CHANGED")
        }
        if delayedPostWrites { try await Task.sleep(for: .milliseconds(6500)) }
        else if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        let old = posts[index]
        let updated = BackendCrewPost(postId: old.id, crewId: old.crewId, crewName: old.crewName, boardId: old.boardId,
            boardName: old.boardName, boardKind: old.boardKind, authorMemberId: old.authorMemberId,
            authorNickname: old.authorNickname, title: title, content: content, createdAt: old.createdAt,
            updatedAt: "2026-10-17T12:00:00Z")
        posts[index] = updated
        return updated
    }

    func deletePost(crewID: String, boardID: String, postID: String) async throws {
        guard let memberID = currentMemberIDValue,
              boards.contains(where: { $0.id == boardID && $0.crewId == crewID && $0.status == "ACTIVE" }),
              let index = posts.firstIndex(where: { $0.id == postID && $0.crewId == crewID && $0.boardId == boardID }) else {
            throw CrewClientFailure.notFound
        }
        guard posts[index].authorMemberId == memberID || manager || operatorRole else { throw CrewClientFailure.forbidden }
        if failPostDeleteOnce {
            failPostDeleteOnce = false
            throw CrewClientFailure.conflict(code: "POST_CHANGED")
        }
        if delayedPostWrites { try await Task.sleep(for: .milliseconds(6500)) }
        else if delayedWrites { try await Task.sleep(for: .milliseconds(1100)) }
        posts.remove(at: index)
    }
}
#endif
