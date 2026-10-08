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
    let description: String
    let category: WPointCategory
    let price: Int

    static let catalog: [WPointProduct] = [
        .init(id: "line", name: "모브 라인", kind: "러닝 카드 배경", description: "가볍게 이어지는 선으로 러닝 카드의 분위기를 바꿔 보세요.", category: .image, price: 400),
        .init(id: "dawn", name: "새벽의 길", kind: "러닝 카드 배경", description: "밝은 여백과 둥근 코스로 표현한 러닝 카드 배경이에요.", category: .image, price: 900),
        .init(id: "card-frame", name: "라임 라인", kind: "러닝 카드 프레임", description: "러닝 카드 가장자리를 얇은 라임 선으로 꾸며 보세요.", category: .frame, price: 700),
        .init(id: "frame", name: "페이스 프레임", kind: "프로필 장식", description: "프로필 사진 가장자리에 작은 움직임을 더하는 장식이에요.", category: .face, price: 1_600)
    ]
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

    func canPurchase(_ product: WPointProduct) -> Bool {
        !dataUnavailable && balance >= product.price && !ownedItemIDs.contains(product.id)
    }

    @discardableResult func purchase(_ product: WPointProduct, at date: Date = Date()) -> Bool {
        guard canPurchase(product) else { return false }
        balance -= product.price
        ownedItemIDs.insert(product.id)
        entries.insert(WPointEntry(title: product.name, detail: "로컬 구매 예시", amount: -product.price, date: date), at: 0)
        guard persist() else {
            balance += product.price
            ownedItemIDs.remove(product.id)
            entries.removeFirst()
            dataUnavailable = true
            return false
        }
        return true
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

    var points: some View {
        VStack(spacing: 0) {
            WHeader(title: "내 포인트", trailing: AnyView(
                Button { go("B02") } label: { Text("내역보기").font(W.font(14, .medium)).foregroundStyle(W.ink).frame(minWidth: 68, minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("openPointHistory")
            ))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if pointsStore.dataUnavailable { pointDataUnavailableNotice }
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) { WPointsMark(size: 18); Text("보유 포인트").font(W.font(15, .medium)).foregroundStyle(W.muted) }
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
                    if pointsStore.dataUnavailable { pointDataUnavailableNotice }
                    ZStack {
                        W.soft
                        Text("입점 상품 광고 영역").font(W.font(12, .medium)).foregroundStyle(W.muted)
                        Text("광고").font(W.font(9)).foregroundStyle(W.muted).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                    }.frame(maxWidth: .infinity, minHeight: 76)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(W.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    HStack(spacing: 8) {
                        Text("보유 포인트").font(W.font(15, .medium))
                        Spacer()
                        WPointsMark(size: 22)
                        Text(pointsBalanceDisplay).font(W.font(25, .semibold)).monospacedDigit()
                    }.padding(.horizontal, 16).frame(minHeight: 60)
                        .background(W.soft, in: RoundedRectangle(cornerRadius: 16))
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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 26) {
                        ForEach(visiblePointProducts) { product in
                            Button { ui.selectedPointProductID = product.id; go("B06") } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    WPointProductArtwork(product: product).aspectRatio(WPointArtworkGeometry.listingAspect, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                                    Text(product.kind).font(W.font(11)).foregroundStyle(W.muted)
                                    Text(product.name).font(W.font(16, .semibold)).lineLimit(1)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(product.price.formatted())").font(W.font(15, .semibold)); Text("포인트").font(W.font(11)) }
                                    if pointsStore.ownedItemIDs.contains(product.id) { Text("보유 중").font(W.font(11, .medium)).foregroundStyle(W.muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityIdentifier("shop-item-\(product.id)")
                        }
                    }
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
        WPointProduct.catalog.filter { $0.category == selectedPointCategory }
    }

    private var selectedPointProduct: WPointProduct {
        WPointProduct.catalog.first(where: { $0.id == ui.selectedPointProductID }) ?? WPointProduct.catalog[0]
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
    }

    private func pointHistory(empty: Bool) -> some View {
        VStack(spacing: 0) {
            WHeader(title: "포인트 내역", back: back)
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
                pointGuideRow("어디에 사용할 수 있나요?", "러닝 카드 배경과 프로필 장식 같은 앱 꾸미기 아이템을 검토하고 있어요.")
                W.line.frame(height: 1)
                pointGuideRow("어떻게 적립하나요?", "달리기 적립과 광고 보상 방식을 검토 중이에요. 적립 기준과 수량은 아직 정해지지 않았어요.")
                W.line.frame(height: 1)
                pointGuideRow("사용 전에 확인해 주세요", "유효기간과 사용 조건, 교환 약관은 확정 후 안내할 예정이에요. 지금 보이는 잔액과 가격은 화면 검토용 예시예요.")
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

    private var pointProductDetail: some View {
        let product = selectedPointProduct
        let owned = pointsStore.ownedItemIDs.contains(product.id)
        let enough = pointsStore.canPurchase(product)
        return WPage(title: "아이템", back: back) {
            if pointsStore.dataUnavailable { pointDataUnavailableNotice }
            WPointProductArtwork(product: product, large: true).aspectRatio(WPointArtworkGeometry.detailAspect, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("pointProductArtwork")
            Text(product.name).font(W.font(22, .semibold))
            WText(text: product.kind, small: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) { Text("\(product.price.formatted())").font(W.font(23, .semibold)); Text("포인트").font(W.font(13)) }
            WText(text: product.description)
            HStack { Text("보유 포인트"); Spacer(); Text(pointsBalanceDisplay) }
                .font(W.font(13)).frame(minHeight:64).frame(maxWidth:.infinity,alignment:.leading)
                .accessibilityElement(children:.ignore).accessibilityLabel("보유 포인트")
                .accessibilityValue(pointsStore.dataUnavailable ? "unavailable" : "balance:\(pointsStore.balance)|entries:\(pointsStore.entries.count)")
                .accessibilityIdentifier("detailPointBalance")
        } actions: {
            HStack(spacing: 10) {
                Button("미리보기") { go("B10") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointPreview")
                Button(pointsStore.dataUnavailable ? "저장 데이터 확인 불가" : owned ? "보유 중" : enough ? "구매하기" : "포인트 부족") {
                    showingPointPurchaseConfirmation = true
                }.buttonStyle(WButtonStyle()).disabled(owned || !enough).accessibilityIdentifier("purchaseShopItem")
            }
            if !pointsStore.dataUnavailable && !owned && !enough {
                Button("포인트 부족 안내") { go("B08") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointShortageHelp")
            }
        }.confirmationDialog("가상 포인트를 사용할까요?", isPresented: $showingPointPurchaseConfirmation, titleVisibility: .visible) {
            Button("구매 예시 확인", role: .destructive) {
                if pointsStore.purchase(product) { go("B07") }
                else { go("B08") }
            }.accessibilityIdentifier("confirmPointPurchase")
            Button("취소", role: .cancel) {}.accessibilityIdentifier("cancelPointPurchase")
        } message: {
            Text("\(product.price.formatted())P를 이 기기의 예시 잔액에서 차감합니다. 실제 결제는 없어요.")
        }
    }

    private var pointPurchaseComplete: some View {
        WPage(title: "구매 결과", back: back) {
            if pointsStore.dataUnavailable {
                pointDataUnavailableNotice
            } else {
            VStack(spacing: 14) {
                Text("구매 완료 예시").font(W.font(20, .semibold)).multilineTextAlignment(.center)
                Text(selectedPointProduct.name).font(W.font(16, .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
            WRow(title: "보유 포인트", value: "\((pointsStore.balance + selectedPointProduct.price).formatted())")
            WRow(title: "필요 포인트 · 예시", value: "\(selectedPointProduct.price.formatted())")
            WRow(title: "사용 후 잔액 · 예시", value: "\(pointsStore.balance.formatted())", separator: false)
            WText(text: "샘플 구매 결과예요. 실제 서버 결제나 상품 지급은 없어요.", small: true)
            }
        } actions: {
            Button("확인") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("backToShop")
        }
    }

    private var pointShortage: some View {
        WPage(title: "포인트 부족", back: back) {
            if pointsStore.dataUnavailable {
                pointDataUnavailableNotice
            } else {
                WHeading(text: "포인트가 부족해요")
                WText(text: "\(selectedPointProduct.name)을 구매하려면 포인트가 더 필요해요.")
                WRow(title: "보유 포인트", value: "\(pointsStore.balance.formatted())P", separator: false)
                WRow(title: "필요 포인트", value: "\(selectedPointProduct.price.formatted())P", separator: false)
                WRow(title: "부족한 포인트", value: "\(max(0, selectedPointProduct.price - pointsStore.balance).formatted())P", separator: false)
                    .accessibilityIdentifier("pointShortageAmount")
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
        return WPage(title: "미리보기", back: back) {
            Text("\(selectedPointProduct.name) 적용 예시").font(W.font(14)).foregroundStyle(W.muted)
            runnerIdentityCard(decorationID:selectedPointProduct.id)
            WText(text: "현재 러닝 카드는 바뀌지 않아요", small: true)
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

    private func cardArtwork(width: CGFloat, height: CGFloat) -> some View {
        let cardWidth = max(0, width)
        let cardHeight = max(0, height)
        let radius: CGFloat = large ? 12 : 8
        let markSize: CGFloat = large ? 20 : 11
        let strokeScale = min(cardWidth / 240, cardHeight / 140)
        return ZStack(alignment: .topLeading) {
            W.paper
            if product.id == "card-frame" {
                RoundedRectangle(cornerRadius: radius).stroke(W.lime, lineWidth: 3)
            } else {
                WPointPath(productID: product.id)
                    .stroke(W.lime.opacity(product.id == "dawn" ? 0.45 : 0.9), style: StrokeStyle(lineWidth: (product.id == "line" ? 11 : 18) * strokeScale, lineCap: .round))
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
        .rotationEffect(.degrees(product.id == "line" ? 4 : product.id == "dawn" ? -4 : 0))
    }

    private var profileArtwork: some View {
        let diameter: CGFloat = large ? 124 : 75
        let ringWidth: CGFloat = large ? 5 : 3
        let innerDiameter: CGFloat = large ? 103 : 59
        let iconSize: CGFloat = large ? 45 : 28
        let dotDiameter: CGFloat = large ? 14 : 9
        let markerDiameter = dotDiameter + 6
        return ZStack {
            Circle().stroke(W.lime, lineWidth: ringWidth).frame(width: diameter, height: diameter)
            Circle().fill(W.paper).frame(width: innerDiameter, height: innerDiameter)
            WPointProfileGlyph().stroke(W.muted, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: iconSize, height: iconSize).rotationEffect(.degrees(12))
            ForEach(0..<3) { index in
                Circle().fill(W.lime).frame(width: dotDiameter, height: dotDiameter)
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
    let productID: String
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if productID == "line" {
            path.move(to: CGPoint(x: -15, y: 121))
            path.addCurve(to: CGPoint(x: 91, y: 28), control1: CGPoint(x: 45, y: 121), control2: CGPoint(x: 15, y: 28))
            path.addCurve(to: CGPoint(x: 218, y: 52), control1: CGPoint(x: 167, y: 28), control2: CGPoint(x: 147, y: 113))
            path.addCurve(to: CGPoint(x: 265, y: 73), control1: CGPoint(x: 289, y: -9), control2: CGPoint(x: 265, y: 73))
        } else {
            path.move(to: CGPoint(x: -10, y: 100))
            path.addCurve(to: CGPoint(x: 62, y: 59), control1: CGPoint(x: 62, y: 159), control2: CGPoint(x: 103, y: 79))
            path.addCurve(to: CGPoint(x: 145, y: 37), control1: CGPoint(x: 21, y: 39), control2: CGPoint(x: 72, y: -10))
            path.addCurve(to: CGPoint(x: 241, y: 112), control1: CGPoint(x: 218, y: 84), control2: CGPoint(x: 134, y: 131))
        }
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
