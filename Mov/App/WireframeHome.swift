import SwiftUI

struct WCommunityComment:Identifiable {
    let id:String
    var author:String
    var authorMemberID:String?=nil
    var text:String
    let date:String
    var parentID:String?=nil
    var isDeleted=false
}

enum WCommunityCommentActions {
    static func add(_ text:String,author:String,authorMemberID:String,date:String,parentID:String?,to comments:inout [WCommunityComment])->Bool {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.count<=WCommunityTextLimit.comment,
              parentID == nil || comments.contains(where:{$0.id==parentID}) else{return false}
        comments.append(WCommunityComment(id:UUID().uuidString,author:author,authorMemberID:authorMemberID,text:value,date:date,parentID:parentID))
        return true
    }
    static func delete(_ id:String,byMemberID memberID:String,to comments:inout [WCommunityComment])->Bool {
        guard let i=comments.firstIndex(where:{$0.id==id}),comments[i].authorMemberID==memberID,!comments[i].isDeleted else{return false}
        comments[i].author=""
        comments[i].authorMemberID=nil
        comments[i].text=""
        comments[i].isDeleted=true
        return true
    }
    static func isPostAuthor(_ comment:WCommunityComment,postAuthorMemberID:String)->Bool {
        !comment.isDeleted && comment.authorMemberID == postAuthorMemberID
    }
}

struct WCommunityRunner:Identifiable,Equatable {
    let id:String
    let name:String
    let rank:String
    let introduction:String
    let region:String
    let averageDistance:Double
    let verified:Bool
}

enum WCommunityRunnerFixtures {
    static let values:[WCommunityRunner]=[
        WCommunityRunner(id:"fixture-member-ga-on",name:"가온러너",rank:"열정러너",introduction:"천천히, 멀리 함께 달려요",region:"모브시 강변",averageDistance:4.2,verified:true),
        WCommunityRunner(id:"fixture-member-no-eul",name:"노을러너",rank:"새싹러너",introduction:"퇴근 후 가볍게 달려요",region:"모브시 중앙",averageDistance:3.1,verified:false),
        WCommunityRunner(id:"fixture-member-early",name:"새벽러너",rank:"시작러너",introduction:"일찍 시작하는 하루",region:"모브시 북부",averageDistance:1.8,verified:false)
    ]
    static let baseFollowing:[(String,String)]=[
        ("fixture-member-ga-on","fixture-member-no-eul"),
        ("fixture-member-no-eul","fixture-member-ga-on"),
        ("fixture-member-early","fixture-member-ga-on"),
        ("fixture-member-ga-on","fixture-member-current")
    ]
}

struct WLocalCommunityFollowProvider {
    private(set) var viewerFollows:Set<String>=[]
    mutating func toggle(_ target:String,viewer:String,knownUsers:Set<String>)->Bool {
        guard target != viewer,knownUsers.contains(target) else{return false}
        if !viewerFollows.insert(target).inserted{viewerFollows.remove(target)}
        return true
    }
    mutating func removeFollow(_ target:String){viewerFollows.remove(target)}
    func followingIDs(for user:String,viewer:String)->Set<String> {
        var ids=Set(WCommunityRunnerFixtures.baseFollowing.filter{$0.0==user}.map{$0.1})
        if user==viewer{ids.formUnion(viewerFollows)}
        return ids
    }
    func followerIDs(for user:String,viewer:String)->Set<String> {
        var ids=Set(WCommunityRunnerFixtures.baseFollowing.filter{$0.1==user}.map{$0.0})
        if viewerFollows.contains(user){ids.insert(viewer)}
        return ids
    }
}

struct WCommunityProfileDraft:Equatable {
    var nickname:String
    var introduction:String
    var region:String
    var photo:Data?

    init(nickname:String,introduction:String,region:String,photo:Data?) {
        self.nickname=nickname;self.introduction=introduction;self.region=region;self.photo=photo
    }
    init(profile:WLocalProfile) {
        self.init(nickname:profile.nickname,introduction:profile.introduction,region:profile.region,photo:WProfilePhotoPolicy.sanitizeStored(profile.photo))
    }
    func differs(from profile:WLocalProfile)->Bool {self != WCommunityProfileDraft(profile:profile)}
}

enum WCommunityReportTarget:Equatable {
    case member(String)
    case post(String,String)
    var memberID:String {switch self{case .member(let id):return id;case .post(_,let memberID):return memberID}}
    var postID:String? {if case .post(let id,_)=self{return id};return nil}
}

struct WCommunityReport:Identifiable,Equatable {
    let id:String
    let target:WCommunityReportTarget
    let reason:String
    let detail:String
}

enum WCommunityMoreMenu:Equatable {case profile(String),post(String)}
enum WCommunityModerationDialog:Equatable {case blockProfile(String),blockPost(String,Bool),blockAfterReport(String,Bool)}

struct WLocalCommunityModerationProvider {
    static let reportReasons=["욕설·괴롭힘","스팸·광고","개인정보 노출","기타"]
    private(set) var blockedMemberIDs:Set<String>=[]
    private(set) var anonymousBlockedMemberIDs:Set<String>=[]
    private(set) var reports:[WCommunityReport]=[]

    mutating func block(_ memberID:String,viewerID:String,anonymous:Bool=false,knownUsers:Set<String>)->Bool {
        guard memberID != viewerID,knownUsers.contains(memberID) else{return false}
        guard blockedMemberIDs.insert(memberID).inserted else{return false}
        if anonymous{anonymousBlockedMemberIDs.insert(memberID)}
        return true
    }
    mutating func unblock(_ memberID:String,viewerID:String)->Bool {
        guard memberID != viewerID,blockedMemberIDs.remove(memberID) != nil else{return false}
        anonymousBlockedMemberIDs.remove(memberID)
        return true
    }
    func isBlocked(_ memberID:String)->Bool {blockedMemberIDs.contains(memberID)}
    func shouldHide(authorID:String,viewerID:String,ownerID:String)->Bool {
        guard authorID != viewerID else{return false}
        return (viewerID==ownerID && blockedMemberIDs.contains(authorID)) || (authorID==ownerID && blockedMemberIDs.contains(viewerID))
    }
    mutating func submitReport(_ target:WCommunityReportTarget,reason:String,detail:String)->Bool {
        let value=detail.trimmingCharacters(in:.whitespacesAndNewlines)
        guard Self.reportReasons.contains(reason),value.count<=300 else{return false}
        reports.append(WCommunityReport(id:UUID().uuidString,target:target,reason:reason,detail:value))
        return true
    }
}

struct WCommunityPost:Identifiable {
    let id:String
    let authorMemberID:String
    let author:String
    let rank:String
    let board:String
    var title:String
    var text:String
    let date:String
    var likes:Int
    var views:Int
    var comments:[WCommunityComment]
    var imageName:String?=nil
    var hot:Bool=false
}

enum WCommunityFixtures {
    static let boards=["러닝 인증","러닝 질문","러닝 정보·팁","러닝화·장비","대회 정보·후기","러닝 메이트 모집","크루 모집","자유게시판","연애","익명게시판"]
    static let posts:[WCommunityPost]=[
        WCommunityPost(id:"p1",authorMemberID:"fixture-member-ga-on",author:"가온러너",rank:"열정러너",board:boards[0],title:"오늘은 강변을 따라 5 km",text:"속도보다 일정한 호흡에 집중했어요. 오늘 달린 분들도 수고하셨어요.",date:"10.05 08:30",likes:24,views:138,comments:[WCommunityComment(id:"c1",author:"가온러너",authorMemberID:"fixture-member-ga-on",text:"함께 달린 기분이네요!",date:"10.05 08:42")],imageName:"CommunityRiverside",hot:true),
        WCommunityPost(id:"p2",authorMemberID:"fixture-member-no-eul",author:"노을러너",rank:"새싹러너",board:boards[1],title:"비 오는 날에는 어떻게 달리세요?",text:"가볍게 나갈지 실내에서 운동할지 고민이에요. 각자의 방법을 듣고 싶어요.",date:"10.05 08:16",likes:12,views:92,comments:[],hot:true),
        WCommunityPost(id:"p3",authorMemberID:"fixture-member-ga-on",author:"가온러너",rank:"열정러너",board:boards[6],title:"모브 강변 크루에서 함께 달려요",text:"주말 아침에 편하게 만나요. 소개와 가입 안내를 먼저 확인해 주세요.",date:"10.05 07:52",likes:8,views:64,comments:[],hot:true)
    ]
}

enum WCommunityTextLimit {
    static let title=60
    static let body=2000
    static let comment=300
    static func apply(_ text:String,limit:Int)->String{String(text.prefix(limit))}
}

/// Review-only provider. It models the server's member/post/KST-day deduplication rule in memory.
/// It is not an authoritative view counter; production counts must come from the backend response.
protocol WCommunityViewCountProvider {
    mutating func recordDetailView(viewerMemberID:String,postID:String,authorMemberID:String,date:Date)->Bool
}

struct WLocalCommunityViewCountProvider:WCommunityViewCountProvider {
    private(set) var recordedKeys:Set<String>=[]
    static let kst=TimeZone(identifier:"Asia/Seoul")!

    mutating func recordDetailView(viewerMemberID:String,postID:String,authorMemberID:String,date:Date)->Bool {
        guard !viewerMemberID.isEmpty,!postID.isEmpty,viewerMemberID != authorMemberID else{return false}
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=Self.kst
        let day=calendar.dateComponents([.year,.month,.day],from:date)
        let key="\(viewerMemberID)|\(postID)|\(day.year!)-\(day.month!)-\(day.day!)"
        return recordedKeys.insert(key).inserted
    }
}

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo:.largeTitle) private var largeValueSize:CGFloat = 48
    @ScaledMetric(relativeTo:.title3) private var compactValueSize:CGFloat = 27
    @ScaledMetric(relativeTo:.body) private var largeUnitSize:CGFloat = 16
    @ScaledMetric(relativeTo:.caption) private var compactUnitSize:CGFloat = 12
    let value:String
    let unit:String
    let progress:CGFloat
    let size:CGFloat
    let accessibilityTitle:String
    let accessibilityValue:String
    var reduceMotion:Bool = false
    private var lineWidth:CGFloat { WReview54HomeArc.strokeWidth * size / WReview54HomeArc.viewBoxWidth }
    @ViewBuilder private var centerMetric:some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing:0) {
                Text(value)
                    .font(.system(size:largeValueSize,weight:.semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.62)
                    .frame(maxWidth:size*0.9)
                    .contentTransition(reduceMotion ? .identity:.opacity).animation(reduceMotion ? nil:.easeOut(duration:0.18),value:value)
                if !unit.isEmpty {
                    Text(unit).font(.system(size:largeUnitSize)).foregroundStyle(W.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .multilineTextAlignment(.center)
            .position(x:size/2,y:size*0.47)
        } else {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(value).font(.system(size:size<200 ? compactValueSize:largeValueSize,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    .contentTransition(reduceMotion ? .identity:.opacity).animation(reduceMotion ? nil:.easeOut(duration:0.18),value:value)
                if !unit.isEmpty { Text(unit).font(.system(size:size<200 ? compactUnitSize:largeUnitSize)).foregroundStyle(W.muted) }
            }.position(x:size/2,y:size/2)
        }
    }
    var body:some View {
        ZStack {
            WReview54Arc().stroke(W.soft,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
            WReview54Arc().trim(from:0,to:progress)
                .stroke(W.lime,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
                .animation(reduceMotion ? nil:.easeOut(duration:0.32),value:progress)
            centerMetric
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo:.caption) private var summaryTitleSize:CGFloat = 12
    @ScaledMetric(relativeTo:.body) private var summaryActualSize:CGFloat = 13
    @ScaledMetric(relativeTo:.caption) private var summaryTargetSize:CGFloat = 11
    @ScaledMetric(relativeTo:.caption2) private var summaryPercentSize:CGFloat = 11
    @ScaledMetric(relativeTo:.caption2) private var summaryOverageSize:CGFloat = 10
    @ScaledMetric(relativeTo:.footnote) private var selectorTitleSize:CGFloat = 13
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
        let percent=HStack(spacing:4) {
            if reached { Image(systemName:"checkmark").foregroundStyle(W.lime).accessibilityHidden(true) }
            Text("\(percentage)%").monospacedDigit()
        }.font(.system(size:summaryPercentSize)).accessibilityIdentifier("homeSummaryPercent-\(id)")
        return VStack(alignment:.leading,spacing:0) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment:.firstTextBaseline) {
                    Text(title).font(.system(size:summaryTitleSize)).foregroundStyle(W.muted)
                    Spacer(minLength:8)
                    percent
                }
                Text(actual).font(.system(size:summaryActualSize,weight:.medium))
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    .accessibilityIdentifier("homeSummaryActual-\(id)")
                Text(" / \(target)").font(.system(size:summaryTargetSize)).foregroundStyle(W.muted)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    .accessibilityIdentifier("homeSummaryTarget-\(id)")
            } else {
                HStack(alignment:.firstTextBaseline,spacing:0) {
                    Text(title).font(.system(size:summaryTitleSize)).foregroundStyle(W.muted).frame(width:28,alignment:.leading).padding(.trailing,9)
                    Text(actual).font(.system(size:summaryActualSize,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("homeSummaryActual-\(id)")
                    Text(" / \(target)").font(.system(size:summaryTargetSize)).foregroundStyle(W.muted).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("homeSummaryTarget-\(id)")
                    Spacer(minLength:8)
                    percent
                }
            }
            if !surplus.isEmpty {
                Text(surplus).font(.system(size:summaryOverageSize)).foregroundStyle(W.muted)
                    .fixedSize(horizontal:false,vertical:true).padding(.leading,dynamicTypeSize.isAccessibilitySize ? 0:37)
                    .accessibilityIdentifier("homeSummaryOverage-\(id)")
            }
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
            Text(title).font(.system(size:selectorTitleSize,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                .foregroundStyle(selected == kind ? Color(red:32/255,green:41/255,blue:37/255):W.muted)
                .padding(.horizontal,17).frame(minWidth:76,minHeight:44)
                .background(selected == kind ? W.lime:Color.clear,in:RoundedRectangle(cornerRadius:11))
                .contentShape(RoundedRectangle(cornerRadius:11))
                .animation(reduceMotion ? nil:.easeOut(duration:0.18),value:selected)
        }.buttonStyle(.plain).accessibilityIdentifier("homeGoalSelector-\(kind)")
            .accessibilityAddTraits(selected == kind ? .isSelected:[])
    }
}

private struct WReview55RingFooter: View {
    @ScaledMetric(relativeTo:.caption) private var textSize:CGFloat = 12
    @ScaledMetric(relativeTo:.caption2) private var availabilitySize:CGFloat = 11
    let targetText:String
    let percent:Int
    let identifier:String
    let overageText:String?
    let reached:Bool
    let reservesAvailability:Bool

    init(targetText:String,percent:Int,identifier:String,overageText:String?,reached:Bool,reservesAvailability:Bool,baseSize:CGFloat) {
        self.targetText=targetText
        self.percent=percent
        self.identifier=identifier
        self.overageText=overageText
        self.reached=reached
        self.reservesAvailability=reservesAvailability
        _textSize=ScaledMetric(wrappedValue:baseSize,relativeTo:.caption)
    }

    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:6) {
                Text(targetText).accessibilityIdentifier("homeRingTarget-\(identifier)")
                Text("·").accessibilityHidden(true)
                Text("\(percent)%").accessibilityIdentifier("homeRingPercent-\(identifier)")
                if reached { Image(systemName:"checkmark.circle.fill").foregroundStyle(W.lime).accessibilityHidden(true) }
            }
            .font(.system(size:textSize)).foregroundStyle(W.muted)
            .fixedSize(horizontal:false,vertical:true)
            .padding(.top,8)

            if reservesAvailability {
                Text(overageText ?? "")
                    .font(.system(size:textSize)).foregroundStyle(W.muted)
                    .fixedSize(horizontal:false,vertical:true)
                    .frame(minHeight:18,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
                    .padding(.top,3).accessibilityIdentifier("homeRingOverage-\(identifier)")
                Text("").font(.system(size:availabilitySize)).frame(height:18,alignment:.leading)
                    .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("homeAvailability-\(identifier)")
            } else if let overageText {
                Text(overageText).font(.system(size:textSize)).foregroundStyle(W.muted)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    .padding(.top,6).accessibilityIdentifier("homeRingOverage-\(identifier)")
            }
        }
        .frame(maxWidth:.infinity)
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
                let overage=value>target ? (unit=="km" ? "\(MovNumber.display(value-target)) km 더 달렸어요":"\(RunGoal.duration(Int(value-target))) 더 달렸어요"):nil
                WReview55RingFooter(targetText:unit=="km" ? "목표 \(targetText) km":"목표 \(targetText)",percent:percent,identifier:identifier,overageText:overage,reached:value>=target,reservesAvailability:stableReview55Slots,baseSize:size<200 ? 10:12)
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
    @ViewBuilder var community:some View {
        if ui.screen=="C08" && ui.communitySelectedUserID==ui.communityViewerMemberID { communityOwnProfile }
        else { communityFeed }
    }

    var communityFeed:some View {
        VStack(spacing:0){
            HStack {
                Button { go("C02") } label:{Image(systemName:"square.grid.2x2").font(.system(size:19,weight:.regular)).frame(width:44,height:44).contentShape(Rectangle())}
                    .buttonStyle(.plain).accessibilityLabel("전체 게시판").accessibilityIdentifier("communityAllBoards")
                Spacer(minLength:0)
                Button{go("C28")}label:{Image(systemName:"gearshape").font(.system(size:18,weight:.regular)).frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("커뮤니티 설정").accessibilityIdentifier("communitySettings")
                Button{openCommunityOwnProfile()}label:{Image(systemName:"person.crop.circle").font(.system(size:20,weight:.regular)).frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("내 프로필").accessibilityIdentifier("communityOpenOwnProfile")
            }
            .overlay { BrandMark(size:26).frame(width:44,height:44).accessibilityIdentifier("communityHeaderMark") }
            .padding(.horizontal,16).frame(height:64).background(W.paper)
            ScrollView {
                VStack(alignment:.leading,spacing:0){
                    HStack(spacing:9){Text("지금 많이 보는 글").font(W.font(17,.semibold));Text("HOT").font(W.font(10,.bold)).foregroundStyle(Color(red:0.92,green:0.30,blue:0.32));Spacer()}
                        .padding(.top,16).padding(.bottom,8)
                    ForEach(communityVisiblePosts.filter{$0.hot}.prefix(3)){post in
                        Button { ui.communitySelectedPostID=post.id;go("C04") } label:{
                            HStack(spacing:12){Text("\(ui.communityPosts.firstIndex(where:{$0.id==post.id}).map{$0+1} ?? 1)").font(W.font(13,.medium)).foregroundStyle(W.muted).frame(width:18);Text(post.title).font(W.font(14,.medium)).lineLimit(1);Spacer(minLength:4);Text("♡ \(post.likes + (ui.communityLikedPosts.contains(post.id) ? 1:0))").font(W.font(11)).foregroundStyle(W.muted)}
                                .frame(minHeight:44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("communityHot-\(post.id)")
                    }
                    W.line.frame(height:1).padding(.top,10)
                    HStack{Text("러너들의 이야기").font(W.font(17,.semibold));Spacer();Text("최신순").font(W.font(11)).foregroundStyle(W.muted)}.padding(.top,22).padding(.bottom,4)
                    ForEach(communityVisiblePosts){post in communityPostCard(post)}
                }.padding(.horizontal,22).padding(.bottom,28)
            }.accessibilityIdentifier("communityFeedScroll")
        }
        .background(W.paper)
        .overlay(alignment:.bottomTrailing){Button { beginCommunityCompose() } label:{Label("글쓰기",systemImage:"square.and.pencil").font(W.font(13,.medium)).padding(.horizontal,16).frame(height:46).foregroundStyle(Color(red:32/255,green:41/255,blue:37/255)).background(W.lime,in:Capsule()).shadow(color:.black.opacity(0.12),radius:8,y:3)}.buttonStyle(.plain).padding(.trailing,18).padding(.bottom,18).accessibilityIdentifier("communityCompose")}
    }

    func communityPostCard(_ post:WCommunityPost)->some View {
        let commentCount=communityVisibleComments(post).count
        return VStack(alignment:.leading,spacing:0){
            Button { openCommunityCard(for:post.authorMemberID,origin:"C01") } label:{
                HStack(spacing:10){communityAvatar(post.author);VStack(alignment:.leading,spacing:2){Text(post.author).font(W.font(13,.semibold));Text("\(post.rank) · \(post.date)").font(W.font(10)).foregroundStyle(W.muted)};Spacer();Text(post.board).font(W.font(10,.medium)).foregroundStyle(W.muted)}
                    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("communityPostAuthor-\(post.id)")
            Button { openCommunityPost(post) } label:{VStack(alignment:.leading,spacing:6){
                Text(post.title).font(W.font(16,.semibold)).foregroundStyle(W.ink).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("communityPostTitle-\(post.id)")
                Text(post.text).font(W.font(13)).foregroundStyle(W.ink).lineSpacing(4).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.bottom,8).contentShape(Rectangle()).frame(maxWidth:.infinity,alignment:.leading)}
                .buttonStyle(.plain).accessibilityIdentifier(post.author=="나" ? "communityPostOpen-local":"communityPostOpen-\(post.id)")
            if let imageName=post.imageName{Button{openCommunityPost(post)}label:{Image(imageName).resizable().scaledToFill().frame(maxWidth:.infinity).frame(height:194).clipped().clipShape(RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).padding(.top,8).accessibilityLabel("게시글 예시 사진 열기").accessibilityIdentifier("communityFeedImageOpen-\(post.id)")}
            HStack(spacing:18){
                Button { toggleCommunityLike(post.id) } label:{Label("\(post.likes + (ui.communityLikedPosts.contains(post.id) ? 1:0))",systemImage:ui.communityLikedPosts.contains(post.id) ? "heart.fill":"heart").font(W.font(11)).foregroundStyle(ui.communityLikedPosts.contains(post.id) ? Color.wire(0xE85D68,0xFF9CA3):W.muted)}
                    .accessibilityLabel("좋아요 \(post.likes + (ui.communityLikedPosts.contains(post.id) ? 1:0))").accessibilityIdentifier("communityLike-\(post.id)")
                Button { openCommunityPost(post) } label:{Label("\(commentCount)",systemImage:"bubble.right").font(W.font(11)).foregroundStyle(W.muted)}
                    .accessibilityLabel("댓글 \(commentCount)").accessibilityIdentifier("communityComments-\(post.id)")
                Button{openCommunityPost(post)}label:{Label("\(post.views)",systemImage:"eye").font(W.font(11)).foregroundStyle(W.muted).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("communityViews-\(post.id)")
            }.buttonStyle(.plain).padding(.horizontal,2).padding(.top,12).padding(.bottom,20)
        }.overlay(alignment:.bottom){W.line.frame(height:1)}
    }

    func communityAvatar(_ name:String)->some View {Text(String(name.prefix(1))).font(W.font(13,.semibold)).foregroundStyle(W.ink).frame(width:38,height:38).background(W.soft,in:Circle()).accessibilityHidden(true)}
    var communityVisiblePosts:[WCommunityPost]{ui.communityPosts.filter{communityCanSeeMember($0.authorMemberID)}}
    func communityCanSeeMember(_ memberID:String,viewerID:String?=nil)->Bool {
        !ui.communityModerationProvider.shouldHide(authorID:memberID,viewerID:viewerID ?? ui.communityViewerMemberID,ownerID:ui.communityViewerMemberID)
    }
    func communityVisibleComments(_ post:WCommunityPost)->[WCommunityComment] {
        var visible=Set<String>(),result:[WCommunityComment]=[]
        for comment in post.comments {
            if let author=comment.authorMemberID,ui.communityModerationProvider.shouldHide(authorID:author,viewerID:ui.communityViewerMemberID,ownerID:ui.communityViewerMemberID){continue}
            if let parent=comment.parentID,!visible.contains(parent){continue}
            visible.insert(comment.id);result.append(comment)
        }
        return result
    }
    func toggleCommunityLike(_ id:String){guard let post=ui.communityPosts.first(where:{$0.id==id}),communityCanSeeMember(post.authorMemberID) else{return};if ui.communityLikedPosts.contains(id){ui.communityLikedPosts.remove(id)}else{ui.communityLikedPosts.insert(id)}}
    func beginCommunityCompose(board:String?=nil){ui.communityDraftTitle="";ui.communityDraftBody="";ui.communityDraftBoard=board ?? "러닝 인증";ui.communityError="";go("C05")}
    func currentCommunityPost()->WCommunityPost?{ui.communityPosts.first{$0.id==ui.communitySelectedPostID && communityCanSeeMember($0.authorMemberID)}}
    func openCommunityPost(_ post:WCommunityPost){guard communityCanSeeMember(post.authorMemberID) else{return};ui.communitySelectedPostID=post.id;go("C04")}
    func recordCommunityDetailView(_ post:WCommunityPost){
        guard communityCanSeeMember(post.authorMemberID),let index=ui.communityPosts.firstIndex(where:{$0.id==post.id}) else{return}
        if ui.communityViewCountProvider.recordDetailView(viewerMemberID:ui.communityViewerMemberID,postID:post.id,authorMemberID:post.authorMemberID,date:Date()) {ui.communityPosts[index].views+=1}
    }
    func publishCommunityDraft(){
        let title=ui.communityDraftTitle.trimmingCharacters(in:.whitespacesAndNewlines),body=ui.communityDraftBody.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty else{ui.communityError="제목을 입력해 주세요.";return}
        guard !body.isEmpty else{ui.communityError="내용을 입력해 주세요.";return}
        guard title.count<=60,body.count<=2000 else{ui.communityError="제목은 60자, 내용은 2,000자 이내로 입력해 주세요.";return}
        ui.communityPosts.insert(WCommunityPost(id:UUID().uuidString,authorMemberID:ui.communityViewerMemberID,author:"나",rank:"시작러너",board:ui.communityDraftBoard,title:title,text:body,date:"방금 전",likes:0,views:0,comments:[]),at:0)
        ui.communityDraftTitle="";ui.communityDraftBody="";ui.communityError="";go("C01")
    }
    func submitCommunityComment(){
        guard let index=ui.communityPosts.firstIndex(where:{$0.id==ui.communitySelectedPostID}),
              WCommunityCommentActions.add(ui.communityComment,author:"나",authorMemberID:ui.communityViewerMemberID,date:"방금 전",parentID:ui.communityReplyToID,to:&ui.communityPosts[index].comments) else{ui.communityError="댓글을 입력해 주세요.";return}
        ui.communityComment="";ui.communityReplyToID=nil;ui.communityError=""
    }

    func communityCommentRow(_ comment:WCommunityComment,all:[WCommunityComment],depth:Int)->AnyView {
        let children=all.filter{$0.parentID==comment.id}
        return AnyView(VStack(alignment:.leading,spacing:0){
            VStack(alignment:.leading,spacing:6){
                if let parentID=comment.parentID,let parent=all.first(where:{$0.id==parentID}) {
                    HStack(spacing:7){Rectangle().fill(W.border).frame(width:2,height:28);Text(parent.isDeleted ? "삭제된 댓글입니다":"\(parent.author)에게 답글 · \(parent.text)").font(W.font(10)).foregroundStyle(W.muted).lineLimit(2)}
                        .accessibilityIdentifier("communityReplyQuote-\(comment.id)")
                }
                if comment.isDeleted {Text("삭제된 댓글입니다").font(W.font(13)).foregroundStyle(W.muted).italic().accessibilityIdentifier("communityCommentText-\(comment.id)")}
                else {
                    HStack(spacing:6){Text(comment.author).font(W.font(12,.semibold));if WCommunityCommentActions.isPostAuthor(comment,postAuthorMemberID:currentCommunityPost()?.authorMemberID ?? ""){Text("작성자").font(W.font(9,.medium)).padding(.horizontal,5).padding(.vertical,2).background(W.soft,in:Capsule()).accessibilityIdentifier("communityCommentAuthorBadge-\(comment.id)")};Spacer();Text(comment.date).font(W.font(10)).foregroundStyle(W.muted)}
                    Text(comment.text).font(W.font(13)).lineSpacing(4).accessibilityIdentifier("communityCommentText-\(comment.id)")
                }
                HStack(spacing:16){Button("답글"){ui.communityReplyToID=comment.id}.font(W.font(11,.medium)).accessibilityIdentifier("communityReply-\(comment.id)")
                    if comment.authorMemberID==ui.communityViewerMemberID && !comment.isDeleted {Button("삭제"){if let i=ui.communityPosts.firstIndex(where:{$0.id==ui.communitySelectedPostID}){_ = WCommunityCommentActions.delete(comment.id,byMemberID:ui.communityViewerMemberID,to:&ui.communityPosts[i].comments)}}.font(W.font(11)).foregroundStyle(W.muted).accessibilityIdentifier("communityDeleteComment-\(comment.id)")}}
            }.padding(.vertical,12).padding(.leading,depth == 0 ? 0:14)
                .overlay(alignment:.leading){if depth>0{Rectangle().fill(W.border).frame(width:1)}}
            ForEach(children){child in communityCommentRow(child,all:all,depth:depth+1)}
            W.line.frame(height:1)
        })
    }

    func communityRunner(_ id:String)->WCommunityRunner {
        if id==ui.communityViewerMemberID {
            let rank=store.totalDistance==0 ? "시작러너":store.tier=="마스터" ? "러닝마스터":store.tier=="도전" ? "도전러너":store.tier=="열정" ? "열정러너":"새싹러너"
            return WCommunityRunner(id:id,name:ui.profile.nickname,rank:rank,introduction:ui.profile.introduction,region:ui.profile.region,averageDistance:store.averageDistance,verified:false)
        }
        return WCommunityRunnerFixtures.values.first{$0.id==id} ?? WCommunityRunnerFixtures.values[0]
    }

    func communityRunnerPhoto(_ id:String)->Data? {
        id==ui.communityViewerMemberID ? WProfilePhotoPolicy.sanitizeStored(ui.profile.photo):nil
    }

    @ViewBuilder func communityRunnerAvatar(_ runner:WCommunityRunner,photo:Data?,zoomable:Bool)->some View {
        if zoomable {Button{ui.communitySelectedUserID=runner.id;go("C31")}label:{communityRunnerAvatarFace(runner,photo:photo)}.buttonStyle(.plain).accessibilityLabel("\(runner.name) 프로필 사진 확대").accessibilityIdentifier("communityCardPhotoOpen")}
        else {communityRunnerAvatarFace(runner,photo:photo)}
    }

    func communityRunnerAvatarFace(_ runner:WCommunityRunner,photo:Data?)->some View {
        Group {
            if let photo,let image=UIImage(data:photo){Image(uiImage:image).resizable().scaledToFill()}
            else{Text(String(runner.name.prefix(1))).font(W.font(18,.semibold)).foregroundStyle(W.ink)}
        }.frame(width:48,height:48).background(W.paper).clipShape(Circle()).overlay(Circle().stroke(W.line))
    }

    func communityRunnerCard(_ runner:WCommunityRunner,photo:Data?,zoomable:Bool)->some View {
        VStack(alignment:.leading,spacing:0){
            HStack{Text("러닝 카드").font(W.font(11)).foregroundStyle(W.muted);Spacer();BrandMark(size:28)}.frame(height:28)
            HStack(alignment:.center,spacing:12){
                communityRunnerAvatar(runner,photo:photo,zoomable:zoomable)
                VStack(alignment:.leading,spacing:3){
                    HStack(spacing:5){Text(runner.rank).font(W.font(11,.medium)).foregroundStyle(W.muted);if runner.verified{Image(systemName:"checkmark.seal.fill").font(.system(size:13)).foregroundStyle(Color.wire(0x2580EB,0x63A5F2)).accessibilityLabel("계정 인증 완료")}}
                    Text(runner.name).font(W.font(22,.semibold)).lineLimit(2).minimumScaleFactor(0.8).accessibilityIdentifier("communityCardName")
                }
            }.padding(.top,22).padding(.bottom,18)
            Text(runner.introduction).font(W.font(14)).lineSpacing(5).fixedSize(horizontal:false,vertical:true).padding(.bottom,14)
            Text(runner.region).font(W.font(12)).foregroundStyle(W.muted)
            W.line.frame(height:1).padding(.top,16)
            HStack(alignment:.firstTextBaseline){Text("최근 1달 평균 러닝당 거리").font(W.font(10)).foregroundStyle(W.muted);Spacer();(Text(MovNumber.display(runner.averageDistance)).font(W.font(21,.semibold))+Text(" km").font(W.font(12))).accessibilityIdentifier("communityCardAverage")}
                .padding(.top,12)
        }
        .padding(20).frame(maxWidth:.infinity,minHeight:250,alignment:.topLeading)
        .background(W.soft,in:RoundedRectangle(cornerRadius:20))
        .accessibilityElement(children:.contain).accessibilityIdentifier("communityRunnerCard")
    }

    func openCommunityCard(for userID:String,origin:String){guard communityCanSeeMember(userID) else{return};ui.communitySelectedUserID=userID;ui.communityCardOriginScreen=origin;go("C07")}
    func openCommunityOwnProfile(){ui.communitySelectedUserID=ui.communityViewerMemberID;ui.communityProfileEditing=false;go("C08")}
    func communityKnownUserIDs()->Set<String>{Set(WCommunityRunnerFixtures.values.map(\.id)+[ui.communityViewerMemberID])}
    func communityFollowingIDs(for userID:String)->[String]{ui.communityFollowProvider.followingIDs(for:userID,viewer:ui.communityViewerMemberID).filter{communityCanSeeMember($0)}.sorted()}
    func communityFollowerIDs(for userID:String)->[String]{ui.communityFollowProvider.followerIDs(for:userID,viewer:ui.communityViewerMemberID).filter{communityCanSeeMember($0)}.sorted()}
    func communityProfilePosts(for userID:String)->[WCommunityPost]{ui.communityPosts.filter{$0.authorMemberID==userID && $0.board != "익명게시판" && communityCanSeeMember($0.authorMemberID)}}
    func toggleCommunityFollow(_ userID:String){guard communityCanSeeMember(userID) else{return};_ = ui.communityFollowProvider.toggle(userID,viewer:ui.communityViewerMemberID,knownUsers:communityKnownUserIDs())}

    func beginCommunityReport(_ target:WCommunityReportTarget){
        guard communityReportTargetIsAvailable(target) else{return}
        ui.communityMoreMenu=nil;ui.communityReportTarget=target;ui.communityReportReason=WLocalCommunityModerationProvider.reportReasons[0];ui.communityReportDetail="";ui.communityReportError="";go("C23")
    }
    func communityReportTargetIsAvailable(_ target:WCommunityReportTarget)->Bool {
        let id=target.memberID
        guard id != ui.communityViewerMemberID,communityKnownUserIDs().contains(id),communityCanSeeMember(id) else{return false}
        if case .post(let postID,_)=target{return ui.communityPosts.contains(where:{$0.id==postID && $0.authorMemberID==id && communityCanSeeMember($0.authorMemberID)})}
        return true
    }
    func submitCommunityReport(){
        guard let target=ui.communityReportTarget,communityReportTargetIsAvailable(target) else{ui.communityReportError="신고할 대상을 확인할 수 없어요.";return}
        guard ui.communityReportDetail.count<=300 else{ui.communityReportError="상세 사유는 300자 이내로 입력해 주세요.";return}
        guard ui.communityModerationProvider.submitReport(target,reason:ui.communityReportReason,detail:ui.communityReportDetail) else{ui.communityReportError="신고 사유를 선택해 주세요.";return}
        let post=target.postID.flatMap{id in ui.communityPosts.first{$0.id==id}}
        ui.communityReportTarget=nil;ui.communityReportError="";go("C25")
        ui.communityModerationDialog = .blockAfterReport(target.memberID,post?.board=="익명게시판")
    }
    func confirmCommunityModerationAction(){
        guard let dialog=ui.communityModerationDialog else{return}
        ui.communityModerationDialog=nil
        switch dialog {
        case .blockProfile(let id):applyCommunityBlock(id,anonymous:false)
        case .blockPost(let id,let anonymous),.blockAfterReport(let id,let anonymous):applyCommunityBlock(id,anonymous:anonymous)
        }
    }
    func applyCommunityBlock(_ memberID:String,anonymous:Bool){
        guard ui.communityModerationProvider.block(memberID,viewerID:ui.communityViewerMemberID,anonymous:anonymous,knownUsers:communityKnownUserIDs()) else{return}
        ui.communityFollowProvider.removeFollow(memberID);ui.communityMoreMenu=nil;ui.communityReportTarget=nil;ui.communityReplyToID=nil;ui.communityComment="";ui.path=[]
        ui.screen="C01";ui.rootIndex=3;ui.previousRootIndex=3;ui.forward=false
    }
    func unblockCommunityMember(_ memberID:String){_ = ui.communityModerationProvider.unblock(memberID,viewerID:ui.communityViewerMemberID)}

    func communityProfileMetrics(_ userID:String,posts:[WCommunityPost])->some View {
        let followers=communityFollowerIDs(for:userID),following=communityFollowingIDs(for:userID)
        return HStack(spacing:0){
            VStack(spacing:7){Text("게시글").font(W.font(12)).foregroundStyle(W.muted);Text("\(posts.count)").font(W.font(18,.semibold)).accessibilityIdentifier("communityProfilePostCount")}.frame(maxWidth:.infinity,minHeight:58)
            W.line.frame(width:1,height:42)
            Button{ui.communityConnectionsKind="followers";go("C30")}label:{VStack(spacing:7){Text("팔로워").font(W.font(12)).foregroundStyle(W.muted);Text("\(followers.count)").font(W.font(18,.semibold)).accessibilityIdentifier("communityProfileFollowerCount")}.frame(maxWidth:.infinity,minHeight:58)}.buttonStyle(.plain).accessibilityIdentifier("communityProfileFollowers")
            W.line.frame(width:1,height:42)
            Button{ui.communityConnectionsKind="following";go("C30")}label:{VStack(spacing:7){Text("팔로잉").font(W.font(12)).foregroundStyle(W.muted);Text("\(following.count)").font(W.font(18,.semibold)).accessibilityIdentifier("communityProfileFollowingCount")}.frame(maxWidth:.infinity,minHeight:58)}.buttonStyle(.plain).accessibilityIdentifier("communityProfileFollowing")
        }.padding(.vertical,4)
    }

    var communityCardPreview:some View {
        let runner=communityRunner(ui.communitySelectedUserID)
        return ZStack(alignment:.bottom){
            Group {switch ui.communityCardOriginScreen{case "C04":communityPostDetail;case "C30":communityConnections;case "C08":communityRunnerProfile;default:communityFeed}}
                .accessibilityHidden(true).allowsHitTesting(false)
            Color.black.opacity(0.42).ignoresSafeArea()
            ScrollView{VStack(spacing:9){
                communityRunnerCard(runner,photo:communityRunnerPhoto(runner.id),zoomable:true)
                Button("프로필 방문"){ui.communityProfileEditing=false;go("C08")}.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityCardVisit")
                Button("닫기",action:back).buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityCardClose")
            }.padding(16).frame(maxWidth:520).frame(maxWidth:.infinity).padding(.bottom,12)}
                .frame(maxHeight:.infinity,alignment:.bottom)
                .background(W.paper,in:UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24))
                .accessibilityElement(children:.contain).accessibilityIdentifier("communityCardSheet")
        }
        .accessibilityIdentifier("communityCardPreview")
    }

    var communityRunnerProfile:some View {
        let runner=communityRunner(ui.communitySelectedUserID),posts=communityProfilePosts(for:ui.communitySelectedUserID)
        let own=runner.id==ui.communityViewerMemberID
        return VStack(spacing:0){
            WHeader(title:runner.name,back:back,trailing:own ? AnyView(EmptyView()):AnyView(Button{ui.communityMoreMenu = .profile(runner.id)}label:{Image(systemName:"ellipsis").font(.system(size:19,weight:.medium)).frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("프로필 더보기").accessibilityIdentifier("communityProfileMore")))
            ScrollView{VStack(alignment:.leading,spacing:18){
                communityRunnerCard(runner,photo:communityRunnerPhoto(runner.id),zoomable:false)
                communityProfileMetrics(runner.id,posts:posts)
                if own {
                    Button("내 정보 수정"){beginCommunityProfileEdit()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityProfileEdit")
                } else {
                    Button(ui.communityFollowProvider.viewerFollows.contains(runner.id) ? "팔로우 취소":"팔로우"){toggleCommunityFollow(runner.id)}.buttonStyle(WButtonStyle(kind:ui.communityFollowProvider.viewerFollows.contains(runner.id) ? 1:0)).accessibilityIdentifier("communityProfileFollow")
                }
                HStack{Text("작성한 글").font(W.font(17,.semibold));Spacer();Text("\(posts.count)").font(W.font(13)).foregroundStyle(W.muted)}
                if posts.isEmpty{VStack(alignment:.leading,spacing:5){Text("아직 작성한 글이 없어요").font(W.font(15,.medium))}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,20).accessibilityIdentifier("communityProfilePostsEmpty")}
                else{ForEach(posts){post in communityPostCard(post)}}
            }.padding(.horizontal,22).padding(.top,16).padding(.bottom,24)}
        }.background(W.paper).accessibilityIdentifier("communityRunnerProfile")
    }

    func beginCommunityProfileEdit(){ui.nickname=ui.profile.nickname;ui.introduction=ui.profile.introduction;ui.region=ui.profile.region;ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo);ui.error="";ui.communityProfileEditing=true}
    func communityProfileDraftHasChanges()->Bool {
        WCommunityProfileDraft(nickname:ui.nickname,introduction:ui.introduction,region:ui.region,photo:ui.photo).differs(from:ui.profile)
    }
    func saveCommunityProfileEdit(){
        guard WProfileValidation.isValid(nickname:ui.nickname,introduction:ui.introduction) else{ui.error="닉네임은 1–20자, 한 줄 소개는 60자 이내로 입력해 주세요.";return}
        ui.profile.nickname=ui.nickname.trimmingCharacters(in:.whitespacesAndNewlines);ui.profile.introduction=ui.introduction;ui.profile.region=ui.region;ui.profile.photo=ui.photo;ui.save();ui.communityProfileEditing=false;ui.error=""
    }
    var communityOwnProfile:some View {
        VStack(spacing:0){rootHeader("내 정보",settingsRoute:"C28")
            if ui.communityProfileEditing {
                ScrollView{VStack(alignment:.leading,spacing:14){Text("나를 소개하는 러닝 카드").font(W.font(20,.semibold));WAvatarEditor(data:$ui.photo).accessibilityIdentifier("communityEditPhoto");WField(label:"닉네임",text:$ui.nickname,limit:20,textSize:14,labelSize:13,secondaryLabel:"필수",accessibilityID:"communityEditNickname");WField(label:"한 줄 소개",text:$ui.introduction,placeholder:"어떤 러너인지 소개해 주세요",limit:60,multiline:true,multilineHeight:86,textSize:14,labelSize:13,secondaryLabel:"선택",accessibilityID:"communityEditIntroduction");Text("활동 지역").font(W.font(13,.medium));WRegionPicker(selection:$ui.region);if !ui.error.isEmpty{WNotice(text:ui.error,danger:true)}}.padding(22)}
                HStack(spacing:10){Button("저장하기",action:saveCommunityProfileEdit).buttonStyle(WButtonStyle()).accessibilityIdentifier("communityProfileSave");Button("취소"){requestCommunityProfileExit(destination:"stay")}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityProfileEditCancel")}.padding(.horizontal,20).padding(.vertical,12)
            } else {
                ScrollView{VStack(alignment:.leading,spacing:18){communityRunnerCard(communityRunner(ui.communityViewerMemberID),photo:communityRunnerPhoto(ui.communityViewerMemberID),zoomable:false);let posts=communityProfilePosts(for:ui.communityViewerMemberID);communityProfileMetrics(ui.communityViewerMemberID,posts:posts);Button("내 정보 수정"){beginCommunityProfileEdit()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityProfileEdit");Text("작성한 글").font(W.font(17,.semibold));if posts.isEmpty{Text("아직 작성한 글이 없어요").font(W.font(14)).foregroundStyle(W.muted).accessibilityIdentifier("communityProfilePostsEmpty")}else{ForEach(posts){post in communityPostCard(post)}}}.padding(.horizontal,22).padding(.top,16).padding(.bottom,24)}
            }
        }.background(W.paper).accessibilityElement(children:.contain).accessibilityIdentifier("communityOwnProfile")
    }

    var communityConnections:some View {
        let id=ui.communitySelectedUserID,rows=(ui.communityConnectionsKind=="followers" ? communityFollowerIDs(for:id):communityFollowingIDs(for:id)).map(communityRunner)
        return WPage(title:ui.communityConnectionsKind=="followers" ? "팔로워":"팔로잉",back:back){
            if rows.isEmpty{Text("아직 연결된 러너가 없어요").font(W.font(15,.medium)).padding(.vertical,32).accessibilityIdentifier("communityConnectionsEmpty")}
            else{ForEach(rows){runner in HStack(spacing:10){Button{openCommunityCard(for:runner.id,origin:"C30")}label:{HStack(spacing:10){communityAvatar(runner.name);Text(runner.name).font(W.font(14,.medium));Spacer()}.frame(minHeight:52)}.buttonStyle(.plain).accessibilityIdentifier("communityConnection-\(runner.id)");if runner.id != ui.communityViewerMemberID{Button(ui.communityFollowProvider.viewerFollows.contains(runner.id) ? "팔로우 취소":"팔로우"){toggleCommunityFollow(runner.id)}.font(W.font(12,.medium)).accessibilityIdentifier("communityConnectionFollow-\(runner.id)")}}.overlay(alignment:.bottom){W.line.frame(height:1)}}}
        }actions:{}
    }

    var communityPhotoViewer:some View {
        let runner=communityRunner(ui.communitySelectedUserID),photo=communityRunnerPhoto(ui.communitySelectedUserID).flatMap(UIImage.init(data:))
        return ZStack{Color.black.opacity(0.52).ignoresSafeArea();VStack(spacing:14){HStack{Spacer();Button("닫기",action:back).font(W.font(13,.medium)).frame(minWidth:52,minHeight:44).accessibilityIdentifier("communityPhotoClose")}.padding(.horizontal,12)
            if let photo{Image(uiImage:photo).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:430).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityLabel("\(runner.name) 프로필 사진").accessibilityIdentifier("communityPhotoImage")}
            else{VStack(spacing:12){communityAvatar(runner.name).frame(width:70,height:70);Text("등록된 사진이 없어요").font(W.font(13)).foregroundStyle(W.muted)}.frame(maxWidth:.infinity,minHeight:180).accessibilityIdentifier("communityPhotoEmpty")}
        }.padding(12).background(W.paper,in:RoundedRectangle(cornerRadius:18)).padding(18)}.accessibilityElement(children:.contain).accessibilityIdentifier("communityPhotoViewer")
    }

    var communityReport:some View {
        WPage(title:"신고",back:back){
            Text("어떤 문제가 있나요?").font(W.font(20,.semibold)).accessibilityIdentifier("communityReportHeading")
            Picker("신고 사유",selection:$ui.communityReportReason){ForEach(WLocalCommunityModerationProvider.reportReasons,id:\.self){Text($0).tag($0)}}.pickerStyle(.inline).labelsHidden().accessibilityIdentifier("communityReportReason")
            VStack(alignment:.leading,spacing:8){Text("상세 사유 (선택)").font(W.font(14,.medium));TextEditor(text:$ui.communityReportDetail).font(W.font(14)).scrollContentBackground(.hidden).frame(minHeight:120).padding(8).background(W.soft,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("communityReportDetail");Text("\(ui.communityReportDetail.count)/300").font(W.font(11)).foregroundStyle(W.muted).frame(maxWidth:.infinity,alignment:.trailing)}
            if !ui.communityReportError.isEmpty{WNotice(text:ui.communityReportError,danger:true)}
        }actions:{
            Button("신고 접수"){submitCommunityReport()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityReportSubmit")
            Button("취소"){ui.communityReportTarget=nil;back()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityReportCancel")
        }.onChange(of:ui.communityReportDetail){_,value in let limited=WCommunityTextLimit.apply(value,limit:300);if limited != value{ui.communityReportDetail=limited}}
    }

    var communityReportReceipt:some View {
        WPage(title:"신고",back:back){VStack(alignment:.leading,spacing:12){Text("신고가 접수됐어요").font(W.font(21,.semibold));Text("보내주신 내용을 확인할게요.").font(W.font(14)).foregroundStyle(W.muted)}.accessibilityIdentifier("communityReportReceipt")}
        actions:{Button("커뮤니티로 돌아가기"){ui.communityModerationDialog=nil;go("C01");ui.path=[]}.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityReportDone")}
    }

    var communitySettings:some View {
        WPage(title:"커뮤니티 설정",back:back){
            WRow(title:"차단한 사용자",action:{go("C42")},height:58,arrow:true).accessibilityIdentifier("communityBlockedUsersRow")
        }actions:{}
    }

    var communityBlockedUsers:some View {
        let ids=ui.communityModerationProvider.blockedMemberIDs.sorted()
        return WPage(title:"차단한 사용자",back:back){
            if ids.isEmpty {Text("차단한 사용자가 없어요").font(W.font(15,.medium)).foregroundStyle(W.muted).frame(maxWidth:.infinity).padding(.vertical,36).accessibilityIdentifier("communityBlockedUsersEmpty")}
            else {ForEach(ids,id:\.self){id in
                let anonymous=ui.communityModerationProvider.anonymousBlockedMemberIDs.contains(id),runner=communityRunner(id)
                HStack(spacing:12){if anonymous{communityAvatar("차단한 사용자")}else{communityAvatar(runner.name)};VStack(alignment:.leading,spacing:4){Text(anonymous ? "차단한 사용자":"\(runner.name)").font(W.font(14,.medium));if anonymous{Text("익명으로 차단한 사용자예요").font(W.font(11)).foregroundStyle(W.muted)}};Spacer();Button("차단 해제"){unblockCommunityMember(id)}.font(W.font(12,.medium)).accessibilityIdentifier("communityUnblock-\(id)")}.frame(minHeight:64).overlay(alignment:.bottom){W.line.frame(height:1)}
            }}
        }actions:{}
    }

    func communityModerationMenu(_ menu:WCommunityMoreMenu)->some View {
        ZStack(alignment:.topTrailing){Color.black.opacity(0.18).ignoresSafeArea().onTapGesture{ui.communityMoreMenu=nil}
            VStack(spacing:0){
                let isPost:Bool={if case .post=menu{return true};return false}()
                Button{ui.communityMoreMenu=nil;beginCommunityReport(isPost ? .post(menuID(menu),communityPostAuthorID(menuID(menu))):.member(menuID(menu)))}label:{Label("신고",systemImage:"exclamationmark.bubble").font(W.font(14,.medium)).frame(maxWidth:.infinity,minHeight:48,alignment:.leading).padding(.horizontal,14)}.buttonStyle(.plain).accessibilityIdentifier(isPost ? "communityMenuReportPost":"communityMenuReportProfile")
                Button{ui.communityMoreMenu=nil;ui.communityModerationDialog=isPost ? .blockPost(communityPostAuthorID(menuID(menu)),ui.communityPosts.first(where:{$0.id==menuID(menu)})?.board=="익명게시판"):.blockProfile(menuID(menu))}label:{Label("차단",systemImage:"hand.raised").font(W.font(14,.medium)).foregroundStyle(Color.wire(0xC83E49,0xFF8C95)).frame(maxWidth:.infinity,minHeight:48,alignment:.leading).padding(.horizontal,14)}.buttonStyle(.plain).accessibilityIdentifier(isPost ? "communityMenuBlockPost":"communityMenuBlockProfile")
                Button{ui.communityMoreMenu=nil}label:{Text("닫기").font(W.font(13)).foregroundStyle(W.muted).frame(maxWidth:.infinity,minHeight:42)}.buttonStyle(.plain).accessibilityIdentifier("communityMenuClose")
            }.frame(width:210).background(W.paper,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(W.line,lineWidth:1)).shadow(color:.black.opacity(0.15),radius:18,y:6).padding(.top,56).padding(.trailing,12)
        }
    }
    func menuID(_ menu:WCommunityMoreMenu)->String{switch menu{case .profile(let id):id;case .post(let id):id}}
    func communityPostAuthorID(_ postID:String)->String{ui.communityPosts.first(where:{$0.id==postID})?.authorMemberID ?? ""}

    func communityModerationDialogView(_ dialog:WCommunityModerationDialog)->some View {
        let title:String,body:String,skip:String
        switch dialog{case .blockProfile:title="이 러너를 차단할까요?";body="이 러너의 글과 댓글을 더 이상 표시하지 않아요.";skip="취소";case .blockPost:title="작성자를 차단할까요?";body="이 작성자의 글과 댓글을 더 이상 표시하지 않아요.";skip="취소";case .blockAfterReport:title="작성자도 차단할까요?";body="차단하면 이 작성자의 글과 댓글을 더 이상 표시하지 않아요.";skip="건너뛰기"}
        return ZStack{Color.black.opacity(0.48).ignoresSafeArea();VStack(alignment:.leading,spacing:12){Text(title).font(W.font(19,.semibold));Text(body).font(W.font(14)).foregroundStyle(W.muted).fixedSize(horizontal:false,vertical:true);HStack(spacing:10){Button(skip){ui.communityModerationDialog=nil}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("communityModerationCancel");Button("차단"){confirmCommunityModerationAction()}.buttonStyle(WButtonStyle(kind:2)).accessibilityIdentifier("communityModerationConfirm")}}.padding(20).frame(maxWidth:360).background(W.paper,in:RoundedRectangle(cornerRadius:22)).padding(24)}
    }

    var communityBoards:some View {
        WPage(title:"게시판",back:back){
            Text("게시판 바로가기").font(W.font(15,.semibold))
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){ForEach(["러닝 질문","러닝 인증","대회 정보·후기","크루 모집"],id:\.self){board in Button{ui.communityBoard=board;go("C03")}label:{VStack(alignment:.leading,spacing:8){Image(systemName:board=="러닝 질문" ? "bubble.left.and.bubble.right":"figure.run").font(.system(size:20));Text(board).font(W.font(12,.medium))}.frame(maxWidth:.infinity,minHeight:78,alignment:.leading).padding(.horizontal,14).background(W.soft,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).accessibilityIdentifier("communityBoardShortcut-\(board)")}}
            HStack{Text("새로 올라온 이야기").font(W.font(15,.semibold));Spacer();Button("전체 게시판 보기"){go("C27")}.font(W.font(11,.medium)).foregroundStyle(W.muted).accessibilityIdentifier("communityBrowseAllBoards")}.padding(.top,14)
            ForEach(communityVisiblePosts){post in communityPostCard(post)}
        }actions:{}
    }
    var communityAllBoards:some View {WPage(title:"전체 게시판",back:back){ForEach(WCommunityFixtures.boards,id:\.self){board in WRow(title:board,action:{ui.communityBoard=board;go("C03")},height:58,arrow:true).accessibilityIdentifier("communityBoard-\(board)")}}actions:{}}
    var communityBoardPosts:some View {let posts=communityVisiblePosts.filter{$0.board==ui.communityBoard};return WPage(title:ui.communityBoard,back:back){Text("\(posts.count)개 이야기").font(W.font(12)).foregroundStyle(W.muted);ForEach(posts){post in communityPostCard(post)}}actions:{Button("글쓰기"){beginCommunityCompose(board:ui.communityBoard)}.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityBoardCompose")}}

    @ViewBuilder var communityPostDetail:some View {
        if let post=currentCommunityPost(){
            let comments=communityVisibleComments(post)
            WPage(title:post.board,back:back,trailing:post.authorMemberID==ui.communityViewerMemberID ? AnyView(EmptyView()):AnyView(Button{ui.communityMoreMenu = .post(post.id)}label:{Image(systemName:"ellipsis").font(.system(size:19,weight:.medium)).frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("게시물 더보기").accessibilityIdentifier("communityPostMore"))){
                Button{openCommunityCard(for:post.authorMemberID,origin:"C04")}label:{HStack(spacing:10){communityAvatar(post.author);VStack(alignment:.leading,spacing:3){Text(post.author).font(W.font(13,.semibold));Text("\(post.rank) · \(post.date)").font(W.font(10)).foregroundStyle(W.muted)};Spacer()}.frame(maxWidth:.infinity,minHeight:48,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("communityDetailAuthorCard")
                Text(post.title).font(W.font(23,.semibold)).lineSpacing(5).padding(.top,5).accessibilityIdentifier("communityDetailTitle")
                Text(post.text).font(W.font(14)).lineSpacing(7).accessibilityIdentifier("communityDetailBody")
                if let imageName=post.imageName{Button{go("C04-IMAGE")}label:{Image(imageName).resizable().scaledToFill().frame(maxWidth:.infinity).frame(height:210).clipped().clipShape(RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).accessibilityLabel("게시글 사진 확대").accessibilityIdentifier("communityDetailImageOpen")}
                HStack(spacing:18){
                    Button{toggleCommunityLike(post.id)}label:{Label("\(post.likes+(ui.communityLikedPosts.contains(post.id) ? 1:0))",systemImage:ui.communityLikedPosts.contains(post.id) ? "heart.fill":"heart").font(W.font(12)).foregroundStyle(ui.communityLikedPosts.contains(post.id) ? Color.wire(0xE85D68,0xFF9CA3):W.muted)}.accessibilityIdentifier("communityDetailLike")
                    Label("\(comments.count)",systemImage:"bubble.right").font(W.font(12)).foregroundStyle(W.muted)
                    Spacer();Label("\(post.views)",systemImage:"eye").font(W.font(11)).foregroundStyle(W.muted).accessibilityIdentifier("communityDetailViews")
                }.buttonStyle(.plain).padding(.vertical,12).overlay(alignment:.bottom){W.line.frame(height:1)}
                VStack(alignment:.leading,spacing:0){
                    Text("댓글 \(comments.count)").font(W.font(16,.semibold)).padding(.top,8).padding(.bottom,4)
                    ForEach(comments.filter{$0.parentID==nil}){comment in communityCommentRow(comment,all:comments,depth:0)}
                }
            }actions:{
                if let parent=post.comments.first(where:{$0.id==ui.communityReplyToID}) {
                    HStack(spacing:8){Text(parent.isDeleted ? "삭제된 댓글입니다":"\(parent.author)에게 답글 · \(parent.text)").font(W.font(11)).foregroundStyle(W.muted).lineLimit(1);Spacer();Button("취소"){ui.communityReplyToID=nil}.font(W.font(11)).accessibilityIdentifier("communityReplyCancel")}
                        .accessibilityIdentifier("communityReplyComposerTarget")
                }
                TextField("댓글을 남겨 보세요",text:Binding(get:{ui.communityComment},set:{ui.communityComment=WCommunityTextLimit.apply($0,limit:WCommunityTextLimit.comment)})).font(W.font(14)).padding(14).frame(minHeight:50).background(W.soft,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("communityCommentInput").submitLabel(.send).onSubmit{submitCommunityComment()}
                if !ui.communityError.isEmpty{WText(text:ui.communityError,small:true)}
                Button(ui.communityReplyToID == nil ? "댓글 등록":"답글 등록"){submitCommunityComment()}.buttonStyle(WButtonStyle(kind:1)).disabled(ui.communityComment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("communityCommentSubmit")
            }.onAppear{recordCommunityDetailView(post)}
                .onChange(of:ui.communityComment){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.comment);if limited != value{ui.communityComment=limited}}
        } else {
            WPage(title:"게시물",back:back){WText(text:"지금은 볼 수 없는 글이에요.")}actions:{}
        }
    }

    var communityImageViewer:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing:0){
                HStack{Spacer();Button{back()}label:{Image(systemName:"xmark").font(.system(size:18,weight:.semibold)).foregroundStyle(.white).frame(width:48,height:48).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("확대 사진 닫기").accessibilityIdentifier("communityImageClose")}.padding(.horizontal,12).padding(.top,8)
                Spacer(minLength:12)
                if let post=currentCommunityPost(),let imageName=post.imageName {Image(imageName).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityLabel("확대된 게시글 사진").accessibilityIdentifier("communityImageZoom")}
                Spacer(minLength:12)
            }
        }
    }

    var communityCompose:some View {
        WPage(title:"글쓰기",back:back){
            VStack(alignment:.leading,spacing:8){Text("게시판").font(W.font(14,.medium));Picker("게시판",selection:$ui.communityDraftBoard){ForEach(WCommunityFixtures.boards.filter{$0 != "익명게시판"},id:\.self){Text($0).tag($0)}}.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading).padding(12).background(W.soft,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("communityComposeBoard")}
            WField(label:"제목",text:$ui.communityDraftTitle,placeholder:"제목을 입력해 주세요",limit:60,accessibilityID:"communityComposeTitle")
            VStack(alignment:.leading,spacing:8){Text("내용").font(W.font(14,.medium));TextEditor(text:$ui.communityDraftBody).font(W.font(14)).scrollContentBackground(.hidden).frame(minHeight:178).padding(8).background(W.soft,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("communityComposeBody");Text("\(ui.communityDraftBody.count)/2000").font(W.font(11)).foregroundStyle(W.muted).frame(maxWidth:.infinity,alignment:.trailing)}
            WText(text:"가상 커뮤니티 글은 이 기기 안에서만 보여요. 사진·영상 첨부와 서버 게시 기능은 연결되어 있지 않아요.",small:true)
            if !ui.communityError.isEmpty{WNotice(text:ui.communityError,danger:true)}
        }actions:{
            Button("미리보기"){guard !ui.communityDraftTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{ui.communityError="제목을 입력해 주세요.";return};guard !ui.communityDraftBody.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{ui.communityError="내용을 입력해 주세요.";return};ui.communityError="";go("C09")}.buttonStyle(WButtonStyle()).disabled(ui.communityDraftTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || ui.communityDraftBody.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("communityPreviewButton")
            Button("취소"){back()}.buttonStyle(WButtonStyle(kind:1))
        }
        .onChange(of:ui.communityDraftTitle){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.title);if limited != value{ui.communityDraftTitle=limited}}
        .onChange(of:ui.communityDraftBody){_,value in let limited=WCommunityTextLimit.apply(value,limit:WCommunityTextLimit.body);if limited != value{ui.communityDraftBody=limited}}
    }
    var communityPreview:some View {WPage(title:"미리보기",back:back){Text("커뮤니티에 공개").font(W.font(12)).foregroundStyle(W.muted);Text(ui.communityDraftBoard).font(W.font(12,.medium)).accessibilityIdentifier("communityPreviewBoard");Text(ui.communityDraftTitle).font(W.font(23,.semibold)).lineSpacing(5).accessibilityIdentifier("communityPreviewTitle");Text(ui.communityDraftBody).font(W.font(14)).lineSpacing(7).accessibilityIdentifier("communityPreviewBody");WNotice(text:"게시물은 로컬 예시 데이터로만 추가돼요.");if !ui.communityError.isEmpty{WNotice(text:ui.communityError,danger:true)}}actions:{Button("게시하기"){publishCommunityDraft()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("communityPublishButton");Button("다시 수정"){go("C05")}.buttonStyle(WButtonStyle(kind:1))}}
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
