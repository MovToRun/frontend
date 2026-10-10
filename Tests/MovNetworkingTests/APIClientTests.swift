import Foundation
import XCTest
@testable import MovNetworking

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private enum Outcome {
        case response(Int, Data)
        case failure(URLError.Code)
    }

    private final class Store: @unchecked Sendable {
        static let shared = Store()
        private let lock = NSLock()
        private var nextResponse: (Int, Data)?
        private var nextError: URLError.Code?

        func configure(statusCode: Int, data: Data) {
            lock.lock(); defer { lock.unlock() }
            nextResponse = (statusCode, data)
            nextError = nil
        }

        func configure(error: URLError.Code) {
            lock.lock(); defer { lock.unlock() }
            nextResponse = nil
            nextError = error
        }

        func take() -> Outcome {
            lock.lock(); defer { lock.unlock() }
            if let error = nextError { return .failure(error) }
            guard let response = nextResponse else { return .failure(.unknown) }
            return .response(response.0, response.1)
        }
    }

    static func respond(statusCode: Int, data: Data = Data()) { Store.shared.configure(statusCode: statusCode, data: data) }
    static func fail(with error: URLError.Code) { Store.shared.configure(error: error) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Store.shared.take() {
        case let .response(statusCode, data):
            guard let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
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
            baseURLString: "https://api-dev.example.invalid/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        return APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
    }

    func testBuildsRelativeRequestUnderConfiguredBasePath() throws {
        let request = try makeClient().makeRequest(path: "profile", method: "PATCH", body: Data("{}".utf8), headers: ["Content-Type": "application/json"])
        XCTAssertEqual(request.url?.absoluteString, "https://api-dev.example.invalid/v1/profile")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.timeoutInterval, 4)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testDefaultSessionUsesConfiguredTimeouts() throws {
        let configuration = try APIClientConfiguration(
            environment: .development,
            baseURLString: "https://api-dev.example.invalid/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = APIClient.defaultSessionConfiguration(for: configuration)
        XCTAssertEqual(sessionConfiguration.timeoutIntervalForRequest, 4)
        XCTAssertEqual(sessionConfiguration.timeoutIntervalForResource, 9)
    }

    func testNormalizesBaseURLWithoutTrailingSlash() throws {
        let configuration = try APIClientConfiguration(environment: .production, baseURLString: "https://api.example.invalid/v2", requestTimeout: 5, resourceTimeout: 10)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.example.invalid/v2/")
        XCTAssertEqual(try APIClient(configuration: configuration).makeRequest(path: "health").url?.absoluteString, "https://api.example.invalid/v2/health")
    }

    func testRejectsMissingOrInsecureBaseURLAndInvalidTimeouts() {
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "", requestTimeout: 4, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .missingBaseURL) }
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "http://localhost", requestTimeout: 4, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .insecureBaseURL) }
        XCTAssertThrowsError(try APIClientConfiguration(environment: .development, baseURLString: "https://api.example.invalid", requestTimeout: 10, resourceTimeout: 9)) { XCTAssertEqual($0 as? APIClientError, .invalidTimeout) }
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
}
