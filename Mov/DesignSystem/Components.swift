import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View { Image("BrandMark").resizable().renderingMode(.template).scaledToFit().frame(width:size,height:size).foregroundStyle(MovTokens.brand).accessibilityLabel("모브") }
}
struct AssetIcon: View {
    let name: String
    var size: CGFloat = 24
    var body: some View { Image(name).resizable().renderingMode(.template).scaledToFit().frame(width:size,height:size).accessibilityHidden(true) }
}
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(MovTokens.text)
            .background(MovTokens.surface,in:RoundedRectangle(cornerRadius:12)).opacity(configuration.isPressed ? 0.7:1)
    }
}
struct DestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(Color(red:0.20,green:0.02,blue:0.02))
            .background(Color(red:1,green:0.40,blue:0.42),in:RoundedRectangle(cornerRadius:12)).opacity(configuration.isPressed ? 0.7:1)
    }
}
struct DemoCaption: View {
    var body: some View { Text("샘플 모드 · 실제 GPS를 사용하지 않아요").font(.caption).foregroundStyle(MovTokens.secondary) }
}
struct MetricView: View {
    let record: RunRecord
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:8) {
                Text("샘플 거리").font(.subheadline).foregroundStyle(MovTokens.secondary)
                HStack(alignment:.firstTextBaseline,spacing:8) { Text(record.kilometers,format:.number.precision(.fractionLength(2))).font(.system(.largeTitle,design:.default,weight:.bold)).monospacedDigit();Text("km").font(.title3) }
            }
            HStack {
                metric("러닝 시간", RunRecord.clock(record.seconds))
                Rectangle().fill(Color(.separator)).frame(width:1,height:55).padding(.horizontal,18)
                metric("평균 페이스", record.pace + " /km")
            }
        }
    }
    private func metric(_ label:String,_ value:String)->some View {
        VStack(alignment:.leading,spacing:8) { Text(label).font(.caption).foregroundStyle(MovTokens.secondary);Text(value).font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1) }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
// Exact map() SVG coordinates and final theme.css tokens from the original v32 HTML.
nonisolated struct SampleMap: View, Animatable {
    @MainActor @Environment(\.colorScheme) private var scheme
    var route=false
    var focusUser=false
    var userCenterY:CGFloat=0
    var panOffset:CGSize = .zero
    var animatableData:AnimatablePair<CGFloat,AnimatablePair<CGFloat,CGFloat>> {
        get{AnimatablePair(userCenterY,AnimatablePair(panOffset.width,panOffset.height))}
        set{userCenterY=newValue.first;panOffset=CGSize(width:newValue.second.first,height:newValue.second.second)}
    }
    @MainActor var body:some View {let scheme=scheme;return Canvas{context,size in
        var c=context
        let scale=max(size.width/390,size.height/480)
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(scheme == .dark ? Color(red:32/255,green:32/255,blue:32/255):Color(red:251/255,green:251/255,blue:251/255)))
        c.translateBy(x:(focusUser ? size.width/2-217*scale:(size.width-390*scale)/2)+panOffset.width,y:(focusUser ? userCenterY-269*scale:(size.height-480*scale)/2)+panOffset.height)
        c.scaleBy(x:scale,y:scale)
        let dark=scheme == .dark
        func color(_ light:UInt32,_ night:UInt32)->Color{let n=dark ? night:light;return Color(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255)}
        func stroke(_ p:Path,_ color:Color,_ width:CGFloat){c.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:width))}
        c.fill(Path(CGRect(x:0,y:0,width:390,height:480)),with:.color(color(0xFBFBFB,0x202020)))
        for r in [CGRect(x:18,y:25,width:74,height:49),CGRect(x:109,y:25,width:71,height:49),CGRect(x:18,y:94,width:74,height:67),CGRect(x:109,y:94,width:71,height:67),CGRect(x:18,y:182,width:74,height:55),CGRect(x:109,y:182,width:71,height:55),CGRect(x:18,y:385,width:82,height:67),CGRect(x:118,y:389,width:55,height:62),CGRect(x:291,y:18,width:78,height:63)]{let p=Path(r);c.fill(p,with:.color(color(0xF4F4F4,0x282828)));stroke(p,color(0xEEEEEE,0x373737),1)}
        var river=Path();river.move(to:CGPoint(x:423,y:-25));river.addCurve(to:CGPoint(x:203,y:321),control1:CGPoint(x:193,y:72),control2:CGPoint(x:365,y:187));river.addCurve(to:CGPoint(x:83,y:544),control1:CGPoint(x:41,y:455),control2:CGPoint(x:213,y:457));stroke(river,color(0xEEEEEE,0x373737),95)
        var water=Path();water.move(to:CGPoint(x:424,y:-25));water.addCurve(to:CGPoint(x:203,y:321),control1:CGPoint(x:192,y:75),control2:CGPoint(x:365,y:185));water.addCurve(to:CGPoint(x:83,y:544),control1:CGPoint(x:41,y:457),control2:CGPoint(x:213,y:457));stroke(water,color(0xF7F7F7,0x242424),62)
        let roads:[[(CGFloat,CGFloat)]]=[ [(-20,84),(202,84),(404,182)],[(101,-10),(101,242),(142,377),(173,491)],[(-20,173),(190,173),(408,301)],[(-21,253),(217,266),(405,393)],[(-20,382),(327,76)],[(8,-10),(390,457)] ]
        for vertices in roads{var p=Path();for (i,v) in vertices.enumerated(){if i==0{p.move(to:CGPoint(x:v.0,y:v.1))}else{p.addLine(to:CGPoint(x:v.0,y:v.1))}};stroke(p,color(0xFFFFFF,0x414141),8)}
        var track=Path();track.move(to:CGPoint(x:36,y:343));track.addQuadCurve(to:CGPoint(x:226,y:161),control:CGPoint(x:145,y:276));track.addQuadCurve(to:CGPoint(x:343,y:32),control:CGPoint(x:307,y:46));track.move(to:CGPoint(x:51,y:361));track.addQuadCurve(to:CGPoint(x:244,y:179),control:CGPoint(x:163,y:295));track.addQuadCurve(to:CGPoint(x:361,y:50),control:CGPoint(x:325,y:63));stroke(track,color(0xF0F0F0,0x4B4B4B),2)
        if route{var p=Path();p.move(to:CGPoint(x:75,y:348));for v in [(120,334),(156,307),(190,295),(217,269)]{p.addLine(to:CGPoint(x:v.0,y:v.1))};c.stroke(p,with:.color(W.lime),style:StrokeStyle(lineWidth:7,lineCap:.round))};if route && !focusUser{let point=Path(ellipseIn:CGRect(x:207,y:259,width:20,height:20));c.fill(point,with:.color(W.lime));stroke(point,.white,3)}
        for (text,x,y) in [("주거 구역",34.0,130.0),("하천",245.0,332.0),("산책로",116.0,357.0)]{c.draw(Text(text).font(.custom("Arial",size:12)).foregroundStyle(color(0x707070,0xBDBDBD)),at:CGPoint(x:x,y:y),anchor:.bottomLeading)}
    }.accessibilityLabel("실제 장소가 아닌 도식 지도").accessibilityHidden(focusUser).overlay{if focusUser{GeometryReader{g in Circle().fill(W.lime).overlay(Circle().stroke(.white,lineWidth:3)).frame(width:20,height:20).position(x:g.size.width/2+panOffset.width,y:userCenterY+panOffset.height).accessibilityElement().accessibilityLabel("사용자 위치").accessibilityIdentifier("runUserPosition")}}}.accessibilityElement(children:.contain)}
}
struct GPSBadge: View {
    var body: some View {
        ZStack { RoundedRectangle(cornerRadius:12).fill(MovTokens.background);RoundedRectangle(cornerRadius:12).stroke(Color(.separator),lineWidth:1)
            Circle().stroke(MovTokens.brand.opacity(0.45),lineWidth:1).frame(width:20,height:20)
            Circle().stroke(MovTokens.brand.opacity(0.7),lineWidth:1).frame(width:14,height:14)
            Circle().fill(MovTokens.brand).frame(width:8,height:8)
        }.frame(width:44,height:44).accessibilityLabel("샘플 신호 표시, 실제 GPS 연결 아님")
    }
}
struct ScreenHeader: View {
    var title: String
    var home = false
    var showActions = true
    var running = false
    var settings: ()->Void
    var notifications: ()->Void
    var records: ()->Void = {}
    var body: some View {
        HStack(spacing:8) {
            BrandMark().frame(width:44,height:44)
            Spacer()
            if showActions {
                Button(action:running ? records:notifications){AssetIcon(name:running ? "records":"bell",size:20).frame(width:44,height:44)}.accessibilityLabel(running ? "기록 보기":"알림")
                Button(action:settings){AssetIcon(name:"settings",size:20).frame(width:44,height:44)}.accessibilityLabel("설정")
            }
        }.padding(.horizontal,16).frame(height:60)
            .overlay { if !home {Text(title).font(.headline).lineLimit(1).frame(maxWidth:160).allowsHitTesting(false)} }
            .foregroundStyle(MovTokens.text).background(MovTokens.background)
    }
}
