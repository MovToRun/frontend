import Foundation

enum MediaUploadPurpose: String, Codable, Sendable {
    case profilePhoto = "PROFILE_PHOTO"
    case postAttachment = "POST_ATTACHMENT"
}

enum MediaUploadKind: String, Codable, Sendable {
    case photo = "PHOTO"
    case video = "VIDEO"
}

struct MediaUploadFile: Equatable, Sendable {
    let kind: MediaUploadKind
    let contentType: String
    let data: Data

    init(kind: MediaUploadKind = .photo, contentType: String, data: Data) {
        self.kind = kind
        self.contentType = contentType
        self.data = data
    }
}

struct MediaReadyItem: Equatable, Sendable {
    let assetID: String
    let kind: MediaUploadKind
    let contentType: String
    let bytes: Int64
    let widthPixels: Int
    let heightPixels: Int
    let durationMilliseconds: Int64
    let position: Int
}

struct MediaReadyBatch: Equatable, Sendable {
    let batchID: String
    let purpose: MediaUploadPurpose
    let items: [MediaReadyItem]
    let totalBytes: Int64
}

protocol MediaSignedURLSending: Sendable {
    /// The ticket URL is the only authority for this request. Callers must not add API credentials.
    func put(data: Data, to url: URL, headers: [String: String]) async throws -> APIClientResponse
}

struct URLSessionMediaSignedURLSender: MediaSignedURLSending, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func put(data: Data, to url: URL, headers: [String: String]) async throws -> APIClientResponse {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw APIClientError.invalidPath
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (body, response) = try await session.upload(for: request, from: data)
            guard let response = response as? HTTPURLResponse else { throw APIClientError.unexpectedResponse }
            return APIClientResponse(statusCode: response.statusCode, data: body,
                                     requestID: response.value(forHTTPHeaderField: "X-Request-Id"))
        } catch let error as APIClientError {
            throw error
        } catch is CancellationError {
            throw APIClientError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw APIClientError.cancelled }
            throw APIClientError.transport(error.code)
        } catch {
            throw APIClientError.transport(.unknown)
        }
    }
}

enum MediaUploadFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case forbidden
    case invalidInput
    case mediaUnavailable
    case uploadPending
    case uploadExpired
    case uploadURLExpired
    case uploadRejected(statusCode: Int)
    case profilePhotoNotFound
    case invalidResponse
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .forbidden:
            return "이 미디어에 접근할 수 없어요. 계정과 게시글 권한을 확인해 주세요."
        case .invalidInput:
            return "파일 형식이나 크기를 확인해 주세요."
        case .mediaUnavailable:
            return "미디어 서버를 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .uploadPending:
            return "파일 전송을 확인하고 있어요. 잠시 후 다시 시도해 주세요."
        case .uploadExpired, .uploadURLExpired:
            return "업로드 주소가 만료됐어요. 새 주소를 받아 다시 시도해 주세요."
        case .uploadRejected:
            return "파일을 전송하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요."
        case .profilePhotoNotFound:
            return "등록된 프로필 사진을 찾을 수 없어요."
        case .invalidResponse:
            return "서버 응답을 확인하지 못했어요. 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "전송이 취소됐어요. 다시 시도할 수 있어요."
        }
    }

    var canManuallyRetry: Bool {
        switch self {
        case .mediaUnavailable, .uploadPending, .uploadExpired, .uploadURLExpired, .uploadRejected,
             .invalidResponse, .transport:
            true
        case .accessTokenUnavailable, .unauthenticated, .forbidden, .invalidInput,
             .profilePhotoNotFound, .cancelled:
            false
        }
    }
}

enum MediaUploadPolicy {
    static let bytesPerMegabyte: Int64 = 1_000_000
    static let profileSourceMaximumBytes: Int64 = 20 * bytesPerMegabyte
    static let profileUploadMaximumBytes: Int64 = 2 * bytesPerMegabyte
    static let profileMaximumEdgePixels = 1_024
    static let postPhotoSourceMaximumBytes: Int64 = 20 * bytesPerMegabyte
    static let postPhotoUploadMaximumBytes: Int64 = 5 * bytesPerMegabyte
    static let postPhotoMaximumLongEdgePixels = 8_192
    static let postPhotoMaximumPixels: Int64 = 40_000_000
    static let postVideoSourceMaximumBytes: Int64 = 50 * bytesPerMegabyte
    static let postVideoUploadMaximumBytes: Int64 = 20 * bytesPerMegabyte
    static let postVideoMaximumDurationMilliseconds: Int64 = 15_000
    static let postVideoMaximumLongEdgePixels = 1_920
    static let postVideoMaximumShortEdgePixels = 1_080
    static let postMaximumItems = 10
    static let postBatchMaximumBytes: Int64 = 100 * bytesPerMegabyte

    static func validate(_ files: [MediaUploadFile], purpose: MediaUploadPurpose) throws {
        guard !files.isEmpty else { throw MediaUploadFailure.invalidInput }
        if purpose == .profilePhoto {
            guard files.count == 1, files[0].kind == .photo else { throw MediaUploadFailure.invalidInput }
        } else if files.count > postMaximumItems {
            throw MediaUploadFailure.invalidInput
        }

        var totalBytes: Int64 = 0
        for file in files {
            guard let byteCount = Int64(exactly: file.data.count), byteCount > 0,
                  isAllowed(file, purpose: purpose), byteCount <= maximumUploadBytes(for: file.kind, purpose: purpose),
                  signatureMatches(file) else {
                throw MediaUploadFailure.invalidInput
            }
            let (sum, overflow) = totalBytes.addingReportingOverflow(byteCount)
            guard !overflow else { throw MediaUploadFailure.invalidInput }
            totalBytes = sum
        }
        if purpose == .postAttachment && totalBytes > postBatchMaximumBytes {
            throw MediaUploadFailure.invalidInput
        }
    }

    static func isAllowed(_ file: MediaUploadFile, purpose: MediaUploadPurpose) -> Bool {
        switch (purpose, file.kind, file.contentType) {
        case (.profilePhoto, .photo, "image/jpeg"),
             (.postAttachment, .photo, "image/jpeg"),
             (.postAttachment, .photo, "image/png"),
             (.postAttachment, .video, "video/mp4"):
            true
        default:
            false
        }
    }

    static func maximumUploadBytes(for kind: MediaUploadKind, purpose: MediaUploadPurpose) -> Int64 {
        switch purpose {
        case .profilePhoto: profileUploadMaximumBytes
        case .postAttachment: kind == .photo ? postPhotoUploadMaximumBytes : postVideoUploadMaximumBytes
        }
    }

    static func signatureMatches(_ file: MediaUploadFile) -> Bool {
        switch file.contentType {
        case "image/jpeg": file.data.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/png": file.data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "video/mp4": file.data.count >= 12 && file.data[4..<8].elementsEqual([0x66, 0x74, 0x79, 0x70])
        default: false
        }
    }
}

struct MediaUploadClient: Sendable {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding
    private let signedURLSender: any MediaSignedURLSending
    private let now: @Sendable () -> Date

    init(
        apiClient: any APIResponseSending,
        tokenProvider: any AccessTokenProviding,
        signedURLSender: any MediaSignedURLSending = URLSessionMediaSignedURLSender(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.signedURLSender = signedURLSender
        self.now = now
    }

    func scoped(to tokenProvider: any AccessTokenProviding) -> MediaUploadClient {
        MediaUploadClient(apiClient: apiClient, tokenProvider: tokenProvider,
                          signedURLSender: signedURLSender, now: now)
    }

    /// Requests a fresh batch after an expired signed URL or expired 24-hour batch. The
    /// number of automatic restarts is deliberately bounded to one.
    func upload(_ files: [MediaUploadFile], purpose: MediaUploadPurpose) async throws -> MediaReadyBatch {
        try MediaUploadPolicy.validate(files, purpose: purpose)
        for attempt in 0..<2 {
            let ticket = try await requestTicket(files, purpose: purpose)
            var expired = false
            for item in ticket.items {
                guard now() < item.expiresAt else { expired = true; break }
                let response: APIClientResponse
                do {
                    response = try await signedURLSender.put(
                        data: files[item.position].data,
                        to: item.uploadURL,
                        headers: [
                            "Content-Type": item.contentType,
                            "Content-Length": String(files[item.position].data.count)
                        ]
                    )
                } catch let failure as MediaUploadFailure {
                    throw failure
                } catch let error as APIClientError {
                    if case .cancelled = error { throw MediaUploadFailure.cancelled }
                    if now() >= item.expiresAt { expired = true; break }
                    throw Self.mapTransportFailure(error)
                } catch is CancellationError {
                    throw MediaUploadFailure.cancelled
                } catch {
                    throw MediaUploadFailure.transport(.unknown)
                }
                guard (200..<300).contains(response.statusCode) else {
                    if (response.statusCode == 401 || response.statusCode == 403), now() >= item.expiresAt {
                        expired = true
                        break
                    }
                    throw MediaUploadFailure.uploadRejected(statusCode: response.statusCode)
                }
            }
            if expired {
                if attempt == 0 { continue }
                throw MediaUploadFailure.uploadURLExpired
            }

            do {
                return try await complete(batchID: ticket.batchID, purpose: purpose, ticket: ticket, files: files)
            } catch MediaUploadFailure.uploadExpired where attempt == 0 {
                continue
            }
        }
        throw MediaUploadFailure.uploadURLExpired
    }

    func fetchOwnProfilePhoto() async throws -> Data {
        let response = try await sendAuthorized(path: "members/me/profile-photo", method: "GET", body: nil,
                                                contentType: nil, accepts: "image/jpeg")
        guard response.statusCode == 200 else {
            if response.statusCode == 404 { throw MediaUploadFailure.profilePhotoNotFound }
            throw Self.mapResponseFailure(response)
        }
        guard Int64(response.data.count) <= MediaUploadPolicy.profileUploadMaximumBytes,
              response.data.starts(with: [0xFF, 0xD8, 0xFF]) else {
            throw MediaUploadFailure.invalidResponse
        }
        return response.data
    }

    private func requestTicket(_ files: [MediaUploadFile], purpose: MediaUploadPurpose) async throws -> UploadTicket {
        let body: Data
        do {
            body = try JSONEncoder.sorted.encode(UploadBatchRequest(
                purpose: purpose,
                items: files.map { UploadBatchItemRequest(kind: $0.kind, contentType: $0.contentType,
                                                          uploadBytes: Int64($0.data.count)) }
            ))
        } catch {
            throw MediaUploadFailure.invalidInput
        }
        let response = try await sendAuthorized(path: "media/upload-batches", method: "POST", body: body,
                                                contentType: "application/json")
        guard response.statusCode == 201 else { throw Self.mapResponseFailure(response) }
        do {
            let dto = try JSONDecoder().decode(UploadTicketResponse.self, from: response.data)
            guard let batchID = UUID(uuidString: dto.batchId), dto.items.count == files.count,
                  !dto.items.isEmpty else { throw MediaUploadFailure.invalidResponse }
            var seen: Set<String> = []
            let items = try dto.items.enumerated().map { expectedPosition, dto -> TicketItem in
                guard let assetID = UUID(uuidString: dto.assetId), seen.insert(assetID.uuidString.lowercased()).inserted,
                      dto.position == expectedPosition, dto.method == "PUT",
                      let url = URL(string: dto.uploadUrl), url.scheme?.lowercased() == "https",
                      url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil,
                      let expiresAt = Self.parseTimestamp(dto.expiresAt),
                      dto.contentType == files[expectedPosition].contentType,
                      dto.maxUploadBytes == files[expectedPosition].data.count else {
                    throw MediaUploadFailure.invalidResponse
                }
                return TicketItem(assetID: assetID.uuidString.lowercased(), uploadURL: url,
                                  expiresAt: expiresAt, contentType: dto.contentType,
                                  maxUploadBytes: dto.maxUploadBytes, position: dto.position)
            }
            return UploadTicket(batchID: batchID.uuidString.lowercased(), items: items)
        } catch let failure as MediaUploadFailure {
            throw failure
        } catch {
            throw MediaUploadFailure.invalidResponse
        }
    }

    private func complete(batchID: String, purpose: MediaUploadPurpose, ticket: UploadTicket,
                          files: [MediaUploadFile]) async throws -> MediaReadyBatch {
        let response = try await sendAuthorized(path: "media/upload-batches/\(batchID)/complete", method: "POST",
                                                body: nil, contentType: nil)
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response) }
        do {
            let dto = try JSONDecoder().decode(ReadyBatchResponse.self, from: response.data)
            guard dto.batchId.lowercased() == batchID, dto.purpose == purpose,
                  dto.items.count == files.count, dto.totalBytes >= 0 else {
                throw MediaUploadFailure.invalidResponse
            }
            let ordered = dto.items.sorted { $0.position < $1.position }
            guard ordered.enumerated().allSatisfy({ index, item in
                item.assetId.lowercased() == ticket.items[index].assetID
                    && item.position == index
                    && item.kind == files[index].kind
                    && item.contentType == files[index].contentType
                    && item.bytes > 0
                    && item.bytes <= Int64(files[index].data.count)
                    && item.widthPixels > 0 && item.heightPixels > 0
                    && (item.kind != .video || item.durationMilliseconds > 0)
            }) else { throw MediaUploadFailure.invalidResponse }
            let calculatedTotal = ordered.reduce(Int64(0)) { $0 + $1.bytes }
            guard calculatedTotal == dto.totalBytes else { throw MediaUploadFailure.invalidResponse }
            return MediaReadyBatch(
                batchID: batchID,
                purpose: purpose,
                items: ordered.map {
                    MediaReadyItem(assetID: $0.assetId.lowercased(), kind: $0.kind,
                                   contentType: $0.contentType, bytes: $0.bytes,
                                   widthPixels: $0.widthPixels, heightPixels: $0.heightPixels,
                                   durationMilliseconds: $0.durationMilliseconds, position: $0.position)
                },
                totalBytes: dto.totalBytes
            )
        } catch let failure as MediaUploadFailure {
            throw failure
        } catch {
            throw MediaUploadFailure.invalidResponse
        }
    }

    private func sendAuthorized(path: String, method: String, body: Data?, contentType: String?,
                                accepts: String = "application/json") async throws -> APIClientResponse {
        let token: String?
        do {
            token = try await tokenProvider.accessToken()
        } catch {
            throw MediaUploadFailure.accessTokenUnavailable
        }
        guard let token, !token.isEmpty,
              token.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw MediaUploadFailure.accessTokenUnavailable
        }
        var headers = ["Authorization": "Bearer \(token)", "Accept": accepts, "Cache-Control": "no-store"]
        if let contentType { headers["Content-Type"] = contentType }
        do {
            return try await apiClient.sendResponse(path: path, method: method, body: body,
                                                   headers: headers, queryItems: [])
        } catch is CancellationError {
            throw MediaUploadFailure.cancelled
        } catch let error as APIClientError {
            throw Self.mapTransportFailure(error)
        } catch {
            throw MediaUploadFailure.transport(.unknown)
        }
    }

    private static func mapResponseFailure(_ response: APIClientResponse) -> MediaUploadFailure {
        let code = (try? JSONDecoder().decode(APIProblem.self, from: response.data).code) ?? nil
        return switch (response.statusCode, code) {
        case (401, _), (_, "UNAUTHENTICATED"): .unauthenticated
        case (403, _): .forbidden
        case (_, "MEDIA_UPLOAD_PENDING"): .uploadPending
        case (410, _), (_, "MEDIA_UPLOAD_EXPIRED"): .uploadExpired
        case (422, _), (_, "MEDIA_UPLOAD_INVALID"), (_, "VALIDATION_FAILED"): .invalidInput
        case (503, _), (_, "MEDIA_UNAVAILABLE"): .mediaUnavailable
        default: .uploadRejected(statusCode: response.statusCode)
        }
    }

    private static func mapTransportFailure(_ error: APIClientError) -> MediaUploadFailure {
        switch error {
        case .cancelled: .cancelled
        case .transport(let code): .transport(code)
        default: .invalidResponse
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: value)
    }

    private struct UploadBatchRequest: Encodable {
        let purpose: MediaUploadPurpose
        let items: [UploadBatchItemRequest]
    }

    private struct UploadBatchItemRequest: Encodable {
        let kind: MediaUploadKind
        let contentType: String
        let uploadBytes: Int64
    }

    private struct UploadTicketResponse: Decodable {
        let batchId: String
        let items: [TicketItemResponse]
    }

    private struct TicketItemResponse: Decodable {
        let assetId: String
        let method: String
        let uploadUrl: String
        let expiresAt: String
        let contentType: String
        let maxUploadBytes: Int
        let position: Int
    }

    private struct ReadyBatchResponse: Decodable {
        let batchId: String
        let purpose: MediaUploadPurpose
        let items: [ReadyItemResponse]
        let totalBytes: Int64
    }

    private struct ReadyItemResponse: Decodable {
        let assetId: String
        let kind: MediaUploadKind
        let contentType: String
        let bytes: Int64
        let widthPixels: Int
        let heightPixels: Int
        let durationMilliseconds: Int64
        let position: Int
    }

    private struct APIProblem: Decodable {
        let code: String?
    }

    private struct TicketItem {
        let assetID: String
        let uploadURL: URL
        let expiresAt: Date
        let contentType: String
        let maxUploadBytes: Int
        let position: Int
    }

    private struct UploadTicket {
        let batchID: String
        let items: [TicketItem]
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
