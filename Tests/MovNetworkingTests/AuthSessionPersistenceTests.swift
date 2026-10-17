import Foundation
import XCTest
@testable import MovNetworking

private final class InMemoryKeychain: AuthSessionKeychainAccess, @unchecked Sendable {
    private struct Identity: Hashable {
        let service: String
        let account: String
    }

    private struct Policy {
        let accessibility: AuthSessionKeychainAccessibility
        let synchronizable: Bool
    }

    private let lock = NSLock()
    private var items: [Identity: Data] = [:]
    private var policies: [Identity: Policy] = [:]
    private var replacementsToSkipBeforeFailure = 0
    private var shouldFailReplacement = false
    private var shouldFailDeletion = false

    func readData(service: String, account: String, synchronizable: Bool) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[Identity(service: service, account: account)]
    }

    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        accessibility: AuthSessionKeychainAccessibility,
        synchronizable: Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if shouldFailReplacement {
            if replacementsToSkipBeforeFailure > 0 {
                replacementsToSkipBeforeFailure -= 1
            } else {
                shouldFailReplacement = false
                throw AuthSessionKeychainStoreError.keychainUnavailable
            }
        }

        let identity = Identity(service: service, account: account)
        items[identity] = data
        policies[identity] = Policy(accessibility: accessibility, synchronizable: synchronizable)
    }

    func deleteData(service: String, account: String, synchronizable: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailDeletion {
            shouldFailDeletion = false
            throw AuthSessionKeychainStoreError.keychainUnavailable
        }
        let identity = Identity(service: service, account: account)
        items.removeValue(forKey: identity)
        policies.removeValue(forKey: identity)
    }

    func failNextReplacement(afterSuccessfulReplacements count: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        replacementsToSkipBeforeFailure = count
        shouldFailReplacement = true
    }

    func failNextDeletion() {
        lock.lock()
        defer { lock.unlock() }
        shouldFailDeletion = true
    }

    func policy(service: String, account: String) -> (AuthSessionKeychainAccessibility, Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let policy = policies[Identity(service: service, account: account)] else { return nil }
        return (policy.accessibility, policy.synchronizable)
    }
}

private struct CapturedAuthRequest {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
}

private actor ScriptedAuthSessionTransport: APIResponseSending {
    enum Reply {
        case response(APIClientResponse)
        case failure(APIClientError)
    }

    private var replies: [Reply]
    private var requests: [CapturedAuthRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        requests.append(CapturedAuthRequest(path: path, method: method, body: body, headers: headers))
        guard !replies.isEmpty else { throw APIClientError.unexpectedResponse }
        switch replies.removeFirst() {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }

    func request(at index: Int) -> CapturedAuthRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }

    func requestCount() -> Int { requests.count }
}

private actor GatedAuthSessionTransport: APIResponseSending {
    private var requests: [CapturedAuthRequest] = []
    private var continuation: CheckedContinuation<APIClientResponse, Error>?

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        requests.append(CapturedAuthRequest(path: path, method: method, body: body, headers: headers))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }

    func respond(_ response: APIClientResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }

    func requestCount() -> Int { requests.count }
}

private actor ConcurrentLogoutTransport: APIResponseSending {
    private var requests: [CapturedAuthRequest] = []
    private var continuations: [Int: CheckedContinuation<APIClientResponse, Error>] = [:]

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        let index = requests.count
        requests.append(CapturedAuthRequest(path: path, method: method, body: body, headers: headers))
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }

    func respond(at index: Int, with result: Result<APIClientResponse, APIClientError>) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        switch result {
        case .success(let response): continuation.resume(returning: response)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func requestCount() -> Int { requests.count }
}

private struct RefreshRequestBody: Decodable {
    let refreshToken: String
    let requestId: UUID
}

private struct PersistedSocialLoginService: SocialLoginServing {
    let tokens: SocialLoginSessionTokens

    func issueChallenge(provider: SocialLoginProvider, deviceID: UUID) async throws -> SocialLoginChallenge {
        throw SocialLoginFailure.invalidRequest
    }

    func verify(
        provider: SocialLoginProvider,
        challenge: SocialLoginChallenge,
        deviceID: UUID,
        requestID: UUID,
        credential: String
    ) async throws -> SocialLoginProof {
        throw SocialLoginFailure.invalidRequest
    }

    func complete(_ request: SocialLoginCompletionRequest) async throws -> SocialLoginSessionTokens { tokens }
}

private struct UnusedSocialLoginCredentials: SocialLoginCredentialProviding {
    func credential(for provider: SocialLoginProvider, challenge: SocialLoginChallenge) async throws -> String? { nil }
}

final class AuthSessionPersistenceTests: XCTestCase {
    func testFixtureCleanupRequiresAnExplicitUUIDScopedAuthFixture() {
        let service = AuthSessionFixtureLaunchPolicy.servicePrefix + UUID().uuidString
        let validArguments = [
            "-wire-fixture",
            "-wire-auth-session-flow-fixture",
            "-wire-auth-session-fixture-service", service,
            "-wire-auth-session-fixture-cleanup"
        ]

        XCTAssertTrue(AuthSessionFixtureLaunchPolicy.isFixtureServiceName(service))
        XCTAssertFalse(AuthSessionFixtureLaunchPolicy.isFixtureServiceName("com.movtorun.auth-session.shared"))
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.fixtureServiceName(arguments: [
            "-wire-fixture", "-wire-auth-session-flow-fixture",
            "-wire-auth-session-fixture-service", "com.movtorun.ui-fixture.auth-session.not-a-uuid"
        ]))
        #if DEBUG
        XCTAssertEqual(AuthSessionFixtureLaunchPolicy.cleanupServiceName(arguments: validArguments), service)
        #else
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.cleanupServiceName(arguments: validArguments))
        #endif
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.cleanupServiceName(arguments: [
            "-wire-auth-session-fixture-cleanup"
        ]))
    }

    func testFixtureAppearanceDefaultsStayInTheInjectedSuite() {
        let suite = "mov.tests.appearance.\(UUID().uuidString)"
        let arguments = ["-wire-fixture", "-wire-test-store-suite", suite]
        #if DEBUG
        XCTAssertEqual(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: arguments), suite)
        XCTAssertEqual(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: ["-wire-fixture"]), "mov.wireframe.review")
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: []))
        #else
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: arguments))
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: ["-wire-fixture"]))
        #endif
    }

    func testFocusedUITestFixtureSuitesEndWithAStandaloneUUIDComponent() {
        let uuid = UUID().uuidString
        let prefixes = [
            "publish-busy",
            "create-unknown",
            "profile-photo-cancel",
            "profile-photo-failure"
        ]

        for prefix in prefixes {
            let validSuite = "mov.wireframe.test.\(prefix).\(uuid)"
            let invalidSuite = "mov.wireframe.test.\(prefix)-\(uuid)"
            let validArguments = ["-wire-fixture", "-wire-test-store-suite", validSuite]
            let invalidArguments = ["-wire-fixture", "-wire-test-store-suite", invalidSuite]
            #if DEBUG
            XCTAssertTrue(AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: validArguments), validSuite)
            XCTAssertFalse(AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: invalidArguments), invalidSuite)
            #else
            XCTAssertFalse(AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: validArguments), validSuite)
            XCTAssertFalse(AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: invalidArguments), invalidSuite)
            #endif
        }
    }

#if !DEBUG
    func testReleaseIgnoresAuthFixtureCleanupArguments() {
        let service = AuthSessionFixtureLaunchPolicy.servicePrefix + UUID().uuidString
        let arguments = [
            "-wire-fixture",
            "-wire-auth-session-flow-fixture",
            "-wire-auth-session-fixture-service", service,
            "-wire-auth-session-fixture-cleanup"
        ]

        XCTAssertNil(AuthSessionFixtureLaunchPolicy.cleanupServiceName(arguments: arguments))
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.fixtureServiceName(arguments: arguments))
        XCTAssertNil(AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments: arguments))
    }
#endif

    func testKeychainStoreRestoresWholeSnapshotAfterStoreRecreationAndUsesDeviceOnlyPolicy() throws {
        let service = uniqueService()
        let keychain = InMemoryKeychain()
        let expected = try snapshot(memberID: "41", access: "fixture-access-a", refresh: "fixture-refresh-a")
        let firstProcessStore = KeychainAuthSessionStore(service: service, keychain: keychain)

        try firstProcessStore.replaceAtomically(with: expected)

        let relaunchedProcessStore = KeychainAuthSessionStore(service: service, keychain: keychain)
        XCTAssertEqual(try relaunchedProcessStore.loadSnapshot(), expected)
        let policy = try XCTUnwrap(keychain.policy(service: service, account: "current-session-v1"))
        XCTAssertEqual(policy.0, .afterFirstUnlockThisDeviceOnly)
        XCTAssertFalse(policy.1)
        XCTAssertTrue(firstProcessStore.mutationCoordinator === relaunchedProcessStore.mutationCoordinator)
    }

    func testKeychainReplacementFailureLeavesPreviousSnapshotAndDoesNotExposeToken() throws {
        let service = uniqueService()
        let keychain = InMemoryKeychain()
        let store = KeychainAuthSessionStore(service: service, keychain: keychain)
        let old = try snapshot(memberID: "41", access: "fixture-old-access-secret", refresh: "fixture-old-refresh-secret")
        let replacement = try snapshot(memberID: "41", access: "fixture-new-access-secret", refresh: "fixture-new-refresh-secret")
        try store.replaceAtomically(with: old)
        keychain.failNextReplacement()

        XCTAssertThrowsError(try store.replaceAtomically(with: replacement)) { error in
            XCTAssertFalse(String(describing: error).contains(old.accessToken))
            XCTAssertFalse(String(describing: error).contains(old.refreshToken))
        }
        XCTAssertEqual(try store.loadSnapshot(), old)
    }

    func testCancelledLoginIgnoresLateSuccessfulResponseAndDoesNotPersistSession() async throws {
        let store = makeStore()
        let transport = GatedAuthSessionTransport()
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)

        let login = Task {
            try await client.login(email: "runner@example.test", password: "fixture-password", deviceID: UUID())
        }
        await transport.waitForRequestCount(1)
        login.cancel()
        await transport.respond(tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "cancelled-login-late-success"),
            refresh: "fixture-cancelled-login-refresh"
        ))

        do {
            _ = try await login.value
            XCTFail("A successful response returned after cancellation must not complete login")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        XCTAssertNil(try store.loadSnapshot())
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testRestoreAfterLaunchRefreshesSavedSessionAndDoesNothingWhenNoSessionExists() async throws {
        let emptyStore = makeStore()
        let unusedTransport = ScriptedAuthSessionTransport([])
        let emptyClient = AuthSessionClient(apiClient: unusedTransport, sessionStore: emptyStore)

        let emptyRestore = try await emptyClient.restoreAfterAppLaunch()
        let emptyRequestCount = await unusedTransport.requestCount()
        XCTAssertNil(emptyRestore)
        XCTAssertEqual(emptyRequestCount, 0)

        let store = makeStore()
        let original = try snapshot(memberID: "41", access: serverAccessToken(memberID: "41", marker: "old"), refresh: "fixture-refresh-before-launch")
        try store.replaceAtomically(with: original)
        let transport = ScriptedAuthSessionTransport([.response(tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "restored"),
            refresh: "fixture-refresh-after-launch"
        ))])
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)

        let restored = try await client.restoreAfterAppLaunch()

        XCTAssertEqual(restored?.accessToken, serverAccessToken(memberID: "41", marker: "restored"))
        XCTAssertEqual(try store.loadSnapshot()?.refreshToken, "fixture-refresh-after-launch")
        let capturedRequest = await transport.request(at: 0)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.path, "auth/token/refresh")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(try JSONDecoder().decode(RefreshRequestBody.self, from: XCTUnwrap(request.body)).refreshToken, original.refreshToken)
    }

    func testLostRefreshResponseRetriesSameTokenAndRequestIDThenReplacesSnapshotAtomically() async throws {
        let service = uniqueService()
        let keychain = InMemoryKeychain()
        let store = KeychainAuthSessionStore(service: service, keychain: keychain)
        let original = try snapshot(memberID: "41", access: serverAccessToken(memberID: "41", marker: "before"), refresh: "fixture-rtr-before")
        try store.replaceAtomically(with: original)
        let replacement = tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "after"),
            refresh: "fixture-rtr-after",
            refreshExpiresInSeconds: 399_900
        )
        let transport = ScriptedAuthSessionTransport([
            .failure(.transport(.timedOut)),
            .response(replacement)
        ])
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)

        do {
            _ = try await client.restoreAfterAppLaunch()
            XCTFail("Expected the first response to be lost")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .transport(.timedOut))
        }
        let relaunchedStore = KeychainAuthSessionStore(service: service, keychain: keychain)
        let relaunchedClient = AuthSessionClient(apiClient: transport, sessionStore: relaunchedStore)
        let pending = try XCTUnwrap(try relaunchedStore.loadSnapshot())
        let requestID = try XCTUnwrap(pending.refreshRequestID)
        XCTAssertEqual(pending.accessToken, original.accessToken)
        XCTAssertEqual(pending.refreshToken, original.refreshToken)

        let completed = try await relaunchedClient.restoreAfterAppLaunch()

        XCTAssertEqual(completed?.refreshToken, "fixture-rtr-after")
        XCTAssertNil(try relaunchedStore.loadSnapshot()?.refreshRequestID)
        let capturedFirstRequest = await transport.request(at: 0)
        let capturedRetryRequest = await transport.request(at: 1)
        let firstRequest = try XCTUnwrap(capturedFirstRequest)
        let retryRequest = try XCTUnwrap(capturedRetryRequest)
        let firstBody = try JSONDecoder().decode(RefreshRequestBody.self, from: XCTUnwrap(firstRequest.body))
        let retryBody = try JSONDecoder().decode(RefreshRequestBody.self, from: XCTUnwrap(retryRequest.body))
        XCTAssertEqual(firstBody.refreshToken, original.refreshToken)
        XCTAssertEqual(retryBody.refreshToken, original.refreshToken)
        XCTAssertEqual(firstBody.requestId, requestID)
        XCTAssertEqual(retryBody.requestId, requestID)
    }

    func testRefreshWriteFailureKeepsPendingOldPairForExactServerRetry() async throws {
        let service = uniqueService()
        let keychain = InMemoryKeychain()
        let store = KeychainAuthSessionStore(service: service, keychain: keychain)
        let original = try snapshot(memberID: "41", access: serverAccessToken(memberID: "41", marker: "before-write-failure"), refresh: "fixture-refresh-write-failure")
        try store.replaceAtomically(with: original)
        // The pending request write succeeds; the successor replacement fails.
        keychain.failNextReplacement(afterSuccessfulReplacements: 1)
        let response = tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "after-write-failure"),
            refresh: "fixture-successor"
        )
        let transport = ScriptedAuthSessionTransport([.response(response), .response(response)])
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)

        do {
            _ = try await client.refresh()
            XCTFail("Expected the local successor write to fail")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .storageUnavailable)
        }
        let pending = try XCTUnwrap(try store.loadSnapshot())
        let requestID = try XCTUnwrap(pending.refreshRequestID)
        XCTAssertEqual(pending.accessToken, original.accessToken)
        XCTAssertEqual(pending.refreshToken, original.refreshToken)

        let retried = try await client.refresh()

        XCTAssertEqual(retried.refreshToken, "fixture-successor")
        let firstRequest = await transport.request(at: 0)
        let secondRequest = await transport.request(at: 1)
        let first = try JSONDecoder().decode(RefreshRequestBody.self, from: XCTUnwrap(firstRequest?.body))
        let second = try JSONDecoder().decode(RefreshRequestBody.self, from: XCTUnwrap(secondRequest?.body))
        XCTAssertEqual(first.refreshToken, original.refreshToken)
        XCTAssertEqual(second.refreshToken, original.refreshToken)
        XCTAssertEqual(first.requestId, requestID)
        XCTAssertEqual(second.requestId, requestID)
    }

    func testConcurrentRefreshCallsShareOneRequest() async throws {
        let store = makeStore()
        try store.replaceAtomically(with: snapshot(
            memberID: "41",
            access: serverAccessToken(memberID: "41", marker: "single-flight"),
            refresh: "fixture-single-flight-refresh"
        ))
        let transport = GatedAuthSessionTransport()
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)

        let first = Task { try await client.refresh() }
        await transport.waitForRequestCount(1)
        let second = Task { try await client.refresh() }
        for _ in 0..<20 { await Task.yield() }
        let countBeforeResponse = await transport.requestCount()
        XCTAssertEqual(countBeforeResponse, 1)

        await transport.respond(tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "single-flight-next"),
            refresh: "fixture-single-flight-next"
        ))
        let firstSnapshot = try await first.value
        let secondSnapshot = try await second.value
        XCTAssertEqual(firstSnapshot, secondSnapshot)
        let finalRequestCount = await transport.requestCount()
        XCTAssertEqual(finalRequestCount, 1)
    }

    func testCancelledRefreshDoesNotPublishAResultButKeepsCommittedSuccessor() async throws {
        let store = makeStore()
        try store.replaceAtomically(with: snapshot(
            memberID: "41",
            access: serverAccessToken(memberID: "41", marker: "cancelled-refresh"),
            refresh: "fixture-cancelled-refresh"
        ))
        let transport = GatedAuthSessionTransport()
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)
        let refresh = Task { try await client.refresh() }
        await transport.waitForRequestCount(1)
        refresh.cancel()
        await transport.respond(tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "cancelled-successor"),
            refresh: "fixture-cancelled-successor"
        ))

        do {
            _ = try await refresh.value
            XCTFail("A cancelled caller must not receive a late refresh result")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .cancelled)
        }
        XCTAssertEqual(try store.loadSnapshot()?.refreshToken, "fixture-cancelled-successor")
    }

    func testCancelledStaleRefreshCannotOverwriteChangedAccount() async throws {
        let store = makeStore()
        try store.replaceAtomically(with: snapshot(
            memberID: "41",
            access: serverAccessToken(memberID: "41", marker: "account-a"),
            refresh: "fixture-account-a-refresh"
        ))
        let transport = GatedAuthSessionTransport()
        let client = AuthSessionClient(apiClient: transport, sessionStore: store)
        let refresh = Task { try await client.refresh() }
        await transport.waitForRequestCount(1)
        refresh.cancel()

        let coordinator = store.mutationCoordinator
        let lease = try await coordinator.beginLogin()
        let accountB = try snapshot(memberID: "99", access: serverAccessToken(memberID: "99", marker: "account-b"), refresh: "fixture-account-b-refresh")
        try await coordinator.commitLogin(accountB, lease: lease, store: store)
        await transport.respond(tokenResponse(
            access: serverAccessToken(memberID: "41", marker: "stale-account-a"),
            refresh: "fixture-stale-account-a-refresh"
        ))

        do {
            _ = try await refresh.value
            XCTFail("A stale response must not restore the prior account")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .sessionChanged)
        }
        XCTAssertEqual(try store.loadSnapshot(), accountB)
    }

    func testUnauthorizedRefreshAndConfirmedLogoutClearStoredSession() async throws {
        let store = makeStore()
        try store.replaceAtomically(with: snapshot(
            memberID: "41",
            access: serverAccessToken(memberID: "41", marker: "logout"),
            refresh: "fixture-logout-refresh"
        ))
        let expired = AuthSessionClient(
            apiClient: ScriptedAuthSessionTransport([.response(APIClientResponse(statusCode: 401, data: Data(), requestID: nil))]),
            sessionStore: store
        )
        do {
            _ = try await expired.refresh()
            XCTFail("Expected the expired session to fail")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .unauthenticated)
        }
        XCTAssertNil(try store.loadSnapshot())

        try store.replaceAtomically(with: snapshot(
            memberID: "41",
            access: serverAccessToken(memberID: "41", marker: "logout-confirmed"),
            refresh: "fixture-logout-confirmed-refresh"
        ))
        let loggedOut = AuthSessionClient(
            apiClient: ScriptedAuthSessionTransport([.response(APIClientResponse(statusCode: 204, data: Data(), requestID: nil))]),
            sessionStore: store
        )
        try await loggedOut.logout()
        XCTAssertNil(try store.loadSnapshot())
    }

    func testLogoutStorageFailureRetainsPriorSession() async throws {
        let service = uniqueService()
        let keychain = InMemoryKeychain()
        let store = KeychainAuthSessionStore(service: service, keychain: keychain)
        let original = try snapshot(memberID: "41", access: serverAccessToken(memberID: "41", marker: "logout-store-fail"), refresh: "fixture-logout-store-fail")
        try store.replaceAtomically(with: original)
        keychain.failNextDeletion()
        let client = AuthSessionClient(
            apiClient: ScriptedAuthSessionTransport([.response(APIClientResponse(statusCode: 204, data: Data(), requestID: nil))]),
            sessionStore: store
        )

        do {
            try await client.logout()
            XCTFail("The client must not report logout when local cleanup fails")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .storageUnavailable)
        }
        XCTAssertEqual(try store.loadSnapshot(), original)
    }

    func testConcurrentLogoutFirstSuccessThenSecondTimeoutClearsStoredSession() async throws {
        let store = makeStore()
        let original = try snapshot(memberID: "41", access: "fixture-logout-order-a", refresh: "fixture-logout-refresh-order-a")
        try store.replaceAtomically(with: original)
        let transport = ConcurrentLogoutTransport()
        let firstClient = AuthSessionClient(apiClient: transport, sessionStore: store)
        let secondClient = AuthSessionClient(apiClient: transport, sessionStore: store)

        let first = Task { try await firstClient.logout() }
        await transport.waitForRequestCount(1)
        let second = Task { try await secondClient.logout() }
        await transport.waitForRequestCount(2)

        await transport.respond(at: 0, with: .success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
        try await first.value
        await transport.respond(at: 1, with: .failure(.transport(.timedOut)))
        do {
            try await second.value
            XCTFail("Expected the second logout request to time out")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .transport(.timedOut))
        }

        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(try store.loadSnapshot())
    }

    func testConcurrentLogoutFirstTimeoutThenSecondSuccessClearsStoredSession() async throws {
        let store = makeStore()
        let original = try snapshot(memberID: "41", access: "fixture-logout-order-b", refresh: "fixture-logout-refresh-order-b")
        try store.replaceAtomically(with: original)
        let transport = ConcurrentLogoutTransport()
        let firstClient = AuthSessionClient(apiClient: transport, sessionStore: store)
        let secondClient = AuthSessionClient(apiClient: transport, sessionStore: store)

        let first = Task { try await firstClient.logout() }
        await transport.waitForRequestCount(1)
        let second = Task { try await secondClient.logout() }
        await transport.waitForRequestCount(2)

        await transport.respond(at: 0, with: .failure(.transport(.timedOut)))
        do {
            try await first.value
            XCTFail("Expected the first logout request to time out")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .transport(.timedOut))
        }
        XCTAssertEqual(try store.loadSnapshot(), original)

        await transport.respond(at: 1, with: .success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
        try await second.value

        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(try store.loadSnapshot())
    }

    func testLateLogoutSuccessCannotClearNewAccountSession() async throws {
        let store = makeStore()
        let original = try snapshot(memberID: "41", access: "fixture-logout-old-account", refresh: "fixture-logout-old-refresh")
        try store.replaceAtomically(with: original)
        let transport = ConcurrentLogoutTransport()
        let firstClient = AuthSessionClient(apiClient: transport, sessionStore: store)
        let secondClient = AuthSessionClient(apiClient: transport, sessionStore: store)

        let first = Task { try await firstClient.logout() }
        await transport.waitForRequestCount(1)
        let second = Task { try await secondClient.logout() }
        await transport.waitForRequestCount(2)

        do {
            _ = try await store.mutationCoordinator.beginLogin()
            XCTFail("A new login must not start while logout requests are pending")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure, .requestInProgress)
        }

        await transport.respond(at: 0, with: .success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
        try await first.value

        let loginLease = try await store.mutationCoordinator.beginLogin()
        let newAccount = try snapshot(memberID: "99", access: "fixture-logout-new-account", refresh: "fixture-logout-new-refresh")
        try await store.mutationCoordinator.commitLogin(newAccount, lease: loginLease, store: store)

        await transport.respond(at: 1, with: .success(APIClientResponse(statusCode: 204, data: Data(), requestID: nil)))
        do {
            try await second.value
            XCTFail("A stale logout response must not commit against the new account")
        } catch let failure as SessionLogoutFailure {
            XCTAssertEqual(failure, .sessionChanged)
        }

        XCTAssertEqual(try store.loadSnapshot(), newAccount)
    }

    func testSocialLoginPersistsOnlyValidatedServerIssuedTokensAndRetainsOldPairOnFailure() async throws {
        let store = makeStore()
        let old = try snapshot(memberID: "41", access: "fixture-existing-access", refresh: "fixture-existing-refresh")
        try store.replaceAtomically(with: old)
        let tokens = SocialLoginSessionTokens(
            accessToken: serverAccessToken(memberID: "99", marker: "social-login"),
            refreshToken: "fixture-social-refresh",
            tokenType: "Bearer",
            accessExpiresInSeconds: 900,
            refreshExpiresInSeconds: 604_800
        )
        let service = PersistedSocialLoginService(tokens: tokens)
        let coordinator = SocialLoginCoordinator(service: service, credentials: UnusedSocialLoginCredentials(), sessionStore: store)
        let request = SocialLoginCompletionRequest(socialSignupProof: "fixture-proof", deviceID: UUID())

        let persistedTokens = try await coordinator.complete(request)
        XCTAssertEqual(persistedTokens, tokens)
        XCTAssertEqual(try store.loadSnapshot()?.memberID, "99")
        XCTAssertEqual(try store.loadSnapshot()?.refreshToken, "fixture-social-refresh")

        let failingKeychain = InMemoryKeychain()
        let failingStore = KeychainAuthSessionStore(service: uniqueService(), keychain: failingKeychain)
        let retained = try snapshot(memberID: "41", access: "fixture-retained-access", refresh: "fixture-retained-refresh")
        try failingStore.replaceAtomically(with: retained)
        failingKeychain.failNextReplacement()
        let failingCoordinator = SocialLoginCoordinator(service: service, credentials: UnusedSocialLoginCredentials(), sessionStore: failingStore)
        do {
            _ = try await failingCoordinator.complete(request)
            XCTFail("Expected server-issued tokens to fail local persistence")
        } catch let failure as SocialLoginFailure {
            XCTAssertEqual(failure, .storageUnavailable)
        }
        XCTAssertEqual(try failingStore.loadSnapshot(), retained)
    }

    private func makeStore() -> KeychainAuthSessionStore {
        KeychainAuthSessionStore(service: uniqueService(), keychain: InMemoryKeychain())
    }

    private func uniqueService() -> String { "com.movtorun.tests.auth-session.\(UUID().uuidString)" }

    private func snapshot(memberID: String, access: String, refresh: String) throws -> AuthSessionSnapshot {
        try AuthSessionSnapshot(accessToken: access, refreshToken: refresh, memberID: memberID)
    }

    private func serverAccessToken(memberID: String, marker: String) -> String {
        let claims = Data("{\"sub\":\"\(memberID)\",\"fixture\":\"\(marker)\"}".utf8)
        let payload = claims.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "fixture-header.\(payload).fixture-signature"
    }

    private func tokenResponse(
        access: String,
        refresh: String,
        refreshExpiresInSeconds: Int = 604_800
    ) -> APIClientResponse {
        let body = try! JSONSerialization.data(withJSONObject: [
            "accessToken": access,
            "refreshToken": refresh,
            "tokenType": "Bearer",
            "accessExpiresInSeconds": 900,
            "refreshExpiresInSeconds": refreshExpiresInSeconds
        ])
        return APIClientResponse(statusCode: 200, data: body, requestID: nil)
    }

}
