import Foundation

enum SocialLoginProvider: String, CaseIterable, Sendable {
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
}

struct SocialLoginChallenge: Decodable, Equatable, Sendable {
    let state: String
    let nonce: String
    let expiresInSeconds: Int
}

struct SocialLoginProof: Decodable, Equatable, Sendable {
    let socialSignupProof: String
    let expiresInSeconds: Int
}

struct SocialLoginConsent: Codable, Equatable, Sendable {
    let documentId: String
    let version: String
    let accepted: Bool

    init(documentId: String, version: String, accepted: Bool) {
        self.documentId = documentId
        self.version = version
        self.accepted = accepted
    }
}

/// Validates an injected consent catalog against the backend's exact required set.
/// Production document IDs and versions must come from the active backend catalog.
struct SocialLoginConsentCatalog: Sendable {
    let required: [SocialLoginConsent]

    func accepts(_ supplied: [SocialLoginConsent]?) -> Bool {
        guard !required.isEmpty, let supplied, supplied.count == required.count, supplied.count <= 16,
              required.allSatisfy({ item in
                  !item.documentId.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
                      && !item.version.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
                      && item.documentId.utf16.count <= 80 && item.version.utf16.count <= 80
              }),
              Set(required.map(ConsentKey.init)).count == required.count,
              Set(supplied.map(ConsentKey.init)).count == supplied.count else { return false }
        let requiredKeys=Set(required.map(ConsentKey.init))
        return supplied.allSatisfy { $0.accepted && requiredKeys.contains(ConsentKey($0)) }
    }

    private struct ConsentKey: Hashable {
        let documentId:String
        let version:String

        init(_ consent:SocialLoginConsent) {
            documentId=consent.documentId
            version=consent.version
        }
    }
}

struct SocialLoginCompletionRequest: Equatable, Sendable {
    let socialSignupProof: String
    let requestID: UUID
    let deviceID: UUID
    let nickname: String?
    let termsConsents: [SocialLoginConsent]?

    /// Keep and reuse this value for an exact retry after an uncertain response.
    init(
        socialSignupProof: String,
        requestID: UUID = UUID(),
        deviceID: UUID,
        nickname: String? = nil,
        termsConsents: [SocialLoginConsent]? = nil
    ) {
        self.socialSignupProof = socialSignupProof
        self.requestID = requestID
        self.deviceID = deviceID
        self.nickname = nickname
        self.termsConsents = termsConsents
    }

    func addingSignupDetails(nickname: String, termsConsents: [SocialLoginConsent]) -> SocialLoginCompletionRequest {
        SocialLoginCompletionRequest(
            socialSignupProof: socialSignupProof,
            requestID: requestID,
            deviceID: deviceID,
            nickname: nickname,
            termsConsents: termsConsents
        )
    }
}

struct SocialLoginSessionTokens: Decodable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let accessExpiresInSeconds: Int
    let refreshExpiresInSeconds: Int
}

enum SocialLoginFailure: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case invalidCredentials
    case termsNotAccepted
    case signupProofInvalid
    case nicknameAlreadyUsed
    case signupRequestConflict
    case tooManyRequests
    case serviceUnavailable
    case serverFailure(statusCode: Int, requestID: String?)
    case transport(URLError.Code)
    case cancelled
    case requestInProgress
    case providerAuthorizationUnavailable

    /// True when the backend has returned a response that conclusively rejects completion.
    /// Transport and malformed-response failures keep the exact request available for replay.
    var completionWasRejected: Bool {
        switch self {
        case .invalidRequest, .invalidCredentials, .termsNotAccepted, .signupProofInvalid,
             .nicknameAlreadyUsed, .signupRequestConflict, .tooManyRequests, .providerAuthorizationUnavailable,
             .requestInProgress:
            true
        case .invalidResponse, .serviceUnavailable, .serverFailure, .transport, .cancelled:
            false
        }
    }

    var userMessage: String {
        switch self {
        case .invalidRequest, .invalidCredentials:
            "인증 정보를 확인한 뒤 다시 시도해 주세요."
        case .invalidResponse:
            "로그인 응답을 확인할 수 없어요. 다시 시도해 주세요."
        case .termsNotAccepted:
            "필수 약관에 동의해 주세요."
        case .signupProofInvalid:
            "소셜 인증이 만료됐어요. 로그인 화면에서 다시 시작해 주세요."
        case .nicknameAlreadyUsed:
            "이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요."
        case .signupRequestConflict:
            "가입 요청을 확인할 수 없어요. 다시 시작해 주세요."
        case .tooManyRequests:
            "요청 횟수가 많아요. 잠시 후 다시 시도해 주세요."
        case .serviceUnavailable:
            "인증 서버가 잠시 응답하지 않아요. 다시 시도해 주세요."
        case .serverFailure, .transport:
            "연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            "로그인을 취소했어요."
        case .requestInProgress:
            "요청을 처리하고 있어요. 잠시만 기다려 주세요."
        case .providerAuthorizationUnavailable:
            "제공자 인증이 설정되지 않았어요."
        }
    }
}

protocol SocialLoginServing: Sendable {
    func issueChallenge(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginChallenge
    func verify(
        provider: SocialLoginProvider,
        challenge: SocialLoginChallenge,
        deviceID: UUID,
        requestID: UUID,
        credential: String
    ) async throws -> SocialLoginProof
    func complete(_ request: SocialLoginCompletionRequest) async throws -> SocialLoginSessionTokens
}

/// Returns nil when the user cancels the provider's native authorization flow.
protocol SocialLoginCredentialProviding: Sendable {
    func credential(for provider: SocialLoginProvider, challenge: SocialLoginChallenge) async throws -> String?
}

struct SocialLoginAttempt: Equatable, Sendable {
    let provider: SocialLoginProvider
    let deviceID: UUID
    let proof: SocialLoginProof
    let completionRequestID: UUID
}

enum SocialLoginOutcome: Equatable, Sendable {
    case authenticated(SocialLoginSessionTokens)
    case signupRequired(SocialLoginAttempt)
}

/// Coordinates the provider boundary without selecting an OAuth SDK or persisting tokens.
/// The caller owns the completion payload and must retain it unchanged for a retry.
actor SocialLoginCoordinator {
    private let service: any SocialLoginServing
    private let credentials: any SocialLoginCredentialProviding
    private var isStarting = false
    private var completions: [UUID: (SocialLoginCompletionRequest, Task<SocialLoginSessionTokens, Error>)] = [:]

    init(service: any SocialLoginServing, credentials: any SocialLoginCredentialProviding) {
        self.service = service
        self.credentials = credentials
    }

    func begin(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginAttempt {
        guard !isStarting else { throw SocialLoginFailure.requestInProgress }
        isStarting = true
        defer { isStarting = false }

        do {
            try Task.checkCancellation()
            let challenge = try await service.issueChallenge(provider: provider, deviceID: deviceID)
            try Task.checkCancellation()
            guard let credential = try await credentials.credential(for: provider, challenge: challenge) else {
                throw SocialLoginFailure.cancelled
            }
            try Task.checkCancellation()
            guard Self.isCredential(credential) else { throw SocialLoginFailure.invalidRequest }
            try Task.checkCancellation()
            let proof = try await service.verify(
                provider: provider,
                challenge: challenge,
                deviceID: deviceID,
                requestID: UUID(),
                credential: credential
            )
            try Task.checkCancellation()
            return SocialLoginAttempt(provider: provider, deviceID: deviceID, proof: proof, completionRequestID: UUID())
        } catch is CancellationError {
            throw SocialLoginFailure.cancelled
        }
    }

    func authenticate(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginOutcome {
        try await resolve(try await begin(provider: provider, deviceID: deviceID))
    }

    /// Existing identities complete with tokens. A new identity returns the backend's
    /// TERMS_NOT_ACCEPTED response until required signup fields are supplied.
    func resolve(_ attempt: SocialLoginAttempt) async throws -> SocialLoginOutcome {
        let request = SocialLoginCompletionRequest(
            socialSignupProof: attempt.proof.socialSignupProof,
            requestID: attempt.completionRequestID,
            deviceID: attempt.deviceID
        )
        do {
            return .authenticated(try await complete(request))
        } catch let failure as SocialLoginFailure where failure == .termsNotAccepted {
            return .signupRequired(attempt)
        }
    }

    func completeSignup(
        for attempt: SocialLoginAttempt,
        nickname: String,
        termsConsents: [SocialLoginConsent]
    ) async throws -> SocialLoginSessionTokens {
        let request = SocialLoginCompletionRequest(
            socialSignupProof: attempt.proof.socialSignupProof,
            requestID: attempt.completionRequestID,
            deviceID: attempt.deviceID,
            nickname: nickname,
            termsConsents: termsConsents
        )
        return try await complete(request)
    }

    func complete(_ request: SocialLoginCompletionRequest) async throws -> SocialLoginSessionTokens {
        guard !Task.isCancelled else { throw SocialLoginFailure.cancelled }
        if let (existingRequest, task) = completions[request.requestID] {
            guard existingRequest == request else { throw SocialLoginFailure.invalidRequest }
            return try await task.value
        }

        let task = Task { try await service.complete(request) }
        completions[request.requestID] = (request, task)
        defer { completions.removeValue(forKey: request.requestID) }
        do {
            return try await task.value
        } catch is CancellationError {
            throw SocialLoginFailure.cancelled
        }
    }

    private static func isCredential(_ credential: String) -> Bool {
        !credential.isEmpty && credential.utf8.count <= 8_192
            && credential.rangeOfCharacter(from: .controlCharacters) == nil
    }
}

struct SocialLoginClient: SocialLoginServing {
    private let apiClient: any APIResponseSending

    init(apiClient: any APIResponseSending) {
        self.apiClient = apiClient
    }

    func issueChallenge(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginChallenge {
        let response = try await send(
            path: "auth/social/\(provider.rawValue)/challenge",
            body: try Self.encode(DeviceRequest(deviceId: deviceID))
        )
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let challenge = try? JSONDecoder().decode(SocialLoginChallenge.self, from: response.data),
              Self.isToken(challenge.state), Self.isToken(challenge.nonce), challenge.expiresInSeconds == 600 else {
            throw SocialLoginFailure.invalidResponse
        }
        return challenge
    }

    func verify(
        provider: SocialLoginProvider,
        challenge: SocialLoginChallenge,
        deviceID: UUID,
        requestID: UUID,
        credential: String
    ) async throws -> SocialLoginProof {
        guard Self.isToken(challenge.state), Self.isToken(challenge.nonce), Self.isCredential(credential) else {
            throw SocialLoginFailure.invalidRequest
        }
        let response = try await send(
            path: "auth/social/\(provider.rawValue)/verify",
            body: try Self.encode(VerifyRequest(
                deviceId: deviceID,
                state: challenge.state,
                nonce: challenge.nonce,
                requestId: requestID.uuidString,
                credential: credential
            ))
        )
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let proof = try? JSONDecoder().decode(SocialLoginProof.self, from: response.data),
              Self.isToken(proof.socialSignupProof), proof.expiresInSeconds == 600 else {
            throw SocialLoginFailure.invalidResponse
        }
        return proof
    }

    func complete(_ request: SocialLoginCompletionRequest) async throws -> SocialLoginSessionTokens {
        guard Self.isToken(request.socialSignupProof),
              request.nickname.map({ $0.count <= 48 }) ?? true,
              request.termsConsents.map({ $0.count <= 16 }) ?? true,
              request.termsConsents?.allSatisfy({ $0.documentId.count <= 80 && $0.version.count <= 80 }) ?? true else {
            throw SocialLoginFailure.invalidRequest
        }
        let response = try await send(
            path: "auth/social/complete",
            body: try Self.encode(CompleteBody(
                socialSignupProof: request.socialSignupProof,
                requestId: request.requestID.uuidString,
                deviceId: request.deviceID,
                nickname: request.nickname,
                termsConsents: request.termsConsents
            ))
        )
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let session = try? JSONDecoder().decode(SocialLoginSessionTokens.self, from: response.data),
              session.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !session.accessToken.isEmpty, !session.refreshToken.isEmpty,
              session.accessExpiresInSeconds > 0, session.refreshExpiresInSeconds > 0 else {
            throw SocialLoginFailure.invalidResponse
        }
        return session
    }

    private func send(path: String, body: Data) async throws -> APIClientResponse {
        do {
            return try await apiClient.sendResponse(
                path: path,
                method: "POST",
                body: body,
                headers: Self.jsonHeaders,
                queryItems: []
            )
        } catch let error as APIClientError {
            switch error {
            case .cancelled:
                throw SocialLoginFailure.cancelled
            case .transport(let code):
                throw SocialLoginFailure.transport(code)
            default:
                throw SocialLoginFailure.invalidResponse
            }
        } catch is CancellationError {
            throw SocialLoginFailure.cancelled
        } catch {
            throw SocialLoginFailure.invalidResponse
        }
    }

    private static func mapFailure(_ response: APIClientResponse) -> SocialLoginFailure {
        let problem = try? JSONDecoder().decode(Problem.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        return switch (response.statusCode, problem?.code) {
        case (401, "INVALID_CREDENTIALS"):
            .invalidCredentials
        case (401, _):
            .invalidCredentials
        case (409, "NICKNAME_ALREADY_USED"):
            .nicknameAlreadyUsed
        case (409, "SIGNUP_REQUEST_CONFLICT"):
            .signupRequestConflict
        case (422, "TERMS_NOT_ACCEPTED"):
            .termsNotAccepted
        case (422, "SIGNUP_PROOF_INVALID"):
            .signupProofInvalid
        case (400, "VALIDATION_FAILED"), (422, "VALIDATION_FAILED"):
            .invalidRequest
        case (429, _):
            .tooManyRequests
        case (503, _):
            .serviceUnavailable
        default:
            .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SocialLoginFailure.invalidRequest
        }
    }

    private static func isToken(_ value: String) -> Bool {
        value.utf8.count == 43 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0)
        }
    }

    private static func isCredential(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8_192
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static var jsonHeaders: [String: String] {
        ["Accept": "application/json", "Content-Type": "application/json", "Cache-Control": "no-store"]
    }

    private struct DeviceRequest: Encodable { let deviceId: UUID }
    private struct VerifyRequest: Encodable {
        let deviceId: UUID
        let state: String
        let nonce: String
        let requestId: String
        let credential: String
    }
    private struct CompleteBody: Encodable {
        let socialSignupProof: String
        let requestId: String
        let deviceId: UUID
        let nickname: String?
        let termsConsents: [SocialLoginConsent]?
    }
    private struct Problem: Decodable { let code: String?; let requestId: String? }
}
