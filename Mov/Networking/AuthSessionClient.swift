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
    case requestInProgress
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
/// `mutationCoordinator` must be the same actor for every client sharing this store.
protocol AuthSessionStoring: Sendable {
    var mutationCoordinator: AuthSessionMutationCoordinator { get }
    func loadSnapshot() throws -> AuthSessionSnapshot?
    func replaceAtomically(with snapshot: AuthSessionSnapshot?) throws
}

/// Serializes ownership changes and shares a single refresh task across every client
/// injected with one store. The store owns this coordinator for its full lifetime.
actor AuthSessionMutationCoordinator {
    private var mutationVersion: UInt64 = 0
    private var activeLoginID: UUID?
    private var activeLoginVersion: UInt64?
    private var activeLogoutID: UUID?
    private var refreshInFlight: (id: UUID, task: Task<AuthSessionSnapshot, Error>)?

    func beginLogin() throws -> UUID {
        // Keep this owner for the full transport lifetime. Replacing it when a newer
        // request starts is unsafe because the server may process the older POST last.
        guard activeLoginID == nil, activeLogoutID == nil else {
            throw AuthSessionFailure.requestInProgress
        }
        mutationVersion &+= 1
        let lease = UUID()
        activeLoginID = lease
        activeLoginVersion = mutationVersion
        refreshInFlight = nil
        return lease
    }

    func commitLogin(_ snapshot: AuthSessionSnapshot, lease: UUID, store: any AuthSessionStoring) throws {
        guard activeLoginID == lease,
              activeLoginVersion == mutationVersion,
              activeLogoutID == nil else {
            throw AuthSessionFailure.sessionChanged
        }
        do {
            try store.replaceAtomically(with: snapshot)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        activeLoginID = nil
        activeLoginVersion = nil
        mutationVersion &+= 1
    }

    func finishLogin(lease: UUID) {
        if activeLoginID == lease {
            activeLoginID = nil
            activeLoginVersion = nil
        }
    }

    func beginLogout() -> UUID {
        mutationVersion &+= 1
        let lease = UUID()
        activeLogoutID = lease
        refreshInFlight = nil
        return lease
    }

    func commitLogout(lease: UUID, expected: AuthSessionSnapshot, store: any AuthSessionStoring) throws {
        guard activeLogoutID == lease else { throw SessionLogoutFailure.sessionChanged }
        let current: AuthSessionSnapshot?
        do {
            current = try store.loadSnapshot()
        } catch {
            throw SessionLogoutFailure.storageUnavailable
        }
        guard current == expected else { throw SessionLogoutFailure.sessionChanged }
        do {
            try store.replaceAtomically(with: nil)
        } catch {
            throw SessionLogoutFailure.storageUnavailable
        }
        activeLogoutID = nil
        mutationVersion &+= 1
    }

    func finishLogout(lease: UUID) {
        if activeLogoutID == lease { activeLogoutID = nil }
    }

    func runRefreshSingleFlight(
        _ operation: @escaping @Sendable (UInt64) async throws -> AuthSessionSnapshot
    ) async throws -> AuthSessionSnapshot {
        guard activeLoginID == nil, activeLogoutID == nil else { throw AuthSessionFailure.sessionChanged }
        if let refreshInFlight { return try await refreshInFlight.task.value }

        let operationID = UUID()
        let version = mutationVersion
        let task = Task { try await operation(version) }
        refreshInFlight = (operationID, task)
        do {
            let result = try await task.value
            finishRefresh(operationID: operationID)
            return result
        } catch {
            finishRefresh(operationID: operationID)
            throw error
        }
    }

    func prepareRefresh(
        expected: AuthSessionSnapshot,
        pending: AuthSessionSnapshot,
        version: UInt64,
        store: any AuthSessionStoring
    ) throws -> AuthSessionSnapshot {
        try requireCurrentRefresh(version: version)
        let current = try loadSnapshot(from: store)
        guard current == expected else { throw AuthSessionFailure.sessionChanged }
        guard expected.refreshRequestID == nil else { return expected }
        do {
            try store.replaceAtomically(with: pending)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        return pending
    }

    func commitRefresh(
        _ snapshot: AuthSessionSnapshot,
        expected: AuthSessionSnapshot,
        version: UInt64,
        store: any AuthSessionStoring
    ) throws {
        try requireCurrentRefresh(version: version)
        guard snapshot.memberID == expected.memberID else { throw AuthSessionFailure.memberIdentityChanged }
        let current = try loadSnapshot(from: store)
        guard current == expected else { throw AuthSessionFailure.sessionChanged }
        do {
            try store.replaceAtomically(with: snapshot)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        mutationVersion &+= 1
    }

    func clearExpiredRefresh(
        expected: AuthSessionSnapshot,
        version: UInt64,
        store: any AuthSessionStoring
    ) throws {
        try requireCurrentRefresh(version: version)
        let current = try loadSnapshot(from: store)
        guard current == expected else { throw AuthSessionFailure.sessionChanged }
        do {
            try store.replaceAtomically(with: nil)
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        mutationVersion &+= 1
    }

    private func requireCurrentRefresh(version: UInt64) throws {
        guard mutationVersion == version, activeLoginID == nil, activeLogoutID == nil else {
            throw AuthSessionFailure.sessionChanged
        }
    }

    private func loadSnapshot(from store: any AuthSessionStoring) throws -> AuthSessionSnapshot? {
        do {
            return try store.loadSnapshot()
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
    }

    private func finishRefresh(operationID: UUID) {
        if refreshInFlight?.id == operationID { refreshInFlight = nil }
    }
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

        let coordinator = store.mutationCoordinator
        let lease: UUID
        do {
            lease = try await coordinator.beginLogin()
        } catch let failure as AuthSessionFailure {
            throw failure
        } catch {
            throw AuthSessionFailure.sessionChanged
        }
        do {
            let response = try await apiClient.sendResponse(
                path: "auth/login",
                method: "POST",
                body: body,
                headers: Self.jsonHeaders,
                queryItems: []
            )
            guard response.statusCode == 200 else { throw Self.mapResponseFailure(response, isLogin: true) }

            let snapshot = try Self.decodeSession(response.data, refreshRequestID: nil)
            try await coordinator.commitLogin(snapshot, lease: lease, store: store)
            return snapshot
        } catch let failure as AuthSessionFailure {
            await coordinator.finishLogin(lease: lease)
            throw failure
        } catch {
            await coordinator.finishLogin(lease: lease)
            throw Self.mapTransportFailure(error)
        }
    }

    /// All clients that share the injected store also share its coordinator and one
    /// network rotation. A lost response retains the exact saved token/request ID pair.
    func refresh() async throws -> AuthSessionSnapshot {
        let store = try requiredStore()
        let coordinator = store.mutationCoordinator
        return try await coordinator.runRefreshSingleFlight { version in
            try await self.performRefresh(store: store, coordinator: coordinator, startingVersion: version)
        }
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
        guard let sessionStore else {
            try await logoutUsingLegacyTokenProvider()
            return
        }

        let coordinator = sessionStore.mutationCoordinator
        let lease = await coordinator.beginLogout()
        do {
            let session: AuthSessionSnapshot?
            do {
                session = try sessionStore.loadSnapshot()
            } catch {
                throw SessionLogoutFailure.storageUnavailable
            }
            guard let session else { throw SessionLogoutFailure.accessTokenUnavailable }
            let token = session.accessToken
            guard !token.isEmpty,
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
                try await coordinator.commitLogout(lease: lease, expected: session, store: sessionStore)
            case 401:
                try await coordinator.commitLogout(lease: lease, expected: session, store: sessionStore)
                throw SessionLogoutFailure.unauthenticated
            default:
                throw Self.mapLogoutResponseFailure(response)
            }
        } catch {
            await coordinator.finishLogout(lease: lease)
            throw error
        }
    }

    private func logoutUsingLegacyTokenProvider() async throws {
        let token: String?
        do {
            token = try await legacyTokenProvider?.accessToken()
        } catch is CancellationError {
            throw SessionLogoutFailure.cancelled
        } catch {
            throw SessionLogoutFailure.accessTokenUnavailable
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
            return
        case 401:
            throw SessionLogoutFailure.unauthenticated
        default:
            throw Self.mapLogoutResponseFailure(response)
        }
    }

    private func performRefresh(
        store: any AuthSessionStoring,
        coordinator: AuthSessionMutationCoordinator,
        startingVersion: UInt64
    ) async throws -> AuthSessionSnapshot {
        let original: AuthSessionSnapshot?
        do {
            original = try store.loadSnapshot()
        } catch {
            throw AuthSessionFailure.storageUnavailable
        }
        guard let original else { throw AuthSessionFailure.sessionUnavailable }
        let requestID = original.refreshRequestID ?? UUID()
        let pendingSnapshot = try AuthSessionSnapshot(
            accessToken: original.accessToken,
            refreshToken: original.refreshToken,
            memberID: original.memberID,
            refreshRequestID: requestID
        )
        let pending = try await coordinator.prepareRefresh(
            expected: original,
            pending: pendingSnapshot,
            version: startingVersion,
            store: store
        )

        let body: Data
        do {
            body = try JSONEncoder().encode(AuthRefreshRequest(refreshToken: pending.refreshToken, requestId: requestID))
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
            try await coordinator.clearExpiredRefresh(expected: pending, version: startingVersion, store: store)
            throw AuthSessionFailure.unauthenticated
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response, isLogin: false) }

        let received = try Self.decodeSession(
            response.data,
            refreshRequestID: nil,
            allowsRemainingRefreshTTL: original.refreshRequestID != nil
        )
        guard received.memberID == pending.memberID else { throw AuthSessionFailure.memberIdentityChanged }
        // The store coordinator checks ownership and atomically replaces the complete
        // snapshot; a server-success/local-write failure keeps the recovery pair.
        try await coordinator.commitRefresh(received, expected: pending, version: startingVersion, store: store)
        return received
    }

    private func requiredStore() throws -> any AuthSessionStoring {
        guard let sessionStore else { throw AuthSessionFailure.sessionUnavailable }
        return sessionStore
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
        // Redis PTTL is converted with Duration.toSeconds, so an exact replay may
        // report zero while less than one second remains. Accept only that replay
        // value verbatim; do not extend it or manufacture a replacement token.
        guard response.tokenType == "Bearer",
              response.accessExpiresInSeconds == 900,
              (response.refreshExpiresInSeconds == 604_800
                || (allowsRemainingRefreshTTL && (0...604_800).contains(response.refreshExpiresInSeconds))),
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
