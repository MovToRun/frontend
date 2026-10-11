import Foundation

enum APIEnvironment: String, Sendable {
    case development
    case production
}

struct APIClientConfiguration: Sendable {
    let environment: APIEnvironment
    let baseURL: URL
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval

    init(environment: APIEnvironment, baseURLString: String, requestTimeout: TimeInterval, resourceTimeout: TimeInterval) throws {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIClientError.missingBaseURL }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.url != nil else {
            throw APIClientError.invalidBaseURL
        }
        guard scheme == "https" else { throw APIClientError.insecureBaseURL }
        let encodedPath = components.percentEncodedPath
        let basePathSegments = encodedPath.split(separator: "/", omittingEmptySubsequences: false)
        let allowedBasePathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        guard !encodedPath.contains("%"),
              encodedPath.unicodeScalars.allSatisfy(allowedBasePathCharacters.contains),
              basePathSegments.enumerated().allSatisfy({ index, segment in
                  if segment.isEmpty { return index == 0 || index == basePathSegments.count - 1 }
                  return segment != "." && segment != ".."
              }) else {
            throw APIClientError.invalidBaseURL
        }
        guard requestTimeout.isFinite, requestTimeout > 0,
              resourceTimeout.isFinite, resourceTimeout >= requestTimeout else {
            throw APIClientError.invalidTimeout
        }

        var normalizedComponents = components
        if !normalizedComponents.path.hasSuffix("/") { normalizedComponents.path += "/" }
        guard let normalizedURL = normalizedComponents.url else { throw APIClientError.invalidBaseURL }

        self.environment = environment
        self.baseURL = normalizedURL
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    static func bundled(from bundle: Bundle = .main) throws -> APIClientConfiguration {
        let environmentKey = "MovAPIEnvironment"
        let baseURLKey = "MovAPIBaseURL"
        let timeoutKey = "MovAPIRequestTimeoutSeconds"
        let resourceTimeoutKey = "MovAPIResourceTimeoutSeconds"

        guard let rawEnvironment = bundle.object(forInfoDictionaryKey: environmentKey) as? String,
              let environment = APIEnvironment(rawValue: rawEnvironment) else {
            throw APIClientError.missingEnvironment
        }
        guard let baseURL = bundle.object(forInfoDictionaryKey: baseURLKey) as? String else {
            throw APIClientError.missingBaseURL
        }
        let requestTimeout = (bundle.object(forInfoDictionaryKey: timeoutKey) as? NSString)?.doubleValue
            ?? (bundle.object(forInfoDictionaryKey: timeoutKey) as? NSNumber)?.doubleValue ?? 30
        let resourceTimeout = (bundle.object(forInfoDictionaryKey: resourceTimeoutKey) as? NSString)?.doubleValue
            ?? (bundle.object(forInfoDictionaryKey: resourceTimeoutKey) as? NSNumber)?.doubleValue ?? 60
        return try APIClientConfiguration(
            environment: environment,
            baseURLString: baseURL,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
    }
}

enum APIClientError: Error, Equatable {
    case missingEnvironment
    case missingBaseURL
    case invalidBaseURL
    case insecureBaseURL
    case invalidTimeout
    case invalidPath
    case invalidQuery
    case cancelled
    case unexpectedResponse
    case httpStatus(Int)
    case transport(URLError.Code)
}

struct APIClientResponse: Sendable {
    let statusCode: Int
    let data: Data
    let requestID: String?
}

final class APIClient: @unchecked Sendable {
    private let configuration: APIClientConfiguration
    private let session: URLSession

    init(configuration: APIClientConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            self.session = URLSession(configuration: Self.defaultSessionConfiguration(for: configuration))
        }
    }

    static func defaultSessionConfiguration(for configuration: APIClientConfiguration) -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
        return sessionConfiguration
    }

    func makeRequest(path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let allowedPathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pathSegments = path.split(separator: "/", omittingEmptySubsequences: false)
        let configuredBasePath = configuration.baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let repeatsConfiguredBasePath = !configuredBasePath.isEmpty
            && (path == configuredBasePath || path.hasPrefix(configuredBasePath + "/"))
        guard !path.isEmpty, !path.hasPrefix("/"),
              !repeatsConfiguredBasePath,
              pathSegments.allSatisfy({ segment in
                  !segment.isEmpty && segment != "." && segment != ".."
                      && segment.unicodeScalars.allSatisfy(allowedPathCharacters.contains)
              }),
              let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL,
              url.host == configuration.baseURL.host,
              url.scheme == "https",
              url.path.hasPrefix(configuration.baseURL.path) else {
            throw APIClientError.invalidPath
        }

        let allowedQueryNameCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard queryItems.allSatisfy({ item in
            !item.name.isEmpty
                && item.name.unicodeScalars.allSatisfy(allowedQueryNameCharacters.contains)
                && (item.value?.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ?? true)
        }) else {
            throw APIClientError.invalidQuery
        }

        var requestURL = url
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIClientError.invalidQuery
            }
            components.queryItems = queryItems
            guard let urlWithQuery = components.url else { throw APIClientError.invalidQuery }
            requestURL = urlWithQuery
        }

        var request = URLRequest(url: requestURL, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    func send(path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], queryItems: [URLQueryItem] = []) async throws -> Data {
        let response = try await sendResponse(path: path, method: method, body: body, headers: headers, queryItems: queryItems)
        guard (200..<300).contains(response.statusCode) else {
            throw APIClientError.httpStatus(response.statusCode)
        }
        return response.data
    }

    func sendResponse(path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], queryItems: [URLQueryItem] = []) async throws -> APIClientResponse {
        let request = try makeRequest(path: path, method: method, body: body, headers: headers, queryItems: queryItems)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw APIClientError.unexpectedResponse
            }
            return APIClientResponse(
                statusCode: response.statusCode,
                data: data,
                requestID: response.value(forHTTPHeaderField: "X-Request-Id")
            )
        } catch let error as APIClientError {
            throw error
        } catch is CancellationError {
            throw APIClientError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw APIClientError.cancelled }
            throw APIClientError.transport(error.code)
        } catch {
            throw APIClientError.transport(.unknown)
        }
    }
}

struct MemberProfile: Equatable, Sendable {
    let nickname: String
}

private struct MemberProfileResponse: Decodable, Sendable {
    let nickname: String

    var profile: MemberProfile { MemberProfile(nickname: nickname) }
}

private struct APIProblemResponse: Decodable {
    let code: String?
    let requestId: String?
}

protocol AccessTokenProviding: Sendable {
    /// Returns the current access token without refreshing, storing, or revoking it.
    func accessToken() async throws -> String?
}

protocol MemberProfileFetching: Sendable {
    func fetchProfile() async throws -> MemberProfile
}

enum MemberProfileFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case profileNotFound
    case serviceUnavailable(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case invalidResponse
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .profileNotFound, .invalidResponse:
            return "프로필을 불러오지 못했어요. 다시 시도해 주세요."
        case .serviceUnavailable:
            return "서비스가 잠시 불안정해요. 잠시 후 다시 시도해 주세요."
        case .serverFailure:
            return "프로필을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        }
    }
}

struct MemberProfileRetryPolicy: Sendable {
    let maximumAttempts: Int
    let delayNanoseconds: UInt64

    init(maximumAttempts: Int = 2, delayNanoseconds: UInt64 = 200_000_000) {
        self.maximumAttempts = min(2, max(1, maximumAttempts))
        self.delayNanoseconds = delayNanoseconds
    }
}

final class MemberProfileClient: MemberProfileFetching, Sendable {
    private let apiClient: APIClient
    private let tokenProvider: any AccessTokenProviding
    private let retryPolicy: MemberProfileRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    init(
        apiClient: APIClient,
        tokenProvider: any AccessTokenProviding,
        retryPolicy: MemberProfileRetryPolicy = MemberProfileRetryPolicy(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func fetchProfile() async throws -> MemberProfile {
        let token: String
        do {
            guard let value = try await tokenProvider.accessToken(),
                  !value.isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw MemberProfileFailure.accessTokenUnavailable
            }
            token = value
        } catch let failure as MemberProfileFailure {
            throw failure
        } catch is CancellationError {
            throw MemberProfileFailure.cancelled
        } catch {
            throw MemberProfileFailure.accessTokenUnavailable
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]

        for attempt in 1...retryPolicy.maximumAttempts {
            do {
                let response = try await apiClient.sendResponse(path: "members/me/profile", headers: headers)
                guard (200..<300).contains(response.statusCode) else {
                    let failure = mapFailure(response)
                    if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                        try await waitBeforeRetry()
                        continue
                    }
                    throw failure
                }

                do {
                    return try JSONDecoder().decode(MemberProfileResponse.self, from: response.data).profile
                } catch {
                    throw MemberProfileFailure.invalidResponse
                }
            } catch let failure as MemberProfileFailure {
                if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch let error as APIClientError {
                let failure = mapFailure(error)
                if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch is CancellationError {
                throw MemberProfileFailure.cancelled
            } catch {
                throw MemberProfileFailure.invalidResponse
            }
        }

        throw MemberProfileFailure.invalidResponse
    }

    private func waitBeforeRetry() async throws {
        do {
            try await sleep(retryPolicy.delayNanoseconds)
        } catch {
            throw MemberProfileFailure.cancelled
        }
    }

    private func mapFailure(_ response: APIClientResponse) -> MemberProfileFailure {
        let problem = try? JSONDecoder().decode(APIProblemResponse.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401:
            return .unauthenticated
        case 404:
            return .profileNotFound
        case 503 where problem?.code == "AUTH_UNAVAILABLE":
            return .serviceUnavailable(requestID: requestID)
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func mapFailure(_ error: APIClientError) -> MemberProfileFailure {
        switch error {
        case .cancelled:
            return .cancelled
        case .transport(let code):
            return .transport(code)
        default:
            return .invalidResponse
        }
    }
}

private extension MemberProfileFailure {
    var isRetryable: Bool {
        switch self {
        case .serviceUnavailable:
            return true
        case .transport(let code):
            return [
                .timedOut,
                .cannotConnectToHost,
                .networkConnectionLost,
                .notConnectedToInternet,
                .dnsLookupFailed
            ].contains(code)
        default:
            return false
        }
    }
}

enum MemberProfileLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(MemberProfile)
    case failed(MemberProfileFailure)
}

actor MemberProfileLoader {
    private let fetcher: any MemberProfileFetching
    private var loadGeneration: UInt64 = 0
    private(set) var state: MemberProfileLoadState = .idle

    init(fetcher: any MemberProfileFetching) {
        self.fetcher = fetcher
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        state = .loading

        do {
            let profile = try await fetcher.fetchProfile()
            guard generation == loadGeneration else { return }
            state = .loaded(profile)
        } catch let failure as MemberProfileFailure {
            guard generation == loadGeneration else { return }
            state = .failed(failure)
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            state = .failed(.cancelled)
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed(.invalidResponse)
        }
    }

    func retry() async {
        guard case .failed = state else { return }
        await load()
    }
}

struct PointsBalance: Equatable, Sendable {
    let balancePoints: Int64
}

enum PointsDirection: String, Decodable, Equatable, Sendable {
    case credit = "CREDIT"
    case debit = "DEBIT"
}

struct PointsLedgerEntry: Identifiable, Equatable, Sendable {
    let entryID: String
    let direction: PointsDirection
    let deltaPoints: Int64
    let balanceAfterPoints: Int64
    let reasonCode: String
    let createdAt: Date

    var id: String { entryID }
}

struct PointsLedgerPage: Equatable, Sendable {
    let entries: [PointsLedgerEntry]
    let nextCursor: String?
}

private struct PointsBalanceResponse: Decodable {
    let balancePoints: Int64
}

private struct PointsLedgerResponse: Decodable {
    let entries: [PointsLedgerEntryResponse]
    let nextCursor: String?
}

private struct PointsLedgerEntryResponse: Decodable {
    let entryId: String
    let direction: PointsDirection
    let deltaPoints: Int64
    let balanceAfterPoints: Int64
    let reasonCode: String
    let createdAt: Date

    var entry: PointsLedgerEntry {
        PointsLedgerEntry(
            entryID: entryId,
            direction: direction,
            deltaPoints: deltaPoints,
            balanceAfterPoints: balanceAfterPoints,
            reasonCode: reasonCode,
            createdAt: createdAt
        )
    }
}

enum PointsReadFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case pointsUnavailable(requestID: String?)
    case invalidPageSize
    case invalidResponse
    case paginationLoop
    case serverFailure(statusCode: Int, requestID: String?)
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인해 주세요."
        case .pointsUnavailable:
            return "포인트 정보를 잠시 불러올 수 없어요. 다시 시도해 주세요."
        case .invalidPageSize:
            return "포인트 내역 요청의 페이지 크기를 확인해 주세요."
        case .invalidResponse, .paginationLoop:
            return "포인트 내역을 불러오지 못했어요. 다시 시도해 주세요."
        case .serverFailure(let statusCode, _) where (500...599).contains(statusCode):
            return "포인트 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .serverFailure:
            return "포인트 정보를 불러오지 못했어요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        }
    }
}

struct PointsReadRetryPolicy: Sendable {
    let maximumAttempts: Int
    let delayNanoseconds: UInt64

    init(maximumAttempts: Int = 2, delayNanoseconds: UInt64 = 200_000_000) {
        self.maximumAttempts = min(2, max(1, maximumAttempts))
        self.delayNanoseconds = delayNanoseconds
    }
}

protocol PointsWalletReading: Sendable {
    func fetchBalance() async throws -> PointsBalance
    func fetchEntries(cursor: String?, size: Int) async throws -> PointsLedgerPage
}

final class PointsWalletClient: PointsWalletReading, Sendable {
    static let defaultPageSize = 20
    static let maximumPageSize = 50

    private let apiClient: APIClient
    private let tokenProvider: any AccessTokenProviding
    private let retryPolicy: PointsReadRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    init(
        apiClient: APIClient,
        tokenProvider: any AccessTokenProviding,
        retryPolicy: PointsReadRetryPolicy = PointsReadRetryPolicy(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func fetchBalance() async throws -> PointsBalance {
        let response = try await sendAuthorized(path: "points/me")
        do {
            let decoded = try JSONDecoder().decode(PointsBalanceResponse.self, from: response.data)
            guard decoded.balancePoints >= 0 else { throw PointsReadFailure.invalidResponse }
            return PointsBalance(balancePoints: decoded.balancePoints)
        } catch let failure as PointsReadFailure {
            throw failure
        } catch {
            throw PointsReadFailure.invalidResponse
        }
    }

    func fetchEntries(cursor: String? = nil, size: Int = defaultPageSize) async throws -> PointsLedgerPage {
        guard (1...Self.maximumPageSize).contains(size) else {
            throw PointsReadFailure.invalidPageSize
        }

        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        queryItems.append(URLQueryItem(name: "size", value: String(size)))

        let response = try await sendAuthorized(path: "points/me/entries", queryItems: queryItems)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(PointsLedgerResponse.self, from: response.data)
            guard decoded.entries.count <= size,
                  decoded.entries.allSatisfy({
                      !$0.entryId.isEmpty && !$0.reasonCode.isEmpty && $0.balanceAfterPoints >= 0
                  }),
                  decoded.nextCursor != "" else {
                throw PointsReadFailure.invalidResponse
            }
            return PointsLedgerPage(entries: decoded.entries.map(\.entry), nextCursor: decoded.nextCursor)
        } catch let failure as PointsReadFailure {
            throw failure
        } catch {
            throw PointsReadFailure.invalidResponse
        }
    }

    private func sendAuthorized(path: String, queryItems: [URLQueryItem] = []) async throws -> APIClientResponse {
        let token: String
        do {
            guard let value = try await tokenProvider.accessToken(),
                  !value.isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw PointsReadFailure.accessTokenUnavailable
            }
            token = value
        } catch let failure as PointsReadFailure {
            throw failure
        } catch is CancellationError {
            throw PointsReadFailure.cancelled
        } catch {
            throw PointsReadFailure.accessTokenUnavailable
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]

        for attempt in 1...retryPolicy.maximumAttempts {
            do {
                let response = try await apiClient.sendResponse(path: path, headers: headers, queryItems: queryItems)
                guard (200..<300).contains(response.statusCode) else {
                    let failure = mapFailure(response)
                    if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                        try await waitBeforeRetry()
                        continue
                    }
                    throw failure
                }
                return response
            } catch let failure as PointsReadFailure {
                if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch let error as APIClientError {
                let failure = mapFailure(error)
                if attempt < retryPolicy.maximumAttempts, failure.isRetryable {
                    try await waitBeforeRetry()
                    continue
                }
                throw failure
            } catch is CancellationError {
                throw PointsReadFailure.cancelled
            } catch {
                throw PointsReadFailure.invalidResponse
            }
        }

        throw PointsReadFailure.invalidResponse
    }

    private func waitBeforeRetry() async throws {
        do {
            try await sleep(retryPolicy.delayNanoseconds)
        } catch {
            throw PointsReadFailure.cancelled
        }
    }

    private func mapFailure(_ response: APIClientResponse) -> PointsReadFailure {
        let problem = try? JSONDecoder().decode(APIProblemResponse.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401:
            return .unauthenticated
        case 503 where problem?.code == "POINT_UNAVAILABLE":
            return .pointsUnavailable(requestID: requestID)
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func mapFailure(_ error: APIClientError) -> PointsReadFailure {
        switch error {
        case .cancelled:
            return .cancelled
        case .transport(let code):
            return .transport(code)
        default:
            return .invalidResponse
        }
    }
}

private extension PointsReadFailure {
    var canManuallyRetry: Bool {
        switch self {
        case .pointsUnavailable, .invalidResponse, .paginationLoop:
            return true
        case .serverFailure(let statusCode, _):
            return (500...599).contains(statusCode)
        case .transport:
            return true
        case .accessTokenUnavailable, .unauthenticated, .invalidPageSize, .cancelled:
            return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .pointsUnavailable:
            return true
        case .transport(let code):
            return [
                .timedOut,
                .cannotConnectToHost,
                .networkConnectionLost,
                .notConnectedToInternet,
                .dnsLookupFailed
            ].contains(code)
        default:
            return false
        }
    }
}

struct PointsWalletSnapshot: Equatable, Sendable {
    let balance: PointsBalance
    let entries: [PointsLedgerEntry]
    let nextCursor: String?

    func appending(_ page: PointsLedgerPage) -> PointsWalletSnapshot {
        PointsWalletSnapshot(balance: balance, entries: entries + page.entries, nextCursor: page.nextCursor)
    }
}

enum PointsWalletReadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(PointsWalletSnapshot)
    case loadingMore(PointsWalletSnapshot)
    case failed(PointsReadFailure)
    case failedLoadingMore(PointsWalletSnapshot, PointsReadFailure)
}

actor PointsWalletLoader {
    private let client: any PointsWalletReading
    private let pageSize: Int
    private var generation: UInt64 = 0
    private var consumedCursors: Set<String> = []
    private(set) var state: PointsWalletReadState = .idle

    init(client: any PointsWalletReading, pageSize: Int = PointsWalletClient.defaultPageSize) {
        self.client = client
        self.pageSize = pageSize
    }

    func load() async {
        generation &+= 1
        let requestGeneration = generation
        consumedCursors.removeAll()
        state = .loading

        guard (1...PointsWalletClient.maximumPageSize).contains(pageSize) else {
            state = .failed(.invalidPageSize)
            return
        }

        do {
            let balance = try await client.fetchBalance()
            guard requestGeneration == generation else { return }
            let firstPage = try await client.fetchEntries(cursor: nil, size: pageSize)
            guard requestGeneration == generation else { return }
            state = .loaded(PointsWalletSnapshot(balance: balance, entries: firstPage.entries, nextCursor: firstPage.nextCursor))
        } catch let failure as PointsReadFailure {
            guard requestGeneration == generation else { return }
            state = .failed(failure)
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            state = .failed(.cancelled)
        } catch {
            guard requestGeneration == generation else { return }
            state = .failed(.invalidResponse)
        }
    }

    func loadNextPage() async {
        let snapshot: PointsWalletSnapshot
        switch state {
        case .loaded(let current), .failedLoadingMore(let current, _):
            snapshot = current
        default:
            return
        }

        guard let cursor = snapshot.nextCursor else { return }
        guard !consumedCursors.contains(cursor) else {
            state = .failedLoadingMore(snapshot, .paginationLoop)
            return
        }

        generation &+= 1
        let requestGeneration = generation
        state = .loadingMore(snapshot)
        do {
            let page = try await client.fetchEntries(cursor: cursor, size: pageSize)
            guard requestGeneration == generation else { return }

            var nextConsumedCursors = consumedCursors
            nextConsumedCursors.insert(cursor)
            if let nextCursor = page.nextCursor, nextConsumedCursors.contains(nextCursor) {
                state = .failedLoadingMore(snapshot, .paginationLoop)
                return
            }

            consumedCursors = nextConsumedCursors
            state = .loaded(snapshot.appending(page))
        } catch let failure as PointsReadFailure {
            guard requestGeneration == generation else { return }
            switch failure {
            case .accessTokenUnavailable, .unauthenticated:
                state = .failed(failure)
            default:
                state = .failedLoadingMore(snapshot, failure)
            }
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            state = .failedLoadingMore(snapshot, .cancelled)
        } catch {
            guard requestGeneration == generation else { return }
            state = .failedLoadingMore(snapshot, .invalidResponse)
        }
    }

    func retry() async {
        switch state {
        case .failed(let failure) where failure.canManuallyRetry:
            await load()
        case .failedLoadingMore(_, .invalidResponse), .failedLoadingMore(_, .paginationLoop):
            await load()
        case .failedLoadingMore(_, let failure) where failure.canManuallyRetry:
            await loadNextPage()
        default:
            return
        }
    }
}
