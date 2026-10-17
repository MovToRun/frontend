import SwiftUI
import Observation

enum WPointKind: String, Codable, CaseIterable, Hashable {
    case all, earn, use
    var title: String { switch self { case .all: "전체"; case .earn: "적립"; case .use: "사용" } }
}

struct WPointEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
    var amount: Int
    var date: Date
    var kind: WPointKind { amount >= 0 ? .earn : .use }
}

enum WPointCategory: String, CaseIterable, Identifiable, Equatable {
    case image = "러닝 카드 이미지", frame = "프레임", face = "페이스 프레임"
    var id: String { rawValue }

    var storeCategory: CosmeticStoreCategory {
        switch self {
        case .image: .runCardBackground
        case .frame: .runCardFrame
        case .face: .paceFrame
        }
    }

    init(storeCategory: CosmeticStoreCategory) {
        switch storeCategory {
        case .runCardBackground: self = .image
        case .runCardFrame: self = .frame
        case .paceFrame: self = .face
        }
    }
}

enum WPointArtworkGeometry {
    static let listingAspect: CGFloat = 1.16
    static let detailAspect: CGFloat = 1.35

    static func cardSize(in container: CGSize, large: Bool) -> CGSize {
        let horizontalInset: CGFloat = large ? 38 : 12
        let verticalInset: CGFloat = large ? 42 : 17
        let width = max(0, container.width - horizontalInset * 2)
        let height = min(width / 1.65, max(0, container.height - verticalInset * 2))
        return CGSize(width: width, height: height)
    }
}

struct WPointProduct: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let description: String?
    let category: WPointCategory
    let price: Int64
    let previewData: CosmeticPreviewData
    let owned: Bool

    init(_ product: CosmeticStoreProduct) {
        id = product.id
        name = product.displayName
        kind = WPointCategory(storeCategory: product.category).rawValue
        description = product.description
        category = WPointCategory(storeCategory: product.category)
        price = product.pricePoints
        previewData = product.previewData
        owned = product.owned
    }

    init(_ item: CosmeticStoreInventoryItem) {
        id = item.productID
        name = item.displayName
        kind = WPointCategory(storeCategory: item.category).rawValue
        description = item.description
        category = WPointCategory(storeCategory: item.category)
        price = item.purchasePricePoints
        previewData = item.previewData
        owned = true
    }
}

@MainActor @Observable final class WPointsStore {
    private let defaults: UserDefaults
    private let key = "mov.points.local.v2"
    private let legacyKey = "mov.points.local.v1"
    private struct Saved: Codable {
        var balance: Int
        var entries: [WPointEntry]
        var owned: Set<String>
    }
    private struct LegacyEntry: Decodable {
        var id: UUID?
        var title: String
        var amount: Int
        var date: Date
    }
    private struct LegacySaved: Decodable {
        var balance: Int
        var entries: [LegacyEntry]
        var owned: Set<String>

        private enum CodingKeys: String, CodingKey { case balance, entries, owned }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            balance = try values.decode(Int.self, forKey: .balance)
            entries = try values.decode([LegacyEntry].self, forKey: .entries)
            owned = try values.decodeIfPresent(Set<String>.self, forKey: .owned) ?? []
        }
    }

    var balance: Int
    var entries: [WPointEntry]
    var ownedItemIDs: Set<String>
    private(set) var dataUnavailable = false

    init(defaults: UserDefaults = .standard, insufficientFixture: Bool = false, emptyFixture: Bool = false) {
        self.defaults = defaults
        balance = 0
        entries = []
        ownedItemIDs = []

        if defaults.object(forKey: key) != nil {
            if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
                balance = saved.balance
                entries = saved.entries
                ownedItemIDs = saved.owned
            } else {
                dataUnavailable = true
            }
        } else if defaults.object(forKey: legacyKey) != nil {
            if let data = defaults.data(forKey: legacyKey), let saved = try? JSONDecoder().decode(LegacySaved.self, from: data) {
                balance = saved.balance
                entries = saved.entries.map {
                    WPointEntry(id: $0.id ?? UUID(), title: $0.title, detail: $0.amount < 0 ? "사용 내역" : "적립 내역", amount: $0.amount, date: $0.date)
                }
                // v1 catalog IDs do not identify the different v2 products. Keep them namespaced
                // so legacy ownership survives without accidentally marking a new item as owned.
                ownedItemIDs = Set(saved.owned.map { "legacy.v1.\($0)" })
                if !persist() { dataUnavailable = true }
            } else {
                dataUnavailable = true
            }
        } else {
            let calendar = Calendar(identifier: .gregorian)
            let base = ISO8601DateFormatter().date(from: "2026-10-01T09:00:00+09:00") ?? Date()
            balance = 1_250
            entries = [
                WPointEntry(title: "러닝 카드 배경", detail: "사용 내역 예시", amount: -250, date: base),
                WPointEntry(title: "포인트 적립", detail: "적립 내역 예시", amount: 500, date: calendar.date(byAdding: .day, value: -1, to: base) ?? base),
                WPointEntry(title: "포인트 적립", detail: "적립 내역 예시", amount: 1_000, date: calendar.date(byAdding: .day, value: -2, to: base) ?? base)
            ]
            ownedItemIDs = []
            if !persist() {
                dataUnavailable = true
                balance = 0
                entries = []
                ownedItemIDs = []
            }
        }
        if dataUnavailable {
            // A present but unreadable value must never be replaced with the sample state.
            balance = 0
            entries = []
            ownedItemIDs = []
        }
        if insufficientFixture { balance = 100 }
        if emptyFixture { balance = 0; entries = []; ownedItemIDs = [] }
    }

    func filteredEntries(_ kind: WPointKind) -> [WPointEntry] {
        kind == .all ? entries : entries.filter { $0.kind == kind }
    }

    @discardableResult private func persist() -> Bool {
        guard !dataUnavailable else { return false }
        let saved = Saved(balance: balance, entries: entries, owned: ownedItemIDs)
        guard let data = try? JSONEncoder().encode(saved) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

extension WireframeRoot {
    private var pointsBalanceDisplay: String {
        pointsStore.dataUnavailable ? "—" : pointsStore.balance.formatted()
    }

    private var pointDataUnavailableNotice: some View {
        WNotice(text: "저장된 포인트 데이터를 읽지 못해 표시하거나 변경할 수 없어요. 원본을 보존하고 예시 데이터로 덮어쓰지 않았어요.", danger: true)
    }

    func returnToPointShop() {
        ui.path.removeAll()
        ui.screen = "POINTS"
        ui.rootIndex = 0
        ui.previousRootIndex = 0
        go("SHOP")
    }

    @ViewBuilder private var remotePointsBalancePanel:some View {
        if remoteReads.hasPointsDependency {
            VStack(alignment:.leading,spacing:9){
                Text("원격 포인트 조회").font(W.font(13,.semibold))
                switch remoteReads.pointsState {
                case .idle:
                    WText(text:"조회 준비 중이에요.",small:true)
                case .loading:
                    HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"포인트를 불러오는 중이에요.",small:true)}
                case .loaded(let snapshot), .loadingMore(let snapshot):
                    HStack(alignment:.firstTextBaseline,spacing:5){Text(snapshot.balance.balancePoints.formatted()).font(W.font(27,.semibold)).monospacedDigit().accessibilityIdentifier("remotePointBalance");Text("포인트").font(W.font(12)).foregroundStyle(W.muted)}
                    if case .loadingMore = remoteReads.pointsState { HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"다음 내역을 불러오는 중이에요.",small:true)} }
                case .failed(let failure):
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("remotePointsReadFailure")
                    if failure.canManuallyRetry { remotePointsRetryButton }
                case .failedLoadingMore(_,let failure):
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("remotePointsReadFailure")
                    if failure.canManuallyRetry { remotePointsRetryButton }
                }
                WText(text:"읽기 전용 조회예요. 아래 잔액과 상점은 이 기기의 예시 데이터예요.",small:true)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(W.soft,in:RoundedRectangle(cornerRadius:14)).accessibilityIdentifier("remotePointsBalancePanel")
        }
    }

    @ViewBuilder private var remotePointsLedgerPanel:some View {
        if remoteReads.hasPointsDependency {
            VStack(alignment:.leading,spacing:10){
                Text("원격 포인트 내역").font(W.font(13,.semibold))
                switch remoteReads.pointsState {
                case .idle:
                    WText(text:"조회 준비 중이에요.",small:true)
                case .loading:
                    HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"포인트 내역을 불러오는 중이에요.",small:true)}.frame(maxWidth:.infinity,minHeight:54,alignment:.leading)
                case .loaded(let snapshot):
                    remotePointsLedgerRows(snapshot.entries)
                    if snapshot.entries.isEmpty { WText(text:"원격 포인트 내역이 없어요.",small:true).accessibilityIdentifier("remotePointsEmpty") }
                    if snapshot.nextCursor != nil { remotePointsLoadMoreButton }
                case .loadingMore(let snapshot):
                    remotePointsLedgerRows(snapshot.entries)
                    HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"다음 내역을 불러오는 중이에요.",small:true)}
                case .failed(let failure):
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("remotePointsReadFailure")
                    if failure.canManuallyRetry { remotePointsRetryButton }
                case .failedLoadingMore(let snapshot,let failure):
                    remotePointsLedgerRows(snapshot.entries)
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("remotePointsReadFailure")
                    if failure.canManuallyRetry { remotePointsRetryButton }
                }
                WText(text:"읽기 전용 조회예요. 아래 내역은 이 기기에 저장된 예시 데이터예요.",small:true)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(W.soft,in:RoundedRectangle(cornerRadius:14)).accessibilityIdentifier("remotePointsLedgerPanel")
        }
    }

    private func remotePointsLedgerRows(_ entries:[PointsLedgerEntry])->some View {
        ScrollView {
            VStack(spacing:0){
                ForEach(entries){entry in
                    HStack(spacing:12){
                        VStack(alignment:.leading,spacing:4){
                            Text(entry.direction == .credit ? "포인트 적립":"포인트 사용").font(W.font(13,.medium))
                            Text(entry.createdAt.formatted(date:.abbreviated,time:.omitted)).font(W.font(11)).foregroundStyle(W.muted)
                        }
                        Spacer()
                        Text(entry.deltaPoints.formatted()).font(W.font(16,.semibold)).monospacedDigit()
                    }.frame(minHeight:56).overlay(alignment:.bottom){W.line.frame(height:1)}.accessibilityElement(children:.combine).accessibilityIdentifier("remotePointEntry-\(entry.entryID)")
                }
            }
        }.frame(maxHeight:220)
    }

    private var remotePointsRetryButton:some View {
        Button("다시 시도"){remoteReads.retryPoints()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("remotePointsRetry")
    }

    private var remotePointsLoadMoreButton:some View {
        Button("더 불러오기"){remoteReads.loadNextPointsPage()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("remotePointsLoadMore")
    }

    var points: some View {
        VStack(spacing: 0) {
            WHeader(title: "내 포인트", trailing: AnyView(
                Button { go("B02") } label: { Text("내역보기").font(W.font(14, .medium)).foregroundStyle(W.ink).frame(minWidth: 68, minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("openPointHistory")
            ))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if pointsStore.dataUnavailable { pointDataUnavailableNotice }
                    if remoteReads.hasPointsDependency { remotePointsBalancePanel }
                    WText(text:"화면 검토용 예시 잔액 · 상점 구매에 사용할 수 없어요",small:true)
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) { WPointsMark(size: 18); Text("화면 예시 잔액").font(W.font(15, .medium)).foregroundStyle(W.muted) }
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(pointsBalanceDisplay).font(W.font(44, .bold)).monospacedDigit().accessibilityIdentifier("pointBalance")
                                Text("포인트").font(W.font(17, .semibold)).foregroundStyle(W.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        Image("PrismArt").resizable().scaledToFit().frame(width: 96, height: 96).accessibilityHidden(true)
                    }.padding(.top, 14)
                    Button { go("SHOP") } label: {
                        Text("쇼핑하러 가기").font(W.font(15, .semibold)).foregroundStyle(MovTokens.onBrand).frame(maxWidth: .infinity, minHeight: 54)
                            .background(W.lime, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("browsePointShop")
                    VStack(alignment: .leading, spacing: 12) {
                        Button { go("B04") } label: {
                            HStack { Text("포인트 안내").font(W.font(16, .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(W.muted) }
                                .foregroundStyle(W.ink).padding(.horizontal, 16).frame(minHeight: 54)
                                .background(W.soft, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("pointGuideOverview")
                        ZStack {
                            W.soft
                            Text("입점 상품 광고 영역").font(W.font(13, .medium)).foregroundStyle(W.muted)
                            Text("광고").font(W.font(9)).foregroundStyle(W.muted).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                        }.frame(maxWidth: .infinity, minHeight: 156)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(W.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20).frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .top)
            }.accessibilityIdentifier("pointsOverviewScroll")
        }.background(W.paper)
    }

    var shop: some View {
        VStack(spacing: 0) {
            WHeader(title: "포인트 상점", back: { if ui.path.isEmpty { go("POINTS") } else { back() } })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if cosmeticStoreFixture {
                        WNotice(text:"격리된 UI 검증 fixture예요. 실제 계정이나 서버 포인트를 사용하지 않아요.")
                            .accessibilityIdentifier("cosmeticStoreFixtureBanner")
                    } else {
                        WText(text:"상점 잔액과 상품은 로그인한 계정의 서버 조회값이에요. 포인트 화면의 예시 잔액은 구매에 사용하지 않아요.",small:true)
                            .accessibilityIdentifier("cosmeticStoreServerNotice")
                    }
                    if let sessionNotice = cosmeticStoreFlow.sessionNotice {
                        WNotice(text:sessionNotice,danger:true).accessibilityIdentifier("cosmeticStoreSessionNotice")
                    }
                    ZStack {
                        W.soft
                        Text("입점 상품 광고 영역").font(W.font(12, .medium)).foregroundStyle(W.muted)
                        Text("광고").font(W.font(9)).foregroundStyle(W.muted).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                    }.frame(maxWidth: .infinity, minHeight: 76)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(W.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    HStack(spacing: 8) {
                        Text("계정 포인트").font(W.font(15, .medium))
                        Spacer()
                        WPointsMark(size: 22)
                        Group {
                            if let balance = cosmeticStoreFlow.balancePoints {
                                Text(balance.formatted()).accessibilityIdentifier("storeBalance")
                            } else {
                                Text("—").accessibilityIdentifier("storeBalance")
                            }
                        }.font(W.font(25, .semibold)).monospacedDigit()
                    }.padding(.horizontal, 16).frame(minHeight: 60)
                        .background(W.soft, in: RoundedRectangle(cornerRadius: 16))
                    if case .failed(let failure) = cosmeticStoreFlow.balanceState {
                        WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreBalanceFailure")
                    }
                    if let balanceNotice = cosmeticStoreFlow.balanceNotice {
                        WText(text:balanceNotice,small:true).accessibilityIdentifier("cosmeticStoreBalanceNotice")
                    }
                    VStack(alignment: .leading, spacing: 8) { WHeading(text: "나의 러닝에\n작은 변화를") }
                    GeometryReader { geometry in
                        HStack(spacing: 5) {
                            ForEach(WPointCategory.allCases) { category in
                                let fraction: CGFloat = category == .image ? 1.5 / 3.45 : category == .frame ? 0.75 / 3.45 : 1.2 / 3.45
                                Button { selectedPointCategory = category } label: {
                                    Text(category.rawValue).font(W.font(11, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                                        .padding(.horizontal, 5).frame(width: (geometry.size.width - 10) * fraction, height: 44)
                                        .foregroundStyle(selectedPointCategory == category ? MovTokens.onBrand : W.muted)
                                        .background(selectedPointCategory == category ? W.lime : W.soft, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).accessibilityIdentifier("shop-category-\(category == .image ? "image" : category == .frame ? "frame" : "face")")
                                    .accessibilityAddTraits(selectedPointCategory == category ? .isSelected : [])
                            }
                        }
                    }
                    .frame(height: 44)
                    if case .loading = cosmeticStoreFlow.catalogState, cosmeticStoreFlow.catalog == nil {
                        HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"상품을 불러오는 중이에요.",small:true)}
                            .accessibilityIdentifier("cosmeticStoreCatalogLoading")
                    }
                    if case .failed(let failure) = cosmeticStoreFlow.catalogState {
                        WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreCatalogFailure")
                        Button("상품 다시 불러오기") {
                            Task { await cosmeticStoreFlow.refreshShop(category:selectedPointCategory.storeCategory) }
                        }.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("cosmeticStoreRetry")
                    }
                    if cosmeticStoreFlow.catalog != nil {
                        if visiblePointProducts.isEmpty {
                            WText(text:"현재 판매 중인 상품이 없어요.",small:true).accessibilityIdentifier("emptyCosmeticStoreCatalog")
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 26) {
                                ForEach(visiblePointProducts) { product in
                                    Button {
                                        ui.selectedPointProductID = product.id
                                        go("B06")
                                    } label: {
                                        VStack(alignment: .leading, spacing: 7) {
                                            WPointProductArtwork(product: product).aspectRatio(WPointArtworkGeometry.listingAspect, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                                            Text(product.kind).font(W.font(11)).foregroundStyle(W.muted)
                                            Text(product.name).font(W.font(16, .semibold)).lineLimit(1)
                                            HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(product.price.formatted())").font(W.font(15, .semibold)); Text("포인트").font(W.font(11)) }
                                            if cosmeticStoreFlow.isOwned(product.id) { Text("보유 중").font(W.font(11, .medium)).foregroundStyle(W.muted) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).accessibilityIdentifier("shop-item-\(product.id)")
                                }
                            }
                        }
                    }
                    storeInventorySection
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .top)
            }
        }.background(W.paper)
    }

    @ViewBuilder var pointDetailRoute: some View {
        switch ui.screen {
        case "B02": pointHistory(empty: false)
        case "B03": pointHistory(empty: true)
        case "B04": pointGuide
        case "B05": shop
        case "B06": pointProductDetail
        case "B07": pointPurchaseComplete
        case "B08": pointShortage
        case "B09": pointEarningGuide
        case "B10": pointCardPreview
        default: points
        }
    }

    private var visiblePointProducts: [WPointProduct] {
        (cosmeticStoreFlow.catalog?.items ?? [])
            .filter { $0.category == selectedPointCategory.storeCategory }
            .map(WPointProduct.init)
    }

    private var selectedPointProduct: WPointProduct? {
        cosmeticStoreFlow.product(id:ui.selectedPointProductID).map(WPointProduct.init)
    }

    @ViewBuilder private var storeInventorySection: some View {
        VStack(alignment:.leading,spacing:14) {
            WHeading(text:"나의 보관함")
            if case .loading = cosmeticStoreFlow.inventoryState, cosmeticStoreFlow.inventory == nil {
                HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"보관함을 불러오는 중이에요.",small:true)}
                    .accessibilityIdentifier("cosmeticStoreInventoryLoading")
            }
            if case .failed(let failure) = cosmeticStoreFlow.inventoryState {
                WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreInventoryFailure")
            }
            if let equipment = cosmeticStoreFlow.equipment {
                VStack(spacing:0) {
                    ForEach(equipment.slots) { slot in
                        HStack(spacing:10) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(WPointCategory(storeCategory:slot.category).rawValue).font(W.font(13,.medium))
                                let equippedName = cosmeticStoreFlow.inventory?.items.first(where:{$0.productID==slot.productID})?.displayName
                                Text(slot.usesDefault ? "기본 디자인" : (equippedName ?? "장착 상품")).font(W.font(11)).foregroundStyle(W.muted)
                            }
                            Spacer()
                            if !slot.usesDefault {
                                Button("기본으로") {
                                    Task { await cosmeticStoreFlow.unequip(category:slot.category) }
                                }.font(W.font(12,.medium))
                                    .disabled(cosmeticStoreFlow.equipmentMutationCategory != nil)
                                    .accessibilityIdentifier("unequip-\(slot.category.rawValue)")
                            }
                        }.frame(minHeight:55).overlay(alignment:.bottom){W.line.frame(height:1)}
                    }
                }.accessibilityIdentifier("cosmeticStoreEquipment")
            } else if case .failed(let failure) = cosmeticStoreFlow.equipmentState {
                WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreEquipmentFailure")
            }
            if let failure = cosmeticStoreFlow.equipmentFailure {
                WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreEquipmentMutationFailure")
            }
            if let inventory = cosmeticStoreFlow.inventory {
                if inventory.items.isEmpty {
                    WText(text:"아직 보유한 상품이 없어요.",small:true).accessibilityIdentifier("emptyCosmeticStoreInventory")
                } else {
                    LazyVGrid(columns:[GridItem(.flexible(),spacing:16),GridItem(.flexible(),spacing:16)],spacing:20) {
                        ForEach(inventory.items) { item in
                            let product = WPointProduct(item)
                            VStack(alignment:.leading,spacing:8) {
                                WPointProductArtwork(product:product)
                                    .aspectRatio(WPointArtworkGeometry.listingAspect,contentMode:.fit)
                                    .clipShape(RoundedRectangle(cornerRadius:14))
                                Text(product.kind).font(W.font(11)).foregroundStyle(W.muted)
                                Text(product.name).font(W.font(15,.semibold)).lineLimit(1)
                                if cosmeticStoreFlow.isEquipped(item.productID,in:item.category) {
                                    Text("장착 중").font(W.font(11,.medium)).foregroundStyle(W.muted)
                                } else {
                                    Button("장착") {
                                        Task { await cosmeticStoreFlow.equip(productID:item.productID,to:item.category) }
                                    }.font(W.font(12,.medium))
                                        .disabled(cosmeticStoreFlow.equipmentMutationCategory != nil)
                                        .accessibilityIdentifier("equip-\(item.productID)")
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }.accessibilityIdentifier("cosmeticStoreInventory")
                }
            }
        }.padding(.top,10).accessibilityIdentifier("cosmeticStoreInventorySection")
    }

    private var emptyPointHistory: some View {
        VStack(spacing: 12) {
            Image("PrismPoint").resizable().scaledToFit().frame(width: 40, height: 40)
            Text("포인트 내역이 없어요").font(W.font(16, .semibold))
            WText(text: "내역이 생기면 이곳에 모아 보여드려요", small: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 75).accessibilityIdentifier("emptyPointHistory")
    }

    private func pointEntryRow(_ entry: WPointEntry) -> some View {
        HStack(spacing: 12) {
            Image(entry.kind == .earn ? "PrismEarned" : "PrismSpent").resizable().scaledToFit().frame(width: 24, height: 24)
                .accessibilityIdentifier(entry.kind == .earn ? "point-entry-earned-icon" : "point-entry-spent-icon")
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(W.font(13, .medium))
                HStack(spacing: 6) { Text(entry.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(W.font(11)); Text(entry.detail).font(W.font(11)) }.foregroundStyle(W.muted)
            }
            Spacer()
            Text("\(entry.amount >= 0 ? "+" : "−")\(abs(entry.amount).formatted())").font(W.font(17, .semibold)).monospacedDigit()
                .foregroundStyle(entry.amount >= 0 ? W.ink : W.muted)
                .accessibilityLabel("\(entry.amount >= 0 ? "더하기" : "빼기") \(abs(entry.amount).formatted()) 포인트")
        }.frame(minHeight: 62).overlay(alignment: .bottom) { W.line.frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("point-entry-row-\(entry.kind == .earn ? "earned" : "spent")")
    }

    private func pointHistory(empty: Bool) -> some View {
        VStack(spacing: 0) {
            WHeader(title: "포인트 내역", back: back)
            if remoteReads.hasPointsDependency { remotePointsLedgerPanel }
            WText(text:"화면 검토용 예시 내역 · 서버 원장과 별개예요",small:true).padding(.horizontal,20).padding(.top,12)
            if pointsStore.dataUnavailable {
                ScrollView { VStack(spacing: 14) { pointDataUnavailableNotice }.padding(.horizontal, 24).accessibilityIdentifier("unavailablePointHistoryScreen") }
            } else if empty || pointsStore.entries.isEmpty {
                ScrollView { VStack(spacing: 14) { emptyPointHistory }.padding(.horizontal, 24).accessibilityIdentifier("emptyPointHistoryScreen") }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        ForEach(WPointKind.allCases, id: \.self) { kind in
                            Button { selectedPointKind = kind } label: {
                                VStack(spacing: 9) { Text(kind.title).font(W.font(14, .medium)).foregroundStyle(W.ink); (selectedPointKind == kind ? W.lime : Color.clear).frame(height: 3) }
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8).accessibilityIdentifier("pointHistoryFilter")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(pointsStore.filteredEntries(selectedPointKind)) { pointEntryRow($0) }
                            if pointsStore.filteredEntries(selectedPointKind).isEmpty { emptyPointHistory }
                        }.padding(20)
                    }
                }
            }
        }.background(W.paper)
    }

    private var pointGuide: some View {
        WPage(title: "포인트 안내", back: back) {
            HStack(alignment: .top, spacing: 14) {
                WPointsMark(size: 34)
                Text("포인트로\n나의 러닝을 꾸며요").font(W.font(25, .bold)).lineSpacing(5)
            }.padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 0) {
                pointGuideRow("어디에 사용할 수 있나요?", "러닝 카드 배경과 프레임 같은 앱 안의 꾸미기 상품에 사용할 수 있어요.")
                W.line.frame(height: 1)
                pointGuideRow("어떻게 적립하나요?", "달리기 적립과 광고 보상 방식을 검토 중이에요. 적립 기준과 수량은 아직 정해지지 않았어요.")
                W.line.frame(height: 1)
                pointGuideRow("사용 전에 확인해 주세요", "구매한 꾸미기 상품은 계정에 영구 보유해요. 포인트로만 사용할 수 있고 환불은 제공하지 않아요.")
            }
        } actions: {
            Button("상점 둘러보기") { go("SHOP") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("browsePointShopFromGuide")
        }
    }

    private func pointGuideRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(W.font(14, .semibold))
            WText(text: detail, small: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
    }

    @ViewBuilder private var pointProductDetail: some View {
        if let product = selectedPointProduct {
            pointProductDetail(product)
        } else {
            WPage(title:"아이템",back:back) {
                if case .loading = cosmeticStoreFlow.productState {
                    HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"상품 정보를 불러오는 중이에요.",small:true)}
                        .accessibilityIdentifier("cosmeticStoreProductLoading")
                }
                if case .failed(let failure) = cosmeticStoreFlow.productState {
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreProductFailure")
                    Button("상품 다시 불러오기") {
                        Task { await cosmeticStoreFlow.refreshProduct(id:ui.selectedPointProductID) }
                    }.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("cosmeticStoreProductRetry")
                }
            } actions: { EmptyView() }
        }
    }

    private func pointProductDetail(_ product: WPointProduct) -> some View {
        let serverProduct = cosmeticStoreFlow.selectedProduct?.id == product.id ? cosmeticStoreFlow.selectedProduct : nil
        let owned = cosmeticStoreFlow.isOwned(product.id) || product.owned
        let enough = cosmeticStoreFlow.balancePoints.map { $0 >= product.price } ?? false
        let canPurchase = serverProduct.map(cosmeticStoreFlow.canPurchase) ?? false
        let failureMessage: String? = {
            if case .failed(let failure) = cosmeticStoreFlow.purchaseState { return failure.userMessage }
            if case .failed(let failure) = cosmeticStoreFlow.productState {
                switch failure {
                case .productUnavailable, .notFound: return failure.userMessage
                default: break
                }
            }
            return nil
        }()
        let purchaseLabel = owned ? "보유 중"
            : cosmeticStoreFlow.purchaseOutcomeUnknown ? "구매 결과 확인 필요"
            : cosmeticStoreFlow.isUnavailable(product.id) ? "판매 종료"
            : cosmeticStoreFlow.balancePoints == nil ? "잔액 확인 필요"
            : enough ? "구매하기" : "포인트 부족"

        return WPage(title: "아이템", back: back) {
            if cosmeticStoreFixture {
                WText(text:"격리된 UI 검증 상품이에요. 실제 구매와 잔액에는 영향이 없어요.",small:true)
                    .accessibilityIdentifier("cosmeticStoreFixtureBanner")
            }
            if let sessionNotice = cosmeticStoreFlow.sessionNotice {
                WNotice(text:sessionNotice,danger:true).accessibilityIdentifier("cosmeticStoreSessionNotice")
            }
            WPointProductArtwork(product: product, large: true).aspectRatio(WPointArtworkGeometry.detailAspect, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("pointProductArtwork")
            Text(product.name).font(W.font(22, .semibold))
            WText(text: product.kind, small: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) { Text("\(product.price.formatted())").font(W.font(23, .semibold)); Text("포인트").font(W.font(13)) }
            if let description = product.description { WText(text:description) }
            HStack { Text("계정 포인트"); Spacer(); Text(cosmeticStoreFlow.balancePoints?.formatted() ?? "—") }
                .font(W.font(13)).frame(minHeight:64).frame(maxWidth:.infinity,alignment:.leading)
                .accessibilityElement(children:.ignore).accessibilityLabel("계정 포인트")
                .accessibilityValue(cosmeticStoreFlow.balancePoints.map{"balance:\($0)"} ?? "unavailable")
                .accessibilityIdentifier("detailPointBalance")
            if let failureMessage {
                WNotice(text:failureMessage,danger:true).accessibilityIdentifier("cosmeticStorePurchaseFailure")
            }
            if case .outcomeUnknown(_,let failure) = cosmeticStoreFlow.purchaseState {
                WNotice(text:"\(failure.userMessage) 구매 여부를 확인할 때까지 다시 구매하지 않아요. 같은 요청으로 결과를 확인해 주세요.",danger:true)
                    .accessibilityIdentifier("cosmeticStorePurchaseOutcomeUnknown")
            }
            if let equipmentFailure = cosmeticStoreFlow.equipmentFailure {
                WNotice(text:equipmentFailure.userMessage,danger:true).accessibilityIdentifier("cosmeticStoreEquipmentMutationFailure")
            }
            if let balanceNotice = cosmeticStoreFlow.balanceNotice {
                WText(text:balanceNotice,small:true).accessibilityIdentifier("cosmeticStoreBalanceNotice")
            }
            if case .loading = cosmeticStoreFlow.productState {
                HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"서버 상품 정보를 확인하고 있어요.",small:true)}
                    .accessibilityIdentifier("cosmeticStoreProductLoading")
            }
        } actions: {
            HStack(spacing: 10) {
                Button("미리보기") { go("B10") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointPreview")
                Button(purchaseLabel) {
                    showingPointPurchaseConfirmation = true
                }.buttonStyle(WButtonStyle()).disabled(!canPurchase).accessibilityIdentifier("purchaseShopItem")
            }
            if cosmeticStoreFlow.purchaseOutcomeUnknown {
                Button("구매 결과 확인") {
                    Task { await cosmeticStoreFlow.resolveUnknownPurchase() }
                }.buttonStyle(WButtonStyle(kind:1)).disabled(cosmeticStoreFlow.purchaseInFlight)
                    .accessibilityIdentifier("resolveCosmeticStorePurchase")
            } else if !owned && cosmeticStoreFlow.balancePoints != nil && !enough {
                Button("포인트 부족 안내") { go("B08") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointShortageHelp")
            }
            if case .failed = cosmeticStoreFlow.productState {
                Button("상품 다시 불러오기") {
                    Task { await cosmeticStoreFlow.refreshProduct(id:ui.selectedPointProductID) }
                }.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("cosmeticStoreProductRetry")
            }
        }.confirmationDialog("구매를 확인할까요?", isPresented: $showingPointPurchaseConfirmation, titleVisibility: .visible) {
            Button("구매 확정", role: .destructive) {
                Task { await cosmeticStoreFlow.purchase(productID:product.id) }
            }.disabled(!canPurchase).accessibilityIdentifier("confirmPointPurchase")
            Button("취소", role: .cancel) {}.accessibilityIdentifier("cancelPointPurchase")
        } message: {
            Text("\(product.price.formatted())P를 사용해요. 상품은 계정에 영구 보유되고 환불할 수 없어요.")
        }
    }

    private var pointPurchaseComplete: some View {
        WPage(title: "구매 결과", back: back) {
            if let receipt = cosmeticStoreFlow.purchaseReceipt {
                VStack(spacing:14) {
                    Text("구매 완료").font(W.font(20,.semibold)).multilineTextAlignment(.center)
                    Text(cosmeticStoreFlow.product(id:receipt.productID)?.displayName ?? selectedPointProduct?.name ?? "꾸미기 상품")
                        .font(W.font(16,.medium))
                }.frame(maxWidth:.infinity).padding(.vertical,24)
                WRow(title:"구매에 사용한 포인트",value:"\(receipt.purchasePricePoints.formatted())P")
                WRow(title:"구매 당시 잔액",value:"\(receipt.balanceAfterPoints.formatted())P")
                if let currentBalance = cosmeticStoreFlow.balancePoints, currentBalance != receipt.balanceAfterPoints {
                    WRow(title:"현재 계정 잔액",value:"\(currentBalance.formatted())P",separator:false)
                    if let balanceNotice = cosmeticStoreFlow.balanceNotice { WText(text:balanceNotice,small:true) }
                }
                if receipt.replayed {
                    WText(text:"같은 구매 요청의 영수증을 확인했어요. 포인트를 다시 차감하지 않았어요.",small:true)
                        .accessibilityIdentifier("cosmeticStorePurchaseReplay")
                }
            } else if cosmeticStoreFlow.purchaseOutcomeUnknown {
                WNotice(text:"구매 결과를 아직 확인할 수 없어요. 구매를 다시 보내지 않았어요.",danger:true)
                    .accessibilityIdentifier("cosmeticStorePurchaseOutcomeUnknown")
            } else {
                WNotice(text:"확인된 구매 결과가 없어요. 상점 정보를 새로 불러와 주세요.",danger:true)
            }
        } actions: {
            Button("상점으로") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("backToShop")
        }
    }

    private var pointShortage: some View {
        WPage(title: "포인트 부족", back: back) {
            if let product = selectedPointProduct, let balance = cosmeticStoreFlow.balancePoints {
                WHeading(text: "포인트가 부족해요")
                WText(text: "\(product.name)을 구매하려면 포인트가 더 필요해요.")
                WRow(title: "계정 포인트", value: "\(balance.formatted())P", separator: false)
                WRow(title: "필요 포인트", value: "\(product.price.formatted())P", separator: false)
                WRow(title: "부족한 포인트", value: "\(max(0, product.price - balance).formatted())P", separator: false)
                    .accessibilityIdentifier("pointShortageAmount")
            } else {
                WNotice(text:"계정 잔액을 불러올 수 없어 부족한 포인트를 계산하지 못했어요.",danger:true)
            }
        } actions: {
            Button("확인") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("backToShop")
        }
    }

    private var pointEarningGuide: some View {
        WPage(title: "포인트 받는 방법", back: back) {
            Text("달리기와 함께\n준비하고 있어요").font(W.font(27, .bold)).lineSpacing(5).padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                Text("달리기로 모으기").font(W.font(15, .semibold))
                WText(text: "달린 양에 따라 적립하는 방식을 검토하고 있어요.", small: true)
                WText(text: "기준·적립량 미정", small: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            W.line.frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("광고 보고 받기").font(W.font(15, .semibold))
                WText(text: "광고 보상 방식과 사용할 수 있는 곳을 검토하고 있어요.", small: true)
                WText(text: "준비 중 · 광고 재생 없음", small: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            WText(text: "포인트는 구매할 수 없어요. 기본 사용처는 앱 내 꾸미기이며, 적립·보상 세부 정책은 확정 후 안내할 예정이에요.", small: true)
        } actions: { EmptyView() }
    }

    private var pointCardPreview: some View {
        WPage(title: "미리보기", back: back) {
            if let product = selectedPointProduct {
                Text("\(product.name) 적용 예시").font(W.font(14)).foregroundStyle(W.muted)
                runnerIdentityCard(decorationID:product.id)
                WText(text: "미리보기예요. 장착하거나 구매해도 현재 러닝 카드에는 적용되지 않아요.", small: true)
            } else {
                WNotice(text:"상품 미리보기를 찾을 수 없어요. 상점에서 다시 선택해 주세요.",danger:true)
            }
        } actions: {
            Button("아이템으로 돌아가기") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("previewBackToShop")
        }
    }

}

private struct WPointsMark: View {
    var size: CGFloat = 20
    var body: some View {
        Image("PrismPoint").resizable().renderingMode(.original).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct WPointProductArtwork: View {
    let product: WPointProduct
    var large = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                W.soft
                if product.category == .face {
                    profileArtwork
                } else {
                    let cardSize = WPointArtworkGeometry.cardSize(in: size, large: large)
                    cardArtwork(width: cardSize.width, height: cardSize.height)
                }
            }.frame(width: size.width, height: size.height)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(product.name) 예시 아이템 미리보기")
            .accessibilityIdentifier("pointArtwork-\(product.id)")
    }

    private var accent: Color {
        guard let value = product.previewData.accentColor,
              let rgb = UInt32(value.dropFirst(),radix:16) else { return W.lime }
        return Color(
            red:Double((rgb >> 16) & 0xff)/255,
            green:Double((rgb >> 8) & 0xff)/255,
            blue:Double(rgb & 0xff)/255
        )
    }

    private func cardArtwork(width: CGFloat, height: CGFloat) -> some View {
        let cardWidth = max(0, width)
        let cardHeight = max(0, height)
        let radius: CGFloat = large ? 12 : 8
        let markSize: CGFloat = large ? 20 : 11
        let strokeScale = min(cardWidth / 240, cardHeight / 140)
        return ZStack(alignment: .topLeading) {
            W.paper
            if product.category == .frame {
                RoundedRectangle(cornerRadius: radius).stroke(accent, lineWidth: 3)
            } else {
                WPointPath()
                    .stroke(accent.opacity(0.78), style: StrokeStyle(lineWidth: 14 * strokeScale, lineCap: .round))
                    .frame(width: cardWidth, height: cardHeight)
            }
            BrandMark(size: markSize).frame(width: markSize, height: markSize).padding(.leading, large ? 16 : 10).padding(.top, large ? 14 : 9)
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 1).fill(W.ink.opacity(0.8)).frame(width: 29, height: 3)
                RoundedRectangle(cornerRadius: 1).fill(W.ink.opacity(0.25)).frame(width: 18, height: 3)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 11).padding(.bottom, 8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: .black.opacity(0.04), radius: 6.5, y: 3.5)
        .rotationEffect(.degrees(product.category == .image ? 4 : 0))
    }

    private var profileArtwork: some View {
        let diameter: CGFloat = large ? 124 : 75
        let ringWidth: CGFloat = large ? 5 : 3
        let innerDiameter: CGFloat = large ? 103 : 59
        let iconSize: CGFloat = large ? 45 : 28
        let dotDiameter: CGFloat = large ? 14 : 9
        let markerDiameter = dotDiameter + 6
        return ZStack {
            Circle().stroke(accent, lineWidth: ringWidth).frame(width: diameter, height: diameter)
            Circle().fill(W.paper).frame(width: innerDiameter, height: innerDiameter)
            WPointProfileGlyph().stroke(W.muted, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: iconSize, height: iconSize).rotationEffect(.degrees(12))
            ForEach(0..<3) { index in
                Circle().fill(accent).frame(width: dotDiameter, height: dotDiameter)
                    .overlay(Circle().stroke(W.soft, lineWidth: 3))
                    .position(markerPosition(index, diameter: diameter, markerDiameter: markerDiameter, large: large))
            }
        }.frame(width: diameter, height: diameter).rotationEffect(.degrees(-12))
    }

    private func markerPosition(_ index: Int, diameter: CGFloat, markerDiameter: CGFloat, large: Bool) -> CGPoint {
        switch index {
        case 0: CGPoint(x: markerDiameter / 2 - 4, y: 8 + markerDiameter / 2)
        case 1: CGPoint(x: diameter - markerDiameter / 2 + 4, y: 8 + markerDiameter / 2)
        default: CGPoint(x: (large ? 48 : 26) + markerDiameter / 2, y: diameter + 8 - markerDiameter / 2)
        }
    }
}

private struct WPointPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -10, y: 100))
        path.addCurve(to: CGPoint(x: 62, y: 59), control1: CGPoint(x: 62, y: 159), control2: CGPoint(x: 103, y: 79))
        path.addCurve(to: CGPoint(x: 145, y: 37), control1: CGPoint(x: 21, y: 39), control2: CGPoint(x: 72, y: -10))
        path.addCurve(to: CGPoint(x: 241, y: 112), control1: CGPoint(x: 218, y: 84), control2: CGPoint(x: 134, y: 131))
        let scale = min(rect.width / 240, rect.height / 140)
        var transformed = Path()
        transformed.addPath(path, transform: CGAffineTransform(translationX: (rect.width - 240 * scale) / 2, y: (rect.height - 140 * scale) / 2).scaledBy(x: scale, y: scale))
        return transformed
    }
}

private struct WPointProfileGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 24, rect.height / 24)
        let x = (rect.width - 24 * scale) / 2, y = (rect.height - 24 * scale) / 2
        let t = CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
        var path = Path()
        path.addEllipse(in: CGRect(x: 8.5, y: 3.5, width: 7, height: 7))
        path.move(to: CGPoint(x: 5, y: 21)); path.addLine(to: CGPoint(x: 5, y: 19))
        path.addCurve(to: CGPoint(x: 12, y: 12), control1: CGPoint(x: 5, y: 15.134), control2: CGPoint(x: 8.134, y: 12))
        path.addCurve(to: CGPoint(x: 19, y: 19), control1: CGPoint(x: 15.866, y: 12), control2: CGPoint(x: 19, y: 15.134))
        path.addLine(to: CGPoint(x: 19, y: 21)); path.closeSubpath()
        return path.applying(t)
    }
}

#if DEBUG
/// In-memory API fixture for focused MovUITestHost runs. The launch policy
/// creates it only from a review launch with a UUID-scoped defaults suite.
actor WireframeCosmeticStoreFixture: CosmeticStoreServing, PointsWalletReading, RunUploadSessionProviding {
    private struct Seed: Sendable {
        let id: String
        let name: String
        let description: String
        let category: CosmeticStoreCategory
        let price: Int64
        let assetID: String
        let accent: String
    }

    private let seeds: [Seed] = [
        Seed(id:"101",name:"모브 라인",description:"가볍게 이어지는 선으로 러닝 카드의 분위기를 바꿔 보세요.",category:.runCardBackground,price:400,assetID:"card_line",accent:"#AABBCC"),
        Seed(id:"102",name:"새벽의 길",description:"밝은 여백과 둥근 코스로 표현한 러닝 카드 배경이에요.",category:.runCardBackground,price:900,assetID:"card_dawn",accent:"#88AA99"),
        Seed(id:"201",name:"라임 라인",description:"러닝 카드 가장자리를 얇은 라임 선으로 꾸며 보세요.",category:.runCardFrame,price:700,assetID:"frame_lime",accent:"#AABBCC"),
        Seed(id:"301",name:"페이스 프레임",description:"페이스 화면에 작은 움직임을 더하는 장식이에요.",category:.paceFrame,price:1_600,assetID:"pace_frame",accent:"#88AA99")
    ]
    private let unavailableFirstProduct: Bool
    private let hideUnavailableFirstProduct: Bool
    private let loseFirstPurchaseResponse: Bool
    private let balanceAdjustment: Int64
    private let changesAccountAfterPurchase: Bool
    private var lostResponseConsumed = false
    private var balance: Int64
    private var ownerID = "fixture-member-101"
    private var nextPurchaseID: Int64 = 9001
    private var inventoryItems: [CosmeticStoreInventoryItem] = []
    private var equipmentByCategory: [CosmeticStoreCategory:String] = [:]
    private var receiptsByKey: [String:(productID:String,receipt:CosmeticStorePurchaseReceipt)] = [:]

    init(arguments: [String]) {
        unavailableFirstProduct = arguments.contains("-wire-cosmetic-store-sale-stopped")
            || arguments.contains("-wire-cosmetic-store-sale-stopped-on-detail")
        hideUnavailableFirstProduct = arguments.contains("-wire-cosmetic-store-sale-stopped")
        loseFirstPurchaseResponse = arguments.contains("-wire-cosmetic-store-lost-response-once")
        balanceAdjustment = arguments.contains("-wire-cosmetic-store-balance-changed") ? 25 : 0
        changesAccountAfterPurchase = arguments.contains("-wire-cosmetic-store-account-switch-on-purchase")
        balance = arguments.contains("-wire-cosmetic-store-insufficient") ? 100 : 1_475
    }

    func currentSession() async throws -> RunUploadSession? {
        RunUploadSession(ownerID:ownerID,accessToken:"fixture-store-token")
    }

    func fetchCatalog(category: CosmeticStoreCategory?) async throws -> CosmeticStoreCatalog {
        let available = seeds.filter { seed in
            !(hideUnavailableFirstProduct && seed.id=="101")
                && (category == nil || category == seed.category)
        }
        return CosmeticStoreCatalog(items:available.map(makeProduct))
    }

    func fetchProduct(id: String) async throws -> CosmeticStoreProduct {
        guard let seed=seed(for:id), !(unavailableFirstProduct && id=="101") else {
            throw CosmeticStoreFailure.notFound(requestID:"fixture-store-not-found")
        }
        return makeProduct(seed)
    }

    func fetchInventory() async throws -> CosmeticStoreInventory {
        CosmeticStoreInventory(items:inventoryItems)
    }

    func fetchBalance() async throws -> PointsBalance {
        PointsBalance(balancePoints:balance)
    }

    func fetchEntries(cursor: String?, size: Int) async throws -> PointsLedgerPage {
        PointsLedgerPage(entries:[],nextCursor:nil)
    }

    func fetchEquipment() async throws -> CosmeticEquipment {
        CosmeticEquipment(slots:CosmeticStoreCategory.allCases.map { category in
            let productID=equipmentByCategory[category]
            return CosmeticEquipmentSlot(category:category,productID:productID,usesDefault:productID == nil)
        })
    }

    func purchase(productID: String, idempotencyKey: String) async throws -> CosmeticStorePurchaseReceipt {
        if let replay=receiptsByKey[idempotencyKey] {
            guard replay.productID==productID else {
                throw CosmeticStoreFailure.idempotencyConflict(requestID:"fixture-store-key-conflict")
            }
            let receipt=replay.receipt
            return CosmeticStorePurchaseReceipt(
                purchaseID:receipt.purchaseID,productID:receipt.productID,
                purchasePricePoints:receipt.purchasePricePoints,balanceAfterPoints:receipt.balanceAfterPoints,
                purchasedAt:receipt.purchasedAt,replayed:true
            )
        }
        guard let seed=seed(for:productID), !(unavailableFirstProduct && productID=="101") else {
            throw CosmeticStoreFailure.productUnavailable(requestID:"fixture-store-unavailable")
        }
        guard !inventoryItems.contains(where:{$0.productID==productID}) else {
            throw CosmeticStoreFailure.alreadyOwned(requestID:"fixture-store-owned")
        }
        guard balance >= seed.price else {
            throw CosmeticStoreFailure.insufficientPoints(requestID:"fixture-store-insufficient")
        }

        balance = balance - seed.price + balanceAdjustment
        let receipt=CosmeticStorePurchaseReceipt(
            purchaseID:String(nextPurchaseID),productID:productID,purchasePricePoints:seed.price,
            balanceAfterPoints:balance,purchasedAt:"2026-10-17T08:30:00+09:00",replayed:false
        )
        nextPurchaseID += 1
        inventoryItems.append(CosmeticStoreInventoryItem(
            purchaseID:receipt.purchaseID,productID:productID,category:seed.category,displayName:seed.name,
            description:seed.description,purchasePricePoints:seed.price,balanceAfterPoints:balance,
            previewData:preview(for:seed),purchasedAt:receipt.purchasedAt
        ))
        receiptsByKey[idempotencyKey]=(productID,receipt)
        if loseFirstPurchaseResponse && !lostResponseConsumed {
            lostResponseConsumed=true
            throw CosmeticStoreFailure.transport(.networkConnectionLost)
        }
        if changesAccountAfterPurchase { ownerID="fixture-member-202" }
        return receipt
    }

    func equip(productID: String, to category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        guard let item=inventoryItems.first(where:{$0.productID==productID}) else {
            throw CosmeticStoreFailure.notFound(requestID:"fixture-store-not-owned")
        }
        guard item.category==category else {
            throw CosmeticStoreFailure.categoryMismatch(requestID:"fixture-store-category")
        }
        let changed=equipmentByCategory[category] != productID
        equipmentByCategory[category]=productID
        return CosmeticEquipmentChange(category:category,productID:productID,usesDefault:false,changed:changed)
    }

    func unequip(category: CosmeticStoreCategory) async throws -> CosmeticEquipmentChange {
        let changed=equipmentByCategory.removeValue(forKey:category) != nil
        return CosmeticEquipmentChange(category:category,productID:nil,usesDefault:true,changed:changed)
    }

    private func makeProduct(_ seed: Seed) -> CosmeticStoreProduct {
        CosmeticStoreProduct(
            id:seed.id,category:seed.category,displayName:seed.name,description:seed.description,
            pricePoints:seed.price,previewData:preview(for:seed),
            owned:inventoryItems.contains(where:{$0.productID==seed.id})
        )
    }

    private func preview(for seed: Seed) -> CosmeticPreviewData {
        CosmeticPreviewData(version:1,assetID:seed.assetID,accentColor:seed.accent)
    }

    private func seed(for id: String) -> Seed? {
        seeds.first(where:{$0.id==id})
    }
}
#endif
