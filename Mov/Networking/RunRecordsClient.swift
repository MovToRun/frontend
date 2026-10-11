import Foundation

struct BackendRunPointReward: Equatable, Sendable {
    enum Status: String, Decodable, Sendable {
        case pending = "PENDING"
        case settled = "SETTLED"
        case unavailable = "UNAVAILABLE"
    }

    let status: Status
    let pointsAwarded: Int64?
}

struct BackendRunSummary: Equatable, Sendable, Identifiable {
    let id: String
    let clientRunID: UUID
    let version: Int64
    let startedAt: Date
    let endedAt: Date?
    /// The server's KST calendar date, kept as its canonical yyyy-MM-dd value.
    let runDate: String
    let elapsedSeconds: Int64
    let movingSeconds: Int64
    let distanceMeters: Int64
    let verdict: String
    let verdictReason: String?
    let validDistanceMeters: Int64?
    let validSeconds: Int64?
    let paceSecondsPerKm: Int64?
    let title: String?
    let memo: String?
    let createdAt: Date
    let updatedAt: Date
    let pointReward: BackendRunPointReward?
}

struct BackendRunPage: Equatable, Sendable {
    let items: [BackendRunSummary]
    /// Opaque server value; callers must not inspect or transform it.
    let nextCursor: String?
}

struct BackendRunPoint: Equatable, Sendable {
    let recordedAt: Date
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let altitudeMeters: Double?
    let speedMetersPerSecond: Double?
}

struct BackendRunPause: Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
}

struct BackendRunExclusion: Equatable, Sendable {
    let reason: String
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Int64
    let seconds: Int64
}

struct BackendRunJudgement: Equatable, Sendable {
    let algorithmVersion: String
    let exclusions: [BackendRunExclusion]
    let inaccuratePoints: Int64
    let jumpPoints: Int64
}

struct BackendRunDetail: Equatable, Sendable {
    let summary: BackendRunSummary
    let points: [BackendRunPoint]
    let pauses: [BackendRunPause]
    let judgement: BackendRunJudgement?
}

struct BackendRunSnapshot: Equatable, Sendable {
    let items: [BackendRunSummary]
    let nextCursor: String?

    func appending(_ page: BackendRunPage) -> BackendRunSnapshot {
        BackendRunSnapshot(items: items + page.items, nextCursor: page.nextCursor)
    }
}

enum RunRecordsFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case recordNotFound
    case versionConflict
    case versionConflictRefreshFailed
    case invalidEdit
    case invalidPageSize
    case invalidResponse
    case paginationLoop
    case serverFailure(statusCode: Int, requestID: String?)
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .recordNotFound:
            return "이 러닝 기록을 찾을 수 없어요. 목록을 새로고침해 주세요."
        case .versionConflict:
            return "다른 곳에서 기록이 변경됐어요. 초안은 유지했어요. 완료를 다시 누르면 최신 기록에 적용해요."
        case .versionConflictRefreshFailed:
            return "다른 곳에서 기록이 변경됐어요. 초안은 유지했어요. 최신 기록을 확인하지 못했어요. 잠시 후 다시 완료해 주세요."
        case .invalidEdit:
            return "제목은 40자, 메모는 300자 이내로 입력해 주세요."
        case .invalidPageSize, .invalidResponse, .paginationLoop:
            return "러닝 기록을 불러오지 못했어요. 다시 시도해 주세요."
        case .serverFailure(let statusCode, _) where (500...599).contains(statusCode):
            return "러닝 기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .serverFailure:
            return "러닝 기록을 불러오지 못했어요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        }
    }

    var canManuallyRetry: Bool {
        switch self {
        case .invalidResponse, .paginationLoop, .serverFailure, .transport:
            true
        case .accessTokenUnavailable, .unauthenticated, .recordNotFound, .versionConflict, .versionConflictRefreshFailed, .invalidEdit, .invalidPageSize, .cancelled:
            false
        }
    }

    var editMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .recordNotFound:
            return "이 러닝 기록에 저장하지 못했어요. 초안은 이 화면에 남아 있고, 목록으로 돌아가면 서버 기록을 다시 확인해요."
        case .versionConflict, .versionConflictRefreshFailed, .invalidEdit:
            return userMessage
        case .serverFailure(let statusCode, _) where (500...599).contains(statusCode):
            return "저장하지 못했어요. 잠시 후 다시 완료해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 완료해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        case .invalidPageSize, .invalidResponse, .paginationLoop, .serverFailure:
            return "저장 결과를 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
}

struct RunRecordsRetryPolicy: Sendable {
    let maximumAttempts: Int
    let delayNanoseconds: UInt64

    init(maximumAttempts: Int = 2, delayNanoseconds: UInt64 = 200_000_000) {
        self.maximumAttempts = min(2, max(1, maximumAttempts))
        self.delayNanoseconds = delayNanoseconds
    }
}

protocol RunRecordsReading: Sendable {
    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage
    func fetchRun(id: String) async throws -> BackendRunDetail
}

enum BackendRunEditField: Equatable, Sendable {
    case title
    case memo
}

struct BackendRunEditPatch: Equatable, Sendable {
    /// `nil` omits the field; an empty string explicitly clears it.
    let title: String?
    /// `nil` omits the field; an empty string explicitly clears it.
    let memo: String?

    init(title: String? = nil, memo: String? = nil) {
        self.title = title
        self.memo = memo
    }

    var field: BackendRunEditField? {
        if title != nil, memo == nil { return .title }
        if memo != nil, title == nil { return .memo }
        return nil
    }

    func value(for field: BackendRunEditField) -> String? {
        switch field {
        case .title: title
        case .memo: memo
        }
    }
}

protocol RunRecordsUpdating: Sendable {
    func updateRun(id: String, version: Int64, patch: BackendRunEditPatch) async throws -> BackendRunSummary
}

final class RunRecordsClient: RunRecordsReading, RunRecordsUpdating, Sendable {
    static let defaultPageSize = 20
    static let maximumPageSize = 50

    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding
    private let retryPolicy: RunRecordsRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    init(
        apiClient: any APIResponseSending,
        tokenProvider: any AccessTokenProviding,
        retryPolicy: RunRecordsRetryPolicy = RunRecordsRetryPolicy(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func fetchRuns(cursor: String? = nil, size: Int = defaultPageSize) async throws -> BackendRunPage {
        guard (1...Self.maximumPageSize).contains(size) else { throw RunRecordsFailure.invalidPageSize }
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        queryItems.append(URLQueryItem(name: "size", value: String(size)))

        let response = try await sendAuthorized(path: "runs", queryItems: queryItems)
        do {
            let wire = try JSONDecoder().decode(RunListResponse.self, from: response.data)
            guard wire.items.count <= size, wire.nextCursor != "" else { throw RunRecordsFailure.invalidResponse }
            let items = try wire.items.map { try $0.value() }
            guard Set(items.map(\.id)).count == items.count else { throw RunRecordsFailure.invalidResponse }
            return BackendRunPage(items: items, nextCursor: wire.nextCursor)
        } catch let failure as RunRecordsFailure {
            throw failure
        } catch {
            throw RunRecordsFailure.invalidResponse
        }
    }

    func fetchRun(id: String) async throws -> BackendRunDetail {
        guard Self.isSafeRunID(id) else { throw RunRecordsFailure.invalidResponse }
        let response = try await sendAuthorized(path: "runs/\(id)")
        do {
            let wire = try JSONDecoder().decode(RunDetailResponse.self, from: response.data)
            return try wire.value()
        } catch let failure as RunRecordsFailure {
            throw failure
        } catch {
            throw RunRecordsFailure.invalidResponse
        }
    }

    func updateRun(id: String, version: Int64, patch: BackendRunEditPatch) async throws -> BackendRunSummary {
        guard Self.isSafeRunID(id), version >= 0, patch.field != nil,
              patch.title.map({ $0.utf16.count <= 40 }) ?? true,
              patch.memo.map({ $0.utf16.count <= 300 }) ?? true else {
            throw RunRecordsFailure.invalidEdit
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(RunUpdateRequest(version: version, title: patch.title, memo: patch.memo))
        } catch {
            throw RunRecordsFailure.invalidResponse
        }

        let response = try await sendAuthorized(
            path: "runs/\(id)", method: "PATCH", body: body, contentType: "application/json", retriesEnabled: false
        )
        do {
            let summary = try JSONDecoder().decode(RunSummaryResponse.self, from: response.data).value()
            guard summary.id == id, version < Int64.max, summary.version == version + 1 else {
                throw RunRecordsFailure.invalidResponse
            }
            return summary
        } catch let failure as RunRecordsFailure {
            throw failure
        } catch {
            throw RunRecordsFailure.invalidResponse
        }
    }

    private func sendAuthorized(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        queryItems: [URLQueryItem] = [],
        retriesEnabled: Bool = true
    ) async throws -> APIClientResponse {
        let token: String
        do {
            guard let value = try await tokenProvider.accessToken(),
                  !value.isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw RunRecordsFailure.accessTokenUnavailable
            }
            token = value
        } catch let failure as RunRecordsFailure {
            throw failure
        } catch is CancellationError {
            throw RunRecordsFailure.cancelled
        } catch {
            throw RunRecordsFailure.accessTokenUnavailable
        }

        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]
        if let contentType { headers["Content-Type"] = contentType }

        for attempt in 1...retryPolicy.maximumAttempts {
            do {
                let response = try await apiClient.sendResponse(path: path, method: method, body: body, headers: headers, queryItems: queryItems)
                guard (200..<300).contains(response.statusCode) else {
                    let failure = mapFailure(response, isDetail: path != "runs", isEdit: method == "PATCH")
                    if retriesEnabled, attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                        try await waitBeforeRetry()
                        continue
                    }
                    throw failure
                }
                return response
            } catch let failure as RunRecordsFailure {
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
                throw RunRecordsFailure.cancelled
            } catch {
                throw RunRecordsFailure.invalidResponse
            }
        }
        throw RunRecordsFailure.invalidResponse
    }

    private func waitBeforeRetry() async throws {
        do { try await sleep(retryPolicy.delayNanoseconds) }
        catch { throw RunRecordsFailure.cancelled }
    }

    private func mapFailure(_ response: APIClientResponse, isDetail: Bool, isEdit: Bool = false) -> RunRecordsFailure {
        let problem = try? JSONDecoder().decode(RunProblemResponse.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401:
            return .unauthenticated
        case 404 where isDetail:
            return .recordNotFound
        case 409 where isEdit && problem?.code == "VERSION_CONFLICT":
            return .versionConflict
        case 400 where isEdit:
            return .invalidEdit
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func mapFailure(_ error: APIClientError) -> RunRecordsFailure {
        switch error {
        case .cancelled: .cancelled
        case .transport(let code): .transport(code)
        default: .invalidResponse
        }
    }

    private static func isSafeRunID(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return !value.isEmpty && value != "." && value != ".." && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

private extension RunRecordsFailure {
    var isRetryable: Bool {
        switch self {
        case .serverFailure(let statusCode, _): (500...599).contains(statusCode)
        case .transport(let code): [
            .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed
        ].contains(code)
        default: false
        }
    }
}

private struct RunListResponse: Decodable {
    let items: [RunSummaryResponse]
    let nextCursor: String?
}

private struct RunProblemResponse: Decodable {
    let code: String?
    let requestId: String?
}

private struct RunUpdateRequest: Encodable {
    let version: Int64
    let title: String?
    let memo: String?
}

private struct RunSummaryResponse: Decodable {
    let id: String
    let clientRunId: UUID
    let version: Int64
    let startedAt: String
    let endedAt: String?
    let runDate: String
    let elapsedSeconds: Int64
    let movingSeconds: Int64
    let distanceMeters: Int64
    let verdict: String
    let verdictReason: String?
    let validDistanceMeters: Int64?
    let validSeconds: Int64?
    let paceSecondsPerKm: Int64?
    let title: String?
    let memo: String?
    let createdAt: String
    let updatedAt: String
    let pointReward: PointRewardResponse?

    private enum CodingKeys: String, CodingKey {
        case id, clientRunId, version, startedAt, endedAt, runDate, elapsedSeconds, movingSeconds, distanceMeters
        case verdict, verdictReason, validDistanceMeters, validSeconds, paceSecondsPerKm, title, memo
        case createdAt, updatedAt, pointReward
    }

    init(
        id: String, clientRunId: UUID, version: Int64, startedAt: String, endedAt: String?, runDate: String,
        elapsedSeconds: Int64, movingSeconds: Int64, distanceMeters: Int64, verdict: String, verdictReason: String?,
        validDistanceMeters: Int64?, validSeconds: Int64?, paceSecondsPerKm: Int64?, title: String?, memo: String?,
        createdAt: String, updatedAt: String, pointReward: PointRewardResponse?
    ) {
        self.id = id; self.clientRunId = clientRunId; self.version = version; self.startedAt = startedAt; self.endedAt = endedAt
        self.runDate = runDate; self.elapsedSeconds = elapsedSeconds; self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters; self.verdict = verdict; self.verdictReason = verdictReason
        self.validDistanceMeters = validDistanceMeters; self.validSeconds = validSeconds; self.paceSecondsPerKm = paceSecondsPerKm
        self.title = title; self.memo = memo; self.createdAt = createdAt; self.updatedAt = updatedAt; self.pointReward = pointReward
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        clientRunId = try container.decode(UUID.self, forKey: .clientRunId)
        version = try container.decode(Int64.self, forKey: .version)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try decodeRequiredNullable(String.self, from: container, forKey: .endedAt)
        runDate = try container.decode(String.self, forKey: .runDate)
        elapsedSeconds = try container.decode(Int64.self, forKey: .elapsedSeconds)
        movingSeconds = try container.decode(Int64.self, forKey: .movingSeconds)
        distanceMeters = try container.decode(Int64.self, forKey: .distanceMeters)
        verdict = try container.decode(String.self, forKey: .verdict)
        verdictReason = try decodeRequiredNullable(String.self, from: container, forKey: .verdictReason)
        validDistanceMeters = try decodeRequiredNullable(Int64.self, from: container, forKey: .validDistanceMeters)
        validSeconds = try decodeRequiredNullable(Int64.self, from: container, forKey: .validSeconds)
        paceSecondsPerKm = try decodeRequiredNullable(Int64.self, from: container, forKey: .paceSecondsPerKm)
        title = try decodeRequiredNullable(String.self, from: container, forKey: .title)
        memo = try decodeRequiredNullable(String.self, from: container, forKey: .memo)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        pointReward = try decodeRequiredNullable(PointRewardResponse.self, from: container, forKey: .pointReward)
    }

    func value() throws -> BackendRunSummary {
        guard !id.isEmpty, version >= 0,
              ["VALID", "INVALID", "PENDING"].contains(verdict),
              Self.isRunDate(runDate),
              elapsedSeconds >= 0, movingSeconds >= 0, movingSeconds <= elapsedSeconds,
              distanceMeters >= 0,
              validDistanceMeters.map({ $0 >= 0 && $0 <= distanceMeters }) ?? true,
              validSeconds.map({ $0 >= 0 && $0 <= movingSeconds }) ?? true,
              paceSecondsPerKm.map({ $0 >= 0 }) ?? true else {
            throw RunRecordsFailure.invalidResponse
        }
        return BackendRunSummary(
            id: id,
            clientRunID: clientRunId,
            version: version,
            startedAt: try BackendRunTimestamp.parse(startedAt),
            endedAt: try endedAt.map(BackendRunTimestamp.parse),
            runDate: runDate,
            elapsedSeconds: elapsedSeconds,
            movingSeconds: movingSeconds,
            distanceMeters: distanceMeters,
            verdict: verdict,
            verdictReason: verdictReason,
            validDistanceMeters: validDistanceMeters,
            validSeconds: validSeconds,
            paceSecondsPerKm: paceSecondsPerKm,
            title: title,
            memo: memo,
            createdAt: try BackendRunTimestamp.parse(createdAt),
            updatedAt: try BackendRunTimestamp.parse(updatedAt),
            pointReward: try pointReward?.value()
        )
    }

    private static func isRunDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) }) else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
}

private struct PointRewardResponse: Decodable {
    let status: BackendRunPointReward.Status
    let pointsAwarded: Int64?

    private enum CodingKeys: String, CodingKey { case status, pointsAwarded }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(BackendRunPointReward.Status.self, forKey: .status)
        pointsAwarded = try decodeRequiredNullable(Int64.self, from: container, forKey: .pointsAwarded)
    }

    func value() throws -> BackendRunPointReward {
        switch status {
        case .pending where pointsAwarded == nil: break
        case .unavailable where pointsAwarded == nil: break
        case .settled where pointsAwarded.map({ $0 >= 0 }) == true: break
        default: throw RunRecordsFailure.invalidResponse
        }
        return BackendRunPointReward(status: status, pointsAwarded: pointsAwarded)
    }
}

private struct RunDetailResponse: Decodable {
    let id: String
    let clientRunId: UUID
    let version: Int64
    let startedAt: String
    let endedAt: String?
    let runDate: String
    let elapsedSeconds: Int64
    let movingSeconds: Int64
    let distanceMeters: Int64
    let verdict: String
    let verdictReason: String?
    let validDistanceMeters: Int64?
    let validSeconds: Int64?
    let paceSecondsPerKm: Int64?
    let title: String?
    let memo: String?
    let createdAt: String
    let updatedAt: String
    let pointReward: PointRewardResponse?
    let points: [PointResponse]
    let pauses: [PauseResponse]
    let judgement: JudgementResponse?

    private enum CodingKeys: String, CodingKey {
        case id, clientRunId, version, startedAt, endedAt, runDate, elapsedSeconds, movingSeconds, distanceMeters
        case verdict, verdictReason, validDistanceMeters, validSeconds, paceSecondsPerKm, title, memo
        case createdAt, updatedAt, pointReward, points, pauses, judgement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        clientRunId = try container.decode(UUID.self, forKey: .clientRunId)
        version = try container.decode(Int64.self, forKey: .version)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try decodeRequiredNullable(String.self, from: container, forKey: .endedAt)
        runDate = try container.decode(String.self, forKey: .runDate)
        elapsedSeconds = try container.decode(Int64.self, forKey: .elapsedSeconds)
        movingSeconds = try container.decode(Int64.self, forKey: .movingSeconds)
        distanceMeters = try container.decode(Int64.self, forKey: .distanceMeters)
        verdict = try container.decode(String.self, forKey: .verdict)
        verdictReason = try decodeRequiredNullable(String.self, from: container, forKey: .verdictReason)
        validDistanceMeters = try decodeRequiredNullable(Int64.self, from: container, forKey: .validDistanceMeters)
        validSeconds = try decodeRequiredNullable(Int64.self, from: container, forKey: .validSeconds)
        paceSecondsPerKm = try decodeRequiredNullable(Int64.self, from: container, forKey: .paceSecondsPerKm)
        title = try decodeRequiredNullable(String.self, from: container, forKey: .title)
        memo = try decodeRequiredNullable(String.self, from: container, forKey: .memo)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        pointReward = try decodeRequiredNullable(PointRewardResponse.self, from: container, forKey: .pointReward)
        points = try container.decode([PointResponse].self, forKey: .points)
        pauses = try container.decode([PauseResponse].self, forKey: .pauses)
        judgement = try decodeRequiredNullable(JudgementResponse.self, from: container, forKey: .judgement)
    }

    func value() throws -> BackendRunDetail {
        let summaryResponse = RunSummaryResponse(
            id: id, clientRunId: clientRunId, version: version, startedAt: startedAt, endedAt: endedAt,
            runDate: runDate, elapsedSeconds: elapsedSeconds, movingSeconds: movingSeconds,
            distanceMeters: distanceMeters, verdict: verdict, verdictReason: verdictReason,
            validDistanceMeters: validDistanceMeters, validSeconds: validSeconds,
            paceSecondsPerKm: paceSecondsPerKm, title: title, memo: memo,
            createdAt: createdAt, updatedAt: updatedAt, pointReward: pointReward
        )
        return BackendRunDetail(
            summary: try summaryResponse.value(),
            points: try points.map { try $0.value() },
            pauses: try pauses.map { try $0.value() },
            judgement: try judgement?.value()
        )
    }
}

private struct PointResponse: Decodable {
    let recordedAt: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let altitudeMeters: Double?
    let speedMetersPerSecond: Double?

    private enum CodingKeys: String, CodingKey { case recordedAt, latitude, longitude, accuracyMeters, altitudeMeters, speedMetersPerSecond }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordedAt = try container.decode(String.self, forKey: .recordedAt)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        accuracyMeters = try container.decode(Double.self, forKey: .accuracyMeters)
        altitudeMeters = try decodeRequiredNullable(Double.self, from: container, forKey: .altitudeMeters)
        speedMetersPerSecond = try decodeRequiredNullable(Double.self, from: container, forKey: .speedMetersPerSecond)
    }

    func value() throws -> BackendRunPoint {
        guard latitude.isFinite, (-90...90).contains(latitude), longitude.isFinite, (-180...180).contains(longitude),
              accuracyMeters.isFinite, accuracyMeters >= 0,
              altitudeMeters.map(\.isFinite) ?? true,
              speedMetersPerSecond.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw RunRecordsFailure.invalidResponse }
        return BackendRunPoint(
            recordedAt: try BackendRunTimestamp.parse(recordedAt), latitude: latitude, longitude: longitude,
            accuracyMeters: accuracyMeters, altitudeMeters: altitudeMeters, speedMetersPerSecond: speedMetersPerSecond
        )
    }
}

private func decodeRequiredNullable<Value: Decodable, Key: CodingKey>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> Value? {
    guard container.contains(key) else {
        throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "The backend contract requires this field, even when its value is null."))
    }
    return try container.decodeIfPresent(type, forKey: key)
}

private struct PauseResponse: Decodable {
    let startedAt: String
    let endedAt: String

    func value() throws -> BackendRunPause {
        BackendRunPause(startedAt: try BackendRunTimestamp.parse(startedAt), endedAt: try BackendRunTimestamp.parse(endedAt))
    }
}

private struct JudgementResponse: Decodable {
    let algorithmVersion: String
    let exclusions: [ExclusionResponse]
    let inaccuratePoints: Int64
    let jumpPoints: Int64

    func value() throws -> BackendRunJudgement {
        guard !algorithmVersion.isEmpty, inaccuratePoints >= 0, jumpPoints >= 0 else { throw RunRecordsFailure.invalidResponse }
        return BackendRunJudgement(
            algorithmVersion: algorithmVersion,
            exclusions: try exclusions.map { try $0.value() },
            inaccuratePoints: inaccuratePoints,
            jumpPoints: jumpPoints
        )
    }
}

private struct ExclusionResponse: Decodable {
    let reason: String
    let startedAt: String
    let endedAt: String
    let distanceMeters: Int64
    let seconds: Int64

    func value() throws -> BackendRunExclusion {
        guard !reason.isEmpty, distanceMeters >= 0, seconds >= 0 else { throw RunRecordsFailure.invalidResponse }
        return BackendRunExclusion(
            reason: reason, startedAt: try BackendRunTimestamp.parse(startedAt), endedAt: try BackendRunTimestamp.parse(endedAt),
            distanceMeters: distanceMeters, seconds: seconds
        )
    }
}

private enum BackendRunTimestamp {
    static func parse(_ value: String) throws -> Date {
        guard value.hasSuffix("+09:00") else { throw RunRecordsFailure.invalidResponse }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw RunRecordsFailure.invalidResponse }
        return date
    }
}

enum RunRecordsReadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(BackendRunSnapshot)
    case loadingMore(BackendRunSnapshot)
    case failed(RunRecordsFailure)
    case failedLoadingMore(BackendRunSnapshot, RunRecordsFailure)
}

enum RunDetailReadState: Equatable, Sendable {
    case idle
    case loading(runID: String)
    case loaded(BackendRunDetail)
    case failed(runID: String, RunRecordsFailure)
}

actor RunRecordsLoader {
    private let client: any RunRecordsReading
    private let pageSize: Int
    private var listGeneration: UInt64 = 0
    private var detailGeneration: UInt64 = 0
    private var consumedCursors: Set<String> = []
    private(set) var state: RunRecordsReadState = .idle
    private(set) var detailState: RunDetailReadState = .idle

    init(client: any RunRecordsReading, pageSize: Int = RunRecordsClient.defaultPageSize) {
        self.client = client
        self.pageSize = pageSize
    }

    func load() async {
        listGeneration &+= 1
        let requestGeneration = listGeneration
        consumedCursors.removeAll()
        state = .loading
        guard (1...RunRecordsClient.maximumPageSize).contains(pageSize) else { state = .failed(.invalidPageSize); return }
        do {
            let page = try await client.fetchRuns(cursor: nil, size: pageSize)
            guard requestGeneration == listGeneration else { return }
            state = .loaded(BackendRunSnapshot(items: page.items, nextCursor: page.nextCursor))
        } catch let failure as RunRecordsFailure {
            guard requestGeneration == listGeneration else { return }; state = .failed(failure)
        } catch is CancellationError {
            guard requestGeneration == listGeneration else { return }; state = .failed(.cancelled)
        } catch {
            guard requestGeneration == listGeneration else { return }; state = .failed(.invalidResponse)
        }
    }

    func loadNextPage() async {
        let snapshot: BackendRunSnapshot
        switch state {
        case .loaded(let value), .failedLoadingMore(let value, _): snapshot = value
        default: return
        }
        guard let cursor = snapshot.nextCursor else { return }
        guard !consumedCursors.contains(cursor) else { state = .failedLoadingMore(snapshot, .paginationLoop); return }
        listGeneration &+= 1
        let requestGeneration = listGeneration
        state = .loadingMore(snapshot)
        do {
            let page = try await client.fetchRuns(cursor: cursor, size: pageSize)
            guard requestGeneration == listGeneration else { return }
            var nextCursors = consumedCursors
            nextCursors.insert(cursor)
            if page.nextCursor.map(nextCursors.contains) == true {
                state = .failedLoadingMore(snapshot, .paginationLoop)
                return
            }
            consumedCursors = nextCursors
            state = .loaded(snapshot.appending(page))
        } catch let failure as RunRecordsFailure {
            guard requestGeneration == listGeneration else { return }
            switch failure {
            case .accessTokenUnavailable, .unauthenticated: state = .failed(failure)
            default: state = .failedLoadingMore(snapshot, failure)
            }
        } catch is CancellationError {
            guard requestGeneration == listGeneration else { return }; state = .failedLoadingMore(snapshot, .cancelled)
        } catch {
            guard requestGeneration == listGeneration else { return }; state = .failedLoadingMore(snapshot, .invalidResponse)
        }
    }

    func loadDetail(runID: String) async {
        detailGeneration &+= 1
        let requestGeneration = detailGeneration
        detailState = .loading(runID: runID)
        do {
            let detail = try await client.fetchRun(id: runID)
            guard requestGeneration == detailGeneration else { return }
            guard detail.summary.id == runID else { detailState = .failed(runID: runID, .invalidResponse); return }
            detailState = .loaded(detail)
        } catch let failure as RunRecordsFailure {
            guard requestGeneration == detailGeneration else { return }; detailState = .failed(runID: runID, failure)
        } catch is CancellationError {
            guard requestGeneration == detailGeneration else { return }; detailState = .failed(runID: runID, .cancelled)
        } catch {
            guard requestGeneration == detailGeneration else { return }; detailState = .failed(runID: runID, .invalidResponse)
        }
    }

    func retry() async {
        switch state {
        case .failed(let failure) where failure.canManuallyRetry: await load()
        case .failedLoadingMore(_, .invalidResponse), .failedLoadingMore(_, .paginationLoop): await load()
        case .failedLoadingMore(_, let failure) where failure.canManuallyRetry: await loadNextPage()
        default: return
        }
    }

    func retryDetail(runID: String) async {
        guard case .failed(let failedID, let failure) = detailState, failedID == runID, failure.canManuallyRetry else { return }
        await loadDetail(runID: runID)
    }

    func applyUpdatedSummary(_ summary: BackendRunSummary) {
        switch state {
        case .loaded(let snapshot): state = .loaded(snapshot.replacing(summary))
        case .loadingMore(let snapshot): state = .loadingMore(snapshot.replacing(summary))
        case .failedLoadingMore(let snapshot, let failure): state = .failedLoadingMore(snapshot.replacing(summary), failure)
        case .idle, .loading, .failed: break
        }
        if case .loaded(let detail) = detailState, detail.summary.id == summary.id {
            detailState = .loaded(BackendRunDetail(
                summary: summary, points: detail.points, pauses: detail.pauses, judgement: detail.judgement
            ))
        }
    }

    func cancelAll() {
        listGeneration &+= 1
        detailGeneration &+= 1
        state = .idle
        detailState = .idle
        consumedCursors.removeAll()
    }
}

private extension BackendRunSnapshot {
    func replacing(_ summary: BackendRunSummary) -> BackendRunSnapshot {
        BackendRunSnapshot(
            items: items.map { $0.id == summary.id ? summary : $0 },
            nextCursor: nextCursor
        )
    }
}
