import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
extension WireframeRoot {
    func completeSocialSignup(_ attempt:SocialLoginAttempt){
        guard ui.screen=="A03",socialLoginPendingAttempt==attempt,let coordinator=socialLoginCoordinator else{return}
        guard !socialLoginBusy else{return}
        let termsConsents: [SocialLoginConsent]
        #if DEBUG
        termsConsents = WReviewMode.tools
            ? WireframeSocialLoginFixtureTerms.catalog.required
            : WireframeSocialLoginTerms.catalog.required
        #else
        termsConsents = WireframeSocialLoginTerms.catalog.required
        #endif
        let request=socialLoginPendingCompletion ?? SocialLoginCompletionRequest(
            socialSignupProof:attempt.proof.socialSignupProof,
            requestID:socialLoginNextCompletionRequestID ?? attempt.completionRequestID,
            deviceID:attempt.deviceID,
            nickname:WSignupNicknameValidation.normalized(ui.nickname),
            termsConsents:termsConsents
        )
        socialLoginPendingCompletion=request
        socialLoginNextCompletionRequestID=nil
        socialLoginCompletionSubmitted=true
        socialLoginBusy=true
        socialLoginTask=Task { @MainActor in
            defer {socialLoginBusy=false;socialLoginTask=nil}
            do {
                let tokens=try await coordinator.complete(request)
                guard ui.screen=="A03",socialLoginPendingAttempt==attempt else{return}
                let snapshot=try loadCommittedSocialSnapshot(tokens)
                ui.profile.weight=ui.weight
                ui.profile.photo=ui.photo
                ui.profile.nickname=request.nickname ?? ""
                if !ui.provider.isEmpty && !ui.profile.providers.contains(ui.provider){ui.profile.providers.append(ui.provider)}
                applyAuthenticatedSnapshot(snapshot)
                socialLoginPendingAttempt=nil
                socialLoginPendingCompletion=nil
                socialLoginNextCompletionRequestID=nil
                socialLoginCompletionSubmitted=false
                go("A15")
            } catch let failure as SocialLoginFailure {
                guard ui.screen=="A03",socialLoginPendingAttempt==attempt else{return}
                if failure == .signupProofInvalid || failure == .signupRequestConflict {
                    socialLoginPendingAttempt=nil
                    socialLoginPendingCompletion=nil
                    socialLoginNextCompletionRequestID=nil
                    socialLoginCompletionSubmitted=false
                    go("A04")
                    ui.error=failure.userMessage
                } else {
                    if failure.completionWasRejected {
                        socialLoginPendingCompletion=nil
                        socialLoginNextCompletionRequestID=UUID()
                        socialLoginCompletionSubmitted=false
                    }
                    ui.error=failure.userMessage
                }
            } catch {
                guard ui.screen=="A03",socialLoginPendingAttempt==attempt else{return}
                ui.error=SocialLoginFailure.invalidResponse.userMessage
            }
        }
    }

    func beginMemberProfileDraft(_ profile:MemberProfile,for screen:String){
        memberProfileDraftBaseline=profile
        memberProfileDraftScopeID=ui.remoteAccountScopeID
        if screen=="M02" {
            memberProfilePhotoDraftBaseline=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo)
            memberProfilePhotoUploadedDraft=nil
        }
        ui.error=""
        if screen=="M02" {
            ui.nickname=profile.nickname
            ui.introduction=profile.introduction ?? ""
            ui.region=profile.region ?? "선택 안 함"
            ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo)
        } else if screen=="T02" {
            ui.weight=WMemberProfileValidation.weightText(profile.weightKg)
            ui.profile.weight=ui.weight
        }
    }

    func cancelMemberProfilePhotoUpload(){
        guard memberProfilePhotoUploading else{return}
        memberProfilePhotoUploadTask?.cancel()
        memberProfilePhotoUploadTask=nil
        memberProfilePhotoUploadOperationID=nil
        memberProfilePhotoUploading=false
    }

    func applyMemberProfilePublicFields(_ profile:MemberProfile){
        ui.profile.nickname=profile.nickname
        ui.profile.introduction=profile.introduction ?? ""
        ui.profile.region=profile.region ?? "선택 안 함"
    }

    func restoreMemberProfileDraft(){
        let baseline=memberProfileDraftScopeID==ui.remoteAccountScopeID ? memberProfileDraftBaseline:nil
        if ui.screen=="M02" {
            if let baseline {
                ui.nickname=baseline.nickname
                ui.introduction=baseline.introduction ?? ""
                ui.region=baseline.region ?? "선택 안 함"
            } else {
                ui.nickname=ui.profile.nickname
                ui.introduction=ui.profile.introduction
                ui.region=ui.profile.region
            }
            ui.photo=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo)
        } else if ui.screen=="T02" {
            ui.weight=baseline.map { WMemberProfileValidation.weightText($0.weightKg) } ?? ui.profile.weight
            if baseline != nil { ui.profile.weight=ui.weight }
        }
        ui.error=""
    }

    func saveMemberProfileEdit(){
        ui.error=""
        guard remoteReads.hasMemberProfileDependency else {
            guard WProfileValidation.isValid(nickname:ui.nickname,introduction:ui.introduction) else {
                ui.error="닉네임은 1–20자, 한 줄 소개는 60자 이내로 입력해 주세요."
                return
            }
            ui.profile.photo=ui.photo
            ui.profile.nickname=ui.nickname.trimmingCharacters(in:.whitespacesAndNewlines)
            ui.profile.introduction=ui.introduction
            ui.profile.region=ui.region
            ui.save();back();return
        }
        guard let baseline=memberProfileDraftBaseline,
              memberProfileDraftScopeID==ui.remoteAccountScopeID,
              remoteReads.accountScopeID==ui.remoteAccountScopeID,
              case .loaded=remoteReads.memberProfileState else {
            ui.error="계정 프로필을 불러온 뒤 저장해 주세요."
            return
        }
        if let error=WMemberProfileValidation.nicknameError(for:ui.nickname){ui.error=error;return}
        if let error=WMemberProfileValidation.introductionError(for:ui.introduction){ui.error=error;return}
        if let error=WMemberProfileValidation.regionError(for:ui.region){ui.error=error;return}
        let patch=WMemberProfileValidation.profilePatch(baseline:baseline,nickname:ui.nickname,introduction:ui.introduction,region:ui.region)
        let photoChanged=ui.photo != memberProfilePhotoDraftBaseline
        if photoChanged && ui.photo == nil {
            ui.error="프로필 사진 삭제 API가 아직 제공되지 않아 계정 사진은 삭제할 수 없어요. 사진을 다시 선택해 주세요."
            return
        }
        if let photo=ui.photo,photoChanged,photo != memberProfilePhotoUploadedDraft,let mediaUploadClient {
            guard !memberProfilePhotoUploading else{return}
            guard let authSessionStore,
                  let memberID=try? authSessionStore.loadSnapshot()?.memberID,
                  AuthSessionSnapshot.isCanonicalMemberID(memberID) else {
                ui.error="로그인 상태를 확인한 뒤 다시 시도해 주세요."
                return
            }
            let accountScopeID=ui.remoteAccountScopeID
            let binding=ProfilePhotoUploadSessionBinding(memberID:memberID,generationID:accountScopeID)
            let state=ui
            let reads=remoteReads
            let isBindingCurrent:ProfilePhotoUploadBindingValidator = { expectedBinding in
                await MainActor.run {
                    guard expectedBinding==binding,
                          !Task.isCancelled,
                          state.remoteAccountScopeID==expectedBinding.generationID,
                          state.screen=="M02",
                          memberProfileDraftScopeID==expectedBinding.generationID,
                          reads.accountScopeID==expectedBinding.generationID else{return false}
                    do { return try authSessionStore.loadSnapshot()?.memberID==expectedBinding.memberID }
                    catch { return false }
                }
            }
            let operationID=UUID()
            memberProfilePhotoUploadOperationID=operationID
            memberProfilePhotoUploading=true
            ui.error=""
            memberProfilePhotoUploadTask=Task { @MainActor [photo, patch, baseline] in
                defer {
                    if memberProfilePhotoUploadOperationID==operationID {
                        memberProfilePhotoUploading=false
                        memberProfilePhotoUploadTask=nil
                        memberProfilePhotoUploadOperationID=nil
                    }
                }
                do {
                    let service=ProfilePhotoUploadService(mediaClient:mediaUploadClient,sessionStore:authSessionStore)
                    let confirmed=try await service.uploadAndFetchPhoto(photo,binding:binding,isBindingCurrent:isBindingCurrent)
                    guard await isBindingCurrent(binding),memberProfilePhotoUploadOperationID==operationID else{return}
                    memberProfilePhotoUploadedDraft=confirmed
                    ui.photo=confirmed
                    ui.profile.photo=confirmed
                    if patch.hasChanges {
                        remoteReads.saveMemberProfile(patch,accountScopeID:accountScopeID,screen:"M02")
                    } else {
                        applyMemberProfilePublicFields(baseline)
                        ui.save();back()
                    }
                } catch is ProfilePhotoUploadFailure {
                    return
                } catch let failure as MediaUploadFailure {
                    guard !Task.isCancelled,await isBindingCurrent(binding),
                          memberProfilePhotoUploadOperationID==operationID else{return}
                    ui.error=failure.userMessage
                } catch {
                    guard !Task.isCancelled,await isBindingCurrent(binding),
                          memberProfilePhotoUploadOperationID==operationID else{return}
                    ui.error=MediaUploadFailure.invalidResponse.userMessage
                }
            }
            return
        }
        guard patch.hasChanges else {
            applyMemberProfilePublicFields(baseline)
            ui.profile.photo=ui.photo
            ui.save();back();return
        }
        remoteReads.saveMemberProfile(patch,accountScopeID:ui.remoteAccountScopeID,screen:"M02")
    }

    func saveMemberProfileWeight(){
        ui.error=""
        guard let baseline=memberProfileDraftBaseline,
              memberProfileDraftScopeID==ui.remoteAccountScopeID,
              remoteReads.accountScopeID==ui.remoteAccountScopeID,
              case .loaded=remoteReads.memberProfileState else {
            ui.error="계정 프로필을 불러온 뒤 저장해 주세요."
            return
        }
        let input=WMemberProfileValidation.weightInput(ui.weight)
        guard input != .invalid else {
            ui.error="체중은 20~300 kg 사이로 입력하거나 비워 두세요. 소수 둘째 자리에서 저장돼요."
            return
        }
        let patch=WMemberProfileValidation.weightPatch(baseline:baseline,input:input)
        guard patch.hasChanges else {
            ui.weight=WMemberProfileValidation.weightText(baseline.weightKg)
            ui.profile.weight=ui.weight
            back();return
        }
        remoteReads.saveMemberProfile(patch,accountScopeID:ui.remoteAccountScopeID,screen:"T02")
    }

    var profile:some View {VStack(spacing:0){rootHeader("내 정보");ScrollView{VStack(alignment:.leading,spacing:14){HStack{Text("나의 러닝 카드").font(W.font(17,.semibold));Spacer();Button("카드 편집"){go("M02")}.font(W.font(12)).frame(minHeight:44)}
        runnerIdentityCard()
        if remoteReads.hasMemberProfileDependency { remoteMemberProfileReadPanel }
        gradeProgress.padding(.top,-8)
        WDisclosure(title:"등급 기준",expanded:$ui.gradeExpanded){VStack(alignment:.leading,spacing:12){WText(text:"첫 유효 기록을 완료하면 시작러너가 돼요. 새싹러너부터는 누적 거리와 활동일 수를 함께 확인해요. 하루 유효 구간 합계가 4분 이상이면서 1 km 이상이면 활동일 1일로 계산해요. 같은 날 여러 번 달려도 1일이에요.",small:true);ForEach(Array(zip(["start","sprout","passion","challenge","distance"],["시작러너|첫 유효 기록 완료","새싹러너|누적 10 km + 서로 다른 7일","열정러너|누적 30 km + 서로 다른 10일","도전러너|누적 100 km + 서로 다른 20일","러닝마스터|누적 300 km + 서로 다른 50일"])),id:\.0){key,copy in let parts=copy.components(separatedBy:"|");HStack{Image("Tier-"+key).resizable().scaledToFit().frame(width:24,height:24);Text(parts[0]).font(W.font(13,.medium));Spacer();WText(text:parts[1],small:true)}};WText(text:"저장된 유효 구간의 거리와 활동일을 기준으로 계산해요. 제외된 구간은 합계에 포함하지 않아요.",small:true)}.padding(.top,12)}.font(W.font(13)).padding(.top,-10)
        Text("개인 설정").font(W.font(12)).foregroundStyle(W.muted).padding(.top,18);WRow(title:"체중 정보",subtitle:"선택 입력 · 러닝 카드에 표시되지 않아요",action:{go("T02")},arrow:true).accessibilityIdentifier("memberProfileWeightRow");WText(text:"활동 지역과 소개는 카드 편집에서 변경할 수 있어요.",small:true)
    }.padding(.horizontal,24).padding(.top,20).padding(.bottom,24)}}}
    @ViewBuilder private var remoteMemberProfileReadPanel:some View {
        VStack(alignment:.leading,spacing:9){
            Text("계정 프로필 조회").font(W.font(13,.semibold))
            switch remoteReads.memberProfileState {
            case .idle:
                WText(text:"조회 준비 중이에요.",small:true)
            case .loading:
                HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"계정 정보를 불러오는 중이에요.",small:true)}
            case .loaded(let profile):
                Text(profile.nickname).font(W.font(16,.medium)).accessibilityIdentifier("remoteProfileNickname")
                if let introduction=profile.introduction,!introduction.isEmpty{WText(text:introduction,small:true)}
                if let region=profile.region{WText(text:region,small:true)}
                WText(text:"체중은 본인 프로필에서만 사용하며 러닝 카드에는 표시하지 않아요.",small:true)
            case .failed(let failure):
                WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("remoteProfileReadFailure")
                Button("다시 시도"){remoteReads.retryMemberProfile()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("remoteProfileRetry")
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(W.soft,in:RoundedRectangle(cornerRadius:14))
    }
    @ViewBuilder func runnerIdentityCard(previewDecoration:WPointPreviewPresentation? = nil)->some View {
        let previewAccent = WPointPreviewColor.fromHex(previewDecoration?.accentColorHex)
        let card = VStack(alignment:.leading,spacing:0){HStack{Text("러닝 프로필").font(W.font(11)).kerning(0.275).foregroundStyle(W.muted);Spacer();BrandMark(size:28)}.frame(height:28)
            HStack(spacing:14){Group{if let data=WProfilePhotoPolicy.sanitizeStored(ui.profile.photo),let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}else{Text(String(ui.profile.nickname.prefix(1))).font(W.font(20,.semibold))}}.frame(width:56,height:56).background(W.soft).clipShape(Circle()).overlay(Circle().stroke(W.line)).overlay{if previewDecoration?.treatment == .paceFrame{Circle().stroke(previewAccent,lineWidth:3).padding(-5)}};VStack(alignment:.leading,spacing:0){
                HStack(spacing:5){if store.totalDistance>0{Image("Tier-"+currentTierKey).resizable().scaledToFit().frame(width:28,height:28)};Text(store.totalDistance==0 ? "등급 없음":tierName).font(W.font(12,.medium)).foregroundStyle(W.muted)}.frame(height:28).padding(.bottom,6)
                Text(ui.profile.nickname).font(W.font(31,.semibold)).kerning(-1.86).frame(minHeight:38.13,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                Text(ui.profile.introduction).font(W.font(13)).kerning(-0.195).foregroundStyle(W.muted).frame(minHeight:22.1,alignment:.leading).padding(.top,12)
            }}.padding(.top,35).padding(.bottom,28)
            W.line.frame(height:1);HStack(alignment:.top,spacing:16){VStack(alignment:.leading,spacing:7){Text("활동 지역").font(W.font(10)).foregroundStyle(W.muted).frame(height:15);Text(ui.profile.region).font(W.font(13,.medium)).frame(minHeight:17.55).padding(.top,5)}.frame(maxWidth:.infinity,alignment:.leading);VStack(alignment:.leading,spacing:7){Text("최근 1달 평균 러닝당 거리").font(W.font(10)).foregroundStyle(W.muted).frame(height:15);(Text(MovNumber.display(store.averageDistance)).font(W.font(24,.semibold)).kerning(-0.96)+Text(" km").font(W.font(11,.medium))).frame(height:32.4)}.frame(maxWidth:.infinity,alignment:.leading)}.padding(.top,18)
        }.padding(.horizontal,23).padding(.top,23).padding(.bottom,20).frame(minHeight:315,alignment:.top).background(W.paper,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(W.line)).shadow(color:.black.opacity(0.025),radius:10,y:5)
        card.overlay(alignment:.topTrailing){
            if let previewDecoration {
                switch previewDecoration.treatment {
                case .runCardBackground:
                    WRunnerCardBackgroundPreview(accent:previewAccent)
                        .frame(width:245,height:170).offset(x:100,y:-50).accessibilityHidden(true)
                case .runCardFrame:
                    RoundedRectangle(cornerRadius:18).stroke(previewAccent,lineWidth:3).padding(5).accessibilityHidden(true)
                case .paceFrame:
                    EmptyView()
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:18))
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
    var profileEdit:some View {
        let remote=remoteReads.hasMemberProfileDependency
        let profileLoaded:Bool={if case .loaded=remoteReads.memberProfileState{return remoteReads.accountScopeID==ui.remoteAccountScopeID};return false}()
        return WPage(title:"러닝 카드 편집",back:back){
            Text("나를 소개하는 러닝 카드").font(W.font(23,.semibold)).padding(.top,4)
            WText(text:"닉네임과 활동 지역으로 나를 소개해 보세요.",small:true).padding(.bottom,10)
            if remote && !profileLoaded {
                switch remoteReads.memberProfileState {
                case .idle,.loading:
                    HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"계정 프로필을 불러오는 중이에요.",small:true)}.accessibilityIdentifier("memberProfileEditLoading")
                case .failed(let failure):
                    WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("memberProfileEditReadFailure")
                    Button("다시 시도"){remoteReads.retryMemberProfile()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("memberProfileEditRetry")
                case .loaded:
                    WText(text:"계정 프로필을 준비하고 있어요.",small:true)
                }
            } else {
                WAvatarEditor(data:$ui.photo).padding(.bottom,9).disabled(remoteReads.isSavingMemberProfile || memberProfilePhotoUploading)
                WField(label:"닉네임",text:$ui.nickname,limit:12,textSize:14,labelSize:13,secondaryLabel:"필수",accessibilityID:"memberProfileEditNickname").padding(.top,5)
                    .disabled(remoteReads.isSavingMemberProfile || memberProfilePhotoUploading)
                Text(remote ? "2–12자 · 한글·영문·숫자·밑줄 · 중복 여부 확인": "최대 20자 · 중복 여부는 확인하지 않아요")
                    .font(W.font(11)).kerning(-0.165).foregroundStyle(W.muted).frame(height:17.6,alignment:.leading).padding(.top,-11)
                WField(label:"한 줄 소개",text:$ui.introduction,placeholder:"어떤 러너인지 소개해 주세요",limit:60,multiline:true,multilineHeight:86,textSize:14,labelSize:13,secondaryLabel:"선택",accessibilityID:"memberProfileEditIntroduction").padding(.top,4)
                    .disabled(remoteReads.isSavingMemberProfile || memberProfilePhotoUploading)
                (Text("활동 지역").font(W.font(13))+Text("  선택").font(W.font(10)).foregroundColor(W.muted))
                WRegionPicker(selection:$ui.region).disabled(remoteReads.isSavingMemberProfile || memberProfilePhotoUploading)
                WText(text:"활동 지역은 선택하지 않아도 괜찮아요.",small:true)
                if memberProfilePhotoUploading{HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"프로필 사진을 업로드하고 있어요.",small:true)}.accessibilityIdentifier("memberProfilePhotoUploadProgress")}
                if !ui.error.isEmpty{WNotice(text:ui.error,danger:true).accessibilityIdentifier("memberProfileEditFailure")}
            }
        }actions:{
            Button(memberProfilePhotoUploading ? "사진 업로드 중…":remoteReads.isSavingMemberProfile ? "저장 중…":"저장하기") {
                saveMemberProfileEdit()
            }.buttonStyle(WButtonStyle()).disabled(memberProfilePhotoUploading || remoteReads.isSavingMemberProfile || (remote && !profileLoaded)).accessibilityIdentifier("memberProfileEditSave")
            Button("취소",action:back).buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("memberProfileEditCancel")
        }
    }
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
    var weightProfile:some View {
        let onboarding=ui.screen=="A03"
        let usesRemoteProfile=remoteReads.hasMemberProfileDependency && !onboarding
        let profileLoaded:Bool={if case .loaded=remoteReads.memberProfileState{return remoteReads.accountScopeID==ui.remoteAccountScopeID};return false}()
        return WPage(title:onboarding ? "프로필":"프로필·체중",back:back,backDisabled:onboarding && socialLoginCompletionSubmitted){
            if onboarding {
                WText(text:"02 / 02",small:true).offset(y:6)
                WHeading(text:"어떻게 불러드릴까요?")
                WField(label:"닉네임 (필수)",text:$ui.nickname,placeholder:"예: 아침러너",limit:12,accessibilityID:"signupNicknameInput")
                    .disabled(socialLoginCompletionSubmitted)
                Text("2~12자 · 한글, 영문, 숫자, 밑줄만").font(W.font(11)).kerning(-0.165).foregroundStyle(W.muted).frame(maxWidth:.infinity,alignment:.leading)
                if !ui.error.isEmpty {Text(ui.error).font(W.font(12)).foregroundStyle(Color.wire(0xA92D32,0xFF9CA3)).accessibilityIdentifier("signupNicknameError")}
                Text("체중은 선택이에요").font(W.font(17,.semibold)).padding(.top,4)
            } else {
                WHeading(text:"체중은 선택이에요")
                if usesRemoteProfile && !profileLoaded {
                    switch remoteReads.memberProfileState {
                    case .idle,.loading:
                        HStack(spacing:8){ProgressView().controlSize(.small);WText(text:"계정 체중 정보를 불러오는 중이에요.",small:true)}.accessibilityIdentifier("memberProfileWeightLoading")
                    case .failed(let failure):
                        WNotice(text:failure.userMessage,danger:true).accessibilityIdentifier("memberProfileWeightReadFailure")
                        Button("다시 시도"){remoteReads.retryMemberProfile()}.buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("memberProfileWeightRetry")
                    case .loaded:
                        WText(text:"계정 체중 정보를 준비하고 있어요.",small:true)
                    }
                }
            }
            WText(text:"입력하면 달린 거리를 바탕으로\n추정 소모 칼로리를 보여드려요.")
            HStack(alignment:.bottom,spacing:8){
                WField(label:onboarding ? "예시 체중":"체중",text:$ui.weight,placeholder:"입력하지 않아도 괜찮아요",textSize:onboarding ? 14:16,placeholderColor:onboarding ? Color.wire(0x686868,0xA5A5A5):nil,accessibilityID:onboarding ? "signupWeightInput":"profileWeightInput")
                    .keyboardType(.decimalPad)
                    .disabled((onboarding && socialLoginCompletionSubmitted) || (usesRemoteProfile && (!profileLoaded || remoteReads.isSavingMemberProfile)))
                Text("kg").font(W.font(14)).frame(height:54)
            }.padding(.top,onboarding ? 4:0)
            WText(text:onboarding ? "테스트할 예시값만 입력하세요. 실제 체중은 필요 없어요.":"입력한 체중은 러닝 카드에 표시되지 않아요.",small:true)
            let notice="체중이 없으면 칼로리는 —로 표시해요. 기록 당시의 체중으로 계산한 추정값이며 건강 측정값이 아니에요."
            if onboarding {WAuthNotice(text:notice)} else {WNotice(text:notice)}
            if onboarding && socialLoginCompletionSubmitted {
                WAuthNotice(text:socialLoginBusy ? "가입 결과를 확인하고 있어요.":"응답을 확인하지 못했어요. 아래에서 같은 가입 요청을 다시 확인해요.")
                    .accessibilityIdentifier("socialSignupCompletionState")
            }
        } actions: {
            Button(onboarding ? "계속":"변경 저장") {
                ui.error=""
                if onboarding, let error=WSignupNicknameValidation.error(for:ui.nickname){ui.error=error;return}
                if onboarding, reviewTools, let error=WSignupNicknameValidation.fixtureError(for:ui.nickname){ui.error=error;return}
                if usesRemoteProfile {saveMemberProfileWeight();return}
                if let error=WSignupWeightValidation.error(for:ui.weight){ui.error=error;return}
                if onboarding && (!ui.consentTerms || !ui.consentPrivacy){ui.error="필수 항목을 확인해 주세요.";go("A02");return}
                if onboarding,let attempt=socialLoginPendingAttempt {completeSocialSignup(attempt);return}
                ui.profile.weight=ui.weight
                if onboarding {
                    guard reviewTools else {ui.error="회원가입 서버가 연결되지 않아 계정을 만들지 않았어요.";return}
                    ui.profile.photo=ui.photo
                    ui.profile.nickname=WSignupNicknameValidation.normalized(ui.nickname)
                    if !ui.provider.isEmpty && !ui.profile.providers.contains(ui.provider){ui.profile.providers.append(ui.provider)}
                    ui.save();go("A15")
                } else {ui.save();back()}
            }.buttonStyle(WButtonStyle()).disabled((onboarding && socialLoginBusy) || (usesRemoteProfile && (!profileLoaded || remoteReads.isSavingMemberProfile))).accessibilityIdentifier(onboarding ? "signupContinue":"saveWeightProfile")
            if !onboarding {Button("체중 정보 제거"){
                if usesRemoteProfile {ui.weight="";saveMemberProfileWeight()}
                else {ui.profile.weight="";ui.weight="";ui.save();back()}
            }.buttonStyle(WButtonStyle(kind:1)).disabled(usesRemoteProfile && (!profileLoaded || remoteReads.isSavingMemberProfile))}
            if !ui.error.isEmpty {WNotice(text:ui.error,danger:true).accessibilityIdentifier("memberProfileWeightFailure")}
            if usesRemoteProfile {WText(text:"체중은 본인 프로필에서만 사용하며 러닝 카드와 커뮤니티 프로필에는 표시하지 않아요.",small:true)}
        }
    }
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
    @State private var importGuard=WProfilePhotoImportGuard()
    @Binding var data:Data?
    @State private var draft:UIImage?
    @State private var message=""
    var picture:UIImage?{WProfilePhotoPolicy.sanitizeStored(data).flatMap(UIImage.init(data:))}
    var body:some View {let hasPhoto=data != nil || draft != nil;return VStack(alignment:.leading,spacing:12){(Text("프로필 사진").font(W.font(13))+Text("  선택").font(W.font(10)).foregroundColor(W.muted)).padding(.bottom,7)
        if let draft{WPhotoCrop(image:draft){data=$0}}
        else{Group{if let picture{Image(uiImage:picture).resizable().scaledToFill()}else{WAvatarPlaceholder().stroke(W.muted,style:StrokeStyle(lineWidth:1.6*34/24,lineCap:.butt,lineJoin:.miter)).frame(width:34,height:34)}}.frame(width:80,height:80).background(W.soft).clipShape(Circle()).overlay(Circle().stroke(W.line)).frame(maxWidth:.infinity).padding(.bottom,6).accessibilityIdentifier("profilePhotoPreview")}
        HStack{PhotosPicker(selection:$item,matching:.images){Text(hasPhoto ? "사진 바꾸기":"사진 선택").font(W.font(12,.medium)).frame(minWidth:72,minHeight:24).padding(.horizontal,14).padding(.vertical,10).background(W.lime,in:RoundedRectangle(cornerRadius:10)).foregroundStyle(MovTokens.onBrand)};Button("사진 삭제"){data=nil;item=nil;draft=nil}.font(W.font(12,.medium)).frame(minWidth:72,minHeight:24).padding(.horizontal,14).padding(.vertical,10).background(W.paper,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(W.line)).foregroundStyle(hasPhoto ? W.ink:W.muted).disabled(!hasPhoto)}.frame(maxWidth:.infinity)
        Text("사진 원본 20 MB 이하 · HEIC/HEIF 포함\n회전 보정 후 JPEG 최대 1024×1024 · 2 MB 이하").font(W.font(11)).lineSpacing(6).foregroundStyle(W.muted)
        if !message.isEmpty{WNotice(text:message,danger:true)}
    }.task(id:item){let request=importGuard.begin();await load(item,request:request)}.onChange(of:item){_,_ in importGuard.invalidate()}.onDisappear{importGuard.invalidate()}.onAppear{if WReviewMode.tools && ProcessInfo.processInfo.arguments.contains("-wire-photo-crop-fixture"){draft=WProfilePhotoPolicy.reviewCaptureFixture()}}}
    private func load(_ selected:PhotosPickerItem?,request:UUID)async {
        guard let selected,isCurrent(request) else{return}
        do {
            guard let imported=try await selected.loadTransferable(type:WImportedProfilePhoto.self) else{if isCurrent(request){message="지원되는 사진 원본을 20 MB 이하로 선택해 주세요."};return}
            guard isCurrent(request) else{return}
            guard let image=UIImage(data:imported.data),let decoded=image.cgImage,WProfilePhotoPolicy.accepts(width:decoded.width,height:decoded.height) else{message="지원되는 사진 원본을 20 MB 이하로 선택해 주세요.";return}
            draft=image;message=""
        } catch {if isCurrent(request) && !Task.isCancelled{message=WPhotoPickerFailureMessage.userFacing(error)}}
    }
    private func isCurrent(_ request:UUID)->Bool{!Task.isCancelled && importGuard.accepts(request)}
}
struct WCommunityCrewPhotoPicker:View {
    @Binding var data:Data?
    @State private var item:PhotosPickerItem?
    @State private var importGuard=WProfilePhotoImportGuard()
    @State private var image:UIImage?
    @State private var message=""
    var body:some View {
        let hasPhoto=data != nil
        VStack(alignment:.leading,spacing:10){
            Group{
                if let image{Image(uiImage:image).resizable().scaledToFill()}
                else if let data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}
                else{ZStack{RoundedRectangle(cornerRadius:16).fill(W.soft);Image(systemName:"person.3.fill").font(.system(size:34)).foregroundStyle(W.muted)}}
            }.frame(maxWidth:.infinity).frame(height:155).clipped().clipShape(RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("communityCrewPhotoPreview")
            PhotosPicker(selection:$item,matching:.images){Label(hasPhoto ? "사진 바꾸기":"크루 사진 선택",systemImage:"photo").font(W.font(13,.medium)).frame(maxWidth:.infinity,minHeight:46).background(W.soft,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("communityCrewPhotoPicker")
            Text("사진 원본 20 MB 이하 · 기기 안 예시로만 사용돼요.").font(W.font(11)).foregroundStyle(W.muted)
            if !message.isEmpty{WNotice(text:message,danger:true).accessibilityIdentifier("communityCrewPhotoError")}
        }.task(id:item){let request=importGuard.begin();await load(item,request:request)}.onChange(of:item){_,_ in importGuard.invalidate()}.onDisappear{importGuard.invalidate()}
    }
    private func load(_ selected:PhotosPickerItem?,request:UUID)async {
        guard let selected,isCurrent(request) else{return}
        do {
            guard let imported=try await selected.loadTransferable(type:WImportedProfilePhoto.self) else{if isCurrent(request){message="지원되는 사진 원본을 20 MB 이하로 선택해 주세요."};return}
            guard isCurrent(request) else{return}
            guard let decoded=UIImage(data:imported.data),let cgImage=decoded.cgImage,WProfilePhotoPolicy.accepts(width:cgImage.width,height:cgImage.height) else{message="지원되는 사진 원본을 20 MB 이하로 선택해 주세요.";return}
            data=imported.data;image=decoded;message=""
        } catch {if isCurrent(request) && !Task.isCancelled{message=WPhotoPickerFailureMessage.userFacing(error)}}
    }
    private func isCurrent(_ request:UUID)->Bool{!Task.isCancelled && importGuard.accepts(request)}
}

private struct WRunnerCardBackgroundPreview:View {
    let accent:Color

    var body:some View {
        ZStack {
            Ellipse().stroke(accent.opacity(0.24),lineWidth:24)
            Ellipse().stroke(accent.opacity(0.42),lineWidth:5).padding(17)
            Ellipse().stroke(accent.opacity(0.16),lineWidth:3).padding(34)
        }.rotationEffect(.degrees(-25))
    }
}

struct WProfilePhotoImportGuard {
    private(set) var current:UUID?
    mutating func begin()->UUID{let request=UUID();current=request;return request}
    mutating func invalidate(){current=nil}
    func accepts(_ request:UUID)->Bool{current==request}
}

enum WPhotoPickerFailureMessage {
    static func userFacing(_ error:Error)->String {
        let value=error as NSError
        let description=value.localizedDescription.lowercased()
        if value.code==NSFileReadNoPermissionError || value.code==257 || description.contains("permission denied") || description.contains("access denied") || description.contains("권한") || description.contains("접근 거부") {
            return "사진 접근 권한이 거부됐어요. 설정에서 사진 접근을 허용한 뒤 다시 시도해 주세요."
        }
        return error.localizedDescription
    }
}
struct WPhotoCrop:View {
    var image:UIImage
    var updatePhoto:(Data)->Void
    @State private var point=CGSize.zero
    @State private var anchor=CGSize.zero
    @State private var stageSide:CGFloat=340
    @State private var errorMessage=""
    var body:some View {VStack(spacing:10){GeometryReader{geo in let side=geo.size.width;let fit=min(side/image.size.width,side/image.size.height);let displayed=CGSize(width:image.size.width*fit,height:image.size.height*fit);let cropDiameter=WProfilePhotoPolicy.cropDiameter(for:min(displayed.width,displayed.height))
            ZStack{ZStack{Rectangle().fill(.white).frame(width:displayed.width,height:displayed.height);Image(uiImage:image).resizable().scaledToFit().frame(width:side,height:side)};WPhotoCropShade(diameter:cropDiameter,offset:point).fill(.black.opacity(0.56),style:FillStyle(eoFill:true));Circle().stroke(.white,lineWidth:2).frame(width:cropDiameter,height:cropDiameter).overlay(alignment:.bottom){Text("↔").font(W.font(19)).foregroundStyle(.white).frame(width:32,height:24).background(.black.opacity(0.48),in:Capsule()).offset(y:-10)}.offset(point).contentShape(Circle()).gesture(DragGesture().onChanged{v in point=WProfilePhotoPolicy.clampedCropCenter(CGSize(width:anchor.width+v.translation.width,height:anchor.height+v.translation.height),displayedSize:displayed,cropDiameter:cropDiameter)}.onEnded{_ in anchor=point;announceCropPosition();exportCrop(side:side)}).focusable().onKeyPress(keys:[.leftArrow,.rightArrow,.upArrow,.downArrow]){press in let direction:CGSize;switch press.key{case .leftArrow:direction=CGSize(width:-1,height:0);case .rightArrow:direction=CGSize(width:1,height:0);case .upArrow:direction=CGSize(width:0,height:-1);case .downArrow:direction=CGSize(width:0,height:1);default:return .ignored};moveCrop(direction,step:press.modifiers.contains(.shift) ? 16:4);return .handled}.accessibilityElement().accessibilityLabel("프로필 사진에 사용할 원형 영역").accessibilityHint("드래그하거나 방향키로 이동해요. Shift와 함께 누르면 더 크게 이동해요.").accessibilityValue(cropPositionValue).accessibilityIdentifier("profilePhotoCropCircle").accessibilityAddTraits(.isButton).accessibilityAction(named:Text("왼쪽으로 이동")){moveCrop(CGSize(width:-1,height:0))}.accessibilityAction(named:Text("오른쪽으로 이동")){moveCrop(CGSize(width:1,height:0))}.accessibilityAction(named:Text("위로 이동")){moveCrop(CGSize(width:0,height:-1))}.accessibilityAction(named:Text("아래로 이동")){moveCrop(CGSize(width:0,height:1))}}.frame(width:side,height:side).background(Color(red:32.0/255,green:41.0/255,blue:37.0/255)).clipShape(RoundedRectangle(cornerRadius:14)).onAppear{stageSide=side;exportCrop(side:side)}
        }.aspectRatio(1,contentMode:.fit).frame(maxWidth:360).frame(maxWidth:.infinity)
        Text("원을 직접 움직여 프로필로 사용할 부분을 골라 주세요.\n키보드 방향키로도 움직일 수 있어요. Shift와 함께 누르면 더 크게 이동해요.").font(W.font(11)).lineSpacing(6).foregroundStyle(W.muted).multilineTextAlignment(.center).frame(maxWidth:.infinity).accessibilityIdentifier("profilePhotoCropHelp")
        if !errorMessage.isEmpty{WNotice(text:errorMessage,danger:true)}
    }}
    private var cropPositionValue:String {let fit=min(stageSide/image.size.width,stageSide/image.size.height);let displayed=CGSize(width:image.size.width*fit,height:image.size.height*fit);let diameter=WProfilePhotoPolicy.cropDiameter(for:min(displayed.width,displayed.height));let x=WProfilePhotoPolicy.cropPositionPercent(offset:point.width,displayedSide:displayed.width,cropDiameter:diameter);let y=WProfilePhotoPolicy.cropPositionPercent(offset:point.height,displayedSide:displayed.height,cropDiameter:diameter);return "선택 영역: 가로 \(Int(x.rounded()))%, 세로 \(Int(y.rounded()))%"}
    private func moveCrop(_ direction:CGSize,step:CGFloat=4){let fit=min(stageSide/image.size.width,stageSide/image.size.height);let displayed=CGSize(width:image.size.width*fit,height:image.size.height*fit);let diameter=WProfilePhotoPolicy.cropDiameter(for:min(displayed.width,displayed.height));point=WProfilePhotoPolicy.clampedCropCenter(CGSize(width:point.width+direction.width*step,height:point.height+direction.height*step),displayedSize:displayed,cropDiameter:diameter);anchor=point;announceCropPosition();exportCrop(side:stageSide)}
    private func exportCrop(side:CGFloat){let fit=min(side/image.size.width,side/image.size.height);let diameter=WProfilePhotoPolicy.cropDiameter(for:min(image.size.width*fit,image.size.height*fit));let sourceSide=diameter/fit;let center=CGPoint(x:image.size.width/2+point.width/fit,y:image.size.height/2+point.height/fit);let sourceRect=CGRect(x:center.x-sourceSide/2,y:center.y-sourceSide/2,width:sourceSide,height:sourceSide);guard let data=WProfilePhotoPolicy.encode(image:image,crop:sourceRect)else{errorMessage="사진 용량을 줄이지 못했어요. 다른 사진을 선택해 주세요.";return};errorMessage="";updatePhoto(data)}
    private func announceCropPosition(){guard UIAccessibility.isVoiceOverRunning else{return};UIAccessibility.post(notification:.announcement,argument:cropPositionValue)}
}

enum WProfilePhotoPolicy {
    static let maximumInputBytes=20_000_000
    static let maximumOutputBytes=2_000_000
    static let maximumPixels=20_000_000
    static let maximumEdge=8_192
    static let outputEdge=1_024

    static func reviewCaptureFixture()->UIImage {
        let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque=false
        return UIGraphicsImageRenderer(size:CGSize(width:600,height:400),format:format).image{context in
            let cg=context.cgContext;cg.translateBy(x:0,y:400);cg.scaleBy(x:1,y:-1);cg.clear(CGRect(x:0,y:0,width:600,height:400))
            cg.setFillColor(UIColor(red:0.18,green:0.42,blue:0.92,alpha:1).cgColor);cg.fill(CGRect(x:55,y:45,width:230,height:310))
            cg.setFillColor(UIColor(red:0.96,green:0.28,blue:0.18,alpha:1).cgColor);cg.fillEllipse(in:CGRect(x:325,y:45,width:220,height:220))
            cg.setFillColor(UIColor(red:0.20,green:0.80,blue:0.46,alpha:1).cgColor);cg.fill(CGRect(x:330,y:290,width:210,height:65))
            cg.setFillColor(UIColor(red:1,green:0.82,blue:0.10,alpha:1).cgColor);cg.fillEllipse(in:CGRect(x:105,y:135,width:95,height:95))
        }
    }

    static let initialZoom:CGFloat=1.35

    static func accepts(_ type:UTType)->Bool {
        type.conforms(to:.image)
    }

    static func accepts(byteCount:Int)->Bool {
        byteCount>0 && byteCount<=maximumInputBytes
    }

    static func acceptsOutput(byteCount:Int)->Bool {
        byteCount>0 && byteCount<=maximumOutputBytes
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

    static func clampedCropCenter(_ center:CGSize,displayedSize:CGSize,cropDiameter:CGFloat)->CGSize {
        let half=cropDiameter/2
        return CGSize(width:min(displayedSize.width/2-half,max(-displayedSize.width/2+half,center.width)),height:min(displayedSize.height/2-half,max(-displayedSize.height/2+half,center.height)))
    }

    static func cropPositionPercent(offset:CGFloat,displayedSide:CGFloat,cropDiameter:CGFloat)->CGFloat {
        let maximumOffset=max(0,displayedSide/2-cropDiameter/2)
        guard maximumOffset>0 else{return 50}
        let clamped=min(maximumOffset,max(-maximumOffset,offset))
        return (clamped+maximumOffset)/(2*maximumOffset)*100
    }

    static func sanitizeStored(_ data:Data?)->Data? {
        guard let data,acceptsOutput(byteCount:data.count),let info=inspect(data),
              ((info.width==outputEdge && info.height==outputEdge && info.type.conforms(to:.jpeg)) ||
               (info.width==256 && info.height==256 && (info.type.conforms(to:.jpeg) || info.type.conforms(to:.png)) && data.count<=200*1024)) else{return nil}
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
        let normalized=renderer.image{context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin:.zero,size:size))
            let scale=CGFloat(outputEdge)/crop.width
            image.draw(in:CGRect(x:-crop.minX*scale,y:-crop.minY*scale,width:image.size.width*scale,height:image.size.height*scale))
        }
        guard let normalizedCGImage=normalized.cgImage else{return nil}
        for quality in [0.88,0.76,0.6,0.45] {
            let encoded=NSMutableData()
            guard let destination=CGImageDestinationCreateWithData(encoded as CFMutableData,UTType.jpeg.identifier as CFString,1,nil) else{continue}
            CGImageDestinationAddImage(destination,normalizedCGImage,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else{continue}
            let data=encoded as Data
            if data.count<=maximumOutputBytes,
               let decoded=UIImage(data:data)?.cgImage,decoded.width==outputEdge,decoded.height==outputEdge{return data}
        }
        return nil
    }
}

struct WImportedProfilePhoto:Transferable {
    let data:Data
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.image){received in
            WImportedProfilePhoto(data:try WProfilePhotoPolicy.validatedBytes(at:received.file))
        }
    }
}

private enum WProfilePhotoImportError:LocalizedError {
    case invalidPhoto
    var errorDescription:String?{"지원되는 사진 원본을 20 MB 이하(최대 2,000만 화소)로 선택해 주세요."}
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
