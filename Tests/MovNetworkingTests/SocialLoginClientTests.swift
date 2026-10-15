import Foundation
import XCTest
@testable import MovNetworking

private struct SocialLoginRequestRecord: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
    let queryItems: [URLQueryItem]
}

private actor SocialLoginResponseMock: APIResponseSending {
    private var responses: [APIClientResponse]
    private(set) var captured: [SocialLoginRequestRecord] = []

    init(_ responses: [APIClientResponse]) { self.responses = responses }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        captured.append(SocialLoginRequestRecord(path: path, method: method, body: body, headers: headers, queryItems: queryItems))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func requests() -> [SocialLoginRequestRecord] { captured }
}

private actor SocialLoginServiceMock: SocialLoginServing {
    private let challenge: SocialLoginChallenge
    private let proof: SocialLoginProof
    private let tokens: SocialLoginSessionTokens
    private(set) var calls: [String] = []
    private(set) var completionRequests: [SocialLoginCompletionRequest] = []
    private var completionContinuation: CheckedContinuation<SocialLoginSessionTokens, Error>?
    private var completionStartedContinuation: CheckedContinuation<Void, Never>?
    private let holdCompletion: Bool
    private let requiresSignup: Bool

    init(holdCompletion: Bool = false, requiresSignup: Bool = false) {
        self.challenge = SocialLoginChallenge(state: String(repeating: "s", count: 43), nonce: String(repeating: "n", count: 43), expiresInSeconds: 600)
        self.proof = SocialLoginProof(socialSignupProof: String(repeating: "p", count: 43), expiresInSeconds: 600)
        self.tokens = SocialLoginSessionTokens(accessToken: "fixture-access", refreshToken: "fixture-refresh", tokenType: "Bearer", accessExpiresInSeconds: 900, refreshExpiresInSeconds: 604_800)
        self.holdCompletion = holdCompletion
        self.requiresSignup = requiresSignup
    }

    func issueChallenge(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginChallenge {
        calls.append("challenge:\(provider.rawValue):\(deviceID.uuidString)")
        return challenge
    }

    func verify(provider: SocialLoginProvider, challenge: SocialLoginChallenge, deviceID: UUID, requestID: UUID, credential: String) async throws -> SocialLoginProof {
        calls.append("verify:\(provider.rawValue):\(requestID.uuidString):\(credential)")
        return proof
    }

    func complete(_ request: SocialLoginCompletionRequest) async throws -> SocialLoginSessionTokens {
        calls.append("complete:\(request.requestID.uuidString)")
        completionRequests.append(request)
        if requiresSignup && request.nickname == nil && request.termsConsents == nil {
            throw SocialLoginFailure.termsNotAccepted
        }
        guard holdCompletion else { return tokens }
        return try await withCheckedThrowingContinuation { continuation in
            completionContinuation = continuation
            completionStartedContinuation?.resume()
            completionStartedContinuation = nil
        }
    }

    func waitUntilCompletionStarts() async {
        if completionContinuation != nil { return }
        await withCheckedContinuation { continuation in completionStartedContinuation = continuation }
    }

    func releaseCompletion() {
        completionContinuation?.resume(returning: tokens)
        completionContinuation = nil
    }

    func recordedCalls() -> [String] { calls }
    func completedRequests() -> [SocialLoginCompletionRequest] { completionRequests }
    func completionCount() -> Int { completionRequests.count }
}

private actor SocialLoginCredentialMock: SocialLoginCredentialProviding {
    private let result: String?
    private(set) var requestedProviders: [SocialLoginProvider] = []

    init(result: String?) { self.result = result }

    func credential(for provider: SocialLoginProvider, challenge: SocialLoginChallenge) async throws -> String? {
        requestedProviders.append(provider)
        return result
    }
}

final class SocialLoginClientTests: XCTestCase {
    func testChallengeAndVerifyMatchContractForAllSupportedProviders() async throws {
        let state = String(repeating: "s", count: 43)
        let nonce = String(repeating: "n", count: 43)
        let proof = String(repeating: "p", count: 43)
        let api = SocialLoginResponseMock([
            response(200, #"{"state":"\#(state)","nonce":"\#(nonce)","expiresInSeconds":600}"#),
            response(200, #"{"socialSignupProof":"\#(proof)","expiresInSeconds":600}"#),
            response(200, #"{"state":"\#(state)","nonce":"\#(nonce)","expiresInSeconds":600}"#),
            response(200, #"{"socialSignupProof":"\#(proof)","expiresInSeconds":600}"#),
            response(200, #"{"state":"\#(state)","nonce":"\#(nonce)","expiresInSeconds":600}"#),
            response(200, #"{"socialSignupProof":"\#(proof)","expiresInSeconds":600}"#)
        ])
        let client = SocialLoginClient(apiClient: api)
        let deviceID = UUID(uuidString: "AEB8CAAB-90E6-4E3D-8E61-B4B0EC899217")!
        let verifyRequestID = UUID(uuidString: "41C91247-2A18-4851-B86E-B5A71B0016B2")!

        for provider in SocialLoginProvider.allCases {
            let challenge = try await client.issueChallenge(provider: provider, deviceID: deviceID)
            let receivedProof = try await client.verify(provider: provider, challenge: challenge, deviceID: deviceID, requestID: verifyRequestID, credential: "mock-\(provider.rawValue)-credential")
            XCTAssertEqual(challenge.expiresInSeconds, 600)
            XCTAssertEqual(receivedProof.socialSignupProof, proof)
        }

        let requests = await api.requests()
        XCTAssertEqual(requests.map(\.path), [
            "auth/social/kakao/challenge", "auth/social/kakao/verify",
            "auth/social/naver/challenge", "auth/social/naver/verify",
            "auth/social/google/challenge", "auth/social/google/verify"
        ])
        XCTAssertEqual(requests.map(\.method), Array(repeating: "POST", count: 6))
        XCTAssertTrue(requests.allSatisfy { $0.queryItems.isEmpty && $0.headers["Cache-Control"] == "no-store" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Accept"] == "application/json" && $0.headers["Content-Type"] == "application/json" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == nil }, "Social challenge and verification are unauthenticated")

        let challengeBody = try XCTUnwrap(requests[0].body).jsonObject()
        XCTAssertEqual(challengeBody["deviceId"] as? String, deviceID.uuidString)
        let verifyBody = try XCTUnwrap(requests[1].body).jsonObject()
        XCTAssertEqual(verifyBody["deviceId"] as? String, deviceID.uuidString)
        XCTAssertEqual(verifyBody["state"] as? String, state)
        XCTAssertEqual(verifyBody["nonce"] as? String, nonce)
        XCTAssertEqual(verifyBody["requestId"] as? String, verifyRequestID.uuidString)
        XCTAssertEqual(verifyBody["credential"] as? String, "mock-kakao-credential")
    }

    func testCompleteUsesOptionalSignupFieldsAndRetainableRequestID() async throws {
        let responseBody = #"{"accessToken":"fixture-access","refreshToken":"fixture-refresh","tokenType":"Bearer","accessExpiresInSeconds":900,"refreshExpiresInSeconds":604800}"#
        let api = SocialLoginResponseMock([response(200, responseBody), response(200, responseBody)])
        let client = SocialLoginClient(apiClient: api)
        let request = SocialLoginCompletionRequest(
            socialSignupProof: String(repeating: "p", count: 43),
            requestID: UUID(uuidString: "78FC8E1A-B99A-41B1-88D2-DAC01D1CF63E")!,
            deviceID: UUID(uuidString: "AEB8CAAB-90E6-4E3D-8E61-B4B0EC899217")!,
            nickname: "달리는별",
            termsConsents: [SocialLoginConsent(documentId: "terms.test.privacy", version: "fixture-v1", accepted: true)]
        )

        let first = try await client.complete(request)
        let retry = try await client.complete(request)

        XCTAssertEqual(first, retry)
        let requests = await api.requests()
        XCTAssertEqual(requests.map(\.path), ["auth/social/complete", "auth/social/complete"])
        let bodies = try requests.map { try XCTUnwrap($0.body).jsonObject() }
        XCTAssertEqual(bodies[0]["requestId"] as? String, request.requestID.uuidString)
        XCTAssertEqual(bodies[1]["requestId"] as? String, request.requestID.uuidString, "A retry must reuse the original request ID")
        XCTAssertEqual(bodies[0]["socialSignupProof"] as? String, request.socialSignupProof)
        XCTAssertEqual(bodies[0]["deviceId"] as? String, request.deviceID.uuidString)
        XCTAssertEqual(bodies[0]["nickname"] as? String, "달리는별")
        let consents = try XCTUnwrap(bodies[0]["termsConsents"] as? [[String: Any]])
        XCTAssertEqual(consents[0]["documentId"] as? String, "terms.test.privacy")
        XCTAssertEqual(consents[0]["version"] as? String, "fixture-v1")
        XCTAssertEqual(consents[0]["accepted"] as? Bool, true)
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == nil && $0.headers["Cache-Control"] == "no-store" })
        XCTAssertEqual(first.tokenType, "Bearer")
        XCTAssertEqual(first.refreshExpiresInSeconds, 604_800)
    }

    func testCompleteAllowsLoginWithoutSignupFields() async throws {
        let api = SocialLoginResponseMock([response(200, #"{"accessToken":"a","refreshToken":"r","tokenType":"Bearer","accessExpiresInSeconds":900,"refreshExpiresInSeconds":604800}"#)])
        let client = SocialLoginClient(apiClient: api)
        let request = SocialLoginCompletionRequest(socialSignupProof: String(repeating: "p", count: 43), deviceID: UUID())

        _ = try await client.complete(request)

        let requests = await api.requests()
        let body = try XCTUnwrap(requests.first?.body).jsonObject()
        XCTAssertNil(body["nickname"])
        XCTAssertNil(body["termsConsents"])
    }

    func testMalformedChallengeAndSessionResponsesAreRejected() async {
        let badChallenge = SocialLoginClient(apiClient: SocialLoginResponseMock([response(200, #"{"state":"short","nonce":"short","expiresInSeconds":600}"#)]))
        do {
            _ = try await badChallenge.issueChallenge(provider: .google, deviceID: UUID())
            XCTFail("Expected malformed challenge to be rejected")
        } catch let failure as SocialLoginFailure {
            XCTAssertEqual(failure, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let badSession = SocialLoginClient(apiClient: SocialLoginResponseMock([response(200, #"{"accessToken":"","refreshToken":"r","tokenType":"Basic","accessExpiresInSeconds":0,"refreshExpiresInSeconds":0}"#)]))
        do {
            _ = try await badSession.complete(SocialLoginCompletionRequest(socialSignupProof: String(repeating: "p", count: 43), deviceID: UUID()))
            XCTFail("Expected malformed session response to be rejected")
        } catch let failure as SocialLoginFailure {
            XCTAssertEqual(failure, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderErrorsAndTransportFailuresRemainTyped() async {
        let cases: [(APIClientResponse, SocialLoginFailure)] = [
            (response(401, #"{"code":"INVALID_CREDENTIALS","requestId":"bad-auth"}"#), .invalidCredentials),
            (response(422, #"{"code":"TERMS_NOT_ACCEPTED","requestId":"terms"}"#), .termsNotAccepted),
            (response(409, #"{"code":"NICKNAME_ALREADY_USED","requestId":"name"}"#), .nicknameAlreadyUsed),
            (response(409, #"{"code":"SIGNUP_REQUEST_CONFLICT","requestId":"conflict"}"#), .signupRequestConflict),
            (response(429, #"{"code":"TOO_MANY_REQUESTS"}"#), .tooManyRequests),
            (response(503, #"{"code":"AUTH_UNAVAILABLE"}"#), .serviceUnavailable)
        ]

        for (response, expected) in cases {
            let client = SocialLoginClient(apiClient: SocialLoginResponseMock([response]))
            do {
                _ = try await client.issueChallenge(provider: .kakao, deviceID: UUID())
                XCTFail("Expected \(expected)")
            } catch let failure as SocialLoginFailure {
                XCTAssertEqual(failure, expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let transport = SocialLoginClient(apiClient: SocialLoginTransportFailureMock())
        do {
            _ = try await transport.issueChallenge(provider: .naver, deviceID: UUID())
            XCTFail("Expected transport failure")
        } catch let failure as SocialLoginFailure {
            XCTAssertEqual(failure, .transport(.notConnectedToInternet))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderCancellationDoesNotVerifyOrSubmitAnythingElse() async throws {
        let service = SocialLoginServiceMock()
        let credentials = SocialLoginCredentialMock(result: nil)
        let coordinator = SocialLoginCoordinator(service: service, credentials: credentials)

        do {
            _ = try await coordinator.begin(provider: .naver, deviceID: UUID())
            XCTFail("Expected provider cancellation")
        } catch let failure as SocialLoginFailure {
            XCTAssertEqual(failure, .cancelled)
        }

        let calls = await service.recordedCalls()
        let requestedProviders = await credentials.requestedProviders
        XCTAssertEqual(calls.count, 1, "Cancellation stops after the challenge and never sends a provider credential")
        XCTAssertEqual(requestedProviders, [.naver])
    }

    func testBackendTermsFailureBranchesToSignupAndReusesProofAndRequestID() async throws {
        let service = SocialLoginServiceMock(requiresSignup: true)
        let coordinator = SocialLoginCoordinator(service: service, credentials: SocialLoginCredentialMock(result: "fixture-credential"))
        let attempt = try await coordinator.begin(provider: .google, deviceID: UUID())

        let outcome = try await coordinator.resolve(attempt)
        guard case .signupRequired(let pending) = outcome else {
            return XCTFail("A new social identity waits for required signup details")
        }
        XCTAssertEqual(pending, attempt)

        let tokens = try await coordinator.completeSignup(
            for: pending,
            nickname: "아침러너",
            termsConsents: [SocialLoginConsent(documentId: "terms.test.privacy", version: "fixture-v1", accepted: true)]
        )

        XCTAssertEqual(tokens.accessToken, "fixture-access")
        let requests = await service.completedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].socialSignupProof, requests[1].socialSignupProof)
        XCTAssertEqual(requests[0].requestID, requests[1].requestID)
        XCTAssertNil(requests[0].nickname)
        XCTAssertNil(requests[0].termsConsents)
        XCTAssertEqual(requests[1].nickname, "아침러너")
        XCTAssertEqual(requests[1].termsConsents?.first?.accepted, true)
    }

    func testCoordinatorCoalescesDuplicateCompletionSubmission() async throws {
        let service = SocialLoginServiceMock(holdCompletion: true)
        let coordinator = SocialLoginCoordinator(service: service, credentials: SocialLoginCredentialMock(result: "fixture-credential"))
        let request = SocialLoginCompletionRequest(socialSignupProof: String(repeating: "p", count: 43), requestID: UUID(), deviceID: UUID())

        let first = Task { try await coordinator.complete(request) }
        await service.waitUntilCompletionStarts()
        let second = Task { try await coordinator.complete(request) }
        try await Task.sleep(for: .milliseconds(20))
        let duplicateCount = await service.completionCount()
        XCTAssertEqual(duplicateCount, 1)
        await service.releaseCompletion()

        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, secondValue)
        let finalCount = await service.completionCount()
        XCTAssertEqual(finalCount, 1)
    }
}

private struct SocialLoginTransportFailureMock: APIResponseSending {
    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        throw APIClientError.transport(.notConnectedToInternet)
    }
}

private func response(_ statusCode: Int, _ body: String, requestID: String? = nil) -> APIClientResponse {
    APIClientResponse(statusCode: statusCode, data: Data(body.utf8), requestID: requestID)
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}
