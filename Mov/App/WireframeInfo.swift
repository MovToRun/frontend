import SwiftUI
struct WInfo {
    var title:String;var heading:String;var text:String;var notice:String="";var buttons:[(String,String,Int)]=[]
}
extension WireframeRoot {
    var info:WInfo {
        if reviewTools{return reviewInfo}
        switch ui.screen {
        case "A06":return .init(title:"동의 내용",heading:ui.consentTopic,text:"서비스 이용과 개인정보 처리 내용을 확인해 주세요.",notice:"운동 기록과 프로필은 이 기기에 저장돼요. 앱 삭제 시 복구가 어려울 수 있어요.",buttons:[("확인했어요","consent-reviewed",0)])
        case "A11":return .init(title:"비밀번호 재설정",heading:"새 비밀번호를\n설정해 주세요",text:"입력한 이메일을 확인하고 계속해 주세요.",buttons:[("계속","A12",0),("이메일 다시 입력","A10",1),("취소","reset-cancel",3)])
        case "A13":return .init(title:"비밀번호 재설정",heading:"다시 로그인해 주세요",text:"설정을 마쳤어요. 로그인 화면으로 돌아가요.",buttons:[("로그인으로","A01",0)])
        case "A14":return .init(title:"소셜 로그인",heading:(ui.provider.isEmpty ? "소셜 계정":ui.provider)+"로\n계속할까요?",text:"선택한 로그인 수단으로 시작해요.",buttons:[((ui.provider.isEmpty ? "선택한 계정":ui.provider)+"로 계속","social-success",0),("취소","A01",1)])
        case "A15":return .init(title:"시작하기",heading:"이제 달려 볼까요?",text:"러닝 프로필이 준비됐어요.",buttons:[("홈으로","H00",0)])
        case "A18":return .init(title:"이메일 로그인",heading:ui.passwordChanged ? "다시 로그인해 주세요":"이메일 로그인을 연결했어요",text:ui.passwordChanged ? "설정을 마쳤어요. 로그인 화면으로 돌아가요.":"로그인 수단에서 연결 상태를 확인할 수 있어요.",buttons:[(ui.passwordChanged ? "다시 로그인":"로그인 수단 확인",ui.passwordChanged ? "A01":"T05",0)])
        case "H11":return .init(title:"시간대 변경",heading:"주간 기준이\n달라질 수 있어요",text:"통계는 기기의 시간대를 따라요.",buttons:[("확인했어요","H07",0)])
        case "P01":return .init(title:"위치 접근",heading:"달린 길을\n기록할 준비",text:"거리와 경로를 기록하려면 위치 접근이 필요해요.",buttons:[("계속","start-local",0),("지금은 허용하지 않기","P02",1)])
        case "P02":var page=reviewInfo;page.notice="기기 설정에서 위치 접근과 정확한 위치를 확인해 주세요.";return page
        case "P04":return .init(title:"설정 변경 안내",heading:"위치 접근과\n정확한 위치 확인",text:"기기 설정에서 위치 접근을 확인해 주세요.",buttons:[("러닝으로 돌아가기","H01",0)])
        case "P05":var page=reviewInfo;page.buttons=[("다시 시도","H01",0),("홈으로","H00",1)];return page
        case "R11":var page=reviewInfo;page.notice="삭제한 임시 기록은 복구할 수 없어요.";return page
        case "L07":var page=reviewInfo;page.notice="삭제한 기록은 복구할 수 없어요. 이 기기의 합계와 통계에서도 제외돼요.";return page
        case "T06":var page=reviewInfo;page.text="현재 계정에 로그인 수단을 추가해요.";page.notice="현재 계정의 러닝 기록은 유지돼요.";page.buttons=[("연결하기","link",0),("취소","T05",1)];return page
        case "T07":return .init(title:"로그인 안내",heading:"카카오로\n계속할까요?",text:"현재 기기의 프로필로 돌아가요.",buttons:[("카카오로 계속","local-login",0),("다른 방법으로 로그인","A01",1)])
        case "T10":var page=reviewInfo;page.notice="이 기기에 저장한 기록은 유지돼요.";return page
        case "T12":return .init(title:"탈퇴 완료",heading:"프로필을 초기화했어요",text:"로그인 화면에서 다시 시작할 수 있어요.",buttons:[("로그인으로","A01",0)])
        case "T13":var page=reviewInfo;page.notice="이 기기에 저장된 모든 러닝 기록을 삭제해요. 프로필과 로그인 수단은 유지돼요. 삭제한 기록은 복구할 수 없어요.";page.buttons=[("기기 기록 삭제","clear-device",2),("기록 유지","T04",1)];return page
        case "T15":return .init(title:"현재 계정 확인",heading:"지금 계정을\n먼저 확인해요",text:"연결된 로그인 수단으로 계속해 주세요.",buttons:[((ui.profile.providers.first ?? "카카오")+"로 계속","reauth",0),("취소","T05",1)])
        case "T16":return .init(title:"탈퇴 확인",heading:"탈퇴를\n마칠까요?",text:"현재 프로필과 로그인 수단을 초기화해요.",buttons:[("탈퇴하기","delete-account-demo",0),("취소","T01",1)])
        case "T17":var page=reviewInfo;page.notice="";return page
        default:return reviewInfo
        }
    }
    var reviewInfo:WInfo {
        switch ui.screen {
        case "A04":return .init(title:"로그인",heading:"로그인을 마치지\n못했어요",text:"인증이 취소됐거나 연결이 끊겼어요.\n아직 새 계정을 만들지 않았어요.",notice:"같은 로그인 수단으로 다시 시도하거나 다른 수단을 선택할 수 있어요.",buttons:[("다시 시도","A01",0)])
        case "A06":return .init(title:"동의 내용 검토",heading:ui.consentTopic,text:"이 화면은 최종 약관이 아닌\n고지 구조 검토안이에요.",notice:"운영 주체, 처리 근거, 보존 기간, 문의처와 최종 문구는 출시 전 확정이 필요해요.",buttons:[("확인했어요","consent-reviewed",0)])
        case "A11":return .init(title:"재설정 요청",heading:"요청 확인 화면이에요",text:"메일은 발송되지 않았어요.\n계정이 있는지도 확인하지 않았어요.",notice:"아래 버튼으로 새 비밀번호 UI 데모를 확인할 수 있어요. 실제 인증 링크나 토큰은 없어요.",buttons:[("새 비밀번호 UI 데모","A12",0),("예시 이메일 다시 입력","A10",1),("취소하고 돌아가기","reset-cancel",3)])
        case "A13":return .init(title:"재설정 완료",heading:"완료 화면까지 확인했어요",text:"이 흐름은 UI 데모예요.\n실제 비밀번호는 바뀌지 않았어요.",buttons:[(ui.resetBack=="T05" ? "로그인 수단으로":"로그인으로","reset-cancel",0)])
        case "A14":return .init(title:"소셜 로그인",heading:(ui.provider.isEmpty ? "소셜":ui.provider)+" 로그인 예시",text:"실제 제공자에 연결하지 않아요.\n아래에서 가상 인증 결과를 선택해 주세요.",buttons:[("인증 성공 · 예시","social-success",0),("인증 오류 · 예시","A04",1),("인증 취소","A01",3)])
        case "A15":return .init(title:"회원가입",heading:"이제 달려 볼까요?",text:"기기 안의 데모 프로필이 준비됐어요.\n실제 회원가입은 하지 않았어요.",buttons:[("홈으로","H00",0),("로그인 화면 보기","A01",1)])
        case "A18":return .init(title:"이메일 로그인",heading:ui.passwordChanged ? "변경 완료 화면이에요":"이메일 로그인을 연결했어요",text:ui.passwordChanged ? "실제 비밀번호는 바뀌지 않았어요.\n변경 데모를 마쳐 다시 로그인해야 해요.\n입력한 비밀번호는 보관하지 않아요.":"이 브라우저의 데모 연결 상태만 바뀌었어요.\n입력한 비밀번호는 보관하지 않아요.",buttons:[(ui.passwordChanged ? "다시 로그인":"로그인 수단 확인",ui.passwordChanged ? "A01":"T05",0)])
        case "H06":return .init(title:"임시 기록 확인",heading:"이전 러닝이\n남아 있어요",text:"마지막 확인 지점까지의 기록이에요.\n멈춰 있던 시간은 더하지 않았어요.",notice:"미저장 기록의 마지막 확인 지점을 이 기기에 임시 보관했어요. 저장 버튼을 눌러 완료해 주세요.",buttons:[("이 기록 저장","save",0),("일시정지 상태로 보기","R04",1),("임시 기록 삭제","R11",3)])
        case "H10":return .init(title:"목표 삭제",heading:"주간 목표를\n삭제할까요?",text:"설정된 거리·시간 목표를 모두 삭제해요.\n지금까지 달린 기록은 그대로 남아요.",buttons:[("주간 목표 삭제","delete-week",2),("목표 유지","H04",1)])
        case "H11":return .init(title:"시간대 변경",heading:"주간 기준이\n달라질 수 있어요",text:"통계의 날짜와 한 주의 경계는 설정된 시간대를 따라요.",notice:"가상 예시: Asia/Seoul → Etc/UTC\n저장된 시각과 실제 운동 시간은 변경하지 않아요.",buttons:[("확인했어요","H07",0)])
        case "P01":return .init(title:"위치 접근",heading:"달린 길을\n기록할 준비",text:"경로와 거리를 기록하려면\n위치 접근이 필요해요.",notice:"허용 버튼 다음에 실제 iOS 권한 요청이 이어지는 설계예요. 여기서는 결과만 시뮬레이션합니다.",buttons:[("위치 권한 허용 · 예시","start-local",0),("지금은 허용하지 않기","P02",1)])
        case "P02":return .init(title:"위치 설정",heading:"위치 접근이\n필요해요",text:"허용되지 않아 GPS 러닝을 시작할 수 없어요. 기존 기록은 계속 볼 수 있어요.",notice:"설정 → 이 앱 → 위치 접근 → 정확한 위치\n실제 설정 이동은 연결하지 않았어요.",buttons:[("설정 안내 보기","P04",0),("홈으로","H01",1)])
        case "P03":return .init(title:"위치 설정",heading:"정확한 위치가\n꺼져 있어요",text:"대략적인 위치만으로는 거리와 경로가 정확하지 않을 수 있어요.",notice:"설정 → 이 앱 → 위치 접근 → 정확한 위치",buttons:[("설정 안내 보기","P04",0),("홈으로","H01",1)])
        case "P04":return .init(title:"설정 변경 안내",heading:"위치 접근과\n정확한 위치 확인",text:"",notice:"실제 기기 설정을 바꾸지 않아요. 설정에서 돌아온 결과만 시뮬레이션합니다.",buttons:[("허용 후 돌아오기 · 예시","start-local",0),("변경하지 않고 돌아오기","H01",1)])
        case "P05":return .init(title:"저장 공간 확인",heading:"기록을 보관할\n공간이 부족해요",text:"초안을 보존할 수 없어\n아직 측정을 시작하지 않았어요.",notice:"기기 저장 공간을 확보한 후 다시 시도해 주세요.",buttons:[("공간 확보 후 재시도 · 예시","H01",0),("홈으로","H00",1)])
        case "R09":return .init(title:"일시정지 유지",heading:"다시 달리기 전에\n위치를 확인해요",text:"권한이 없거나 위치를 확인할 수 없어요. 지금은 일시정지를 유지해요.",notice:"설정 → 이 앱 → 위치 접근 → 정확한 위치",buttons:[("설정 안내 보기","P04",0),("일시정지로 돌아가기","R04",1)])
        case "R11":return .init(title:"기록 삭제",heading:"이 임시 기록을\n삭제할까요?",text:"\(MovNumber.display(current.kilometers)) km · \(RunRecord.clock(current.seconds))\n아직 저장하지 않은 이 기록이 사라져요.",notice:"이 프로토타입의 가상 세션에만 적용돼요.",buttons:[("기록 삭제","discard",2),("기록 유지","R04",1)])
        case "R12":return .init(title:"러닝 종료",heading:"아직 기록된\n시간과 거리가 없어요",text:"계속 달리거나 빈 세션을 닫을 수 있어요. 빈 완료 기록은 만들지 않아요.",buttons:[("러닝으로 돌아가기","R04",0),("빈 세션 닫기","R11",1)])
        case "L07":return .init(title:"기록 삭제",heading:"이 러닝 기록을\n삭제할까요?",text:"\(deletionDate(current)) · \(MovNumber.display(current.kilometers)) km\n주간·월간 합계에서도 빠져요.",notice:"데모 기록에만 적용돼요. 초기화하면 예시 기록을 다시 볼 수 있어요.",buttons:[("이 기록 삭제","delete-record",2),("기록 유지","L04",1)])
        case "T03":return .init(title:"단위",heading:"익숙한 단위로",text:"",notice:"첫 출시 기본 단위예요. 단위 변환은 현재 범위에 포함하지 않아요.")
        case "T04":return .init(title:"개인정보·데이터",heading:"내 기록은 이 기기에",text:"경로·거리·운동 시간은 개인 기록을 위해 보관해요. 체중은 입력한 경우에만 칼로리 추정에 사용해요.",notice:"앱 삭제나 기기 분실 시 기록 복구가 어려울 수 있어요. 클라우드 백업은 별도 검토 대상이에요.")
        case "T06":return .init(title:"로그인 수단 연결",heading:ui.provider+(ui.provider=="Google" ? "을":"를")+"\n연결할까요?",text:"현재 계정은 확인했어요.\n다음으로 \(ui.provider) 인증을 진행해요.",notice:"다른 계정에 연결돼 있으면 자동으로 합치거나 기록을 덮어쓰지 않아요.",buttons:[(ui.provider+" 인증 완료 · 예시","link",0),("연결 취소","T05",1)])
        case "T07":return .init(title:"로그인 안내",heading:"카카오로 로그인한\n기록이 있어요.",text:"카카오로 로그인할까요?",notice:"확인된 가상 계정으로 이동해요. 지금 계정의 기록과 로그인 수단은 그대로 보관해요.",buttons:[("카카오로 로그인","switch-local-account",0),("다른 방법으로 로그인","A01",1)])
        case "T08":return .init(title:"연결 해제",heading:ui.provider+" 연결을\n해제할까요?",text:"남은 로그인 수단으로\n이 계정에 들어올 수 있어요.",notice:"러닝 기록과 회원 계정은 삭제하지 않아요.",buttons:[("연결 해제","unlink",2),("연결 유지","T05",1)])
        case "T09":return .init(title:"로그인 수단 보호",heading:"마지막 로그인 수단은\n해제할 수 없어요",text:"다시 로그인할 수 있도록\n다른 수단을 먼저 연결해 주세요.",buttons:[("다른 수단 연결하기","T05",0)])
        case "T10":return .init(title:"로그아웃",heading:"로그아웃할까요?",text:"이 기기의 기록은 삭제하지 않아요. 같은 계정으로 다시 로그인하면 확인할 수 있어요.",notice:"데모 로그인 상태만 바뀌어요. 실제 제공자 로그아웃은 하지 않아요.",buttons:[("로그아웃","logout",0),("계속 사용하기","T01",1)])
        case "T12":return .init(title:"시뮬레이션 완료",heading:"삭제 완료 화면이에요",text:"실제 계정은 바뀌지 않았어요.\n현재 브라우저의 예시 상태만\n처음으로 돌렸어요.",buttons:[("로그인 화면 보기","A01",0),("홈 검토로 돌아가기","H00",1)])
        case "T13":return .init(title:"기기 기록 삭제",heading:"이 기기의 기록만\n지울까요?",text:"현재 계정의 이 기기 러닝 기록과 임시 데이터를 삭제하는 흐름이에요.",notice:"회원 계정과 로그인 수단은 유지해요. 실제 동작은 브라우저의 데모 기록에만 적용돼요.",buttons:[("기기 데모 기록 삭제","clear-device",2),("기록 유지","T04",1)])
        case "T14":return .init(title:"진행 중 러닝",heading:"먼저 러닝을\n마쳐 주세요",text:"진행 중이거나 저장하지 않은 기록이 있어요. 저장 또는 삭제 후 계정을 변경할 수 있어요.",buttons:[("러닝으로 돌아가기","R04",0),("설정으로 돌아가기","T01",1)])
        case "T15":return .init(title:"현재 계정 확인",heading:"지금 계정을\n먼저 확인해요",text:"연결된 로그인 수단으로 현재 계정을\n확인하는 시뮬레이션이에요.",notice:"실제 인증이나 권한 요청은 하지 않아요.",buttons:[((ui.profile.providers.first ?? "카카오")+"로 재확인 · 예시","reauth",0),("취소","T05",1)])
        case "T16":return .init(title:"탈퇴 요청",heading:"삭제 요청을\n확인하고 있어요",text:"요청됨과 실제 완료 상태를\n구분해 안내해요.",notice:"실제 서버에 보내지 않는 시뮬레이션이에요.",buttons:[("완료 응답 확인 · 예시","delete-account-demo",0),("오류 응답 확인 · 예시","delete-account-error",1)])
        case "T17":return .init(title:"연결 완료",heading:ui.provider+(ui.provider=="Google" ? "이":"가")+"\n연결됐어요",text:"이 계정으로 들어올 수 있는\n로그인 수단이 추가됐어요.",notice:"프로토타입의 연결 상태만 변경됐어요. 실제 계정은 연결하지 않았어요.",buttons:[("로그인 수단 확인","T05",0)])
        default:return .init(title:"화면 확인",heading:"화면을 확인해 주세요",text:"",buttons:[("홈으로","H00",0)])
        }
    }
    var informationPage:some View {let data=info;let navigationBack:(()->Void)? = ui.screen=="T12" ? nil:{back()};return WPage(title:data.title,back:navigationBack){if ["A14","T06","T07","T08","T15","T17"].contains(ui.screen){providerMark(ui.screen=="T15" ? ui.profile.providers.first ?? "카카오":ui.screen=="T07" ? "카카오":ui.provider).padding(.top,["T06","T07","T08","T17"].contains(ui.screen) ? 10:0)};if ui.screen=="A06"{Text(data.heading).font(W.font(22,.semibold)).padding(.top,12)}else{WHeading(text:data.heading).padding(.top,ui.screen=="A14" ? 20:["L07","A04","T09","T10","T12","T13","T14","T16"].contains(ui.screen) ? 9:0)};if !data.text.isEmpty{if ui.screen=="T13"{WAuthSourceParagraph(text:data.text,size:14,lineHeight:24.5).offset(y:-6).padding(.bottom,-4)}else{WText(text:data.text)}}
        if ui.screen=="H06"{WMetric(record:current)}
        if ui.screen=="P01"{WMap().frame(height:172).clipShape(RoundedRectangle(cornerRadius:14))}
        if ui.screen=="A06"{VStack(spacing:0){ForEach(["서비스 이용 목적과 범위","회원 식별 및 제공자 연결 정보","위치·경로·운동 기록 처리","선택 체중과 칼로리 추정","기기 저장·보존·삭제 정책","동의 철회와 문의 방법"],id:\.self){WRow(title:$0,plain:true)}}}
        if ui.screen=="P04"{VStack(spacing:0){ForEach(["1. 기기 설정에서 이 앱 열기","2. 위치 접근 허용","3. 정확한 위치 켜기"],id:\.self){WRow(title:$0)}}}
        if ui.screen=="T03"{VStack(spacing:0){WRow(title:"거리",value:"km");WRow(title:"페이스",value:"분/km");WRow(title:"추정 칼로리",value:"kcal");WRow(title:"체중",value:"kg")}}
        if !data.notice.isEmpty{if ui.screen=="L07"{WRecordDeletionParagraph(text:data.notice).offset(y:-3).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).padding(16).background(Color.wire(0xFFF1F1,0x3C2024),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color.wire(0xF0BFC3,0x83535A))).padding(.top,4)}else if ui.screen.hasPrefix("A") || ["T06","T07","T08","T10","T13","T15","T16","T17"].contains(ui.screen){WAuthNotice(text:data.notice,danger:ui.screen=="T13",sourceWrapping:["A04","T10","T17"].contains(ui.screen))}else{WNotice(text:data.notice,danger:["P05","R11","T13"].contains(ui.screen))}}
        if ui.screen=="T04"{WRow(title:"이 기기의 기록 삭제",subtitle:"회원은 유지",action:{go(store.session==nil ? "T13":"T14")});WRow(title:"회원 탈퇴",subtitle:"계정 삭제 범위 확인",action:{ui.pending="T11";go(store.session==nil ? "T15":"T14")});WText(text:"이 기기의 기록 삭제와 회원 탈퇴는 별도로 관리해요.",small:true)}
        if ui.screen=="T07" && reviewTools{Text("제공자 인증 결과가 기존 계정 연결이 확인된 예시에요.\n실제 로그인이나 계정 합치기는 하지 않아요.").font(W.font(11)).lineSpacing(5).foregroundStyle(W.muted)}else if ["A13","A14","A15","A18"].contains(ui.screen){authDemoNote}
    }actions:{ForEach(Array(data.buttons.enumerated()),id:\.offset){_,item in if item.2==3{Button(item.0){infoAction(item.1)}.font(W.font(13)).frame(maxWidth:.infinity,minHeight:32,alignment:.leading)}else{Button(item.0){infoAction(item.1)}.buttonStyle(WButtonStyle(kind:item.2)).disabled(ui.screen=="A14" && item.1=="social-success" && ui.provider.isEmpty)}}}}
    func infoAction(_ action:String){switch action {
    case "reset-cancel":go(ui.resetBack)
    case "consent-reviewed":if ui.consentTopic=="이용약관"{ui.consentTerms=true}else{ui.consentPrivacy=true};back()
    case "local-login":ui.profile.logged=true;ui.save();go("H00")
    case "switch-local-account":if reviewTools{ui.switchLocalAccount(store,clearShare:{shareWorkspace.clear()})}
    case "save":saveRun()
    case "delete-week":store.weekly.distanceEnabled=false;store.weekly.timeEnabled=false;store.persist();go("H00")
    case "start-local":store.start(weight:Double(ui.profile.weight));go("R01")
    case "discard":store.finish(save:false);ui.collapsed=false;go("H01")
    case "delete-record":store.delete(current.id);ui.selected=nil;go("L01")
    case "clear-device":guard store.session==nil else{go("T14");return};store.records=[];store.persist();go("L02")
    case "logout":guard store.session==nil else{go("T14");return};ui.profile.logged=false;ui.save();ui.authFilled=false;go("A01")
    case "social-success":guard ui.screen=="A14", !ui.provider.isEmpty else{return};ui.verified=true;if ui.profile.providers.contains(ui.provider){ui.profile.logged=true;ui.save();go("H00")}else{ui.consentTerms=false;ui.consentPrivacy=false;go("A02")}
    case "link":guard ui.screen=="T06",ui.settingsGrant else{return};if !ui.profile.providers.contains(ui.provider){ui.profile.providers.append(ui.provider);ui.save()};go("T17")
    case "unlink":guard ui.screen=="T08" else{return};guard ui.profile.providers.count>1 else{go("T09");return};ui.profile.providers.removeAll{$0==ui.provider};ui.save();go("T05")
    case "reauth":guard ui.screen=="T15" else{return};ui.settingsGrant=true;go(ui.pending)
    case "delete-account-demo":guard store.session==nil else{go("T14");return};ui.profile=WLocalProfile();ui.profile.logged=false;ui.save();go("T12")
    case "delete-account-error":ui.deleteConsent=false;go("T11")
    default:go(action)
    }}
}

extension WireframeRoot {
    func deletionDate(_ record:RunRecord)->String {
        if ProcessInfo.processInfo.arguments.contains("-wire-review-size"){return "2026.09.29"}
        let f=DateFormatter();f.locale=Locale(identifier:"ko_KR");f.dateFormat="yyyy.MM.dd";return f.string(from:record.date)
    }
}

// CSS word-break: keep-all wraps Korean at spaces. SwiftUI's balanced wrapping
// moves "수 있어요" together; a native UILabel uses the source's word wrapping.
private struct WRecordDeletionParagraph:UIViewRepresentable {
    let text:String
    func makeUIView(context:Context)->UILabel {
        let label=UILabel();label.numberOfLines=0;label.lineBreakMode = .byWordWrapping
        label.lineBreakStrategy = .hangulWordPriority;label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return label
    }
    func updateUIView(_ label:UILabel,context:Context) {
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = .hangulWordPriority;paragraph.minimumLineHeight=22.1;paragraph.maximumLineHeight=22.1
        let font=UIFontMetrics(forTextStyle:.body).scaledFont(for:UIFont(name:"PretendardVariable-Regular",size:13)!)
        label.attributedText=NSAttributedString(string:text,attributes:[.font:font,.kern:-0.195,.paragraphStyle:paragraph,.foregroundColor:UIColor(Color.wire(0xA92D32,0xFF9CA3))])
        label.accessibilityLabel=text
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:UILabel,context:Context)->CGSize? {
        guard let width=proposal.width else{return nil}
        return uiView.sizeThatFits(CGSize(width:width,height:.greatestFiniteMagnitude))
    }
}
