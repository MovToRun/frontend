import SwiftUI
extension WireframeRoot {
    var runPanel:some View {
        TimelineView(.periodic(from:.now,by:1)){context in
            let review=ProcessInfo.processInfo.arguments.contains("-wire-review-size")
            let record=review ? RunRecord(date:Date(),title:"현재 러닝",seconds:ui.screen=="R01" ? 4:302,kilometers:ui.screen=="R01" ? 0:0.81):(store.session?.record(at:context.date) ?? current)
            let paused=ui.screen=="R04" || ui.screen=="R05" || store.session?.paused == true
            GeometryReader{geometry in
                WRunningViewport(collapsed:$ui.collapsed,reduced:reduceMotion,topInset:geometry.safeAreaInsets.top,bottomInset:geometry.safeAreaInsets.bottom,paused:paused,screen:ui.screen,pause:togglePause){handle in
                    fixedRunPanel(record:record,paused:paused,handle:handle)
                }.ignoresSafeArea(.container,edges:[.top,.bottom])
            }
        }
    }
    private func fixedRunPanel(record:RunRecord,paused:Bool,handle:AnyView)->some View {
        VStack(spacing:0){
            handle.frame(maxWidth:.infinity).frame(height:44)
            ZStack(alignment:.topLeading){
                runPanelMetrics(record:record,paused:paused).id(ui.screen=="R05" ? "finish":ui.screen=="R10" ? "error":"metrics").transition(.opacity)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            VStack(spacing:10){
                Button(ui.screen=="R05" ? "아직 쉴게요":ui.screen=="R10" ? "저장 다시 시도":paused ? "계속 달리기":"Ⅱ 일시정지"){
                    if ui.screen=="R05"{changeRunState("R04")}
                    else if ui.screen=="R10"{saveRun()}
                    else{togglePause()}
                }.buttonStyle(WButtonStyle(panel:true)).contentTransition(.opacity).accessibilityIdentifier(ui.collapsed ? "inactiveExpandedPause":ui.screen=="R05" ? "cancelFinish":ui.screen=="R10" ? "retryRunSave":paused ? "resumeRun":"pauseRun").accessibilityHidden(ui.collapsed)
                Button(ui.screen=="R05" ? "종료하고 저장":ui.screen=="R10" ? "정지된 기록 확인":paused ? "러닝 종료":"상세 기록 보기"){
                    if ui.screen=="R05"{saveRun()}
                    else if ui.screen=="R10"{changeRunState("R04")}
                    else if paused{changeRunState(record.seconds<=0 ? "R12":"R05")}
                    else{go("R06")}
                }.buttonStyle(WButtonStyle(kind:1,panel:true)).contentTransition(.opacity).accessibilityIdentifier(ui.screen=="R05" ? "saveRun":paused ? "finishRun":"runDetails").accessibilityHidden(ui.collapsed)
            }
            Button("이 기록 삭제"){go("R11")}.font(W.font(13,.medium)).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3))
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).opacity(ui.screen=="R05" ? 1:0)
                .allowsHitTesting(ui.screen=="R05").accessibilityHidden(ui.screen != "R05")
        }.padding(.horizontal,24).padding(.bottom,12)
    }
    @ViewBuilder private func runPanelMetrics(record:RunRecord,paused:Bool)->some View {
        VStack(alignment:.leading,spacing:8){
            Text(ui.screen=="R05" ? "러닝을 마칠까요?":ui.screen=="R10" ? "저장을 다시 시도해 주세요":ui.screen=="R01" ? "위치 확인 중":" ")
                .font(W.font(22,.bold)).frame(height:28,alignment:.leading)
            WMetric(record:record,paused:paused,reservePauseSpace:true)
            Text(ui.screen=="R03" ? "GPS 신호가 약해요":ui.screen=="R08" ? "네트워크 연결 없음":ui.screen=="R01" ? "시간은 계속 기록돼요":" ")
                .font(W.font(12)).foregroundStyle(W.muted).frame(height:18,alignment:.leading)
        }
    }
    func changeRunState(_ next:String){
        withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){ui.screen=next}
    }

    func togglePause(){withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){if store.session==nil{store.start(weight:Double(ui.profile.weight))};if store.session?.paused == true || ui.screen=="R04"{store.resume();ui.screen="R02"}else{store.pause();ui.screen="R04"}}}
    func saveRun(){
        guard !ui.saving,let session=store.session else{return}
        guard session.elapsed(at:Date())>0 else{go("R12");return}
        ui.saving=true;store.pause();ui.screen="S02"
        Task { @MainActor in
            if !reduceMotion{try? await Task.sleep(for:.milliseconds(220))}
            if let record=store.finish(save:true){ui.selected=record.id;ui.screen=record.isValid ? "S01":"S05"}else{ui.screen="S03"}
            ui.saving=false
        }
    }
    var runDetails:some View {WPage(title:"현재 러닝",back:back){WMetric(record:current);VStack(spacing:0){WRow(title:"유효 구간 평균 페이스",value:(current.kilometers>0 && current.pace.count==4 ? "0":"")+current.pace+" /km",plain:true);WRow(title:"추정 소모 칼로리",value:current.caloriesText,plain:true);WRow(title:"이번 러닝 목표",value:store.goal.summary,plain:true)};WText(text:"체중과 유효 거리를 바탕으로 한 추정값이에요.",small:true);WDisclosure(title:"유효 구간과 원본 기록",expanded:$ui.validityExpanded,triangle:true){WText(text:"위치 센서에서 확인한 구간 정보가 없어요. 시간 기록은 계속 유지돼요.",small:true)}.font(W.font(12))}actions:{Button(store.session?.paused == true ? "계속 달리기":"Ⅱ 일시정지"){togglePause()}.buttonStyle(WButtonStyle());button("러닝 화면으로 돌아가기",store.session?.paused == true ? "R04":"R02",kind:1)}}
    var records:some View {VStack(spacing:0){WHeader(title:"러닝 기록",back:{if ui.path.isEmpty{go("H01")}else{back()}});ScrollView{VStack(alignment:.leading,spacing:16){if ui.screen=="L03"{WNotice(text:"일부 기록을 불러오지 못했어요. 마지막으로 확인한 기록은 그대로 보여드려요.",danger:true);Button("다시 불러오기"){go("L01")}}
        if ui.screen == "L03" && store.records.isEmpty {
            VStack(alignment:.leading,spacing:12){Text("기록을 확인할 수 없어요").font(W.font(20,.semibold));WText(text:"조회에 실패해 기록이 0건이라고 단정하지 않아요. 다시 불러오거나 나중에 다시 확인해 주세요.")}.padding(.vertical,28).accessibilityIdentifier("recordLookupFailure")
        } else if ui.screen=="L02" || (store.records.isEmpty && ui.screen != "L03") {
            VStack(spacing:0){Text("아직 러닝 기록이 없어요").font(W.font(23,.semibold)).padding(.top,13).padding(.bottom,31);WText(text:"첫 러닝을 시작해 보세요").padding(.bottom,20);button("러닝 시작","H02")}.padding(.vertical,65)
        } else {WText(text:"기기에 저장된 기록",small:true);ForEach(store.records){r in recordRow(r)}}
    }.padding(24)}}}
    func recordRow(_ r:RunRecord)->some View {Button{ui.selected=r.id;go("L04")}label:{HStack(spacing:14){WMap(route:r.isValid).frame(width:70,height:64).clipShape(RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:5){Text(r.title).font(W.font(13,.medium)).fixedSize(horizontal:false,vertical:true);Text("\(MovNumber.display(r.kilometers)) km").font(W.font(18,.semibold));WText(text:r.date.formatted(.dateTime.year().month().day())+"\n"+RunRecord.clock(r.seconds)+" · "+r.pace+" /km",small:true)};Spacer();Image(systemName:"chevron.right").font(W.font(13))}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,15)}.buttonStyle(.plain).overlay(alignment:.bottom){W.line.frame(height:1)}}
    var recordDetail:some View {
        VStack(spacing:0){
            WHeader(title:"러닝 기록",back:back)
            ScrollViewReader{proxy in
                ScrollView{VStack(alignment:.leading,spacing:18){
                    WText(text:current.date.formatted(.dateTime.year().month().day()),small:true)
                    WInlineRecordField(value:current.title,multiline:false,save:{value in var record=current;record.title=value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? RunRecord.title(for:record.date):value;store.update(record)},focus:{scrollEditor(proxy,"inlineTitle")}).id("inlineTitle")
                    WMetric(record:current,saved:true)
                    WMap(route:current.isValid).frame(height:172).clipShape(RoundedRectangle(cornerRadius:14))
                    WRow(title:"추정 소모 칼로리",value:current.caloriesText)
                    WText(text:current.weightKg==nil ? "기록 당시 체중 정보가 없어요":"기록 당시의 체중으로 계산",small:true)
                    WDisclosure(title:"유효 구간과 원본 기록",expanded:$ui.validityExpanded,triangle:true){VStack(alignment:.leading,spacing:8){ForEach(Array(current.validityDetails.enumerated()),id:\.offset){item in WText(text:item.element,small:true)};WText(text:"표시한 거리와 페이스는 저장된 유효 구간을 바탕으로 계산해요. 원본 판별 정보가 없는 구간을 임의로 분류하지 않아요.",small:true)}.frame(maxWidth:.infinity,alignment:.leading)}.font(W.font(12)).padding(.vertical,18)
                    WInlineRecordField(value:current.memo,multiline:true,save:{value in var record=current;record.memo=value;store.update(record)},focus:{scrollEditor(proxy,"inlineMemo")}).id("inlineMemo")
                    WRow(title:"구간 기록",subtitle:"유효 구간·제외 이유",action:{go("L05")})
                    Button("이 러닝 기록 삭제"){go("L07")}.foregroundStyle(Color.wire(0xA92D32,0xFF9CA3)).font(W.font(13)).frame(minHeight:44).accessibilityIdentifier("deleteRecord")
                }.padding(24)}.scrollDismissesKeyboard(.interactively)
            }
        }.modifier(WRecordKeyboardViewport()).id(current.id)
    }
    private func scrollEditor(_ proxy:ScrollViewProxy,_ id:String){
        guard ui.screen=="L04" else{return}
        proxy.scrollTo(id,anchor:.center)
    }

    var recordEdit:some View {WPage(title:"기록 편집",back:back){WField(label:"제목 (40자 이내)",text:$ui.title,limit:40).accessibilityIdentifier("recordTitleInput").padding(.top,18);WField(label:"메모 (300자 이내)",text:$ui.memo,limit:300,multiline:true).accessibilityIdentifier("recordMemoInput");WText(text:"제목을 비우면 시작 날짜와 시간대의 기본 이름을 사용해요.\n거리·시간·경로는 바꾸지 않아요.",small:true);if !ui.error.isEmpty{WNotice(text:ui.error,danger:true)}}actions:{Button("변경 저장"){guard ui.title.count<=40 && ui.memo.count<=300 else{ui.error="제목은 40자, 메모는 300자 이내로 입력해 주세요.";return};var r=current;r.title=ui.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? RunRecord.title(for:r.date):ui.title;r.memo=ui.memo;store.update(r);back()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("saveRecordEdit")}}
    var splits:some View {WPage(title:"구간 기록",back:back){HStack{Text("구간 평균 페이스").font(W.font(16,.semibold));Spacer();Text(current.pace+" /km").font(W.font(13,.medium))};WPaceChart(record:current).padding(.top,-18)}actions:{}}
    var completion:some View {WPage(title:"러닝 완료",back:ui.screen=="S02" ? nil:{go("H00")}){VStack(alignment:.leading,spacing:0){if ["S01","S05"].contains(ui.screen){WCompletionFeedback(recordID:current.id,seen:$ui.completionFeedbackSeen)};WText(text:recordWhen(current),small:true).padding(.top,["S01","S05"].contains(ui.screen) ? 0:6)};Text(ProcessInfo.processInfo.arguments.contains("-wire-review-size") ? "10월 1일 아침 러닝":current.title).font(W.font(14,.medium));WHeading(text:ui.screen=="S03" ? "아직 저장하지\n못했어요":ui.screen=="S02" ? "기록을\n저장하고 있어요":ui.screen=="S05" ? "유효한 러닝\n구간이 없어요":"가볍게,\n잘 달렸어요").padding(.top,-7);WMetric(record:current,saved:ui.screen != "S03").padding(.top,-3);WMap(route:ui.screen != "S05").frame(height:172).clipShape(RoundedRectangle(cornerRadius:14));WRow(title:"추정 소모 칼로리",value:current.caloriesText,separator:false);if !["S01","S05"].contains(ui.screen){WNotice(text:ui.screen=="S03" ? "이 기기에 임시 기록이 남아 있어요. 다시 저장해 주세요.":ui.screen=="S02" ? "저장 결과를 확인하기 전에는 완료로 표시하지 않아요.":"기기에 저장됨 · 동기화 대기\n클라우드 백업을 추가할 경우의 후속 상태예요.",danger:ui.screen=="S03")}}actions:{if ui.screen=="S02"{Button("저장 중…"){}.buttonStyle(WButtonStyle()).disabled(true)}else if ui.screen=="S03"{Button("다시 저장"){saveRun()}.buttonStyle(WButtonStyle());button("임시 기록 확인","H06",kind:1)}else{button("기록 보기","L04");button("홈으로","H00",kind:1)}}}
}

struct WPaceChart:View {
    var record:RunRecord
    @State private var selected=0
    struct Point:Identifiable {var id:Int;var start:Double;var end:Double;var pace:Double;var group:Int}
    var points:[Point] {var distance=0.0;var group=0;var result:[Point]=[];for (i,s) in (record.segments ?? []).enumerated(){if s.type != "include" || s.distance<=0 || s.seconds<=0{group+=1;continue};let start=distance;distance+=s.distance;result.append(Point(id:i,start:start,end:distance,pace:s.seconds/s.distance,group:group))};return result}
    var body:some View {VStack(alignment:.leading,spacing:0){
        if points.isEmpty{VStack(spacing:14){Text("구간 데이터가 없어요").font(W.font(18,.medium));WText(text:"유효 평균은 확인할 수 있어요. 임의의 구간이나 변화 선은 만들지 않아요.",small:true)}.frame(maxWidth:.infinity,minHeight:210).background(W.soft,in:RoundedRectangle(cornerRadius:12))}
        else {Text("페이스 (분/km) · 위로 갈수록 빨라요").font(W.font(11)).foregroundStyle(W.muted).padding(.top,21).padding(.bottom,4)
            GeometryReader{geometry in
                let values=points.map(\.pace)+[record.seconds/max(0.01,record.kilometers)]
                let low=max(0,floor((values.min() ?? 0)/30)*30-30),high=ceil((values.max() ?? 60)/30)*30+30
                let width:CGFloat=320
                let x:(Double)->CGFloat={(54+CGFloat($0/max(0.01,record.kilometers))*232)*width/320}
                let y:(Double)->CGFloat={22+CGFloat(($0-low)/(high-low))*128}
                ZStack(alignment:.topLeading){
                    ForEach([low,(low+high)/2,high],id:\.self){v in Path{p in p.move(to:CGPoint(x:x(0),y:y(v)));p.addLine(to:CGPoint(x:x(record.kilometers),y:y(v)))}.stroke(Color.wire(0xEEEEEE,0x373A38),lineWidth:1);Text(pace(v)).font(W.font(12.5)).foregroundStyle(W.muted).frame(width:45,alignment:.trailing).position(x:22.5,y:y(v))}
                    Path{path in var previous:Int?;for point in points{let p=CGPoint(x:x(point.end),y:y(point.pace));if previous==point.group{path.addLine(to:p)}else{path.move(to:p)};previous=point.group}}.stroke(W.lime,style:StrokeStyle(lineWidth:3.5,lineCap:.round,lineJoin:.round))
                    if !points.isEmpty{let point=points[min(selected,points.count-1)];Path{p in p.move(to:CGPoint(x:x(point.end),y:18));p.addLine(to:CGPoint(x:x(point.end),y:155))}.stroke(Color.wire(0xD6D6D6,0x666A67),style:StrokeStyle(lineWidth:1,dash:[2,4]))}
                    Path{p in let average=record.seconds/max(0.01,record.kilometers);p.move(to:CGPoint(x:x(0),y:y(average)));p.addLine(to:CGPoint(x:x(record.kilometers),y:y(average)))}.stroke(W.muted,style:StrokeStyle(lineWidth:1,dash:[4,4]))
                    ForEach(Array(points.enumerated()),id:\.element.id){i,p in Circle().fill(W.lime).opacity(i==selected ? 1:0.75).frame(width:i==selected ? 12:7,height:i==selected ? 12:7).position(x:x(p.end),y:y(p.pace))}
                    HStack{Text("0");Spacer();Text(MovNumber.display(record.kilometers/2));Spacer();Text(MovNumber.display(record.kilometers))}.font(W.font(12.5)).foregroundStyle(W.muted).padding(.leading,54*width/320).padding(.trailing,34*width/320).offset(y:162)
                    Text("누적 유효 거리 (km)").font(W.font(12.5)).foregroundStyle(W.muted).frame(width:286*width/320,alignment:.trailing).offset(y:186)
                }.frame(width:320,height:216,alignment:.topLeading).scaleEffect(geometry.size.width/320,anchor:.topLeading).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in selected=points.enumerated().min(by:{abs(x($0.element.end)-v.location.x)<abs(x($1.element.end)-v.location.x)})?.offset ?? 0})
        }.aspectRatio(320.0/216.0,contentMode:.fit).accessibilityElement(children:.ignore).accessibilityLabel("구간 평균 페이스 그래프").accessibilityValue(readout).accessibilityAdjustableAction{d in selected=min(points.count-1,max(0,selected+(d == .increment ? 1:-1)))}
            Text(readout).font(W.font(13)).frame(maxWidth:.infinity,minHeight:24);Text("┄ 유효 평균 \(record.pace) /km").font(W.font(11)).foregroundStyle(W.muted).frame(maxWidth:.infinity,alignment:.center).padding(.top,7)
        }
        Text(points.isEmpty ? "기존 저장 합계의 평균이에요. 원본 구간 판별 정보가 없어 변화 선은 표시하지 않아요.":"저장된 구간의 유효 거리와 이동 시간으로 계산해요. 제외된 구간은 아래에서 확인할 수 있어요.").font(W.font(11)).kerning(-0.165).foregroundStyle(W.muted).lineSpacing(5.15).padding(.top,23)
        Text("구간별 기록").font(W.font(15,.semibold)).padding(.top,29).padding(.bottom,5);VStack(spacing:0){splitRow("구간",value:"페이스",header:true)
        if let segments=record.segments,!segments.isEmpty{ForEach(Array(segments.enumerated()),id:\.offset){i,s in if let point=points.first(where:{$0.id==i}){splitRow("\(MovNumber.display(point.start))–\(MovNumber.display(point.end)) km",value:pace(point.pace),separator:i<segments.count-1)}else{VStack(alignment:.leading,spacing:6){Text(s.type=="pause" ? "일시정지":"유효 구간에서 제외").font(W.font(14,.medium));WText(text:s.reason ?? "유효 러닝으로 확인할 수 없어 제외했어요.",small:true)}.padding(.vertical,12)}}}else{splitRow("전체 \(MovNumber.display(record.kilometers)) km",value:record.pace)} }
    }.onChange(of:record.id){_,_ in selected=0}.onChange(of:points.count){_,count in selected=min(selected,max(0,count-1))}}
    func pace(_ seconds:Double)->String {String(format:"%d:%02d",Int(seconds)/60,Int(seconds)%60)}
    func splitRow(_ title:String,value:String,header:Bool=false,separator:Bool=true)->some View {HStack{Text(title).font(W.font(12,header ? .semibold:.regular));Spacer();Text(value).font(W.font(header ? 12:11,header ? .semibold:.regular)).foregroundStyle(header ? W.ink:W.muted)}.frame(minHeight:49).overlay(alignment:.bottom){if separator{W.line.frame(height:1)}}}
    var readout:String{guard !points.isEmpty else{return "구간 데이터 없음"};let p=points[min(selected,points.count-1)];return "\(MovNumber.display(p.start))–\(MovNumber.display(p.end)) km 구간 · \(pace(p.pace)) /km"}
}

struct WSuccess:View {
    @Environment(\.accessibilityReduceMotion) var systemMotion
    var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    @State private var began=Date()
    @State private var settled=false
    var body:some View{TimelineView(.animation(minimumInterval:1.0/60,paused:reduced || settled)){context in
        let t=reduced ? 1:min(1,WOriginalMotion.time(settled ? 0.98:context.date.timeIntervalSince(began))/0.98)
        let dotX=WOriginalMotion.interpolate(t,[(0,1),(0.12,1),(0.32,0),(1,0)])
        let dotScale=WOriginalMotion.interpolate(t,[(0,0.8),(0.12,1),(0.32,0.9),(0.43,0.5),(1,0.5)])
        let dotAlpha=WOriginalMotion.interpolate(t,[(0,0),(0.12,1),(0.32,1),(0.43,0),(1,0)])
        let circleAlpha=WOriginalMotion.interpolate(t,[(0,0),(0.27,0),(0.35,1),(1,1)])
        let checkAlpha=WOriginalMotion.interpolate(t,[(0,0),(0.43,0),(0.48,1),(1,1)])
        let check=WOriginalMotion.interpolate(t,[(0,0),(0.48,0),(0.78,1),(1,1)])
        let label=WOriginalMotion.interpolate(t,[(0,0),(0.4,0),(0.82,1),(1,1)])
        HStack(spacing:13){ZStack{
            ForEach(0..<3){i in Circle().fill(W.lime).frame(width:10,height:10).scaleEffect(dotScale).offset(x:Double(i-1)*26*dotX).opacity(dotAlpha)}
            Circle().fill(W.lime).scaleEffect(WOriginalMotion.successCircle(t)).opacity(circleAlpha)
            Path{p in p.move(to:CGPoint(x:18*58/64,y:33*58/64));p.addLine(to:CGPoint(x:28*58/64,y:43*58/64));p.addLine(to:CGPoint(x:47*58/64,y:23*58/64))}.trim(from:0,to:check).stroke(MovTokens.onBrand,style:StrokeStyle(lineWidth:5*58/64,lineCap:.round,lineJoin:.round)).opacity(checkAlpha)
        }.frame(width:58,height:58)
            Text("기기에 저장했어요").font(W.font(14,.semibold)).frame(height:22.4).opacity(label).offset(y:8*(1-label))
        }.frame(minHeight:64).accessibilityElement(children:.combine)
    }.task{began=Date();settled=false;do{try await Task.sleep(for:.milliseconds(980));settled=true}catch{}}}
}

extension WireframeRoot {
    func zeroCompletionNotice(_ record:RunRecord)->String {
        let parts=record.segments ?? [];let names=["gps-gap":"GPS 누락","pause":"일시정지","vehicle":"차량 이동","transit":"대중교통","gps-spike":"GPS 튐","long-idle":"오랜 정지","unknown":"판별 정보 없음"]
        var reasons:[String]=[];for part in parts where part.type != "include" {let name=names[part.type] ?? "판별 정보 없음";if !reasons.contains(name){reasons.append(name)}}
        let reason=reasons.isEmpty ? "아직 확인된 유효 러닝 구간이 없어요.":"제외 또는 미확인 구간: "+reasons.joined(separator:" · ")+"."
        return "기기에 저장했어요. "+reason+"\n원본 타이머 시간 "+RunRecord.clock(record.seconds)+"은 참고 정보로 보관했어요. 유효 러닝 시간과는 달라요."
    }
    func recordWhen(_ record:RunRecord)->String{let f=DateFormatter();f.locale=Locale(identifier:"ko_KR");f.timeZone=TimeZone(secondsFromGMT:9*3600);f.dateFormat="yyyy.MM.dd · HH:mm";return f.string(from:record.date)+" 시작"}
}

// Original HTML recordEditButton SVG, translated without a substitute SF Symbol.
struct WRecordEditIcon:Shape {
    func path(in rect:CGRect)->Path {
        var p=Path();p.move(to:CGPoint(x:16.5,y:3.5));p.addLine(to:CGPoint(x:20.5,y:7.5))
        p.move(to:CGPoint(x:4,y:20));p.addLine(to:CGPoint(x:8.6,y:19));p.addLine(to:CGPoint(x:20.6,y:7))
        p.addArc(center:CGPoint(x:18.6,y:5),radius:CGFloat(8).squareRoot(),startAngle:.degrees(45),endAngle:.degrees(225),clockwise:true)
        p.addLine(to:CGPoint(x:4.6,y:15));p.addLine(to:CGPoint(x:4,y:20));p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX:rect.width/24,y:rect.height/24))
    }
}

// One shared progress drives both the panel and the map camera. No scrolling content.
private struct WRunningViewport<Panel:View>:View {
    @Binding var collapsed:Bool
    var reduced:Bool
    var topInset:CGFloat
    var bottomInset:CGFloat
    var paused:Bool
    var screen:String
    var pause:()->Void
    @ViewBuilder var panel:(AnyView)->Panel
    @State private var drag:CGFloat=0
    private var motion:Animation?{reduced ? nil:.timingCurve(0.22,0.72,0.18,1,duration:0.6)}
    var body:some View {
        GeometryReader{g in
            let height=min(480,max(0,g.size.height-topInset-bottomInset))
            let travel=height+bottomInset
            let progress=min(1,max(0,(collapsed ? 1.0:0.0)+drag/max(1,travel)))
            let expandedTop=g.size.height-bottomInset-height
            let centerY=(expandedTop+(g.size.height-expandedTop)*progress)/2
            ZStack(alignment:.bottom){
                WMap(route:screen != "R01",controls:true,centerControl:true,failed:screen=="R07",gpsSearching:screen=="R01",gpsWeak:screen=="R03",focusUser:true,userCenterY:centerY,centerControlBottomInset:bottomInset+height*(1-progress)+68*progress,controlsTopInset:topInset,backgroundTap:{guard !collapsed else{return};withAnimation(motion){drag=0;collapsed=true}})
                panel(AnyView(handle(compact:false,travel:travel))).frame(height:height)
                    .background(W.paper,in:UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24))
                    .padding(.bottom,bottomInset).background(alignment:.bottom){W.paper.frame(height:bottomInset)}
                    .offset(y:progress*travel).accessibilityElement(children:.contain).accessibilityHidden(collapsed).allowsHitTesting(!collapsed)
                HStack(spacing:8){handle(compact:true,travel:travel);Button(paused ? "계속 달리기":"Ⅱ 일시정지",action:pause).font(W.font(14,.semibold)).padding(.horizontal,14).frame(minHeight:44).background(W.lime,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(MovTokens.onBrand).accessibilityIdentifier(collapsed ? (paused ? "resumeRun":"pauseRun"):"inactiveCompactPause").accessibilityHidden(!collapsed)}
                    .padding(8).background(W.paper,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(W.border)).shadow(color:.black.opacity(0.12),radius:8,y:3)
                    .padding(.bottom,bottomInset+12).offset(y:(1-progress)*(bottomInset+84)).opacity(progress)
                    .accessibilityElement(children:.contain).accessibilityHidden(!collapsed).allowsHitTesting(collapsed)
            }.accessibilityElement(children:.contain).accessibilityIdentifier("runViewport")
        }
    }
    private func handle(compact:Bool,travel:CGFloat)->some View {
        Button{withAnimation(motion){drag=0;collapsed.toggle()}}label:{Group{if compact{Image(systemName:"chevron.up").font(W.font(17,.semibold)).foregroundStyle(W.muted)}else{Capsule().fill(W.muted).frame(width:34,height:4)}}.frame(width:52,height:44).contentShape(Rectangle())}
            .accessibilityLabel(compact ? "러닝 정보 펼치기":"러닝 정보 접기").accessibilityIdentifier(compact == collapsed ? "panelHandle":"inactivePanelHandle").accessibilityHidden(compact != collapsed)
            .highPriorityGesture(DragGesture(minimumDistance:8,coordinateSpace:.global).onChanged{v in
                var transaction=Transaction();transaction.disablesAnimations=true
                withTransaction(transaction){drag=v.translation.height}
            }.onEnded{v in
                let projected=(collapsed ? travel:0)+v.translation.height+(v.predictedEndTranslation.height-v.translation.height)*0.25
                withAnimation(motion){collapsed=projected>travel*0.5;drag=0}
            })
    }
}

// Root-owned consumed IDs survive body refreshes and trips to record detail.
private struct WCompletionFeedback:View {
    let recordID:UUID
    @Binding var seen:Set<UUID>
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var visible=false
    @State private var occupying:Bool
    init(recordID:UUID,seen:Binding<Set<UUID>>){self.recordID=recordID;_seen=seen;_occupying=State(initialValue:!seen.wrappedValue.contains(recordID))}
    var body:some View {
        ZStack(alignment:.topLeading){
            Color.clear
            if visible{WSuccess().padding(.top,10).transition(.opacity).accessibilityIdentifier("saveCompletionFeedback")}
        }.frame(height:occupying ? 88:0).clipped().allowsHitTesting(false)
        .task(id:recordID){
            guard !seen.contains(recordID) else{return}
            seen.insert(recordID);visible=true
            do{try await Task.sleep(for:.milliseconds(2100))}catch{return}
            withAnimation(reduced || ProcessInfo.processInfo.arguments.contains("-wire-reduced") ? nil:.easeInOut(duration:0.45)){visible=false;occupying=false}
        }
    }
}

private struct WInlineRecordField:View {
    let value:String
    let multiline:Bool
    let save:(String)->Void
    let focus:()->Void
    @State private var editing=false
    @State private var draft=""
    @FocusState private var focused:Bool
    private var limit:Int{multiline ? 300:40}
    private var key:String{multiline ? "Memo":"Title"}
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack(alignment:.top,spacing:10){
                if multiline{Text("메모").font(W.font(14,.medium)).frame(minHeight:44)}
                else if editing{TextField("제목",text:$draft).font(W.font(20,.semibold)).padding(10).background(W.soft,in:RoundedRectangle(cornerRadius:10)).focused($focused).submitLabel(.done).onSubmit(commit).accessibilityIdentifier("inlineTitleInput")}
                else{Text(value).font(W.font(22,.semibold)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("recordTitle")}
                Spacer(minLength:0)
                Button{if editing{commit()}else{draft=value;editing=true;focused=true}}label:{
                    Group{if editing{Text("완료").font(W.font(13,.semibold))}else{WRecordEditIcon().stroke(W.ink,style:StrokeStyle(lineWidth:1.6,lineCap:.round,lineJoin:.round)).frame(width:20,height:20)}}.frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(editing && draft.count>limit).accessibilityLabel((multiline ? "메모":"제목")+(editing ? " 편집 완료":" 편집")).accessibilityIdentifier((editing ? "finish":"edit")+key)
            }
            if multiline{
                if editing{TextField("메모",text:$draft,axis:.vertical).lineLimit(6...6).font(W.font(14)).lineSpacing(6).frame(minHeight:140).padding(10).background(W.soft,in:RoundedRectangle(cornerRadius:12)).focused($focused).accessibilityIdentifier("inlineMemoInput")}
                else{Text(value.isEmpty ? "러닝의 느낌을 남겨 보세요":value).font(W.font(14)).lineSpacing(6).frame(maxWidth:.infinity,alignment:.leading).padding(16).background(W.soft,in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("recordMemo")}
            }
            if editing{Text("\(draft.count)/\(limit)").font(W.font(11)).foregroundStyle(draft.count>limit ? .red:W.muted).frame(maxWidth:.infinity,alignment:.trailing).accessibilityIdentifier("inline"+key+"Count")
                if draft.count>limit{Text("최대 \(limit)자까지 입력해 주세요.").font(W.font(12)).foregroundStyle(.red)}
            }
        }.onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardDidShowNotification)){_ in if editing && focused{focus()}}.onDisappear{editing=false;focused=false;draft=""}
    }
    private func commit(){guard editing,draft.count<=limit else{return};save(draft);focused=false;editing=false}
}

// Only inset the keyboard overlap that the enclosing custom screen has not already avoided.
private struct WRecordKeyboardViewport:ViewModifier {
    @State private var keyboardTop:CGFloat?
    func body(content:Content)->some View {
        GeometryReader{geometry in
            content.padding(.bottom,keyboardTop.map{max(0,geometry.frame(in:.global).maxY-$0)} ?? 0)
        }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillChangeFrameNotification)){note in
            keyboardTop=(note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
        }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)){_ in keyboardTop=nil}
    }
}
