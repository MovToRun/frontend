import XCTest
@MainActor final class LaunchTests:XCTestCase {
    var app=XCUIApplication()
    override func setUp(){continueAfterFailure=false}
    func open(_ screen:String="H00",reset:Bool=true){app.launchArguments=["-wire-screen",screen,"-wire-fixture","-appearance","light"];if reset{app.launchArguments.append("-wire-reset")};app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))}
    func tap(_ label:String){let matches=app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label));let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in matches.allElementsBoundByIndex.contains(where:{$0.isHittable})},object:nil);XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed,"Visible button: "+label);matches.allElementsBoundByIndex.first(where:{$0.isHittable})?.tap()}
    func capture(_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="Wire-"+name;a.lifetime = .keepAlways;add(a)}
    func testCoreFlowAndAppearancePersistence(){
        open();let frames=(0...4).map{app.buttons["tab-\($0)"].frame}
        for i in [0,1,2,3,4,3,2,1,0,2]{app.buttons["tab-\(i)"].tap()}
        for i in 0...4{XCTAssertEqual(app.buttons["tab-\(i)"].frame,frames[i])}
        capture("H00")
        tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","화면 테마")).firstMatch.tap()
        app.buttons["theme-dark"].tap();capture("T18-dark")
        app.terminate();app.launchArguments=["-wire-screen","T18","-wire-fixture"];app.launch();XCTAssertTrue(app.buttons["theme-dark"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-dark"].isSelected)
        app.buttons["theme-system"].tap();app.terminate();app.launch();XCTAssertTrue(app.buttons["theme-system"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-system"].isSelected)
        app.buttons["theme-light"].tap()
    }
    func testWeeklyGoalRecordEditingDeletionAndDiscard(){
        open("H04");app.buttons["weeklyTimeToggle"].tap();capture("H04-both")
        app.buttons["saveWeeklyGoal"].tap();tap("tab-1");tap("기록 보기");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","가볍게 달린 아침")).allElementsBoundByIndex.first(where:{$0.isHittable})!.tap()
        tap("editTitle");let title=app.textFields["inlineTitleInput"];title.tap();title.typeText(" — 한글 제목 줄바꿈과 입력 검증");tap("finishTitle");app.swipeUp();tap("editMemo")
        let memo=app.descendants(matching:.any)["inlineMemoInput"].firstMatch;memo.tap();memo.typeText("\n조금씩 달린 오늘의 느낌을 여러 줄로 남깁니다. 긴 한국어 문장이 화면 밖으로 나가지 않는지 확인합니다.")
        tap("finishMemo");capture("L04-long")
        app.swipeUp();app.swipeUp();app.buttons["deleteRecord"].tap();app.buttons["기록 유지"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].exists)
        app.buttons["deleteRecord"].tap();app.buttons["이 기록 삭제"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].exists)
    }
    func testRunningCollapsedDetailFinishAndDuplicateSave(){
        open("H01");app.buttons["startRun"].tap();XCTAssertTrue(app.buttons["pauseRun"].waitForExistence(timeout:5));app.buttons["panelHandle"].tap();capture("R02-collapsed")
        app.buttons["pauseRun"].tap();XCTAssertTrue(app.buttons["resumeRun"].exists);app.buttons["resumeRun"].tap();app.buttons["panelHandle"].tap();app.buttons["상세 기록 보기"].tap();capture("R06")
        app.buttons["러닝 화면으로 돌아가기"].tap();app.buttons["pauseRun"].tap();app.buttons["finishRun"].tap();capture("R05")
        for _ in 0..<3 {app.buttons["아직 쉴게요"].tap();XCTAssertTrue(app.buttons["resumeRun"].isHittable);app.buttons["panelHandle"].tap();XCTAssertTrue(app.buttons["resumeRun"].isHittable);app.buttons["panelHandle"].tap();app.buttons["finishRun"].tap();XCTAssertTrue(app.buttons["saveRun"].isHittable)};app.buttons["saveRun"].doubleTap();XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:5));tap("기록 보기");XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].exists)
    }
    func testAuthenticationConsentAndProviderProtection(){
        open("A01");app.buttons["회원가입"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:5));app.buttons["가상 예시값 채우기"].tap();capture("A07-filled");app.buttons["authPrimary"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        app.buttons["예시 코드 입력"].tap();app.buttons["인증하고 계속"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].exists)
        app.buttons["모두 동의하고 계속"].doubleTap();XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5));let nickname=app.textFields.firstMatch;nickname.tap();nickname.typeText("아침러너");app.buttons["계속"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A15"].exists);capture("A15")
        app.buttons["홈으로"].tap();tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap();capture("T05")
    }
    func testNotificationReadAndProfileValidation(){
        open("M01");tap("알림");let first=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","러닝 목표 안내")).firstMatch;first.tap();capture("N01-read-one");app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].exists)
        app.buttons["카드 편집"].tap();let field=app.textFields.firstMatch;field.tap();field.typeText(String(repeating:"가",count:25));app.buttons["저장하기"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M02"].exists);XCTAssertTrue(app.staticTexts["닉네임은 1–20자, 한 줄 소개는 60자 이내로 입력해 주세요."].exists)
        app.buttons["취소"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].exists)
    }
    func testSegmentsAndGoalInputs(){
        open("L05");XCTAssertTrue(app.descendants(matching:.any)["구간 평균 페이스 그래프"].exists);capture("L05")
        app.terminate();open("H03");app.buttons["goal-none"].tap();XCTAssertFalse(app.descendants(matching:.any)["timeGoalPicker"].exists)
        app.buttons["goal-time"].tap();XCTAssertTrue(app.descendants(matching:.any)["timeGoalPicker"].exists);capture("H03-time")
        app.buttons["이 목표로 달리기"].tap()
    }
}

// Regression coverage for HTML's independent consent topics and fractional run target.
extension LaunchTests {
    func testConsentTopicAndHalfKilometerGoal() {
        open("A02")
        app.buttons.matching(identifier:"내용 확인").element(boundBy:1).tap()
        XCTAssertTrue(app.staticTexts["개인정보 수집·이용"].waitForExistence(timeout:5))
        tap("확인했어요")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        app.terminate();open("H03")
        tap("goal-distance")
        let wheel=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout:5))
        wheel.swipeUp(velocity:.slow)
        capture("H03-fractional")
        tap("이 목표로 달리기")
    }
}

extension LaunchTests {
    func testWeeklyIndependentSelectionAndDarkAppearance() {
        open("H04")
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택 안 됨")
        tap("weeklyTimeToggle");tap("weeklyDistanceToggle")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택 안 됨")
        tap("saveWeeklyGoal");app.terminate();open("H04",reset:false)
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택 안 됨")
        tap("weeklyDistanceToggle");capture("H04-followup-light-both")
        tap("saveWeeklyGoal");app.terminate()
        app.launchArguments=["-wire-screen","H04","-wire-fixture","-appearance","dark"]
        app.launch();XCTAssertTrue(app.buttons["weeklyDistanceToggle"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택됨")
        capture("H04-followup-dark-both")
    }
}

extension LaunchTests {
    func testReducedMotionRunningFlow() {
        app.launchArguments=["-wire-screen","R02","-wire-fixture","-wire-reset","-wire-reduced","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.buttons["panelHandle"].waitForExistence(timeout:10))
        tap("panelHandle");XCTAssertTrue(app.buttons["pauseRun"].isHittable);XCTAssertEqual(app.buttons.matching(identifier:"지도 중심").allElementsBoundByIndex.filter(\.isHittable).count,1)
        tap("pauseRun");XCTAssertTrue(app.buttons["resumeRun"].waitForExistence(timeout:5))
        tap("panelHandle");tap("finishRun")
        XCTAssertTrue(app.descendants(matching:.any)["screen-R05"].waitForExistence(timeout:5))
        tap("아직 쉴게요");tap("resumeRun")
        XCTAssertTrue(app.descendants(matching:.any)["screen-R02"].waitForExistence(timeout:5))
        capture("R02-reduced-motion")
    }
}

extension LaunchTests {
    // No -wire-screen: use the same splash, root navigation and auth routing as ordinary launch.
    func testNormalEntryAuthenticationNotificationsAndRunBothThemes() {
        for theme in ["light","dark"] {
            app.launchArguments=["-wire-fixture","-wire-reset","-appearance",theme]
            app.launch()
            XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:10))
            tap("tab-4");tap("설정");tap("로그아웃");tap("로그아웃")
            XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
            tap("authPrimary")
            XCTAssertTrue(app.staticTexts["예시 이메일을 입력해 주세요."].exists)
            tap("회원가입");tap("가입 취소")
            XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
            tap("가상 예시값 채우기");tap("authPrimary")
            XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
            tap("알림");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","러닝 목표 안내")).firstMatch.tap()
            capture("normal-notification-"+theme);tap("뒤로")
            tap("tab-1");tap("startRun")
            XCTAssertTrue(app.buttons["pauseRun"].waitForExistence(timeout:5))
            tap("panelHandle");XCTAssertTrue(app.buttons["pauseRun"].isHittable);XCTAssertEqual(app.buttons.matching(identifier:"지도 중심").allElementsBoundByIndex.filter(\.isHittable).count,1)
            capture("normal-collapsed-"+theme);tap("panelHandle")
            tap("상세 기록 보기");tap("유효 구간과 원본 기록")
            capture("normal-detail-"+theme);tap("러닝 화면으로 돌아가기")
            tap("pauseRun");tap("finishRun");tap("아직 쉴게요");tap("finishRun")
            tap("saveRun");XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:5))
            tap("기록 보기");capture("normal-saved-"+theme)
            XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].exists)
            app.terminate()
        }
    }
}

extension LaunchTests {
    func testEmptyAndResumableRunRootsUseRunningTab() {
        for screen in ["H02","H05"] {
            open(screen)
            XCTAssertTrue(app.buttons["startRun"].isHittable)
            XCTAssertTrue(app.buttons["tab-1"].isSelected)
            capture(screen+"-running-root")
            tap("startRun")
            XCTAssertTrue(app.buttons["pauseRun"].waitForExistence(timeout:5) || app.buttons["resumeRun"].waitForExistence(timeout:5))
            app.terminate()
        }
    }
}

extension LaunchTests {
    func testEmailCodeLockExpiryResendAndCancel() {
        open("A19")
        let code=app.textFields["인증 코드 6자리"]
        code.tap();code.typeText("111111");app.descendants(matching:.any)["screen-A19"].scrollViews.firstMatch.swipeUp()
        for attempt in 1...5 {
            tap("인증하고 계속")
            XCTAssertTrue(app.descendants(matching:.any)[attempt==5 ? "screen-A22":"screen-A20"].waitForExistence(timeout:5))
        }
        XCTAssertFalse(app.buttons["인증하고 계속"].isEnabled)
        capture("A22-actual-locked")
        app.terminate();open("A21")
        XCTAssertFalse(app.buttons["인증하고 계속"].isEnabled)
        tap("새 예시 코드 요청")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A23"].waitForExistence(timeout:5))
        capture("A23-actual-resent")
        tap("예시 코드 입력");tap("인증하고 계속")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        app.terminate();open("A19");tap("가입 취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
    }
    func testProviderLinkCancelUnlinkAndLastMethodProtection() {
        open("T05")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Google")).firstMatch.tap()
        tap("취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Google")).firstMatch.tap()
        tap("카카오로 재확인 · 예시");tap("Google 인증 완료 · 예시")
        XCTAssertTrue(app.staticTexts["Google이\n연결됐어요"].waitForExistence(timeout:5))
        tap("로그인 수단 확인")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Google")).firstMatch.tap()
        tap("연결 유지")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Google")).firstMatch.tap()
        tap("연결 해제")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","카카오")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-T09"].waitForExistence(timeout:5))
        capture("T09-last-method-protected")
    }
}

extension LaunchTests {
    func testPasswordResetAndEmailMethodManagement() {
        open("A01");tap("비밀번호 찾기");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A11"].waitForExistence(timeout:5))
        tap("새 비밀번호 UI 데모");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A13"].waitForExistence(timeout:5))
        tap("로그인으로");XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
        app.terminate();open("T05");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap();tap("카카오로 재확인 · 예시");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A18"].waitForExistence(timeout:5));tap("로그인 수단 확인")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap()
        tap("카카오로 재확인 · 예시");XCTAssertTrue(app.descendants(matching:.any)["screen-A17"].waitForExistence(timeout:5))
        tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.staticTexts["변경 완료 화면이에요"].waitForExistence(timeout:5));capture("A18-password-changed")
        tap("다시 로그인");XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
    }
    func testLocalRecoveryPrivacyAndCancellationRoutes() {
        let cases:[(String,String,String)]=[
            ("A04","다시 시도","A01"),("H10","목표 유지","H04"),("H11","확인했어요","H07"),
            ("P01","위치 권한 허용 · 예시","R01"),("P02","설정 안내 보기","P04"),("P03","홈으로","H01"),
            ("P04","변경하지 않고 돌아오기","H01"),("P05","공간 확보 후 재시도 · 예시","H01"),
            ("R09","일시정지로 돌아가기","R04"),("R10","정지된 기록 확인","R04"),("R11","기록 유지","R04"),
            ("R12","빈 세션 닫기","R11"),("S03","임시 기록 확인","H06"),("S04","기록 보기","L04"),
            ("S05","홈으로","H00"),("L03","다시 불러오기","L01"),("C01","내 러닝 카드 보기","M01"),
            ("T07","카카오로 로그인","H00"),("T10","계속 사용하기","T01"),("T12","로그인 화면 보기","A01"),
            ("T13","기기 데모 기록 삭제","L02"),("T14","설정으로 돌아가기","T01"),("T16","완료 응답 확인 · 예시","T12")
        ]
        for (screen,label,destination) in cases {
            open(screen);tap(label)
            XCTAssertTrue(app.descendants(matching:.any)["screen-"+destination].waitForExistence(timeout:5),screen+" → "+destination)
            app.terminate()
        }
    }
    func testGradeProgressAndMonthlyCalendar() {
        open("M01");tap("등급 기준")
        XCTAssertTrue(app.staticTexts["새싹러너"].exists)
        XCTAssertTrue(app.staticTexts["누적 거리"].exists)
        XCTAssertTrue(app.staticTexts["활동일"].exists)
        capture("M01-two-progress-and-grades")
        app.terminate();open("H07");tap("이번 달");tap("이전 달");tap("다음 달")
        XCTAssertTrue(app.buttons["이전 달"].exists);capture("H07-month-calendar")
    }
}

// Offline account regression: never enters or stores a real person's credentials.
extension LaunchTests {
    func testAuthIndependentRevealAndOTPBackClearsChallenge() {
        open("A07");tap("가상 예시값 채우기")
        XCTAssertEqual(app.secureTextFields.count,2)
        tap("예시 비밀번호 보기")
        XCTAssertEqual(app.secureTextFields.count,1)
        XCTAssertTrue(app.buttons["예시 비밀번호 숨기기"].exists)
        tap("authPrimary");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:5))
        XCTAssertEqual(app.secureTextFields.count,2)
        tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].exists)
        tap("가상 예시값 채우기");tap("authPrimary");tap("가입 취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
    }
    func testSocialReloginAndConsentPartialValidationBothThemes() {
        for theme in ["light","dark"] {
            app.launchArguments=["-wire-fixture","-wire-reset","-appearance",theme]
            app.launch();XCTAssertTrue(app.buttons["tab-4"].waitForExistence(timeout:10))
            tap("tab-4");tap("설정");tap("로그아웃");tap("로그아웃");tap("카카오로 로그인");tap("인증 성공 · 예시")
            XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
            tap("tab-4");tap("설정");tap("로그아웃");tap("로그아웃");tap("Google로 로그인");tap("인증 오류 · 예시");tap("다시 시도")
            tap("Google로 로그인");tap("인증 취소")
            tap("Google로 로그인");tap("인증 성공 · 예시")
            XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
            app.buttons.matching(identifier:"내용 확인").element(boundBy:1).tap();tap("확인했어요");tap("동의하고 계속")
            XCTAssertTrue(app.staticTexts["필수 항목을 모두 확인해 주세요."].exists)
            app.staticTexts["이용약관 동의 (필수)"].tap();tap("모두 동의하고 계속")
            XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5));capture("A03-consents-"+theme)
            app.terminate()
        }
    }
    func testAccountRemovalConfirmationAndRetry() {
        open("T11");XCTAssertFalse(app.buttons["삭제 흐름 확인 · 시뮬레이션"].isEnabled)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","삭제 흐름의 영향 설명")).firstMatch.tap()
        tap("삭제 흐름 확인 · 시뮬레이션");tap("오류 응답 확인 · 예시")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T11"].waitForExistence(timeout:5))
        tap("계정 유지");XCTAssertTrue(app.descendants(matching:.any)["screen-T01"].waitForExistence(timeout:5))
    }
    func testEmailManageCancelReturnsToProviders() {
        open("T05");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap();tap("카카오로 재확인 · 예시");tap("취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap();tap("카카오로 재확인 · 예시");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5))
    }
}


extension LaunchTests {
    func testSingleGoalWheelBothThemes() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","H03","-wire-fixture","-wire-reset","-wire-review-size","-appearance",theme];app.launch()
            XCTAssertTrue(app.buttons["goal-distance"].waitForExistence(timeout:10));app.buttons["goal-distance"].tap()
            let distance=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
            XCTAssertTrue(distance.waitForExistence(timeout:5));XCTAssertEqual(distance.value as? String,"5 km");capture("H03-distance-"+theme)
            distance.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()
            XCTAssertEqual(distance.value as? String,"5.5 km")
            app.buttons["goal-time"].tap();let time=app.descendants(matching:.any)["timeGoalPicker"].firstMatch
            XCTAssertTrue(time.waitForExistence(timeout:5));XCTAssertEqual(time.value as? String,"30분")
            for _ in 0..<3{time.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()}
            XCTAssertEqual(time.value as? String,"1시간");capture("H03-time-"+theme)
            app.buttons["goal-none"].tap();XCTAssertFalse(time.exists);capture("H03-none-"+theme)
            app.terminate()
        }
    }
    func testProviderCompletionBackAndEmailEscape() {
        open("T01");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap()
        func provider(_ name:String){app.buttons.matching(NSPredicate(format:"label CONTAINS %@",name)).firstMatch.tap()}
        provider("Google");tap("카카오로 재확인 · 예시");tap("Google 인증 완료 · 예시");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5));tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T01"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap()
        provider("이메일");tap("카카오로 재확인 · 예시");tap("취소")
        provider("이메일");tap("카카오로 재확인 · 예시");tap("가상 예시값 채우기");app.buttons["authPrimary"].tap();tap("로그인 수단 확인")
        provider("이메일");tap("카카오로 재확인 · 예시");tap("뒤로")
        provider("이메일");tap("카카오로 재확인 · 예시");tap("취소")
        provider("Apple");tap("카카오로 재확인 · 예시");tap("Apple 인증 완료 · 예시");tap("로그인 수단 확인");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T01"].waitForExistence(timeout:5));capture("Provider-flow-returned-to-settings")
    }
}

extension LaunchTests {
    func testGoalWheelDragAndBounds() {
        open("H03");tap("goal-distance")
        let wheel=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
        func drag(_ element:XCUIElement,_ up:Bool,_ speed:XCUIGestureVelocity){
            let a=element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.92:0.08))
            let b=element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.08:0.92))
            a.press(forDuration:0.05,thenDragTo:b,withVelocity:speed,thenHoldForDuration:0)
        }
        drag(wheel,true,.slow);XCTAssertNotEqual(wheel.value as? String,"5 km")
        drag(wheel,true,.fast);capture("H03-fast-flick")
        drag(wheel,false,.fast);capture("H03-reverse")
        for _ in 0..<10{drag(wheel,false,.fast)}
        XCTAssertEqual(wheel.value as? String,"1 km")
        drag(wheel,false,.slow);XCTAssertEqual(wheel.value as? String,"1 km")
        tap("goal-time");let time=app.descendants(matching:.any)["timeGoalPicker"].firstMatch
        for _ in 0..<3{drag(time,false,.fast)}
        XCTAssertEqual(time.value as? String,"10분")
        for _ in 0..<36{drag(time,true,.fast)}
        XCTAssertEqual(time.value as? String,"6시간");capture("H03-time-upper-bound")
        drag(time,true,.slow);XCTAssertEqual(time.value as? String,"6시간")
        tap("goal-distance");XCTAssertEqual(wheel.value as? String,"1 km")
    }
    func testSummaryMovingPeriodAndCalendarPreservation() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-appearance",theme];app.launch()
            let week=app.buttons["summary-week"],month=app.buttons["summary-month"]
            XCTAssertTrue(week.waitForExistence(timeout:10));let frame=week.frame
            month.tap();XCTAssertTrue(month.isSelected);XCTAssertEqual(week.frame,frame)
            tap("이전 달");let calendar=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","2026년 9월")).firstMatch
            XCTAssertTrue(calendar.exists);capture("H07-month-"+theme)
            week.tap();XCTAssertTrue(week.isSelected);month.tap()
            XCTAssertTrue(calendar.exists);XCTAssertEqual(week.frame,frame)
            week.tap();month.tap();week.tap();XCTAssertTrue(week.isSelected);capture("H07-week-"+theme)
            app.terminate()
        }
        app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-wire-reduced"];app.launch()
        XCTAssertTrue(app.buttons["summary-month"].waitForExistence(timeout:10));tap("summary-month");tap("summary-week")
        XCTAssertTrue(app.buttons["summary-week"].isSelected)
    }
}

extension LaunchTests {
    func testCollapsedRunMapAndRestore() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","R02","-wire-fixture","-wire-reset","-appearance",theme];app.launch()
            let handle=app.buttons["panelHandle"]
            XCTAssertTrue(handle.waitForExistence(timeout:10));handle.tap()
            XCTAssertEqual(handle.label,"러닝 정보 펼치기");XCTAssertGreaterThanOrEqual(handle.frame.height,44)
            XCTAssertLessThan(handle.frame.maxY,app.frame.maxY-20);capture("R02-collapsed-"+theme)
            tap("pauseRun");XCTAssertTrue(app.buttons["resumeRun"].exists);tap("resumeRun")
            handle.tap();XCTAssertEqual(handle.label,"러닝 정보 접기");XCTAssertTrue(app.buttons["상세 기록 보기"].exists)
            capture("R02-expanded-"+theme)
        }
    }
}

extension LaunchTests {
    func userOpen(_ screen:String,compact:Bool=false){
        app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen",screen]
        if compact{app.launchArguments.append("-wire-compact-review")}
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))
    }
    func fillUserAuth(confirm:Bool=false,current:Bool=false){
        if app.textFields["auth-email"].exists{let f=app.textFields["auth-email"];f.tap();f.typeText("runner@example.test")}
        if current{let f=app.secureTextFields["auth-current"];f.tap();f.typeText("MovReview482619\n")}
        let f=app.secureTextFields["auth-password"];if f.exists{f.tap();f.typeText("MovReview482619\n")}
        if confirm{let f=app.secureTextFields["auth-confirm"];f.tap();f.typeText("MovReview482619\n")}
        app.swipeUp()
    }
    func assertRunFrame(_ actual:CGRect,_ expected:CGRect,file:StaticString=#filePath,line:UInt=#line){
        XCTAssertEqual(actual.minX,expected.minX,accuracy:0.5,file:file,line:line)
        XCTAssertEqual(actual.minY,expected.minY,accuracy:0.5,file:file,line:line)
        XCTAssertEqual(actual.width,expected.width,accuracy:0.5,file:file,line:line)
        XCTAssertEqual(actual.height,expected.height,accuracy:0.5,file:file,line:line)
    }
    func testFixedRunPanelUserFlow(){
        for compact in [false,true]{
            userOpen("R02",compact:compact)
            let handle=app.buttons["panelHandle"],primary=app.buttons["pauseRun"],secondary=app.buttons["runDetails"]
            let top=handle.frame,first=primary.frame,second=secondary.frame
            XCTAssertTrue(primary.isHittable);XCTAssertTrue(secondary.isHittable)
            for i in 0..<3{
                tap("pauseRun");assertRunFrame(app.buttons["resumeRun"].frame,first);assertRunFrame(app.buttons["finishRun"].frame,second);assertRunFrame(handle.frame,top)
                tap("finishRun");assertRunFrame(app.buttons["cancelFinish"].frame,first);assertRunFrame(app.buttons["saveRun"].frame,second);assertRunFrame(handle.frame,top)
                XCTAssertTrue(app.buttons["saveRun"].isHittable);if i==0{capture(compact ? "Run-finish-320x568":"Run-finish")}
                tap("cancelFinish");tap("resumeRun");assertRunFrame(primary.frame,first)
            }
            let point=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:first.midX,dy:top.maxY+70))
            point.press(forDuration:0.05,thenDragTo:point.withOffset(CGVector(dx:0,dy:-45)))
            assertRunFrame(primary.frame,first);assertRunFrame(handle.frame,top)
            handle.tap();XCTAssertEqual(handle.label,"러닝 정보 펼치기");tap("pauseRun");tap("resumeRun");handle.tap()
            let restored=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in abs(handle.frame.minY-top.minY)<0.5 && abs(primary.frame.minY-first.minY)<0.5},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:3),.completed)
            assertRunFrame(handle.frame,top);assertRunFrame(primary.frame,first);capture(compact ? "Run-active-320x568":"Run-active")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","확인된 유효 구간만")).firstMatch.exists)
        }
    }
    func testUserLoginSignupResetAndBack(){
        userOpen("A01");XCTAssertFalse(app.buttons["가상 예시값 채우기"].exists);XCTAssertTrue(app.buttons["로그인"].exists)
        fillUserAuth();tap("authPrimary");XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
        userOpen("A01");tap("회원가입");fillUserAuth(confirm:true);tap("authPrimary")
        let otp=app.textFields["인증 코드 6자리"];XCTAssertTrue(otp.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["예시 코드 입력"].exists)
        otp.tap();otp.typeText("000000");tap("인증하고 계속");XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","코드가 일치하지")).firstMatch.exists)
        otp.tap();otp.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:6)+"482619");tap("인증하고 계속")
        tap("모두 동의하고 계속");let nickname=app.textFields.firstMatch;XCTAssertTrue(nickname.waitForExistence(timeout:5));nickname.tap();nickname.typeText("검수러너");tap("계속")
        XCTAssertTrue(app.buttons["홈으로"].waitForExistence(timeout:5));tap("뒤로");XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5));capture("User-signup-home")
        userOpen("A01");tap("비밀번호 찾기");let email=app.textFields["auth-email"];email.tap();email.typeText("runner@example.test\n");tap("authPrimary");tap("계속");fillUserAuth(confirm:true);tap("authPrimary");tap("뒤로")
        XCTAssertTrue(app.buttons["로그인"].waitForExistence(timeout:5));capture("User-reset-login")
    }
    func testUserProviderCompletionCancelAndLogout(){
        userOpen("T01");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Google")).firstMatch.tap();tap("카카오로 계속");tap("연결하기");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5));tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-T01"].exists)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap();app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap();tap("카카오로 계속");tap("취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].exists)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","이메일 · 비밀번호")).firstMatch.tap();tap("카카오로 계속");fillUserAuth(confirm:true);tap("authPrimary");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T05"].waitForExistence(timeout:5));tap("뒤로");tap("로그아웃");tap("로그아웃")
        XCTAssertTrue(app.buttons["로그인"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["가상 예시값 채우기"].exists);capture("User-logout-login")
    }
}


extension LaunchTests {
    func testRunViewportCentersAndSmoothGestures(){
        for theme in ["light","dark"]{for compact in [false,true]{
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen","R02","-appearance",theme]
            if compact{app.launchArguments.append("-wire-compact-review")}
            app.launch();let handle=app.buttons["panelHandle"]
            XCTAssertTrue(handle.waitForExistence(timeout:10))
            let map=app.descendants(matching:.any)["runningMap"].firstMatch
            let marker=app.descendants(matching:.any)["runUserPosition"].firstMatch
            XCTAssertTrue(marker.exists)
            let first=app.buttons["pauseRun"].frame
            let expanded=handle.frame
            XCTAssertEqual(marker.frame.midX,map.frame.midX,accuracy:2)
            XCTAssertEqual(marker.frame.midY,(map.frame.minY+expanded.minY)/2,accuracy:3)
            if !compact{XCTAssertLessThanOrEqual(map.frame.minY,1)}
            capture("Map-expanded-"+theme+(compact ? "-compact":""))
            let background=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:map.frame.midX+60,dy:marker.frame.midY))
            background.press(forDuration:0.1,thenDragTo:background.withOffset(CGVector(dx:30,dy:0)),withVelocity:.slow,thenHoldForDuration:0.1)
            assertRunFrame(handle.frame,expanded)
            tap("위치 상태 안내");assertRunFrame(handle.frame,expanded);tap("위치 상태 안내")
            tap("지도 중심");assertRunFrame(handle.frame,expanded)
            background.tap()
            let centered=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in abs(marker.frame.midY-map.frame.midY)<2},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[centered],timeout:3),.completed)
            capture("Map-collapsed-"+theme+(compact ? "-compact":""))
            let origin=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
            origin.press(forDuration:0.1,thenDragTo:origin.withOffset(CGVector(dx:0,dy:-330)),withVelocity:.slow,thenHoldForDuration:0.2)
            let restored=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in abs(handle.frame.minY-expanded.minY)<1},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:3),.completed)
            assertRunFrame(app.buttons["pauseRun"].frame,first)
            let top=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
            top.press(forDuration:0.1,thenDragTo:top.withOffset(CGVector(dx:0,dy:100)),withVelocity:.slow,thenHoldForDuration:0.2)
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in abs(handle.frame.minY-expanded.minY)<1},object:nil)],timeout:3),.completed)
            XCTAssertEqual(marker.frame.midY,(map.frame.minY+handle.frame.minY)/2,accuracy:3)
        }}
    }

}


extension LaunchTests {
    func visible(_ label:String)->Bool {app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label)).allElementsBoundByIndex.contains{$0.isHittable}}
    func replaceInput(_ field:XCUIElement,_ text:String){XCTAssertTrue(field.waitForExistence(timeout:5));XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5));let old=field.value as? String ?? "";field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+text)}
    func testPointsShopAndHeaderRoutes(){
        userOpen("H00");XCTAssertTrue(visible("알림"));XCTAssertFalse(visible("설정"));capture("Home-bell-only")
        tap("tab-0");XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].exists);XCTAssertEqual(app.buttons["tab-0"].label,"포인트");XCTAssertFalse(visible("설정"));XCTAssertFalse(visible("기록 보기"));XCTAssertTrue(visible("openShop"));capture("Points-empty")
        tap("openShop");XCTAssertTrue(app.descendants(matching:.any)["screen-SHOP"].exists);XCTAssertFalse(visible("tab-0"));capture("Shop-empty-page");tap("뒤로");XCTAssertTrue(app.buttons["tab-0"].isSelected);XCTAssertTrue(visible("openShop"))
        tap("tab-1");XCTAssertTrue(visible("기록 보기"));XCTAssertFalse(visible("알림"));XCTAssertFalse(visible("설정"));capture("Run-records-only")
        tap("기록 보기");XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].exists);capture("Record-list-back")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","가볍게 달린 아침")).firstMatch.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].exists)
        tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].exists);tap("뒤로");XCTAssertTrue(app.buttons["startRun"].isHittable)
        tap("tab-4");XCTAssertTrue(visible("알림"));XCTAssertTrue(visible("설정"));capture("Profile-bell-settings")
        tap("tab-2");tap("전체 보기");tap("뒤로");XCTAssertTrue(app.buttons["tab-2"].isSelected)
    }
    func testIndependentInlineRecordEditing(){
        userOpen("L04");XCTAssertFalse(visible("기록 편집"));tap("editTitle")
        let title=app.textFields["inlineTitleInput"]
        replaceInput(title,String(repeating:"가",count:41));XCTAssertFalse(app.buttons["finishTitle"].isEnabled);XCTAssertEqual(app.staticTexts["inlineTitleCount"].label,"41/40")
        replaceInput(title,"제목만 수정");tap("finishTitle");XCTAssertEqual(app.staticTexts["recordTitle"].label,"제목만 수정")
        app.swipeUp();XCTAssertEqual(app.staticTexts["recordMemo"].label,"가상 예시 기록");tap("editMemo")
        let memo=app.descendants(matching:.any)["inlineMemoInput"].firstMatch
        replaceInput(memo,"첫 줄\n둘째 줄 메모");XCTAssertTrue(app.buttons["finishMemo"].isHittable);XCTAssertTrue(app.staticTexts["inlineMemoCount"].isHittable);capture("Memo-inline-keyboard");tap("finishMemo")
        XCTAssertEqual(app.staticTexts["recordMemo"].label,"첫 줄\n둘째 줄 메모")
        app.swipeDown();XCTAssertEqual(app.staticTexts["recordTitle"].label,"제목만 수정");capture("Title-inline-saved")
        tap("editTitle");replaceInput(title,"저장하지 않을 제목");tap("뒤로")
        tap("전체 보기");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","제목만 수정")).firstMatch.tap();XCTAssertEqual(app.staticTexts["recordTitle"].label,"제목만 수정")
        app.swipeUp();tap("editMemo");replaceInput(memo,String(repeating:"나",count:301));XCTAssertFalse(app.buttons["finishMemo"].isEnabled);XCTAssertEqual(app.staticTexts["inlineMemoCount"].label,"301/300")
        replaceInput(memo,"");tap("finishMemo");XCTAssertEqual(app.staticTexts["recordMemo"].label,"러닝의 느낌을 남겨 보세요");tap("editMemo");replaceInput(memo,"저장하지 않을 메모");tap("뒤로")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","제목만 수정")).firstMatch.tap();app.swipeUp();XCTAssertEqual(app.staticTexts["recordMemo"].label,"러닝의 느낌을 남겨 보세요");capture("Memo-empty-restored")
    }
    func testCompletionReflowsOnce(){
        for screen in ["S01","S05"]{
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen",screen]
            app.launch();XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:5))
            let feedback=app.descendants(matching:.any)["saveCompletionFeedback"].firstMatch
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in !feedback.exists},object:nil)],timeout:5),.completed)
            let heading=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",screen=="S01" ? "잘 달렸어요":"구간이 없어요")).firstMatch
            XCTAssertLessThan(heading.frame.minY,260);let settled=heading.frame
            app.swipeUp();capture(screen+"-calories-no-divider");app.swipeDown();capture(screen+"-reflowed")
            tap("기록 보기");tap("뒤로");XCTAssertFalse(feedback.exists);XCTAssertEqual(heading.frame,settled)
        }
    }
}

extension LaunchTests {
    func testPointIconAppearanceCapture(){
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen","POINTS","-appearance",theme]
            app.launch();XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["tab-0"].isSelected);capture("PointIcon-selected-"+theme)
            tap("tab-2");XCTAssertFalse(app.buttons["tab-0"].isSelected);capture("PointIcon-unselected-"+theme);app.terminate()
        }
    }
}
