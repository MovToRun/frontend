import Foundation

enum APIEnvironment: String, Sendable {
    case development
    case production
}

struct APIClientConfiguration: Sendable {
    let environment: APIEnvironment
    let baseURL: URL
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval

    init(environment: APIEnvironment, baseURLString: String, requestTimeout: TimeInterval, resourceTimeout: TimeInterval) throws {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIClientError.missingBaseURL }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.url != nil else {
            throw APIClientError.invalidBaseURL
        }
        guard scheme == "https" else { throw APIClientError.insecureBaseURL }
        guard requestTimeout.isFinite, requestTimeout > 0,
              resourceTimeout.isFinite, resourceTimeout >= requestTimeout else {
            throw APIClientError.invalidTimeout
        }

        var normalizedComponents = components
        if !normalizedComponents.path.hasSuffix("/") { normalizedComponents.path += "/" }
        guard let normalizedURL = normalizedComponents.url else { throw APIClientError.invalidBaseURL }

        self.environment = environment
        self.baseURL = normalizedURL
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    static func bundled(from bundle: Bundle = .main) throws -> APIClientConfiguration {
        let environmentKey = "MovAPIEnvironment"
        let baseURLKey = "MovAPIBaseURL"
        let timeoutKey = "MovAPIRequestTimeoutSeconds"
        let resourceTimeoutKey = "MovAPIResourceTimeoutSeconds"

        guard let rawEnvironment = bundle.object(forInfoDictionaryKey: environmentKey) as? String,
              let environment = APIEnvironment(rawValue: rawEnvironment) else {
            throw APIClientError.missingEnvironment
        }
        guard let baseURL = bundle.object(forInfoDictionaryKey: baseURLKey) as? String else {
            throw APIClientError.missingBaseURL
        }
        let requestTimeout = (bundle.object(forInfoDictionaryKey: timeoutKey) as? NSString)?.doubleValue
            ?? (bundle.object(forInfoDictionaryKey: timeoutKey) as? NSNumber)?.doubleValue ?? 30
        let resourceTimeout = (bundle.object(forInfoDictionaryKey: resourceTimeoutKey) as? NSString)?.doubleValue
            ?? (bundle.object(forInfoDictionaryKey: resourceTimeoutKey) as? NSNumber)?.doubleValue ?? 60
        return try APIClientConfiguration(
            environment: environment,
            baseURLString: baseURL,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
    }
}

enum APIClientError: Error, Equatable {
    case missingEnvironment
    case missingBaseURL
    case invalidBaseURL
    case insecureBaseURL
    case invalidTimeout
    case invalidPath
    case unexpectedResponse
    case httpStatus(Int)
    case transport(URLError.Code)
}

final class APIClient: @unchecked Sendable {
    private let configuration: APIClientConfiguration
    private let session: URLSession

    init(configuration: APIClientConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            self.session = URLSession(configuration: Self.defaultSessionConfiguration(for: configuration))
        }
    }

    static func defaultSessionConfiguration(for configuration: APIClientConfiguration) -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
        return sessionConfiguration
    }

    func makeRequest(path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        let allowedPathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pathSegments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              pathSegments.allSatisfy({ segment in
                  !segment.isEmpty && segment != "." && segment != ".."
                      && segment.unicodeScalars.allSatisfy(allowedPathCharacters.contains)
              }),
              let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL,
              url.host == configuration.baseURL.host,
              url.scheme == "https",
              url.path.hasPrefix(configuration.baseURL.path) else {
            throw APIClientError.invalidPath
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    func send(path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        let request = try makeRequest(path: path, method: method, body: body, headers: headers)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw APIClientError.unexpectedResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw APIClientError.httpStatus(response.statusCode)
            }
            return data
        } catch let error as APIClientError {
            throw error
        } catch let error as URLError {
            throw APIClientError.transport(error.code)
        } catch {
            throw APIClientError.transport(.unknown)
        }
    }
}
