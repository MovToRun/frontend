import XCTest
import UIKit
@testable import Mov

final class ThemeTests:XCTestCase {
    func testRootTabRoutesAndLabelsMatchReview52Navigation() {
        XCTAssertEqual(WRootTab.allCases.map(\.title), ["포인트", "러닝", "홈", "커뮤니티", "내 정보"])
        XCTAssertEqual(WRootTab.allCases.map(\.caption), ["포인트", "러닝", nil, "커뮤니티", "내 정보"])
        XCTAssertEqual(WRootTab.allCases.map(\.route), ["POINTS", "H01", "H00", "C01", "M01"])
    }
    func testThemeMappingAndBrand() {
        XCTAssertNil(ThemePreference.system.colorScheme)
        XCTAssertEqual(ThemePreference.light.colorScheme,.light)
        XCTAssertEqual(ThemePreference.dark.colorScheme,.dark)
        XCTAssertEqual(MovTokens.brandHex,0x5EF76D)
        XCTAssertNotNil(UIFont(name:"PretendardVariable-Regular",size:16))
        XCTAssertNotNil(UIFont(name:"Cafe24Ssurround",size:29))
        XCTAssertEqual(RunGoal.duration(90),"1시간 30분")
        XCTAssertEqual(RunRecord.clock(8625),"143:45")
        for name in ["Regular","Medium","SemiBold","Bold"]{XCTAssertNotNil(UIFont(name:"PretendardVariable-"+name,size:17))}
        XCTAssertEqual(RunGoal(kind:.distance,kilometers:1.5).summary,"1.5 km 달리기")
        let legacy=Data(#"{"kind":"distance","kilometers":5,"minutes":30}"#.utf8)
        XCTAssertEqual(try? JSONDecoder().decode(RunGoal.self,from:legacy).kilometers,5)
        XCTAssertEqual(RunGoal.duration(360),"6시간")
        XCTAssertEqual(RunGoal.duration(6000),"100시간")
        XCTAssertEqual(WeeklyGoal.percent(value:23,goal:20),115)
        XCTAssertEqual(WeeklyGoal.percent(value:0,goal:20),0)
        XCTAssertEqual(WeeklyGoal.percent(value:4.82,goal:20),24)
    }
    @MainActor func testPauseResumeAndSavedRecordSurviveReload() {
        let suite="MovTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=RunStore(defaults:defaults)
        XCTAssertTrue(store.records.isEmpty,"New local profiles must not receive fabricated running records")
        let start=Date(timeIntervalSince1970:1000)
        store.start(at:start)
        store.pause(at:start.addingTimeInterval(120))
        XCTAssertEqual(store.session!.elapsed(at:start.addingTimeInterval(500)),120)
        store.resume(at:start.addingTimeInterval(500))
        let record=store.finish(save:true,at:start.addingTimeInterval(740))!
        XCTAssertEqual(record.seconds,360)
        XCTAssertEqual(record.kilometers,0,"Unconnected GPS must never fabricate distance")
        let countAfterSave=store.records.count
        XCTAssertNil(store.finish(save:true,at:start.addingTimeInterval(741)))
        XCTAssertEqual(store.records.count,countAfterSave,"Repeated save must not duplicate a record")
        let reloaded=RunStore(defaults:defaults)
        XCTAssertNil(reloaded.session)
        XCTAssertEqual(reloaded.records.first?.id,record.id)
        reloaded.delete(record.id)
        XCTAssertFalse(RunStore(defaults:defaults).records.contains{$0.id==record.id})
    }
    @MainActor func testZeroDistanceInvalidAndDiscardDoesNotSave() {
        let suite="MovTests."+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=RunStore(defaults:defaults);let count=store.records.count;let start=Date()
        store.start(at:start)
        XCTAssertNil(store.finish(save:true,at:start),"An empty session must not create a record")
        let record=store.finish(save:true,at:start.addingTimeInterval(60))!
        XCTAssertFalse(record.isValid);XCTAssertEqual(record.kilometers,0);XCTAssertEqual(record.pace,"0:00")
        store.start(at:start);store.finish(save:false,at:start.addingTimeInterval(100))
        XCTAssertEqual(store.records.count,count+1)
    }
    @MainActor func testTierRequiresDistanceAndDistinctQualifyingDays() {
        let suite="MovTests."+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=RunStore(defaults:defaults);store.records=[]
        XCTAssertEqual(store.tier,"등급 없음")
        let day=Calendar.current.startOfDay(for:Date())
        store.records=[RunRecord(date:day,title:"fixture",seconds:120,kilometers:0.5),RunRecord(date:day,title:"fixture",seconds:120,kilometers:0.5)]
        XCTAssertEqual(store.activityDays,1)
        store.records=(0..<7).map{RunRecord(date:Calendar.current.date(byAdding:.day,value:-$0,to:day)!,title:"fixture",seconds:720,kilometers:2)}
        XCTAssertEqual(store.tier,"새싹")
        store.records=[RunRecord(date:day,title:"fixture",seconds:3600,kilometers:300)]
        XCTAssertEqual(store.tier,"시작")
    }
    @MainActor func testExplicitSegmentsAndMissingData(){
        let original=[RunSegment(distance:1,seconds:378),RunSegment(distance:1,seconds:369),RunSegment(distance:1,seconds:386),RunSegment(distance:1,seconds:370),RunSegment(distance:0.82,seconds:305)]
        var record=RunRecord(date:Date(),title:"원본 구간",seconds:1808,kilometers:4.82,segments:original)
        let points=WPaceChart(record:record).points
        XCTAssertEqual(points.count,5);XCTAssertEqual(points.last!.end,4.82,accuracy:0.00001)
        XCTAssertEqual(points.last!.pace,305/0.82,accuracy:0.00001)
        record.segments=nil;XCTAssertTrue(WPaceChart(record:record).points.isEmpty)
        record.segments=[original[0],RunSegment(distance:0,seconds:30,type:"gps-gap",reason:"누락 거리 추정 안 함"),original[1]]
        let separated=WPaceChart(record:record).points
        XCTAssertNotEqual(separated[0].group,separated[1].group)
        XCTAssertEqual(separated.last!.end,2)
    }

    func testStatisticsSeparateValidRunCountAndTimeAndKeepZeroVisible() {
        let valid=RunRecord(date:Date(),title:"valid",seconds:1808,kilometers:4.82)
        let invalid=RunRecord(date:Date(),title:"invalid",seconds:312,kilometers:0,segments:[RunSegment(distance:0,seconds:312,type:"gps-gap",reason:"GPS 수신 실패 예시")])
        let summary=RunPeriodSummary(records:[valid,invalid])
        XCTAssertEqual(summary.recordCount,1)
        XCTAssertEqual(summary.kilometers,4.82,accuracy:0.00001)
        XCTAssertEqual(summary.seconds,1808)
        XCTAssertEqual(RunPeriodSummary(records:[invalid]).recordCount,0)
        XCTAssertEqual(MovNumber.display(RunPeriodSummary(records:[invalid]).kilometers),"0")
        XCTAssertEqual(RunRecord.clock(RunPeriodSummary(records:[invalid]).seconds),"00:00")
        XCTAssertEqual(invalid.caloriesText,"0 kcal")
    }

    @MainActor func testRecentMonthlyAverageUsesValidRecordsAndShowsZero() {
        let suite="MovTests."+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=RunStore(defaults:defaults),now=Date(),start=Calendar.current.date(byAdding:.month,value:-1,to:now)!
        store.records=[RunRecord(date:start,title:"at boundary",seconds:600,kilometers:2),RunRecord(date:now.addingTimeInterval(-3600),title:"recent",seconds:1200,kilometers:4),RunRecord(date:now.addingTimeInterval(-3600),title:"invalid",seconds:900,kilometers:0),RunRecord(date:now.addingTimeInterval(60),title:"future",seconds:900,kilometers:20)]
        XCTAssertEqual(store.averageDistance(asOf:now),3,accuracy:0.00001)
        store.records=[store.records[2]]
        XCTAssertEqual(store.averageDistance(asOf:now),0)
        XCTAssertEqual(MovNumber.display(store.averageDistance(asOf:now)),"0")
    }

    func testRecordValidityDetailsUseStoredReasonsWithoutGuessing() {
        let date=Date()
        let reasoned=RunRecord(date:date,title:"invalid",seconds:60,kilometers:0,segments:[RunSegment(distance:0,seconds:60,type:"gps-gap",reason:"센서 원본의 제외 사유")])
        XCTAssertEqual(reasoned.validityDetails,["센서 원본의 제외 사유"])
        let unlabelled=RunRecord(date:date,title:"legacy",seconds:60,kilometers:0,segments:[RunSegment(distance:0,seconds:60,type:"gps-gap")])
        XCTAssertEqual(unlabelled.validityDetails,["GPS 누락"])
        let whitespaceReasons=RunRecord(date:date,title:"legacy",seconds:60,kilometers:0,segments:[RunSegment(distance:0,seconds:30,type:"gps-gap",reason:""),RunSegment(distance:0,seconds:30,type:"custom",reason:" \n ")])
        XCTAssertEqual(whitespaceReasons.validityDetails,["GPS 누락","유효 거리로 확인할 수 없는 구간"])
        XCTAssertTrue(whitespaceReasons.validityDetails.allSatisfy{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty})
        let noSegments=RunRecord(date:date,title:"legacy",seconds:60,kilometers:0)
        XCTAssertEqual(noSegments.validityDetails,["구간별 판별 정보가 없어 제외 이유를 확인할 수 없어요."])
    }

    func testShareElapsedFormatsMinutesAndHoursWithoutDateTimeNoise() {
        XCTAssertEqual(ShareElapsed.string(570),"9m30s")
        XCTAssertEqual(ShareElapsed.string(3723),"1h2m3s")
        XCTAssertEqual(ShareGestureBounds.offset(CGSize(width:900,height:-900),canvas:CGSize(width:360,height:450)),CGSize(width:129.6,height:-144))
        XCTAssertEqual(ShareGestureBounds.scale(9),1.8)
        XCTAssertEqual(ShareGestureBounds.scale(0.1,minimum:0.65,maximum:1.7),0.65)
    }

    @MainActor func testShareImageInputValidationAndWorkspaceIdempotence() async throws {
        let image=UIGraphicsImageRenderer(size:CGSize(width:12,height:12)).image{context in UIColor.systemGreen.setFill();context.fill(CGRect(x:0,y:0,width:12,height:12))}
        let bytes=try XCTUnwrap(image.pngData())
        XCTAssertNotNil(try ShareMediaValidation.image(bytes))
        do { _ = try ShareMediaValidation.image(Data(repeating:0,count:20*1024*1024+1)); XCTFail("Oversize image must be rejected") }
        catch ShareMediaError.tooLarge {}
        do { _ = try ShareMediaValidation.image(Data([0,1,2,3])); XCTFail("Undecodable image must be rejected") }
        catch ShareMediaError.invalidImage {}
        let corruptMovie=FileManager.default.temporaryDirectory.appendingPathComponent("mov-corrupt-\(UUID().uuidString).mp4")
        try Data([0,1,2,3]).write(to:corruptMovie)
        defer{try? FileManager.default.removeItem(at:corruptMovie)}
        do { try await ShareMediaValidation.video(corruptMovie); XCTFail("Undecodable video must be rejected") }
        catch ShareMediaError.invalidVideo {}

        let workspace=ShareWorkspace(),record=UUID()
        let first=workspace.insertPNG(bytes,for:record)
        let second=workspace.insertPNG(bytes,for:record)
        XCTAssertEqual(first?.id,second?.id)
        XCTAssertEqual(workspace.outputs[record]?.count,1)
        XCTAssertNil(workspace.insertPNG(Data(repeating:1,count:2*1024*1024+1),for:record))
        XCTAssertEqual(workspace.outputs[record]?.count,1,"A rejected insertion must leave the previous image available for retry")
        workspace.clear()
        XCTAssertEqual(workspace.outputs.count,0)
    }

    @MainActor func testShareArtifactsAreRecordScopedAndOnlyOwnedTempVideosAreRemoved() throws {
        let workspace=ShareWorkspace(),recordA=UUID(),recordB=UUID()
        let bytes=Data([1,2,3]),outputA=try XCTUnwrap(workspace.insertPNG(bytes,for:recordA)),outputB=try XCTUnwrap(workspace.insertPNG(bytes,for:recordB))
        workspace.selectedOutputID=outputA.id
        workspace.delete(outputB.id,for:recordA)
        XCTAssertEqual(workspace.output(outputA.id,for:recordA)?.id,outputA.id,"Deleting by record A must not touch record B's image")
        XCTAssertEqual(workspace.output(outputB.id,for:recordB)?.id,outputB.id)
        workspace.delete(outputA.id,for:recordA)
        XCTAssertNil(workspace.output(outputA.id,for:recordA),"Deleting a share image removes exactly the selected record's artifact")
        XCTAssertEqual(workspace.output(outputB.id,for:recordB)?.id,outputB.id,"Deleting record A's image preserves record B's image")
        let retryOutput=try XCTUnwrap(workspace.insertPNG(bytes,for:recordA));workspace.selectedOutputID=retryOutput.id
        XCTAssertTrue(workspace.exportFailureMessage(for:retryOutput.id,record:recordA).contains("다시 시도"))
        XCTAssertEqual(workspace.output(retryOutput.id,for:recordA)?.data,bytes,"An OS file export failure retains the in-memory output for retry")

        let temp=FileManager.default.temporaryDirectory
        let owned=temp.appendingPathComponent("mov-share-fixture-\(UUID().uuidString).mp4")
        let source=temp.appendingPathComponent("user-source-fixture-\(UUID().uuidString).mp4")
        try bytes.write(to:owned);try bytes.write(to:source)
        defer{try? FileManager.default.removeItem(at:owned);try? FileManager.default.removeItem(at:source)}
        workspace.registerImportedVideo(owned)
        workspace.update(recordA){$0.videoURL=owned}
        workspace.removeArtifacts(for:recordA)
        XCTAssertFalse(FileManager.default.fileExists(atPath:owned.path),"Deleting the parent record removes its app-owned imported movie copy")
        XCTAssertNil(workspace.output(outputA.id,for:recordA))
        XCTAssertNil(workspace.selectedOutputID)
        XCTAssertEqual(workspace.output(outputB.id,for:recordB)?.id,outputB.id,"Deleting record A preserves record B's image")
        workspace.update(recordA){$0.videoURL=source}
        workspace.removeArtifacts(for:recordA)
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path),"Cleanup never deletes an unregistered source media path")
    }

    @MainActor func testShareVideoReplacementCancelReleaseAndDismissCleanup() throws {
        let workspace=ShareWorkspace(),record=UUID(),temp=FileManager.default.temporaryDirectory
        let old=temp.appendingPathComponent("mov-share-old-\(UUID().uuidString).mp4")
        let replacement=temp.appendingPathComponent("mov-share-new-\(UUID().uuidString).mp4")
        let canceled=temp.appendingPathComponent("mov-share-cancel-\(UUID().uuidString).mp4")
        for url in [old,replacement,canceled]{try Data([1]).write(to:url)}
        defer{for url in [old,replacement,canceled]{try? FileManager.default.removeItem(at:url)}}
        for url in [old,replacement,canceled]{workspace.registerImportedVideo(url)}
        workspace.update(record){$0.videoURL=old}
        workspace.update(record){$0.videoURL=replacement}
        XCTAssertFalse(FileManager.default.fileExists(atPath:old.path),"Replacing media deletes only the old imported copy")
        var baseline=ShareDraft();baseline.videoURL=old
        workspace.restoreDraft(baseline,for:record)
        XCTAssertFalse(FileManager.default.fileExists(atPath:replacement.path),"Cancel or dismiss restores the baseline and releases its imported copy")
        XCTAssertNil(workspace.draft(for:record).videoURL,"A replaced baseline movie is not restored as a stale temp path")
        workspace.update(record){$0.videoURL=canceled}
        workspace.releaseVideo(for:record)
        XCTAssertFalse(FileManager.default.fileExists(atPath:canceled.path),"After successful PNG composition, the unneeded video temp is released")
        XCTAssertNil(workspace.draft(for:record).videoURL)

        var guardState=ShareMediaLoadGuard()
        let oldRequest=guardState.begin(),latestRequest=guardState.begin()
        XCTAssertFalse(guardState.accepts(oldRequest),"A late async media/render result cannot commit after a newer selection")
        XCTAssertTrue(guardState.accepts(latestRequest))
        guardState.invalidate()
        XCTAssertFalse(guardState.accepts(latestRequest),"A late async media/render result cannot commit after screen dismissal")
    }

}

extension ThemeTests {
    func testOfflineAuthBoundaries() {
        for email in ["runner@example.test","fake+review@EXAMPLE.TEST"]{XCTAssertTrue(WAuthValidation.email(email))}
        for email in ["a@@example.test","@example.test","person@gmail.com","a b@example.test",String(repeating:"a",count:250)+"@example.test"]{XCTAssertFalse(WAuthValidation.email(email))}
        XCTAssertFalse(WAuthValidation.password("1234567"));XCTAssertTrue(WAuthValidation.password("12345678"))
        XCTAssertTrue(WAuthValidation.password(String(repeating:"x",count:128)));XCTAssertFalse(WAuthValidation.password(String(repeating:"x",count:129)))
    }
    @MainActor func testAuthNavigationClearsTransientSecrets() {
        let state=WireState();state.screen="A19";state.path=["A07"]
        state.challengeIssued=Date();state.code="482619";state.authPassword="FixtureOnly482619";state.revealedFields=["예시 비밀번호"]
        state.back()
        XCTAssertEqual(state.screen,"A07");XCTAssertNil(state.challengeIssued);XCTAssertTrue(state.code.isEmpty);XCTAssertTrue(state.authPassword.isEmpty);XCTAssertTrue(state.revealedFields.isEmpty)
        state.screen="T15";state.settingsGrant=true;state.go("A16");XCTAssertTrue(state.settingsGrant)
        state.go("T05");XCTAssertFalse(state.settingsGrant)
        state.screen="A07";state.authEmail="runner@example.test";state.authPassword="FixtureOnly482619";state.go("A19")
        XCTAssertEqual(state.authEmail,"runner@example.test","The address is retained only for the active OTP screen")
        state.go("A02");XCTAssertTrue(state.authEmail.isEmpty,"The address is cleared when the OTP flow ends")
    }
}


extension ThemeTests {
    func testDisplayNumbersDoNotRoundStoredValues() {
        for (value,expected) in [(0.0,"0"),(5.0,"5"),(5.5,"5.5"),(1.23456789,"1.23"),(0.1+0.2,"0.3"),(9.999,"10"),(-0.001,"0"),(1000.0,"1000")]{XCTAssertEqual(MovNumber.display(value),expected)}
        let record=RunRecord(date:Date(),title:"fixture",seconds:240.123456,kilometers:0.999999)
        _=MovNumber.display(record.kilometers)
        XCTAssertEqual(record.kilometers,0.999999);XCTAssertEqual(record.seconds,240.123456)
        XCTAssertEqual(RunRecord.clock(65.789),"01:05")
    }
    @MainActor func testProviderFlowDoesNotRevisitCompletion() {
        let state=WireState();state.screen="T01";state.path=["H00"]
        state.go("T05");state.go("T15");state.settingsGrant=true;state.go("T06");state.go("T17")
        state.back();XCTAssertEqual(state.screen,"T05");XCTAssertEqual(state.path,["H00","T01"])
        state.back();XCTAssertEqual(state.screen,"T01")
        state.go("T05")
        for destination in ["A16","A17","T06"]{
            state.go("T15");state.settingsGrant=true;state.go(destination);state.go("T05")
            XCTAssertEqual(state.path,["H00","T01"]);XCTAssertFalse(state.settingsGrant)
        }
        state.go("T15");state.settingsGrant=true;state.go("A16");state.go("A18");state.go("T05");state.back()
        XCTAssertEqual(state.screen,"T01");XCTAssertFalse(state.path.contains("A18"))
    }
}

extension ThemeTests {
    @MainActor func testCompletedAuthDoesNotReopenCompletedSteps(){
        let state=WireState();state.screen="A01";state.path=["T01","T10"];state.go("H00");XCTAssertTrue(state.path.isEmpty)
        state.screen="A15";state.path=["A07","A19","A02","A03"];state.back();XCTAssertEqual(state.screen,"H00");XCTAssertTrue(state.path.isEmpty)
        state.screen="A13";state.path=["A10","A11","A12"];state.back();XCTAssertEqual(state.screen,"A01");XCTAssertTrue(state.path.isEmpty)
        state.screen="A18";state.passwordChanged=true;state.path=["T01","T05","A17"];state.back();XCTAssertEqual(state.screen,"A01");XCTAssertTrue(state.path.isEmpty)
        state.screen="A19";state.authPassword="NotPersisted123";state.authConfirm=state.authPassword;state.go("A02");XCTAssertTrue(state.authPassword.isEmpty);XCTAssertTrue(state.authConfirm.isEmpty)
    }
}
