import Foundation
import Observation

/// Supplies the authenticated member identity at run start. UI-only account scopes
/// are deliberately not accepted by this boundary.
@MainActor protocol RunUploadMemberIdentityProviding {
    func currentAuthenticatedMemberID() -> String?
}

enum MovNumber {
    static func display(_ value:Double)->String {
        guard value.isFinite else{return "—"}
        let fixed=String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value)
        let trimmed=fixed.replacingOccurrences(of:#"\.?0+$"#,with:"",options:.regularExpression)
        return trimmed == "-0" ? "0":trimmed
    }
}

enum GoalKind: String, Codable, CaseIterable { case none, distance, time
    var title: String { switch self { case .none: "목표 없이 달리기"; case .distance: "거리 목표"; case .time: "시간 목표" } }
}
struct RunGoal: Codable, Equatable {
    var kind: GoalKind = .none
    var kilometers: Double = 5
    var minutes: Int = 30
    var summary: String { switch kind { case .none: "목표 없이 달리기"; case .distance: "\(MovNumber.display(kilometers)) km 달리기"; case .time: "\(Self.duration(minutes)) 달리기" } }
    static func duration(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)분" : "\(minutes / 60)시간" + (minutes % 60 == 0 ? "" : " \(minutes % 60)분") }
}
struct WeeklyGoal: Codable {
    var distanceEnabled = true
    var timeEnabled = false
    var kilometers:Double = 20
    var minutes = 120
    static func percent(value:Double,goal:Double)->Int {guard goal>0 else{return 0};return Int((value/goal*100).rounded())}
}
enum WReviewClock {
    static var referenceDate: Date { ISO8601DateFormatter().date(from: "2026-10-01T12:00:00+09:00")! }
    static var now: Date {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-wire-fixture") && (args.contains("-wire-capture-viewport") || args.contains("-wire-fixed-reference-week")) ? referenceDate : Date()
    }
}
struct RunSegment: Codable, Equatable {
    var distance:Double;var seconds:Double;var type="include";var reason:String?
}
enum RunPointRewardStatus: String, Codable, Equatable {
    case pending = "PENDING"
    case settled = "SETTLED"
    case unavailable = "UNAVAILABLE"
}
enum RunPointRewardValidationError: Error {
    case unexpectedAmount
    case missingSettledAmount
    case negativeAmount
}
struct RunPointReward: Codable, Equatable {
    let status: RunPointRewardStatus
    let pointsAwarded: Int?

    private enum CodingKeys: String, CodingKey { case status, pointsAwarded }

    init(status: RunPointRewardStatus, pointsAwarded: Int?) throws {
        try Self.validate(status: status, pointsAwarded: pointsAwarded)
        self.status = status
        self.pointsAwarded = pointsAwarded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(RunPointRewardStatus.self, forKey: .status)
        guard container.contains(.pointsAwarded) else {
            throw DecodingError.keyNotFound(CodingKeys.pointsAwarded, .init(codingPath: decoder.codingPath, debugDescription: "pointReward.pointsAwarded is required and may be null"))
        }
        let pointsAwarded = try container.decodeIfPresent(Int.self, forKey: .pointsAwarded)
        do { try Self.validate(status: status, pointsAwarded: pointsAwarded) }
        catch {
            throw DecodingError.dataCorruptedError(forKey: .pointsAwarded, in: container, debugDescription: "pointReward status and pointsAwarded do not match the backend contract")
        }
        self.status = status
        self.pointsAwarded = pointsAwarded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(pointsAwarded, forKey: .pointsAwarded)
    }

    private static func validate(status: RunPointRewardStatus, pointsAwarded: Int?) throws {
        switch status {
        case .pending, .unavailable:
            guard pointsAwarded == nil else { throw RunPointRewardValidationError.unexpectedAmount }
        case .settled:
            guard let pointsAwarded else { throw RunPointRewardValidationError.missingSettledAmount }
            guard pointsAwarded >= 0 else { throw RunPointRewardValidationError.negativeAmount }
        }
    }

    var compactText: String {
        switch status {
        case .pending: "확인 중"
        case .settled: "\(pointsAwarded!.formatted())"
        case .unavailable: "확인 불가"
        }
    }
    var accessibilityLabel: String {
        switch status {
        case .pending: "러닝 포인트 적립 확인 중"
        case .settled: "러닝 포인트 \(pointsAwarded!.formatted()) 포인트 적립"
        case .unavailable: "러닝 포인트 적립 상태 확인 불가"
        }
    }
}
struct RunRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var memo = ""
    var seconds: Double
    var kilometers: Double
    var segments:[RunSegment]? = nil
    var weightKg:Double? = nil
    var isExample:Bool? = nil
    var pointReward:RunPointReward? = nil
    /// Set only for runs started with an explicitly injected authenticated identity.
    var uploadOwnerID:String? = nil
    /// Stable idempotency key pinned when this run starts.
    var clientRunID:UUID? = nil
    /// Immutable measurement snapshot used for enqueue and crash recovery.
    var uploadPayload:RunUploadPayload? = nil
    /// True once the immutable snapshot has been persisted in the outbox.
    var uploadEnqueued:Bool? = nil
    var caloriesText:String {guard isValid else{return "0 kcal"};guard let weightKg else{return "—"};return "약 \(Int((weightKg*kilometers).rounded())) kcal"}
    var isValid: Bool { kilometers > 0 }
    var pace: String { guard kilometers>0 else{return "0:00"};let value=max(0,Int(seconds/kilometers));return String(format:"%d:%02d",value/60,value%60) }
    var validityDetails: [String] {
        guard let segments, !segments.isEmpty else { return ["구간별 판별 정보가 없어 제외 이유를 확인할 수 없어요."] }
        let labels = ["gps-gap":"GPS 누락", "pause":"일시정지", "vehicle":"차량 이동", "transit":"대중교통", "gps-spike":"GPS 튐", "long-idle":"오랜 정지", "unknown":"판별 정보 없음"]
        let details = segments.compactMap { segment -> String? in
            guard segment.type != "include" || segment.distance <= 0 || segment.seconds <= 0 else { return nil }
            let reason = segment.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.flatMap { $0.isEmpty ? nil : $0 } ?? labels[segment.type] ?? "유효 거리로 확인할 수 없는 구간"
        }
        return details.isEmpty ? ["저장된 구간에서 제외 항목이 없습니다."] : details
    }
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    static func title(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 6 ? "새벽" : hour < 12 ? "아침" : hour < 18 ? "오후" : "저녁"
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) + " \(part) 러닝"
    }
}
struct RunPeriodSummary: Equatable {
    var recordCount: Int
    var kilometers: Double
    var seconds: Double
    init(records: [RunRecord]) {
        let valid = records.filter(\.isValid)
        recordCount = valid.count
        kilometers = valid.reduce(0) { $0 + $1.kilometers }
        seconds = valid.reduce(0) { $0 + $1.seconds }
    }
}
struct DemoSession: Codable {
    var startedAt: Date
    var segmentStart: Date?
    var accumulated: Double = 0
    var goal: RunGoal
    var distance:Double? = nil
    var weightKg:Double? = nil
    var uploadOwnerID:String? = nil
    var clientRunID:UUID? = nil
    var paused: Bool { segmentStart == nil }
    func elapsed(at now: Date) -> Double { accumulated + (segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    func record(at now: Date) -> RunRecord {
        let seconds = elapsed(at: now)
        return RunRecord(
            date: startedAt,
            title: RunRecord.title(for: startedAt),
            seconds: seconds,
            kilometers: distance ?? 0,
            weightKg: weightKg,
            uploadOwnerID: uploadOwnerID,
            clientRunID: clientRunID
        )
    }
}

enum RunUploadRecoveryPersistenceFailure: Error, Equatable {
    case unreadable
    case corrupt
    case unsupportedVersion
    case invalidRecord
    case duplicateClientRunIDConflict
    case writeFailed
}

@MainActor protocol RunUploadRecoveryPersisting {
    /// Contains only newly completed, explicitly owned upload records.
    func loadPending() throws -> [RunRecord]
    /// Atomically records the immutable completion snapshot before the UI can report success.
    func savePending(_ record: RunRecord) throws
    func removePending(clientRunID: UUID) throws
}

/// Durable recovery source for owner-bound upload payloads. Legacy ownerless records stay in
/// the existing local store and are never copied into this file.
@MainActor final class FileRunUploadRecoveryPersistence: RunUploadRecoveryPersisting {
    private struct StoredRecovery: Codable {
        let version: Int
        let records: [RunRecord]
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    convenience init() {
        self.init(fileURL: Self.applicationDefaultFileURL)
    }

    static var applicationDefaultFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MovToRun/run-upload-recovery.json")
    }

    func loadPending() throws -> [RunRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RunUploadRecoveryPersistenceFailure.unreadable
        }

        do {
            let stored = try JSONDecoder().decode(StoredRecovery.self, from: data)
            guard stored.version == 1 else { throw RunUploadRecoveryPersistenceFailure.unsupportedVersion }
            guard stored.records.allSatisfy(Self.isValidRecoveryRecord),
                  Set(stored.records.compactMap { $0.uploadPayload?.clientRunID }).count == stored.records.count else {
                throw RunUploadRecoveryPersistenceFailure.corrupt
            }
            return stored.records
        } catch let failure as RunUploadRecoveryPersistenceFailure {
            throw failure
        } catch {
            throw RunUploadRecoveryPersistenceFailure.corrupt
        }
    }

    func savePending(_ record: RunRecord) throws {
        guard Self.isValidRecoveryRecord(record),
              let clientRunID = record.uploadPayload?.clientRunID else {
            throw RunUploadRecoveryPersistenceFailure.invalidRecord
        }
        var current = try loadPending()
        if let existing = current.first(where: { $0.uploadPayload?.clientRunID == clientRunID }) {
            guard existing.uploadOwnerID == record.uploadOwnerID,
                  existing.uploadPayload == record.uploadPayload else {
                throw RunUploadRecoveryPersistenceFailure.duplicateClientRunIDConflict
            }
            return
        }
        current.append(record)
        try save(current)
    }

    func removePending(clientRunID: UUID) throws {
        let current = try loadPending()
        let remaining = current.filter { $0.uploadPayload?.clientRunID != clientRunID }
        guard remaining.count != current.count else { return }
        try save(remaining)
    }

    private func save(_ records: [RunRecord]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(StoredRecovery(version: 1, records: records))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RunUploadRecoveryPersistenceFailure.writeFailed
        }
    }

    private static func isValidRecoveryRecord(_ record: RunRecord) -> Bool {
        guard let ownerID = record.uploadOwnerID,
              !ownerID.isEmpty,
              ownerID.rangeOfCharacter(from: .controlCharacters) == nil,
              let payload = record.uploadPayload else { return false }
        return record.clientRunID == payload.clientRunID
    }
}

@MainActor @Observable final class RunStore {
    private let defaults: UserDefaults
    private let uploadIdentityProvider: (any RunUploadMemberIdentityProviding)?
    private let uploadQueue: (any RunUploadEnqueueing)?
    private let uploadRecoveryPersistence: any RunUploadRecoveryPersisting
    var records: [RunRecord] = []
    var goal = RunGoal()
    var weekly = WeeklyGoal()
    var session: DemoSession?
    var storageMessage: String?
    init(
        defaults: UserDefaults = .standard,
        uploadIdentityProvider: (any RunUploadMemberIdentityProviding)? = nil,
        uploadQueue: (any RunUploadEnqueueing)? = nil,
        uploadRecoveryPersistence: (any RunUploadRecoveryPersisting)? = nil
    ) {
        self.defaults = defaults
        self.uploadIdentityProvider = uploadIdentityProvider
        self.uploadQueue = uploadQueue
        self.uploadRecoveryPersistence = uploadRecoveryPersistence ?? FileRunUploadRecoveryPersistence()
        if let data = defaults.data(forKey: "mov.demo.v1") {
            do { let state = try JSONDecoder().decode(Saved.self, from: data); records=state.records; goal=state.goal; weekly=state.weekly; session=state.session; session?.segmentStart=nil }
            catch { storageMessage = "저장한 기록을 읽지 못했습니다. 새 데이터를 저장하기 전에 앱을 다시 실행해 주세요." }
        } else {
            records=[]
            persist()
        }
        restorePendingUploadRecords()
    }
    private struct Saved: Codable { var records: [RunRecord]; var goal: RunGoal; var weekly: WeeklyGoal; var session: DemoSession? }

    private func restorePendingUploadRecords() {
        do {
            let durableRecords = try uploadRecoveryPersistence.loadPending()
            var restoredRecords = records
            var restoredSession = session
            var localStateChanged = false
            var durableClientRunIDs = Set<UUID>()

            for durableRecord in durableRecords {
                guard Self.isValidCompletedUploadRecord(durableRecord),
                      let ownerID = durableRecord.uploadOwnerID,
                      let clientRunID = durableRecord.uploadPayload?.clientRunID else {
                    throw RunUploadRecoveryPersistenceFailure.corrupt
                }
                durableClientRunIDs.insert(clientRunID)

                if let index = restoredRecords.firstIndex(where: { $0.id == durableRecord.id }) {
                    var localRecord = restoredRecords[index]
                    guard localRecord.uploadOwnerID == ownerID,
                          localRecord.clientRunID == clientRunID,
                          localRecord.uploadPayload == durableRecord.uploadPayload else {
                        // Never bind an ownerless local row to an upload snapshot.
                        throw RunUploadRecoveryPersistenceFailure.duplicateClientRunIDConflict
                    }
                    if localRecord.uploadEnqueued != true {
                        localRecord.uploadEnqueued = false
                    }
                    if localRecord != restoredRecords[index] {
                        restoredRecords[index] = localRecord
                        localStateChanged = true
                    }
                } else {
                    restoredRecords.append(durableRecord)
                    localStateChanged = true
                }

                if restoredSession?.clientRunID == clientRunID {
                    restoredSession = nil
                    localStateChanged = true
                }
            }

            // Cover pending owner-bound records created by the earlier PR60 build. This does
            // not copy or rewrite ownerless rows.
            for record in restoredRecords where record.uploadEnqueued != true {
                guard let payload = record.uploadPayload,
                      record.uploadOwnerID != nil,
                      Self.isValidCompletedUploadRecord(record),
                      !durableClientRunIDs.contains(payload.clientRunID) else { continue }
                try uploadRecoveryPersistence.savePending(record)
                durableClientRunIDs.insert(payload.clientRunID)
            }

            records = restoredRecords
            session = restoredSession
            if localStateChanged { _ = persist() }
        } catch {
            if storageMessage == nil {
                storageMessage = "업로드 기록을 복구하지 못했습니다. 저장된 기록은 보존했어요."
            }
        }
    }

    @discardableResult func persist() -> Bool {
        guard storageMessage == nil else { return false }
        do {
            defaults.set(try JSONEncoder().encode(Saved(records: records, goal: goal, weekly: weekly, session: session)), forKey: "mov.demo.v1")
            return true
        } catch {
            storageMessage = "기록을 저장하지 못했습니다."
            return false
        }
    }
    @discardableResult func start(at now: Date = Date(),weight:Double?=nil) -> Bool {
        guard session == nil, storageMessage == nil else { return false }
        let memberID = uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID)
        session = DemoSession(
            startedAt: now,
            segmentStart: now,
            goal: goal,
            weightKg: weight,
            uploadOwnerID: memberID,
            clientRunID: UUID()
        )
        guard persist() else {
            session = nil
            return false
        }
        return true
    }
    func pause(at now: Date = Date()) { guard var current=session, !current.paused else { return }; current.accumulated=current.elapsed(at:now); current.segmentStart=nil; session=current; persist() }
    func resume(at now: Date = Date()) { guard var current=session, current.paused else { return }; current.segmentStart=now; session=current; persist() }
    @discardableResult func finish(save: Bool, at now: Date = Date()) -> RunRecord? {
        guard let current=session else { return nil }
        if save && (current.elapsed(at:now)<=0 || storageMessage != nil) { return nil }
        var record=current.record(at:now)
        if save {
            record.uploadPayload = Self.uploadPayload(for: current, record: record, endedAt: now)
            record.uploadEnqueued = record.uploadPayload == nil ? nil : false
        }

        if save, let clientRunID = record.uploadPayload?.clientRunID {
            // Persist the still-active session snapshot first, then write the completed upload
            // recovery source. If the atomic source write fails, the run remains active and no
            // completed record can be reported to the UI.
            guard persist() else { return nil }
            do {
                let durableRecords = try uploadRecoveryPersistence.loadPending()
                if let existing = durableRecords.first(where: { $0.uploadPayload?.clientRunID == clientRunID }) {
                    guard existing.uploadOwnerID == record.uploadOwnerID,
                          existing.uploadPayload == record.uploadPayload,
                          Self.isValidCompletedUploadRecord(existing) else {
                        throw RunUploadRecoveryPersistenceFailure.duplicateClientRunIDConflict
                    }
                    // Reuse a completion snapshot already written before a prior local-store
                    // failure; the clientRunID always retains one immutable payload.
                    record = existing
                } else {
                    try uploadRecoveryPersistence.savePending(record)
                }
            } catch {
                storageMessage = "완료 기록을 안전하게 저장하지 못했습니다. 러닝 상태를 유지했어요."
                return nil
            }
        }

        let previousRecords = records
        if save, !records.contains(where: { $0.id == record.id }) { records.insert(record,at:0) }
        session=nil
        guard persist() else {
            records = previousRecords
            session = current
            return nil
        }
        return save ? record : nil
    }

    /// Saves locally first. If queue persistence fails or the app stops before enqueue,
    /// the immutable payload on the completed record remains available for recovery.
    @discardableResult func finishAndEnqueue(save: Bool, at now: Date = Date()) async -> RunRecord? {
        guard let record = finish(save: save, at: now) else { return nil }
        guard save,
              let ownerID = record.uploadOwnerID,
              let payload = record.uploadPayload,
              let uploadQueue else { return record }
        do {
            try await uploadQueue.enqueueRunUpload(payload, ownerID: ownerID)
            if markUploadEnqueued(recordID: record.id) {
                try? uploadRecoveryPersistence.removePending(clientRunID: payload.clientRunID)
            }
        } catch {
            // The durable local payload remains pending for a later recovery attempt.
        }
        return records.first(where: { $0.id == record.id }) ?? record
    }

    /// Re-enqueues completed snapshots after launch. The outbox de-duplicates the
    /// same owner/clientRunId/payload, and this method never drains or sends requests.
    func recoverPendingRunUploads() async {
        guard let uploadQueue else { return }
        let snapshots: [RunRecord]
        do {
            var durableRecords = try uploadRecoveryPersistence.loadPending()
            var durableIDs = Set(durableRecords.compactMap { $0.uploadPayload?.clientRunID })
            for record in records where record.uploadEnqueued != true {
                guard let payload = record.uploadPayload,
                      record.uploadOwnerID != nil,
                      Self.isValidCompletedUploadRecord(record),
                      !durableIDs.contains(payload.clientRunID) else { continue }
                try uploadRecoveryPersistence.savePending(record)
                durableIDs.insert(payload.clientRunID)
            }
            durableRecords = try uploadRecoveryPersistence.loadPending()
            snapshots = durableRecords
        } catch {
            storageMessage = "업로드 기록을 복구하지 못했습니다. 저장된 기록은 보존했어요."
            return
        }

        for durableRecord in snapshots {
            guard Self.isValidCompletedUploadRecord(durableRecord),
                  let ownerID = durableRecord.uploadOwnerID,
                  let payload = durableRecord.uploadPayload else {
                storageMessage = "업로드 기록을 복구하지 못했습니다. 저장된 기록은 보존했어요."
                return
            }

            if records.first(where: { $0.id == durableRecord.id })?.uploadEnqueued == true {
                try? uploadRecoveryPersistence.removePending(clientRunID: payload.clientRunID)
                continue
            }

            do {
                try await uploadQueue.enqueueRunUpload(payload, ownerID: ownerID)
                if records.contains(where: { $0.id == durableRecord.id }) {
                    if markUploadEnqueued(recordID: durableRecord.id) {
                        try? uploadRecoveryPersistence.removePending(clientRunID: payload.clientRunID)
                    }
                } else {
                    // The outbox has the durable payload, so the sidecar can be retired even if
                    // the user removed the local history row after its completion was saved.
                    try? uploadRecoveryPersistence.removePending(clientRunID: payload.clientRunID)
                }
            } catch {
                // Leave the atomic recovery source pending so a later launch can retry it.
            }
        }
    }

    @discardableResult private func markUploadEnqueued(recordID: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              records[index].uploadPayload != nil else { return false }
        let previous = records[index]
        records[index].uploadEnqueued = true
        if !persist() {
            records[index] = previous
            return false
        }
        return true
    }

    private static func validMemberID(_ memberID: String) -> String? {
        guard !memberID.isEmpty,
              memberID.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return memberID
    }

    private static func isValidCompletedUploadRecord(_ record: RunRecord) -> Bool {
        guard let ownerID = record.uploadOwnerID,
              validMemberID(ownerID) != nil,
              let clientRunID = record.clientRunID,
              let payload = record.uploadPayload else { return false }
        return clientRunID == payload.clientRunID
    }

    private static func uploadPayload(for session: DemoSession, record: RunRecord, endedAt: Date) -> RunUploadPayload? {
        guard let ownerID = session.uploadOwnerID,
              validMemberID(ownerID) != nil,
              let clientRunID = session.clientRunID,
              let measuredKilometers = session.distance,
              measuredKilometers.isFinite,
              measuredKilometers >= 0,
              session.startedAt <= endedAt,
              record.seconds.isFinite,
              record.seconds >= 0 else { return nil }

        let meters = measuredKilometers * 1_000
        guard meters.isFinite else { return nil }
        let wholeMeters = meters.rounded()
        // The backend accepts integer meters. Do not invent a rounding policy for
        // fractional-meter values that this RunStore cannot represent exactly.
        guard abs(meters - wholeMeters) <= max(1, abs(meters)) * 1e-12,
              let distanceMeters = Int(exactly: wholeMeters) else { return nil }

        let wholeSeconds = record.seconds.rounded(.towardZero)
        guard let movingSeconds = Int(exactly: wholeSeconds) else { return nil }

        return RunUploadPayload(
            clientRunID: clientRunID,
            startedAt: session.startedAt,
            endedAt: endedAt,
            movingSeconds: movingSeconds,
            distanceMeters: distanceMeters,
            title: record.title,
            memo: record.memo,
            points: [],
            pauses: []
        )
    }
    func update(_ record: RunRecord) {
        guard let index=records.firstIndex(where:{$0.id==record.id}) else{return}
        var updated=record
        let persisted=records[index]
        updated.uploadOwnerID=persisted.uploadOwnerID
        updated.clientRunID=persisted.clientRunID
        updated.uploadPayload=persisted.uploadPayload
        updated.uploadEnqueued=persisted.uploadEnqueued
        records[index]=updated
        persist()
    }
    func delete(_ id: UUID) { records.removeAll{$0.id==id}; persist() }
    func weeklyRecords(asOf now: Date = WReviewClock.now) -> [RunRecord] { var calendar=Calendar(identifier:.iso8601);calendar.timeZone = .current;let interval=calendar.dateInterval(of:.weekOfYear,for:now)!;return records.filter{interval.contains($0.date) && $0.isValid} }
    var weeklyRecords: [RunRecord] { weeklyRecords(asOf: WReviewClock.now) }
    var weeklyDistance: Double { weeklyRecords.reduce(0){$0+$1.kilometers} }
    var weeklySeconds: Double { weeklyRecords.reduce(0){$0+$1.seconds} }
    var totalDistance: Double { records.filter(\.isValid).reduce(0){$0+$1.kilometers} }
    var activityDays: Int {
        let groups=Dictionary(grouping: records.filter(\.isValid)) { Calendar.current.startOfDay(for:$0.date) }
        return groups.values.filter { $0.reduce(0){$0+$1.seconds} >= 240 && $0.reduce(0){$0+$1.kilometers} >= 1 }.count
    }
    func averageDistance(asOf now: Date) -> Double {
        let start=Calendar.current.date(byAdding:.month,value:-1,to:now) ?? now
        let recent=records.filter{$0.isValid && $0.date >= start && $0.date <= now}
        return recent.isEmpty ? 0 : recent.reduce(0){$0+$1.kilometers}/Double(recent.count)
    }
    var averageDistance: Double { averageDistance(asOf: Date()) }
    var tier: String {
        if totalDistance >= 300 && activityDays >= 50 { return "마스터" }
        if totalDistance >= 100 && activityDays >= 20 { return "도전" }
        if totalDistance >= 30 && activityDays >= 10 { return "열정" }
        if totalDistance >= 10 && activityDays >= 7 { return "새싹" }
        return records.contains(where: \.isValid) ? "시작" : "등급 없음"
    }
}
