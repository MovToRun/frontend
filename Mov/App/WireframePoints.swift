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
            balance = 1_250
            entries = [
                WPointEntry(title: "러닝 카드 배경", detail: "사용 내역 예시", amount: -250, date: base),
                WPointEntry(title: "포인트 적립", detail: "적립 내역 예시", amount: 500, date: calendar.date(byAdding: .day, value: -1, to: base) ?? base),
                WPointEntry(title: "포인트 적립", detail: "적립 내역 예시", amount: 1_000, date: calendar.date(byAdding: .day, value: -2, to: base) ?? base)
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
        entries.insert(WPointEntry(title: product.name, detail: "로컬 구매 예시", amount: -product.price, date: date), at: 0)
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
            WHeader(title: "내 포인트", trailing: AnyView(
                Button { go("B02") } label: { Text("내역보기").font(W.font(14, .medium)).foregroundStyle(W.ink).frame(minWidth: 68, minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("openPointHistory")
            ))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) { WPointsMark(size: 18); Text("보유 포인트").font(W.font(15, .medium)).foregroundStyle(W.muted) }
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(pointsStore.balance.formatted()).font(W.font(44, .bold)).monospacedDigit().accessibilityIdentifier("pointBalance")
                                Text("포인트").font(W.font(17, .semibold)).foregroundStyle(W.muted)
                            }
                            Button { go("B04") } label: { Text("포인트 안내  ›").font(W.font(13, .medium)).foregroundStyle(W.ink) }
                                .accessibilityIdentifier("pointGuideOverview")
                        }
                        Spacer(minLength: 0)
                        Image("PrismArt").resizable().scaledToFit().frame(width: 96, height: 96).accessibilityHidden(true)
                    }.padding(.top, 14)
                    Button { go("SHOP") } label: {
                        Text("쇼핑하러 가기").font(W.font(15, .semibold)).foregroundStyle(W.ink).frame(maxWidth: .infinity, minHeight: 54)
                            .background(W.lime, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("browsePointShop")
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            W.soft
                            Text("입점 상품 광고 영역").font(W.font(13, .medium)).foregroundStyle(W.muted)
                            Text("광고").font(W.font(9)).foregroundStyle(W.muted).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                        }.frame(maxWidth: .infinity, minHeight: 156)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(W.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        Button { go("B04") } label: {
                            HStack { Text("포인트 안내").font(W.font(16, .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(W.muted) }
                                .foregroundStyle(W.ink).padding(.horizontal, 16).frame(minHeight: 54)
                                .background(W.soft, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
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
                        Text(pointsStore.balance.formatted()).font(W.font(25, .semibold)).monospacedDigit()
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
                                        .foregroundStyle(selectedPointCategory == category ? W.ink : W.muted)
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
                                    WPointProductArtwork(product: product).aspectRatio(1.16, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
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
            if empty || pointsStore.entries.isEmpty {
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
            WPointProductArtwork(product: product).aspectRatio(1.35, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("pointProductArtwork")
            Text(product.name).font(W.font(22, .semibold))
            WText(text: product.kind, small: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) { Text("\(product.price.formatted())").font(W.font(23, .semibold)); Text("포인트").font(W.font(13)) }
            WText(text: product.description)
            WRow(title: "보유 포인트", value: pointsStore.balance.formatted(), separator: false)
        } actions: {
            HStack(spacing: 10) {
                Button("미리보기") { go("B10") }.buttonStyle(WButtonStyle(kind: 1)).accessibilityIdentifier("pointPreview")
                Button(owned ? "보유 중" : enough ? "구매하기" : "포인트 부족") {
                    showingPointPurchaseConfirmation = true
                }.buttonStyle(WButtonStyle()).disabled(owned || !enough).accessibilityIdentifier("purchaseShopItem")
            }
            if !owned && !enough {
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
            VStack(spacing: 14) {
                Text("구매 완료 예시").font(W.font(20, .semibold)).multilineTextAlignment(.center)
                Text(selectedPointProduct.name).font(W.font(16, .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
            WRow(title: "보유 포인트", value: "\((pointsStore.balance + selectedPointProduct.price).formatted())")
            WRow(title: "필요 포인트 · 예시", value: "\(selectedPointProduct.price.formatted())")
            WRow(title: "사용 후 잔액 · 예시", value: "\(pointsStore.balance.formatted())", separator: false)
            WText(text: "샘플 구매 결과예요. 실제 서버 결제나 상품 지급은 없어요.", small: true)
        } actions: {
            Button("확인") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("backToShop")
        }
    }

    private var pointShortage: some View {
        WPage(title: "포인트 부족", back: back) {
            WHeading(text: "포인트가 부족해요")
            WText(text: "\(selectedPointProduct.name)을 구매하려면 포인트가 더 필요해요.")
            WRow(title: "보유 포인트", value: "\(pointsStore.balance.formatted())P", separator: false)
            WRow(title: "필요 포인트", value: "\(selectedPointProduct.price.formatted())P", separator: false)
            WRow(title: "부족한 포인트", value: "\(max(0, selectedPointProduct.price - pointsStore.balance).formatted())P", separator: false)
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
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("러닝 프로필").font(W.font(11)).foregroundStyle(W.muted); Spacer(); BrandMark(size: 28) }
                HStack(spacing: 14) {
                    Group {
                        if let data = ui.profile.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Text(String(ui.profile.nickname.prefix(1))).font(W.font(20, .semibold)) }
                    }.frame(width: 56, height: 56).background(W.soft).clipShape(Circle()).overlay(Circle().stroke(W.line))
                        .overlay { if selectedPointProduct.id == "frame" { Circle().stroke(W.lime, lineWidth: 3).padding(-5) } }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.totalDistance == 0 ? "등급 없음" : tierName).font(W.font(12, .medium)).foregroundStyle(W.muted).padding(.bottom, 6)
                        Text(ui.profile.nickname).font(W.font(24, .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(ui.profile.introduction).font(W.font(13)).foregroundStyle(W.muted).padding(.top, 10)
                    }
                }.padding(.top, 34).padding(.bottom, 26)
                W.line.frame(height: 1)
                HStack(alignment: .top, spacing: 16) {
                    previewMetric("활동 지역", ui.profile.region)
                    previewMetric("최근 1달 평균 러닝당 거리", "\(MovNumber.display(store.averageDistance)) km")
                }.padding(.top, 18)
            }.padding(23).frame(minHeight: 315, alignment: .top).background(W.paper, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(W.line))
                .overlay(alignment: .topTrailing) {
                    if selectedPointProduct.id == "line" {
                        Ellipse().stroke(W.lime.opacity(0.24), lineWidth: 22).frame(width: 260, height: 230).rotationEffect(.degrees(-25)).offset(x: 155, y: -60)
                    } else if selectedPointProduct.id == "dawn" {
                        Ellipse().stroke(W.lime.opacity(0.24), lineWidth: 40).frame(width: 260, height: 230).rotationEffect(.degrees(-25)).offset(x: 70, y: 160)
                    } else if selectedPointProduct.id == "card-frame" {
                        RoundedRectangle(cornerRadius: 18).stroke(W.lime, lineWidth: 3).padding(4)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 18))
            WText(text: "현재 러닝 카드는 바뀌지 않아요", small: true)
        } actions: {
            Button("아이템으로 돌아가기") { back() }.buttonStyle(WButtonStyle()).accessibilityIdentifier("previewBackToShop")
        }
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(W.font(10)).foregroundStyle(W.muted).lineLimit(1); Text(value).font(W.font(13, .semibold)).lineLimit(2).minimumScaleFactor(0.75) }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.wire(0xF7F7F7, 0x292F2B)
                if product.category == .face {
                    Circle().stroke(W.lime, lineWidth: size.width * 0.04).frame(width: size.width * 0.44, height: size.width * 0.44)
                    Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(W.ink.opacity(0.65))
                        .frame(width: size.width * 0.34, height: size.width * 0.34).overlay(Circle().stroke(W.lime, lineWidth: size.width * 0.035))
                    HStack(spacing: size.width * 0.055) { ForEach(0..<3) { _ in Circle().fill(W.lime).frame(width: size.width * 0.04, height: size.width * 0.04) } }
                        .offset(y: size.width * 0.26)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: size.width * 0.035).fill(.white).shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        if product.id == "card-frame" { RoundedRectangle(cornerRadius: size.width * 0.035).stroke(W.lime, lineWidth: 3) }
                        BrandMark(size: size.width * 0.075).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(size.width * 0.06)
                        if product.id != "card-frame" {
                            WPointPath(productID: product.id).stroke(W.lime, style: StrokeStyle(lineWidth: product.id == "line" ? 5 : 8, lineCap: .round, lineJoin: .round))
                                .padding(.horizontal, size.width * 0.04).padding(.vertical, size.height * 0.12)
                        }
                        VStack(spacing: 3) { Capsule().fill(W.ink.opacity(0.75)).frame(width: size.width * 0.2, height: 3); Capsule().fill(W.ink.opacity(0.25)).frame(width: size.width * 0.13, height: 3) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(size.width * 0.06)
                    }
                    .frame(width: size.width * 0.74, height: size.height * 0.72)
                    .rotationEffect(.degrees(product.id == "line" ? 4 : product.id == "dawn" ? -4 : 0))
                    .opacity(product.id == "dawn" ? 0.68 : 1)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(size.width * 0.06)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(product.name) 예시 아이템 미리보기")
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
        let sx = rect.width / 240, sy = rect.height / 140
        var transformed = Path()
        transformed.addPath(path, transform: CGAffineTransform(scaleX: sx, y: sy))
        return transformed
    }
}
