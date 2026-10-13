import Foundation
import XCTest
@testable import MovNetworking

private struct CosmeticStoreSessionStub: RunUploadSessionProviding {
    let value: RunUploadSession?

    func currentSession() async throws -> RunUploadSession? { value }
}

private actor MutableCosmeticStoreSessionProvider: RunUploadSessionProviding {
    private var value: RunUploadSession?

    init(_ value: RunUploadSession?) { self.value = value }

    func currentSession() async throws -> RunUploadSession? { value }
    func set(_ value: RunUploadSession?) { self.value = value }
}

private struct RecordedCosmeticStoreRequest: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
}

private actor RecordingCosmeticStoreTransport: APIResponseSending {
    private var responses: [APIClientResponse]
    private var requests: [RecordedCosmeticStoreRequest] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses.map { APIClientResponse(statusCode: $0.0, data: $0.1, requestID: nil) }
    }

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        requests.append(RecordedCosmeticStoreRequest(path: path, method: method, body: body, headers: headers))
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func capturedRequests() -> [RecordedCosmeticStoreRequest] { requests }
}

private func makeCosmeticStoreClient(
    token: String? = "fixture-store-token",
    sessionProvider: (any RunUploadSessionProviding)? = nil,
    mockScope: String? = nil
) throws -> CosmeticStoreClient {
    let configuration = try APIClientConfiguration(
        environment: .development,
        baseURLString: "https://api-dev.example.invalid/api/v1/",
        requestTimeout: 4,
        resourceTimeout: 9
    )
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    if let mockScope {
        var headers = sessionConfiguration.httpAdditionalHeaders ?? [:]
        headers[MockURLProtocol.scopeHeader] = mockScope
        sessionConfiguration.httpAdditionalHeaders = headers
    }
    let apiClient = APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
    return CosmeticStoreClient(
        apiClient: apiClient,
        sessionProvider: sessionProvider ?? CosmeticStoreSessionStub(
            value: token.map { RunUploadSession(ownerID: "101", accessToken: $0) }
        )
    )
}

private func makeCosmeticStoreClient(
    transport: any APIResponseSending,
    sessionProvider: any RunUploadSessionProviding = CosmeticStoreSessionStub(
        value: RunUploadSession(ownerID: "101", accessToken: "fixture-store-token")
    )
) -> CosmeticStoreClient {
    CosmeticStoreClient(apiClient: transport, sessionProvider: sessionProvider)
}

private let catalogFixture = Data("""
{"items":[{"productId":"101","category":"RUN_CARD_BACKGROUND","displayName":"Blue dusk","description":"A calm blue background","pricePoints":125,"previewData":{"version":1,"assetId":"blue_dusk","accentColor":"#AABBCC"},"owned":false}]}
""".utf8)

private let productFixture = Data("""
{"productId":"101","category":"RUN_CARD_BACKGROUND","displayName":"Blue dusk","description":"A calm blue background","pricePoints":125,"previewData":{"version":1,"assetId":"blue_dusk","accentColor":"#AABBCC"},"owned":true}
""".utf8)

private let inventoryFixture = Data("""
{"items":[{"purchaseId":"9001","productId":"101","category":"RUN_CARD_BACKGROUND","displayName":"Blue dusk","description":"A calm blue background","purchasePricePoints":125,"balanceAfterPoints":375,"previewData":{"version":1,"assetId":"blue_dusk","accentColor":"#AABBCC"},"purchasedAt":"2026-10-12T08:30:00+09:00"}]}
""".utf8)

private let emptyInventoryFixture = Data(#"{"items":[]}"#.utf8)

private let equipmentFixture = Data("""
{"slots":[{"category":"RUN_CARD_BACKGROUND","productId":null,"usesDefault":true},{"category":"RUN_CARD_FRAME","productId":"202","usesDefault":false},{"category":"PACE_FRAME","productId":null,"usesDefault":true}]}
""".utf8)

private func purchaseFixture(replayed: Bool) -> Data {
    Data("""
    {"purchaseId":"9001","productId":"101","purchasePricePoints":125,"balanceAfterPoints":375,"purchasedAt":"2026-10-12T08:30:00+09:00","replayed":\(replayed)}
    """.utf8)
}

private func problemFixture(code: String, status: Int = 409, requestID: String = "req-store-1") -> Data {
    Data("""
    {"status":\(status),"code":"\(code)","title":"private backend detail","requestId":"\(requestID)"}
    """.utf8)
}

private func waitForCosmeticStorePendingRequest(in scope: String) async -> Bool {
    for _ in 0..<500 {
        if MockURLProtocol.pendingCount(in: scope) > 0 { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private func waitForCosmeticStorePendingRequest() async -> Bool {
    for _ in 0..<500 {
        if MockURLProtocol.pendingCount > 0 { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private func waitForCosmeticStorePendingCleanup(in scope: String) async -> Bool {
    for _ in 0..<500 {
        if MockURLProtocol.pendingCount(in: scope) == 0 { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

final class CosmeticStoreClientTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testCatalogAndProductDetailsDecodeServerPriceAndAllowlistedPreview() async throws {
        MockURLProtocol.respondSequence([(200, catalogFixture), (200, productFixture)])
        let client = try makeCosmeticStoreClient()

        let catalog = try await client.fetchCatalog(category: .runCardBackground)
        let product = try await client.fetchProduct(id: "101")
        let requests = MockURLProtocol.requests
        let catalogRequest = try XCTUnwrap(requests.first)
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(catalogRequest.url), resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(catalog.items.map(\.id), ["101"])
        XCTAssertEqual(catalog.items[0].pricePoints, 125)
        XCTAssertEqual(catalog.items[0].category, .runCardBackground)
        XCTAssertEqual(catalog.items[0].previewData, CosmeticPreviewData(version: 1, assetID: "blue_dusk", accentColor: "#AABBCC"))
        XCTAssertFalse(catalog.items[0].owned)
        XCTAssertTrue(product.owned, "Owned state comes from the authenticated server response")
        XCTAssertEqual(product.pricePoints, 125, "The catalog price is displayed from the server")
        XCTAssertEqual(catalogRequest.url?.path, "/api/v1/store/catalog")
        XCTAssertEqual(query, [URLQueryItem(name: "category", value: "RUN_CARD_BACKGROUND")])
        XCTAssertEqual(catalogRequest.httpMethod, "GET")
        XCTAssertEqual(catalogRequest.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-store-token")
        XCTAssertEqual(catalogRequest.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/store/catalog/101")
        XCTAssertNil(requests.last?.httpBody)
    }

    func testInventoryEquipmentReplacementAndDefaultResetUseServerSlotState() async throws {
        let equipped = Data(#"{"category":"RUN_CARD_BACKGROUND","productId":"101","usesDefault":false,"changed":true}"#.utf8)
        let reset = Data(#"{"category":"RUN_CARD_BACKGROUND","productId":null,"usesDefault":true,"changed":true}"#.utf8)
        MockURLProtocol.respondSequence([(200, inventoryFixture), (200, equipmentFixture), (200, equipped), (200, reset)])
        let client = try makeCosmeticStoreClient()

        let inventory = try await client.fetchInventory()
        let equipment = try await client.fetchEquipment()
        let equipChange = try await client.equip(productID: "101", to: .runCardBackground)
        let unequipChange = try await client.unequip(category: .runCardBackground)
        let requests = MockURLProtocol.requests

        XCTAssertEqual(inventory.items.count, 1)
        XCTAssertEqual(inventory.items[0].purchaseID, "9001")
        XCTAssertEqual(inventory.items[0].productID, "101")
        XCTAssertEqual(inventory.items[0].purchasePricePoints, 125)
        XCTAssertEqual(inventory.items[0].balanceAfterPoints, 375)
        XCTAssertEqual(equipment.slots.map(\.category), CosmeticStoreCategory.allCases)
        XCTAssertEqual(equipment.slots[0].productID, nil)
        XCTAssertTrue(equipment.slots[0].usesDefault)
        XCTAssertEqual(equipment.slots[1].productID, "202")
        XCTAssertFalse(equipment.slots[1].usesDefault)
        XCTAssertEqual(equipChange.productID, "101")
        XCTAssertTrue(equipChange.changed)
        XCTAssertNil(unequipChange.productID)
        XCTAssertTrue(unequipChange.usesDefault)
        XCTAssertTrue(unequipChange.changed)
        XCTAssertEqual(requests[0].url?.path, "/api/v1/store/me/inventory")
        XCTAssertEqual(requests[1].url?.path, "/api/v1/store/me/equipment")
        XCTAssertEqual(requests[2].url?.path, "/api/v1/store/me/equipment/RUN_CARD_BACKGROUND")
        XCTAssertEqual(requests[2].httpMethod, "PUT")
        XCTAssertEqual(requests[3].url?.path, "/api/v1/store/me/equipment/RUN_CARD_BACKGROUND")
        XCTAssertEqual(requests[3].httpMethod, "DELETE")
        XCTAssertNil(requests[3].httpBody)
    }

    func testPurchaseUsesOnlyProductIDAndBackendIdempotencyReceiptForDuplicateRetry() async throws {
        let transport = RecordingCosmeticStoreTransport(responses: [
            (201, purchaseFixture(replayed: false)), (200, purchaseFixture(replayed: true))
        ])
        let client = makeCosmeticStoreClient(transport: transport)

        let first = try await client.purchase(productID: "101", idempotencyKey: "purchase-abc_1")
        let retry = try await client.purchase(productID: "101", idempotencyKey: "purchase-abc_1")
        let requests = await transport.capturedRequests()

        XCTAssertFalse(first.replayed)
        XCTAssertTrue(retry.replayed)
        XCTAssertEqual(first.purchaseID, retry.purchaseID)
        XCTAssertEqual(first.productID, "101")
        XCTAssertEqual(first.purchasePricePoints, 125, "Purchase price comes from the server receipt")
        XCTAssertEqual(first.balanceAfterPoints, 375, "Balance comes from the server receipt")
        XCTAssertEqual(first.purchasedAt, "2026-10-12T08:30:00+09:00")
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.path, "store/purchases")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.headers["Idempotency-Key"], "purchase-abc_1")
            XCTAssertEqual(request.headers["Cache-Control"], "no-store")
            let body = try XCTUnwrap(request.body)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["productId"])
            XCTAssertEqual(object["productId"] as? String, "101")
        }
    }

    func testURLProtocolPurchaseCreatedAndReplayResponsesReturnTheOriginalServerReceipt() async throws {
        MockURLProtocol.respondSequence([(201, purchaseFixture(replayed: false)), (200, purchaseFixture(replayed: true))])
        let client = try makeCosmeticStoreClient()

        let created = try await client.purchase(productID: "101", idempotencyKey: "purchase-replay-1")
        let replayed = try await client.purchase(productID: "101", idempotencyKey: "purchase-replay-1")
        let requests = MockURLProtocol.requests

        XCTAssertEqual(created.purchaseID, "9001")
        XCTAssertEqual(replayed.purchaseID, created.purchaseID)
        XCTAssertEqual(replayed.purchasePricePoints, created.purchasePricePoints)
        XCTAssertEqual(replayed.balanceAfterPoints, created.balanceAfterPoints)
        XCTAssertFalse(created.replayed)
        XCTAssertTrue(replayed.replayed)
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/api/v1/store/purchases" })
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == "purchase-replay-1" })
    }

    func testEquipmentWriteSendsOnlyTheProductIDInTheCategorySlot() async throws {
        let response = Data(#"{"category":"RUN_CARD_BACKGROUND","productId":"101","usesDefault":false,"changed":true}"#.utf8)
        let transport = RecordingCosmeticStoreTransport(responses: [(200, response)])
        let client = makeCosmeticStoreClient(transport: transport)

        _ = try await client.equip(productID: "101", to: .runCardBackground)
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.path, "store/me/equipment/RUN_CARD_BACKGROUND")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(Set(object.keys), ["productId"])
        XCTAssertEqual(object["productId"] as? String, "101")
    }

    func testManualPurchaseRetryCanReuseTheSameKeyAfterAmbiguousServiceFailure() async throws {
        let client = try makeCosmeticStoreClient()
        MockURLProtocol.respondSequence([
            (503, problemFixture(code: "POINT_UNAVAILABLE", status: 503)),
            (200, purchaseFixture(replayed: true))
        ])

        do {
            _ = try await client.purchase(productID: "101", idempotencyKey: "purchase-retry-1")
            XCTFail("A 503 must not look like a completed purchase")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .serviceUnavailable(code: "POINT_UNAVAILABLE", requestID: "req-store-1"))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1, "The purchase client does not automatically replay writes")

        let receipt = try await client.purchase(productID: "101", idempotencyKey: "purchase-retry-1")
        XCTAssertTrue(receipt.replayed)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }, ["purchase-retry-1", "purchase-retry-1"])
    }

    func testHTTPAuthenticationAuthorizationNotFoundConflictAndUnavailableFailuresStayTyped() async throws {
        let cases: [(Int, String, CosmeticStoreFailure)] = [
            (401, "UNAUTHENTICATED", .unauthenticated(requestID: "req-store-1")),
            (403, "FORBIDDEN", .forbidden(requestID: "req-store-1")),
            (404, "NOT_FOUND", .notFound(requestID: "req-store-1")),
            (409, "STORE_PRODUCT_ALREADY_OWNED", .alreadyOwned(requestID: "req-store-1")),
            (503, "POINT_UNAVAILABLE", .serviceUnavailable(code: "POINT_UNAVAILABLE", requestID: "req-store-1"))
        ]
        let client = try makeCosmeticStoreClient()
        MockURLProtocol.respondSequence(cases.map { status, code, _ in
            (status, problemFixture(code: code, status: status))
        })

        for (status, _, expected) in cases {
            do {
                _ = try await client.fetchProduct(id: "101")
                XCTFail("Expected HTTP \(status) to fail")
            } catch let failure as CosmeticStoreFailure {
                XCTAssertEqual(failure, expected)
                XCTAssertFalse(String(describing: failure).contains("private backend detail"))
                XCTAssertFalse(failure.userMessage.contains("private backend detail"))
            }
        }
        XCTAssertEqual(MockURLProtocol.requests.count, cases.count)
    }

    func testPurchaseInsufficientBalanceAndIdempotencyConflictRemainDistinct() async throws {
        let client = try makeCosmeticStoreClient()
        let cases: [(String, CosmeticStoreFailure)] = [
            ("POINT_INSUFFICIENT", .insufficientPoints(requestID: "req-store-1")),
            ("POINT_IDEMPOTENCY_CONFLICT", .idempotencyConflict(requestID: "req-store-1")),
            ("STORE_PRODUCT_ALREADY_OWNED", .alreadyOwned(requestID: "req-store-1")),
            ("STORE_PRODUCT_UNAVAILABLE", .productUnavailable(requestID: "req-store-1"))
        ]

        for (code, expected) in cases {
            MockURLProtocol.respond(statusCode: 409, data: problemFixture(code: code))
            do {
                _ = try await client.purchase(productID: "101", idempotencyKey: "purchase-key-1")
                XCTFail("Expected \(code) to fail")
            } catch let failure as CosmeticStoreFailure {
                XCTAssertEqual(failure, expected)
            }
        }

        MockURLProtocol.respond(statusCode: 409, data: problemFixture(code: "STORE_CATEGORY_MISMATCH"))
        do {
            _ = try await client.equip(productID: "101", to: .paceFrame)
            XCTFail("Expected a category mismatch")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .categoryMismatch(requestID: "req-store-1"))
        }
    }

    func testAccountSwitchUsesFreshBearerTokenForEveryRequestWithoutSendingMemberID() async throws {
        let session = MutableCosmeticStoreSessionProvider(
            RunUploadSession(ownerID: "101", accessToken: "fixture-user-a-token")
        )
        let client = try makeCosmeticStoreClient(sessionProvider: session)
        MockURLProtocol.respondSequence([(200, emptyInventoryFixture), (200, emptyInventoryFixture)])

        _ = try await client.fetchInventory()
        await session.set(RunUploadSession(ownerID: "202", accessToken: "fixture-user-b-token"))
        _ = try await client.fetchInventory()
        let requests = MockURLProtocol.requests

        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer fixture-user-a-token", "Bearer fixture-user-b-token"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/api/v1/store/me/inventory" })
        XCTAssertTrue(requests.allSatisfy { $0.httpBody == nil })
        XCTAssertTrue(requests.allSatisfy { !($0.url?.absoluteString.contains("memberId") ?? false) })
    }

    func testAccountSwitchDuringAnInFlightSuccessDoesNotReturnThePreviousAccountsResult() async throws {
        let session = MutableCosmeticStoreSessionProvider(
            RunUploadSession(ownerID: "101", accessToken: "fixture-user-a-token")
        )
        let client = try makeCosmeticStoreClient(sessionProvider: session)
        MockURLProtocol.holdFirstThenRespondSequence([(200, emptyInventoryFixture)])

        let previousAccountRequest = Task { () -> CosmeticStoreFailure? in
            do {
                _ = try await client.fetchInventory()
                return nil
            } catch let failure as CosmeticStoreFailure {
                return failure
            } catch {
                return nil
            }
        }
        let didSuspend = await waitForCosmeticStorePendingRequest()
        XCTAssertTrue(didSuspend)

        await session.set(RunUploadSession(ownerID: "202", accessToken: "fixture-user-b-token"))
        _ = try await client.fetchInventory()
        XCTAssertTrue(MockURLProtocol.resumeNextPending(statusCode: 200, data: emptyInventoryFixture))

        let oldResult = await previousAccountRequest.value
        XCTAssertEqual(oldResult, .sessionChanged)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer fixture-user-a-token", "Bearer fixture-user-b-token"
        ])
    }

    func testTaskCancellationDoesNotBecomeAnEmptySuccessOrTriggerAnotherRequest() async throws {
        let mockScope = UUID().uuidString
        defer { MockURLProtocol.reset(in: mockScope) }
        MockURLProtocol.suspendNext(in: mockScope)
        let client = try makeCosmeticStoreClient(mockScope: mockScope)
        let requestTask = Task { () -> CosmeticStoreFailure? in
            do {
                _ = try await client.fetchInventory()
                return nil
            } catch let failure as CosmeticStoreFailure {
                return failure
            } catch {
                return nil
            }
        }

        let didSuspend = await waitForCosmeticStorePendingRequest(in: mockScope)
        XCTAssertTrue(didSuspend, "Expected the mock URL protocol to hold the request")
        requestTask.cancel()

        let failure = await requestTask.value
        XCTAssertEqual(failure, .cancelled)
        let didFinishCancellationCleanup = await waitForCosmeticStorePendingCleanup(in: mockScope)
        XCTAssertTrue(didFinishCancellationCleanup, "URLSession must release the canceled request's scoped pending protocol")
        XCTAssertEqual(MockURLProtocol.requests(in: mockScope).count, 1)
        XCTAssertEqual(MockURLProtocol.pendingCount(in: mockScope), 0)
    }

    func testMalformedDTOPreviewPurchaseAndEquipmentResponsesFailClosed() async throws {
        let unsafePreview = Data(#"{"items":[{"productId":"101","category":"RUN_CARD_BACKGROUND","displayName":"Blue dusk","description":null,"pricePoints":125,"previewData":{"version":1,"assetId":"blue_dusk","assetUrl":"https://private.example.invalid/image.png"},"owned":false}]}"#.utf8)
        MockURLProtocol.respond(statusCode: 200, data: unsafePreview)
        do {
            _ = try await makeCosmeticStoreClient().fetchCatalog(category: nil)
            XCTFail("Unknown preview fields must not be accepted")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        MockURLProtocol.respond(statusCode: 201, data: purchaseFixture(replayed: true))
        do {
            _ = try await makeCosmeticStoreClient().purchase(productID: "101", idempotencyKey: "purchase-key-1")
            XCTFail("A creation response cannot claim to be an idempotent replay")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        let duplicateSlots = Data(#"{"slots":[{"category":"RUN_CARD_BACKGROUND","productId":null,"usesDefault":true},{"category":"RUN_CARD_BACKGROUND","productId":"202","usesDefault":false},{"category":"PACE_FRAME","productId":null,"usesDefault":true}]}"#.utf8)
        MockURLProtocol.respond(statusCode: 200, data: duplicateSlots)
        do {
            _ = try await makeCosmeticStoreClient().fetchEquipment()
            XCTFail("A duplicate category slot must not be treated as valid equipment")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testInvalidIDsAndIdempotencyKeysAreRejectedBeforeNetworkAccess() async throws {
        let client = try makeCosmeticStoreClient()

        do {
            _ = try await client.fetchProduct(id: "../101")
            XCTFail("A product ID cannot become a path component")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .invalidProductID)
        }

        do {
            _ = try await client.purchase(productID: "101", idempotencyKey: "short")
            XCTFail("An idempotency key must satisfy the backend ASCII format")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .invalidIdempotencyKey)
        }

        XCTAssertTrue(MockURLProtocol.requests.isEmpty)

        do {
            _ = try await makeCosmeticStoreClient(token: nil).fetchInventory()
            XCTFail("A missing authenticated session must stop before the request")
        } catch let failure as CosmeticStoreFailure {
            XCTAssertEqual(failure, .accessTokenUnavailable)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }
}
