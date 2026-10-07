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
        let noSegments=RunRecord(date:date,title:"legacy",seconds:60,kilometers:0)
        XCTAssertEqual(noSegments.validityDetails,["구간별 판별 정보가 없어 제외 이유를 확인할 수 없어요."])
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
