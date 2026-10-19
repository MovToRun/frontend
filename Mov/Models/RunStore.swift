import Foundation
import Observation
@preconcurrency import CoreLocation
import Network

struct RunLocationFix: Equatable, Sendable {
    var recordedAt: Date
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double
    var altitudeMeters: Double?
    var speedMetersPerSecond: Double?
}

@MainActor protocol RunLocationCapturing: AnyObject {
    var onFix: ((RunLocationFix) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor final class CoreLocationRunCapture: NSObject, @preconcurrency CLLocationManagerDelegate, RunLocationCapturing {
    private let manager = CLLocationManager()
    private var active = false
    var onFix: ((RunLocationFix) -> Void)?
    var onStatus: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        active = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            onStatus?("위치 측정 중")
        case .notDetermined:
            onStatus?("위치 권한을 확인해 주세요")
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            onStatus?("위치 권한이 없어 거리 측정을 할 수 없어요")
        @unknown default:
            onStatus?("위치 상태를 확인할 수 없어요")
        }
    }

    func stop() {
        active = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard active else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            onStatus?("위치 측정 중")
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            onStatus?("위치 권한이 없어 거리 측정을 할 수 없어요")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active else { return }
        for location in locations {
            onFix?(RunLocationFix(
                recordedAt: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                speedMetersPerSecond: location.speed >= 0 ? location.speed : nil
            ))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onStatus?("GPS 신호를 받지 못했어요. 다시 시도할 수 있어요")
    }
}

@MainActor @Observable final class RunUploadNetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.movtorun.run-upload-network")
    private var started = false
    var isOnline = false
    var onReconnect: (() -> Void)?

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                if online && !wasOnline { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

enum RunServerJudgement: String, Codable, Equatable {
    case pending
    case valid
    case invalid
}

struct RunLocalSplit: Equatable, Identifiable {
    var id: Int
    var distanceMeters: Double
    var seconds: Double
    var pace: String {
        guard distanceMeters > 0 else { return "—" }
        let value = max(0, Int(seconds / (distanceMeters / 1_000)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Supplies the authenticated member identity at run start. UI-only account scopes
/// are deliberately not accepted by this boundary.
@MainActor protocol RunUploadMemberIdentityProviding {
    func currentAuthenticatedMemberID() -> String?
}

/// RunStore receives only the stable ID mapped from an accepted server session.
/// A screen's fixture/account scope is never used as a member identity.
@MainActor final class AuthSessionRunUploadMemberIdentityProvider: RunUploadMemberIdentityProviding {
    private let sessionStore: any AuthSessionStoring

    init(sessionStore: any AuthSessionStoring) {
        self.sessionStore = sessionStore
    }

    func currentAuthenticatedMemberID() -> String? {
        guard let snapshot = try? sessionStore.loadSnapshot(),
              AuthSessionSnapshot.isCanonicalMemberID(snapshot.memberID) else { return nil }
        return snapshot.memberID
    }
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
    var routePoints:[RunUploadPoint]? = nil
    var pauseIntervals:[RunUploadPause]? = nil
    var serverJudgement:RunServerJudgement? = nil
    var serverRunID:String? = nil
    var serverVersion:Int64? = nil
    var serverVerdictReason:String? = nil
    var serverValidDistanceMeters:Int64? = nil
    var serverValidSeconds:Int64? = nil
    var serverPaceSecondsPerKm:Int64? = nil
    var serverUpdatedAt:Date? = nil
    var displayedKilometers:Double {
        serverJudgement == .valid ? Double(serverValidDistanceMeters ?? 0)/1_000 : kilometers
    }
    var displayedSeconds:Double {
        serverJudgement == .valid ? Double(serverValidSeconds ?? 0) : seconds
    }
    var statisticalKilometers:Double {
        switch serverJudgement {
        case .valid: Double(serverValidDistanceMeters ?? 0)/1_000
        case .invalid, .pending: 0
        case nil: kilometers
        }
    }
    var statisticalSeconds:Double {
        switch serverJudgement {
        case .valid: Double(serverValidSeconds ?? 0)
        case .invalid, .pending: 0
        case nil: seconds
        }
    }
    var caloriesText:String {guard isValid || serverJudgement == .pending else{return "0 kcal"};guard let weightKg else{return "—"};return "약 \(Int((weightKg*displayedKilometers).rounded())) kcal"}
    var isValid: Bool {
        switch serverJudgement {
        case .valid: true
        case .pending, .invalid: false
        case nil: kilometers > 0
        }
    }
    var hasMeasuredDistance:Bool {kilometers > 0}
    var pace: String {
        if serverJudgement == .valid, let serverPaceSecondsPerKm, let value=Int(exactly:serverPaceSecondsPerKm) {
            return String(format:"%d:%02d",value/60,value%60)
        }
        guard displayedKilometers>0 else{return "0:00"}
        let value=max(0,Int(displayedSeconds/displayedKilometers))
        return String(format:"%d:%02d",value/60,value%60)
    }
    var provisionalSplits:[RunLocalSplit] {
        guard let routePoints, routePoints.count > 1 else { return [] }
        var accumulatedDistance = 0.0
        var accumulatedSeconds = 0.0
        var result:[RunLocalSplit] = []
        for pair in zip(routePoints, routePoints.dropFirst()) {
            let distance = Self.distanceMeters(from: pair.0, to: pair.1)
            guard distance.isFinite, distance > 0 else { continue }
            var seconds = max(0, pair.1.recordedAt.timeIntervalSince(pair.0.recordedAt))
            for pause in pauseIntervals ?? [] {
                let overlapStart = max(pair.0.recordedAt, pause.startedAt)
                let overlapEnd = min(pair.1.recordedAt, pause.endedAt)
                if overlapEnd > overlapStart { seconds -= overlapEnd.timeIntervalSince(overlapStart) }
            }
            accumulatedDistance += distance
            accumulatedSeconds += max(0, seconds)
            if accumulatedDistance >= 1_000 {
                result.append(RunLocalSplit(id: result.count, distanceMeters: accumulatedDistance, seconds: accumulatedSeconds))
                accumulatedDistance = 0
                accumulatedSeconds = 0
            }
        }
        if accumulatedDistance > 0 {
            result.append(RunLocalSplit(id: result.count, distanceMeters: accumulatedDistance, seconds: accumulatedSeconds))
        }
        return result
    }
    private static func distanceMeters(from first:RunUploadPoint, to second:RunUploadPoint)->Double {
        let radius = 6_371_000.0
        let lat1 = first.latitude * .pi / 180
        let lat2 = second.latitude * .pi / 180
        let dLat = (second.latitude - first.latitude) * .pi / 180
        let dLon = (second.longitude - first.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
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
        kilometers = valid.reduce(0) { $0 + $1.statisticalKilometers }
        seconds = valid.reduce(0) { $0 + $1.statisticalSeconds }
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
    var routePoints:[RunUploadPoint]? = nil
    var pauseIntervals:[RunUploadPause]? = nil
    var activePauseStartedAt:Date? = nil
    var locationCaptureEnabled:Bool? = nil
    var paused: Bool { segmentStart == nil }
    var maximumEndedAt:Date { startedAt.addingTimeInterval(21_600) }
    func elapsed(at now: Date) -> Double { accumulated + (segmentStart.map { max(0, min(now, maximumEndedAt).timeIntervalSince($0)) } ?? 0) }
    func record(at now: Date) -> RunRecord {
        let seconds = elapsed(at: now)
        return RunRecord(
            date: startedAt,
            title: RunRecord.title(for: startedAt),
            seconds: seconds,
            kilometers: distance ?? 0,
            weightKg: weightKg,
            uploadOwnerID: uploadOwnerID,
            clientRunID: clientRunID,
            routePoints: routePoints,
            pauseIntervals: pauseIntervals,
            serverJudgement: locationCaptureEnabled == true ? .pending : nil
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
    private let locationCapture: (any RunLocationCapturing)?
    private var uploadDrainOperationID: UUID?
    private var uploadDrainGeneration: UInt64 = 0
    private var uploadDrainTask: Task<RunUploadDrainReport, Error>?
    var records: [RunRecord] = []
    var goal = RunGoal()
    var weekly = WeeklyGoal()
    var session: DemoSession?
    var storageMessage: String?
    var locationMessage = "위치 확인 중"
    var uploadMessage: String?
    var uploadNeedsRetry = false
    init(
        defaults: UserDefaults = .standard,
        uploadIdentityProvider: (any RunUploadMemberIdentityProviding)? = nil,
        uploadQueue: (any RunUploadEnqueueing)? = nil,
        uploadDrainer: (any RunUploadDraining)? = nil,
        ownedRecordsPersistence: (any RunStoreOwnedRecordsPersisting)? = nil,
        locationCapture: (any RunLocationCapturing)? = nil
    ) {
        self.defaults = defaults
        self.uploadIdentityProvider = uploadIdentityProvider
        self.uploadQueue = uploadQueue
        self.uploadDrainer = uploadDrainer
        self.ownedRecordsPersistence = ownedRecordsPersistence ?? FileRunStoreOwnedRecordsPersistence()
        self.locationCapture = locationCapture
        locationCapture?.onFix = { [weak self] fix in self?.recordLocation(fix) }
        locationCapture?.onStatus = { [weak self] message in self?.locationMessage = message }
        if let data = defaults.data(forKey: "mov.demo.v1") {
            do {
                let state = try JSONDecoder().decode(Saved.self, from: data)
                records=state.records; goal=state.goal; weekly=state.weekly; session=state.session
                if session?.locationCaptureEnabled == true, let priorSegmentStart=session?.segmentStart {
                    session?.activePauseStartedAt=priorSegmentStart
                }
                session?.segmentStart=nil
            }
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

    /// Removes only records and queued uploads owned by this member. Ownerless
    /// history, other members' records, and account-independent goals are retained.
    func clearOwnedRecords(for memberID: String) async -> Bool {
        guard Self.validMemberID(memberID) != nil, storageMessage == nil,
              session?.uploadOwnerID != memberID else { return false }
        if let uploadQueue, !(uploadQueue is any RunUploadOwnerScopedClearing) { return false }

        cancelPendingRunUploadDrain()
        let previousRecords = records
        let retainedRecords = previousRecords.filter { $0.uploadOwnerID != memberID }
        do {
            let snapshot = try ownedRecordsPersistence.loadSnapshot()
            let sourceRecords: [RunRecord]
            switch snapshot {
            case .missing: sourceRecords = previousRecords.filter { $0.uploadOwnerID != nil }
            case .legacyPending(let records), .canonical(let records): sourceRecords = records
            }
            try ownedRecordsPersistence.saveCanonical(sourceRecords.filter { $0.uploadOwnerID != memberID })
            if let clearing = uploadQueue as? any RunUploadOwnerScopedClearing {
                try await clearing.clearRunUploads(ownerID: memberID)
            }
            records = retainedRecords
            guard persist() else {
                records = previousRecords
                return false
            }
            return true
        } catch {
            records = previousRecords
            return false
        }
    }

    @discardableResult func start(at now: Date = Date(),weight:Double?=nil,clientRunID:UUID?=nil) -> Bool {
        guard session == nil, storageMessage == nil else { return false }
        let memberID = uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID)
        session = DemoSession(
            startedAt: now,
            segmentStart: now,
            goal: goal,
            weightKg: weight,
            uploadOwnerID: memberID,
            clientRunID: clientRunID ?? UUID(),
            routePoints: locationCapture == nil ? nil : [],
            pauseIntervals: locationCapture == nil ? nil : [],
            locationCaptureEnabled: locationCapture != nil
        )
        guard persist() else {
            session = nil
            return false
        }
        locationMessage = locationCapture == nil ? "GPS 연결을 사용할 수 없어요" : "위치 확인 중"
        locationCapture?.start()
        return true
    }
    func pause(at now: Date = Date()) {
        guard var current=session, !current.paused else { return }
        let cappedNow = min(now, current.maximumEndedAt)
        current.accumulated=current.elapsed(at:cappedNow)
        current.segmentStart=nil
        current.activePauseStartedAt=cappedNow
        session=current
        locationCapture?.stop()
        locationMessage="일시정지 중"
        persist()
    }
    func resume(at now: Date = Date()) {
        guard var current=session, current.paused, now < current.maximumEndedAt else { return }
        if let pauseStart=current.activePauseStartedAt {
            current.pauseIntervals=(current.pauseIntervals ?? []) + [RunUploadPause(startedAt:pauseStart,endedAt:now)]
        }
        current.activePauseStartedAt=nil
        current.segmentStart=now
        session=current
        persist()
        locationCapture?.start()
        locationMessage="위치 확인 중"
    }

    func recordLocation(_ fix:RunLocationFix) {
        guard var current=session, let segmentStart=current.segmentStart,
              fix.recordedAt >= segmentStart,
              fix.recordedAt >= current.startedAt, fix.recordedAt <= current.maximumEndedAt,
              fix.latitude.isFinite, (-90...90).contains(fix.latitude),
              fix.longitude.isFinite, (-180...180).contains(fix.longitude),
              fix.accuracyMeters.isFinite, fix.accuracyMeters >= 0,
              fix.altitudeMeters.map({$0.isFinite && $0 >= 0}) != false,
              fix.speedMetersPerSecond.map({$0.isFinite && $0 >= 0}) != false else { return }
        var points=current.routePoints ?? []
        guard points.count < 21_600 else { locationMessage="GPS 샘플 상한에 도달했어요";locationCapture?.stop();return }
        let point=RunUploadPoint(
            recordedAt:fix.recordedAt,
            latitude:fix.latitude,
            longitude:fix.longitude,
            accuracyMeters:fix.accuracyMeters,
            altitudeMeters:fix.altitudeMeters,
            speedMetersPerSecond:fix.speedMetersPerSecond
        )
        if let last=points.last, fix.recordedAt < last.recordedAt { return }
        if points.last?.recordedAt == fix.recordedAt && points.last?.latitude == fix.latitude && points.last?.longitude == fix.longitude { return }
        if let last=points.last { current.distance=(current.distance ?? 0) + Self.distanceMeters(from:last,to:point)/1_000 }
        else { current.distance=0 }
        current.accumulated=current.elapsed(at:fix.recordedAt)
        current.segmentStart=fix.recordedAt
        points.append(point)
        current.routePoints=points
        session=current
        locationMessage="위치 측정 중 · \(points.count)개 샘플"
        persist()
    }

    @discardableResult func finish(save: Bool, at now: Date = Date()) -> RunRecord? {
        guard var current=session else { return nil }
        let endedAt=max(current.startedAt,min(now,current.maximumEndedAt))
        if let pauseStart=current.activePauseStartedAt, endedAt > pauseStart {
            current.pauseIntervals=(current.pauseIntervals ?? []) + [RunUploadPause(startedAt:pauseStart,endedAt:endedAt)]
        }
        current.activePauseStartedAt=nil
        if let points=current.routePoints {
            let retainedPoints=points.filter{$0.recordedAt <= endedAt}
            current.routePoints=retainedPoints
            current.distance=Self.totalDistanceMeters(retainedPoints)/1_000
        }
        if save && (current.elapsed(at:endedAt)<=0 || storageMessage != nil) { return nil }
        var record=current.record(at:endedAt)
        record.pauseIntervals=current.pauseIntervals
        if save {
            record.uploadPayload = Self.uploadPayload(for: current, record: record, endedAt: endedAt)
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
        locationCapture?.stop()
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

    @discardableResult func finishIfPastSixHourLimit(at now:Date=Date()) async -> RunRecord? {
        guard let current=session, now >= current.maximumEndedAt else { return nil }
        return await finishAndEnqueue(save:true,at:current.maximumEndedAt)
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
        await recoverAcceptedRunSummaries()
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

    private func recoverAcceptedRunSummaries() async {
        guard let ownerID=authenticatedUploadMemberID,let uploadDrainer else{return}
        let summaries:[BackendRunSummary]
        do { summaries=try await uploadDrainer.pendingAcceptedRunSummaries(ownerID:ownerID) }
        catch {
            uploadMessage="서버 판정 대기를 복구하지 못했습니다. 기기 기록은 보존했어요."
            uploadNeedsRetry=true
            return
        }
        guard !summaries.isEmpty else{return}
        var appliedIDs:[UUID]=[]
        for summary in summaries {
            guard authenticatedUploadMemberID==ownerID,
                  applyServerRunSummary(summary,ownerID:ownerID) else {
                uploadMessage="서버 판정 결과를 기기에 반영하지 못했습니다. 저장된 기록은 보존했어요."
                uploadNeedsRetry=true
                return
            }
            appliedIDs.append(summary.clientRunID)
        }
        do {
            try await uploadDrainer.acknowledgeAcceptedRunSummaries(ownerID:ownerID,clientRunIDs:appliedIDs)
            guard authenticatedUploadMemberID==ownerID else{return}
            setServerJudgementMessage(summaries)
        } catch {
            uploadMessage="서버 판정은 기기에 반영했어요. 업로드 상태 확인을 다시 시도해 주세요."
            uploadNeedsRetry=true
        }
    }

    private func applyAcceptedRunSummaries(_ summaries:[BackendRunSummary],ownerID:String) async -> Bool {
        guard !summaries.isEmpty else{return true}
        guard authenticatedUploadMemberID==ownerID,let uploadDrainer else{return false}
        var appliedIDs:[UUID]=[]
        for summary in summaries {
            guard authenticatedUploadMemberID==ownerID,
                  applyServerRunSummary(summary,ownerID:ownerID) else{return false}
            appliedIDs.append(summary.clientRunID)
        }
        do {
            try await uploadDrainer.acknowledgeAcceptedRunSummaries(ownerID:ownerID,clientRunIDs:appliedIDs)
            guard authenticatedUploadMemberID==ownerID else{return false}
        } catch {return false}
        setServerJudgementMessage(summaries)
        return true
    }

    private func setServerJudgementMessage(_ summaries:[BackendRunSummary]) {
        guard !summaries.isEmpty else{return}
        let valid=summaries.filter{$0.verdict=="VALID"}.count
        let invalid=summaries.filter{$0.verdict=="INVALID"}.count
        if invalid>0 && valid>0 {uploadMessage="서버 판정 결과를 기기 기록에 반영했어요 · 유효 \(valid)건, 비유효 \(invalid)건"}
        else if invalid>0 {uploadMessage="서버에서 비유효로 판정한 결과를 기기 기록에 반영했어요"}
        else if valid>0 {uploadMessage="서버 판정 완료 · 유효 기록으로 반영했어요"}
        else {uploadMessage="서버 판정 대기 상태를 기기 기록에 반영했어요"}
        uploadNeedsRetry=false
    }

    /// Drains the existing outbox only when an authenticated stable member ID is available.
    /// The caller must invoke this explicitly; completion records remain canonical after drain.
    func drainPendingRunUploads() async -> RunStoreUploadDrainResult {
        guard uploadDrainOperationID == nil else { return .alreadyRunning }
        guard let ownerID = uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID) else {
            uploadMessage = "기기에 저장됨 · 로그인 후 서버 업로드를 할 수 있어요"
            uploadNeedsRetry = false
            return .authenticationUnavailable
        }
        guard let uploadDrainer else {
            uploadMessage = "기기에 안전하게 저장했어요 · 서버 업로드 준비를 확인해 주세요"
            uploadNeedsRetry = true
            return .drainerUnavailable
        }

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

        var result:RunStoreUploadDrainResult
        var acceptedSummaries:[BackendRunSummary]=[]
        switch drainResult {
        case .success(let report):
            acceptedSummaries=report.acceptedSummaries
            result = Self.uploadDrainResult(for: report)
        case .failure(let error):
            if error is CancellationError { result = .cancelled }
            else if let failure = error as? RunUploadOutboxPersistenceFailure, failure == .writeFailed {
                result = .retryableAcknowledgementFailure
            } else { result = .storageFailure }
        }
        if !acceptedSummaries.isEmpty,
           !(await applyAcceptedRunSummaries(acceptedSummaries,ownerID:ownerID)) {
            result = .retryableAcknowledgementFailure
        }
        switch result {
        case .completed(let uploadedCount, _):
            if acceptedSummaries.isEmpty {
                uploadMessage = uploadedCount > 0 ? "업로드 접수 완료 · 서버 판정 대기" : (uploadMessage ?? "업로드할 기록이 없어요")
                uploadNeedsRetry = false
            }
        case .permanentFailure(let count, _, _):
            uploadMessage = "\(count)개 기록의 업로드를 완료하지 못했어요. 저장된 측정값을 확인해 주세요"
            uploadNeedsRetry = false
        case .retryableFailure(_, let code, _, _, _):
            uploadMessage = code == "TRANSPORT" ? "네트워크 전송이 실패했어요 · 기록은 기기에 보관했고 다시 시도할 수 있어요" : "업로드를 완료하지 못했어요 · 기록은 기기에 보관했고 다시 시도할 수 있어요"
            uploadNeedsRetry = true
        case .retryableAcknowledgementFailure, .storageFailure:
            uploadMessage = "업로드 상태를 저장하지 못했어요 · 같은 기록으로 다시 시도할 수 있어요"
            uploadNeedsRetry = true
        case .authenticationUnavailable:
            uploadMessage = "기기에 저장됨 · 로그인 후 서버 업로드를 할 수 있어요"
            uploadNeedsRetry = false
        case .drainerUnavailable:
            uploadMessage = "기기에 안전하게 저장했어요 · 서버 업로드 준비를 확인해 주세요"
            uploadNeedsRetry = true
        case .alreadyRunning:
            uploadMessage = "업로드 중이에요"
            uploadNeedsRetry = false
        case .ownerMismatch, .accountChanged, .cancelled, .ignored:
            uploadMessage = "업로드가 보류됐어요 · 계정을 확인한 뒤 다시 시도해 주세요"
            uploadNeedsRetry = true
        }
        return result
    }

    func retryPendingRunUploads() async -> RunStoreUploadDrainResult {
        await recoverPendingRunUploads()
        return await drainPendingRunUploads()
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
        guard let distanceMeters = Int(exactly: wholeMeters) else { return nil }

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
            points: session.routePoints ?? [],
            pauses: session.pauseIntervals ?? []
        )
    }

    private static func distanceMeters(from first:RunUploadPoint,to second:RunUploadPoint)->Double {
        let radius=6_371_000.0
        let lat1=first.latitude * .pi / 180
        let lat2=second.latitude * .pi / 180
        let dLat=(second.latitude-first.latitude) * .pi / 180
        let dLon=(second.longitude-first.longitude) * .pi / 180
        let a=sin(dLat/2)*sin(dLat/2)+cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
        return radius * 2 * atan2(sqrt(a),sqrt(max(0,1-a)))
    }

    private static func totalDistanceMeters(_ points:[RunUploadPoint])->Double {
        zip(points,points.dropFirst()).reduce(0){$0+distanceMeters(from:$1.0,to:$1.1)}
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

    var authenticatedUploadMemberID:String? {
        uploadIdentityProvider?.currentAuthenticatedMemberID().flatMap(Self.validMemberID)
    }

    func hasLocalRecord(ownerID:String,clientRunID:UUID)->Bool {
        records.contains{$0.uploadOwnerID==ownerID && $0.clientRunID==clientRunID}
    }

    /// Applies an authoritative POST/list summary to the one local snapshot that was
    /// created for the same authenticated member and immutable clientRunId.
    @discardableResult func applyServerRunSummary(_ summary:BackendRunSummary,ownerID:String)->Bool {
        let matchingIndices=records.indices.filter{
            records[$0].uploadOwnerID==ownerID && records[$0].clientRunID==summary.clientRunID
        }
        guard Self.validMemberID(ownerID) != nil,
              authenticatedUploadMemberID==ownerID,
              matchingIndices.count==1,
              let index=matchingIndices.first,
              let payload=records[index].uploadPayload,
              summary.matches(payload) else {return false}
        let judgement:RunServerJudgement
        switch summary.verdict {
        case "VALID":
            guard summary.validDistanceMeters != nil,
                  summary.validSeconds != nil,
                  summary.paceSecondsPerKm != nil else {return false}
            judgement = .valid
        case "INVALID": judgement = .invalid
        case "PENDING": judgement = .pending
        default: return false
        }
        var updated=records[index]
        updated.serverRunID=summary.id
        updated.serverVersion=summary.version
        updated.serverJudgement=judgement
        updated.serverVerdictReason=summary.verdictReason
        updated.serverValidDistanceMeters=summary.validDistanceMeters
        updated.serverValidSeconds=summary.validSeconds
        updated.serverPaceSecondsPerKm=summary.paceSecondsPerKm
        updated.serverUpdatedAt=summary.updatedAt
        if let reward=summary.pointReward,
           let status=RunPointRewardStatus(rawValue:reward.status.rawValue),
           let value=try? RunPointReward(status:status,pointsAwarded:reward.pointsAwarded.flatMap{Int(exactly:$0)}) {
            updated.pointReward=value
        }
        if records[index]==updated {return true}

        let previous=records[index]
        records[index]=updated
        do {
            try ownedRecordsPersistence.saveCanonical(records.filter{$0.uploadOwnerID != nil})
        } catch {
            records[index]=previous
            storageMessage="서버 판정 결과를 기기에 안전하게 저장하지 못했습니다. 업로드 확인을 다시 시도해 주세요."
            return false
        }
        // The owner-scoped file is canonical. UserDefaults is only its local read cache.
        _=persist()
        return true
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
    var weeklyDistance: Double { weeklyRecords.reduce(0){$0+$1.statisticalKilometers} }
    var weeklySeconds: Double { weeklyRecords.reduce(0){$0+$1.statisticalSeconds} }
    var totalDistance: Double { records.filter(\.isValid).reduce(0){$0+$1.statisticalKilometers} }
    var activityDays: Int {
        let groups=Dictionary(grouping: records.filter(\.isValid)) { Calendar.current.startOfDay(for:$0.date) }
        return groups.values.filter { $0.reduce(0){$0+$1.statisticalSeconds} >= 240 && $0.reduce(0){$0+$1.statisticalKilometers} >= 1 }.count
    }
    func averageDistance(asOf now: Date) -> Double {
        let start=Calendar.current.date(byAdding:.month,value:-1,to:now) ?? now
        let recent=records.filter{$0.isValid && $0.date >= start && $0.date <= now}
        return recent.isEmpty ? 0 : recent.reduce(0){$0+$1.statisticalKilometers}/Double(recent.count)
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
