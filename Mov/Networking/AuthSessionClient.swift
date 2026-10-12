import Foundation

protocol SessionLogoutRequesting: Sendable {
    func logout() async throws
}

enum SessionLogoutFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case serviceUnavailable(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case storageUnavailable
    case sessionChanged
    case invalidResponse
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable:
            return "로그아웃할 계정을 확인할 수 없어요. 로그인 상태를 유지한 채 다시 시도해 주세요."
        case .unauthenticated:
            return "로그인 상태가 만료됐어요. 로그인 화면으로 이동해요."
        case .serviceUnavailable:
            return "인증 서버가 잠시 응답하지 않아요. 로그인 상태를 유지하고 나중에 다시 시도해 주세요."
        case .storageUnavailable:
            return "로그아웃 상태를 저장하지 못했어요. 로그인 상태를 유지하고 다시 시도해 주세요."
        case .sessionChanged:
            return "계정 상태가 바뀌어 로그아웃 결과를 적용하지 못했어요. 현재 로그인 상태를 다시 확인해 주세요."
        case .serverFailure, .invalidResponse:
            return "로그아웃을 완료하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "로그아웃 요청이 취소됐어요."
        }
    }
}

enum AuthSessionFailure: Error, Equatable, Sendable {
    case invalidCredentials(requestID: String?)
    case unauthenticated
    case serviceUnavailable(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case invalidResponse
    case transport(URLError.Code)
    case cancelled
    case sessionUnavailable
    case storageUnavailable
    case sessionChanged
    case memberIdentityChanged
}

/// One atomic value contains the access token, refresh token, stable server member ID,
/// and the request ID paired with the current refresh token during recovery.
struct AuthSessionSnapshot: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let memberID: String
    let refreshRequestID: UUID?

    init(accessToken: String, refreshToken: String, memberID: String, refreshRequestID: UUID? = nil) throws {
        guard Self.isUsableToken(accessToken), Self.isUsableToken(refreshToken),
              Self.isCanonicalMemberID(memberID) else {
            throw AuthSessionFailure.invalidResponse
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.memberID = memberID
        self.refreshRequestID = refreshRequestID
    }

    private static func isUsableToken(_ token: String) -> Bool {
        !token.isEmpty && token.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
        }
    }

    static func isCanonicalMemberID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int64(value), number > 0 else { return false }
        return String(number) == value
    }
}

/// Implementations must replace this complete snapshot atomically. In particular, a
/// refresh token and its retry request ID may never be persisted as separate writes.
protocol AuthSessionStoring: Sendable {
    func loadSnapshot() throws -> AuthSessionSnapshot?
    func replaceAtomically(with snapshot: AuthSessionSnapshot?) throws
}

private struct AuthSessionProblem: Decodable {
    let code: String?
    let requestId: String?
}

private struct AuthTokenPairResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let accessExpiresInSeconds: Int
    let refreshExpiresInSeconds: Int
}

private struct AuthLoginRequest: Encodable {
    let email: String
    let password: String
    let deviceId: UUID
}

private struct AuthRefreshRequest: Encodable {
    let refreshToken: String
    let requestId: UUID
}

/// Owns only the client side of the bearer session. Token issuance, verification,
/// rotation, and authorization remain server responsibilities.
actor AuthSessionClient: SessionLogoutRequesting, AccessTokenProviding {
    private let apiClient: any APIResponseSending
    private let sessionStore: (any AuthSessionStoring)?
    private let legacyTokenProvider: (any AccessTokenProviding)?
    private var refreshInFlight: Task<AuthSessionSnapshot, Error>?
    /// Changes only when a login or logout invalidates/replaces the server session.
    /// A refresh response that began under an older generation cannot restore it.
    private var sessionGeneration: UInt64 = 0

    init(apiClient: any APIResponseSending, sessionStore: any AuthSessionStoring) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.legacyTokenProvider = nil
    }

    /// Kept for existing logout-only call sites. Login and refresh require an injected
    /// session store so token state and retry IDs have one atomic persistence boundary.
    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.sessionStore = nil
        self.legacyTokenProvider = tokenProvider
    }

    func login(email: String, password: String, deviceID: UUID) async throws -> AuthSessionSnapshot {
        let store = try requiredStore()
        let body: Data
        do {
            body = try JSONEncoder().encode(AuthLoginRequest(email: email, password: password, deviceId: deviceID))
        } catch {
            throw AuthSessionFailure.invalidResponse
        }

        let response: APIClientResponse
        do {
            response = try await apiClient.sendResponse(
                path: "auth/login",
                method: "POST",
                body: body,
                headers: Self.jsonHeaders,
                queryItems: []
            )
        } catch {
            throw Self.mapTransportFailure(error)
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response, isLogin: true) }

        let snapshot = try Self.decodeSession(response.data, refreshRequestID: nil)
        do {
            try store.replaceAtomically(with: snapshot)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        sessionGeneration &+= 1
        return snapshot
    }

    /// All callers in this actor share one network rotation. If a response is lost,
    /// the stored old refresh token and request ID remain the exact retry pair.
    func refresh() async throws -> AuthSessionSnapshot {
        if let refreshInFlight {
            return try await refreshInFlight.value
        }

        let task = Task { try await self.performRefresh() }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    func accessToken() async throws -> String? {
        if let sessionStore {
            do {
                return try sessionStore.loadSnapshot()?.accessToken
            } catch {
                throw AuthSessionFailure.storageUnavailable
            }
        }
        return try await legacyTokenProvider?.accessToken()
    }

    func logout() async throws {
        let startingGeneration = sessionGeneration
        let token: String?
        if let sessionStore {
            do {
                token = try sessionStore.loadSnapshot()?.accessToken
            } catch {
                throw SessionLogoutFailure.storageUnavailable
            }
        } else {
            do {
                token = try await legacyTokenProvider?.accessToken()
            } catch is CancellationError {
                throw SessionLogoutFailure.cancelled
            } catch {
                throw SessionLogoutFailure.accessTokenUnavailable
            }
        }
        guard let token, !token.isEmpty,
              token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw SessionLogoutFailure.accessTokenUnavailable
        }

        let response: APIClientResponse
        do {
            response = try await apiClient.sendResponse(
                path: "auth/logout",
                method: "POST",
                body: nil,
                headers: ["Authorization": "Bearer \(token)", "Accept": "application/json", "Cache-Control": "no-store"],
                queryItems: []
            )
        } catch let error as APIClientError {
            throw Self.mapLogoutFailure(error)
        } catch is CancellationError {
            throw SessionLogoutFailure.cancelled
        } catch {
            throw SessionLogoutFailure.invalidResponse
        }

        switch response.statusCode {
        case 204:
            try clearSessionAfterLogout(startingGeneration: startingGeneration)
        case 401:
            try clearSessionAfterLogout(startingGeneration: startingGeneration)
            throw SessionLogoutFailure.unauthenticated
        default:
            throw Self.mapLogoutResponseFailure(response)
        }
    }

    private func performRefresh() async throws -> AuthSessionSnapshot {
        let store = try requiredStore()
        let original: AuthSessionSnapshot?
        do {
            original = try store.loadSnapshot()
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        guard let original else { throw AuthSessionFailure.sessionUnavailable }
        let startingGeneration = sessionGeneration
        let requestID = original.refreshRequestID ?? UUID()
        let pendingSnapshot = try AuthSessionSnapshot(
            accessToken: original.accessToken,
            refreshToken: original.refreshToken,
            memberID: original.memberID,
            refreshRequestID: requestID
        )

        if original.refreshRequestID == nil {
            do {
                try store.replaceAtomically(with: pendingSnapshot)
            } catch {
                throw AuthSessionFailure.storageUnavailable
            }
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(AuthRefreshRequest(refreshToken: original.refreshToken, requestId: requestID))
        } catch {
            throw AuthSessionFailure.invalidResponse
        }

        let response: APIClientResponse
        do {
            response = try await apiClient.sendResponse(
                path: "auth/token/refresh",
                method: "POST",
                body: body,
                headers: Self.jsonHeaders,
                queryItems: []
            )
        } catch {
            // Keep the saved pair unchanged for a same-token, same-requestId retry.
            throw Self.mapTransportFailure(error)
        }

        guard response.statusCode != 401 else {
            try clearExpiredSession(
                store: store,
                startingGeneration: startingGeneration,
                refreshToken: original.refreshToken,
                requestID: requestID
            )
            throw AuthSessionFailure.unauthenticated
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response, isLogin: false) }

        let received = try Self.decodeSession(
            response.data,
            refreshRequestID: nil,
            allowsRemainingRefreshTTL: original.refreshRequestID != nil
        )
        guard received.memberID == original.memberID else { throw AuthSessionFailure.memberIdentityChanged }
        guard sessionGeneration == startingGeneration,
              let current = try loadCurrentSnapshot(from: store),
              current.refreshToken == original.refreshToken,
              current.refreshRequestID == requestID else {
            throw AuthSessionFailure.sessionChanged
        }

        do {
            // The server response is accepted only if this single atomic replacement
            // succeeds; on failure the old refresh token + retry ID remain recoverable.
            try store.replaceAtomically(with: received)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        return received
    }

    private func requiredStore() throws -> any AuthSessionStoring {
        guard let sessionStore else { throw AuthSessionFailure.sessionUnavailable }
        return sessionStore
    }

    private func loadCurrentSnapshot(from store: any AuthSessionStoring) throws -> AuthSessionSnapshot? {
        do {
            return try store.loadSnapshot()
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
    }

    private func clearExpiredSession(
        store: any AuthSessionStoring,
        startingGeneration: UInt64,
        refreshToken: String,
        requestID: UUID
    ) throws {
        guard sessionGeneration == startingGeneration,
              let current = try loadCurrentSnapshot(from: store),
              current.refreshToken == refreshToken,
              current.refreshRequestID == requestID else {
            throw AuthSessionFailure.sessionChanged
        }
        do {
            try store.replaceAtomically(with: nil)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        sessionGeneration &+= 1
    }

    private func clearSessionAfterLogout(startingGeneration: UInt64) throws {
        guard let sessionStore else { return }
        guard sessionGeneration == startingGeneration else { throw SessionLogoutFailure.sessionChanged }
        do {
            try sessionStore.replaceAtomically(with: nil)
        } catch {
            throw SessionLogoutFailure.storageUnavailable
        }
        sessionGeneration &+= 1
    }

    private static let jsonHeaders = [
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Cache-Control": "no-store"
    ]

    private static func decodeSession(
        _ data: Data,
        refreshRequestID: UUID?,
        allowsRemainingRefreshTTL: Bool = false
    ) throws -> AuthSessionSnapshot {
        let response: AuthTokenPairResponse
        do {
            response = try JSONDecoder().decode(AuthTokenPairResponse.self, from: data)
        } catch {
            throw AuthSessionFailure.invalidResponse
        }
        guard response.tokenType == "Bearer",
              response.accessExpiresInSeconds == 900,
              (response.refreshExpiresInSeconds == 604_800
                || (allowsRemainingRefreshTTL && (1...604_800).contains(response.refreshExpiresInSeconds))),
              let memberID = memberIDFromTrustedServerToken(response.accessToken) else {
            throw AuthSessionFailure.invalidResponse
        }
        return try AuthSessionSnapshot(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            memberID: memberID,
            refreshRequestID: refreshRequestID
        )
    }

    /// Maps `sub` only to the server-issued decimal member ID used by the local
    /// RunStore ownership boundary. This is format mapping, not JWT verification or
    /// authorization; the backend validates signatures, expiry, sessions, and access.
    private static func memberIDFromTrustedServerToken(_ accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty else { return nil }
        let encoded = String(parts[1])
        guard !encoded.isEmpty, encoded.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let payload = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let subject = claims["sub"] as? String,
              AuthSessionSnapshot.isCanonicalMemberID(subject) else { return nil }
        return subject
    }

    private static func mapResponseFailure(_ response: APIClientResponse, isLogin: Bool) -> AuthSessionFailure {
        let problem = try? JSONDecoder().decode(AuthSessionProblem.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401 where isLogin:
            return .invalidCredentials(requestID: requestID)
        case 401:
            return .unauthenticated
        case 503:
            return .serviceUnavailable(requestID: requestID)
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private static func mapTransportFailure(_ error: Error) -> AuthSessionFailure {
        if let failure = error as? AuthSessionFailure { return failure }
        if let error = error as? APIClientError {
            switch error {
            case .cancelled:
                return .cancelled
            case .transport(let code):
                return .transport(code)
            default:
                return .invalidResponse
            }
        }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            if error.code == .cancelled { return .cancelled }
            return .transport(error.code)
        }
        return .invalidResponse
    }

    private static func mapLogoutResponseFailure(_ response: APIClientResponse) -> SessionLogoutFailure {
        let problem = try? JSONDecoder().decode(AuthSessionProblem.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        if response.statusCode == 503 { return .serviceUnavailable(requestID: requestID) }
        return .serverFailure(statusCode: response.statusCode, requestID: requestID)
    }

    private static func mapLogoutFailure(_ error: APIClientError) -> SessionLogoutFailure {
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
