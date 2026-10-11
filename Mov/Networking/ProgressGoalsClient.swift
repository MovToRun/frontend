import Foundation

struct BackendProgressSummary: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let fromDate: String
        let toDate: String
        let distanceMeters: Int64
        let activityDays: Int
    }

    struct NextGrade: Equatable, Sendable {
        let grade: String
        let requiredDistanceMeters: Int64
        let requiredActivityDays: Int
        let remainingDistanceMeters: Int64
        let remainingActivityDays: Int
    }

    struct Total: Equatable, Sendable {
        let distanceMeters: Int64
        let seconds: Int64
        let activityDays: Int
        let runCount: Int64
    }

    let grade: String
    let gradeAchievedAt: Date?
    let window: Window
    let nextGrade: NextGrade?
    let total: Total
}

struct BackendDailyProgressDay: Equatable, Sendable, Identifiable {
    let date: String
    let validDistanceMeters: Int64
    let validSeconds: Int64
    let runCount: Int64
    let activityDay: Bool

    var id: String { date }
}

struct BackendDailyProgressRange: Equatable, Hashable, Sendable {
    let fromDate: String
    let toDate: String

    init(fromDate: String, toDate: String) throws {
        guard let from = BackendProgressDate.parse(fromDate),
              let to = BackendProgressDate.parse(toDate),
              to >= from,
              BackendProgressDate.dayDistance(from: fromDate, to: toDate).map({ $0 < 366 }) == true else {
            throw ProgressGoalsFailure.invalidDateRange
        }
        self.fromDate = fromDate
        self.toDate = toDate
    }

    static func week(containing date: Date) -> Self {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = BackendProgressDate.timeZone
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
        let end = calendar.date(byAdding: .day, value: 6, to: interval.start)!
        return try! Self(fromDate: BackendProgressDate.string(interval.start), toDate: BackendProgressDate.string(end))
    }

    static func month(containing date: Date) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BackendProgressDate.timeZone
        let interval = calendar.dateInterval(of: .month, for: date)!
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return try! Self(fromDate: BackendProgressDate.string(interval.start), toDate: BackendProgressDate.string(end))
    }

    var cacheKey: String { "\(fromDate)...\(toDate)" }
}

struct BackendWeeklyGoalAxis: Equatable, Sendable {
    let goal: Int64?
    let done: Int64
    let remaining: Int64?
    let achieved: Bool
}

struct BackendWeeklyGoalStatus: Equatable, Sendable {
    let weekStartDate: String
    let weekEndDate: String
    let version: Int64
    let distance: BackendWeeklyGoalAxis
    let time: BackendWeeklyGoalAxis
}

struct BackendDailyProgress: Equatable, Sendable {
    let range: BackendDailyProgressRange
    let days: [BackendDailyProgressDay]

    var distanceMeters: Int64 { days.reduce(0) { $0 + $1.validDistanceMeters } }
    var seconds: Int64 { days.reduce(0) { $0 + $1.validSeconds } }
    var runCount: Int64 { days.reduce(0) { $0 + $1.runCount } }
}

protocol RunningProgressReading: Sendable {
    func fetchProgress() async throws -> BackendProgressSummary
    func fetchWeeklyGoal() async throws -> BackendWeeklyGoalStatus
    func fetchDaily(range: BackendDailyProgressRange) async throws -> BackendDailyProgress
}

protocol RunningWeeklyGoalWriting: Sendable {
    func saveWeeklyGoal(version: Int64, distanceGoalMeters: Int64?, timeGoalSeconds: Int64?) async throws -> BackendWeeklyGoalStatus
}

enum ProgressGoalsFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case serviceUnavailable(requestID: String?)
    case invalidDateRange
    case invalidResponse
    case invalidWeeklyGoalDraft
    case weeklyGoalWriteUnavailable
    case weeklyGoalBaselineUnavailable
    case weeklyGoalVersionConflict(requestID: String?)
    case weeklyGoalValidationFailed(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case transport(URLError.Code)
    case cancelled

    var canManuallyRetry: Bool {
        if case .cancelled = self { return false }
        return true
    }

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .serviceUnavailable:
            return "러닝 진행 정보를 잠시 불러올 수 없어요. 다시 시도해 주세요."
        case .invalidDateRange:
            return "조회할 날짜 범위를 확인해 주세요."
        case .invalidWeeklyGoalDraft, .weeklyGoalValidationFailed:
            return "거리와 시간 목표의 범위와 단위를 확인해 주세요."
        case .weeklyGoalWriteUnavailable:
            return "주간 목표 저장 기능을 사용할 수 없어요."
        case .weeklyGoalBaselineUnavailable:
            return "주간 목표 정보를 불러온 뒤 저장해 주세요."
        case .weeklyGoalVersionConflict:
            return "다른 곳에서 목표가 변경됐어요. 다시 불러온 뒤 저장해 주세요."
        case .invalidResponse:
            return "러닝 진행 정보를 불러오지 못했어요. 다시 시도해 주세요."
        case .serverFailure(let statusCode, _) where (500...599).contains(statusCode):
            return "러닝 진행 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .serverFailure:
            return "러닝 진행 정보를 불러오지 못했어요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        }
    }

    var weeklyGoalWriteMessage: String {
        switch self {
        case .weeklyGoalVersionConflict:
            return "다른 곳에서 목표가 변경됐어요. 다시 불러온 뒤 저장해 주세요."
        case .weeklyGoalValidationFailed, .invalidWeeklyGoalDraft:
            return "거리와 시간 목표의 범위와 단위를 확인해 주세요."
        case .weeklyGoalWriteUnavailable:
            return "주간 목표 저장 기능을 사용할 수 없어요."
        case .weeklyGoalBaselineUnavailable:
            return "주간 목표 정보를 불러온 뒤 저장해 주세요."
        case .serviceUnavailable:
            return "주간 목표를 저장하지 못했어요. 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        default:
            return "주간 목표를 저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

struct ProgressGoalsRetryPolicy: Sendable {
    let maximumAttempts: Int
    let delayNanoseconds: UInt64

    init(maximumAttempts: Int = 1, delayNanoseconds: UInt64 = 200_000_000) {
        self.maximumAttempts = min(2, max(1, maximumAttempts))
        self.delayNanoseconds = delayNanoseconds
    }
}

final class ProgressGoalsClient: RunningProgressReading, RunningWeeklyGoalWriting, Sendable {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding
    private let retryPolicy: ProgressGoalsRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    init(
        apiClient: any APIResponseSending,
        tokenProvider: any AccessTokenProviding,
        retryPolicy: ProgressGoalsRetryPolicy = ProgressGoalsRetryPolicy(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func fetchProgress() async throws -> BackendProgressSummary {
        let response = try await sendAuthorized(path: "progress")
        do {
            return try ProgressResponse.decode(response.data)
        } catch let failure as ProgressGoalsFailure {
            throw failure
        } catch {
            throw ProgressGoalsFailure.invalidResponse
        }
    }

    func fetchWeeklyGoal() async throws -> BackendWeeklyGoalStatus {
        let response = try await sendAuthorized(path: "goals/weekly")
        do {
            return try WeeklyGoalResponse.decode(response.data)
        } catch let failure as ProgressGoalsFailure {
            throw failure
        } catch {
            throw ProgressGoalsFailure.invalidResponse
        }
    }

    func saveWeeklyGoal(version: Int64, distanceGoalMeters: Int64?, timeGoalSeconds: Int64?) async throws -> BackendWeeklyGoalStatus {
        guard version >= 0,
              Self.isValidGoal(distanceGoalMeters, step: 1_000, maximum: 500_000),
              Self.isValidGoal(timeGoalSeconds, step: 600, maximum: 360_000) else {
            throw ProgressGoalsFailure.invalidWeeklyGoalDraft
        }

        let body = try JSONEncoder().encode(WeeklyGoalUpdateRequest(
            version: version,
            distanceGoalMeters: distanceGoalMeters,
            timeGoalSeconds: timeGoalSeconds
        ))
        let response = try await sendAuthorized(
            path: "goals/weekly",
            method: "PUT",
            body: body,
            additionalHeaders: ["Content-Type": "application/json"],
            retriesEnabled: false
        )
        do {
            return try WeeklyGoalResponse.decode(response.data)
        } catch let failure as ProgressGoalsFailure {
            throw failure
        } catch {
            throw ProgressGoalsFailure.invalidResponse
        }
    }

    func fetchDaily(range: BackendDailyProgressRange) async throws -> BackendDailyProgress {
        // Revalidate even ranges constructed through an internal fixture or future caller.
        let checkedRange = try BackendDailyProgressRange(fromDate: range.fromDate, toDate: range.toDate)
        let response = try await sendAuthorized(
            path: "progress/daily",
            queryItems: [URLQueryItem(name: "from", value: checkedRange.fromDate), URLQueryItem(name: "to", value: checkedRange.toDate)]
        )
        do {
            return try DailyProgressResponse.decode(response.data, range: checkedRange)
        } catch let failure as ProgressGoalsFailure {
            throw failure
        } catch {
            throw ProgressGoalsFailure.invalidResponse
        }
    }

    private func sendAuthorized(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        additionalHeaders: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        retriesEnabled: Bool = true
    ) async throws -> APIClientResponse {
        let token: String
        do {
            guard let value = try await tokenProvider.accessToken(),
                  !value.isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw ProgressGoalsFailure.accessTokenUnavailable
            }
            token = value
        } catch let failure as ProgressGoalsFailure {
            throw failure
        } catch is CancellationError {
            throw ProgressGoalsFailure.cancelled
        } catch {
            throw ProgressGoalsFailure.accessTokenUnavailable
        }

        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]
        additionalHeaders.forEach { headers[$0.key] = $0.value }

        for attempt in 1...retryPolicy.maximumAttempts {
            do {
                let response = try await apiClient.sendResponse(path: path, method: method, body: body, headers: headers, queryItems: queryItems)
                guard (200..<300).contains(response.statusCode) else {
                    let failure = mapFailure(response, weeklyGoalWrite: method == "PUT" && path == "goals/weekly")
                    if retriesEnabled, attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                        try await waitBeforeRetry()
                        continue
                    }
                    throw failure
                }
                return response
            } catch let failure as ProgressGoalsFailure {
                if retriesEnabled, attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch let error as APIClientError {
                let failure = mapFailure(error)
                if retriesEnabled, attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch is CancellationError {
                throw ProgressGoalsFailure.cancelled
            } catch {
                throw ProgressGoalsFailure.invalidResponse
            }
        }
        throw ProgressGoalsFailure.invalidResponse
    }

    private func waitBeforeRetry() async throws {
        do { try await sleep(retryPolicy.delayNanoseconds) }
        catch { throw ProgressGoalsFailure.cancelled }
    }

    private func mapFailure(_ response: APIClientResponse, weeklyGoalWrite: Bool = false) -> ProgressGoalsFailure {
        let problem = try? JSONDecoder().decode(ProgressProblemResponse.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401: return .unauthenticated
        case 503: return .serviceUnavailable(requestID: requestID)
        case 409 where weeklyGoalWrite: return .weeklyGoalVersionConflict(requestID: requestID)
        case 400 where weeklyGoalWrite: return .weeklyGoalValidationFailed(requestID: requestID)
        default: return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private static func isValidGoal(_ value: Int64?, step: Int64, maximum: Int64) -> Bool {
        guard let value else { return true }
        return value >= step && value <= maximum && value.isMultiple(of: step)
    }

    private func mapFailure(_ error: APIClientError) -> ProgressGoalsFailure {
        switch error {
        case .cancelled: return .cancelled
        case .transport(let code): return .transport(code)
        default: return .invalidResponse
        }
    }
}

private struct ProgressProblemResponse: Decodable {
    let requestId: String?
}

private struct WeeklyGoalUpdateRequest: Encodable {
    let version: Int64
    let distanceGoalMeters: Int64?
    let timeGoalSeconds: Int64?

    private enum CodingKeys: String, CodingKey { case version, distanceGoalMeters, timeGoalSeconds }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(distanceGoalMeters, forKey: .distanceGoalMeters)
        try container.encode(timeGoalSeconds, forKey: .timeGoalSeconds)
    }
}

private extension ProgressGoalsFailure {
    var isRetryable: Bool {
        switch self {
        case .serviceUnavailable:
            return true
        case .transport(let code):
            return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed].contains(code)
        default:
            return false
        }
    }
}

private enum ProgressResponse {
    private struct DTO: Decodable {
        struct Window: Decodable {
            let fromDate: String
            let toDate: String
            let distanceMeters: Int64
            let activityDays: Int
        }

        struct NextGrade: Decodable {
            let grade: String
            let requiredDistanceMeters: Int64
            let requiredActivityDays: Int
            let remainingDistanceMeters: Int64
            let remainingActivityDays: Int
        }

        struct Total: Decodable {
            let distanceMeters: Int64
            let seconds: Int64
            let activityDays: Int
            let runCount: Int64
        }

        let grade: String
        let gradeAchievedAt: String?
        let window: Window
        let nextGrade: NextGrade?
        let total: Total

        private enum CodingKeys: String, CodingKey { case grade, gradeAchievedAt, window, nextGrade, total }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            grade = try container.decode(String.self, forKey: .grade)
            gradeAchievedAt = try decodeRequiredNullable(String.self, from: container, forKey: .gradeAchievedAt)
            window = try container.decode(Window.self, forKey: .window)
            nextGrade = try decodeRequiredNullable(NextGrade.self, from: container, forKey: .nextGrade)
            total = try container.decode(Total.self, forKey: .total)
        }
    }

    static func decode(_ data: Data) throws -> BackendProgressSummary {
        let value = try JSONDecoder().decode(DTO.self, from: data)
        let grades = ["NONE", "STARTER", "SPROUT", "PASSION", "CHALLENGE", "MASTER"]
        guard grades.contains(value.grade),
              BackendProgressDate.isValidRange(from: value.window.fromDate, to: value.window.toDate),
              value.window.distanceMeters >= 0, value.window.activityDays >= 0,
              value.total.distanceMeters >= 0, value.total.seconds >= 0,
              value.total.activityDays >= 0, value.total.runCount >= 0,
              value.nextGrade.map({ grades.contains($0.grade) && $0.requiredDistanceMeters >= 0 && $0.requiredActivityDays >= 0 && $0.remainingDistanceMeters >= 0 && $0.remainingActivityDays >= 0 }) ?? true,
              (value.grade == "MASTER") == (value.nextGrade == nil) else {
            throw ProgressGoalsFailure.invalidResponse
        }
        let achievedAt: Date?
        if let raw = value.gradeAchievedAt {
            achievedAt = try BackendProgressDate.parseTimestamp(raw)
        } else {
            achievedAt = nil
        }
        return BackendProgressSummary(
            grade: value.grade,
            gradeAchievedAt: achievedAt,
            window: .init(fromDate: value.window.fromDate, toDate: value.window.toDate, distanceMeters: value.window.distanceMeters, activityDays: value.window.activityDays),
            nextGrade: value.nextGrade.map {
                .init(grade: $0.grade, requiredDistanceMeters: $0.requiredDistanceMeters, requiredActivityDays: $0.requiredActivityDays, remainingDistanceMeters: $0.remainingDistanceMeters, remainingActivityDays: $0.remainingActivityDays)
            },
            total: .init(distanceMeters: value.total.distanceMeters, seconds: value.total.seconds, activityDays: value.total.activityDays, runCount: value.total.runCount)
        )
    }
}

private enum DailyProgressResponse {
    private struct DTO: Decodable {
        struct Day: Decodable {
            let date: String
            let validDistanceMeters: Int64
            let validSeconds: Int64
            let runCount: Int64
            let activityDay: Bool
        }
        let items: [Day]
    }

    static func decode(_ data: Data, range: BackendDailyProgressRange) throws -> BackendDailyProgress {
        let value = try JSONDecoder().decode(DTO.self, from: data)
        var previous: String?
        for day in value.items {
            guard BackendProgressDate.parse(day.date) != nil,
                  day.date >= range.fromDate, day.date <= range.toDate,
                  previous.map({ day.date > $0 }) ?? true,
                  day.validDistanceMeters >= 0, day.validSeconds >= 0, day.runCount >= 0,
                  !day.activityDay || (day.validDistanceMeters >= 1_000 && day.validSeconds >= 240) else {
                throw ProgressGoalsFailure.invalidResponse
            }
            previous = day.date
        }
        return BackendDailyProgress(
            range: range,
            days: value.items.map {
                BackendDailyProgressDay(date: $0.date, validDistanceMeters: $0.validDistanceMeters, validSeconds: $0.validSeconds, runCount: $0.runCount, activityDay: $0.activityDay)
            }
        )
    }
}

private enum WeeklyGoalResponse {
    private struct DTO: Decodable {
        struct Axis: Decodable {
            let goalMeters: Int64?
            let doneMeters: Int64
            let remainingMeters: Int64?
            let achieved: Bool

            private enum CodingKeys: String, CodingKey { case goalMeters, doneMeters, remainingMeters, achieved }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                goalMeters = try decodeRequiredNullable(Int64.self, from: container, forKey: .goalMeters)
                doneMeters = try container.decode(Int64.self, forKey: .doneMeters)
                remainingMeters = try decodeRequiredNullable(Int64.self, from: container, forKey: .remainingMeters)
                achieved = try container.decode(Bool.self, forKey: .achieved)
            }
        }
        struct TimeAxis: Decodable {
            let goalSeconds: Int64?
            let doneSeconds: Int64
            let remainingSeconds: Int64?
            let achieved: Bool

            private enum CodingKeys: String, CodingKey { case goalSeconds, doneSeconds, remainingSeconds, achieved }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                goalSeconds = try decodeRequiredNullable(Int64.self, from: container, forKey: .goalSeconds)
                doneSeconds = try container.decode(Int64.self, forKey: .doneSeconds)
                remainingSeconds = try decodeRequiredNullable(Int64.self, from: container, forKey: .remainingSeconds)
                achieved = try container.decode(Bool.self, forKey: .achieved)
            }
        }
        let weekStartDate: String
        let weekEndDate: String
        let version: Int64
        let distance: Axis
        let time: TimeAxis
    }

    static func decode(_ data: Data) throws -> BackendWeeklyGoalStatus {
        let value = try JSONDecoder().decode(DTO.self, from: data)
        guard BackendProgressDate.isValidWeek(from: value.weekStartDate, to: value.weekEndDate), value.version >= 0,
              valid(value.distance.goalMeters, done: value.distance.doneMeters, remaining: value.distance.remainingMeters, achieved: value.distance.achieved, step: 1_000, maximum: 500_000),
              valid(value.time.goalSeconds, done: value.time.doneSeconds, remaining: value.time.remainingSeconds, achieved: value.time.achieved, step: 600, maximum: 360_000) else {
            throw ProgressGoalsFailure.invalidResponse
        }
        return BackendWeeklyGoalStatus(
            weekStartDate: value.weekStartDate,
            weekEndDate: value.weekEndDate,
            version: value.version,
            distance: BackendWeeklyGoalAxis(goal: value.distance.goalMeters, done: value.distance.doneMeters, remaining: value.distance.remainingMeters, achieved: value.distance.achieved),
            time: BackendWeeklyGoalAxis(goal: value.time.goalSeconds, done: value.time.doneSeconds, remaining: value.time.remainingSeconds, achieved: value.time.achieved)
        )
    }

    private static func valid(_ goal: Int64?, done: Int64, remaining: Int64?, achieved: Bool, step: Int64, maximum: Int64) -> Bool {
        guard done >= 0 else { return false }
        guard let goal else { return remaining == nil && !achieved }
        guard goal >= step, goal <= maximum, goal % step == 0,
              let remaining, remaining == max(0, goal - done), achieved == (done >= goal) else { return false }
        return true
    }
}

private enum BackendProgressDate {
    static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    static func parse(_ value: String) -> Date? {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) }) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isValidRange(from: String, to: String) -> Bool {
        dayDistance(from: from, to: to).map({ $0 < 366 }) == true
    }

    static func dayDistance(from: String, to: String) -> Int? {
        guard let first = parse(from), let last = parse(to), last >= first else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.day], from: first, to: last).day
    }

    static func isValidWeek(from: String, to: String) -> Bool {
        guard let first = parse(from), let last = parse(to) else { return false }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.weekday, from: first) == 2
            && calendar.date(byAdding: .day, value: 6, to: first).map { calendar.isDate($0, inSameDayAs: last) } == true
    }

    static func parseTimestamp(_ value: String) throws -> Date {
        guard value.hasSuffix("+09:00") else { throw ProgressGoalsFailure.invalidResponse }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw ProgressGoalsFailure.invalidResponse }
        return date
    }
}

private func decodeRequiredNullable<Value: Decodable, Key: CodingKey>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> Value? {
    guard container.contains(key) else {
        throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "The backend contract requires this nullable field."))
    }
    return try container.decodeIfPresent(type, forKey: key)
}

enum ProgressReadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(BackendProgressSummary)
    case failed(ProgressGoalsFailure)
}

enum WeeklyGoalReadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(BackendWeeklyGoalStatus)
    case failed(ProgressGoalsFailure)
}

enum WeeklyGoalWriteState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed(ProgressGoalsFailure)
}

enum DailyProgressReadState: Equatable, Sendable {
    case idle
    case loading(BackendDailyProgressRange)
    case loaded(BackendDailyProgress)
    case failed(BackendDailyProgressRange, ProgressGoalsFailure)
}

actor RunningProgressLoader {
    private let client: any RunningProgressReading
    private var progressGeneration: UInt64 = 0
    private var weeklyGoalGeneration: UInt64 = 0
    private var dailyGeneration: UInt64 = 0
    private(set) var progressState: ProgressReadState = .idle
    private(set) var weeklyGoalState: WeeklyGoalReadState = .idle
    private(set) var dailyState: DailyProgressReadState = .idle

    init(client: any RunningProgressReading) { self.client = client }

    func loadProgress() async -> ProgressReadState {
        progressGeneration &+= 1
        let generation = progressGeneration
        progressState = .loading
        do {
            let summary = try await client.fetchProgress()
            guard generation == progressGeneration else { return progressState }
            progressState = .loaded(summary)
        } catch let failure as ProgressGoalsFailure {
            guard generation == progressGeneration else { return progressState }
            progressState = .failed(failure)
        } catch is CancellationError {
            guard generation == progressGeneration else { return progressState }
            progressState = .failed(.cancelled)
        } catch {
            guard generation == progressGeneration else { return progressState }
            progressState = .failed(.invalidResponse)
        }
        return progressState
    }

    func retryProgress() async -> ProgressReadState {
        guard case .failed = progressState else { return progressState }
        return await loadProgress()
    }

    func loadWeeklyGoal() async -> WeeklyGoalReadState {
        weeklyGoalGeneration &+= 1
        let generation = weeklyGoalGeneration
        weeklyGoalState = .loading
        do {
            let goal = try await client.fetchWeeklyGoal()
            guard generation == weeklyGoalGeneration else { return weeklyGoalState }
            weeklyGoalState = .loaded(goal)
        } catch let failure as ProgressGoalsFailure {
            guard generation == weeklyGoalGeneration else { return weeklyGoalState }
            weeklyGoalState = .failed(failure)
        } catch is CancellationError {
            guard generation == weeklyGoalGeneration else { return weeklyGoalState }
            weeklyGoalState = .failed(.cancelled)
        } catch {
            guard generation == weeklyGoalGeneration else { return weeklyGoalState }
            weeklyGoalState = .failed(.invalidResponse)
        }
        return weeklyGoalState
    }

    func retryWeeklyGoal() async -> WeeklyGoalReadState {
        guard case .failed = weeklyGoalState else { return weeklyGoalState }
        return await loadWeeklyGoal()
    }

    func loadDaily(range: BackendDailyProgressRange) async {
        dailyGeneration &+= 1
        let generation = dailyGeneration
        dailyState = .loading(range)
        do {
            let daily = try await client.fetchDaily(range: range)
            guard generation == dailyGeneration else { return }
            dailyState = .loaded(daily)
        } catch let failure as ProgressGoalsFailure {
            guard generation == dailyGeneration else { return }
            dailyState = .failed(range, failure)
        } catch is CancellationError {
            guard generation == dailyGeneration else { return }
            dailyState = .failed(range, .cancelled)
        } catch {
            guard generation == dailyGeneration else { return }
            dailyState = .failed(range, .invalidResponse)
        }
    }

    func retryDaily(range: BackendDailyProgressRange) async {
        guard case .failed(let failedRange, _) = dailyState, failedRange == range else { return }
        await loadDaily(range: range)
    }
}
