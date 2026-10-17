import Foundation
import XCTest
@testable import MovNetworking

private actor CosmeticFlowSession: RunUploadSessionProviding {
    private var ownerID = "member-1"

    func currentSession() async throws -> RunUploadSession? {
        RunUploadSession(ownerID: ownerID, accessToken: "fixture-token")
    }

    func switchTo(_ ownerID: String) { self.ownerID = ownerID }
}

private actor CosmeticFlowService: CosmeticStoreServing, PointsWalletReading {
    private let loseFirstResponse: Bool
    private let serverBalanceAdjustment: Int64
    private let purchaseDelayNanoseconds: UInt64
    private let productUnavailable: Bool
    private var lostFirstResponse = false
    private var balance: Int64
    private var nextPurchaseID = 1
    private var inventory: [CosmeticStoreInventoryItem] = []
    private var equipment: [CosmeticStoreCategory: String] = [:]
    private var receipts: [String: CosmeticStorePurchaseReceipt] = [:]
    private var keys: [String] = []

    private let product = CosmeticStoreProduct(
        id: "101",
        category: .runCardBackground,
        displayName: "모브 라인",
        description: "fixture product",
        pricePoints: 400,
        previewData: CosmeticPreviewData(version: 1, assetID: "fixture-line", accentColor: "#AABBCC"),
        owned: false
    )

    init(
        balance: Int64 = 1_475,
        loseFirstResponse: Bool = false,
        serverBalanceAdjustment: Int64 = 0,
        purchaseDelayNanoseconds: UInt64 = 0,
        productUnavailable: Bool = false
    ) {
        self.balance = balance
        self.loseFirstResponse = loseFirstResponse
        self.serverBalanceAdjustment = serverBalanceAdjustment
        self.purchaseDelayNanoseconds = purchaseDelayNanoseconds
        self.productUnavailable = productUnavailable
    }

    func fetchCatalog(category: CosmeticStoreCategory?) async throws -> CosmeticStoreCatalog {
        let owned = inventory.contains { $0.productID == product.id }
        let current = CosmeticStoreProduct(
            id: product.id, category: product.category, displayName: product.displayName,
            description: product.description, pricePoints: product.pricePoints,
            previewData: product.previewData, owned: owned
        )
        return CosmeticStoreCatalog(items: category == nil || category == current.category ? [current] : [])
    }

    func fetchProduct(id: String) async throws -> CosmeticStoreProduct {
        guard id == product.id, !productUnavailable else { throw CosmeticStoreFailure.notFound(requestID: nil) }
        let owned = inventory.contains { $0.productID == product.id }
        return CosmeticStoreProduct(
            id: product.id, category: product.category, displayName: product.displayName,
            description: product.description, pricePoints: product.pricePoints,
            previewData: product.previewData, owned: owned
        )
    }

    func fetchInventory() async throws -> CosmeticStoreInventory { CosmeticStoreInventory(items: inventory) }

    func fetchBalance() async throws -> PointsBalance { PointsBalance(balancePoints: balance) }

    func fetchEntries(cursor: String?, size: Int) async throws -> PointsLedgerPage {
        PointsLedgerPage(entries: [], nextCursor: nil)
    }

    func fetchEquipment() async throws -> CosmeticEquipment {
        CosmeticEquipment(slots: CosmeticStoreCategory.allCases.map { category in
            let productID = equipment[category]
            return CosmeticEquipmentSlot(category: category, productID: productID, usesDefault: productID == nil)
        })
    }

    func purchase(productID: String, idempotencyKey: String) async throws -> CosmeticStorePurchaseReceipt {
        if purchaseDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: purchaseDelayNanoseconds) }
        keys.append(idempotencyKey)
        if let receipt = receipts[idempotencyKey] {
            return CosmeticStorePurchaseReceipt(
                purchaseID: receipt.purchaseID, productID: receipt.productID,
                purchasePricePoints: receipt.purchasePricePoints, balanceAfterPoints: receipt.balanceAfterPoints,
                purchasedAt: receipt.purchasedAt, replayed: true
            )
        }
        guard productID == product.id else { throw CosmeticStoreFailure.notFound(requestID: nil) }
        guard !productUnavailable else { throw CosmeticStoreFailure.productUnavailable(requestID: nil) }
        guard !inventory.contains(where: { $0.productID == productID }) else {
            throw CosmeticStoreFailure.alreadyOwned(requestID: nil)
        }
        guard balance >= product.pricePoints else { throw CosmeticStoreFailure.insufficientPoints(requestID: nil) }

        balance = balance - product.pricePoints + serverBalanceAdjustment
        let purchasedAt = "2026-10-17T08:30:00+09:00"
        let receipt = CosmeticStorePurchaseReceipt(
            purchaseID: String(nextPurchaseID), productID: productID,
            purchasePricePoints: product.pricePoints, balanceAfterPoints: balance,
            purchasedAt: purchasedAt, replayed: false
        )
        nextPurchaseID += 1
        receipts[idempotencyKey] = receipt
        inventory.append(CosmeticStoreInventoryItem(
            purchaseID: receipt.purchaseID, productID: product.id, category: product.category,
            displayName: product.displayName, description: product.description,
            purchasePricePoints: product.pricePoints, balanceAfterPoints: balance,
            previewData: product.previewData, purchasedAt: purchasedAt
        ))
        if loseFirstResponse && !lostFirstResponse {
            lostFirstResponse = true
            throw CosmeticStoreFailure.transport(.networkConnectionLost)
        }
        return receipt
    }

    func fetchPurchaseKeys() -> [String] { keys }
    func currentBalance() -> Int64 { balance }
    func equip(productID: String, to category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        guard let item = inventory.first(where: { $0.productID == productID }) else {
            throw CosmeticStoreFailure.notFound(requestID: nil)
        }
        guard item.category == category else { throw CosmeticStoreFailure.categoryMismatch(requestID: nil) }
        let changed = equipment[category] != productID
        equipment[category] = productID
        return CosmeticEquipmentChange(category: category, productID: productID, usesDefault: false, changed: changed)
    }

    func unequip(category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        let changed = equipment.removeValue(forKey: category) != nil
        return CosmeticEquipmentChange(category: category, productID: nil, usesDefault: true, changed: changed)
    }
}

@MainActor
final class CosmeticStoreFlowTests: XCTestCase {
    private func makeFlow(
        balance: Int64 = 1_475,
        loseFirstResponse: Bool = false,
        serverBalanceAdjustment: Int64 = 0,
        purchaseDelayNanoseconds: UInt64 = 0,
        productUnavailable: Bool = false
    ) -> (CosmeticStoreFlow, CosmeticFlowService, CosmeticFlowSession) {
        let service = CosmeticFlowService(
            balance: balance,
            loseFirstResponse: loseFirstResponse,
            serverBalanceAdjustment: serverBalanceAdjustment,
            purchaseDelayNanoseconds: purchaseDelayNanoseconds,
            productUnavailable: productUnavailable
        )
        let session = CosmeticFlowSession()
        return (CosmeticStoreFlow(store: service, wallet: service, sessionProvider: session), service, session)
    }

    func testInsufficientBalanceDisablesPurchaseAndDoesNotSubmit() async throws {
        let (flow, service, _) = makeFlow(balance: 100)

        await flow.refreshShop(category: .runCardBackground)
        let product = try XCTUnwrap(flow.product(id: "101"))
        XCTAssertEqual(flow.balancePoints, 100)
        XCTAssertFalse(flow.canPurchase(product))

        await flow.purchase(productID: product.id)

        let purchaseKeys = await service.fetchPurchaseKeys()
        XCTAssertTrue(purchaseKeys.isEmpty)
        XCTAssertEqual(flow.purchaseState, .idle)
        XCTAssertEqual(flow.balancePoints, 100)
    }

    func testConcurrentDuplicateTapsSubmitOnlyOnePurchase() async throws {
        let (flow, service, _) = makeFlow(purchaseDelayNanoseconds: 100_000_000)
        await flow.refreshShop(category: .runCardBackground)

        async let firstTap: Void = flow.purchase(productID: "101")
        async let secondTap: Void = flow.purchase(productID: "101")
        _ = await (firstTap, secondTap)

        let purchaseKeys = await service.fetchPurchaseKeys()
        XCTAssertEqual(purchaseKeys.count, 1)
        XCTAssertEqual(flow.balancePoints, 1_075)
    }

    func testDiscontinuedProductRemainsUnavailableAfterCatalogRefresh() async throws {
        let (flow, _, _) = makeFlow(productUnavailable: true)
        await flow.refreshShop(category: .runCardBackground)
        let catalogProduct = try XCTUnwrap(flow.product(id: "101"))
        XCTAssertTrue(flow.canPurchase(catalogProduct))

        await flow.purchase(productID: "101")

        XCTAssertEqual(flow.purchaseState, .failed(.productUnavailable(requestID: nil)))
        XCTAssertTrue(flow.isUnavailable("101"))
        let stillListedProduct = try XCTUnwrap(flow.product(id: "101"))
        XCTAssertFalse(flow.canPurchase(stillListedProduct))
    }

    func testLostResponseRequiresManualSameKeyReplayAndDoesNotRebuy() async throws {
        let (flow, service, _) = makeFlow(loseFirstResponse: true)
        await flow.refreshShop(category: .runCardBackground)

        await flow.purchase(productID: "101")

        guard case .outcomeUnknown(productID: "101", failure: .transport(.networkConnectionLost)) = flow.purchaseState else {
            return XCTFail("Expected an explicit unresolved purchase state")
        }
        let firstKeys = await service.fetchPurchaseKeys()
        XCTAssertEqual(firstKeys.count, 1)
        XCTAssertNil(flow.purchaseReceipt)
        let committedBalance = await service.currentBalance()
        XCTAssertEqual(committedBalance, 1_075, "The fixture commits the purchase before simulating a lost response")

        await flow.purchase(productID: "101")
        let keysAfterNormalPurchaseAction = await service.fetchPurchaseKeys()
        XCTAssertEqual(keysAfterNormalPurchaseAction.count, 1, "A normal purchase action must be blocked while outcome is unknown")

        await flow.resolveUnknownPurchase()

        let keysAfterReplay = await service.fetchPurchaseKeys()
        XCTAssertEqual(keysAfterReplay, firstKeys + [firstKeys[0]])
        XCTAssertEqual(flow.purchaseReceipt?.replayed, true)
        XCTAssertEqual(flow.balancePoints, 1_075)
        XCTAssertTrue(flow.isOwned("101"))
    }

    func testReceiptAndWalletRemainServerAuthoritativeAndEquipmentUsesOwnedItem() async throws {
        let (flow, service, _) = makeFlow(serverBalanceAdjustment: 25)
        await flow.refreshShop(category: .runCardBackground)

        await flow.purchase(productID: "101")

        XCTAssertEqual(flow.purchaseReceipt?.purchasePricePoints, 400)
        XCTAssertEqual(flow.purchaseReceipt?.balanceAfterPoints, 1_100)
        let currentBalance = await service.currentBalance()
        XCTAssertEqual(flow.balancePoints, currentBalance)
        let ownedProduct = try XCTUnwrap(flow.product(id: "101"))
        XCTAssertFalse(flow.canPurchase(ownedProduct))
        XCTAssertTrue(flow.inventory?.items.contains { $0.productID == "101" } == true)

        await flow.equip(productID: "101", to: .runCardBackground)
        XCTAssertTrue(flow.isEquipped("101", in: .runCardBackground))
        await flow.unequip(category: .runCardBackground)
        XCTAssertFalse(flow.isEquipped("101", in: .runCardBackground))
    }

    func testAccountContextChangeClearsAccountScopedStoreState() async {
        let (flow, _, session) = makeFlow()
        await flow.refreshShop(category: .runCardBackground)
        XCTAssertNotNil(flow.catalog)
        XCTAssertNotNil(flow.balancePoints)

        await session.switchTo("member-2")
        flow.accountContextDidChange()

        XCTAssertNil(flow.activeOwnerID)
        XCTAssertNil(flow.catalog)
        XCTAssertNil(flow.balancePoints)
        XCTAssertEqual(flow.sessionNotice, "계정이 변경되어 상점 정보를 다시 불러와야 해요.")
    }
}
