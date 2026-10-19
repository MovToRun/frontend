import SwiftUI
import Observation

@MainActor @Observable final class WireframeCommunityCourseFlow {
    let service: (any CommunityCourseServing)?
    private(set) var accountScopeID: String?
    private(set) var application: CommunityCertificationApplication?
    private(set) var operatorQueue: [CommunityCertificationApplication] = []
    private(set) var operatorQueueNextCursor: String?
    private(set) var operatorApplication: CommunityCertificationApplication?
    private(set) var coursePage: BackendCommunityCoursePage?
    private(set) var course: BackendCommunityCourse?
    private(set) var followSession: BackendCourseFollowSession?
    private(set) var followClientRunID: UUID?
    private(set) var comparison: BackendCourseFollowComparison?
    private(set) var busy = false
    private(set) var courseLoading = false
    private(set) var lastProgress: (meters: Int64, seconds: Int64)?
    var applicationReason = ""
    var evidenceURLs = ""
    var operatorDecisionReason = ""
    var courseRunID = ""
    var courseStartMask = "300"
    var courseEndMask = "300"
    var publicConsent = false
    var draftCourseID: String?
    var draftStartMaskMeters: Int64?
    var draftEndMaskMeters: Int64?
    var draftCreateResultUnknown = false
    var errorMessage = ""
    var noticeMessage = ""
    var operatorAccessDenied = false
    var certificationLoading = false
    var operatorLoading = false
    var courseListLoading = false
    var verified: Bool { application?.status == .approved }
    var isAvailable: Bool { service != nil }
    var canContinueFollowing: Bool {
        guard let followSession, followSession.courseAvailable != false else { return false }
        return course?.routeVersion == followSession.routeVersion
    }

    func canBeginFollowing(course: BackendCommunityCourse, runStore: RunStore) -> Bool {
        guard let memberID = runStore.authenticatedUploadMemberID else { return false }
        guard let current = runStore.session else { return true }
        let key = Self.followKey(memberID: memberID, courseID: course.courseId, routeVersion: course.routeVersion)
        return pendingFollowKeys[key]?.runID == current.clientRunID
    }

    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var consumedCourseCursor: String?
    @ObservationIgnored private var pendingFollowKeys: [String: PendingFollowKey] = [:]
    @ObservationIgnored private var unknownDraftAttemptKeys: Set<String> = []

    init(service: (any CommunityCourseServing)?) {
        self.service = service
        self.pendingFollowKeys = Self.loadPendingFollowKeys()
        self.unknownDraftAttemptKeys = Self.loadUnknownDraftAttemptKeys()
    }

    func setAccountScope(_ value: String) {
        guard accountScopeID != value else { return }
        generation &+= 1
        operationID = nil
        accountScopeID = value
        application = nil
        operatorQueue = []
        operatorQueueNextCursor = nil
        operatorApplication = nil
        coursePage = nil
        course = nil
        followSession = nil
        followClientRunID = nil
        comparison = nil
        draftCourseID = nil
        draftStartMaskMeters = nil
        draftEndMaskMeters = nil
        draftCreateResultUnknown = false
        applicationReason = ""
        evidenceURLs = ""
        operatorDecisionReason = ""
        courseRunID = ""
        courseStartMask = "300"
        courseEndMask = "300"
        publicConsent = false
        lastProgress = nil
        errorMessage = ""
        noticeMessage = ""
        operatorAccessDenied = false
        busy = false
        certificationLoading = false
        operatorLoading = false
        courseLoading = false
        courseListLoading = false
        consumedCourseCursor = nil
        pendingFollowKeys = Self.loadPendingFollowKeys()
        unknownDraftAttemptKeys = Self.loadUnknownDraftAttemptKeys()
    }

    func loadCertification() async {
        guard let service, !certificationLoading else { return }
        let ticket = generation
        certificationLoading = true
        errorMessage = ""
        defer { if generation == ticket { certificationLoading = false } }
        do {
            let result = try await service.fetchMyCertification()
            guard generation == ticket else { return }
            application = result
            if let result { applicationReason = result.applicationReason ?? applicationReason }
        } catch {
            guard generation == ticket else { return }
            errorMessage = message(for: error)
        }
    }

    func submitCertification() async {
        guard let service, !busy else { return }
        let reason = applicationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = evidenceURLs.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard (1...300).contains(reason.count), (1...5).contains(evidence.count), evidence.allSatisfy(Self.isPublicHTTPSURL) else {
            errorMessage = "활동 소개와 HTTPS 확인 자료 1~5개를 입력해 주세요."
            return
        }
        let ticket = beginOperation()
        do {
            let result = try await service.submitCertification(reason: reason, evidenceURLs: evidence)
            finishOperation(ticket)
            guard generation == ticket.generation else { return }
            application = result
            noticeMessage = "인증 신청을 접수했어요. 검토 결과를 기다려 주세요."
        } catch {
            guard generation == ticket.generation else { return }
            if case CommunityCourseFailure.conflict = error {
                await refreshCertification(after: ticket.generation, fallback: error)
            } else if case CommunityCourseFailure.resultUnknown = error {
                await refreshCertification(after: ticket.generation, fallback: error)
            } else if case CommunityCourseFailure.transport = error {
                await refreshCertification(after: ticket.generation, fallback: error)
            } else {
                finishOperation(ticket)
                errorMessage = message(for: error)
            }
        }
    }

    func withdrawCertification() async {
        guard let service, !busy, application?.status == .pending else { return }
        let ticket = beginOperation()
        do {
            try await service.withdrawCertification()
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            application = nil
            noticeMessage = "대기 중인 신청을 철회했어요. 확인 자료도 서버에서 삭제됐어요."
        } catch {
            guard generation == ticket.generation else { return }
            if case CommunityCourseFailure.resultUnknown = error {
                await refreshCertification(after: ticket.generation, fallback: error, missingMeansWithdrawn: true)
            } else if case CommunityCourseFailure.transport = error {
                await refreshCertification(after: ticket.generation, fallback: error, missingMeansWithdrawn: true)
            } else {
                finishOperation(ticket)
                errorMessage = message(for: error)
            }
        }
    }

    func loadOperatorQueue(loadMore: Bool = false) async {
        guard let service, !operatorLoading else { return }
        if loadMore, operatorQueueNextCursor == nil { return }
        let ticket = generation
        operatorLoading = true
        errorMessage = ""
        operatorAccessDenied = false
        let requestedCursor = loadMore ? operatorQueueNextCursor : nil
        defer { if generation == ticket { operatorLoading = false } }
        do {
            let page = try await service.fetchOperatorQueue(cursor: requestedCursor, size: 20)
            guard generation == ticket else { return }
            if loadMore {
                let known = Set(operatorQueue.map(\.applicationId))
                operatorQueue += page.items.filter { !known.contains($0.applicationId) }
            } else { operatorQueue = page.items }
            operatorQueueNextCursor = page.nextCursor == requestedCursor ? nil : page.nextCursor
        } catch {
            guard generation == ticket else { return }
            if case CommunityCourseFailure.forbidden = error { operatorAccessDenied = true }
            errorMessage = message(for: error)
        }
    }

    func openOperatorApplication(id: String) async {
        guard let service, !busy else { return }
        let ticket = beginOperation()
        do {
            let value = try await service.fetchOperatorApplication(id: id)
            finishOperation(ticket)
            guard generation == ticket.generation else { return }
            operatorApplication = value
            operatorDecisionReason = ""
            errorMessage = ""
        } catch {
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            if case CommunityCourseFailure.forbidden = error { operatorAccessDenied = true }
            errorMessage = message(for: error)
        }
    }

    func decideOperatorApplication(action: String) async {
        guard let service, !busy, let selected = operatorApplication, selected.status == .pending else { return }
        let reason = operatorDecisionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...300).contains(reason.count) else { errorMessage = "검토 사유를 1~300자로 입력해 주세요."; return }
        let ticket = beginOperation()
        do {
            let value = try await service.decideOperatorApplication(id: selected.applicationId, action: action, reason: reason)
            finishOperation(ticket)
            guard generation == ticket.generation else { return }
            operatorApplication = value
            operatorQueue.removeAll { $0.applicationId == value.applicationId }
            noticeMessage = action == "APPROVE" ? "인증을 승인했어요." : "인증 신청을 거부했어요."
            errorMessage = ""
        } catch {
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            errorMessage = message(for: error)
        }
    }

    func loadCourses(loadMore: Bool = false) async {
        guard let service, !courseListLoading else { return }
        if loadMore, consumedCourseCursor == nil { return }
        let ticket = generation
        courseListLoading = true
        errorMessage = ""
        defer { if generation == ticket { courseListLoading = false } }
        do {
            let page = try await service.listCourses(cursor: loadMore ? consumedCourseCursor : nil, size: 20)
            guard generation == ticket else { return }
            if loadMore, let previous = coursePage {
                coursePage = BackendCommunityCoursePage(items: previous.items + page.items, nextCursor: page.nextCursor)
            } else { coursePage = page }
            consumedCourseCursor = page.nextCursor
        } catch {
            guard generation == ticket else { return }
            errorMessage = message(for: error)
        }
    }

    func openCourse(id: String) async {
        guard let service, !courseLoading else { return }
        let ticket = generation
        courseLoading = true
        errorMessage = ""
        defer { if generation == ticket { courseLoading = false } }
        do {
            let value = try await service.fetchCourse(id: id)
            guard generation == ticket else { return }
            course = value
            followSession = nil
            comparison = nil
        } catch {
            guard generation == ticket else { return }
            course = nil
            errorMessage = message(for: error)
        }
    }

    func clearSelectedCourse() { course = nil; followSession = nil; comparison = nil; lastProgress = nil }

    func restoreDraftCreateUnknown(memberID: String?) {
        guard let memberID, let runID = Int64(courseRunID), runID > 0 else {
            draftCreateResultUnknown = false
            return
        }
        draftCreateResultUnknown = unknownDraftAttemptKeys.contains(Self.unknownDraftKey(memberID: memberID, runID: runID))
    }

    func createCourseDraftAndPublish(memberID: String?) async {
        guard let service, !busy else { return }
        course = nil
        noticeMessage = ""
        errorMessage = ""
        guard verified else { errorMessage = "운영자의 인증 승인을 받은 뒤 코스를 공유할 수 있어요."; return }
        guard let runID = Int64(courseRunID), runID > 0,
              let start = Int64(courseStartMask), start >= 0,
              let end = Int64(courseEndMask), end >= 0 else {
            errorMessage = "유효한 서버 러닝 기록과 0 이상의 시작·끝 숨김 거리를 선택해 주세요."
            return
        }
        guard let memberID, !memberID.isEmpty else {
            errorMessage = "로그인한 회원과 유효 서버 러닝 기록이 필요해요."
            return
        }
        if let draftCourseID {
            guard publicConsent else { errorMessage = "코스 공개에 동의해야 게시할 수 있어요."; return }
            await publishDraft(id: draftCourseID)
            return
        }
        let unknownKey = Self.unknownDraftKey(memberID: memberID, runID: runID)
        guard !unknownDraftAttemptKeys.contains(unknownKey) else {
            draftCreateResultUnknown = true
            errorMessage = "초안 생성 결과가 불명확해요. 중복 방지를 위해 같은 기록으로 다시 요청하지 않았어요."
            return
        }
        guard !draftCreateResultUnknown else {
            errorMessage = "비공개 초안 생성 결과를 확인할 수 없어요. 중복 초안 방지를 위해 새 요청은 보내지 않았어요."
            return
        }
        let ticket = beginOperation()
        do {
            let draft = try await service.createCourseDraft(runID: runID, startMaskMeters: start, endMaskMeters: end)
            guard generation == ticket.generation else { return }
            draftCourseID = draft.courseId
            draftStartMaskMeters = draft.startMaskMeters
            draftEndMaskMeters = draft.endMaskMeters
            finishOperation(ticket)
            noticeMessage = "비공개 초안을 준비했어요. 숨길 거리를 확인하고 게시를 선택해 주세요."
        } catch {
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            if case CommunityCourseFailure.resultUnknown = error {
                unknownDraftAttemptKeys.insert(unknownKey)
                Self.saveUnknownDraftAttemptKeys(unknownDraftAttemptKeys)
                draftCreateResultUnknown = true
            }
            if case CommunityCourseFailure.transport = error {
                unknownDraftAttemptKeys.insert(unknownKey)
                Self.saveUnknownDraftAttemptKeys(unknownDraftAttemptKeys)
                draftCreateResultUnknown = true
            }
            errorMessage = message(for: error)
        }
    }

    private func publishDraft(id: String, existingTicket: OperationTicket? = nil) async {
        guard let service else { return }
        let ticket = existingTicket ?? beginOperation()
        do {
            guard let start = Int64(courseStartMask), start >= 0,
                  let end = Int64(courseEndMask), end >= 0 else { throw CommunityCourseFailure.invalidRequest }
            if start != draftStartMaskMeters || end != draftEndMaskMeters {
                let updated = try await service.adjustCourseDraft(id: id, startMaskMeters: start, endMaskMeters: end)
                guard generation == ticket.generation else { return }
                draftStartMaskMeters = updated.startMaskMeters
                draftEndMaskMeters = updated.endMaskMeters
            }
            let value = try await service.publishCourse(id: id)
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            course = value
            draftCourseID = nil
            draftStartMaskMeters = nil
            draftEndMaskMeters = nil
            draftCreateResultUnknown = false
            noticeMessage = "시작·끝 위치를 가린 코스를 공개했어요."
            errorMessage = ""
        } catch {
            guard generation == ticket.generation else { return }
            if case CommunityCourseFailure.resultUnknown = error {
                do {
                    let recovered = try await service.fetchCourse(id: id)
                    guard generation == ticket.generation else { return }
                    finishOperation(ticket)
                    course = recovered
                    draftCourseID = nil
                    draftStartMaskMeters = nil
                    draftEndMaskMeters = nil
                    noticeMessage = "코스가 공개된 상태를 다시 확인했어요."
                    errorMessage = ""
                    return
                } catch { /* keep the known draft ID for a safe retry */ }
            }
            finishOperation(ticket)
            errorMessage = message(for: error)
        }
    }

    func beginFollowing(course: BackendCommunityCourse, runStore: RunStore, weight: Double?, routeIsCurrent: () -> Bool = { true }) async -> Bool {
        guard let service, !busy else { return false }
        guard canBeginFollowing(course: course, runStore: runStore),
              let memberID = runStore.authenticatedUploadMemberID else {
            errorMessage = "로그인 상태와 러닝 기록을 확인한 뒤 따라달리기를 시작해 주세요."
            return false
        }
        let key = Self.followKey(memberID: memberID, courseID: course.courseId, routeVersion: course.routeVersion)
        let pending: PendingFollowKey
        if let existing = pendingFollowKeys[key] {
            pending = existing
        } else {
            guard runStore.session == nil else {
                errorMessage = "다른 러닝이 진행 중이에요. 해당 기록을 먼저 마쳐 주세요."
                return false
            }
            pending = PendingFollowKey(memberID: memberID, courseID: course.courseId, routeVersion: course.routeVersion,
                sessionID: UUID(), runID: UUID())
            pendingFollowKeys[key] = pending
            Self.savePendingFollowKeys(pendingFollowKeys)
        }
        if let running = runStore.session, running.clientRunID != pending.runID {
            errorMessage = "다른 러닝이 진행 중이에요. 해당 기록을 먼저 마쳐 주세요."
            return false
        }
        let ticket = beginOperation()
        do {
            // The same pair is retained for this logical operation so a caller can retry the POST idempotently.
            let created = try await service.createFollowSession(courseID: course.courseId, clientSessionID: pending.sessionID, clientRunID: pending.runID, routeVersion: course.routeVersion)
            guard generation == ticket.generation else { return false }
            let current = try await service.fetchFollowSession(id: created.sessionId)
            guard generation == ticket.generation else { return false }
            guard routeIsCurrent() else {
                finishOperation(ticket)
                return false
            }
            guard current.courseAvailable != false, let liveCourse = current.course,
                  liveCourse.routeVersion == course.routeVersion else {
                finishOperation(ticket)
                errorMessage = "코스가 변경되거나 공개가 끝나 따라달리기를 시작할 수 없어요. 목록을 새로고침해 주세요."
                return false
            }
            if runStore.session == nil {
                guard runStore.start(weight: weight, clientRunID: pending.runID),
                      runStore.session?.uploadOwnerID != nil else {
                    finishOperation(ticket)
                    errorMessage = runStore.storageMessage ?? "러닝을 저장할 준비가 되지 않았어요. 다시 시도해 주세요."
                    return false
                }
            } else if runStore.session?.clientRunID != pending.runID {
                finishOperation(ticket)
                errorMessage = "다른 러닝이 진행 중이에요. 해당 기록을 먼저 마쳐 주세요."
                return false
            }
            followSession = current
            followClientRunID = pending.runID
            self.course = liveCourse
            comparison = nil
            lastProgress = (current.progressMeters, current.elapsedSeconds)
            finishOperation(ticket)
            return true
        } catch {
            guard generation == ticket.generation else { return false }
            finishOperation(ticket)
            if case CommunityCourseFailure.resultUnknown = error {
                errorMessage = "요청 결과를 확인하지 못했어요. 진행 상태를 먼저 새로고침해 주세요."
                return false
            }
            errorMessage = message(for: error)
            return false
        }
    }

    func refreshFollowSession() async -> Bool {
        guard let service, let followSession, !courseLoading else { return false }
        let ticket = generation
        courseLoading = true
        defer { if generation == ticket { courseLoading = false } }
        do {
            let value = try await service.fetchFollowSession(id: followSession.sessionId)
            guard generation == ticket else { return false }
            self.followSession = value
            if let liveCourse = value.course { course = liveCourse }
            if value.courseAvailable == false || value.course?.routeVersion != value.routeVersion {
                errorMessage = "이 코스는 더 이상 공개되지 않거나 경로 버전이 바뀌었어요. 기록은 유지돼요."
                return false
            }
            return value.course != nil
        } catch {
            guard generation == ticket else { return false }
            errorMessage = message(for: error)
            return false
        }
    }

    func sendFollowProgress(meters: Int64, seconds: Int64) async {
        guard let service, let followSession, !busy else { return }
        let boundedMeters = min(meters, course?.distanceMeters ?? meters)
        guard boundedMeters >= 0, seconds >= 0,
              lastProgress.map({ boundedMeters >= $0.meters && seconds >= $0.seconds }) ?? true,
              lastProgress?.meters != boundedMeters || lastProgress?.seconds != seconds else { return }
        let ticket = beginOperation()
        do {
            try await service.updateFollowProgress(id: followSession.sessionId, routeVersion: followSession.routeVersion, progressMeters: boundedMeters, elapsedSeconds: seconds)
            guard generation == ticket.generation else { return }
            lastProgress = (boundedMeters, seconds)
            finishOperation(ticket)
            errorMessage = ""
        } catch {
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            if case CommunityCourseFailure.conflict = error {
                if !(await refreshFollowSession()) { return }
            }
            errorMessage = message(for: error)
        }
    }

    func finishFollowingRun(runStore: RunStore) async {
        guard let service, let followSession, !busy else { return }
        let ticket = beginOperation()
        if runStore.session != nil {
            guard runStore.session?.clientRunID == followClientRunID else {
                finishOperation(ticket)
                errorMessage = "따라달리기 세션과 현재 러닝이 일치하지 않아요."
                return
            }
            guard await runStore.finishAndEnqueue(save: true) != nil else {
                finishOperation(ticket)
                errorMessage = runStore.storageMessage ?? "러닝 기록을 저장하지 못했어요. 측정 상태를 확인해 주세요."
                return
            }
        } else if !runStore.records.contains(where: { $0.clientRunID == followClientRunID }) {
            finishOperation(ticket)
            errorMessage = "이 세션에 연결된 저장 기록을 찾을 수 없어요."
            return
        }
        _ = await runStore.retryPendingRunUploads()
        guard generation == ticket.generation else { return }
        guard let record = runStore.records.first(where: { $0.clientRunID == followClientRunID }),
              record.isValid, let serverRunID = record.serverRunID,
              Int64(serverRunID) != nil, Int64(serverRunID)! > 0 else {
            finishOperation(ticket)
            errorMessage = "러닝 기록은 저장됐어요. 서버의 유효 판정이 도착하면 다시 비교할 수 있어요."
            return
        }
        do {
            let result = try await service.compareFollowRun(id: followSession.sessionId, routeVersion: followSession.routeVersion, runID: serverRunID)
            guard generation == ticket.generation else { return }
            comparison = result
            if let memberID = runStore.authenticatedUploadMemberID {
                pendingFollowKeys.removeValue(forKey: Self.followKey(memberID: memberID, courseID: followSession.courseId, routeVersion: followSession.routeVersion))
                Self.savePendingFollowKeys(pendingFollowKeys)
            }
            followClientRunID = nil
            finishOperation(ticket)
            errorMessage = ""
            noticeMessage = "따라달리기 기록 비교를 저장했어요."
        } catch {
            guard generation == ticket.generation else { return }
            finishOperation(ticket)
            if case CommunityCourseFailure.conflict = error, !(await refreshFollowSession()) { return }
            errorMessage = message(for: error)
        }
    }

    func retryComparison(runStore: RunStore) async { await finishFollowingRun(runStore: runStore) }

    private struct OperationTicket { let id: UUID; let generation: UInt64 }
    private struct PendingFollowKey: Codable, Sendable {
        let memberID: String
        let courseID: String
        let routeVersion: Int64
        let sessionID: UUID
        let runID: UUID
    }
    private static let pendingFollowDefaultsKey = "WireframeCommunityCourseFlow.pendingFollowKeys.v1"
    private static let unknownDraftDefaultsKey = "WireframeCommunityCourseFlow.unknownDraftAttempts.v1"
    private static func followKey(memberID: String, courseID: String, routeVersion: Int64) -> String {
        "\(memberID)|\(courseID)|\(routeVersion)"
    }
    private static func loadPendingFollowKeys() -> [String: PendingFollowKey] {
        guard let data = UserDefaults.standard.data(forKey: pendingFollowDefaultsKey),
              let values = try? JSONDecoder().decode([String: PendingFollowKey].self, from: data) else { return [:] }
        return values
    }
    private static func savePendingFollowKeys(_ values: [String: PendingFollowKey]) {
        let retained = Dictionary(values.sorted { $0.key < $1.key }.suffix(32), uniquingKeysWith: { _, newest in newest })
        guard let data = try? JSONEncoder().encode(retained) else { return }
        UserDefaults.standard.set(data, forKey: pendingFollowDefaultsKey)
    }
    private static func unknownDraftKey(memberID: String, runID: Int64) -> String { "\(memberID)|\(runID)" }
    private static func loadUnknownDraftAttemptKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: unknownDraftDefaultsKey) ?? [])
    }
    private static func saveUnknownDraftAttemptKeys(_ values: Set<String>) {
        UserDefaults.standard.set(Array(values.sorted().suffix(32)), forKey: unknownDraftDefaultsKey)
    }
    private func beginOperation() -> OperationTicket {
        let id = UUID()
        operationID = id
        busy = true
        errorMessage = ""
        noticeMessage = ""
        return OperationTicket(id: id, generation: generation)
    }
    private func finishOperation(_ ticket: OperationTicket) {
        guard operationID == ticket.id else { return }
        busy = false
        operationID = nil
    }

    private func refreshCertification(after ticket: UInt64, fallback: Error, missingMeansWithdrawn: Bool = false) async {
        guard let service else { return }
        do {
            let actual = try await service.fetchMyCertification()
            guard generation == ticket else { return }
            application = actual
            busy = false
            operationID = nil
            if missingMeansWithdrawn, actual == nil {
                noticeMessage = "대기 중인 신청 철회를 확인했어요."
                errorMessage = ""
            } else if actual?.status == .pending { noticeMessage = "신청 접수를 확인했어요."; errorMessage = "" }
            else if actual?.status == .approved { noticeMessage = "이미 인증 승인이 완료됐어요."; errorMessage = "" }
            else { errorMessage = message(for: fallback) }
        } catch {
            guard generation == ticket else { return }
            busy = false
            operationID = nil
            errorMessage = "신청 결과를 확인하지 못했어요. 인증 상태를 새로고침한 뒤 진행해 주세요."
        }
    }

    private func message(for error: Error) -> String {
        guard let failure = error as? CommunityCourseFailure else { return "요청을 처리하지 못했어요. 다시 확인해 주세요." }
        switch failure {
        case .accessTokenUnavailable, .unauthenticated: return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .forbidden: return "서비스 운영자 권한이 있는 계정만 이 검토 화면을 사용할 수 있어요."
        case .notFound: return "대상을 찾을 수 없거나 공개 코스가 아니에요. 목록을 새로고침해 주세요."
        case .conflict: return "상태가 바뀌었어요. 최신 상태를 새로고침해 주세요."
        case .invalidRequest: return "입력값과 선택한 기록을 확인해 주세요."
        case .resultUnknown: return "서버 응답이 끊겼어요. 안전하게 확인할 수 있는 결과만 다시 조회해 주세요."
        case .invalidResponse: return "서버 응답을 확인하지 못했어요. 다시 시도해 주세요."
        case .serverFailure: return "서버에서 처리하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport: return "네트워크 연결을 확인해 주세요."
        case .cancelled: return "요청이 중단됐어요. 현재 상태를 다시 불러올 수 있어요."
        }
    }

    private static func isPublicHTTPSURL(_ value: String) -> Bool {
        guard value.count <= 2_048, let parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https", let host = parts.host,
              !host.isEmpty, parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        return true
    }
}

private struct WRemoteCourseRouteMap: View {
    let segments: [[BackendCommunityRoutePoint]]
    var body: some View {
        GeometryReader { proxy in
            let points = segments.flatMap { $0 }
            if points.count >= 2 {
                let latitudes = points.map(\.latitude), longitudes = points.map(\.longitude)
                let minLat = latitudes.min() ?? 0, maxLat = latitudes.max() ?? 0
                let minLon = longitudes.min() ?? 0, maxLon = longitudes.max() ?? 0
                let width = max(maxLon - minLon, 0.00001), height = max(maxLat - minLat, 0.00001)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(W.soft)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Path { path in
                            for (index, point) in segment.enumerated() {
                                let x = 18 + (point.longitude - minLon) / width * max(1, proxy.size.width - 36)
                                let y = proxy.size.height - 18 - (point.latitude - minLat) / height * max(1, proxy.size.height - 36)
                                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(W.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    Circle().fill(W.lime).frame(width: 10, height: 10).position(x: 18, y: proxy.size.height - 18)
                }
            } else {
                RoundedRectangle(cornerRadius: 14).fill(W.soft).overlay(Text("표시할 경로가 없어요").font(W.font(12)).foregroundStyle(W.muted))
            }
        }.frame(height: 180).accessibilityIdentifier("communityRemoteCourseMap")
    }
}

extension WireframeRoot {
    var remoteCommunityVerificationForm: some View {
        WPage(title: "계정 인증", back: back) {
            Text("나의 러닝 활동을\n소개해 주세요").font(W.font(26, .bold)).kerning(-0.78).lineSpacing(5)
            Text("서비스 운영자가 신청 내용을 검토해요. 인증 승인은 코스 공개 권한을 부여해요.").font(W.font(13)).lineSpacing(7).foregroundStyle(W.muted)
            WField(label: "활동 소개", text: $courseFlow.applicationReason, limit: 300, multiline: true, multilineHeight: 132, textSize: 15, labelSize: 13, softFieldStyle: true).accessibilityIdentifier("communityVerificationNote")
            WField(label: "HTTPS 확인 자료 (줄마다 하나씩)", text: $courseFlow.evidenceURLs, limit: 10_240, multiline: true, multilineHeight: 100, textSize: 13, labelSize: 13, softFieldStyle: true).accessibilityIdentifier("communityCertificationEvidenceURLs")
            WNotice(text: "확인 자료는 검토 후 서버에서 삭제돼요. 공개 코스에는 시작·끝 위치를 가린 경로만 포함돼요.")
            if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityVerificationError") }
        } actions: {
            Button(courseFlow.busy ? "신청 중…" : "인증 신청") {
                let scope = ui.remoteAccountScopeID
                Task {
                    await courseFlow.submitCertification()
                    if ui.screen == "C10", ui.remoteAccountScopeID == scope, courseFlow.application?.status == .pending { go("C11") }
                }
            }
                .buttonStyle(WButtonStyle()).disabled(courseFlow.busy).accessibilityIdentifier("communityVerificationSubmit")
        }.task(id: ui.remoteAccountScopeID) { await courseFlow.loadCertification() }
    }

    var remoteCommunityVerificationStatus: some View {
        let status = courseFlow.application?.status
        let heading: String = switch status { case .pending: "인증을 검토하고 있어요"; case .approved: "계정 인증이 완료됐어요"; case .rejected: "신청 내용을 다시 확인해 주세요"; case .withdrawn, .none: "계정 인증을 신청해 보세요" }
        let text: String = switch status { case .pending: "결과가 나오면 상태를 새로고침해 확인해 주세요."; case .approved: "이제 유효한 서버 러닝 기록을 코스로 공유할 수 있어요."; case .rejected: courseFlow.application?.reviews?.last?.reason ?? "내용을 보완해 다시 신청할 수 있어요."; case .withdrawn, .none: "서비스 운영자가 신청을 검토해요." }
        return WPage(title: "인증 신청", back: back) {
            Text(heading).font(W.font(21, .semibold)).accessibilityIdentifier("communityVerificationHeading")
            Text(text).font(W.font(14)).foregroundStyle(W.muted).accessibilityIdentifier("communityVerificationMessage")
            if let app = courseFlow.application, app.status == .pending {
                if let reason = app.applicationReason { WNotice(text: reason) }
                Text("검토 중에는 신청을 취소할 수 있어요.").font(W.font(12)).foregroundStyle(W.muted)
            }
            WNotice(text: "배지는 운영자 승인 상태를 보여 줘요. 코스 경로의 안전이나 달리기 능력을 보증하지 않아요.")
            if !courseFlow.noticeMessage.isEmpty { WNotice(text: courseFlow.noticeMessage).accessibilityIdentifier("communityCertificationNotice") }
            if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityCertificationError") }
            Button("운영자 검토 화면 열기") { go("C44") }.font(W.font(13, .medium)).accessibilityIdentifier("communityOperatorReviewEntry")
        } actions: {
            if status == .pending { Button(courseFlow.busy ? "처리 중…" : "신청 취소") { Task { await courseFlow.withdrawCertification() } }.buttonStyle(WButtonStyle(kind: 1)).disabled(courseFlow.busy).accessibilityIdentifier("communityCertificationWithdraw") }
            else if status == .approved { Button("코스 공유하기") { go("C13") }.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityVerificationContinue") }
            else { Button("신청하기") { go("C10") }.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityVerificationContinue") }
            Button(courseFlow.certificationLoading ? "불러오는 중…" : "상태 새로고침") { Task { await courseFlow.loadCertification() } }.font(W.font(13)).disabled(courseFlow.certificationLoading || courseFlow.busy).accessibilityIdentifier("communityCertificationRefresh")
        }.task(id: ui.remoteAccountScopeID) { await courseFlow.loadCertification() }
    }

    var remoteCommunityOperatorQueue: some View {
        WPage(title: "인증 검토", back: back) {
            if courseFlow.operatorAccessDenied { WNotice(text: "서비스 운영자 권한이 있는 계정만 대기 신청을 볼 수 있어요.", danger: true).accessibilityIdentifier("communityOperatorRestricted") }
            if courseFlow.operatorLoading { ProgressView().accessibilityIdentifier("communityOperatorLoading") }
            if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityOperatorError") }
            if !courseFlow.operatorAccessDenied, !courseFlow.operatorLoading, courseFlow.errorMessage.isEmpty {
                if courseFlow.operatorQueue.isEmpty { Text("대기 중인 신청이 없어요").font(W.font(14)).foregroundStyle(W.muted).accessibilityIdentifier("communityOperatorQueueEmpty") }
                ForEach(courseFlow.operatorQueue) { application in
                    Button {
                        let scope = ui.remoteAccountScopeID
                        Task {
                            await courseFlow.openOperatorApplication(id: application.applicationId)
                            if ui.screen == "C44", ui.remoteAccountScopeID == scope,
                               courseFlow.operatorApplication?.applicationId == application.applicationId { go("C45") }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("신청 \(application.applicationId)").font(W.font(14, .semibold))
                            Text(application.applicationReason ?? "소개 없음").font(W.font(12)).foregroundStyle(W.muted).lineLimit(2)
                        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("communityOperatorRequest-\(application.applicationId)")
                    W.line.frame(height: 1)
                }
            }
            if courseFlow.operatorQueueNextCursor != nil {
                Button(courseFlow.operatorLoading ? "불러오는 중…" : "더 보기") { Task { await courseFlow.loadOperatorQueue(loadMore: true) } }
                    .font(W.font(13)).disabled(courseFlow.operatorLoading).accessibilityIdentifier("communityOperatorQueueMore")
            }
            Button("대기 신청 새로고침") { Task { await courseFlow.loadOperatorQueue() } }.font(W.font(13)).disabled(courseFlow.operatorLoading).accessibilityIdentifier("communityOperatorQueueRefresh")
        } actions: { }
            .task(id: ui.remoteAccountScopeID) { await courseFlow.loadOperatorQueue() }
    }

    var remoteCommunityOperatorApplication: some View {
        WPage(title: "인증 신청 검토", back: back) {
            if let app = courseFlow.operatorApplication {
                Text("신청 \(app.applicationId)").font(W.font(18, .semibold))
                Text(app.applicationReason ?? "신청 소개 없음").font(W.font(14)).lineSpacing(6)
                if let urls = app.evidenceUrls { ForEach(Array(urls.enumerated()), id: \.offset) { _, url in Text(url).font(W.font(11)).foregroundStyle(W.muted).textSelection(.enabled) } }
                if app.status != .pending { WNotice(text: "이 신청은 이미 \(app.status.rawValue) 상태예요.") }
                WField(label: "검토 사유", text: $courseFlow.operatorDecisionReason, limit: 300, multiline: true, multilineHeight: 100, textSize: 14, labelSize: 13, softFieldStyle: true).accessibilityIdentifier("communityOperatorDecisionReason")
                Text("이 검토는 서비스 운영자 권한으로 처리돼요. 크루 관리자 권한은 사용할 수 없어요.").font(W.font(12)).foregroundStyle(W.muted)
            }
            if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityOperatorDecisionError") }
            if !courseFlow.noticeMessage.isEmpty { WNotice(text: courseFlow.noticeMessage).accessibilityIdentifier("communityOperatorDecisionNotice") }
        } actions: {
            if courseFlow.operatorApplication?.status == .pending {
                Button(courseFlow.busy ? "처리 중…" : "인증 승인") { Task { await courseFlow.decideOperatorApplication(action: "APPROVE") } }.buttonStyle(WButtonStyle()).disabled(courseFlow.busy).accessibilityIdentifier("communityOperatorApprove")
                Button(courseFlow.busy ? "처리 중…" : "인증 거부") { Task { await courseFlow.decideOperatorApplication(action: "REJECT") } }.buttonStyle(WButtonStyle(kind: 1)).disabled(courseFlow.busy).accessibilityIdentifier("communityOperatorReject")
            }
            Button("신청 다시 불러오기") { if let id = courseFlow.operatorApplication?.applicationId { Task { await courseFlow.openOperatorApplication(id: id) } } }.font(W.font(13)).disabled(courseFlow.busy).accessibilityIdentifier("communityOperatorApplicationRefresh")
        }
    }

    var remoteCommunityCourseComposer: some View {
        let summaries: [BackendRunSummary] = {
            switch remoteReads.runRecordsState {
            case .loaded(let snapshot), .loadingMore(let snapshot), .failedLoadingMore(let snapshot, _):
                return snapshot.items.filter { $0.verdict == "VALID" && Int64($0.id).map { $0 > 0 } == true }
            default: return []
            }
        }()
        return WPage(title: "코스 공유", back: back) {
            if !courseFlow.verified {
                Text("계정 인증이 필요해요").font(W.font(18, .semibold)).accessibilityIdentifier("communityCourseNeedsVerification")
                Text("서비스 운영자의 승인을 받은 뒤 코스를 공유할 수 있어요.").font(W.font(13)).foregroundStyle(W.muted)
                Button("인증 상태 확인") { go("C11") }.font(W.font(13)).accessibilityIdentifier("communityCourseVerify")
            } else {
                Text("유효 판정이 끝난 내 서버 러닝 기록만 선택할 수 있어요. 코스 이름이나 작성자 정보는 코스 API에 저장되지 않아요.").font(W.font(13)).foregroundStyle(W.muted).lineSpacing(5)
                if summaries.isEmpty {
                    WNotice(text: "공유할 유효 서버 러닝 기록이 없어요.").accessibilityIdentifier("communityCourseNoValidRuns")
                    Button("기록 새로고침") { Task { await remoteReads.activate(feature: .runs, accountScopeID: ui.remoteAccountScopeID, runID: nil, screen: "C13", routeIsCurrent: { ui.screen == "C13" }) } }.font(W.font(13)).accessibilityIdentifier("communityCourseRefreshRuns")
                } else {
                    Picker("러닝 기록", selection: $courseFlow.courseRunID) {
                        Text("기록 선택").tag("")
                        ForEach(summaries) { run in
                            Text("\(run.runDate) · \(String(format: "%.2f", Double(run.validDistanceMeters ?? 0) / 1_000)) km").tag(run.id)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("communityRemoteCourseRunPicker")
                }
                HStack(spacing: 12) {
                    WField(label: "시작 숨김 (m)", text: $courseFlow.courseStartMask, limit: 6, textSize: 14, labelSize: 12, softFieldStyle: true).accessibilityIdentifier("communityCourseStartMask")
                    WField(label: "끝 숨김 (m)", text: $courseFlow.courseEndMask, limit: 6, textSize: 14, labelSize: 12, softFieldStyle: true).accessibilityIdentifier("communityCourseEndMask")
                }
                Toggle(isOn: $courseFlow.publicConsent) { Text("시작·끝 위치를 숨긴 경로를 공개하는 데 동의해요") }.tint(W.lime).accessibilityIdentifier("communityRemoteCourseConsent")
                if let draftID = courseFlow.draftCourseID { WNotice(text: "비공개 초안 \(draftID)가 준비됐어요. 게시 전 동의와 서버 검증을 다시 확인해요.").accessibilityIdentifier("communityCourseDraftReady") }
                if courseFlow.draftCreateResultUnknown { WNotice(text: "초안 생성 결과를 확인하지 못했어요. 서버에 초안 조회 API가 없어 중복 생성 재시도를 막았어요.", danger: true).accessibilityIdentifier("communityCourseDraftUnknown") }
                if !courseFlow.noticeMessage.isEmpty { WNotice(text: courseFlow.noticeMessage).accessibilityIdentifier("communityCourseNotice") }
                if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityCourseError") }
            }
        } actions: {
            if courseFlow.verified {
                Button(courseFlow.busy ? "처리 중…" : courseFlow.draftCourseID == nil ? "비공개 초안 만들기" : "공개 코스로 게시") {
                    Task {
                        let scope = ui.remoteAccountScopeID
                        await courseFlow.createCourseDraftAndPublish(memberID: store.authenticatedUploadMemberID)
                        if ui.screen == "C13", ui.remoteAccountScopeID == scope,
                           courseFlow.noticeMessage == "시작·끝 위치를 가린 코스를 공개했어요." || courseFlow.noticeMessage == "코스가 공개된 상태를 다시 확인했어요." { go("C12") }
                    }
                }
                    .buttonStyle(WButtonStyle()).disabled(courseFlow.busy || summaries.isEmpty || Int64(courseFlow.courseRunID) == nil || courseFlow.draftCreateResultUnknown || (courseFlow.draftCourseID != nil && !courseFlow.publicConsent)).accessibilityIdentifier("communityRemoteCoursePublish")
            }
        }.task(id: ui.screen) {
            guard ui.screen == "C13" else { return }
            courseFlow.restoreDraftCreateUnknown(memberID: store.authenticatedUploadMemberID)
            await courseFlow.loadCertification()
            if case .idle = remoteReads.runRecordsState {
                await remoteReads.activate(feature: .runs, accountScopeID: ui.remoteAccountScopeID, runID: nil, screen: "C13", routeIsCurrent: { ui.screen == "C13" })
            }
        }.onChange(of: courseFlow.courseRunID) { _, _ in
            courseFlow.restoreDraftCreateUnknown(memberID: store.authenticatedUploadMemberID)
        }
    }

    var remoteCommunityCourseCatalogOrDetail: some View {
        if let course = courseFlow.course {
            AnyView(WPage(title: "공유 코스", back: { courseFlow.clearSelectedCourse(); back() }) {
                Text("공유 코스").font(W.font(26, .semibold)).accessibilityIdentifier("communityCourseTitle")
                WRemoteCourseRouteMap(segments: course.routeSegments)
                HStack(alignment: .top, spacing: 0) {
                    remoteCourseFact("거리", "\(MovNumber.display(Double(course.distanceMeters) / 1_000)) km")
                    remoteCourseFact("기록 시간", RunRecord.clock(Double(course.runningSeconds)))
                    remoteCourseFact("페이스", course.paceSecondsPerKm.map { RunRecord.clock(Double($0)) + " /km" } ?? "—")
                }
                Text("시작과 끝 위치를 가린 코스 경로와 러닝 기록만 표시해요.").font(W.font(13)).foregroundStyle(W.muted)
                if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityRemoteCourseDetailError") }
            } actions: {
                Button(courseFlow.busy ? "세션 준비 중…" : "따라달리기 시작") {
                    let scope = ui.remoteAccountScopeID
                    Task {
                        let started = await courseFlow.beginFollowing(course: course, runStore: store, weight: Double(ui.profile.weight), routeIsCurrent: { ui.screen == "C12" && ui.remoteAccountScopeID == scope })
                        if started, ui.screen == "C12", ui.remoteAccountScopeID == scope { go("C14") }
                    }
                }
                    .buttonStyle(WButtonStyle()).disabled(courseFlow.busy || !courseFlow.canBeginFollowing(course: course, runStore: store)).accessibilityIdentifier("communityRemoteFollowStart")
            })
        } else {
            AnyView(WPage(title: "공유 코스", back: back) {
                if courseFlow.courseListLoading { ProgressView().accessibilityIdentifier("communityRemoteCourseLoading") }
                if courseFlow.coursePage?.items.isEmpty == true { Text("아직 공개된 코스가 없어요").font(W.font(14)).foregroundStyle(W.muted).accessibilityIdentifier("communityRemoteCourseEmpty") }
                ForEach(courseFlow.coursePage?.items ?? []) { summary in
                    Button { Task { await courseFlow.openCourse(id: summary.courseId) } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("공유 코스").font(W.font(15, .semibold))
                            Text("\(summary.runDate) · \(MovNumber.display(Double(summary.distanceMeters) / 1_000)) km · \(RunRecord.clock(Double(summary.runningSeconds)))").font(W.font(12)).foregroundStyle(W.muted)
                        }.frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("communityRemoteCourse-\(summary.courseId)")
                    W.line.frame(height: 1)
                }
                if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityRemoteCourseListError") }
                Button(courseFlow.courseListLoading ? "불러오는 중…" : "목록 새로고침") { Task { await courseFlow.loadCourses() } }.font(W.font(13)).disabled(courseFlow.courseListLoading).accessibilityIdentifier("communityRemoteCourseRefresh")
                if courseFlow.coursePage?.nextCursor != nil { Button("더 보기") { Task { await courseFlow.loadCourses(loadMore: true) } }.font(W.font(13)).accessibilityIdentifier("communityRemoteCourseMore") }
            } actions: { }
                .task(id: ui.screen) { if ui.screen == "C12", courseFlow.coursePage == nil { await courseFlow.loadCourses() } })
        }
    }

    var remoteCommunityFollowRun: some View {
        let session = courseFlow.followSession
        return WPage(title: "따라달리기", back: back) {
            if let course = courseFlow.course { WRemoteCourseRouteMap(segments: course.routeSegments) }
            if let run = store.session, session != nil, run.clientRunID == courseFlow.followClientRunID {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RunRecord.clock(run.elapsed(at: Date()))).font(W.font(26, .semibold)).monospacedDigit()
                    Text("· \(MovNumber.display((run.distance ?? 0) * 1_000)) / \(MovNumber.display(Double(courseFlow.course?.distanceMeters ?? 0))) m").font(W.font(13)).foregroundStyle(W.muted)
                }.accessibilityIdentifier("communityFollowProgress")
                Button(run.paused ? "러닝 재개" : "일시정지") { if run.paused { store.resume() } else { store.pause() } }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("communityFollowPause")
                Button(courseFlow.busy ? "기록 저장 중…" : "러닝 완료하고 비교") { Task { await courseFlow.finishFollowingRun(runStore: store) } }.buttonStyle(WButtonStyle()).disabled(courseFlow.busy || run.elapsed(at: Date()) <= 0).accessibilityIdentifier("communityFollowFinish")
            } else if let comparison = courseFlow.comparison {
                Text("따라달리기 비교를 저장했어요").font(W.font(18, .semibold)).accessibilityIdentifier("communityFollowComparisonTitle")
                remoteCourseFact("코스 거리", "\(MovNumber.display(Double(comparison.courseDistanceMeters))) m")
                remoteCourseFact("내 거리", "\(MovNumber.display(Double(comparison.runDistanceMeters))) m")
                remoteCourseFact("시간 차이", "\(RunRecord.clock(Double(abs(comparison.runningSecondsDelta))))")
            } else if store.session != nil {
                WNotice(text: "다른 러닝이 진행 중이에요. 코스 세션과 일치하는 기록만 연결할 수 있어요.", danger: true)
            } else {
                Text("완료된 러닝 기록을 저장하면 서버에서 유효 판정을 확인해 코스와 비교해요.").font(W.font(13)).foregroundStyle(W.muted)
                Button("저장된 러닝 다시 확인") { Task { await courseFlow.retryComparison(runStore: store) } }.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityFollowCompareRetry")
            }
            Text("\(session?.progressMeters ?? 0) m · 경로 버전 \(session?.routeVersion ?? 0)").font(W.font(11)).foregroundStyle(W.muted).accessibilityIdentifier("communityFollowRouteVersion")
            if !courseFlow.errorMessage.isEmpty { WNotice(text: courseFlow.errorMessage, danger: true).accessibilityIdentifier("communityFollowError") }
            if !courseFlow.noticeMessage.isEmpty { WNotice(text: courseFlow.noticeMessage).accessibilityIdentifier("communityFollowNotice") }
        } actions: {
            Button("코스 화면으로 돌아가기") { back() }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("communityFollowBackToCourse")
        }
        .task(id: session?.sessionId) {
            guard session != nil else { return }
            guard await courseFlow.refreshFollowSession() else { return }
            while !Task.isCancelled, courseFlow.canContinueFollowing,
                  let live = store.session, live.clientRunID == courseFlow.followClientRunID {
                let meters = Int64(max(0, ((live.distance ?? 0) * 1_000).rounded(.down)))
                let seconds = Int64(max(0, live.elapsed(at: Date()).rounded(.down)))
                await courseFlow.sendFollowProgress(meters: meters, seconds: seconds)
                if !courseFlow.canContinueFollowing { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func remoteCourseFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(W.font(11)).foregroundStyle(W.muted)
            Text(value).font(W.font(17, .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            .accessibilityElement(children: .combine).accessibilityIdentifier("communityCourseFact-\(title)")
    }
}

#if DEBUG
actor WireframeCommunityCourseFixture: CommunityCourseServing {
    private let operatorEnabled: Bool
    private let failSubmissionOnce: Bool
    private let delayCertificationRead: Bool
    private let delaySubmission: Bool
    private let failWithdrawalOnce: Bool
    private let unavailableFollowCourse: Bool
    private let emptyCourseList: Bool
    private var submissionFailed = false
    private var withdrawalFailed = false
    private var submissionCalls = 0
    private let failCourseCreateOnce: Bool
    private var courseCreateFailed = false
    private var application: CommunityCertificationApplication?
    private var courseWasPublished = true
    private var draft: BackendCommunityCourseDraft?
    private var followSessions: [UUID: BackendCourseFollowSession] = [:]

    init(arguments: [String]) {
        operatorEnabled = arguments.contains("-wire-community-course-operator")
        failSubmissionOnce = arguments.contains("-wire-community-course-submit-fail-once")
        delayCertificationRead = arguments.contains("-wire-community-course-delay-status")
        delaySubmission = arguments.contains("-wire-community-course-delay-submit")
        failWithdrawalOnce = arguments.contains("-wire-community-course-withdraw-fail-once")
        unavailableFollowCourse = arguments.contains("-wire-community-course-follow-revision-changed")
        emptyCourseList = arguments.contains("-wire-community-course-empty")
        failCourseCreateOnce = arguments.contains("-wire-community-course-create-fail-once")
        let status: CommunityCertificationStatus? = arguments.contains("-wire-community-course-approved") ? .approved
            : arguments.contains("-wire-community-course-pending") ? .pending
            : arguments.contains("-wire-community-course-rejected") ? .rejected : nil
        if let status {
            application = CommunityCertificationApplication(
                applicationId: "501", applicantMemberId: "fixture-applicant", status: status,
                applicationReason: "주간 러닝 활동을 기록하고 있어요.", submittedAt: "2026-10-18T07:00:00Z",
                updatedAt: "2026-10-18T07:00:00Z", evidenceUrls: ["https://example.org/running"],
                reviews: status == .rejected ? [CommunityCertificationReview(fromStatus: "PENDING", toStatus: "REJECTED", reason: "활동 내용을 보완해 주세요.", occurredAt: "2026-10-18T08:00:00Z", retainUntil: "2027-10-18T08:00:00Z")] : []
            )
        }
    }

    func fetchMyCertification() async throws -> CommunityCertificationApplication? {
        if delayCertificationRead { try? await Task.sleep(for: .milliseconds(800)) }
        return application
    }
    func submitCertification(reason: String, evidenceURLs: [String]) async throws -> CommunityCertificationApplication {
        submissionCalls += 1
        if delaySubmission { try? await Task.sleep(for: .milliseconds(900)) }
        if application?.status == .pending || application?.status == .approved { throw CommunityCourseFailure.conflict }
        application = CommunityCertificationApplication(applicationId: "502", applicantMemberId: nil, status: .pending,
            applicationReason: reason, submittedAt: "2026-10-19T08:00:00Z", updatedAt: "2026-10-19T08:00:00Z",
            evidenceUrls: evidenceURLs, reviews: [])
        if failSubmissionOnce && !submissionFailed { submissionFailed = true; throw CommunityCourseFailure.transport(.timedOut) }
        return application!
    }
    func withdrawCertification() async throws {
        guard application?.status == .pending else { throw CommunityCourseFailure.conflict }
        application = nil
        if failWithdrawalOnce && !withdrawalFailed { withdrawalFailed = true; throw CommunityCourseFailure.transport(.timedOut) }
    }
    func certificationSubmissionCount() -> Int { submissionCalls }
    func fetchOperatorQueue(cursor: String?, size: Int) async throws -> CommunityCertificationPage {
        guard operatorEnabled else { throw CommunityCourseFailure.forbidden }
        return CommunityCertificationPage(items: application?.status == .pending ? [application!] : [], nextCursor: nil)
    }
    func fetchOperatorApplication(id: String) async throws -> CommunityCertificationApplication {
        guard operatorEnabled else { throw CommunityCourseFailure.forbidden }
        guard let application, application.applicationId == id else { throw CommunityCourseFailure.notFound }
        return application
    }
    func decideOperatorApplication(id: String, action: String, reason: String) async throws -> CommunityCertificationApplication {
        guard operatorEnabled else { throw CommunityCourseFailure.forbidden }
        guard let current = application, current.applicationId == id else { throw CommunityCourseFailure.notFound }
        if current.status == (action == "APPROVE" ? .approved : .rejected) { return current }
        guard current.status == .pending else { throw CommunityCourseFailure.conflict }
        let next: CommunityCertificationStatus = action == "APPROVE" ? .approved : .rejected
        let review = CommunityCertificationReview(fromStatus: "PENDING", toStatus: next.rawValue, reason: reason, occurredAt: "2026-10-19T08:00:00Z", retainUntil: "2027-10-19T08:00:00Z")
        application = CommunityCertificationApplication(applicationId: current.applicationId, applicantMemberId: current.applicantMemberId,
            status: next, applicationReason: current.applicationReason, submittedAt: current.submittedAt,
            updatedAt: "2026-10-19T08:00:00Z", evidenceUrls: nil, reviews: [review])
        return application!
    }
    func listCourses(cursor: String?, size: Int) async throws -> BackendCommunityCoursePage {
        let summary = BackendCommunityCourseSummary(courseId: "7001", routeVersion: 1, runDate: "2026-10-18", distanceMeters: 4_820, runningSeconds: 1_808, paceSecondsPerKm: 375)
        return BackendCommunityCoursePage(items: courseWasPublished && !emptyCourseList ? [summary] : [], nextCursor: nil)
    }
    func fetchCourse(id: String) async throws -> BackendCommunityCourse {
        guard courseWasPublished, id == "7001" || id == draft?.courseId else { throw CommunityCourseFailure.notFound }
        return Self.course(id: id)
    }
    func createCourseDraft(runID: Int64, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft {
        guard application?.status == .approved else { throw CommunityCourseFailure.forbidden }
        if draft != nil { throw CommunityCourseFailure.conflict }
        let value = BackendCommunityCourseDraft(courseId: "9001", status: "DRAFT", startMaskMeters: startMaskMeters, endMaskMeters: endMaskMeters)
        draft = value
        courseWasPublished = false
        if failCourseCreateOnce && !courseCreateFailed { courseCreateFailed = true; throw CommunityCourseFailure.resultUnknown }
        return value
    }
    func adjustCourseDraft(id: String, startMaskMeters: Int64, endMaskMeters: Int64) async throws -> BackendCommunityCourseDraft {
        guard let current = draft, current.courseId == id else { throw CommunityCourseFailure.conflict }
        let updated = BackendCommunityCourseDraft(courseId: current.courseId, status: current.status,
            startMaskMeters: startMaskMeters, endMaskMeters: endMaskMeters)
        draft = updated
        return updated
    }
    func publishCourse(id: String) async throws -> BackendCommunityCourse {
        guard draft?.courseId == id, application?.status == .approved else { throw CommunityCourseFailure.conflict }
        courseWasPublished = true
        return Self.course(id: id)
    }
    func unpublishCourse(id: String) async throws { courseWasPublished = false }
    func createFollowSession(courseID: String, clientSessionID: UUID, clientRunID: UUID, routeVersion: Int64) async throws -> BackendCourseFollowSession {
        guard courseWasPublished, courseID == "7001", routeVersion == 1 else { throw CommunityCourseFailure.notFound }
        if let existing = followSessions[clientSessionID] {
            guard existing.clientRunId == clientRunID, existing.courseId == courseID, existing.routeVersion == routeVersion else { throw CommunityCourseFailure.conflict }
            return existing
        }
        let value = BackendCourseFollowSession(sessionId: "8101", courseId: courseID, clientSessionId: clientSessionID, clientRunId: clientRunID,
            routeVersion: routeVersion, progressMeters: 0, elapsedSeconds: 0, courseAvailable: true, course: Self.course(id: courseID), comparison: nil)
        followSessions[clientSessionID] = value
        return value
    }
    func fetchFollowSession(id: String) async throws -> BackendCourseFollowSession {
        guard let value = followSessions.values.first(where: { $0.sessionId == id }) else { throw CommunityCourseFailure.notFound }
        if unavailableFollowCourse {
            return BackendCourseFollowSession(sessionId: value.sessionId, courseId: value.courseId,
                clientSessionId: value.clientSessionId, clientRunId: value.clientRunId, routeVersion: value.routeVersion,
                progressMeters: value.progressMeters, elapsedSeconds: value.elapsedSeconds,
                courseAvailable: false, course: nil, comparison: nil)
        }
        return value
    }
    func updateFollowProgress(id: String, routeVersion: Int64, progressMeters: Int64, elapsedSeconds: Int64) async throws {
        guard let (key, value) = followSessions.first(where: { $0.value.sessionId == id }), routeVersion == value.routeVersion,
              progressMeters >= value.progressMeters, elapsedSeconds >= value.elapsedSeconds,
              progressMeters <= 4_820 else { throw CommunityCourseFailure.conflict }
        followSessions[key] = BackendCourseFollowSession(sessionId: value.sessionId, courseId: value.courseId,
            clientSessionId: value.clientSessionId, clientRunId: value.clientRunId, routeVersion: value.routeVersion,
            progressMeters: progressMeters, elapsedSeconds: elapsedSeconds, courseAvailable: value.courseAvailable, course: value.course, comparison: value.comparison)
    }
    func compareFollowRun(id: String, routeVersion: Int64, runID: String) async throws -> BackendCourseFollowComparison {
        guard let value = followSessions.values.first(where: { $0.sessionId == id }), value.routeVersion == routeVersion else { throw CommunityCourseFailure.notFound }
        guard Int64(runID) != nil else { throw CommunityCourseFailure.invalidRequest }
        return BackendCourseFollowComparison(courseId: value.courseId, routeVersion: routeVersion, runId: runID,
            courseDistanceMeters: 4_820, courseRunningSeconds: 1_808, coursePaceSecondsPerKm: 375,
            runDistanceMeters: 5_000, runRunningSeconds: 1_900, runPaceSecondsPerKm: 380,
            distanceDeltaMeters: 180, runningSecondsDelta: 92, paceSecondsPerKmDelta: 5)
    }

    private static func course(id: String) -> BackendCommunityCourse {
        let segment = [
            BackendCommunityRoutePoint(latitude: 37.5680, longitude: 126.9760, elapsedSeconds: 0),
            BackendCommunityRoutePoint(latitude: 37.5690, longitude: 126.9780, elapsedSeconds: 320),
            BackendCommunityRoutePoint(latitude: 37.5700, longitude: 126.9800, elapsedSeconds: 670),
            BackendCommunityRoutePoint(latitude: 37.5710, longitude: 126.9820, elapsedSeconds: 1_000)
        ]
        return BackendCommunityCourse(courseId: id, routeVersion: 1, runDate: "2026-10-18", distanceMeters: 4_820,
            runningSeconds: 1_808, paceSecondsPerKm: 375, routeSegments: [segment])
    }
}
#endif
