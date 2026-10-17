import Foundation

enum CommunityPostBoardKey: String, Codable, Equatable, Sendable {
    case free
    case anonymous
    case runningVerification = "running_verification"
}

struct CommunityPostAttachment: Equatable, Sendable {
    let assetID: String
    let kind: MediaUploadKind
    let contentType: String
    let bytes: Int64
    let widthPixels: Int
    let heightPixels: Int
    let position: Int
}

struct CommunityPostSnapshot: Equatable, Sendable {
    let postID: String
    let boardKey: CommunityPostBoardKey
    let title: String
    let content: String
    let attachmentVersion: Int64
    let attachments: [CommunityPostAttachment]

    var assetIDs: [String] { attachments.map(\.assetID) }
}

struct CommunityRunShareCardData: Equatable, Sendable {
    let templateVersion: Int
    let runDate: String
    let distanceMeters: Int
    let runningSeconds: Int
    let paceSecondsPerKm: Int
    let designSnapshot: Data?
}

enum CommunityMediaFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case unauthenticated
    case forbidden
    case invalidPostDraft
    case unsupportedVideoUpload
    case mediaUnavailable
    case uploadPending
    case uploadExpired
    case postNotFound
    case versionConflict
    case postCreationResultUnknown
    case attachmentResultUnknown
    case attachmentUnavailable
    case invalidResponse
    case serverFailure(statusCode: Int)
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .forbidden:
            return "이 게시글이나 첨부를 볼 수 없어요."
        case .invalidPostDraft:
            return "게시판에 사용할 제목과 내용을 입력해 주세요."
        case .unsupportedVideoUpload:
            return "서버 동영상 검사가 준비되지 않아 영상 게시를 사용할 수 없어요. 사진만 남겨 다시 시도해 주세요."
        case .mediaUnavailable:
            return "미디어 서버를 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .uploadPending:
            return "파일 전송을 확인하지 못했어요. 다시 시도해 주세요."
        case .uploadExpired:
            return "업로드가 만료됐어요. 파일을 다시 선택해 주세요."
        case .postNotFound:
            return "게시글을 찾을 수 없거나 접근할 수 없어요."
        case .versionConflict:
            return "게시글 첨부가 바뀌었어요. 최신 상태를 확인한 뒤 다시 시도해 주세요."
        case .postCreationResultUnknown:
            return "게시글 생성 응답을 받지 못해 완료 여부를 확인할 수 없어요. 커뮤니티에서 게시글을 확인한 뒤 다시 시도해 주세요."
        case .attachmentResultUnknown:
            return "첨부 결과를 확인하지 못했어요. 게시글을 새로 읽어 확인한 뒤 다시 시도해 주세요."
        case .attachmentUnavailable:
            return "게시글 첨부를 불러오지 못했어요. 다시 시도해 주세요."
        case .invalidResponse:
            return "서버 응답을 확인하지 못했어요. 다시 시도해 주세요."
        case .serverFailure:
            return "게시글을 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요. 다시 시도할 수 있어요."
        }
    }

    var canManuallyRetry: Bool {
        switch self {
        case .mediaUnavailable, .uploadPending, .uploadExpired, .versionConflict,
             .attachmentResultUnknown, .attachmentUnavailable, .serverFailure, .transport:
            true
        case .accessTokenUnavailable, .unauthenticated, .forbidden, .invalidPostDraft,
             .unsupportedVideoUpload, .postNotFound, .postCreationResultUnknown, .invalidResponse, .cancelled:
            false
        }
    }
}

struct CommunityMediaClient: Sendable {
    private let apiClient: any APIResponseSending
    private let tokenProvider: any AccessTokenProviding

    init(apiClient: any APIResponseSending, tokenProvider: any AccessTokenProviding) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func scoped(to tokenProvider: any AccessTokenProviding) -> CommunityMediaClient {
        CommunityMediaClient(apiClient: apiClient, tokenProvider: tokenProvider)
    }

    /// Post creation has no idempotency key in the current API contract. A transport
    /// failure is surfaced as an unknown outcome and must not be blindly replayed.
    func createPost(board: CommunityPostBoardKey, title: String, content: String,
                    runID: String? = nil) async throws -> CommunityPostSnapshot {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty,
              normalizedTitle.count <= 60, normalizedContent.count <= 2_000 else {
            throw CommunityMediaFailure.invalidPostDraft
        }
        let path: String
        let body: Data
        do {
            switch board {
            case .free:
                path = "community/boards/free/posts"
                body = try JSONEncoder.sortedCommunity.encode(PostRequest(title: normalizedTitle,
                                                                            content: normalizedContent))
            case .anonymous:
                path = "community/boards/anonymous/posts"
                body = try JSONEncoder.sortedCommunity.encode(PostRequest(title: normalizedTitle,
                                                                            content: normalizedContent))
            case .runningVerification:
                guard let runID, Self.isCanonicalPostID(runID) else { throw CommunityMediaFailure.invalidPostDraft }
                path = "community/boards/running-verification/posts"
                body = try JSONEncoder.sortedCommunity.encode(RunVerificationPostRequest(
                    runId: runID, title: normalizedTitle, content: normalizedContent
                ))
            }
        } catch let failure as CommunityMediaFailure {
            throw failure
        } catch {
            throw CommunityMediaFailure.invalidPostDraft
        }
        do {
            let response = try await sendAuthorized(path: path, method: "POST", body: body)
            // A 5xx response can be produced after the server committed the post but
            // failed while serializing or returning the response. The create routes
            // have no idempotency key, so replaying such a request could duplicate it.
            if (500..<600).contains(response.statusCode) {
                throw CommunityMediaFailure.postCreationResultUnknown
            }
            guard response.statusCode == 201 else { throw Self.mapResponseFailure(response) }
            do { return try Self.decodePost(response.data) }
            catch { throw CommunityMediaFailure.postCreationResultUnknown }
        } catch let failure as CommunityMediaFailure {
            throw Self.mapTransportFailure(failure,postCreation:true)
        } catch {
            throw Self.mapTransportFailure(error, postCreation: true)
        }
    }

    func updatePost(postID: String, title: String, content: String) async throws -> CommunityPostSnapshot {
        guard Self.isCanonicalPostID(postID), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.trimmingCharacters(in: .whitespacesAndNewlines).count <= 60,
              content.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2_000 else {
            throw CommunityMediaFailure.invalidPostDraft
        }
        let body = try JSONEncoder.sortedCommunity.encode(PostRequest(title: title, content: content))
        let response: APIClientResponse
        do {
            response = try await sendAuthorized(path: "community/posts/\(postID)", method: "PATCH", body: body)
        } catch {
            throw Self.mapTransportFailure(error, postCreation: false)
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response) }
        return try Self.decodePost(response.data)
    }

    func fetchPost(postID: String) async throws -> CommunityPostSnapshot {
        guard Self.isCanonicalPostID(postID) else { throw CommunityMediaFailure.postNotFound }
        let response: APIClientResponse
        do {
            response = try await sendAuthorized(path: "community/posts/\(postID)", method: "GET", body: nil)
        } catch {
            throw Self.mapTransportFailure(error, postCreation: false)
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response) }
        return try Self.decodePost(response.data)
    }

    /// Reconciles an uncertain PUT by reading the current attachment version and list.
    /// A transport retry never replays a stale version or duplicates an attached list.
    func replaceAttachments(postID: String, expectedVersion: Int64, assetIDs: [String]) async throws -> CommunityPostSnapshot {
        guard Self.isCanonicalPostID(postID), expectedVersion >= 0,
              assetIDs.count <= MediaUploadPolicy.postMaximumItems,
              assetIDs.allSatisfy({ UUID(uuidString: $0) != nil }),
              Set(assetIDs.map { $0.lowercased() }).count == assetIDs.count else {
            throw CommunityMediaFailure.invalidPostDraft
        }
        do {
            return try await putAttachments(postID: postID, expectedVersion: expectedVersion, assetIDs: assetIDs)
        } catch let failure as CommunityMediaFailure where Self.isUncertainAttachmentMutation(failure) {
            let current: CommunityPostSnapshot
            do {
                current = try await fetchPost(postID: postID)
            } catch {
                throw CommunityMediaFailure.attachmentResultUnknown
            }
            if current.assetIDs.map({ $0.lowercased() }) == assetIDs.map({ $0.lowercased() }) {
                return current
            }
            do {
                return try await putAttachments(postID: postID, expectedVersion: current.attachmentVersion,
                                                assetIDs: assetIDs)
            } catch let retryFailure as CommunityMediaFailure {
                if Self.isUncertainAttachmentMutation(retryFailure) {
                    throw CommunityMediaFailure.attachmentResultUnknown
                }
                throw retryFailure
            }
        }
    }

    func readAttachment(postID: String, attachment: CommunityPostAttachment) async throws -> Data {
        guard Self.isCanonicalPostID(postID), UUID(uuidString: attachment.assetID) != nil,
              attachment.kind == .photo,
              attachment.contentType == "image/jpeg" || attachment.contentType == "image/png",
              attachment.bytes > 0, attachment.bytes <= MediaUploadPolicy.postPhotoUploadMaximumBytes else {
            throw CommunityMediaFailure.attachmentUnavailable
        }
        let response: APIClientResponse
        do {
            response = try await sendAuthorized(
                path: "community/posts/\(postID)/attachments/\(attachment.assetID)", method: "GET", body: nil,
                accepts: attachment.contentType
            )
        } catch {
            throw Self.mapTransportFailure(error, postCreation: false)
        }
        guard response.statusCode == 200,
              Int64(response.data.count) == attachment.bytes,
              response.data.starts(with: attachment.contentType == "image/jpeg"
                                   ? [0xFF, 0xD8, 0xFF]
                                   : [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            if response.statusCode == 503 { throw CommunityMediaFailure.mediaUnavailable }
            throw CommunityMediaFailure.attachmentUnavailable
        }
        return response.data
    }

    func fetchRunShareCardData(postID: String) async throws -> CommunityRunShareCardData {
        guard Self.isCanonicalPostID(postID) else { throw CommunityMediaFailure.postNotFound }
        let response: APIClientResponse
        do {
            response = try await sendAuthorized(path: "community/posts/\(postID)/run-share-card-data",
                                                method: "GET", body: nil)
        } catch {
            throw Self.mapTransportFailure(error, postCreation: false)
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response) }
        do {
            let dto = try JSONDecoder().decode(RunShareCardDataResponse.self, from: response.data)
            guard dto.templateVersion == 1, dto.distanceMeters >= 0,
                  dto.runningSeconds >= 0, dto.paceSecondsPerKm >= 0 else {
                throw CommunityMediaFailure.invalidResponse
            }
            let snapshot = try dto.designSnapshot.map(JSONEncoder().encode)
            return CommunityRunShareCardData(templateVersion: dto.templateVersion, runDate: dto.runDate,
                                             distanceMeters: dto.distanceMeters, runningSeconds: dto.runningSeconds,
                                             paceSecondsPerKm: dto.paceSecondsPerKm, designSnapshot: snapshot)
        } catch let failure as CommunityMediaFailure {
            throw failure
        } catch {
            throw CommunityMediaFailure.invalidResponse
        }
    }

    private func putAttachments(postID: String, expectedVersion: Int64,
                                assetIDs: [String]) async throws -> CommunityPostSnapshot {
        let body = try JSONEncoder.sortedCommunity.encode(ReplaceAttachmentsRequest(
            attachmentVersion: expectedVersion, assetIds: assetIDs
        ))
        let response: APIClientResponse
        do {
            response = try await sendAuthorized(path: "community/posts/\(postID)/attachments",
                                                method: "PUT", body: body)
        } catch {
            throw Self.mapTransportFailure(error, postCreation: false)
        }
        guard response.statusCode == 200 else { throw Self.mapResponseFailure(response) }
        do {
            let dto = try JSONDecoder().decode(AttachmentSetResponse.self, from: response.data)
            let attachments = try Self.decodeAttachments(dto.items)
            guard dto.attachmentVersion >= expectedVersion,
                  attachments.map({ $0.assetID.lowercased() }) == assetIDs.map({ $0.lowercased() }) else {
                throw CommunityMediaFailure.invalidResponse
            }
            return CommunityPostSnapshot(postID: postID, boardKey: .free, title: "", content: "",
                                         attachmentVersion: dto.attachmentVersion, attachments: attachments)
        } catch let failure as CommunityMediaFailure {
            throw failure
        } catch {
            throw CommunityMediaFailure.invalidResponse
        }
    }

    private func sendAuthorized(path: String, method: String, body: Data?, accepts: String = "application/json") async throws -> APIClientResponse {
        let token: String?
        do { token = try await tokenProvider.accessToken() }
        catch { throw CommunityMediaFailure.accessTokenUnavailable }
        guard let token, !token.isEmpty,
              token.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw CommunityMediaFailure.accessTokenUnavailable
        }
        var headers = ["Authorization": "Bearer \(token)", "Accept": accepts, "Cache-Control": "no-store"]
        if body != nil { headers["Content-Type"] = "application/json" }
        do {
            return try await apiClient.sendResponse(path: path, method: method, body: body,
                                                   headers: headers, queryItems: [])
        } catch is CancellationError {
            throw CommunityMediaFailure.cancelled
        } catch let error as APIClientError {
            switch error {
            case .cancelled: throw CommunityMediaFailure.cancelled
            case .transport(let code): throw CommunityMediaFailure.transport(code)
            default: throw CommunityMediaFailure.invalidResponse
            }
        } catch {
            throw CommunityMediaFailure.transport(.unknown)
        }
    }

    private static func decodePost(_ data: Data) throws -> CommunityPostSnapshot {
        do {
            let dto = try JSONDecoder().decode(PostResponse.self, from: data)
            guard isCanonicalPostID(dto.postId), let version = dto.attachmentVersion, version >= 0,
                  let board = CommunityPostBoardKey(rawValue: dto.boardKey) else {
                throw CommunityMediaFailure.invalidResponse
            }
            let attachments = try decodeAttachments(dto.attachments ?? [])
            return CommunityPostSnapshot(postID: dto.postId, boardKey: board, title: dto.title,
                                         content: dto.content, attachmentVersion: version, attachments: attachments)
        } catch let failure as CommunityMediaFailure {
            throw failure
        } catch {
            throw CommunityMediaFailure.invalidResponse
        }
    }

    private static func decodeAttachments(_ rows: [PostAttachmentResponse]) throws -> [CommunityPostAttachment] {
        guard rows.count <= MediaUploadPolicy.postMaximumItems else { throw CommunityMediaFailure.invalidResponse }
        let ordered = rows.sorted { $0.position < $1.position }
        var total: Int64 = 0
        let result = try ordered.enumerated().map { index, row -> CommunityPostAttachment in
            guard UUID(uuidString: row.assetId) != nil, row.position == index, row.kind == "PHOTO",
                  row.contentType == "image/jpeg" || row.contentType == "image/png",
                  row.bytes > 0, row.bytes <= MediaUploadPolicy.postPhotoUploadMaximumBytes,
                  row.widthPixels > 0, row.heightPixels > 0,
                  max(row.widthPixels, row.heightPixels) <= MediaUploadPolicy.postPhotoMaximumLongEdgePixels,
                  Int64(row.widthPixels) * Int64(row.heightPixels) <= MediaUploadPolicy.postPhotoMaximumPixels else {
                throw CommunityMediaFailure.invalidResponse
            }
            let (sum, overflow) = total.addingReportingOverflow(row.bytes)
            guard !overflow, sum <= MediaUploadPolicy.postBatchMaximumBytes else {
                throw CommunityMediaFailure.invalidResponse
            }
            total = sum
            return CommunityPostAttachment(assetID: row.assetId.lowercased(), kind: .photo,
                                           contentType: row.contentType, bytes: row.bytes,
                                           widthPixels: row.widthPixels, heightPixels: row.heightPixels,
                                           position: row.position)
        }
        return result
    }

    private static func mapResponseFailure(_ response: APIClientResponse) -> CommunityMediaFailure {
        let code = (try? JSONDecoder().decode(APIProblem.self, from: response.data).code) ?? nil
        return switch (response.statusCode, code) {
        case (401, _), (_, "UNAUTHENTICATED"): .unauthenticated
        case (403, _): .forbidden
        case (404, _): .postNotFound
        case (409, "VERSION_CONFLICT"): .versionConflict
        case (_, "MEDIA_UPLOAD_PENDING"): .uploadPending
        case (410, _), (_, "MEDIA_UPLOAD_EXPIRED"): .uploadExpired
        case (422, _), (_, "MEDIA_UPLOAD_INVALID"), (_, "VALIDATION_FAILED"): .invalidPostDraft
        case (503, _), (_, "MEDIA_UNAVAILABLE"), (_, "COMMUNITY_UNAVAILABLE"): .mediaUnavailable
        default: .serverFailure(statusCode: response.statusCode)
        }
    }

    private static func mapTransportFailure(_ error: Error, postCreation: Bool) -> CommunityMediaFailure {
        if let failure = error as? CommunityMediaFailure {
            if postCreation && failure == .cancelled { return .postCreationResultUnknown }
            if postCreation, isTransport(failure) { return .postCreationResultUnknown }
            return failure
        }
        if let apiError = error as? APIClientError {
            switch apiError {
            case .cancelled: return .cancelled
            case .transport(let code): return postCreation ? .postCreationResultUnknown : .transport(code)
            default: return .invalidResponse
            }
        }
        if error is CancellationError { return .cancelled }
        return postCreation ? .postCreationResultUnknown : .transport(.unknown)
    }

    private static func isTransport(_ failure: CommunityMediaFailure) -> Bool {
        if case .transport = failure { return true }
        return false
    }

    private static func isUncertainAttachmentMutation(_ failure:CommunityMediaFailure)->Bool {
        switch failure {
        case .versionConflict,.attachmentResultUnknown,.invalidResponse,.transport:
            true
        case .serverFailure(let statusCode):statusCode>=500
        default:false
        }
    }

    private static func isCanonicalPostID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let parsed = Int64(value), parsed > 0 else { return false }
        return String(parsed) == value
    }

    private struct PostRequest: Encodable {
        let title: String
        let content: String
    }

    private struct RunVerificationPostRequest: Encodable {
        let runId: String
        let title: String
        let content: String
    }

    private struct ReplaceAttachmentsRequest: Encodable {
        let attachmentVersion: Int64
        let assetIds: [String]
    }

    private struct PostResponse: Decodable {
        let postId: String
        let boardKey: String
        let title: String
        let content: String
        let attachmentVersion: Int64?
        let attachments: [PostAttachmentResponse]?
    }

    private struct PostAttachmentResponse: Decodable {
        let assetId: String
        let kind: String
        let contentType: String
        let bytes: Int64
        let widthPixels: Int
        let heightPixels: Int
        let position: Int
    }

    private struct AttachmentSetResponse: Decodable {
        let attachmentVersion: Int64
        let items: [PostAttachmentResponse]
    }

    private struct RunShareCardDataResponse: Decodable {
        let templateVersion: Int
        let runDate: String
        let distanceMeters: Int
        let runningSeconds: Int
        let paceSecondsPerKm: Int
        let designSnapshot: JSONValue?
    }

    private struct APIProblem: Decodable {
        let code: String?
    }
}

private enum JSONValue: Decodable, Encodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private extension JSONEncoder {
    static var sortedCommunity: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
