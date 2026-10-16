import SwiftUI

enum WCommunityDiscardContext:Equatable {
    case profile,crew,crewManage,postComposer,courseComposer
    var message:String{
        switch self {
        case .profile:return "저장하지 않은 프로필 변경사항이 있어요."
        case .crew:return "저장하지 않은 크루 수정사항이 있어요."
        case .crewManage:return "저장하지 않은 관리 변경사항이 있어요."
        case .postComposer:return "저장하지 않은 글이 있어요. 변경 사항을 버리면 저장 전 내용으로 돌아가요."
        case .courseComposer:return "저장하지 않은 코스가 있어요. 변경 사항을 버리면 저장 전 내용으로 돌아가요."
        }
    }
}
struct WCommunityComposerSnapshot:Equatable {
    var screen:String
    var board:String
    var crewID:String?
    var postID:String?
    var title:String
    var body:String
    var recordID:String
    var hideEnds:Bool
    var attachmentIDs:[String]=[]
}

enum WWireDefaults {
    static func resolve(arguments:[String] = ProcessInfo.processInfo.arguments)->(defaults:UserDefaults,suiteName:String?) {
        if let suite=AuthSessionFixtureLaunchPolicy.defaultsSuiteName(arguments:arguments) {
            return (UserDefaults(suiteName:suite)!,suite)
        }
        return (.standard,nil)
    }
}

// Native views use the original HTML's dimensions. No web view or screen raster is used for UI.
extension Color {
    static func wire(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let h = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((h >> 16) & 255)/255, green: CGFloat((h >> 8) & 255)/255, blue: CGFloat(h & 255)/255, alpha: 1)
        })
    }
}
enum W {
    static let paper = Color.wire(0xFFFFFF,0x191919)
    static let soft = Color.wire(0xF7F7F7,0x262626)
    static let secondary = Color.wire(0xEEEEEE,0x333333)
    static let ink = Color.wire(0x202925,0xF1F1F1)
    static let muted = Color.wire(0x686868,0xB0B0B0)
    static let line = Color.wire(0xE5E5E5,0x3A3A3A)
    static let border = Color.wire(0xD0D0D0,0x575757)
    static let controlBorder = Color.wire(0x767676,0x939393)
    static let lime = MovTokens.brand
    static func font(_ size:CGFloat,_ weight:Font.Weight = .regular)->Font {
        let name=weight == .bold ? "Bold":weight == .semibold ? "SemiBold":weight == .medium ? "Medium":"Regular"
        return .custom("PretendardVariable-"+name,size:size,relativeTo:.body)
    }
}
struct WButtonStyle:ButtonStyle {
    var kind = 0
    var panel = false
    @Environment(\.authPageMotion) var authMotion
    @Environment(\.isEnabled) var enabled
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(W.font(panel ? 17:16,.semibold)).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity,minHeight:panel ? 58:54).padding(.horizontal,12)
            .foregroundStyle(enabled ? (kind == 1 ? W.ink:Color(red:32/255,green:41/255,blue:37/255)):W.muted)
            .background(enabled ? (kind == 1 ? W.secondary:kind == 2 ? Color(red:1,green:90/255,blue:95/255):W.lime):(kind == 2 ? Color.wire(0xFFDADD,0x503136):Color.wire(0xE7E7E7,0x343434)),in:RoundedRectangle(cornerRadius:12))
            .scaleEffect(configuration.isPressed && !reduced ? (authMotion.enabled ? 0.955:0.988):1)
            .animation(reduced ? nil:(authMotion.enabled ? .timingCurve(0.2,0.8,0.2,1,duration:configuration.isPressed ? 0.09:0.18):.easeOut(duration:configuration.isPressed ? 0.09:0.18)),value:configuration.isPressed)
    }
}
struct WPage<Content:View,Actions:View>:View {
    var title:String
    var back:(()->Void)?
    var backDisabled=false
    var backIdentifier:String?=nil
    var trailing:AnyView=AnyView(EmptyView())
    var onCommunityScrollOffset:((CGFloat)->Void)?=nil
    @ViewBuilder var content:Content
    @ViewBuilder var actions:Actions
    var body:some View {
        VStack(spacing:0){
            WHeader(title:title,back:back,backIdentifier:backIdentifier,backDisabled:backDisabled,mark:title=="시뮬레이션 완료",trailing:trailing)
            ScrollView {
                if onCommunityScrollOffset != nil {WCommunityScrollOffsetProbe(coordinateSpace:"community-page-scroll")}
                VStack(alignment:.leading,spacing:18){content}
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .padding(24)
                    .padding(.bottom,onCommunityScrollOffset == nil ? 0:WCommunityBottomTab.barHeight+24)
            }
            .coordinateSpace(name:"community-page-scroll")
            .wObserveCommunityScrollOffset{onCommunityScrollOffset?($0)}
            .scrollDismissesKeyboard(.interactively)
            .modifier(WAuthBodyMotion())
            if Actions.self != EmptyView.self { VStack(spacing:10){actions}.padding(.horizontal,24).padding(.top,16).padding(.bottom,24).overlay(alignment:.top){W.line.frame(height:1)} }
        }.background(W.paper)
    }
}
private struct WCommunityScrollOffsetPreferenceKey:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=nextValue()}
}
struct WCommunityScrollOffsetProbe:View {
    let coordinateSpace:String
    var body:some View {
        GeometryReader{geometry in
            Color.clear.preference(key:WCommunityScrollOffsetPreferenceKey.self,value:geometry.frame(in:.named(coordinateSpace)).minY)
        }.frame(height:0)
    }
}
extension View {
    @ViewBuilder func wAccessibilityIdentifier(_ identifier:String?)->some View {
        if let identifier { accessibilityIdentifier(identifier) } else { self }
    }
    func wOnCommunityScrollOffset(_ action:@escaping (CGFloat)->Void)->some View {
        onPreferenceChange(WCommunityScrollOffsetPreferenceKey.self,perform:action)
    }
    func wObserveCommunityScrollOffset(_ action:@escaping (CGFloat)->Void)->some View {
        modifier(WCommunityScrollObserver(action:action))
    }
}
private struct WCommunityScrollObserver:ViewModifier {
    let action:(CGFloat)->Void
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 18.0,*) {
            content.onScrollGeometryChange(for:CGFloat.self,of:{geometry in geometry.contentOffset.y}){_,offset in action(-offset)}
        } else {
            content.wOnCommunityScrollOffset(action)
        }
    }
}
private struct WOutgoingRouteAccessibility:ViewModifier {
    let hidden:Bool
    func body(content:Content)->some View {content.accessibilityHidden(hidden)}
}
struct WHeader:View {
    var title:String
    var back:(()->Void)? = nil
    var backIdentifier:String? = nil
    var backDisabled=false
    var root=false
    var showRootMark=true
    var centerRootMark=false
    var mark=false
    var trailing:AnyView = AnyView(EmptyView())
    var body:some View {
        HStack {
            if let back { Button(action:back){WBackIcon().stroke(W.ink,style:StrokeStyle(lineWidth:1.2,lineCap:.round,lineJoin:.round)).frame(width:18,height:18).frame(width:44,height:44)}.disabled(backDisabled).accessibilityLabel("뒤로").wAccessibilityIdentifier(backIdentifier) }
            else if root ? showRootMark : mark {BrandMark(size:root ? 30:28).frame(width:root ? 30:28,height:44).accessibilityIdentifier(root ? "rootHeaderBrandMark":"completionBrandMark")}
            else {Color.clear.frame(width:44,height:44)}
            Spacer();trailing
        }.padding(.horizontal,root ? 16:10).frame(height:root ? 64:68)
            .overlay{
                if centerRootMark {
                    BrandMark(size:30).accessibilityLabel("커뮤니티 내 프로필").accessibilityIdentifier("communityOwnProfileHeaderBrandMark").allowsHitTesting(false)
                } else {
                    Text(title).font(W.font(17,.medium)).lineLimit(2).minimumScaleFactor(0.65).frame(maxWidth:220).allowsHitTesting(false)
                }
            }
            .background(W.paper.ignoresSafeArea(edges:.top)).overlay(alignment:.bottom){if !(root && title=="내 정보"){W.line.frame(height:1)}}
    }
}
struct WHeading:View {let text:String;@Environment(\.authPageMotion) var authMotion;var body:some View {Text(text).font(W.font(27,.bold)).kerning(authMotion.enabled ? -0.945:0).lineSpacing(5).fixedSize(horizontal:false,vertical:true).padding(.top,6).padding(.bottom,3)}}
struct WText:View {let text:String;var small=false;var body:some View {Text(text).font(W.font(small ? 12:14)).lineSpacing(small ? 5:7).foregroundStyle(W.muted).fixedSize(horizontal:false,vertical:true)}}
struct WNotice:View {let text:String;var danger=false;var body:some View {Text(text).font(W.font(13)).lineSpacing(6).foregroundStyle(danger ? Color.wire(0xA92D32,0xFF9CA3):W.muted).frame(maxWidth:.infinity,alignment:.leading).padding(16).background(danger ? Color.wire(0xFFF1F1,0x3C2024):W.soft,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(danger ? Color.wire(0xF0BFC3,0x83535A):W.line,lineWidth:1))}}
struct WRow:View {
    let title:String
    var subtitle=""
    var value=""
    var action:(()->Void)?
    var separator=true
    var height:CGFloat=64
    var plain=false
    var arrow=false
    var body:some View {
        Button {action?()} label:{HStack(spacing:12){VStack(alignment:.leading,spacing:6){Text(title).font(W.font(plain ? 14:15,plain ? .regular:.medium));if !subtitle.isEmpty{WText(text:subtitle,small:true)}};Spacer();if !value.isEmpty{Text(value).font(W.font(13))};if action != nil{Text(arrow ? "→":"›").font(W.font(arrow ? 20:14)).foregroundStyle(W.muted).accessibilityHidden(true)}}.frame(minHeight:height).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}
            .buttonStyle(.plain).overlay(alignment:.bottom){if separator{W.line.frame(height:1)}}
    }
}
struct WField:View {
    let label:String
    @Binding var text:String
    var placeholder=""
    var limit:Int?=nil
    var multiline=false
    var multilineHeight:CGFloat=193.2
    var textSize:CGFloat=16
    var labelSize:CGFloat=14
    var secondaryLabel=""
    var placeholderColor:Color? = nil
    var accessibilityID:String? = nil
    var softFieldStyle=false
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            (Text(label).font(W.font(labelSize,labelSize==13 ? .regular:.medium))+Text(secondaryLabel.isEmpty ? "":"  "+secondaryLabel).font(W.font(10)).foregroundColor(W.muted)).frame(height:labelSize==13 ? 19:21,alignment:.leading).padding(.bottom,8)
            if multiline{TextEditor(text:$text).font(W.font(textSize)).scrollContentBackground(.hidden).lineSpacing(textSize==16 ? 8:4.2).frame(height:multilineHeight-12).padding(.horizontal,9).padding(.vertical,6).background(softFieldStyle ? W.soft:W.paper,in:RoundedRectangle(cornerRadius:softFieldStyle ? 12:10)).overlay(RoundedRectangle(cornerRadius:softFieldStyle ? 12:10).stroke(softFieldStyle ? W.line:W.controlBorder)).accessibilityIdentifier(accessibilityID ?? "")}
            else{TextField(placeholder,text:$text,prompt:placeholderColor.map{Text(placeholder).foregroundColor($0)}).font(W.font(textSize)).padding(14).frame(minHeight:54).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.controlBorder)).accessibilityIdentifier(accessibilityID ?? "")}
            if let limit{Text("\(text.count)/\(limit)").font(W.font(11)).foregroundStyle(text.count>limit ? .red:W.muted).frame(maxWidth:.infinity,minHeight:18,alignment:.trailing).padding(.top,6)}
        }
    }
}
// CSS .metric-row: two equal border-box columns, 20px gap; the second owns its divider.
struct WMetric:View {
    var record:RunRecord
    var paused=false
    var saved=false
    var reservePauseSpace=false
    var clockOverride:Double?=nil
    var metricPace:String {
        guard record.displayedKilometers>0 else{return saved ? record.pace:"—"}
        return record.pace.count==4 ? "0"+record.pace:record.pace
    }
    var metricDistance:Text {
        record.displayedKilometers>0 || saved
            ? Text(record.displayedKilometers,format:.number.precision(.fractionLength(2)))
            : Text("—")
    }
    private var distanceLabel:String {
        switch record.serverJudgement {
        case .pending: "기기 측정 거리"
        case .invalid: "서버 판정 원본 거리"
        case .valid, nil: "유효 거리"
        }
    }
    private var timeLabel:String {
        switch record.serverJudgement {
        case .pending: "기기 측정 시간"
        case .invalid: "기록 상태"
        case .valid, nil: saved ? "유효 러닝 시간":"러닝 시간"
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            metricLabel(distanceLabel)
            (metricDistance.font(W.font(52,.bold)).kerning(-2.34)+Text(" km").font(W.font(22,.semibold)).kerning(-0.44))
                .monospacedDigit().frame(height:57.2,alignment:.leading).padding(.top,5).padding(.bottom,22).accessibilityIdentifier("runDistanceMetric")
            HStack(alignment:.top,spacing:20){
                VStack(alignment:.leading,spacing:0){
                    metricLabel(timeLabel)
                    Text(saved && !record.isValid && record.serverJudgement != .pending ? "비유효 러닝":RunRecord.clock(clockOverride ?? record.displayedSeconds)).font(W.font(saved && !record.isValid && record.serverJudgement != .pending ? 18:28,.semibold)).kerning(-0.98).monospacedDigit().frame(height:39.2,alignment:.leading)
                    if paused || reservePauseSpace{Text(paused ? "일시정지":" ").font(W.font(12)).foregroundStyle(W.muted).frame(height:19).padding(.top,3)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:0){
                    metricLabel(record.serverJudgement == .pending ? "기기 측정 페이스":record.serverJudgement == .invalid ? "기록 상태":"평균 페이스")
                    (Text(metricPace).font(W.font(28,.semibold)).kerning(-0.98)+Text(" /km").font(W.font(14,.medium)).kerning(-0.14)).monospacedDigit().frame(height:39.2,alignment:.leading).accessibilityIdentifier("runPaceMetric")
                    if paused || reservePauseSpace{Color.clear.frame(height:22)}
                }.padding(.leading,20).frame(maxWidth:.infinity,alignment:.leading).overlay(alignment:.leading){Color.wire(0xE1E1E1,0xE1E1E1).frame(width:1)}
            }
        }.accessibilityElement(children:.contain)
    }
    func metricLabel(_ title:String)->some View{Text(title).font(W.font(13,.medium)).kerning(-0.26).foregroundStyle(W.muted).frame(height:18.85,alignment:.leading)}
}
struct WMap:View {
    var route=false
    var routePoints:[RunUploadPoint]=[]
    var controls=false
    var centerControl=true
    var failed=false
    var gpsSearching=false
    var gpsWaiting=false
    var gpsWeak=false
    var focusUser=false
    var userCenterY:CGFloat=0
    var centerControlBottomInset:CGFloat=0
    var controlsTopInset:CGFloat=0
    var backgroundTap:(()->Void)?=nil
    @State private var info=false
    @State private var mapRecovered=false
    @State private var panOffset=CGSize.zero
    @GestureState private var panDrag=CGSize.zero
    private var isCentered:Bool{abs(panOffset.width)<1 && abs(panOffset.height)<1}
    private var displayedPanOffset:CGSize{CGSize(width:panOffset.width+panDrag.width,height:panOffset.height+panDrag.height)}
    var body:some View {
        ZStack(alignment:.topLeading){if failed && !mapRecovered{W.soft.overlay{VStack(spacing:14){WText(text:"지도를 불러오지 못했어요");Button("다시 시도"){mapRecovered=true}.font(W.font(13));WText(text:"GPS 수치와 기록 제어는 유지돼요",small:true)}.padding(20)}}else{if let backgroundTap{SampleMap(route:route,routePoints:routePoints,focusUser:focusUser,userCenterY:userCenterY,panOffset:displayedPanOffset).accessibilityIdentifier(focusUser ? "runningMap":"mapSurface").gesture(DragGesture(minimumDistance:0).updating($panDrag){v,state,_ in
                    if hypot(v.translation.width,v.translation.height)>=8{state=v.translation}
                }.onEnded{v in
                    if hypot(v.translation.width,v.translation.height)<8{backgroundTap()}
                    else{panOffset=CGSize(width:panOffset.width+v.translation.width,height:panOffset.height+v.translation.height)}
                })}else{SampleMap(route:route,routePoints:routePoints,focusUser:focusUser,userCenterY:userCenterY,panOffset:displayedPanOffset).accessibilityIdentifier(focusUser ? "runningMap":"mapSurface")}}
            if !controls && WReviewMode.tools{GeometryReader{g in if g.size.height>100{VStack(alignment:.leading){Text("가상 코스").font(W.font(11)).padding(.vertical,6).padding(.horizontal,9).background(W.paper.opacity(0.8),in:RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(W.line));Spacer();Text("실제 장소가 아닌 도식 지도").font(W.font(9)).padding(.vertical,4).padding(.horizontal,6).background(W.paper.opacity(0.8),in:RoundedRectangle(cornerRadius:3))}.foregroundStyle(W.muted).padding(.horizontal,18).padding(.vertical,16)}}}
            if controls {VStack(alignment:.leading,spacing:8){Button{info.toggle()}label:{WGPSSignal(searching:gpsSearching,weak:gpsWeak,waiting:gpsWaiting)}.accessibilityLabel("위치 상태 안내");if WReviewMode.tools && (!failed || mapRecovered){Text("실제 장소가 아닌 도식 지도").font(W.font(9)).padding(.horizontal,6).padding(.vertical,4).background(W.paper).padding(.leading,6)};if info{WNotice(text:"위치와 신호 상태를 확인해 주세요.").frame(maxWidth:280)}}.padding(.horizontal,12).padding(.top,controlsTopInset+10)}
        }.clipped().overlay(alignment:.bottomTrailing){if controls && centerControl{Button{withAnimation(.easeOut(duration:0.22)){panOffset = .zero}}label:{AssetIcon(name:"location",size:24).frame(width:44,height:44).background(W.paper,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line))}.accessibilityLabel("지도 중심").accessibilityIdentifier("mapRecenter").accessibilityValue(isCentered ? "중심":"이동됨").padding(16).padding(.bottom,centerControlBottomInset)}}
    }
}
struct WLocalProfile:Codable {
    var nickname="새벽러너";var introduction="조금씩, 멀리 가는 중";var region="모브시 중부권";var weight=""
    var photo:Data? = nil
    var providers=["카카오"];var logged=false;var notificationRead:[Int]=[]
}
enum WProfileValidation {
    static func isValid(nickname:String,introduction:String)->Bool {
        let normalized=nickname.trimmingCharacters(in:.whitespacesAndNewlines)
        return !normalized.isEmpty && normalized.count<=20 && introduction.count<=60
    }
}
enum WMemberProfileValidation {
    static let activityRegions = ["모브시 북부권", "모브시 중부권", "모브시 남부권"]

    enum WeightInput: Equatable {
        case empty
        case value(Decimal)
        case invalid
    }

    static func nicknameError(for value: String) -> String? {
        let normalized = value.precomposedStringWithCanonicalMapping
        let scalars = Array(normalized.unicodeScalars)
        let allowed = scalars.allSatisfy { scalar in
            let code = scalar.value
            return (0x41...0x5A).contains(code) || (0x61...0x7A).contains(code)
                || (0x30...0x39).contains(code) || code == 0x5F
                || (0xAC00...0xD7A3).contains(code)
        }
        guard (2...12).contains(scalars.count), allowed else {
            return "닉네임은 2–12자이며 한글·영문·숫자·밑줄만 사용할 수 있어요."
        }
        return nil
    }

    static func introductionError(for value: String) -> String? {
        value.count <= 60 ? nil : "한 줄 소개는 60자 이내로 입력해 주세요."
    }

    static func regionError(for value: String) -> String? {
        value.isEmpty || value == "선택 안 함" || activityRegions.contains(value)
            ? nil : "활동 지역을 선택해 주세요."
    }

    static func weightInput(_ value: String) -> WeightInput {
        guard !value.isEmpty else { return .empty }
        guard value.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 20, decimal <= 300 else { return .invalid }
        return .value(decimal)
    }

    static func weightText(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    static func profilePatch(
        baseline: MemberProfile,
        nickname: String,
        introduction: String,
        region: String
    ) -> MemberProfilePatch {
        let nicknameField: MemberProfilePatchField<String> = nickname == baseline.nickname
            ? .unchanged : .set(nickname)
        let introductionValue = introduction.isEmpty ? nil : introduction
        let introductionField: MemberProfilePatchField<String> = introductionValue == baseline.introduction
            ? .unchanged : introductionValue.map(MemberProfilePatchField.set) ?? .clear
        let regionValue = region.isEmpty || region == "선택 안 함" ? nil : region
        let regionField: MemberProfilePatchField<String> = regionValue == baseline.region
            ? .unchanged : regionValue.map(MemberProfilePatchField.set) ?? .clear
        return MemberProfilePatch(nickname: nicknameField, introduction: introductionField, region: regionField)
    }

    static func weightPatch(baseline: MemberProfile, input: WeightInput) -> MemberProfilePatch {
        let field: MemberProfilePatchField<Decimal>
        switch input {
        case .empty:
            field = baseline.weightKg == nil ? .unchanged : .clear
        case .value(let value):
            field = baseline.weightKg == value ? .unchanged : .set(value)
        case .invalid:
            field = .unchanged
        }
        return MemberProfilePatch(weightKg: field)
    }
}
enum WSignupNicknameValidation {
    static let fixtureNicknames=["달빛러너","RunMate"]

    static func normalized(_ value:String)->String {
        value.precomposedStringWithCanonicalMapping
    }

    static func canonical(_ value:String)->String {normalized(value).lowercased()}

    static func error(for value:String)->String? {
        let name=normalized(value)
        guard !name.isEmpty else{return "닉네임을 입력해 주세요."}
        let scalars=Array(name.unicodeScalars)
        guard (2...12).contains(scalars.count) else{return "닉네임은 2~12자로 입력해 주세요."}
        guard scalars.allSatisfy({scalar in
            let code=scalar.value
            return (0xAC00...0xD7A3).contains(code) || (0x41...0x5A).contains(code) || (0x61...0x7A).contains(code) || (0x30...0x39).contains(code) || code==0x5F
        }) else{return "한글, 영문, 숫자, 밑줄만 사용할 수 있어요."}
        return nil
    }

    static func fixtureError(for value:String)->String? {
        fixtureNicknames.contains(where:{canonical($0)==canonical(value)}) ? "검토용 예시 계정에서 사용 중인 닉네임이에요.":nil
    }
}
enum WSocialLoginNavigationPolicy {
    static func canNavigateAway(from screen:String,completionSubmitted:Bool)->Bool {
        !completionSubmitted || !["A14","A03"].contains(screen)
    }
}
enum WSignupWeightValidation {
    static func error(for value:String)->String? {
        guard !value.isEmpty else{return nil}
        guard let weight=Double(value),weight.isFinite,(20...300).contains(weight) else{return "20~300 kg 사이로 입력하거나 비워 두세요."}
        return nil
    }
}
enum WRootTab: Int, CaseIterable {
    case points, run, home, community, profile
    static let homeMarkSize: CGFloat = 26

    var title: String {
        switch self {
        case .points: "포인트"
        case .run: "러닝"
        case .home: "홈"
        case .community: "커뮤니티"
        case .profile: "내 정보"
        }
    }

    var caption: String? { self == .home ? nil : title }

    var route: String { ["POINTS", "H01", "H00", "C01", "M01"][rawValue] }
    var assetName: String? { [nil, "run", nil, "community", "profile"][rawValue] }
}

enum WCommunityBottomTab:Int,CaseIterable {
    static let barHeight:CGFloat=64
    case feed,boards,home,crew,profile
    var title:String {switch self{case .feed:"피드";case .boards:"게시판";case .home:"홈";case .crew:"크루";case .profile:"내 프로필"}}
    var route:String {switch self{case .feed:"C01";case .boards:"C02";case .home:"H00";case .crew:"C15";case .profile:"C08"}}
    var accessibilityID:String {switch self{case .feed:"community-tab-feed";case .boards:"community-tab-boards";case .home:"community-tab-home";case .crew:"community-tab-crew";case .profile:"community-tab-profile"}}
    var systemImage:String? {switch self{case .feed:"text.bubble";case .boards:"square.grid.2x2";case .home:nil;case .crew:"person.3";case .profile:"person.crop.circle"}}
}

enum WireframeRemoteReadFeature: String, Equatable, Sendable {
    case profile
    case points
    case runs
    case progressGoals

    static func forScreen(_ screen: String) -> WireframeRemoteReadFeature? {
        switch screen {
        case "M01", "M02", "T02": .profile
        case "POINTS", "B02": .points
        case "L01", "L04", "L07": .runs
        case "H00", "H04", "H07", "H08", "H09", "H10": .progressGoals
        default: nil
        }
    }
}

enum WireframeDailyProgressTaskIdentity {
    static func key(screen: String, accountScopeID: String, range: BackendDailyProgressRange) -> String {
        let screenScope = ["H07","H08","H09"].contains(screen) ? "progress-statistics" : screen
        return "\(screenScope)|\(accountScopeID)|\(range.cacheKey)"
    }
}

struct WireframeRemoteReadDependencies {
    let memberProfileLoader: MemberProfileLoader?
    let memberProfileUpdater: (any MemberProfileUpdating)?
    let pointsWalletLoader: PointsWalletLoader?
    let runRecordsLoader: RunRecordsLoader?
    let runRecordsUpdater: (any RunRecordsUpdating)?
    let runRecordsDeleter: (any RunRecordsDeleting)?
    let runningProgressLoader: RunningProgressLoader?
    let weeklyGoalWriter: (any RunningWeeklyGoalWriting)?
    let sessionLogoutRequester: (any SessionLogoutRequesting)?
    let passwordResetService: (any PasswordResetServing)?
    let authSessionStore: (any AuthSessionStoring)?
    let authSessionClient: AuthSessionClient?
    let runUploadAPIClient: (any APIResponseSending)?
    let mediaUploadClient: MediaUploadClient?
    let communityMediaClient: CommunityMediaClient?
    let accountLinkFlow: (any AccountLinkFlowServing)?
    let accountLinkCredentialProvider: (any AccountLinkCredentialProviding)?
    let memberWithdrawalService: (any MemberWithdrawalServing)?

    init(
        memberProfileLoader: MemberProfileLoader? = nil,
        memberProfileUpdater: (any MemberProfileUpdating)? = nil,
        pointsWalletLoader: PointsWalletLoader? = nil,
        runRecordsLoader: RunRecordsLoader? = nil,
        runRecordsUpdater: (any RunRecordsUpdating)? = nil,
        runRecordsDeleter: (any RunRecordsDeleting)? = nil,
        runningProgressLoader: RunningProgressLoader? = nil,
        weeklyGoalWriter: (any RunningWeeklyGoalWriting)? = nil,
        sessionLogoutRequester: (any SessionLogoutRequesting)? = nil,
        passwordResetService: (any PasswordResetServing)? = nil,
        authSessionStore: (any AuthSessionStoring)? = nil,
        authSessionClient: AuthSessionClient? = nil,
        runUploadAPIClient: (any APIResponseSending)? = nil,
        mediaUploadClient: MediaUploadClient? = nil,
        communityMediaClient: CommunityMediaClient? = nil,
        accountLinkFlow: (any AccountLinkFlowServing)? = nil,
        accountLinkCredentialProvider: (any AccountLinkCredentialProviding)? = nil,
        memberWithdrawalService: (any MemberWithdrawalServing)? = nil
    ) {
        self.memberProfileLoader = memberProfileLoader
        self.memberProfileUpdater = memberProfileUpdater
        self.pointsWalletLoader = pointsWalletLoader
        self.runRecordsLoader = runRecordsLoader
        self.runRecordsUpdater = runRecordsUpdater
        self.runRecordsDeleter = runRecordsDeleter
        self.runningProgressLoader = runningProgressLoader
        self.weeklyGoalWriter = weeklyGoalWriter
        self.sessionLogoutRequester = sessionLogoutRequester
        self.passwordResetService = passwordResetService
        self.authSessionStore = authSessionStore
        self.authSessionClient = authSessionClient
        self.runUploadAPIClient = runUploadAPIClient
        self.mediaUploadClient = mediaUploadClient
        self.communityMediaClient = communityMediaClient
        self.accountLinkFlow = accountLinkFlow
        self.accountLinkCredentialProvider = accountLinkCredentialProvider
        self.memberWithdrawalService = memberWithdrawalService
    }
}

enum WireframeRunRecordEditState: Equatable {
    case idle
    case saving(runID: String, field: BackendRunEditField)
    case refreshingConflict(runID: String, field: BackendRunEditField)
    case failed(runID: String, field: BackendRunEditField, failure: RunRecordsFailure)
}

enum WireframeRunRecordDeleteState: Equatable {
    case idle
    case deleting(runID: String)
    case failed(runID: String, failure: RunRecordsFailure)
}

enum WireframeRunRecordsRefreshState: Equatable {
    case idle
    case refreshing
    case failed(RunRecordsFailure)
}

actor WireframeRunUploadSessionProvider: RunUploadSessionProviding {
    private let sessionStore:any AuthSessionStoring
    private let authClient:AuthSessionClient

    init(sessionStore:any AuthSessionStoring,authClient:AuthSessionClient){
        self.sessionStore=sessionStore
        self.authClient=authClient
    }

    func currentSession() async throws -> RunUploadSession? {
        guard let before=try sessionStore.loadSnapshot(),AuthSessionSnapshot.isCanonicalMemberID(before.memberID),
              let token=try await authClient.accessToken(),
              let after=try sessionStore.loadSnapshot(),after.memberID==before.memberID else{return nil}
        return RunUploadSession(ownerID:after.memberID,accessToken:token)
    }
}

#if DEBUG
@MainActor final class WireframeRunLocationFixture:RunLocationCapturing {
    var onFix:((RunLocationFix)->Void)?
    var onStatus:((String)->Void)?
    func start(){
        let now=Date()
        onStatus?("가짜 위치 측정 중")
        onFix?(RunLocationFix(recordedAt:now,latitude:37.56650,longitude:126.97800,accuracyMeters:4))
        onFix?(RunLocationFix(recordedAt:now.addingTimeInterval(0.1),latitude:37.56662,longitude:126.97800,accuracyMeters:4))
    }
    func stop(){onStatus?("일시정지 중")}
}

@MainActor final class WireframeRunUploadIdentityFixture:RunUploadMemberIdentityProviding {
    func currentAuthenticatedMemberID()->String?{"123"}
}

@MainActor final class WireframeOwnedRunRecordsFixture:RunStoreOwnedRecordsPersisting {
    private var records:[RunRecord]=[]
    func loadSnapshot() throws -> RunStoreOwnedRecordsSnapshot { .canonical(records) }
    func saveCanonical(_ records:[RunRecord]) throws { self.records=records }
}

actor WireframeRunUploadNetworkFixture:RunUploadEnqueueing,RunUploadDraining {
    private var pending:[(ownerID:String,payload:RunUploadPayload)]=[]
    private var drainAttempts=0
    func enqueueRunUpload(_ payload:RunUploadPayload,ownerID:String) async throws {
        if let existing=pending.first(where:{$0.ownerID==ownerID && $0.payload.clientRunID==payload.clientRunID}) {
            guard existing.payload==payload else{throw RunUploadOutboxFailure.duplicateClientRunIDConflict}
            return
        }
        pending.append((ownerID,payload))
    }
    func drain(ownerID:String) async throws -> RunUploadDrainReport {
        guard let index=pending.firstIndex(where:{$0.ownerID==ownerID}) else{return RunUploadDrainReport(uploadedCount:0,deletedCount:0,terminalCount:0,stopReason:.finished)}
        drainAttempts+=1
        if drainAttempts==1 {
            return RunUploadDrainReport(uploadedCount:0,deletedCount:0,terminalCount:0,stopReason:.retryLater(clientRunID:pending[index].payload.clientRunID,code:"TRANSPORT"))
        }
        let summary=Self.acceptedSummary(for:pending[index].payload)
        pending.remove(at:index)
        return RunUploadDrainReport(uploadedCount:1,deletedCount:0,terminalCount:0,stopReason:.finished,acceptedSummaries:[summary])
    }
    private static func acceptedSummary(for payload:RunUploadPayload)->BackendRunSummary {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian);formatter.timeZone=TimeZone(identifier:"Asia/Seoul");formatter.dateFormat="yyyy-MM-dd"
        let date=formatter.string(from:payload.startedAt)
        let distance=Int64(max(0,payload.distanceMeters))
        let seconds=Int64(max(0,payload.movingSeconds))
        let elapsed=Int64(max(payload.movingSeconds,Int(payload.endedAt.timeIntervalSince(payload.startedAt))))
        return BackendRunSummary(
            id:"fixture-\(payload.clientRunID.uuidString)",clientRunID:payload.clientRunID,version:1,
            startedAt:payload.startedAt,endedAt:payload.endedAt,runDate:date,elapsedSeconds:elapsed,
            movingSeconds:seconds,distanceMeters:distance,verdict:"VALID",verdictReason:nil,
            validDistanceMeters:distance,validSeconds:seconds,
            paceSecondsPerKm:distance>0 ? Int64(Double(seconds)*1_000/Double(distance)):nil,
            title:payload.title,memo:payload.memo,createdAt:payload.endedAt,updatedAt:payload.endedAt,pointReward:nil
        )
    }
}
#endif

enum SessionLogoutState: Equatable {
    case idle
    case loggingOut
    case loggedOut
    case failed(SessionLogoutFailure)
}

enum WireframeAccountLinkReauthentication: Equatable {
    case password
    case provider(AccountLinkProvider)
}

enum WireframeAccountLinkState: Equatable {
    case idle
    case loadingMethods
    case reauthenticating(WireframeAccountLinkReauthentication)
    case ready
    case linking(AccountLinkProvider)
    case submittingLink(AccountLinkProvider)
    case confirmingLinkStatus(AccountLinkProvider)
    case unlinking(AccountLinkProvider)
    case submittingUnlink(AccountLinkProvider)
    case confirmingUnlinkStatus(AccountLinkProvider)
    case completed
    case cancelled
    case failed(AccountLinkFailure)
}

enum WireframeMemberWithdrawalState: Equatable {
    case idle
    case loadingConfirmation
    case ready
    case submitting
    case cleaningLocalData(MemberWithdrawalReceipt)
    case failed(MemberWithdrawalFailure)
    case outcomeUnknown(MemberWithdrawalFailure)
    case accepted(MemberWithdrawalReceipt)
    case cleanupFailed(MemberWithdrawalReceipt)
}

#if DEBUG
enum AccountLinkDiagnosticClass: String {
    case unauthenticated
    case credentialsRejected = "credentials-rejected"
    case server
    case transport
    case cancelled
    case accountLink = "account-link"
    case unexpected

    static func classify(_ failure: AccountLinkFailure) -> Self {
        switch failure {
        case .unauthenticated:
            .unauthenticated
        case .invalidCredentials:
            .credentialsRejected
        case .serverFailure:
            .server
        case .transport:
            .transport
        case .cancelled:
            .cancelled
        default:
            .accountLink
        }
    }

    static func classify(_ error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        guard let failure = error as? AccountLinkFailure else { return .unexpected }
        return classify(failure)
    }
}

extension WireframeAccountLinkState {
    var testTraceLabel: String {
        switch self {
        case .idle: "idle"
        case .loadingMethods: "loading-methods"
        case .reauthenticating: "reauthenticating"
        case .ready: "ready"
        case .linking: "linking"
        case .submittingLink: "submitting-link"
        case .confirmingLinkStatus: "confirming-link-status"
        case .unlinking: "unlinking"
        case .submittingUnlink: "submitting-unlink"
        case .confirmingUnlinkStatus: "confirming-unlink-status"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed(let failure): "failed:\(AccountLinkDiagnosticClass.classify(failure).rawValue)"
        }
    }
}
#endif

@MainActor @Observable final class WireframeRemoteReadBridge {
    private enum ManualOperationKind: Equatable {
        case profileRetry
        case pointsRetry
        case pointsPage
        case runsRetry
        case runsPage
        case runDetailRetry
        case progressRetry
        case weeklyGoalRetry
        case weeklyGoalConflictRefresh
        case progressDailyRetry
    }

    private let memberProfileLoader: MemberProfileLoader?
    private let memberProfileUpdater: (any MemberProfileUpdating)?
    private let pointsWalletLoader: PointsWalletLoader?
    private let runRecordsLoader: RunRecordsLoader?
    private let runRecordsUpdater: (any RunRecordsUpdating)?
    private let runRecordsDeleter: (any RunRecordsDeleting)?
    private let runningProgressLoader: RunningProgressLoader?
    private let weeklyGoalWriter: (any RunningWeeklyGoalWriting)?
    private let sessionLogoutRequester: (any SessionLogoutRequesting)?
    private let authSessionStore: (any AuthSessionStoring)?
    private let authSessionClient: AuthSessionClient?
    private let accountLinkFlow: (any AccountLinkFlowServing)?
    private let memberWithdrawalService: (any MemberWithdrawalServing)?
    private let accountLinkProviderAuthorizationConfigured: Bool
    private(set) var accountLinkUnavailableFailure: AccountLinkFailure?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var dailyGeneration: UInt64 = 0
    @ObservationIgnored private var dailyProgressTask: Task<Void, Never>?
    @ObservationIgnored private var manualOperationID: UUID?
    @ObservationIgnored private var manualOperationTask: Task<Void, Never>?
    @ObservationIgnored private var manualOperationKind: ManualOperationKind?
    @ObservationIgnored private var manualPointsPreviousState: PointsWalletReadState?
    @ObservationIgnored private var manualRunsPreviousState: RunRecordsReadState?
    @ObservationIgnored private var weeklyGoalWriteOperationID: UUID?
    @ObservationIgnored private var weeklyGoalWriteTask: Task<Void, Never>?
    @ObservationIgnored private var sessionLogoutOperationID: UUID?
    @ObservationIgnored private var sessionLogoutTask: Task<Void, Never>?
    @ObservationIgnored private var accountLinkOperationID: UUID?
    @ObservationIgnored private var accountLinkOperationTask: Task<Void, Error>?
    @ObservationIgnored private var memberWithdrawalOperationID: UUID?
    @ObservationIgnored private var accountLinkMethodsRefreshOperationID: UUID?
    @ObservationIgnored private var unconfirmedAccountLinkMutation: AccountLinkMutation?
    @ObservationIgnored private var memberProfileWriteOperationID: UUID?
    @ObservationIgnored private var memberProfileWriteTask: Task<Void, Never>?
    @ObservationIgnored private var runRecordEditOperationID: UUID?
    @ObservationIgnored private var runRecordEditTask: Task<Bool, Never>?
    @ObservationIgnored private var runRecordDeleteOperationID: UUID?
    @ObservationIgnored private var runRecordDeleteTask: Task<Bool, Never>?
    @ObservationIgnored private var runRecordsRefreshOperationID: UUID?
    @ObservationIgnored private var runRecordsRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var runRecordsNeedsRefresh = false
    @ObservationIgnored private var staleRunDetailIDs: Set<String> = []
    @ObservationIgnored private var weeklyGoalNeedsRefresh = false
    @ObservationIgnored private var manualWeeklyGoalPreviousState: WeeklyGoalReadState?
    private(set) var accountScopeID: String?
    private(set) var activeFeature: WireframeRemoteReadFeature?
    private(set) var activeScreen: String?
    private(set) var memberProfileState: MemberProfileLoadState = .idle
    private(set) var memberProfileWriteState: MemberProfileWriteState = .idle
    private(set) var pointsState: PointsWalletReadState = .idle
    private(set) var runRecordsState: RunRecordsReadState = .idle
    private(set) var runRecordsRefreshState: WireframeRunRecordsRefreshState = .idle
    private(set) var runDetailState: RunDetailReadState = .idle
    private(set) var runRecordEditState: WireframeRunRecordEditState = .idle
    private(set) var runRecordDeleteState: WireframeRunRecordDeleteState = .idle
    private(set) var activeRunID: String?
    private(set) var progressState: ProgressReadState = .idle
    private(set) var weeklyGoalState: WeeklyGoalReadState = .idle
    private(set) var weeklyGoalWriteState: WeeklyGoalWriteState = .idle
    private(set) var weeklyGoalConflictRefreshState: WeeklyGoalConflictRefreshState = .idle
    private(set) var dailyProgressState: DailyProgressReadState = .idle
    private(set) var sessionLogoutState: SessionLogoutState = .idle
    private(set) var accountLinkMethods: AccountLinkMethods?
    private(set) var accountLinkState: WireframeAccountLinkState = .idle
    private(set) var accountLinkCompletedMutation: AccountLinkMutation?
    private(set) var memberWithdrawalState: WireframeMemberWithdrawalState = .idle
    private(set) var memberWithdrawalNotice: MemberWithdrawalConfirmationNotice?
    private(set) var memberWithdrawalReceipt: MemberWithdrawalReceipt?
    private(set) var memberWithdrawalMemberID: String?
#if DEBUG
    private let accountLinkTestTraceEnabled = ProcessInfo.processInfo.arguments.contains("-wire-account-link-action-trace")
    private(set) var accountLinkTestTrace = ""

    var exposesAccountLinkTestTrace:Bool { accountLinkTestTraceEnabled }
    func recordAccountLinkTestTrace(_ event: @autoclosure () -> String) {
        guard accountLinkTestTraceEnabled else{return}
        let event = event()
        accountLinkTestTrace = accountLinkTestTrace.isEmpty ? event : accountLinkTestTrace+" | "+event
    }
#endif

    init(dependencies: WireframeRemoteReadDependencies? = nil) {
        memberProfileLoader = dependencies?.memberProfileLoader
        memberProfileUpdater = dependencies?.memberProfileUpdater
        pointsWalletLoader = dependencies?.pointsWalletLoader
        runRecordsLoader = dependencies?.runRecordsLoader
        runRecordsUpdater = dependencies?.runRecordsUpdater
        runRecordsDeleter = dependencies?.runRecordsDeleter
        runningProgressLoader = dependencies?.runningProgressLoader
        weeklyGoalWriter = dependencies?.weeklyGoalWriter
        sessionLogoutRequester = dependencies?.sessionLogoutRequester
        authSessionStore = dependencies?.authSessionStore
        authSessionClient = dependencies?.authSessionClient
        memberWithdrawalService = dependencies?.memberWithdrawalService
        if let injectedFlow = dependencies?.accountLinkFlow {
            accountLinkFlow = injectedFlow
            accountLinkProviderAuthorizationConfigured = true
        } else {
            let args = ProcessInfo.processInfo.arguments
            let previewOnly = (args.contains("-wire-fixture") || args.contains("-wire-user-flow"))
                && !args.contains("-wire-account-link-unconfigured")
            if previewOnly {
                accountLinkFlow = nil
                accountLinkProviderAuthorizationConfigured = false
            } else {
                switch AccountLinkFlowFactory.resolve(
                    configuration: try? APIClientConfiguration.bundled(),
                    authSessionStore: dependencies?.authSessionStore,
                    credentialProvider: dependencies?.accountLinkCredentialProvider
                ) {
                case .available(let flow, let providerAuthorizationConfigured):
                    accountLinkFlow = flow
                    accountLinkProviderAuthorizationConfigured = providerAuthorizationConfigured
                case .unavailable(let failure):
                    accountLinkFlow = nil
                    accountLinkProviderAuthorizationConfigured = false
                    accountLinkUnavailableFailure = failure
                    accountLinkState = .failed(failure)
                }
            }
        }
    }

    var hasMemberProfileDependency: Bool { memberProfileLoader != nil }
    var canWriteMemberProfile: Bool { memberProfileUpdater != nil && memberProfileLoader != nil }
    var isSavingMemberProfile: Bool { memberProfileWriteState == .saving }
    var hasPointsDependency: Bool { pointsWalletLoader != nil }
    var hasRunRecordsDependency: Bool { runRecordsLoader != nil }
    var hasRunRecordsUpdater: Bool { runRecordsLoader != nil && runRecordsUpdater != nil }
    var hasRunRecordsDeleter: Bool { runRecordsLoader != nil && runRecordsDeleter != nil }
    var isSavingRunRecord: Bool {
        switch runRecordEditState {
        case .saving, .refreshingConflict: true
        case .idle, .failed: false
        }
    }
    func canEditRunRecord(_ runID: String) -> Bool {
        guard hasRunRecordsUpdater, activeFeature == .runs, activeScreen == "L04",
              activeRunID == runID, case .loaded(let detail) = runDetailState,
              detail.summary.id == runID, !isSavingRunRecord else { return false }
        if case .failed(let failedID, _, .recordNotFound) = runRecordEditState, failedID == runID { return false }
        return true
    }
    func runRecordEditFailure(runID: String, field: BackendRunEditField) -> RunRecordsFailure? {
        guard case .failed(let failedID, let failedField, let failure) = runRecordEditState,
              failedID == runID, failedField == field else { return nil }
        return failure
    }
    var isDeletingRunRecord: Bool {
        if case .deleting = runRecordDeleteState { return true }
        return false
    }
    func canDeleteRunRecord(_ runID: String) -> Bool {
        guard hasRunRecordsDeleter, activeFeature == .runs, activeScreen == "L07",
              activeRunID == runID, case .loaded(let detail) = runDetailState,
              detail.summary.id == runID, !isDeletingRunRecord else { return false }
        if case .failed(let failedID, let failure) = runRecordDeleteState, failedID == runID {
            return failure.canManuallyRetry
        }
        return true
    }
    func runRecordDeleteFailure(runID: String) -> RunRecordsFailure? {
        guard case .failed(let failedID, let failure) = runRecordDeleteState, failedID == runID else { return nil }
        return failure
    }
    var hasRunningProgressDependency: Bool { runningProgressLoader != nil }
    var canWriteWeeklyGoal: Bool { runningProgressLoader != nil && weeklyGoalWriter != nil }
    var isSavingWeeklyGoal: Bool { weeklyGoalWriteState == .saving }
    var hasSessionLogoutDependency: Bool { sessionLogoutRequester != nil }
    var isLoggingOut: Bool { sessionLogoutState == .loggingOut }
    var hasAccountLinkDependency: Bool { accountLinkFlow != nil }
    func isAccountLinkScreenActive(_ screen: String) -> Bool { activeScreen == screen }
    var shouldUseAccountLinkUI: Bool { hasAccountLinkDependency || accountLinkUnavailableFailure != nil }
    var canAuthorizeAccountLinkProvider: Bool { hasAccountLinkDependency && accountLinkProviderAuthorizationConfigured }
    var hasUnconfirmedAccountLink: Bool { unconfirmedAccountLinkMutation != nil }
    var canReauthenticateAccountLink: Bool {
        hasAccountLinkDependency && (accountLinkMethods?.localPassword == true || accountLinkProviderAuthorizationConfigured)
    }
    func isLastAccountLinkMethod(_ provider: AccountLinkProvider) -> Bool {
        guard let accountLinkMethods, accountLinkMethods.socialProviders.contains(provider) else { return false }
        return !accountLinkMethods.localPassword && accountLinkMethods.socialProviders.count <= 1
    }
    var isAccountLinkMutationInFlight: Bool {
        if hasUnconfirmedAccountLink { return true }
        if case .submittingLink = accountLinkState { return true }
        if case .confirmingLinkStatus = accountLinkState { return true }
        if case .submittingUnlink = accountLinkState { return true }
        if case .confirmingUnlinkStatus = accountLinkState { return true }
        return false
    }
    var hasMemberWithdrawalDependency: Bool { memberWithdrawalService != nil && authSessionClient != nil }
    var isMemberWithdrawalSubmitting: Bool {
        if case .submitting = memberWithdrawalState { return true }
        return false
    }
    var isMemberWithdrawalMutationInFlight: Bool {
        switch memberWithdrawalState {
        case .submitting, .cleaningLocalData, .cleanupFailed: true
        default: false
        }
    }
    var isMemberWithdrawalCleanupFailed: Bool {
        if case .cleanupFailed = memberWithdrawalState { return true }
        return false
    }
    var isMemberWithdrawalAccepted: Bool {
        if case .accepted = memberWithdrawalState { return true }
        return false
    }
    var memberWithdrawalFailure: MemberWithdrawalFailure? {
        switch memberWithdrawalState {
        case .failed(let failure), .outcomeUnknown(let failure): failure
        default: nil
        }
    }
    var isAccountLinkBusy: Bool {
        switch accountLinkState {
        case .loadingMethods, .reauthenticating, .linking, .submittingLink, .confirmingLinkStatus,
             .unlinking, .submittingUnlink, .confirmingUnlinkStatus: true
        case .idle, .ready, .completed, .cancelled, .failed: false
        }
    }
    var accountLinkFailure: AccountLinkFailure? {
        if case .failed(let failure) = accountLinkState { return failure }
        return nil
    }
    func canStartAccountLink(provider: AccountLinkProvider) -> Bool {
        guard shouldUseAccountLinkUI, hasAccountLinkDependency, canAuthorizeAccountLinkProvider,
              accountLinkMethods != nil, !isAccountLinkBusy, unconfirmedAccountLinkMutation == nil else { return false }
        return !(accountLinkMethods?.socialProviders.contains(provider) ?? false)
    }
    var needsWeeklyGoalConflictRefresh: Bool { weeklyGoalNeedsRefresh }
    var isEnabled: Bool { hasMemberProfileDependency || hasPointsDependency || hasRunRecordsDependency || hasRunningProgressDependency || hasAccountLinkDependency }

    func refreshAccountLinkMethods(expectedScreen: String? = nil) async {
        guard let accountLinkFlow, let accountScopeID, !isAccountLinkBusy else { return }
        let operationID=UUID()
        let requestGeneration=generation
        let previousState=accountLinkState
        accountLinkMethodsRefreshOperationID=operationID
        accountLinkState = .loadingMethods
        defer {
            if accountLinkMethodsRefreshOperationID==operationID { accountLinkMethodsRefreshOperationID=nil }
        }
        do {
            let methods = try await accountLinkFlow.methods()
            guard accountLinkMethodsRefreshOperationID==operationID else{return}
            guard self.accountScopeID==accountScopeID else{return}
            guard generation==requestGeneration else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            guard expectedScreen == nil || activeScreen == expectedScreen else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            accountLinkMethods = methods
            if let pending = unconfirmedAccountLinkMutation {
                unconfirmedAccountLinkMutation = nil
                if pending.isApplied(to: methods) {
                    accountLinkCompletedMutation = pending
                    accountLinkState = .completed
                } else {
                    accountLinkState = .failed(.completionNotApplied)
                }
            } else {
                accountLinkCompletedMutation = nil
                accountLinkState = .idle
            }
        } catch let failure as AccountLinkFailure {
            guard accountLinkMethodsRefreshOperationID==operationID else{return}
            guard self.accountScopeID==accountScopeID else{return}
            guard generation==requestGeneration else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            guard expectedScreen == nil || activeScreen == expectedScreen else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            accountLinkState = .failed(failure)
        } catch {
            guard accountLinkMethodsRefreshOperationID==operationID else{return}
            guard self.accountScopeID==accountScopeID else{return}
            guard generation==requestGeneration else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            guard expectedScreen == nil || activeScreen == expectedScreen else {
                if accountLinkState == .loadingMethods { accountLinkState=previousState }
                return
            }
            accountLinkState = .failed(.invalidResponse)
        }
    }

    func reauthenticateAccountLink(using provider: AccountLinkProvider, purpose: AccountLinkPurpose = .link, accountScopeID: String, screen: String) async -> Bool {
        guard let accountLinkFlow, !isAccountLinkBusy,
              self.accountScopeID == accountScopeID, activeScreen == screen, screen == "T15" else {
#if DEBUG
            recordAccountLinkTestTrace("reauth-core-guard-rejected:flow=\(accountLinkFlow != nil),busy=\(isAccountLinkBusy),scope=\(self.accountScopeID == accountScopeID),active=\(activeScreen ?? "nil"),screen=\(screen)")
#endif
            return false
        }
#if DEBUG
        recordAccountLinkTestTrace("reauth-core-start:\(provider.rawValue):\(purpose.rawValue)")
#endif
        let operationID = UUID()
        let operationGeneration=generation
        accountLinkOperationID = operationID
        accountLinkState = .reauthenticating(.provider(provider))
        let task = Task { try await accountLinkFlow.reauthenticate(using: provider, purpose: purpose) }
        accountLinkOperationTask = task
        do {
            try await task.value
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = .ready
#if DEBUG
            recordAccountLinkTestTrace("reauth-core-succeeded")
#endif
            return true
        } catch let failure as AccountLinkFailure {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = failure == .cancelled ? .cancelled : .failed(failure)
#if DEBUG
            recordAccountLinkTestTrace("reauth-core-failed:\(AccountLinkDiagnosticClass.classify(failure).rawValue)")
#endif
            if failure == .cancelled { await accountLinkFlow.cancel() }
            return false
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = .failed(.invalidResponse)
#if DEBUG
            recordAccountLinkTestTrace("reauth-core-error:\(AccountLinkDiagnosticClass.classify(error).rawValue)")
#endif
            return false
        }
    }

    func reauthenticateAccountLinkWithPassword(_ password: String, purpose: AccountLinkPurpose = .link, accountScopeID: String, screen: String) async -> Bool {
        guard let accountLinkFlow, !isAccountLinkBusy, self.accountScopeID == accountScopeID,
              activeScreen == screen, screen == "T15" else { return false }
        let operationID = UUID()
        let operationGeneration=generation
        accountLinkOperationID = operationID
        accountLinkState = .reauthenticating(.password)
        let task = Task { try await accountLinkFlow.reauthenticateWithPassword(password, purpose: purpose) }
        accountLinkOperationTask = task
        do {
            try await task.value
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = .ready
            return true
        } catch let failure as AccountLinkFailure {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = failure == .cancelled ? .cancelled : .failed(failure)
            if failure == .cancelled { await accountLinkFlow.cancel() }
            return false
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = .failed(.invalidResponse)
            return false
        }
    }

    func linkAccountMethod(provider: AccountLinkProvider, accountScopeID: String, screen: String) async -> Bool {
        guard let accountLinkFlow, !isAccountLinkBusy, accountLinkState == .ready,
              self.accountScopeID == accountScopeID, activeScreen == screen, screen == "T06" else {
            return false
        }
        let operationID = UUID()
        let operationGeneration=generation
        accountLinkOperationID = operationID
        accountLinkCompletedMutation = nil
        accountLinkState = .linking(provider)
        let task = Task { [weak self] in
            try await accountLinkFlow.link(provider: provider) {
                await MainActor.run {
                    guard let self,
                          self.accountLinkOperationID == operationID,
                          self.accountScopeID == accountScopeID,
                          self.generation == operationGeneration,
                          self.activeScreen == screen,
                          self.accountLinkState == .linking(provider) else { return false }
                    self.accountLinkState = .submittingLink(provider)
                    return true
                }
            }
        }
        accountLinkOperationTask = task
        do {
            try await task.value
            guard accountLinkOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == operationGeneration,
                  activeScreen == screen else { return false }
            accountLinkOperationTask = nil
            unconfirmedAccountLinkMutation = nil
            accountLinkCompletedMutation = .link(provider)
            if let methods=accountLinkMethods, !methods.socialProviders.contains(provider) {
                accountLinkMethods=AccountLinkMethods(localPassword:methods.localPassword,socialProviders:methods.socialProviders+[provider])
            }
            accountLinkState = .completed
            await refreshAccountLinkMethodsAfterConfirmedMutation(
                operationID:operationID,
                accountScopeID:accountScopeID,
                generation:operationGeneration
            )
            return true
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration else { return false }
            let failure = (error as? AccountLinkFailure) ?? (error is CancellationError ? .cancelled : .invalidResponse)
            let mutationWasSubmitted: Bool
            if case .submittingLink(let submittedProvider) = accountLinkState, submittedProvider == provider {
                mutationWasSubmitted = true
            } else {
                mutationWasSubmitted = false
            }
            if mutationWasSubmitted {
                return await reconcileAccountLinkCompletion(
                    mutation: .link(provider),
                    originalFailure: failure,
                    operationID: operationID,
                    accountScopeID:accountScopeID,
                    generation:operationGeneration,
                    screen:screen
                )
            }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = failure == .cancelled ? .cancelled : .failed(failure)
            if failure == .cancelled { await accountLinkFlow.cancel() }
            if failure == .alreadyLinked { await refreshAccountLinkMethods(expectedScreen:"T06") }
            return false
        }
    }

    func unlinkAccountMethod(provider: AccountLinkProvider, accountScopeID: String, screen: String) async -> Bool {
        guard let accountLinkFlow, !isAccountLinkBusy, accountLinkState == .ready,
              self.accountScopeID == accountScopeID, activeScreen == screen, screen == "T15",
              accountLinkMethods?.socialProviders.contains(provider) == true else {
#if DEBUG
            recordAccountLinkTestTrace("unlink-core-guard-rejected:flow=\(accountLinkFlow != nil),busy=\(isAccountLinkBusy),state=\(accountLinkState.testTraceLabel),scope=\(self.accountScopeID == accountScopeID),active=\(activeScreen ?? "nil"),screen=\(screen),methodLinked=\(accountLinkMethods?.socialProviders.contains(provider) == true)")
#endif
            return false
        }
#if DEBUG
        recordAccountLinkTestTrace("unlink-core-start:\(provider.rawValue)")
#endif
        let operationID = UUID()
        let operationGeneration=generation
        accountLinkOperationID = operationID
        accountLinkCompletedMutation = nil
        accountLinkState = .unlinking(provider)
        let task = Task { [weak self] in
            try await accountLinkFlow.unlink(provider: provider) {
                await MainActor.run {
                    guard let self else { return false }
                    guard self.accountLinkOperationID == operationID,
                          self.accountScopeID == accountScopeID,
                          self.generation == operationGeneration,
                          self.activeScreen == screen,
                          self.accountLinkState == .unlinking(provider) else {
#if DEBUG
                        self.recordAccountLinkTestTrace("unlink-submit-guard-rejected:op=\(self.accountLinkOperationID == operationID),scope=\(self.accountScopeID == accountScopeID),generation=\(self.generation == operationGeneration),active=\(self.activeScreen ?? "nil"),state=\(self.accountLinkState.testTraceLabel)")
#endif
                        return false
                    }
                    self.accountLinkState = .submittingUnlink(provider)
#if DEBUG
                    self.recordAccountLinkTestTrace("unlink-submit-accepted")
#endif
                    return true
                }
            }
        }
        accountLinkOperationTask = task
        do {
            try await task.value
            guard accountLinkOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == operationGeneration,
                  activeScreen == screen else { return false }
            accountLinkOperationTask = nil
            unconfirmedAccountLinkMutation = nil
            accountLinkCompletedMutation = .unlink(provider)
            if let methods=accountLinkMethods {
                accountLinkMethods=AccountLinkMethods(
                    localPassword:methods.localPassword,
                    socialProviders:methods.socialProviders.filter{$0 != provider}
                )
            }
            accountLinkState = .completed
#if DEBUG
            recordAccountLinkTestTrace("unlink-core-confirmed-response")
#endif
            await refreshAccountLinkMethodsAfterConfirmedMutation(
                operationID:operationID,
                accountScopeID:accountScopeID,
                generation:operationGeneration
            )
            return true
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration else { return false }
            let failure = (error as? AccountLinkFailure) ?? (error is CancellationError ? .cancelled : .invalidResponse)
            let mutationWasSubmitted: Bool
            if case .submittingUnlink(let submittedProvider) = accountLinkState, submittedProvider == provider {
                mutationWasSubmitted = true
            } else {
                mutationWasSubmitted = false
            }
            if mutationWasSubmitted {
#if DEBUG
                recordAccountLinkTestTrace("unlink-response-error-after-submit:\(AccountLinkDiagnosticClass.classify(failure).rawValue)")
#endif
                return await reconcileAccountLinkCompletion(
                    mutation: .unlink(provider),
                    originalFailure: failure,
                    operationID: operationID,
                    accountScopeID:accountScopeID,
                    generation:operationGeneration,
                    screen:screen
                )
            }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            accountLinkState = failure == .cancelled ? .cancelled : .failed(failure)
#if DEBUG
            recordAccountLinkTestTrace("unlink-failed-before-confirmation:\(AccountLinkDiagnosticClass.classify(failure).rawValue)")
#endif
            if failure == .cancelled { await accountLinkFlow.cancel() }
            return false
        }
    }

    private func refreshAccountLinkMethodsAfterConfirmedMutation(
        operationID:UUID,
        accountScopeID:String,
        generation operationGeneration:UInt64
    ) async {
        guard let accountLinkFlow else {
            if accountLinkOperationID==operationID { accountLinkOperationID=nil }
            return
        }
        let readOperationID=UUID()
        accountLinkMethodsRefreshOperationID=readOperationID
        defer {
            if accountLinkMethodsRefreshOperationID==readOperationID {
                accountLinkMethodsRefreshOperationID=nil
            }
        }
        do {
            let methods=try await accountLinkFlow.methods()
            guard accountLinkOperationID==operationID else{return}
            guard accountLinkMethodsRefreshOperationID==readOperationID,
                  self.accountScopeID==accountScopeID,
                  self.generation==operationGeneration else {
                accountLinkOperationID=nil
                accountLinkOperationTask=nil
                return
            }
            accountLinkMethods=methods
            accountLinkOperationID=nil
            accountLinkOperationTask=nil
#if DEBUG
            recordAccountLinkTestTrace("confirmed-mutation-methods-refresh-succeeded")
#endif
        } catch {
            guard accountLinkOperationID==operationID else{return}
            accountLinkOperationID=nil
            accountLinkOperationTask=nil
#if DEBUG
            recordAccountLinkTestTrace("confirmed-mutation-methods-refresh-failed:\(AccountLinkDiagnosticClass.classify(error).rawValue);state=\(accountLinkState.testTraceLabel)")
#endif
        }
    }

    private func reconcileAccountLinkCompletion(
        mutation: AccountLinkMutation,
        originalFailure: AccountLinkFailure,
        operationID: UUID,
        accountScopeID:String,
        generation operationGeneration:UInt64,
        screen:String
    ) async -> Bool {
        guard let accountLinkFlow,
              accountLinkOperationID == operationID,
              self.accountScopeID==accountScopeID,
              generation==operationGeneration,
              activeScreen==screen else { return false }
#if DEBUG
        recordAccountLinkTestTrace("unlink-reconciliation-start")
#endif
        switch mutation {
        case .link(let provider): accountLinkState = .confirmingLinkStatus(provider)
        case .unlink(let provider): accountLinkState = .confirmingUnlinkStatus(provider)
        }
        do {
            let methods = try await accountLinkFlow.methods()
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkMethods = methods
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            if mutation.isApplied(to: methods) {
                unconfirmedAccountLinkMutation = nil
                accountLinkCompletedMutation = mutation
                accountLinkState = .completed
#if DEBUG
                recordAccountLinkTestTrace("mutation-reconciliation-confirmed")
#endif
                return true
            }
            unconfirmedAccountLinkMutation = nil
            accountLinkState = .failed(originalFailure == .cancelled ? .completionNotApplied : originalFailure)
#if DEBUG
            recordAccountLinkTestTrace("mutation-reconciliation-not-applied:\(AccountLinkDiagnosticClass.classify(originalFailure).rawValue)")
#endif
            return false
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkOperationTask = nil
            unconfirmedAccountLinkMutation = mutation
            accountLinkState = .failed(.completionStatusUnknown)
#if DEBUG
            recordAccountLinkTestTrace("mutation-reconciliation-status-read-failed:\(AccountLinkDiagnosticClass.classify(error).rawValue)")
#endif
            return false
        }
    }

    func retryAccountLinkStatusConfirmation(accountScopeID: String, screen: String) async -> Bool {
        guard let mutation = unconfirmedAccountLinkMutation, let accountLinkFlow, !isAccountLinkBusy,
              self.accountScopeID == accountScopeID, activeScreen == screen else { return false }
        let expectedScreen: String
        switch mutation {
        case .link: expectedScreen = "T06"
        case .unlink: expectedScreen = "T15"
        }
        guard screen == expectedScreen else { return false }
        let operationID = UUID()
        let operationGeneration=generation
        accountLinkOperationID = operationID
        switch mutation {
        case .link(let provider): accountLinkState = .confirmingLinkStatus(provider)
        case .unlink(let provider): accountLinkState = .confirmingUnlinkStatus(provider)
        }
        do {
            let methods = try await accountLinkFlow.methods()
            guard accountLinkOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation==operationGeneration,
                  activeScreen == screen else { return false }
            accountLinkMethods = methods
            accountLinkOperationID = nil
            unconfirmedAccountLinkMutation = nil
            if mutation.isApplied(to: methods) {
                accountLinkCompletedMutation = mutation
                accountLinkState = .completed
                return true
            }
            accountLinkState = .failed(.completionNotApplied)
            return false
        } catch {
            guard accountLinkOperationID == operationID,
                  self.accountScopeID==accountScopeID,
                  generation==operationGeneration,
                  activeScreen==screen else { return false }
            accountLinkOperationID = nil
            accountLinkState = .failed(.completionStatusUnknown)
            return false
        }
    }

    @discardableResult
    func cancelAccountLinkFlow() -> Bool {
        guard !isAccountLinkMutationInFlight else { return false }
        let operationTask = accountLinkOperationTask
        accountLinkOperationID = nil
        accountLinkOperationTask = nil
        accountLinkState = .cancelled
        operationTask?.cancel()
        Task { await accountLinkFlow?.cancel() }
        return true
    }

    func loadMemberWithdrawalConfirmation(accountScopeID: String, screen: String) async {
        guard let service = memberWithdrawalService,
              self.accountScopeID == accountScopeID, activeScreen == screen, screen == "T11",
              !isMemberWithdrawalSubmitting else { return }
        let operationID = UUID()
        let requestGeneration = generation
        memberWithdrawalOperationID = operationID
        memberWithdrawalState = .loadingConfirmation
        do {
            let notice = try await service.confirmationNotice()
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return }
            memberWithdrawalNotice = notice
            memberWithdrawalState = .ready
        } catch let failure as MemberWithdrawalFailure {
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return }
            memberWithdrawalState = failure.outcomeUnknown ? .outcomeUnknown(failure) : .failed(failure)
        } catch {
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return }
            memberWithdrawalState = .failed(.invalidResponse)
        }
        if memberWithdrawalOperationID == operationID { memberWithdrawalOperationID = nil }
    }

    func submitMemberWithdrawal(accountScopeID: String, screen: String) async -> MemberWithdrawalReceipt? {
        guard let service = memberWithdrawalService, let accountLinkFlow,
              hasMemberWithdrawalDependency,
              self.accountScopeID == accountScopeID, activeScreen == screen, screen == "T16",
              memberWithdrawalNotice != nil, !isMemberWithdrawalSubmitting else { return nil }
        let operationID = UUID()
        let requestGeneration = generation
        memberWithdrawalOperationID = operationID
        memberWithdrawalReceipt = nil
        memberWithdrawalState = .submitting
        do {
            guard let authSessionStore else { throw MemberWithdrawalFailure.accessTokenUnavailable }
            let snapshot: AuthSessionSnapshot?
            do { snapshot = try authSessionStore.loadSnapshot() }
            catch { throw MemberWithdrawalFailure.accessTokenUnavailable }
            guard let snapshot else { throw MemberWithdrawalFailure.accessTokenUnavailable }
            memberWithdrawalMemberID = snapshot.memberID
            let proof = try await accountLinkFlow.consumeReauthenticationProof(for: .withdrawal)
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return nil }
            let receipt = try await service.requestWithdrawal(reauthProof: proof, confirmed: true)
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return nil }
            memberWithdrawalReceipt = receipt
            memberWithdrawalState = .accepted(receipt)
            memberWithdrawalOperationID = nil
            return receipt
        } catch let failure as MemberWithdrawalFailure {
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return nil }
            memberWithdrawalState = failure.outcomeUnknown ? .outcomeUnknown(failure) : .failed(failure)
        } catch let failure as AccountLinkFailure {
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return nil }
            memberWithdrawalState = .failed(failure == .cancelled ? .cancelled : .reauthenticationRequired)
        } catch {
            guard memberWithdrawalOperationID == operationID,
                  self.accountScopeID == accountScopeID,
                  generation == requestGeneration, activeScreen == screen else { return nil }
            memberWithdrawalState = .failed(.invalidResponse)
        }
        if memberWithdrawalOperationID == operationID { memberWithdrawalOperationID = nil }
        return nil
    }

    @discardableResult
    func cancelMemberWithdrawalFlow() -> Bool {
        guard !isMemberWithdrawalSubmitting else { return false }
        memberWithdrawalOperationID = nil
        memberWithdrawalNotice = nil
        memberWithdrawalReceipt = nil
        memberWithdrawalMemberID = nil
        memberWithdrawalState = .idle
        let cancelled = cancelAccountLinkFlow()
        if !cancelled { Task { await accountLinkFlow?.cancel() } }
        return true
    }

    func markMemberWithdrawalCleanupFailed(_ receipt: MemberWithdrawalReceipt) {
        guard memberWithdrawalReceipt == receipt else { return }
        memberWithdrawalState = .cleanupFailed(receipt)
    }

    func beginMemberWithdrawalCleanup(_ receipt: MemberWithdrawalReceipt) {
        guard memberWithdrawalReceipt == receipt else { return }
        memberWithdrawalState = .cleaningLocalData(receipt)
    }

    func completeMemberWithdrawalCleanup(_ receipt: MemberWithdrawalReceipt) {
        guard memberWithdrawalReceipt == receipt else { return }
        memberWithdrawalState = .accepted(receipt)
    }

    func retryMemberWithdrawalCleanup() {
        guard let receipt = memberWithdrawalReceipt else { return }
        memberWithdrawalState = .accepted(receipt)
    }

    func requestSessionLogout(accountScopeID: String, screen: String) {
        guard let requester = sessionLogoutRequester,
              self.accountScopeID == accountScopeID,
              activeScreen == screen,
              sessionLogoutState != .loggedOut,
              sessionLogoutOperationID == nil else { return }

        let operationID = UUID()
        let requestGeneration = generation
        sessionLogoutOperationID = operationID
        sessionLogoutState = .loggingOut
        sessionLogoutTask = Task { [weak self] in
            let result: Result<Void, SessionLogoutFailure>
            do {
                try await requester.logout()
                result = .success(())
            } catch let failure as SessionLogoutFailure {
                result = .failure(failure)
            } catch is CancellationError {
                result = .failure(.cancelled)
            } catch {
                result = .failure(.invalidResponse)
            }
            guard let self else { return }
            self.completeSessionLogout(
                result,
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen
            )
        }
    }

    private func completeSessionLogout(
        _ result: Result<Void, SessionLogoutFailure>,
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String,
        screen: String
    ) {
        guard sessionLogoutOperationID == operationID,
              generation == requestGeneration,
              self.accountScopeID == accountScopeID,
              activeScreen == screen else { return }
        sessionLogoutTask = nil
        sessionLogoutOperationID = nil
        switch result {
        case .success:
            sessionLogoutState = .loggedOut
        case .failure(.unauthenticated):
            // The API contract treats 401 as an invalid session; the client must leave it.
            sessionLogoutState = .loggedOut
        case .failure(.sessionChanged):
            // A concurrent request for this same logout may have already cleared the
            // shared store. Treat that as the same completed intent, while retaining
            // the account-change boundary when a newer session is present.
            if let authSessionStore {
                do {
                    sessionLogoutState = try authSessionStore.loadSnapshot() == nil ? .loggedOut : .failed(.sessionChanged)
                } catch {
                    sessionLogoutState = .failed(.storageUnavailable)
                }
            } else {
                sessionLogoutState = .failed(.sessionChanged)
            }
        case .failure(.cancelled):
            sessionLogoutState = .idle
        case .failure(let failure):
            sessionLogoutState = .failed(failure)
        }
    }

    private func cancelSessionLogout() {
        let task = sessionLogoutTask
        sessionLogoutTask = nil
        sessionLogoutOperationID = nil
        sessionLogoutState = .idle
        task?.cancel()
    }

    private func invalidateDailyProgressRead() {
        dailyGeneration &+= 1
        dailyProgressTask?.cancel()
        dailyProgressTask = nil
    }

    func accountDidChange(to nextScopeID: String) {
        guard accountScopeID != nextScopeID else { return }
        guard !isAccountLinkMutationInFlight else { return }
        let preserveAcceptedWithdrawal: Bool = {
            if case .accepted = memberWithdrawalState { return true }
            return false
        }()
        let withdrawalWasSubmitting = isMemberWithdrawalSubmitting
        memberWithdrawalOperationID = nil
        if !preserveAcceptedWithdrawal {
            memberWithdrawalNotice = nil
            memberWithdrawalReceipt = nil
            memberWithdrawalMemberID = nil
            memberWithdrawalState = withdrawalWasSubmitting
                ? .outcomeUnknown(.transport(.cancelled, outcomeUnknown: true))
                : .idle
        }
        cancelRunRecordsRefresh(markNeedsRefresh: false)
        cancelSessionLogout()
        cancelAccountLinkFlow()
        accountLinkMethods = nil
        accountLinkMethodsRefreshOperationID = nil
        unconfirmedAccountLinkMutation = nil
        accountLinkCompletedMutation = nil
        accountLinkState = .idle
        cancelMemberProfileMutation()
        cancelWeeklyGoalMutation()
        cancelRunRecordEdit()
        cancelRunRecordDeletion(markStale: false)
        cancelManualOperation()
        generation &+= 1
        invalidateDailyProgressRead()
        accountScopeID = nextScopeID
        activeFeature = nil
        activeScreen = nil
        memberProfileState = .idle
        memberProfileWriteState = .idle
        pointsState = .idle
        runRecordsState = .idle
        runDetailState = .idle
        runRecordsNeedsRefresh = false
        runRecordsRefreshState = .idle
        staleRunDetailIDs.removeAll()
        runRecordEditState = .idle
        runRecordDeleteState = .idle
        activeRunID = nil
        progressState = .idle
        weeklyGoalState = .idle
        weeklyGoalWriteState = .idle
        weeklyGoalNeedsRefresh = false
        weeklyGoalConflictRefreshState = .idle
        manualWeeklyGoalPreviousState = nil
        dailyProgressState = .idle
    }

    func activate(
        feature: WireframeRemoteReadFeature?,
        accountScopeID: String,
        runID: String? = nil,
        screen: String? = nil,
        routeIsCurrent: @MainActor () -> Bool = { true }
    ) async {
        let routeStillCurrent=routeIsCurrent()
        guard !Task.isCancelled, routeStillCurrent else { return }
        if self.accountScopeID != accountScopeID { accountDidChange(to: accountScopeID) }
        let previousScreen = activeScreen
        let nextScreen = screen ?? feature?.rawValue
        guard !isAccountLinkMutationInFlight || (self.accountScopeID == accountScopeID && nextScreen == activeScreen) else { return }
        if activeFeature == .runs, activeScreen == "L01",
           (feature != .runs || nextScreen != "L01" || runID != nil) {
            runRecordsNeedsRefresh = true
            cancelRunRecordsRefresh()
        }
        if activeScreen != nextScreen { cancelSessionLogout() }
        if runRecordEditOperationID != nil,
           (feature != .runs || activeScreen != nextScreen || (feature == .runs && activeRunID != runID)) {
            cancelRunRecordEdit()
        }
        if runRecordEditState != .idle,
           (feature != .runs || activeScreen != nextScreen || (feature == .runs && activeRunID != runID)) {
            runRecordEditState = .idle
        }
        if runRecordDeleteOperationID != nil,
           (feature != .runs || activeScreen != nextScreen || activeRunID != runID || nextScreen != "L07") {
            cancelRunRecordDeletion()
        }
        if runRecordDeleteState != .idle,
           (feature != .runs || activeScreen != nextScreen || activeRunID != runID || nextScreen != "L07") {
            runRecordDeleteState = .idle
        }
        if weeklyGoalConflictRefreshState == .refreshed, nextScreen != activeScreen {
            weeklyGoalConflictRefreshState = .idle
        }
        if weeklyGoalWriteOperationID != nil, nextScreen != activeScreen {
            cancelWeeklyGoalMutation()
        }
        if memberProfileWriteOperationID != nil, nextScreen != activeScreen {
            cancelMemberProfileMutation()
        }
        if activeFeature == feature, activeScreen == nextScreen, activeRunID == (feature == .runs ? runID : nil) {
            return
        }
        let sameFeature = activeFeature == feature && feature != nil
        cancelManualOperation(restorePreviousState: sameFeature)
        generation &+= 1
        let requestGeneration = generation
        activeFeature = feature
        activeScreen = nextScreen

        let preserveUnlinkFailure = previousScreen == "T15" && nextScreen == "T08"
            && { if case .failed = accountLinkState { return true }; return false }()
        let preservingWithdrawalProof = previousScreen == "T15" && nextScreen == "T11"
        if (previousScreen == "T15" || previousScreen == "T06"), !preservingWithdrawalProof,
           nextScreen != "T15", nextScreen != "T06", accountLinkState != .completed, !preserveUnlinkFailure {
            cancelAccountLinkFlow()
        }
        let leavingWithdrawalFlow = ["T11", "T16"].contains(previousScreen ?? "")
            && !["T11", "T16", "T15", "T12"].contains(nextScreen ?? "")
        if leavingWithdrawalFlow && !isMemberWithdrawalAccepted {
            _ = cancelMemberWithdrawalFlow()
        }
        if nextScreen == "T05" || nextScreen == "T15" {
            await refreshAccountLinkMethods(expectedScreen:nextScreen)
        }
        if nextScreen == "T11", hasMemberWithdrawalDependency {
            await loadMemberWithdrawalConfirmation(accountScopeID: accountScopeID, screen: "T11")
        }

        guard let feature else {
            memberProfileState = .idle
            pointsState = .idle
            runRecordsState = .idle
            runDetailState = .idle
            runRecordDeleteState = .idle
            activeRunID = nil
            progressState = .idle
            weeklyGoalState = .idle
            dailyProgressState = .idle
            invalidateDailyProgressRead()
            return
        }

        if !sameFeature {
            memberProfileState = .idle
            pointsState = .idle
            runRecordsState = .idle
            runDetailState = .idle
            runRecordDeleteState = .idle
            activeRunID = nil
            progressState = .idle
            weeklyGoalState = .idle
            dailyProgressState = .idle
            invalidateDailyProgressRead()
        } else {
            if memberProfileState == .loading { memberProfileState = .idle }
            switch pointsState {
            case .loading, .loadingMore:
                pointsState = .idle
            default:
                break
            }
            if activeRunID != runID { runDetailState = .idle }
            if feature == .progressGoals {
                if progressState == .loading { progressState = .idle }
                if weeklyGoalState == .loading { weeklyGoalState = .idle }
                if !["H07","H08","H09"].contains(nextScreen ?? "") {
                    dailyProgressState = .idle
                    invalidateDailyProgressRead()
                }
            }
        }
        activeRunID = feature == .runs ? runID : nil

        switch feature {
        case .profile:
            guard let memberProfileLoader else { memberProfileState = .idle; return }
            guard memberProfileState == .idle else { return }
            memberProfileState = .loading
            await memberProfileLoader.load()
            let result = await memberProfileLoader.state
            guard requestGeneration == generation else { return }
            if Task.isCancelled {
                memberProfileState = .idle
                activeFeature = nil
            } else {
                memberProfileState = result
            }
        case .points:
            guard let pointsWalletLoader else { pointsState = .idle; return }
            guard pointsState == .idle else { return }
            pointsState = .loading
            await pointsWalletLoader.load()
            let result = await pointsWalletLoader.state
            guard requestGeneration == generation else { return }
            if Task.isCancelled {
                pointsState = .idle
                activeFeature = nil
            } else {
                pointsState = result
            }
        case .runs:
            guard let runRecordsLoader else { runRecordsState = .idle; runDetailState = .idle; return }
            if let runID {
                let detailNeedsRefresh = staleRunDetailIDs.contains(runID)
                if case .loaded(let detail) = runDetailState, detail.summary.id == runID, !detailNeedsRefresh { return }
                if case .failed(let failedID, _) = runDetailState, failedID == runID, !detailNeedsRefresh { return }
                runDetailState = .loading(runID: runID)
                await runRecordsLoader.loadDetail(runID: runID)
                let result = await runRecordsLoader.detailState
                guard requestGeneration == generation else { return }
                if Task.isCancelled {
                    runDetailState = .idle
                    activeFeature = nil
                } else {
                    runDetailState = result
                    if case .loaded(let detail) = result, detail.summary.id == runID {
                        staleRunDetailIDs.remove(runID)
                    }
                    if case .failed(let failedID, .recordNotFound) = result, failedID == runID {
                        invalidateRunListAfterMissingRecord(runID: runID)
                    }
                }
            } else {
                if runRecordsNeedsRefresh {
                    await refreshRunRecords()
                    return
                }
                guard runRecordsState == .idle else { return }
                runRecordsState = .loading
                await runRecordsLoader.load()
                let result = await runRecordsLoader.state
                guard requestGeneration == generation else { return }
                if Task.isCancelled {
                    runRecordsState = .idle
                    activeFeature = nil
                } else {
                    runRecordsState = result
                    if case .loaded = result { runRecordsNeedsRefresh = false }
                }
            }
        case .progressGoals:
            guard let runningProgressLoader else {
                progressState = .idle
                weeklyGoalState = .idle
                dailyProgressState = .idle
                return
            }
            let shouldLoadProgress = progressState == .idle
            let shouldLoadWeeklyGoal = weeklyGoalState == .idle || weeklyGoalNeedsRefresh
            guard shouldLoadProgress || shouldLoadWeeklyGoal else { return }
            if shouldLoadProgress { progressState = .loading }
            if shouldLoadWeeklyGoal {
                weeklyGoalState = .loading
                if weeklyGoalNeedsRefresh { weeklyGoalConflictRefreshState = .refreshing }
            }
            if shouldLoadProgress && shouldLoadWeeklyGoal {
                async let progressRead: Void = completeProgressRead(using: runningProgressLoader, generation: requestGeneration)
                async let weeklyGoalRead: Void = completeWeeklyGoalRead(using: runningProgressLoader, generation: requestGeneration)
                await progressRead
                await weeklyGoalRead
            } else if shouldLoadProgress {
                await completeProgressRead(using: runningProgressLoader, generation: requestGeneration)
            } else {
                await completeWeeklyGoalRead(using: runningProgressLoader, generation: requestGeneration)
            }
        }
    }

    func refreshRunRecords() async {
        guard let operation = beginRunRecordsRefresh() else { return }
        await withTaskCancellationHandler {
            await operation.task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRunRecordsRefresh(operationID: operation.operationID)
            }
        }
    }

    private func beginRunRecordsRefresh() -> (operationID: UUID, task: Task<Void, Never>)? {
        guard let loader = runRecordsLoader,
              runRecordsRefreshOperationID == nil,
              activeFeature == .runs,
              activeScreen == "L01",
              activeRunID == nil,
              let accountScopeID else { return nil }

        let operationID = UUID()
        let requestGeneration = generation
        runRecordsRefreshOperationID = operationID
        runRecordsNeedsRefresh = true
        switch runRecordsState {
        case .idle, .failed:
            runRecordsState = .loading
        default:
            break
        }
        runRecordsRefreshState = .refreshing
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRunRecordsRefresh(
                using: loader,
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID
            )
        }
        runRecordsRefreshTask = task
        return (operationID, task)
    }

    private func performRunRecordsRefresh(
        using loader: RunRecordsLoader,
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String
    ) async {
        var restartAfterStaleCompletion = false
        defer {
            if runRecordsRefreshOperationID == operationID {
                runRecordsRefreshTask = nil
                runRecordsRefreshOperationID = nil
                if restartAfterStaleCompletion,
                   runRecordsNeedsRefresh,
                   self.accountScopeID == accountScopeID,
                   activeFeature == .runs,
                   activeScreen == "L01",
                   activeRunID == nil {
                    _ = beginRunRecordsRefresh()
                }
            }
        }

        do {
            let candidate = try await loader.fetchCompleteList()
            guard isCurrentRunRecordsRefresh(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID
            ) else {
                await loader.discardCompleteList(candidate)
                return
            }
            guard await loader.applyCompleteList(candidate) else {
                runRecordsRefreshState = .idle
                runRecordsNeedsRefresh = true
                restartAfterStaleCompletion = true
                return
            }
            runRecordsState = await loader.state
            // A successful list refresh can prove that a previously viewed run was deleted.
            // Keep that explicit not-found result, but do not restore a still-existing detail
            // into the list screen after returning from an edit.
            if case .failed(let runID, .recordNotFound) = await loader.detailState {
                runDetailState = .failed(runID: runID, .recordNotFound)
            } else {
                runDetailState = .idle
            }
            runRecordsNeedsRefresh = false
            runRecordsRefreshState = .idle
        } catch let failure as RunRecordsFailure {
            guard isCurrentRunRecordsRefresh(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID
            ) else { return }
            if failure == .cancelled || Task.isCancelled {
                if case .loading = runRecordsState { runRecordsState = .idle }
                runRecordsRefreshState = .idle
            } else {
                if case .loading = runRecordsState { runRecordsState = .failed(failure) }
                runRecordsRefreshState = .failed(failure)
            }
            runRecordsNeedsRefresh = true
        } catch {
            guard isCurrentRunRecordsRefresh(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID
            ) else { return }
            if case .loading = runRecordsState {
                runRecordsState = Task.isCancelled ? .idle : .failed(.invalidResponse)
            }
            runRecordsRefreshState = Task.isCancelled ? .idle : .failed(.invalidResponse)
            runRecordsNeedsRefresh = true
        }
    }

    private func cancelRunRecordsRefresh(operationID: UUID? = nil, markNeedsRefresh: Bool = true) {
        guard let currentOperationID = runRecordsRefreshOperationID,
              operationID == nil || operationID == currentOperationID else { return }
        let task = runRecordsRefreshTask
        runRecordsRefreshTask = nil
        runRecordsRefreshOperationID = nil
        if markNeedsRefresh { runRecordsNeedsRefresh = true }
        if runRecordsRefreshState == .refreshing { runRecordsRefreshState = .idle }
        task?.cancel()
    }

    private func isCurrentRunRecordsRefresh(
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String
    ) -> Bool {
        runRecordsRefreshOperationID == operationID
            && generation == requestGeneration
            && self.accountScopeID == accountScopeID
            && activeFeature == .runs
            && activeScreen == "L01"
            && activeRunID == nil
    }

    private func completeProgressRead(using loader: RunningProgressLoader, generation requestGeneration: UInt64) async {
        let result = await loader.loadProgress()
        guard requestGeneration == generation else { return }
        if Task.isCancelled {
            progressState = .idle
            activeFeature = nil
        } else {
            progressState = result
        }
    }

    private func completeWeeklyGoalRead(using loader: RunningProgressLoader, generation requestGeneration: UInt64) async {
        let result = await loader.loadWeeklyGoal()
        guard requestGeneration == generation else { return }
        if Task.isCancelled {
            weeklyGoalState = .idle
            activeFeature = nil
        } else {
            weeklyGoalState = result
            finishWeeklyGoalRead(result)
        }
    }

    func saveRunRecordField(
        _ field: BackendRunEditField,
        value: String,
        runID: String,
        accountScopeID: String,
        screen: String
    ) async -> Bool {
        guard let updater = runRecordsUpdater,
              let loader = runRecordsLoader,
              self.accountScopeID == accountScopeID,
              activeFeature == .runs,
              activeScreen == screen,
              screen == "L04",
              activeRunID == runID,
              case .loaded(let detail) = runDetailState,
              detail.summary.id == runID,
              runRecordEditOperationID == nil else { return false }

        let characterLimit = field == .title ? 40 : 300
        guard value.utf16.count <= characterLimit else {
            runRecordEditState = .failed(runID: runID, field: field, failure: .invalidEdit)
            return false
        }

        let operationID = UUID()
        let requestGeneration = generation
        let baseVersion = detail.summary.version
        let patch = BackendRunEditPatch(
            title: field == .title ? value : nil,
            memo: field == .memo ? value : nil
        )
        runRecordEditOperationID = operationID
        runRecordEditState = .saving(runID: runID, field: field)
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performRunRecordFieldSave(
                updater: updater,
                loader: loader,
                field: field,
                value: value,
                runID: runID,
                baseVersion: baseVersion,
                patch: patch,
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen
            )
        }
        runRecordEditTask = task
        let saved = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRunRecordEdit(operationID: operationID) }
        }
        if runRecordEditOperationID == operationID {
            runRecordEditTask = nil
            runRecordEditOperationID = nil
        }
        return saved
    }

    private func performRunRecordFieldSave(
        updater: any RunRecordsUpdating,
        loader: RunRecordsLoader,
        field: BackendRunEditField,
        value: String,
        runID: String,
        baseVersion: Int64,
        patch: BackendRunEditPatch,
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String,
        screen: String
    ) async -> Bool {
        do {
            let summary = try await updater.updateRun(id: runID, version: baseVersion, patch: patch)
            guard isCurrentRunRecordEdit(
                operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                screen: screen, runID: runID
            ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
            guard baseVersion < Int64.max, summary.version == baseVersion + 1 else {
                runRecordEditState = .failed(runID: runID, field: field, failure: .invalidResponse)
                return false
            }
            await applyRunRecordSummary(summary, using: loader)
            guard isCurrentRunRecordEdit(
                operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                screen: screen, runID: runID
            ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
            runRecordEditState = .idle
            return true
        } catch let failure as RunRecordsFailure {
            guard isCurrentRunRecordEdit(
                operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                screen: screen, runID: runID
            ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
            if failure == .cancelled || Task.isCancelled {
                runRecordEditState = .idle
                return false
            }
            guard failure == .versionConflict else {
                runRecordEditState = .failed(runID: runID, field: field, failure: failure)
                if failure == .recordNotFound { invalidateRunListAfterMissingRecord(runID: runID) }
                return false
            }

            runRecordEditState = .refreshingConflict(runID: runID, field: field)
            await loader.loadDetail(runID: runID)
            let refreshedState = await loader.detailState
            guard isCurrentRunRecordEdit(
                operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                screen: screen, runID: runID
            ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
            switch refreshedState {
            case .loaded(let latest) where latest.summary.id == runID:
                await applyRunRecordSummary(latest.summary, using: loader)
                guard isCurrentRunRecordEdit(
                    operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                    screen: screen, runID: runID
                ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
                let latestValue = field == .title ? latest.summary.title ?? "" : latest.summary.memo ?? ""
                if latestValue.utf16.elementsEqual(value.utf16) {
                    runRecordEditState = .idle
                    return true
                }
                runRecordEditState = .failed(runID: runID, field: field, failure: .versionConflict)
            case .failed(let failedID, .recordNotFound) where failedID == runID:
                runRecordEditState = .failed(runID: runID, field: field, failure: .recordNotFound)
                invalidateRunListAfterMissingRecord(runID: runID)
            default:
                runRecordEditState = .failed(runID: runID, field: field, failure: .versionConflictRefreshFailed)
            }
            return false
        } catch {
            guard isCurrentRunRecordEdit(
                operationID: operationID, generation: requestGeneration, accountScopeID: accountScopeID,
                screen: screen, runID: runID
            ) else { handleStaleRunEditResponse(runID: runID, accountScopeID: accountScopeID, using: loader); return false }
            if Task.isCancelled {
                runRecordEditState = .idle
            } else {
                runRecordEditState = .failed(runID: runID, field: field, failure: .invalidResponse)
            }
            return false
        }
    }

    private func isCurrentRunRecordEdit(
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String,
        screen: String,
        runID: String
    ) -> Bool {
        guard runRecordEditOperationID == operationID,
              generation == requestGeneration,
              self.accountScopeID == accountScopeID,
              activeFeature == .runs,
              activeScreen == screen,
              activeRunID == runID,
              case .loaded(let detail) = runDetailState else { return false }
        return detail.summary.id == runID
    }

    private func applyRunRecordSummary(_ summary: BackendRunSummary, using loader: RunRecordsLoader) async {
        await loader.applyUpdatedSummary(summary)
        staleRunDetailIDs.remove(summary.id)
        runRecordsState = await loader.state
        if case .loaded(let detail) = await loader.detailState,
           detail.summary.id == summary.id {
            runDetailState = .loaded(detail)
        }
    }

    private func invalidateRunListAfterMissingRecord(runID: String) {
        staleRunDetailIDs.insert(runID)
        runRecordsNeedsRefresh = true
        runRecordsState = .idle
    }

    private func handleStaleRunEditResponse(runID: String, accountScopeID: String, using loader: RunRecordsLoader) {
        guard self.accountScopeID == accountScopeID else { return }
        staleRunDetailIDs.insert(runID)
        runRecordsNeedsRefresh = true
        guard activeFeature == .runs, activeScreen == "L01", activeRunID == nil else { return }
        let requestGeneration = generation
        runRecordsState = .loading
        Task { @MainActor [weak self] in
            await loader.load()
            let result = await loader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.accountScopeID == accountScopeID,
                  self.activeFeature == .runs,
                  self.activeScreen == "L01",
                  self.activeRunID == nil else { return }
            self.runRecordsState = Task.isCancelled ? .idle : result
            if case .loaded = result { self.runRecordsNeedsRefresh = false }
        }
    }

    func cancelRunRecordEdit() {
        guard runRecordEditOperationID != nil else { return }
        runRecordEditTask?.cancel()
        runRecordEditTask = nil
        runRecordEditOperationID = nil
        runRecordEditState = .idle
    }

    private func cancelRunRecordEdit(operationID: UUID) {
        guard runRecordEditOperationID == operationID else { return }
        cancelRunRecordEdit()
    }

    func deleteRunRecord(id runID: String, accountScopeID: String, screen: String = "L07") async -> Bool {
        guard let deleter = runRecordsDeleter,
              let loader = runRecordsLoader,
              canDeleteRunRecord(runID),
              runRecordDeleteOperationID == nil,
              self.accountScopeID == accountScopeID,
              activeScreen == screen,
              screen == "L07",
              case .loaded(let detail) = runDetailState,
              detail.summary.id == runID else { return false }

        let operationID = UUID()
        let requestGeneration = generation
        let version = detail.summary.version
        runRecordDeleteOperationID = operationID
        runRecordDeleteState = .deleting(runID: runID)
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performRunRecordDeletion(
                deleter: deleter,
                loader: loader,
                runID: runID,
                version: version,
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen
            )
        }
        runRecordDeleteTask = task
        let deleted = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRunRecordDeletion(operationID: operationID) }
        }
        if runRecordDeleteOperationID == operationID {
            runRecordDeleteTask = nil
            runRecordDeleteOperationID = nil
        }
        return deleted
    }

    private func performRunRecordDeletion(
        deleter: any RunRecordsDeleting,
        loader: RunRecordsLoader,
        runID: String,
        version: Int64,
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String,
        screen: String
    ) async -> Bool {
        do {
            try await deleter.deleteRun(id: runID, version: version)
            guard isCurrentRunRecordDeletion(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen,
                runID: runID
            ) else {
                await reconcileStaleRunDeletion(runID: runID, accountScopeID: accountScopeID, loader: loader, confirmed: true)
                return false
            }

            await loader.applyDeletedRun(id: runID)
            guard isCurrentRunRecordDeletion(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen,
                runID: runID
            ) else {
                await reconcileStaleRunDeletion(runID: runID, accountScopeID: accountScopeID, loader: loader, confirmed: true)
                return false
            }
            runRecordsState = await loader.state
            runDetailState = await loader.detailState
            runRecordsNeedsRefresh = true
            staleRunDetailIDs.insert(runID)
            invalidateRunSummariesAfterDeletion()
            runRecordDeleteState = .idle
            return true
        } catch let failure as RunRecordsFailure {
            guard isCurrentRunRecordDeletion(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen,
                runID: runID
            ) else {
                await reconcileStaleRunDeletion(runID: runID, accountScopeID: accountScopeID, loader: loader, confirmed: false)
                return false
            }
            runRecordsNeedsRefresh = true
            staleRunDetailIDs.insert(runID)
            if failure == .cancelled || Task.isCancelled {
                runRecordDeleteState = .idle
            } else {
                runRecordDeleteState = .failed(runID: runID, failure: failure)
            }
            return false
        } catch {
            guard isCurrentRunRecordDeletion(
                operationID: operationID,
                generation: requestGeneration,
                accountScopeID: accountScopeID,
                screen: screen,
                runID: runID
            ) else {
                await reconcileStaleRunDeletion(runID: runID, accountScopeID: accountScopeID, loader: loader, confirmed: false)
                return false
            }
            runRecordsNeedsRefresh = true
            staleRunDetailIDs.insert(runID)
            runRecordDeleteState = .failed(runID: runID, failure: .invalidResponse)
            return false
        }
    }

    private func isCurrentRunRecordDeletion(
        operationID: UUID,
        generation requestGeneration: UInt64,
        accountScopeID: String,
        screen: String,
        runID: String
    ) -> Bool {
        guard runRecordDeleteOperationID == operationID,
              generation == requestGeneration,
              self.accountScopeID == accountScopeID,
              activeFeature == .runs,
              activeScreen == screen,
              screen == "L07",
              activeRunID == runID,
              case .loaded(let detail) = runDetailState else { return false }
        return detail.summary.id == runID
    }

    private func reconcileStaleRunDeletion(
        runID: String,
        accountScopeID: String,
        loader: RunRecordsLoader,
        confirmed: Bool
    ) async {
        guard self.accountScopeID == accountScopeID else { return }
        if confirmed { await loader.applyDeletedRun(id: runID) }
        runRecordsState = await loader.state
        runRecordsNeedsRefresh = true
        staleRunDetailIDs.insert(runID)
        invalidateRunSummariesAfterDeletion()
        guard activeFeature == .runs, activeScreen == "L01", activeRunID == nil else { return }
        let requestGeneration = generation
        runRecordsState = .loading
        Task { @MainActor [weak self] in
            await loader.load()
            let result = await loader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.accountScopeID == accountScopeID,
                  self.activeFeature == .runs,
                  self.activeScreen == "L01",
                  self.activeRunID == nil else { return }
            self.runRecordsState = Task.isCancelled ? .idle : result
            if case .loaded = result { self.runRecordsNeedsRefresh = false }
        }
    }

    private func invalidateRunSummariesAfterDeletion() {
        progressState = .idle
        weeklyGoalState = .idle
        dailyProgressState = .idle
        invalidateDailyProgressRead()
    }

    func cancelRunRecordDeletion(markStale: Bool = true) {
        guard runRecordDeleteOperationID != nil else { return }
        let runID: String? = {
            if case .deleting(let id) = runRecordDeleteState { return id }
            return activeRunID
        }()
        runRecordDeleteTask?.cancel()
        runRecordDeleteTask = nil
        runRecordDeleteOperationID = nil
        runRecordDeleteState = .idle
        if markStale, let runID {
            runRecordsNeedsRefresh = true
            staleRunDetailIDs.insert(runID)
        }
    }

    private func cancelRunRecordDeletion(operationID: UUID) {
        guard runRecordDeleteOperationID == operationID else { return }
        cancelRunRecordDeletion()
    }

    private func finishWeeklyGoalRead(_ result: WeeklyGoalReadState) {
        guard weeklyGoalNeedsRefresh else { return }
        switch result {
        case .loaded:
            weeklyGoalNeedsRefresh = false
            if weeklyGoalConflictRefreshState != .idle {
                weeklyGoalConflictRefreshState = .refreshed
            }
        case .failed(let failure):
            if weeklyGoalConflictRefreshState != .idle {
                weeklyGoalConflictRefreshState = .failed(failure)
            }
        case .idle, .loading:
            break
        }
    }

    func loadDailyProgress(range: BackendDailyProgressRange, accountScopeID: String, screen: String = "H07") async {
        if self.accountScopeID != accountScopeID { accountDidChange(to: accountScopeID) }
        guard let runningProgressLoader else { dailyProgressState = .idle; return }
        guard ["H07","H08","H09"].contains(screen) else { return }
        if activeFeature != .progressGoals || activeScreen != screen {
            activeFeature = .progressGoals
            activeScreen = screen
        }
        if case .loaded(let daily) = dailyProgressState, daily.range == range { return }
        if case .loading(let loadingRange) = dailyProgressState,
           loadingRange == range,
           dailyProgressTask != nil { return }
        if case .failed(let failedRange, _) = dailyProgressState, failedRange == range { return }
        if manualOperationKind == .progressDailyRetry { cancelManualOperation() }
        invalidateDailyProgressRead()
        let requestGeneration = dailyGeneration
        dailyProgressState = .loading(range)
        let loader = runningProgressLoader
        let requestTask = Task { @MainActor [weak self, loader] in
            await loader.loadDaily(range: range)
            let result = await loader.dailyState
            guard let self,
                  self.dailyGeneration == requestGeneration,
                  self.accountScopeID == accountScopeID,
                  self.activeFeature == .progressGoals,
                  ["H07","H08","H09"].contains(self.activeScreen ?? "") else { return }
            self.dailyProgressTask = nil
            if Task.isCancelled {
                self.dailyProgressState = .idle
            } else {
                self.dailyProgressState = result
            }
        }
        dailyProgressTask = requestTask
        await requestTask.value
    }

    func retryMemberProfile() {
        guard activeFeature == .profile,
              manualOperationTask == nil,
              case .failed = memberProfileState,
              let memberProfileLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .profileRetry
        memberProfileState = .loading
        manualOperationTask = Task { @MainActor [weak self] in
            await memberProfileLoader.retry()
            let result = await memberProfileLoader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.memberProfileState = Task.isCancelled ? .idle : result
        }
    }

    func saveMemberProfile(
        _ patch: MemberProfilePatch,
        accountScopeID: String,
        screen: String
    ) {
        guard memberProfileWriteOperationID == nil else { return }
        guard accountScopeID == self.accountScopeID, screen == activeScreen,
              activeFeature == .profile else { return }
        guard patch.hasChanges else { return }
        guard case .loaded = memberProfileState else {
            memberProfileWriteState = .failed(.profileWriteUnavailable)
            return
        }
        guard let memberProfileUpdater else {
            memberProfileWriteState = .failed(.profileWriteUnavailable)
            return
        }

        let requestGeneration = generation
        let operationID = UUID()
        memberProfileWriteOperationID = operationID
        memberProfileWriteState = .saving
        memberProfileWriteTask = Task { @MainActor [weak self, memberProfileUpdater] in
            do {
                let saved = try await memberProfileUpdater.updateProfile(patch)
                guard let self else { return }
                guard self.memberProfileWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshMemberProfileAfterStaleWrite(accountScopeID: accountScopeID)
                    return
                }
                self.memberProfileWriteTask = nil
                self.memberProfileWriteOperationID = nil
                self.memberProfileState = .loaded(saved)
                self.memberProfileWriteState = .saved
            } catch let failure as MemberProfileFailure {
                guard let self else { return }
                guard self.memberProfileWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshMemberProfileAfterStaleWrite(accountScopeID: accountScopeID)
                    return
                }
                self.memberProfileWriteTask = nil
                self.memberProfileWriteOperationID = nil
                self.memberProfileWriteState = .failed(failure)
            } catch is CancellationError {
                guard let self else { return }
                guard self.memberProfileWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshMemberProfileAfterStaleWrite(accountScopeID: accountScopeID)
                    return
                }
                self.memberProfileWriteTask = nil
                self.memberProfileWriteOperationID = nil
                self.memberProfileWriteState = .failed(.cancelled)
            } catch {
                guard let self else { return }
                guard self.memberProfileWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshMemberProfileAfterStaleWrite(accountScopeID: accountScopeID)
                    return
                }
                self.memberProfileWriteTask = nil
                self.memberProfileWriteOperationID = nil
                self.memberProfileWriteState = .failed(.invalidResponse)
            }
        }
    }

    func cancelMemberProfileMutation() {
        guard memberProfileWriteOperationID != nil else { return }
        memberProfileWriteTask?.cancel()
        memberProfileWriteTask = nil
        memberProfileWriteOperationID = nil
        memberProfileWriteState = .idle
        memberProfileState = .idle
    }

    func consumeMemberProfileWriteResult() {
        guard memberProfileWriteState == .saved else { return }
        memberProfileWriteState = .idle
    }

    func clearMemberProfileWriteFailure() {
        guard memberProfileWriteOperationID == nil else { return }
        if case .failed = memberProfileWriteState { memberProfileWriteState = .idle }
    }

    private func refreshMemberProfileAfterStaleWrite(accountScopeID: String) {
        guard self.accountScopeID == accountScopeID,
              activeFeature == .profile,
              let memberProfileLoader else { return }
        let requestGeneration = generation
        let requestScreen = activeScreen
        memberProfileState = .loading
        Task { @MainActor [weak self] in
            await memberProfileLoader.load()
            let result = await memberProfileLoader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.accountScopeID == accountScopeID,
                  self.activeScreen == requestScreen else { return }
            self.memberProfileState = Task.isCancelled ? .idle : result
        }
    }

    func retryPoints() {
        guard activeFeature == .points,
              manualOperationTask == nil,
              let pointsWalletLoader else { return }
        let requestGeneration = generation
        switch pointsState {
        case .failed(let failure) where failure.canManuallyRetry:
            pointsState = .loading
        case .failedLoadingMore(let snapshot, let failure) where failure.canManuallyRetry:
            pointsState = .loadingMore(snapshot)
        default:
            return
        }
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .pointsRetry
        manualOperationTask = Task { @MainActor [weak self] in
            await pointsWalletLoader.retry()
            let result = await pointsWalletLoader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.pointsState = Task.isCancelled ? .idle : result
        }
    }

    func loadNextPointsPage() {
        guard activeFeature == .points,
              manualOperationTask == nil,
              case .loaded(let snapshot) = pointsState,
              snapshot.nextCursor != nil,
              let pointsWalletLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .pointsPage
        manualPointsPreviousState = pointsState
        pointsState = .loadingMore(snapshot)
        manualOperationTask = Task { @MainActor [weak self] in
            await pointsWalletLoader.loadNextPage()
            let result = await pointsWalletLoader.state
            guard let self,
                  self.generation == requestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.manualPointsPreviousState = nil
            self.pointsState = Task.isCancelled ? .idle : result
        }
    }

    func retryRunRecords() {
        guard activeFeature == .runs, activeRunID == nil, manualOperationTask == nil,
              runRecordsRefreshOperationID == nil,
              let runRecordsLoader else { return }
        if runRecordsNeedsRefresh {
            _ = beginRunRecordsRefresh()
            return
        }
        switch runRecordsState {
        case .failed(let failure) where failure.canManuallyRetry:
            runRecordsState = .loading
        case .failedLoadingMore(let snapshot, let failure) where failure.canManuallyRetry:
            manualRunsPreviousState = .failedLoadingMore(snapshot, failure)
            runRecordsState = .loadingMore(snapshot)
        default:
            return
        }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .runsRetry
        manualOperationTask = Task { @MainActor [weak self] in
            await runRecordsLoader.retry()
            let result = await runRecordsLoader.state
            guard let self, self.generation == requestGeneration, self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.manualRunsPreviousState = nil
            self.runRecordsState = Task.isCancelled ? .idle : result
            if case .loaded = result { self.runRecordsNeedsRefresh = false }
        }
    }

    func loadNextRunRecordsPage() {
        guard activeFeature == .runs, activeRunID == nil, manualOperationTask == nil,
              runRecordsRefreshOperationID == nil,
              case .loaded(let snapshot) = runRecordsState, snapshot.nextCursor != nil,
              let runRecordsLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .runsPage
        manualRunsPreviousState = runRecordsState
        runRecordsState = .loadingMore(snapshot)
        manualOperationTask = Task { @MainActor [weak self] in
            await runRecordsLoader.loadNextPage()
            let result = await runRecordsLoader.state
            guard let self, self.generation == requestGeneration, self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.manualRunsPreviousState = nil
            self.runRecordsState = Task.isCancelled ? .idle : result
        }
    }

    func retryRunDetail() {
        guard activeFeature == .runs, let runID = activeRunID, manualOperationTask == nil,
              case .failed(let failedID, let failure) = runDetailState, failedID == runID,
              failure.canManuallyRetry, let runRecordsLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .runDetailRetry
        runDetailState = .loading(runID: runID)
        manualOperationTask = Task { @MainActor [weak self] in
            await runRecordsLoader.retryDetail(runID: runID)
            let result = await runRecordsLoader.detailState
            guard let self, self.generation == requestGeneration, self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.runDetailState = Task.isCancelled ? .idle : result
        }
    }

    func retryProgress() {
        guard activeFeature == .progressGoals, manualOperationTask == nil,
              case .failed(let failure) = progressState,
              failure.canManuallyRetry, let runningProgressLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .progressRetry
        progressState = .loading
        manualOperationTask = Task { @MainActor [weak self] in
            let result = await runningProgressLoader.retryProgress()
            guard let self,
                  self.generation == requestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.progressState = Task.isCancelled ? .idle : result
        }
    }

    func retryWeeklyGoal() {
        if weeklyGoalNeedsRefresh {
            refreshWeeklyGoalAfterConflict()
            return
        }
        guard activeFeature == .progressGoals, manualOperationTask == nil,
              case .failed(let failure) = weeklyGoalState,
              failure.canManuallyRetry, let runningProgressLoader else { return }
        let requestGeneration = generation
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .weeklyGoalRetry
        weeklyGoalState = .loading
        manualOperationTask = Task { @MainActor [weak self] in
            let result = await runningProgressLoader.retryWeeklyGoal()
            guard let self,
                  self.generation == requestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.weeklyGoalState = Task.isCancelled ? .idle : result
        }
    }

    func refreshWeeklyGoalAfterConflict() {
        guard activeFeature == .progressGoals,
              weeklyGoalNeedsRefresh,
              manualOperationTask == nil,
              let runningProgressLoader,
              weeklyGoalConflictRefreshState == .required || isWeeklyGoalConflictRefreshFailed else { return }
        let requestGeneration = generation
        let requestScopeID = accountScopeID
        let requestScreen = activeScreen
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .weeklyGoalConflictRefresh
        manualWeeklyGoalPreviousState = weeklyGoalState
        weeklyGoalConflictRefreshState = .refreshing
        let previousState = weeklyGoalState
        manualOperationTask = Task { @MainActor [weak self] in
            let result = await runningProgressLoader.loadWeeklyGoal()
            guard let self,
                  self.generation == requestGeneration,
                  self.accountScopeID == requestScopeID,
                  self.activeScreen == requestScreen,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.manualWeeklyGoalPreviousState = nil
            if Task.isCancelled {
                self.weeklyGoalState = previousState
                self.weeklyGoalConflictRefreshState = .required
            } else {
                self.weeklyGoalState = result
                self.finishWeeklyGoalRead(result)
            }
        }
    }

    private var isWeeklyGoalConflictRefreshFailed: Bool {
        if case .failed = weeklyGoalConflictRefreshState { return true }
        return false
    }

    func saveWeeklyGoal(
        version: Int64,
        distanceGoalMeters: Int64?,
        timeGoalSeconds: Int64?,
        accountScopeID: String,
        screen: String
    ) {
        guard weeklyGoalWriteOperationID == nil else { return }
        guard accountScopeID == self.accountScopeID, screen == activeScreen else { return }
        guard !weeklyGoalNeedsRefresh else { return }
        guard let weeklyGoalWriter, let runningProgressLoader else {
            weeklyGoalWriteState = .failed(.weeklyGoalWriteUnavailable)
            return
        }
        guard case .loaded(let baseline) = weeklyGoalState, baseline.version == version else {
            weeklyGoalWriteState = .failed(.weeklyGoalBaselineUnavailable)
            return
        }

        let requestGeneration = generation
        let operationID = UUID()
        weeklyGoalWriteOperationID = operationID
        weeklyGoalConflictRefreshState = .idle
        weeklyGoalWriteState = .saving
        weeklyGoalWriteTask = Task { @MainActor [weak self, weeklyGoalWriter, runningProgressLoader] in
            do {
                let saved = try await weeklyGoalWriter.saveWeeklyGoal(
                    version: version,
                    distanceGoalMeters: distanceGoalMeters,
                    timeGoalSeconds: timeGoalSeconds
                )
                guard let self else { return }
                guard self.weeklyGoalWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshWeeklyGoalAfterStaleMutation(accountScopeID:accountScopeID,using:runningProgressLoader)
                    return
                }

                let refreshed = await runningProgressLoader.loadWeeklyGoal()
                guard self.weeklyGoalWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshWeeklyGoalAfterStaleMutation(accountScopeID:accountScopeID,using:runningProgressLoader)
                    return
                }
                if case .loaded(let current) = refreshed {
                    self.weeklyGoalState = .loaded(current)
                } else {
                    // PUT already returned the server's complete status. Keep that committed state if the follow-up read is unavailable.
                    self.weeklyGoalState = .loaded(saved)
                    self.weeklyGoalNeedsRefresh = true
                }
                self.weeklyGoalConflictRefreshState = .idle
                self.weeklyGoalWriteTask = nil
                self.weeklyGoalWriteOperationID = nil
                self.weeklyGoalWriteState = .saved
            } catch let failure as ProgressGoalsFailure {
                guard let self else { return }
                guard self.weeklyGoalWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshWeeklyGoalAfterStaleMutation(accountScopeID:accountScopeID,using:runningProgressLoader)
                    return
                }
                self.weeklyGoalWriteTask = nil
                self.weeklyGoalWriteOperationID = nil
                self.weeklyGoalWriteState = .failed(failure)
                if case .weeklyGoalVersionConflict = failure {
                    self.weeklyGoalNeedsRefresh = true
                    self.weeklyGoalConflictRefreshState = .required
                }
            } catch is CancellationError {
                guard let self else { return }
                guard self.weeklyGoalWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshWeeklyGoalAfterStaleMutation(accountScopeID:accountScopeID,using:runningProgressLoader)
                    return
                }
                self.weeklyGoalWriteTask = nil
                self.weeklyGoalWriteOperationID = nil
                self.weeklyGoalWriteState = .failed(.cancelled)
            } catch {
                guard let self else { return }
                guard self.weeklyGoalWriteOperationID == operationID,
                      self.generation == requestGeneration,
                      self.accountScopeID == accountScopeID,
                      self.activeScreen == screen else {
                    self.refreshWeeklyGoalAfterStaleMutation(accountScopeID:accountScopeID,using:runningProgressLoader)
                    return
                }
                self.weeklyGoalWriteTask = nil
                self.weeklyGoalWriteOperationID = nil
                self.weeklyGoalWriteState = .failed(.invalidResponse)
            }
        }
    }

    func cancelWeeklyGoalMutation() {
        guard weeklyGoalWriteOperationID != nil else { return }
        weeklyGoalWriteTask?.cancel()
        weeklyGoalWriteTask = nil
        weeklyGoalWriteOperationID = nil
        weeklyGoalNeedsRefresh = true
        weeklyGoalWriteState = .idle
    }

    func consumeWeeklyGoalWriteResult() {
        guard weeklyGoalWriteState == .saved else { return }
        weeklyGoalWriteState = .idle
    }

    private func refreshWeeklyGoalAfterStaleMutation(accountScopeID: String, using loader: RunningProgressLoader) {
        guard self.accountScopeID == accountScopeID else { return }
        weeklyGoalNeedsRefresh = true
        guard activeFeature == .progressGoals else { return }
        let requestGeneration = generation
        Task { @MainActor [weak self] in
            let refreshed = await loader.loadWeeklyGoal()
            guard let self,
                  self.accountScopeID == accountScopeID,
                  self.generation == requestGeneration,
                  self.activeFeature == .progressGoals,
                  self.weeklyGoalNeedsRefresh else { return }
            self.weeklyGoalState = refreshed
            self.weeklyGoalNeedsRefresh = false
        }
    }

    func retryDailyProgress(range: BackendDailyProgressRange) {
        guard activeFeature == .progressGoals, ["H07","H08","H09"].contains(activeScreen ?? ""), manualOperationTask == nil,
              case .failed(let failedRange, let failure) = dailyProgressState,
              failedRange == range, failure.canManuallyRetry,
              let runningProgressLoader else { return }
        let requestGeneration = generation
        dailyGeneration &+= 1
        let dailyRequestGeneration = dailyGeneration
        let operationID = UUID()
        manualOperationID = operationID
        manualOperationKind = .progressDailyRetry
        dailyProgressState = .loading(range)
        manualOperationTask = Task { @MainActor [weak self] in
            await runningProgressLoader.retryDaily(range: range)
            let result = await runningProgressLoader.dailyState
            guard let self,
                  self.generation == requestGeneration,
                  self.dailyGeneration == dailyRequestGeneration,
                  self.manualOperationID == operationID else { return }
            self.manualOperationTask = nil
            self.manualOperationID = nil
            self.manualOperationKind = nil
            self.dailyProgressState = Task.isCancelled ? .idle : result
        }
    }

    private func cancelManualOperation(restorePreviousState: Bool = false) {
        let task = manualOperationTask
        manualOperationTask = nil
        manualOperationID = nil
        if restorePreviousState {
            switch manualOperationKind {
            case .profileRetry:
                memberProfileState = .idle
            case .pointsRetry:
                pointsState = .idle
            case .pointsPage:
                if let previous = manualPointsPreviousState { pointsState = previous }
            case .runsRetry:
                if let previous = manualRunsPreviousState { runRecordsState = previous }
                else { runRecordsState = .idle }
            case .runsPage:
                if let previous = manualRunsPreviousState { runRecordsState = previous }
            case .runDetailRetry:
                runDetailState = .idle
            case .progressRetry:
                progressState = .idle
            case .weeklyGoalRetry:
                weeklyGoalState = .idle
            case .weeklyGoalConflictRefresh:
                if let previous = manualWeeklyGoalPreviousState { weeklyGoalState = previous }
                if weeklyGoalNeedsRefresh { weeklyGoalConflictRefreshState = .required }
            case .progressDailyRetry:
                dailyProgressState = .idle
            case nil:
                break
            }
        }
        manualOperationKind = nil
        manualPointsPreviousState = nil
        manualRunsPreviousState = nil
        manualWeeklyGoalPreviousState = nil
        task?.cancel()
    }
}

enum WCommunityVerificationStatus:String,Codable,CaseIterable {case none,pending,approved,rejected}
enum WCommunityVerificationSubmissionResult:Equatable {case submitted,invalidActivity,alreadyPending,alreadyApproved}

struct WCommunityVerificationState:Codable,Equatable {
    var status:WCommunityVerificationStatus = .none
    var note=""
    var reason=""
    var isVerified:Bool{status == .approved}

    mutating func submit(_ value:String)->WCommunityVerificationSubmissionResult {
        guard status != .pending else{return .alreadyPending}
        guard status != .approved else{return .alreadyApproved}
        let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty,trimmed.count<=300 else{return .invalidActivity}
        note=trimmed;reason="";status = .pending;return .submitted
    }

    mutating func review(as result:WCommunityVerificationStatus)->Bool {
        guard status == .pending,result == .approved || result == .rejected else{return false}
        status=result;reason=result == .rejected ? "신청 내용을 조금 더 구체적으로 적어 주세요.":"";return true
    }
}

@MainActor @Observable final class WireState {
    private let defaults:UserDefaults
    var profile:WLocalProfile
    var remoteAccountScopeID=UUID().uuidString
    var screen="H00"
    var rootIndex=2;var previousRootIndex=2;var forward=true
    var calendarMonth=Date();var calendarDay:Date?
    var path:[String]=[]
    var selected:UUID?
    var remoteSelectedRunID:String?
    var communityPosts=WCommunityFixtures.posts
    var communityAttachmentStore=WCommunityAttachmentStore()
    var communityDraftAttachments:[WCommunityAttachment]=[]
    var communityMediaImportCoordinator=WCommunityMediaImportCoordinator()
    var communityMediaImporting=false
    var communityDraftSessionID=UUID().uuidString
    var communityVideoPlayback=WCommunityVideoPlaybackController()
    var communityImageViewerIndex=0
    var communityImageViewerIsDraft=false
    var communityImageZoomScale:CGFloat=1
    var communityNotificationCenter=WCommunityNotificationCenter()
    var communityNotificationError=""
    var communitySelectedPostID="p1"
    var communitySearchQuery=""
    var communitySelectedUserID="fixture-member-ga-on"
    var communityCardOriginScreen="C01"
    var communityCardOriginAnonymous=false
    var communityProfileEditing=false
    var communityConnectionsKind="followers"
    var communityFollowProvider=WLocalCommunityFollowProvider()
    var communityActivityProvider=WLocalCommunityActivityProvider()
    var communityModerationProvider=WLocalCommunityModerationProvider()
    var communityReportTarget:WCommunityReportTarget?
    var communityReportReason="욕설·괴롭힘"
    var communityReportDetail=""
    var communityReportError=""
    var communityMoreMenu:WCommunityMoreMenu?
    var communityModerationDialog:WCommunityModerationDialog?
    var communityPostDeleteConfirmationID:String?
    var communityViewerMemberID="fixture-member-current"
    var communityViewCountProvider:WCommunityViewCountProvider=WLocalCommunityViewCountProvider()
    var communityBoard="러닝 인증"
    var communityDraftBoard="러닝 인증"
    var communityDraftCrewID:String?
    var communityDraftPostID:String?
    var communityRemotePosts:[String:WCommunityRemotePostMetadata]=[:]
    var communityRemoteDraftPostID:String?
    var communityRemoteDraftAttachmentVersion:Int64?
    var communityRemoteDraftAssetIDs:[String:String]=[:]
    var communityRemoteDraftCreateResultUnknown=false
    var communityRemotePublishBusy=false
    var communityRemotePublishNeedsRetry=false
    var communityRemotePublishStatus=""
    var communityDraftTitle=""
    var communityDraftBody=""
    var communityComment=""
    var communityReplyToID:String?
    var communityError=""
    var communityLikedPosts:Set<String>=[]
    var communityVerification=WCommunityVerificationState()
    var communityVerificationError=""
    var communityAccountVerified:Bool{communityVerification.isVerified}
    var communityCourseTitle="강변 아침 코스"
    var communityCourseIntroduction="강변을 따라 편하게 달리는 예시 코스예요."
    var communityCourseDistance=4.82
    var communityCourseSeconds=1808.0
    var communityCourseHideEnds=true
    var communityCourseRecordID=""
    var communityCourseDraftOwnerID=""
    var communitySelectedCourse:WCommunityCourse?
    var communityCourseDraft=false
    var communityCoursePlayback=0.0
    var communityCoursePlaying=false
    var communityCourseError=""
    var communityCrewTab="my"
    var communityCrewFilter="내 주변"
    var communitySelectedCrewID="river"
    var communityCrewBoardID="dawn-board-0"
    var communityCrewJoinMemo=""
    var communityCrewJoinError=""
    var communityCrewApplications=WCommunityCrewFixtures.applications
    var communityJoinedCrewIDs:Set<String>=["dawn"]
    var communityCrewOverrides:[String:WCommunityCrew]=[:]
    var communityLocalCrews:[WCommunityCrew]=[]
    var communityCrewDraftID:String?
    var communityCrewDraftName=""
    var communityCrewDraftIntroduction=""
    var communityCrewDraftRegion="모브시 중앙"
    var communityCrewDraftRank=0
    var communityCrewDraftPhoto:Data?
    var communityCrewDraftError=""
    var communityCrewNameCheck=""
    var communityCrewReviewApplicationID="fixture-request-dawn-early"
    var communityCrewReviewError=""
    var communitySelectedCrewMemberID=""
    var communityCrewMemberWarningDraft=""
    var communityCrewMemberFeedback=""
    var communityCrewMemberError=""
    var communityCrewManageDraft:WCommunityCrewManageDraft?
    var communityCrewManageError=""
    var communityCrewManageFeedback=""
    var selectedPointProductID="line"
    var provider="Google"
    var pending="T05"
    var pendingBack="T05"
    var error=""
    var completionFeedbackSeen:Set<UUID>=[]
    var collapsed=false
    var month=false
    var gradeExpanded=false;var validityExpanded=false;var consentBusy=false
    var consentTerms=false;var consentPrivacy=false;var deleteConsent=false
    var consentSequenceID:UUID?
    var consentSequenceOriginalTerms=false;var consentSequenceOriginalPrivacy=false
    var consentTopic="이용약관"
    var nickname="";var introduction="";var region="";var weight=""
    var title="";var memo="";var photo:Data?
    var challengeIssued:Date?;var challengeCode="482619";var otpCodeIssuer=WLocalOTPCodeIssuer();var passwordReset:WPasswordResetSession
    var authErrorField="";var authFilled=false;var authEmail="";var authPassword="";var authConfirm="";var authCurrent="";var revealedFields:Set<String>=[];var settingsGrant=false;var otpSuccess=false;var otpFocused=false;var otpVerifying=false;var otpVerificationID:UUID?;var lastAttemptedOTP:String?;var code="";var codeAttempts=0;var verified=false
    var goal=RunGoal();var weekly=WeeklyGoal()
    var testing=false
    var saving=false;var passwordChanged=false;var resetBack="A01"
    init(){defaults=WWireDefaults.resolve().defaults;profile=defaults.data(forKey:"mov.wireframe.profile.v1").flatMap{try? JSONDecoder().decode(WLocalProfile.self,from:$0)} ?? WLocalProfile();communityVerification=defaults.data(forKey:"mov.wireframe.community-verification.v1").flatMap{try? JSONDecoder().decode(WCommunityVerificationState.self,from:$0)} ?? WCommunityVerificationState();passwordReset=WPasswordResetSession()}
    func seedCommunityPhotoFixtures(draft:Bool,post:Bool,videoPost:Bool=false,videoDraft:Bool=false){
        if draft,let photos=try? communityAttachmentStore.makeReviewFixtures(){communityDraftAttachments=photos.map(WCommunityAttachment.photo);communityDraftTitle="사진 첨부 예시";communityDraftBody=""}
        if post,let index=communityPosts.firstIndex(where:{$0.id=="p1"}),let draft=try? communityAttachmentStore.makeReviewFixtures(count:1),let photos=try? communityAttachmentStore.commit(draft,forPost:"p1"){communityPosts[index].attachments=photos.map(WCommunityAttachment.photo)}
        if videoPost,let index=communityPosts.firstIndex(where:{$0.id=="p1"}),let fixture=try? communityAttachmentStore.makeReviewVideoFixture(),let attachments=try? communityAttachmentStore.commit([.video(fixture)],forPost:"p1"){communityPosts[index].attachments += attachments}
        if videoDraft,let fixture=try? communityAttachmentStore.makeReviewVideoFixture(){communityDraftAttachments=[.video(fixture)];communityDraftTitle="영상 첨부 예시";communityDraftBody=""}
    }
    func save(){if let data=try? JSONEncoder().encode(profile){defaults.set(data,forKey:"mov.wireframe.profile.v1")}}
    func setLoggedIn(_ loggedIn:Bool){if profile.logged != loggedIn{profile.logged=loggedIn;remoteAccountScopeID=UUID().uuidString}}
    func resetRemoteAccountScope(){remoteAccountScopeID=UUID().uuidString}
    func submitCommunityVerification()->Bool{
        switch communityVerification.submit(communityVerification.note){
        case .submitted:communityVerificationError="";saveCommunityVerification();communityNotificationCenter.append(WCommunityNotification(id:UUID().uuidString,title:"인증 신청이 접수됐어요",text:"커뮤니티 계정 인증 상태를 확인해 보세요.",target:.verification));return true
        case .invalidActivity:communityVerificationError="활동 소개를 300자 안으로 입력해 주세요."
        case .alreadyPending:communityVerificationError="인증 신청을 검토하고 있어요."
        case .alreadyApproved:communityVerificationError="계정 인증이 완료됐어요."
        }
        return false
    }
    func reviewCommunityVerification(as result:WCommunityVerificationStatus){guard communityVerification.review(as:result)else{return};saveCommunityVerification()}
    private func saveCommunityVerification(){if let data=try? JSONEncoder().encode(communityVerification){defaults.set(data,forKey:"mov.wireframe.community-verification.v1")}}
    var notificationIDs:[Int]{WReviewMode.tools && ProcessInfo.processInfo.arguments.contains("-wire-empty-notifications") ? []:[0,1]}
    var hasUnreadNotifications:Bool{notificationIDs.contains{!profile.notificationRead.contains($0)}}
    var hasUnreadCommunityNotifications:Bool{communityNotificationCenter.hasUnread}
    func cancelReauthentication(){guard screen=="T15" else{return};settingsGrant=false;let destination=pendingBack;if path.last==destination{path.removeLast()};leaveAuth(for:destination);forward=false;screen=destination;error=""}
    struct Account:Codable {var profile:WLocalProfile;var records:[RunRecord];var goal:RunGoal;var weekly:WeeklyGoal}
    func switchLocalAccount(_ store:RunStore,clearShare:()->Void = {}){
        guard store.session==nil else{go("T14");return}
        let owner=defaults.string(forKey:"mov.local.owner") ?? "primary"
        var accounts=defaults.data(forKey:"mov.local.accounts").flatMap{try? JSONDecoder().decode([String:Account].self,from:$0)} ?? [:]
        accounts[owner]=Account(profile:profile,records:store.records,goal:store.goal,weekly:store.weekly)
        let next=owner=="existing-kakao" ? "primary":"existing-kakao"
        var fallback=WLocalProfile();fallback.nickname="카카오러너"
        let target=accounts[next] ?? Account(profile:fallback,records:[],goal:RunGoal(),weekly:WeeklyGoal())
        guard let encoded=try? JSONEncoder().encode(accounts)else{return}
        defaults.set(encoded,forKey:"mov.local.accounts");defaults.set(next,forKey:"mov.local.owner")
        profile=target.profile;store.records=target.records;store.goal=target.goal;store.weekly=target.weekly;remoteAccountScopeID=UUID().uuidString;store.persist();save();clearShare();go("H00")
    }
    static let otpScreens:Set<String>=["A19","A20","A21","A22","A23"]
    static let passwordResetScreens:Set<String>=["A10","A11","A12","A13","A24","A25","A26","A27","A28"]
    func clearAuthSecrets(preservingOTP:Bool=false){authErrorField="";authPassword="";authConfirm="";authCurrent="";authFilled=false;revealedFields=[];if !preservingOTP{code="";otpFocused=false;lastAttemptedOTP=nil}}
    func leaveAuth(for next:String){
        if screen=="A02" && next != "A02",consentSequenceID != nil{consentTerms=consentSequenceOriginalTerms;consentPrivacy=consentSequenceOriginalPrivacy;consentSequenceID=nil;consentBusy=false}
        let preservingOTP=Self.otpScreens.contains(screen) && Self.otpScreens.contains(next)
        if !preservingOTP{otpSuccess=false;otpVerifying=false;otpVerificationID=nil}
        if !Self.passwordResetScreens.contains(screen) || !Self.passwordResetScreens.contains(next){passwordReset.invalidate()}
        clearAuthSecrets(preservingOTP:preservingOTP)
        if !Self.otpScreens.contains(next){challengeIssued=nil;challengeCode="482619";otpCodeIssuer.reset();codeAttempts=0;lastAttemptedOTP=nil;authEmail=""}
        if !["A16","A17","A18","T15","T06"].contains(next){settingsGrant=false}
    }
    static let providerRoutes:Set<String>=["T06","T07","T08","T09","T15","T17","A16","A17","A18"]
    func returnToProviders(){
        if let index=path.firstIndex(of:"T05"){path=Array(path.prefix(index))}
        else{path.removeAll{Self.providerRoutes.contains($0)};if path.isEmpty{path=["T01"]}}
        leaveAuth(for:"T05");forward=false;screen="T05";pending="T05";error=""
    }
    func go(_ next:String){guard next != screen else{return};
        if ["L04","L07"].contains(screen), !["L04","L07"].contains(next) { remoteSelectedRunID = nil }
        if (next=="H00" && screen.hasPrefix("A")) || (next=="A01" && ["T10","A13","A18","T12","A04"].contains(screen)){
            leaveAuth(for:next);path=[];screen=next;forward=true;rootIndex=2;error="";return
        };if next=="T05" && (Self.providerRoutes.contains(screen) || resetBack=="T05"){returnToProviders();return};if ["T17","A18"].contains(next){if let index=path.firstIndex(of:"T05"){path=Array(path.prefix(index+1))}else{path=["T01","T05"]};leaveAuth(for:next);forward=true;screen=next;error="";return};if screen=="A18" && next=="A01"{path=[];leaveAuth(for:next);screen=next;error="";return};leaveAuth(for:next);forward=true;let roots=["POINTS","H01","H00","C01","M01"];if let index=["H02":1,"H05":1][next] ?? roots.firstIndex(of:next){forward=index>rootIndex;previousRootIndex=rootIndex;rootIndex=index};path.append(screen);screen=next;error=""}
    func openRecord(_ record:RunRecord){remoteSelectedRunID=nil;selected=record.id;forward=true;path.append(screen);screen="L04";error=""}
    func openRemoteRecord(id:String){remoteSelectedRunID=id;selected=nil;forward=true;path.append(screen);screen="L04";error=""}
    func back(){
        if screen=="A15"{go("H00");return}
        if screen=="A13"{return}
        if screen=="A18" && passwordChanged{go("A01");return}
        if ["T17","A18"].contains(screen){returnToProviders();return};let destination=path.popLast() ?? "H00";if ["L04","L07"].contains(screen), !["L04","L07"].contains(destination){remoteSelectedRunID=nil};leaveAuth(for:destination);forward=false;screen=destination;error="";let roots=["POINTS","H01","H00","C01","M01"];if let index=["H02":1,"H05":1][screen] ?? roots.firstIndex(of:screen){rootIndex=index}}
}
actor WireframeAccountLinkFixture: AccountLinkFlowServing {
    private var providers: [AccountLinkProvider]
    private let localPassword: Bool
    private var reauthProof: String?
    private var reauthProofPurpose: AccountLinkPurpose?
    private var failCompletionOnce: Bool
    private var failUnlinkWithMethodRequiredOnce: Bool
    private var failUnlinkOnce: Bool
    private let cancelReauthentication: Bool
    private let cancelLinkCredential: Bool
    private var delaysLinkCompletion: Bool
    private let delaysUnlinkCompletion: Bool
    private let delaysMethodsAfterUnlinkForAccountSwitch: Bool
    private var loseCompletionResponseOnce: Bool
    private var loseCompletionStatusOnce: Bool
    private var loseUnlinkResponseOnce: Bool
    private var loseUnlinkStatusOnce: Bool
    private var failMethodsAfterUnlinkOnce:Bool
    private var expireLinkChallengeOnce:Bool
    private var expireUnlinkProofOnce:Bool
    private var loseNextStatusResponse = false
    private var unlinkHasCompleted = false
    private var delayNextUnlinkMethodsRead = false
    private var postUnlinkMethodsReadCount = 0

    init(initiallyLinkedGoogle: Bool, onlyGoogleLinked: Bool, localPassword: Bool, failCompletionOnce: Bool, failUnlinkWithMethodRequiredOnce: Bool, failUnlinkOnce: Bool, cancelReauthentication: Bool, cancelLinkCredential: Bool, delaysLinkCompletion: Bool, delaysUnlinkCompletion: Bool, delaysMethodsAfterUnlinkForAccountSwitch:Bool, loseCompletionResponseOnce: Bool, loseCompletionStatusOnce: Bool, loseUnlinkResponseOnce: Bool, loseUnlinkStatusOnce: Bool, failMethodsAfterUnlinkOnce:Bool, expireLinkChallengeOnce:Bool, expireUnlinkProofOnce:Bool) {
        providers = onlyGoogleLinked ? [.google] : initiallyLinkedGoogle ? [.kakao, .google] : [.kakao]
        self.localPassword = localPassword
        self.failCompletionOnce = failCompletionOnce
        self.failUnlinkWithMethodRequiredOnce = failUnlinkWithMethodRequiredOnce
        self.failUnlinkOnce = failUnlinkOnce
        self.cancelReauthentication = cancelReauthentication
        self.cancelLinkCredential = cancelLinkCredential
        self.delaysLinkCompletion = delaysLinkCompletion
        self.delaysUnlinkCompletion = delaysUnlinkCompletion
        self.delaysMethodsAfterUnlinkForAccountSwitch=delaysMethodsAfterUnlinkForAccountSwitch
        self.loseCompletionResponseOnce = loseCompletionResponseOnce
        self.loseUnlinkResponseOnce = loseUnlinkResponseOnce
        self.loseNextStatusResponse = false
        self.loseCompletionStatusOnce = loseCompletionStatusOnce
        self.loseUnlinkStatusOnce = loseUnlinkStatusOnce
        self.failMethodsAfterUnlinkOnce=failMethodsAfterUnlinkOnce
        self.expireLinkChallengeOnce=expireLinkChallengeOnce
        self.expireUnlinkProofOnce=expireUnlinkProofOnce
    }

    func methods() async throws -> AccountLinkMethods {
        if loseNextStatusResponse {
            loseNextStatusResponse = false
            throw AccountLinkFailure.transport(.networkConnectionLost)
        }
        if unlinkHasCompleted && failMethodsAfterUnlinkOnce {
            failMethodsAfterUnlinkOnce=false
            throw AccountLinkFailure.serviceUnavailable
        }
        if delayNextUnlinkMethodsRead {
            delayNextUnlinkMethodsRead=false
            postUnlinkMethodsReadCount += 1
            let delayedSnapshot=AccountLinkMethods(localPassword:localPassword,socialProviders:providers)
            try await Task.sleep(for:.seconds(5))
            return delayedSnapshot
        }
        if delaysMethodsAfterUnlinkForAccountSwitch && unlinkHasCompleted {
            postUnlinkMethodsReadCount += 1
            if postUnlinkMethodsReadCount > 1 {
                return AccountLinkMethods(localPassword:false,socialProviders:[.google])
            }
        }
        return AccountLinkMethods(localPassword: localPassword, socialProviders: providers)
    }

    func reauthenticateWithPassword(_ password: String, purpose: AccountLinkPurpose) async throws {
        guard localPassword, !password.isEmpty else { throw AccountLinkFailure.invalidCredentials }
        reauthProof = Self.token("r")
        reauthProofPurpose = purpose
    }

    func reauthenticate(using provider: AccountLinkProvider, purpose: AccountLinkPurpose) async throws {
        guard providers.contains(provider) else { throw AccountLinkFailure.invalidCredentials }
        if cancelReauthentication { throw AccountLinkFailure.cancelled }
        reauthProof = Self.token("r")
        reauthProofPurpose = purpose
    }

    func consumeReauthenticationProof(for purpose: AccountLinkPurpose) async throws -> String {
        guard reauthProofPurpose == purpose, let proof = reauthProof else {
            throw AccountLinkFailure.reauthenticationRequired
        }
        reauthProof = nil
        reauthProofPurpose = nil
        return proof
    }

    func link(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws {
        guard reauthProof != nil, reauthProofPurpose == .link else { throw AccountLinkFailure.reauthenticationRequired }
        guard !providers.contains(provider) else { throw AccountLinkFailure.alreadyLinked }
        if cancelLinkCredential {
            self.reauthProof = nil
            self.reauthProofPurpose = nil
            throw AccountLinkFailure.cancelled
        }
        guard await onMutationRequestWillSubmit() else {
            self.reauthProof = nil
            self.reauthProofPurpose = nil
            throw AccountLinkFailure.cancelled
        }
        if delaysLinkCompletion {
            delaysLinkCompletion=false
            try await Task.sleep(for: .seconds(6))
        }
        if expireLinkChallengeOnce {
            expireLinkChallengeOnce=false
            reauthProof=nil
            reauthProofPurpose=nil
            throw AccountLinkFailure.unauthenticated
        }
        if failCompletionOnce {
            failCompletionOnce = false
            self.reauthProof = nil
            self.reauthProofPurpose = nil
            throw AccountLinkFailure.accountLinkConflict
        }
        providers.append(provider)
        self.reauthProof = nil
        self.reauthProofPurpose = nil
        if loseCompletionResponseOnce {
            loseCompletionResponseOnce = false
            loseNextStatusResponse = loseCompletionStatusOnce
            loseCompletionStatusOnce = false
            throw AccountLinkFailure.transport(.networkConnectionLost)
        }
    }

    func unlink(provider: AccountLinkProvider, onMutationRequestWillSubmit: @escaping @Sendable () async -> Bool) async throws {
        guard reauthProof != nil, reauthProofPurpose == .unlink else { throw AccountLinkFailure.reauthenticationRequired }
        guard providers.contains(provider) else {
            reauthProof = nil
            reauthProofPurpose = nil
            throw AccountLinkFailure.accountLinkNotFound
        }
        guard await onMutationRequestWillSubmit() else {
            reauthProof = nil
            reauthProofPurpose = nil
            throw AccountLinkFailure.cancelled
        }
        if delaysUnlinkCompletion { try await Task.sleep(for: .seconds(6)) }
        if expireUnlinkProofOnce {
            expireUnlinkProofOnce=false
            reauthProof=nil
            reauthProofPurpose=nil
            throw AccountLinkFailure.unauthenticated
        }
        if failUnlinkWithMethodRequiredOnce {
            failUnlinkWithMethodRequiredOnce = false
            reauthProof = nil
            reauthProofPurpose = nil
            throw AccountLinkFailure.accountMethodRequired
        }
        if failUnlinkOnce {
            failUnlinkOnce = false
            reauthProof = nil
            reauthProofPurpose = nil
            throw AccountLinkFailure.serviceUnavailable
        }
        guard localPassword || providers.count > 1 else {
            reauthProof = nil
            reauthProofPurpose = nil
            throw AccountLinkFailure.accountMethodRequired
        }
        providers.removeAll { $0 == provider }
        unlinkHasCompleted=true
        if delaysMethodsAfterUnlinkForAccountSwitch { delayNextUnlinkMethodsRead=true }
        reauthProof = nil
        reauthProofPurpose = nil
        if loseUnlinkResponseOnce {
            loseUnlinkResponseOnce = false
            loseNextStatusResponse = loseUnlinkStatusOnce
            loseUnlinkStatusOnce = false
            throw AccountLinkFailure.transport(.networkConnectionLost)
        }
    }

    func cancel() async {
        reauthProof = nil
        reauthProofPurpose = nil
    }

    private static func token(_ prefix: String) -> String {
        prefix + String(repeating: "x", count: 42)
    }
}

#if DEBUG
/// In-memory withdrawal transport for isolated UUID-backed UI fixtures only.
private actor WireframeMemberWithdrawalFixture: MemberWithdrawalServing {
    private var failOnce: Bool
    private var expireProofOnce: Bool
    private var loseResponseOnce: Bool
    private var delayOnce: Bool
    private var requestCount = 0

    init(arguments: [String]) {
        failOnce = arguments.contains("-wire-member-withdrawal-fail-once")
        expireProofOnce = arguments.contains("-wire-member-withdrawal-expired-proof-once")
        loseResponseOnce = arguments.contains("-wire-member-withdrawal-response-lost-once")
        delayOnce = arguments.contains("-wire-member-withdrawal-delay-once")
    }

    func confirmationNotice() async throws -> MemberWithdrawalConfirmationNotice {
        MemberWithdrawalConfirmationNotice(
            message: "탈퇴 범위와 처리 항목을 확인해 주세요.",
            recentReauthenticationValiditySeconds: 300
        )
    }

    func requestWithdrawal(reauthProof: String, confirmed: Bool) async throws -> MemberWithdrawalReceipt {
        guard confirmed else { throw MemberWithdrawalFailure.confirmationRequired }
        guard reauthProof.utf8.count == 43 else { throw MemberWithdrawalFailure.reauthenticationRequired }
        requestCount += 1

        if delayOnce {
            delayOnce = false
            do { try await Task.sleep(for: .seconds(3)) }
            catch { throw MemberWithdrawalFailure.transport(.cancelled, outcomeUnknown: true) }
        }
        if expireProofOnce {
            expireProofOnce = false
            throw MemberWithdrawalFailure.unauthenticated
        }
        if failOnce {
            failOnce = false
            throw MemberWithdrawalFailure.serviceUnavailable
        }
        if loseResponseOnce {
            loseResponseOnce = false
            // Model a committed request whose 202 response was lost. No receipt is exposed.
            throw MemberWithdrawalFailure.transport(.networkConnectionLost, outcomeUnknown: true)
        }

        return MemberWithdrawalReceipt(
            requestId: "debug-withdrawal-\(requestCount)",
            status: "WITHDRAWN",
            gpsStatus: .completed,
            profilePhotoStatus: .pending,
            communityAttachmentsStatus: .retryableFailure
        )
    }
}
#endif

struct RootView:View {
    @Environment(\.dynamicTypeSize) var systemSize
    let remoteReadDependencies: WireframeRemoteReadDependencies?
    var captureViewport:Bool{ProcessInfo.processInfo.arguments.contains("-wire-fixture") && ProcessInfo.processInfo.arguments.contains("-wire-capture-viewport")}

    init(remoteReadDependencies: WireframeRemoteReadDependencies? = nil) {
        self.remoteReadDependencies = remoteReadDependencies
    }

    private var resolvedRemoteReadDependencies:WireframeRemoteReadDependencies? {
        if let remoteReadDependencies { return remoteReadDependencies }
        let args = ProcessInfo.processInfo.arguments
        let authComposition = WireframeAuthSessionComposition.resolve(arguments: args)
        let runFixture = args.contains("-wire-run-records-fixture")
        let runEditFixture = args.contains("-wire-run-records-edit-fixture")
        let runDeleteFixture = args.contains("-wire-run-records-delete-fixture")
        let weeklyGoalWriteFixture = args.contains("-wire-weekly-goal-write-fixture")
        let progressFixture = args.contains("-wire-progress-goals-fixture") || weeklyGoalWriteFixture
        let logoutFixture = WReviewMode.tools && args.contains("-wire-auth-logout-fixture")
            ? WireframeAuthLogoutFixture(
                failureSequence: {
                    if args.contains("-wire-auth-logout-fail-once-500") {
                        return [.serverFailure(statusCode:500,requestID:"fixture-logout-500")]
                    }
                    if args.contains("-wire-auth-logout-response-lost-then-401") {
                        return [.transport(.timedOut),.unauthenticated]
                    }
                    if args.contains("-wire-auth-logout-fail-once") {
                        return [.serviceUnavailable(requestID:"fixture-logout-unavailable")]
                    }
                    return []
                }(),
                alwaysFails:args.contains("-wire-auth-logout-fail"),
                delaysResponse:args.contains("-wire-auth-logout-delay")
            ) : nil
        let passwordResetFixture: WireframePasswordResetFixture? = WReviewMode.tools && args.contains("-wire-fixture")
            ? WireframePasswordResetFixture(
                initialChallenge: {
                    guard let index=args.firstIndex(of:"-wire-screen"),args.indices.contains(index+1) else{return false}
                    return WireState.passwordResetScreens.contains(args[index+1]) && args[index+1] != "A10"
                }(),
                initialCode: args.contains("-wire-screen") && args.indices.contains((args.firstIndex(of:"-wire-screen") ?? 0)+1) && args[(args.firstIndex(of:"-wire-screen") ?? 0)+1] == "A28" ? "700001":"700000",
                initialChallengeAge: {
                    guard let index=args.firstIndex(of:"-wire-screen"),args.indices.contains(index+1) else{return 0}
                    if args[index+1]=="A26"{return PasswordResetPolicy.codeLifetime+1}
                    if args[index+1]=="A28" || args.contains("-wire-password-reset-resend-ready"){return PasswordResetPolicy.resendInterval}
                    return 0
                }(),
                failChallengeOnce:args.contains("-wire-password-reset-challenge-timeout-once"),
                failVerificationOnce:args.contains("-wire-password-reset-confirm-timeout-once"),
                loseCompletionResponseOnce:args.contains("-wire-password-reset-completion-response-lost-once")
            ) : nil
        let passwordResetSessionStore: (any AuthSessionStoring)? = WReviewMode.tools && args.contains("-wire-password-reset-session-store-fixture")
            ? WireframePasswordResetSessionFixtureStore(failReplacementOnce:args.contains("-wire-password-reset-session-store-fail-once")) : nil
        // User-flow auth fixtures disable the broader review mode. Permit this mock only
        // when both the defaults suite and Keychain service are UUID-isolated.
        let uuidScopedAuthFixture = AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: args)
            && AuthSessionFixtureLaunchPolicy.fixtureServiceName(arguments: args) != nil
        let accountLinkFixture: (any AccountLinkFlowServing)? = (WReviewMode.tools || uuidScopedAuthFixture)
            && (args.contains("-wire-account-link-fixture") || args.contains("-wire-member-withdrawal-fixture"))
            ? WireframeAccountLinkFixture(
                initiallyLinkedGoogle:args.contains("-wire-account-link-google-already-linked"),
                onlyGoogleLinked:args.contains("-wire-account-unlink-last-method"),
                localPassword:args.contains("-wire-account-link-local-password") || args.contains("-wire-member-withdrawal-fixture"),
                failCompletionOnce:args.contains("-wire-account-link-fail-once"),
                failUnlinkWithMethodRequiredOnce:args.contains("-wire-account-unlink-last-method-race"),
                failUnlinkOnce:args.contains("-wire-account-unlink-fail-once"),
                cancelReauthentication:args.contains("-wire-account-link-cancel-reauth"),
                cancelLinkCredential:args.contains("-wire-account-link-cancel-target"),
                delaysLinkCompletion:args.contains("-wire-account-link-delay-completion"),
                delaysUnlinkCompletion:args.contains("-wire-account-unlink-delay-completion"),
                delaysMethodsAfterUnlinkForAccountSwitch:args.contains("-wire-account-link-scope-switch-regression"),
                loseCompletionResponseOnce:args.contains("-wire-account-link-response-lost-once"),
                loseCompletionStatusOnce:args.contains("-wire-account-link-status-read-lost-once"),
                loseUnlinkResponseOnce:args.contains("-wire-account-unlink-response-lost-once"),
                loseUnlinkStatusOnce:args.contains("-wire-account-unlink-status-read-lost-once"),
                failMethodsAfterUnlinkOnce:args.contains("-wire-account-link-methods-fail-after-unlink-once"),
                expireLinkChallengeOnce:args.contains("-wire-account-link-expired-challenge-once"),
                expireUnlinkProofOnce:args.contains("-wire-account-unlink-expired-proof-once")
            ) : nil
#if DEBUG
        let memberWithdrawalFixture: (any MemberWithdrawalServing)? = (WReviewMode.tools || uuidScopedAuthFixture)
            && args.contains("-wire-member-withdrawal-fixture")
            && AuthSessionFixtureLaunchPolicy.hasUUIDDefaultsSuite(arguments: args)
            && AuthSessionFixtureLaunchPolicy.fixtureServiceName(arguments: args) != nil
            ? WireframeMemberWithdrawalFixture(arguments: args) : nil
#else
        let memberWithdrawalFixture: (any MemberWithdrawalServing)? = nil
#endif
        let profileFixture = WReviewMode.tools && args.contains("-wire-member-profile-fixture")
            ? WireframeMemberProfileFixture(
                failReadOnce:args.contains("-wire-member-profile-read-fail-once"),
                failWrite:args.contains("-wire-member-profile-write-fail"),
                conflictNickname:args.contains("-wire-member-profile-nickname-conflict"),
                delayWrite:args.contains("-wire-member-profile-write-delay")
            ) : nil
        guard runFixture || runEditFixture || runDeleteFixture || progressFixture || profileFixture != nil || logoutFixture != nil || passwordResetFixture != nil || passwordResetSessionStore != nil || accountLinkFixture != nil || authComposition.store != nil || authComposition.client != nil else { return nil }
        let profileLoader = profileFixture.map { MemberProfileLoader(fetcher:$0) }
        let runClient = (runFixture || runEditFixture || runDeleteFixture) ? WireframeRunRecordsFixture(
            fails:args.contains("-wire-run-records-fail"),
            failsWrite:args.contains("-wire-run-records-write-fail"),
            conflictsFirstWrite:args.contains("-wire-run-records-write-conflict"),
            missingWrite:args.contains("-wire-run-records-write-404"),
            deletionFailure:args.contains("-wire-run-records-delete-404") ? .recordNotFound : args.contains("-wire-run-records-delete-fail") ? .serverFailure(statusCode:503,requestID:"fixture-run-delete-unavailable") : nil,
            losesFirstDeleteResponse:args.contains("-wire-run-records-delete-response-lost"),
            removesRunOnNextRefresh:args.contains("-wire-run-records-remote-delete-on-refresh")
        ):nil
        let runLoader = runClient.map { RunRecordsLoader(client:$0) }
        let progressClient = progressFixture ? WireframeProgressGoalsFixture(
            failsOverview:args.contains("-wire-progress-goals-fail"),
            failsDaily:args.contains("-wire-progress-daily-fail"),
            failsWeeklyGoalWrite:args.contains("-wire-weekly-goal-write-fail"),
            conflictsWeeklyGoalWrite:args.contains("-wire-weekly-goal-write-conflict"),
            failsConflictRefreshOnce:args.contains("-wire-weekly-goal-conflict-refresh-fail-once")
        ):nil
        let progressLoader = progressClient.map { RunningProgressLoader(client:$0) }
        let accountLinkFlow: (any AccountLinkFlowServing)?
        if let accountLinkFixture {
            accountLinkFlow = accountLinkFixture
        } else if WReviewMode.tools {
            accountLinkFlow = nil
        } else {
            if let apiClient = authComposition.apiClient, let authClient = authComposition.client {
                accountLinkFlow = AccountLinkFlowFactory.make(apiClient: apiClient, tokenProvider: authClient)
            } else {
                accountLinkFlow = nil
            }
        }
        let memberWithdrawalService: (any MemberWithdrawalServing)?
#if DEBUG
        if let memberWithdrawalFixture {
            memberWithdrawalService = memberWithdrawalFixture
        } else if WReviewMode.tools {
            memberWithdrawalService = nil
        } else if let apiClient = authComposition.apiClient, let authClient = authComposition.client {
            memberWithdrawalService = MemberWithdrawalClient(apiClient: apiClient, tokenProvider: authClient)
        } else {
            memberWithdrawalService = nil
        }
#else
        if let apiClient = authComposition.apiClient, let authClient = authComposition.client {
            memberWithdrawalService = MemberWithdrawalClient(apiClient: apiClient, tokenProvider: authClient)
        } else {
            memberWithdrawalService = nil
        }
#endif
        return WireframeRemoteReadDependencies(
            memberProfileLoader:profileLoader,
            memberProfileUpdater:profileFixture,
            runRecordsLoader:runLoader,
            runRecordsUpdater:runEditFixture ? runClient:nil,
            runRecordsDeleter:runDeleteFixture ? runClient:nil,
            runningProgressLoader:progressLoader,
            weeklyGoalWriter:weeklyGoalWriteFixture ? progressClient:nil,
            sessionLogoutRequester:logoutFixture ?? authComposition.client,
            passwordResetService:passwordResetFixture ?? authComposition.apiClient.map { PasswordResetClient(apiClient: $0) },
            authSessionStore:passwordResetSessionStore ?? authComposition.store,
            authSessionClient:authComposition.client,
            runUploadAPIClient:authComposition.apiClient,
            mediaUploadClient: {
                guard let apiClient = authComposition.apiClient, let authClient = authComposition.client else { return nil }
                return MediaUploadClient(apiClient: apiClient, tokenProvider: authClient)
            }(),
            communityMediaClient: {
                guard let apiClient = authComposition.apiClient, let authClient = authComposition.client else { return nil }
                return CommunityMediaClient(apiClient: apiClient, tokenProvider: authClient)
            }(),
            accountLinkFlow:accountLinkFlow,
            memberWithdrawalService:memberWithdrawalService
        )
    }

    var body: some View {
        Group {
            if captureViewport {
                ZStack(alignment:.top){W.paper;Text("SIMULATION · 가상 데이터 · 실제 GPS·인증 없음").font(.system(size:8)).foregroundStyle(Color(white:0.4)).frame(maxWidth:.infinity).frame(height:24).background(Color(white:0.93));WireframeRoot(remoteReadDependencies:resolvedRemoteReadDependencies).frame(width:390,height:766).clipped().offset(y:24)}
                    .frame(width:390,height:790,alignment:.top).clipped().ignoresSafeArea()
            } else if ProcessInfo.processInfo.arguments.contains("-wire-fixture") && ProcessInfo.processInfo.arguments.contains("-wire-compact-review") {
                WireframeRoot(remoteReadDependencies:resolvedRemoteReadDependencies).frame(width:320,height:568).clipped()
            } else if ProcessInfo.processInfo.arguments.contains("-wire-review-size") {
                WireframeRoot(remoteReadDependencies:resolvedRemoteReadDependencies).frame(width:388,height:764).clipped()
            } else {
                WireframeRoot(remoteReadDependencies:resolvedRemoteReadDependencies)
            }
        }.dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("-wire-large") ? .accessibility3:systemSize).statusBarHidden(captureViewport)
    }
}

/// An in-memory profile API fake for isolated UI review and test suites.
private actor WireframeMemberProfileFixture:MemberProfileFetching, MemberProfileUpdating {
    private var profile=MemberProfile(
        nickname:"RunMate",introduction:"아침마다 달려요",region:"모브시 북부권",weightKg:Decimal(string:"63.12")!
    )
    private var failReadOnce:Bool
    private let failWrite:Bool
    private let conflictNickname:Bool
    private let delayWrite:Bool

    init(failReadOnce:Bool,failWrite:Bool,conflictNickname:Bool,delayWrite:Bool){
        self.failReadOnce=failReadOnce;self.failWrite=failWrite;self.conflictNickname=conflictNickname;self.delayWrite=delayWrite
    }

    func fetchProfile() async throws -> MemberProfile {
        if failReadOnce {failReadOnce=false;throw MemberProfileFailure.serviceUnavailable(requestID:"fixture-profile-read")}
        return profile
    }

    func updateProfile(_ patch:MemberProfilePatch) async throws -> MemberProfile {
        if delayWrite {try await Task.sleep(for:.milliseconds(350))}
        if failWrite {throw MemberProfileFailure.serviceUnavailable(requestID:"fixture-profile-write")}
        if conflictNickname,case .set=patch.nickname {
            throw MemberProfileFailure.nicknameAlreadyUsed(requestID:"fixture-profile-conflict")
        }
        var nickname=profile.nickname
        var introduction=profile.introduction
        var region=profile.region
        var weightKg=profile.weightKg
        switch patch.nickname {
        case .unchanged:break
        case .set(let value):nickname=value.precomposedStringWithCanonicalMapping
        case .clear:throw MemberProfileFailure.invalidProfileDraft
        }
        switch patch.introduction {
        case .unchanged:break
        case .set(let value):introduction=value
        case .clear:introduction=nil
        }
        switch patch.region {
        case .unchanged:break
        case .set(let value):region=value
        case .clear:region=nil
        }
        switch patch.weightKg {
        case .unchanged:break
        case .set(let value):
            guard value>=20,value<=300 else{throw MemberProfileFailure.validationFailed(requestID:"fixture-profile-validation")}
            var input=value;var stored=Decimal();NSDecimalRound(&stored,&input,2,.down);weightKg=stored
        case .clear:weightKg=nil
        }
        profile=MemberProfile(nickname:nickname,introduction:introduction,region:region,weightKg:weightKg)
        return profile
    }
}

private actor WireframeProgressGoalsFixture: RunningProgressReading, RunningWeeklyGoalWriting {
    private let failsOverview: Bool
    private let failsDaily: Bool
    private let failsWeeklyGoalWrite: Bool
    private let conflictsWeeklyGoalWrite: Bool
    private var failsConflictRefreshOnce: Bool
    private var weeklyGoalReadCalls=0
    private var didConflictWeeklyGoalWrite=false
    private var weeklyGoal = BackendWeeklyGoalStatus(
        weekStartDate:"2026-09-28",weekEndDate:"2026-10-04",version:3,
        distance:.init(goal:20_000,done:12_400,remaining:7_600,achieved:false),
        time:.init(goal:7_200,done:3_900,remaining:3_300,achieved:false)
    )

    init(
        failsOverview: Bool,
        failsDaily: Bool,
        failsWeeklyGoalWrite: Bool = false,
        conflictsWeeklyGoalWrite: Bool = false,
        failsConflictRefreshOnce: Bool = false
    ) {
        self.failsOverview=failsOverview
        self.failsDaily=failsDaily
        self.failsWeeklyGoalWrite=failsWeeklyGoalWrite
        self.conflictsWeeklyGoalWrite=conflictsWeeklyGoalWrite
        self.failsConflictRefreshOnce=failsConflictRefreshOnce
    }

    func fetchProgress() async throws -> BackendProgressSummary {
        if failsOverview { throw ProgressGoalsFailure.serviceUnavailable(requestID:"fixture-progress") }
        return BackendProgressSummary(
            grade:"SPROUT",gradeAchievedAt:nil,
            window:.init(fromDate:"2026-07-04",toDate:"2026-10-01",distanceMeters:12_400,activityDays:8),
            nextGrade:.init(grade:"PASSION",requiredDistanceMeters:30_000,requiredActivityDays:10,remainingDistanceMeters:17_600,remainingActivityDays:2),
            total:.init(distanceMeters:48_200,seconds:17_350,activityDays:31,runCount:40)
        )
    }

    func fetchWeeklyGoal() async throws -> BackendWeeklyGoalStatus {
        weeklyGoalReadCalls+=1
        if weeklyGoalReadCalls>1 && failsConflictRefreshOnce {
            failsConflictRefreshOnce=false
            throw ProgressGoalsFailure.serviceUnavailable(requestID:"fixture-weekly-goal-conflict-refresh")
        }
        if failsOverview { throw ProgressGoalsFailure.serviceUnavailable(requestID:"fixture-weekly-goal") }
        return weeklyGoal
    }

    func saveWeeklyGoal(version: Int64, distanceGoalMeters: Int64?, timeGoalSeconds: Int64?) async throws -> BackendWeeklyGoalStatus {
        if failsWeeklyGoalWrite { throw ProgressGoalsFailure.serviceUnavailable(requestID:"fixture-weekly-goal-write") }
        if conflictsWeeklyGoalWrite && !didConflictWeeklyGoalWrite {
            didConflictWeeklyGoalWrite=true
            weeklyGoal=BackendWeeklyGoalStatus(
                weekStartDate:weeklyGoal.weekStartDate,weekEndDate:weeklyGoal.weekEndDate,version:weeklyGoal.version+1,
                distance:.init(goal:40_000,done:weeklyGoal.distance.done,remaining:27_600,achieved:false),
                time:.init(goal:12_000,done:weeklyGoal.time.done,remaining:8_100,achieved:false)
            )
            throw ProgressGoalsFailure.weeklyGoalVersionConflict(requestID:"fixture-weekly-goal-write-conflict")
        }
        guard version == weeklyGoal.version else { throw ProgressGoalsFailure.weeklyGoalVersionConflict(requestID:"fixture-weekly-goal-write-conflict") }
        guard Self.isValidGoal(distanceGoalMeters, step:1_000, maximum:500_000),
              Self.isValidGoal(timeGoalSeconds, step:600, maximum:360_000) else {
            throw ProgressGoalsFailure.weeklyGoalValidationFailed(requestID:"fixture-weekly-goal-validation")
        }
        weeklyGoal = BackendWeeklyGoalStatus(
            weekStartDate:weeklyGoal.weekStartDate,
            weekEndDate:weeklyGoal.weekEndDate,
            version:weeklyGoal.version + 1,
            distance:Self.axis(distanceGoalMeters, done:weeklyGoal.distance.done),
            time:Self.axis(timeGoalSeconds, done:weeklyGoal.time.done)
        )
        return weeklyGoal
    }

    func fetchDaily(range:BackendDailyProgressRange) async throws -> BackendDailyProgress {
        if failsDaily { throw ProgressGoalsFailure.serviceUnavailable(requestID:"fixture-daily") }
        let all=[
            BackendDailyProgressDay(date:"2026-09-28",validDistanceMeters:6_400,validSeconds:2_400,runCount:1,activityDay:true),
            BackendDailyProgressDay(date:"2026-09-30",validDistanceMeters:6_000,validSeconds:1_500,runCount:1,activityDay:true),
            BackendDailyProgressDay(date:"2026-10-05",validDistanceMeters:7_200,validSeconds:3_600,runCount:1,activityDay:true)
        ]
        return BackendDailyProgress(range:range,days:all.filter{$0.date >= range.fromDate && $0.date <= range.toDate})
    }

    private static func isValidGoal(_ value:Int64?,step:Int64,maximum:Int64)->Bool {
        guard let value else{return true}
        return value >= step && value <= maximum && value.isMultiple(of:step)
    }

    private static func axis(_ goal:Int64?,done:Int64)->BackendWeeklyGoalAxis {
        guard let goal else{return .init(goal:nil,done:done,remaining:nil,achieved:false)}
        return .init(goal:goal,done:done,remaining:max(0,goal-done),achieved:done>=goal)
    }
}

/// An in-memory UI test seam. The normal app entry point never supplies this reader.
private actor WireframeAuthLogoutFixture: SessionLogoutRequesting {
    private let failureSequence: [SessionLogoutFailure]
    private let alwaysFails: Bool
    private let delaysResponse: Bool
    private var attempts = 0

    init(failureSequence: [SessionLogoutFailure], alwaysFails: Bool, delaysResponse: Bool) {
        self.failureSequence = failureSequence
        self.alwaysFails = alwaysFails
        self.delaysResponse = delaysResponse
    }

    func logout() async throws {
        if delaysResponse {
            // Keep the response alive after request cancellation to exercise the bridge's scope guard.
            await Task.detached { try? await Task.sleep(nanoseconds: 5_000_000_000) }.value
        }
        let attempt = attempts
        attempts += 1
        if failureSequence.indices.contains(attempt) {
            throw failureSequence[attempt]
        }
        if alwaysFails {
            throw SessionLogoutFailure.serviceUnavailable(requestID: "fixture-logout-unavailable")
        }
    }
}

private actor WireframeRunRecordsFixture:RunRecordsReading,RunRecordsUpdating,RunRecordsDeleting {
    let fails:Bool
    let failsWrite:Bool
    let missingWrite:Bool
    private let deletionFailure:RunRecordsFailure?
    private var losesFirstDeleteResponse:Bool
    private var conflictsFirstWrite:Bool
    private var recordMissing=false
    private var removesRunOnNextRefresh:Bool
    private var listReadCount=0
    private var currentSummary:BackendRunSummary

    init(fails:Bool,failsWrite:Bool=false,conflictsFirstWrite:Bool=false,missingWrite:Bool=false,deletionFailure:RunRecordsFailure?=nil,losesFirstDeleteResponse:Bool=false,removesRunOnNextRefresh:Bool=false){
        self.fails=fails;self.failsWrite=failsWrite;self.conflictsFirstWrite=conflictsFirstWrite
        self.missingWrite=missingWrite;self.deletionFailure=deletionFailure;self.losesFirstDeleteResponse=losesFirstDeleteResponse
        self.removesRunOnNextRefresh=removesRunOnNextRefresh;self.currentSummary=Self.makeSummary()
    }

    func fetchRuns(cursor:String?,size:Int) async throws -> BackendRunPage {
        if fails { throw RunRecordsFailure.serverFailure(statusCode:503,requestID:"fixture-run-unavailable") }
        if cursor == nil {
            listReadCount += 1
            if removesRunOnNextRefresh && listReadCount > 1 {
                recordMissing=true
                removesRunOnNextRefresh=false
            }
        }
        if recordMissing { return BackendRunPage(items:[],nextCursor:nil) }
        guard cursor == nil else { return BackendRunPage(items:[],nextCursor:nil) }
        return BackendRunPage(items:[currentSummary],nextCursor:nil)
    }

    func fetchRun(id:String) async throws -> BackendRunDetail {
        guard id == currentSummary.id,!recordMissing else { throw RunRecordsFailure.recordNotFound }
        return BackendRunDetail(summary:currentSummary,points:[],pauses:[],judgement:nil)
    }

    func updateRun(id:String,version:Int64,patch:BackendRunEditPatch) async throws -> BackendRunSummary {
        guard id == currentSummary.id,!recordMissing else{throw RunRecordsFailure.recordNotFound}
        if missingWrite {recordMissing=true;throw RunRecordsFailure.recordNotFound}
        if failsWrite{throw RunRecordsFailure.serverFailure(statusCode:503,requestID:"fixture-run-edit-unavailable")}
        if conflictsFirstWrite{
            conflictsFirstWrite=false
            currentSummary=Self.updated(currentSummary,version:currentSummary.version+1,title:"외부 수정 제목",memo:currentSummary.memo)
            throw RunRecordsFailure.versionConflict
        }
        guard currentSummary.version==version else{throw RunRecordsFailure.versionConflict}
        guard patch.field != nil,
              patch.title.map({$0.utf16.count<=40}) ?? true,
              patch.memo.map({$0.utf16.count<=300}) ?? true else{throw RunRecordsFailure.invalidEdit}
        var title=currentSummary.title
        var memo=currentSummary.memo
        if let value=patch.title{title=value.isEmpty ? nil:value}
        if let value=patch.memo{memo=value.isEmpty ? nil:value}
        currentSummary=Self.updated(currentSummary,version:version+1,title:title,memo:memo)
        return currentSummary
    }

    func deleteRun(id:String,version:Int64) async throws {
        guard id==currentSummary.id else{throw RunRecordsFailure.recordNotFound}
        if let deletionFailure {throw deletionFailure}
        if recordMissing {return}
        guard currentSummary.version==version else{throw RunRecordsFailure.versionConflict}
        recordMissing=true
        if losesFirstDeleteResponse {
            losesFirstDeleteResponse=false
            throw RunRecordsFailure.transport(.networkConnectionLost)
        }
    }

    private static func makeSummary()->BackendRunSummary {
        BackendRunSummary(
            id:"fixture-run-104",clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:2,
            startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
            runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
            verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
            title:"서버 밤 러닝",memo:"fixture only",createdAt:Date(timeIntervalSince1970:1_791_215_462),
            updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:BackendRunPointReward(status:.settled,pointsAwarded:0)
        )
    }

    private static func updated(_ summary:BackendRunSummary,version:Int64,title:String?,memo:String?)->BackendRunSummary {
        BackendRunSummary(
            id:summary.id,clientRunID:summary.clientRunID,version:version,startedAt:summary.startedAt,endedAt:summary.endedAt,
            runDate:summary.runDate,elapsedSeconds:summary.elapsedSeconds,movingSeconds:summary.movingSeconds,
            distanceMeters:summary.distanceMeters,verdict:summary.verdict,verdictReason:summary.verdictReason,
            validDistanceMeters:summary.validDistanceMeters,validSeconds:summary.validSeconds,paceSecondsPerKm:summary.paceSecondsPerKm,
            title:title,memo:memo,createdAt:summary.createdAt,updatedAt:summary.updatedAt.addingTimeInterval(1),pointReward:summary.pointReward
        )
    }
}

struct WireframeRoot:View {
    @MainActor private static var didPrepareFixture=false
    @State var store:RunStore
    @State var shareWorkspace=ShareWorkspace()
    @State var pointsStore:WPointsStore
    @State var remoteReads:WireframeRemoteReadBridge
    let mediaUploadClient: MediaUploadClient?
    let communityMediaClient: CommunityMediaClient?
    @State var runUploadNetworkMonitor=RunUploadNetworkMonitor()
    @State var passwordResetService: (any PasswordResetServing)?
    @State var authSessionStore: (any AuthSessionStoring)?
    #if DEBUG
    @State var authSessionFixtureStore: WireframeAuthSessionFixtureStore?
    #endif
    @State var authSessionClient: AuthSessionClient?
    @State var authLoginBusy = false
    @State var authLoginInvocationID: UUID?
    @State var authLoginTask: Task<Void, Never>?
    @State var socialLoginCoordinator: SocialLoginCoordinator?
    @State var socialLoginPendingAttempt: SocialLoginAttempt?
    @State var socialLoginPendingCompletion: SocialLoginCompletionRequest?
    @State var socialLoginNextCompletionRequestID: UUID?
    @State var socialLoginCompletionSubmitted = false
    @State var socialLoginBusy = false
    @State var socialLoginInvocationID: UUID?
    @State var socialLoginTask: Task<Void,Never>?
    @State var accountLinkPasswordInput = ""
    @State var weeklyGoalDraftVersion:Int64?
    @State var weeklyGoalDraftScopeID:String?
    @State var weeklyGoalDraftDirty=false
    @State var weeklyTimeDraftInvalid=false
    @State var memberProfileDraftBaseline:MemberProfile?
    @State var memberProfileDraftScopeID:String?
    @State var memberProfilePhotoDraftBaseline:Data?
    @State var memberProfilePhotoUploadedDraft:Data?
    @State var memberProfilePhotoUploading=false
    @State var memberProfilePhotoUploadTask:Task<Void,Never>?
    init(
        remoteReadDependencies: WireframeRemoteReadDependencies? = nil,
        runUploadIdentityProvider: (any RunUploadMemberIdentityProviding)? = nil,
        runUploadQueue: (any RunUploadEnqueueing)? = nil,
        runUploadDrainer: (any RunUploadDraining)? = nil
    ){
        let args=ProcessInfo.processInfo.arguments
        self.mediaUploadClient=remoteReadDependencies?.mediaUploadClient
        self.communityMediaClient=remoteReadDependencies?.communityMediaClient
        _passwordResetService=State(initialValue:remoteReadDependencies?.passwordResetService)
        _authSessionStore=State(initialValue:remoteReadDependencies?.authSessionStore)
        #if DEBUG
        _authSessionFixtureStore=State(initialValue:remoteReadDependencies?.authSessionStore as? WireframeAuthSessionFixtureStore)
        #endif
        _authSessionClient=State(initialValue:remoteReadDependencies?.authSessionClient)
        #if DEBUG
        let socialLoginFixture: SocialLoginCoordinator? = {
            guard WReviewMode.tools, args.contains("-wire-social-login-fixture") else{return nil}
            let service=WireframeSocialLoginServiceFixture(
                requiresSignup:args.contains("-wire-social-login-new"),
                failVerificationOnce:args.contains("-wire-social-login-fail-once"),
                delayChallenge:args.contains("-wire-social-login-delay-challenge"),
                delayCompletion:args.contains("-wire-social-login-delay-completion"),
                expireSignupProofOnce:args.contains("-wire-social-login-expired-proof-once"),
                loseCompletionResponseOnce:args.contains("-wire-social-login-lose-completion-once")
            )
            let credentials=WireframeSocialLoginCredentialFixture(cancelled:args.contains("-wire-social-login-cancel"))
            return SocialLoginCoordinator(service:service,credentials:credentials,sessionStore:remoteReadDependencies?.authSessionStore)
        }()
        #else
        let socialLoginFixture: SocialLoginCoordinator? = nil
        #endif
        _socialLoginCoordinator=State(initialValue:socialLoginFixture)
        let defaultsSelection=WWireDefaults.resolve(arguments:args)
        let defaults=defaultsSelection.defaults
        let resetFixture=args.contains("-wire-reset") && !Self.didPrepareFixture
        if resetFixture{Self.didPrepareFixture=true;if let suite=defaultsSelection.suiteName{defaults.removePersistentDomain(forName:suite)}}
        var resolvedIdentityProvider=runUploadIdentityProvider
        var resolvedUploadQueue=runUploadQueue
        var resolvedUploadDrainer=runUploadDrainer
        if let remoteReadDependencies,
           let sessionStore=remoteReadDependencies.authSessionStore,
           let authClient=remoteReadDependencies.authSessionClient,
           let apiClient=remoteReadDependencies.runUploadAPIClient {
            if resolvedIdentityProvider == nil { resolvedIdentityProvider=AuthSessionRunUploadMemberIdentityProvider(sessionStore:sessionStore) }
            if resolvedUploadQueue == nil && resolvedUploadDrainer == nil {
                let directory=URL(fileURLWithPath:NSHomeDirectory(),isDirectory:true).appendingPathComponent("Library/Application Support/MovToRun",isDirectory:true)
                let persistence=FileRunUploadOutboxPersistence(fileURL:directory.appendingPathComponent("run-upload-outbox.json"))
                let sessions=WireframeRunUploadSessionProvider(sessionStore:sessionStore,authClient:authClient)
                if let outbox=try? RunUploadOutbox(persistence:persistence,sessionProvider:sessions,uploader:RunUploadClient(apiClient:apiClient)) {
                    resolvedUploadQueue=outbox
                    resolvedUploadDrainer=outbox
                }
            }
        }
        #if DEBUG
        if args.contains("-wire-run-upload-fixture") {
            let fixture=WireframeRunUploadNetworkFixture()
            resolvedIdentityProvider=WireframeRunUploadIdentityFixture()
            resolvedUploadQueue=fixture
            resolvedUploadDrainer=fixture
        }
        #endif
        let locationCapture:(any RunLocationCapturing)?
        #if DEBUG
        if args.contains("-wire-run-location-fixture") {
            locationCapture=WireframeRunLocationFixture()
        } else if args.contains("-wire-fixture") || args.contains("-wire-user-flow") {
            locationCapture=nil
        } else {
            locationCapture=CoreLocationRunCapture()
        }
        #else
        locationCapture=CoreLocationRunCapture()
        #endif
        #if DEBUG
        let fixtureOwnedRecords: (any RunStoreOwnedRecordsPersisting)? = args.contains("-wire-fixture") ? WireframeOwnedRunRecordsFixture() : nil
        #else
        let fixtureOwnedRecords:(any RunStoreOwnedRecordsPersisting)? = nil
        #endif
        let model=RunStore(defaults:defaults,uploadIdentityProvider:resolvedIdentityProvider,uploadQueue:resolvedUploadQueue,uploadDrainer:resolvedUploadDrainer,ownedRecordsPersistence:fixtureOwnedRecords,locationCapture:locationCapture)
        let pointModel=WPointsStore(defaults:defaults,insufficientFixture:args.contains("-wire-points-insufficient"),emptyFixture:args.contains("-wire-points-empty"))
        if resetFixture{
            model.goal=RunGoal();model.weekly=WeeklyGoal();model.session=nil;model.storageMessage=nil
            model.records=[RunRecord(date:ISO8601DateFormatter().date(from:"2026-09-29T07:12:00+09:00")!,title:"가볍게 달린 아침",memo:"가상 예시 기록",seconds:1808,kilometers:4.82,segments:[RunSegment(distance:1,seconds:378),RunSegment(distance:1,seconds:369),RunSegment(distance:1,seconds:386),RunSegment(distance:1,seconds:370),RunSegment(distance:0.82,seconds:305)],isExample:true)]
            model.persist()
        }
        if args.contains("-wire-legacy-invalid-run") {
            model.records=[RunRecord(date:ISO8601DateFormatter().date(from:"2026-09-29T07:12:00+09:00")!,title:"기존 기록",seconds:312,kilometers:0)]
            model.persist()
        }
        if args.contains("-wire-fixture"), defaultsSelection.suiteName != nil,
           let i=args.firstIndex(of:"-wire-home-weekly-example"),args.indices.contains(i+1) {
            let date=ISO8601DateFormatter().date(from:"2026-09-29T07:12:00+09:00")!
            let examples:[String:(Double,Double,Double?,Int?)] = [
                "below":(12,4500,20,nil), "exact":(20,7500,20,nil), "over":(23,8625,20,nil),
                "time":(12,5400,nil,120), "both":(12,5400,20,120), "half":(20,5400,20,120),
                "both-over":(23,9000,20,120), "long-week":(60,36000,nil,600),
                "both-long-over":(60,39600,50,600), "unset":(12,4500,nil,nil)
            ]
            if let example=examples[args[i+1]] {
                model.weekly.distanceEnabled=example.2 != nil
                model.weekly.kilometers=example.2 ?? 20
                model.weekly.timeEnabled=example.3 != nil
                model.weekly.minutes=example.3 ?? 120
                model.records=[RunRecord(date:date,title:"가볍게 달린 아침",memo:"가상 예시 기록",seconds:example.1,kilometers:example.0,segments:[RunSegment(distance:example.0,seconds:example.1)],isExample:true)]
                model.persist()
            }
        }
        let state=WireState();if resetFixture{state.profile=WLocalProfile();state.profile.logged=true;state.save()}
        _ui=State(initialValue:state);_store=State(initialValue:model);_pointsStore=State(initialValue:pointModel);_remoteReads=State(initialValue:WireframeRemoteReadBridge(dependencies:remoteReadDependencies))
    }
    @State var ui=WireState()
    @State var selectedPointCategory:WPointCategory = .image
    @State var selectedPointKind:WPointKind = .all
    @State var showingPointPurchaseConfirmation=false
    @State var showingCommunityDiscardConfirmation=false
    @State var communityDiscardContext:WCommunityDiscardContext?
    @State var communityComposerOriginal:WCommunityComposerSnapshot?
    @State var communityComposerExitDestination:String?
    @State var communityProfileExitDestination:String?
    @State var communityCrewExitDestination:String?
    @State var communityCrewDraftOriginal:WCommunityCrewDraftSnapshot?
    @State var showingCommunityCrewKickConfirmation=false
    @State var communityCrewManageExitDestination:String?
    @State var showingCrewBoardArchiveConfirmation=false
    @State var communityCrewPendingArchiveBoardID:String?
    @State var showingCommunityCrewApplicationCancelConfirmation=false
    @State var communityCrewPendingCancellationApplicationID:String?
    @State var communityBottomBarVisible=true
    @State var communityScrollToTopVisible=false
    @State var lastCommunityScrollOffset:CGFloat?
    @State var communityBoardScrollOffset:CGFloat=0
    @FocusState var otpInputFocused:Bool
    @FocusState var authInput:String?
    @FocusState var communitySearchFocused:Bool
    @State var splash=true
    @AppStorage("appearance",store:WWireDefaults.resolve().defaults) var appearance="system"
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduceMotion:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    @Namespace var indicator
    @Environment(\.scenePhase) var scenePhase
    var current:RunRecord {if ui.testing && ui.screen.hasPrefix("R") && store.session==nil{return RunRecord(date:Date(),title:"현재 러닝",seconds:ui.screen=="R01" ? 4:302,kilometers:ui.screen=="R01" ? 0:0.81)};if let id=ui.selected,let r=store.records.first(where:{$0.id==id}){return r};return store.session?.record(at:Date()) ?? store.records.first ?? RunRecord(date:Date(),title:"현재 러닝",seconds:0,kilometers:0)}
    var roots:[String]{WRootTab.allCases.map(\.route)}
    var remoteReadFeature:WireframeRemoteReadFeature? {
        if ["L04","L07"].contains(ui.screen), ui.remoteSelectedRunID == nil { return nil }
        return WireframeRemoteReadFeature.forScreen(ui.screen)
    }
    var remoteReadTaskKey:String { "\(ui.screen)|\(ui.remoteAccountScopeID)|\(ui.remoteSelectedRunID ?? "")" }
    var remoteDailyProgressRange:BackendDailyProgressRange {
        ui.month ? .month(containing:ui.calendarMonth):.week(containing:WReviewClock.now)
    }
    var remoteDailyProgressTaskKey:String {
        WireframeDailyProgressTaskIdentity.key(screen:ui.screen,accountScopeID:ui.remoteAccountScopeID,range:remoteDailyProgressRange)
    }
    var reviewTools:Bool {WReviewMode.tools}
    var isAccountScreen:Bool {ui.screen.hasPrefix("A") || (5...17).contains(Int(ui.screen.dropFirst()) ?? 0) && ui.screen.hasPrefix("T")}
    var isRoot:Bool {roots.contains(ui.screen) || ["H02","H05","L01"].contains(ui.screen) || (ui.screen=="C08" && ui.communitySelectedUserID==ui.communityViewerMemberID)}
    var isCommunityPrimaryTabScreen:Bool {ui.screen=="C01" || ui.screen=="C02" || ui.screen=="C03" || ui.screen=="C15" || (ui.screen=="C08" && ui.communitySelectedUserID==ui.communityViewerMemberID)}
    var routeScreenTransition:AnyTransition {
        guard !isAccountScreen else{return .identity}
        let insertion:AnyTransition=reduceMotion ? .opacity:.move(edge:ui.forward ? .trailing:.leading)
        let removal:AnyTransition=reduceMotion ? .opacity:.move(edge:ui.forward ? .leading:.trailing)
        let hideOutgoing=AnyTransition.modifier(active:WOutgoingRouteAccessibility(hidden:true),identity:WOutgoingRouteAccessibility(hidden:false))
        return .asymmetric(insertion:insertion,removal:hideOutgoing.combined(with:removal))
    }
    var body:some View {
        rootCommunityManageUpdates.alert("변경사항을 버릴까요?",isPresented:$showingCommunityDiscardConfirmation){
            Button("계속 편집",role:.cancel){clearCommunityDiscardDestinations()}
            Button("버리기",role:.destructive){discardCurrentCommunityDraft()}
        }message:{Text(communityDiscardContext?.message ?? "")}
    }
    var rootCommunityManageUpdates:some View {
        rootCommunityTextUpdates
            .onChange(of:ui.communityCrewManageDraft?.name ?? ""){_,value in guard var draft=ui.communityCrewManageDraft else{return};let limited=WCommunityTextLimit.apply(value,limit:WCommunityCrewPolicy.boardNameLimit);if limited != value{draft.name=limited;ui.communityCrewManageDraft=draft}}
            .onChange(of:ui.communityCrewManageDraft?.title ?? ""){_,value in guard var draft=ui.communityCrewManageDraft else{return};let limited=WCommunityTextLimit.apply(value,limit:WCommunityCrewPolicy.announcementTitleLimit);if limited != value{draft.title=limited;ui.communityCrewManageDraft=draft}}
            .onChange(of:ui.communityCrewManageDraft?.text ?? ""){_,value in guard var draft=ui.communityCrewManageDraft else{return};let limit=draft.kind == .guidance ? WCommunityCrewPolicy.guidanceLimit:WCommunityCrewPolicy.announcementTextLimit;let limited=WCommunityTextLimit.apply(value,limit:limit);if limited != value{draft.text=limited;ui.communityCrewManageDraft=draft}}
    }
    var rootCommunityTextUpdates:some View {
        rootRemoteStateUpdates
            .onChange(of:ui.communityDraftTitle){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.title);if limited != value{ui.communityDraftTitle=limited}}
            .onChange(of:ui.communityDraftBody){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.body);if limited != value{ui.communityDraftBody=limited}}
            .onChange(of:ui.communityComment){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.comment);if limited != value{ui.communityComment=limited}}
            .onChange(of:ui.communityCrewJoinMemo){_,value in let limited=WCommunityTextLimit.apply(value,limit:300);if limited != value{ui.communityCrewJoinMemo=limited}}
            .onChange(of:ui.communityCrewDraftName){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityCrewPolicy.nameLimit);if limited != value{ui.communityCrewDraftName=limited};ui.communityCrewNameCheck=""}
            .onChange(of:ui.communityCrewDraftIntroduction){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityCrewPolicy.introductionLimit);if limited != value{ui.communityCrewDraftIntroduction=limited}}
            .onChange(of:ui.communityCrewMemberWarningDraft){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityCrewPolicy.memberWarningLimit);if limited != value{ui.communityCrewMemberWarningDraft=limited}}
    }
    var rootRemoteStateUpdates:some View {
        rootTaskViews
            .onChange(of:ui.screen){oldScreen,newScreen in if oldScreen=="T15" && newScreen != "T15"{accountLinkPasswordInput=""}}
            .onChange(of:scenePhase){_,phase in handleScenePhaseChange(phase)}
            .onChange(of:ui.remoteAccountScopeID){_,scopeID in handleRemoteAccountScopeChange(scopeID)}
            .onChange(of:remoteReads.memberProfileState){_,state in handleRemoteMemberProfileStateChange(state)}
            .onChange(of:remoteReads.memberProfileWriteState){_,state in handleRemoteMemberProfileWriteStateChange(state)}
            .onChange(of:remoteReads.weeklyGoalState){_,state in handleRemoteWeeklyGoalStateChange(state)}
            .onChange(of:remoteReads.weeklyGoalWriteState){_,state in handleRemoteWeeklyGoalWriteStateChange(state)}
            .onChange(of:remoteReads.weeklyGoalConflictRefreshState){_,state in handleRemoteWeeklyGoalConflictRefreshStateChange(state)}
            .onChange(of:remoteReads.sessionLogoutState){_,state in handleSessionLogoutStateChange(state)}
            .onChange(of:remoteReads.accountLinkState){_,state in
                guard state == .completed else{return}
                switch remoteReads.accountLinkCompletedMutation {
                case .link where ui.screen == "T06": go("T17")
                case .unlink where ui.screen == "T15" && ui.pending == "T08": go("T17")
                default: break
                }
            }
    }
    var rootTaskViews:some View {
        rootStyledLayers
            .task(id:remoteReadTaskKey){
                let feature=remoteReadFeature
                let scopeID=ui.remoteAccountScopeID
                let runID=ui.remoteSelectedRunID
                let screen=ui.screen
                guard !Task.isCancelled,
                      ui.screen==screen,
                      ui.remoteAccountScopeID==scopeID,
                      ui.remoteSelectedRunID==runID else{return}
                await remoteReads.activate(
                    feature:feature,
                    accountScopeID:scopeID,
                    runID:runID,
                    screen:screen,
                    routeIsCurrent:{
                        ui.screen==screen && ui.remoteAccountScopeID==scopeID && ui.remoteSelectedRunID==runID
                    }
                )
            }
            .task {
                runUploadNetworkMonitor.onReconnect={Task{@MainActor in _=await store.retryPendingRunUploads()}}
                runUploadNetworkMonitor.start()
                await configureRootForLaunch()
                await store.recoverPendingRunUploads()
                if runUploadNetworkMonitor.isOnline {_=await store.drainPendingRunUploads()}
            }
            .task(id:store.session?.startedAt) {
                guard let startedAt=store.session?.startedAt else{return}
                while !Task.isCancelled,store.session?.startedAt==startedAt {
                    if let record=await store.finishIfPastSixHourLimit(at:Date()) {
                        ui.selected=record.id
                        ui.screen="S01"
                        _=await store.drainPendingRunUploads()
                        return
                    }
                    try? await Task.sleep(for:.seconds(1))
                }
            }
    }
    var rootStyledLayers:some View {
        rootLayers.foregroundStyle(W.ink).tint(W.ink)
            .preferredColorScheme(ThemePreference(rawValue:appearance)?.colorScheme)
            .clipShape(WScreenClip(extendMap:["R01","R02","R03","R04","R05","R07","R08","R10"].contains(ui.screen)))
            // Keep the theme-aware canvas outside the route clip; only the content is clipped.
            .background { W.paper.ignoresSafeArea(.container,edges:.all) }
    }
    var rootLayers:some View {
        ZStack {
            VStack(spacing:0){
                if isRoot {
                    GeometryReader { geo in
                        ZStack {
                            if ui.screen=="L01" {
                                recordsRoot
                            } else {
                                home.accessibilityElement(children:.contain).offset(x:ui.rootIndex==2 ? 0:ui.rootIndex>2 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==2 || ui.previousRootIndex==2 ? 1:0).accessibilityHidden(ui.rootIndex != 2 || splash).allowsHitTesting(ui.rootIndex == 2 && !splash)
                                ready.accessibilityElement(children:.contain).offset(x:ui.rootIndex==1 ? 0:ui.rootIndex>1 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==1 || ui.previousRootIndex==1 ? 1:0).accessibilityHidden(ui.rootIndex != 1 || splash).allowsHitTesting(ui.rootIndex == 1 && !splash)
                                points.accessibilityElement(children:.contain).offset(x:ui.rootIndex==0 ? 0:ui.rootIndex>0 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==0 || ui.previousRootIndex==0 ? 1:0).accessibilityHidden(ui.rootIndex != 0 || splash).allowsHitTesting(ui.rootIndex == 0 && !splash)
                                community.accessibilityElement(children:.contain).offset(x:ui.rootIndex==3 ? 0:ui.rootIndex>3 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==3 || ui.previousRootIndex==3 ? 1:0).accessibilityHidden(ui.rootIndex != 3 || splash).allowsHitTesting(ui.rootIndex == 3 && !splash)
                                profile.accessibilityElement(children:.contain).offset(x:ui.rootIndex==4 ? 0:ui.rootIndex>4 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==4 || ui.previousRootIndex==4 ? 1:0).accessibilityHidden(ui.rootIndex != 4 || splash).allowsHitTesting(ui.rootIndex == 4 && !splash)
                            }
                        }.frame(width:geo.size.width,height:geo.size.height).clipped()
                        }
                    if !isCommunityPrimaryTabScreen { nav }
                }
            }
            .opacity(!splash ? 1:0)
            .allowsHitTesting(!splash)
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("screen-"+ui.screen)
            .accessibilityHidden(splash)
            if !isRoot && !splash {
                if ui.screen=="C20" {
                    VStack(spacing:0){
                        screenView.id(ui.screen).accessibilityElement(children:.contain).accessibilityIdentifier("screen-"+ui.screen)
                            .environment(\.authPageMotion,WAuthMotionContext(enabled:isAccountScreen,reduced:reduceMotion,forward:ui.forward))
                            .transition(routeScreenTransition)
                            .frame(maxHeight:.infinity)
                        nav
                    }.zIndex(10)
                }else{
                    screenView.id(["R01","R02","R03","R04","R05","R07","R08","R10"].contains(ui.screen) ? "run-map":ui.screen).accessibilityElement(children:.contain).accessibilityIdentifier("screen-"+ui.screen)
                        .environment(\.authPageMotion,WAuthMotionContext(enabled:isAccountScreen,reduced:reduceMotion,forward:ui.forward))
                        .transition(routeScreenTransition)
                }
            }
#if DEBUG
            if remoteReads.exposesAccountLinkTestTrace {
                Text(remoteReads.accountLinkTestTrace.isEmpty ? "trace-pending" : remoteReads.accountLinkTestTrace)
                    .font(.system(size:1))
                    .frame(width:1,height:1)
                    .opacity(0.01)
                    .accessibilityElement()
                    .accessibilityLabel(remoteReads.accountLinkTestTrace.isEmpty ? "trace-pending" : remoteReads.accountLinkTestTrace)
                    .accessibilityIdentifier("accountLinkActionTrace")
                    .allowsHitTesting(false)
            }
#endif
            if ui.otpSuccess && ["A02","A15"].contains(ui.screen){WOTPSuccess(reduced:reduceMotion).padding(.horizontal,22).frame(maxHeight:.infinity,alignment:.bottom).padding(.bottom,112).allowsHitTesting(false)}
            if splash {WSplash().frame(maxWidth:.infinity,maxHeight:.infinity).background(W.paper)}
            if let menu=ui.communityMoreMenu{communityModerationMenu(menu).zIndex(50)}
            if let dialog=ui.communityModerationDialog{communityModerationDialogView(dialog).zIndex(60)}
            if let postID=ui.communityPostDeleteConfirmationID{communityPostDeleteConfirmationView(postID).zIndex(70)}
            if isCommunityPrimaryTabScreen && communityBottomBarVisible && !splash {
                VStack(spacing:0){Spacer(minLength:0);communityNav}
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .transition(.move(edge:.bottom).combined(with:.opacity)).zIndex(40)
            }
        }.onChange(of:ui.screen){_,_ in resetCommunityScrollPresentation()}
    }
    func configureRootForLaunch() async {
                let args=ProcessInfo.processInfo.arguments
#if DEBUG
                if let cleanupService = AuthSessionFixtureLaunchPolicy.cleanupServiceName(arguments: args),
                   let fixtureStore = authSessionFixtureStore,
                   fixtureStore.serviceName == cleanupService {
                    do { try fixtureStore.clearFixtureSession() }
                    catch { ui.error="테스트 세션을 정리하지 못했어요." }
                    ui.setLoggedIn(false);ui.save();ui.authFilled=false
                    splash=false;ui.screen="A01";ui.rootIndex=2
                    return
                }
#endif
                if let i=args.firstIndex(of:"-wire-community-viewer"),args.indices.contains(i+1){ui.communityViewerMemberID=args[i+1]}
                if WReviewMode.tools && args.contains("-wire-community-not-member"){ui.communityJoinedCrewIDs.removeAll()}
                if WReviewMode.tools,let i=args.firstIndex(of:"-wire-community-crew"),args.indices.contains(i+1){ui.communitySelectedCrewID=args[i+1]}
                if WReviewMode.tools,let i=args.firstIndex(of:"-wire-community-board"),args.indices.contains(i+1){ui.communityCrewBoardID=args[i+1]}
                if reviewTools && args.contains("-wire-community-crew-data-test"),var crew=WCommunityCrewFixtures.values.first(where:{$0.id=="dawn"}) {
                    crew=WCommunityCrewFixtures.informationReviewFixture(crew,introduction:"선택된 크루 소개",ownerMemberID:"fixture-member-ga-on",level:7,boards:Array(crew.boards.prefix(1)));ui.communityCrewOverrides[crew.id]=crew
                }
                if reviewTools && args.contains("-wire-community-review55-crew-info"),let crew=WCommunityCrewFixtures.values.first(where:{$0.id=="dawn"}) {
                    ui.communityCrewOverrides[crew.id]=WCommunityCrewFixtures.informationReviewFixture(crew,introduction:"가볍게 하루를 여는 사람들",level:1);ui.profile.nickname="이메일데모"
                }
                if reviewTools && args.contains("-wire-empty-community-notifications"){ui.communityNotificationCenter=WCommunityNotificationCenter(notifications:[])}
                if reviewTools && args.contains("-wire-community-notification-samples"){prepareCommunityNotificationSamples()}
                if reviewTools && args.contains("-wire-community-notification-missing-target") {ui.communityNotificationCenter=WCommunityNotificationCenter(notifications:[WCommunityNotification(id:"missing-post",title:"게시물 알림 예시",text:"삭제되었거나 접근할 수 없는 게시물입니다.",target:.post(postID:"deleted-post"))])}
                if let i=args.firstIndex(of:"-wire-screen"),args.indices.contains(i+1){
                    let requestedScreen=args[i+1];ui.screen=requestedScreen=="B01" ? "POINTS":requestedScreen;ui.rootIndex=["H02":1,"H05":1][ui.screen] ?? roots.firstIndex(of:ui.screen) ?? (isCommunityPrimaryTabScreen ? 3:ui.screen.hasPrefix("L") ? 1:2);ui.testing=true;splash=false;prepare(ui.screen);if requestedScreen=="B08"{ui.selectedPointProductID="frame"}
                    if args.contains("-wire-community-course-two-records"),let date=ISO8601DateFormatter().date(from:"2026-10-02T07:12:00+09:00") {store.records.append(RunRecord(date:date,title:"저녁 공원 러닝",seconds:900,kilometers:3.4,segments:[RunSegment(distance:3.4,seconds:900)],isExample:true));store.persist()}
                    if args.contains("-wire-community-anonymous-post"),let index=ui.communityPosts.firstIndex(where:{$0.id=="p1"}) {let original=ui.communityPosts[index];ui.communityPosts[index]=WCommunityPost(id:original.id,authorMemberID:original.authorMemberID,author:"노출되면 안 되는 실명",rank:original.rank,board:"익명게시판",title:original.title,text:original.text,date:original.date,likes:original.likes,views:original.views,comments:[WCommunityComment(id:"c1",author:"노출되면 안 되는 실명",authorMemberID:original.authorMemberID,text:"익명 댓글",date:"10.05 08:42")],imageName:original.imageName,hot:original.hot,crewID:original.crewID)}
                    if reviewTools && args.contains("-wire-community-crew-post"),let index=ui.communityPosts.firstIndex(where:{$0.id=="p1"}){ui.communityPosts[index].crewID="dawn";ui.communityPosts[index].crewBoardID="dawn-board-2";ui.communityPosts[index].isCrewOnly=true;ui.communityPosts[index].comments.append(WCommunityComment(id:"c1-reply",author:"가온러너",authorMemberID:"fixture-member-ga-on",text:"네, 다음에 함께 달려요.",date:"10.05 08:50",parentID:"c1"))}
                    if reviewTools && args.contains("-wire-community-empty-hot") {for index in ui.communityPosts.indices{ui.communityPosts[index].hot=false}}
                    if reviewTools{ui.seedCommunityPhotoFixtures(draft:args.contains("-wire-community-photo-draft-fixture"),post:args.contains("-wire-community-photo-post-fixture"),videoPost:args.contains("-wire-community-video-post-fixture"),videoDraft:args.contains("-wire-community-video-draft-fixture"))}
                    if WReviewMode.tools,let i=args.firstIndex(of:"-wire-community-verification-status"),args.indices.contains(i+1),let status=WCommunityVerificationStatus(rawValue:args[i+1]) {ui.communityVerification.status=status}
                    if ["Q01","Q02","Q03"].contains(ui.screen),let valid=store.records.first(where:{$0.isValid}){ui.selected=valid.id}
                    if WireState.otpScreens.contains(ui.screen){let age:TimeInterval=ui.screen=="A21" ? 301:args.contains("-wire-otp-resend-ready") ? 60:0;ui.challengeIssued=Date().addingTimeInterval(-age);ui.challengeCode=ui.screen=="A23" ? "731204":"482619";ui.otpCodeIssuer.seed(ui.challengeCode);ui.authEmail="runner@example.test";ui.codeAttempts=ui.screen=="A22" ? 5:ui.screen=="A20" ? 1:0;if ui.screen=="A20"{ui.error="코드가 일치하지 않아요. 4번 더 시도할 수 있어요."}}
                    if WireState.passwordResetScreens.contains(ui.screen),ui.screen != "A10"{ui.passwordReset.prepareFixture(screen:ui.screen,resendReady:args.contains("-wire-password-reset-resend-ready"))}
                    if args.contains("-wire-collapsed"){ui.collapsed=true}
                    if ui.screen.hasPrefix("R") || ["H05","H06","S03"].contains(ui.screen){
                        store.session=DemoSession(startedAt:Date().addingTimeInterval(-302),segmentStart:["R01","R02","R03","R07","R08"].contains(ui.screen) ? Date():nil,accumulated:ui.screen=="R12" ? 0:ui.screen=="R01" ? 4:302,goal:store.goal,distance:ui.screen=="R12" || ui.screen=="R01" ? 0:0.81)
                    }
                    if args.contains("-wire-review-size") {
                        if ["M01","L02","L03","H00","H01","H02","H05","H07","H08"].contains(ui.screen){store.records=[]}
                        if ui.screen=="H09" || ui.screen=="L01"{store.records=[RunRecord(date:ISO8601DateFormatter().date(from:"2026-10-01T07:12:00+09:00")!,title:"주간 목표 확인 예시",seconds:8625,kilometers:23,segments:[RunSegment(distance:23,seconds:8625)])]}
                        if ui.screen=="A03"{ui.nickname=""}
                        if ui.screen=="A14"{ui.provider=""}
                        if ui.screen=="S03"{ui.selected=store.records.first?.id}
                        if WireState.otpScreens.contains(ui.screen){ui.code="";ui.error="";ui.challengeIssued=nil}

                    }
                    if ui.screen=="S05"{var record=current;record.kilometers=0;record.seconds=312;record.segments=[RunSegment(distance:0,seconds:312,type:"gps-gap",reason:"GPS 수신 실패 예시")];store.records=[record];ui.selected=record.id}
                    if WReviewMode.tools,let i=args.firstIndex(of:"-wire-run-point-reward"),args.indices.contains(i+1),let index=store.records.indices.first {
                        let reward:RunPointReward?
                        switch args[i+1] {
                        case "pending": reward=try? RunPointReward(status:.pending,pointsAwarded:nil)
                        case "settled-zero": reward=try? RunPointReward(status:.settled,pointsAwarded:0)
                        case "settled-positive": reward=try? RunPointReward(status:.settled,pointsAwarded:15)
                        case "unavailable": reward=try? RunPointReward(status:.unavailable,pointsAwarded:nil)
                        default: reward=nil
                        }
                        if let reward {store.records[index].pointReward=reward;store.persist()}
                    }
                }else{
                    let splashMilliseconds=args.contains("-wire-splash-test-hold") ? 3000:1040
                    try? await Task.sleep(for:.milliseconds(splashMilliseconds))
                    if reviewTools && !args.contains("-wire-auth-session-flow-fixture") {
                        // Screen-review fixtures preserve their clearly labeled local
                        // navigation demo. The ordinary app and session-flow fixture
                        // always use Keychain as the sign-in authority.
                        splash=false
                        if !ui.profile.logged { ui.screen="A01" }
                        else if store.session != nil { ui.screen="H06" }
                    } else {
                        await restoreAuthSessionForLaunch()
                    }
                }
    }
    func handleScenePhaseChange(_ phase:ScenePhase){
        if phase != .active{ui.clearAuthSecrets();ui.otpSuccess=false}
        if phase == .active {
            Task { @MainActor in
                if let record=await store.finishIfPastSixHourLimit(at:Date()) {
                    ui.selected=record.id
                    ui.screen="S01"
                }
                await store.recoverPendingRunUploads()
                if runUploadNetworkMonitor.isOnline {_=await store.drainPendingRunUploads()}
            }
        }
    }
    func handleRemoteAccountScopeChange(_ scopeID:String){
        store.cancelPendingRunUploadDrain()
        cancelMemberProfilePhotoUpload()
        memberProfilePhotoUploadedDraft=nil
        memberProfilePhotoDraftBaseline=nil
        remoteReads.accountDidChange(to:scopeID)
        memberProfileDraftBaseline=nil
        memberProfileDraftScopeID=scopeID
        if ui.screen=="M02" {ui.nickname="";ui.introduction="";ui.region="選択 안 함";ui.error=""}
        if ui.screen=="T02" {ui.weight="";ui.error=""}
        guard ["H04","H10"].contains(ui.screen) else{return}
        weeklyGoalDraftVersion=nil
        weeklyGoalDraftScopeID=scopeID
        weeklyGoalDraftDirty=false
        weeklyTimeDraftInvalid=false
        ui.weekly=emptyWeeklyGoalDraft()
        ui.error=""
    }
    func handleRemoteMemberProfileStateChange(_ state:MemberProfileLoadState){
        guard case .loaded(let profile)=state,
              remoteReads.accountScopeID==ui.remoteAccountScopeID else{return}
        applyMemberProfilePublicFields(profile)
        if ui.screen=="M02",memberProfileDraftBaseline==nil || memberProfileDraftScopeID != ui.remoteAccountScopeID {
            beginMemberProfileDraft(profile,for:"M02")
        } else if ui.screen=="T02",memberProfileDraftBaseline==nil || memberProfileDraftScopeID != ui.remoteAccountScopeID {
            beginMemberProfileDraft(profile,for:"T02")
        }
    }
    func handleRemoteMemberProfileWriteStateChange(_ state:MemberProfileWriteState){
        switch state {
        case .failed(let failure):
            guard ["M02","T02"].contains(ui.screen) else{return}
            ui.error=failure.writeMessage
        case .saved:
            guard case .loaded(let profile)=remoteReads.memberProfileState else{
                ui.error=MemberProfileFailure.invalidResponse.writeMessage
                remoteReads.consumeMemberProfileWriteResult()
                return
            }
            if ui.screen=="M02" {
                beginMemberProfileDraft(profile,for:"M02")
                applyMemberProfilePublicFields(profile)
                ui.profile.photo=ui.photo
                ui.save()
            } else if ui.screen=="T02" {
                beginMemberProfileDraft(profile,for:"T02")
                ui.profile.weight=WMemberProfileValidation.weightText(profile.weightKg)
                ui.save()
            }
            ui.error=""
            remoteReads.consumeMemberProfileWriteResult()
            performBack()
        case .idle,.saving:
            break
        }
    }
    func handleRemoteWeeklyGoalStateChange(_ state:WeeklyGoalReadState){
        guard ["H04","H10"].contains(ui.screen),weeklyGoalDraftScopeID==ui.remoteAccountScopeID,
              case .loaded(let status)=state else{return}
        weeklyGoalDraftVersion=status.version
        if ui.screen=="H04" && !weeklyGoalDraftDirty{applyWeeklyGoalDraft(status)}
    }
    func handleRemoteWeeklyGoalWriteStateChange(_ state:WeeklyGoalWriteState){
        switch state {
        case .failed(let failure):
            if ["H04","H10"].contains(ui.screen){
                ui.error=failure.weeklyGoalWriteMessage
                if case .weeklyGoalVersionConflict = failure { weeklyGoalDraftDirty=true }
            }
        case .saved:
            let destination=ui.screen
            ui.error=""
            remoteReads.consumeWeeklyGoalWriteResult()
            if destination=="H10"{go("H00")}else if destination=="H04"{back()}
        case .idle,.saving:
            break
        }
    }
    func handleRemoteWeeklyGoalConflictRefreshStateChange(_ state:WeeklyGoalConflictRefreshState){
        guard ["H04","H10"].contains(ui.screen) else{return}
        switch state {
        case .failed,.refreshed:
            ui.error=""
        case .idle,.required,.refreshing:
            break
        }
    }
    func handleSessionLogoutStateChange(_ state:SessionLogoutState){
        guard ui.screen=="T10",remoteReads.accountScopeID==ui.remoteAccountScopeID else{return}
        guard state == .loggedOut else{return}
        guard store.session==nil else{go("T14");return}
        store.cancelPendingRunUploadDrain()
        ui.setLoggedIn(false);ui.save();ui.authFilled=false;go("A01")
    }
    func discardCurrentCommunityDraft(){
        switch communityDiscardContext {
        case .some(.profile):discardCommunityProfileDraftAndExit()
        case .some(.crew):discardCommunityCrewDraftAndExit()
        case .some(.crewManage):discardCommunityCrewManageDraftAndExit()
        case .some(.postComposer),.some(.courseComposer):discardCommunityComposerAndExit()
        case nil:break
        }
        communityDiscardContext=nil
    }
    func prepareSocialLoginNavigation(to route:String)->Bool {
        guard WSocialLoginNavigationPolicy.canNavigateAway(from:ui.screen,completionSubmitted:socialLoginCompletionSubmitted) else{return false}
        guard route != ui.screen else{return true}
        if ui.screen=="A01",route != "A01",authLoginBusy {
            authLoginInvocationID=nil;authLoginTask?.cancel();authLoginTask=nil;authLoginBusy=false
        }
        if ui.screen=="A14" {
            socialLoginInvocationID=nil
            socialLoginTask?.cancel()
            if route != "A02" {
                socialLoginPendingAttempt=nil
                socialLoginPendingCompletion=nil
                socialLoginNextCompletionRequestID=nil
            }
        }
        if socialLoginPendingAttempt != nil && ["A02","A03"].contains(ui.screen) && !["A02","A03"].contains(route) {
            socialLoginPendingAttempt=nil
            socialLoginPendingCompletion=nil
            socialLoginNextCompletionRequestID=nil
        }
        return true
    }
    func go(_ id:String){
        guard !remoteReads.isAccountLinkMutationInFlight, !remoteReads.isMemberWithdrawalMutationInFlight else{return}
        let route=id=="B01" ? "POINTS":id
        guard prepareSocialLoginNavigation(to:route) else{return}
        if route=="C08" && ui.communityCardOriginAnonymous{return}
        if ui.communityProfileEditing && route != "C08"{requestCommunityProfileExit(destination:"route:\(route)");return}
        if ui.communityCrewDraftID != nil && route != "C20"{requestCommunityCrewExit(destination:"route:\(route)");return}
        if let draft=ui.communityCrewManageDraft,route != communityCrewManageScreen(for:draft.kind){requestCommunityCrewManageExit(destination:"route:\(route)");return}
        if ["C05","C13"].contains(ui.screen),route != "C09"{requestCommunityComposerExit(destination:"route:\(route)");return}
        performNavigation(route)
    }
    func performNavigation(_ route:String){
        guard !remoteReads.isAccountLinkMutationInFlight, !remoteReads.isMemberWithdrawalMutationInFlight,
              prepareSocialLoginNavigation(to:route) else{return}
        if ui.screen=="L07",route != "L07"{remoteReads.cancelRunRecordDeletion()}
        if ["H04","H10"].contains(ui.screen),route != ui.screen{remoteReads.cancelWeeklyGoalMutation()}
        if ui.screen=="M02",route != ui.screen{cancelMemberProfilePhotoUpload()}
        if ["M02","T02"].contains(ui.screen),route != ui.screen{remoteReads.cancelMemberProfileMutation();restoreMemberProfileDraft()}
        if route=="C19"{guard let crew=communityCrew(),communityCrewIsMember(crew) else{return}}
        if route=="A01" && ui.screen=="T10"{shareWorkspace.clear()}
        let mapStates=["R01","R02","R03","R04","R05","R07","R08","R10"]
        let duration=mapStates.contains(ui.screen) && mapStates.contains(route) ? 0.3:((ui.screen=="L01" && route=="L04") || (ui.screen=="L04" && route=="L01")) ? 0.32:0.24
        prepare(route)
        withAnimation(reduceMotion ? nil:.timingCurve(0.2,0.8,0.2,1,duration:duration)){ui.go(route)}
    }
    func back(){
        guard !remoteReads.isAccountLinkMutationInFlight, !remoteReads.isMemberWithdrawalMutationInFlight else{return}
        if ui.communityProfileEditing{requestCommunityProfileExit(destination:"back");return}
        if ui.communityCrewDraftID != nil{requestCommunityCrewExit(destination:"back");return}
        if ui.communityCrewManageDraft != nil{requestCommunityCrewManageExit(destination:"back");return}
        if ["C05","C13"].contains(ui.screen){requestCommunityComposerExit(destination:"back");return}
        performBack()
    }
    func performBack(){
        guard !remoteReads.isAccountLinkMutationInFlight, !remoteReads.isMemberWithdrawalMutationInFlight else{return}
        let source=ui.screen
        if source=="T11" {
            _=remoteReads.cancelMemberWithdrawalFlow()
            ui.deleteConsent=false
            withAnimation(reduceMotion ? nil:.timingCurve(0.2,0.8,0.2,1,duration:0.24)){ui.back()}
            return
        }
        if source=="T15",ui.pending=="T11" {
            if ui.pendingBack=="T16" { _=remoteReads.cancelAccountLinkFlow() }
            else { _=remoteReads.cancelMemberWithdrawalFlow() }
            ui.deleteConsent=false
            ui.cancelReauthentication()
            return
        }
        let destination=ui.path.last ?? "H00"
        guard prepareSocialLoginNavigation(to:destination) else{return}
        if source=="L07"{remoteReads.cancelRunRecordDeletion()}
        if ["H04","H10"].contains(source){remoteReads.cancelWeeklyGoalMutation()}
        if source=="M02"{cancelMemberProfilePhotoUpload()}
        if ["M02","T02"].contains(source){remoteReads.cancelMemberProfileMutation();restoreMemberProfileDraft()}
        withAnimation(reduceMotion ? nil:.timingCurve(0.2,0.8,0.2,1,duration:0.24)){ui.back()}
    }
    func selectRootTab(_ route:String){
        guard !remoteReads.isAccountLinkMutationInFlight, !remoteReads.isMemberWithdrawalMutationInFlight,
              prepareSocialLoginNavigation(to:route) else{return}
        if ui.communityProfileEditing{requestCommunityProfileExit(destination:"tab:\(route)");return}
        if ui.communityCrewDraftID != nil{requestCommunityCrewExit(destination:"tab:\(route)");return}
        if ui.communityCrewManageDraft != nil{requestCommunityCrewManageExit(destination:"tab:\(route)");return}
        if ["C05","C13"].contains(ui.screen){requestCommunityComposerExit(destination:"tab:\(route)");return}
        ui.path=[]
        if ["C02","C08","C15"].contains(route),ui.rootIndex != 3{ui.forward=3>ui.rootIndex;ui.previousRootIndex=ui.rootIndex;ui.rootIndex=3}
        go(route)
    }
    func clearCommunityDiscardDestinations(){communityProfileExitDestination=nil;communityCrewExitDestination=nil;communityCrewManageExitDestination=nil;communityComposerExitDestination=nil;communityDiscardContext=nil}
    func communityComposerSnapshot(for screen:String)->WCommunityComposerSnapshot {
        if screen=="C13"{return WCommunityComposerSnapshot(screen:screen,board:"",crewID:nil,postID:nil,title:ui.communityCourseTitle,body:ui.communityCourseIntroduction,recordID:ui.communityCourseRecordID,hideEnds:ui.communityCourseHideEnds)}
        return WCommunityComposerSnapshot(screen:"C05",board:ui.communityDraftBoard,crewID:ui.communityDraftCrewID,postID:ui.communityDraftPostID,title:ui.communityDraftTitle,body:ui.communityDraftBody,recordID:"",hideEnds:false,attachmentIDs:ui.communityDraftAttachments.map(\.id))
    }
    func captureCommunityComposerBaseline(for screen:String){
        guard ["C05","C13"].contains(screen),communityComposerOriginal?.screen != screen else{return}
        communityComposerOriginal=communityComposerSnapshot(for:screen)
    }
    func communityComposerHasChanges()->Bool {
        guard ["C05","C13"].contains(ui.screen) else{return false}
        captureCommunityComposerBaseline(for:ui.screen)
        return communityComposerOriginal != communityComposerSnapshot(for:ui.screen)
    }
    func requestCommunityComposerExit(destination:String){
        guard !ui.communityRemotePublishBusy else{ui.communityError="게시글과 사진을 저장하고 있어요. 완료될 때까지 기다려 주세요.";return}
        guard ["C05","C13"].contains(ui.screen) else{completeCommunityComposerExit(destination);return}
        guard communityComposerHasChanges() else{resetCommunityComposerDraft();communityComposerOriginal=nil;completeCommunityComposerExit(destination);return}
        communityComposerExitDestination=destination;communityDiscardContext=ui.screen=="C13" ? .courseComposer:.postComposer;showingCommunityDiscardConfirmation=true
    }
    func resetCommunityComposerDraft(){
        ui.communityMediaImportCoordinator.invalidate();ui.communityMediaImporting=false;ui.communityDraftSessionID=UUID().uuidString
        ui.communityAttachmentStore.discardDraft(ui.communityDraftAttachments);ui.communityDraftAttachments=[]
        ui.communityDraftTitle="";ui.communityDraftBody="";ui.communityError="";ui.communityDraftCrewID=nil;ui.communityDraftPostID=nil
        ui.communityRemoteDraftPostID=nil;ui.communityRemoteDraftAttachmentVersion=nil;ui.communityRemoteDraftAssetIDs=[:]
        ui.communityRemoteDraftCreateResultUnknown=false;ui.communityRemotePublishBusy=false
        ui.communityRemotePublishNeedsRetry=false;ui.communityRemotePublishStatus=""
        ui.communityCourseDraft=false;ui.communityCourseError="";ui.communityCourseTitle="";ui.communityCourseIntroduction="";ui.communityCourseRecordID="";ui.communityCourseHideEnds=true
    }
    func discardCommunityComposerAndExit(){
        resetCommunityComposerDraft();communityComposerOriginal=nil
        let destination=communityComposerExitDestination;communityComposerExitDestination=nil
        if let destination{Task{@MainActor in await Task.yield();completeCommunityComposerExit(destination)}}
    }
    func completeCommunityComposerExit(_ destination:String){
        if destination=="back"{performBack();return}
        if destination.hasPrefix("tab:"){ui.path=[];performNavigation(String(destination.dropFirst(4)));return}
        if destination.hasPrefix("route:"){performNavigation(String(destination.dropFirst(6)))}
    }
    func requestCommunityProfileExit(destination:String){
        guard ui.communityProfileEditing else{completeCommunityProfileExit(destination);return}
        guard communityProfileDraftHasChanges() else{ui.communityProfileEditing=false;ui.error="";completeCommunityProfileExit(destination);return}
        communityProfileExitDestination=destination;communityDiscardContext = .profile;showingCommunityDiscardConfirmation=true
    }
    func discardCommunityProfileDraftAndExit(){
        ui.nickname=ui.profile.nickname;ui.introduction=ui.profile.introduction;ui.region=ui.profile.region;ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo);ui.error="";ui.communityProfileEditing=false
        let destination=communityProfileExitDestination;communityProfileExitDestination=nil
        if let destination{completeCommunityProfileExit(destination)}
    }
    func completeCommunityProfileExit(_ destination:String){
        if destination=="stay"{return}
        if destination=="back"{performBack();return}
        if destination.hasPrefix("tab:"){selectRootTab(String(destination.dropFirst(4)));return}
        if destination.hasPrefix("route:"){performNavigation(String(destination.dropFirst(6)))}
    }
    func communityCrewDraftHasChanges()->Bool {
        WCommunityCrewPolicy.draftHasChanges(communityCrewDraftOriginal,name:ui.communityCrewDraftName,introduction:ui.communityCrewDraftIntroduction,region:ui.communityCrewDraftRegion,minimumRank:ui.communityCrewDraftRank,photoData:ui.communityCrewDraftPhoto)
    }
    func requestCommunityCrewExit(destination:String){
        guard ui.communityCrewDraftID != nil else{completeCommunityCrewExit(destination);return}
        guard communityCrewDraftHasChanges() else{communityCrewDraftOriginal=nil;ui.communityCrewDraftID=nil;completeCommunityCrewExit(destination);return}
        communityCrewExitDestination=destination;communityDiscardContext = .crew;showingCommunityDiscardConfirmation=true
    }
    func discardCommunityCrewDraftAndExit(){
        if let original=communityCrewDraftOriginal{ui.communityCrewDraftName=original.name;ui.communityCrewDraftIntroduction=original.introduction;ui.communityCrewDraftRegion=original.region;ui.communityCrewDraftRank=original.minimumRank;ui.communityCrewDraftPhoto=original.photoData}
        ui.communityCrewDraftError="";ui.communityCrewNameCheck="";ui.communityCrewDraftID=nil;communityCrewDraftOriginal=nil
        let destination=communityCrewExitDestination;communityCrewExitDestination=nil
        if let destination{Task{@MainActor in await Task.yield();completeCommunityCrewExit(destination)}}
    }
    func completeCommunityCrewExit(_ destination:String){
        if destination=="stay"{return}
        if destination=="back"{performBack();return}
        if destination.hasPrefix("tab:"){ui.path=[];performNavigation(String(destination.dropFirst(4)));return}
        if destination.hasPrefix("route:"){performNavigation(String(destination.dropFirst(6)))}
    }
    func requestCommunityCrewManageExit(destination:String){
        guard let draft=ui.communityCrewManageDraft else{completeCommunityCrewManageExit(destination);return}
        guard draft.hasChanges else{ui.communityCrewManageDraft=nil;ui.communityCrewManageError="";completeCommunityCrewManageExit(destination);return}
        communityCrewManageExitDestination=destination;communityDiscardContext = .crewManage;showingCommunityDiscardConfirmation=true
    }
    func discardCommunityCrewManageDraftAndExit(){
        ui.communityCrewManageDraft=nil;ui.communityCrewManageError=""
        let destination=communityCrewManageExitDestination;communityCrewManageExitDestination=nil
        if let destination{Task{@MainActor in await Task.yield();completeCommunityCrewManageExit(destination)}}
    }
    func completeCommunityCrewManageExit(_ destination:String){
        if destination=="stay"{return}
        if destination=="back"{performBack();return}
        if destination.hasPrefix("tab:"){ui.path=[];performNavigation(String(destination.dropFirst(4)));return}
        if destination.hasPrefix("route:"){performNavigation(String(destination.dropFirst(6)))}
    }
    func prepare(_ id:String){
        if id=="H03"{ui.goal=store.goal}
        if id=="H04"{
            weeklyGoalDraftDirty=false
            weeklyTimeDraftInvalid=false
            if remoteReads.hasRunningProgressDependency {
                weeklyGoalDraftScopeID=ui.remoteAccountScopeID
                if case .loaded(let status)=remoteReads.weeklyGoalState,remoteReads.accountScopeID==ui.remoteAccountScopeID {
                    applyWeeklyGoalDraft(status)
                } else {
                    weeklyGoalDraftVersion=nil
                    ui.weekly=emptyWeeklyGoalDraft()
                }
            } else {
                weeklyGoalDraftVersion=nil
                weeklyGoalDraftScopeID=nil
                ui.weekly=store.weekly
            }
        }
        if ["Q01","Q02","Q03"].contains(id),!current.isValid,let valid=store.records.first(where:{$0.isValid}){ui.selected=valid.id}
        if id=="M02"{
            remoteReads.clearMemberProfileWriteFailure()
            memberProfileDraftBaseline=nil;memberProfileDraftScopeID=ui.remoteAccountScopeID;ui.error=""
            ui.nickname=ui.profile.nickname;ui.introduction=ui.profile.introduction;ui.region=ui.profile.region;ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo)
            if remoteReads.hasMemberProfileDependency,
               remoteReads.accountScopeID==ui.remoteAccountScopeID,
               case .loaded(let profile)=remoteReads.memberProfileState {beginMemberProfileDraft(profile,for:"M02")}
        }
        if id=="T02"{
            remoteReads.clearMemberProfileWriteFailure()
            memberProfileDraftBaseline=nil;memberProfileDraftScopeID=ui.remoteAccountScopeID;ui.error=""
            ui.weight=ui.profile.weight
            if remoteReads.hasMemberProfileDependency,
               remoteReads.accountScopeID==ui.remoteAccountScopeID,
               case .loaded(let profile)=remoteReads.memberProfileState {beginMemberProfileDraft(profile,for:"T02")}
        }
        if id=="L06"{ui.title=current.title;ui.memo=current.memo}
        if id=="C12",ui.communitySelectedCourse==nil{ui.communitySelectedCourse=WCommunityCourseFixtures.sample}
        if id=="C13"{ui.communityCourseDraftOwnerID=ui.communityViewerMemberID}
    }
    func applyWeeklyGoalDraft(_ status:BackendWeeklyGoalStatus){
        weeklyGoalDraftVersion=status.version
        weeklyGoalDraftScopeID=ui.remoteAccountScopeID
        var draft=WeeklyGoal()
        if let meters=status.distance.goal{draft.distanceEnabled=true;draft.kilometers=Double(meters)/1_000}
        else{draft.distanceEnabled=false}
        if let seconds=status.time.goal{draft.timeEnabled=true;draft.minutes=Int(seconds/60)}
        else{draft.timeEnabled=false}
        ui.weekly=draft
        weeklyTimeDraftInvalid=false
        weeklyGoalDraftDirty=false
    }
    func emptyWeeklyGoalDraft()->WeeklyGoal{
        var draft=WeeklyGoal()
        draft.distanceEnabled=false
        draft.timeEnabled=false
        return draft
    }
    var nav:some View {
        let tabsEnabled=isRoot || ui.screen=="C20"
        return HStack(spacing:0){
            ForEach(WRootTab.allCases,id:\.rawValue){tab in
                let index=tab.rawValue
                let selected=isRoot ? ui.rootIndex==index:ui.screen=="C20" && tab == .community
                Button{selectRootTab(tab.route)}label:{
                    VStack(spacing:3){
                        ZStack{
                            Color.clear.frame(height:3)
                            if selected || ui.screen==tab.route || (tab == .run && ["H02","H05"].contains(ui.screen)){
                                Capsule().fill(W.lime).frame(width:20,height:3).matchedGeometryEffect(id:"nav",in:indicator)
                            }
                        }
                        ZStack{
                            if tab == .home { BrandMark(size:WRootTab.homeMarkSize).accessibilityIdentifier("homeTabBrandMark") }
                            else if tab == .points { Image("PrismPoint").resizable().renderingMode(.original).scaledToFit().frame(width:24,height:24).accessibilityHidden(true) }
                            else if let asset=tab.assetName { AssetIcon(name:asset,size:24) }
                        }.frame(width:WRootTab.homeMarkSize,height:WRootTab.homeMarkSize)
                        if let caption=tab.caption {
                            Text(caption).font(W.font(11,.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(selected ? W.ink:W.muted)
                                .accessibilityIdentifier("tab-caption-\(index)")
                        } else {
                            Text("홈").font(W.font(11,.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                .hidden().accessibilityHidden(true)
                        }
                    }
                    .padding(.top,3)
                    .frame(maxWidth:.infinity,minHeight:64,maxHeight:64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(index)")
                .accessibilityAddTraits(selected ? .isSelected:[])
            }
        }
        .padding(.horizontal,8).background(W.paper).overlay(alignment:.top){W.line.frame(height:1)}
        // The run map takes over the full viewport. Keep the hidden tab bar out
        // of VoiceOver and hit testing while a run is active; otherwise its
        // invisible bottom hit region can cover the compact run controls.
        .accessibilityHidden(!tabsEnabled || splash)
        .allowsHitTesting(tabsEnabled && !splash)
    }
    var communityNav:some View {
        HStack(spacing:0){
            ForEach(WCommunityBottomTab.allCases,id:\.rawValue){tab in
                let selected=tab == .profile ? ui.screen=="C08" && ui.communitySelectedUserID==ui.communityViewerMemberID:tab == .boards ? ["C02","C03"].contains(ui.screen):ui.screen==tab.route
                Button{selectCommunityTab(tab.route)}label:{
                    VStack(spacing:3){
                        ZStack{
                            Color.clear.frame(height:3)
                            if selected{Capsule().fill(W.lime).frame(width:20,height:3)}
                        }
                        ZStack{
                            if tab == .home {BrandMark(size:WRootTab.homeMarkSize).accessibilityIdentifier("communityHomeTabBrandMark")}
                            else if let symbol=tab.systemImage {Image(systemName:symbol).font(.system(size:22,weight:.regular)).foregroundStyle(selected ? W.ink:W.muted)}
                        }.frame(width:WRootTab.homeMarkSize,height:WRootTab.homeMarkSize)
                        Text(tab.title).font(W.font(11,.medium)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(selected ? W.ink:W.muted)
                    }
                    .padding(.top,3)
                    .frame(maxWidth:.infinity,minHeight:64,maxHeight:64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityID)
                .accessibilityAddTraits(selected ? .isSelected:[])
            }
        }
        .padding(.horizontal,8)
        .background(W.paper)
        .overlay(alignment:.top){W.line.frame(height:1)}
    }
    func selectCommunityTab(_ route:String){
        if route=="C08" {
            if ui.screen=="C08" && ui.communitySelectedUserID==ui.communityViewerMemberID{return}
            ui.communitySelectedUserID=ui.communityViewerMemberID
            ui.communityCardOriginAnonymous=false
        }
        if route=="H00"{selectRootTab(route);return}
        if route=="C15"{ui.communityCrewTab="my"}
        selectRootTab(route)
    }
    func resetCommunityScrollPresentation(){
        lastCommunityScrollOffset=nil
        communityBottomBarVisible=true
        communityScrollToTopVisible=false
        communityBoardScrollOffset=0
    }
    func handleCommunityScrollOffset(_ offset:CGFloat){
        let previous=lastCommunityScrollOffset
        lastCommunityScrollOffset=offset
        let shouldShowTop=ui.screen=="C01" ? offset < -120:ui.screen=="C03" && offset < -8
        if shouldShowTop != communityScrollToTopVisible{communityScrollToTopVisible=shouldShowTop}
        if shouldShowTop && communityBottomBarVisible{withAnimation(.easeInOut(duration:0.24)){communityBottomBarVisible=false}}
        guard let previous else{
            if offset < -8 && communityBottomBarVisible{withAnimation(.easeInOut(duration:0.24)){communityBottomBarVisible=false}}
            return
        }
        if ui.screen=="C08" && ui.communityProfileEditing {
            if !communityBottomBarVisible{withAnimation(.easeInOut(duration:0.24)){communityBottomBarVisible=true}}
            return
        }
        let delta=offset-previous
        if offset > -8 || delta > 1.5 {
            if !communityBottomBarVisible{withAnimation(.easeInOut(duration:0.24)){communityBottomBarVisible=true}}
        }else if delta < -1.5,communityBottomBarVisible{
            withAnimation(.easeInOut(duration:0.24)){communityBottomBarVisible=false}
        }
    }
    func button(_ text:String,_ target:String,kind:Int=0)->some View {Button(text){go(target)}.buttonStyle(WButtonStyle(kind:kind))}
    func rootHeader(_ title:String,run:Bool=false,showMark:Bool=true,settingsRoute:String?=nil,notificationRoute:String?=nil,notificationIdentifier:String?=nil,centerRootMark:Bool=false)->some View {let communityNotifications=notificationRoute != nil;let unread=communityNotifications ? ui.hasUnreadCommunityNotifications:ui.hasUnreadNotifications;let destination=settingsRoute ?? "T01";let notificationID=notificationIdentifier ?? (run ? "openRecords":"notificationBell");return WHeader(title:title,root:true,showRootMark:centerRootMark ? false:showMark,centerRootMark:centerRootMark,trailing:AnyView(HStack(spacing:0){Button{go(run ? "L01":notificationRoute ?? "N01")}label:{AssetIcon(name:run ? "records":"bell",size:20).frame(width:44,height:44).contentShape(Rectangle()).overlay(alignment:.topTrailing){if !run && unread{Circle().fill(communityNotifications ? Color.wire(0xFF5A5F,0xFF5A5F):W.lime).frame(width:5,height:5).padding(.top,8).padding(.trailing,10)}}}.accessibilityLabel(run ? "기록 보기":communityNotifications ? "커뮤니티 알림":"알림").accessibilityIdentifier(notificationID).accessibilityValue(run ? "":"\(unread ? "읽지 않음":"읽음")");if title=="내 정보" || settingsRoute != nil{Button{go(destination)}label:{AssetIcon(name:"settings",size:20).frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel("설정").accessibilityIdentifier(settingsRoute=="C28" ? "communityOwnProfileSettings":"profileSettings")}}))}
    @ViewBuilder var screenView:some View {
        switch ui.screen {
        case "E01":BrandMark(size:84).frame(maxWidth:.infinity,maxHeight:.infinity)
        case "E02":WSplash().frame(maxWidth:.infinity,maxHeight:.infinity)
        case "POINTS","B01":points
        case "SHOP","B05":shop
        case "B02","B03","B04","B06","B07","B08","B09","B10":pointDetailRoute
        case "H00":home
        case "H01","H02","H05":ready
        case "H03":sessionGoal
        case "H04":weeklyGoal
        case "H07","H08","H09":statistics
        case "M01":profile
        case "M02":profileEdit
        case "N01":notifications
        case "R01","R02","R03","R04","R05","R07","R08","R10":runPanel
        case "R06":runDetails
        case "L01","L02","L03":records
        case "L04":recordDetail
        case "L05":splits
        case "L06":recordEdit
        case "Q01":ShareImageEditor(record:current,workspace:shareWorkspace,back:{back()},openOutput:{go("Q02")})
        case "Q02":ShareOutputView(record:current,workspace:shareWorkspace,back:{back()},gallery:{go("Q03")},attachToCommunity:{beginCommunityComposeWithShareImage($0)})
        case "Q03":ShareGallery(record:current,workspace:shareWorkspace,back:{back()},create:{go("Q01")},open:{id in shareWorkspace.selectedOutputID=id;go("Q02")})
        case "S01","S02","S03","S04","S05":completion
        case "T01":settings
        case "T18":theme
        case "T02","A03":weightProfile
        case "T05":providers
        case "T11":deleteAccount
        case "A01","A07","A10","A12","A16","A17":authForm
        case "A04":loginFailure
        case "A02":consents
        case "A06":consentReview
        case "A19","A20","A21","A22","A23":verification
        case "A24","A25","A26","A27","A28":passwordResetVerification
        case "C01":community
        case "C06":communityLikedPosts
        case "C10":communityVerificationForm
        case "C11":communityVerificationStatus
        case "C12":communityCourseDetail
        case "C13":communityCourseCompose
        case "C14":communityGhostRun
        case "C15":communityCrewOverview
        case "C16":communityCrewDetail
        case "C17":communityCrewJoinForm
        case "C18":communityCrewApplicationStatus
        case "C19":communityCrewBoard
        case "C20":communityCrewEditor
        case "C21":communityCrewManagement
        case "C22":communityCrewApplicationReview
        case "C36":communityCrewGuidanceSettings
        case "C37":communityCrewBoardManagement
        case "C38":communityCrewBoardEditor
        case "C39":communityCrewAnnouncementEditor
        case "C40":communityCrewPendingApplications
        case "C34":communityCrewMemberList
        case "C35":communityCrewMemberDetail
        case "C07":communityCardPreview
        case "C08":communityRunnerProfile
        case "C30":communityConnections
        case "C31":communityPhotoViewer
        case "C32":communityCrewInformation
        case "C33":communityCrewApplicationList
        case "C23":communityReport
        case "C24":communityNotifications
        case "C25":communityReportReceipt
        case "C28":communitySettings
        case "C29":communitySearch
        case "C41":communityHotPosts
        case "C42":communityBlockedUsers
        case "C43":communityActivity
        case "C02":communityBoards
        case "C03":communityBoardPosts
        case "C27":communityAllBoards
        case "C04":communityPostDetail
        case "C05":communityCompose
        case "C09":communityPreview
        case "C04-IMAGE":communityImageViewer
        default:informationPage
        }
    }
}

struct WCommunityVerificationStatusPage:View {
    @Bindable var state:WireState
    let reviewTools:Bool
    let back:()->Void
    let go:(String)->Void
    var body:some View {
        let status=state.communityVerification.status
        let heading=headingText(status)
        let message=messageText(status)
        return WPage(title:"인증 신청",back:back){
            VStack(alignment:.leading,spacing:14){
                Text(heading).font(W.font(21,.semibold)).accessibilityIdentifier("communityVerificationHeading")
                Text(message).font(W.font(14)).foregroundStyle(W.muted).accessibilityIdentifier("communityVerificationMessage")
                WNotice(text:"인증 배지는 코스의 안전이나 운동 능력을 보증하지 않아요.")
                if reviewTools {VStack(alignment:.leading,spacing:10){
                    Text("플랫폼 운영자 인증 결과 예시").font(W.font(14,.medium))
                    Text("아래 도구는 계정 인증 담당자의 응답을 흉내냅니다. 일반 앱 화면에는 승인 버튼이 없습니다.").font(W.font(12)).foregroundStyle(W.muted)
                    Button("인증 승인 예시"){state.reviewCommunityVerification(as:.approved)}.buttonStyle(WButtonStyle()).disabled(status != .pending).accessibilityIdentifier("communityVerificationApproveExample")
                    Button("인증 반려 예시"){state.reviewCommunityVerification(as:.rejected)}.buttonStyle(WButtonStyle(kind:1)).disabled(status != .pending).accessibilityIdentifier("communityVerificationRejectExample")
                }.padding(.top,12)}
            }
        }actions:{
            Button(continueText(status)){if status == .approved{go("C13")}else if status != .pending{go("C10")}}.buttonStyle(WButtonStyle()).disabled(status == .pending).accessibilityIdentifier("communityVerificationContinue")
        }
    }
    private func headingText(_ status:WCommunityVerificationStatus)->String {switch status{case .none:return "계정 인증을 신청해 보세요";case .pending:return "인증을 검토하고 있어요";case .approved:return "계정 인증이 완료됐어요";case .rejected:return "신청 내용을 다시 확인해 주세요"}}
    private func messageText(_ status:WCommunityVerificationStatus)->String {switch status{case .none:return "운영자가 신청 내용을 검토해요.";case .pending:return "결과가 나오면 알림으로 알려드려요.";case .approved:return "이제 코스를 공유할 수 있어요.";case .rejected:return state.communityVerification.reason}}
    private func continueText(_ status:WCommunityVerificationStatus)->String {switch status{case .none:return "신청하기";case .pending:return "검토 중";case .approved:return "코스 공유하기";case .rejected:return "다시 신청"}}
}

struct WGoalWheel:View {
    var values:[Int]
    @Binding var selection:Int
    var time=false
    // Physical scroll position is independent of the selected value. Rows keep their value IDs.
    @State private var position:CGFloat=0
    @State private var dragY:CGFloat?
    @State private var dragTime=Date()
    @State private var velocity:CGFloat=0
    @State private var motion:Task<Void,Never>?
    func move(_ next:CGFloat){
        position=min(CGFloat(values.count-1)*60,max(0,next))
        selection=values[Int((position/60).rounded())]
    }
    func stop(){motion?.cancel();motion=nil}
    func settle(coast:CGFloat=0){
        stop()
        if reduced{move((position/60).rounded()*60);return}
        motion=Task{@MainActor in
            if abs(coast)>=0.025{
                let start=position,began=Date()
                while !Task.isCancelled{
                    let elapsed=min(160,Date().timeIntervalSince(began)*1000)
                    let distance=min(31,abs(coast)*85*(1-exp(-elapsed/85)))
                    move(start+(coast<0 ? -distance:distance))
                    if elapsed>=160 || position==0 || position==CGFloat(values.count-1)*60{break}
                    do{try await Task.sleep(for:.milliseconds(8))}catch{return}
                }
            }
            guard !Task.isCancelled else{return}
            let start=position,target=(position/60).rounded()*60,began=Date()
            while !Task.isCancelled{
                let t=min(1,Date().timeIntervalSince(began)/0.096)
                move(start+(target-start)*(1-pow(1-t,3)))
                if t>=1{break}
                do{try await Task.sleep(for:.milliseconds(8))}catch{return}
            }
            if !Task.isCancelled{motion=nil}
        }
    }
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    var index:Int{values.firstIndex(of:selection) ?? 0}
    func label(_ n:Int)->String {time ? RunGoal.duration(n):MovNumber.display(Double(n)/2)+" km"}
    @ViewBuilder func number(_ n:Int)->some View {
        if time{HStack(alignment:.firstTextBaseline,spacing:9){if n>=60{HStack(alignment:.firstTextBaseline,spacing:5){Text("\(n/60)");Text("시간").font(W.font(16,.medium))}};if n%60 != 0{HStack(alignment:.firstTextBaseline,spacing:5){Text("\(n%60)");Text("분").font(W.font(16,.medium))}}}}
        else{Text(MovNumber.display(Double(n)/2))}
    }
    private var wheelRows:some View {
GeometryReader{geo in
                        let center=Int((position/60).rounded())
                        ZStack{ForEach(max(0,center-2)...min(values.count-1,center+2),id:\.self){candidate in
                            number(values[candidate])
                                .font(W.font(32,.semibold)).kerning(-0.8).monospacedDigit().foregroundStyle(W.ink)
                                .scaleEffect(candidate==center ? 1:0.84).opacity(candidate==center ? 1:0.52)
                                .frame(width:geo.size.width,height:60).contentShape(Rectangle())
                                .position(x:geo.size.width/2,y:72+CGFloat(candidate)*60-position)
                                .onTapGesture{stop();move(CGFloat(candidate)*60)}
                        }}
                    }.frame(width:time ? 260:128,height:144)
    }
    private var wheelDrag:some Gesture {
DragGesture(minimumDistance:0).onChanged{v in
                if dragY == nil{stop();dragY=0;velocity=0;dragTime=v.time}
                let delta=(v.translation.height-(dragY ?? 0))*0.55
                let before=position
                move(position-delta)
                let sample=(position-before)/max(8,v.time.timeIntervalSince(dragTime)*1000)
                velocity=min(0.4,max(-0.4,sample.sign != velocity.sign ? sample:velocity*0.25+sample*0.75))
                dragY=v.translation.height;dragTime=v.time
            }.onEnded{v in
                let travelled=abs(v.translation.height)
                let coast=v.time.timeIntervalSince(dragTime)>0.08 ? 0:velocity
                dragY=nil
                if travelled<5{stop();move((position/60+((v.location.y-72)/60)).rounded()*60)}
                else{settle(coast:coast)}
            }
    }
    var body:some View {
        VStack(spacing:10){
            ZStack{
                RoundedRectangle(cornerRadius:18).fill(W.paper)
                RoundedRectangle(cornerRadius:12).fill(W.soft).frame(height:60).padding(.horizontal,10)
                HStack(spacing:0){
                    wheelRows
                    if !time{Text("km").font(W.font(18,.medium)).frame(width:40,alignment:.leading).padding(.trailing,26)}
                }.mask(LinearGradient(stops:[.init(color:.clear,location:0),.init(color:.black,location:0.24),.init(color:.black,location:0.76),.init(color:.clear,location:1)],startPoint:.top,endPoint:.bottom))
            }.frame(height:144).clipShape(RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(W.line))
            .contentShape(Rectangle()).highPriorityGesture(wheelDrag)
            .onAppear{position=CGFloat(index)*60}
            .onChange(of:values){_,_ in stop();dragY=nil;position=CGFloat(index)*60}
            .onChange(of:selection){_,_ in if dragY == nil && motion == nil{position=CGFloat(index)*60}}
            .onDisappear{stop()}
            .transaction{$0.animation=nil}
            .modifier(WGoalWheelAccessibility(identifier:time ? "timeGoalPicker":"distanceGoalPicker",label:time ? "시간 목표":"거리 목표",value:label(selection)))
            .accessibilityAdjustableAction{direction in stop();move(CGFloat(min(values.count-1,max(0,index+(direction == .increment ? 1:-1))))*60)}
            Text("위아래로 스크롤해 목표를 맞춰 주세요").font(W.font(12)).foregroundStyle(W.muted).frame(height:18)
        }
    }
}

private struct WGoalWheelAccessibility:ViewModifier {
    let identifier:String
    let label:String
    let value:String
    func body(content:Content)->some View {
        content.accessibilityElement(children:.ignore)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint("위아래로 스크롤해 목표를 맞춰 주세요")
    }
}

struct WSplash:View {
    @State private var began=Date()
    @State private var settled=false
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    var body:some View {TimelineView(.animation(minimumInterval:1.0/60,paused:reduced || settled)){context in
        let t=WOriginalMotion.time(settled ? 1.04:context.date.timeIntervalSince(began))
        let symbol=reduced ? 1:WOriginalMotion.settle(min(1,t/0.4))
        let word=reduced ? 1:WOriginalMotion.interpolate(WOriginalMotion.settle(min(1,t/0.88)),[(0,0),(0.4,0),(1,1)])
        let tagline=reduced ? 1:WOriginalMotion.interpolate(WOriginalMotion.settle(min(1,t/1.04)),[(0,0),(0.5,0),(1,1)])
        VStack(spacing:0){BrandMark(size:84).scaleEffect(0.96+0.04*symbol).opacity(0.75+0.25*symbol)
            Text("모브").font(.custom("Cafe24Ssurround",size:28)).kerning(-1.4).frame(height:36.4).padding(.top,22).opacity(word).offset(y:7*(1-word)).accessibilityIdentifier("splashWordmark")
            Text("오늘의 달리기를 나의 기록으로").font(W.font(14)).kerning(-0.21).foregroundStyle(W.muted).frame(height:21).padding(.top,9).opacity(tagline).offset(y:6*(1-tagline)).accessibilityIdentifier("splashTagline")
        }.offset(y:-26).accessibilityElement(children:.contain).accessibilityIdentifier("screen-E02")
    }.task{began=Date();settled=false;do{try await Task.sleep(for:.milliseconds(1040));settled=true}catch{}}}
}

struct WCheck:Shape {func path(in rect:CGRect)->Path {var p=Path();let x=rect.width/24,y=rect.height/24;p.move(to:CGPoint(x:5.8*x,y:12.3*y));p.addLine(to:CGPoint(x:8.8*x,y:15.4*y));p.addQuadCurve(to:CGPoint(x:10.2*x,y:15.3*y),control:CGPoint(x:9.5*x,y:16.1*y));p.addLine(to:CGPoint(x:18.2*x,y:7.5*y));return p}}
struct WMail:Shape {func path(in rect:CGRect)->Path {var p=Path();let x=rect.width/24,y=rect.height/24;p.addRoundedRect(in:CGRect(x:3*x,y:5*y,width:18*x,height:14*y),cornerSize:CGSize(width:3*x,height:3*y));p.move(to:CGPoint(x:4*x,y:7*y));p.addLine(to:CGPoint(x:12*x,y:13*y));p.addLine(to:CGPoint(x:20*x,y:7*y));return p}}

// HTML summary control: text followed by a small chevron, no system disclosure chrome.
struct WDisclosure<Content:View>:View {
    var title:String
    @Binding var expanded:Bool
    var triangle=false
    @ViewBuilder var content:Content
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    var body:some View {VStack(alignment:.leading,spacing:0){
        Button{if triangle{expanded.toggle()}else{withAnimation(reduced ? nil:.easeOut(duration:0.16)){expanded.toggle()}}}label:{HStack(spacing:triangle ? 4:8){
            if triangle{WTriangle().fill(Color.wire(0x535353,0xD0D0D0)).frame(width:7,height:8).rotationEffect(.degrees(expanded ? 90:0))}
            Text(title).font(W.font(triangle ? 12:13,.medium))
            if !triangle{WChevron().stroke(Color.wire(0x535353,0xD0D0D0),style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round)).frame(width:17,height:17).rotationEffect(.degrees(expanded ? 180:0))};Spacer()
        }.foregroundStyle(Color.wire(0x535353,0xD0D0D0)).frame(minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityValue(expanded ? "펼침":"접힘")
        if expanded{content}
    }}
}
struct WTriangle:Shape{func path(in r:CGRect)->Path{Path{p in p.move(to:.zero);p.addLine(to:CGPoint(x:r.width,y:r.height/2));p.addLine(to:CGPoint(x:0,y:r.height));p.closeSubpath()}}}
struct WChevron:Shape{func path(in r:CGRect)->Path{Path{p in p.move(to:CGPoint(x:r.width*0.3,y:r.height*0.4));p.addLine(to:CGPoint(x:r.width*0.5,y:r.height*0.6));p.addLine(to:CGPoint(x:r.width*0.7,y:r.height*0.4))}}}

// Original v32 inline SVG paths, rendered natively at their CSS dimensions.
struct WBackIcon:Shape {
    func path(in rect:CGRect)->Path {var p=Path();p.move(to:CGPoint(x:15.5,y:4.5));p.addLine(to:CGPoint(x:8,y:12));p.addLine(to:CGPoint(x:15.5,y:19.5));return p.applying(CGAffineTransform(scaleX:rect.width/24,y:rect.height/24))}
}
struct WEyeIcon:Shape {
    var revealed=false
    func path(in rect:CGRect)->Path {
        var p=Path()
        if revealed {
            p.move(to:CGPoint(x:3,y:3));p.addLine(to:CGPoint(x:21,y:21))
            p.move(to:CGPoint(x:9.9,y:9.9));p.addArc(center:CGPoint(x:12,y:12),radius:3,startAngle:.degrees(225),endAngle:.degrees(45),clockwise:true)
            p.move(to:CGPoint(x:6.4,y:6.4));p.addCurve(to:CGPoint(x:2,y:12),control1:CGPoint(x:4.5,y:7.7),control2:CGPoint(x:3,y:9.6));p.addCurve(to:CGPoint(x:12,y:19),control1:CGPoint(x:4.1,y:17),control2:CGPoint(x:7.4,y:19));p.addCurve(to:CGPoint(x:17.2,y:17.7),control1:CGPoint(x:14,y:19),control2:CGPoint(x:15.7,y:18.6))
            p.move(to:CGPoint(x:10,y:5.2));p.addCurve(to:CGPoint(x:12,y:5),control1:CGPoint(x:10.7,y:5.1),control2:CGPoint(x:11.3,y:5));p.addCurve(to:CGPoint(x:22,y:12),control1:CGPoint(x:16.6,y:5),control2:CGPoint(x:19.9,y:7));p.addQuadCurve(to:CGPoint(x:19.3,y:16.2),control:CGPoint(x:20.9,y:14.3))
        } else {
            p.move(to:CGPoint(x:2,y:12));p.addCurve(to:CGPoint(x:12,y:5),control1:CGPoint(x:4.1,y:7),control2:CGPoint(x:7.4,y:5));p.addCurve(to:CGPoint(x:22,y:12),control1:CGPoint(x:16.6,y:5),control2:CGPoint(x:19.9,y:7));p.addCurve(to:CGPoint(x:12,y:19),control1:CGPoint(x:19.9,y:17),control2:CGPoint(x:16.6,y:19));p.addCurve(to:CGPoint(x:2,y:12),control1:CGPoint(x:7.4,y:19),control2:CGPoint(x:4.1,y:17));p.closeSubpath();p.addEllipse(in:CGRect(x:9,y:9,width:6,height:6))
        }
        return p.applying(CGAffineTransform(scaleX:rect.width/24,y:rect.height/24))
    }
}

// Exact source WAAPI/CSS timing. Timeline state is view-owned; removal cancels its task.
enum WOriginalMotion {
    static func time(_ elapsed:Double)->Double {
        let args=ProcessInfo.processInfo.arguments
        if args.contains("-wire-fixture"),let i=args.firstIndex(of:"-wire-motion-time"),args.indices.contains(i+1),let value=Double(args[i+1]){return max(0,value)}
        return max(0,elapsed)
    }
    static func curve(_ t:Double,_ x1:Double,_ y1:Double,_ x2:Double,_ y2:Double)->Double {
        let value=min(1,max(0,t));var lo=0.0,hi=1.0
        func bezier(_ u:Double,_ a:Double,_ b:Double)->Double{3*(1-u)*(1-u)*u*a+3*(1-u)*u*u*b+u*u*u}
        for _ in 0..<24 {let u=(lo+hi)/2;if bezier(u,x1,x2)<value{lo=u}else{hi=u}}
        return bezier((lo+hi)/2,y1,y2)
    }
    static func settle(_ t:Double)->Double{curve(t,0.2,0.8,0.2,1)}
    static func interpolate(_ t:Double,_ keys:[(Double,Double)],easeFrom:Double?=nil)->Double {
        if t<=keys[0].0{return keys[0].1}
        for i in 1..<keys.count where t<=keys[i].0 {
            let a=keys[i-1],b=keys[i];var fraction=(t-a.0)/(b.0-a.0)
            if let easeFrom,abs(a.0-easeFrom)<0.0001{fraction=curve(fraction,0.16,1,0.3,1)}
            return a.1+(b.1-a.1)*fraction
        }
        return keys.last!.1
    }
    static func successCircle(_ t:Double)->Double{interpolate(t,[(0,0.12),(0.27,0.12),(0.35,0.23),(0.64,1.07),(0.82,0.985),(1,1)],easeFrom:0.64)}
    static func gpsRing(_ elapsed:Double,outer:Bool)->(opacity:Double,scale:Double){
        let delay=outer ? 0.9:0.0
        if elapsed<delay{return (outer ? 0.2:0.45,1)}
        let phase=(elapsed-delay).truncatingRemainder(dividingBy:1.8)/1.8
        let eased=curve(phase,0.2,0.65,0.35,1)
        return (0.36*(1-eased),0.65+0.45*eased)
    }
}
struct WGPSSignal:View {
    var searching=false
    var weak=false
    var waiting=false
    @State private var began=Date()
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    var review:Bool{ProcessInfo.processInfo.arguments.contains("-wire-review-size")}
    var color:Color{(searching || waiting) ? Color(white:0.6):weak ? Color(red:244/255,green:189/255,blue:50/255):W.lime}
    var body:some View{TimelineView(.animation(minimumInterval:1.0/60,paused:reduced || !searching || review)){context in
        ZStack{RoundedRectangle(cornerRadius:12).fill(W.paper).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line,lineWidth:1))
            Circle().fill(color).frame(width:8,height:8)
            ForEach(0..<2){i in let value=searching && !reduced && !review ? WOriginalMotion.gpsRing(WOriginalMotion.time(context.date.timeIntervalSince(began)),outer:i==1):(opacity:i==1 ? 0.2:0.45,scale:1.0)
                Circle().stroke(color,lineWidth:1).frame(width:i==1 ? 20:14,height:i==1 ? 20:14).opacity(value.opacity).scaleEffect(value.scale)
            }
        }.frame(width:44,height:44).accessibilityValue(waiting ? "GPS 연결 전":searching ? "위치 확인 중":weak ? "신호 약함":"GPS 연결됨")
    }.onAppear{began=Date()}.onChange(of:searching){_,_ in began=Date()}}
}

// Clip horizontal transitions while allowing the active map through both safe areas.
private struct WScreenClip:Shape {
    var extendMap:Bool
    func path(in rect:CGRect)->Path{Path(CGRect(x:rect.minX,y:rect.minY-(extendMap ? 100:0),width:rect.width,height:rect.height+(extendMap ? 200:0)))}
}

// Review controls never appear in a normal launch. Tests can isolate storage while exercising user-facing UI.
enum WReviewMode {
    static var tools:Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-wire-fixture") && !ProcessInfo.processInfo.arguments.contains("-wire-user-flow")
        #else
        false
        #endif
    }
}

// Storefront outline matches the weight and 24pt grid of the existing navigation icons.
struct WShopIcon:Shape {
    func path(in r:CGRect)->Path {
        var p=Path()
        p.move(to:CGPoint(x:4,y:10));p.addLine(to:CGPoint(x:4,y:21));p.addLine(to:CGPoint(x:20,y:21));p.addLine(to:CGPoint(x:20,y:10))
        p.move(to:CGPoint(x:3,y:4));p.addLine(to:CGPoint(x:21,y:4));p.addLine(to:CGPoint(x:22,y:9))
        p.addQuadCurve(to:CGPoint(x:17,y:9),control:CGPoint(x:19.5,y:14));p.addQuadCurve(to:CGPoint(x:12,y:9),control:CGPoint(x:14.5,y:14));p.addQuadCurve(to:CGPoint(x:7,y:9),control:CGPoint(x:9.5,y:14));p.addQuadCurve(to:CGPoint(x:2,y:9),control:CGPoint(x:4.5,y:14));p.addLine(to:CGPoint(x:3,y:4))
        p.move(to:CGPoint(x:9,y:21));p.addLine(to:CGPoint(x:9,y:15));p.addLine(to:CGPoint(x:15,y:15));p.addLine(to:CGPoint(x:15,y:21))
        return p.applying(CGAffineTransform(scaleX:r.width/24,y:r.height/24))
    }
}

// A single coin with a narrow visible rim; no letter or decorative detail at tab size.
struct WPointsIcon:Shape {
    func path(in r:CGRect)->Path {
        var p=Path()
        p.addEllipse(in:CGRect(x:2.5,y:2.5,width:16,height:19))
        p.move(to:CGPoint(x:10.5,y:2.5))
        p.addCurve(to:CGPoint(x:21.5,y:12),control1:CGPoint(x:17,y:1.5),control2:CGPoint(x:21.5,y:5.5))
        p.addCurve(to:CGPoint(x:10.5,y:21.5),control1:CGPoint(x:21.5,y:18.5),control2:CGPoint(x:17,y:22.5))
        return p.applying(CGAffineTransform(scaleX:r.width/24,y:r.height/24))
    }
}
