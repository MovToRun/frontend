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

enum RunStoreOwnedRecordsPersistenceFailure: Error, Equatable {
    case unreadable
    case corrupt
    case unsupportedVersion
    case invalidRecord
    case duplicateRecordID
    case writeFailed
}

enum RunStoreOwnedRecordsSnapshot {
    case missing
    case legacyPending([RunRecord])
    case canonical([RunRecord])

    var canonicalRecords: [RunRecord] {
        switch self {
        case .missing: return []
        case .legacyPending(let records), .canonical(let records): return records
        }
    }
}

@MainActor protocol RunStoreOwnedRecordsPersisting {
    func loadSnapshot() throws -> RunStoreOwnedRecordsSnapshot
    /// Replaces the canonical set of owner-assigned local records atomically.
    func saveCanonical(_ records: [RunRecord]) throws
}

/// Canonical local source for owner-assigned records. Ownerless history remains in the
/// existing local store and is never copied into this file.
@MainActor final class FileRunStoreOwnedRecordsPersistence: RunStoreOwnedRecordsPersisting {
    private struct StoredOwnedRecords: Codable {
        let version: Int
        let records: [RunRecord]
    }

    /// Version 1 was the short-lived enqueue-recovery file used by the preceding PR60 build.
    private struct LegacyRecovery: Codable {
        let version: Int
        let records: [RunRecord]
    }

    private let fileURL: URL
    private let legacyRecoveryFileURL: URL?

    init(fileURL: URL, legacyRecoveryFileURL: URL? = nil) {
        self.fileURL = fileURL.standardizedFileURL
        self.legacyRecoveryFileURL = legacyRecoveryFileURL?.standardizedFileURL
    }

    convenience init() {
        let directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MovToRun", isDirectory: true)
        self.init(
            fileURL: directory.appendingPathComponent("owned-run-records.json"),
            legacyRecoveryFileURL: directory.appendingPathComponent("run-upload-recovery.json")
        )
    }

    func loadSnapshot() throws -> RunStoreOwnedRecordsSnapshot {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw RunStoreOwnedRecordsPersistenceFailure.unreadable
            }
            do {
                let stored = try JSONDecoder().decode(StoredOwnedRecords.self, from: data)
                guard stored.version == 1 else { throw RunStoreOwnedRecordsPersistenceFailure.unsupportedVersion }
                guard Self.hasValidUniqueOwnedRecords(stored.records) else {
                    throw RunStoreOwnedRecordsPersistenceFailure.corrupt
                }
                removeLegacyRecoveryFileIfPresent()
                return .canonical(stored.records)
            } catch let failure as RunStoreOwnedRecordsPersistenceFailure {
                throw failure
            } catch {
                throw RunStoreOwnedRecordsPersistenceFailure.corrupt
            }
        }

        guard let legacyRecoveryFileURL,
              FileManager.default.fileExists(atPath: legacyRecoveryFileURL.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: legacyRecoveryFileURL)
        } catch {
            throw RunStoreOwnedRecordsPersistenceFailure.unreadable
        }
        do {
            let stored = try JSONDecoder().decode(LegacyRecovery.self, from: data)
            guard stored.version == 1 else { throw RunStoreOwnedRecordsPersistenceFailure.unsupportedVersion }
            guard stored.records.allSatisfy(Self.isValidLegacyPendingRecord),
                  Set(stored.records.compactMap { $0.uploadPayload?.clientRunID }).count == stored.records.count else {
                throw RunStoreOwnedRecordsPersistenceFailure.corrupt
            }
            return .legacyPending(stored.records)
        } catch let failure as RunStoreOwnedRecordsPersistenceFailure {
            throw failure
        } catch {
            throw RunStoreOwnedRecordsPersistenceFailure.corrupt
        }
    }

    func saveCanonical(_ records: [RunRecord]) throws {
        guard Self.hasValidUniqueOwnedRecords(records) else {
            throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(StoredOwnedRecords(version: 1, records: records))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RunStoreOwnedRecordsPersistenceFailure.writeFailed
        }
        removeLegacyRecoveryFileIfPresent()
    }

    private func removeLegacyRecoveryFileIfPresent() {
        guard let legacyRecoveryFileURL,
              FileManager.default.fileExists(atPath: legacyRecoveryFileURL.path) else { return }
        try? FileManager.default.removeItem(at: legacyRecoveryFileURL)
    }

    private static func hasValidUniqueOwnedRecords(_ records: [RunRecord]) -> Bool {
        var recordIDs = Set<UUID>()
        var clientRunIDs = Set<UUID>()
        for record in records {
            guard isValidOwnedRecord(record), recordIDs.insert(record.id).inserted else { return false }
            if let clientRunID = record.clientRunID, !clientRunIDs.insert(clientRunID).inserted { return false }
        }
        return true
    }

    private static func isValidLegacyPendingRecord(_ record: RunRecord) -> Bool {
        guard isValidOwnedRecord(record), let payload = record.uploadPayload else { return false }
        return record.clientRunID == payload.clientRunID
    }

    private static func isValidOwnedRecord(_ record: RunRecord) -> Bool {
        guard let ownerID = record.uploadOwnerID,
              !ownerID.isEmpty,
              ownerID.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
        guard let payload = record.uploadPayload else { return true }
        return record.clientRunID == payload.clientRunID
    }
}

enum RunStoreUploadDrainResult: Equatable {
    case authenticationUnavailable
    case drainerUnavailable
    case alreadyRunning
    case completed(uploadedCount: Int, deletedCount: Int)
    case permanentFailure(count: Int, uploadedCount: Int, deletedCount: Int)
    case retryableFailure(
        clientRunID: UUID?,
        code: String,
        uploadedCount: Int,
        deletedCount: Int,
        permanentFailureCount: Int
    )
    case retryableAcknowledgementFailure
    case ownerMismatch
    case accountChanged
    case cancelled
    case ignored
    case storageFailure
}

@MainActor @Observable final class RunStore {
    private let defaults: UserDefaults
    private let uploadIdentityProvider: (any RunUploadMemberIdentityProviding)?
    private let uploadQueue: (any RunUploadEnqueueing)?
    private let uploadDrainer: (any RunUploadDraining)?
    private let ownedRecordsPersistence: any RunStoreOwnedRecordsPersisting
    private var uploadDrainOperationID: UUID?
    private var uploadDrainGeneration: UInt64 = 0
    private var uploadDrainTask: Task<RunUploadDrainReport, Error>?
    var records: [RunRecord] = []
    var goal = RunGoal()
    var weekly = WeeklyGoal()
    var session: DemoSession?
    var storageMessage: String?
    init(
        defaults: UserDefaults = .standard,
        uploadIdentityProvider: (any RunUploadMemberIdentityProviding)? = nil,
        uploadQueue: (any RunUploadEnqueueing)? = nil,
        uploadDrainer: (any RunUploadDraining)? = nil,
        ownedRecordsPersistence: (any RunStoreOwnedRecordsPersisting)? = nil
    ) {
        self.defaults = defaults
        self.uploadIdentityProvider = uploadIdentityProvider
        self.uploadQueue = uploadQueue
        self.uploadDrainer = uploadDrainer
        self.ownedRecordsPersistence = ownedRecordsPersistence ?? FileRunStoreOwnedRecordsPersistence()
        if let data = defaults.data(forKey: "mov.demo.v1") {
            do { let state = try JSONDecoder().decode(Saved.self, from: data); records=state.records; goal=state.goal; weekly=state.weekly; session=state.session; session?.segmentStart=nil }
            catch { storageMessage = "저장한 기록을 읽지 못했습니다. 새 데이터를 저장하기 전에 앱을 다시 실행해 주세요." }
        } else {
            records=[]
        }
        restoreOwnedRecordSnapshot()
    }
    private struct Saved: Codable { var records: [RunRecord]; var goal: RunGoal; var weekly: WeeklyGoal; var session: DemoSession? }

    private func restoreOwnedRecordSnapshot() {
        do {
            let snapshot = try ownedRecordsPersistence.loadSnapshot()
            let defaultOwnedRecords = records.filter { $0.uploadOwnerID != nil }
            let canonicalRecords: [RunRecord]
            switch snapshot {
            case .missing:
                canonicalRecords = defaultOwnedRecords
                try Self.validateOwnedRecordSet(canonicalRecords)
                try Self.validateNoOwnerlessIdentityCollision(canonicalRecords, among: records)
                if !canonicalRecords.isEmpty { try ownedRecordsPersistence.saveCanonical(canonicalRecords) }
            case .legacyPending(let pendingRecords):
                canonicalRecords = try Self.mergeLegacyPendingRecords(pendingRecords, with: defaultOwnedRecords)
                try Self.validateOwnedRecordSet(canonicalRecords)
                try Self.validateNoOwnerlessIdentityCollision(canonicalRecords, among: records)
                if !canonicalRecords.isEmpty { try ownedRecordsPersistence.saveCanonical(canonicalRecords) }
            case .canonical(let records):
                canonicalRecords = records
                try Self.validateOwnedRecordSet(canonicalRecords)
            }

            try Self.validateNoOwnerlessIdentityCollision(canonicalRecords, among: records)
            var reconciledRecords: [RunRecord] = []
            let canonicalByID = Dictionary(uniqueKeysWithValues: canonicalRecords.map { ($0.id, $0) })
            var includedIDs = Set<UUID>()
            for localRecord in records {
                if localRecord.uploadOwnerID == nil {
                    reconciledRecords.append(localRecord)
                } else if let canonicalRecord = canonicalByID[localRecord.id] {
                    reconciledRecords.append(canonicalRecord)
                    includedIDs.insert(canonicalRecord.id)
                }
            }
            for canonicalRecord in canonicalRecords where !includedIDs.contains(canonicalRecord.id) {
                reconciledRecords.append(canonicalRecord)
            }

            var restoredSession = session
            let completedClientRunIDs = Set(canonicalRecords.compactMap(\.clientRunID))
            let sessionWasCleared = restoredSession?.clientRunID.map(completedClientRunIDs.contains) == true
            if let activeClientRunID = restoredSession?.clientRunID,
               completedClientRunIDs.contains(activeClientRunID) {
                restoredSession = nil
            }
            records = reconciledRecords
            session = restoredSession
            if sessionWasCleared || snapshotNeedsCacheRefresh(snapshot, originalRecords: defaultOwnedRecords, canonicalRecords: canonicalRecords) {
                _ = persist()
            }
        } catch {
            if storageMessage == nil {
                storageMessage = "저장한 회원 기록을 복구하지 못했습니다. 원본 파일을 보존했어요."
            }
        }
    }

    private func snapshotNeedsCacheRefresh(
        _ snapshot: RunStoreOwnedRecordsSnapshot,
        originalRecords: [RunRecord],
        canonicalRecords: [RunRecord]
    ) -> Bool {
        switch snapshot {
        case .missing: return !canonicalRecords.isEmpty
        case .legacyPending: return true
        case .canonical: return originalRecords != canonicalRecords
        }
    }

    private static func mergeLegacyPendingRecords(_ pendingRecords: [RunRecord], with localOwnedRecords: [RunRecord]) throws -> [RunRecord] {
        var merged = localOwnedRecords
        for pending in pendingRecords {
            guard isValidOwnedSnapshotRecord(pending),
                  let clientRunID = pending.clientRunID,
                  let payload = pending.uploadPayload else {
                throw RunStoreOwnedRecordsPersistenceFailure.corrupt
            }
            if let index = merged.firstIndex(where: { $0.id == pending.id }) {
                let local = merged[index]
                guard local.uploadOwnerID == pending.uploadOwnerID,
                      local.clientRunID == clientRunID,
                      local.uploadPayload == payload else {
                    throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
                }
                // Keep user-edited local metadata and its enqueue marker when available.
                continue
            }
            guard !merged.contains(where: { $0.clientRunID == clientRunID }) else {
                throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
            }
            merged.append(pending)
        }
        return merged
    }

    private static func validateNoOwnerlessIdentityCollision(_ ownedRecords: [RunRecord], among records: [RunRecord]) throws {
        let ownerlessIDs = Set(records.filter { $0.uploadOwnerID == nil }.map(\.id))
        guard ownedRecords.allSatisfy({ !ownerlessIDs.contains($0.id) }) else {
            throw RunStoreOwnedRecordsPersistenceFailure.duplicateRecordID
        }
    }

    private static func validateOwnedRecordSet(_ records: [RunRecord]) throws {
        var recordIDs = Set<UUID>()
        var clientRunIDs = Set<UUID>()
        for record in records {
            guard let ownerID = record.uploadOwnerID,
                  validMemberID(ownerID) != nil,
                  recordIDs.insert(record.id).inserted else {
                throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
            }
            if let clientRunID = record.clientRunID,
               !clientRunIDs.insert(clientRunID).inserted {
                throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
            }
            if let payload = record.uploadPayload,
               record.clientRunID != payload.clientRunID {
                throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
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
            guard record.seconds.isFinite,
                  record.kilometers.isFinite,
                  record.weightKg?.isFinite != false else {
                storageMessage = "측정값을 안전하게 저장하지 못했습니다. 러닝 상태를 유지했어요."
                return nil
            }
        }

        if save, let ownerID = record.uploadOwnerID {
            do {
                var canonicalRecords = try ownedRecordsPersistence.loadSnapshot().canonicalRecords
                if let clientRunID = record.clientRunID,
                   let existingIndex = canonicalRecords.firstIndex(where: { $0.clientRunID == clientRunID }) {
                    let existing = canonicalRecords[existingIndex]
                    guard existing.uploadOwnerID == ownerID,
                          existing.uploadPayload == record.uploadPayload,
                          Self.isValidOwnedSnapshotRecord(existing) else {
                        throw RunStoreOwnedRecordsPersistenceFailure.invalidRecord
                    }
                    record = existing
                } else {
                    canonicalRecords.removeAll { $0.id == record.id }
                    canonicalRecords.insert(record, at: 0)
                    try ownedRecordsPersistence.saveCanonical(canonicalRecords)
                }
            } catch {
                storageMessage = "완료 기록을 안전하게 저장하지 못했습니다. 러닝 상태를 유지했어요."
                return nil
            }
        }

        let previousRecords = records
        if save, !records.contains(where: { $0.id == record.id }) { records.insert(record,at:0) }
        session=nil
        if save, record.uploadOwnerID != nil {
            // The canonical file is the durability boundary. UserDefaults is refreshed only as
            // a display/session cache and cannot roll a committed completion back.
            _ = persist()
        } else if !persist() {
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
            _ = markUploadEnqueued(recordID: record.id)
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
            snapshots = try ownedRecordsPersistence.loadSnapshot().canonicalRecords.filter {
                $0.uploadEnqueued != true && $0.uploadPayload != nil
            }
        } catch {
            storageMessage = "업로드 기록을 복구하지 못했습니다. 저장된 기록은 보존했어요."
            return
        }

        for durableRecord in snapshots {
            guard Self.isValidOwnedSnapshotRecord(durableRecord),
                  let ownerID = durableRecord.uploadOwnerID,
                  let payload = durableRecord.uploadPayload else {
                storageMessage = "업로드 기록을 복구하지 못했습니다. 저장된 기록은 보존했어요."
                return
            }

            do {
                try await uploadQueue.enqueueRunUpload(payload, ownerID: ownerID)
                if records.contains(where: { $0.id == durableRecord.id }) {
                    _ = markUploadEnqueued(recordID: durableRecord.id)
                }
            } catch {
                // Leave the atomic recovery source pending so a later launch can retry it.
            }
        }
    }

    /// Drains the existing outbox only when an authenticated stable member ID is available.
    /// The caller must invoke this explicitly; completion records remain canonical after drain.
    func drainPendingRunUploads() async -> RunStoreUploadDrainResult {
        guard uploadDrainOperationID == nil else { return .alreadyRunning }
        guard let ownerID = uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID) else {
            return .authenticationUnavailable
        }
        guard let uploadDrainer else { return .drainerUnavailable }

        let operationID = UUID()
        let generation = uploadDrainGeneration
        uploadDrainOperationID = operationID
        let task = Task { try await uploadDrainer.drain(ownerID: ownerID) }
        uploadDrainTask = task

        let drainResult: Result<RunUploadDrainReport, Error> = await withTaskCancellationHandler {
            do { return .success(try await task.value) }
            catch { return .failure(error) }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancelPendingRunUploadDrain(operationID: operationID) }
        }

        if Task.isCancelled {
            cancelPendingRunUploadDrain(operationID: operationID)
            return .ignored
        }
        guard uploadDrainOperationID == operationID,
              uploadDrainGeneration == generation else { return .ignored }

        uploadDrainOperationID = nil
        uploadDrainTask = nil
        guard uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID) == ownerID else {
            return .ignored
        }

        switch drainResult {
        case .success(let report):
            return Self.uploadDrainResult(for: report)
        case .failure(let error):
            if error is CancellationError { return .cancelled }
            if let failure = error as? RunUploadOutboxPersistenceFailure, failure == .writeFailed {
                return .retryableAcknowledgementFailure
            }
            return .storageFailure
        }
    }

    /// Call on logout, account transition, or cancellation. A later response from this
    /// operation cannot be reflected by its caller, even if it ignores task cancellation.
    func cancelPendingRunUploadDrain() {
        cancelPendingRunUploadDrain(operationID: uploadDrainOperationID)
    }

    private func cancelPendingRunUploadDrain(operationID: UUID?) {
        guard let operationID, uploadDrainOperationID == operationID else { return }
        uploadDrainGeneration &+= 1
        uploadDrainOperationID = nil
        let task = uploadDrainTask
        uploadDrainTask = nil
        task?.cancel()
    }

    private static func uploadDrainResult(for report: RunUploadDrainReport) -> RunStoreUploadDrainResult {
        switch report.stopReason {
        case .finished:
            if report.terminalCount > 0 {
                return .permanentFailure(
                    count: report.terminalCount,
                    uploadedCount: report.uploadedCount,
                    deletedCount: report.deletedCount
                )
            }
            return .completed(uploadedCount: report.uploadedCount, deletedCount: report.deletedCount)
        case .retryLater(let clientRunID, let code):
            return .retryableFailure(
                clientRunID: clientRunID,
                code: code,
                uploadedCount: report.uploadedCount,
                deletedCount: report.deletedCount,
                permanentFailureCount: report.terminalCount
            )
        case .busy:
            return .alreadyRunning
        case .sessionUnavailable:
            return .authenticationUnavailable
        case .ownerMismatch:
            if report.terminalCount > 0 {
                return .permanentFailure(
                    count: report.terminalCount,
                    uploadedCount: report.uploadedCount,
                    deletedCount: report.deletedCount
                )
            }
            return .ownerMismatch
        case .accountChanged:
            return .accountChanged
        case .cancelled:
            return .cancelled
        }
    }

    @discardableResult private func markUploadEnqueued(recordID: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              records[index].uploadPayload != nil else { return false }
        let previous = records[index]
        records[index].uploadEnqueued = true
        do {
            try ownedRecordsPersistence.saveCanonical(records.filter { $0.uploadOwnerID != nil })
        } catch {
            records[index] = previous
            storageMessage = "업로드 상태를 저장하지 못했습니다. 완료 기록은 보존했어요."
            return false
        }
        if !persist() {
            // The canonical owner record is already committed. Do not roll it back because
            // the UserDefaults cache could not be refreshed.
        }
        return true
    }

    private static func validMemberID(_ memberID: String) -> String? {
        guard !memberID.isEmpty,
              memberID.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return memberID
    }

    private static func isValidOwnedSnapshotRecord(_ record: RunRecord) -> Bool {
        guard let ownerID = record.uploadOwnerID,
              validMemberID(ownerID) != nil,
              record.clientRunID != nil || record.uploadPayload == nil else { return false }
        guard let payload = record.uploadPayload else { return true }
        return record.clientRunID == payload.clientRunID
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
        guard storageMessage == nil else { return }
        guard let index=records.firstIndex(where:{$0.id==record.id}) else{return}
        var updated=record
        let persisted=records[index]
        updated.uploadOwnerID=persisted.uploadOwnerID
        updated.clientRunID=persisted.clientRunID
        updated.uploadPayload=persisted.uploadPayload
        updated.uploadEnqueued=persisted.uploadEnqueued
        if persisted.uploadOwnerID != nil {
            var nextOwnedRecords = records.filter { $0.uploadOwnerID != nil }
            guard let ownedIndex = nextOwnedRecords.firstIndex(where: { $0.id == persisted.id }) else { return }
            nextOwnedRecords[ownedIndex] = updated
            do {
                try ownedRecordsPersistence.saveCanonical(nextOwnedRecords)
            } catch {
                storageMessage = "회원 기록을 안전하게 수정하지 못했습니다. 기존 기록을 보존했어요."
                return
            }
        }
        records[index]=updated
        _ = persist()
    }
    func delete(_ id: UUID) {
        guard storageMessage == nil,
              let record = records.first(where: { $0.id == id }) else { return }
        if record.uploadOwnerID != nil {
            let nextOwnedRecords = records.filter { $0.uploadOwnerID != nil && $0.id != id }
            do {
                try ownedRecordsPersistence.saveCanonical(nextOwnedRecords)
            } catch {
                storageMessage = "회원 기록을 안전하게 삭제하지 못했습니다. 기존 기록을 보존했어요."
                return
            }
        }
        records.removeAll { $0.id == id }
        _ = persist()
    }
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
