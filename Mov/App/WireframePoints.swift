import SwiftUI
import Observation

enum WPointKind: String, Codable, CaseIterable, Hashable {
    case all, earn, use
    var title: String { switch self { case .all: "전체"; case .earn: "적립"; case .use: "사용" } }
}

struct WPointEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var amount: Int
    var date: Date
    var kind: WPointKind { amount >= 0 ? .earn : .use }
}

enum WPointCategory: String, CaseIterable, Identifiable, Equatable {
    case all = "전체", shard = "프리즘 샤드", card = "러닝 카드"
    var id: String { rawValue }
}

struct WPointProduct: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let category: WPointCategory
    let price: Int
    let palette: Int

    static let catalog: [WPointProduct] = [
        .init(id: "dawn", name: "새벽빛 샤드", subtitle: "러닝 카드 장식", category: .shard, price: 500, palette: 0),
        .init(id: "tide", name: "물결빛 샤드", subtitle: "러닝 카드 장식", category: .shard, price: 900, palette: 1),
        .init(id: "aurora", name: "오로라 카드", subtitle: "러닝 카드 테마", category: .card, price: 1_200, palette: 2),
        .init(id: "forest", name: "숲의 카드", subtitle: "러닝 카드 테마", category: .card, price: 1_600, palette: 3)
    ]
}

@MainActor @Observable final class WPointsStore {
    private let defaults: UserDefaults
    private let key = "mov.points.local.v1"
    private struct Saved: Codable {
        var balance: Int
        var entries: [WPointEntry]
        var owned: Set<String>
    }

    var balance: Int
    var entries: [WPointEntry]
    var ownedItemIDs: Set<String>

    init(defaults: UserDefaults = .standard, insufficientFixture: Bool = false, emptyFixture: Bool = false) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            balance = saved.balance
            entries = saved.entries
            ownedItemIDs = saved.owned
        } else {
            let calendar = Calendar(identifier: .gregorian)
            let base = ISO8601DateFormatter().date(from: "2026-10-01T09:00:00+09:00") ?? Date()
            balance = 1_200
            entries = [
                WPointEntry(title: "예시 적립", amount: 1_000, date: base),
                WPointEntry(title: "예시 적립", amount: 500, date: calendar.date(byAdding: .day, value: -2, to: base) ?? base),
                WPointEntry(title: "예시 사용", amount: -300, date: calendar.date(byAdding: .day, value: -4, to: base) ?? base)
            ]
            ownedItemIDs = []
            persist()
        }
        if insufficientFixture { balance = 100 }
        if emptyFixture { balance = 0; entries = []; ownedItemIDs = [] }
    }

    func canPurchase(_ product: WPointProduct) -> Bool {
        balance >= product.price && !ownedItemIDs.contains(product.id)
    }

    @discardableResult func purchase(_ product: WPointProduct, at date: Date = Date()) -> Bool {
        guard canPurchase(product) else { return false }
        balance -= product.price
        ownedItemIDs.insert(product.id)
        entries.insert(WPointEntry(title: "로컬 예시 구매 · \(product.name)", amount: -product.price, date: date), at: 0)
        persist()
        return true
    }

    func filteredEntries(_ kind: WPointKind) -> [WPointEntry] {
        kind == .all ? entries : entries.filter { $0.kind == kind }
    }

    private func persist() {
        let saved = Saved(balance: balance, entries: entries, owned: ownedItemIDs)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: key)
    }
}

extension WireframeRoot {
    func returnToPointShop() {
        ui.path.removeAll()
        ui.screen = "POINTS"
        ui.rootIndex = 0
        ui.previousRootIndex = 0
        go("SHOP")
    }

    var points: some View {
        VStack(spacing: 0) {
            WHeader(title: "포인트", root: true, trailing: AnyView(
                Button { go("SHOP") } label: {
                    WShopIcon().stroke(W.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 24, height: 24).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("상점").accessibilityIdentifier("openShop")
            ))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("내 포인트").font(W.font(22, .semibold))
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(pointsStore.balance.formatted()).font(W.font(40, .bold)).monospacedDigit().accessibilityIdentifier("pointBalance")
                            Text("P").font(W.font(17, .semibold)).foregroundStyle(W.muted)
                        }
                        WText(text: "가상 예시 잔액 · 실제 포인트와 연결되지 않아요", small: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .background(W.soft, in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 10) {
                        Button { go("SHOP") } label: { Label("상점 둘러보기", systemImage: "bag") }
                            .buttonStyle(WButtonStyle()).accessibilityIdentifier("browsePointShop")
                        Button { go(pointsStore.entries.isEmpty ? "B03" : "B02") } label: { Label("포인트 내역", systemImage: "list.bullet") }
                            .buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("openPointHistory")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("최근 내역").font(W.font(17, .semibold)); Spacer(); Button("전체 보기") { go(pointsStore.entries.isEmpty ? "B03" : "B02") }.font(W.font(12, .medium)).accessibilityIdentifier("allPointHistory") }
                        if pointsStore.entries.isEmpty { emptyPointHistory }
                        else { ForEach(pointsStore.entries.prefix(3)) { pointEntryRow($0) } }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("포인트 안내").font(W.font(17, .semibold))
                        WText(text: "적립과 상품은 화면 검토용 예시예요. 실제 적립·사용은 제공하지 않아요.", small: true)
                        WRow(title: "포인트 안내", subtitle: "사용 범위와 로컬 데이터", action: { go("B04") }, separator: false, height: 58)
                        WRow(title: "포인트 받는 방법", subtitle: "현재 연결된 적립 기능 없음", action: { go("B09") }, separator: false, height: 58)
                    }
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .top)
            }.accessibilityIdentifier("pointsOverviewScroll")
        }.background(W.paper)
    }

    var shop: some View {
        VStack(spacing: 0) {
            WHeader(title: "상점", back: { if ui.path.isEmpty { go("POINTS") } else { back() } }, trailing: AnyView(
                Button { go("B02") } label: { Text("\(pointsStore.balance.formatted())P").font(W.font(13, .semibold)).frame(minWidth: 52, minHeight: 44) }
                    .accessibilityLabel("포인트 내역").accessibilityIdentifier("shopPointBalance")
            ))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        WHeading(text: "러닝을 꾸며 보세요")
                        WText(text: "상품과 가격은 화면 흐름 확인을 위한 예시예요.", small: true)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(WPointCategory.allCases) { category in
                                Button { selectedPointCategory = category } label: {
                                    Text(category.rawValue).font(W.font(13, .medium)).padding(.horizontal, 16).frame(minHeight: 40)
                                        .background(selectedPointCategory == category ? W.lime : W.soft, in: Capsule())
                                        .foregroundStyle(W.ink)
                                }.buttonStyle(.plain).accessibilityIdentifier("shop-category-\(category == .all ? "all" : category == .shard ? "shard" : "card")")
                                    .accessibilityAddTraits(selectedPointCategory == category ? .isSelected : [])
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(visiblePointProducts) { product in
                            Button { ui.selectedPointProductID = product.id; go("B06") } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    WPointProductArtwork(product: product).frame(height: 128).clipShape(RoundedRectangle(cornerRadius: 14))
                                    Text(product.name).font(W.font(14, .semibold)).lineLimit(1)
                                    Text(product.category.rawValue).font(W.font(11)).foregroundStyle(W.muted)
                                    HStack(spacing: 5) { WPointsMark(size: 15); Text("\(product.price.formatted())P").font(W.font(13, .medium)) }
                                    if pointsStore.ownedItemIDs.contains(product.id) { Text("보유 중").font(W.font(11, .medium)).foregroundStyle(W.muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10).background(W.paper, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(W.line))
                            }.buttonStyle(.plain).accessibilityIdentifier("shop-item-\(product.id)")
                        }
                    }
                    WText(text: "모든 구매는 이 기기에서만 작동하는 예시입니다. 실제 결제나 서버 요청은 없어요.", small: true)
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
        selectedPointCategory == .all ? WPointProduct.catalog : WPointProduct.catalog.filter { $0.category == selectedPointCategory }
    }

    private var selectedPointProduct: WPointProduct {
        WPointProduct.catalog.first(where: { $0.id == ui.selectedPointProductID }) ?? WPointProduct.catalog[0]
    }

    private var emptyPointHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("아직 포인트 내역이 없어요").font(W.font(14, .medium))
            WText(text: "포인트가 생기거나 사용되면 여기에 표시돼요.", small: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(W.soft, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("emptyPointHistory")
    }

    private func pointEntryRow(_ entry: WPointEntry) -> some View {
        HStack(spacing: 12) {
            WPointsMark(size: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(W.font(13, .medium))
                Text(entry.date.formatted(.dateTime.year().month().day())).font(W.font(11)).foregroundStyle(W.muted)
            }
            Spacer()
            Text("\(entry.amount > 0 ? "+" : "")\(entry.amount.formatted())P").font(W.font(14, .semibold)).monospacedDigit()
                .foregroundStyle(entry.amount >= 0 ? W.ink : W.muted)
        }.frame(minHeight: 62).overlay(alignment: .bottom) { W.line.frame(height: 1) }
            .accessibilityElement(children: .combine)
    }

    private func pointHistory(empty: Bool) -> some View {
        VStack(spacing: 0) {
            WHeader(title: "포인트 내역", back: back)
            if empty || pointsStore.entries.isEmpty {
                ScrollView { VStack(alignment: .leading, spacing: 14) { WHeading(text: "포인트 내역"); emptyPointHistory }.padding(24).accessibilityIdentifier("emptyPointHistoryScreen") }
            } else {
                VStack(spacing: 0) {
                    Picker("내역 유형", selection: $selectedPointKind) {
                        ForEach(WPointKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                    }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 14).accessibilityIdentifier("pointHistoryFilter")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("최근 내역").font(W.font(14, .medium))
                            ForEach(pointsStore.filteredEntries(selectedPointKind)) { pointEntryRow($0) }
                            if pointsStore.filteredEntries(selectedPointKind).isEmpty { emptyPointHistory }
                            WText(text: "적립 내역은 기능 연결 전까지 예시로 표시돼요.", small: true).padding(.top, 4)
                        }.padding(20)
                    }
                }
            }
        }.background(W.paper)
    }

    private var pointGuide: some View {
        WPage(title: "포인트 안내", back: back) {
            WHeading(text: "가상 포인트를 확인해요")
            WText(text: "포인트는 이 화면에서 잔액과 상품 구매 흐름을 확인하기 위한 로컬 예시입니다.")
            WNotice(text: "적립·결제·서버 저장은 연결되지 않았어요. 표시된 잔액과 내역은 이 기기의 앱 데이터에 저장돼요.")
            WRow(title: "포인트 내역", subtitle: "예시 적립과 로컬 사용", action: { go(pointsStore.entries.isEmpty ? "B03" : "B02") }, separator: false)
            WRow(title: "포인트 받는 방법", subtitle: "현재 연결된 적립 기능 없음", action: { go("B09") }, separator: false)
        } actions: { EmptyView() }
    }

    private var pointProductDetail: some View {
        let product = selectedPointProduct
        let owned = pointsStore.ownedItemIDs.contains(product.id)
        let enough = pointsStore.canPurchase(product)
        return WPage(title: "아이템 상세", back: back) {
            WPointProductArtwork(product: product).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("pointProductArtwork")
            Text(product.name).font(W.font(22, .semibold))
            WText(text: product.subtitle + " · 예시 상품", small: true)
            HStack(spacing: 8) { WPointsMark(size: 20); Text("\(product.price.formatted())P").font(W.font(18, .semibold)) }
            WRow(title: "러닝 카드에서 보기", subtitle: "선택한 테마로 미리보기", action: { go("B10") }, separator: false, height: 62)
                .accessibilityIdentifier("pointPreview")
            if owned { WNotice(text: "이 예시 아이템은 이 기기에 보유 상태로 저장돼 있어요.") }
            if !enough && !owned { WNotice(text: "포인트가 부족해요. 실제 적립은 제공하지 않아요.") }
        } actions: {
            Button(owned ? "보유 중" : enough ? "\(product.price.formatted())P로 예시 구매" : "포인트 부족") {
                showingPointPurchaseConfirmation = true
            }.buttonStyle(WButtonStyle()).disabled(owned || !enough).accessibilityIdentifier("purchaseShopItem")
            if !owned && !enough {
                Button("포인트 부족 안내") { go("B08") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointShortageHelp")
            }
        }.confirmationDialog("가상 포인트를 사용할까요?", isPresented: $showingPointPurchaseConfirmation, titleVisibility: .visible) {
            Button("구매 예시 확인", role: .destructive) {
                if pointsStore.purchase(product) { go("B07") }
                else { go("B08") }
            }.accessibilityIdentifier("confirmPointPurchase")
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(product.price.formatted())P를 이 기기의 예시 잔액에서 차감합니다. 실제 결제는 없어요.")
        }
    }

    private var pointPurchaseComplete: some View {
        WPage(title: "구매 완료 예시", back: back) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(W.lime)
                Text("아이템을 보유 목록에 담았어요").font(W.font(20, .semibold)).multilineTextAlignment(.center)
                Text(selectedPointProduct.name).font(W.font(16, .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
            WPointProductArtwork(product: selectedPointProduct).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
            WRow(title: "남은 예시 포인트", value: "\(pointsStore.balance.formatted())P", separator: false)
            WNotice(text: "구매는 이 기기에만 저장된 예시 흐름이에요. 결제나 서버 요청은 발생하지 않았어요.")
        } actions: {
            Button("러닝 카드 미리보기") { go("B10") }.buttonStyle(WButtonStyle()).accessibilityIdentifier("previewPurchasedPointItem")
            Button("상점으로 돌아가기") { returnToPointShop() }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("backToShop")
        }
    }

    private var pointShortage: some View {
        WPage(title: "포인트 부족", back: back) {
            WHeading(text: "포인트가 부족해요")
            WText(text: "\(selectedPointProduct.name)을 구매하려면 예시 포인트가 더 필요해요.")
            WRow(title: "보유 포인트", value: "\(pointsStore.balance.formatted())P", separator: false)
            WRow(title: "필요 포인트", value: "\(selectedPointProduct.price.formatted())P", separator: false)
            WNotice(text: "현재 실제 포인트 적립 기능은 연결되지 않았어요. 예시 상품은 필요한 잔액이 부족하면 구매할 수 없어요.")
        } actions: {
            Button("포인트 받는 방법") { go("B09") }.buttonStyle(WButtonStyle()).accessibilityIdentifier("pointEarningGuide")
            Button("상점으로 돌아가기") { returnToPointShop() }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("backToShop")
        }
    }

    private var pointEarningGuide: some View {
        WPage(title: "포인트 받는 방법", back: back) {
            WHeading(text: "적립 기능은 아직 연결되지 않았어요")
            WText(text: "러닝 기록은 이 기기에 저장되지만, 기록 저장만으로 포인트가 적립되지는 않아요.")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle").font(.system(size: 17))
                    Text("광고 영역").font(W.font(14, .medium))
                }.foregroundStyle(W.muted)
                WText(text: "실제 광고 연결 전의 자리예요. 광고 재생이나 광고 보상은 제공하지 않아요.", small: true)
            }.frame(maxWidth: .infinity, minHeight: 106, alignment: .leading).padding(16)
                .background(W.soft, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(W.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .accessibilityIdentifier("pointAdPlaceholder")
            WNotice(text: "적립 조건이나 보상 정책을 정하지 않은 상태라 현재 잔액에 포인트를 더하는 기능은 제공하지 않아요.")
            WRow(title: "내 포인트 내역", subtitle: "로컬 예시 잔액과 거래", action: { go(pointsStore.entries.isEmpty ? "B03" : "B02") }, separator: false)
        } actions: { EmptyView() }
    }

    private var pointCardPreview: some View {
        let record = store.records.first(where: \.isValid)
        return WPage(title: "러닝 카드 미리보기", back: back) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("MOV · RUNNING CARD").font(W.font(10, .semibold)).foregroundStyle(W.muted); Text(ui.profile.nickname).font(W.font(22, .semibold)) }; Spacer(); WPointsMark(size: 24) }
                WPointProductArtwork(product: selectedPointProduct).frame(height: 184).clipShape(RoundedRectangle(cornerRadius: 16))
                if let record {
                    HStack(spacing: 14) {
                        previewMetric("거리", "\(MovNumber.display(record.kilometers)) km")
                        previewMetric("시간", RunRecord.clock(record.seconds))
                        previewMetric("페이스", "\(record.pace) /km")
                    }
                    Text(record.date.formatted(.dateTime.year().month().day())).font(W.font(11)).foregroundStyle(W.muted)
                } else {
                    WText(text: "저장된 러닝 기록이 없어요. 기록을 저장하면 이 영역에 실제 기기 데이터를 미리 볼 수 있어요.", small: true)
                }
                WText(text: "실제 공유 이미지 파일을 만들거나 게시하지 않는 미리보기예요.", small: true)
            }.padding(18).background(W.soft, in: RoundedRectangle(cornerRadius: 20))
        } actions: {
            Button("상점으로 돌아가기") { returnToPointShop() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("previewBackToShop")
        }
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(W.font(10)).foregroundStyle(W.muted); Text(value).font(W.font(13, .semibold)).lineLimit(1).minimumScaleFactor(0.75) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WPointsMark: View {
    var size: CGFloat = 20
    var body: some View {
        WPointsIcon().stroke(W.ink, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct WPointProductArtwork: View {
    let product: WPointProduct
    private var colors: [Color] {
        switch product.palette {
        case 1: [Color.wire(0x6CC5E8, 0x225A78), Color.wire(0xC5F2FF, 0x77BED7), Color.wire(0x4766AF, 0x3E4A88)]
        case 2: [Color.wire(0xB7B3F6, 0x51478C), Color.wire(0xF2C6E9, 0x9E5F94), Color.wire(0xBDE9D6, 0x3A7866)]
        case 3: [Color.wire(0x91C59A, 0x335C43), Color.wire(0xD6E7B6, 0x759353), Color.wire(0x669B85, 0x2D655C)]
        default: [Color.wire(0xFFB77A, 0xA75555), Color.wire(0xFFE5A4, 0xD59A4C), Color.wire(0xD47BAA, 0x783C78)]
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(colors: colors.map { $0.opacity(0.22) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                WPrismFacet(points: [CGPoint(x: 0.5, y: 0.08), CGPoint(x: 0.78, y: 0.37), CGPoint(x: 0.5, y: 0.92), CGPoint(x: 0.22, y: 0.37)]).fill(LinearGradient(colors: [colors[0], colors[1]], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: size.width * 0.48, height: size.height * 0.82)
                WPrismFacet(points: [CGPoint(x: 0.5, y: 0.08), CGPoint(x: 0.5, y: 0.92), CGPoint(x: 0.78, y: 0.37)]).fill(colors[2].opacity(0.85)).frame(width: size.width * 0.48, height: size.height * 0.82)
                VStack { HStack { Text("예시 아이템").font(W.font(10, .medium)); Spacer(); WPointsMark(size: 18) }; Spacer(); Text(product.name).font(W.font(14, .semibold)).frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(14).foregroundStyle(W.ink)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(product.name) 예시 아이템 미리보기")
    }
}

private struct WPrismFacet: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height)) }
        path.closeSubpath()
        return path
    }
}
