import Foundation
import XCTest
@testable import MovNetworking

private struct FixedAccessTokenProvider: AccessTokenProviding {
    let value: String?

    func accessToken() async throws -> String? { value }
}

private actor CountingAccessTokenProvider: AccessTokenProviding {
    private let value: String?
    private var requests = 0

    init(value: String?) { self.value = value }

    func accessToken() async throws -> String? {
        requests += 1
        return value
    }

    func requestCount() -> Int { requests }
}

private struct DelayedMemberProfileFetcher: MemberProfileFetching {
    let delayNanoseconds: UInt64

    func fetchProfile() async throws -> MemberProfile {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return MemberProfile(nickname: "MoveRunner")
    }
}

private actor SequencedMemberProfileFetcher: MemberProfileFetching {
    private var results: [Result<MemberProfile, MemberProfileFailure>]
    private var requests = 0

    init(_ results: [Result<MemberProfile, MemberProfileFailure>]) { self.results = results }

    func fetchProfile() async throws -> MemberProfile {
        requests += 1
        guard !results.isEmpty else { throw MemberProfileFailure.invalidResponse }
        return try results.removeFirst().get()
    }

    func requestCount() -> Int { requests }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private enum Outcome: Sendable {
        case response(Int, Data, [String: String])
        case failure(URLError.Code)
    }

    private final class Store: @unchecked Sendable {
        static let shared = Store()
        private let lock = NSLock()
        private var outcomes: [Outcome] = []
        private var requests: [URLRequest] = []

        func configure(_ outcomes: [Outcome]) {
            lock.lock(); defer { lock.unlock() }
            self.outcomes = outcomes
            requests = []
        }

        func take(for request: URLRequest) -> Outcome {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            guard !outcomes.isEmpty else { return .failure(.unknown) }
            return outcomes.removeFirst()
        }

        func recordedRequests() -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return requests
        }
    }

    static func respond(statusCode: Int, data: Data = Data(), headers: [String: String] = [:]) {
        Store.shared.configure([.response(statusCode, data, headers)])
    }
    static func respondSequence(_ responses: [(Int, Data)]) {
        Store.shared.configure(responses.map { .response($0.0, $0.1, [:]) })
    }
    static func fail(with error: URLError.Code) { Store.shared.configure([.failure(error)]) }
    static func failThenRespond(with error: URLError.Code, statusCode: Int, data: Data) {
        Store.shared.configure([.failure(error), .response(statusCode, data, [:])])
    }
    static func cancel() { Store.shared.configure([.failure(.cancelled)]) }
    static func reset() { Store.shared.configure([]) }
    static var requests: [URLRequest] { Store.shared.recordedRequests() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Store.shared.take(for: request) {
        case let .response(statusCode, data, headers):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func makeClient() throws -> APIClient {
        let configuration = try APIClientConfiguration(
            environment: .development,
            baseURLString: "https://api-dev.example.invalid/api/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        return APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
    }

    func testBuildsRelativeRequestUnderConfiguredBasePath() throws {
        let request = try makeClient().makeRequest(path: "runs", method: "POST", body: Data("{}".utf8), headers: ["Content-Type": "application/json"])
        XCTAssertEqual(request.url?.absoluteString, "https://api-dev.example.invalid/api/v1/runs")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 4)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testDefaultSessionUsesConfiguredTimeouts() throws {
        let configuration = try APIClientConfiguration(
            environment: .development,
            baseURLString: "https://api-dev.example.invalid/api/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = APIClient.defaultSessionConfiguration(for: configuration)
        XCTAssertEqual(sessionConfiguration.timeoutIntervalForRequest, 4)
        XCTAssertEqual(sessionConfiguration.timeoutIntervalForResource, 9)
    }

    func testNormalizesBaseURLWithoutTrailingSlash() throws {
        let configuration = try APIClientConfiguration(environment: .production, baseURLString: "https://api.example.invalid/api/v1", requestTimeout: 5, resourceTimeout: 10)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.example.invalid/api/v1/")
        XCTAssertEqual(try APIClient(configuration: configuration).makeRequest(path: "runs").url?.absoluteString, "https://api.example.invalid/api/v1/runs")
    }

    func testRejectsMissingOrInsecureBaseURLAndInvalidTimeouts() {
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "", requestTimeout: 4, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .missingBaseURL) }
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "http://localhost", requestTimeout: 4, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .insecureBaseURL) }
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "https://api.example.invalid", requestTimeout: 10, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .invalidTimeout) }
        for invalidPath in ["/%2e%2e/", "/%2E%2E/", "/%2fadmin/", "/%5cadmin/", "/%3fquery/", "/%23fragment/", "/../", "/api//v1/"] {
            XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "https://api.example.invalid\(invalidPath)", requestTimeout: 4, resourceTimeout: 9), invalidPath) {
                XCTAssertEqual($0 as? APIClientError, .invalidBaseURL)
            }
        }
    }

    func testRejectsAbsoluteAndTraversalPaths() throws {
        let client = try makeClient()
        XCTAssertThrowsError(try client.makeRequest(path: "/outside")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "../outside")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "%2e%2e/admin")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "%2E%2E/admin")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "%2fadmin")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "users?admin=true")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "users//admin")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
        XCTAssertThrowsError(try client.makeRequest(path: "api/v1/runs")) { XCTAssertEqual($0 as? APIClientError, .invalidPath) }
    }

    func testReturnsSuccessBodyFromMockedNetwork() async throws {
        let body = Data("{\"ok\":true}".utf8)
        MockURLProtocol.respond(statusCode: 200, data: body)
        let result = try await makeClient().send(path: "health")
        XCTAssertEqual(result, body)
    }

    func testMapsMockedHTTPErrorWithoutExposingResponseBody() async throws {
        MockURLProtocol.respond(statusCode: 503, data: Data("sensitive upstream detail".utf8))
        do {
            _ = try await makeClient().send(path: "health")
            XCTFail("Expected a server status error")
        } catch {
            XCTAssertEqual(error as? APIClientError, .httpStatus(503))
            XCTAssertFalse(String(describing: error).contains("sensitive"))
        }
    }

    func testMapsMockedTransportError() async throws {
        MockURLProtocol.fail(with: .timedOut)
        do {
            _ = try await makeClient().send(path: "health")
            XCTFail("Expected a transport error")
        } catch {
            XCTAssertEqual(error as? APIClientError, .transport(.timedOut))
        }
    }

    func testMapsMockedCancellationError() async throws {
        MockURLProtocol.cancel()
        do {
            _ = try await makeClient().send(path: "runs")
            XCTFail("Expected a cancellation error")
        } catch {
            XCTAssertEqual(error as? APIClientError, .cancelled)
        }
    }

    func testMemberProfileFetchUsesConfirmedRouteAndDecodesNickname() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("{\"nickname\":\"MoveRunner\"}".utf8))
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: FixedAccessTokenProvider(value: "fixture-access-token"),
            sleep: { _ in }
        )

        let profile = try await client.fetchProfile()
        let request = try XCTUnwrap(MockURLProtocol.requests.first)

        XCTAssertEqual(profile, MemberProfile(nickname: "MoveRunner"))
        XCTAssertEqual(request.url?.absoluteString, "https://api-dev.example.invalid/api/v1/members/me/profile")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testUnavailableProfileServiceRetriesOnceAndReadsTokenOnlyOnce() async throws {
        let problem = Data("{\"status\":503,\"code\":\"AUTH_UNAVAILABLE\",\"title\":\"Temporary outage\",\"requestId\":\"req-profile-1\"}".utf8)
        let profileBody = Data("{\"nickname\":\"MoveRunner\"}".utf8)
        MockURLProtocol.respondSequence([(503, problem), (200, profileBody)])
        let tokenProvider = CountingAccessTokenProvider(value: "fixture-access-token")
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: tokenProvider,
            retryPolicy: MemberProfileRetryPolicy(maximumAttempts: 2, delayNanoseconds: 0),
            sleep: { _ in }
        )

        let profile = try await client.fetchProfile()

        XCTAssertEqual(profile.nickname, "MoveRunner")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        let tokenRequestCount = await tokenProvider.requestCount()
        XCTAssertEqual(tokenRequestCount, 1)
        XCTAssertTrue(MockURLProtocol.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token"
        })
    }

    func testUnavailableProfileServiceRetainsResponseRequestID() async throws {
        let problem = Data("{\"status\":503,\"code\":\"AUTH_UNAVAILABLE\",\"title\":\"Temporary outage\"}".utf8)
        MockURLProtocol.respond(statusCode: 503, data: problem, headers: ["X-Request-Id": "req-profile-header"])
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: FixedAccessTokenProvider(value: "fixture-access-token"),
            retryPolicy: MemberProfileRetryPolicy(maximumAttempts: 1),
            sleep: { _ in }
        )

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected a service unavailable response")
        } catch let failure as MemberProfileFailure {
            XCTAssertEqual(failure, .serviceUnavailable(requestID: "req-profile-header"))
            XCTAssertFalse(failure.userMessage.contains("Temporary outage"))
        }
    }

    func testUnauthenticatedProfileResponseIsSafeAndNeverRetried() async throws {
        let problem = Data("{\"status\":401,\"code\":\"UNAUTHENTICATED\",\"title\":\"private backend exception\",\"requestId\":\"req-profile-2\"}".utf8)
        MockURLProtocol.respond(statusCode: 401, data: problem)
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: FixedAccessTokenProvider(value: "fixture-access-token"),
            retryPolicy: MemberProfileRetryPolicy(maximumAttempts: 3, delayNanoseconds: 0),
            sleep: { _ in }
        )

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected an unauthenticated response")
        } catch let failure as MemberProfileFailure {
            XCTAssertEqual(failure, .unauthenticated)
            XCTAssertFalse(String(describing: failure).contains("private backend exception"))
            XCTAssertFalse(failure.userMessage.contains("private backend exception"))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testMissingAccessTokenStopsBeforeSendingARequest() async throws {
        MockURLProtocol.reset()
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: FixedAccessTokenProvider(value: nil),
            sleep: { _ in }
        )

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected a missing access token")
        } catch let failure as MemberProfileFailure {
            XCTAssertEqual(failure, .accessTokenUnavailable)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testMalformedProfileBodyMapsToSafeNonRetryableFailure() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data("{\"name\":\"not-the-contract\"}".utf8))
        let client = MemberProfileClient(
            apiClient: try makeClient(),
            tokenProvider: FixedAccessTokenProvider(value: "fixture-access-token"),
            retryPolicy: MemberProfileRetryPolicy(maximumAttempts: 3, delayNanoseconds: 0),
            sleep: { _ in }
        )

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected an invalid response")
        } catch let failure as MemberProfileFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testRetryPolicyAllowsAtMostOneAutomaticRetry() {
        XCTAssertEqual(MemberProfileRetryPolicy(maximumAttempts: 1).maximumAttempts, 1)
        XCTAssertEqual(MemberProfileRetryPolicy(maximumAttempts: 2).maximumAttempts, 2)
        XCTAssertEqual(MemberProfileRetryPolicy(maximumAttempts: 20).maximumAttempts, 2)
    }

    func testProfileLoaderPublishesLoadingThenLoadedState() async throws {
        let loader = MemberProfileLoader(fetcher: DelayedMemberProfileFetcher(delayNanoseconds: 100_000_000))
        let task = Task { await loader.load() }

        var observedLoading = false
        for _ in 0..<100 {
            if await loader.state == .loading {
                observedLoading = true
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(observedLoading)
        await task.value
        let finalState = await loader.state
        XCTAssertEqual(finalState, .loaded(MemberProfile(nickname: "MoveRunner")))
    }

    func testProfileLoaderExposesFailureAndExplicitRetry() async {
        let profile = MemberProfile(nickname: "MoveRunner")
        let fetcher = SequencedMemberProfileFetcher([
            .failure(.serviceUnavailable(requestID: "req-profile-3")),
            .success(profile)
        ])
        let loader = MemberProfileLoader(fetcher: fetcher)

        await loader.load()
        let failedState = await loader.state
        XCTAssertEqual(failedState, .failed(.serviceUnavailable(requestID: "req-profile-3")))
        await loader.retry()
        let loadedState = await loader.state
        XCTAssertEqual(loadedState, .loaded(profile))
        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 2)
    }
}
