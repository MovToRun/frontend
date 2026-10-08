import SwiftUI

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
    @ViewBuilder var content:Content
    @ViewBuilder var actions:Actions
    var body:some View {
        VStack(spacing:0){
            WHeader(title:title,back:back,mark:title=="시뮬레이션 완료")
            ScrollView { VStack(alignment:.leading,spacing:18){content}.frame(maxWidth:.infinity,alignment:.leading).padding(24) }.scrollDismissesKeyboard(.interactively).modifier(WAuthBodyMotion())
            if Actions.self != EmptyView.self { VStack(spacing:10){actions}.padding(.horizontal,24).padding(.top,16).padding(.bottom,24).overlay(alignment:.top){W.line.frame(height:1)} }
        }.background(W.paper)
    }
}
struct WHeader:View {
    var title:String
    var back:(()->Void)? = nil
    var root=false
    var showRootMark=true
    var mark=false
    var trailing:AnyView = AnyView(EmptyView())
    var body:some View {
        HStack {
            if let back { Button(action:back){WBackIcon().stroke(W.ink,style:StrokeStyle(lineWidth:1.2,lineCap:.round,lineJoin:.round)).frame(width:18,height:18).frame(width:44,height:44)}.accessibilityLabel("뒤로") }
            else if root ? showRootMark : mark {BrandMark(size:root ? 30:28).frame(width:root ? 30:28,height:44).accessibilityIdentifier(root ? "rootHeaderBrandMark":"completionBrandMark")}
            else {Color.clear.frame(width:44,height:44)}
            Spacer();trailing
        }.padding(.horizontal,root ? 16:10).frame(height:root ? 64:68)
            .overlay{Text(title).font(W.font(17,.medium)).lineLimit(2).minimumScaleFactor(0.65).frame(maxWidth:220).allowsHitTesting(false)}
            .background(W.paper).overlay(alignment:.bottom){if !(root && title=="내 정보"){W.line.frame(height:1)}}
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
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            (Text(label).font(W.font(labelSize,labelSize==13 ? .regular:.medium))+Text(secondaryLabel.isEmpty ? "":"  "+secondaryLabel).font(W.font(10)).foregroundColor(W.muted)).frame(height:labelSize==13 ? 19:21,alignment:.leading).padding(.bottom,8)
            if multiline{TextEditor(text:$text).font(W.font(textSize)).scrollContentBackground(.hidden).lineSpacing(textSize==16 ? 8:4.2).frame(height:multilineHeight-12).padding(.horizontal,9).padding(.vertical,6).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.controlBorder))}
            else{TextField(placeholder,text:$text,prompt:placeholderColor.map{Text(placeholder).foregroundColor($0)}).font(W.font(textSize)).padding(14).frame(minHeight:54).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.controlBorder))}
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
        guard record.kilometers>0 else{return saved ? record.pace:"—"}
        return record.pace.count==4 ? "0"+record.pace:record.pace
    }
    var metricDistance:Text {
        record.kilometers>0 || saved
            ? Text(record.kilometers,format:.number.precision(.fractionLength(2)))
            : Text("—")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            metricLabel("유효 거리")
            (metricDistance.font(W.font(52,.bold)).kerning(-2.34)+Text(" km").font(W.font(22,.semibold)).kerning(-0.44))
                .monospacedDigit().frame(height:57.2,alignment:.leading).padding(.top,5).padding(.bottom,22).accessibilityIdentifier("runDistanceMetric")
            HStack(alignment:.top,spacing:20){
                VStack(alignment:.leading,spacing:0){
                    metricLabel(saved && !record.isValid ? "기록 상태":saved ? "유효 러닝 시간":"러닝 시간")
                    Text(saved && !record.isValid ? "비유효 러닝":RunRecord.clock(clockOverride ?? record.seconds)).font(W.font(saved && !record.isValid ? 18:28,.semibold)).kerning(-0.98).monospacedDigit().frame(height:39.2,alignment:.leading)
                    if paused || reservePauseSpace{Text(paused ? "일시정지":" ").font(W.font(12)).foregroundStyle(W.muted).frame(height:19).padding(.top,3)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:0){
                    metricLabel("평균 페이스")
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
        ZStack(alignment:.topLeading){if failed && !mapRecovered{W.soft.overlay{VStack(spacing:14){WText(text:"지도를 불러오지 못했어요");Button("다시 시도"){mapRecovered=true}.font(W.font(13));WText(text:"GPS 수치와 기록 제어는 유지돼요",small:true)}.padding(20)}}else{if let backgroundTap{SampleMap(route:route,focusUser:focusUser,userCenterY:userCenterY,panOffset:displayedPanOffset).accessibilityIdentifier(focusUser ? "runningMap":"mapSurface").gesture(DragGesture(minimumDistance:0).updating($panDrag){v,state,_ in
                    if hypot(v.translation.width,v.translation.height)>=8{state=v.translation}
                }.onEnded{v in
                    if hypot(v.translation.width,v.translation.height)<8{backgroundTap()}
                    else{panOffset=CGSize(width:panOffset.width+v.translation.width,height:panOffset.height+v.translation.height)}
                })}else{SampleMap(route:route,focusUser:focusUser,userCenterY:userCenterY,panOffset:displayedPanOffset).accessibilityIdentifier(focusUser ? "runningMap":"mapSurface")}}
            if !controls && WReviewMode.tools{GeometryReader{g in if g.size.height>100{VStack(alignment:.leading){Text("가상 코스").font(W.font(11)).padding(.vertical,6).padding(.horizontal,9).background(W.paper.opacity(0.8),in:RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(W.line));Spacer();Text("실제 장소가 아닌 도식 지도").font(W.font(9)).padding(.vertical,4).padding(.horizontal,6).background(W.paper.opacity(0.8),in:RoundedRectangle(cornerRadius:3))}.foregroundStyle(W.muted).padding(.horizontal,18).padding(.vertical,16)}}}
            if controls {VStack(alignment:.leading,spacing:8){Button{info.toggle()}label:{WGPSSignal(searching:gpsSearching,weak:gpsWeak,waiting:gpsWaiting)}.accessibilityLabel("위치 상태 안내");if WReviewMode.tools && (!failed || mapRecovered){Text("실제 장소가 아닌 도식 지도").font(W.font(9)).padding(.horizontal,6).padding(.vertical,4).background(W.paper).padding(.leading,6)};if info{WNotice(text:"위치와 신호 상태를 확인해 주세요.").frame(maxWidth:280)}}.padding(.horizontal,12).padding(.top,controlsTopInset+10)}
        }.clipped().overlay(alignment:.bottomTrailing){if controls && centerControl{Button{withAnimation(.easeOut(duration:0.22)){panOffset = .zero}}label:{AssetIcon(name:"location",size:24).frame(width:44,height:44).background(W.paper,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line))}.accessibilityLabel("지도 중심").accessibilityIdentifier("mapRecenter").accessibilityValue(isCentered ? "중심":"이동됨").padding(16).padding(.bottom,centerControlBottomInset)}}
    }
}
struct WLocalProfile:Codable {
    var nickname="새벽러너";var introduction="조금씩, 멀리 가는 중";var region="모브시 중부권";var weight=""
    var photo:Data? = nil
    var providers=["카카오"];var logged=true;var notificationRead:[Int]=[]
}
enum WProfileValidation {
    static func isValid(nickname:String,introduction:String)->Bool {
        let normalized=nickname.trimmingCharacters(in:.whitespacesAndNewlines)
        return !normalized.isEmpty && normalized.count<=20 && introduction.count<=60
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

@MainActor @Observable final class WireState {
    private let defaults:UserDefaults
    var profile:WLocalProfile
    var screen="H00"
    var rootIndex=2;var previousRootIndex=2;var forward=true
    var calendarMonth=Date();var calendarDay:Date?
    var path:[String]=[]
    var selected:UUID?
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
    var consentTopic="이용약관"
    var nickname="";var introduction="";var region="";var weight=""
    var title="";var memo="";var photo:Data?
    var challengeIssued:Date?;var challengeCode="482619"
    var authErrorField="";var authFilled=false;var authEmail="";var authPassword="";var authConfirm="";var authCurrent="";var revealedFields:Set<String>=[];var settingsGrant=false;var otpSuccess=false;var otpFocused=false;var code="";var codeAttempts=0;var verified=false
    var goal=RunGoal();var weekly=WeeklyGoal()
    var testing=false
    var saving=false;var passwordChanged=false;var resetBack="A01"
    init(){let args=ProcessInfo.processInfo.arguments;defaults=args.contains("-wire-fixture") ? UserDefaults(suiteName:"mov.wireframe.review")! : UserDefaults.standard;profile=defaults.data(forKey:"mov.wireframe.profile.v1").flatMap{try? JSONDecoder().decode(WLocalProfile.self,from:$0)} ?? WLocalProfile()}
    func save(){if let data=try? JSONEncoder().encode(profile){defaults.set(data,forKey:"mov.wireframe.profile.v1")}}
    var notificationIDs:[Int]{WReviewMode.tools && ProcessInfo.processInfo.arguments.contains("-wire-empty-notifications") ? []:[0,1]}
    var hasUnreadNotifications:Bool{notificationIDs.contains{!profile.notificationRead.contains($0)}}
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
        profile=target.profile;store.records=target.records;store.goal=target.goal;store.weekly=target.weekly;store.persist();save();clearShare();go("H00")
    }
    static let otpScreens:Set<String>=["A19","A20","A21","A22","A23"]
    func clearAuthSecrets(){authErrorField="";authPassword="";authConfirm="";authCurrent="";authFilled=false;revealedFields=[];code="";otpFocused=false}
    func leaveAuth(for next:String){
        clearAuthSecrets();otpSuccess=false
        if !Self.otpScreens.contains(next){challengeIssued=nil;codeAttempts=0;authEmail=""}
        if !["A16","A17","A18","T15","T06"].contains(next){settingsGrant=false}
    }
    static let providerRoutes:Set<String>=["T06","T07","T08","T09","T15","T17","A16","A17","A18"]
    func returnToProviders(){
        if let index=path.firstIndex(of:"T05"){path=Array(path.prefix(index))}
        else{path.removeAll{Self.providerRoutes.contains($0)};if path.isEmpty{path=["T01"]}}
        leaveAuth(for:"T05");forward=false;screen="T05";pending="T05";error=""
    }
    func go(_ next:String){guard next != screen else{return};
        if (next=="H00" && screen.hasPrefix("A")) || (next=="A01" && ["T10","A13","A18","T12"].contains(screen)){
            leaveAuth(for:next);path=[];screen=next;forward=true;rootIndex=2;error="";return
        };if next=="T05" && (Self.providerRoutes.contains(screen) || resetBack=="T05"){returnToProviders();return};if ["T17","A18"].contains(next){if let index=path.firstIndex(of:"T05"){path=Array(path.prefix(index+1))}else{path=["T01","T05"]};leaveAuth(for:next);forward=true;screen=next;error="";return};if screen=="A18" && next=="A01"{path=[];leaveAuth(for:next);screen=next;error="";return};leaveAuth(for:next);forward=true;let roots=["POINTS","H01","H00","C01","M01"];if let index=["H02":1,"H05":1][next] ?? roots.firstIndex(of:next){forward=index>rootIndex;previousRootIndex=rootIndex;rootIndex=index};path.append(screen);screen=next;error=""}
    func openRecord(_ record:RunRecord){selected=record.id;forward=true;path.append(screen);screen="L04";error=""}
    func back(){
        if screen=="A15"{go("H00");return}
        if screen=="A13" || (screen=="A18" && passwordChanged){go("A01");return}
        if ["T17","A18"].contains(screen){returnToProviders();return};let destination=path.popLast() ?? "H00";leaveAuth(for:destination);forward=false;screen=destination;error="";let roots=["POINTS","H01","H00","C01","M01"];if let index=["H02":1,"H05":1][screen] ?? roots.firstIndex(of:screen){rootIndex=index}}
}
struct RootView:View {@Environment(\.dynamicTypeSize) var systemSize;var captureViewport:Bool{ProcessInfo.processInfo.arguments.contains("-wire-fixture") && ProcessInfo.processInfo.arguments.contains("-wire-capture-viewport")};var body:some View {Group{if captureViewport{ZStack(alignment:.top){W.paper;Text("SIMULATION · 가상 데이터 · 실제 GPS·인증 없음").font(.system(size:8)).foregroundStyle(Color(white:0.4)).frame(maxWidth:.infinity).frame(height:24).background(Color(white:0.93));WireframeRoot().frame(width:390,height:766).clipped().offset(y:24)}.frame(width:390,height:790,alignment:.top).clipped().ignoresSafeArea()}else if ProcessInfo.processInfo.arguments.contains("-wire-fixture") && ProcessInfo.processInfo.arguments.contains("-wire-compact-review"){WireframeRoot().frame(width:320,height:568).clipped()}else if ProcessInfo.processInfo.arguments.contains("-wire-review-size"){WireframeRoot().frame(width:388,height:764).clipped()}else{WireframeRoot()}}.dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("-wire-large") ? .accessibility3:systemSize).statusBarHidden(captureViewport)}}
struct WireframeRoot:View {
    @MainActor private static var didPrepareFixture=false
    @State var store:RunStore
    @State var shareWorkspace=ShareWorkspace()
    @State var pointsStore:WPointsStore
    init(){
        let args=ProcessInfo.processInfo.arguments
        let defaults=args.contains("-wire-fixture") ? UserDefaults(suiteName:"mov.wireframe.review")! : UserDefaults.standard
        let resetFixture=args.contains("-wire-reset") && !Self.didPrepareFixture
        if resetFixture{Self.didPrepareFixture=true;defaults.removePersistentDomain(forName:"mov.wireframe.review")}
        let model=RunStore(defaults:defaults)
        let pointModel=WPointsStore(defaults:defaults,insufficientFixture:args.contains("-wire-points-insufficient"),emptyFixture:args.contains("-wire-points-empty"))
        if resetFixture{
            model.goal=RunGoal();model.weekly=WeeklyGoal();model.session=nil;model.storageMessage=nil
            model.records=[RunRecord(date:ISO8601DateFormatter().date(from:"2026-09-29T07:12:00+09:00")!,title:"가볍게 달린 아침",memo:"가상 예시 기록",seconds:1808,kilometers:4.82,segments:[RunSegment(distance:1,seconds:378),RunSegment(distance:1,seconds:369),RunSegment(distance:1,seconds:386),RunSegment(distance:1,seconds:370),RunSegment(distance:0.82,seconds:305)],isExample:true)]
            model.persist()
        }
        let state=WireState();if resetFixture{state.profile=WLocalProfile();state.save()}
        _ui=State(initialValue:state);_store=State(initialValue:model);_pointsStore=State(initialValue:pointModel)
    }
    @State var ui=WireState()
    @State var selectedPointCategory:WPointCategory = .image
    @State var selectedPointKind:WPointKind = .all
    @State var showingPointPurchaseConfirmation=false
    @FocusState var otpInputFocused:Bool
    @FocusState var authInput:String?
    @State var splash=true
    @AppStorage("appearance") var appearance="system"
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduceMotion:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    @Namespace var indicator
    @Environment(\.scenePhase) var scenePhase
    var current:RunRecord {if ui.testing && ui.screen.hasPrefix("R") && store.session==nil{return RunRecord(date:Date(),title:"현재 러닝",seconds:ui.screen=="R01" ? 4:302,kilometers:ui.screen=="R01" ? 0:0.81)};if let id=ui.selected,let r=store.records.first(where:{$0.id==id}){return r};return store.session?.record(at:Date()) ?? store.records.first ?? RunRecord(date:Date(),title:"현재 러닝",seconds:0,kilometers:0)}
    var roots:[String]{WRootTab.allCases.map(\.route)}
    var reviewTools:Bool {WReviewMode.tools}
    var isAccountScreen:Bool {ui.screen.hasPrefix("A") || (5...17).contains(Int(ui.screen.dropFirst()) ?? 0) && ui.screen.hasPrefix("T")}
    var isRoot:Bool {roots.contains(ui.screen) || ["H02","H05","L01"].contains(ui.screen)}
    var body:some View {
        ZStack {
            VStack(spacing:0){
                GeometryReader { geo in
                    ZStack {
                        if ui.screen=="L01" {
                            recordsRoot
                        } else {
                        home.accessibilityElement(children:.contain).offset(x:ui.rootIndex==2 ? 0:ui.rootIndex>2 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==2 || ui.previousRootIndex==2 ? 1:0).accessibilityHidden(ui.rootIndex != 2 || !isRoot || splash).allowsHitTesting(ui.rootIndex == 2 && isRoot && !splash)
                        ready.accessibilityElement(children:.contain).offset(x:ui.rootIndex==1 ? 0:ui.rootIndex>1 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==1 || ui.previousRootIndex==1 ? 1:0).accessibilityHidden(ui.rootIndex != 1 || !isRoot || splash).allowsHitTesting(ui.rootIndex == 1 && isRoot && !splash)
                        points.accessibilityElement(children:.contain).offset(x:ui.rootIndex==0 ? 0:ui.rootIndex>0 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==0 || ui.previousRootIndex==0 ? 1:0).accessibilityHidden(ui.rootIndex != 0 || !isRoot || splash).allowsHitTesting(ui.rootIndex == 0 && isRoot && !splash)
                        community.accessibilityElement(children:.contain).offset(x:ui.rootIndex==3 ? 0:ui.rootIndex>3 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==3 || ui.previousRootIndex==3 ? 1:0).accessibilityHidden(ui.rootIndex != 3 || !isRoot || splash).allowsHitTesting(ui.rootIndex == 3 && isRoot && !splash)
                        profile.accessibilityElement(children:.contain).offset(x:ui.rootIndex==4 ? 0:ui.rootIndex>4 ? -geo.size.width:geo.size.width).opacity(ui.rootIndex==4 || ui.previousRootIndex==4 ? 1:0).accessibilityHidden(ui.rootIndex != 4 || !isRoot || splash).allowsHitTesting(ui.rootIndex == 4 && isRoot && !splash)
                        }
                    }.frame(width:geo.size.width,height:geo.size.height).clipped()
                }
                nav
            }.opacity(isRoot && !splash ? 1:0).allowsHitTesting(isRoot && !splash).accessibilityHidden(!isRoot || splash).accessibilityElement(children:.contain).accessibilityIdentifier("screen-"+ui.screen)
            if !isRoot && !splash {
                screenView.id(["R01","R02","R03","R04","R05","R07","R08","R10"].contains(ui.screen) ? "run-map":ui.screen).accessibilityElement(children:.contain).accessibilityIdentifier("screen-"+ui.screen)
                    .environment(\.authPageMotion,WAuthMotionContext(enabled:isAccountScreen,reduced:reduceMotion,forward:ui.forward))
                    .transition(isAccountScreen ? .identity:reduceMotion ? .opacity:.asymmetric(insertion:.move(edge:ui.forward ? .trailing:.leading),removal:.move(edge:ui.forward ? .leading:.trailing)))
            }
            if ui.otpSuccess && ["A02","A15"].contains(ui.screen){WOTPSuccess(reduced:reduceMotion).padding(.horizontal,22).frame(maxHeight:.infinity,alignment:.bottom).padding(.bottom,112).allowsHitTesting(false)}
            if splash {WSplash().frame(maxWidth:.infinity,maxHeight:.infinity).background(W.paper)}
        }.background(W.paper).foregroundStyle(W.ink).tint(W.ink).preferredColorScheme(ThemePreference(rawValue:appearance)?.colorScheme).clipShape(WScreenClip(extendMap:["R01","R02","R03","R04","R05","R07","R08","R10"].contains(ui.screen)))
            .task{
                let args=ProcessInfo.processInfo.arguments
                if let i=args.firstIndex(of:"-wire-screen"),args.indices.contains(i+1){
                    let requestedScreen=args[i+1];ui.screen=requestedScreen=="B01" ? "POINTS":requestedScreen;ui.rootIndex=["H02":1,"H05":1][ui.screen] ?? roots.firstIndex(of:ui.screen) ?? (ui.screen.hasPrefix("L") ? 1:2);ui.testing=true;splash=false;prepare(ui.screen);if requestedScreen=="B08"{ui.selectedPointProductID="frame"}
                    if ["Q01","Q02","Q03"].contains(ui.screen),let valid=store.records.first(where:{$0.isValid}){ui.selected=valid.id}
                    if ui.screen.hasPrefix("A2") || ui.screen=="A19"{ui.challengeIssued=Date().addingTimeInterval(ui.screen=="A21" ? -301:0);ui.challengeCode=ui.screen=="A23" ? "731204":"482619"}
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
                        if ui.screen.hasPrefix("A2") || ui.screen=="A19"{ui.code="";ui.error="";ui.challengeIssued=nil}

                    }
                    if ui.screen=="S05"{var record=current;record.kilometers=0;record.seconds=312;record.segments=[RunSegment(distance:0,seconds:312,type:"gps-gap",reason:"GPS 수신 실패 예시")];store.records=[record];ui.selected=record.id}
                }else{try? await Task.sleep(for:.milliseconds(1040));splash=false;if !ui.profile.logged{ui.screen="A01"}else if store.session != nil{ui.screen="H06"}}
            }.onChange(of:scenePhase){_,phase in if phase != .active{ui.clearAuthSecrets();ui.otpSuccess=false};if phase == .background && store.session?.paused == false{store.pause();ui.screen="R04"}}
    }
    func go(_ id:String){let route=id=="B01" ? "POINTS":id;if route=="A01" && ui.screen=="T10"{shareWorkspace.clear()};let mapStates=["R01","R02","R03","R04","R05","R07","R08","R10"];let duration=mapStates.contains(ui.screen) && mapStates.contains(route) ? 0.3:((ui.screen=="L01" && route=="L04") || (ui.screen=="L04" && route=="L01")) ? 0.32:0.24;prepare(route);withAnimation(reduceMotion ? nil:.timingCurve(0.2,0.8,0.2,1,duration:duration)){ui.go(route)}}
    func back(){withAnimation(reduceMotion ? nil:.timingCurve(0.2,0.8,0.2,1,duration:0.24)){ui.back()}}
    func prepare(_ id:String){
        if id=="H03"{ui.goal=store.goal};if id=="H04"{ui.weekly=store.weekly}
        if ["Q01","Q02","Q03"].contains(id),!current.isValid,let valid=store.records.first(where:{$0.isValid}){ui.selected=valid.id}
        if id=="M02"{ui.nickname=ui.profile.nickname;ui.introduction=ui.profile.introduction;ui.region=ui.profile.region;ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo)}
        if id=="T02"{ui.weight=ui.profile.weight}
        if id=="L06"{ui.title=current.title;ui.memo=current.memo}
    }
    var nav:some View {
        HStack(spacing:0){
            ForEach(WRootTab.allCases,id:\.rawValue){tab in
                let index=tab.rawValue
                Button{ui.path=[];go(tab.route)}label:{
                    VStack(spacing:3){
                        ZStack{
                            Color.clear.frame(height:3)
                            if ui.screen==tab.route || (tab == .run && ["H02","H05"].contains(ui.screen)){
                                Capsule().fill(W.lime).frame(width:20,height:3).matchedGeometryEffect(id:"nav",in:indicator)
                            }
                        }
                        if tab == .home { BrandMark(size:WRootTab.homeMarkSize).accessibilityIdentifier("homeTabBrandMark") }
                        else if tab == .points { Image("PrismPoint").resizable().renderingMode(.original).scaledToFit().frame(width:24,height:24).accessibilityHidden(true) }
                        else if let asset=tab.assetName { AssetIcon(name:asset,size:24) }
                        if let caption=tab.caption {
                            Text(caption).font(W.font(11,.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(isRoot && ui.rootIndex==index ? W.ink:W.muted)
                                .accessibilityIdentifier("tab-caption-\(index)")
                        } else {
                            Text("홈").font(W.font(11,.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                .hidden().accessibilityHidden(true)
                        }
                    }
                    .padding(.top,3).frame(maxWidth:.infinity,minHeight:64).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(index)")
                .accessibilityAddTraits(isRoot && ui.rootIndex==index ? .isSelected:[])
            }
        }
        .padding(.horizontal,8).background(W.paper).overlay(alignment:.top){W.line.frame(height:1)}
        // The run map takes over the full viewport. Keep the hidden tab bar out
        // of VoiceOver and hit testing while a run is active; otherwise its
        // invisible bottom hit region can cover the compact run controls.
        .accessibilityHidden(!isRoot || splash)
        .allowsHitTesting(isRoot && !splash)
    }
    func button(_ text:String,_ target:String,kind:Int=0)->some View {Button(text){go(target)}.buttonStyle(WButtonStyle(kind:kind))}
    func rootHeader(_ title:String,run:Bool=false,showMark:Bool=true)->some View {let unread = ui.hasUnreadNotifications;return WHeader(title:title,root:true,showRootMark:showMark,trailing:AnyView(HStack(spacing:0){Button{go(run ? "L01":"N01")}label:{AssetIcon(name:run ? "records":"bell",size:20).frame(width:44,height:44).contentShape(Rectangle()).overlay(alignment:.topTrailing){if !run && unread{Circle().fill(W.lime).frame(width:5,height:5).padding(.top,8).padding(.trailing,10)}}}.accessibilityLabel(run ? "기록 보기":"알림").accessibilityIdentifier(run ? "openRecords":"notificationBell").accessibilityValue(run ? "":"\(unread ? "읽지 않음":"읽음")");if title=="내 정보"{Button{go("T01")}label:{AssetIcon(name:"settings",size:20).frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel("설정")}}))}
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
        case "Q02":ShareOutputView(record:current,workspace:shareWorkspace,back:{back()},gallery:{go("Q03")})
        case "Q03":ShareGallery(record:current,workspace:shareWorkspace,back:{back()},create:{go("Q01")},open:{id in shareWorkspace.selectedOutputID=id;go("Q02")})
        case "S01","S02","S03","S04","S05":completion
        case "T01":settings
        case "T18":theme
        case "T02","A03":weightProfile
        case "T05":providers
        case "T11":deleteAccount
        case "A01","A07","A10","A12","A16","A17":authForm
        case "A02":consents
        case "A19","A20","A21","A22","A23":verification
        case "C01":community
        default:informationPage
        }
    }
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
            Text("모브").font(.custom("Cafe24Ssurround",size:28)).kerning(-1.4).frame(height:36.4).padding(.top,22).opacity(word).offset(y:7*(1-word))
            Text("오늘의 달리기를 나의 기록으로").font(W.font(14)).kerning(-0.21).foregroundStyle(W.muted).frame(height:21).padding(.top,9).opacity(tagline).offset(y:6*(1-tagline))
        }.offset(y:-26)
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
    static var tools:Bool{ProcessInfo.processInfo.arguments.contains("-wire-fixture") && !ProcessInfo.processInfo.arguments.contains("-wire-user-flow")}
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
