import Foundation
import XCTest
@testable import MovNetworking

final class MediaUploadClientTests: XCTestCase {
    func testProfileUploadUsesTicketedPUTWithoutAPITokenAndCompletesReceipt() async throws {
        let now = Date(timeIntervalSince1970: 1_893_455_999)
        let file = MediaUploadFile(contentType: "image/jpeg", data: Self.jpeg)
        let batchID = "B74F045C-0EC2-4EB0-9C68-621C9F4D4E51"
        let assetID = "1DC6B74F-7C47-424B-B0B5-934165AEFE16"
        let api = RecordingMediaAPI(steps: [
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: Self.ticket(
                batchID: batchID, assetIDs: [assetID], contentTypes: ["image/jpeg"], byteCounts: [Self.jpeg.count],
                expiresAt: "2030-01-01T00:00:00Z"
            ))),
            .init(path: "media/upload-batches/\(batchID.lowercased())/complete", method: "POST",
                  response: .init(statusCode: 200, data: Self.readyBatch(batchID: batchID, assetID: assetID,
                                                                         purpose: "PROFILE_PHOTO", contentType: "image/jpeg",
                                                                         bytes: Self.jpeg.count)))
        ])
        let signed = RecordingSignedURLSender(responses: [.init(statusCode: 204, data: Data())])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("test-access-token"),
                                       signedURLSender: signed, now: { now })

        let ready = try await client.upload([file], purpose: .profilePhoto)

        XCTAssertEqual(ready.batchID, batchID.lowercased())
        XCTAssertEqual(ready.items.map(\.assetID), [assetID.lowercased()])
        XCTAssertEqual(ready.totalBytes, Int64(Self.jpeg.count))
        let apiRequests = await api.recordedRequests()
        XCTAssertEqual(apiRequests.map(\.path), ["media/upload-batches", "media/upload-batches/\(batchID.lowercased())/complete"])
        XCTAssertEqual(apiRequests[0].headers["Authorization"], "Bearer test-access-token")
        let body = try XCTUnwrap(apiRequests[0].body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["purpose"] as? String, "PROFILE_PHOTO")
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["kind"] as? String, "PHOTO")
        XCTAssertEqual(items.first?["contentType"] as? String, "image/jpeg")
        XCTAssertEqual(items.first?["uploadBytes"] as? Int, Self.jpeg.count)

        let puts = await signed.recordedRequests()
        XCTAssertEqual(puts.count, 1)
        XCTAssertEqual(puts[0].url.host, "storage.example.test")
        XCTAssertEqual(puts[0].headers["Content-Type"], "image/jpeg")
        XCTAssertEqual(puts[0].headers["Content-Length"], String(Self.jpeg.count))
        XCTAssertNil(puts[0].headers["Authorization"])
    }

    func testPolicyRejectsWrongSignatureAndOversizedProfileBeforeRequestingBatch() async {
        let api = RecordingMediaAPI(steps: [])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("token"),
                                       signedURLSender: RecordingSignedURLSender(responses: []))
        do {
            _ = try await client.upload([MediaUploadFile(contentType: "image/jpeg", data: Data("not jpeg".utf8))],
                                        purpose: .profilePhoto)
            XCTFail("mismatched bytes must be rejected")
        } catch let failure as MediaUploadFailure {
            XCTAssertEqual(failure, .invalidInput)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        do {
            let oversized = Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0, count: Int(MediaUploadPolicy.profileUploadMaximumBytes))
            _ = try await client.upload([MediaUploadFile(contentType: "image/jpeg", data: oversized)], purpose: .profilePhoto)
            XCTFail("oversized profile photo must be rejected")
        } catch let failure as MediaUploadFailure {
            XCTAssertEqual(failure, .invalidInput)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let requests = await api.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testExpiredSignedURLRequestsFreshBatchAndDoesNotReuseTheOldURL() async throws {
        let now = Date(timeIntervalSince1970: 1_893_455_999)
        let file = MediaUploadFile(contentType: "image/png", data: Self.png)
        let firstBatch = "B74F045C-0EC2-4EB0-9C68-621C9F4D4E51"
        let secondBatch = "1DC6B74F-7C47-424B-B0B5-934165AEFE16"
        let assetID = "2110CFF7-6B6B-4C8F-9C48-1F19CE3989BC"
        let api = RecordingMediaAPI(steps: [
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: Self.ticket(
                batchID: firstBatch, assetIDs: [assetID], contentTypes: ["image/png"], byteCounts: [Self.png.count],
                expiresAt: "2029-01-01T00:00:00Z"
            ))),
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: Self.ticket(
                batchID: secondBatch, assetIDs: [assetID], contentTypes: ["image/png"], byteCounts: [Self.png.count],
                expiresAt: "2030-01-01T00:00:00Z"
            ))),
            .init(path: "media/upload-batches/\(secondBatch.lowercased())/complete", method: "POST",
                  response: .init(statusCode: 200, data: Self.readyBatch(batchID: secondBatch, assetID: assetID,
                                                                         purpose: "POST_ATTACHMENT", contentType: "image/png",
                                                                         bytes: Self.png.count)))
        ])
        let signed = RecordingSignedURLSender(responses: [.init(statusCode: 204, data: Data())])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("token"),
                                       signedURLSender: signed, now: { now })

        _ = try await client.upload([file], purpose: .postAttachment)

        let apiRequests = await api.recordedRequests()
        XCTAssertEqual(apiRequests.filter { $0.path == "media/upload-batches" }.count, 2)
        XCTAssertEqual(apiRequests.last?.path, "media/upload-batches/\(secondBatch.lowercased())/complete")
        let signedRequests = await signed.recordedRequests()
        XCTAssertEqual(signedRequests.count, 1)
    }

    func testExpiredTwentyFourHourBatchIsRecreatedOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_893_455_999)
        let batchOne = "B74F045C-0EC2-4EB0-9C68-621C9F4D4E51"
        let batchTwo = "1DC6B74F-7C47-424B-B0B5-934165AEFE16"
        let assetID = "2110CFF7-6B6B-4C8F-9C48-1F19CE3989BC"
        let file = MediaUploadFile(contentType: "image/jpeg", data: Self.jpeg)
        let api = RecordingMediaAPI(steps: [
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: Self.ticket(
                batchID: batchOne, assetIDs: [assetID], contentTypes: ["image/jpeg"], byteCounts: [Self.jpeg.count],
                expiresAt: "2030-01-01T00:00:00Z"
            ))),
            .init(path: "media/upload-batches/\(batchOne.lowercased())/complete", method: "POST",
                  response: .init(statusCode: 410, data: Self.problem("MEDIA_UPLOAD_EXPIRED"))),
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: Self.ticket(
                batchID: batchTwo, assetIDs: [assetID], contentTypes: ["image/jpeg"], byteCounts: [Self.jpeg.count],
                expiresAt: "2030-01-01T00:00:00Z"
            ))),
            .init(path: "media/upload-batches/\(batchTwo.lowercased())/complete", method: "POST",
                  response: .init(statusCode: 200, data: Self.readyBatch(batchID: batchTwo, assetID: assetID,
                                                                         purpose: "POST_ATTACHMENT", contentType: "image/jpeg",
                                                                         bytes: Self.jpeg.count)))
        ])
        let signed = RecordingSignedURLSender(responses: [
            .init(statusCode: 204, data: Data()), .init(statusCode: 204, data: Data())
        ])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("token"),
                                       signedURLSender: signed, now: { now })

        let ready = try await client.upload([file], purpose: .postAttachment)

        XCTAssertEqual(ready.batchID, batchTwo.lowercased())
        let signedRequests = await signed.recordedRequests()
        XCTAssertEqual(signedRequests.count, 2)
    }

    func testCompletePendingAndMediaUnavailableMapToRetryableFailures() async throws {
        let batch = "B74F045C-0EC2-4EB0-9C68-621C9F4D4E51"
        let asset = "1DC6B74F-7C47-424B-B0B5-934165AEFE16"
        let ticket = Self.ticket(batchID: batch, assetIDs: [asset], contentTypes: ["image/jpeg"],
                                 byteCounts: [Self.jpeg.count], expiresAt: "2030-01-01T00:00:00Z")
        let api = RecordingMediaAPI(steps: [
            .init(path: "media/upload-batches", method: "POST", response: .init(statusCode: 201, data: ticket)),
            .init(path: "media/upload-batches/\(batch.lowercased())/complete", method: "POST",
                  response: .init(statusCode: 409, data: Self.problem("MEDIA_UPLOAD_PENDING")))
        ])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("token"),
                                       signedURLSender: RecordingSignedURLSender(responses: [.init(statusCode: 204, data: Data())]),
                                       now: { Date(timeIntervalSince1970: 1_893_455_999) })
        do {
            _ = try await client.upload([MediaUploadFile(contentType: "image/jpeg", data: Self.jpeg)], purpose: .postAttachment)
            XCTFail("pending should be surfaced for a user retry")
        } catch let failure as MediaUploadFailure {
            XCTAssertEqual(failure, .uploadPending)
            XCTAssertTrue(failure.canManuallyRetry)
        }

        let unavailable = MediaUploadClient(apiClient: RecordingMediaAPI(steps: [
            .init(path: "media/upload-batches", method: "POST",
                  response: .init(statusCode: 503, data: Self.problem("MEDIA_UNAVAILABLE")))
        ]), tokenProvider: StaticTokenProvider("token"), signedURLSender: RecordingSignedURLSender(responses: []))
        do {
            _ = try await unavailable.upload([MediaUploadFile(contentType: "image/jpeg", data: Self.jpeg)], purpose: .postAttachment)
            XCTFail("disabled backend adapter must fail closed")
        } catch let failure as MediaUploadFailure {
            XCTAssertEqual(failure, .mediaUnavailable)
            XCTAssertTrue(failure.canManuallyRetry)
        }
    }

    func testOwnProfilePhotoReadRequiresJPEGBytes() async throws {
        let api = RecordingMediaAPI(steps: [
            .init(path: "members/me/profile-photo", method: "GET", response: .init(statusCode: 200, data: Self.jpeg))
        ])
        let client = MediaUploadClient(apiClient: api, tokenProvider: StaticTokenProvider("token"),
                                       signedURLSender: RecordingSignedURLSender(responses: []))
        let profilePhoto = try await client.fetchOwnProfilePhoto()
        XCTAssertEqual(profilePhoto, Self.jpeg)
        let requests = await api.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["Accept"], "image/jpeg")
        XCTAssertEqual(request.headers["Cache-Control"], "no-store")
    }

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

    private static func ticket(batchID: String, assetIDs: [String], contentTypes: [String],
                               byteCounts: [Int], expiresAt: String) -> Data {
        let items: [[String: Any]] = assetIDs.enumerated().map { index, assetID in
            ["assetId": assetID, "method": "PUT", "uploadUrl": "https://storage.example.test/upload?sig=mock\(index)",
             "expiresAt": expiresAt, "contentType": contentTypes[index], "maxUploadBytes": byteCounts[index],
             "position": index]
        }
        return try! JSONSerialization.data(withJSONObject: ["batchId": batchID, "items": items])
    }

    private static func readyBatch(batchID: String, assetID: String, purpose: String,
                                   contentType: String, bytes: Int) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "batchId": batchID, "purpose": purpose,
            "items": [["assetId": assetID, "kind": "PHOTO", "contentType": contentType,
                       "bytes": bytes, "widthPixels": 1, "heightPixels": 1,
                       "durationMilliseconds": 0, "position": 0]],
            "totalBytes": bytes
        ])
    }

    private static func problem(_ code: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["code": code, "requestId": "fake-request"])
    }
}

private struct StaticTokenProvider: AccessTokenProviding {
    let token: String?
    init(_ token: String?) { self.token = token }
    func accessToken() async throws -> String? { token }
}

private actor RecordingMediaAPI: APIResponseSending {
    struct Step: Sendable {
        let path: String
        let method: String
        let response: APIClientResponse
    }
    struct Request: Sendable {
        let path: String
        let method: String
        let body: Data?
        let headers: [String: String]
    }
    private var steps: [Step]
    private var requests: [Request] = []

    init(steps: [Step]) { self.steps = steps }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String],
                      queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        requests.append(Request(path: path, method: method, body: body, headers: headers))
        guard !steps.isEmpty else { throw APIClientError.unexpectedResponse }
        let step = steps.removeFirst()
        guard step.path == path, step.method == method, queryItems.isEmpty else {
            throw APIClientError.unexpectedResponse
        }
        return step.response
    }

    func recordedRequests() -> [Request] { requests }
}

private actor RecordingSignedURLSender: MediaSignedURLSending {
    struct Request: Sendable {
        let data: Data
        let url: URL
        let headers: [String: String]
    }
    private var responses: [APIClientResponse]
    private var requests: [Request] = []

    init(responses: [APIClientResponse]) { self.responses = responses }

    func put(data: Data, to url: URL, headers: [String: String]) async throws -> APIClientResponse {
        requests.append(Request(data: data, url: url, headers: headers))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [Request] { requests }
}
