import Foundation

enum AccountLinkProvider: String, CaseIterable, Hashable, Sendable {
    case kakao
    case naver
    case google

    var displayName: String {
        switch self {
        case .kakao: "카카오"
        case .naver: "네이버"
        case .google: "Google"
        }
    }

    init?(wireValue: String) {
        self.init(rawValue: wireValue.lowercased())
    }
}

enum AccountLinkPurpose: String, Sendable {
    case link = "LINK"
    case unlink = "UNLINK"
    case withdrawal = "WITHDRAWAL"
}

enum AccountLinkMutation: Equatable, Sendable {
    case link(AccountLinkProvider)
    case unlink(AccountLinkProvider)

    func isApplied(to methods: AccountLinkMethods) -> Bool {
        switch self {
        case .link(let provider): methods.socialProviders.contains(provider)
        case .unlink(let provider): !methods.socialProviders.contains(provider)
        }
    }
}

enum AccountLinkCredentialPurpose: Hashable, Sendable {
    case reauthentication
    case link
}

struct AccountLinkMethods: Decodable, Equatable, Sendable {
    let localPassword: Bool
    let socialProviders: [AccountLinkProvider]

    private enum CodingKeys: String, CodingKey {
        case localPassword
        case socialProviders
    }

    init(localPassword: Bool, socialProviders: [AccountLinkProvider]) {
        self.localPassword = localPassword
        self.socialProviders = socialProviders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localPassword = try container.decode(Bool.self, forKey: .localPassword)
        let values = try container.decode([String].self, forKey: .socialProviders)
        socialProviders = try values.map { value in
            guard let provider = AccountLinkProvider(wireValue: value) else {
                throw DecodingError.dataCorruptedError(forKey: .socialProviders, in: container, debugDescription: "Unknown provider")
            }
            return provider
        }
    }
}

struct AccountLinkChallenge: Decodable, Equatable, Sendable {
    let state: String
    let nonce: String
    let expiresInSeconds: Int
}

struct AccountLinkReauthProof: Decodable, Equatable, Sendable {
    let reauthProof: String
    let expiresInSeconds: Int
}

protocol AccountLinkServing: Sendable {
    func methods() async throws -> AccountLinkMethods
    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof
    func issueReauthChallenge(provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws -> AccountLinkChallenge
    func verifyReauthentication(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof
    func issueLinkChallenge(provider: AccountLinkProvider) async throws -> AccountLinkChallenge
    func completeLink(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, reauthProof: String, consent: Bool) async throws
    func unlink(provider: AccountLinkProvider, reauthProof: String, consent: Bool) async throws
}

protocol AccountLinkCredentialProviding: Sendable {
    /// A nil result means the user cancelled provider authorization.
    func credential(for provider: AccountLinkProvider, purpose: AccountLinkCredentialPurpose, challenge: AccountLinkChallenge) async throws -> String?
}

protocol AccountLinkFlowServing: Sendable {
    func methods() async throws -> AccountLinkMethods
    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws
    func reauthenticate(using provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws
    /// Consumes one purpose-bound proof. Withdrawal cannot reuse LINK or UNLINK proofs.
    func consumeReauthenticationProof(for purpose: AccountLinkPurpose) async throws -> String
    /// Returns false if cancellation won before the completion request was submitted.
    func link(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws
    func unlink(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws
    func cancel() async
}

extension AccountLinkFlowServing {
    func consumeReauthenticationProof(for purpose: AccountLinkPurpose) async throws -> String {
        throw AccountLinkFailure.reauthenticationRequired
    }

    func reauthenticateWithPassword(_ password: String) async throws {
        try await reauthenticateWithPassword(password, purpose: .link)
    }

    func reauthenticate(using provider: AccountLinkProvider) async throws {
        try await reauthenticate(using: provider, purpose: .link)
    }
}

enum AccountLinkFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case apiEnvironmentUnavailable
    case authenticationUnavailable
    case providerAuthorizationUnavailable
    case invalidRequest
    case invalidResponse
    case unauthenticated
    case invalidCredentials
    case accountLinkConflict
    case accountMethodRequired
    case consentRequired
    case tooManyRequests
    case serviceUnavailable
    case serverFailure(statusCode: Int, requestID: String?)
    case transport(URLError.Code)
    case cancelled
    case requestInProgress
    case reauthenticationRequired
    case alreadyLinked
    case accountLinkNotFound
    case completionStatusUnknown
    case completionNotApplied

    var requestID: String? {
        if case .serverFailure(_, let requestID) = self { return requestID }
        return nil
    }

    var userMessage: String {
        switch self {
        case .apiEnvironmentUnavailable:
            "API 환경이 설정되지 않아 로그인 수단을 확인할 수 없어요."
        case .authenticationUnavailable:
            "인증 세션 저장소가 준비되지 않아 로그인 수단을 확인할 수 없어요."
        case .providerAuthorizationUnavailable:
            "제공자 인증이 설정되지 않아 새 로그인 수단을 연결할 수 없어요."
        case .accessTokenUnavailable, .unauthenticated:
            "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .invalidRequest:
            "요청 내용을 확인해 주세요."
        case .invalidResponse:
            "계정 연결 응답을 확인할 수 없어요."
        case .invalidCredentials:
            "현재 연결된 로그인 수단으로 계정을 확인해 주세요."
        case .accountLinkConflict:
            "계정 연결을 처리할 수 없어요. 다른 로그인 수단을 선택해 주세요."
        case .accountMethodRequired:
            "다른 로그인 수단을 먼저 추가해 주세요."
        case .consentRequired:
            "로그인 수단 연결에 동의해 주세요."
        case .tooManyRequests:
            "요청 횟수가 많아요. 잠시 후 다시 시도해 주세요."
        case .serviceUnavailable:
            "지금은 로그인 수단을 연결할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .serverFailure, .transport:
            "연결 결과를 확인할 수 없어요. 로그인 수단 목록을 다시 확인해 주세요."
        case .cancelled:
            "로그인 수단 연결을 취소했어요."
        case .requestInProgress:
            "요청을 처리하고 있어요. 잠시만 기다려 주세요."
        case .reauthenticationRequired:
            "현재 계정을 먼저 확인해 주세요."
        case .alreadyLinked:
            "이미 이 계정에 연결된 로그인 수단이에요."
        case .accountLinkNotFound:
            "연결된 로그인 수단을 찾을 수 없어요. 목록을 다시 확인해 주세요."
        case .completionStatusUnknown:
            "연결 결과를 확인하지 못했어요. 로그인 수단 상태를 다시 확인해 주세요."
        case .completionNotApplied:
            "연결 요청이 완료되지 않았어요. 현재 계정을 다시 확인한 뒤 시도해 주세요."
        }
    }
}

struct AccountLinkClient: AccountLinkServing {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding

    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func methods() async throws -> AccountLinkMethods {
        let response = try await send(path: "auth/account/links", method: "GET", body: nil)
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let result = try? JSONDecoder().decode(AccountLinkMethods.self, from: response.data) else { throw AccountLinkFailure.invalidResponse }
        return result
    }

    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        guard (1...128).contains(password.utf8.count) else { throw AccountLinkFailure.invalidRequest }
        let response = try await send(
            path: "auth/account/reauth/password",
            method: "POST",
            body: try Self.encode(PasswordReauthRequest(password: password, purpose: purpose.rawValue))
        )
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let proof = try? JSONDecoder().decode(AccountLinkReauthProof.self, from: response.data),
              Self.isToken(proof.reauthProof), proof.expiresInSeconds == 300 else { throw AccountLinkFailure.invalidResponse }
        return proof
    }

    func issueReauthChallenge(provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws -> AccountLinkChallenge {
        let response = try await send(
            path: "auth/account/reauth/\(provider.rawValue)/challenge",
            method: "POST",
            body: try Self.encode(PurposeRequest(purpose: purpose.rawValue))
        )
        let challenge = try Self.decodeChallenge(response, lifetime: 300)
        return challenge
    }

    func verifyReauthentication(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        guard Self.isToken(challenge.state), Self.isToken(challenge.nonce), Self.isCredential(credential) else {
            throw AccountLinkFailure.invalidRequest
        }
        let response = try await send(
            path: "auth/account/reauth/\(provider.rawValue)/verify",
            method: "POST",
            body: try Self.encode(ProviderReauthRequest(
                state: challenge.state,
                nonce: challenge.nonce,
                credential: credential,
                purpose: purpose.rawValue
            ))
        )
        guard response.statusCode == 200,
              let proof = try? JSONDecoder().decode(AccountLinkReauthProof.self, from: response.data),
              Self.isToken(proof.reauthProof), proof.expiresInSeconds == 300 else {
            throw Self.mapFailure(response)
        }
        return proof
    }

    func issueLinkChallenge(provider: AccountLinkProvider) async throws -> AccountLinkChallenge {
        let response = try await send(
            path: "auth/account/links/\(provider.rawValue)/challenge",
            method: "POST",
            body: nil
        )
        return try Self.decodeChallenge(response, lifetime: 600)
    }

    func completeLink(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, reauthProof: String, consent: Bool) async throws {
        guard Self.isToken(challenge.state), Self.isToken(challenge.nonce),
              Self.isCredential(credential), Self.isToken(reauthProof) else {
            throw AccountLinkFailure.invalidRequest
        }
        let response = try await send(
            path: "auth/account/links/\(provider.rawValue)/complete",
            method: "POST",
            body: try Self.encode(LinkRequest(
                state: challenge.state,
                nonce: challenge.nonce,
                credential: credential,
                reauthProof: reauthProof,
                consent: consent
            ))
        )
        guard response.statusCode == 204 else { throw Self.mapFailure(response) }
        guard response.data.isEmpty else { throw AccountLinkFailure.invalidResponse }
    }

    func unlink(provider: AccountLinkProvider, reauthProof: String, consent: Bool) async throws {
        guard Self.isToken(reauthProof) else { throw AccountLinkFailure.invalidRequest }
        let response = try await send(
            path: "auth/account/links/\(provider.rawValue)",
            method: "DELETE",
            body: try Self.encode(UnlinkRequest(reauthProof: reauthProof, consent: consent))
        )
        guard response.statusCode == 204 else { throw Self.mapFailure(response) }
        guard response.data.isEmpty else { throw AccountLinkFailure.invalidResponse }
    }

    private func send(path: String, method: String, body: Data?) async throws -> APIClientResponse {
        let token: String?
        do {
            token = try await tokenProvider.accessToken()
        } catch is CancellationError {
            throw AccountLinkFailure.cancelled
        } catch {
            throw AccountLinkFailure.accessTokenUnavailable
        }
        guard let token, !token.isEmpty,
              token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw AccountLinkFailure.accessTokenUnavailable
        }
        do {
            return try await apiClient.sendResponse(
                path: path,
                method: method,
                body: body,
                headers: Self.jsonHeaders.merging(["Authorization": "Bearer \(token)"]) { _, new in new },
                queryItems: []
            )
        } catch let error as APIClientError {
            switch error {
            case .cancelled:
                throw AccountLinkFailure.cancelled
            case .transport(let code):
                throw AccountLinkFailure.transport(code)
            default:
                throw AccountLinkFailure.invalidResponse
            }
        } catch is CancellationError {
            throw AccountLinkFailure.cancelled
        } catch {
            throw AccountLinkFailure.invalidResponse
        }
    }

    private static func decodeChallenge(_ response: APIClientResponse, lifetime: Int) throws -> AccountLinkChallenge {
        guard response.statusCode == 200 else { throw mapFailure(response) }
        guard let challenge = try? JSONDecoder().decode(AccountLinkChallenge.self, from: response.data),
              isToken(challenge.state), isToken(challenge.nonce), challenge.expiresInSeconds == lifetime else { throw AccountLinkFailure.invalidResponse }
        return challenge
    }

    private static func mapFailure(_ response: APIClientResponse) -> AccountLinkFailure {
        let problem = try? JSONDecoder().decode(AccountLinkProblem.self, from: response.data)
        return switch (response.statusCode, problem?.code) {
        case (401, "INVALID_CREDENTIALS"):
            .invalidCredentials
        case (401, _):
            .unauthenticated
        case (409, "ACCOUNT_LINK_CONFLICT"):
            .accountLinkConflict
        case (409, "ACCOUNT_METHOD_REQUIRED"):
            .accountMethodRequired
        case (422, "ACCOUNT_LINK_CONSENT_REQUIRED"):
            .consentRequired
        case (429, _):
            .tooManyRequests
        case (503, _):
            .serviceUnavailable
        default:
            .serverFailure(statusCode: response.statusCode, requestID: problem?.requestId ?? response.requestID)
        }
    }

    private static var jsonHeaders: [String: String] {
        [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
        ]
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw AccountLinkFailure.invalidRequest }
    }

    private static func isToken(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil
    }

    private static func isCredential(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8192
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private struct PurposeRequest: Encodable { let purpose: String }
    private struct PasswordReauthRequest: Encodable { let password: String; let purpose: String }
    private struct ProviderReauthRequest: Encodable {
        let state: String
        let nonce: String
        let credential: String
        let purpose: String
    }
    private struct LinkRequest: Encodable {
        let state: String
        let nonce: String
        let credential: String
        let reauthProof: String
        let consent: Bool
    }
    private struct UnlinkRequest: Encodable { let reauthProof: String; let consent: Bool }
    private struct AccountLinkProblem: Decodable {
        let code: String?
        let requestId: String?
    }
}

actor AccountLinkFlowCoordinator: AccountLinkFlowServing {
    private let service: any AccountLinkServing
    private let credentials: any AccountLinkCredentialProviding
    private var operationInProgress = false
    private var reauthProof: String?
    private var reauthProofPurpose: AccountLinkPurpose?
    private var cancellationGeneration: UInt64 = 0
    private var mutationRequestSubmitted = false

    init(service: any AccountLinkServing, credentials: any AccountLinkCredentialProviding) {
        self.service = service
        self.credentials = credentials
    }

    func methods() async throws -> AccountLinkMethods {
        try await service.methods()
    }

    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws {
        guard !operationInProgress else { throw AccountLinkFailure.requestInProgress }
        operationInProgress = true
        let startingCancellationGeneration = cancellationGeneration
        reauthProof = nil
        reauthProofPurpose = nil
        defer { operationInProgress = false }

        let methods = try await service.methods()
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        guard methods.localPassword else { throw AccountLinkFailure.invalidCredentials }
        let proof = try await service.reauthenticateWithPassword(password, purpose: purpose)
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        reauthProof = proof.reauthProof
        reauthProofPurpose = purpose
    }

    func reauthenticate(using provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws {
        guard !operationInProgress else { throw AccountLinkFailure.requestInProgress }
        operationInProgress = true
        let startingCancellationGeneration = cancellationGeneration
        reauthProof = nil
        reauthProofPurpose = nil
        defer { operationInProgress = false }

        let methods = try await service.methods()
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        guard methods.socialProviders.contains(provider) else { throw AccountLinkFailure.invalidCredentials }
        let challenge = try await service.issueReauthChallenge(provider: provider, purpose: purpose)
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        guard let credential = try await credentials.credential(for: provider, purpose: .reauthentication, challenge: challenge) else {
            throw AccountLinkFailure.cancelled
        }
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        let proof = try await service.verifyReauthentication(provider: provider, challenge: challenge, credential: credential, purpose: purpose)
        guard !Task.isCancelled else { throw AccountLinkFailure.cancelled }
        guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
        reauthProof = proof.reauthProof
        reauthProofPurpose = purpose
    }

    func consumeReauthenticationProof(for purpose: AccountLinkPurpose) async throws -> String {
        guard !operationInProgress,
              let proof = reauthProof,
              reauthProofPurpose == purpose else {
            throw AccountLinkFailure.reauthenticationRequired
        }
        reauthProof = nil
        reauthProofPurpose = nil
        return proof
    }

    func link(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws {
        guard !operationInProgress else { throw AccountLinkFailure.requestInProgress }
        guard let proof = reauthProof, reauthProofPurpose == .link else { throw AccountLinkFailure.reauthenticationRequired }
        operationInProgress = true
        let startingCancellationGeneration = cancellationGeneration
        defer {
            operationInProgress = false
            mutationRequestSubmitted = false
        }

        do {
            let methods = try await service.methods()
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            guard !methods.socialProviders.contains(provider) else { throw AccountLinkFailure.alreadyLinked }
            let challenge = try await service.issueLinkChallenge(provider: provider)
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            guard let credential = try await credentials.credential(for: provider, purpose: .link, challenge: challenge) else {
                throw AccountLinkFailure.cancelled
            }
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            // Completion consumes both the reauthentication proof and provider challenge.
            // Do not reuse them after a failed or cancelled completion.
            reauthProof = nil
            reauthProofPurpose = nil
            guard await onMutationRequestWillSubmit() else { throw AccountLinkFailure.cancelled }
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            mutationRequestSubmitted = true
            try await service.completeLink(provider: provider, challenge: challenge, credential: credential, reauthProof: proof, consent: true)
        } catch {
            reauthProof = nil
            reauthProofPurpose = nil
            throw error
        }
    }

    func unlink(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws {
        guard !operationInProgress else { throw AccountLinkFailure.requestInProgress }
        guard let proof = reauthProof, reauthProofPurpose == .unlink else { throw AccountLinkFailure.reauthenticationRequired }
        operationInProgress = true
        let startingCancellationGeneration = cancellationGeneration
        defer {
            operationInProgress = false
            mutationRequestSubmitted = false
        }

        do {
            let methods = try await service.methods()
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            guard methods.socialProviders.contains(provider) else { throw AccountLinkFailure.accountLinkNotFound }
            guard await onMutationRequestWillSubmit() else { throw AccountLinkFailure.cancelled }
            try Task.checkCancellation()
            guard startingCancellationGeneration == cancellationGeneration else { throw AccountLinkFailure.cancelled }
            // The one-time UNLINK proof is consumed by the mutation and must not be reused.
            reauthProof = nil
            reauthProofPurpose = nil
            mutationRequestSubmitted = true
            try await service.unlink(provider: provider, reauthProof: proof, consent: true)
        } catch {
            reauthProof = nil
            reauthProofPurpose = nil
            throw error
        }
    }

    func cancel() {
        guard !mutationRequestSubmitted else { return }
        cancellationGeneration &+= 1
        reauthProof = nil
        reauthProofPurpose = nil
    }
}

enum AccountLinkFlowResolution {
    case available(flow: any AccountLinkFlowServing, providerAuthorizationConfigured: Bool)
    case unavailable(AccountLinkFailure)
}

private struct UnavailableAccountLinkCredentialProvider: AccountLinkCredentialProviding {
    func credential(for provider: AccountLinkProvider, purpose: AccountLinkCredentialPurpose, challenge: AccountLinkChallenge) async throws -> String? {
        throw AccountLinkFailure.providerAuthorizationUnavailable
    }
}

enum AccountLinkFlowFactory {
    static func make(
        apiClient: any APIResponseSending,
        tokenProvider: any AccessTokenProviding,
        credentialProvider: (any AccountLinkCredentialProviding)? = nil
    ) -> any AccountLinkFlowServing {
        AccountLinkFlowCoordinator(
            service: AccountLinkClient(apiClient: apiClient, tokenProvider: tokenProvider),
            credentials: credentialProvider ?? UnavailableAccountLinkCredentialProvider()
        )
    }

    static func resolve(
        configuration: APIClientConfiguration?,
        authSessionStore: (any AuthSessionStoring)?,
        credentialProvider: (any AccountLinkCredentialProviding)?
    ) -> AccountLinkFlowResolution {
        guard let configuration else { return .unavailable(.apiEnvironmentUnavailable) }
        guard let authSessionStore else { return .unavailable(.authenticationUnavailable) }

        let apiClient = APIClient(configuration: configuration)
        let tokenProvider = AuthSessionClient(apiClient: apiClient, sessionStore: authSessionStore)
        let flow = make(apiClient: apiClient, tokenProvider: tokenProvider, credentialProvider: credentialProvider)
        return .available(flow: flow, providerAuthorizationConfigured: credentialProvider != nil)
    }
}

struct MemberWithdrawalConfirmationNotice: Decodable, Equatable, Sendable {
    let message: String
    let recentReauthenticationValiditySeconds: Int
}

enum MemberWithdrawalProcessingStatus: String, Decodable, Equatable, Sendable {
    case completed = "COMPLETED"
    case pending = "PENDING"
    case retryableFailure = "RETRYABLE_FAILURE"
}

struct MemberWithdrawalReceipt: Decodable, Equatable, Sendable {
    let requestId: String
    let status: String
    let gpsStatus: MemberWithdrawalProcessingStatus
    let profilePhotoStatus: MemberWithdrawalProcessingStatus
    let communityAttachmentsStatus: MemberWithdrawalProcessingStatus

    var externalMediaDeletionComplete: Bool {
        profilePhotoStatus == .completed && communityAttachmentsStatus == .completed
    }

    var allReportedDeletionComplete: Bool {
        externalMediaDeletionComplete && gpsStatus == .completed
    }
}

enum MemberWithdrawalFailure: Error, Equatable, Sendable {
    case apiEnvironmentUnavailable
    case accessTokenUnavailable
    case invalidRequest
    case invalidResponse
    case unauthenticated
    case confirmationRequired
    case tooManyRequests
    case serviceUnavailable
    case serverFailure(statusCode: Int, requestID: String?, outcomeUnknown: Bool)
    case transport(URLError.Code, outcomeUnknown: Bool)
    case cancelled
    case requestInProgress
    case reauthenticationRequired

    var outcomeUnknown: Bool {
        switch self {
        case .serverFailure(_, _, let unknown), .transport(_, let unknown): unknown
        default: false
        }
    }

    var userMessage: String {
        switch self {
        case .apiEnvironmentUnavailable:
            "탈퇴 안내를 불러올 수 없어요. 서버 설정을 확인해 주세요."
        case .accessTokenUnavailable, .unauthenticated:
            "로그인 상태나 현재 계정 확인이 만료됐어요. 탈퇴 요청은 확인되지 않아 계정 정보와 기록을 유지했어요."
        case .invalidRequest, .confirmationRequired:
            "탈퇴 최종 확인이 필요해요. 안내를 확인한 뒤 다시 진행해 주세요."
        case .invalidResponse:
            "탈퇴 처리 응답을 확인할 수 없어요. 계정 정보와 기록은 유지했어요."
        case .tooManyRequests:
            "요청 횟수가 많아요. 잠시 기다린 뒤 현재 계정을 다시 확인해 주세요."
        case .serviceUnavailable:
            "지금은 탈퇴 요청을 처리할 수 없어요. 계정 정보와 기록을 유지했어요."
        case .serverFailure(_, _, let unknown) where unknown:
            "요청 결과를 확인하지 못했어요. 계정 정보와 기록은 유지했어요. 다시 시도하기 전에 현재 계정을 확인해 주세요."
        case .transport(_, let unknown) where unknown:
            "연결 결과를 확인하지 못했어요. 계정 정보와 기록은 유지했어요. 다시 시도하기 전에 현재 계정을 확인해 주세요."
        case .serverFailure, .transport:
            "탈퇴 요청을 처리하지 못했어요. 계정 정보와 기록을 유지했어요. 현재 계정을 다시 확인해 주세요."
        case .cancelled:
            "탈퇴 요청을 취소했어요. 계정 정보와 기록을 유지했어요."
        case .requestInProgress:
            "탈퇴 요청을 처리하고 있어요. 잠시만 기다려 주세요."
        case .reauthenticationRequired:
            "탈퇴 요청을 위해 현재 계정을 다시 확인해 주세요."
        }
    }
}

protocol MemberWithdrawalServing: Sendable {
    func confirmationNotice() async throws -> MemberWithdrawalConfirmationNotice
    func requestWithdrawal(reauthProof: String, confirmed: Bool) async throws -> MemberWithdrawalReceipt
}

struct MemberWithdrawalClient: MemberWithdrawalServing {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding

    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func confirmationNotice() async throws -> MemberWithdrawalConfirmationNotice {
        let response = try await send(path: "members/me/withdrawal/confirmation", method: "GET", body: nil, authenticated: true)
        guard response.statusCode == 200 else { throw Self.mapFailure(response, outcomeUnknown: false) }
        guard let notice = try? JSONDecoder().decode(MemberWithdrawalConfirmationNotice.self, from: response.data),
              !notice.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              notice.recentReauthenticationValiditySeconds == 300 else {
            throw MemberWithdrawalFailure.invalidResponse
        }
        return notice
    }

    func requestWithdrawal(reauthProof: String, confirmed: Bool) async throws -> MemberWithdrawalReceipt {
        guard confirmed else { throw MemberWithdrawalFailure.confirmationRequired }
        guard Self.isProof(reauthProof) else { throw MemberWithdrawalFailure.reauthenticationRequired }
        let body: Data
        do { body = try JSONEncoder().encode(WithdrawalRequest(reauthProof: reauthProof, confirmed: confirmed)) }
        catch { throw MemberWithdrawalFailure.invalidRequest }

        let response = try await send(path: "members/me/withdrawal", method: "POST", body: body, authenticated: true)
        guard response.statusCode == 202 else { throw Self.mapFailure(response, outcomeUnknown: true) }
        guard let receipt = try? JSONDecoder().decode(MemberWithdrawalReceipt.self, from: response.data),
              !receipt.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              receipt.status == "WITHDRAWN" else {
            // HTTP 202 without the contracted receipt cannot be used to clear local state.
            throw MemberWithdrawalFailure.serverFailure(statusCode: 202, requestID: response.requestID, outcomeUnknown: true)
        }
        return receipt
    }

    private func send(path: String, method: String, body: Data?, authenticated: Bool) async throws -> APIClientResponse {
        var headers = ["Accept": "application/json", "Cache-Control": "no-store"]
        if body != nil { headers["Content-Type"] = "application/json" }
        if authenticated {
            let token: String?
            do { token = try await tokenProvider.accessToken() }
            catch is CancellationError { throw MemberWithdrawalFailure.cancelled }
            catch { throw MemberWithdrawalFailure.accessTokenUnavailable }
            guard let token, !token.isEmpty,
                  token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw MemberWithdrawalFailure.accessTokenUnavailable
            }
            headers["Authorization"] = "Bearer \(token)"
        }
        do {
            return try await apiClient.sendResponse(path: path, method: method, body: body, headers: headers, queryItems: [])
        } catch let error as APIClientError {
            switch error {
            case .cancelled:
                throw authenticated
                    ? MemberWithdrawalFailure.transport(.cancelled, outcomeUnknown: true)
                    : MemberWithdrawalFailure.cancelled
            case .transport(let code): throw MemberWithdrawalFailure.transport(code, outcomeUnknown: authenticated)
            default: throw MemberWithdrawalFailure.invalidResponse
            }
        } catch is CancellationError {
            throw authenticated
                ? MemberWithdrawalFailure.transport(.cancelled, outcomeUnknown: true)
                : MemberWithdrawalFailure.cancelled
        } catch {
            throw MemberWithdrawalFailure.invalidResponse
        }
    }

    private static func mapFailure(_ response: APIClientResponse, outcomeUnknown: Bool) -> MemberWithdrawalFailure {
        let problem = try? JSONDecoder().decode(WithdrawalProblem.self, from: response.data)
        return switch response.statusCode {
        case 401: .unauthenticated
        case 422 where problem?.code == "WITHDRAWAL_CONFIRMATION_REQUIRED": .confirmationRequired
        case 429: .tooManyRequests
        case 503: .serviceUnavailable
        case 500...599: .serverFailure(statusCode: response.statusCode, requestID: problem?.requestId ?? response.requestID, outcomeUnknown: outcomeUnknown)
        default: .serverFailure(statusCode: response.statusCode, requestID: problem?.requestId ?? response.requestID, outcomeUnknown: false)
        }
    }

    private static func isProof(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil
    }

    private struct WithdrawalRequest: Encodable {
        let reauthProof: String
        let confirmed: Bool
    }

    private struct WithdrawalProblem: Decodable {
        let code: String?
        let requestId: String?
    }
}
