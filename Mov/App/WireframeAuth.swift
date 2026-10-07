import SwiftUI
extension WireframeRoot {
    var authForm:some View {
        let id=ui.screen
        let title=["A07":"회원가입","A10":"비밀번호 찾기","A12":"새 비밀번호","A16":"이메일 로그인 연결","A17":"이메일 로그인 관리"][id] ?? ""
        return VStack(spacing:0){
            if id != "A01"{WHeader(title:title,back:{authBack(id)})}
            ScrollView{VStack(alignment:.leading,spacing:18){
                if id=="A01"{VStack(alignment:.leading,spacing:24){BrandMark(size:84);Text("오늘의 달리기를\n나의 기록으로").font(W.font(25,.bold)).lineSpacing(6)}}
                else{WHeading(text:["A07":"모브와 함께 시작해요","A10":"비밀번호를\n다시 설정해요","A12":"새 비밀번호를 설정해요","A16":"이메일로도 로그인해요","A17":"비밀번호를 관리해요"][id] ?? "")}
                if id != "A01"{WText(text:id=="A07" ? "이메일과 비밀번호로 시작해요.":id=="A10" ? "가입할 때 사용한 이메일을 입력해 주세요.":id=="A16" ? "현재 계정에 이메일 로그인 수단을 추가해요.":"새 비밀번호를 입력하고 확인해 주세요.")}
                authDemoNote
                VStack(alignment:.leading,spacing:0){
                    VStack(alignment:.leading,spacing:16){
                        if !["A12","A17"].contains(id){authField("이메일",value:"",email:true)}
                        if id != "A10"{authField(id=="A17" ? "현재 비밀번호":id=="A12" ? "새 비밀번호":"비밀번호",value:"")}
                        if ["A07","A12","A16","A17"].contains(id){authField(id=="A17" ? "새 비밀번호":id=="A12" ? "새 비밀번호 확인":"비밀번호 확인",value:"")}
                        if id=="A17"{authField("새 비밀번호 확인",value:"")}
                    }
                    if reviewTools{Button{ui.authFilled=true;ui.authEmail="runner@example.test";ui.authPassword="MovDemo482619";ui.authConfirm=ui.authPassword;ui.authCurrent=ui.authPassword;ui.error=""}label:{Text("가상 예시값 채우기").font(W.font(12)).frame(maxWidth:.infinity,minHeight:36,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain)}
                    if !ui.error.isEmpty && ui.authErrorField.isEmpty{WAuthNotice(text:ui.error,danger:true).padding(.vertical,8)}
                    Button(authSubmitTitle(id)){submitAuth(id)}.buttonStyle(WButtonStyle()).padding(.top,9).accessibilityIdentifier("authPrimary")
                }
                if id=="A01"{
                    VStack(spacing:0){
                        HStack(spacing:24){Button("회원가입"){ui.authFilled=false;ui.provider="이메일";go("A07")};Button("비밀번호 찾기"){ui.authFilled=false;ui.resetBack="A01";go("A10")}}.buttonStyle(.plain).font(W.font(12,.semibold)).frame(maxWidth:.infinity,minHeight:44)
                        HStack(spacing:12){W.line.frame(height:1);Text("또는 소셜 계정으로").font(W.font(12)).fixedSize();W.line.frame(height:1)}.frame(height:18).padding(.top,14).padding(.bottom,16)
                        HStack(spacing:18){ForEach(["카카오","네이버","Google","Apple"],id:\.self){provider in Button{ui.provider=provider;go("A14")}label:{providerMark(provider)}.accessibilityLabel(provider+"로 로그인")}}.frame(maxWidth:.infinity)
                        authDemoNote.frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)
                    }.padding(.top,-13)
                }
                if id=="A17"{VStack(alignment:.leading,spacing:0){Button("비밀번호 재설정"){ui.resetBack="T05";go("A10")}.font(W.font(13)).frame(minHeight:44);Button("이메일 로그인 연결 해제"){ui.provider="이메일";go(ui.profile.providers.count>1 ? "T08":"T09")}.font(W.font(13)).frame(minHeight:44)}}
                if id=="A16"{authDemoNote}
            }.padding(.horizontal,24).padding(.top,id=="A01" ? 26:24).padding(.bottom,24)}.scrollDismissesKeyboard(.immediately).modifier(WAuthBodyMotion())
            if id != "A01"{Button(id=="A07" ? "가입 취소":"취소"){ui.authFilled=false;if ["A10","A12"].contains(id){go(ui.resetBack)}else{authBack(id)}}.buttonStyle(WButtonStyle(kind:1)).padding(.horizontal,24).padding(.top,16).padding(.bottom,24).overlay(alignment:.top){W.line.frame(height:1)}}
        }
    }
    func authBack(_ id:String){
        if ["A16","A17"].contains(id){go("T05")}
        else if id=="A12"{go("A11")}
        else if ["A07","A10"].contains(id){go(id=="A10" ? ui.resetBack:"A01")}
        else{back()}
    }
    func submitAuth(_ id:String){
        guard ui.screen==id else{return}
        if ["A16","A17"].contains(id) && !ui.settingsGrant{ui.pending=id;go("T15");return}
        guard validateAuth(id) else{return}
        switch id {
        case "A01":ui.profile.logged=true;ui.save();go("H00")
        case "A07":ui.consentTerms=false;ui.consentPrivacy=false;ui.verified=false;ui.code="";ui.codeAttempts=0;ui.challengeCode="482619";ui.challengeIssued=Date();go("A19")
        case "A10":go("A11")
        case "A12":ui.profile.logged=false;ui.save();go("A13")
        case "A16":ui.passwordChanged=false;if !ui.profile.providers.contains("이메일"){ui.profile.providers.append("이메일")};ui.save();go("A18")
        case "A17":ui.profile.logged=false;ui.save();ui.authFilled=false;ui.passwordChanged=true;go("A18")
        default:break
        }
    }
    @ViewBuilder var authDemoNote:some View {if reviewTools{Text("SIMULATION · 가상 값으로만 확인해 주세요\n실제 가입·인증·메일 발송 없이 동작해요").font(W.font(11)).lineSpacing(5).foregroundStyle(W.muted).fixedSize(horizontal:false,vertical:true)}}
    func authSubmitTitle(_ id:String)->String {
        if reviewTools{return ["A01":"데모 로그인","A07":"다음 · 이메일 인증","A10":"재설정 요청 예시 보기","A12":"변경 완료 화면 보기","A16":"이메일 로그인 연결 · 데모","A17":"변경 완료 화면 보기"][id] ?? "계속"}
        return ["A01":"로그인","A07":"다음","A10":"계속","A12":"비밀번호 변경","A16":"연결하기","A17":"비밀번호 변경"][id] ?? "계속"
    }
    func acceptConsents(){
        guard ui.screen=="A02", !ui.consentBusy else{return}
        if ui.consentTerms != ui.consentPrivacy{ui.error="필수 항목을 모두 확인해 주세요.";return}
        if ui.consentTerms && ui.consentPrivacy{ui.nickname="";go("A03");return}
        ui.consentBusy=true
        Task { @MainActor in
            if !reduceMotion{try? await Task.sleep(for:.milliseconds(40))}
            guard ui.screen=="A02" else{ui.consentBusy=false;return};withAnimation(reduceMotion ? nil:.easeOut(duration:0.16)){ui.consentTerms=true}
            if !reduceMotion{try? await Task.sleep(for:.milliseconds(90))}
            guard ui.screen=="A02" else{ui.consentBusy=false;return};withAnimation(reduceMotion ? nil:.easeOut(duration:0.16)){ui.consentPrivacy=true}
            if !reduceMotion{try? await Task.sleep(for:.milliseconds(290))}
            guard ui.screen=="A02" else{ui.consentBusy=false;return};ui.consentBusy=false;ui.nickname="";go("A03")
        }
    }
    func validateAuth(_ id:String)->Bool {
        ui.error="";ui.authErrorField=""
        if !["A12","A17"].contains(id) && !WAuthValidation.email(ui.authEmail){ui.authErrorField="이메일";ui.error=ui.authEmail.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "이메일을 입력해 주세요.":"이메일 형식을 확인해 주세요.";return false}
        if id=="A17" && !WAuthValidation.password(ui.authCurrent){ui.authErrorField="현재 비밀번호";ui.error="8~128자의 비밀번호를 입력해 주세요.";return false}
        if id != "A10" && !WAuthValidation.password(ui.authPassword){ui.authErrorField=["A12","A17"].contains(id) ? "새 비밀번호":"비밀번호";ui.error="8~128자의 비밀번호를 입력해 주세요.";return false}
        if ["A07","A12","A16","A17"].contains(id) && ui.authPassword != ui.authConfirm{ui.authErrorField=["A12","A17"].contains(id) ? "새 비밀번호 확인":"비밀번호 확인";ui.error="비밀번호가 서로 달라요.";return false}
        return true
    }
    func authField(_ label:String,value:String,email:Bool=false)->some View {
        let fieldID=email ? "auth-email":label.contains("확인") ? "auth-confirm":label.contains("현재") ? "auth-current":"auth-password"
        let revealed=ui.revealedFields.contains(label)
        let binding=email ? $ui.authEmail:label.contains("확인") ? $ui.authConfirm:label.contains("현재") ? $ui.authCurrent:$ui.authPassword
        return VStack(alignment:.leading,spacing:8){Text(label).font(W.font(13,.medium)).frame(height:18.85,alignment:.leading);HStack{if email{TextField("",text:binding,prompt:Text(verbatim:"runner@example.test").foregroundStyle(W.muted)).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier(fieldID).focused($authInput,equals:fieldID).submitLabel(.done).onSubmit{authInput=nil}}else if revealed{TextField("",text:binding,prompt:Text("비밀번호 8자 이상").foregroundStyle(W.muted)).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier(fieldID).focused($authInput,equals:fieldID).submitLabel(.done).onSubmit{authInput=nil}}else{SecureField("",text:binding,prompt:Text("비밀번호 8자 이상").foregroundStyle(W.muted)).textContentType(nil).accessibilityIdentifier(fieldID).focused($authInput,equals:fieldID).submitLabel(.done).onSubmit{authInput=nil}};if !email{Button{if revealed{ui.revealedFields.remove(label)}else{ui.revealedFields.insert(label)}}label:{WEyeIcon(revealed:revealed).stroke(W.muted,style:StrokeStyle(lineWidth:1.125,lineCap:.round,lineJoin:.round)).frame(width:18,height:18).frame(width:30,height:44)}.accessibilityLabel(label+(revealed ? " 숨기기":" 보기")).accessibilityIdentifier("auth-reveal-\(fieldID)")}}.font(W.font(14)).foregroundStyle(W.ink).padding(14).frame(height:52).background(W.soft,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(ui.authErrorField==label && !ui.error.isEmpty ? Color.wire(0xA92D32,0xFF9CA3):W.line));if ui.authErrorField==label && !ui.error.isEmpty{Text(ui.error).font(W.font(12)).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3)).fixedSize(horizontal:false,vertical:true)};if email && reviewTools{Text("실제 주소 대신 example.test 예시 주소를 써 주세요").font(W.font(11)).foregroundStyle(W.muted).padding(.bottom,26)}}
    }
    func providerMark(_ name:String)->some View {Group{if name=="이메일"{BrandMark(size:28).frame(width:48,height:48).background(W.soft,in:Circle())}else if !name.isEmpty{Image("Provider-"+["카카오":"kakao","네이버":"naver","Google":"google","Apple":"apple"][name,default:"google"]).resizable().scaledToFit().frame(width:48,height:48).clipShape(Circle())}}}
    var consents:some View {WPage(title:"시작하기",back:back){WText(text:"01 / 02",small:true).offset(y:6);WHeading(text:"먼저 확인해 주세요");WText(text:"필수 항목을 확인하고 동의해 주세요.");consentRow("이용약관 동의 (필수)",value:$ui.consentTerms);consentRow("개인정보 수집·이용 동의 (필수)",value:$ui.consentPrivacy).padding(.top,-18);WText(text:"아래 버튼은 위의 필수 항목 2개에만 적용돼요.",small:true);if !ui.error.isEmpty{Text(ui.error).font(W.font(12)).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3))};WAuthNotice(text:"운동 기록은 이 기기에 저장돼요. 앱 삭제나 기기 분실 시 복구가 어려울 수 있어요. 클라우드 백업은 별도 검토 중이에요.")}actions:{Button(ui.consentTerms == ui.consentPrivacy ? "모두 동의하고 계속":"동의하고 계속"){acceptConsents()}.buttonStyle(WButtonStyle()).disabled(ui.consentBusy)}}
    func consentRow(_ label:String,value:Binding<Bool>)->some View {
        HStack(alignment:.top,spacing:12){
            WCheck().stroke(value.wrappedValue ? W.lime:W.muted,style:StrokeStyle(lineWidth:2.1,lineCap:.round,lineJoin:.round)).frame(width:21,height:21).padding(.top,1)
            VStack(alignment:.leading,spacing:0){Text(label).font(W.font(14)).kerning(-0.21).frame(height:23.1,alignment:.leading)
                Button("내용 확인"){ui.consentTopic=label.contains("개인정보") ? "개인정보 수집·이용":"이용약관";go("A06")}.buttonStyle(.plain).font(W.font(12,.semibold)).frame(minHeight:44)
            }
            Spacer(minLength:0)
        }.padding(.vertical,18).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        .onTapGesture{withAnimation(reduceMotion ? nil:.easeOut(duration:0.16)){value.wrappedValue.toggle()}}
        .accessibilityElement(children:.contain).accessibilityLabel(label).accessibilityValue(value.wrappedValue ? "동의함":"동의 안 함")
        .overlay(alignment:.bottom){W.line.frame(height:1)}
    }
    var verification:some View {WSecondTicker{now in
        let elapsed=ui.challengeIssued.map{now.timeIntervalSince($0)} ?? 0
        let missing=ui.challengeIssued==nil
        let expired=elapsed>=300
        let locked=ui.screen=="A22"
        let disabled=missing || expired || locked
        WPage(title:"이메일 인증",back:{go("A07")}){
            WHeading(text:"이메일을 확인해요")
            WText(text:ui.authEmail.isEmpty ? "이메일":ui.authEmail)
            if reviewTools{VStack(alignment:.leading,spacing:3){Text("DEMO · 실제 메일은 발송되지 않아요").font(W.font(13));if !missing{(Text("화면 검토용 공개 예시 코드 ").font(W.font(13))+Text(ui.challengeCode).font(W.font(19,.semibold)).tracking(2)).accessibilityIdentifier("publicDemoEmailCode")}}.lineSpacing(6).frame(maxWidth:.infinity,minHeight:missing ? 22:47,alignment:.leading).padding(.vertical,15).padding(.horizontal,16).background(W.soft,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line))}
            if ui.screen=="A23"{Text("새 코드를 준비했어요. 이전 코드는 사용할 수 없어요.").font(W.font(13)).lineSpacing(6).fixedSize(horizontal:false,vertical:true)}
            VStack(alignment:.leading,spacing:0){
                Text("인증 코드 6자리").font(W.font(13,.medium)).padding(.bottom,10)
                ZStack{
                    HStack(spacing:8){ForEach(0..<6){i in Text(ui.code.count>i ? String(Array(ui.code)[i]):" ").font(W.font(24,.medium)).frame(maxWidth:.infinity,minHeight:56).background(W.soft,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(!ui.error.isEmpty && !missing ? Color(red:1,green:90/255,blue:95/255):otpInputFocused && i==min(5,ui.code.count) && !disabled ? W.lime:Color.clear)).animation(reduceMotion ? nil:.easeOut(duration:0.16),value:otpInputFocused)}}
                    TextField("",text:$ui.code).keyboardType(.numberPad).textContentType(.oneTimeCode).foregroundStyle(.clear).tint(.clear).focused($otpInputFocused).accessibilityLabel("인증 코드 6자리").accessibilityIdentifier("emailOtpInput").disabled(disabled).onChange(of:ui.code){_,v in ui.code=String(v.filter{("0"..."9").contains($0)}.prefix(6));if ui.code.count==6{otpInputFocused=false}}
                }.padding(.bottom,12)
                Text("인증 코드 6자리를 입력해 주세요").font(W.font(11)).foregroundStyle(W.muted).padding(.bottom,5)
                Text(missing ? "회원가입 정보 입력부터 다시 시작해 주세요.":expired ? "코드가 만료됐어요. 새 코드를 요청해 주세요.":locked ? "현재 코드는 잠겼어요. 새 코드를 요청해 주세요.":"코드 유효 시간 \(max(0,300-Int(elapsed))/60):\(String(format:"%02d",max(0,300-Int(elapsed))%60))").font(W.font(11)).foregroundStyle(W.muted)
                if !ui.error.isEmpty && !missing{Text(ui.error).font(W.font(12)).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3)).padding(.top,5)}
                if reviewTools{Button{ui.code=ui.challengeCode}label:{Text("예시 코드 입력").font(W.font(12)).frame(maxWidth:.infinity,minHeight:36,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier("fillDemoEmailCode")}
                Button("인증하고 계속"){
                    guard WireState.otpScreens.contains(ui.screen), !disabled else{return}
                    if ui.code==ui.challengeCode{ui.verified=true;ui.consentTerms=false;ui.consentPrivacy=false;go("A02");ui.otpSuccess=true;Task{@MainActor in try? await Task.sleep(for:.milliseconds(1100));ui.otpSuccess=false}}
                    else{ui.codeAttempts+=1;ui.screen=ui.codeAttempts>=5 ? "A22":"A20";ui.error=ui.codeAttempts>=5 ? "잘못된 입력이 5회 쌓여 현재 코드가 잠겼어요. 새 코드를 요청해 주세요.":"코드가 일치하지 않아요. \(5-ui.codeAttempts)번 더 시도할 수 있어요."}
                }.buttonStyle(WButtonStyle()).padding(.top,9).disabled(ui.code.count != 6 || disabled).accessibilityIdentifier("verifyEmailCode")
                Button(!missing && elapsed<30 ? "새 인증 코드 요청 · \(max(0,30-Int(elapsed)))초 후":"새 인증 코드 요청"){
                    ui.code="";ui.codeAttempts=0;ui.challengeCode=ui.challengeCode=="482619" ? "731204":"482619";ui.challengeIssued=Date();go("A23")
                }.buttonStyle(.plain).font(W.font(12)).foregroundStyle(missing || elapsed<30 ? W.muted:W.ink).frame(minHeight:44).disabled(missing || elapsed<30).accessibilityIdentifier("requestNewEmailCode")
                Text("유효 시간 5분 · 재요청 간격 30초\n코드마다 최대 5회 입력할 수 있어요").font(W.font(11)).lineSpacing(5).foregroundStyle(W.muted).padding(.top,14)
            }
        }actions:{button("이메일 다시 입력","A07",kind:1);Button("가입 취소"){ui.code="";ui.verified=false;ui.challengeIssued=nil;go("A01")}.font(W.font(13)).frame(maxWidth:.infinity,minHeight:32,alignment:.leading)}
    }}
    var providers:some View {WPage(title:"로그인 수단",back:back){Text("하나의 계정에 연결해요").font(W.font(22,.semibold));WText(text:"이름이나 이메일만으로\n계정을 합치지 않아요.");VStack(spacing:0){ForEach(["이메일","카카오","네이버","Google","Apple"],id:\.self){p in Button{ui.provider=p;if p=="이메일"{ui.pending=ui.profile.providers.contains(p) ? "A17":"A16";go("T15")}else if ui.profile.providers.contains(p){go(ui.profile.providers.count>1 ? "T08":"T09")}else{ui.pending="T06";go("T15")}}label:{HStack(spacing:14){providerMark(p);VStack(alignment:.leading,spacing:6){Text(p=="이메일" ? "이메일 · 비밀번호":p).font(W.font(14,.medium));WText(text:ui.profile.providers.contains(p) ? "이 계정에 연결됨":"연결되지 않음",small:true)};Spacer();Text(ui.profile.providers.contains(p) ? (p=="이메일" ? "관리":"해제"):"연결").font(W.font(12))}.frame(minHeight:85).overlay(alignment:.bottom){W.line.frame(height:1)}}}};WAuthNotice(text:"현재 계정을 확인한 뒤 새 로그인 수단을 연결해요.",sourceWrapping:true)}actions:{}}
    var deleteAccount:some View {WPage(title:"회원 탈퇴",back:back){WHeading(text:"계정을 삭제하기 전\n확인해 주세요").padding(.top,9);WText(text:"계정과 연결된 로그인 수단을 삭제하는 흐름이에요. 기기 기록 삭제와 범위가 달라요.");Text("실제 삭제 범위·법정 보존·처리 시간은 출시 정책에서 확정해야 해요. 이 데모는 실제 회원·기록을 삭제하지 않아요.").font(W.font(13)).kerning(-0.195).lineSpacing(6).fixedSize(horizontal:false,vertical:true).offset(y:-1).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).padding(16).background(Color.wire(0xFFF1F1,0x3C2024),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color.wire(0xF0BFC3,0x83535A))).padding(.top,4).accessibilityIdentifier("accountDeletionImpactNotice");Button{ui.deleteConsent.toggle()}label:{HStack(alignment:.top){WCheck().stroke(ui.deleteConsent ? W.lime:W.muted,style:StrokeStyle(lineWidth:2.1,lineCap:.round,lineJoin:.round)).frame(width:21,height:21).padding(.trailing,4).padding(.top,2);VStack(alignment:.leading,spacing:4){Text("삭제 흐름의 영향 설명을 확인했어요").font(W.font(14)).kerning(-0.21);Text("실제 삭제가 아닌 시뮬레이션이에요").font(W.font(12)).foregroundStyle(W.muted)}.lineSpacing(5).multilineTextAlignment(.leading)}.frame(minHeight:80,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading).overlay(alignment:.bottom){W.line.frame(height:1)}}.buttonStyle(.plain).accessibilityIdentifier("accountDeletionImpactAcknowledgement").accessibilityAddTraits(ui.deleteConsent ? .isSelected:[])}actions:{Button(reviewTools ? "삭제 흐름 확인 · 시뮬레이션":"탈퇴하기"){if reviewTools{go("T16")}else{infoAction("delete-account-demo")}}.buttonStyle(WButtonStyle(kind:2)).disabled(!ui.deleteConsent).accessibilityIdentifier("confirmAccountDeletion");button("계정 유지","T01",kind:1)}}
}

// Offline example input constraints from the original auth adapter; no credential persistence.
enum WAuthValidation {
    static func email(_ value:String)->Bool {
        let value=value.trimmingCharacters(in:.whitespacesAndNewlines)
        return value.count<=254 && value.range(of:#"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@example\.test$"#,options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func password(_ value:String)->Bool {(8...128).contains(value.count)}
}
struct WAuthNotice:View {
    let text:String;var danger=false;var sourceWrapping=false
    var body:some View {Group{if sourceWrapping{WAuthSourceParagraph(text:text,color:danger ? Color.wire(0xA92D32,0xFF9CA3):Color.wire(0x535353,0xD0D0D0))}else{Text(text).font(W.font(13)).kerning(-0.195).lineSpacing(6).fixedSize(horizontal:false,vertical:true).foregroundStyle(danger ? Color.wire(0xA92D32,0xFF9CA3):W.muted)}}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,sourceWrapping ? 16:19).padding(.horizontal,16).background(danger ? Color.wire(0xFFF1F1,0x3C2024):W.soft,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(danger ? Color.wire(0xF0BFC3,0x83535A):W.line))}
}
struct WOTPSuccess:View {
    let reduced:Bool
    @State private var line=false
    @State private var check=false
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack(spacing:14){
                VStack(spacing:5){HStack(spacing:5){ForEach(0..<6){_ in RoundedRectangle(cornerRadius:5).fill(W.soft).frame(height:22)}}
                    Rectangle().fill(W.lime).frame(height:2).scaleEffect(x:line ? 1:0,y:1,anchor:.leading)
                }
                WCheck().stroke(W.lime,style:StrokeStyle(lineWidth:2.2,lineCap:.round,lineJoin:.round)).frame(width:24,height:24).opacity(check ? 1:0).offset(y:check ? 0:3)
            }
            Text("이메일 확인 완료").font(W.font(14,.medium)).frame(height:21)
        }.padding(.vertical,18).padding(.horizontal,20).background(W.paper,in:RoundedRectangle(cornerRadius:16)).shadow(color:.black.opacity(0.07),radius:16,x:0,y:8).accessibilityIdentifier("otpSuccessFeedback")
        .task{withAnimation(reduced ? nil:.timingCurve(0.2,0.7,0.2,1,duration:0.28)){line=true};if !reduced{try? await Task.sleep(for:.milliseconds(180))};withAnimation(reduced ? nil:.easeOut(duration:0.18)){check=true}}
    }
}

private struct WSecondTicker<Content:View>:View {
    @State private var now=Date()
    @ViewBuilder var content:(Date)->Content
    var body:some View {
        content(now).task {
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(1))
                guard !Task.isCancelled else{break}
                now=Date()
            }
        }
    }
}

// Original RunningMotion: only the page body enters 20px forward / -16px back.
// Header and fixed action area stay still; reduced motion settles immediately.
struct WAuthMotionContext {var enabled=false;var reduced=false;var forward=true}
private struct WAuthMotionKey:EnvironmentKey {static let defaultValue=WAuthMotionContext()}
extension EnvironmentValues {
    var authPageMotion:WAuthMotionContext {get{self[WAuthMotionKey.self]}set{self[WAuthMotionKey.self]=newValue}}
}
struct WAuthBodyMotion:ViewModifier {
    @Environment(\.authPageMotion) private var motion
    @State private var entered=false
    func body(content:Content)->some View {
        content.offset(x:motion.enabled && !motion.reduced && !entered ? (motion.forward ? 20:-16):0)
            .opacity(motion.enabled && !motion.reduced && !entered ? 0.7:1)
            .task{withAnimation(motion.enabled && !motion.reduced ? .timingCurve(0.16,1,0.3,1,duration:0.24):nil){entered=true}}
    }
}

// CSS keep-all uses greedy Hangul word wrapping; SwiftUI Text balances short lines.
// Scoped to the reviewed account paragraphs; no forced line breaks or font scaling.
struct WAuthSourceParagraph:UIViewRepresentable {
    let text:String
    var size:CGFloat=13
    var lineHeight:CGFloat=22.1
    var color:Color=W.muted
    func makeUIView(context:Context)->UILabel {
        let label=UILabel();label.numberOfLines=0;label.lineBreakMode = .byWordWrapping
        label.lineBreakStrategy = .hangulWordPriority
        label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return label
    }
    func updateUIView(_ label:UILabel,context:Context) {
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = .hangulWordPriority
        paragraph.minimumLineHeight=lineHeight;paragraph.maximumLineHeight=lineHeight
        let font=UIFontMetrics(forTextStyle:.body).scaledFont(for:UIFont(name:"PretendardVariable-Regular",size:size)!)
        label.attributedText=NSAttributedString(string:text,attributes:[.font:font,.kern:-size*0.015,.paragraphStyle:paragraph,.foregroundColor:UIColor(color)])
        label.accessibilityLabel=text
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:UILabel,context:Context)->CGSize? {
        guard let width=proposal.width else{return nil}
        return uiView.sizeThatFits(CGSize(width:width,height:.greatestFiniteMagnitude))
    }
}
