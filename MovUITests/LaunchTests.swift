import XCTest
import UIKit
@MainActor final class LaunchTests:XCTestCase {
    var app=XCUIApplication()
    private let isolatedStoreSuite="mov.ui.fixture.\(UUID().uuidString)"
    override func setUp(){continueAfterFailure=false}
    private func makeFixtureStoreSuite(_ prefix:String)->String {
        "\(prefix).\(UUID().uuidString)"
    }
    func open(_ screen:String="H00",reset:Bool=true){app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-appearance","light"];if reset{app.launchArguments.append("-wire-reset")};app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))}
    func openAuthFixture(_ screen:String,suite:String,userFlow:Bool=false){let isolatedSuite=makeFixtureStoreSuite(suite);app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite",isolatedSuite,"-wire-reset","-appearance","light"];if userFlow{app.launchArguments.append("-wire-user-flow")};app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))}
    func openMemberProfileFixture(_ extraArguments:[String]=[]){
        let suite=makeFixtureStoreSuite("mov.wireframe.test.member-profile")
        app.launchArguments=["-wire-screen","M01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-member-profile-fixture","-appearance","light"]+extraArguments
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["remoteProfileNickname"].waitForExistence(timeout:8),app.debugDescription)
    }
    func tap(_ label:String){let matches=app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label));let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in matches.allElementsBoundByIndex.contains(where:{$0.isHittable})},object:nil);XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed,"Visible button: "+label);matches.allElementsBoundByIndex.first(where:{$0.isHittable})?.tap()}
    private func scrollCurrentScreen(){
        let visible=app.scrollViews.allElementsBoundByIndex.first{$0.isHittable && $0.frame.minX>=0}
        visible?.swipeUp()
    }
    private func pasteText(_ value:String,into element:XCUIElement){
        UIPasteboard.general.string=value
        element.tap()
        element.press(forDuration:0.8)
        let paste=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ OR label == %@","붙여넣기","Paste")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout:5),app.debugDescription)
        paste.tap()
    }
    private func replace(_ value:String,into element:XCUIElement){if !element.exists || !element.isHittable{scrollCurrentScreen()};XCTAssertTrue(element.waitForExistence(timeout:5));element.tap();let old=element.value as? String ?? "";element.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+value)}
    func waitHittable(_ element:XCUIElement,timeout:Double=3)->Bool{let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in element.exists && element.isHittable},object:nil);return XCTWaiter.wait(for:[ready],timeout:timeout) == .completed}
    func waitForLayout(_ condition:@escaping()->Bool,timeout:Double=3)->Bool{let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in condition()},object:nil);return XCTWaiter.wait(for:[ready],timeout:timeout) == .completed}
    func capture(_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="Wire-"+name;a.lifetime = .keepAlways;add(a)}
    func testMemberProfileEditSavesPartialFieldsAndShowsServerValues(){
        openMemberProfileFixture()
        XCTAssertEqual(app.staticTexts["remoteProfileNickname"].label,"RunMate")
        tap("카드 편집")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M02"].waitForExistence(timeout:6))
        replace("RunnerNew",into:app.textFields["memberProfileEditNickname"])
        tap("memberProfileEditSave")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["remoteProfileNickname"].label,"RunnerNew")
        XCTAssertTrue(app.staticTexts["아침마다 달려요"].exists,"An omitted introduction remains on the server")
        XCTAssertTrue(app.staticTexts["모브시 북부권"].exists,"An omitted region remains on the server")
        XCTAssertFalse(app.staticTexts["63.12"].exists,"Private weight is not displayed on the profile card")
        app.launchArguments=["-wire-screen","M01","-wire-fixture","-wire-test-store-suite","mov.wireframe.test.member-profile.read-failure.\(UUID().uuidString)","-wire-reset","-wire-member-profile-fixture","-wire-member-profile-read-fail-once","-appearance","light"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["remoteProfileReadFailure"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["새벽러너"].exists,"A failed read does not replace the existing local card")
        tap("remoteProfileRetry")
        XCTAssertTrue(app.staticTexts["remoteProfileNickname"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["remoteProfileNickname"].label,"RunMate")
    }
    func testMemberProfileNicknameConflictKeepsDraftAndDoesNotChangeExistingValue(){
        openMemberProfileFixture(["-wire-member-profile-nickname-conflict"])
        tap("카드 편집")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M02"].waitForExistence(timeout:6))
        let nickname=app.textFields["memberProfileEditNickname"]
        replace("TakenName",into:nickname)
        tap("memberProfileEditSave")
        XCTAssertTrue(app.staticTexts["memberProfileEditFailure"].waitForExistence(timeout:6))
        XCTAssertEqual(nickname.value as? String,"TakenName")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M02"].exists)
        tap("memberProfileEditCancel")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].waitForExistence(timeout:6))
        XCTAssertEqual(app.staticTexts["remoteProfileNickname"].label,"RunMate")
    }
    func testMemberProfileWeightShowsServerTruncationAndRejectsOutOfRangeInput(){
        openMemberProfileFixture()
        if !app.buttons["memberProfileWeightRow"].isHittable{scrollCurrentScreen()}
        tap("memberProfileWeightRow")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T02"].waitForExistence(timeout:6))
        let weight=app.textFields["profileWeightInput"]
        XCTAssertTrue(weight.waitForExistence(timeout:5))
        replace("63.129",into:weight)
        tap("saveWeightProfile")
        XCTAssertTrue(app.descendants(matching:.any)["screen-M01"].waitForExistence(timeout:8))
        if !app.buttons["memberProfileWeightRow"].isHittable{scrollCurrentScreen()}
        tap("memberProfileWeightRow")
        XCTAssertTrue(app.descendants(matching:.any)["screen-T02"].waitForExistence(timeout:6))
        XCTAssertEqual(app.textFields["profileWeightInput"].value as? String,"63.12")
        replace("300.001",into:app.textFields["profileWeightInput"])
        tap("saveWeightProfile")
        XCTAssertTrue(app.staticTexts["memberProfileWeightFailure"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["profileWeightInput"].value as? String,"300.001","Invalid source input must remain visible and must not be truncated")
    }
    private func openRemoteRunDeleteFixture(extraArguments:[String]=[])->String {
        let suite="mov.wireframe.test.run-delete.\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-run-records-delete-fixture","-appearance","light"]+extraArguments
        if app.state != .notRunning { app.terminate() }
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        XCTAssertTrue(app.buttons["remoteRun-fixture-run-104"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"The fixture only adds a server row; the isolated local sample remains present")
        return suite
    }
    private func openRemoteDeleteConfirmation() {
        tap("remoteRun-fixture-run-104")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8))
        let delete=app.buttons["deleteRecord"]
        if !delete.isHittable { scrollCurrentScreen() }
        tap("deleteRecord")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L07"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","서버 기록과 경로 정보")).firstMatch.waitForExistence(timeout:5),app.debugDescription)
    }
    func testRemoteRunDeleteConfirmsOn204AndPreservesTheLocalSample(){
        let suite=openRemoteRunDeleteFixture()
        openRemoteDeleteConfirmation()
        tap("confirmDeleteRecord")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.buttons["remoteRun-fixture-run-104"].exists,"A confirmed 204 removes the remote row")
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"A remote delete must not touch local sample records")
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }
    func testRemoteRunDeleteLostResponseKeepsConfirmationAndAllowsManualIdempotentRetry(){
        let suite=openRemoteRunDeleteFixture(extraArguments:["-wire-run-records-delete-response-lost"])
        openRemoteDeleteConfirmation()
        tap("confirmDeleteRecord")
        XCTAssertTrue(app.staticTexts["remoteRunDeleteFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["screen-L07"].exists,"An uncertain response must not navigate away as if deletion were confirmed")
        XCTAssertTrue(app.buttons["confirmDeleteRecord"].isEnabled,app.debugDescription+"\nRetry is an explicit user action on the same record")
        tap("confirmDeleteRecord")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.buttons["remoteRun-fixture-run-104"].exists,"The idempotent retry succeeds and removes the remote row")
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists)
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }
    func testRemoteRunDelete404RemainsUnknownAndKeepsTheRecord(){
        let suite=openRemoteRunDeleteFixture(extraArguments:["-wire-run-records-delete-404"])
        openRemoteDeleteConfirmation()
        tap("confirmDeleteRecord")
        XCTAssertTrue(app.staticTexts["remoteRunDeleteFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["기록을 찾을 수 없거나 접근할 수 없어요. 삭제 여부를 확인하지 못했어요."].exists)
        XCTAssertFalse(app.buttons["confirmDeleteRecord"].exists,"An ambiguous ownership-hiding 404 is not treated as success or a retryable delete")
        tap("기록 상세 다시 확인")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8))
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["remoteRun-fixture-run-104"].exists,"The server record remains visible after an ambiguous 404")
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists)
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }
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
    func matchesRGB(in image:UIImage,rect:CGRect,expected:(Int,Int,Int),tolerance:Int=20)->Bool {
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
        let totals=pixels.withUnsafeBufferPointer{bytes in
            stride(from:0,to:bytes.count,by:4).reduce((0,0,0,0)){sum,index in (sum.0+Int(bytes[index]),sum.1+Int(bytes[index+1]),sum.2+Int(bytes[index+2]),sum.3+1)}
        }
        guard totals.3>0 else{return false}
        return abs(totals.0/totals.3-expected.0)<=tolerance && abs(totals.1/totals.3-expected.1)<=tolerance && abs(totals.2/totals.3-expected.2)<=tolerance
    }
    func containsDarkVariantFacetPixel(in image:UIImage, rect:CGRect)->Bool {
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
            stride(from:0,to:bytes.count,by:4).contains{index in
                bytes[index]>=175 && bytes[index]<=205 && bytes[index+1]>=235 && bytes[index+2]>=175 && bytes[index+2]<=215 && bytes[index+3]>200
            }
        }
    }
    func testReview55HomeGoalSelectorAndPersistentSummaries() {
        let suite="mov.wireframe.test.review55-home"
        func launchExample(_ example:String,appearance:String="light",compact:Bool=false) {
            app.terminate()
            app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",suite,
                "-wire-reset","-wire-capture-viewport","-wire-home-weekly-example",example,"-appearance",appearance]
            if compact { app.launchArguments.append("-wire-compact-review") }
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:12),"Home example: \(example)")
        }

        launchExample("below")
        XCTAssertTrue(app.staticTexts["homeWeeklyHeading"].exists)
        XCTAssertFalse(app.buttons["editGoal"].exists,"The home removes the per-run goal card")
        XCTAssertTrue(app.buttons["homeStartRun"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeRingPercent-distance"].exists,app.debugDescription)
        XCTAssertEqual(app.staticTexts["homeRingPercent-distance"].label,"60%")
        XCTAssertTrue(app.staticTexts["homeRecentMetadata"].label.contains("07:12 시작 · 75:00 유효 러닝 · 예시"))
        capture("H00-weekly-below")
        app.buttons["homeWeeklySummary"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H07"].waitForExistence(timeout:6))

        launchExample("time")
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-time"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertEqual(app.descendants(matching:.any)["homeRing-time"].value as? String,"1시간 30분 / 2시간 · 75%")
        XCTAssertEqual(app.staticTexts["homeRingTarget-time"].label,"목표 2시간")
        XCTAssertFalse(app.buttons["homeGoalSelector-distance"].exists,"Single goal keeps the direct large arc")

        launchExample("both")
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].exists)
        XCTAssertTrue(app.buttons["homeGoalSelector-time"].exists)
        XCTAssertEqual(app.descendants(matching:.any)["homeGoalSelector"].label,"크게 볼 주간 목표")
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].isSelected)
        XCTAssertEqual(app.buttons["homeGoalSelector-distance"].frame.width,76,accuracy:0.5,"Review55 selector buttons include their horizontal padding in the 76pt minimum")
        XCTAssertEqual(app.buttons["homeGoalSelector-distance"].frame.height,44,accuracy:0.5)
        XCTAssertTrue(app.descendants(matching:.any)["homeGoalSummaries"].exists)
        XCTAssertEqual(app.staticTexts["homeSummaryActual-distance"].label,"12.00 km")
        XCTAssertEqual(app.staticTexts["homeSummaryTarget-time"].label," / 2시간")
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertTrue(app.buttons["homeEditWeeklyGoal"].exists)
        XCTAssertLessThanOrEqual(app.descendants(matching:.any)["homeWeeklyRings"].frame.maxX,app.frame.width-22,"The selector and summaries stay within the 22pt content inset")
        app.buttons["homeGoalSelector-time"].tap()
        XCTAssertTrue(app.buttons["homeGoalSelector-time"].isSelected)
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-time"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeSummary-distance"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeSummary-time"].exists)
        XCTAssertEqual(app.descendants(matching:.any)["homeRing-time"].value as? String,"1시간 30분 / 2시간 · 75%")
        app.buttons["homeGoalSelector-distance"].tap()
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].isSelected)
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeAvailability-distance"].exists,"The availability line reserves its source height")
        capture("H00-review55-selector")
        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:6))

        launchExample("both-over")
        let distanceOverage=app.staticTexts["homeRingOverage-distance"]
        XCTAssertTrue(distanceOverage.exists)
        XCTAssertEqual(app.staticTexts["homeSummaryOverage-distance"].label,"3 km 더 달렸어요")
        XCTAssertEqual(app.staticTexts["homeSummaryOverage-time"].label,"30분 더 달렸어요")
        app.buttons["homeGoalSelector-time"].tap()
        let timeOverage=app.staticTexts["homeRingOverage-time"]
        XCTAssertTrue(timeOverage.exists)
        XCTAssertEqual(app.descendants(matching:.any)["homeRing-time"].value as? String,"2시간 30분 / 2시간 · 125%")
        XCTAssertEqual(timeOverage.label,"30분 더 달렸어요")
        XCTAssertEqual(app.staticTexts["homeRingTarget-time"].label,"목표 2시간")
        XCTAssertGreaterThanOrEqual(app.buttons["homeEditWeeklyGoal"].frame.minY,app.descendants(matching:.any)["homeGoalSummaries"].frame.maxY,"Goal action stays below the persistent summary rows")

        launchExample("unset")
        XCTAssertTrue(app.buttons["주간 목표 설정 하기"].exists)
        XCTAssertFalse(app.buttons["homeEditWeeklyGoal"].exists)
        XCTAssertEqual(app.descendants(matching:.any)["homeRing-distance"].label,"이번 주 달린 거리")
        XCTAssertEqual(app.descendants(matching:.any)["homeRing-distance"].value as? String,"12.00 km")
        XCTAssertFalse(app.staticTexts["homeRingPercent-distance"].exists)

        launchExample("over")
        XCTAssertEqual(app.staticTexts["homeRingPercent-distance"].label,"115%")
        XCTAssertTrue(app.staticTexts["homeRingOverage-distance"].exists)
        app.buttons["homeStartRun"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H01"].waitForExistence(timeout:6))

        launchExample("both",appearance:"dark")
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].isSelected)
        XCTAssertTrue(app.descendants(matching:.any)["homeGoalSummaries"].exists)
        capture("H00-review55-dark")

        launchExample("both",compact:true)
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].exists)
        XCTAssertTrue(app.buttons["homeGoalSelector-distance"].isHittable)
        XCTAssertTrue(app.buttons["homeGoalSelector-time"].isHittable)
        XCTAssertTrue(app.descendants(matching:.any)["homeSummary-distance"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeSummary-time"].exists)
        capture("H00-review55-compact")
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }

    func testReview55HomeGoalSelectorAccessibility3ReflowsWithoutClipping() {
        let suite=isolatedStoreSuite
        for compact in [false,true] {
            app.terminate()
            app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-reset",
                "-wire-test-store-suite",suite,"-wire-home-weekly-example","both-long-over","-wire-large","-wire-fixed-reference-week","-appearance","light"]
            if !compact { app.launchArguments.append("-wire-capture-viewport") }
            if compact { app.launchArguments.append("-wire-compact-review") }
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))

            let distance=app.buttons["homeGoalSelector-distance"]
            let time=app.buttons["homeGoalSelector-time"]
            XCTAssertTrue(distance.waitForExistence(timeout:6))
            XCTAssertTrue(distance.isHittable);XCTAssertTrue(time.isHittable)
            XCTAssertGreaterThanOrEqual(distance.frame.height,44)
            XCTAssertGreaterThanOrEqual(time.frame.height,44)
            XCTAssertLessThan(distance.frame.maxX,time.frame.minX+1,"Selector choices remain side by side without overlapping")
            XCTAssertGreaterThanOrEqual(distance.frame.minX,0)
            XCTAssertLessThanOrEqual(time.frame.maxX,app.frame.width)

            let ring=app.descendants(matching:.any)["homeRing-distance"].firstMatch
            let actual=app.staticTexts["homeSummaryActual-distance"]
            let target=app.staticTexts["homeSummaryTarget-distance"]
            let ringTarget=app.staticTexts["homeRingTarget-distance"]
            let ringPercent=app.staticTexts["homeRingPercent-distance"]
            let ringOverage=app.staticTexts["homeRingOverage-distance"]
            let summary=app.descendants(matching:.any)["homeGoalSummaries"]
            let edit=app.buttons["homeEditWeeklyGoal"]
            let scroll=app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists,"Home content remains scrollable at Accessibility3")
            func waitForStableFrame(_ element:XCUIElement,timeout:Double=1.5)->Bool {
                var previous=element.frame
                var stableReads=0
                let settled=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
                    let current=element.frame
                    if current==previous { stableReads+=1 } else { previous=current;stableReads=0 }
                    return stableReads>=2
                },object:nil)
                return XCTWaiter.wait(for:[settled],timeout:timeout) == .completed
            }
            func alignToViewport(_ element:XCUIElement) {
                for _ in 0..<16 {
                    _ = waitForStableFrame(element)
                    let viewport=scroll.frame
                    let frame=element.frame
                    let delta:CGFloat
                    let maximumDrag=max(1,viewport.height*0.18)
                    let minimumEffectiveDrag=max(1,viewport.height*0.04)
                    let viewportInset=min(8,viewport.height*0.025)
                    if frame.minY < viewport.minY+viewportInset { delta=min(maximumDrag,max(minimumEffectiveDrag,viewport.minY+viewportInset-frame.minY)) }
                    else if frame.maxY > viewport.maxY-viewportInset { delta = -min(maximumDrag,max(minimumEffectiveDrag,frame.maxY-viewport.maxY+viewportInset)) }
                    else { break }
                    let start=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
                    start.press(forDuration:0.25,thenDragTo:start.withOffset(CGVector(dx:0,dy:delta)),withVelocity:.slow,thenHoldForDuration:0.05)
                }
                _ = waitForStableFrame(element)
            }
            XCTAssertTrue(ring.exists,app.debugDescription)
            XCTAssertTrue(actual.exists);XCTAssertTrue(target.exists)
            XCTAssertEqual(actual.label,"60.00 km")
            XCTAssertEqual(target.label," / 50 km")
            XCTAssertEqual(app.staticTexts["homeSummaryActual-time"].label,"11시간")
            XCTAssertEqual(app.staticTexts["homeSummaryTarget-time"].label," / 10시간")
            XCTAssertEqual(app.staticTexts["homeSummaryPercent-time"].label,"110%")
            XCTAssertEqual(app.staticTexts["homeSummaryOverage-distance"].label,"10 km 더 달렸어요")
            XCTAssertEqual(app.staticTexts["homeSummaryOverage-time"].label,"1시간 더 달렸어요")
            XCTAssertEqual(ringTarget.label,"목표 50 km")
            XCTAssertEqual(ringPercent.label,"120%")
            XCTAssertEqual(ringOverage.label,"10 km 더 달렸어요")
            XCTAssertGreaterThan(actual.frame.height,30,"Summary values scale with Accessibility3 text")
            XCTAssertGreaterThan(target.frame.height,20,"Summary targets scale with Accessibility3 text")
            XCTAssertFalse(actual.frame.intersects(target.frame),"Actual and target values reflow vertically rather than overlap")
            XCTAssertLessThanOrEqual(actual.frame.maxX,scroll.frame.maxX+1)
            XCTAssertLessThanOrEqual(target.frame.maxX,scroll.frame.maxX+1)
            XCTAssertGreaterThan(summary.frame.height,80,"Both summary rows expand to fit large text")
            if compact {
                XCTAssertLessThanOrEqual(summary.frame.width,280,"Compact review uses the 320-point viewport with 22-point side gutters")
                XCTAssertEqual(app.scrollViews.firstMatch.frame.width,320,accuracy:1,"Compact accessibility fixture uses an actual 320pt scroll viewport")
            }
            let weeklyRings=app.descendants(matching:.any)["homeWeeklyRings"]
            for element in [ringTarget,ringPercent,ringOverage] {
                XCTAssertGreaterThanOrEqual(element.frame.minX,weeklyRings.frame.minX-1)
                XCTAssertLessThanOrEqual(element.frame.maxX,weeklyRings.frame.maxX+1,"Ring footer text stays inside the weekly goal layout")
            }
            func assertFooterScales(target:XCUIElement,percent:XCUIElement,overage:XCUIElement) {
                XCTAssertGreaterThan(target.frame.height,20,"Ring goal caption scales with Accessibility3 text")
                XCTAssertGreaterThan(percent.frame.height,20,"Ring percentage scales with Accessibility3 text")
                XCTAssertFalse(target.frame.intersects(percent.frame),"Ring goal and percentage captions do not overlap")
                XCTAssertGreaterThan(overage.frame.height,20,"Ring overage caption scales with Accessibility3 text")
                XCTAssertGreaterThanOrEqual(overage.frame.minY,percent.frame.maxY,"Ring overage stays below the goal and percentage caption")
                for element in [target,percent,overage] {
                    XCTAssertGreaterThanOrEqual(element.frame.minX,weeklyRings.frame.minX-1)
                    XCTAssertLessThanOrEqual(element.frame.maxX,weeklyRings.frame.maxX+1,"Ring footer text stays inside the weekly goal layout")
                }
            }
            assertFooterScales(target:ringTarget,percent:ringPercent,overage:ringOverage)
            if compact {
                XCTAssertEqual(scroll.frame.width,320,accuracy:1,"Compact accessibility fixture uses an actual 320pt scroll viewport")
                for element in [ringTarget,ringPercent,ringOverage] {
                    XCTAssertGreaterThanOrEqual(element.frame.minX,scroll.frame.minX-1,"Compact ring text stays inside the 320pt viewport")
                    XCTAssertLessThanOrEqual(element.frame.maxX,scroll.frame.maxX+1,"Compact ring text does not clip at the 320pt viewport edge")
                }
            }
            XCTAssertGreaterThanOrEqual(edit.frame.minY,summary.frame.maxY,"Weekly goal action remains below both summary rows")
            capture(compact ? "H00-review55-accessibility3-compact-top" : "H00-review55-accessibility3-top")
            for _ in 0..<12 {
                let above=ringTarget.frame.minY < scroll.frame.minY
                let below=ringOverage.frame.maxY > scroll.frame.maxY
                if above && below { break }
                if !above && !below { break }
                let start=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
                start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:below ? -60:60)))
            }
            XCTAssertLessThanOrEqual(ringOverage.frame.maxY-ringTarget.frame.minY,scroll.frame.height,"The scaled ring captions can fit inside the compact scroll viewport")
            for element in [ringTarget,ringPercent,ringOverage] {
                XCTAssertGreaterThanOrEqual(element.frame.minY,scroll.frame.minY-1,"Ring footer does not clip above the visible scroll viewport")
                XCTAssertLessThanOrEqual(element.frame.maxY,scroll.frame.maxY+1,"Ring footer does not clip below the visible scroll viewport")
            }
            capture(compact ? "H00-review55-accessibility3-compact-footer" : "H00-review55-accessibility3-footer")
            if compact {
                XCTAssertEqual(scroll.frame.width,320,accuracy:1)
            }
            for _ in 0..<8 where !time.isHittable { scroll.swipeDown() }
            time.tap()
            let timeRingTarget=app.staticTexts["homeRingTarget-time"]
            let timeRingPercent=app.staticTexts["homeRingPercent-time"]
            let timeRingOverage=app.staticTexts["homeRingOverage-time"]
            XCTAssertEqual(timeRingTarget.label,"목표 10시간")
            XCTAssertEqual(timeRingPercent.label,"110%")
            XCTAssertEqual(timeRingOverage.label,"1시간 더 달렸어요")
            assertFooterScales(target:timeRingTarget,percent:timeRingPercent,overage:timeRingOverage)
            capture(compact ? "H00-review55-accessibility3-compact-time-overage" : "H00-review55-accessibility3-time-overage")
            let distanceSummary=app.descendants(matching:.any)["homeSummary-distance"]
            let timeSummary=app.descendants(matching:.any)["homeSummary-time"]
            let homeTab=app.buttons["tab-2"]
            alignToViewport(summary)
            capture(compact ? "H00-review55-accessibility3-compact-long-summary" : "H00-review55-accessibility3-long-summary")
            XCTAssertLessThanOrEqual(summary.frame.height,scroll.frame.height)
            XCTAssertGreaterThanOrEqual(summary.frame.minY,scroll.frame.minY-1)
            XCTAssertLessThanOrEqual(summary.frame.maxY,scroll.frame.maxY+1)
            XCTAssertTrue(actual.isHittable);XCTAssertTrue(target.isHittable)
            XCTAssertTrue(distanceSummary.isHittable);XCTAssertTrue(timeSummary.isHittable)
            XCTAssertLessThanOrEqual(actual.frame.maxY,homeTab.frame.minY+1)
            XCTAssertLessThanOrEqual(target.frame.maxY,homeTab.frame.minY+1)
            XCTAssertLessThanOrEqual(timeSummary.frame.maxY,homeTab.frame.minY+1)
            capture(compact ? "H00-review55-accessibility3-compact-summary" : "H00-review55-accessibility3-summary")
            alignToViewport(edit)
            XCTAssertTrue(edit.isHittable,"The goal action remains reachable after scrolling the expanded home layout")
            if compact {
                alignToViewport(time)
                time.tap()
                XCTAssertTrue(time.isSelected)
                app.buttons["tab-1"].tap()
                XCTAssertTrue(app.descendants(matching:.any)["screen-H01"].waitForExistence(timeout:8))
                app.buttons["tab-2"].tap()
                XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8))
                XCTAssertTrue(time.isSelected,"The chosen time goal remains selected after visiting another tab and returning to H00")
            }
            app.terminate()
        }
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
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

    func testRunPointRewardContractAcrossCompletionListAndDetail() {
        let scenarios:[(String?,String)] = [
            ("pending","러닝 포인트 적립 확인 중"),
            ("settled-zero","러닝 포인트 0 포인트 적립"),
            ("settled-positive","러닝 포인트 15 포인트 적립"),
            ("unavailable","러닝 포인트 적립 상태 확인 불가"),
            (nil,"")
        ]
        for (scenario,label) in scenarios {
            let suite="run-point-reward-\(UUID().uuidString)"
            app.launchArguments=["-wire-screen","S01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-appearance","light"]
            if let scenario {app.launchArguments += ["-wire-run-point-reward",scenario]}
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-S01"].waitForExistence(timeout:10),app.debugDescription)
            let completionValue=app.descendants(matching:.any)["runPointReward-completionValue"]
            if label.isEmpty {
                XCTAssertFalse(completionValue.exists,"A missing pointReward does not invent a server state")
            } else {
                XCTAssertTrue(completionValue.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertEqual(completionValue.label,label)
            }

            tap("기록 보기")
            XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:5),app.debugDescription)
            let detailValue=app.descendants(matching:.any)["runPointReward-detailValue"]
            if label.isEmpty {XCTAssertFalse(detailValue.exists)} else {XCTAssertTrue(detailValue.waitForExistence(timeout:5));XCTAssertEqual(detailValue.label,label)}

            app.terminate()
            app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-appearance","light"]
            if let scenario {app.launchArguments += ["-wire-run-point-reward",scenario]}
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:5),app.debugDescription)
            let listValue=app.descendants(matching:.any)["runPointReward-list"]
            if label.isEmpty {
                XCTAssertFalse(listValue.exists,"Local example runs remain unchanged and have no backend reward object")
                XCTAssertTrue(app.descendants(matching:.any)["recordPointExample"].exists,"The existing review-only sample marker remains intact")
            } else {
                XCTAssertTrue(listValue.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertEqual(listValue.label,label)
            }
            app.terminate()
        }
    }

    func testInjectedRunRecordReadRendersContractAndKeepsLocalHistoryOnFailure() {
        let suite="run-read-fixture-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-run-records-fixture","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        let remotePanel=app.descendants(matching:.any)["remoteRunRecordsPanel"]
        XCTAssertTrue(remotePanel.waitForExistence(timeout:10),app.debugDescription)
        let remoteRow=app.buttons["remoteRun-fixture-run-104"]
        XCTAssertTrue(remoteRow.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertEqual(app.staticTexts["remoteRunDistances-fixture-run-104"].label,"원본 6.4 km · 유효 6.1 km")
        XCTAssertEqual(app.descendants(matching:.any)["remoteRunReward-fixture-run-104"].label,"러닝 포인트 0 포인트 적립")
        XCTAssertTrue(app.staticTexts["기기에 저장된 기록"].exists,"Remote rows stay separate from the local record collection")
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"The local sample record must remain present")

        remoteRow.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["remoteRunSummaryMetrics"].exists,app.debugDescription)
        XCTAssertEqual(app.descendants(matching:.any)["remoteRunReward-detailValue"].label,"러닝 포인트 0 포인트 적립")
        XCTAssertTrue(app.staticTexts["경로 점"].exists)
        app.terminate()

        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-run-records-fixture","-wire-run-records-fail","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["remoteRunsReadFailure"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"A server failure must not erase the local history or become an empty list")
        XCTAssertFalse(app.descendants(matching:.any)["recordLookupFailure"].exists)
        app.terminate()
    }

    func testRemoteDeletionOnAnotherDeviceReconcilesWhenReturningToList() {
        let suite="run-list-reconcile-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-run-records-fixture","-wire-run-records-remote-delete-on-refresh","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        let remoteRow=app.buttons["remoteRun-fixture-run-104"]
        XCTAssertTrue(remoteRow.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"The fixture's local sample is independent of the remote list")

        remoteRow.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8),app.debugDescription)
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:8),app.debugDescription)
        let remoteRowRemoved=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:remoteRow)
        wait(for:[remoteRowRemoved],timeout:10)
        XCTAssertTrue(app.staticTexts["기기에 저장된 기록"].exists)
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"A remote list refresh must preserve local sample data")
        XCTAssertFalse(app.descendants(matching:.any)["recordLookupFailure"].exists,"An empty remote result is a successful list, not a local-history failure")
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }

    func testInjectedRunRecordEditKeepsInlineFlowAndReappliesDraftAfterConflict() {
        let suite="run-edit-fixture-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-run-records-fixture","-wire-run-records-edit-fixture","-wire-run-records-write-conflict","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        let row=app.buttons["remoteRun-fixture-run-104"]
        XCTAssertTrue(row.waitForExistence(timeout:8),app.debugDescription)
        row.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8),app.debugDescription)

        tap("editTitle")
        let title=app.textFields["inlineTitleInput"]
        replaceInput(title,"초안 제목")
        tap("finishTitle")
        XCTAssertTrue(app.descendants(matching:.any)["inlineTitleSaveFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(title.value as? String,"초안 제목","A version conflict keeps the inline draft in place")
        tap("finishTitle")
        XCTAssertEqual(app.staticTexts["recordTitle"].label,"초안 제목")
        XCTAssertTrue(app.staticTexts["원본 거리"].exists,"Editing a title leaves the measured run fields visible")

        app.swipeUp()
        tap("editMemo")
        let memo=app.descendants(matching:.any)["inlineMemoInput"].firstMatch
        replaceInput(memo,"새 메모")
        tap("finishMemo")
        XCTAssertEqual(app.staticTexts["recordMemo"].label,"새 메모")
        app.terminate()
    }

    func testInjectedRunRecordEditFailurePreservesDraft() {
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite","run-edit-failure-\(UUID().uuidString)","-wire-reset","-wire-run-records-fixture","-wire-run-records-edit-fixture","-wire-run-records-write-fail","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        app.buttons["remoteRun-fixture-run-104"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8),app.debugDescription)
        tap("editTitle")
        let title=app.textFields["inlineTitleInput"]
        replaceInput(title,"실패 뒤에도 남을 초안")
        tap("finishTitle")
        XCTAssertTrue(app.descendants(matching:.any)["inlineTitleSaveFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(title.value as? String,"실패 뒤에도 남을 초안")
        XCTAssertTrue(app.buttons["finishTitle"].isEnabled,"The user can correct or retry without retyping the draft")
        app.terminate()
    }

    func testRunRecordEdit404PreservesDraftUntilListReturnAndThenRefreshes() {
        let suite="run-edit-missing-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","L01","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-wire-run-records-fixture","-wire-run-records-edit-fixture","-wire-run-records-write-404","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:15),app.debugDescription)
        let row=app.buttons["remoteRun-fixture-run-104"]
        XCTAssertTrue(row.waitForExistence(timeout:8),app.debugDescription)
        row.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:8),app.debugDescription)

        tap("editTitle")
        let title=app.textFields["inlineTitleInput"]
        replaceInput(title,"404 뒤 보존할 초안")
        tap("finishTitle")
        XCTAssertTrue(app.descendants(matching:.any)["inlineTitleSaveFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(title.value as? String,"404 뒤 보존할 초안")

        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L01"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["서버에 러닝 기록이 없어요."].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["가볍게 달린 아침"].exists,"Refreshing the server list leaves local history untouched")
        app.terminate()
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
        for i in [0,1,2,3,4,3,2,1,0,2]{
            if app.buttons["community-tab-home"].exists {
                if i == 2 { app.buttons["community-tab-home"].tap(); continue }
                if i == 4 { app.buttons["community-tab-home"].tap() }
            }
            app.buttons["tab-\(i)"].tap()
        }
        for i in 0...4{XCTAssertEqual(app.buttons["tab-\(i)"].frame,frames[i])}
        capture("H00")
        tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","화면 테마")).firstMatch.tap()
        app.buttons["theme-dark"].tap();capture("T18-dark")
        app.terminate();app.launchArguments=["-wire-screen","T18","-wire-fixture"];app.launch();XCTAssertTrue(app.buttons["theme-dark"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-dark"].isSelected)
        app.buttons["theme-system"].tap();app.terminate();app.launch();XCTAssertTrue(app.buttons["theme-system"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["theme-system"].isSelected)
        app.buttons["theme-light"].tap()
    }
    func testHomeTabAlignmentAtAccessibilityTextSize(){
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-wire-reset","-wire-large"]
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
        app.buttons["fillDemoEmailCode"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        app.buttons["모두 동의하고 계속"].doubleTap();XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5));let nickname=app.textFields.firstMatch;nickname.tap();nickname.typeText("아침러너");app.buttons["계속"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A15"].exists);capture("A15")
        let signupCompletion=app.buttons["signupCompletionStart"]
        XCTAssertTrue(signupCompletion.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertEqual(signupCompletion.label,"시작하기","The accessibility ID stays stable while the approved CTA copy remains visible")
        signupCompletion.tap();tap("tab-4");tap("설정");app.buttons.matching(NSPredicate(format:"label CONTAINS %@","로그인 수단")).firstMatch.tap();capture("T05")
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
        app.terminate();app.launchArguments=["-wire-screen","M01","-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-appearance","light"];app.launch()
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

    func testPaceChartTouchSelectsTheSegmentUnderItsVisiblePosition() {
        app.launchArguments=["-wire-screen","L05","-wire-fixture","-wire-reset","-wire-capture-viewport","-wire-reduced","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L05"].waitForExistence(timeout:15),app.debugDescription)
        let chart=app.descendants(matching:.any)["구간 평균 페이스 그래프"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue((chart.value as? String ?? "").contains("0–1 km"),String(describing:chart.value))
        capture("L05-valid-chart-touch")
        chart.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.55)).tap()
        XCTAssertTrue((chart.value as? String ?? "").contains("4–4.82 km"),"A touch on the visible chart's right edge should select its last split; value=\(String(describing:chart.value)) frame=\(chart.frame)")
    }

    func testInvalidRunSplitViewOmitsAverageAndExplainsRecordedGap() {
        app.launchArguments=["-wire-screen","S05","-wire-fixture","-wire-reset","-wire-test-store-suite","mov.records.splits.invalid.\(UUID().uuidString)","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:10))
        tap("기록 보기")
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:5))
        XCTAssertTrue(waitHittable(app.buttons["editTitle"],timeout:8),app.debugDescription)
        let splitButtons=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","구간 기록"))
        for _ in 0..<3 where !splitButtons.allElementsBoundByIndex.contains(where:{$0.isHittable}) { app.swipeUp() }
        XCTAssertTrue(waitForLayout({splitButtons.allElementsBoundByIndex.contains(where:{$0.isHittable})},timeout:5),app.debugDescription)
        splitButtons.allElementsBoundByIndex.first(where:{$0.isHittable})?.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L05"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["아직 표시할 페이스가 없어요"].exists)
        XCTAssertTrue(app.staticTexts["유효한 거리와 시간이 있는 기록부터 표시해요."].exists)
        XCTAssertEqual(app.staticTexts["splitAverageLabel"].label,"0:00 /km")
        XCTAssertFalse(app.staticTexts["유효 평균은 확인할 수 있어요. 임의의 구간이나 변화 선은 만들지 않아요."].exists)
        XCTAssertTrue(app.staticTexts["GPS 누락"].exists)
        XCTAssertTrue(app.staticTexts["신호가 누락된 구간은 제외하고 거리를 추정하지 않았어요"].exists)
        capture("L05-invalid-gap-copy")
    }

    func testLegacyInvalidRunUsesZeroPlaceholderInSplitAverageAndRow() {
        app.launchArguments=["-wire-screen","L04","-wire-fixture","-wire-reset","-wire-legacy-invalid-run","-wire-test-store-suite","mov.records.splits.legacy.\(UUID().uuidString)","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L04"].waitForExistence(timeout:10))
        XCTAssertTrue(waitHittable(app.buttons["editTitle"],timeout:8),app.debugDescription)
        let splitButtons=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","구간 기록"))
        for _ in 0..<3 where !splitButtons.allElementsBoundByIndex.contains(where:{$0.isHittable}) { app.swipeUp() }
        XCTAssertTrue(waitForLayout({splitButtons.allElementsBoundByIndex.contains(where:{$0.isHittable})},timeout:5),app.debugDescription)
        splitButtons.allElementsBoundByIndex.first(where:{$0.isHittable})?.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L05"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["splitAverageLabel"].label,"0:00 /km")
        XCTAssertTrue(app.staticTexts["유효 기록 없음"].exists)
        XCTAssertTrue(app.staticTexts["0:00"].exists,"Legacy records with no distance, time, or segments use the same zero placeholder as the header")
    }

    func launchCommunity(_ screen:String,appearance:String="light",compact:Bool=false,anonymousPost:Bool=false,emptyHot:Bool=false,verificationStatus:String?=nil,twoCourseRecords:Bool=false,viewerID:String?=nil,crewID:String?=nil,crewBoardID:String?=nil,photoDraftFixture:Bool=false,photoPostFixture:Bool=false,videoPostFixture:Bool=false,videoDraftFixture:Bool=false) {
        app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite","community-\(UUID().uuidString)","-wire-reset","-appearance",appearance]
        if compact{app.launchArguments.append("-wire-compact-review")}
        if anonymousPost{app.launchArguments.append("-wire-community-anonymous-post")}
        if emptyHot{app.launchArguments.append("-wire-community-empty-hot")}
        if let verificationStatus{app.launchArguments += ["-wire-community-verification-status",verificationStatus]}
        if twoCourseRecords{app.launchArguments.append("-wire-community-course-two-records")}
        if let viewerID{app.launchArguments += ["-wire-community-viewer",viewerID]}
        if let crewID{app.launchArguments += ["-wire-community-crew",crewID]}
        if let crewBoardID{app.launchArguments += ["-wire-community-board",crewBoardID]}
        if photoDraftFixture{app.launchArguments.append("-wire-community-photo-draft-fixture")}
        if photoPostFixture{app.launchArguments.append("-wire-community-photo-post-fixture")}
        if videoPostFixture{app.launchArguments.append("-wire-community-video-post-fixture")}
        if videoDraftFixture{app.launchArguments.append("-wire-community-video-draft-fixture")}
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:10))
    }

    private func openCommunitySettingsFromProfile() {
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),app.debugDescription)
        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5),app.debugDescription)
        app.buttons["communityOwnProfileSettings"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C28"].waitForExistence(timeout:5),app.debugDescription)
    }

    func launchCommunityNotifications(screen:String="C01",scenario:String){
        app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite","community-notifications-\(UUID().uuidString)","-wire-reset","-appearance","light",scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:10))
    }

    func testCommunityNotificationProfileEntryRoutesAndBackContext(){
        launchCommunityNotifications(scenario:"-wire-community-notification-samples")
        XCTAssertTrue(app.buttons["communitySearch"].exists,"C01 keeps its search action")
        XCTAssertFalse(app.buttons["communityNotificationBell"].exists,"C01 does not gain a notification bell")
        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        let bell=app.buttons["communityNotificationBell"]
        XCTAssertTrue(bell.waitForExistence(timeout:5));XCTAssertEqual(bell.value as? String,"읽지 않음")
        bell.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityNotification-sample-verification"].exists)

        app.buttons["communityNotification-sample-verification"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C11"].waitForExistence(timeout:5))
        let verificationBackButtons=app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@","뒤로","뒤로"))
        XCTAssertTrue(waitForLayout({verificationBackButtons.count == 1},timeout:3),"After the route transition settles, only the active screen exposes a back button. Accessibility hierarchy: \(app.debugDescription)")
        XCTAssertEqual(verificationBackButtons.count,1,"Only the active notification route exposes a back button")
        capture("C11-notification-profile-entry")
        verificationBackButtons.element.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        XCTAssertEqual(app.buttons["communityNotification-sample-verification"].value as? String,"읽음")
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)

        app.buttons["communityNotificationBell"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        app.buttons["communityNotification-sample-application"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C18"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)

        app.buttons["communityNotificationBell"].tap()
        app.buttons["communityNotification-sample-crew-board"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)

        app.buttons["communityNotificationBell"].tap()
        app.buttons["communityNotification-sample-post"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"오늘은 강변을 따라 5 km")
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)

        app.buttons["communityNotificationBell"].tap()
        app.buttons["communityNotification-sample-feed"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        app.buttons["communityNotificationBackFromFeed"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].waitForExistence(timeout:5),"Opening the feed from a notification keeps the C24 return context")
        app.buttons["뒤로"].tap();XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)
    }

    func testCommunityNotificationEmptyStateAndProfileBadge(){
        launchCommunityNotifications(scenario:"-wire-empty-community-notifications")
        app.buttons["community-tab-profile"].tap()
        let bell=app.buttons["communityNotificationBell"]
        XCTAssertTrue(bell.waitForExistence(timeout:5));XCTAssertEqual(bell.value as? String,"읽음")
        bell.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityNotificationEmptyState"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)
    }

    func testCommunityNotificationDeletedTargetStaysOnListAndMarksRead(){
        launchCommunityNotifications(screen:"C24",scenario:"-wire-community-notification-missing-target")
        let row=app.buttons["communityNotification-missing-post"]
        XCTAssertTrue(row.waitForExistence(timeout:5));XCTAssertEqual(row.value as? String,"읽지 않음")
        row.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists)
        XCTAssertTrue(app.staticTexts["communityNotificationError"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["communityNotification-missing-post"].value as? String,"읽음")
    }

    func testCommunityCrewBrowseApplyAndCancelStaysLocal() {
        launchCommunity("C01")
        app.buttons["community-tab-crew"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityCrewTab-my"].exists)
        XCTAssertTrue(app.staticTexts["크루와 신청 상태는 화면 확인용 로컬 예시예요. 실제 가입 신청은 전송되지 않아요."].exists)
        app.buttons["communityCrewTab-find"].tap()
        app.buttons["communityCrewFilter-모두"].tap()
        app.buttons["communityCrewOpen-river"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewMemberCount"].label,"모브시 강변 · 멤버 2/20명")
        app.buttons["communityCrewJoin"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C17"].waitForExistence(timeout:5))
        let memo=app.textViews["communityCrewJoinMemo"]
        XCTAssertTrue(memo.waitForExistence(timeout:5),app.debugDescription)
        memo.tap();memo.typeText("주말 아침에 천천히 함께 달리고 싶어요.")
        app.buttons["communityCrewSubmitApplication"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C18"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityCrewApplicationHeading"].label.contains("가입 승인을 기다리고 있어요"))
        XCTAssertTrue(app.otherElements["communityCrewLocalNotice"].exists || app.descendants(matching:.any)["communityCrewLocalNotice"].exists)
        app.buttons["communityCrewCancelPending"].tap()
        XCTAssertTrue(app.staticTexts["communityCrewApplicationHeading"].label.contains("가입 신청을 취소했어요"))
        app.buttons["communityCrewReturnToDetail"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityCrewJoin"].exists,"Cancelled local requests can be started again")
        app.buttons["communityCrewJoin"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C17"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5),"Back preserves navigation and does not submit a request")
    }

    func testCommunityCrewInformationUsesCurrentLocalPolicyAndRoutesFromDetailAndBoard() {
        launchCommunity("C01")
        app.buttons["community-tab-crew"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        app.buttons["communityCrewOpen-dawn"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        app.buttons["communityCrewInformation"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C32"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewInfoName"].label,"모브 새벽 크루")
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewInfoRegion"].label.contains("모브시 중앙"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewInfoLevel"].label.contains("운영 기준 미정"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewInfoMembers"].label.contains("1/20명"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewInfoOwner"].label.contains("크루장"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewInfoBoards"].label.contains("4/5개"))
        XCTAssertTrue(app.staticTexts["communityCrewInfoGuidance"].label.contains("처음 오신 분도 편하게 인사해 주세요."))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        app.buttons["communityCrewEnterBoard"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5))
        app.buttons["communityCrewInformationFromBoard"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C32"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewInfoName"].label,"모브 새벽 크루")
    }

    func testCommunityCrewApplicationListOpensStatusAndConfirmsLocalCancellation() {
        launchCommunity("C16")
        app.buttons["communityCrewJoin"].tap()
        let memo=app.textViews["communityCrewJoinMemo"]
        XCTAssertTrue(memo.waitForExistence(timeout:5))
        memo.tap();memo.typeText("주말에 함께 달리고 싶어요.")
        app.buttons["communityCrewSubmitApplication"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C18"].waitForExistence(timeout:5))
        app.buttons["communityCrewReturnToFeed"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        app.buttons["community-tab-crew"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["communityCrewPending"].label,"신청중 1")
        app.buttons["communityCrewPending"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C33"].waitForExistence(timeout:5))
        let openRequest=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityCrewApplicationOpen-")).firstMatch
        XCTAssertTrue(openRequest.waitForExistence(timeout:5))
        openRequest.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C18"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewApplicationName"].label,"모브 강변 크루")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C33"].waitForExistence(timeout:5))
        let cancelRequest=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityCrewApplicationCancel-")).firstMatch
        XCTAssertTrue(cancelRequest.waitForExistence(timeout:5))
        cancelRequest.tap()
        XCTAssertTrue(app.alerts["가입 신청을 취소할까요?"].waitForExistence(timeout:3))
        app.alerts.buttons["유지"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityCrewApplicationCancel-")).firstMatch.exists,"Dismissing confirmation keeps the pending application")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityCrewApplicationCancel-")).firstMatch.tap()
        app.alerts.buttons.matching(identifier:"communityCrewApplicationCancelConfirm").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["communityCrewApplicationsEmpty"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["communityCrewPending"].label,"신청중 0")
    }

    func testCommunityCrewMemberBoardShowsOnlyLocalExamplePosts() {
        launchCommunity("C01")
        app.buttons["community-tab-crew"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        app.buttons["communityCrewOpen-dawn"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        app.buttons["communityCrewEnterBoard"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityCrewBoardLocalNotice"].exists || app.descendants(matching:.any)["communityCrewBoardLocalNotice"].exists)
        XCTAssertTrue(app.staticTexts["이번 주 러닝 안내"].exists)
        app.buttons["communityCrewBoardTab-dawn-board-1"].tap()
        XCTAssertTrue(app.staticTexts["다음 모임은 천천히 한 바퀴"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["이번 주 러닝 안내"].exists,"Changing board tabs filters the local example posts")
        app.buttons["communityCrewComposePost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityComposeCrewBoard"].label.contains("러닝 일정"))
        let title=app.textFields["communityComposeTitle"]
        title.tap();title.typeText("이번 주 일정 예시")
        let body=app.textViews["communityComposeBody"]
        body.tap();body.typeText("토요일 아침에 천천히 한 바퀴 달려요.")
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityPreviewTitle"].label,"이번 주 일정 예시")
        app.buttons["communityPublishButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["이번 주 일정 예시"].exists,"Publishing adds a local example to the selected crew board")
        let createdPost=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","communityCrewPost-","이번 주 일정 예시")).firstMatch
        XCTAssertTrue(createdPost.waitForExistence(timeout:5),"The new C19 row is backed by the shared post store")
        createdPost.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"이번 주 일정 예시")
        XCTAssertTrue(app.descendants(matching:.any)["communityDetailCrewContext"].label.contains("모브 새벽 크루"))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5),"Detail back returns to the selected crew board")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","communityCrewPost-","이번 주 일정 예시")).firstMatch.exists)
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
    }

    func testCrewPostCanBeEditedFromC19AndReturnsToSameBoard() {
        launchCommunity("C19",viewerID:"fixture-member-ga-on",crewID:"dawn",crewBoardID:"dawn-board-1")
        let row=app.buttons["communityCrewPost-dawn-run-1"]
        XCTAssertTrue(row.waitForExistence(timeout:5))
        row.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"다음 모임은 천천히 한 바퀴")
        XCTAssertTrue(app.descendants(matching:.any)["communityDetailCrewContext"].label.contains("모브 새벽 크루"))
        app.buttons["communityPostMore"].tap()
        XCTAssertTrue(app.buttons["communityMenuEditPost"].exists,"The author can edit the post in C04")
        app.buttons["communityMenuEditPost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        replace("수정된 새벽 모임",into:app.textFields["communityComposeTitle"])
        replace("한 주 뒤에도 같은 게시물 ID로 보여요.",into:app.textViews["communityComposeBody"])
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        app.buttons["communityEditPostSave"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"수정된 새벽 모임")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityCrewPost-dawn-run-1"].label.contains("수정된 새벽 모임"))
        XCTAssertEqual(app.buttons.matching(identifier:"communityCrewPost-dawn-run-1").count,1,"Editing updates the shared post instead of duplicating it")
    }

    func testCrewPostDeleteFromC19ReturnsToItsBoardAndRemovesTheSameID() {
        launchCommunity("C19",viewerID:"fixture-member-current",crewID:"dawn",crewBoardID:"dawn-board-1")
        XCTAssertTrue(app.buttons["communityCrewPost-dawn-run-1"].waitForExistence(timeout:5))
        app.buttons["communityCrewPost-dawn-run-1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        XCTAssertFalse(app.buttons["communityMenuEditPost"].exists,"The crew owner cannot edit another member's post")
        app.buttons["communityMenuDeletePost"].tap()
        app.buttons["communityPostDeleteConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C19"].waitForExistence(timeout:5),"Deleting a detail returns to the originating crew board")
        XCTAssertFalse(app.buttons["communityCrewPost-dawn-run-1"].exists,"The same shared post ID is removed from the crew board")
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewBoardEmpty"].exists)
    }

    func testCommunityCrewBoardHidesPostsFromNonMembers() {
        launchCommunity("C19")
        XCTAssertTrue(app.staticTexts["크루 회원에게만 공개돼요"].exists)
        XCTAssertTrue(app.buttons["communityCrewBoardDetail"].exists)
        XCTAssertFalse(app.staticTexts["오늘도 함께 완료"].exists,"A non-member never sees a crew's private posts")
    }

    func testCommunityCrewCreateAndEditEntryStaysLocal() {
        launchCommunity("C15")
        app.buttons["communityCrewCreate"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C20"].waitForExistence(timeout:5))
        let name=app.textFields["communityCrewDraftName"]
        name.tap();name.typeText("모브 저녁 크루")
        app.buttons["communityCrewCheckName"].tap()
        XCTAssertEqual(app.staticTexts["communityCrewNameCheckResult"].label,"사용할 수 있는 크루 이름이에요.")
        let introduction=app.textViews["communityCrewDraftIntroduction"]
        introduction.tap();introduction.typeText("하루를 마치고 함께 천천히 달려요.")
        XCTAssertTrue(app.buttons["communityCrewPhotoPicker"].exists)
        XCTAssertTrue(app.staticTexts["communityCrewDraftLocalNotice"].exists || app.descendants(matching:.any)["communityCrewDraftLocalNotice"].exists)
        app.buttons["communityCrewSave"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewManagementName"].label,"모브 저녁 크루")
        XCTAssertTrue(app.buttons["communityCrewEdit"].exists)
        app.buttons["communityCrewEdit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C20"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["communityCrewDraftName"].value as? String,"모브 저녁 크루")
        app.buttons["communityCrewCancelEdit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
    }

    func testCommunityCrewManagerReviewsPendingApplicationsLocally() {
        launchCommunity("C15")
        app.buttons["communityCrewOpen-dawn"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        app.buttons["communityCrewManage"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
        app.buttons["communityCrewPendingApplications"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C40"].waitForExistence(timeout:5))
        app.buttons["communityCrewPendingRequest-fixture-request-dawn-early"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C22"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewApplicantName"].label,"새벽러너")
        XCTAssertEqual(app.staticTexts["communityCrewReviewMemo"].label,"주 1회 함께 달리고 싶어요.")
        XCTAssertTrue(app.staticTexts["communityCrewReviewLocalNotice"].exists || app.descendants(matching:.any)["communityCrewReviewLocalNotice"].exists)
        app.buttons["communityCrewApproveApplication"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C40"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewPendingApplicationCount"].label,"대기 중인 신청 1건")
        app.buttons["communityCrewPendingRequest-fixture-request-dawn-ga-on"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C22"].waitForExistence(timeout:5))
        app.buttons["communityCrewRejectApplication"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C40"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityCrewPendingApplicationsEmpty"].exists,"Resolved requests leave the pending list")
    }

    func testCommunityCrewGuidanceBoardsAndAnnouncementsUseLocalFlows() {
        launchCommunity("C15")
        app.buttons["communityCrewOpen-dawn"].tap()
        app.buttons["communityCrewManage"].tap()

        app.buttons["communityCrewGuidance"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C36"].waitForExistence(timeout:5))
        replaceInput(app.textViews["communityCrewGuidanceText"],"처음 오신 분은 게시판 일정을 먼저 확인해 주세요.")
        app.buttons["communityCrewGuidanceSave"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.staticTexts["communityCrewGuidanceDetails"].label.contains("처음 오신 분은 게시판 일정을 먼저 확인해 주세요."))
        app.buttons["communityCrewManage"].tap()

        app.buttons["communityCrewBoards"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C37"].waitForExistence(timeout:5))
        let boardCount=app.staticTexts["communityCrewBoardCount"]
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 4/5개")
        app.buttons["communityCrewBoardEdit-dawn-board-1"].tap()
        replaceInput(app.textFields["communityCrewBoardName"],"새벽 모임")
        app.buttons["communityCrewBoardSave"].tap()
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 4/5개")
        app.buttons["communityCrewBoardEdit-dawn-board-1"].tap()
        app.buttons["communityCrewBoardArchive"].tap()
        XCTAssertTrue(app.alerts["게시판을 보관할까요?"].waitForExistence(timeout:3))
        app.alerts.buttons.matching(identifier:"communityCrewBoardArchiveConfirm").firstMatch.tap()
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 3/5개")

        app.buttons["communityCrewBoardAdd"].tap()
        replaceInput(app.textFields["communityCrewBoardName"],"이른 러닝")
        app.buttons["communityCrewBoardSave"].tap()
        app.buttons["communityCrewBoardAdd"].tap()
        replaceInput(app.textFields["communityCrewBoardName"],"주말 러닝")
        app.buttons["communityCrewBoardSave"].tap()
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 5/5개")
        app.buttons["communityCrewBoardRestore-dawn-board-1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewManageError"].label.contains("최대 5개"))
        XCTAssertEqual(boardCount.label,"활성 게시판 5/5개")
        app.buttons["communityCrewBoardEdit-dawn-board-2"].tap()
        app.buttons["communityCrewBoardArchive"].tap()
        app.alerts.buttons.matching(identifier:"communityCrewBoardArchiveConfirm").firstMatch.tap()
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 4/5개")
        let restoreBoard=app.buttons["communityCrewBoardRestore-dawn-board-1"]
        XCTAssertTrue(waitHittable(restoreBoard,timeout:8))
        restoreBoard.tap()
        XCTAssertTrue(waitHittable(boardCount,timeout:8))
        XCTAssertEqual(boardCount.label,"활성 게시판 5/5개")

        app.buttons["communityCrewBoardsBackToManage"].tap()
        app.buttons["communityCrewAnnouncements"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C39"].waitForExistence(timeout:5))
        app.textFields["communityCrewAnnouncementTitle"].tap()
        app.textFields["communityCrewAnnouncementTitle"].typeText("토요일 아침 모임")
        app.textViews["communityCrewAnnouncementText"].tap()
        app.textViews["communityCrewAnnouncementText"].typeText("오전 8시에 중앙 공원에서 만나요.")
        app.buttons["communityCrewAnnouncementSend"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewManageFeedback"].label.contains("실제 알림은 전송되지 않았어요"))
        app.buttons["communityCrewManageBoard"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","토요일 아침 모임")).firstMatch.waitForExistence(timeout:5))
        app.buttons["communityCrewBoardTab-dawn-board-1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewPost-dawn-run-1"].exists,"Archiving and restoring a populated board preserves its post")
        XCTAssertTrue(app.descendants(matching:.any)["communityCrewAnnouncementLocalNotice"].exists)
    }

    func testCommunityCrewMemberManagementUsesOwnerRoleAndLocalWarningAndRemoval() {
        launchCommunity("C15")
        app.buttons["communityCrewOpen-dawn"].tap()
        app.buttons["communityCrewManage"].tap()
        app.buttons["communityCrewPendingApplications"].tap()
        app.buttons["communityCrewPendingRequest-fixture-request-dawn-early"].tap()
        app.buttons["communityCrewApproveApplication"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C40"].waitForExistence(timeout:5))
        app.buttons["communityCrewPendingApplicationsBack"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))

        app.buttons["communityCrewMembers"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C34"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewMemberCount"].label,"2/20명")
        app.buttons["communityCrewMember-fixture-member-early"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C35"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewMemberDetailRole"].label,"멤버")

        app.buttons["communityCrewMemberRoleChange"].tap()
        XCTAssertEqual(app.staticTexts["communityCrewMemberDetailRole"].label,"운영자","The owner can grant operator status")
        app.buttons["communityCrewMemberRoleChange"].tap()
        XCTAssertEqual(app.staticTexts["communityCrewMemberDetailRole"].label,"멤버","The owner can revoke operator status")

        let note=app.textViews["communityCrewMemberWarning"]
        note.tap();note.typeText("함께 안전하게 달려 주세요.")
        app.buttons["communityCrewMemberWarn"].tap()
        XCTAssertEqual(app.staticTexts["communityCrewWarningCount"].label,"주의 기록 1회")
        XCTAssertTrue(app.staticTexts["communityCrewMemberFeedback"].label.contains("실제로 전달되지는 않았어요"))

        app.buttons["communityCrewMemberKick"].tap()
        XCTAssertTrue(app.alerts["이 멤버를 내보낼까요?"].waitForExistence(timeout:3))
        app.alerts.buttons["취소"].tap()
        XCTAssertEqual(app.staticTexts["communityCrewMemberDetailRole"].label,"멤버","Cancel keeps the member in the crew")
        app.buttons["communityCrewMemberKick"].tap()
        app.alerts.buttons.matching(identifier:"communityCrewConfirmRemove").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C34"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewMemberCount"].label,"1/20명")
        XCTAssertFalse(app.buttons["communityCrewMember-fixture-member-early"].exists,"A removed member leaves the local member list")
    }

    func testCommunityCrewEditDiscardPromptTracksActualChangesAndTabExit() {
        launchCommunity("C15")
        app.buttons["communityCrewOpen-dawn"].tap()
        app.buttons["communityCrewManage"].tap()
        app.buttons["communityCrewEdit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C20"].waitForExistence(timeout:5))
        app.buttons["communityCrewCancelEdit"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"An unchanged edit exits immediately")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))

        app.buttons["communityCrewEdit"].tap()
        let name=app.textFields["communityCrewDraftName"]
        replaceInput(name,"임시 이름")
        replaceInput(name,"모브 새벽 크루")
        app.buttons["communityCrewCancelEdit"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Restoring the original values clears the dirty state")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))

        app.buttons["communityCrewEdit"].tap()
        replaceInput(app.textFields["communityCrewDraftName"],"버릴 이름")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["계속 편집"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C20"].exists)
        app.buttons["communityCrewCancelEdit"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewManagementName"].label,"모브 새벽 크루","Discard leaves saved crew data unchanged")

        app.buttons["communityCrewEdit"].tap()
        app.segmentedControls["communityCrewDraftRegion"].buttons["모브시 강변"].tap()
        app.buttons["tab-0"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:5),"Discard completes the pending tab change")
        XCTAssertFalse(app.descendants(matching:.any)["screen-C20"].isHittable)

        app.buttons["tab-3"].tap()
        app.buttons["community-tab-crew"].tap()
        app.buttons["communityCrewOpen-dawn"].tap()
        app.buttons["communityCrewManage"].tap()
        app.buttons["communityCrewEdit"].tap()
        replaceInput(app.textFields["communityCrewDraftName"],"저장한 새벽 크루")
        app.buttons["communityCrewSave"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C21"].waitForExistence(timeout:5))
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Saving clears the dirty state")
    }

    func testOrdinaryMemberCannotOpenCrewManagementOrApplicationReview() {
        launchCommunity("C21",viewerID:"fixture-member-no-eul")
        XCTAssertTrue(app.staticTexts["communityCrewManageRestricted"].exists || app.descendants(matching:.any)["communityCrewManageRestricted"].exists)
        launchCommunity("C22",viewerID:"fixture-member-no-eul")
        XCTAssertTrue(app.staticTexts["communityCrewReviewRestricted"].exists || app.descendants(matching:.any)["communityCrewReviewRestricted"].exists)
    }

    func testCommunityCourseWritingAndFollowPreviewStayLocal() {
        launchCommunity("C01",verificationStatus:"approved",twoCourseRecords:true)
        app.buttons["communityStartCourseShare"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5))
        courseReplace("강변 코스 기록",into:app.textFields["communityCourseName"])
        courseReplace("강변에서 달리는 예시 코스입니다.",into:app.textViews["communityCourseIntroduction"])
        XCTAssertTrue(app.buttons["communityCoursePreview"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityCoursePreview"].isEnabled,"The first eligible fixture record is selectable")
        app.buttons["communityCoursePreview"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityPreviewTitle"].label,"강변 코스 기록")
        XCTAssertTrue(app.otherElements["communityPreviewCourseMap"].exists || app.descendants(matching:.any)["communityPreviewCourseMap"].exists)
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5),"Back from preview returns to the same draft")
        XCTAssertEqual(app.textFields["communityCourseName"].value as? String,"강변 코스 기록")
        app.buttons["communityCoursePreview"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        app.buttons["communityCoursePublish"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons.matching(identifier:"communityPostOpen-local").count,1,"One publish tap creates one local post")
        app.buttons.matching(identifier:"communityPostOpen-local").element(boundBy:0).tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityOpenAttachedCourse"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C12"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCourseTitle"].label,"강변 코스 기록")
        XCTAssertEqual(app.buttons["communityCourseAuthor"].label.contains("새벽러너"),true,"The course uses the actual local publisher profile")
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseAuthorBadge"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseSourceRecord"].label.contains("가볍게 달린 아침"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-거리"].label.contains("4.82 km"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-기록 시간"].label.contains("30:08"))
        XCTAssertTrue(app.otherElements["communityCourseMap"].exists || app.descendants(matching:.any)["communityCourseMap"].exists)
        app.buttons["뒤로"].tap();app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))

        app.buttons["communityStartCourseShare"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5))
        app.buttons["communityCourseRecordPicker"].tap()
        let secondRecord=app.buttons["저녁 공원 러닝 · 3.4 km"]
        XCTAssertTrue(secondRecord.waitForExistence(timeout:5),app.debugDescription)
        secondRecord.tap()
        courseReplace("공원 코스 기록",into:app.textFields["communityCourseName"])
        courseReplace("공원에서 달리는 별도 예시 경로입니다.",into:app.textViews["communityCourseIntroduction"])
        app.buttons["communityCoursePreview"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityPreviewTitle"].label,"공원 코스 기록")
        app.buttons["communityCoursePublish"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons.matching(identifier:"communityPostOpen-local").count,2,"Two explicitly published courses remain separately available")
        app.buttons.matching(identifier:"communityPostOpen-local").element(boundBy:0).tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityOpenAttachedCourse"].tap()
        XCTAssertEqual(app.staticTexts["communityCourseTitle"].label,"공원 코스 기록")
        XCTAssertEqual(app.buttons["communityCourseAuthor"].label.contains("새벽러너"),true)
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseSourceRecord"].label.contains("저녁 공원 러닝"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-거리"].label.contains("3.4 km"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-기록 시간"].label.contains("15:00"))
        app.buttons["communityCourseFollowRun"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C14"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityGhostCourseTitle"].label,"공원 코스 기록")
        XCTAssertEqual(app.staticTexts["communityGhostClock"].label,"00:00 / 15:00")
        app.buttons["communityGhostPlayPause"].tap()
        XCTAssertTrue(waitForLayout({self.app.staticTexts["communityGhostClock"].label != "00:00 / 15:00"},timeout:4),"Example playback advances on the selected course's local timeline")
        app.buttons["communityGhostPlayPause"].tap()
        app.buttons["communityGhostReset"].tap()
        XCTAssertEqual(app.staticTexts["communityGhostClock"].label,"00:00 / 15:00")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C12"].exists,"Back returns to the course detail")
        app.buttons["뒤로"].tap();app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons.matching(identifier:"communityPostOpen-local").count,2)
        app.buttons.matching(identifier:"communityPostOpen-local").element(boundBy:1).tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityOpenAttachedCourse"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C12"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCourseTitle"].label,"강변 코스 기록")
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseSourceRecord"].label.contains("가볍게 달린 아침"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-거리"].label.contains("4.82 km"))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-기록 시간"].label.contains("30:08"))
    }

    func testCommunityCourseCancelAndBackPreserveOnlyUnpublishedDraft() {
        launchCommunity("C01",verificationStatus:"approved",twoCourseRecords:true)
        app.buttons["communityStartCourseShare"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5))
        app.buttons["communityCourseCancel"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"A fresh course composer exits without a confirmation")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))

        app.buttons["communityStartCourseShare"].tap()
        app.buttons["communityCourseRecordPicker"].tap()
        app.buttons["저녁 공원 러닝 · 3.4 km"].tap()
        courseReplace("취소할 코스",into:app.textFields["communityCourseName"])
        courseReplace("게시하지 않을 초안",into:app.textViews["communityCourseIntroduction"])
        let hideEnds=app.switches["communityCourseHideEnds"]
        XCTAssertTrue(hideEnds.waitForExistence(timeout:5),app.debugDescription)
        hideEnds.tap()
        app.buttons["communityCoursePreview"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityCourseFact-거리"].label.contains("3.4 km"),"The selected run record supplies the course preview facts")
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Entering preview is part of the composer flow")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["communityCourseName"].value as? String,"취소할 코스")
        XCTAssertEqual(app.textViews["communityCourseIntroduction"].value as? String,"게시하지 않을 초안")
        XCTAssertEqual(app.switches["communityCourseHideEnds"].value as? String,"0","The course privacy setting survives a preview round trip")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["계속 편집"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].exists)
        XCTAssertEqual(app.textFields["communityCourseName"].value as? String,"취소할 코스","Continue editing keeps the draft intact")
        app.buttons["communityCourseCancel"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons.matching(identifier:"communityPostOpen-local").count,0,"Cancelling never publishes a post")
        app.buttons["communityStartCourseShare"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C13"].waitForExistence(timeout:5),"Cancel cleared its navigation stack")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),"Back from a fresh composer returns to the community root")
    }

    private func courseReplace(_ value:String,into element:XCUIElement){
        XCTAssertTrue(element.waitForExistence(timeout:5),app.debugDescription)
        if !element.isHittable{app.scrollViews.firstMatch.swipeUp()}
        element.tap();let old=element.value as? String ?? "";element.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+value)
    }

    func testCommunityCourseWritingRequiresApprovedLocalAccount() {
        launchCommunity("C13")
        XCTAssertTrue(app.staticTexts["communityCourseNeedsVerification"].exists)
        app.buttons["communityCourseVerify"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C11"].waitForExistence(timeout:5))
    }

    func testCommunityFeedCardImageAndBlankAreaOpenDetailOnCompactDark() {
        launchCommunity("C01",appearance:"dark",compact:true)
        let card=app.buttons["communityPostOpen-p1"]
        XCTAssertTrue(card.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(waitHittable(card))
        app.scrollViews["communityFeedScroll"].swipeUp()
        let feedImage=app.buttons["communityFeedImageOpen-p1"]
        XCTAssertTrue(feedImage.waitForExistence(timeout:5),app.debugDescription)
        feedImage.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5),"Feed photo opens the post detail")
        XCTAssertTrue(app.buttons["communityDetailImageOpen"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        let returnedCard=app.buttons["communityPostOpen-p1"]
        XCTAssertTrue(waitHittable(returnedCard))
        app.scrollViews["communityFeedScroll"].swipeDown()
        returnedCard.coordinate(withNormalizedOffset:CGVector(dx:0.04,dy:0.02)).tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5),"The padded blank region of a post card opens its detail")
        app.buttons["communityDetailImageOpen"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04-IMAGE"].waitForExistence(timeout:5))
        let zoom=app.images["communityImageZoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertLessThanOrEqual(zoom.frame.width,321,"Zoomed image fits the 320pt compact viewport")
        XCTAssertTrue(app.buttons["communityImageClose"].isHittable)
        XCTAssertTrue(containsDarkPixel(in:app.screenshot().image,rect:CGRect(x:50,y:280,width:12,height:12)),"The viewer stays legible on a dark background")
        app.buttons["communityImageClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        capture("community-detail-image-compact-dark")
    }

    func testCommunityVideoOpensPlaysPausesAndStopsWhenViewerCloses() {
        launchCommunity("C01",videoPostFixture:true)
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.descendants(matching:.any)["communityDetailPhotos"].swipeLeft()
        let video=app.buttons["communityDetailPhotoOpen-1"]
        XCTAssertTrue(video.waitForExistence(timeout:5),app.debugDescription)
        video.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04-IMAGE"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityVideoViewer"].waitForExistence(timeout:5),app.debugDescription)
        let play=app.buttons["communityVideoPlay"]
        XCTAssertTrue(play.waitForExistence(timeout:5))
        play.tap()
        let pause=app.buttons["communityVideoPause"]
        XCTAssertTrue(pause.waitForExistence(timeout:3),"Playback toggles into the playing state")
        pause.tap()
        XCTAssertTrue(app.buttons["communityVideoPlay"].waitForExistence(timeout:3),"Playback can be paused")
        app.buttons["communityImageClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.descendants(matching:.any)["communityDetailPhotos"].swipeLeft()
        app.buttons["communityDetailPhotoOpen-1"].tap()
        XCTAssertTrue(app.buttons["communityVideoPlay"].waitForExistence(timeout:5),"Reopening the viewer starts paused from the beginning")
    }

    func testCommunityVideoDraftPreviewPlaysLocally() {
        launchCommunity("C05",videoDraftFixture:true)
        XCTAssertTrue(app.descendants(matching:.any)["communityComposePhotoCount"].waitForExistence(timeout:5))
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        let previewVideo=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityPreviewPhoto-")).firstMatch
        XCTAssertTrue(previewVideo.waitForExistence(timeout:5),app.debugDescription)
        previewVideo.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04-IMAGE"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityVideoPlay"].waitForExistence(timeout:5))
        app.buttons["communityVideoPlay"].tap()
        XCTAssertTrue(app.buttons["communityVideoPause"].waitForExistence(timeout:3))
        app.buttons["communityImageClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
    }

    func testCommunityViewCountRunsLocalKSTPolicyOnlyOnDetailEntry() {
        launchCommunity("C01")
        let listCount=app.descendants(matching:.any)["communityViews-p1"]
        XCTAssertTrue(listCount.waitForExistence(timeout:5))
        XCTAssertTrue(listCount.label.contains("138"),listCount.label)
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        let detailCount=app.descendants(matching:.any)["communityDetailViews"]
        XCTAssertTrue(detailCount.waitForExistence(timeout:5))
        XCTAssertTrue(detailCount.label.contains("139"),detailCount.label)
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(listCount.label.contains("139"),listCount.label)
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertTrue(detailCount.label.contains("139"),"Repeat detail entry by the same member on the same KST date counts once: \(detailCount.label)")
    }

    func testCommunitySearchFiltersGroupsNormalizesAndReturnsToQuery() {
        launchCommunity("C01")
        tap("communitySearch")
        XCTAssertTrue(app.textFields["communitySearchField"].waitForExistence(timeout:5),app.debugDescription)
        let query=app.textFields["communitySearchField"]
        XCTAssertTrue(app.staticTexts["communitySearchHint"].exists)
        query.typeText("강변")
        XCTAssertTrue(app.buttons["communitySearchPost-p1"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.buttons["communitySearchPost-p3"].exists)
        XCTAssertEqual(app.staticTexts["communitySearchCount-posts"].label,"게시물 2")
        XCTAssertEqual(app.staticTexts["communitySearchCount-profiles"].label,"프로필 0")
        XCTAssertEqual(app.staticTexts["communitySearchCount-crews"].label,"크루 1")
        app.buttons["communitySearchPost-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"오늘은 강변을 따라 5 km")
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C29"].waitForExistence(timeout:5))
        XCTAssertEqual(query.value as? String,"강변","Returning to search preserves the query and result group")

        tap("communitySearchClear")
        query.typeText("가온러너")
        let profile=app.buttons["communitySearchProfile-fixture-member-ga-on"]
        XCTAssertTrue(profile.waitForExistence(timeout:5),app.debugDescription)
        profile.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C07"].waitForExistence(timeout:5))
        tap("communityCardClose")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C29"].waitForExistence(timeout:5))
        XCTAssertEqual(query.value as? String,"가온러너","Profile preview close returns to the same search")

        tap("communitySearchClear")
        query.typeText("모브 강변")
        let crew=app.buttons["communityCrewOpen-river"]
        XCTAssertTrue(crew.waitForExistence(timeout:5),app.debugDescription)
        crew.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C16"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityCrewMemberCount"].label,"모브시 강변 · 멤버 2/20명")
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C29"].waitForExistence(timeout:5))
        XCTAssertEqual(query.value as? String,"모브 강변","Crew introduction returns to the same search")

        tap("communitySearchClear")
        query.typeText("없는검색어")
        XCTAssertTrue(app.descendants(matching:.any)["communitySearchNoResults"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communitySearchEmpty-posts"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["communitySearchEmpty-profiles"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["communitySearchEmpty-crews"].exists)
    }

    func testCommunityHotListUsesExplicitPublicFlagsAndReturnsToFeed() {
        launchCommunity("C01")
        XCTAssertTrue(app.buttons["communityHot-p1"].exists)
        XCTAssertTrue(app.buttons["communityHotMore"].exists)
        tap("communityHotMore")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C41"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityPostOpen-p1"].exists)
        XCTAssertTrue(app.buttons["communityPostOpen-p2"].exists)
        app.buttons["communityPostOpen-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C41"].waitForExistence(timeout:5))
        tap("뒤로")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityHot-p1"].exists)

        launchCommunity("C01",emptyHot:true)
        XCTAssertTrue(app.staticTexts["communityHotEmpty"].waitForExistence(timeout:5))
        tap("communityHotMore")
        XCTAssertTrue(app.descendants(matching:.any)["communityHotListEmpty"].waitForExistence(timeout:5))

        launchCommunity("C41",emptyHot:true)
        XCTAssertTrue(app.descendants(matching:.any)["communityHotListEmpty"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityPostOpen-")).firstMatch.exists)
    }

    func testCommunitySettingsLikedPostsRespectLikesAndBlockedMembers() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityDetailLike"].tap()
        app.buttons["뒤로"].tap()
        app.buttons["communityHot-p2"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityDetailLike"].tap()
        app.buttons["뒤로"].tap()
        openCommunitySettingsFromProfile()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C28"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityVerificationRow"].exists,"Settings keeps the existing account verification entry")
        app.buttons["communityLikedPostsRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C06"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityPersonalPostOpen-p1"].exists)
        XCTAssertTrue(app.buttons["communityPersonalPostOpen-p2"].exists)
        XCTAssertFalse(app.buttons["communityPersonalPostOpen-p3"].exists)

        app.buttons["communityPersonalPostOpen-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuBlockPost"].tap()
        app.buttons["communityModerationConfirm"].tap()
        openCommunitySettingsFromProfile()
        app.buttons["communityLikedPostsRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C06"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityPersonalPostOpen-p1"].exists,"Blocked authors' posts are hidden from liked posts")
        XCTAssertTrue(app.buttons["communityPersonalPostOpen-p2"].exists)
    }

    func testCommunityRecentActivityDeduplicatesOrdersAndHidesBlockedPosts() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        app.buttons["communityHot-p2"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        openCommunitySettingsFromProfile()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C28"].waitForExistence(timeout:5))
        app.buttons["communityActivityRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C43"].waitForExistence(timeout:5))
        let first=app.buttons["communityPersonalPostOpen-p1"],second=app.buttons["communityPersonalPostOpen-p2"]
        XCTAssertTrue(first.exists);XCTAssertTrue(second.exists)
        XCTAssertFalse(app.buttons["communityPersonalPostOpen-p3"].exists)
        XCTAssertEqual(app.buttons.matching(identifier:"communityPersonalPostOpen-p1").count,1,"Repeat visits update recency without duplicate rows")
        XCTAssertLessThan(first.frame.minY,second.frame.minY,"History is sorted by each post's latest view")

        app.buttons["communityPersonalPostOpen-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuBlockPost"].tap()
        app.buttons["communityModerationConfirm"].tap()
        openCommunitySettingsFromProfile()
        app.buttons["communityActivityRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C43"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityPersonalPostOpen-p1"].exists,"Blocked authors' posts are hidden from recent activity")
        XCTAssertTrue(app.buttons["communityPersonalPostOpen-p2"].exists)
    }

    func testCommunityVerificationSubmitOperatorReviewAndResubmission() {
        let suite="mov.community.verification.\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","C10","-wire-fixture","-wire-test-store-suite",suite,"-wire-reset","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C10"].waitForExistence(timeout:10))
        let note=app.textViews["communityVerificationNote"]
        XCTAssertTrue(note.waitForExistence(timeout:5))
        app.buttons["communityVerificationSubmit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C10"].exists,"Empty application stays on the form")
        XCTAssertTrue(app.staticTexts["communityVerificationError"].exists)
        note.tap();note.typeText("주간 러닝 활동을 기록하고 있어요.")
        app.buttons["communityVerificationSubmit"].tap()
        XCTAssertEqual(app.staticTexts["communityVerificationHeading"].label,"인증을 검토하고 있어요")
        app.buttons["뒤로"].tap()
        app.buttons["communityVerificationSubmit"].tap()
        XCTAssertEqual(app.staticTexts["communityVerificationError"].label,"인증 신청을 검토하고 있어요.","A duplicate submission reports the pending state, not an input error")
        app.terminate()
        app.launchArguments=["-wire-screen","C11","-wire-fixture","-wire-test-store-suite",suite,"-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C11"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["communityVerificationHeading"].label,"인증을 검토하고 있어요")
        app.buttons["communityVerificationRejectExample"].tap()
        XCTAssertEqual(app.staticTexts["communityVerificationHeading"].label,"신청 내용을 다시 확인해 주세요")
        XCTAssertTrue(app.staticTexts["communityVerificationMessage"].label.contains("조금 더 구체적으로"))
        app.buttons["communityVerificationContinue"].tap()
        XCTAssertTrue(app.textViews["communityVerificationNote"].waitForExistence(timeout:5))
        app.buttons["communityVerificationSubmit"].tap()
        XCTAssertEqual(app.staticTexts["communityVerificationHeading"].label,"인증을 검토하고 있어요")
        app.buttons["communityVerificationApproveExample"].tap()
        XCTAssertEqual(app.staticTexts["communityVerificationHeading"].label,"계정 인증이 완료됐어요")
        XCTAssertEqual(app.staticTexts["communityVerificationMessage"].label,"이제 코스를 공유할 수 있어요.")

        app.terminate()
        app.launchArguments=["-wire-screen","C01","-wire-fixture","-wire-test-store-suite",suite,"-appearance","light"]
        app.launch()
        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityOwnProfile"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["communityRunnerVerifiedBadge-fixture-member-current"].exists,"Approved state persists and marks the signed-in runner's profile card")
        app.buttons["community-tab-feed"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        app.buttons["communityCompose"].tap()
        let postTitle=app.textFields["communityComposeTitle"]
        postTitle.tap();postTitle.typeText("인증된 러닝 기록")
        let postBody=app.textViews["communityComposeBody"]
        postBody.tap();postBody.typeText("오늘의 러닝 활동을 남깁니다.")
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        let publish=app.buttons["communityPublishButton"]
        XCTAssertTrue(publish.waitForExistence(timeout:5))
        publish.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityPostVerificationBadge-current"].exists,"The same approved state marks the signed-in runner's post")
        for status in ["pending","rejected"] {
            app.terminate()
            app.launchArguments=["-wire-screen","C01","-wire-fixture","-wire-test-store-suite",suite,"-wire-community-verification-status",status,"-appearance","light"]
            app.launch()
            app.buttons["community-tab-profile"].tap()
            XCTAssertTrue(app.descendants(matching:.any)["communityOwnProfile"].waitForExistence(timeout:10))
            XCTAssertFalse(app.descendants(matching:.any)["communityRunnerVerifiedBadge-fixture-member-current"].exists,"\(status) applications do not show a verification badge")
        }
        app.terminate()
        app.launchArguments=["-wire-screen","C01","-wire-fixture","-wire-test-store-suite",suite,"-appearance","light"]
        app.launch()
        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityOwnProfile"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["communityRunnerVerifiedBadge-fixture-member-current"].exists,"The approved profile badge remains after relaunch")
    }

    func testCommunityTextLimitsDisableEmptyActionsAndKeepDraftOnBack() {
        launchCommunity("C05")
        let preview=app.buttons["communityPreviewButton"]
        XCTAssertTrue(preview.waitForExistence(timeout:5))
        XCTAssertFalse(preview.isEnabled,"Empty title/body cannot proceed")
        let title=app.textFields["communityComposeTitle"]
        title.tap();title.typeText(String(repeating:"a",count:61))
        XCTAssertEqual((title.value as? String)?.count,60,"Title entry stops at 60 characters")
        let body=app.textViews["communityComposeBody"]
        body.tap();body.typeText(String(repeating:"b",count:2001))
        XCTAssertEqual((body.value as? String)?.count,2000,"Body entry stops at 2,000 characters")
        XCTAssertTrue(preview.isEnabled,"Both maximum-length values are valid")
        preview.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        XCTAssertEqual((app.textFields["communityComposeTitle"].value as? String)?.count,60)
        XCTAssertEqual((app.textViews["communityComposeBody"].value as? String)?.count,2000)
    }

    func testCommunityPostComposerDiscardPromptTracksReversionPreviewAndDestination() {
        launchCommunity("C01")
        app.buttons["communityCompose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"An unchanged post composer exits immediately")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))

        app.buttons["communityCompose"].tap()
        let title=app.textFields["communityComposeTitle"]
        replaceInput(title,"초안 제목")
        let body=app.textViews["communityComposeBody"]
        body.tap();body.typeText("저장 전 초안")
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Preview does not count as leaving the draft")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["communityComposeTitle"].value as? String,"초안 제목")
        XCTAssertEqual(app.textViews["communityComposeBody"].value as? String,"저장 전 초안")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["계속 편집"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].exists)
        XCTAssertEqual(app.textFields["communityComposeTitle"].value as? String,"초안 제목","Continue editing retains the post draft")

        replaceInput(app.textFields["communityComposeTitle"],"")
        let postBody=app.textViews["communityComposeBody"]
        courseReplace("",into:postBody)
        XCTAssertFalse(app.buttons["communityPreviewButton"].isEnabled,"The reverted title and body leave no publishable draft")
        app.buttons["뒤로"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Reverting all fields clears the dirty state")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))

        app.buttons["communityCompose"].tap()
        replaceInput(app.textFields["communityComposeTitle"],"버릴 초안")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),"Discard follows the original feed destination")
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"The confirmed exit does not reopen the modal")
    }


    func testCommunityFeedOpensPostAndAddsLocalComment() {
        launchCommunity("C01")
        XCTAssertTrue(app.staticTexts["지금 많이 보는 글"].exists)
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"오늘은 강변을 따라 5 km")
        let like=app.buttons["communityDetailLike"]
        XCTAssertTrue(like.waitForExistence(timeout:5))
        like.tap()
        XCTAssertTrue(like.label.contains("25"),like.label)
        let comment=app.textFields["communityCommentInput"]
        XCTAssertTrue(comment.waitForExistence(timeout:5))
        let submit=app.buttons["communityCommentSubmit"]
        XCTAssertFalse(submit.isEnabled,"Empty comment cannot be registered")
        comment.tap();comment.typeText(String(repeating:"x",count:301))
        XCTAssertTrue(submit.isEnabled)
        tap("communityCommentSubmit")
        let registeredComment=app.staticTexts.matching(NSPredicate(format:"label == %@",String(repeating:"x",count:300))).firstMatch
        XCTAssertTrue(registeredComment.waitForExistence(timeout:5),"The overlong entry is locally capped at 300 characters")
        XCTAssertTrue(app.staticTexts["댓글 2"].exists)
    }

    func testCommunityCommentComposerWrapsThreeHundredUnbrokenCharactersAndClearsAfterSend() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))

        let input=app.textFields["communityCommentInput"]
        let submit=app.buttons["communityCommentSubmit"]
        XCTAssertTrue(input.waitForExistence(timeout:5),app.debugDescription)
        let initialFrame=input.frame
        let prefix=String(repeating:"한",count:299)
        pasteText(prefix,into:input)

        let keyboard=app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(waitForLayout({input.frame.height>initialFrame.height},timeout:5),app.debugDescription)
        let eightLineHeightBudget=8*UIFont.systemFont(ofSize:14).lineHeight+40
        XCTAssertLessThanOrEqual(input.frame.height,eightLineHeightBudget,"The composer caps its visible height at eight lines and scrolls within the field")
        input.typeText("끝")
        let text=prefix+"끝"
        XCTAssertEqual(input.value as? String,text,"Display wrapping must not insert newlines into the comment value")
        XCTAssertLessThanOrEqual(input.frame.maxX,app.frame.maxX-12,"The field stays within the available width")
        XCTAssertTrue(waitHittable(submit,timeout:5),app.debugDescription)
        XCTAssertLessThan(submit.frame.maxY,keyboard.frame.minY,"The send button remains above the open keyboard")
        capture("community-comment-300-unbroken-keyboard")

        submit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@",text)).firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(waitForLayout({
            let value=input.value as? String ?? ""
            return value.isEmpty || value=="댓글을 남겨 보세요"
        },timeout:5),app.debugDescription)
    }

    func testCommunityCanvasFillsTopAndBottomSafeAreasInLightAndDark() {
        for (appearance,expected) in [("light",(255,255,255)),("dark",(25,25,25))] {
            if app.state != .notRunning { app.terminate() }
            launchCommunity("C01",appearance:appearance)
            let screenshot=app.screenshot().image
            let topSafeArea=CGRect(x:8,y:8,width:12,height:12)
            let bottomSafeArea=CGRect(x:8,y:screenshot.size.height-20,width:12,height:12)
            XCTAssertTrue(matchesRGB(in:screenshot,rect:topSafeArea,expected:expected),"The \(appearance) canvas color reaches the status-bar safe area")
            XCTAssertTrue(matchesRGB(in:screenshot,rect:bottomSafeArea,expected:expected),"The \(appearance) canvas color reaches the home-indicator safe area")
            capture("community-safe-area-\(appearance)")
        }
    }

    func testCommunityCommentComposerPreservesMultilinePasteAndLongURL() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))

        let input=app.textFields["communityCommentInput"]
        let submit=app.buttons["communityCommentSubmit"]
        XCTAssertTrue(input.waitForExistence(timeout:5),app.debugDescription)
        let initialFrame=input.frame
        let longEnglish=String(repeating:"Runner",count:22)
        let longURL="https://example.com/"+String(repeating:"path/",count:14)
        let pastedText="첫 줄\n\(longEnglish)\n\(longURL)\n마지막 줄"
        XCTAssertLessThanOrEqual(pastedText.count,300)
        pasteText(pastedText,into:input)

        let keyboard=app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(waitForLayout({input.frame.height>initialFrame.height},timeout:5),app.debugDescription)
        XCTAssertEqual(input.value as? String,pastedText,"Only the pasted line breaks belong in the stored value")
        XCTAssertLessThanOrEqual(input.frame.maxX,app.frame.maxX-12)
        XCTAssertTrue(waitHittable(submit,timeout:5),app.debugDescription)
        XCTAssertLessThan(submit.frame.maxY,keyboard.frame.minY)
        capture("community-comment-multiline-url-paste")

        submit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@",pastedText)).firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(waitForLayout({
            let value=input.value as? String ?? ""
            return value.isEmpty || value=="댓글을 남겨 보세요"
        },timeout:5),app.debugDescription)
    }

    func testCommunityCrewReplyComposerKeepsTargetWhileGrowingAndResetsAfterSend() {
        launchCommunity("C19",viewerID:"fixture-member-ga-on",crewID:"river",crewBoardID:"river-board-2")
        let post=app.buttons["communityCrewPost-river-run-1"]
        XCTAssertTrue(post.waitForExistence(timeout:5),app.debugDescription)
        post.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityDetailCrewContext"].exists)
        app.buttons["communityReply-river-comment-1"].tap()

        let target=app.staticTexts["communityReplyComposerTarget"]
        XCTAssertTrue(target.waitForExistence(timeout:3),app.debugDescription)
        XCTAssertTrue(target.label.contains("노을러너에게 답글"),target.label)
        let input=app.textFields["communityCommentInput"]
        XCTAssertTrue(input.waitForExistence(timeout:5),app.debugDescription)
        let initialFrame=input.frame
        let text=Array(repeating:"crew reply",count:20).joined(separator:" ")
        input.tap()
        input.typeText(text)
        XCTAssertTrue(waitForLayout({input.frame.height>initialFrame.height},timeout:5),app.debugDescription)
        XCTAssertEqual(input.value as? String,text)
        XCTAssertTrue(target.exists,"Growing the input keeps the reply target visible")

        let submit=app.buttons["communityCommentSubmit"]
        let keyboard=app.keyboards.firstMatch
        XCTAssertEqual(submit.label,"답글 등록")
        XCTAssertTrue(keyboard.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(waitHittable(submit,timeout:5),app.debugDescription)
        XCTAssertLessThan(submit.frame.maxY,keyboard.frame.minY)
        capture("crew-reply-long-input-keyboard")

        submit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@",text)).firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(waitForLayout({!target.exists},timeout:5),app.debugDescription)
        XCTAssertTrue(waitForLayout({
            let value=input.value as? String ?? ""
            return value.isEmpty || value=="댓글을 남겨 보세요"
        },timeout:5),app.debugDescription)
    }

    func testCommunityPostBlockHidesContentAndSettingsCanUnblock() {
        launchCommunity("C01")
        let post=app.buttons["communityHot-p1"]
        XCTAssertTrue(post.waitForExistence(timeout:5));post.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuBlockPost"].tap()
        XCTAssertTrue(app.staticTexts["작성자를 차단할까요?"].waitForExistence(timeout:3))
        app.buttons["communityModerationConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityHot-p1"].exists,"Blocking a post author hides that author's post in the feed")
        openCommunitySettingsFromProfile()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C28"].waitForExistence(timeout:5))
        app.buttons["communityBlockedUsersRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C42"].waitForExistence(timeout:5))
        let unblock=app.buttons["communityUnblock-fixture-member-ga-on"]
        XCTAssertTrue(unblock.waitForExistence(timeout:5));unblock.tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityBlockedUsersEmpty"].waitForExistence(timeout:3))
        app.buttons["뒤로"].tap();app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityHot-p1"].waitForExistence(timeout:5),"Unblocking restores the author's content")
    }

    func testCommunityReportAllReasonsAndPostReportBlockPrompt() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuReportPost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C23"].waitForExistence(timeout:5))
        let detail=app.textViews["communityReportDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout:5));detail.tap();detail.typeText("개인 정보가 포함되어 있어요")
        app.buttons["communityReportSubmit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C25"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["신고가 접수됐어요"].exists)
        XCTAssertTrue(app.buttons["communityModerationConfirm"].waitForExistence(timeout:3))
        app.buttons["communityModerationCancel"].tap()
        XCTAssertFalse(app.staticTexts["작성자도 차단할까요?"].exists)
        XCTAssertTrue(app.buttons["communityReportDone"].exists)
    }

    func testCommunityAnonymousPostCannotOpenProfileAndBlockListMasksIdentity() {
        launchCommunity("C01",anonymousPost:true)
        XCTAssertFalse(app.buttons["communityHot-p1"].exists,"Anonymous posts do not enter the public HOT list")
        XCTAssertFalse(app.buttons["communityPostOpen-p1"].exists,"Anonymous posts do not enter the public feed")
        XCTAssertFalse(app.staticTexts["노출되면 안 되는 실명"].exists)
        tap("communitySearch")
        let search=app.textFields["communitySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout:5))
        search.typeText("강변")
        XCTAssertFalse(app.buttons["communitySearchPost-p1"].exists,"Anonymous post text is excluded from search")
        app.terminate()
        launchCommunity("C04",anonymousPost:true)
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityDetailAuthorCard"].exists,"Anonymous post detail must not open C07")
        XCTAssertTrue(app.staticTexts["communityAnonymousDetailAuthor"].exists)
        XCTAssertTrue(app.staticTexts["communityAnonymousCommentAuthor-c1"].exists)
        XCTAssertFalse(app.staticTexts["노출되면 안 되는 실명"].exists)
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuBlockPost"].tap()
        app.buttons["communityModerationConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertFalse(app.buttons["communityHot-p1"].exists)
        openCommunitySettingsFromProfile()
        app.buttons["communityBlockedUsersRow"].tap()
        XCTAssertTrue(app.staticTexts["차단한 사용자"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["익명으로 차단한 사용자예요"].exists)
        XCTAssertFalse(app.staticTexts["가온러너"].exists,"Anonymous block list entry must not disclose the member identity")
        app.buttons["communityUnblock-fixture-member-ga-on"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityBlockedUsersEmpty"].waitForExistence(timeout:3))
        app.buttons["뒤로"].tap();app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityHot-p1"].exists,"Unblocking does not place anonymous content in the public feed")
        tap("communitySearch")
        let searchAfterUnblock=app.textFields["communitySearchField"]
        XCTAssertTrue(searchAfterUnblock.waitForExistence(timeout:5))
        searchAfterUnblock.typeText("강변")
        XCTAssertFalse(app.buttons["communitySearchPost-p1"].exists,"Anonymous content stays out of public search after unblock")
    }

    func testCommunityNamedProfileMoreCanReportAndSelectReason() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        let author=app.buttons["communityDetailAuthorCard"]
        XCTAssertTrue(author.waitForExistence(timeout:5));XCTAssertTrue(author.isHittable)
        author.tap()
        XCTAssertTrue(app.buttons["communityCardVisit"].waitForExistence(timeout:5))
        app.buttons["communityCardVisit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        app.buttons["communityProfileMore"].tap()
        app.buttons["communityMenuReportProfile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C23"].waitForExistence(timeout:5))
        let reasonPicker=app.descendants(matching:.any)["communityReportReason"]
        XCTAssertTrue(reasonPicker.waitForExistence(timeout:5));reasonPicker.tap()
        let reason=app.buttons["개인정보 노출"]
        XCTAssertTrue(reason.waitForExistence(timeout:5));reason.tap()
        let detail=app.textViews["communityReportDetail"]
        detail.tap();detail.typeText("신고 사유 선택 확인")
        app.buttons["communityReportSubmit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C25"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityModerationConfirm"].exists)
    }

    func testCommunityNestedRepliesQuoteParentsAndKeepChildrenWhenDeleted() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["communityCommentAuthorBadge-c1"].waitForExistence(timeout:3),"Post-author comments use the stable member ID to show the badge")
        app.buttons["communityReply-c1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityReplyComposerTarget"].waitForExistence(timeout:3))
        let input=app.textFields["communityCommentInput"]
        input.tap();input.typeText("첫 단계 답글")
        app.buttons["communityCommentSubmit"].tap()
        let child=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityReply-"))
        XCTAssertTrue(child.firstMatch.waitForExistence(timeout:5))
        child.element(boundBy:1).tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityReplyComposerTarget"].waitForExistence(timeout:3))
        input.tap();input.typeText("한 단계 더 깊은 답글")
        app.buttons["communityCommentSubmit"].tap()
        XCTAssertTrue(app.staticTexts["한 단계 더 깊은 답글"].waitForExistence(timeout:5))
        let grandchildReplyID=String(child.element(boundBy:2).identifier.dropFirst("communityReply-".count))
        let delete=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","communityDeleteComment-"))
        XCTAssertTrue(delete.firstMatch.waitForExistence(timeout:3))
        let deletedCommentID=String(delete.firstMatch.identifier.dropFirst("communityDeleteComment-".count))
        delete.firstMatch.tap()
        let tombstone=app.staticTexts["communityCommentText-\(deletedCommentID)"]
        XCTAssertTrue(tombstone.waitForExistence(timeout:3))
        XCTAssertEqual(tombstone.label,"삭제된 댓글입니다")
        XCTAssertFalse(app.staticTexts["communityCommentAuthorBadge-\(deletedCommentID)"].exists,"Deleted comments do not retain the author badge")
        XCTAssertTrue(app.staticTexts["한 단계 더 깊은 답글"].exists,"Deleting a parent keeps its descendant visible")
        let quote=app.descendants(matching:.any)["communityReplyQuote-\(grandchildReplyID)"]
        XCTAssertTrue(quote.exists)
        XCTAssertEqual(quote.label,"삭제된 댓글입니다","A quote to a deleted parent must not expose its author")
    }

    func testCommunityProfilePreviewVisitPhotoFollowAndProfileContent() {
        launchCommunity("C01")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.buttons["communityDetailAuthorCard"].waitForExistence(timeout:5))
        app.buttons["communityDetailAuthorCard"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C07"].waitForExistence(timeout:5))
        let visit=app.buttons["communityCardVisit"],close=app.buttons["communityCardClose"]
        XCTAssertTrue(visit.exists);XCTAssertTrue(close.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier == %@ OR identifier == %@","communityCardVisit","communityCardClose")).count,2)
        app.buttons["communityCardPhotoOpen"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C31"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityPhotoEmpty"].waitForExistence(timeout:3))
        app.buttons["communityPhotoClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C07"].waitForExistence(timeout:5))
        app.buttons["communityCardClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityDetailAuthorCard"].tap()
        app.buttons["communityCardVisit"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        XCTAssertEqual(app.descendants(matching:.any)["communityProfilePostCount"].label,"2")
        XCTAssertEqual(app.descendants(matching:.any)["communityProfileFollowerCount"].label,"2")
        let follow=app.buttons["communityProfileFollow"]
        XCTAssertEqual(follow.label,"팔로우")
        follow.tap()
        XCTAssertEqual(follow.label,"팔로우 취소")
        XCTAssertEqual(app.descendants(matching:.any)["communityProfileFollowerCount"].label,"3")
        follow.tap()
        XCTAssertEqual(follow.label,"팔로우")
        XCTAssertEqual(app.descendants(matching:.any)["communityProfileFollowerCount"].label,"2")
        XCTAssertTrue(app.buttons["communityPostOpen-p1"].exists)
        app.buttons["communityProfileFollowers"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C30"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityConnection-fixture-member-no-eul"].exists)
    }

    func testCommunityOwnProfileEditsLocallyAndRendersRunningCard() {
        launchCommunity("C01")
        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityProfilePostsEmpty"].exists)
        app.buttons["communityProfileEdit"].tap()
        let nickname=app.textFields["communityEditNickname"]
        XCTAssertTrue(nickname.waitForExistence(timeout:5))
        nickname.tap()
        for _ in 0..<5 { nickname.typeText(XCUIKeyboardKey.delete.rawValue) }
        nickname.typeText("저녁러너")
        app.buttons["communityProfileSave"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"A saved profile closes without a discard prompt")
        let savedName=app.descendants(matching:.any)["communityCardName"]
        XCTAssertTrue(savedName.waitForExistence(timeout:5))
        XCTAssertEqual(savedName.label,"저녁러너")
    }

    func testCommunityProfileCancelConfirmsDiscardAndPreservesDraftOnContinue() {
        launchCommunity("C01")
        app.buttons["community-tab-profile"].tap()
        app.buttons["communityProfileEdit"].tap()
        let nickname=app.textFields["communityEditNickname"]
        nickname.tap()
        for _ in 0..<5 { nickname.typeText(XCUIKeyboardKey.delete.rawValue) }
        nickname.typeText("저녁러너")
        app.buttons["communityProfileEditCancel"].tap()
        let prompt=app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(prompt.waitForExistence(timeout:3))
        prompt.buttons["계속 편집"].tap()
        XCTAssertEqual(app.textFields["communityEditNickname"].value as? String,"저녁러너","Continuing keeps the draft intact")
        app.buttons["communityProfileEditCancel"].tap()
        let secondPrompt=app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(secondPrompt.waitForExistence(timeout:3))
        secondPrompt.buttons["버리기"].tap()
        XCTAssertEqual(app.descendants(matching:.any)["communityCardName"].label,"새벽러너","Discard leaves the saved profile unchanged")
        app.buttons["communityProfileEdit"].tap()
        app.buttons["communityProfileEditCancel"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists,"Closing an unchanged draft is quiet")
        XCTAssertTrue(app.buttons["communityProfileEdit"].exists)
    }

    func testCommunityProfileExitRoutesPromptBeforeSettingsOrTabNavigation() {
        launchCommunity("C01")
        app.buttons["community-tab-profile"].tap()
        app.buttons["communityProfileEdit"].tap()
        let nickname=app.textFields["communityEditNickname"]
        nickname.tap()
        for _ in 0..<5 { nickname.typeText(XCUIKeyboardKey.delete.rawValue) }
        nickname.typeText("저녁러너")
        app.buttons.matching(identifier:"communityOwnProfileSettings").firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        let settingsPrompt=app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(settingsPrompt.waitForExistence(timeout:3))
        settingsPrompt.buttons["계속 편집"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].exists)
        XCTAssertEqual(app.textFields["communityEditNickname"].value as? String,"저녁러너")
        app.buttons["community-tab-home"].tap()
        let tabPrompt=app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(tabPrompt.waitForExistence(timeout:3))
        tabPrompt.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:5))
        app.buttons["tab-3"].tap()
        app.buttons["community-tab-profile"].tap()
        XCTAssertEqual(app.descendants(matching:.any)["communityCardName"].label,"새벽러너","Leaving via a tab after discard preserves the saved value")
    }

    func testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile() {
        launchCommunity("C01")
        let feed=app.buttons["community-tab-feed"]
        let boards=app.buttons["community-tab-boards"]
        let home=app.buttons["community-tab-home"]
        let crew=app.buttons["community-tab-crew"]
        let profile=app.buttons["community-tab-profile"]
        XCTAssertTrue(feed.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(boards.exists && home.exists && crew.exists && profile.exists,app.debugDescription)
        XCTAssertFalse(app.buttons["tab-0"].exists,"Community replaces the global five-tab bar")
        XCTAssertEqual(home.label,"홈")
        XCTAssertEqual(home.frame.midX,app.frame.midX,accuracy:2,"Mov home stays in the center slot")

        let allBoards=app.buttons["communityAllBoards"]
        let mark=app.images["communityHeaderBrandMark"]
        let search=app.buttons["communitySearch"]
        let settings=app.buttons["communitySettings"]
        XCTAssertTrue(allBoards.isHittable,app.debugDescription)
        XCTAssertTrue(mark.exists,app.debugDescription)
        XCTAssertGreaterThanOrEqual(search.frame.minY,50,"The header starts below the iPhone safe area")
        XCTAssertEqual(mark.frame.midX,app.frame.midX,accuracy:2,"The Mov mark stays centered in the feed header")
        XCTAssertLessThan(allBoards.frame.maxX,mark.frame.minX,"The all-boards action stays left of the centered mark")
        XCTAssertLessThan(mark.frame.maxX,search.frame.minX,"The search action stays right of the centered mark")
        XCTAssertFalse(allBoards.frame.intersects(search.frame),"Header actions have separate hit targets")
        XCTAssertFalse(settings.exists,"Community settings stay on the own-profile route")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label == %@","커뮤니티")).firstMatch.exists,"The C01 header omits the Community title")
        capture("community-C01-light-header")

        allBoards.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C27"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.buttons["뒤로"].isHittable,"All boards has a working back route")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),app.debugDescription)
        search.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C29"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.textFields["communitySearchField"].exists)
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5),app.debugDescription)

        for (tab,screen) in [(boards,"C02"),(feed,"C01"),(crew,"C15"),(feed,"C01"),(profile,"C08"),(feed,"C01")] {
            XCTAssertTrue(tab.isHittable,app.debugDescription)
            tab.tap()
            XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:5),app.debugDescription)
            XCTAssertTrue(app.buttons["community-tab-home"].exists,"The community bar remains available on \(screen)")
            if ["C02","C15","C08"].contains(screen){capture("community-\(screen)-light")}
        }

        profile.tap()
        app.buttons["communityOwnProfileSettings"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C28"].waitForExistence(timeout:5))
        capture("community-C28-settings-light")
        app.buttons["communityLikedPostsRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C06"].waitForExistence(timeout:5),"Liked posts stay inside community profile settings")
        capture("community-C06-liked-posts-light")
        app.buttons["뒤로"].tap()
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))

        app.buttons["community-tab-home"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:5))
        capture("community-H00-central-home")
        XCTAssertTrue(app.buttons["tab-3"].exists,"Leaving community returns to the global navigation")
        app.buttons["tab-3"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["community-tab-feed"].exists)
        capture("community-dedicated-navigation-light")
    }

    func testCommunityBottomBarHidesOnDownScrollAndFloatsMoveWithIt() {
        launchCommunity("C01")
        let feed=app.scrollViews["communityFeedScroll"]
        let compose=app.buttons["communityCompose"]
        let feedTab=app.buttons["community-tab-feed"]
        XCTAssertTrue(feed.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(compose.waitForExistence(timeout:5))
        let composeAtTop=compose.frame.midY

        feed.swipeUp()
        XCTAssertTrue(app.buttons["communityScrollToTop"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(waitForLayout({compose.frame.midY>composeAtTop+30},timeout:5),"The compose action moves smoothly into the freed bar area")
        XCTAssertTrue(compose.isHittable,"Writing remains available while the bar is hidden")
        capture("community-scroll-bar-hidden-light")
        XCTAssertTrue(waitForLayout({!feedTab.isHittable},timeout:5),"Scrolling down hides the community bar; frame: \(feedTab.frame)\n\(app.debugDescription)")

        app.buttons["communityScrollToTop"].tap()
        XCTAssertTrue(waitForLayout({feedTab.isHittable},timeout:5),"Returning to the top restores the bar")
        XCTAssertTrue(waitForLayout({!self.app.buttons["communityScrollToTop"].exists},timeout:5),"The top action disappears at the top")
        XCTAssertTrue(waitForLayout({compose.frame.midY<composeAtTop+20},timeout:5),"The compose action returns above the visible bar")

        feed.swipeUp()
        XCTAssertTrue(waitForLayout({!feedTab.isHittable},timeout:5))
        feed.swipeDown()
        XCTAssertTrue(waitForLayout({feedTab.isHittable},timeout:5),"Scrolling back up restores the bar")
        capture("community-scroll-bar-restored-light")
    }

    func testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar() {
        launchCommunity("C01",appearance:"dark")
        let communityTabIDs=["community-tab-feed","community-tab-boards","community-tab-home","community-tab-crew","community-tab-profile"]
        func assertCommunityBar(_ selected:String){
            for id in communityTabIDs {
                let button=app.buttons[id]
                XCTAssertTrue(button.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertTrue(button.isHittable,"\(id) remains visible on the dark community screen")
            }
            XCTAssertFalse(app.buttons["tab-0"].exists,"Primary community screens use only the dedicated community bar")
            XCTAssertTrue(app.buttons[selected].isHittable)
        }

        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label == %@","커뮤니티")).firstMatch.exists)
        XCTAssertTrue(app.buttons["communityAllBoards"].isHittable)
        XCTAssertTrue(app.buttons["communitySearch"].isHittable)
        XCTAssertFalse(app.buttons["communitySettings"].exists)
        let headerMark=app.images["communityHeaderBrandMark"]
        XCTAssertTrue(headerMark.exists,app.debugDescription)
        XCTAssertEqual(headerMark.frame.midX,app.frame.midX,accuracy:2,"The dark feed keeps the Mov mark centered")
        assertCommunityBar("community-tab-feed")
        capture("community-dark-C01-feed-header")

        app.buttons["community-tab-boards"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C02"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["게시판"].exists)
        XCTAssertTrue(app.buttons["뒤로"].isHittable)
        assertCommunityBar("community-tab-boards")
        capture("community-dark-C02-boards")

        app.buttons["community-tab-crew"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C15"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["크루"].exists)
        XCTAssertTrue(app.buttons["뒤로"].isHittable)
        assertCommunityBar("community-tab-crew")
        let crewScroll=app.scrollViews["communityCrewOverview"]
        XCTAssertTrue(crewScroll.waitForExistence(timeout:5),app.debugDescription)
        crewScroll.swipeUp()
        XCTAssertTrue(app.buttons["community-tab-crew"].isHittable,"A short crew screen keeps its bar visible after a no-op upward swipe")
        capture("community-short-dark-C15-crew")

        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["내 정보"].exists)
        XCTAssertTrue(app.buttons["communityOwnProfileSettings"].isHittable)
        assertCommunityBar("community-tab-profile")
        XCTAssertTrue(app.staticTexts["communityProfilePostsEmpty"].exists,"The fixture is the short empty-post profile")
        let profileScroll=app.scrollViews["communityOwnProfileScroll"]
        XCTAssertTrue(profileScroll.waitForExistence(timeout:5),app.debugDescription)
        profileScroll.swipeUp()
        XCTAssertTrue(app.buttons["community-tab-profile"].isHittable,"A short own-profile screen keeps its bar visible after a no-op upward swipe")
        capture("community-short-dark-C08-profile")
    }

    func testCommunityBoardRouteAndLocalPostPreviewPublish() {
        app.launchArguments=["-wire-screen","C01","-wire-fixture","-wire-reset","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:10))
        tap("community-tab-boards")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C02"].waitForExistence(timeout:5))
        tap("communityBrowseAllBoards")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C27"].waitForExistence(timeout:5))
        tap("communityBoard-러닝 질문")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C03"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C02"].waitForExistence(timeout:5))
        tap("communityBoardShortcut-러닝 질문")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C03"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["비 오는 날에는 어떻게 달리세요?"].exists)
        tap("communityBoardCompose")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        let title=app.textFields["communityComposeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout:5))
        title.tap();title.typeText("주말 러닝 메모")
        let body=app.textViews["communityComposeBody"]
        XCTAssertTrue(body.waitForExistence(timeout:5))
        body.tap();body.typeText("강변 코스를 천천히 달렸어요.")
        tap("communityPreviewButton")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityPreviewTitle"].label,"주말 러닝 메모")
        XCTAssertEqual(app.staticTexts["communityPreviewBoard"].label,"러닝 질문")
        tap("communityPublishButton")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","주말 러닝 메모")).firstMatch.waitForExistence(timeout:5))
    }

    func testCommunityOwnPostEditPreviewsAndUpdatesExistingPostInPlace() {
        launchCommunity("C01",viewerID:"fixture-member-ga-on")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuEditPost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["communityComposeTitle"].value as? String,"오늘은 강변을 따라 5 km")
        XCTAssertEqual(app.textViews["communityComposeBody"].value as? String,"속도보다 일정한 호흡에 집중했어요. 오늘 달린 분들도 수고하셨어요.")
        replace("수정한 강변 러닝",into:app.textFields["communityComposeTitle"])
        replace("기존 글의 내용을 고쳤어요.",into:app.textViews["communityComposeBody"])
        tap("communityPreviewButton")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C09"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityPreviewTitle"].label,"수정한 강변 러닝")
        XCTAssertEqual(app.staticTexts["communityPreviewBody"].label,"기존 글의 내용을 고쳤어요.")
        tap("communityEditPostSave")
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"수정한 강변 러닝")
        XCTAssertTrue(app.buttons["communityDetailImageOpen"].exists,"Editing text preserves the existing fixture image")
        XCTAssertTrue(app.staticTexts["댓글 1"].exists,"Editing text preserves the existing comments")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts.matching(identifier:"communityPostTitle-p1").count,1,"Editing keeps the original post ID and does not create a duplicate")
        XCTAssertEqual(app.staticTexts["communityPostTitle-p1"].label,"수정한 강변 러닝")
    }

    func testCommunityPhotoDraftOrderPreviewAndC26Discard() {
        launchCommunity("C05",photoDraftFixture:true)
        XCTAssertEqual(app.staticTexts["communityComposePhotoCount"].label,"사진 2/10")
        app.buttons["communityDraftPhotoMoveRight-0"].tap()
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityPreviewPhoto-review-photo-1"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["communityPreviewPhoto-review-photo-0"].exists)
        app.buttons["다시 수정"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        app.buttons["communityDraftPhotoRemove-0"].tap()
        XCTAssertEqual(app.staticTexts["communityComposePhotoCount"].label,"사진 1/10")
        app.buttons["communityComposeCancel"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5),"Reordering/removing a photo marks the draft dirty")
        app.alerts.buttons["계속 편집"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].exists)
        XCTAssertEqual(app.staticTexts["communityComposePhotoCount"].label,"사진 1/10","Continue editing retains the remaining photo")
        app.buttons["communityComposeCancel"].tap()
        app.alerts.buttons["버리기"].tap()
        XCTAssertFalse(app.staticTexts["communityComposePhotoCount"].exists,"Discard leaves the composer and its photo draft")
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)
    }

    func testCommunityPhotoPostPreviewDetailZoomAndDelete() {
        launchCommunity("C05",photoDraftFixture:true)
        app.buttons["communityPreviewButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityPreviewPhoto-review-photo-0"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["communityPreviewPhoto-review-photo-1"].exists)
        app.buttons["communityPublishButton"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        let post=app.staticTexts.matching(NSPredicate(format:"label == %@","사진 첨부 예시")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout:5))
        post.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityDetailPhotoOpen-0"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04-IMAGE"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityImageCount"].label,"1 / 2")
        app.buttons["communityImageNext"].tap()
        XCTAssertEqual(app.staticTexts["communityImageCount"].label,"2 / 2")
        app.buttons["communityImagePrevious"].tap()
        let image=app.images["communityImageZoom"]
        XCTAssertTrue(image.waitForExistence(timeout:5))
        image.pinch(withScale:1.8,velocity:1)
        XCTAssertNotEqual(image.value as? String,"확대 100%","C04 supports pinch zoom for attached photos")
        app.buttons["communityImageClose"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuDeletePost"].tap()
        app.buttons["communityPostDeleteConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label == %@","사진 첨부 예시")).firstMatch.exists)
    }

    func testCommunityPhotoEditDiscardPreservesPublishedFileAndSaveRemovesIt() {
        launchCommunity("C01",viewerID:"fixture-member-ga-on",photoPostFixture:true)
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap();app.buttons["communityMenuEditPost"].tap()
        app.buttons["communityDraftPhotoRemove-0"].tap()
        app.buttons["communityComposeCancel"].tap()
        XCTAssertTrue(app.alerts["변경사항을 버릴까요?"].waitForExistence(timeout:5))
        app.alerts.buttons["계속 편집"].tap()
        XCTAssertEqual(app.staticTexts["communityComposePhotoCount"].label,"사진 0/10")
        app.buttons["communityComposeCancel"].tap();app.alerts.buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["communityDetailPhotoOpen-1"].exists,"Discard retains the published file and attachment")

        app.buttons["communityPostMore"].tap();app.buttons["communityMenuEditPost"].tap()
        app.buttons["communityDraftPhotoRemove-0"].tap()
        app.buttons["communityPreviewButton"].tap()
        app.buttons["communityEditPostSave"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["communityDetailPhotoOpen-1"].exists,"Saving the edit releases the removed published file")
    }

    func testCommunityPostEditUsesC26ForChangedDraftAndSkipsItWhenUnchanged() {
        launchCommunity("C01",viewerID:"fixture-member-ga-on")
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityPostMore"].tap();app.buttons["communityMenuEditPost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        app.buttons["communityComposeCancel"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5),"An unchanged edit returns immediately")
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)

        app.buttons["communityPostMore"].tap();app.buttons["communityMenuEditPost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C05"].waitForExistence(timeout:5))
        replace("버릴 수정 초안",into:app.textFields["communityComposeTitle"])
        app.buttons["communityComposeCancel"].tap()
        let discard=app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout:5))
        discard.buttons["계속 편집"].tap()
        XCTAssertEqual(app.textFields["communityComposeTitle"].value as? String,"버릴 수정 초안","Continuing edit keeps only the draft changed")
        app.buttons["communityComposeCancel"].tap()
        app.alerts["변경사항을 버릴까요?"].buttons["버리기"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityDetailTitle"].label,"오늘은 강변을 따라 5 km","Discard leaves the saved post unchanged")
    }

    func testCommunityPostDeleteCleansProfileLikesHistoryAndLeavesSafeNotificationTarget() {
        app.launchArguments=["-wire-screen","C01","-wire-fixture","-wire-test-store-suite","community-delete-\(UUID().uuidString)","-wire-reset","-appearance","light","-wire-community-viewer","fixture-member-ga-on","-wire-community-notification-samples"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:10))
        app.buttons["communityHot-p1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:5))
        app.buttons["communityDetailLike"].tap()
        app.buttons["communityPostMore"].tap()
        XCTAssertTrue(app.buttons["communityMenuEditPost"].exists)
        app.buttons["communityMenuDeletePost"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityPostDeleteConfirmation"].waitForExistence(timeout:3))
        app.buttons["communityPostDeleteCancel"].tap()
        XCTAssertTrue(app.staticTexts["communityDetailTitle"].exists,"Cancel keeps the post intact")
        app.buttons["communityPostMore"].tap();app.buttons["communityMenuDeletePost"].tap()
        app.buttons["communityPostDeleteConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C01"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["communityPostTitle-p1"].exists,"Deleted posts disappear from the feed")

        app.buttons["community-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C08"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["communityProfilePostCount"].label,"1","The own-profile post list and count are derived from remaining posts")
        let profileSettings=app.buttons["communityOwnProfileSettings"]
        XCTAssertTrue(profileSettings.exists)
        profileSettings.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        app.buttons["communityLikedPostsRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityLikedPostsEmpty"].waitForExistence(timeout:5),"Deleting a post clears its like entry")
        app.buttons["뒤로"].tap()
        app.buttons["communityActivityRow"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityActivityEmpty"].waitForExistence(timeout:5),"Deleting a post clears its recent-view entry")
        app.buttons["뒤로"].tap();app.buttons["뒤로"].tap()
        app.buttons["communityNotificationBell"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityNotificationUnavailable-sample-post"].waitForExistence(timeout:5),"A stale notification remains visibly marked unavailable")
        app.buttons["communityNotification-sample-post"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["communityNotificationError"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["screen-C24"].exists,"A notification for a deleted post never routes to a stale detail")
    }

    func testCrewManagerCanDeleteCrewPostButCannotEditAnotherMembersPost() {
        app.launchArguments=["-wire-screen","C04","-wire-fixture","-wire-test-store-suite","community-crew-post-delete-\(UUID().uuidString)","-wire-reset","-appearance","light","-wire-community-crew-post"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["communityDetailTitle"].exists)
        app.buttons["communityPostMore"].tap()
        XCTAssertFalse(app.buttons["communityMenuEditPost"].exists,"A crew manager cannot edit another member's post")
        XCTAssertTrue(app.buttons["communityMenuDeletePost"].exists,"The crew owner can delete a crew post")
        app.buttons["communityMenuClose"].tap()
        XCTAssertTrue(app.buttons["communityDeleteComment-c1"].exists,"Crew managers can delete other members' comments on crew posts")
        app.buttons["communityDeleteComment-c1"].tap()
        XCTAssertTrue(app.staticTexts["communityCommentText-c1"].label.contains("삭제된 댓글"))
        XCTAssertTrue(app.descendants(matching:.any)["communityReplyQuote-c1-reply"].exists,"Deleting a parent comment preserves its reply")
        app.buttons["communityPostMore"].tap()
        app.buttons["communityMenuDeletePost"].tap()
        app.buttons["communityPostDeleteConfirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:5))
    }

    func testDirectCrewPostRouteHidesContentFromNonMembers() {
        app.launchArguments=["-wire-screen","C04","-wire-fixture","-wire-test-store-suite","community-crew-private-\(UUID().uuidString)","-wire-reset","-appearance","light","-wire-community-crew-post","-wire-community-not-member","-wire-community-viewer","fixture-member-early"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-C04"].waitForExistence(timeout:10))
        XCTAssertTrue(app.descendants(matching:.any)["communityPostUnavailable"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["communityDetailTitle"].exists,"A direct route never reveals a non-member's crew post")
        XCTAssertFalse(app.buttons["communityPostMore"].exists,"A non-member cannot use post actions through a direct route")
    }

    func testPaceChartReflowsOnCompactDarkViewport() {
        app.launchArguments=["-wire-screen","L05","-wire-fixture","-wire-reset","-wire-test-store-suite","mov.records.splits.compact.\(UUID().uuidString)","-wire-compact-review","-wire-reduced","-appearance","dark"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-L05"].waitForExistence(timeout:10))
        let chart=app.descendants(matching:.any)["구간 평균 페이스 그래프"].firstMatch
        XCTAssertTrue(chart.exists,app.debugDescription)
        XCTAssertLessThanOrEqual(chart.frame.maxX,app.frame.maxX+1,"The chart stays within the 320pt review viewport")
        XCTAssertTrue(app.staticTexts["구간별 기록"].exists)
        capture("L05-compact-dark-reduced")
    }
}

extension LaunchTests {
    func testAuthLogoutFailureCanRetryAndSuccessfulLogoutSurvivesRelaunch() {
        let suite = "mov.wireframe.test.auth-logout-success.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        app.launchArguments = ["-wire-screen", "T10", "-wire-fixture", "-wire-test-store-suite", suite,
            "-wire-reset", "-wire-auth-logout-fixture", "-wire-auth-logout-fail-once", "-wire-auth-logout-delay", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-T10"].waitForExistence(timeout: 15))
        let logout = app.buttons["authLogoutConfirm"]
        XCTAssertTrue(logout.waitForExistence(timeout: 5))
        tap("authLogoutConfirm")
        XCTAssertFalse(logout.isEnabled, "The confirm button is disabled while the request is pending")
        XCTAssertTrue(app.staticTexts["authLogoutFailure"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["screen-T10"].exists, "A 503 keeps the current session on T10")

        tap("authLogoutConfirm")
        XCTAssertTrue(app.descendants(matching: .any)["screen-A01"].waitForExistence(timeout: 12), app.debugDescription)

        app.terminate()
        app.launchArguments = ["-wire-fixture", "-wire-test-store-suite", suite, "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-A01"].waitForExistence(timeout: 15), "The saved logged-out state routes to A01 after relaunch")
    }

    func testAuthLogoutLateSuccessAfterLeavingConfirmationKeepsAccountLoggedIn() {
        let suite = "mov.wireframe.test.auth-logout-late.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        app.launchArguments = ["-wire-screen", "T10", "-wire-fixture", "-wire-test-store-suite", suite,
            "-wire-reset", "-wire-auth-logout-fixture", "-wire-auth-logout-delay", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-T10"].waitForExistence(timeout: 15))
        tap("authLogoutConfirm")
        XCTAssertFalse(app.buttons["authLogoutConfirm"].isEnabled)
        tap("계속 사용하기")
        XCTAssertTrue(app.descendants(matching: .any)["screen-T01"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["authLogoutConfirm"].exists)

        let lateResponseWindow = expectation(description: "Delayed fixture responds after screen navigation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { lateResponseWindow.fulfill() }
        wait(for: [lateResponseWindow], timeout: 7)
        XCTAssertTrue(app.descendants(matching: .any)["screen-T01"].exists, "The late response cannot navigate away from T01")

        app.terminate()
        app.launchArguments = ["-wire-fixture", "-wire-test-store-suite", suite, "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-H00"].waitForExistence(timeout: 15), "Leaving T10 before the response preserves the signed-in state on relaunch")
    }

    func testAuthLogoutResponseLostNeedsExplicitRetryAnd401SurvivesRelaunch() {
        let suite = "mov.wireframe.test.auth-logout-response-lost.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        app.launchArguments = ["-wire-screen", "T10", "-wire-fixture", "-wire-test-store-suite", suite,
            "-wire-reset", "-wire-auth-logout-fixture", "-wire-auth-logout-response-lost-then-401", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-T10"].waitForExistence(timeout: 15))

        tap("authLogoutConfirm")
        XCTAssertTrue(app.staticTexts["authLogoutFailure"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["screen-T10"].exists, "A lost response keeps the UI on T10 until an explicit retry")

        tap("authLogoutConfirm")
        XCTAssertTrue(app.descendants(matching: .any)["screen-A01"].waitForExistence(timeout: 12), app.debugDescription)

        app.terminate()
        app.launchArguments = ["-wire-fixture", "-wire-test-store-suite", suite, "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen-A01"].waitForExistence(timeout: 15), "The 401 retry persists the logged-out state after relaunch")
    }
}

@MainActor final class PasswordResetUITests:XCTestCase {
    private var app=XCUIApplication()
    override func setUp(){continueAfterFailure=false}
    private func launch(_ screen:String="A01",resendReady:Bool=false){
        app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite","mov.password-reset.ui.\(UUID().uuidString)","-wire-reset","-appearance","light"]
        if resendReady{app.launchArguments.append("-wire-password-reset-resend-ready")}
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-\(screen)"].waitForExistence(timeout:15),app.debugDescription)
    }
    private func tap(_ label:String){let button=app.buttons.matching(NSPredicate(format:"label == %@ OR identifier == %@",label,label)).firstMatch;XCTAssertTrue(button.waitForExistence(timeout:5),label);XCTAssertTrue(button.isHittable,label);button.tap()}
    private func tapPrimary(){let button=app.buttons["authPrimary"];if !button.exists || !button.isHittable{app.scrollViews.firstMatch.swipeUp()};XCTAssertTrue(button.waitForExistence(timeout:5),app.debugDescription);XCTAssertTrue(button.isHittable,app.debugDescription);button.tap()}
    private func dismissKeyboard(){let keys=app.keyboards.buttons;let done=keys.matching(NSPredicate(format:"label CONTAINS[c] %@ OR identifier CONTAINS[c] %@","done","done")).firstMatch;let ret=keys.matching(NSPredicate(format:"identifier == %@ OR label == %@","Return","return")).firstMatch;if done.exists{done.tap()}else if ret.exists{ret.tap()}}
    private func type(_ value:String,into element:XCUIElement){if !element.exists || !element.isHittable{app.scrollViews.firstMatch.swipeUp()};XCTAssertTrue(element.waitForExistence(timeout:5));element.tap();element.typeText(value)}
    private func replace(_ value:String,into element:XCUIElement){if !element.exists || !element.isHittable{app.scrollViews.firstMatch.swipeUp()};XCTAssertTrue(element.waitForExistence(timeout:5));element.tap();let old=element.value as? String ?? "";element.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+value)}
    func testPasswordResetCompleteFlowAndPasswordPolicy() {
        launch();tap("비밀번호 찾기")
        XCTAssertFalse(app.staticTexts["메일·서버 연결 없이 비밀번호 재설정 화면을 확인해요."].exists)
        XCTAssertFalse(app.staticTexts["실제 주소 대신 example.test 예시 주소를 써 주세요"].exists)
        tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A11"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["새 비밀번호를 설정해요"].exists)
        XCTAssertTrue(app.staticTexts["계속해서 새 비밀번호를 입력해 주세요."].exists)
        XCTAssertFalse(app.staticTexts["메일은 발송되지 않았어요."].exists)
        XCTAssertFalse(app.staticTexts["이 흐름은 UI 데모예요."].exists)
        tap("계속");XCTAssertTrue(app.descendants(matching:.any)["screen-A24"].waitForExistence(timeout:5))
        tap("fillDemoResetCode");XCTAssertTrue(app.descendants(matching:.any)["screen-A12"].waitForExistence(timeout:5))
        type("Invalid",into:app.secureTextFields["reset-new-password"]);tap("reset-new-password-reveal");dismissKeyboard();tapPrimary()
        XCTAssertTrue(app.staticTexts["8~20자의 영문과 숫자를 포함해 입력해 주세요."].waitForExistence(timeout:5))
        replace("MovDemo482619",into:app.textFields["reset-new-password"]);type("MovDemo482618",into:app.secureTextFields["reset-confirm-password"]);dismissKeyboard();tapPrimary()
        XCTAssertTrue(app.staticTexts["비밀번호가 서로 달라요."].waitForExistence(timeout:5))
        let fillPassword=app.buttons["가상 예시값 채우기"]
        if !fillPassword.isHittable{app.scrollViews.firstMatch.swipeUp()}
        tap("가상 예시값 채우기")
        dismissKeyboard()
        tapPrimary()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A13"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.staticTexts["이제 로그인해 주세요"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["로그인 화면으로 돌아가 계속해 주세요."].exists)
        XCTAssertFalse(app.staticTexts["실제 비밀번호는 바뀌지 않았어요."].exists)
        XCTAssertFalse(app.staticTexts["이 흐름은 UI 데모예요."].exists)
        tap("로그인으로");XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
    }
    func testResendRejectsOldCodeAndEmailChangeClearsProofAndBackStack() {
        launch("A24",resendReady:true)
        type("482619",into:app.textFields["resetCodeInput"])
        XCTAssertTrue(app.descendants(matching:.any)["screen-A25"].waitForExistence(timeout:5),"The signup OTP cannot authorize password reset")
        tap("requestNewResetCode");XCTAssertTrue(app.descendants(matching:.any)["screen-A28"].waitForExistence(timeout:5))
        type("700000",into:app.textFields["resetCodeInput"])
        XCTAssertTrue(app.descendants(matching:.any)["screen-A25"].waitForExistence(timeout:5),"The previous reset session code must fail after resend")
        tap("fillDemoResetCode");XCTAssertTrue(app.descendants(matching:.any)["screen-A12"].waitForExistence(timeout:5))
        tap("뒤로");XCTAssertTrue(app.descendants(matching:.any)["screen-A24"].waitForExistence(timeout:5))
        tap("changeResetEmail");XCTAssertTrue(app.descendants(matching:.any)["screen-A10"].waitForExistence(timeout:5))
        tapPrimary();XCTAssertTrue(app.staticTexts["이메일을 입력해 주세요."].waitForExistence(timeout:5))
        tap("취소");XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
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
        app.launchArguments=["-wire-screen","H04","-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-appearance","dark"]
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
    func testColdLaunchChoosesSavedAuthStateAndDoesNotReplayOnResume() {
        let suite="mov.launch.cold.\(UUID().uuidString)"
        let base=["-wire-fixture","-wire-test-store-suite",suite,"-appearance","light","-wire-splash-test-hold"]
        app.launchArguments=base
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-E02"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.staticTexts["splashWordmark"].exists)
        XCTAssertTrue(app.staticTexts["splashTagline"].exists)
        XCTAssertFalse(app.buttons["시작하기"].exists)
        let introShot=app.screenshot().image
        XCTAssertTrue(containsBrandGreen(in:introShot,rect:CGRect(origin:.zero,size:introShot.size)),"The cold E02 frame renders the original lime brand mark")
        capture("E02-cold-launch")
        XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:10),"A clean install has no saved login and routes to sign in after E02")
        XCTAssertTrue(app.textFields["auth-email"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","오늘의 달리기를")).firstMatch.exists)
        tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
        app.terminate()
        app.launchArguments=base
        app.launch()
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:10),"The saved login routes to home after a cold launch")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
        XCTAssertFalse(app.descendants(matching:.any)["screen-E02"].exists,"Returning to the suspended app does not replay the intro")

        tap("tab-4");tap("설정");tap("로그아웃");tap("로그아웃")
        XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
        app.terminate()
        app.launchArguments=base
        app.launch()
        XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:10),"A saved signed-out state routes back to sign in")
        app.terminate()
    }

    func testE02SmallViewportDarkLightAndReducedMotion() {
        for theme in ["light","dark"] {
            app.launchArguments=["-wire-screen","E02","-wire-fixture","-wire-test-store-suite","mov.launch.e02.\(theme).\(UUID().uuidString)","-wire-reset","-wire-compact-review","-wire-reduced","-appearance",theme]
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-E02"].waitForExistence(timeout:10),app.debugDescription)
            XCTAssertTrue(app.staticTexts["splashWordmark"].exists)
            XCTAssertTrue(app.staticTexts["splashTagline"].exists)
            XCTAssertFalse(app.buttons["시작하기"].exists)
            capture("E02-compact-\(theme)-reduced")
            app.terminate()
        }
    }

    func testNormalEntryAuthenticationNotificationsAndRunBothThemes() {
        for theme in ["light","dark"] {
            app.launchArguments=["-wire-fixture","-wire-reset","-appearance",theme]
            app.launch()
            XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:10))
            tap("tab-4");tap("설정");tap("로그아웃");tap("로그아웃")
            XCTAssertTrue(app.buttons["authPrimary"].waitForExistence(timeout:5))
            tap("authPrimary")
            XCTAssertTrue(app.staticTexts["이메일을 입력해 주세요."].exists)
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

    func testEmailCodeLockExpiryResendAndReentry() {
        open("A19")
        let code=app.textFields["emailOtpInput"]
        code.tap();code.typeText("111111")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A20"].waitForExistence(timeout:5))
        code.tap();code.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(app.staticTexts["otpDigit-5"].label," ","Deleting the last OTP digit clears the final slot")
        code.typeText("1")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A20"].waitForExistence(timeout:5))
        for attempt in 3...5 {
            code.tap();code.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:6)+"11111\(attempt)")
            XCTAssertTrue(app.descendants(matching:.any)[attempt==5 ? "screen-A22":"screen-A20"].waitForExistence(timeout:5))
        }
        XCTAssertFalse(code.isEnabled)
        capture("A22-actual-locked")
        app.terminate();open("A21")
        XCTAssertFalse(app.textFields["emailOtpInput"].isEnabled)
        let oldCode="482619"
        tap("requestNewEmailCode")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A23"].waitForExistence(timeout:5))
        capture("A23-actual-resent")
        code.tap();code.typeText(oldCode)
        XCTAssertTrue(app.descendants(matching:.any)["screen-A20"].waitForExistence(timeout:5),"The old code must be rejected after resend")
        tap("fillDemoEmailCode")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        app.terminate();open("A19");tap("emailReentry")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:5))
        app.buttons["authPrimary"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].exists,"Returning to signup clears challenge and credentials")
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
    func testA02ConsentReviewPartialRequiredAndCompletion() {
        openAuthFixture("A02",suite:"mov.wireframe.test.a02-consent-review")
        XCTAssertTrue(app.staticTexts["필수 항목을 확인하고 동의해 주세요.\n실제 법적 동의가 아닌 화면 검토입니다."].exists)
        let terms=app.descendants(matching:.any)["consent-row-terms"]
        let privacy=app.descendants(matching:.any)["consent-row-privacy"]
        XCTAssertEqual(terms.value as? String,"동의 안 함")
        XCTAssertEqual(privacy.value as? String,"동의 안 함")

        let links=app.buttons.matching(identifier:"내용 확인")
        links.element(boundBy:0).tap();XCTAssertTrue(app.descendants(matching:.any)["screen-A06"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["이용약관"].exists);tap("확인했어요")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        XCTAssertEqual(terms.value as? String,"동의함")
        XCTAssertEqual(privacy.value as? String,"동의 안 함")
        XCTAssertEqual(app.buttons["consentContinue"].label,"동의하고 계속")
        tap("consentContinue")
        XCTAssertTrue(app.staticTexts["필수 항목을 모두 확인해 주세요."].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].exists)

        app.buttons.matching(identifier:"내용 확인").element(boundBy:1).tap()
        XCTAssertTrue(app.staticTexts["개인정보 수집·이용"].waitForExistence(timeout:5));tap("확인했어요")
        XCTAssertEqual(privacy.value as? String,"동의함")
        XCTAssertEqual(app.buttons["consentContinue"].label,"모두 동의하고 계속")
        tap("consentContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5))
    }

    func testA02SelectAllAnimationBackStopAndReentry() {
        openAuthFixture("A01",suite:"mov.wireframe.test.a02-motion-cancel")
        tap("회원가입");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        tap("fillDemoEmailCode")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        tap("consentContinue")
        XCTAssertFalse(app.buttons["consentContinue"].isEnabled,"The CTA stays locked while both consent marks animate")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        XCTAssertEqual(app.descendants(matching:.any)["consent-row-terms"].value as? String,"동의함")
        XCTAssertEqual(app.descendants(matching:.any)["consent-row-privacy"].value as? String,"동의함")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A07"].waitForExistence(timeout:5))
        tap("가입 취소");XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
        tap("회원가입");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        tap("fillDemoEmailCode")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        XCTAssertEqual(app.descendants(matching:.any)["consent-row-terms"].value as? String,"동의 안 함")
        XCTAssertEqual(app.descendants(matching:.any)["consent-row-privacy"].value as? String,"동의 안 함")
    }

    func testA03NicknameDuplicateRequiredWeightAndLocalCompletion() {
        openAuthFixture("A02",suite:"mov.wireframe.test.a03-profile")
        tap("consentContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5))
        let nickname=app.textFields["signupNicknameInput"]
        XCTAssertTrue(nickname.waitForExistence(timeout:5))
        tap("signupContinue")
        XCTAssertTrue(app.staticTexts["닉네임을 입력해 주세요."].waitForExistence(timeout:5))
        replaceInput(nickname,"runmate");tap("signupContinue")
        XCTAssertTrue(app.staticTexts["검토용 예시 계정에서 사용 중인 닉네임이에요."].waitForExistence(timeout:5))
        replaceInput(nickname,"아침러너")
        let weight=app.textFields["signupWeightInput"]
        replaceInput(weight,"19.9");tap("signupContinue")
        XCTAssertTrue(app.staticTexts["20~300 kg 사이로 입력하거나 비워 두세요."].waitForExistence(timeout:5))
        replaceInput(weight,"");tap("signupContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A15"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["준비가 끝났어요.\n나의 첫 러닝을 시작해 보세요."].exists)
        XCTAssertEqual(app.buttons["signupCompletionStart"].label,"시작하기")
    }

    func testUserFlowSignupDoesNotAssumeGlobalNicknameAvailability() {
        openAuthFixture("A02",suite:"mov.wireframe.test.a03-user-flow-nickname",userFlow:true)
        tap("consentContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5))
        let nickname=app.textFields["signupNicknameInput"]
        replaceInput(nickname,"runmate")
        tap("signupContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A15"].waitForExistence(timeout:5),app.debugDescription)
        XCTAssertFalse(app.staticTexts["검토용 예시 계정에서 사용 중인 닉네임이에요."].exists)
    }

    func testReviewModeKeepsReservedFixtureNicknameFeedback() {
        openAuthFixture("A02",suite:"mov.wireframe.test.a03-review-fixture-nickname")
        tap("consentContinue")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].waitForExistence(timeout:5))
        replaceInput(app.textFields["signupNicknameInput"],"runmate")
        tap("signupContinue")
        XCTAssertTrue(app.staticTexts["검토용 예시 계정에서 사용 중인 닉네임이에요."].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["screen-A03"].exists)
    }

    func testLoginFailureScreenCopyAndRetry() {
        open("A04")
        XCTAssertTrue(app.staticTexts["로그인을 마치지\n못했어요"].exists)
        XCTAssertTrue(app.staticTexts["인증이 취소됐거나 연결이 끊겼어요.\n아직 새 계정을 만들지 않았어요."].exists)
        XCTAssertTrue(app.staticTexts["같은 로그인 수단으로 다시 시도하거나 다른 수단을 선택할 수 있어요."].exists)
        tap("authFailureRetry")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
    }

    func testRepeatedLoginFailureRetryAndBackReturnToLogin() {
        for _ in 0..<3 {
            open("A14",reset:false)
            tap("인증 오류 · 예시")
            XCTAssertTrue(app.descendants(matching:.any)["screen-A04"].waitForExistence(timeout:5))
            tap("authFailureRetry")
            XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))

            open("A14",reset:false)
            tap("인증 오류 · 예시")
            tap("뒤로")
            XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
        }
    }

    func testPasswordResetAndEmailMethodManagement() {
        open("A01");tap("비밀번호 찾기");tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A11"].waitForExistence(timeout:5))
        tap("계속");XCTAssertTrue(app.descendants(matching:.any)["screen-A24"].waitForExistence(timeout:5));tap("fillDemoResetCode");XCTAssertTrue(app.descendants(matching:.any)["screen-A12"].waitForExistence(timeout:5));tap("가상 예시값 채우기");tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A13"].waitForExistence(timeout:10),app.debugDescription)
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
            ("S05","홈으로","H00"),("L03","다시 불러오기","L01"),("C01","tab-4","M01"),
            ("T07","카카오로 로그인","H00"),("T10","계속 사용하기","T01"),("T12","로그인 화면 보기","A01"),
            ("T13","기기 데모 기록 삭제","L02"),("T14","설정으로 돌아가기","T01"),("T16","완료 응답 확인 · 예시","T12")
        ]
        for (screen,label,destination) in cases {
            open(screen)
            if screen == "C01" && label == "tab-4" { tap("community-tab-home") }
            tap(label)
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
        tap("가상 예시값 채우기")
        app.textFields["auth-email"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["가입 취소"].isHittable,"The A07 cancel action remains reachable with the keyboard open")
        tap("가입 취소")
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
func waitForGoalValue(_ element:XCUIElement,_ expected:String,file:StaticString=#filePath,line:UInt=#line) {
        let matched=waitForLayout({element.exists && (element.value as? String)==expected},timeout:5)
        XCTAssertTrue(matched,"Expected goal wheel value \(expected); actual: \(element.value ?? "<nil>")",file:file,line:line)
    }
    func selectGoal(_ identifier:String,file:StaticString=#filePath,line:UInt=#line) {
        let matches=app.buttons.matching(identifier:identifier)
        let tappable=waitForLayout({matches.allElementsBoundByIndex.contains(where:{$0.exists && $0.isHittable})},timeout:8)
        XCTAssertTrue(tappable,"Goal option must become hittable before selection: \(identifier)\n\(app.debugDescription)",file:file,line:line)
        guard tappable else{return}
        guard let button=matches.allElementsBoundByIndex.first(where:{$0.exists && $0.isHittable}) else{return}
        button.tap()
        let selected=waitForLayout({matches.allElementsBoundByIndex.contains(where:{$0.isSelected})},timeout:5)
        XCTAssertTrue(selected,"Goal option did not enter selected state: \(identifier)\n\(app.debugDescription)",file:file,line:line)
    }

    func testSingleGoalWheelBothThemes() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","H03","-wire-fixture","-wire-reset","-wire-capture-viewport","-appearance",theme];app.launch()
            XCTAssertTrue(app.buttons["goal-distance"].waitForExistence(timeout:10));selectGoal("goal-distance")
            let distance=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
            XCTAssertTrue(distance.waitForExistence(timeout:5));waitForGoalValue(distance,"5 km");capture("H03-distance-"+theme)
            distance.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()
            waitForGoalValue(distance,"5.5 km")
            selectGoal("goal-time");let time=app.descendants(matching:.any)["timeGoalPicker"].firstMatch
            XCTAssertTrue(time.waitForExistence(timeout:5));waitForGoalValue(time,"30분")
            for expected in ["40분","50분","1시간"] {
                time.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()
                waitForGoalValue(time,expected)
            }
            capture("H03-time-"+theme)
            selectGoal("goal-none")
            XCTAssertTrue(waitForLayout({!time.exists},timeout:5),"The selected no-goal state removes its wheel")
            capture("H03-none-"+theme)
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
    func testGoalWheelSelectionsPersistAndReturnToRunSetup() {
        open("H01")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","목표 설정")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H03"].waitForExistence(timeout:5))
        let distanceChoice=app.buttons["goal-distance"]
        let timeChoice=app.buttons["goal-time"]
        selectGoal("goal-distance")
        let distance=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout:5))
        waitForGoalValue(distance,"5 km")
        distance.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()
        waitForGoalValue(distance,"5.5 km")

        selectGoal("goal-time")
        let time=app.descendants(matching:.any)["timeGoalPicker"].firstMatch
        XCTAssertTrue(time.waitForExistence(timeout:5))
        waitForGoalValue(time,"30분")
        for expected in ["40분","50분","1시간"] {
            time.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.92)).tap()
            waitForGoalValue(time,expected)
        }

        selectGoal("goal-distance")
        waitForGoalValue(distance,"5.5 km")
        selectGoal("goal-time")
        waitForGoalValue(time,"1시간")
        capture("H03-goal-values-preserved-by-type")

        app.buttons["saveGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H01"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","1시간 달리기")).firstMatch.exists)
        app.terminate()
        open("H01",reset:false)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","목표 변경")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H03"].waitForExistence(timeout:5))
        let savedDistance=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
        XCTAssertTrue(app.buttons["goal-distance"].waitForExistence(timeout:5))
        selectGoal("goal-distance")
        XCTAssertTrue(savedDistance.waitForExistence(timeout:5))
        waitForGoalValue(savedDistance,"5.5 km")
    }

    func testGoalWheelDragAndBounds() {
        open("H03");selectGoal("goal-distance")
        let wheel=app.descendants(matching:.any)["distanceGoalPicker"].firstMatch
        func drag(_ element:XCUIElement,_ up:Bool,_ speed:XCUIGestureVelocity){
            let a=element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.92:0.08))
            let b=element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.08:0.92))
            a.press(forDuration:0.05,thenDragTo:b,withVelocity:speed,thenHoldForDuration:0)
        }
        drag(wheel,true,.slow)
        XCTAssertTrue(waitForLayout({(wheel.value as? String) != "5 km"},timeout:5),"Dragging changes the selected goal")
        drag(wheel,true,.fast);capture("H03-fast-flick")
        drag(wheel,false,.fast);capture("H03-reverse")
        for _ in 0..<10{drag(wheel,false,.fast)}
        waitForGoalValue(wheel,"1 km")
        drag(wheel,false,.slow);waitForGoalValue(wheel,"1 km")
        selectGoal("goal-time");let time=app.descendants(matching:.any)["timeGoalPicker"].firstMatch
        for _ in 0..<3{drag(time,false,.fast)}
        waitForGoalValue(time,"10분")
        for _ in 0..<36{drag(time,true,.fast)}
        waitForGoalValue(time,"6시간");capture("H03-time-upper-bound")
        drag(time,true,.slow);waitForGoalValue(time,"6시간")
        selectGoal("goal-distance");waitForGoalValue(wheel,"1 km")
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

    func testInjectedProgressGoalAndDailySummaryStayOnTheRemoteReadPath() {
        let suite="mov.wireframe.test.remote-progress-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",suite,
            "-wire-reset","-wire-capture-viewport","-wire-progress-goals-fixture","-wire-home-weekly-example","both","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        let distance=app.staticTexts["homeSummaryActual-distance"]
        XCTAssertTrue(distance.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(distance.label,"12.40 km","The remote amount remains distinct from the local 12.00 km fixture")
        XCTAssertEqual(app.staticTexts["homeSummaryActual-time"].label,"1시간 5분")
        XCTAssertFalse(app.buttons["homeEditWeeklyGoal"].isEnabled,"Remote goal state is read only")
        XCTAssertTrue(app.staticTexts["기기 저장 기록"].exists,"Recent device records are labeled as local while remote metrics are shown")

        app.buttons["homeWeeklySummary"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H07"].waitForExistence(timeout:8))
        let periodDistance=app.staticTexts["periodDistanceValue"]
        XCTAssertTrue(periodDistance.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(periodDistance.label,"12.40 km","The daily endpoint range must sum to the weekly goal response")
        let validSummary=app.descendants(matching:.any)["periodValidSummary"]
        XCTAssertTrue(validSummary.exists,app.debugDescription)
        app.terminate()
        UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
    }

    func testWeeklyGoalWriteFixturesCoverBothSingleAxesUnsetAndQuerySync() {
        let suite="mov.wireframe.test.weekly-goal-write-\(UUID().uuidString)"
        defer { app.terminate();UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",suite,
            "-wire-reset","-wire-capture-viewport","-wire-progress-goals-fixture","-wire-weekly-goal-write-fixture","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        let edit=app.buttons["homeEditWeeklyGoal"]
        XCTAssertTrue(edit.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(edit.isEnabled,"The injected writer enables the existing weekly-goal control")

        edit.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택됨")
        app.buttons["weeklyTimeToggle"].tap()
        app.buttons["saveWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-time"].exists,"The synced query reflects a distance-only save")

        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택 안 됨")
        app.buttons["weeklyDistanceToggle"].tap()
        app.buttons["weeklyTimeToggle"].tap()
        app.buttons["saveWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-time"].exists,"The synced query reflects a time-only save")

        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        app.buttons["주간 목표 삭제"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H10"].waitForExistence(timeout:8))
        app.buttons["주간 목표 삭제"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.staticTexts["아직 주간 목표가 없어요"].exists,"The synced query represents both axes as unset")
    }

    func testWeeklyGoalWriteFailureKeepsThePreviousRemoteGoalVisible() {
        let suite="mov.wireframe.test.weekly-goal-write-failure-\(UUID().uuidString)"
        defer { app.terminate();UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",suite,
            "-wire-reset","-wire-progress-goals-fixture","-wire-weekly-goal-write-fixture","-wire-weekly-goal-write-fail","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        app.buttons["weeklyTimeToggle"].tap()
        app.buttons["saveWeeklyGoal"].tap()
        XCTAssertTrue(app.staticTexts["주간 목표를 저장하지 못했어요. 다시 시도해 주세요."].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].exists,"A failed PUT must keep the editor open")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8))
        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택됨","A failed PUT must not replace the previously loaded axes")
    }

    func testWeeklyGoalConflictRefreshRetriesAndPreservesTheDraftUntilConfirmedSave() {
        let suite="mov.wireframe.test.weekly-goal-conflict-refresh-\(UUID().uuidString)"
        defer { app.terminate();UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite) }
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",suite,
            "-wire-reset","-wire-progress-goals-fixture","-wire-weekly-goal-write-fixture",
            "-wire-weekly-goal-write-conflict","-wire-weekly-goal-conflict-refresh-fail-once","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        app.buttons["homeEditWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H04"].waitForExistence(timeout:8))
        app.buttons["weeklyTimeToggle"].tap()
        app.buttons["saveWeeklyGoal"].tap()

        let reload=app.buttons["refreshWeeklyGoalAfterConflict"]
        XCTAssertTrue(reload.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertFalse(app.buttons["saveWeeklyGoal"].isEnabled,"A stale version cannot be resubmitted")
        reload.tap()
        let retry=app.buttons["retryWeeklyGoalConflictRefresh"]
        XCTAssertTrue(retry.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택 안 됨","A failed refresh must retain the user's draft")
        XCTAssertFalse(app.buttons["saveWeeklyGoal"].isEnabled)

        retry.tap()
        let refreshed=app.descendants(matching:.any)["weeklyGoalConflictRefreshedNotice"]
        XCTAssertTrue(refreshed.waitForExistence(timeout:8),app.debugDescription)
        XCTAssertEqual(app.buttons["weeklyDistanceToggle"].value as? String,"선택됨")
        XCTAssertEqual(app.buttons["weeklyTimeToggle"].value as? String,"선택 안 됨","A successful refresh must not replace the draft with the other device's goals")
        XCTAssertTrue(app.staticTexts["weeklyGoalConflictLatestStatus"].label.contains("40 km"),app.debugDescription)
        XCTAssertTrue(app.buttons["saveWeeklyGoal"].isEnabled,"The user may explicitly confirm the retained draft against the refreshed version")

        app.buttons["saveWeeklyGoal"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertTrue(app.descendants(matching:.any)["homeRing-distance"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-time"].exists,"Only the explicitly confirmed distance-only draft is saved")
        let finalRingValue=app.descendants(matching:.any)["homeRing-distance"].value as? String ?? ""
        XCTAssertTrue(finalRingValue.contains("20 km"),"The final query reflects the user's retained 20 km draft")
    }

    func testInjectedProgressFailureDoesNotFallBackToLocalWeeklyOrDailyMetrics() {
        let overviewSuite="mov.wireframe.test.remote-progress-fail-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","H00","-wire-fixture","-wire-test-store-suite",overviewSuite,
            "-wire-reset","-wire-progress-goals-fixture","-wire-progress-goals-fail","-wire-home-weekly-example","both","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:15))
        XCTAssertTrue(app.descendants(matching:.any)["remoteHomeProgressFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertFalse(app.descendants(matching:.any)["homeRing-distance"].exists,"A failed server read must not be replaced by local ring totals")
        XCTAssertTrue(app.staticTexts["기기 저장 기록"].exists)
        app.terminate()
        UserDefaults(suiteName:overviewSuite)?.removePersistentDomain(forName:overviewSuite)

        let dailySuite="mov.wireframe.test.remote-daily-fail-\(UUID().uuidString)"
        app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-test-store-suite",dailySuite,
            "-wire-reset","-wire-progress-goals-fixture","-wire-progress-daily-fail","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H07"].waitForExistence(timeout:15))
        XCTAssertTrue(app.descendants(matching:.any)["remoteDailyProgressFailure"].waitForExistence(timeout:8),app.debugDescription)
        XCTAssertFalse(app.staticTexts["periodDistanceValue"].exists,"A failed daily read must not display local period totals")
        app.terminate()
        UserDefaults(suiteName:dailySuite)?.removePersistentDomain(forName:dailySuite)
    }

    func testReview52StatisticsEmptyAndOverGoalMatchSourcePresentation() {
        for (screen,expectedDistance) in [("H08","0.00 km"),("H09","23.00 km")] {
            app.launchArguments=["-wire-screen",screen,"-wire-fixture","-wire-test-store-suite","mov.wireframe.test.h08-h09","-wire-reset","-wire-capture-viewport","-wire-review-size","-wire-reduced","-appearance","light"]
            app.launch()
            XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))

            let distance=app.staticTexts["periodDistanceValue"]
            XCTAssertTrue(distance.waitForExistence(timeout:5))
            XCTAssertEqual(distance.label,expectedDistance)
            if screen == "H09" {
                let percent=app.staticTexts["goal-percent-거리 목표"]
                let overage=app.staticTexts["goal-overage-거리 목표"]
                XCTAssertTrue(percent.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertEqual(percent.label,"115%")
                XCTAssertTrue(overage.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertEqual(overage.label,"3 km 더 달렸어요")
                let progress=app.descendants(matching:.any)["goal-progress-거리 목표"]
                XCTAssertTrue(progress.waitForExistence(timeout:5),app.debugDescription)
                XCTAssertEqual(progress.label,"거리 목표 진행률")
                XCTAssertEqual(progress.value as? String,"100%","The H09 visual fill and accessible value cap at the source's 100% limit")
            }
            let dateRange=app.staticTexts["statisticsDateRange"]
            XCTAssertTrue(dateRange.waitForExistence(timeout:5))
            XCTAssertEqual(dateRange.label,"가상 기준일은 2026년 10월 1일이에요.\n이번 주는 9월 28일~10월 4일 기록이에요.")
            XCTAssertGreaterThanOrEqual(dateRange.frame.height,24)
            capture(screen+"-statistics-source-layout-390x790")
            app.terminate()
        }
    }

    func testSummaryMovingPeriodAndCalendarPreservation() {
        for theme in ["light","dark"]{
            app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-wire-capture-viewport","-appearance",theme];app.launch()
            let week=app.buttons["summary-week"],month=app.buttons["summary-month"]
            XCTAssertTrue(week.waitForExistence(timeout:10));let frame=week.frame
            XCTAssertEqual(frame.width,165,accuracy:1,"The period selector spans the 342pt source content width with a 4pt gap and 4pt outer inset")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","4.82")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts["30:08"].exists)
            month.tap();XCTAssertTrue(waitForLayout({month.isSelected}));XCTAssertEqual(week.frame,frame)
            XCTAssertTrue(app.staticTexts["월간 유효 거리"].exists)
            let calendarMonth=app.staticTexts["calendarMonthTitle"]
            XCTAssertTrue(calendarMonth.waitForExistence(timeout:5));let selectedMonth=calendarMonth.label
            let pageScroll=app.scrollViews.firstMatch
            let previousMonthButton=app.buttons["이전 달"]
            XCTAssertTrue(waitHittable(previousMonthButton,timeout:5))
            XCTAssertTrue(pageScroll.frame.contains(CGPoint(x:previousMonthButton.frame.midX,y:previousMonthButton.frame.midY)))
            XCTAssertGreaterThanOrEqual(previousMonthButton.frame.width,40)
            previousMonthButton.tap()
            XCTAssertTrue(waitForLayout({calendarMonth.exists && calendarMonth.label != selectedMonth && calendarMonth.label == "2026년 9월"},timeout:5))
            XCTAssertTrue(app.staticTexts["월간 유효 거리"].exists);capture("H07-month-"+theme)
            XCTAssertTrue(app.staticTexts["9월 1일 달렸어요"].exists)
            XCTAssertTrue(app.otherElements["calendarRunDayLegend"].exists || app.staticTexts["달린 날"].exists)
            XCTAssertTrue(app.staticTexts["날짜를 선택하면 그날의 기록을 볼 수 있어요"].exists)
            let populatedMonth=calendarMonth.label
            XCTAssertTrue(waitHittable(previousMonthButton,timeout:5))
            XCTAssertTrue(pageScroll.frame.contains(CGPoint(x:previousMonthButton.frame.midX,y:previousMonthButton.frame.midY)))
            previousMonthButton.tap()
            XCTAssertTrue(waitForLayout({calendarMonth.exists && calendarMonth.label != populatedMonth && calendarMonth.label == "2026년 8월"},timeout:5))
            XCTAssertEqual(calendarMonth.label,"2026년 8월")
            XCTAssertTrue(app.staticTexts["8월 0일 달렸어요"].exists)
            app.swipeUp()
            capture("H07-empty-month-"+theme)
            let emptyMonth=app.descendants(matching:.any)["calendarEmptyMonthMessage"]
            XCTAssertTrue(emptyMonth.waitForExistence(timeout:5))
            XCTAssertEqual(emptyMonth.label,"이 달에 저장된 러닝 기록이 없어요")
            let nextMonthButton=app.buttons["다음 달"]
            var previousCalendarY=calendarMonth.frame.minY
            for _ in 0..<5 where !nextMonthButton.isHittable {
                pageScroll.swipeDown()
                let currentCalendarY=calendarMonth.frame.minY
                XCTAssertGreaterThan(currentCalendarY,previousCalendarY,"The statistics page must return to the month navigation hit area")
                previousCalendarY=currentCalendarY
            }
            XCTAssertTrue(nextMonthButton.isHittable)
            XCTAssertTrue(pageScroll.frame.contains(CGPoint(x:nextMonthButton.frame.midX,y:nextMonthButton.frame.midY)))
            nextMonthButton.tap()
            XCTAssertTrue(waitForLayout({calendarMonth.exists && calendarMonth.label == "2026년 9월"},timeout:5))
            let recordedDay=app.buttons.matching(NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@","9월 29일","러닝 기록 있음")).firstMatch
            XCTAssertTrue(recordedDay.waitForExistence(timeout:5));recordedDay.tap()
            let selectedTitle=app.staticTexts["calendarSelectedDayTitle"],selectedCount=app.staticTexts["calendarSelectedDayCount"]
            XCTAssertTrue(pageScroll.exists)
            var detailsCalendarY=calendarMonth.frame.minY
            for _ in 0..<5 where !selectedTitle.exists || !selectedTitle.isHittable {
                pageScroll.swipeUp()
                let currentCalendarY=calendarMonth.frame.minY
                XCTAssertLessThan(currentCalendarY,detailsCalendarY,"The statistics page must scroll toward selected-day details")
                detailsCalendarY=currentCalendarY
            }
            XCTAssertTrue(selectedTitle.waitForExistence(timeout:5))
            XCTAssertTrue(selectedTitle.isHittable,"The selected-day title should be in the visible scroll viewport")
            XCTAssertTrue(selectedCount.isHittable,"The selected-day count should be in the visible scroll viewport")
            XCTAssertEqual(selectedTitle.label,"9월 29일 기록")
            XCTAssertEqual(selectedCount.label,"1회")
            XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"calendarSelectedDayTitle").count,1)
            XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"calendarSelectedDayCount").count,1)
            app.terminate()
        }
    }

    func testSummaryPeriodControlRepeatedTransitionsFromFreshFixture() {
        for theme in ["light","dark"] {
            app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-wire-capture-viewport","-appearance",theme];app.launch()
            let scroll=app.scrollViews.firstMatch
            let week=app.buttons["summary-week"],month=app.buttons["summary-month"]
            XCTAssertTrue(waitHittable(week,timeout:10));XCTAssertTrue(week.isSelected);XCTAssertFalse(month.isSelected)
            let originalWeekFrame=week.frame
            for (selected,unselected) in [(month,week),(week,month),(month,week),(week,month),(month,week),(week,month)] {
                XCTAssertTrue(waitHittable(selected,timeout:5))
                let hitFrame=selected.frame
                XCTAssertTrue(scroll.frame.contains(CGPoint(x:hitFrame.midX,y:hitFrame.midY)),"Period button hit target must stay inside the visible statistics viewport")
                XCTAssertGreaterThanOrEqual(hitFrame.height,44)
                selected.tap()
                XCTAssertTrue(waitForLayout({selected.isSelected && !unselected.isSelected},timeout:5),"Selected period accessibility state must settle before the next tap")
                XCTAssertTrue(selected.isHittable)
                XCTAssertEqual(selected.frame,hitFrame)
                XCTAssertEqual(week.frame,originalWeekFrame)
            }
            month.tap()
            XCTAssertTrue(waitForLayout({month.isSelected && !week.isSelected},timeout:5))
            let monthTitle=app.staticTexts["calendarMonthTitle"]
            XCTAssertTrue(monthTitle.waitForExistence(timeout:5))
            let preservedMonth=monthTitle.label
            week.tap()
            XCTAssertTrue(waitForLayout({week.isSelected && !month.isSelected},timeout:5))
            month.tap()
            XCTAssertTrue(waitForLayout({month.isSelected && !week.isSelected && monthTitle.exists},timeout:5))
            XCTAssertEqual(monthTitle.label,preservedMonth)
            capture("H07-period-repeated-"+theme)
            app.terminate()
        }

        app.launchArguments=["-wire-screen","H07","-wire-fixture","-wire-reset","-wire-reduced","-appearance","light"];app.launch()
        let week=app.buttons["summary-week"],month=app.buttons["summary-month"]
        XCTAssertTrue(waitHittable(month,timeout:10));month.tap()
        XCTAssertTrue(waitForLayout({month.isSelected && !week.isSelected},timeout:5))
        week.tap();XCTAssertTrue(waitForLayout({week.isSelected && !month.isSelected},timeout:5))
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
        app.launchArguments=["-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-wire-reset","-wire-user-flow","-wire-screen",screen]
        if compact{app.launchArguments.append("-wire-compact-review")}
        if captureViewport{app.launchArguments.append("-wire-capture-viewport")}
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-"+screen].waitForExistence(timeout:15))
    }
    func fillUserAuth(confirm:Bool=false,current:Bool=false){
        if app.textFields["auth-email"].exists{let f=app.textFields["auth-email"];f.tap();f.typeText("runner@example.test");XCTAssertEqual(f.value as? String,"runner@example.test")}
        func enterPassword(_ identifier:String){let secure=app.secureTextFields[identifier];let reveal=app.buttons["auth-reveal-\(identifier)"];if secure.exists && reveal.exists{reveal.tap()};let field=app.textFields[identifier].exists ? app.textFields[identifier]:secure;replaceInput(field,"MovReview482619");if app.textFields[identifier].exists{XCTAssertEqual(field.value as? String,"MovReview482619","Entered value for \(identifier)")}}
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
    func assertRunFrameAfterLayout(_ element:XCUIElement,_ expected:CGRect,file:StaticString=#filePath,line:UInt=#line){
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
            let actual=element.frame
            return abs(actual.minX-expected.minX)<=0.5 && abs(actual.minY-expected.minY)<=0.5 &&
                abs(actual.width-expected.width)<=0.5 && abs(actual.height-expected.height)<=0.5
        },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:2),.completed,"Run panel frame did not return to its fixed layout: actual=\(element.frame), expected=\(expected)",file:file,line:line)
        assertRunFrame(element.frame,expected,file:file,line:line)
    }
    func testFixedRunPanelUserFlow(){
        for compact in [false,true]{
            userOpen("R02",compact:compact)
            let handle=app.buttons["panelHandle"],primary=app.buttons["pauseRun"],secondary=app.buttons["runDetails"]
            let top=handle.frame,first=primary.frame,second=secondary.frame
            XCTAssertTrue(primary.isHittable);XCTAssertTrue(secondary.isHittable)
            for i in 0..<3{
                tap("pauseRun");XCTAssertTrue(waitHittable(app.buttons["resumeRun"]),app.debugDescription);XCTAssertTrue(waitHittable(app.buttons["finishRun"]),app.debugDescription);assertRunFrameAfterLayout(app.buttons["resumeRun"],first);assertRunFrameAfterLayout(app.buttons["finishRun"],second);assertRunFrameAfterLayout(handle,top)
                tap("finishRun");if i==0{capture(compact ? "Run-finish-320x568":"Run-finish")};assertRunFrameAfterLayout(app.buttons["cancelFinish"],first);assertRunFrameAfterLayout(app.buttons["saveRun"],second);assertRunFrameAfterLayout(handle,top)
                XCTAssertTrue(app.buttons["saveRun"].isHittable)
                tap("cancelFinish");assertRunFrameAfterLayout(app.buttons["resumeRun"],first);tap("resumeRun");assertRunFrameAfterLayout(primary,first)
            }
            let point=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:first.midX,dy:top.maxY+70))
            point.press(forDuration:0.05,thenDragTo:point.withOffset(CGVector(dx:0,dy:-45)))
            assertRunFrameAfterLayout(primary,first);assertRunFrameAfterLayout(handle,top)
            handle.tap();XCTAssertEqual(handle.label,"러닝 정보 펼치기");tap("pauseRun");tap("resumeRun");handle.tap()
            let restored=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in abs(handle.frame.minY-top.minY)<0.5 && abs(primary.frame.minY-first.minY)<0.5},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:3),.completed)
            assertRunFrame(handle.frame,top);assertRunFrame(primary.frame,first);capture(compact ? "Run-active-320x568":"Run-active")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","확인된 유효 구간만")).firstMatch.exists)
        }
    }
    func testUserLoginSignupAndPasswordResetCancelBack(){
        userOpen("A01");XCTAssertFalse(app.buttons["가상 예시값 채우기"].exists);XCTAssertTrue(app.buttons["로그인"].exists)
        fillUserAuth();tap("authPrimary");XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5))
        userOpen("A01");tap("회원가입");fillUserAuth(confirm:true);tap("authPrimary")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5),app.debugDescription)
        let otp=app.descendants(matching:.any)["emailOtpInput"];XCTAssertTrue(otp.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["fillDemoEmailCode"].exists)
        otp.tap();otp.typeText("000000");XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","코드가 일치하지")).firstMatch.waitForExistence(timeout:5))
        otp.tap();otp.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:6)+"482619");XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5),"Pasting all six digits verifies and opens consent automatically")
        tap("모두 동의하고 계속");let nickname=app.textFields.firstMatch;XCTAssertTrue(nickname.waitForExistence(timeout:5));nickname.tap();nickname.typeText("검수러너");tap("계속")
        XCTAssertTrue(app.buttons["시작하기"].waitForExistence(timeout:5));tap("시작하기");XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout:5));capture("User-signup-home")
        userOpen("A01");tap("비밀번호 찾기")
        let resetEmail=app.textFields["reset-email"]
        XCTAssertTrue(resetEmail.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["fillDemoResetCode"].exists,"A normal user flow does not expose fixture-only reset codes")
        tap("취소")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A01"].waitForExistence(timeout:5))
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
    func testSignupOtpAutoVerifyAndConsentReviewNavigation() {
        openAuthFixture("A01",suite:"mov.auth.otp.signup-journey")
        app.buttons["회원가입"].tap()
        XCTAssertFalse(app.buttons["auth-reveal-auth-password"].exists)
        app.buttons["가상 예시값 채우기"].tap()
        XCTAssertTrue(app.buttons["auth-reveal-auth-password"].exists)
        app.buttons["authPrimary"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["verifyEmailCode"].exists)
        XCTAssertTrue(app.buttons["이메일 다시 입력"].exists)
        XCTAssertFalse(app.buttons["가입 취소"].exists)
        let otp=app.textFields["emailOtpInput"]
        XCTAssertFalse(app.buttons["verifyEmailCode"].isEnabled)
        otp.tap();otp.typeText("482619")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))

        app.buttons["내용 확인"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A06"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["이용약관"].exists)
        app.buttons["consentReviewed"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))
        XCTAssertEqual(app.otherElements["consent-row-terms"].value as? String,"동의함")
        XCTAssertEqual(app.otherElements["consent-row-privacy"].value as? String,"동의 안 함")
    }

    func testOtpResendAndExpiryFixtureTransitions() {
        app.launchArguments=["-wire-screen","A19","-wire-fixture","-wire-otp-resend-ready","-wire-test-store-suite","mov.auth.otp.resend","-wire-reset","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A19"].waitForExistence(timeout:15))
        let resend=app.buttons["requestNewEmailCode"]
        XCTAssertTrue(resend.isEnabled)
        resend.tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A23"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["publicDemoEmailCode"].exists)
        let otp=app.textFields["emailOtpInput"]
        otp.tap();otp.typeText("482619")
        XCTAssertTrue(app.descendants(matching:.any)["screen-A20"].waitForExistence(timeout:5),"The old code is invalid after resend")
        app.buttons["fillDemoEmailCode"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A02"].waitForExistence(timeout:5))

        app.launchArguments=["-wire-screen","A21","-wire-fixture","-wire-test-store-suite","mov.auth.otp.expired","-wire-reset","-appearance","light"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-A21"].waitForExistence(timeout:15))
        XCTAssertFalse(app.textFields["emailOtpInput"].isEnabled)
        XCTAssertTrue(app.buttons["requestNewEmailCode"].isEnabled)
    }

    func testReview52A01LayoutAndPasswordControls() {
        userOpen("A01",captureViewport:true)
        XCTAssertEqual(app.secureTextFields["auth-password"].placeholderValue,"8자 이상 입력")
        XCTAssertFalse(app.buttons["auth-reveal-auth-password"].exists)
        let gap=app.secureTextFields["auth-password"].frame.minY-app.textFields["auth-email"].frame.maxY
        XCTAssertGreaterThan(gap,90)
        XCTAssertLessThan(gap,110)
    }

    func testReview52H00ReferenceWeekShowsSeededGoalProgress() {
        app.launchArguments=["-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-wire-reset","-wire-screen","H00","-wire-capture-viewport","-wire-fixed-reference-week","-appearance","light"]
        app.launch()
        let dateHeader=app.staticTexts["homeWeekLabel"]
        XCTAssertTrue(dateHeader.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertEqual(dateHeader.label,"9.28 — 10.4 · 가상 예시","The fixed Oct 1 fixture shows its ISO Monday–Sunday reference week")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","4.82")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["24%"].exists)
        XCTAssertEqual(app.staticTexts["homeRecentMetadata"].label,"2026.09.29 · 07:12 시작 · 30:08 유효 러닝 · 예시")
        capture("H00-fixed-reference-week")
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
    func replaceInput(_ field:XCUIElement,_ text:String){
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap()
        let strongPasswordSuggestion=app.buttons["GenerateStrongPasswordButton"]
        if strongPasswordSuggestion.waitForExistence(timeout:0.5){
            let dismissStrongPasswordSuggestion=app.buttons["xmark"]
            XCTAssertTrue(dismissStrongPasswordSuggestion.waitForExistence(timeout:2),app.debugDescription)
            dismissStrongPasswordSuggestion.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5),app.debugDescription)
        let old=field.value as? String ?? "";field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+text)
    }
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
        app.terminate();app.launchArguments=["-wire-screen","POINTS","-wire-fixture","-wire-test-store-suite",isolatedStoreSuite,"-wire-user-flow","-appearance","light"];app.launch();XCTAssertTrue(app.staticTexts["pointBalance"].waitForExistence(timeout:10));XCTAssertEqual(app.staticTexts["pointBalance"].label,"850","Purchase state persists only in the fixture device store")
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
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H00"].waitForExistence(timeout:5))
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["screen-H01"].waitForExistence(timeout:5))
        XCTAssertTrue(waitHittable(app.buttons["openRecords"],timeout:5),app.debugDescription)
        app.buttons["openRecords"].tap();app.buttons.matching(NSPredicate(format:"label CONTAINS %@","제목만 수정")).firstMatch.tap();XCTAssertEqual(app.staticTexts["recordTitle"].label,"제목만 수정")
        app.swipeUp();tap("editMemo");replaceInput(memo,String(repeating:"나",count:301));XCTAssertFalse(app.buttons["finishMemo"].isEnabled);XCTAssertEqual(app.staticTexts["inlineMemoCount"].label,"301/300")
        replaceInput(memo,"");tap("finishMemo");XCTAssertEqual(app.staticTexts["recordMemo"].label,"러닝의 느낌을 남겨 보세요");tap("editMemo");replaceInput(memo,"저장하지 않을 메모");tap("뒤로")
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","제목만 수정")).firstMatch.tap();app.swipeUp();XCTAssertEqual(app.staticTexts["recordMemo"].label,"러닝의 느낌을 남겨 보세요");capture("Memo-empty-restored")
    }
    func testCompletionReflowsOnce(){
        for screen in ["S01","S05"]{
            app.launchArguments=["-wire-fixture","-wire-reset","-wire-user-flow","-wire-screen",screen]
            if app.state != .notRunning { app.terminate() }
            app.launch();XCTAssertTrue(app.buttons["기록 보기"].waitForExistence(timeout:5))
            let feedback=app.descendants(matching:.any)["saveCompletionFeedback"].firstMatch
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in !feedback.exists},object:nil)],timeout:5),.completed)
            let heading=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",screen=="S01" ? "잘 달렸어요":"구간이 없어요")).firstMatch
            XCTAssertLessThan(heading.frame.minY,260);let settled=heading.frame
            app.swipeUp();capture(screen+"-calories-no-divider");app.swipeDown();capture(screen+"-reflowed")
            tap("기록 보기");tap("뒤로");XCTAssertFalse(feedback.exists)
            XCTAssertTrue(waitForLayout({
                let frame=heading.frame
                return abs(frame.minX-settled.minX)<=0.001 && abs(frame.minY-settled.minY)<=0.001 &&
                    abs(frame.width-settled.width)<=0.001 && abs(frame.height-settled.height)<=0.001
            },timeout:3),app.debugDescription)
            let reflowed=heading.frame
            XCTAssertEqual(reflowed.minX,settled.minX,accuracy:0.001)
            XCTAssertEqual(reflowed.minY,settled.minY,accuracy:0.001)
            XCTAssertEqual(reflowed.width,settled.width,accuracy:0.001)
            XCTAssertEqual(reflowed.height,settled.height,accuracy:0.001)
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
        let fileInfo=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","사진 원본 20 MB 이하 · HEIC/HEIF 포함")).firstMatch
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
    func testPointAccentLabelsStayDarkInDarkAppearance(){
        app.launchArguments=["-wire-screen","POINTS","-wire-fixture","-wire-reset","-appearance","dark"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:10))
        let shop=app.buttons["browsePointShop"]
        XCTAssertTrue(shop.waitForExistence(timeout:5))
        let overview=app.screenshot().image
        XCTAssertTrue(containsBrandGreen(in:overview,rect:shop.frame));XCTAssertTrue(containsDarkPixel(in:overview,rect:shop.frame),"The points CTA uses the brand's dark on-accent semantic color in dark mode")
        capture("Points-dark-accent-cta")
        shop.tap();XCTAssertTrue(app.descendants(matching:.any)["screen-SHOP"].waitForExistence(timeout:5))
        let category=app.buttons["shop-category-image"]
        XCTAssertTrue(category.waitForExistence(timeout:5))
        let catalog=app.screenshot().image
        XCTAssertTrue(containsBrandGreen(in:catalog,rect:category.frame));XCTAssertTrue(containsDarkPixel(in:catalog,rect:category.frame),"The selected shop category uses the dark on-accent semantic color in dark mode")
        capture("Shop-dark-accent-category")
    }
    func testPointHistoryEarnedAndSpentIconsKeepContrastInDarkAppearance(){
        app.launchArguments=["-wire-screen","B02","-wire-fixture","-wire-test-store-suite","mov.wireframe.test.points-dark-b02","-wire-reset","-appearance","dark"]
        app.launch();XCTAssertTrue(app.descendants(matching:.any)["screen-B02"].waitForExistence(timeout:10))
        let earned=app.descendants(matching:.any)["point-entry-row-earned"].firstMatch,spent=app.descendants(matching:.any)["point-entry-row-spent"].firstMatch
        XCTAssertTrue(earned.waitForExistence(timeout:5),app.debugDescription);XCTAssertTrue(spent.waitForExistence(timeout:5),app.debugDescription)
        let screenshot=app.screenshot().image
        // The source SVG facet changed from #202925 to #BFFFC7. Sample its interior
        // polygon coordinates (SVG paths scaled by 0.8), excluding the pale #D9FFDE face.
        let earnedFacet=CGRect(x:earned.frame.minX+12,y:earned.frame.midY-5,width:2.5,height:4)
        let spentFacet=CGRect(x:spent.frame.minX+12,y:spent.frame.midY-5,width:2.5,height:4)
        XCTAssertTrue(containsDarkVariantFacetPixel(in:screenshot,rect:earnedFacet),"The earned dark facet uses #BFFFC7 rather than the light asset's #D9FFDE facet")
        XCTAssertTrue(containsDarkVariantFacetPixel(in:screenshot,rect:spentFacet),"The spent dark facet uses #BFFFC7 rather than the light asset's #D9FFDE facet")
        capture("Point-history-earned-spent-dark-contrast")
    }
    func testB01LaunchAliasOpensPointsTab(){
        app.launchArguments=["-wire-screen","B01","-wire-fixture","-wire-reset","-appearance","light"];app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["screen-POINTS"].waitForExistence(timeout:10));XCTAssertEqual(app.buttons["tab-0"].label,"포인트");XCTAssertTrue(app.staticTexts["pointBalance"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","포인트 안내")).count,1,"B01 follows the source with a single guide link");XCTAssertTrue(app.buttons["pointGuideOverview"].exists)
    }
}
