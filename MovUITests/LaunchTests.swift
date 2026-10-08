import XCTest
import UIKit
@MainActor final class LaunchTests:XCTestCase {
    var app=XCUIApplication()
    override func setUp(){continueAfterFailure=false}
    func open(_ screen:String="H00",reset:Bool=true){app.launchArguments=["-wire-screen",screen,"-wire-fixture","-appearance","light"];if reset{app.launchArguments.append("-wire-reset")};app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))}
    func tap(_ label:String){let matches=app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label));let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in matches.allElementsBoundByIndex.contains(where:{$0.isHittable})},object:nil);XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed,"Visible button: "+label);matches.allElementsBoundByIndex.first(where:{$0.isHittable})?.tap()}
    func waitHittable(_ element:XCUIElement,timeout:Double=3)->Bool{let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in element.exists && element.isHittable},object:nil);return XCTWaiter.wait(for:[ready],timeout:timeout) == .completed}
    func waitForLayout(_ condition:@escaping()->Bool,timeout:Double=3)->Bool{let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in condition()},object:nil);return XCTWaiter.wait(for:[ready],timeout:timeout) == .completed}
    func capture(_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="Wire-"+name;a.lifetime = .keepAlways;add(a)}
    func containsBrandGreen(in image:UIImage, rect:CGRect)->Bool {
        guard let source=image.cgImage else{return false}
        let scale=image.scale
        let pixelsRect=CGRect(x:rect.minX*scale,y:rect.minY*scale,width:rect.width*scale,height:rect.height*scale).integral
        let bounds=CGRect(x:0,y:0,width:source.width,height:source.height)
        guard let crop=source.cropping(to:pixelsRect.intersection(bounds)),crop.width>0,crop.height>0 else{return false}
        var pixels=[UInt8](repeating:0,count:crop.width*crop.height*4)
        pixels.withUnsafeMutableBytes{bytes in
            guard let context=CGContext(data:bytes.baseAddress,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue) else{return}
            context.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
        }
        return pixels.withUnsafeBufferPointer{bytes in
            stride(from:0,to:bytes.count,by:4).contains{index in bytes[index+1]>180 && bytes[index]<160 && bytes[index+2]<180 && bytes[index+3]>200}
        }
    }
    func containsDarkPixel(in image:UIImage, rect:CGRect)->Bool {
        guard let source=image.cgImage else{return false}
        let scale=image.scale
        let pixelsRect=CGRect(x:rect.minX*scale,y:rect.minY*scale,width:rect.width*scale,height:rect.height*scale).integral
        let bounds=CGRect(x:0,y:0,width:source.width,height:source.height)
        guard let crop=source.cropping(to:pixelsRect.intersection(bounds)),crop.width>0,crop.height>0 else{return false}
        var pixels=[UInt8](repeating:0,count:crop.width*crop.height*4)
        pixels.withUnsafeMutableBytes{bytes in
            guard let context=CGContext(data:bytes.baseAddress,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue) else{return}
            context.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
        }
        return pixels.withUnsafeBufferPointer{bytes in
            stride(from:0,to:bytes.count,by:4).contains{index in bytes[index]<80 && bytes[index+1]<90 && bytes[index+2]<80 && bytes[index+3]>200}
        }
    }
    func testReview52RunPanelAndRecordListDetailAlignment() {
        app.launchArguments=["-wire-screen","R02","-wire-fixture","-wire-reset","-wire-capture-viewport","-wire-reduced","-appearance","light"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-R02"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["runValidityExplanation"].waitForExistence(timeout:5))
        let pause=app.buttons["pauseRun"],details=app.buttons["runDetails"]
        XCTAssertTrue(pause.isHittable);XCTAssertTrue(details.isHittable)
        XCTAssertEqual(pause.frame.width,342,accuracy:0.5,"Review52 panel actions use the 342pt inset width")
        XCTAssertEqual(details.frame.width,342,accuracy:0.5)
        XCTAssertEqual(pause.frame.height,58,accuracy:0.5,"The final Review52 cascade sets 58pt action rows")
        XCTAssertEqual(details.frame.height,58,accuracy:0.5)
        XCTAssertEqual(details.frame.minY-pause.frame.maxY,10,accuracy:0.5,"The source action rows have a 10pt gap")
        let runningMap=app.descendants(matching:.any)["runningMap"].firstMatch
        XCTAssertTrue(runningMap.exists)
        XCTAssertEqual(pause.frame.minY-runningMap.frame.minY,619,accuracy:4,"The source action stack begins at y=643 after the 24pt simulation banner")
        XCTAssertEqual(app.staticTexts["runDistanceMetric"].frame.minY-runningMap.frame.minY,380,accuracy:6,"The source distance value begins near y=404 after the 24pt simulation banner")
        let gpsSignal=app.buttons.matching(identifier:"위치 상태 안내").firstMatch
        XCTAssertEqual(gpsSignal.value as? String,"GPS 연결됨")
        XCTAssertTrue(containsBrandGreen(in:app.screenshot().image,rect:gpsSignal.frame),"The connected GPS signal uses the source lime color")
        capture("R02-pause-panel-390x790")
        pause.tap();XCTAssertTrue(app.buttons["resumeRun"].waitForExistence(timeout:5))
        app.buttons["resumeRun"].tap();XCTAssertTrue(app.buttons["pauseRun"].waitForExistence(timeout:5))
        app.terminate()

        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-reset","-wire-capture-viewport","-appearance","light"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["tab-1"].isSelected,"The record list keeps the Run root selected")
        XCTAssertFalse(app.buttons["뒤로"].exists,"The root list uses the source header rather than a pushed-page back control")
        XCTAssertEqual(app.staticTexts["recordDate"].label,"2026.09.29")
        XCTAssertEqual(app.staticTexts["recordValidityTime"].label,"30:08 유효 러닝")
        XCTAssertEqual(app.staticTexts["recordPace"].label,"06:15 /km")
        XCTAssertEqual(app.descendants(matching:.any)["recordPointExample"].label,"예시 적립 30 포인트")
        capture("L01-record-list-390x790")

        let record=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","record-")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout:5));XCTAssertTrue(record.isHittable)
        record.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.staticTexts["recordReferenceDate"].waitForExistence(timeout:5),"Opening a saved record should show its detail date")
        XCTAssertEqual(app.staticTexts["recordReferenceDate"].label,"2026.09.29 · 가상 예시")
        capture("L04-record-detail-390x790")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["tab-1"].isSelected,"Back from detail returns to the records root")
    }

    func testReview52BrandMarksRenderFromLocalAsset() {
        for screen in ["H00","H01"] {
            app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-reset","-appearance","light"]
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:10))
            let headerMarks=app.images.matching(identifier:"rootHeaderBrandMark").allElementsBoundByIndex
            XCTAssertTrue(headerMarks.first?.waitForExistence(timeout:5) ?? false,"\(screen) keeps its source-defined header logo")
            let screenshot=app.screenshot().image
            let headerMarkRegion=CGRect(x:8,y:40,width:48,height:48)
            // The final Review52 cascade overrides the initial dark-tile rule: 30×30, transparent, inset 0.
            let visibleHeaderMark=headerMarks.first{$0.frame.intersects(headerMarkRegion)}
            XCTAssertNotNil(visibleHeaderMark,"\(screen) header logo must be in the leading header slot")
            if let visibleHeaderMark {
                XCTAssertEqual(visibleHeaderMark.frame.width,30,accuracy:0.5,"The final header mark is 30pt wide")
                XCTAssertEqual(visibleHeaderMark.frame.height,30,accuracy:0.5,"The final header mark is 30pt high")
            }
            XCTAssertTrue(containsBrandGreen(in:screenshot,rect:headerMarkRegion),"\(screen) header logo must render from the bundled mask asset")
            XCTAssertFalse(containsDarkPixel(in:screenshot,rect:headerMarkRegion),"\(screen) header mark must not gain a dark tile")
            if screen == "H00" {
                let homeTab=app.buttons["tab-2"]
                XCTAssertEqual(homeTab.label,"홈","The home tab keeps its VoiceOver name")
                XCTAssertFalse(app.staticTexts["tab-caption-2"].exists,"The home logo has no visible caption")
                let tabMark=app.images.matching(identifier:"homeTabBrandMark").firstMatch
                XCTAssertTrue(tabMark.waitForExistence(timeout:5),"The centered home tab uses the source brand mark")
                let homeMarkRegion=CGRect(x:homeTab.frame.midX-16,y:homeTab.frame.minY+7,width:32,height:32)
                let tabScreenshot=app.screenshot().image
                XCTAssertTrue(containsBrandGreen(in:tabScreenshot,rect:homeMarkRegion),"The 26pt tab asset must visibly render; an empty CSS-mask-like capture is not acceptable")
                XCTAssertFalse(containsDarkPixel(in:tabScreenshot,rect:homeMarkRegion),"The center mark has no tile background")
            }
            capture(screen+"-brand-mark")
            app.terminate()
        }
    }
    func testCoreFlowAndAppearancePersistence(){
        open();let frames=(0...4).map{app.buttons["tab-\($0)"].frame}
        XCTAssertEqual(app.buttons["tab-2"].label,"홈","Home keeps its VoiceOver name")
        XCTAssertFalse(app.staticTexts["tab-caption-2"].exists,"Home has no visible caption")
        XCTAssertFalse(app.staticTexts["홈"].exists,"Home has no visible caption")
        for title in ["포인트","러닝","커뮤니티","내 정보"] {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@",title)).firstMatch.exists,"Visible tab caption: \(title)")
        }
        for i in [0,1,2,3,4,3,2,1,0,2]{app.buttons["tab-\(i)"].tap()}
        for i in 0...4{XCTAssertEqual(app.buttons["tab-\(i)"].frame,frames[i])}
        capture("H00")
        tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","화면 테마")).firstMatch.tap()
        app.buttons["theme-dark"].tap();capture("T18-dark")
        app.terminate();app.launchArguments=["-wire-screen","T18","-wire-fixture"];app.launch();XCTAssertTrue(app.buttons["theme-dark"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-dark"].isSelected)
        app.buttons["theme-system"].tap();app.terminate();app.launch();XCTAssertTrue(app.buttons["theme-system"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-system"].isSelected)
        app.buttons["theme-light"].tap()
    }
    func testHomeTabAlignmentAtAccessibilityTextSize(){
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-reset","-wire-large"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        let frames=(0...4).map{app.buttons["tab-\($0)"].frame}
        for frame in frames.dropFirst(){XCTAssertEqual(frame.minY,frames[0].minY,accuracy:0.5);XCTAssertEqual(frame.height,frames[0].height,accuracy:1.0)}
        XCTAssertEqual(app.buttons["tab-2"].label,"홈","Home keeps its VoiceOver name at large text sizes")
        XCTAssertFalse(app.staticTexts["홈"].exists,"The home logo has no visible caption")
        XCTAssertTrue(app.staticTexts["tab-caption-1"].exists)
        capture("H00-accessibility3-tab-alignment")
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
        app.buttons["pauseRun"].tap();XCTAssertTrue(app.buttons["resumeRun"].exists);app.buttons["resumeRun"].tap();app.buttons["panelHandle"].tap();tap("상세 기록 보기");capture("R06")
        XCTAssertTrue(app.buttons["러닝 화면으로 돌아가기"].waitForExistence(timeout:5),app.debugDescription);tap("러닝 화면으로 돌아가기");XCTAssertTrue(waitHittable(app.buttons["pauseRun"]));app.buttons["pauseRun"].tap();app.buttons["finishRun"].tap();capture("R05")
        for _ in 0..<3 {app.buttons["아직 쉴게요"].tap();XCTAssertTrue(waitHittable(app.buttons["resumeRun"]));tap("panelHandle");XCTAssertTrue(waitHittable(app.buttons["resumeRun"]));tap("panelHandle");tap("finishRun");XCTAssertTrue(waitForLayout({self.app.buttons["saveRun"].exists && self.app.buttons["saveRun"].isHittable},timeout:5),app.debugDescription)};app.buttons["saveRun"].doubleTap();XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:5));tap("기록 보기");XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].exists)
    }
    func testAuthenticationConsentAndProviderProtection(){
        open("A01");app.buttons["회원가입"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:5));app.buttons["가상 예시값 채우기"].tap();capture("A07-filled");app.buttons["authPrimary"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        app.buttons["예시 코드 입력"].tap();app.buttons["인증하고 계속"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].exists)
        app.buttons["모두 동의하고 계속"].doubleTap();XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5));let nickname=app.textFields.firstMatch;nickname.tap();nickname.typeText("아침러너");app.buttons["계속"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A15"].exists);capture("A15")
        app.buttons["홈으로"].tap();tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap();capture("T05")
    }
    func testNotificationReadAndProfileValidation(){
        open("M01");tap("알림");let first=app.buttons["notification-0"];XCTAssertTrue(first.waitForExistence(timeout:5),app.debugDescription);XCTAssertTrue(waitHittable(first,timeout:5),app.debugDescription);XCTAssertTrue(first.label.contains("러닝 목표 안내"),first.debugDescription);first.tap();capture("N01-read-one");app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].exists)
        app.buttons["카드 편집"].tap();let field=app.textFields.firstMatch;field.tap();field.typeText(String(repeating:"가",count:25));app.buttons["저장하기"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M02"].exists);XCTAssertTrue(app.staticTexts["닉네임은 1–20자, 한 줄 소개는 60자 이내로 입력해 주세요."].exists)
        app.buttons["취소"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].exists)
    }
    func testProfileEditPersistsAndNotificationRecoveryStates() {
        open("M01");tap("카드 편집");let nickname=app.textFields.firstMatch
        let existing=nickname.value as? String ?? "";nickname.tap();nickname.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:existing.count)+"테스트러너");tap("저장하기")
        XCTAssertTrue(app.staticTexts["테스트러너"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments=["-wire-screen","M01","-wire-fixture"];app.launch()
        XCTAssertTrue(app.staticTexts["테스트러너"].waitForExistence(timeout:10),"The profile edit persists in the fixture store")

        app.terminate();app.launchArguments=["-wire-screen","M01","-wire-fixture","-wire-reset","-wire-empty-notifications","-appearance","light"];app.launch()
        let bell=app.buttons.matching(identifier:"notificationBell").firstMatch;XCTAssertTrue(bell.waitForExistence(timeout:10));XCTAssertEqual(bell.value as? String,"읽음")
        tap("notificationBell");XCTAssertTrue(app.descendants(matching:.any)["notificationEmptyState"].waitForExistence(timeout:5))

        app.terminate();app.launchArguments=["-wire-screen","N01","-wire-fixture","-wire-reset","-wire-notification-save-fail-once","-appearance","light"];app.launch()
        let matchingNotifications=app.buttons.matching(identifier:"notification-0")
        XCTAssertTrue(matchingNotifications.firstMatch.waitForExistence(timeout:10))
        let first=matchingNotifications.allElementsBoundByIndex.first(where:{$0.isHittable}) ?? matchingNotifications.firstMatch
        XCTAssertTrue(first.isHittable,app.debugDescription);first.tap()
        XCTAssertTrue((first.value as? String ?? "").contains("펼침"),app.debugDescription)
        XCTAssertTrue(app.buttons["retryNotificationRead"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.staticTexts["읽지 않음"].exists)
        tap("retryNotificationRead");XCTAssertTrue(app.staticTexts["읽음"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments=["-wire-screen","N01","-wire-fixture","-appearance","light"];app.launch()
        XCTAssertTrue(app.staticTexts["읽음"].waitForExistence(timeout:10),"A successful retry persists the read state locally")
    }
    func testPrivacyReauthenticationCancelReturnsToPrivacySettings() {
        open("T01");let privacy=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","개인정보·데이터")).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout:5));for _ in 0..<3 where !privacy.isHittable{app.swipeUp()};XCTAssertTrue(privacy.isHittable);privacy.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-T04"].exists)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","회원 탈퇴")).firstMatch.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-T15"].waitForExistence(timeout:5))
        tap("취소");XCTAssertTrue(app.descendants(matching:.any)["screen-T04"].waitForExistence(timeout:5))
        tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-T01"].waitForExistence(timeout:5))
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
    func testRunMetricsStayUnavailableUntilDistanceIsValid() {
        open("R01")
        XCTAssertEqual(app.staticTexts["runDistanceMetric"].label,"— km")
        XCTAssertEqual(app.staticTexts["runPaceMetric"].label,"— /km")
        app.terminate()
        open("S05")
        XCTAssertEqual(app.staticTexts["runDistanceMetric"].label,"0.00 km")
        XCTAssertEqual(app.staticTexts["runPaceMetric"].label,"0:00 /km")
    }

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
    func testAuthCompactViewportKeyboardFooterAndLargeText(){
        app.launchArguments=["-wire-screen","A07","-wire-fixture","-wire-reset","-wire-compact-review","-wire-large"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:15))
        let email=app.textFields["auth-email"]
        email.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(email.isHittable,"The focused field remains usable above the keyboard")
        XCTAssertTrue(app.buttons["가입 취소"].isHittable,"The cancel action remains reachable in the compact safe area")
        app.buttons["가입 취소"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
    }

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
        let oldCode=app.staticTexts["publicDemoEmailCode"].label.components(separatedBy:" ").last!
        tap("requestNewEmailCode")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A23"].waitForExistence(timeout:5))
        let newCode=app.staticTexts["publicDemoEmailCode"].label.components(separatedBy:" ").last!
        XCTAssertNotEqual(newCode,oldCode,"A resend must invalidate the previously issued code")
        capture("A23-actual-resent")
        let otp=app.textFields["emailOtpInput"];otp.tap();otp.typeText(oldCode)
        app.buttons["verifyEmailCode"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A20"].waitForExistence(timeout:5),"The old code must be rejected after resend")
        tap("fillDemoEmailCode");tap("verifyEmailCode")
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
        tap("auth-reveal-auth-password")
        XCTAssertEqual(app.secureTextFields.count,1)
        XCTAssertEqual(app.buttons["auth-reveal-auth-password"].label,"비밀번호 숨기기")
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
        open("T11")
        let acknowledge=app.buttons["accountDeletionImpactAcknowledgement"]
        let confirm=app.buttons["confirmAccountDeletion"]
        XCTAssertTrue(app.descendants(matching:.any)["accountDeletionImpactNotice"].exists)
        XCTAssertTrue(app.staticTexts["삭제 흐름의 영향 설명을 확인했어요"].exists)
        XCTAssertFalse(confirm.isEnabled)
        acknowledge.tap()
        XCTAssertTrue(acknowledge.isSelected)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-T16"].waitForExistence(timeout:5))
        tap("오류 응답 확인 · 예시")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T11"].waitForExistence(timeout:5))
        XCTAssertFalse(acknowledge.isSelected);XCTAssertFalse(confirm.isEnabled)
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
    func testEmptyRecordListAndLookupFailureAreDistinct() {
        for screen in ["L02","L03"] {
            app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-reset","-wire-review-size","-appearance","light"]
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:10))
            if screen=="L02" {
                XCTAssertTrue(app.staticTexts["아직 러닝 기록이 없어요"].waitForExistence(timeout:5))
                XCTAssertFalse(app.otherElements["recordLookupFailure"].exists)
            } else {
                XCTAssertTrue(app.descendants(matching:.any)["recordLookupFailure"].waitForExistence(timeout:5))
                XCTAssertFalse(app.staticTexts["아직 러닝 기록이 없어요"].exists)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","0건이라고 단정하지 않아요")).firstMatch.exists)
            }
        }
    }

    func testInvalidRecordDetailsShowOnlyRecordedExclusionReason() {
        open("S05")
        tap("기록 보기")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:5))
        tap("유효 구간과 원본 기록")
        XCTAssertTrue(app.staticTexts["GPS 수신 실패 예시"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","임의로 분류하지 않아요")).firstMatch.exists)
    }

    func testShareImageCreationGalleryAndDelete() {
        app.launchArguments=["-wire-screen","Q01","-wire-fixture","-wire-reset","-appearance","light"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-Q01"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["shareCreateImage"].exists);XCTAssertTrue(waitHittable(app.buttons["shareFormatStory"],timeout:10),app.debugDescription);app.buttons["shareFormatStory"].tap();app.swipeUp();tap("shareSelect-route")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","코스 색")).firstMatch.exists)
        tap("shareSelect-metrics");XCTAssertTrue(app.buttons["shareCreateImage"].exists)
        tap("shareCreateImage");XCTAssertTrue(app.descendants(matching:.any)["screen-Q02"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["shareOutputPreview"].waitForExistence(timeout:5))
        let outputDetails=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","PNG ·")).firstMatch
        XCTAssertTrue(outputDetails.waitForExistence(timeout:5),app.debugDescription)
        let dimensions=outputDetails.label.components(separatedBy:" · ").last?.components(separatedBy:" px").first?.components(separatedBy:" × ") ?? []
        XCTAssertEqual(dimensions.count,2,outputDetails.label)
        if dimensions.count==2,let width=Double(dimensions[0]),let height=Double(dimensions[1]) {
            XCTAssertEqual(width/height,9.0/16.0,accuracy:0.002,outputDetails.label)
            XCTAssertLessThanOrEqual(width,1080,outputDetails.label)
            XCTAssertLessThanOrEqual(height,1920,outputDetails.label)
        }
        if let bytes=outputDetails.label.components(separatedBy:" · ").dropFirst().first.flatMap(Int.init){XCTAssertLessThanOrEqual(bytes,2*1024*1024)}
        app.swipeUp();tap("shareOpenGallery");XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:5))
        let remove=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","deleteShare-")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout:5));remove.tap();app.alerts.buttons["삭제"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["shareGalleryEmpty"].waitForExistence(timeout:5))
        capture("Q03-empty-after-delete")
    }

    func testShareEditorCancelAndDynamicType() {
        app.launchArguments=["-wire-screen","Q03","-wire-fixture","-wire-reset","-wire-compact-review","-wire-large","-appearance","light"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:10))
        tap("shareNewImage");XCTAssertTrue(app.descendants(matching:.any)["screen-Q01"].waitForExistence(timeout:5))
        tap("shareFormatStory");app.swipeUp();tap("shareDescription")
        XCTAssertTrue(app.textViews["shareDescriptionInput"].waitForExistence(timeout:5));app.buttons["완료"].tap()
        app.swipeUp();tap("shareCreateImage")
        XCTAssertTrue(app.descendants(matching:.any)["screen-Q02"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["shareOutputPreview"].waitForExistence(timeout:5))
    }

    func testShareEditorCancelReturnsToGallery() {
        app.launchArguments=["-wire-screen","Q03","-wire-fixture","-wire-reset","-appearance","light"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:10))
        tap("shareNewImage");XCTAssertTrue(app.descendants(matching:.any)["screen-Q01"].waitForExistence(timeout:5))
        tap("shareFormatStory");app.swipeUp();tap("취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["shareGalleryEmpty"].exists)
    }

    func testDeletingParentRecordRemovesItsShareArtifacts() {
        open("L04")
        app.swipeUp();app.swipeUp();tap("openShareGallery");XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:5))
        tap("shareNewImage");XCTAssertTrue(app.descendants(matching:.any)["screen-Q01"].waitForExistence(timeout:5))
        tap("shareCreateImage");XCTAssertTrue(app.descendants(matching:.any)["screen-Q02"].waitForExistence(timeout:10))
        tap("shareOpenGallery");XCTAssertTrue(app.descendants(matching:.any)["screen-Q03"].waitForExistence(timeout:5))
        tap("뒤로");tap("뒤로");tap("뒤로");tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:5))
        app.swipeUp();tap("deleteRecord");tap("이 기록 삭제")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["아직 러닝 기록이 없어요"].exists)
    }

    func testSummaryMovingPeriodAndCalendarPreservation() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-appearance",theme];app.launch()
            let week=app.buttons["summary-week"],month=app.buttons["summary-month"]
            XCTAssertTrue(week.waitForExistence(timeout:10));let frame=week.frame
            month.tap();XCTAssertTrue(waitForLayout({month.isSelected}));XCTAssertEqual(week.frame,frame)
            XCTAssertTrue(app.staticTexts["월간 유효 거리"].exists)
            let calendarMonth=app.staticTexts["calendarMonthTitle"]
            XCTAssertTrue(calendarMonth.waitForExistence(timeout:5));let selectedMonth=calendarMonth.label
            tap("이전 달")
            XCTAssertTrue(waitForLayout({calendarMonth.exists && calendarMonth.label != selectedMonth}))
            let priorMonth=calendarMonth.label
            XCTAssertTrue(app.staticTexts["월간 유효 거리"].exists);capture("H07-month-"+theme)
            week.tap();XCTAssertTrue(week.isSelected);month.tap()
            XCTAssertEqual(calendarMonth.label,priorMonth);XCTAssertEqual(week.frame,frame)
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
            XCTAssertTrue(handle.waitForExistence(timeout:10));tap("panelHandle")
            XCTAssertTrue(waitForLayout({let current=self.app.buttons.matching(identifier:"panelHandle").firstMatch;return current.exists && current.frame.minY>self.app.frame.midY}),app.debugDescription)
            let collapsedHandle=app.buttons.matching(identifier:"panelHandle").firstMatch
            XCTAssertGreaterThanOrEqual(collapsedHandle.frame.height,44)
            XCTAssertLessThan(collapsedHandle.frame.maxY,app.frame.maxY-20);capture("R02-collapsed-"+theme)
            tap("pauseRun");XCTAssertTrue(app.buttons["resumeRun"].exists);tap("resumeRun")
            tap("panelHandle");XCTAssertTrue(waitForLayout({let current=self.app.buttons.matching(identifier:"panelHandle").firstMatch;return current.exists && current.frame.minY<self.app.frame.midY}),app.debugDescription);XCTAssertTrue(app.buttons["상세 기록 보기"].exists)
            capture("R02-expanded-"+theme)
        }
    }
}

extension LaunchTests {
    func userOpen(_ screen:String,compact:Bool=false,captureViewport:Bool=false){
        app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen",screen]
        if compact{app.launchArguments.append("-wire-compact-review")}
        if captureViewport{app.launchArguments.append("-wire-capture-viewport")}
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))
    }
    func fillUserAuth(confirm:Bool=false,current:Bool=false){
        if app.textFields["auth-email"].exists{let f=app.textFields["auth-email"];f.tap();f.typeText("runner@example.test");XCTAssertEqual(f.value as? String,"runner@example.test")}
        func enterPassword(_ identifier:String){let secure=app.secureTextFields[identifier];let reveal=app.buttons["auth-reveal-\(identifier)"];if secure.exists && reveal.exists{reveal.tap()};let field=app.textFields[identifier].exists ? app.textFields[identifier]:secure;field.tap();field.typeText("MovReview482619");if app.textFields[identifier].exists{XCTAssertEqual(field.value as? String,"MovReview482619","Entered value for \(identifier)")}}
        if current{enterPassword("auth-current")}
        if app.secureTextFields["auth-password"].exists{enterPassword("auth-password")}
        if confirm{enterPassword("auth-confirm")}
        if confirm{app.typeText("\n")}
        let done=app.keyboards.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","완료","Done")).firstMatch
        if done.exists && done.isHittable{done.tap()}
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
                tap("pauseRun");XCTAssertTrue(waitHittable(app.buttons["resumeRun"]),app.debugDescription);XCTAssertTrue(waitHittable(app.buttons["finishRun"]),app.debugDescription);assertRunFrame(app.buttons["resumeRun"].frame,first);assertRunFrame(app.buttons["finishRun"].frame,second);assertRunFrame(handle.frame,top)
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
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5),app.debugDescription)
        let otp=app.descendants(matching:.any)["emailOtpInput"];XCTAssertTrue(otp.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["fillDemoEmailCode"].exists)
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
    func testReview52A01LayoutAndPasswordControls() {
        userOpen("A01",captureViewport:true)
        XCTAssertEqual(app.secureTextFields["auth-password"].placeholderValue,"8자 이상 입력")
        XCTAssertFalse(app.buttons["auth-reveal-auth-password"].exists)
        let gap=app.secureTextFields["auth-password"].frame.minY-app.textFields["auth-email"].frame.maxY
        XCTAssertGreaterThan(gap,90)
        XCTAssertLessThan(gap,110)
    }

    func testReview52H00ReferenceWeekShowsSeededGoalProgress() {
        app.launchArguments=["-wire-fixture","-wire-reset","-wire-screen","H00","-wire-capture-viewport","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["10월 1일 목요일 · 가상 예시"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","4.82")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["24%"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","2026.09.29 · 30:08 유효 러닝 · 예시")).firstMatch.exists)
    }

    func testReview52H01StartsInGPSWaitingState() {
        app.launchArguments=["-wire-fixture","-wire-reset","-wire-screen","H01","-wire-capture-viewport","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.buttons["startRun"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["위치 상태 안내"].value as? String,"GPS 연결 전")
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
    func visibleMapRecenter() -> XCUIElement? {
        app.buttons.matching(identifier:"mapRecenter").allElementsBoundByIndex.first(where:{$0.isHittable})
    }

    func testRunMapPanAndRecenterTracksVisibleViewport() {
        for collapsed in [false,true] {
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-screen","R02","-appearance","light"]
            if collapsed { app.launchArguments.append("-wire-collapsed") }
            app.launch()
            let map=app.descendants(matching:.any)["runningMap"].firstMatch
            let marker=app.descendants(matching:.any)["runUserPosition"].firstMatch
            let handle=app.buttons["panelHandle"]
            XCTAssertTrue(map.waitForExistence(timeout:10))
            XCTAssertEqual(visibleMapRecenter()?.value as? String,"중심")
            let targetY=collapsed ? map.frame.midY:(map.frame.minY+handle.frame.minY)/2
            XCTAssertEqual(marker.frame.midX,map.frame.midX,accuracy:2)
            XCTAssertEqual(marker.frame.midY,targetY,accuracy:3)

            let startX=map.frame.minX+map.frame.width*0.28,startY=targetY+30
            let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:startX,dy:startY))
            let destination=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:startX+72,dy:startY+48))
            origin.press(forDuration:0.1,thenDragTo:destination,withVelocity:.slow,thenHoldForDuration:0.1)
            XCTAssertTrue(waitForLayout({self.visibleMapRecenter()?.value as? String == "이동됨"},timeout:3),app.debugDescription)
            XCTAssertGreaterThan(abs(marker.frame.midX-map.frame.midX),20)
            XCTAssertGreaterThan(abs(marker.frame.midY-targetY),20)

            tap("mapRecenter")
            let recentered=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
                self.visibleMapRecenter()?.value as? String == "중심" && abs(marker.frame.midX-map.frame.midX)<2 && abs(marker.frame.midY-targetY)<3
            },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[recentered],timeout:3),.completed,app.debugDescription)
            capture(collapsed ? "Map-recenter-collapsed":"Map-recenter-expanded")
        }
    }
}


extension LaunchTests {
    func visible(_ label:String)->Bool {app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label)).allElementsBoundByIndex.contains{$0.isHittable}}
    func replaceInput(_ field:XCUIElement,_ text:String){XCTAssertTrue(field.waitForExistence(timeout:5));XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5));let old=field.value as? String ?? "";field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+text)}
    func testPointsShopAndHeaderRoutes(){
        userOpen("H00");XCTAssertTrue(visible("알림"));XCTAssertFalse(visible("설정"));capture("Home-bell-only")
        tap("tab-0");XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:5));XCTAssertEqual(app.buttons["tab-0"].label,"포인트");XCTAssertFalse(visible("설정"));XCTAssertFalse(visible("기록 보기"));XCTAssertTrue(visible("browsePointShop"),app.debugDescription);XCTAssertTrue(app.staticTexts["pointBalance"].exists,app.debugDescription);capture("Points-overview")
        tap("pointGuideOverview");XCTAssertTrue(app.descendants(matching:.any)["screen-B04"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","포인트로")).firstMatch.exists);tap("browsePointShopFromGuide");XCTAssertTrue(app.descendants(matching:.any)["screen-SHOP"].waitForExistence(timeout:5));tap("뒤로");tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:5))
        tap("browsePointShop");XCTAssertTrue(app.descendants(matching:.any)["screen-SHOP"].waitForExistence(timeout:5));XCTAssertFalse(visible("tab-0"));capture("Shop-catalog")
        tap("shop-category-image");tap("shop-item-line");XCTAssertTrue(app.descendants(matching:.any)["screen-B06"].waitForExistence(timeout:5));capture("Shop-item-detail")
        tap("pointPreview");XCTAssertTrue(app.descendants(matching:.any)["screen-B10"].waitForExistence(timeout:5));tap("뒤로")
        let balanceSnapshot=app.descendants(matching:.any)["detailPointBalance"];XCTAssertTrue(balanceSnapshot.waitForExistence(timeout:5));let beforeCancel=balanceSnapshot.value as? String
        let confirm=app.buttons.matching(identifier:"confirmPointPurchase").firstMatch
        tap("purchaseShopItem");XCTAssertTrue(confirm.waitForExistence(timeout:5))
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-B06"].exists);XCTAssertTrue(app.buttons["purchaseShopItem"].isEnabled)
        XCTAssertEqual(balanceSnapshot.value as? String,beforeCancel,"Cancel must leave the balance and ledger count unchanged")
        let dialogDismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:confirm)
        XCTAssertEqual(XCTWaiter.wait(for:[dialogDismissed],timeout:5),.completed,"Cancel should fully dismiss the purchase dialog before reopening it")
        tap("purchaseShopItem");XCTAssertTrue(waitHittable(confirm,timeout:5));confirm.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-B07"].waitForExistence(timeout:5));capture("Shop-local-purchase")
        tap("backToShop");XCTAssertTrue(app.descendants(matching:.any)["screen-B06"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["purchaseShopItem"].isEnabled);XCTAssertEqual(app.buttons["purchaseShopItem"].label,"보유 중")
        tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-SHOP"].waitForExistence(timeout:5));tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:5));tap("openPointHistory");XCTAssertTrue(app.descendants(matching:.any)["screen-B02"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["모브 라인"].exists)
        app.terminate();app.launchArguments=["-wire-screen","POINTS","-wire-fixture","-appearance","light"];app.launch();XCTAssertTrue(app.staticTexts["pointBalance"].waitForExistence(timeout:10));XCTAssertEqual(app.staticTexts["pointBalance"].label,"850","Purchase state persists only in the fixture device store")
    }
    func testPointsShopDisablesInsufficientPurchaseAndShowsEmptyLedger(){
        app.launchArguments=["-wire-screen","B06","-wire-fixture","-wire-reset","-wire-points-insufficient","-appearance","light"];app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-B06"].waitForExistence(timeout:15))
        let purchase=app.buttons["purchaseShopItem"];XCTAssertTrue(purchase.exists);XCTAssertFalse(purchase.isEnabled);tap("pointShortageHelp");XCTAssertTrue(app.descendants(matching:.any)["screen-B08"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments=["-wire-screen","B08","-wire-fixture","-wire-reset","-appearance","light"];app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-B08"].waitForExistence(timeout:15));XCTAssertTrue(app.buttons["pointShortageAmount"].label.contains("350P"),app.debugDescription)
        app.terminate();app.launchArguments=["-wire-screen","B09","-wire-fixture","-wire-reset","-appearance","light"];app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-B09"].waitForExistence(timeout:15));XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","달리기와 함께")).firstMatch.exists);XCTAssertTrue(app.staticTexts["광고 보고 받기"].exists);XCTAssertFalse(app.descendants(matching:.any)["pointAdPlaceholder"].exists)
        app.terminate();app.launchArguments=["-wire-screen","B03","-wire-fixture","-wire-reset","-wire-points-empty","-appearance","light"];app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-B03"].waitForExistence(timeout:15));XCTAssertTrue(app.staticTexts["포인트 내역이 없어요"].exists)
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
        for _ in 0..<3 where !app.buttons["editTitle"].isHittable { app.swipeDown() }
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
    func testReview52ShopArtworkUsesSourceGeometry() {
        app.launchArguments=["-wire-screen","SHOP","-wire-fixture","-wire-reset","-wire-capture-viewport","-wire-reduced","-appearance","light"]
        app.launch();XCTAssertTrue(app.buttons["shop-item-line"].waitForExistence(timeout:10))
        let listArtwork=app.descendants(matching:.any)["pointArtwork-line"].firstMatch
        XCTAssertTrue(listArtwork.waitForExistence(timeout:5))
        capture("B05-shop-source-artwork-390x790")
        XCTAssertEqual(listArtwork.label,"모브 라인 예시 아이템 미리보기")
        app.buttons["shop-item-line"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-B06"].waitForExistence(timeout:5))
        let detailArtwork=app.descendants(matching:.any)["pointProductArtwork"].firstMatch
        XCTAssertTrue(detailArtwork.waitForExistence(timeout:5))
        capture("B06-shop-detail-source-artwork-390x790")
        XCTAssertEqual(detailArtwork.label,"모브 라인 예시 아이템 미리보기")
    }

    func testProfilePhotoCropHidesPreviewAndPreservesReview52Order(){
        app.launchArguments=["-wire-screen","M02","-wire-fixture","-wire-reset","-wire-capture-viewport","-wire-photo-crop-fixture","-appearance","light"];app.launch()
        let crop=app.buttons["profilePhotoCropCircle"]
        XCTAssertTrue(crop.waitForExistence(timeout:15),app.debugDescription)
        XCTAssertEqual(crop.value as? String,"선택 영역: 가로 50%, 세로 50%")
        XCTAssertFalse(app.otherElements["profilePhotoPreview"].exists,"A pending crop hides the 80×80 photo preview")
        let stage=crop,help=app.staticTexts["profilePhotoCropHelp"],choose=app.buttons["사진 바꾸기"],remove=app.buttons["사진 삭제"]
        let fileInfo=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","JPG · PNG · WebP, 8MB 이하")).firstMatch
        XCTAssertTrue(stage.exists && help.exists && choose.exists && remove.exists && fileInfo.exists,app.debugDescription)
        XCTAssertLessThan(stage.frame.minY,help.frame.minY);XCTAssertLessThan(help.frame.minY,choose.frame.minY);XCTAssertLessThan(choose.frame.minY,remove.frame.minY);XCTAssertLessThan(remove.frame.minY,fileInfo.frame.minY)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="M02 crop app 390x790 synthetic";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testPointIconAppearanceCapture(){
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen","POINTS","-appearance",theme]
            app.launch();XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["tab-0"].isSelected);capture("PointIcon-selected-"+theme)
            tap("tab-2");XCTAssertFalse(app.buttons["tab-0"].isSelected);capture("PointIcon-unselected-"+theme);app.terminate()
        }
    }
    func testB01LaunchAliasOpensPointsTab(){
        app.launchArguments=["-wire-screen","B01","-wire-fixture","-wire-reset","-appearance","light"];app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:10));XCTAssertEqual(app.buttons["tab-0"].label,"포인트");XCTAssertTrue(app.staticTexts["pointBalance"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","포인트 안내")).count,1,"B01 follows the source with a single guide link");XCTAssertTrue(app.buttons["pointGuideOverview"].exists)
    }
}
