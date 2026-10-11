import Foundation

protocol SessionLogoutRequesting: Sendable {
    func logout() async throws
}

enum SessionLogoutFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case serviceUnavailable(requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
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
        case .serverFailure, .invalidResponse:
            return "로그아웃을 완료하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "로그아웃 요청이 취소됐어요."
        }
    }
}

private struct SessionLogoutProblem: Decodable {
    let code: String?
    let requestId: String?
}

final class AuthSessionClient: SessionLogoutRequesting, Sendable {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding

    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func logout() async throws {
        let headers = try await authorizedHeaders()
        do {
            let response = try await apiClient.sendResponse(
                path: "auth/logout",
                method: "POST",
                body: nil,
                headers: headers,
                queryItems: []
            )
            guard response.statusCode == 204 else { throw mapFailure(response) }
        } catch let failure as SessionLogoutFailure {
            throw failure
        } catch let error as APIClientError {
            throw mapFailure(error)
        } catch is CancellationError {
            throw SessionLogoutFailure.cancelled
        } catch {
            throw SessionLogoutFailure.invalidResponse
        }
    }

    private func authorizedHeaders() async throws -> [String: String] {
        do {
            guard let token = try await tokenProvider.accessToken(),
                  !token.isEmpty,
                  token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw SessionLogoutFailure.accessTokenUnavailable
            }
            return [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
                "Cache-Control": "no-store"
            ]
        } catch let failure as SessionLogoutFailure {
            throw failure
        } catch is CancellationError {
            throw SessionLogoutFailure.cancelled
        } catch {
            throw SessionLogoutFailure.accessTokenUnavailable
        }
    }

    private func mapFailure(_ response: APIClientResponse) -> SessionLogoutFailure {
        let problem = try? JSONDecoder().decode(SessionLogoutProblem.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401:
            return .unauthenticated
        case 503 where problem?.code == "AUTH_UNAVAILABLE":
            return .serviceUnavailable(requestID: requestID)
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func mapFailure(_ error: APIClientError) -> SessionLogoutFailure {
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
