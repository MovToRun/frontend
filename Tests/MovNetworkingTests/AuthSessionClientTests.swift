import Foundation
import XCTest
@testable import MovNetworking

private struct LogoutTestTokenProvider: AccessTokenProviding {
    let token: String?

    func accessToken() async throws -> String? { token }
}

private actor LogoutTestTransport: APIResponseSending {
    private let outcome: Result<APIClientResponse, APIClientError>
    private var captured: (path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem])?

    init(_ outcome: Result<APIClientResponse, APIClientError>) { self.outcome = outcome }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        captured = (path, method, body, headers, queryItems)
        return try outcome.get()
    }

    func request() -> (path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem])? { captured }
}

final class AuthSessionClientTests: XCTestCase {
    func testLogoutUsesNoBodyPostAndCurrentBearerToken() async throws {
        let transport = LogoutTestTransport(.success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
        let client = AuthSessionClient(apiClient: transport, tokenProvider: LogoutTestTokenProvider(token: "access-token"))

        try await client.logout()

        let capturedRequest = await transport.request()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.path, "auth/logout")
        XCTAssertEqual(request.method, "POST")
        XCTAssertNil(request.body)
        XCTAssertEqual(request.queryItems, [])
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Cache-Control"], "no-store")
    }

    func testLogoutDoesNotSendRequestWithoutUsableToken() async {
        for token in [nil, "", "bad token"] {
            let transport = LogoutTestTransport(.success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
            let client = AuthSessionClient(apiClient: transport, tokenProvider: LogoutTestTokenProvider(token: token))

            do {
                try await client.logout()
                XCTFail("Expected an unavailable credential")
            } catch let failure as SessionLogoutFailure {
                XCTAssertEqual(failure, .accessTokenUnavailable)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            let capturedRequest = await transport.request()
            XCTAssertNil(capturedRequest)
        }
    }

    func testLogoutMapsInvalidSessionAndAuthenticationServiceOutage() async {
        let unauthorized = AuthSessionClient(
            apiClient: LogoutTestTransport(.success(APIClientResponse(statusCode: 401, data: Data(), requestID: "r-401"))),
            tokenProvider: LogoutTestTokenProvider(token: "access-token")
        )
        do {
            try await unauthorized.logout()
            XCTFail("Expected 401")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .unauthenticated)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let unavailableBody = Data("{\"code\":\"AUTH_UNAVAILABLE\",\"requestId\":\"r-503\"}".utf8)
        let unavailable = AuthSessionClient(
            apiClient: LogoutTestTransport(.success(APIClientResponse(statusCode: 503, data: unavailableBody, requestID: nil))),
            tokenProvider: LogoutTestTokenProvider(token: "access-token")
        )
        do {
            try await unavailable.logout()
            XCTFail("Expected 503")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .serviceUnavailable(requestID: "r-503"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLogoutKeepsOtherServerFailuresAndTransportFailuresTyped() async {
        let serverFailure = AuthSessionClient(
            apiClient: LogoutTestTransport(.success(APIClientResponse(statusCode: 500, data: Data(), requestID: "r-500"))),
            tokenProvider: LogoutTestTokenProvider(token: "access-token")
        )
        do {
            try await serverFailure.logout()
            XCTFail("Expected 500")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .serverFailure(statusCode: 500, requestID: "r-500"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let transportFailure = AuthSessionClient(
            apiClient: LogoutTestTransport(.failure(.transport(.notConnectedToInternet))),
            tokenProvider: LogoutTestTokenProvider(token: "access-token")
        )
        do {
            try await transportFailure.logout()
            XCTFail("Expected a transport failure")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .transport(.notConnectedToInternet))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
