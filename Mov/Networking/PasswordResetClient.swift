import Foundation

struct PasswordResetProof: Equatable, Sendable {
    let value: String
    let expiresInSeconds: Int
}

protocol PasswordResetServing: Sendable {
    func requestCode(email: String) async throws
    func confirmCode(email: String, code: String) async throws -> PasswordResetProof
    func resetPassword(resetProof: String, requestID: String, email: String, password: String) async throws
}

enum PasswordResetPolicy {
    static let codeLength = 6
    static let codeLifetime: TimeInterval = 5 * 60
    static let resendInterval: TimeInterval = 60
    static let maximumAttempts = 5
    static let proofLifetimeSeconds = 600
}

enum PasswordResetFailure: Error, Equatable, Sendable {
    case invalidRequest
    /// The API intentionally merges incorrect, expired, consumed, and wrong-purpose proofs.
    case verificationFailed(requestID: String?)
    case tooManyRequests(requestID: String?)
    case serviceUnavailable(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case invalidResponse
    case sessionStorageUnavailable
    case transport(URLError.Code)
    case cancelled

    var requestID: String? {
        switch self {
        case .verificationFailed(let requestID), .tooManyRequests(let requestID), .serviceUnavailable(let requestID):
            requestID
        case .serverFailure(_, let requestID): requestID
        case .invalidRequest, .invalidResponse, .sessionStorageUnavailable, .transport, .cancelled: nil
        }
    }

    var isVerificationFailure: Bool {
        if case .verificationFailed = self { return true }
        return false
    }

    var requiresExactRetry: Bool {
        switch self {
        case .serviceUnavailable, .serverFailure, .invalidResponse, .sessionStorageUnavailable, .transport, .cancelled:
            true
        case .invalidRequest, .verificationFailed, .tooManyRequests:
            false
        }
    }

    var userMessage: String {
        switch self {
        case .invalidRequest:
            return "입력한 내용을 확인해 주세요."
        case .verificationFailed:
            return "인증 정보를 확인할 수 없어요. 새 코드를 요청해 다시 시도해 주세요."
        case .tooManyRequests:
            return "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case .serviceUnavailable:
            return "인증 서비스를 일시적으로 사용할 수 없어요. 같은 내용으로 다시 시도해 주세요."
        case .serverFailure, .invalidResponse:
            return "비밀번호 변경 결과를 확인하지 못했어요. 같은 내용으로 다시 시도해 주세요."
        case .sessionStorageUnavailable:
            return "비밀번호는 변경됐지만 이 기기의 로그인 정보를 정리하지 못했어요. 같은 내용으로 다시 시도해 주세요."
        case .transport:
            return "연결 상태를 확인한 뒤 같은 내용으로 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요. 같은 내용으로 다시 시도해 주세요."
        }
    }
}

enum PasswordResetValidation {
    static func isValidEmail(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 254 else { return false }
        return value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    static func isValidCode(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil
    }

    static func isValidPassword(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (8...20).contains(bytes.count), bytes.allSatisfy({ (0x21...0x7E).contains($0) }) else { return false }
        return bytes.contains(where: { (65...90).contains($0) || (97...122).contains($0) })
            && bytes.contains(where: { (48...57).contains($0) })
    }

    static func isValidProof(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil
    }

    static func isValidRequestID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._:-]{1,128}$"#, options: .regularExpression) != nil
    }
}

struct PasswordResetClient: PasswordResetServing {
    private let apiClient: any APIResponseSending

    init(apiClient: any APIResponseSending) {
        self.apiClient = apiClient
    }

    func requestCode(email: String) async throws {
        guard PasswordResetValidation.isValidEmail(email) else { throw PasswordResetFailure.invalidRequest }
        let body = try encode(EmailRequest(email: normalizedInput(email)))
        let response = try await send(path: "auth/password/reset/verifications", body: body)
        guard response.statusCode == 202, response.data.isEmpty else { throw Self.mapFailure(response) }
    }

    func confirmCode(email: String, code: String) async throws -> PasswordResetProof {
        guard PasswordResetValidation.isValidEmail(email), PasswordResetValidation.isValidCode(code) else {
            throw PasswordResetFailure.invalidRequest
        }
        let body = try encode(ConfirmRequest(email: normalizedInput(email), code: code))
        let response = try await send(path: "auth/password/reset/verifications/confirm", body: body)
        guard response.statusCode == 200 else { throw Self.mapFailure(response) }
        guard let proof = try? JSONDecoder().decode(ProofResponse.self, from: response.data),
              PasswordResetValidation.isValidProof(proof.resetProof),
              proof.expiresInSeconds == PasswordResetPolicy.proofLifetimeSeconds else {
            throw PasswordResetFailure.invalidResponse
        }
        return PasswordResetProof(value: proof.resetProof, expiresInSeconds: Int(proof.expiresInSeconds))
    }

    func resetPassword(resetProof: String, requestID: String, email: String, password: String) async throws {
        guard PasswordResetValidation.isValidProof(resetProof),
              PasswordResetValidation.isValidRequestID(requestID),
              PasswordResetValidation.isValidEmail(email),
              PasswordResetValidation.isValidPassword(password) else {
            throw PasswordResetFailure.invalidRequest
        }
        let body = try encode(ResetRequest(
            resetProof: resetProof,
            requestId: requestID,
            email: normalizedInput(email),
            password: password
        ))
        let response = try await send(path: "auth/password/reset", body: body)
        guard response.statusCode == 204, response.data.isEmpty else { throw Self.mapFailure(response) }
    }

    private func send(path: String, body: Data) async throws -> APIClientResponse {
        do {
            return try await apiClient.sendResponse(
                path: path,
                method: "POST",
                body: body,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "Cache-Control": "no-store"
                ],
                queryItems: []
            )
        } catch let error as APIClientError {
            switch error {
            case .cancelled: throw PasswordResetFailure.cancelled
            case .transport(let code): throw PasswordResetFailure.transport(code)
            default: throw PasswordResetFailure.invalidResponse
            }
        } catch is CancellationError {
            throw PasswordResetFailure.cancelled
        } catch {
            throw PasswordResetFailure.invalidResponse
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw PasswordResetFailure.invalidRequest }
    }

    private static func mapFailure(_ response: APIClientResponse) -> PasswordResetFailure {
        guard !(200..<300).contains(response.statusCode) else { return .invalidResponse }
        let problem = try? JSONDecoder().decode(ProblemResponse.self, from: response.data)
        let requestID = problem?.requestId.flatMap { $0.isEmpty ? nil : $0 } ?? response.requestID
        switch (response.statusCode, problem?.code) {
        case (422, "VERIFICATION_FAILED"):
            return .verificationFailed(requestID: requestID)
        case (429, "TOO_MANY_REQUESTS"):
            return .tooManyRequests(requestID: requestID)
        case (503, "AUTH_UNAVAILABLE"), (503, "VERIFICATION_EMAIL_UNAVAILABLE"):
            return .serviceUnavailable(requestID: requestID)
        case (400, _), (422, _):
            return .invalidRequest
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func normalizedInput(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct EmailRequest: Encodable {
    let email: String
}

private struct ConfirmRequest: Encodable {
    let email: String
    let code: String
}

private struct ResetRequest: Encodable {
    let resetProof: String
    let requestId: String
    let email: String
    let password: String
}

private struct ProofResponse: Decodable {
    let resetProof: String
    let expiresInSeconds: Int64
}

private struct ProblemResponse: Decodable {
    let code: String?
    let requestId: String?
}
