import Foundation
import XCTest
@testable import MovNetworking

private struct AccountLinkTokenStub: AccessTokenProviding {
    let token: String?
    func accessToken() async throws -> String? { token }
}

private struct AccountLinkRequestRecord: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
}

private actor AccountLinkResponseMock: APIResponseSending {
    private var responses: [APIClientResponse]
    private(set) var requests: [AccountLinkRequestRecord] = []

    init(_ responses: [APIClientResponse]) { self.responses = responses }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        requests.append(AccountLinkRequestRecord(path: path, method: method, body: body, headers: headers))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }
}

private actor AccountLinkServiceMock: AccountLinkServing {
    private var linkedProviders: [AccountLinkProvider]
    private let hasLocalPassword: Bool
    private var reauthChallengeDelay: Duration
    private(set) var calls: [String] = []

    init(linkedProviders: [AccountLinkProvider] = [.kakao], hasLocalPassword: Bool = false, reauthChallengeDelay: Duration = .zero) {
        self.linkedProviders = linkedProviders
        self.hasLocalPassword = hasLocalPassword
        self.reauthChallengeDelay = reauthChallengeDelay
    }

    func methods() async throws -> AccountLinkMethods {
        calls.append("methods")
        return AccountLinkMethods(localPassword: hasLocalPassword, socialProviders: linkedProviders)
    }

    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        calls.append("reauth-password:\(purpose.rawValue):\(password)")
        return AccountLinkReauthProof(reauthProof: token("p"), expiresInSeconds: 300)
    }

    func issueReauthChallenge(provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws -> AccountLinkChallenge {
        calls.append("reauth-challenge:\(provider.rawValue):\(purpose.rawValue)")
        if reauthChallengeDelay > .zero {
            try await Task.sleep(for: reauthChallengeDelay)
            reauthChallengeDelay = .zero
        }
        return AccountLinkChallenge(state: token("r"), nonce: token("n"), expiresInSeconds: 300)
    }

    func verifyReauthentication(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, purpose: AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        calls.append("reauth-verify:\(provider.rawValue):\(purpose.rawValue):\(credential)")
        return AccountLinkReauthProof(reauthProof: token("p"), expiresInSeconds: 300)
    }

    func issueLinkChallenge(provider: AccountLinkProvider) async throws -> AccountLinkChallenge {
        calls.append("link-challenge:\(provider.rawValue)")
        return AccountLinkChallenge(state: token("s"), nonce: token("n"), expiresInSeconds: 600)
    }

    func completeLink(provider: AccountLinkProvider, challenge: AccountLinkChallenge, credential: String, reauthProof: String, consent: Bool) async throws {
        calls.append("link-complete:\(provider.rawValue):\(credential):\(consent)")
        linkedProviders.append(provider)
    }

    func recordedCalls() -> [String] { calls }

    private func token(_ prefix: String) -> String { prefix + String(repeating: "x", count: 42) }
}

private actor AccountLinkCredentialStub: AccountLinkCredentialProviding {
    private let cancelledPurposes: Set<AccountLinkCredentialPurpose>
    private(set) var requests: [(AccountLinkProvider, AccountLinkCredentialPurpose)] = []

    init(cancelledPurposes: Set<AccountLinkCredentialPurpose> = []) {
        self.cancelledPurposes = cancelledPurposes
    }

    func credential(for provider: AccountLinkProvider, purpose: AccountLinkCredentialPurpose, challenge: AccountLinkChallenge) async throws -> String? {
        requests.append((provider, purpose))
        guard !cancelledPurposes.contains(purpose) else { return nil }
        return "fixture-\(purpose == .reauthentication ? "reauth" : "link")-credential"
    }
}

final class AccountLinkClientTests: XCTestCase {
    func testMethodsReadsNamesOnlyWithBearerAndNoStore() async throws {
        let api = AccountLinkResponseMock([
            response(200, #"{"localPassword":true,"socialProviders":["KAKAO","google"]}"#)
        ])
        let client = AccountLinkClient(apiClient: api, tokenProvider: AccountLinkTokenStub(token: "fixture-access"))

        let methods = try await client.methods()

        XCTAssertTrue(methods.localPassword)
        XCTAssertEqual(methods.socialProviders, [.kakao, .google])
        let requests = await api.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].path, "auth/account/links")
        XCTAssertEqual(requests[0].method, "GET")
        XCTAssertNil(requests[0].body)
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer fixture-access")
        XCTAssertEqual(requests[0].headers["Cache-Control"], "no-store")
    }

    func testReauthenticationAndLinkRequestsMatchBackendContract() async throws {
        let api = AccountLinkResponseMock([
            response(200, #"{"state":"rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr","nonce":"nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn","expiresInSeconds":300}"#),
            response(200, #"{"reauthProof":"ppppppppppppppppppppppppppppppppppppppppppp","expiresInSeconds":300}"#),
            response(200, #"{"state":"sssssssssssssssssssssssssssssssssssssssssss","nonce":"nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn","expiresInSeconds":600}"#),
            response(204, "")
        ])
        let client = AccountLinkClient(apiClient: api, tokenProvider: AccountLinkTokenStub(token: "fixture-access"))
        let reauth = try await client.issueReauthChallenge(provider: .kakao, purpose: .link)
        let proof = try await client.verifyReauthentication(provider: .kakao, challenge: reauth, credential: "mock-provider-credential", purpose: .link)
        let link = try await client.issueLinkChallenge(provider: .google)
        try await client.completeLink(provider: .google, challenge: link, credential: "mock-google-credential", reauthProof: proof.reauthProof, consent: true)

        let requests = await api.requests
        XCTAssertEqual(requests.map(\.path), [
            "auth/account/reauth/kakao/challenge",
            "auth/account/reauth/kakao/verify",
            "auth/account/links/google/challenge",
            "auth/account/links/google/complete"
        ])
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST", "POST"])
        XCTAssertEqual(requests.map { $0.headers["Authorization"] }, Array(repeating: "Bearer fixture-access", count: 4))
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
        XCTAssertNil(requests[2].body)

        let reauthChallengeBody = try XCTUnwrap(requests[0].body).jsonObject()
        XCTAssertEqual(reauthChallengeBody["purpose"] as? String, "LINK")
        let reauthVerifyBody = try XCTUnwrap(requests[1].body).jsonObject()
        XCTAssertEqual(reauthVerifyBody["state"] as? String, reauth.state)
        XCTAssertEqual(reauthVerifyBody["nonce"] as? String, reauth.nonce)
        XCTAssertEqual(reauthVerifyBody["credential"] as? String, "mock-provider-credential")
        XCTAssertEqual(reauthVerifyBody["purpose"] as? String, "LINK")
        let linkBody = try XCTUnwrap(requests[3].body).jsonObject()
        XCTAssertEqual(linkBody["state"] as? String, link.state)
        XCTAssertEqual(linkBody["nonce"] as? String, link.nonce)
        XCTAssertEqual(linkBody["credential"] as? String, "mock-google-credential")
        XCTAssertEqual(linkBody["reauthProof"] as? String, proof.reauthProof)
        XCTAssertEqual(linkBody["consent"] as? Bool, true)
    }

    func testPasswordReauthenticationRequestMatchesBackendContract() async throws {
        let api = AccountLinkResponseMock([
            response(200, #"{"reauthProof":"ppppppppppppppppppppppppppppppppppppppppppp","expiresInSeconds":300}"#)
        ])
        let client = AccountLinkClient(apiClient: api, tokenProvider: AccountLinkTokenStub(token: "fixture-access"))

        let proof = try await client.reauthenticateWithPassword("fixture-password", purpose: .link)

        XCTAssertEqual(proof.expiresInSeconds, 300)
        let requests = await api.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].path, "auth/account/reauth/password")
        XCTAssertEqual(requests[0].method, "POST")
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer fixture-access")
        XCTAssertEqual(requests[0].headers["Cache-Control"], "no-store")
        let body = try XCTUnwrap(requests[0].body).jsonObject()
        XCTAssertEqual(body["password"] as? String, "fixture-password")
        XCTAssertEqual(body["purpose"] as? String, "LINK")
    }

    func testLinkConflictDoesNotExposeAccountOwner() async throws {
        let api = AccountLinkResponseMock([
            response(409, #"{"code":"ACCOUNT_LINK_CONFLICT","requestId":"fixture-request"}"#)
        ])
        let client = AccountLinkClient(apiClient: api, tokenProvider: AccountLinkTokenStub(token: "fixture-access"))
        let challenge = AccountLinkChallenge(state: String(repeating: "s", count: 43), nonce: String(repeating: "n", count: 43), expiresInSeconds: 600)

        do {
            try await client.completeLink(provider: .google, challenge: challenge, credential: "mock-provider-credential", reauthProof: String(repeating: "p", count: 43), consent: true)
            XCTFail("A provider already owned by another member must fail generically")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure, .accountLinkConflict)
            XCTAssertFalse(failure.userMessage.contains("member"))
            XCTAssertFalse(failure.userMessage.contains("email"))
        }
    }

    func testFlowLinksAfterMockReauthenticationAndCredentialAcquisition() async throws {
        let service = AccountLinkServiceMock()
        let credentials = AccountLinkCredentialStub()
        let flow = AccountLinkFlowCoordinator(service: service, credentials: credentials)

        try await flow.reauthenticate(using: .kakao)
        try await flow.link(provider: .google)
        let methods = try await flow.methods()

        XCTAssertEqual(methods.socialProviders, [.kakao, .google])
        let calls = await service.recordedCalls()
        XCTAssertEqual(calls.filter { $0.hasPrefix("reauth-challenge:") }.count, 1)
        XCTAssertEqual(calls.filter { $0.hasPrefix("reauth-verify:") }.count, 1)
        XCTAssertEqual(calls.filter { $0.hasPrefix("link-challenge:") }.count, 1)
        XCTAssertEqual(calls.filter { $0.hasPrefix("link-complete:") }.count, 1)
        XCTAssertTrue(calls.contains("reauth-challenge:kakao:LINK"))
        XCTAssertTrue(calls.contains("link-complete:google:fixture-link-credential:true"))
    }

    func testFlowCanReauthenticateWithExistingLocalPassword() async throws {
        let service = AccountLinkServiceMock(hasLocalPassword: true)
        let flow = AccountLinkFlowCoordinator(service: service, credentials: AccountLinkCredentialStub())

        try await flow.reauthenticateWithPassword("fixture-password")
        try await flow.link(provider: .google)

        let calls = await service.recordedCalls()
        XCTAssertTrue(calls.contains("reauth-password:LINK:fixture-password"))
    }

    func testProviderCancellationDoesNotCompleteLink() async throws {
        let service = AccountLinkServiceMock()
        let credentials = AccountLinkCredentialStub(cancelledPurposes: [.link])
        let flow = AccountLinkFlowCoordinator(service: service, credentials: credentials)
        try await flow.reauthenticate(using: .kakao)

        do {
            try await flow.link(provider: .google)
            XCTFail("Cancellation must stop before completion")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        let calls = await service.recordedCalls()
        XCTAssertFalse(calls.contains { $0.hasPrefix("link-complete:") })
    }

    func testConcurrentReauthenticationRejectsDuplicateSubmission() async throws {
        let service = AccountLinkServiceMock(reauthChallengeDelay: .milliseconds(50))
        let flow = AccountLinkFlowCoordinator(service: service, credentials: AccountLinkCredentialStub())
        let first = Task { try await flow.reauthenticate(using: .kakao) }
        try await Task.sleep(for: .milliseconds(5))

        do {
            try await flow.reauthenticate(using: .kakao)
            XCTFail("A second submission must not start another server request")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure, .requestInProgress)
        }
        try await first.value
        let calls = await service.recordedCalls()
        XCTAssertEqual(calls.filter { $0.hasPrefix("reauth-challenge:") }.count, 1)
    }

    private func response(_ status: Int, _ json: String) -> APIClientResponse {
        APIClientResponse(statusCode: status, data: Data(json.utf8), requestID: nil)
    }
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}
