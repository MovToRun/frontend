import Foundation

struct RunUploadPoint: Codable, Equatable, Sendable {
    let recordedAt: Date
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let altitudeMeters: Double?
    let speedMetersPerSecond: Double?

    init(
        recordedAt: Date,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        altitudeMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) {
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

struct RunUploadPause: Codable, Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
}

/// The measurement snapshot sent to POST /runs. A retry must reuse this value and clientRunID.
struct RunUploadPayload: Codable, Equatable, Sendable {
    let clientRunID: UUID
    let startedAt: Date
    let endedAt: Date
    let movingSeconds: Int
    let distanceMeters: Int
    let title: String?
    let memo: String?
    let points: [RunUploadPoint]
    let pauses: [RunUploadPause]

    init(
        clientRunID: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        movingSeconds: Int,
        distanceMeters: Int,
        title: String? = nil,
        memo: String? = nil,
        points: [RunUploadPoint] = [],
        pauses: [RunUploadPause] = []
    ) {
        self.clientRunID = clientRunID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters
        self.title = title
        self.memo = memo
        self.points = points
        self.pauses = pauses
    }

    private enum CodingKeys: String, CodingKey {
        case clientRunID = "clientRunId"
        case startedAt
        case endedAt
        case movingSeconds
        case distanceMeters
        case title
        case memo
        case points
        case pauses
    }

    func requestBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.requestTimestamp(for: date))
        }
        return try encoder.encode(self)
    }

    private static func requestTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Captured atomically by the app's auth adapter at the start of a manual drain.
/// The token is intentionally never persisted with the local outbox.
struct RunUploadSession: Equatable, Sendable {
    let ownerID: String
    let accessToken: String

    init(ownerID: String, accessToken: String) {
        self.ownerID = ownerID
        self.accessToken = accessToken
    }
}

protocol RunUploadSessionProviding: Sendable {
    func currentSession() async throws -> RunUploadSession?
}

enum RunUploadDelivery: Equatable, Sendable {
    case accepted
    case alreadyDeleted
    case terminal(code: String)
    case retryLater(code: String)
}

protocol RunUploading: Sendable {
    func upload(_ payload: RunUploadPayload, session: RunUploadSession) async throws -> RunUploadDelivery
}

struct RunUploadClient: RunUploading, Sendable {
    private let apiClient: any APIResponseSending

    init(apiClient: any APIResponseSending) {
        self.apiClient = apiClient
    }

    func upload(_ payload: RunUploadPayload, session: RunUploadSession) async throws -> RunUploadDelivery {
        guard !session.ownerID.isEmpty,
              session.ownerID.rangeOfCharacter(from: .controlCharacters) == nil,
              !session.accessToken.isEmpty,
              session.accessToken.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
        else {
            return .retryLater(code: "AUTHENTICATION_UNAVAILABLE")
        }

        let body: Data
        do {
            body = try payload.requestBody()
        } catch {
            return .terminal(code: "INVALID_LOCAL_PAYLOAD")
        }

        let response: APIClientResponse
        do {
            response = try await apiClient.sendResponse(
                path: "runs",
                method: "POST",
                body: body,
                headers: [
                    "Authorization": "Bearer \(session.accessToken)",
                    "Accept": "application/json",
                    "Cache-Control": "no-store",
                    "Content-Type": "application/json"
                ],
                queryItems: []
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A transport error can arrive after the server committed. Keep the same id for replay.
            return .retryLater(code: "TRANSPORT")
        }

        switch response.statusCode {
        case 200, 201:
            return .accepted
        case 410:
            let code = Self.problemCode(in: response.data)
            return code == "RUN_DELETED" ? .alreadyDeleted : .terminal(code: code ?? "HTTP_410")
        case 409:
            return .terminal(code: Self.problemCode(in: response.data) ?? "HTTP_409")
        case 400, 413:
            return .terminal(code: Self.problemCode(in: response.data) ?? "HTTP_\(response.statusCode)")
        case 422:
            let code = Self.problemCode(in: response.data) ?? "HTTP_422"
            return code == "RUN_IN_FUTURE" ? .retryLater(code: code) : .terminal(code: code)
        case 401, 403:
            return .retryLater(code: "AUTHENTICATION_REQUIRED")
        case 429:
            return .retryLater(code: "HTTP_429")
        case 500...599:
            return .retryLater(code: "HTTP_\(response.statusCode)")
        default:
            // Unknown responses are ambiguous; an idempotent manual replay is safe.
            return .retryLater(code: "HTTP_\(response.statusCode)")
        }
    }

    private static func problemCode(in data: Data) -> String? {
        struct Problem: Decodable { let code: String? }
        return try? JSONDecoder().decode(Problem.self, from: data).code
    }
}
