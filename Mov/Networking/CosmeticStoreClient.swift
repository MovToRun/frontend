import Foundation
import Combine

enum CosmeticStoreCategory: String, CaseIterable, Equatable, Sendable {
    case runCardBackground = "RUN_CARD_BACKGROUND"
    case runCardFrame = "RUN_CARD_FRAME"
    case paceFrame = "PACE_FRAME"
}

struct CosmeticPreviewData: Equatable, Sendable {
    let version: Int
    let assetID: String
    let accentColor: String?
}

struct CosmeticStoreProduct: Equatable, Sendable, Identifiable {
    let id: String
    let category: CosmeticStoreCategory
    let displayName: String
    let description: String?
    let pricePoints: Int64
    let previewData: CosmeticPreviewData
    let owned: Bool
}

struct CosmeticStoreCatalog: Equatable, Sendable {
    let items: [CosmeticStoreProduct]
}

struct CosmeticStorePurchaseReceipt: Equatable, Sendable {
    let purchaseID: String
    let productID: String
    let purchasePricePoints: Int64
    let balanceAfterPoints: Int64
    let purchasedAt: String
    let replayed: Bool
}

struct CosmeticStoreInventoryItem: Equatable, Sendable, Identifiable {
    let purchaseID: String
    let productID: String
    let category: CosmeticStoreCategory
    let displayName: String
    let description: String?
    let purchasePricePoints: Int64
    let balanceAfterPoints: Int64
    let previewData: CosmeticPreviewData
    let purchasedAt: String

    var id: String { purchaseID }
}

struct CosmeticStoreInventory: Equatable, Sendable {
    let items: [CosmeticStoreInventoryItem]
}

struct CosmeticEquipmentSlot: Equatable, Sendable, Identifiable {
    let category: CosmeticStoreCategory
    let productID: String?
    let usesDefault: Bool

    var id: CosmeticStoreCategory { category }
}

struct CosmeticEquipment: Equatable, Sendable {
    let slots: [CosmeticEquipmentSlot]
}

struct CosmeticEquipmentChange: Equatable, Sendable {
    let category: CosmeticStoreCategory
    let productID: String?
    let usesDefault: Bool
    let changed: Bool
}

enum CosmeticStoreFailure: Error, Equatable, Sendable {
    case accessTokenUnavailable
    case sessionChanged
    case unauthenticated(requestID: String?)
    case forbidden(requestID: String?)
    case notFound(requestID: String?)
    case insufficientPoints(requestID: String?)
    case idempotencyConflict(requestID: String?)
    case alreadyOwned(requestID: String?)
    case productUnavailable(requestID: String?)
    case categoryMismatch(requestID: String?)
    case malformedRequest(requestID: String?)
    case conflict(code: String?, requestID: String?)
    case serviceUnavailable(code: String?, requestID: String?)
    case serverFailure(statusCode: Int, requestID: String?)
    case invalidProductID
    case invalidIdempotencyKey
    case invalidResponse
    case transport(URLError.Code)
    case cancelled

    var userMessage: String {
        switch self {
        case .accessTokenUnavailable, .unauthenticated:
            return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .sessionChanged:
            return "계정이 변경됐어요. 현재 계정의 상점 정보를 다시 불러와 주세요."
        case .forbidden:
            return "이 요청을 처리할 권한이 없어요."
        case .notFound:
            return "상품을 찾을 수 없어요. 목록을 새로고침해 주세요."
        case .insufficientPoints:
            return "포인트가 부족해요. 잔액을 확인해 주세요."
        case .idempotencyConflict:
            return "구매 요청이 이미 다른 상품에 사용됐어요. 상품을 확인해 주세요."
        case .alreadyOwned:
            return "이미 보유한 상품이에요. 보관함을 새로고침해 주세요."
        case .productUnavailable:
            return "현재 구매할 수 없는 상품이에요."
        case .categoryMismatch:
            return "이 상품은 해당 꾸미기 슬롯에 장착할 수 없어요."
        case .malformedRequest, .invalidProductID, .invalidIdempotencyKey:
            return "요청 값을 확인해 주세요."
        case .conflict:
            return "요청한 상태가 변경됐어요. 최신 정보를 다시 확인해 주세요."
        case .serviceUnavailable:
            return "상점 기능을 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .serverFailure, .invalidResponse:
            return "상점 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .transport:
            return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요."
        }
    }
}

protocol CosmeticStoreServing: Sendable {
    func fetchCatalog(category: CosmeticStoreCategory?) async throws -> CosmeticStoreCatalog
    func fetchProduct(id: String) async throws -> CosmeticStoreProduct
    func fetchInventory() async throws -> CosmeticStoreInventory
    func purchase(productID: String, idempotencyKey: String) async throws -> CosmeticStorePurchaseReceipt
    func fetchEquipment() async throws -> CosmeticEquipment
    func equip(productID: String, to category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange
    func unequip(category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange
}

final class CosmeticStoreClient: CosmeticStoreServing, Sendable {
    private let apiClient: any APIResponseSending
    private let sessionProvider: any RunUploadSessionProviding

    init(apiClient: any APIResponseSending, sessionProvider: any RunUploadSessionProviding) {
        self.apiClient = apiClient
        self.sessionProvider = sessionProvider
    }

    func fetchCatalog(category: CosmeticStoreCategory? = nil) async throws -> CosmeticStoreCatalog {
        var queryItems: [URLQueryItem] = []
        if let category { queryItems.append(URLQueryItem(name: "category", value: category.rawValue)) }
        let response = try await send(path: "store/catalog", method: "GET", queryItems: queryItems)
        guard response.statusCode == 200 else { throw mapFailure(response) }

        do {
            let dto = try JSONDecoder().decode(CatalogResponseDTO.self, from: response.data)
            return CosmeticStoreCatalog(items: try dto.items.map(makeProduct))
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    func fetchProduct(id productID: String) async throws -> CosmeticStoreProduct {
        guard Self.isValidProductID(productID) else { throw CosmeticStoreFailure.invalidProductID }
        let response = try await send(path: "store/catalog/\(productID)", method: "GET")
        guard response.statusCode == 200 else { throw mapFailure(response) }

        do {
            return try makeProduct(JSONDecoder().decode(ProductResponseDTO.self, from: response.data))
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    func fetchInventory() async throws -> CosmeticStoreInventory {
        let response = try await send(path: "store/me/inventory", method: "GET")
        guard response.statusCode == 200 else { throw mapFailure(response) }

        do {
            let dto = try JSONDecoder().decode(InventoryResponseDTO.self, from: response.data)
            return CosmeticStoreInventory(items: try dto.items.map(makeInventoryItem))
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    func purchase(productID: String, idempotencyKey: String) async throws -> CosmeticStorePurchaseReceipt {
        guard Self.isValidProductID(productID) else { throw CosmeticStoreFailure.invalidProductID }
        guard Self.isValidIdempotencyKey(idempotencyKey) else { throw CosmeticStoreFailure.invalidIdempotencyKey }
        let body = try encode(ProductRequestDTO(productId: productID))
        let response = try await send(
            path: "store/purchases",
            method: "POST",
            body: body,
            additionalHeaders: ["Idempotency-Key": idempotencyKey]
        )
        guard response.statusCode == 200 || response.statusCode == 201 else { throw mapFailure(response) }

        do {
            let dto = try JSONDecoder().decode(PurchaseResponseDTO.self, from: response.data)
            guard Self.isValidProductID(dto.purchaseId),
                  Self.isValidProductID(dto.productId),
                  dto.purchasePricePoints >= 0,
                  dto.balanceAfterPoints >= 0,
                  Self.isValidOffsetTimestamp(dto.purchasedAt),
                  dto.productId == productID,
                  (response.statusCode == 200) == dto.replayed else {
                throw CosmeticStoreFailure.invalidResponse
            }
            return CosmeticStorePurchaseReceipt(
                purchaseID: dto.purchaseId,
                productID: dto.productId,
                purchasePricePoints: dto.purchasePricePoints,
                balanceAfterPoints: dto.balanceAfterPoints,
                purchasedAt: dto.purchasedAt,
                replayed: dto.replayed
            )
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    func fetchEquipment() async throws -> CosmeticEquipment {
        let response = try await send(path: "store/me/equipment", method: "GET")
        guard response.statusCode == 200 else { throw mapFailure(response) }

        do {
            let dto = try JSONDecoder().decode(EquipmentResponseDTO.self, from: response.data)
            let slots = try dto.slots.map(makeEquipmentSlot)
            guard slots.map(\.category) == CosmeticStoreCategory.allCases,
                  Set(slots.map(\.category)).count == CosmeticStoreCategory.allCases.count else {
                throw CosmeticStoreFailure.invalidResponse
            }
            return CosmeticEquipment(slots: slots)
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    func equip(productID: String, to category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        guard Self.isValidProductID(productID) else { throw CosmeticStoreFailure.invalidProductID }
        let body = try encode(ProductRequestDTO(productId: productID))
        let response = try await send(
            path: "store/me/equipment/\(category.rawValue)",
            method: "PUT",
            body: body
        )
        return try makeEquipmentChange(response, expectedCategory: category, expectedProductID: productID)
    }

    func unequip(category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        let response = try await send(path: "store/me/equipment/\(category.rawValue)", method: "DELETE")
        return try makeEquipmentChange(response, expectedCategory: category, expectedProductID: nil)
    }

    private func send(
        path: String,
        method: String,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:],
        queryItems: [URLQueryItem] = []
    ) async throws -> APIClientResponse {
        let session: RunUploadSession
        do {
            try Task.checkCancellation()
            guard let value = try await sessionProvider.currentSession(),
                  Self.isValidSession(value) else {
                throw CosmeticStoreFailure.accessTokenUnavailable
            }
            try Task.checkCancellation()
            session = value
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch is CancellationError {
            throw CosmeticStoreFailure.cancelled
        } catch let error as APIClientError where error == .cancelled {
            throw CosmeticStoreFailure.cancelled
        } catch {
            throw CosmeticStoreFailure.accessTokenUnavailable
        }

        var headers = [
            "Authorization": "Bearer \(session.accessToken)",
            "Accept": "application/json",
            "Cache-Control": "no-store"
        ]
        if body != nil { headers["Content-Type"] = "application/json" }
        headers.merge(additionalHeaders) { _, new in new }

        do {
            let response = try await apiClient.sendResponse(
                path: path,
                method: method,
                body: body,
                headers: headers,
                queryItems: queryItems
            )
            try Task.checkCancellation()
            if (200..<300).contains(response.statusCode) {
                try await ensureSameMember(as: session.ownerID)
            }
            return response
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch is CancellationError {
            throw CosmeticStoreFailure.cancelled
        } catch let error as APIClientError {
            switch error {
            case .cancelled:
                throw CosmeticStoreFailure.cancelled
            case .transport(let code):
                throw CosmeticStoreFailure.transport(code)
            default:
                throw CosmeticStoreFailure.invalidResponse
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CosmeticStoreFailure.cancelled }
            throw CosmeticStoreFailure.transport(error.code)
        } catch {
            throw CosmeticStoreFailure.transport(.unknown)
        }
    }

    private func ensureSameMember(as expectedOwnerID: String) async throws {
        do {
            try Task.checkCancellation()
            guard let current = try await sessionProvider.currentSession(),
                  Self.isValidSession(current),
                  current.ownerID == expectedOwnerID else {
                throw CosmeticStoreFailure.sessionChanged
            }
            try Task.checkCancellation()
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch is CancellationError {
            throw CosmeticStoreFailure.cancelled
        } catch {
            throw CosmeticStoreFailure.sessionChanged
        }
    }

    private func makeEquipmentChange(
        _ response: APIClientResponse,
        expectedCategory: CosmeticStoreCategory,
        expectedProductID: String?
    ) throws -> CosmeticEquipmentChange {
        guard response.statusCode == 200 else { throw mapFailure(response) }
        do {
            let dto = try JSONDecoder().decode(EquipmentChangeResponseDTO.self, from: response.data)
            guard let category = CosmeticStoreCategory(rawValue: dto.category),
                  category == expectedCategory,
                  dto.productId == expectedProductID,
                  dto.usesDefault == (dto.productId == nil),
                  dto.productId.map(Self.isValidProductID) ?? true else {
                throw CosmeticStoreFailure.invalidResponse
            }
            return CosmeticEquipmentChange(
                category: category,
                productID: dto.productId,
                usesDefault: dto.usesDefault,
                changed: dto.changed
            )
        } catch let failure as CosmeticStoreFailure {
            throw failure
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    private func makeProduct(_ dto: ProductResponseDTO) throws -> CosmeticStoreProduct {
        guard Self.isValidProductID(dto.productId),
              let category = CosmeticStoreCategory(rawValue: dto.category),
              dto.pricePoints >= 0 else {
            throw CosmeticStoreFailure.invalidResponse
        }
        return CosmeticStoreProduct(
            id: dto.productId,
            category: category,
            displayName: dto.displayName,
            description: dto.description,
            pricePoints: dto.pricePoints,
            previewData: dto.previewData,
            owned: dto.owned
        )
    }

    private func makeInventoryItem(_ dto: InventoryItemResponseDTO) throws -> CosmeticStoreInventoryItem {
        guard Self.isValidProductID(dto.purchaseId),
              Self.isValidProductID(dto.productId),
              let category = CosmeticStoreCategory(rawValue: dto.category),
              dto.purchasePricePoints >= 0,
              dto.balanceAfterPoints >= 0,
              Self.isValidOffsetTimestamp(dto.purchasedAt) else {
            throw CosmeticStoreFailure.invalidResponse
        }
        return CosmeticStoreInventoryItem(
            purchaseID: dto.purchaseId,
            productID: dto.productId,
            category: category,
            displayName: dto.displayName,
            description: dto.description,
            purchasePricePoints: dto.purchasePricePoints,
            balanceAfterPoints: dto.balanceAfterPoints,
            previewData: dto.previewData,
            purchasedAt: dto.purchasedAt
        )
    }

    private func makeEquipmentSlot(_ dto: EquipmentSlotResponseDTO) throws -> CosmeticEquipmentSlot {
        guard let category = CosmeticStoreCategory(rawValue: dto.category),
              dto.productId.map(Self.isValidProductID) ?? true,
              dto.usesDefault == (dto.productId == nil) else {
            throw CosmeticStoreFailure.invalidResponse
        }
        return CosmeticEquipmentSlot(category: category, productID: dto.productId, usesDefault: dto.usesDefault)
    }

    private func mapFailure(_ response: APIClientResponse) -> CosmeticStoreFailure {
        let problem = try? JSONDecoder().decode(CosmeticStoreProblemResponse.self, from: response.data)
        let requestID = problem?.requestId ?? response.requestID
        switch response.statusCode {
        case 401:
            return .unauthenticated(requestID: requestID)
        case 403:
            return .forbidden(requestID: requestID)
        case 404:
            return .notFound(requestID: requestID)
        case 400:
            return .malformedRequest(requestID: requestID)
        case 409:
            switch problem?.code {
            case "POINT_INSUFFICIENT": return .insufficientPoints(requestID: requestID)
            case "POINT_IDEMPOTENCY_CONFLICT": return .idempotencyConflict(requestID: requestID)
            case "STORE_PRODUCT_ALREADY_OWNED": return .alreadyOwned(requestID: requestID)
            case "STORE_PRODUCT_UNAVAILABLE": return .productUnavailable(requestID: requestID)
            case "STORE_CATEGORY_MISMATCH": return .categoryMismatch(requestID: requestID)
            default: return .conflict(code: problem?.code, requestID: requestID)
            }
        case 503:
            return .serviceUnavailable(code: problem?.code, requestID: requestID)
        default:
            return .serverFailure(statusCode: response.statusCode, requestID: requestID)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw CosmeticStoreFailure.invalidResponse
        }
    }

    private static func isValidProductID(_ value: String) -> Bool {
        guard value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              let parsed = Int64(value) else { return false }
        return parsed > 0
    }

    private static func isValidSession(_ session: RunUploadSession) -> Bool {
        !session.ownerID.isEmpty
            && session.ownerID.rangeOfCharacter(from: .controlCharacters) == nil
            && !session.accessToken.isEmpty
            && session.accessToken.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }

    private static func isValidIdempotencyKey(_ value: String) -> Bool {
        guard (8...128).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                || byte == 46 || byte == 95 || byte == 126 || byte == 45
        }
    }

    private static func isValidOffsetTimestamp(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
}

private struct CatalogResponseDTO: Decodable {
    let items: [ProductResponseDTO]
}

private struct ProductResponseDTO: Decodable {
    let productId: String
    let category: String
    let displayName: String
    let description: String?
    let pricePoints: Int64
    let previewData: CosmeticPreviewData
    let owned: Bool
}

private struct PurchaseResponseDTO: Decodable {
    let purchaseId: String
    let productId: String
    let purchasePricePoints: Int64
    let balanceAfterPoints: Int64
    let purchasedAt: String
    let replayed: Bool
}

private struct InventoryResponseDTO: Decodable {
    let items: [InventoryItemResponseDTO]
}

private struct InventoryItemResponseDTO: Decodable {
    let purchaseId: String
    let productId: String
    let category: String
    let displayName: String
    let description: String?
    let purchasePricePoints: Int64
    let balanceAfterPoints: Int64
    let previewData: CosmeticPreviewData
    let purchasedAt: String
}

private struct EquipmentResponseDTO: Decodable {
    let slots: [EquipmentSlotResponseDTO]
}

private struct EquipmentSlotResponseDTO: Decodable {
    let category: String
    let productId: String?
    let usesDefault: Bool
}

private struct EquipmentChangeResponseDTO: Decodable {
    let category: String
    let productId: String?
    let usesDefault: Bool
    let changed: Bool
}

private struct ProductRequestDTO: Encodable {
    let productId: String
}

private struct CosmeticStoreProblemResponse: Decodable {
    let code: String?
    let requestId: String?
}

extension CosmeticPreviewData: Decodable {
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let allowedKeys: Set<String> = ["version", "assetId", "accentColor"]
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: allowedKeys) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected preview field"))
        }
        guard let versionKey = Key(stringValue: "version"),
              let assetIDKey = Key(stringValue: "assetId"),
              let accentColorKey = Key(stringValue: "accentColor") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid preview keys"))
        }

        let version = try container.decode(Int.self, forKey: versionKey)
        let assetID = try container.decode(String.self, forKey: assetIDKey)
        let accentColor = try container.decodeIfPresent(String.self, forKey: accentColorKey)
        guard version == 1,
              assetID.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil,
              accentColor.map({ $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid preview payload"))
        }
        self.version = version
        self.assetID = assetID
        self.accentColor = accentColor
    }
}

enum CosmeticStoreLoadState<Value: Equatable & Sendable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(CosmeticStoreFailure)
}

enum CosmeticStoreBalanceState: Equatable {
    case idle
    case loading
    case loaded(Int64)
    case failed(PointsReadFailure)
}

enum CosmeticStorePurchaseState: Equatable {
    case idle
    case submitting(productID: String)
    case outcomeUnknown(productID: String, failure: CosmeticStoreFailure)
    case succeeded(CosmeticStorePurchaseReceipt)
    case failed(CosmeticStoreFailure)
}

/// Owns the account-scoped state used by the shop UI. It never mutates a local
/// points balance; catalog, wallet, ownership, and equipment values come from
/// their authenticated server readers.
@MainActor final class CosmeticStoreFlow: ObservableObject {
    private struct PendingPurchase {
        let productID: String
        let idempotencyKey: String
        let ownerID: String
    }

    private let store: (any CosmeticStoreServing)?
    private let wallet: (any PointsWalletReading)?
    private let sessionProvider: (any RunUploadSessionProviding)?

    @Published private(set) var catalogState: CosmeticStoreLoadState<CosmeticStoreCatalog> = .idle
    @Published private(set) var productState: CosmeticStoreLoadState<CosmeticStoreProduct> = .idle
    @Published private(set) var inventoryState: CosmeticStoreLoadState<CosmeticStoreInventory> = .idle
    @Published private(set) var equipmentState: CosmeticStoreLoadState<CosmeticEquipment> = .idle
    @Published private(set) var balanceState: CosmeticStoreBalanceState = .idle
    @Published private(set) var purchaseState: CosmeticStorePurchaseState = .idle
    @Published private(set) var equipmentMutationCategory: CosmeticStoreCategory?
    @Published private(set) var equipmentFailure: CosmeticStoreFailure?
    @Published private(set) var balanceNotice: String?
    @Published private(set) var sessionNotice: String?
    @Published private(set) var activeOwnerID: String?

    private var readGeneration: UInt64 = 0
    private var pendingPurchase: PendingPurchase?
    private var unavailableProductIDs: Set<String> = []

    init(
        store: (any CosmeticStoreServing)?,
        wallet: (any PointsWalletReading)?,
        sessionProvider: (any RunUploadSessionProviding)?
    ) {
        self.store = store
        self.wallet = wallet
        self.sessionProvider = sessionProvider
    }

    var catalog: CosmeticStoreCatalog? {
        guard case .loaded(let value) = catalogState else { return nil }
        return value
    }

    var selectedProduct: CosmeticStoreProduct? {
        guard case .loaded(let value) = productState else { return nil }
        return value
    }

    var inventory: CosmeticStoreInventory? {
        guard case .loaded(let value) = inventoryState else { return nil }
        return value
    }

    var equipment: CosmeticEquipment? {
        guard case .loaded(let value) = equipmentState else { return nil }
        return value
    }

    var balancePoints: Int64? {
        guard case .loaded(let value) = balanceState else { return nil }
        return value
    }

    var purchaseReceipt: CosmeticStorePurchaseReceipt? {
        guard case .succeeded(let receipt) = purchaseState else { return nil }
        return receipt
    }

    var purchaseInFlight: Bool {
        if case .submitting = purchaseState { return true }
        return false
    }

    var purchaseOutcomeUnknown: Bool {
        if case .outcomeUnknown = purchaseState { return true }
        return false
    }

    func product(id: String) -> CosmeticStoreProduct? {
        if let selectedProduct, selectedProduct.id == id { return selectedProduct }
        return catalog?.items.first { $0.id == id }
    }

    func isOwned(_ productID: String) -> Bool {
        catalog?.items.first { $0.id == productID }?.owned == true
            || inventory?.items.contains { $0.productID == productID } == true
            || purchaseReceipt?.productID == productID
    }

    func isEquipped(_ productID: String, in category: CosmeticStoreCategory) -> Bool {
        equipment?.slots.first { $0.category == category }?.productID == productID
    }

    func isUnavailable(_ productID: String) -> Bool {
        unavailableProductIDs.contains(productID)
    }

    func canPurchase(_ product: CosmeticStoreProduct) -> Bool {
        guard let balancePoints,
              balancePoints >= product.pricePoints,
              !product.owned,
              !isOwned(product.id),
              !unavailableProductIDs.contains(product.id),
              !purchaseInFlight,
              !purchaseOutcomeUnknown else { return false }
        return true
    }

    func refreshShop(category: CosmeticStoreCategory? = nil) async {
        guard let store, let wallet else {
            clearAccountData()
            catalogState = .failed(.accessTokenUnavailable)
            inventoryState = .failed(.accessTokenUnavailable)
            equipmentState = .failed(.accessTokenUnavailable)
            balanceState = .failed(.accessTokenUnavailable)
            return
        }

        let ownerID: String
        do {
            ownerID = try await requireCurrentOwnerID()
        } catch {
            clearAccountData()
            catalogState = .failed(error as? CosmeticStoreFailure ?? .accessTokenUnavailable)
            inventoryState = .failed(error as? CosmeticStoreFailure ?? .accessTokenUnavailable)
            equipmentState = .failed(error as? CosmeticStoreFailure ?? .accessTokenUnavailable)
            balanceState = .failed(.accessTokenUnavailable)
            return
        }

        adoptOwner(ownerID)
        readGeneration &+= 1
        let generation = readGeneration
        sessionNotice = nil
        catalogState = .loading
        inventoryState = .loading
        equipmentState = .loading
        balanceState = .loading

        do {
            let value = try await store.fetchCatalog(category: category)
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            catalogState = .loaded(value)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            catalogState = .failed(failure)
            if failure == .sessionChanged { invalidateAfterSessionChange() }
        }

        guard readGeneration == generation else { return }
        do {
            let value = try await store.fetchInventory()
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            inventoryState = .loaded(value)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            inventoryState = .failed(failure)
            if failure == .sessionChanged { invalidateAfterSessionChange(); return }
        }

        guard readGeneration == generation else { return }
        do {
            let value = try await store.fetchEquipment()
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            equipmentState = .loaded(value)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            equipmentState = .failed(failure)
            if failure == .sessionChanged { invalidateAfterSessionChange(); return }
        }

        guard readGeneration == generation else { return }
        do {
            let value = try await wallet.fetchBalance()
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            balanceState = value.balancePoints >= 0 ? .loaded(value.balancePoints) : .failed(.invalidResponse)
            if let receipt = purchaseReceipt {
                balanceNotice = value.balancePoints == receipt.balanceAfterPoints
                    ? nil
                    : "구매 이후 포인트 변동을 반영한 현재 서버 잔액이에요."
            }
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: generation) else { return }
            let failure = error as? PointsReadFailure ?? .invalidResponse
            balanceState = .failed(failure)
        }
    }

    func refreshProduct(id: String) async {
        guard let store else {
            productState = .failed(.accessTokenUnavailable)
            return
        }
        if activeOwnerID == nil { await refreshShop() }
        guard let ownerID = activeOwnerID else {
            productState = .failed(.accessTokenUnavailable)
            return
        }
        do {
            let currentOwnerID = try await requireCurrentOwnerID()
            guard currentOwnerID == ownerID else {
                invalidateAfterSessionChange()
                return
            }
        } catch {
            productState = .failed(error as? CosmeticStoreFailure ?? .accessTokenUnavailable)
            return
        }

        productState = .loading
        do {
            let value = try await store.fetchProduct(id: id)
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            selectedProductIsAvailable(value)
            productState = .loaded(value)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            productState = .failed(failure)
            switch failure {
            case .productUnavailable, .notFound: unavailableProductIDs.insert(id)
            default: break
            }
            if failure == .sessionChanged { invalidateAfterSessionChange() }
        }
    }

    func purchase(productID: String) async {
        guard !purchaseInFlight, !purchaseOutcomeUnknown,
              let initialProduct = product(id: productID), canPurchase(initialProduct),
              let ownerID = activeOwnerID else { return }
        do {
            guard try await requireCurrentOwnerID() == ownerID else {
                invalidateAfterSessionChange()
                return
            }
        } catch {
            purchaseState = .failed(error as? CosmeticStoreFailure ?? .accessTokenUnavailable)
            return
        }
        guard activeOwnerID == ownerID,
              !purchaseInFlight,
              !purchaseOutcomeUnknown,
              let currentProduct = product(id: productID),
              canPurchase(currentProduct) else { return }

        let attempt = PendingPurchase(productID: productID, idempotencyKey: UUID().uuidString, ownerID: ownerID)
        pendingPurchase = attempt
        await submit(attempt)
    }

    /// Resolves an ambiguous response only after an explicit user action, reusing
    /// the original key so the server can replay the original receipt safely.
    func resolveUnknownPurchase() async {
        guard purchaseOutcomeUnknown, let attempt = pendingPurchase else { return }
        do {
            guard try await requireCurrentOwnerID() == attempt.ownerID else {
                invalidateAfterSessionChange()
                return
            }
        } catch {
            purchaseState = .outcomeUnknown(productID: attempt.productID, failure: .accessTokenUnavailable)
            return
        }
        await submit(attempt)
    }

    func equip(productID: String, to category: CosmeticStoreCategory) async {
        guard equipmentMutationCategory == nil,
              inventory?.items.contains(where: { $0.productID == productID && $0.category == category }) == true,
              let store, let ownerID = activeOwnerID else { return }
        equipmentMutationCategory = category
        equipmentFailure = nil
        defer { equipmentMutationCategory = nil }
        do {
            let change = try await store.equip(productID: productID, to: category)
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            apply(change)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            equipmentFailure = failure
            if failure == .sessionChanged { invalidateAfterSessionChange() }
        }
    }

    func unequip(category: CosmeticStoreCategory) async {
        guard equipmentMutationCategory == nil, let store, let ownerID = activeOwnerID else { return }
        equipmentMutationCategory = category
        equipmentFailure = nil
        defer { equipmentMutationCategory = nil }
        do {
            let change = try await store.unequip(category: category)
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            apply(change)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            equipmentFailure = failure
            if failure == .sessionChanged { invalidateAfterSessionChange() }
        }
    }

    func accountContextDidChange() {
        clearAccountData()
        sessionNotice = "계정이 변경되어 상점 정보를 다시 불러와야 해요."
    }

    private func submit(_ attempt: PendingPurchase) async {
        guard let store, pendingPurchase?.idempotencyKey == attempt.idempotencyKey,
              !purchaseInFlight else { return }
        purchaseState = .submitting(productID: attempt.productID)
        let priorBalance = balancePoints
        do {
            let receipt = try await store.purchase(productID: attempt.productID, idempotencyKey: attempt.idempotencyKey)
            guard receipt.productID == attempt.productID else {
                pendingPurchase = attempt
                purchaseState = .outcomeUnknown(productID: attempt.productID, failure: .invalidResponse)
                return
            }
            guard await isCurrent(ownerID: attempt.ownerID, generation: nil) else { return }
            pendingPurchase = nil
            unavailableProductIDs.remove(attempt.productID)
            purchaseState = .succeeded(receipt)
            balanceState = .loaded(receipt.balanceAfterPoints)
            if let priorBalance, priorBalance - receipt.purchasePricePoints != receipt.balanceAfterPoints {
                balanceNotice = "구매 응답 잔액이 직전 조회와 달라 현재 잔액을 새로 확인하고 있어요."
            }
            await refreshShop()
        } catch {
            let failure = error as? CosmeticStoreFailure ?? .invalidResponse
            guard await isCurrent(ownerID: attempt.ownerID, generation: nil) else { return }
            if failure == .sessionChanged {
                invalidateAfterSessionChange()
                return
            }
            if isAmbiguous(failure) {
                pendingPurchase = attempt
                purchaseState = .outcomeUnknown(productID: attempt.productID, failure: failure)
                return
            }

            pendingPurchase = nil
            purchaseState = .failed(failure)
            switch failure {
            case .productUnavailable, .alreadyOwned:
                unavailableProductIDs.insert(attempt.productID)
                await refreshShop()
            case .insufficientPoints:
                await refreshWallet(ownerID: attempt.ownerID)
            default:
                break
            }
        }
    }

    private func refreshWallet(ownerID: String) async {
        guard let wallet else { return }
        do {
            let value = try await wallet.fetchBalance()
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            balanceState = value.balancePoints >= 0 ? .loaded(value.balancePoints) : .failed(.invalidResponse)
        } catch {
            guard await isCurrent(ownerID: ownerID, generation: nil) else { return }
            balanceState = .failed(error as? PointsReadFailure ?? .invalidResponse)
        }
    }

    private func apply(_ change: CosmeticEquipmentChange) {
        guard case .loaded(let current) = equipmentState else { return }
        let updated = CosmeticEquipment(slots: current.slots.map { slot in
            guard slot.category == change.category else { return slot }
            return CosmeticEquipmentSlot(category: change.category, productID: change.productID, usesDefault: change.usesDefault)
        })
        equipmentState = .loaded(updated)
    }

    private func selectedProductIsAvailable(_ product: CosmeticStoreProduct) {
        unavailableProductIDs.remove(product.id)
    }

    private func isAmbiguous(_ failure: CosmeticStoreFailure) -> Bool {
        switch failure {
        case .transport, .cancelled, .invalidResponse, .serviceUnavailable, .serverFailure:
            true
        case .accessTokenUnavailable, .unauthenticated, .forbidden, .notFound, .insufficientPoints,
             .idempotencyConflict, .alreadyOwned, .productUnavailable, .categoryMismatch,
             .malformedRequest, .conflict, .invalidProductID, .invalidIdempotencyKey, .sessionChanged:
            false
        }
    }

    private func requireCurrentOwnerID() async throws -> String {
        guard let sessionProvider,
              let session = try await sessionProvider.currentSession(),
              !session.ownerID.isEmpty,
              session.ownerID.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CosmeticStoreFailure.accessTokenUnavailable
        }
        return session.ownerID
    }

    private func isCurrent(ownerID: String, generation: UInt64?) async -> Bool {
        if let generation, readGeneration != generation { return false }
        do {
            guard try await requireCurrentOwnerID() == ownerID else {
                invalidateAfterSessionChange()
                return false
            }
            return generation == nil || readGeneration == generation
        } catch {
            invalidateAfterSessionChange()
            return false
        }
    }

    private func adoptOwner(_ ownerID: String) {
        if let activeOwnerID, activeOwnerID != ownerID {
            clearAccountData()
            self.activeOwnerID = ownerID
            sessionNotice = nil
        } else {
            self.activeOwnerID = ownerID
        }
    }

    private func invalidateAfterSessionChange() {
        clearAccountData()
        catalogState = .failed(.sessionChanged)
        inventoryState = .failed(.sessionChanged)
        equipmentState = .failed(.sessionChanged)
        productState = .failed(.sessionChanged)
        balanceState = .failed(.unauthenticated)
        purchaseState = .failed(.sessionChanged)
        sessionNotice = "계정이 변경되어 이전 계정의 상점 결과를 표시하지 않아요. 현재 계정 정보를 다시 불러와 주세요."
    }

    private func clearAccountData() {
        readGeneration &+= 1
        activeOwnerID = nil
        catalogState = .idle
        productState = .idle
        inventoryState = .idle
        equipmentState = .idle
        balanceState = .idle
        purchaseState = .idle
        equipmentMutationCategory = nil
        equipmentFailure = nil
        balanceNotice = nil
        pendingPurchase = nil
        unavailableProductIDs.removeAll()
    }
}
