import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
extension WireframeRoot {
    var profile:some View {VStack(spacing:0){rootHeader("내 정보");ScrollView{VStack(alignment:.leading,spacing:14){HStack{Text("나의 러닝 카드").font(W.font(17,.semibold));Spacer();Button("카드 편집"){go("M02")}.font(W.font(12)).frame(minHeight:44)}
        runnerIdentityCard()
        gradeProgress.padding(.top,-8)
        WDisclosure(title:"등급 기준",expanded:$ui.gradeExpanded){VStack(alignment:.leading,spacing:12){WText(text:"첫 유효 기록을 완료하면 시작러너가 돼요. 새싹러너부터는 누적 거리와 활동일 수를 함께 확인해요. 하루 유효 구간 합계가 4분 이상이면서 1 km 이상이면 활동일 1일로 계산해요. 같은 날 여러 번 달려도 1일이에요.",small:true);ForEach(Array(zip(["start","sprout","passion","challenge","distance"],["시작러너|첫 유효 기록 완료","새싹러너|누적 10 km + 서로 다른 7일","열정러너|누적 30 km + 서로 다른 10일","도전러너|누적 100 km + 서로 다른 20일","러닝마스터|누적 300 km + 서로 다른 50일"])),id:\.0){key,copy in let parts=copy.components(separatedBy:"|");HStack{Image("Tier-"+key).resizable().scaledToFit().frame(width:24,height:24);Text(parts[0]).font(W.font(13,.medium));Spacer();WText(text:parts[1],small:true)}};WText(text:"저장된 유효 구간의 거리와 활동일을 기준으로 계산해요. 제외된 구간은 합계에 포함하지 않아요.",small:true)}.padding(.top,12)}.font(W.font(13)).padding(.top,-10)
        Text("개인 설정").font(W.font(12)).foregroundStyle(W.muted).padding(.top,18);WRow(title:"체중 정보",subtitle:"선택 입력 · 러닝 카드에 표시되지 않아요",action:{go("T02")},arrow:true);WText(text:"활동 지역과 소개는 카드 편집에서 변경할 수 있어요.",small:true)
    }.padding(.horizontal,24).padding(.top,20).padding(.bottom,24)}}}
    @ViewBuilder func runnerIdentityCard(decorationID:String? = nil)->some View {
        let card = VStack(alignment:.leading,spacing:0){HStack{Text("러닝 프로필").font(W.font(11)).kerning(0.275).foregroundStyle(W.muted);Spacer();BrandMark(size:28)}.frame(height:28)
            HStack(spacing:14){Group{if let data=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo),let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}else{Text(String(ui.profile.nickname.prefix(1))).font(W.font(20,.semibold))}}.frame(width:56,height:56).background(W.soft).clipShape(Circle()).overlay(Circle().stroke(W.line)).overlay{if decorationID == "frame"{Circle().stroke(W.lime,lineWidth:3).padding(-5)}};VStack(alignment:.leading,spacing:0){
                HStack(spacing:5){if store.totalDistance>0{Image("Tier-"+currentTierKey).resizable().scaledToFit().frame(width:28,height:28)};Text(store.totalDistance==0 ? "등급 없음":tierName).font(W.font(12,.medium)).foregroundStyle(W.muted)}.frame(height:28).padding(.bottom,6)
                Text(ui.profile.nickname).font(W.font(31,.semibold)).kerning(-1.86).frame(minHeight:38.13,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                Text(ui.profile.introduction).font(W.font(13)).kerning(-0.195).foregroundStyle(W.muted).frame(minHeight:22.1,alignment:.leading).padding(.top,12)
            }}.padding(.top,35).padding(.bottom,28)
            W.line.frame(height:1);HStack(alignment:.top,spacing:16){VStack(alignment:.leading,spacing:7){Text("활동 지역").font(W.font(10)).foregroundStyle(W.muted).frame(height:15);Text(ui.profile.region).font(W.font(13,.medium)).frame(minHeight:17.55).padding(.top,5)}.frame(maxWidth:.infinity,alignment:.leading);VStack(alignment:.leading,spacing:7){Text("최근 1달 평균 러닝당 거리").font(W.font(10)).foregroundStyle(W.muted).frame(height:15);(Text(MovNumber.display(store.averageDistance)).font(W.font(24,.semibold)).kerning(-0.96)+Text(" km").font(W.font(11,.medium))).frame(height:32.4)}.frame(maxWidth:.infinity,alignment:.leading)}.padding(.top,18)
        }.padding(.horizontal,23).padding(.top,23).padding(.bottom,20).frame(minHeight:315,alignment:.top).background(W.paper,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(W.line)).shadow(color:.black.opacity(0.025),radius:10,y:5)
        if let decorationID {
            card.overlay(alignment:.topTrailing){if decorationID == "line"{Ellipse().stroke(W.lime.opacity(0.24),lineWidth:22).frame(width:260,height:230).rotationEffect(.degrees(-25)).offset(x:155,y:-60)}else if decorationID == "dawn"{Ellipse().stroke(W.lime.opacity(0.24),lineWidth:40).frame(width:260,height:230).rotationEffect(.degrees(-25)).offset(x:70,y:160)}else if decorationID == "card-frame"{RoundedRectangle(cornerRadius:18).stroke(W.lime,lineWidth:3).padding(4)}}.clipShape(RoundedRectangle(cornerRadius:18))
        } else {
            card
        }
    }
    var nextTier:(String,String,Double,Int)? {switch store.tier{case "마스터":nil;case "도전":("러닝마스터","distance",300,50);case "열정":("도전러너","challenge",100,20);case "새싹":("열정러너","passion",30,10);default:("새싹러너","sprout",10,7)}}
    @ViewBuilder var gradeProgress:some View {
        if store.totalDistance==0{HStack{Image("Tier-start").resizable().scaledToFit().frame(width:20,height:20);WText(text:"첫 유효 기록을 완료하면 시작러너가 돼요",small:true)}}
        else if let next=nextTier{HStack{Image("Tier-"+next.1).resizable().scaledToFit().frame(width:20,height:20);WText(text:next.0+"까지 \(MovNumber.display(max(0,next.2-store.totalDistance))) km · \(max(0,next.3-store.activityDays))일",small:true)};tierProgress("누적 거리",value:store.totalDistance,maxValue:next.2,unit:"km");tierProgress("활동일",value:Double(store.activityDays),maxValue:Double(next.3),unit:"일")}
        else{WText(text:"러닝마스터 기준을 모두 채웠어요",small:true)}
    }
    var currentTierKey:String {switch store.tier{case "새싹":"sprout";case "열정":"passion";case "도전":"challenge";case "마스터":"distance";default:"start"}}
    var tierName:String {switch store.tier{case "시작":"시작러너";case "새싹":"새싹러너";case "열정":"열정러너";case "도전":"도전러너";case "마스터":"러닝마스터";default:"등급 없음"}}
    func tierProgress(_ title:String,value:Double,maxValue:Double,unit:String)->some View {VStack(spacing:6){HStack{Text(title);Spacer();Text("\(value,specifier:"%.0f") / \(Int(maxValue)) \(unit)")}.font(W.font(11)).foregroundStyle(W.muted);GeometryReader{g in ZStack(alignment:.leading){Capsule().fill(W.secondary);Capsule().fill(W.lime).frame(width:g.size.width*min(1,value/maxValue))}}.frame(height:5)}}
    var profileEdit:some View {WPage(title:"러닝 카드 편집",back:back){Text("나를 소개하는 러닝 카드").font(W.font(23,.semibold)).padding(.top,4);WText(text:"닉네임과 활동 지역으로 나를 소개해 보세요.",small:true).padding(.bottom,10)
        WAvatarEditor(data:$ui.photo).padding(.bottom,9)
        WField(label:"닉네임",text:$ui.nickname,limit:20,textSize:14,labelSize:13,secondaryLabel:"필수").padding(.top,5);Text("최대 20자 · 중복 여부는 확인하지 않아요").font(W.font(11)).kerning(-0.165).foregroundStyle(W.muted).frame(height:17.6,alignment:.leading).padding(.top,-11);WField(label:"한 줄 소개",text:$ui.introduction,placeholder:"어떤 러너인지 소개해 주세요",limit:60,multiline:true,multilineHeight:86,textSize:14,labelSize:13,secondaryLabel:"선택").padding(.top,4)
        (Text("활동 지역").font(W.font(13))+Text("  선택").font(W.font(10)).foregroundColor(W.muted));WRegionPicker(selection:$ui.region);WText(text:"활동 지역은 선택하지 않아도 괜찮아요.",small:true);if !ui.error.isEmpty{WNotice(text:ui.error,danger:true)}
    }actions:{Button("저장하기"){guard WProfileValidation.isValid(nickname:ui.nickname,introduction:ui.introduction) else{ui.error="닉네임은 1–20자, 한 줄 소개는 60자 이내로 입력해 주세요.";return};ui.profile.photo=ui.photo;ui.profile.nickname=ui.nickname.trimmingCharacters(in:.whitespacesAndNewlines);ui.profile.introduction=ui.introduction;ui.profile.region=ui.region;ui.save();back()}.buttonStyle(WButtonStyle());Button("취소",action:back).buttonStyle(WButtonStyle(kind:1))}}
    var notifications:some View {WPage(title:"알림",back:back){VStack(alignment:.leading,spacing:0){
        Text("모브 안내").font(W.font(12,.semibold)).foregroundStyle(W.muted).frame(height:18,alignment:.leading).padding(.bottom,8)
        Text("목표와 기록 관리에 필요한 안내를 확인해요.").font(W.font(13)).lineSpacing(5.95).foregroundStyle(W.muted).frame(height:42.9,alignment:.topLeading).padding(.bottom,22)
        WNotificationList(ids:ui.notificationIDs,profile:$ui.profile,save:ui.save)
    }}actions:{}}
    var settings:some View {WPage(title:"설정",back:back){
        VStack(alignment:.leading,spacing:28){
            VStack(alignment:.leading,spacing:8){settingsLabel("앱 설정");VStack(spacing:0){
                WRow(title:"단위",subtitle:"km · 분/km · kcal",action:{go("T03")},separator:false,height:76)
                W.line.frame(height:1).padding(.horizontal,8)
                WRow(title:"화면 테마",subtitle:appearance=="system" ? "시스템 설정에 따름":appearance=="dark" ? "다크 모드":"라이트 모드",action:{go("T18")},separator:false,height:76)
            }}
            VStack(alignment:.leading,spacing:8){settingsLabel("개인정보");WRow(title:"개인정보·데이터",subtitle:"기기 보관과 삭제 범위",action:{go("T04")},separator:false,height:76)}
            VStack(alignment:.leading,spacing:8){settingsLabel("계정 · 연결");VStack(spacing:0){
                WRow(title:"로그인 수단",subtitle:ui.profile.providers.joined(separator:" · "),action:{go("T05")},separator:false,height:76)
                W.line.frame(height:1).padding(.horizontal,8)
                WRow(title:"로그아웃",action:{go(store.session==nil ? "T10":"T14")},separator:false,height:58)
            }}
        }.padding(.top,2)
        WText(text:"모브 MVP · 화면 설계 검토\n실제 회원 기능은 동작하지 않아요.",small:true).padding(.top,12)
    }actions:{}}
    func settingsLabel(_ text:String)->some View {Text(text).font(W.font(12,.semibold)).foregroundStyle(W.muted).frame(height:20,alignment:.leading)}
    var theme:some View {WPage(title:"화면 테마",back:back){WText(text:"모브의 화면 테마를 선택해 주세요.");ForEach(["light","dark","system"],id:\.self){choice in Button{appearance=choice}label:{HStack{Text(choice=="light" ? "라이트 모드":choice=="dark" ? "다크 모드":"시스템 설정에 따름").font(W.font(15));Spacer();if choice==appearance{Image(systemName:"checkmark").foregroundStyle(W.lime)}}.frame(minHeight:64).overlay(alignment:.bottom){W.line.frame(height:1)}}.accessibilityIdentifier("theme-"+choice).accessibilityAddTraits(choice==appearance ? .isSelected:[])};WText(text:"시스템 설정에 따르면 기기의 화면 설정이 바뀔 때 모브도 함께 바뀌어요.");WText(text:"이 기기에 저장되며, 다시 열어도 유지돼요.",small:true)}actions:{}}
    var weightProfile:some View {WPage(title:ui.screen=="A03" ? "프로필":"프로필·체중",back:back){if ui.screen=="A03"{WText(text:"02 / 02",small:true).offset(y:6);WHeading(text:"어떻게 불러드릴까요?");WField(label:"닉네임 (필수)",text:$ui.nickname,limit:20);WText(text:"최대 20자로 입력해 주세요",small:true)};if ui.screen=="A03"{Text("체중은 선택이에요").font(W.font(17,.semibold)).padding(.top,4)}else{WHeading(text:"체중은 선택이에요")};WText(text:"입력하면 달린 거리를 바탕으로\n추정 소모 칼로리를 보여드려요.");HStack(alignment:.bottom,spacing:8){WField(label:"체중",text:$ui.weight,placeholder:"입력하지 않아도 괜찮아요",textSize:ui.screen=="A03" ? 14:16,placeholderColor:ui.screen=="A03" ? Color.wire(0x686868,0xA5A5A5):nil).keyboardType(.decimalPad);Text("kg").font(W.font(14)).frame(height:54)}.padding(.top,ui.screen=="A03" ? 4:0);WText(text:"입력한 체중은 러닝 카드에 표시되지 않아요.",small:true);Group{if ui.screen=="A03"{WAuthNotice(text:"체중이 없으면 칼로리는 —로 표시해요. 기록 당시의 체중으로 계산한 추정값이며 건강 측정값이 아니에요.")}else{WNotice(text:"체중이 없으면 칼로리는 —로 표시해요. 기록 당시의 체중으로 계산한 추정값이며 건강 측정값이 아니에요.")}};if !ui.error.isEmpty{WNotice(text:ui.error,danger:true)}}actions:{Button(ui.screen=="A03" ? "계속":"변경 저장"){if !ui.weight.isEmpty && !(20...300).contains(Double(ui.weight) ?? 0){ui.error="체중은 20–300 kg 범위로 입력해 주세요.";return};if ui.screen=="A03" && (ui.nickname.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || ui.nickname.count>20){ui.error="닉네임은 1–20자로 입력해 주세요.";return};if ui.screen=="A03" && ["달빛러너","runmate"].contains(ui.nickname.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()){ui.error="이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요.";return};ui.profile.weight=ui.weight;if ui.screen=="A03"{ui.profile.photo=ui.photo;ui.profile.nickname=ui.nickname;if !ui.provider.isEmpty && !ui.profile.providers.contains(ui.provider){ui.profile.providers.append(ui.provider)};ui.profile.logged=true;ui.save();go("A15")}else{ui.save();back()}}.buttonStyle(WButtonStyle());if ui.screen != "A03"{Button("체중 정보 제거"){ui.profile.weight="";ui.weight="";ui.save();back()}.buttonStyle(WButtonStyle(kind:1))}}}
}
struct WNotificationReadState {
    var expandedID:Int?
    var failedID:Int?
    var failuresRemaining=0
    mutating func open(_ id:Int,profile:inout WLocalProfile)->Bool {
        expandedID=expandedID==id ? nil:id
        guard !profile.notificationRead.contains(id) else{return false}
        if failuresRemaining>0{failuresRemaining-=1;failedID=id;return false}
        profile.notificationRead.append(id);failedID=nil;return true
    }
    mutating func retry(profile:inout WLocalProfile)->Bool {
        guard let id=failedID else{return false}
        if !profile.notificationRead.contains(id){profile.notificationRead.append(id)}
        failedID=nil;return true
    }
}
private struct WNotificationList:View {
    let ids:[Int]
    @Binding var profile:WLocalProfile
    let save:()->Void
    @State private var state:WNotificationReadState
    init(ids:[Int],profile:Binding<WLocalProfile>,save:@escaping()->Void){self.ids=ids;_profile=profile;self.save=save;let args=ProcessInfo.processInfo.arguments;_state=State(initialValue:WNotificationReadState(failuresRemaining:WReviewMode.tools && args.contains("-wire-notification-save-fail-once") ? 1:0))}
    var body:some View {Group{if ids.isEmpty{VStack(alignment:.leading,spacing:8){Text("새 알림이 없어요").font(W.font(15,.medium));WText(text:"새로운 안내가 도착하면 여기에 표시돼요.",small:true)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,28).accessibilityIdentifier("notificationEmptyState")}else{ForEach(ids,id:\.self){id in VStack(alignment:.leading,spacing:0){if id != ids.first{W.line.frame(height:1)};Button{open(id)}label:{HStack(spacing:16){VStack(alignment:.leading,spacing:7){Text(id==0 ? "러닝 목표 안내":"기록 확인 안내").font(W.font(15,.medium));Text(profile.notificationRead.contains(id) ? "읽음":"읽지 않음").font(W.font(11)).foregroundStyle(W.muted)};Spacer();WChevron().stroke(W.muted,style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round)).rotationEffect(.degrees(state.expandedID==id ? 180:0)).frame(width:20,height:20)}.frame(maxWidth:.infinity,minHeight:80).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("notification-\(id)").accessibilityValue("\(state.expandedID==id ? "펼침":"접힘") · \(profile.notificationRead.contains(id) ? "읽음":"읽지 않음")");if state.expandedID==id{Text(id==0 ? "거리나 시간 목표를 정한 뒤 러닝을 시작해 보세요.":"저장한 러닝은 기록 탭에서 다시 열어 볼 수 있어요.").font(W.font(14)).lineSpacing(10).foregroundStyle(W.muted).padding(.trailing,24).padding(.bottom,19)};if state.failedID==id{VStack(alignment:.leading,spacing:8){WNotice(text:"읽음 상태를 저장하지 못했어요. 다시 시도해 주세요.",danger:true).accessibilityIdentifier("notificationSaveFailure");Button("다시 시도"){retry(id)}.font(W.font(13,.medium)).accessibilityIdentifier("retryNotificationRead")}.padding(.bottom,14)}}}}}}
    private func open(_ id:Int){var updated=profile;let shouldSave=state.open(id,profile:&updated);profile=updated;if shouldSave{save()}}
    private func retry(_ id:Int){guard state.failedID==id else{return};var updated=profile;if state.retry(profile:&updated){profile=updated;save()}}
}
struct WAvatarEditor:View {
    @State private var item:PhotosPickerItem?
    @Binding var data:Data?
    @State private var draft:UIImage?
    @State private var message=""
    var picture:UIImage?{WProfilePhotoPolicy.sanitizeStored(data).flatMap(UIImage.init(data:))}
    var body:some View {VStack(alignment:.leading,spacing:12){(Text("프로필 사진").font(W.font(13))+Text("  선택").font(W.font(10)).foregroundColor(W.muted)).padding(.bottom,7);Group{if let picture{Image(uiImage:picture).resizable().scaledToFill()}else{WAvatarPlaceholder().stroke(W.muted,style:StrokeStyle(lineWidth:1.6*34/24,lineCap:.butt,lineJoin:.miter)).frame(width:34,height:34)}}.frame(width:80,height:80).background(W.soft).clipShape(Circle()).overlay(Circle().stroke(W.line)).frame(maxWidth:.infinity).padding(.bottom,6);HStack{PhotosPicker(selection:$item,matching:.images){Text("사진 선택").font(W.font(12,.medium)).frame(minWidth:72,minHeight:24).padding(.horizontal,14).padding(.vertical,10).background(W.lime,in:RoundedRectangle(cornerRadius:10)).foregroundStyle(MovTokens.onBrand)};Button("사진 삭제"){data=nil;item=nil;draft=nil}.font(W.font(12,.medium)).frame(minWidth:72,minHeight:24).padding(.horizontal,14).padding(.vertical,10).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.line)).foregroundStyle(data==nil ? W.muted:W.ink).disabled(data==nil)}.frame(maxWidth:.infinity);Text("JPG · PNG · WebP, 8MB 이하\n이 브라우저에만 저장돼요. 서버로 전송하지 않아요.").font(W.font(11)).lineSpacing(6).foregroundStyle(W.muted)
        if !message.isEmpty{WNotice(text:message,danger:true)}
        if let draft{WPhotoCrop(image:draft){value in data=value;self.draft=nil} cancel:{self.draft=nil}}
    }.task(id:item){guard let item else{return};do{guard let imported=try await item.loadTransferable(type:WImportedProfilePhoto.self),!Task.isCancelled,let image=UIImage(data:imported.data),let decoded=image.cgImage,WProfilePhotoPolicy.accepts(width:decoded.width,height:decoded.height)else{message="JPG · PNG · WebP 형식의 8MB 이하 사진을 선택해 주세요.";return};draft=image;message=""}catch{if !Task.isCancelled{message=error.localizedDescription}}}}
}
struct WPhotoCrop:View {
    var image:UIImage
    var commit:(Data)->Void
    var cancel:()->Void
    @State private var point=CGSize.zero
    @State private var anchor=CGSize.zero
    @State private var stageSide:CGFloat=340
    @State private var errorMessage=""
    var body:some View {VStack(spacing:12){Text("사진에서 사용할 부분을 골라요").font(W.font(15,.semibold));GeometryReader{geo in let side=geo.size.width;let fit=min(side/image.size.width,side/image.size.height);let displayed=CGSize(width:image.size.width*fit,height:image.size.height*fit);let cropDiameter=WProfilePhotoPolicy.cropDiameter(for:min(displayed.width,displayed.height))
            ZStack{Image(uiImage:image).resizable().scaledToFit().frame(width:side,height:side);WPhotoCropShade(diameter:cropDiameter,offset:point).fill(.black.opacity(0.56),style:FillStyle(eoFill:true));Circle().stroke(.white,lineWidth:2).frame(width:cropDiameter,height:cropDiameter).overlay(alignment:.bottom){Text("↔").font(W.font(19)).foregroundStyle(.white).frame(width:32,height:24).background(.black.opacity(0.48),in:Capsule()).offset(y:-10)}.offset(point).gesture(DragGesture().onChanged{v in let half=cropDiameter/2;point=CGSize(width:min(displayed.width/2-half,max(-displayed.width/2+half,anchor.width+v.translation.width)),height:min(displayed.height/2-half,max(-displayed.height/2+half,anchor.height+v.translation.height)))}.onEnded{_ in anchor=point})}.frame(width:side,height:side).background(Color.black).clipShape(RoundedRectangle(cornerRadius:14)).onAppear{stageSide=side}
        }.aspectRatio(1,contentMode:.fit)
        if !errorMessage.isEmpty{WNotice(text:errorMessage,danger:true)}
        HStack{Button("사진 적용"){let side:CGFloat=stageSide;let fit=min(side/image.size.width,side/image.size.height);let crop=WProfilePhotoPolicy.cropDiameter(for:min(image.size.width*fit,image.size.height*fit));let sourceSide=crop/fit;let center=CGPoint(x:image.size.width/2+point.width/fit,y:image.size.height/2+point.height/fit);let sourceRect=CGRect(x:center.x-sourceSide/2,y:center.y-sourceSide/2,width:sourceSide,height:sourceSide);if let data=WProfilePhotoPolicy.encode(image:image,crop:sourceRect){commit(data)}else{errorMessage="사진 용량을 줄이지 못했어요. 다른 사진을 선택해 주세요."}}.buttonStyle(WButtonStyle());Button("취소",action:cancel).buttonStyle(WButtonStyle(kind:1))}
    }}
}

enum WProfilePhotoPolicy {
    static let maximumInputBytes=8*1024*1024
    static let maximumOutputBytes=200*1024
    static let maximumPixels=20_000_000
    static let maximumEdge=8_192
    static let outputEdge=256

    static let initialZoom:CGFloat=1.35

    static func accepts(_ type:UTType)->Bool {
        type.conforms(to:.jpeg) || type.conforms(to:.png) || type.conforms(to:.webP)
    }

    static func accepts(byteCount:Int)->Bool {
        byteCount>0 && byteCount<=maximumInputBytes
    }

    static func accepts(width:Int,height:Int)->Bool {
        width>0 && height>0 && width<=maximumEdge && height<=maximumEdge && width<=maximumPixels/height
    }

    static func inspect(_ data:Data)->(type:UTType,width:Int,height:Int)? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),let identifier=CGImageSourceGetType(source),
              let type=UTType(identifier as String),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=(properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height=(properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else{return nil}
        return(type,width,height)
    }

    static func cropDiameter(for shorterSide:CGFloat)->CGFloat {
        shorterSide/initialZoom
    }

    static func sanitizeStored(_ data:Data?)->Data? {
        guard let data,data.count<=maximumOutputBytes,let info=inspect(data),
              info.type.conforms(to:.jpeg) || info.type.conforms(to:.png),
              info.width==outputEdge,info.height==outputEdge else{return nil}
        return data
    }

    static func validatedBytes(at url:URL)throws->Data {
        let values=try url.resourceValues(forKeys:[.fileSizeKey])
        guard let size=values.fileSize,accepts(byteCount:size) else{throw WProfilePhotoImportError.invalidPhoto}
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        guard accepts(byteCount:data.count),let info=inspect(data),accepts(info.type),accepts(width:info.width,height:info.height) else{throw WProfilePhotoImportError.invalidPhoto}
        return data
    }

    static func encode(image:UIImage,crop:CGRect)->Data? {
        guard crop.width>0,crop.height>0 else{return nil}
        let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque=true
        let size=CGSize(width:outputEdge,height:outputEdge)
        let renderer=UIGraphicsImageRenderer(size:size,format:format)
        let normalized=renderer.image{_ in
            let scale=CGFloat(outputEdge)/crop.width
            image.draw(in:CGRect(x:-crop.minX*scale,y:-crop.minY*scale,width:image.size.width*scale,height:image.size.height*scale))
        }
        for quality in [0.88,0.76,0.6,0.45] {
            if let data=normalized.jpegData(compressionQuality:quality),data.count<=maximumOutputBytes,
               let decoded=UIImage(data:data)?.cgImage,decoded.width==outputEdge,decoded.height==outputEdge{return data}
        }
        return nil
    }
}

private struct WImportedProfilePhoto:Transferable {
    let data:Data
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.image){received in
            WImportedProfilePhoto(data:try WProfilePhotoPolicy.validatedBytes(at:received.file))
        }
    }
}

private enum WProfilePhotoImportError:LocalizedError {
    case invalidPhoto
    var errorDescription:String?{"JPG · PNG · WebP 형식의 8MB 이하, 2,000만 화소 이하 사진을 선택해 주세요."}
}

struct WPhotoCropShade:Shape {
    var diameter:CGFloat
    var offset:CGSize
    func path(in rect:CGRect)->Path {
        var path=Path();path.addRect(rect)
        path.addEllipse(in:CGRect(x:rect.midX+offset.width-diameter/2,y:rect.midY+offset.height-diameter/2,width:diameter,height:diameter))
        return path
    }
}

struct WRegionPicker:View {
    @Binding var selection:String
    @State private var expanded=false
    var body:some View {Button{expanded.toggle()}label:{HStack{Text(selection.isEmpty ? "선택 안 함":selection);Spacer();Image(systemName:"chevron.down")}.font(W.font(14)).padding(14).frame(minHeight:54).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.border))}.accessibilityLabel("활동 지역").overlay(alignment:.top){if expanded{VStack(spacing:0){ForEach(["선택 안 함","모브시 북부권","모브시 중부권","모브시 남부권"],id:\.self){region in Button{selection=region;expanded=false}label:{HStack{Text(region);Spacer();if region==selection{Image(systemName:"checkmark").foregroundStyle(W.lime)}}.font(W.font(14)).padding(.horizontal,14).frame(minHeight:48)}}}.padding(8).background(W.paper,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(W.line)).shadow(color:.black.opacity(0.12),radius:18,y:8).offset(y:58)}}.zIndex(10).accessibilityAction(.escape){expanded=false}}
}

// Original RunningAvatar fallback SVG: circle (12,8,3.5) and open shoulder arc.
struct WAvatarPlaceholder:Shape {
    func path(in rect:CGRect)->Path {
        var p=Path();p.addEllipse(in:CGRect(x:8.5,y:4.5,width:7,height:7));p.move(to:CGPoint(x:5,y:21));p.addLine(to:CGPoint(x:5,y:19));p.addArc(center:CGPoint(x:12,y:19),radius:7,startAngle:.degrees(180),endAngle:.degrees(0),clockwise:false);p.addLine(to:CGPoint(x:19,y:21));return p.applying(CGAffineTransform(scaleX:rect.width/24,y:rect.height/24))
    }
}
