import SwiftUI

struct RunningView: View {
    let store: RunStore
    var completed: (RunRecord?)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed=false
    @State private var finishSheet=false
    @State private var detail=false
    @State private var centered=false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment:.bottom) {
                SampleMap(route:true).ignoresSafeArea(edges:.top)
                VStack(alignment:.leading,spacing:8){GPSBadge();Text("실제 장소가 아닌 샘플 지도").font(.caption2).padding(5).background(MovTokens.background,in:RoundedRectangle(cornerRadius:3));Spacer()}.frame(maxWidth:.infinity,alignment:.leading).padding(.leading,16).padding(.top,8)
                VStack {
                    Spacer()
                    HStack { Spacer(); Button {centered.toggle()} label:{AssetIcon(name:"location").frame(width:44,height:44).background(MovTokens.background,in:RoundedRectangle(cornerRadius:12))}.accessibilityLabel("샘플 지도 중심으로").overlay(alignment:.leading){if centered {Text("샘플 중심").font(.caption2).padding(4).background(MovTokens.background).offset(x:-75)}} }.padding(.horizontal,16).padding(.bottom,12)
                    panel.frame(height:collapsed ? 190:min(geo.size.height*0.70,590))
                }
            }
        }.background(MovTokens.background).foregroundStyle(MovTokens.text).tint(MovTokens.text)
            .sheet(isPresented:$finishSheet){finishContent.presentationDetents([.medium])}
            .sheet(isPresented:$detail){liveDetail}
    }
    private var panel: some View {
        VStack(spacing:0) {
            Button {togglePanel()} label:{Capsule().fill(MovTokens.secondary.opacity(0.55)).frame(width:34,height:4).frame(maxWidth:.infinity).frame(height:32).contentShape(Rectangle())}
                .accessibilityLabel(collapsed ? "패널 펼치기":"패널 접기").accessibilityIdentifier("panelHandle")
                .gesture(DragGesture(minimumDistance:15).onEnded{value in setCollapsed(value.translation.height>0)})
            TimelineView(.periodic(from:.now,by:1)) { timeline in
                if let session=store.session {
                    VStack(alignment:.leading,spacing:18) {
                        if !collapsed {
                            ScrollView {
                                VStack(alignment:.leading,spacing:20) {
                                    Text(session.paused ? "일시정지" : "샘플 러닝 중").font(.title2.bold()).accessibilityIdentifier("runState")
                                    MetricView(record:session.record(at:timeline.date))
                                    Text(session.goal.summary).font(.subheadline)
                                    DemoCaption()
                                    Text("거리는 6:00/km 속도로 계산한 데모 값입니다.").font(.caption).foregroundStyle(MovTokens.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }
                        } else {
                            HStack {Text(session.paused ? "일시정지":"샘플 러닝 중").font(.headline);Spacer();Text(RunRecord.clock(session.elapsed(at:timeline.date))).monospacedDigit()}
                        }
                        Button(session.paused ? "러닝 재개":"Ⅱ 일시정지") {if session.paused {store.resume()}else{store.pause()}}.buttonStyle(MovPrimaryButtonStyle()).accessibilityIdentifier("pauseResume")
                        if !collapsed {
                            if session.paused {Button("러닝 종료"){finishSheet=true}.buttonStyle(DestructiveButton()).accessibilityIdentifier("finishRun")}
                            else {Button("상세 기록 보기"){detail=true}.buttonStyle(SecondaryButton())}
                        }
                    }.padding(.horizontal,24).padding(.bottom,20)
                }
            }
        }.frame(maxHeight:.infinity,alignment:.top).background { UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24).fill(MovTokens.background).ignoresSafeArea(edges:.bottom) }
    }
    private var finishContent: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("러닝을 종료할까요?").font(.title2.bold())
            Text("이 기록은 실제 측정이 아닌 샘플 기록으로 저장됩니다.").foregroundStyle(MovTokens.secondary)
            Button("종료하고 샘플 저장") {finishSheet=false;completed(store.finish(save:true))}.buttonStyle(DestructiveButton()).accessibilityIdentifier("saveRun")
            Button("저장하지 않고 삭제",role:.destructive) {finishSheet=false;completed(store.finish(save:false))}.frame(maxWidth:.infinity,minHeight:44)
            Button("돌아가기"){finishSheet=false}.buttonStyle(SecondaryButton())
        }.padding(24).foregroundStyle(MovTokens.text)
    }
    private var liveDetail: some View {
        NavigationStack {
            TimelineView(.periodic(from:.now,by:1)){timeline in
                VStack(alignment:.leading,spacing:24){
                    if let session=store.session {MetricView(record:session.record(at:timeline.date));DemoCaption();Spacer();Button(session.paused ? "러닝 재개":"Ⅱ 일시정지"){if session.paused{store.resume()}else{store.pause()}}.buttonStyle(MovPrimaryButtonStyle())}
                    Button("지도 화면으로 돌아가기"){detail=false}.buttonStyle(SecondaryButton())
                }.padding(24)
            }.navigationTitle("현재 샘플 기록").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func togglePanel(){setCollapsed(!collapsed)}
    private func setCollapsed(_ value:Bool){withAnimation(reduceMotion ? nil:.easeInOut(duration:0.25)){collapsed=value}}
}
