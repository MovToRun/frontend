import SwiftUI

enum WReview52StatisticsFormat {
    static func kilometers(_ value:Double)->String {
        guard value.isFinite else{return "—"}
        return String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value)
    }

    static func weekDateNote(asOf date:Date,timeZone:TimeZone = .current)->String {
        var calendar=Calendar(identifier:.iso8601)
        calendar.timeZone=timeZone
        let day=calendar.dateComponents([.year,.month,.day],from:date)
        let week=calendar.dateInterval(of:.weekOfYear,for:date)!
        let end=calendar.date(byAdding:.day,value:6,to:week.start)!
        let first=calendar.dateComponents([.month,.day],from:week.start)
        let last=calendar.dateComponents([.month,.day],from:end)
        return "가상 기준일은 \(day.year!)년 \(day.month!)월 \(day.day!)일이에요.\n이번 주는 \(first.month!)월 \(first.day!)일~\(last.month!)월 \(last.day!)일 기록이에요."
    }
}

enum WReview54HomeArc {
    static let viewBoxWidth: CGFloat = 240
    static let viewBoxHeight: CGFloat = 190
    static let radius: CGFloat = 107
    static let strokeWidth: CGFloat = 11
    static let sweepDegrees: CGFloat = 220

    static func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = rect.width / viewBoxWidth
        for step in 0...88 {
            let angle=(160 + sweepDegrees * CGFloat(step) / 88) * .pi / 180
            let point=CGPoint(x:rect.minX+(120+radius*cos(angle))*scale,
                              y:rect.minY+(120+radius*sin(angle))*scale)
            if step==0 { path.move(to:point) } else { path.addLine(to:point) }
        }
        return path
    }

    static func ratio(value: Double, target: Double) -> CGFloat {
        guard value.isFinite, target.isFinite, target > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / target)))
    }

    static func progressRatio(value: Double, target: Double?) -> CGFloat {
        guard let target else { return 0 }
        return ratio(value: value, target: target)
    }

    static func dualRingSize(availableWidth: CGFloat) -> CGFloat {
        min(173, max(0, (availableWidth - 14) / 2))
    }

    static func dualRingHeight(size: CGFloat, showsOverage: Bool) -> CGFloat {
        guard showsOverage else { return 165 }
        return max(165, size * viewBoxHeight / viewBoxWidth + 8 + 14 + 18)
    }
}

private struct WReview54Arc: Shape {
    func path(in rect: CGRect) -> Path { WReview54HomeArc.path(in: rect) }
}

private struct WReview54RingVisual: View {
    let value:String
    let unit:String
    let progress:CGFloat
    let size:CGFloat
    let accessibilityTitle:String
    let accessibilityValue:String
    var reduceMotion:Bool = false
    private var lineWidth:CGFloat { WReview54HomeArc.strokeWidth * size / WReview54HomeArc.viewBoxWidth }
    var body:some View {
        ZStack {
            WReview54Arc().stroke(W.soft,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
            WReview54Arc().trim(from:0,to:progress)
                .stroke(W.lime,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
                .animation(reduceMotion ? nil:.easeOut(duration:0.32),value:progress)
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(value).font(.system(size:size<200 ? 27:48,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    .contentTransition(reduceMotion ? .identity:.opacity).animation(reduceMotion ? nil:.easeOut(duration:0.18),value:value)
                if !unit.isEmpty { Text(unit).font(.system(size:size<200 ? 12:16)).foregroundStyle(W.muted) }
            }.position(x:size/2,y:size/2)
        }
        .frame(width:size,height:size*WReview54HomeArc.viewBoxHeight/WReview54HomeArc.viewBoxWidth)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }
}

private struct WReview54HomeCTAStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(W.font(17,.semibold)).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity,minHeight:62).padding(.horizontal,12)
            .foregroundStyle(enabled ? Color(red:32/255,green:41/255,blue:37/255):W.muted)
            .background(enabled ? W.lime:W.secondary,in:RoundedRectangle(cornerRadius:17))
            .scaleEffect(configuration.isPressed && !systemMotion ? 0.988:1)
            .animation(systemMotion ? nil:.easeOut(duration:configuration.isPressed ? 0.09:0.18),value:configuration.isPressed)
    }
}

private struct WReview55GoalSelector: View {
    @State private var selected = "distance"
    let distance: Double
    let minutes: Double
    let distanceGoal: Double
    let timeGoal: Double
    let reduceMotion: Bool
    let ring: (Double, String, Double, Int, String) -> AnyView

    private func summary(_ title:String, value:Double, goal:Double, unit:String, id:String)->some View {
        let reached=value >= goal
        let percentage=WeeklyGoal.percent(value:value,goal:goal)
        let actual=unit == "km" ? "\(WReview52StatisticsFormat.kilometers(value)) km" : RunGoal.duration(Int(value))
        let target=unit == "km" ? "\(MovNumber.display(goal)) km" : RunGoal.duration(Int(goal))
        let surplus=value > goal ? (unit == "km" ? "\(MovNumber.display(value-goal)) km 더 달렸어요" : "\(RunGoal.duration(Int(value-goal))) 더 달렸어요") : ""
        return VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.firstTextBaseline,spacing:0) {
                Text(title).font(.system(size:12)).foregroundStyle(W.muted).frame(width:28,alignment:.leading).padding(.trailing,9)
                Text(actual).font(.system(size:13,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("homeSummaryActual-\(id)")
                Text(" / \(target)").font(.system(size:11)).foregroundStyle(W.muted).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("homeSummaryTarget-\(id)")
                Spacer(minLength:8)
                HStack(spacing:4) {
                    if reached { Image(systemName:"checkmark").foregroundStyle(W.lime).accessibilityHidden(true) }
                    Text("\(percentage)%").monospacedDigit()
                }.font(.system(size:11)).accessibilityIdentifier("homeSummaryPercent-\(id)")
            }
            if !surplus.isEmpty { Text(surplus).font(.system(size:10)).foregroundStyle(W.muted).padding(.leading,37).accessibilityIdentifier("homeSummaryOverage-\(id)") }
        }.padding(.vertical,8)
            .overlay(alignment:.top) { if id == "time" { W.line.frame(height:1) } }
            .accessibilityElement(children:.contain).accessibilityIdentifier("homeSummary-\(id)")
    }

    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:4) {
                selector("distance", title:"거리")
                selector("time", title:"시간")
            }
            .padding(3).background(W.soft,in:RoundedRectangle(cornerRadius:14))
            .padding(.bottom,9)
            .accessibilityElement(children:.contain)
            .accessibilityLabel("크게 볼 주간 목표")
            .accessibilityIdentifier("homeGoalSelector")
            Group {
                if selected == "time" {
                    ring(minutes,"분",timeGoal,WeeklyGoal.percent(value:minutes,goal:timeGoal),"time")
                } else {
                    ring(distance,"km",distanceGoal,WeeklyGoal.percent(value:distance,goal:distanceGoal),"distance")
                }
            }
            .frame(minHeight:190)
            VStack(spacing:0) {
                summary("거리",value:distance,goal:distanceGoal,unit:"km",id:"distance")
                summary("시간",value:minutes,goal:timeGoal,unit:"분",id:"time")
            }.padding(.top,3).padding(.bottom,3)
                .accessibilityElement(children:.contain).accessibilityLabel("두 주간 목표 요약").accessibilityIdentifier("homeGoalSummaries")
        }
        .frame(maxWidth:.infinity).padding(.top,14)
    }

    private func selector(_ kind:String,title:String)->some View {
        Button {
            selected=kind
        } label: {
            Text(title).font(.system(size:13,weight:.medium))
                .foregroundStyle(selected == kind ? Color(red:32/255,green:41/255,blue:37/255):W.muted)
                .padding(.horizontal,17).frame(minWidth:76,minHeight:44)
                .background(selected == kind ? W.lime:Color.clear,in:RoundedRectangle(cornerRadius:11))
                .contentShape(RoundedRectangle(cornerRadius:11))
                .animation(reduceMotion ? nil:.easeOut(duration:0.18),value:selected)
        }.buttonStyle(.plain).accessibilityIdentifier("homeGoalSelector-\(kind)")
            .accessibilityAddTraits(selected == kind ? .isSelected:[])
    }
}

extension WireframeRoot {
    var home:some View {
        VStack(spacing:0){
            rootHeader("")
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    Text(homeWeekLabel).font(W.font(11)).foregroundStyle(W.muted).padding(.bottom,10)
                    HStack(alignment:.top,spacing:10) {
                        Text("이번 주,\n이만큼 달렸어요")
                            .font(W.font(25,.semibold)).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                            .accessibilityIdentifier("homeWeeklyHeading")
                        Spacer(minLength:4)
                        Button("요약 보기"){go("H07")}.font(W.font(11)).foregroundStyle(W.muted)
                            .frame(minHeight:44,alignment:.top).padding(.top,2).accessibilityIdentifier("homeWeeklySummary")
                    }
                    homeRings
                    Button { go("H01") } label: {
                        HStack(spacing:9) {
                            AssetIcon(name:"run",size:23)
                            Text("달리러 가기").font(W.font(17,.semibold))
                        }
                    }.buttonStyle(WReview54HomeCTAStyle()).accessibilityIdentifier("homeStartRun")
                        .padding(.top,0)
                    W.line.frame(height:1).padding(.top,25).padding(.bottom,16)
                    HStack { Text("최근 기록").font(W.font(17,.semibold)); Spacer(); Button("전체 보기"){go("L01")}.font(W.font(12)) }
                    if let r=store.records.first(where:{$0.isValid}) {
                        homeRecentRecord(r).padding(.top,7)
                    } else {
                        VStack(alignment:.leading,spacing:5) {
                            Text("아직 러닝 기록이 없어요").font(W.font(15,.medium))
                            WText(text:"첫 달리기를 시작해 보세요",small:true)
                        }.padding(.vertical,18)
                    }
                }.padding(.horizontal,22).padding(.top,8).padding(.bottom,24)
            }
        }
    }
    var homeWeekLabel:String {
        let date=WReviewClock.now
        var calendar=Calendar(identifier:.iso8601);calendar.timeZone = .current
        guard let interval=calendar.dateInterval(of:.weekOfYear,for:date),
              let last=calendar.date(byAdding:.day,value:6,to:interval.start) else { return "이번 주" }
        let firstParts=calendar.dateComponents([.month,.day],from:interval.start)
        let lastParts=calendar.dateComponents([.month,.day],from:last)
        let example=ProcessInfo.processInfo.arguments.contains("-wire-capture-viewport") ? " · 가상 예시":""
        return "\(firstParts.month!).\(firstParts.day!) — \(lastParts.month!).\(lastParts.day!)\(example)"
    }
    func homeRecentRecord(_ record:RunRecord)->some View {
        let validSeconds=record.segments?.filter{$0.type=="include"}.reduce(0){$0+$1.seconds} ?? record.seconds
        return Button { ui.openRecord(record) } label: {
            HStack(spacing:10) {
                VStack(alignment:.leading,spacing:5) {
                    Text(record.title).font(W.font(14,.medium)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("homeRecentTitle")
                    HStack(alignment:.firstTextBaseline,spacing:4) {
                        Text(MovNumber.display(record.kilometers)).font(W.font(19,.semibold)).monospacedDigit()
                        Text("km").font(W.font(13))
                    }.accessibilityIdentifier("homeRecentDistance")
                    Text("\(recordWhen(record)) · \(RunRecord.clock(validSeconds)) 유효 러닝\(record.isExample == true ? " · 예시":"")")
                        .font(W.font(10)).foregroundStyle(W.muted).lineLimit(1).accessibilityIdentifier("homeRecentMetadata")
                }
                Spacer(minLength:6)
                Image(systemName:"arrow.right").font(W.font(13)).foregroundStyle(W.muted)
            }.frame(maxWidth:.infinity,minHeight:70,alignment:.leading).padding(.vertical,7).contentShape(Rectangle())
        }.buttonStyle(.plain).overlay(alignment:.bottom){W.line.frame(height:1)}
            .accessibilityIdentifier("homeRecentRecord")
    }
    var homeRings:some View {
        let distance=store.weeklyDistance
        let seconds=store.weeklySeconds
        let distanceGoal=store.weekly.distanceEnabled ? Double(store.weekly.kilometers):nil
        let timeGoal=store.weekly.timeEnabled ? Double(store.weekly.minutes):nil
        return VStack(spacing:0) {
            if distanceGoal == nil && timeGoal == nil {
                homeRing(value:distance,unit:"km",target:nil,percent:nil,identifier:"distance")
                Button("주간 목표 설정 하기"){go("H04")}.font(W.font(13,.medium)).padding(.top,8).frame(minHeight:44)
                WText(text:"이번 주 달린 거리",small:true).padding(.top,3)
            } else {
                if let distanceGoal,let timeGoal {
                    WReview55GoalSelector(distance:distance,minutes:seconds/60,distanceGoal:distanceGoal,timeGoal:timeGoal,reduceMotion:reduceMotion,ring:{value,unit,target,percent,identifier in
                        AnyView(homeRing(value:value,unit:unit,target:target,percent:percent,identifier:identifier,reduceMotion:reduceMotion,stableReview55Slots:true))
                    })
                } else if let target=distanceGoal {
                    homeRing(value:distance,unit:"km",target:target,percent:WeeklyGoal.percent(value:distance,goal:target),identifier:"distance")
                } else if let target=timeGoal {
                    homeRing(value:seconds/60,unit:"분",target:target,percent:WeeklyGoal.percent(value:seconds/60,goal:target),identifier:"time")
                }
                Button("주간 목표 변경"){go("H04")}.font(W.font(13,.medium)).frame(minHeight:44).accessibilityIdentifier("homeEditWeeklyGoal")
            }
        }.frame(maxWidth:.infinity).padding(.top,14).accessibilityElement(children:.contain).accessibilityIdentifier("homeWeeklyRings")
    }
    func homeRing(value:Double,unit:String,target:Double?,percent:Int?,identifier:String,size:CGFloat=220,reduceMotion:Bool=false,stableReview55Slots:Bool=false)->some View {
        let displayed=unit=="km" ? WReview52StatisticsFormat.kilometers(value):RunGoal.duration(Int(value))
        let targetText=target.map{unit=="km" ? MovNumber.display($0):RunGoal.duration(Int($0))} ?? ""
        let progressDescription:String
        if target != nil {
            if unit=="km" {
                progressDescription="\(displayed) km / \(targetText) km · \(percent ?? 0)%"
            } else {
                progressDescription="\(displayed) / \(targetText) · \(percent ?? 0)%"
            }
        } else {
            progressDescription=unit=="km" ? "\(displayed) km":displayed
        }
        return VStack(spacing:0) {
            WReview54RingVisual(value:displayed,unit:unit=="km" ? "km":"",progress:WReview54HomeArc.progressRatio(value:value,target:target),size:size,accessibilityTitle:target == nil ? "이번 주 달린 거리":"주간 \(unit=="km" ? "거리":"시간") 목표 진행률",accessibilityValue:progressDescription,reduceMotion:reduceMotion)
            .accessibilityIdentifier("homeRing-\(identifier)")
            if let target,let percent {
                HStack(spacing:6) {
                    Text(unit=="km" ? "목표 \(targetText) km":"목표 \(targetText)").accessibilityIdentifier("homeRingTarget-\(identifier)")
                    Text("·")
                    Text("\(percent)%").accessibilityIdentifier("homeRingPercent-\(identifier)")
                    if value>=target { Image(systemName:"checkmark.circle.fill").foregroundStyle(W.lime).accessibilityHidden(true) }
                }.font(.system(size:size<200 ? 10:12)).foregroundStyle(W.muted).padding(.top,8)
                if stableReview55Slots {
                    Text(value>target ? (unit=="km" ? "\(MovNumber.display(value-target)) km 더 달렸어요":"\(RunGoal.duration(Int(value-target))) 더 달렸어요"):"")
                        .font(.system(size:12)).foregroundStyle(W.muted).frame(height:18,alignment:.leading).padding(.top,3)
                        .accessibilityIdentifier("homeRingOverage-\(identifier)")
                    Text("").font(.system(size:11)).frame(height:18,alignment:.leading)
                        .accessibilityIdentifier("homeAvailability-\(identifier)")
                } else if value>target {
                    Text(unit=="km" ? "\(MovNumber.display(value-target)) km 더 달렸어요":"\(RunGoal.duration(Int(value-target))) 더 달렸어요")
                        .font(.system(size:size<200 ? 10:12)).foregroundStyle(W.muted).padding(.top,6)
                        .accessibilityIdentifier("homeRingOverage-\(identifier)")
                }
            }
        }.frame(maxWidth:.infinity).accessibilityElement(children:.contain).accessibilityIdentifier("homeRingMetric-\(identifier)")
    }
    var weeklySummary:some View {
        VStack(alignment:.leading,spacing:18){
            if store.weekly.distanceEnabled{progress("거리 목표",value:store.weeklyDistance,goal:Double(store.weekly.kilometers),unit:"km")}
            if store.weekly.timeEnabled{progress("시간 목표",value:store.weeklySeconds/60,goal:Double(store.weekly.minutes),unit:"분")}
            if !store.weekly.distanceEnabled && !store.weekly.timeEnabled{WText(text:"아직 주간 목표가 없어요",small:true)}
            Button("주간 목표 변경"){go("H04")}.font(W.font(12,.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.trailing)
        }
    }
    func progress(_ label:String,value:Double,goal:Double,unit:String)->some View {
        VStack(alignment:.leading,spacing:12){HStack{WText(text:label,small:true);Spacer();Text("\(WeeklyGoal.percent(value:value,goal:goal))%").font(W.font(14)).accessibilityIdentifier("goal-percent-\(label)")}
            HStack(alignment:.firstTextBaseline,spacing:3){Text(unit=="분" ? RunGoal.duration(Int(value)):MovNumber.display(value)).font(W.font(unit=="분" ? 26:36,.semibold));Text(unit=="분" ? " / "+RunGoal.duration(Int(goal)):" / \(MovNumber.display(goal)) \(unit)").font(W.font(13))}
            GeometryReader{g in ZStack(alignment:.leading){Capsule().fill(W.secondary);Capsule().fill(W.lime).frame(width:g.size.width*min(1,max(0,value/max(1,goal))))}}.frame(height:5)
                .accessibilityElement(children:.ignore).accessibilityLabel("\(label) 진행률")
                .accessibilityValue("\(min(100,max(0,WeeklyGoal.percent(value:value,goal:goal))))%")
                .accessibilityIdentifier("goal-progress-\(label)")
            if value>goal{WText(text:"\(MovNumber.display(value-goal)) \(unit) 더 달렸어요",small:true).accessibilityIdentifier("goal-overage-\(label)")}
        }
    }
    var ready:some View {
        VStack(spacing:0){rootHeader("러닝",run:true);GeometryReader{g in ZStack(alignment:.bottom){WMap(controls:true,gpsWaiting:true)
            VStack(alignment:.leading,spacing:16){Capsule().fill(W.border).frame(width:32,height:4).frame(maxWidth:.infinity).padding(.bottom,10)
                Text(ui.screen=="H05" ? "러닝이 이어지고 있어요":"오늘의 러닝").font(W.font(24,.bold))
                if ui.screen=="H02"{WText(text:"첫 러닝을 시작해 보세요")}
                Button{go("H03")}label:{HStack{VStack(alignment:.leading,spacing:6){WText(text:"이번 러닝",small:true);Text(store.goal.summary).font(W.font(14,.medium))};Spacer();Text(store.goal.kind == .none ? "목표 설정":"목표 변경").font(W.font(12))}.padding(16).background(W.soft,in:RoundedRectangle(cornerRadius:12))}
                Button(store.session==nil ? "러닝 시작":"러닝으로 돌아가기"){if store.session==nil{store.start(weight:Double(ui.profile.weight));go("R01")}else{go(store.session?.paused == true ? "R04":"R02")}}.buttonStyle(WButtonStyle()).accessibilityIdentifier("startRun")
                runWeeklySummary
            }.padding(.horizontal,24).padding(.top,11).padding(.bottom,32).background(W.paper,in:UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24)).frame(maxHeight:g.size.height,alignment:.bottom)
        }}}
    }
    var runWeeklySummary:some View {VStack(alignment:.leading,spacing:12){
        if store.weekly.distanceEnabled{compactProgress("이번 주 거리 목표",value:store.weeklyDistance,goal:store.weekly.kilometers,unit:"km")}
        if store.weekly.timeEnabled{compactProgress("이번 주 시간 목표",value:store.weeklySeconds/60,goal:Double(store.weekly.minutes),unit:"분")}
        HStack{Button("요약 보기"){go("H07")};Spacer();Button("주간 목표 변경"){go("H04")}}.font(W.font(12)).frame(minHeight:44)
    }.padding(.top,16)}
    func compactProgress(_ title:String,value:Double,goal:Double,unit:String)->some View {VStack(alignment:.leading,spacing:8){HStack{WText(text:title,small:true);Spacer();Text("\(WeeklyGoal.percent(value:value,goal:goal))%").font(W.font(14))};(Text(unit=="분" ? RunGoal.duration(Int(value)):MovNumber.display(value)).font(W.font(18,.semibold))+Text(unit=="분" ? " / "+RunGoal.duration(Int(goal)):" / \(MovNumber.display(goal)) \(unit)").font(W.font(14))).foregroundStyle(W.ink);GeometryReader{g in ZStack(alignment:.leading){Capsule().fill(W.secondary);Capsule().fill(W.lime).frame(width:g.size.width*min(1,max(0,value/max(1,goal))))}}.frame(height:5)}}
    var sessionGoal:some View {
        WPage(title:"이번 러닝 목표",back:back){
            Text("오늘은 어떻게\n달릴까요?").font(W.font(27,.bold)).kerning(-0.945).lineSpacing(5).fixedSize(horizontal:false,vertical:true).padding(.top,12).padding(.bottom,3)
            VStack(spacing:10){ForEach(GoalKind.allCases,id:\.self){kind in
                Button{withAnimation(reduceMotion ? nil:.easeOut(duration:0.16)){ui.goal.kind=kind}}label:{
                    VStack(alignment:.leading,spacing:6){Text(kind.title).font(W.font(15,.medium)).frame(height:19.5);Text(kind == .none ? "거리와 시간에 얽매이지 않아요":kind == .distance ? "원하는 거리를 달려요":"정한 시간만큼 달려요").font(W.font(12,.medium)).frame(height:16.8)}
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,17).frame(height:76)
                        .foregroundStyle(ui.goal.kind==kind ? MovTokens.onBrand:W.ink).background(ui.goal.kind==kind ? W.lime:W.soft,in:RoundedRectangle(cornerRadius:16))
                }.buttonStyle(.plain).accessibilityIdentifier("goal-"+kind.rawValue).accessibilityAddTraits(ui.goal.kind==kind ? .isSelected:[])
            }}
            if ui.goal.kind != .none{
                VStack(spacing:10){
                    HStack(spacing:10){Text(ui.goal.kind == .time ? "시간 목표":"거리 목표").font(W.font(14,.medium));Text("목표에 도달해도 자동으로 종료하지 않아요.").font(W.font(11)).foregroundStyle(Color.wire(0x535353,0xD0D0D0));Spacer(minLength:0)}.frame(height:21)
                    if ui.goal.kind == .distance{WGoalWheel(values:Array(2...1000),selection:Binding(get:{Int((ui.goal.kilometers*2).rounded())},set:{ui.goal.kilometers=Double($0)/2}))}
                    else{WGoalWheel(values:Array(stride(from:10,through:360,by:10)),selection:$ui.goal.minutes,time:true)}
                }.padding(.top,2).transition(.opacity)
            }
        } actions:{Button("이 목표로 달리기"){store.goal=ui.goal;store.persist();back()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("saveGoal")}
    }
    var weeklyGoal:some View {
        WPage(title:"이번 주 목표",back:back){WHeading(text:"차곡차곡,\n나만의 목표로").padding(.top,8);WText(text:"거리나 시간을 선택해 보세요.\n둘 다 선택하면 각각 채워져요.")
            VStack(spacing:14){weeklyEditor(time:false);weeklyEditor(time:true)}.padding(.top,16);if !ui.error.isEmpty{WNotice(text:ui.error,danger:true)}
            WText(text:"월요일부터 일요일까지 유효 러닝만 합산해요.\n일시정지와 제외 구간은 더하지 않아요.\n이번 러닝 1회의 목표와는 별도로 관리해요.",small:true).padding(.top,8)
            Button("주간 목표 삭제"){go("H10")}.font(W.font(13)).frame(minHeight:44)
        } actions:{Button("목표 저장"){guard (!ui.weekly.distanceEnabled || (1...500).contains(ui.weekly.kilometers)), (!ui.weekly.timeEnabled || ((10...6000).contains(ui.weekly.minutes) && ui.weekly.minutes % 10 == 0)) else {ui.error="거리 1–500 km, 시간 10분 단위·최대 100시간으로 입력해 주세요.";return};store.weekly=ui.weekly;store.persist();back()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("saveWeeklyGoal")}
    }
    func weeklyEditor(time:Bool)->some View {
        let enabled=time ? ui.weekly.timeEnabled:ui.weekly.distanceEnabled
        let value=time ? Double(ui.weekly.minutes):ui.weekly.kilometers
        let maxValue=time ? 6000.0:500.0
        return VStack(alignment:.leading,spacing:0){
            Button{withAnimation(reduceMotion ? nil:.easeOut(duration:0.14)){if time{ui.weekly.timeEnabled.toggle()}else{ui.weekly.distanceEnabled.toggle()}}}label:{HStack{VStack(alignment:.leading,spacing:5){Text(time ? "시간 목표":"거리 목표").font(W.font(16,.semibold));Text(time ? "유효 러닝 시간으로 채워요":"달린 유효 거리로 채워요").font(W.font(12)).foregroundStyle(enabled ? MovTokens.onBrand.opacity(0.72):W.muted)};Spacer();WCheck().stroke(enabled ? MovTokens.onBrand:W.border,style:StrokeStyle(lineWidth:1.7,lineCap:.round,lineJoin:.round)).frame(width:24,height:24).frame(width:28,height:28)}.foregroundStyle(enabled ? MovTokens.onBrand:W.ink).padding(16).frame(minHeight:80).background(enabled ? W.lime:W.soft)}.accessibilityIdentifier(time ? "weeklyTimeToggle":"weeklyDistanceToggle").accessibilityAddTraits(enabled ? .isSelected:[]).accessibilityRemoveTraits(enabled ? []:.isSelected).accessibilityValue(enabled ? "선택됨":"선택 안 됨")
            if enabled{VStack(alignment:.leading,spacing:10){Text(time ? "주간 시간 목표":"주간 거리 목표").font(W.font(13,.medium)).frame(height:20,alignment:.leading);HStack(spacing:10){
                Button("−"){adjustWeekly(time,-(time ? 10:1))}.frame(width:48,height:54).background(W.secondary,in:RoundedRectangle(cornerRadius:10)).disabled(value <= (time ? 10:1))
                TextField("목표",value:time ? Binding(get:{Double(ui.weekly.minutes)},set:{ui.weekly.minutes=Int($0)}):$ui.weekly.kilometers,format:.number).keyboardType(time ? .numberPad:.decimalPad).multilineTextAlignment(.center).font(W.font(21,.medium)).frame(minHeight:56).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.controlBorder))
                Button("+"){adjustWeekly(time,time ? 10:1)}.frame(width:48,height:54).background(W.secondary,in:RoundedRectangle(cornerRadius:10)).disabled(value>=maxValue);Text(time ? "분":"km").font(W.font(14))}
                if time{Text(RunGoal.duration(ui.weekly.minutes)).font(W.font(18,.bold))}
                HStack(spacing:4){ForEach(time ? [30,60,180,300,600]:[1,5,10],id:\.self){n in Button{adjustWeekly(time,n)}label:{Text(time ? "+"+RunGoal.duration(n):"+\(n)km").font(W.font(12)).padding(.horizontal,7).frame(minHeight:28).background(W.soft,in:RoundedRectangle(cornerRadius:6))}.frame(minWidth:44,minHeight:44).disabled(value>=maxValue)}}
                WText(text:time ? "10분 단위 · 최대 100시간":"1~500 km · 직접 입력할 수 있어요",small:true)
            }.padding(16).padding(.bottom,4).background(W.paper).overlay(alignment:.top){W.line.frame(height:1)}}
        }.clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(enabled ? W.lime:W.border,lineWidth:1))
    }
    func adjustWeekly(_ time:Bool,_ delta:Int){if time{ui.weekly.minutes=min(6000,max(10,ui.weekly.minutes+delta))}else{ui.weekly.kilometers=min(500,max(1,ui.weekly.kilometers+Double(delta)))}}
    var periodRecords:[RunRecord] {
        if ui.screen=="H08"{return []}
        if ui.month{let range=Calendar.current.dateInterval(of:.month,for:ui.calendarMonth)!;return store.records.filter{$0.isValid && range.contains($0.date)}}
        return store.weeklyRecords
    }
    var statistics:some View {
        let summary=RunPeriodSummary(records:periodRecords)
        return WPage(title:"나의 러닝",back:back){WPeriodControl(month:$ui.month)
            WText(text:ui.month ? "월간 유효 거리":"이번 주 유효 거리",small:true)
            (Text(WReview52StatisticsFormat.kilometers(summary.kilometers)).font(W.font(48,.bold))+Text(" km").font(W.font(20,.semibold))).accessibilityIdentifier("periodDistanceValue")
            HStack(spacing:0){VStack(alignment:.leading,spacing:8){WText(text:"유효 러닝 횟수",small:true);Text("\(summary.recordCount) 회").font(W.font(24,.semibold)).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading);W.line.frame(width:1,height:48).padding(.horizontal,18).accessibilityHidden(true);VStack(alignment:.leading,spacing:8){WText(text:"유효 러닝 시간",small:true);Text(RunRecord.clock(summary.seconds)).font(W.font(24,.semibold)).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)}.accessibilityElement(children:.contain).accessibilityIdentifier("periodValidSummary")
            W.line.frame(height:1).padding(.vertical,10)
            if ui.month{WCalendar(month:$ui.calendarMonth,selected:$ui.calendarDay,records:store.records)
                if let day=ui.calendarDay{let rows=store.records.filter{Calendar.current.isDate($0.date,inSameDayAs:day)};HStack{Text("\(day.formatted(.dateTime.month().day())) 기록").font(W.font(14,.semibold)).accessibilityIdentifier("calendarSelectedDayTitle");Spacer();if !rows.isEmpty{WText(text:"\(rows.count)회",small:true).accessibilityIdentifier("calendarSelectedDayCount")}};if rows.isEmpty{WText(text:"이날은 저장된 러닝 기록이 없어요",small:true)}else{ForEach(rows){recordRow($0)}}}
            }else{Text(ui.screen=="H08" ? "아직 기록이 없어요":"이번 주 목표").font(W.font(17,.semibold));if ui.screen=="H08"{WText(text:"첫 러닝부터 채워질 거예요",small:true)};weeklySummary
                if ["H08","H09"].contains(ui.screen){WText(text:WReview52StatisticsFormat.weekDateNote(asOf:WReviewClock.now),small:true).accessibilityIdentifier("statisticsDateRange")}
                else{WText(text:"월요일부터 일요일까지의 유효 기록을 합산해요.",small:true)}
            }
        } actions:{}
    }
    var community:some View {VStack(spacing:0){WHeader(title:"커뮤니티",root:true);VStack(spacing:24){AssetIcon(name:"community",size:36).foregroundStyle(W.muted);Text("아직 준비 중이에요").font(W.font(22,.semibold));WText(text:"함께 달리는 사람들을 만나는 공간을\n준비하고 있어요.").multilineTextAlignment(.center);button("내 러닝 카드 보기","M01",kind:1).padding(.top,12)}.padding(40).frame(maxWidth:.infinity,maxHeight:.infinity)}}
}

struct WCalendar:View {
    @Binding var month:Date
    @Binding var selected:Date?
    var records:[RunRecord]
    var calendar:Calendar{Calendar.current}
    var first:Date{calendar.dateInterval(of:.month,for:month)!.start}
    var count:Int{calendar.range(of:.day,in:.month,for:month)!.count}
    var offset:Int{calendar.component(.weekday,from:first)-1}
    var runDays:Int{Set(records.filter{calendar.isDate($0.date,equalTo:month,toGranularity:.month)}.map{calendar.startOfDay(for:$0.date)}).count}
    var isReferenceMonth:Bool{calendar.isDate(month,equalTo:WReviewClock.now,toGranularity:.month)}
    var introMonth:String{isReferenceMonth ? "이번 달":"\(calendar.component(.month,from:month))월"}
    var body:some View {VStack(spacing:12){
        HStack(alignment:.firstTextBaseline,spacing:8){(Text(introMonth+" ").font(W.font(17,.medium))+Text("\(runDays)일").font(W.font(17,.bold))+Text(" 달렸어요").font(W.font(17,.medium))).accessibilityIdentifier("calendarRunDaySummary");Spacer(minLength:0);HStack(spacing:5){Circle().fill(W.lime).frame(width:4,height:4);Text("달린 날").font(W.font(11)).foregroundStyle(W.muted)}.fixedSize().accessibilityIdentifier("calendarRunDayLegend")}.padding(.bottom,5)
        HStack{Button{month=calendar.date(byAdding:.month,value:-1,to:month)!;selected=nil}label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.accessibilityLabel("이전 달");Spacer();Text(month.formatted(.dateTime.year().month())).font(W.font(17,.semibold)).accessibilityIdentifier("calendarMonthTitle");Spacer();Button{month=calendar.date(byAdding:.month,value:1,to:month)!;selected=nil}label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.accessibilityLabel("다음 달")}.padding(.bottom,8)
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:0),count:7),spacing:8){ForEach(["일","월","화","수","목","금","토"],id:\.self){Text($0).font(W.font(12)).foregroundStyle(W.muted)};ForEach(0..<(offset+count),id:\.self){index in if index<offset{Color.clear.frame(height:44)}else{let date=calendar.date(byAdding:.day,value:index-offset,to:first)!;let hasRun=records.contains{calendar.isDate($0.date,inSameDayAs:date)};Button{selected=date}label:{VStack(spacing:3){Text("\(index-offset+1)").font(W.font(14));Circle().fill(hasRun ? W.lime:.clear).frame(width:4,height:4)}.frame(maxWidth:.infinity,minHeight:44).background(selected.map{calendar.isDate($0,inSameDayAs:date)} == true ? W.secondary:Color.clear,in:RoundedRectangle(cornerRadius:8))}.accessibilityLabel(date.formatted(.dateTime.month().day())+(hasRun ? " 러닝 기록 있음":""))}}}
        if runDays==0{Text("이 달에 저장된 러닝 기록이 없어요").font(W.font(12)).foregroundStyle(W.muted).frame(maxWidth:.infinity).padding(.top,13).accessibilityIdentifier("calendarEmptyMonthMessage")}
        VStack(alignment:.leading,spacing:7){Text(selected.map{"\($0.formatted(.dateTime.month().day())) 기록"} ?? "날짜별 기록").font(W.font(14,.semibold));if selected==nil{WText(text:"날짜를 선택하면 그날의 기록을 볼 수 있어요",small:true)}}.frame(maxWidth:.infinity,alignment:.leading).padding(.top,18).overlay(alignment:.top){W.line.frame(height:1)}.accessibilityIdentifier("calendarDetailsHeading")
    }}
}

// Animate only the single selection layer; statistics/calendar updates keep their layout transaction.
struct WPeriodControl:View {
    @Binding var month:Bool
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    private var reduced:Bool{systemMotion || ProcessInfo.processInfo.arguments.contains("-wire-reduced")}
    var body:some View {
        HStack(spacing:4){ForEach([false,true],id:\.self){value in
            Button{month=value}label:{
                Text(value ? "이번 달":"이번 주").font(W.font(13))
                    .foregroundStyle(month==value ? W.ink:W.muted)
                    .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier(value ? "summary-month":"summary-week")
                .accessibilityAddTraits(month==value ? .isSelected:[])
        }}
        .background{GeometryReader{geometry in
            RoundedRectangle(cornerRadius:10).fill(W.paper)
                .frame(width:max(0,(geometry.size.width-4)/2),height:44)
                .shadow(color:W.ink.opacity(0.08),radius:2,y:1)
                .offset(x:month ? (geometry.size.width+4)/2:0)
                .animation(reduced ? nil:.easeOut(duration:0.18),value:month)
        }}
        .frame(maxWidth:.infinity,minHeight:44)
        .padding(4).background(W.soft,in:RoundedRectangle(cornerRadius:14))
    }
}
