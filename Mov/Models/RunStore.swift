import Foundation
import Observation

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
        return args.contains("-wire-fixture") && args.contains("-wire-capture-viewport") ? referenceDate : Date()
    }
}
struct RunSegment: Codable, Equatable {
    var distance:Double;var seconds:Double;var type="include";var reason:String?
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
    var paused: Bool { segmentStart == nil }
    func elapsed(at now: Date) -> Double { accumulated + (segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    func record(at now: Date) -> RunRecord {
        let seconds = elapsed(at: now)
        return RunRecord(date: startedAt, title: RunRecord.title(for: startedAt), seconds: seconds, kilometers: distance ?? 0,weightKg:weightKg)
    }
}

@MainActor @Observable final class RunStore {
    private let defaults: UserDefaults
    var records: [RunRecord] = []
    var goal = RunGoal()
    var weekly = WeeklyGoal()
    var session: DemoSession?
    var storageMessage: String?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "mov.demo.v1") {
            do { let state = try JSONDecoder().decode(Saved.self, from: data); records=state.records; goal=state.goal; weekly=state.weekly; session=state.session; session?.segmentStart=nil }
            catch { storageMessage = "저장한 기록을 읽지 못했습니다. 새 데이터를 저장하기 전에 앱을 다시 실행해 주세요." }
        } else {
            records=[]
            persist()
        }
    }
    private struct Saved: Codable { var records: [RunRecord]; var goal: RunGoal; var weekly: WeeklyGoal; var session: DemoSession? }
    func persist() {
        guard storageMessage == nil else { return }
        do { defaults.set(try JSONEncoder().encode(Saved(records: records, goal: goal, weekly: weekly, session: session)), forKey: "mov.demo.v1") }
        catch { storageMessage = "기록을 저장하지 못했습니다." }
    }
    func start(at now: Date = Date(),weight:Double?=nil) { guard session == nil else { return }; session=DemoSession(startedAt:now,segmentStart:now,goal:goal,weightKg:weight); persist() }
    func pause(at now: Date = Date()) { guard var current=session, !current.paused else { return }; current.accumulated=current.elapsed(at:now); current.segmentStart=nil; session=current; persist() }
    func resume(at now: Date = Date()) { guard var current=session, current.paused else { return }; current.segmentStart=now; session=current; persist() }
    @discardableResult func finish(save: Bool, at now: Date = Date()) -> RunRecord? {
        guard let current=session else { return nil }
        if save && (current.elapsed(at:now)<=0 || storageMessage != nil) { return nil }
        let record=current.record(at:now)
        if save { records.insert(record,at:0) }
        session=nil; persist(); return save ? record : nil
    }
    func update(_ record: RunRecord) { if let i=records.firstIndex(where:{$0.id==record.id}) { records[i]=record; persist() } }
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
