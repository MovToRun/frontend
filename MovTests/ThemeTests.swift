Warning: truncated output (original token count: 92430)
Total output lines: 5880

import XCTest
import UIKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
@testable import Mov

private struct V1PointEntryFixture: Codable {
    var id: UUID
    var title: String
    var amount: Int
    var date: Date
}

private struct V1PointsFixture: Codable {
    var balance: Int
    var entries: [V1PointEntryFixture]
    var owned: Set<String>
}

@MainActor private final class RunStoreUploadIdentityFake: RunUploadMemberIdentityProviding {
    var memberID: String?
    init(memberID: String?) { self.memberID = memberID }
    func currentAuthenticatedMemberID() -> String? { memberID }
}

private struct QueuedRunUploadFixture: Equatable, Sendable {
    let ownerID: String
    let payload: RunUploadPayload
}

private enum RunStoreUploadQueueFixtureError: Error {
    case writeFailed
}

private actor RunStoreUploadQueueFake: RunUploadEnqueueing {
    private var attempts = 0
    private var failFirstWrite: Bool
    private var entries: [QueuedRunUploadFixture] = []

    init(failFirstWrite: Bool = false) { self.failFirstWrite = failFirstWrite }

    func enqueueRunUpload(_ payload: RunUploadPayload, ownerID: String) async throws {
        attempts += 1
        if failFirstWrite {
            failFirstWrite = false
            throw RunStoreUploadQueueFixtureError.writeFailed
        }
        entries.append(QueuedRunUploadFixture(ownerID: ownerID, payload: payload))
    }

    func attemptCount() -> Int { attempts }
    func snapshot() -> [QueuedRunUploadFixture] { entries }
}

@MainActor private final class RunStoreOwnedRecordsFake: RunStoreOwnedRecordsPersisting {
    private(set) var snapshot: RunStoreOwnedRecordsSnapshot
    private var failNextSave: Bool

    init(snapshot: RunStoreOwnedRecordsSnapshot = .missing, failNextSave: Bool = false) {
        self.snapshot = snapshot
        self.failNextSave = failNextSave
    }

    func loadSnapshot() throws -> RunStoreOwnedRecordsSnapshot { snapshot }

    func saveCanonical(_ records: [RunRecord]) throws {
        if failNextSave {
            failNextSave = false
            throw RunStoreOwnedRecordsPersistenceFailure.writeFailed
        }
        snapshot = .canonical(records)
    }

    var canonicalRecords: [RunRecord] {
        if case .canonical(let records) = snapshot { return records }
        return []
    }
}

private actor RunStoreUploadSessionFake: RunUploadSessionProviding {
    private var session: RunUploadSession?
    init(session: RunUploadSession?) { self.session = session }
    func currentSession() async throws -> RunUploadSession? { session }
}

private actor RunStoreUploadSenderFake: RunUploading {
    private var uploaded: [RunUploadPayload] = []
    private let delivery: RunUploadDelivery

    init(delivery: RunUploadDelivery = .accepted) { self.delivery = delivery }

    func upload(_ payload: RunUploadPayload, session: RunUploadSession) async throws -> RunUploadDelivery {
        uploaded.append(payload)
        return delivery
    }
    func uploadedPayloads() -> [RunUploadPayload] { uploaded }
}

private actor RunStoreUploadDrainerFake: RunUploadDraining {
    private let suspends: Bool
    private var report: RunUploadDrainReport
    private var calls = 0
    private var continuation: CheckedContinuation<RunUploadDrainReport, Error>?

    init(
        report: RunUploadDrainReport = RunUploadDrainReport(uploadedCount: 1, deletedCount: 0, terminalCount: 0, stopReason: .finished),
        suspends: Bool = false
    ) {
        self.report = report
        self.suspends = suspends
    }

    func drain(ownerID: String) async throws -> RunUploadDrainReport {
        calls += 1
        guard suspends else { return report }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<200 {
            if calls >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func callCount() -> Int { calls }

    func complete(_ report: RunUploadDrainReport) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: report)
    }
}

private final class FailSecondRunUploadOutboxWrite: RunUploadOutboxPersisting, @unchecked Sendable {
    let drainOwnershipKey = "run-store-outbox-\(UUID().uuidString)"
    private let lock = NSLock()
    private var entries: [RunUploadOutboxEntry] = []
    private var writes = 0

    func load() throws -> [RunUploadOutboxEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func transact<Result>(
        _ update: ([RunUploadOutboxEntry]) throws -> RunUploadOutboxMutation<Result>
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        let mutation = try update(entries)
        guard mutation.entries != entries else { return mutation.result }
        writes += 1
        if writes == 2 { throw RunUploadOutboxPersistenceFailure.writeFailed }
        entries = mutation.entries
        return mutation.result
    }
}

private actor PendingSessionLogoutBridgeFake: SessionLogoutRequesting {
    private var continuations: [CheckedContinuation<Void, Error>?] = []
    private var requests = 0

    func logout() async throws {
        try await withCheckedThrowingContinuation { continuation in
            requests += 1
            continuations.append(continuation)
        }
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<200 {
            if requests >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func callCount() -> Int { requests }

    func complete(_ index: Int, with result: Result<Void, SessionLogoutFailure>) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else { return }
        continuations[index] = nil
        continuation.resume(with: result.mapError { $0 })
    }
}

private actor AccountScopedMemberProfileBridgeFake: MemberProfileFetching {
    private var requests = 0

    func fetchProfile() async throws -> MemberProfile {
        requests += 1
        if requests == 1 {
            await Task.detached { try? await Task.sleep(for: .milliseconds(200)) }.value
            return MemberProfile(nickname: "OldAccount")
        }
        return MemberProfile(nickname: "NewAccount")
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<200 {
            if requests >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor MemberProfileBridgeFake: MemberProfileFetching, MemberProfileUpdating {
    private var profile:MemberProfile
    private var writeFailure:MemberProfileFailure?
    private let holdsWrites:Bool
    private var writeCountValue=0
    private var pendingWrite:CheckedContinuation<MemberProfile,Error>?

    init(profile:MemberProfile,writeFailure:MemberProfileFailure?=nil,holdsWrites:Bool=false){
        self.profile=profile;self.writeFailure=writeFailure;self.holdsWrites=holdsWrites
    }

    func fetchProfile() async throws -> MemberProfile { profile }

    func updateProfile(_ patch:MemberProfilePatch) async throws -> MemberProfile {
        writeCountValue+=1
        if holdsWrites {
            return try await withCheckedThrowingContinuation { continuation in pendingWrite=continuation }
        }
        if let writeFailure { throw writeFailure }
        return profile
    }

    func writeCount()->Int{writeCountValue}
    func hasPendingWrite()->Bool{pendingWrite != nil}
    func setProfile(_ profile:MemberProfile){self.profile=profile}
    func completePendingWrite(_ profile:MemberProfile){pendingWrite?.resume(returning:profile);pendingWrite=nil}
}

final class ThemeTests:XCTestCase {
    @MainActor func testMemberProfileBridgeBlocksDuplicateWritesAndUsesServerNormalizedResponse() async throws {
        let original=MemberProfile(nickname:"RunMate",introduction:"기존 소개",region:"모브시 북부권",weightKg:Decimal(string:"63.12"))
        let normalized=MemberProfile(nickname:"가Runner",introduction:"새 소개",region:"모브시 중부권",weightKg:Decimal(string:"63.12"))
        let fake=MemberProfileBridgeFake(profile:original,holdsWrites:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            memberProfileLoader:MemberProfileLoader(fetcher:fake),memberProfileUpdater:fake
        ))
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M02")
        XCTAssertEqual(bridge.memberProfileState,.loaded(original))

        let patch=MemberProfilePatch(introduction:.set("새 소개"))
        bridge.saveMemberProfile(patch,accountScopeID:"account-a",screen:"M02")
        bridge.saveMemberProfile(patch,accountScopeID:"account-a",screen:"M02")
        XCTAssertEqual(bridge.memberProfileWriteState,.saving)
        let writeIsPending=await waitUntil { await fake.hasPendingWrite() }
        XCTAssertTrue(writeIsPending)
        let writes=await fake.writeCount()
        XCTAssertEqual(writes,1,"The bridge admits only one in-flight PATCH")

        await fake.completePendingWrite(normalized)
        let didSave=await waitUntil { bridge.memberProfileWriteState == .saved }
        XCTAssertTrue(didSave)
        XCTAssertEqual(bridge.memberProfileState,.loaded(normalized))
    }

    @MainActor func testMemberProfileNicknameConflictRetainsLoadedBaseline() async throws {
        let original=MemberProfile(nickname:"RunMate",introduction:"기존 소개",region:"모브시 북부권")
        let fake=MemberProfileBridgeFake(profile:original,writeFailure:.nicknameAlreadyUsed(requestID:"conflict"))
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            memberProfileLoader:MemberProfileLoader(fetcher:fake),memberProfileUpdater:fake
        ))
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M02")
        bridge.saveMemberProfile(MemberProfilePatch(nickname:.set("TakenName")),accountScopeID:"account-a",screen:"M02")

        let didFail=await waitUntil { if case .failed = bridge.memberProfileWriteState{return true};return false }
        XCTAssertTrue(didFail)
        XCTAssertEqual(bridge.memberProfileWriteState,.failed(.nicknameAlreadyUsed(requestID:"conflict")))
        XCTAssertEqual(bridge.memberProfileState,.loaded(original),"A conflict must not replace the existing profile")
    }

    @MainActor func testLateProfileWriteAfterAccountSwitchCannotReplaceNewAccount() async throws {
        let accountA=MemberProfile(nickname:"RunnerA",introduction:"A",region:"모브시 북부권")
        let accountB=MemberProfile(nickname:"RunnerB",introduction:"B",region:"모브시 남부권")
        let staleResponse=MemberProfile(nickname:"RunnerA2",introduction:"A2",region:"모브시 중부권")
        let fake=MemberProfileBridgeFake(profile:accountA,holdsWrites:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            memberProfileLoader:MemberProfileLoader(fetcher:fake),memberProfileUpdater:fake
        ))
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M02")
        bridge.saveMemberProfile(MemberProfilePatch(nickname:.set("RunnerA2")),accountScopeID:"account-a",screen:"M02")
        let writeIsPending=await waitUntil { await fake.hasPendingWrite() }
        XCTAssertTrue(writeIsPending)

        await fake.setProfile(accountB)
        await bridge.activate(feature:.profile,accountScopeID:"account-b",screen:"M01")
        XCTAssertEqual(bridge.memberProfileState,.loaded(accountB))
        await fake.completePendingWrite(staleResponse)
        try await Task.sleep(for:.milliseconds(50))

        XCTAssertEqual(bridge.memberProfileState,.loaded(accountB))
        XCTAssertEqual(bridge.memberProfileWriteState,.idle)
    }

    @MainActor func testLateProfileWriteAfterBackRefreshesTheCardFromTheCurrentServerState() async throws {
        let original=MemberProfile(nickname:"RunnerA",introduction:"A",region:"모브시 북부권")
        let committed=MemberProfile(nickname:"RunnerA2",introduction:"A",region:"모브시 북부권")
        let fake=MemberProfileBridgeFake(profile:original,holdsWrites:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            memberProfileLoader:MemberProfileLoader(fetcher:fake),memberProfileUpdater:fake
        ))
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M02")
        bridge.saveMemberProfile(MemberProfilePatch(nickname:.set("RunnerA2")),accountScopeID:"account-a",screen:"M02")
        let writeIsPending=await waitUntil { await fake.hasPendingWrite() }
        XCTAssertTrue(writeIsPending)

        await fake.setProfile(committed)
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M01")
        XCTAssertEqual(bridge.memberProfileState,.loaded(committed))
        XCTAssertEqual(bridge.memberProfileWriteState,.idle)
        await fake.completePendingWrite(committed)
        let refreshedAfterLateCommit=await waitUntil { bridge.memberProfileState == .loaded(committed) }
        XCTAssertTrue(refreshedAfterLateCommit)
        XCTAssertEqual(bridge.memberProfileWriteState,.idle)
    }

    @MainActor func testProfileTransportFailureKeepsTheLoadedBaseline() async throws {
        let original=MemberProfile(nickname:"RunMate",introduction:"기존 소개",region:"모브시 북부권")
        let fake=MemberProfileBridgeFake(profile:original,writeFailure:.transport(.timedOut))
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            memberProfileLoader:MemberProfileLoader(fetcher:fake),memberProfileUpdater:fake
        ))
        await bridge.activate(feature:.profile,accountScopeID:"account-a",screen:"M02")
        bridge.saveMemberProfile(MemberProfilePatch(introduction:.set("변경 소개")),accountScopeID:"account-a",screen:"M02")
        let didFail=await waitUntil { if case .failed = bridge.memberProfileWriteState{return true};return false }
        XCTAssertTrue(didFail)
        XCTAssertEqual(bridge.memberProfileWriteState,.failed(.transport(.timedOut)))
        XCTAssertEqual(bridge.memberProfileState,.loaded(original))
    }

    @MainActor func testProfileEditingValidationMatchesBackendBoundariesWithoutCoercion() throws {
        XCTAssertNil(WMemberProfileValidation.nicknameError(for:"가Runner"))
        XCTAssertNil(WMemberProfileValidation.nicknameError(for:"가Runner"),"NFC-valid input is checked after canonical composition")
        XCTAssertNotNil(WMemberProfileValidation.nicknameError(for:"A"))
        XCTAssertNotNil(WMemberProfileValidation.nicknameError(for:"Runner_Name!"))
        XCTAssertNil(WMemberProfileValidation.introductionError(for:String(repeating:"👨‍👩‍👧‍👦",count:60)))
        XCTAssertNotNil(WMemberProfileValidation.introductionError(for:String(repeating:"👨‍👩‍👧‍👦",count:61)))
        XCTAssertNil(WMemberProfileValidation.regionError(for:"모브시 남부권"))
        XCTAssertNotNil(WMemberProfileValidation.regionError(for:"모브시 중앙"))
        XCTAssertEqual(WMemberProfileValidation.weightInput("63.123"),.value(Decimal(string:"63.123")!))
        XCTAssertEqual(WMemberProfileValidation.weightInput("20"),.value(Decimal(20)))
        XCTAssertEqual(WMemberProfileValidation.weightInput("300"),.value(Decimal(300)))
        XCTAssertEqual(WMemberProfileValidation.weightInput("300.001"),.invalid)
        XCTAssertEqual(WMemberProfileValidation.weightInput("19.999"),.invalid)

        let baseline=MemberProfile(nickname:"RunMate",introduction:"설명",region:"모브시 북부권",weightKg:Decimal(string:"63.12"))
        let partial=WMemberProfileValidation.profilePatch(baseline:baseline,nickname:"RunMate",introduction:"",region:"모브시 북부권")
        XCTAssertEqual(partial,MemberProfilePatch(introduction:.clear))
        let weight=WMemberProfileValidation.weightPatch(baseline:baseline,input:.value(Decimal(string:"63.123")!))
        XCTAssertEqual(weight,MemberProfilePatch(weightKg:.set(Decimal(string:"63.123")!)))
        XCTAssertEqual(WMemberProfileValidation.weightText(Decimal(string:"63.12")),"63.12")
    }

    @MainActor private func waitUntil(_ condition:@escaping() async -> Bool) async -> Bool {
        for _ in 0..<100 {
            if await condition(){return true}
            try? await Task.sleep(for:.milliseconds(10))
        }
        return false
    }

    func communityPhotoFixture(width:Int=240,height:Int=160,transparent:Bool=false)->Data {
        let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque = !transparent
        let size=CGSize(width:CGFloat(width),height:CGFloat(height))
        let image=UIGraphicsImageRenderer(size:size,format:format).image { context in
            if !transparent{context.cgContext.setFillColor(UIColor(red:0.15,green:0.55,blue:0.35,alpha:1).cgColor);context.cgContext.fill(CGRect(origin:.zero,size:size))}
            let diameter=CGFloat(min(110,min(width,height)));context.cgContext.setFillColor(UIColor(red:0.95,green:0.25,blue:0.15,alpha:transparent ? 0.8:1).cgColor);context.cgContext.fillEllipse(in:CGRect(x:CGFloat(width)/3,y:CGFloat(height)/4,width:diameter,height:diameter))
        }
        return transparent ? image.pngData()!:image.jpegData(compressionQuality:0.9)!
    }

    func testCommunityPhotoPolicyEnforcesSizeCountAndAggregateLimits() {
        XCTAssertTrue(WCommunityPhotoPolicy.canAppend(currentCount:0,currentBytes:0,addingCount:10,addingBytes:50_000_000))
        XCTAssertFalse(WCommunityPhotoPolicy.canAppend(currentCount:10,currentBytes:0,addingCount:1,addingBytes:1))
        XCTAssertFalse(WCommunityPhotoPolicy.canAppend(currentCount:1,currentBytes:99_000_000,addingCount:1,addingBytes:2_000_000))
        XCTAssertThrowsError(try WCommunityPhotoPolicy.convertedBytes(from:Data(repeating:0,count:WCommunityPhotoPolicy.maximumOriginalBytes+1))) { error in
            XCTAssertEqual(error as? WCommunityPhotoError,.inputTooLarge)
        }
        XCTAssertThrowsError(try WCommunityPhotoPolicy.convertedBytes(from:Data("not an image".utf8)))
    }

    func testCommunityPhotoConversionKeepsTransparencyAndStripsSourceMetadata() throws {
        let transparent=try WCommunityPhotoPolicy.convertedBytes(from:communityPhotoFixture(transparent:true))
        XCTAssertTrue(transparent.starts(with:[0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A]))
        XCTAssertLessThanOrEqual(transparent.count,WCommunityPhotoPolicy.maximumPhotoBytes)
        let pngInfo=WProfilePhotoPolicy.inspect(transparent)
        XCTAssertTrue(pngInfo?.type.conforms(to:.png) == true)

        let source=communityPhotoFixture()
        guard let imageSource=CGImageSourceCreateWithData(source as CFData,nil),let image=CGImageSourceCreateImageAtIndex(imageSource,0,nil) else{return XCTFail("Synthetic JPEG decodes")}
        let tagged=NSMutableData()
        let gps:[CFString:Any]=[kCGImagePropertyGPSLatitude:37.5,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:127.0,kCGImagePropertyGPSLongitudeRef:"E"]
        let properties:[CFString:Any]=[kCGImagePropertyGPSDictionary:gps]
        guard let destination=CGImageDestinationCreateWithData(tagged,UTType.jpeg.identifier as CFString,1,nil) else{return XCTFail("Synthetic JPEG destination")}
        CGImageDestinationAddImage(destination,image,properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let cleaned=try WCommunityPhotoPolicy.convertedBytes(from:tagged as Data)
        XCTAssertLessThanOrEqual(cleaned.count,WCommunityPhotoPolicy.maximumPhotoBytes)
        let cleanedSource=CGImageSourceCreateWithData(cleaned as CFData,nil)
        let cleanedProperties=CGImageSourceCopyPropertiesAtIndex(cleanedSource!,0,nil) as? [CFString:Any]
        XCTAssertNil(cleanedProperties?[kCGImagePropertyGPSDictionary],"Re-encoding strips GPS metadata before local storage")
    }

    func testCommunityPhotoConversionNormalizesExifRotationAndResizesLongEdge() throws {
        let source=communityPhotoFixture(width:900,height:450)
        guard let sourceReader=CGImageSourceCreateWithData(source as CFData,nil),let image=CGImageSourceCreateImageAtIndex(sourceReader,0,nil) else{return XCTFail("Synthetic JPEG decodes")}
        let rotated=NSMutableData()
        guard let writer=CGImageDestinationCreateWithData(rotated,UTType.jpeg.identifier as CFString,1,nil) else{return XCTFail("Synthetic rotated JPEG destination")}
        CGImageDestinationAddImage(writer,image,[kCGImagePropertyOrientation:6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let normalized=try WCommunityPhotoPolicy.convertedBytes(from:rotated as Data)
        let rotatedInfo=try XCTUnwrap(WProfilePhotoPolicy.inspect(normalized))
        XCTAssertEqual(rotatedInfo.width,450)
        XCTAssertEqual(rotatedInfo.height,900,"EXIF rotation becomes real pixel orientation before storage")

        let wide=try WCommunityPhotoPolicy.convertedBytes(from:communityPhotoFixture(width:9000,height:100))
        let wideInfo=try XCTUnwrap(WProfilePhotoPolicy.inspect(wide))
        XCTAssertEqual(max(wideInfo.width,wideInfo.height),WCommunityPhotoPolicy.maximumEdge)
        XCTAssertLessThanOrEqual(wideInfo.width*wideInfo.height,WCommunityPhotoPolicy.maximumPixels)
    }

    @MainActor func testCommunityAttachmentStoreSeparatesDraftAndPublishedCleanup() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("community-photo-test-\(UUID().uuidString)",isDirectory:true)
        let store=WCommunityAttachmentStore(rootURL:root)
        defer{store.cleanup()}
        let bytes=try WCommunityPhotoPolicy.convertedBytes(from:communityPhotoFixture())
        let first=try store.saveDraft(bytes,id:"first")
        let published=try store.commit([first],forPost:"post-1")
        XCTAssertFalse(store.isDraft(published[0].url));XCTAssertTrue(store.isPublished(published[0].url));XCTAssertTrue(store.contains(published[0].url))
        let second=try store.saveDraft(bytes,id:"second")
        store.discardDraft([second])
        XCTAssertFalse(store.contains(second.url),"Discard removes a temporary draft file")
        XCTAssertTrue(store.contains(published[0].url),"Discard never removes a published post's file")
        store.releaseRemovedPublished(published,keeping:[])
        XCTAssertFalse(store.contains(published[0].url),"A saved edit removes a published file after replacement")
    }

    func testCommunityVideoPolicyEnforcesInputOutputAndMixedAttachmentLimits() throws {
        XCTAssertNoThrow(try WCommunityVideoPolicy.validateSource(size:50_000_000,duration:15,videoTrackCount:1))
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateSource(size:50_000_001,duration:15,videoTrackCount:1)){XCTAssertEqual($0 as? WCommunityVideoError,.inputTooLarge)}
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateSource(size:1,duration:15.01,videoTrackCount:1)){XCTAssertEqual($0 as? WCommunityVideoError,.duration)}
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateSource(size:1,duration:1,videoTrackCount:0)){XCTAssertEqual($0 as? WCommunityVideoError,.noVideoTrack)}
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateSource(size:0,duration:1,videoTrackCount:1)){XCTAssertEqual($0 as? WCommunityVideoError,.invalidVideo)}
        XCTAssertNoThrow(try WCommunityVideoPolicy.validateOutput(size:20_000_000,width:1920,height:1080))
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateOutput(size:20_000_001,width:1920,height:1080)){XCTAssertEqual($0 as? WCommunityVideoError,.outputTooLarge)}
        XCTAssertThrowsError(try WCommunityVideoPolicy.validateOutput(size:10,width:2560,height:1440)){XCTAssertEqual($0 as? WCommunityVideoError,.outputDimensions)}
        XCTAssertFalse(WCommunityVideoPolicy.canAppend(currentCount:9,currentBytes:0,addingCount:2,addingBytes:1))
        XCTAssertFalse(WCommunityVideoPolicy.canAppend(currentCount:1,currentBytes:99_000_000,addingCount:1,addingBytes:1_000_001))
        XCTAssertTrue(WCommunityVideoPolicy.canAppend(currentCount:10,currentBytes:100_000_000,addingCount:0,addingBytes:0))
    }

    func testCommunityVideoRejectsCorruptSyntheticSource() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("community-video-corrupt-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("corrupt.mp4")
        try Data("synthetic corrupt video".utf8).write(to:url)
        do{_ = try await WCommunityVideoTranscoder.inspectSource(url);XCTFail("Corrupt bytes must not be accepted as video")}
        catch let error as WCommunityVideoError{XCTAssertEqual(error,.invalidVideo)}
    }

    @MainActor func testCommunityVideoImportGenerationRejectsStaleRequests() {
        let coordinator=WCommunityMediaImportCoordinator()
        let first=coordinator.beginRequest()
        XCTAssertTrue(coordinator.accepts(first))
        let second=coordinator.beginRequest()
        XCTAssertFalse(coordinator.accepts(first),"A new picker selection invalidates work for the previous selection")
        XCTAssertTrue(coordinator.accepts(second))
        coordinator.invalidate()
        XCTAssertFalse(coordinator.accepts(second),"Discarding or changing draft invalidates pending conversion")
    }

    @MainActor func testCommunityVideoFileLifecycleUsesSyntheticMovieAndPoster() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("community-video-store-\(UUID().uuidString)",isDirectory:true)
        let store=WCommunityAttachmentStore(rootURL:root)
        defer{store.cleanup()}
        let working=try store.makeVideoWorkingURL()
        defer{store.removeTemporaryVideoFile(working)}
        try WCommunityVideoFixtureFactory.writeMP4(to:working)
        let movieType=UTType(filenameExtension:working.pathExtension)
        XCTAssertTrue(movieType?.conforms(to:.movie)==true,"The synthetic fixture is an MP4 movie")
        let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque=true
        let posterImage=UIGraphicsImageRenderer(size:CGSize(width:320,height:240),format:format).image { context in
            context.cgContext.setFillColor(UIColor(red:0.1,green:0.35,blue:0.7,alpha:1).cgColor)
            context.cgContext.fill(CGRect(x:0,y:0,width:320,height:240))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in:CGRect(x:0,y:82,width:72,height:72))
        }
        let posterData=try XCTUnwrap(posterImage.jpegData(compressionQuality:0.82))
        let size=try XCTUnwrap(working.resourceValues(forKeys:[.fileSizeKey]).fileSize)
        let fixtureMetadata=WCommunityVideoMetadata(size:size,duration:2,width:320,height:240)
        let draft=try store.stageConvertedVideo(at:working,posterData:posterData,metadata:fixtureMetadata,sourceIdentifier:"synthetic-review-video",fingerprint:"synthetic-review-video-fingerprint")
        XCTAssertTrue(store.contains(draft.url));XCTAssertTrue(store.contains(draft.posterURL));XCTAssertTrue(store.isDraft(draft.url))
        let poster=try XCTUnwrap(UIImage(contentsOfFile:draft.posterPath))
        XCTAssertEqual(poster.size,CGSize(width:320,height:240),"The generated JPEG poster remains readable at the fixture's dimensions")
        XCTAssertTrue(WCommunityVideoPolicy.canAppend(currentCount:0,currentBytes:0,addingCount:1,addingBytes:draft.byteCount))
        let inspected=try await WCommunityVideoTranscoder.inspectOutput(draft.url)
        XCTAssertEqual(inspected.width,320);XCTAssertEqual(inspected.height,240);XCTAssertLessThanOrEqual(inspected.duration,15)
        XCTAssertFalse(WCommunityVideoPolicy.isDuplicate(draft,in:[]))
        let committed=try store.commit([.video(draft)],forPost:"video-post")
        let first:WCommunityAttachment=try XCTUnwrap(committed.first)
        guard case .video(let published)=first else{return XCTFail("Committed attachment remains a video")}
        XCTAssertTrue(store.isPublished(published.url));XCTAssertTrue(store.isPublished(published.posterURL))
        XCTAssertTrue(WCommunityVideoPolicy.isDuplicate(published,in:committed))
        store.discardDraft(committed)
        XCTAssertTrue(store.contains(published.url),"Discard cannot delete committed media")
        store.releaseRemovedPublished(committed,keeping:[])
        XCTAssertFalse(store.contains(published.url));XCTAssertFalse(store.contains(published.posterURL))
    }

    @MainActor func testCommunityVideoTranscoderConvertsSyntheticMovieToBoundedMP4() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("community-video-convert-\(UUID().uuidString)",isDirectory:true)
        let store=WCommunityAttachmentStore(rootURL:root)
        defer{store.cleanup()}
        let source=try store.makeVideoWorkingURL()
        try WCommunityVideoFixtureFactory.writeMP4(to:source)
        let coordinator=WCommunityMediaImportCoordinator(),request=coordinator.beginRequest()
        let converted=try await WCommunityVideoTranscoder.convert(sourceURL:source,sourceIdentifier:"synthetic-fixture",store:store,coordinator:coordinator,request:request)
        XCTAssertFalse(store.contains(source),"The imported source is removed after conversion")
        XCTAssertTrue(store.contains(converted.url));XCTAssertTrue(store.contains(converted.posterURL))
        XCTAssertTrue(store.isDraft(converted.url));XCTAssertEqual(converted.sourceIdentifier,"synthetic-fixture")
        XCTAssertLessThanOrEqual(converted.byteCount,WCommunityVideoPolicy.maximumConvertedBytes)
        XCTAssertLessThanOrEqual(max(converted.width,converted.height),WCommunityVideoPolicy.maximumLongEdge)
        XCTAssertLessThanOrEqual(min(converted.width,converted.height),WCommunityVideoPolicy.maximumShortEdge)
        XCTAssertLessThanOrEqual(converted.duration,WCommunityVideoPolicy.maximumDuration)
        let inspected=try await WCommunityVideoTranscoder.inspectOutput(converted.url)
        XCTAssertEqual(inspected.size,converted.byteCount)
    }

    func testCommunityComposerSnapshotIncludesAttachmentIdentityAndOrder() {
        let original=WCommunityComposerSnapshot(screen:"C05",board:"러닝 인증",crewID:nil,postID:"p1",title:"제목",body:"본문",recordID:"",hideEnds:false,attachmentIDs:["a","b"])
        let reordered=WCommunityComposerSnapshot(screen:"C05",board:"러닝 인증",crewID:nil,postID:"p1",title:"제목",body:"본문",recordID:"",hideEnds:false,attachmentIDs:["b","a"])
        let removed=WCommunityComposerSnapshot(screen:"C05",board:"러닝 인증",crewID:nil,postID:"p1",title:"제목",body:"본문",recordID:"",hideEnds:false,attachmentIDs:["a"])
        XCTAssertNotEqual(original,reordered)
        XCTAssertNotEqual(original,removed)
    }

    func testCommunityNotificationCenterTracksReadStateAndEmptyState() {
        var center=WCommunityNotificationCenter()
        XCTAssertTrue(center.hasUnread)
        XCTAssertTrue(center.isUnread("community-welcome"))
        center.markRead("community-welcome")
        XCTAssertFalse(center.hasUnread)
        XCTAssertFalse(center.isUnread("community-welcome"))
        center.markRead("missing")
        XCTAssertEqual(center.readIDs,["community-welcome"])
        XCTAssertTrue(WCommunityNotificationCenter(notifications:[]).notifications.isEmpty)
    }

    func testCommunityNotificationDestinationsRejectMissingOrInaccessibleTargets() {
        let crews:Set<String>=["dawn","river"]
        let members:Set<String>=["dawn"]
        let applications:Set<String>=["river"]
        let posts:Set<String>=["p1"]
        XCTAssertEqual(WCommunityNotificationPolicy.destination(for:.feed,crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts),"C01")
        XCTAssertEqual(WCommunityNotificationPolicy.destination(for:.verification,crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts),"C11")
        XCTAssertEqual(WCommunityNotificationPolicy.destination(for:.application(crewID:"river"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts),"C18")
        XCTAssertNil(WCommunityNotificationPolicy.destination(for:.application(crewID:"deleted"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts))
        XCTAssertNil(WCommunityNotificationPolicy.destination(for:.application(crewID:"dawn"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts))
        XCTAssertEqual(WCommunityNotificationPolicy.destination(for:.crewBoard(crewID:"dawn"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts),"C19")
        XCTAssertNil(WCommunityNotificationPolicy.destination(for:.crewBoard(crewID:"river"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts))
        XCTAssertEqual(WCommunityNotificationPolicy.destination(for:.post(postID:"p1"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts),"C04")
        XCTAssertNil(WCommunityNotificationPolicy.destination(for:.post(postID:"blocked-or-deleted"),crewIDs:crews,memberCrewIDs:members,applicationCrewIDs:applications,accessiblePostIDs:posts))
    }

    func testCommunityPostManagementAllowsOnlyAuthorsToEditAndCrewManagersToDeleteCrewPosts() {
        let crew=WCommunityCrew(id:"crew",name:"강변 크루",introduction:"소개",region:"모브시 강변",guidance:"",ownerMemberID:"owner",memberIDs:["owner","operator","member"],minimumRank:0,tags:[],boards:[],operatorMemberIDs:["operator"])
        let crewPost=WCommunityPost(id:"crew-post",authorMemberID:"author",author:"작성자",rank:"시작러너",board:"자유게시판",title:"제목",text:"내용",date:"now",likes:0,views:0,comments:[],isCrewOnly:true,crewID:crew.id)
        XCTAssertFalse(WCommunityPostManagementPolicy.canEdit(crewPost,viewerID:"owner"))
        XCTAssertTrue(WCommunityPostManagementPolicy.canEdit(crewPost,viewerID:"author"))
        XCTAssertTrue(WCommunityPostManagementPolicy.canDelete(crewPost,viewerID:"owner",canManageCrew:WCommunityCrewPolicy.canManage(crew,viewerID:"owner")))
        XCTAssertTrue(WCommunityPostManagementPolicy.canDelete(crewPost,viewerID:"operator",canManageCrew:WCommunityCrewPolicy.canManage(crew,viewerID:"operator")))
        XCTAssertFalse(WCommunityPostManagementPolicy.canDelete(crewPost,viewerID:"member",canManageCrew:WCommunityCrewPolicy.canManage(crew,viewerID:"member")))
        XCTAssertFalse(WCommunityPostManagementPolicy.canDelete(crewPost,viewerID:"outsider",canManageCrew:WCommunityCrewPolicy.canManage(crew,viewerID:"outsider")))
        let publicPost=WCommunityPost(id:"public-post",authorMemberID:"author",author:"작성자",rank:"시작러너",board:"러닝 질문",title:"제목",text:"내용",date:"now",likes:0,views:0,comments:[])
        XCTAssertFalse(WCommunityPostManagementPolicy.canDelete(publicPost,viewerID:"owner",canManageCrew:true),"Crew roles never grant deletion rights on public posts")
    }

    func testCommunityPostEditUpdatesExistingPostAndPreservesUneditedData() {
        let comment=WCommunityComment(id:"comment",author:"작성자",authorMemberID:"author",text:"기존 댓글",date:"now")
        let post=WCommunityPost(id:"post-1",authorMemberID:"author",author:"작성자",rank:"열정러너",board:"러닝 인증",title:"기존 제목",text:"기존 내용",date:"now",likes:7,views:19,comments:[comment],imageName:"CommunityRiverside",hot:true,course:WCommunityCourseFixtures.sample)
        var posts=[post]
        XCTAssertTrue(WCommunityPostManagementPolicy.update("post-1",by:"author",board:"자유게시판",title:"  바뀐 제목  ",text:"  바뀐 내용  ",posts:&posts))
        XCTAssertEqual(posts.count,1,"Editing updates the existing post instead of inserting a duplicate")
        XCTAssertEqual(posts[0].id,"post-1");XCTAssertEqual(posts[0].board,"자유게시판");XCTAssertEqual(posts[0].title,"바뀐 제목");XCTAssertEqual(posts[0].text,"바뀐 내용")
        XCTAssertEqual(posts[0].authorMemberID,post.authorMemberID);XCTAssertEqual(posts[0].likes,7);XCTAssertEqual(posts[0].views,19)
        XCTAssertEqual(posts[0].comments.count,1);XCTAssertEqual(posts[0].comments[0].text,"기존 댓글")
        XCTAssertEqual(posts[0].imageName,"CommunityRiverside","Fixture media stays attached when text is edited")
        XCTAssertEqual(posts[0].course?.id,WCommunityCourseFixtures.sample.id,"Attached course details stay attached when text is edited")
        XCTAssertFalse(WCommunityPostManagementPolicy.update("post-1",by:"another",board:"러닝 인증",title:"무단 수정",text:"변경",posts:&posts))
        XCTAssertFalse(WCommunityPostManagementPolicy.update("post-1",by:"author",board:"러닝 인증",title:" ",text:"변경",posts:&posts))
        XCTAssertEqual(posts[0].title,"바뀐 제목","Rejected updates leave the saved post intact")
    }

    func testCrewPostEditPreservesItsStableBoardIdentityAndRejectsMissingBoardMetadata() {
        let post=WCommunityPost(id:"crew-post",authorMemberID:"author",author:"작성자",rank:"열정러너",board:"러닝 일정",title:"기존 제목",text:"기존 내용",date:"now",likes:0,views:0,comments:[],isCrewOnly:true,crewID:"dawn",crewBoardID:"dawn-board-1")
        var posts=[post]
        XCTAssertFalse(WCommunityPostManagementPolicy.update(post.id,by:"author",board:"새 이름",title:"변경 제목",text:"변경 내용",posts:&posts))
        XCTAssertEqual(posts[0].board,post.board,"A rejected update leaves the post unchanged")
        XCTAssertTrue(WCommunityPostManagementPolicy.update(post.id,by:"author",board:"새 이름",title:"변경 제목",text:"변경 내용",crewBoardID:"dawn-board-1",posts:&posts))
        XCTAssertEqual(posts.count,1)
        XCTAssertEqual(posts[0].id,post.id)
        XCTAssertEqual(posts[0].crewBoardID,"dawn-board-1")
        XCTAssertEqual(posts[0].board,"새 이름")
    }

    func testCrewManagerCommentDeletionTombstonesWithoutRemovingReplies() {
        let reply=WCommunityComment(id:"reply",author:"답글 작성자",authorMemberID:"reply-author",text:"답글 내용",date:"now",parentID:"parent")
        var comments=[WCommunityComment(id:"parent",author:"작성자",authorMemberID:"author",text:"댓글 내용",date:"now"),reply]
        XCTAssertFalse(WCommunityCommentActions.delete("parent",byMemberID:"member",to:&comments),"A regular crew member cannot delete someone else's comment")
        XCTAssertFalse(WCommunityCommentActions.delete("parent",byMemberID:"manager",canManageCrew:true,to:&comments),"A crew role cannot moderate a public-post comment")
        XCTAssertTrue(WCommunityCommentActions.delete("parent",byMemberID:"manager",canManageCrew:true,isCrewPost:true,to:&comments))
        XCTAssertEqual(comments.count,2,"Deleting a comment keeps descendant replies")
        XCTAssertTrue(comments[0].isDeleted)
        XCTAssertNil(comments[0].authorMemberID)
        XCTAssertEqual(comments[1].parentID,"parent")
        XCTAssertEqual(comments[1].text,"답글 내용")
    }

    func testCommunityPostDeleteRemovesOnlyAuthorizedPostAndItsReadState() {
        let deleted=WCommunityPost(id:"delete-me",authorMemberID:"author",author:"작성자",rank:"시작러너",board:"러닝 질문",title:"삭제할 글",text:"내용",date:"now",likes:0,views:0,comments:[WCommunityComment(id:"comment",author:"작성자",authorMemberID:"author",text:"댓글",date:"now")])
        let retained=WCommunityPost(id:"keep-me",authorMemberID:"other",author:"다른 러너",rank:"시작러너",board:"러닝 질문",title:"남길 글",text:"내용",date:"now",likes:0,views:0,comments:[])
        var posts=[deleted,retained]
        XCTAssertFalse(WCommunityPostManagementPolicy.delete("delete-me",by:"other",canManageCrew:false,posts:&posts))
        XCTAssertEqual(posts.map(\.id),["delete-me","keep-me"])
        var likes:Set<String>=["delete-me","keep-me"]
        var activity=WLocalCommunityActivityProvider(ownerMemberID:"viewer")
        let date=Date(timeIntervalSince1970:1_800_000_000)
        XCTAssertTrue(activity.recordView(viewerMemberID:"viewer",postID:"delete-me",date:date))
        var viewCounts=WLocalCommunityViewCountProvider()
        XCTAssertTrue(viewCounts.recordDetailView(viewerMemberID:"viewer",postID:"delete-me",authorMemberID:"author",date:date))
        XCTAssertTrue(WCommunityPostManagementPolicy.delete("delete-me",by:"author",canManageCrew:false,posts:&posts))
        likes.remove("delete-me");activity.remove(postID:"delete-me");viewCounts.remove(postID:"delete-me")
        XCTAssertEqual(posts.map(\.id),["keep-me"],"Removing the post also removes its nested comments")
        XCTAssertEqual(likes,["keep-me"])
        XCTAssertTrue(activity.recentPostIDs(viewerMemberID:"viewer",asOf:date).isEmpty)
        XCTAssertTrue(viewCounts.recordedKeys.isEmpty)
        XCTAssertNil(WCommunityNotificationPolicy.destination(for:.post(postID:"delete-me"),crewIDs:[],memberCrewIDs:[],applicationCrewIDs:[],accessiblePostIDs:Set(posts.map(\.id))))
    }

    func testCommunityCourseRequiresValidLocalRecordsAndClampsExamplePlayback() {
        let date=Date()
        let valid=RunRecord(date:date,title:"유효 예시",seconds:600,kilometers:2,isExample:true)
        let zeroDistance=RunRecord(date:date,title:"거리 없음",seconds:600,kilometers:0,isExample:true)
        let zeroTime=RunRecord(date:date,title:"시간 없음",seconds:0,kilometers:2,isExample:true)
        XCTAssertEqual(WCommunityCoursePolicy.eligibleRecords([valid,zeroDistance,zeroTime]).map(\.id),[valid.id])
        XCTAssertEqual(WCommunityCoursePolicy.pace(distance:2,seconds:600),"05:00 /km")
        XCTAssertEqual(WCommunityCoursePolicy.pace(distance:0,seconds:600),"0:00 /km")
        XCTAssertEqual(WCommunityCoursePolicy.playbackStep(0,duration:180).time,60)
        let end=WCommunityCoursePolicy.playbackStep(150,duration:180)
        XCTAssertEqual(end.time,180);XCTAssertTrue(end.finished)
    }

    func testCommunityCoursePostsKeepTheirOwnAuthorAndRecordSnapshots() {
        let first=RunRecord(date:Date(timeIntervalSince1970:100),title:"강변 기록",seconds:1808,kilometers:4.82,isExample:true)
        let second=RunRecord(date:Date(timeIntervalSince1970:200),title:"공원 기록",seconds:900,kilometers:3.4,isExample:true)
        let firstCourse=WCommunityCoursePolicy.makeCourse(id:"course-1",authorMemberID:"runner-a",authorName:"러너 A",authorRank:"열정러너",title:"강변 코스",introduction:"강변",hideEnds:true,record:first)
        let secondCourse=WCommunityCoursePolicy.makeCourse(id:"course-2",authorMemberID:"runner-b",authorName:"러너 B",authorRank:"새싹러너",title:"공원 코스",introduction:"공원",hideEnds:false,record:second)
        let firstPost=WCommunityPost(id:"post-1",authorMemberID:firstCourse.authorMemberID,author:firstCourse.authorName,rank:firstCourse.authorRank,board:"러닝 인증",title:firstCourse.title,text:firstCourse.introduction,date:"now",likes:0,views:0,comments:[],course:firstCourse)
        let secondPost=WCommunityPost(id:"post-2",authorMemberID:secondCourse.authorMemberID,author:secondCourse.authorName,rank:secondCourse.authorRank,board:"러닝 인증",title:secondCourse.title,text:secondCourse.introduction,date:"now",likes:0,views:0,comments:[],course:secondCourse)
        XCTAssertEqual(firstPost.course?.id,"course-1");XCTAssertEqual(firstPost.author,"러너 A")
        XCTAssertEqual(firstPost.course?.record.title,"강변 기록");XCTAssertEqual(firstPost.course?.record.distance,4.82);XCTAssertEqual(firstPost.course?.record.seconds,1808)
        XCTAssertEqual(secondPost.course?.id,"course-2");XCTAssertEqual(secondPost.author,"러너 B")
        XCTAssertEqual(secondPost.course?.record.title,"공원 기록");XCTAssertEqual(secondPost.course?.record.distance,3.4);XCTAssertEqual(secondPost.course?.record.seconds,900)
        XCTAssertNotEqual(firstPost.course,secondPost.course,"Each post carries its own course snapshot")
    }

    func testCommunityCoursePublicationRechecksIdentityAndCurrentRecord() {
        let valid=RunRecord(date:Date(),title:"유효",seconds:500,kilometers:2)
        let invalid=RunRecord(date:Date(),title:"무효",seconds:0,kilometers:2)
        XCTAssertTrue(isUnauthenticated(WCommunityCoursePolicy.publicationResult(accountVerified:false,draftOwnerID:"me",viewerID:"me",selectedRecordID:valid.id.uuidString,records:[valid])))
        XCTAssertTrue(isOwnerChanged(WCommunityCoursePolicy.publicationResult(accountVerified:true,draftOwnerID:"old",viewerID:"me",selectedRecordID:valid.id.uuidString,records:[valid])))
        XCTAssertTrue(isMissingRecord(WCommunityCoursePolicy.publicationResult(accountVerified:true,draftOwnerID:"me",viewerID:"me",selectedRecordID:UUID().uuidString,records:[valid])))
        XCTAssertTrue(isInvalidRecord(WCommunityCoursePolicy.publicationResult(accountVerified:true,draftOwnerID:"me",viewerID:"me",selectedRecordID:invalid.id.uuidString,records:[invalid])))
        guard case .eligible(let selected)=WCommunityCoursePolicy.publicationResult(accountVerified:true,draftOwnerID:"me",viewerID:"me",selectedRecordID:valid.id.uuidString,records:[valid]) else{return XCTFail("Current verified owner can publish an existing valid local record")}
        XCTAssertEqual(selected.id,valid.id)
    }
    private func isUnauthenticated(_ result:WCommunityCoursePublicationResult)->Bool{if case .unauthenticated=result{return true};return false}
    private func isOwnerChanged(_ result:WCommunityCoursePublicationResult)->Bool{if case .ownerChanged=result{return true};return false}
    private func isMissingRecord(_ result:WCommunityCoursePublicationResult)->Bool{if case .missingRecord=result{return true};return false}
    private func isInvalidRecord(_ result:WCommunityCoursePublicationResult)->Bool{if case .invalidRecord=result{return true};return false}

    func testCommunityCrewApplicationChecksMembershipCapacityRankAndMemo() {
        let viewer="fixture-member-current",river=WCommunityCrewFixtures.values.first{$0.id=="river"}!,dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!,full=WCommunityCrewFixtures.values.first{$0.id=="full"}!
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:"토요일에 함께 달리고 싶어요.",current:nil),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:nil,viewerID:viewer,rank:1,memo:"",current:nil),.missingCrew)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:dawn,viewerID:viewer,rank:1,memo:"",current:nil),.alreadyMember)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:"",current:WCommunityCrewApplication(id:"pending",crewID:river.id,applicantMemberID:viewer,memo:"",status:.pending)),.alreadyPending)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:full,viewerID:viewer,rank:4,memo:"",current:nil),.full)
        XCTAssertEqual(full.memberIDs.count,WCommunityCrewPolicy.memberCapacity)
        XCTAssertTrue(full.memberIDs.contains(full.ownerMemberID),"The owner is included in the 20-member limit")
        let rejectedAt=Date(timeIntervalSince1970:1_000_000)
        let rejected=WCommunityCrewApplication(id:"rejected",crewID:river.id,applicantMemberID:viewer,memo:"",status:.rejected,rejectedAt:rejectedAt)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:"",current:rejected,now:rejectedAt.addingTimeInterval(WCommunityCrewPolicy.rejectionCooldown-1)),.rejectedRecently)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:"",current:rejected,now:rejectedAt.addingTimeInterval(WCommunityCrewPolicy.rejectionCooldown)),.ready,"Exactly 24 hours has elapsed")
        let cancelled=WCommunityCrewApplication(id:"cancelled",crewID:river.id,applicantMemberID:viewer,memo:"",status:.cancelled)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:"",current:cancelled,now:rejectedAt.addingTimeInterval(60)),.ready,"Cancellation allows an immediate new application")
        let rankLimited=WCommunityCrew(id:"rank",name:"등급 예시",introduction:"",region:"",guidance:"",ownerMemberID:"owner",memberIDs:["owner"],minimumRank:3,tags:[],boards:[])
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:rankLimited,viewerID:viewer,rank:1,memo:"",current:nil),.rankRequired)
        XCTAssertEqual(WCommunityCrewPolicy.applicationResult(crew:river,viewerID:viewer,rank:1,memo:String(repeating:"가",count:301),current:nil),.invalidMemo)
    }

    func testCommunityCrewBoardsRequireMembershipAndKeepSamplePostsScoped() {
        let river=WCommunityCrewFixtures.values.first{$0.id=="river"}!,dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!,viewer="fixture-member-current"
        XCTAssertTrue(WCommunityCrewPolicy.canReadBoard(crew:dawn,memberIDs:[],viewerID:viewer))
        XCTAssertFalse(WCommunityCrewPolicy.canReadBoard(crew:river,memberIDs:[],viewerID:viewer))
        XCTAssertTrue(WCommunityCrewPolicy.canReadBoard(crew:river,memberIDs:[river.id],viewerID:viewer))
        let crewPosts=WCommunityFixtures.posts.filter{$0.crewID != nil}
        XCTAssertTrue(crewPosts.contains{$0.id=="dawn-notice-1" && $0.crewBoardID==dawn.boards[0].id && $0.title=="이번 주 러닝 안내"})
        XCTAssertFalse(crewPosts.contains{$0.crewID==river.id && $0.crewBoardID==dawn.boards[0].id},"Posts stay scoped by crew and stable board identity")
        XCTAssertEqual(crewPosts.first{$0.id=="river-run-1"}?.comments.count,2,"Crew post comments use the same detail model")
    }

    func testCrewPostsNeverEnterPublicFeedSearchOrHotResults() {
        let crewPosts=WCommunityFixtures.posts.filter{$0.crewID != nil}
        XCTAssertTrue(WCommunityDiscoveryPolicy.publicPosts(WCommunityFixtures.posts).allSatisfy{$0.crewID==nil && !$0.isCrewOnly})
        XCTAssertFalse(WCommunityDiscoveryPolicy.searchPosts(WCommunityFixtures.posts,query:"회원에게만 공개되는 러닝 인증 예시").contains{$0.id=="river-run-1"})
        let crewPostIDs=Set(crewPosts.map(\.id))
        XCTAssertTrue(WCommunityDiscoveryPolicy.hotPosts(WCommunityFixtures.posts).allSatisfy{!crewPostIDs.contains($0.id)})
    }

    func testCommunityCrewCreateAndEditPolicyUsesLocalReviewRules() {
        let dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!,river=WCommunityCrewFixtures.values.first{$0.id=="river"}!,viewer="fixture-member-current"
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"새벽 크루",introduction:"함께 천천히 달려요.",region:"모브시 중앙",minimumRank:0,existing:[dawn,river],editingID:nil,viewerID:viewer),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"  모브   새벽 크루 ",introduction:"소개",region:"모브시 중앙",minimumRank:0,existing:[dawn],editingID:nil,viewerID:viewer),.duplicateName)
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"MÖVE RUN CLUB",introduction:"소개",region:"모브시 중앙",minimumRank:0,existing:[WCommunityCrew(id:"english",name:"möve run club",introduction:"",region:"",guidance:"",ownerMemberID:viewer,memberIDs:[viewer],minimumRank:0,tags:[],boards:[])],editingID:nil,viewerID:viewer),.duplicateName,"NFC and English case variants share one canonical name")
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"",introduction:"소개",region:"모브시 중앙",minimumRank:0,existing:[dawn],editingID:nil,viewerID:viewer),.invalidName)
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"새 크루",introduction:String(repeating:"가",count:301),region:"모브시 중앙",minimumRank:0,existing:[dawn],editingID:nil,viewerID:viewer),.invalidIntroduction)
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"크루",introduction:"소개",region:"없는 지역",minimumRank:0,existing:[],editingID:nil,viewerID:viewer),.invalidRegion)
        XCTAssertEqual(WCommunityCrewPolicy.saveResult(name:"강변 크루",introduction:"소개",region:"모브시 강변",minimumRank:0,existing:[river],editingID:river.id,viewerID:viewer),.unauthorized)
    }

    func testCommunityCrewReviewEnforcesManagerCapacityAndApplicantRank() {
        let dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!,request=WCommunityCrewFixtures.applications[0],viewer="fixture-member-current"
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:request,crew:dawn,applicantRank:1,viewerID:viewer,approve:true),.approved)
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:request,crew:dawn,applicantRank:1,viewerID:"fixture-member-early",approve:true),.unauthorized)
        var operatorManaged=dawn;operatorManaged.memberIDs.append("fixture-operator");operatorManaged.operatorMemberIDs.insert("fixture-operator")
        XCTAssertTrue(WCommunityCrewPolicy.canManage(operatorManaged,viewerID:"fixture-operator"))
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:request,crew:operatorManaged,applicantRank:1,viewerID:"fixture-operator",approve:false),.rejected)
        let rankLimited=WCommunityCrew(id:"rank",name:"등급 예시",introduction:"",region:"",guidance:"",ownerMemberID:viewer,memberIDs:[viewer],minimumRank:3,tags:[],boards:[])
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:WCommunityCrewApplication(id:"rank-request",crewID:"rank",applicantMemberID:"fixture-member-early",memo:"",status:.pending),crew:rankLimited,applicantRank:1,viewerID:viewer,approve:true),.rankRequired)
        let full=WCommunityCrew(id:"full",name:"정원 예시",introduction:"",region:"",guidance:"",ownerMemberID:viewer,memberIDs:[viewer] + (1..<WCommunityCrewPolicy.memberCapacity).map{"member\($0)"},minimumRank:0,tags:[],boards:[])
        XCTAssertEqual(full.memberIDs.count,WCommunityCrewPolicy.memberCapacity)
        XCTAssertTrue(full.memberIDs.contains(full.ownerMemberID))
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:WCommunityCrewApplication(id:"full-request",crewID:"full",applicantMemberID:"fixture-member-early",memo:"",status:.pending),crew:full,applicantRank:1,viewerID:viewer,approve:true),.full)
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:WCommunityCrewApplication(id:"done",crewID:"dawn",applicantMemberID:"fixture-member-early",memo:"",status:.rejected),crew:dawn,applicantRank:1,viewerID:viewer,approve:false),.notPending)
        var nineteen=dawn;nineteen.memberIDs=[viewer] + (1..<19).map{"member\($0)"}
        let approval=WCommunityCrewApplication(id:"last-seat",crewID:dawn.id,applicantMemberID:"fixture-member-early",memo:"",status:.pending)
        XCTAssertEqual(nineteen.memberIDs.count,19)
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:approval,crew:nineteen,applicantRank:1,viewerID:viewer,approve:true),.approved)
        nineteen.memberIDs.append(approval.applicantMemberID)
        XCTAssertEqual(nineteen.memberIDs.count,20)
        let nextApproval=WCommunityCrewApplication(id:"next-seat",crewID:dawn.id,applicantMemberID:"another-applicant",memo:"",status:.pending)
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:nextApproval,crew:nineteen,applicantRank:1,viewerID:viewer,approve:true),.full,"A subsequent approval cannot exceed 20 total members")
        var resolved=approval;resolved.status = .approved
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:resolved,crew:nineteen,applicantRank:1,viewerID:viewer,approve:true),.notPending,"An already resolved application cannot be approved twice")
        var rejected=approval;rejected.status = .rejected;rejected.rejectedAt=Date()
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:rejected,crew:dawn,applicantRank:1,viewerID:viewer,approve:false),.notPending,"A repeated rejection does not rewrite an already resolved decision")
        XCTAssertFalse(WCommunityCrewPolicy.canManage(dawn,viewerID:"ordinary-member"))
        XCTAssertEqual(WCommunityCrewPolicy.reviewResult(application:approval,crew:dawn,applicantRank:1,viewerID:"ordinary-member",approve:false),.unauthorized)
    }

    func testCommunityCrewMemberRolesCanOnlyBeChangedByOwner() {
        let crew=WCommunityCrew(id:"members",name:"멤버 예시",introduction:"",region:"",guidance:"",ownerMemberID:"owner",memberIDs:["owner","operator","member"],minimumRank:0,tags:[],boards:[],operatorMemberIDs:["operator"])
        XCTAssertEqual(WCommunityCrewPolicy.role(of:"owner",in:crew),.owner)
        XCTAssertEqual(WCommunityCrewPolicy.role(of:"operator",in:crew),.crewOperator)
        XCTAssertEqual(WCommunityCrewPolicy.role(of:"member",in:crew),.member)
        XCTAssertEqual(WCommunityCrewPolicy.role(of:"outsider",in:crew),.outsider)
        XCTAssertEqual(WCommunityCrewPolicy.roleChangeResult(crew:crew,actorID:"owner",targetMemberID:"member"),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.roleChangeResult(crew:crew,actorID:"owner",targetMemberID:"operator"),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.roleChangeResult(crew:crew,actorID:"operator",targetMemberID:"member"),.ownerOnly)
        XCTAssertEqual(WCommunityCrewPolicy.roleChangeResult(crew:crew,actorID:"owner",targetMemberID:"owner"),.ownerProtected)
        XCTAssertEqual(WCommunityCrewPolicy.roleChangeResult(crew:crew,actorID:"owner",targetMemberID:"outsider"),.missingMember)
    }

    func testCommunityCrewMemberActionsProtectOwnerSelfAndPeerOperators() {
        let crew=WCommunityCrew(id:"members",name:"멤버 예시",introduction:"",region:"",guidance:"",ownerMemberID:"owner",memberIDs:["owner","operator","peer-operator","member"],minimumRank:0,tags:[],boards:[],operatorMemberIDs:["operator","peer-operator"])
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"member",kind:.warn,note:"주의 내용"),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"operator",kind:.kick),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"operator",targetMemberID:"member",kind:.kick),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"operator",targetMemberID:"peer-operator",kind:.kick),.peerOperatorProtected)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"operator",targetMemberID:"owner",kind:.kick),.ownerProtected)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"operator",targetMemberID:"operator",kind:.kick),.selfProtected)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"member",targetMemberID:"operator",kind:.kick),.unauthorized)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"outsider",kind:.kick),.notMember)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"member",kind:.warn,note:" \n "),.emptyNote)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"member",kind:.warn,note:String(repeating:"가",count:301)),.noteTooLong)
        XCTAssertEqual(WCommunityCrewPolicy.memberActionResult(crew:crew,actorID:"owner",targetMemberID:"member",kind:.warn,note:String(repeating:"가",count:300)),.ready)
    }

    func testCommunityCrewBoardArchiveAndRestoreUseActiveFiveBoardLimit() {
        let owner="fixture-member-current",dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!
        let archived=WCommunityCrewBoard(id:"archived",title:"기존 글 보관",status:.archived)
        var fourActive=dawn;fourActive.boards.append(archived)
        XCTAssertEqual(WCommunityCrewPolicy.activeBoardCount(in:fourActive),4)
        XCTAssertEqual(WCommunityCrewPolicy.boardCreateResult(crew:fourActive,actorID:owner,name:"새 게시판"),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.boardRestoreResult(crew:fourActive,actorID:owner,boardID:archived.id),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.boardArchiveResult(crew:fourActive,actorID:owner,boardID:dawn.boards[1].id),.ready,"A board with posts may be archived without deleting its content")

        var fiveActive=fourActive
        fiveActive.boards.append(WCommunityCrewBoard(id:"fifth",title:"다섯 번째"))
        XCTAssertEqual(WCommunityCrewPolicy.activeBoardCount(in:fiveActive),5)
        XCTAssertEqual(WCommunityCrewPolicy.boardCreateResult(crew:fiveActive,actorID:owner,name:"여섯 번째"),.activeLimit)
        XCTAssertEqual(WCommunityCrewPolicy.boardRestoreResult(crew:fiveActive,actorID:owner,boardID:archived.id),.activeLimit)
        XCTAssertEqual(WCommunityCrewPolicy.boardCreateResult(crew:fiveActive,actorID:"fixture-member-early",name:"일반 멤버"),.unauthorized)
    }

    func testCommunityCrewBoardNamesMatchBackendGraphemeLimitAndArchivedBoardsCannotBeRenamed() {
        let owner="fixture-member-current",dawn=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!
        XCTAssertEqual(WCommunityCrewPolicy.boardRenameResult(crew:dawn,actorID:owner,boardID:dawn.boards[1].id,name:String(repeating:"가",count:60)),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.boardRenameResult(crew:dawn,actorID:owner,boardID:dawn.boards[1].id,name:String(repeating:"가",count:61)),.invalidName)
        var archived=dawn;archived.boards[1].status = .archived
        XCTAssertEqual(WCommunityCrewPolicy.boardRenameResult(crew:archived,actorID:owner,boardID:dawn.boards[1].id,name:"이름 변경"),.archivedBoard)
        XCTAssertEqual(WCommunityCrewPolicy.boardRenameResult(crew:dawn,actorID:owner,boardID:"missing",name:"이름 변경"),.missingBoard)
    }

    func testCommunityCrewGuidanceAndLocalAnnouncementStayWithinBackendLimits() {
        let owner="fixture-member-current",crew=WCommunityCrewFixtures.values.first{$0.id=="dawn"}!
        XCTAssertEqual(WCommunityCrewPolicy.guidanceLimit,500)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:owner,title:"토요일 모임",text:"아침 8시에 만나요."),.ready)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:"fixture-member-early",title:"토요일 모임",text:"아침 8시에 만나요."),.unauthorized)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:owner,title:"",text:"내용"),.emptyTitle)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:owner,title:"제목",text:" \n "),.emptyText)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:owner,title:String(repeating:"가",count:61),text:"내용"),.titleTooLong)
        XCTAssertEqual(WCommunityCrewPolicy.announcementResult(crew:crew,actorID:owner,title:"제목",text:String(repeating:"가",count:301)),.textTooLong)
    }

    func testCommunityVerificationRequiresApplicationAndOperatorDecision() {
        var state=WCommunityVerificationState()
        XCTAssertEqual(state.submit(" \n "),.invalidActivity)
        XCTAssertEqual(state.submit(String(repeating:"가",count:301)),.invalidActivity)
        XCTAssertFalse(state.review(as:.approved),"An operator cannot decide before submission")
        XCTAssertEqual(state.submit("러닝 활동을 소개합니다."),.submitted)
        XCTAssertEqual(state.status,.pending)
        XCTAssertFalse(state.isVerified)
        XCTAssertEqual(state.submit("다른 신청"),.alreadyPending,"Pending applications get a state error, not an input error")
        XCTAssertTrue(state.review(as:.rejected))
        XCTAssertFalse(state.isVerified)
        XCTAssertEqual(state.reason,"신청 내용을 조금 더 구체적으로 적어 주세요.")
        XCTAssertEqual(state.submit("내용을 보완해 다시 신청합니다."),.submitted)
        XCTAssertTrue(state.review(as:.approved))
        XCTAssertEqual(state.status,.approved)
        XCTAssertTrue(state.isVerified)
        XCTAssertEqual(state.submit("다시 신청"),.alreadyApproved)
        let decoded=try? JSONDecoder().decode(WCommunityVerificationState.self,from:JSONEncoder().encode(state))
        XCTAssertEqual(decoded?.status,.approved,"Approval status survives local serialization")
        XCTAssertFalse(state.review(as:.rejected),"A reviewed application cannot be changed again")
    }

    func testCommunityModerationReportReasonsDetailAndLimits() {
        let target=WCommunityReportTarget.member("fixture-member-ga-on")
        for reason in WLocalCommunityModerationProvider.reportReasons {
            var provider=WLocalCommunityModerationProvider()
            XCTAssertTrue(provider.submitReport(target,reason:reason,detail:"상세 내용"),reason)
            XCTAssertEqual(provider.reports.first?.detail,"상세 내용")
        }
        var provider=WLocalCommunityModerationProvider()
        XCTAssertTrue(provider.submitReport(target,reason:"기타",detail:String(repeating:"가",count:300)))
        XCTAssertFalse(provider.submitReport(target,reason:"기타",detail:String(repeating:"가",count:301)))
        XCTAssertFalse(provider.submitReport(target,reason:"기타 아님",detail:""))
    }

    func testCommunityModerationBlockIsSymmetricAndUnblockRestoresVisibility() {
        let me="fixture-member-current",target="fixture-member-ga-on",known=Set([me,target])
        var provider=WLocalCommunityModerationProvider()
        XCTAssertFalse(provider.block(me,viewerID:me,knownUsers:known))
        XCTAssertFalse(provider.block("unknown",viewerID:me,knownUsers:known))
        XCTAssertTrue(provider.block(target,viewerID:me,anonymous:true,knownUsers:known))
        XCTAssertFalse(provider.block(target,viewerID:me,knownUsers:known))
        XCTAssertTrue(provider.shouldHide(authorID:target,viewerID:me,ownerID:me))
        XCTAssertTrue(provider.shouldHide(authorID:me,viewerID:target,ownerID:me))
        XCTAssertTrue(provider.anonymousBlockedMemberIDs.contains(target))
        XCTAssertTrue(provider.unblock(target,viewerID:me))
        XCTAssertFalse(provider.shouldHide(authorID:target,viewerID:me,ownerID:me))
        XCTAssertFalse(provider.shouldHide(authorID:me,viewerID:target,ownerID:me))
        XCTAssertFalse(provider.unblock(target,viewerID:me))
    }

    func testCommunityAnonymousOriginCannotOpenProfileButNamedProfilesCan() {
        let me="fixture-member-current",target="fixture-member-ga-on",known=Set([me,target])
        var provider=WLocalCommunityModerationProvider()
        XCTAssertTrue(provider.canOpenProfile(memberID:target,viewerID:me,ownerID:me,anonymousOrigin:false))
        XCTAssertFalse(provider.canOpenProfile(memberID:target,viewerID:me,ownerID:me,anonymousOrigin:true))
        XCTAssertTrue(provider.block(target,viewerID:me,knownUsers:known))
        XCTAssertFalse(provider.canOpenProfile(memberID:target,viewerID:me,ownerID:me,anonymousOrigin:false))
        XCTAssertTrue(provider.unblock(target,viewerID:me))
        XCTAssertTrue(provider.canOpenProfile(memberID:target,viewerID:me,ownerID:me,anonymousOrigin:false))
    }

    func testCommunityProfileDraftDetectsEveryFieldAndReversion() {
        let saved=WLocalProfile()
        var draft=WCommunityProfileDraft(profile:saved)
        XCTAssertFalse(draft.differs(from:saved))
        draft.nickname="저녁러너"
        XCTAssertTrue(draft.differs(from:saved))
        draft.nickname=saved.nickname
        XCTAssertFalse(draft.differs(from:saved),"Restoring the edited nickname is clean")
        draft=WCommunityProfileDraft(profile:saved);draft.introduction="오늘도 달려요"
        XCTAssertTrue(draft.differs(from:saved))
        draft=WCommunityProfileDraft(profile:saved);draft.region="모브시 남부권"
        XCTAssertTrue(draft.differs(from:saved))
        draft=WCommunityProfileDraft(profile:saved);draft.photo=WProfilePhotoPolicy.encode(image:WProfilePhotoPolicy.reviewCaptureFixture(),crop:CGRect(x:0,y:0,width:400,height:400))
        XCTAssertTrue(draft.differs(from:saved))
        draft=WCommunityProfileDraft(nickname:saved.nickname,introduction:saved.introduction,region:saved.region,photo:saved.photo)
        XCTAssertFalse(draft.differs(from:saved),"Restoring every field to its saved value should be clean")
    }

    func testCommunityFollowProviderUpdatesFollowerAndFollowingCounts() {
        var follows=WLocalCommunityFollowProvider()
        let me="fixture-member-current",gaon="fixture-member-ga-on",noeul="fixture-member-no-eul",early="fixture-member-early"
        let known=Set([me,gaon,noeul,early])
        XCTAssertEqual(follows.followerIDs(for:gaon,viewer:me),Set([noeul,early]))
        XCTAssertEqual(follows.followingIDs(for:gaon,viewer:me),Set([noeul,me]))
        XCTAssertTrue(follows.toggle(gaon,viewer:me,knownUsers:known))
        XCTAssertTrue(follows.viewerFollows.contains(gaon))
        XCTAssertEqual(follows.followerIDs(for:gaon,viewer:me),Set([noeul,early,me]))
        XCTAssertEqual(follows.followingIDs(for:me,viewer:me),Set([gaon]))
        XCTAssertTrue(follows.toggle(gaon,viewer:me,knownUsers:known))
        XCTAssertFalse(follows.viewerFollows.contains(gaon))
        XCTAssertFalse(follows.toggle(me,viewer:me,knownUsers:known),"A viewer cannot follow themself")
        XCTAssertFalse(follows.toggle("unknown",viewer:me,knownUsers:known))
    }

    func testCommunityRepliesAreUnlimitedAndDeletionKeepsDescendants() {
        var comments=[WCommunityComment(id:"root",author:"러너",authorMemberID:"member-root",text:"root text",date:"now")]
        XCTAssertTrue(WCommunityCommentActions.add(" first ",author:"나",authorMemberID:"member-me",date:"now",parentID:"root",to:&comments))
        let first=comments[1].id
        XCTAssertTrue(WCommunityCommentActions.add("second",author:"나",authorMemberID:"member-me",date:"now",parentID:first,to:&comments))
        let second=comments[2].id
        XCTAssertTrue(WCommunityCommentActions.add("third",author:"나",authorMemberID:"member-me",date:"now",parentID:second,to:&comments))
        XCTAssertTrue(WCommunityCommentActions.delete(first,byMemberID:"member-me",to:&comments))
        XCTAssertTrue(comments.first{$0.id==first}?.isDeleted == true)
        XCTAssertEqual(comments.first{$0.id==first}?.author,"")
        XCTAssertNil(comments.first{$0.id==first}?.authorMemberID)
        XCTAssertEqual(comments.first{$0.id==second}?.parentID,first)
        XCTAssertEqual(comments.first{$0.id=="root"}?.text,"root text")
        XCTAssertFalse(WCommunityCommentActions.delete("root",byMemberID:"member-me",to:&comments))
        XCTAssertFalse(WCommunityCommentActions.add("orphan",author:"나",authorMemberID:"member-me",date:"now",parentID:"missing",to:&comments))
        let namedDifferently=WCommunityComment(id:"author-reply",author:"표시명 변경",authorMemberID:"member-root",text:"reply",date:"now")
        let sameNameOtherMember=WCommunityComment(id:"impostor",author:"러너",authorMemberID:"other",text:"reply",date:"now")
        XCTAssertTrue(WCommunityCommentActions.isPostAuthor(namedDifferently,postAuthorMemberID:"member-root"))
        XCTAssertFalse(WCommunityCommentActions.isPostAuthor(sameNameOtherMember,postAuthorMemberID:"member-root"))
        var tombstone=namedDifferently;tombstone.isDeleted=true
        XCTAssertFalse(WCommunityCommentActions.isPostAuthor(tombstone,postAuthorMemberID:"member-root"))
    }

    func testCommunityViewCountPolicyUsesMemberPostAndKSTDayAndSkipsAuthor() {
        var provider=WLocalCommunityViewCountProvider()
        let viewer="member-viewer",post="post-1",author="member-author"
        let beforeKSTMidnight=ISO8601DateFormatter().date(from:"2026-10-10T14:59:59Z")!
        let afterKSTMidnight=ISO8601DateFormatter().date(from:"2026-10-10T15:00:00Z")!
        XCTAssertTrue(provider.recordDetailView(viewerMemberID:viewer,postID:post,authorMemberID:author,date:beforeKSTMidnight))
        XCTAssertFalse(provider.recordDetailView(viewerMemberID:viewer,postID:post,authorMemberID:author,date:beforeKSTMidnight.addingTimeInterval(0.5)))
        XCTAssertTrue(provider.recordDetailView(viewerMemberID:"another-member",postID:post,authorMemberID:author,date:beforeKSTMidnight))
        XCTAssertTrue(provider.recordDetailView(viewerMemberID:viewer,postID:"post-2",authorMemberID:author,date:beforeKSTMidnight))
        XCTAssertTrue(provider.recordDetailView(viewerMemberID:viewer,postID:post,authorMemberID:author,date:afterKSTMidnight))
        XCTAssertFalse(provider.recordDetailView(viewerMemberID:viewer,postID:"own-post",authorMemberID:viewer,date:beforeKSTMidnight))
        XCTAssertEqual(WCommunityTextLimit.apply(String(repeating:"가",count:61),limit:WCommunityTextLimit.title).count,60)
        XCTAssertEqual(WCommunityTextLimit.apply(String(repeating:"나",count:2001),limit:WCommunityTextLimit.body).count,2000)
        XCTAssertEqual(WCommunityTextLimit.apply(String(repeating:"다",count:301),limit:WCommunityTextLimit.comment).count,300)
    }

    func testCommunityDiscoveryNormalizesQueriesAndKeepsPrivateContentOutOfPublicResults() {
        func post(_ id:String,board:String="러닝 질문",title:String,hot:Bool=false,crewOnly:Bool=false)->WCommunityPost {
            WCommunityPost(id:id,authorMemberID:"author-\(id)",author:"러너",rank:"시작러너",board:board,title:title,text:"오늘 강변을 달려요",date:"now",likes:0,views:0,comments:[],hot:hot,isCrewOnly:crewOnly)
        }
        let publicHot=post("public-hot",title:"Café 강변",hot:true)
        let publicRegular=post("public-regular",title:"비 오는 날",hot:false)
        let anonymous=post("anonymous",board:"익명게시판",title:"Café 비밀",hot:true)
        let crewOnly=post("crew-only",title:"Café 멤버 글",hot:true,crewOnly:true)
        let posts=[publicHot,publicRegular,anonymous,crewOnly]

        XCTAssertTrue(WCommunityDiscoveryPolicy.matches("  café  ",query:"CAFE\u{0301}"),"Search trims and compares canonical Unicode text without case sensitivity")
        XCTAssertTrue(WCommunityDiscoveryPolicy.matches("강변 러닝",query:"강변"),"Composed and decomposed Hangul queries match")
        XCTAssertFalse(WCommunityDiscoveryPolicy.matches("강변 러닝",query:" \n "),"An empty query never becomes a match-all search")
        XCTAssertEqual(WCommunityDiscoveryPolicy.searchPosts(posts,query:"café").map(\.id),["public-hot"])
        XCTAssertEqual(WCommunityDiscoveryPolicy.hotPosts(posts).map(\.id),["public-hot"],"HOT uses only explicit public fixture flags and preserves feed order")
        XCTAssertTrue(WCommunityDiscoveryPolicy.hotPosts([publicRegular]).isEmpty,"No score or implicit fallback creates HOT entries")

        let runners=[WCommunityRunner(id:"visible",name:"Café Runner",rank:"시작러너",introduction:"",region:"",averageDistance:0,verified:false),WCommunityRunner(id:"blocked",name:"Café Blocked",rank:"시작러너",introduction:"",region:"",averageDistance:0,verified:false)]
        XCTAssertEqual(WCommunityDiscoveryPolicy.searchRunners(runners,query:"café",blockedIDs:["blocked"]).map(\.id),["visible"])
        let crew=WCommunityCrew(id:"crew",name:"모브 새벽 크루",introduction:"강변에서 함께 달려요",region:"",guidance:"",ownerMemberID:"owner",memberIDs:["owner"],minimumRank:0,tags:[],boards:[])
        let blockedCrew=WCommunityCrew(id:"blocked-crew",name:"모브 강변 크루",introduction:"같이 달려요",region:"",guidance:"",ownerMemberID:"blocked",memberIDs:["blocked"],minimumRank:0,tags:[],boards:[])
        XCTAssertEqual(WCommunityDiscoveryPolicy.searchCrews([crew,blockedCrew],query:"강변",blockedOwnerIDs:["blocked"]).map(\.id),["crew"])
    }

    func testCommunityActivityHistoryIsPrivateRecentDeduplicatedAndBounded() {
        let owner="member-owner",other="member-other"
        let now=ISO8601DateFormatter().date(from:"2026-10-10T00:00:00Z")!
        var provider=WLocalCommunityActivityProvider(ownerMemberID:owner)
        XCTAssertFalse(provider.recordView(viewerMemberID:other,postID:"private-post",date:now))
        XCTAssertEqual(provider.recentPostIDs(viewerMemberID:other,asOf:now),[])
        XCTAssertTrue(provider.recordView(viewerMemberID:owner,postID:"old-post",date:now.addingTimeInterval(-91*24*60*60)))
        XCTAssertTrue(provider.recordView(viewerMemberID:owner,postID:"90-day-boundary",date:now.addingTimeInterval(-WLocalCommunityActivityProvider.retention)))
        XCTAssertTrue(provider.recordView(viewerMemberID:owner,postID:"first",date:now.addingTimeInterval(-120)))
        XCTAssertTrue(provider.recordView(viewerMemberID:owner,postID:"second",date:now.addingTimeInterval(-60)))
        XCTAssertTrue(provider.recordView(viewerMemberID:owner,postID:"first",date:now.addingTimeInterval(-30)))
        XCTAssertEqual(provider.recentPostIDs(viewerMemberID:owner,asOf:now),["first","second","90-day-boundary"])
        XCTAssertEqual(provider.visits.filter{$0.postID=="first"}.count,1,"A repeat visit moves the post to the newest position without a duplicate")

        var bounded=WLocalCommunityActivityProvider(ownerMemberID:owner)
        for index in 0...WLocalCommunityActivityProvider.maximumEntries {
            XCTAssertTrue(bounded.recordView(viewerMemberID:owner,postID:"post-\(index)",date:now.addingTimeInterval(TimeInterval(index))))
        }
        let ids=bounded.recentPostIDs(viewerMemberID:owner,asOf:now.addingTimeInterval(TimeInterval(WLocalCommunityActivityProvider.maximumEntries)))
        XCTAssertEqual(ids.count,WLocalCommunityActivityProvider.maximumEntries)
        XCTAssertEqual(ids.first,"post-100")
        XCTAssertFalse(ids.contains("post-0"))
    }

    func testReview54HomeArcUsesSourceSweepAndClampsProgress() {
        XCTAssertEqual(WReview54HomeArc.viewBoxWidth,240)
        XCTAssertEqual(WReview54HomeArc.viewBoxHeight,190)
        XCTAssertEqual(WReview54HomeArc.sweepDegrees,220)
        XCTAssertEqual(WReview54HomeArc.ratio(value:12,target:20),0.6,accuracy:0.0001)
        XCTAssertEqual(WReview54HomeArc.progressRatio(value:12,target:nil),0)
        XCTAssertEqual(WReview54HomeArc.progressRatio(value:12,target:20),0.6,accuracy:0.0001)
        XCTAssertEqual(WReview54HomeArc.ratio(value:23,target:20),1,accuracy:0.0001)
        XCTAssertEqual(WReview54HomeArc.ratio(value:12,target:0),0,accuracy:0.0001)
        XCTAssertEqual(WReview54HomeArc.ratio(value:.infinity,target:20),0,accuracy:0.0001)
        XCTAssertEqual(WReview54HomeArc.dualRingSize(availableWidth:346),166,accuracy:0.1)
        XCTAssertEqual(WReview54HomeArc.dualRingSize(availableWidth:276),131,accuracy:0.1)
        XCTAssertLessThanOrEqual(2*WReview54HomeArc.dualRingSize(availableWidth:276)+14,276)
        XCTAssertGreaterThan(WReview54HomeArc.dualRingHeight(size:173,showsOverage:true),WReview54HomeArc.dualRingHeight(size:173,showsOverage:false))
        let bounds=WReview54HomeArc.path(in:CGRect(x:0,y:0,width:240,height:190)).boundingRect
        XCTAssertEqual(bounds.minX,13,accuracy:0.2)
        XCTAssertEqual(bounds.maxX,227,accuracy:0.2)
        XCTAssertLessThan(bounds.maxY,157,"The 220° arc remains open toward the lower edge")
    }

    @MainActor func testReview52WeekFixtureUsesItsReferenceWeek() {
        let suite = "review52-week-\…52430 tokens truncated…id:"sync-race-a",title:"오래된 목록 제목",memo:nil)
        let gate=WireframeRemoteReadGate()
        let fake=WireframeRunRecordsEditFake(details:[runA],listPages:[
            BackendRunPage(items:[runA.summary],nextCursor:nil),
            BackendRunPage(items:[refreshedA.summary],nextCursor:nil)
        ],listFetchGates:[2:gate])
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake,runRecordsDeleter:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        let refresh=Task{@MainActor in await bridge.refreshRunRecords()}
        let waiting=await waitUntil{await gate.isWaiting()}
        XCTAssertTrue(waiting)
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        let didEdit=await bridge.saveRunRecordField(.title,value:"최신 편집",runID:runA.summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertTrue(didEdit)
        await gate.release()
        await refresh.value
        guard case .loaded(let editedList)=bridge.runRecordsState else{XCTFail("The edit must remain in the remote list cache");return}
        XCTAssertEqual(editedList.items.first?.title,"최신 편집")

        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L07")
        let deleting=Task{@MainActor in await bridge.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")}
        let deleted=await deleting.value
        XCTAssertTrue(deleted)
        guard case .loaded(let afterDelete)=bridge.runRecordsState else{XCTFail("A confirmed delete must remain applied");return}
        XCTAssertFalse(afterDelete.items.contains{$0.id==runA.summary.id})
    }

    @MainActor func testRunDeleteIsOptionalAndOnlyConfirmedSuccessRemovesTheSelectedRun() async {
        let runA=makeRunEditNormalizationConflictDetail(id:"delete-a",title:"기록 A",memo:nil)
        let runB=makeRunEditNormalizationConflictDetail(id:"delete-b",title:"기록 B",memo:nil)
        let readOnlyFake=WireframeRunRecordsEditFake(details:[runA,runB])
        let readOnly=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:readOnlyFake)
        ))
        await readOnly.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        await readOnly.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L07")
        XCTAssertFalse(readOnly.hasRunRecordsDeleter)
        XCTAssertFalse(readOnly.canDeleteRunRecord(runA.summary.id))
        let readOnlyDelete=await readOnly.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")
        let readOnlyDeleteCount=await readOnlyFake.deleteCount()
        XCTAssertFalse(readOnlyDelete)
        XCTAssertEqual(readOnlyDeleteCount,0)

        let fake=WireframeRunRecordsEditFake(details:[runA,runB])
        let loader=RunRecordsLoader(client:fake)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(runRecordsLoader:loader,runRecordsDeleter:fake))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L07")
        XCTAssertTrue(bridge.canDeleteRunRecord(runA.summary.id))
        let didDelete=await bridge.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")
        XCTAssertTrue(didDelete)
        guard case .loaded(let remaining)=bridge.runRecordsState else{XCTFail("Expected the remaining list cache");return}
        XCTAssertEqual(remaining.items.map(\.id),[runB.summary.id])
        XCTAssertEqual(bridge.runDetailState,.idle,"The deleted record's detail cache is cleared")
        XCTAssertEqual(bridge.pointsState,.idle,"Deletion never subtracts or mutates the points wallet")
        XCTAssertEqual(bridge.progressState,.idle,"Run summaries are marked for a fresh read")
    }

    @MainActor func testRunDelete404KeepsRecordVisibleAndDoesNotClaimSuccess() async {
        let detail=makeRunEditNormalizationConflictDetail(id:"delete-missing",title:"보존된 기록",memo:nil)
        let fake=WireframeRunRecordsEditFake(details:[detail],deleteFailure:.recordNotFound)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsDeleter:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L07")

        let didDelete=await bridge.deleteRunRecord(id:detail.summary.id,accountScopeID:"account-a")
        XCTAssertFalse(didDelete)
        XCTAssertEqual(bridge.runRecordDeleteFailure(runID:detail.summary.id),.recordNotFound)
        XCTAssertFalse(bridge.canDeleteRunRecord(detail.summary.id),"An ambiguous 404 cannot be retried as though deletion were confirmed")
        guard case .loaded(let snapshot)=bridge.runRecordsState else{XCTFail("Expected the original list snapshot");return}
        XCTAssertEqual(snapshot.items.map(\.id),[detail.summary.id])
        guard case .loaded(let retained)=bridge.runDetailState else{XCTFail("Expected the original detail");return}
        XCTAssertEqual(retained.summary.id,detail.summary.id)

        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        guard case .loaded(let refreshed)=bridge.runRecordsState else{XCTFail("Expected a refreshed list");return}
        XCTAssertEqual(refreshed.items.map(\.id),[detail.summary.id],"The 404 remains an unknown/inaccessible result, not a local deletion")
    }

    @MainActor func testRunDeleteVersionConflictDoesNotRetryAndDetailMustBeRefetched() async {
        let detail=makeRunEditNormalizationConflictDetail(id:"delete-conflict",title:"충돌",memo:nil)
        let fake=WireframeRunRecordsEditFake(details:[detail],conflictsFirstDelete:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsDeleter:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L07")
        let didDelete=await bridge.deleteRunRecord(id:detail.summary.id,accountScopeID:"account-a")
        XCTAssertFalse(didDelete)
        XCTAssertEqual(bridge.runRecordDeleteFailure(runID:detail.summary.id),.versionConflict)
        let deleteCount=await fake.deleteCount()
        XCTAssertEqual(deleteCount,1,"A version conflict is not automatically retried")

        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L04")
        guard case .loaded(let refreshed)=bridge.runDetailState else{XCTFail("Expected the latest version to be read");return}
        XCTAssertEqual(refreshed.summary.version,2)
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L07")
        XCTAssertTrue(bridge.canDeleteRunRecord(detail.summary.id))
    }

    @MainActor func testRunDeletePreventsDuplicateTapAndReconcilesLateSuccessWithoutReplacingOtherDetail() async {
        let runA=makeRunEditNormalizationConflictDetail(id:"delete-late-a",title:"기록 A",memo:nil)
        let runB=makeRunEditNormalizationConflictDetail(id:"delete-late-b",title:"기록 B",memo:nil)
        let fake=WireframeRunRecordsEditFake(details:[runA,runB],holdsFirstDelete:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsDeleter:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L07")
        let deletion=Task{@MainActor in await bridge.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")}
        let pending=await waitUntil{await fake.hasPendingDelete()}
        XCTAssertTrue(pending)
        XCTAssertTrue(bridge.isDeletingRunRecord)
        let duplicate=await bridge.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")
        let deleteCount=await fake.deleteCount()
        XCTAssertFalse(duplicate)
        XCTAssertEqual(deleteCount,1)

        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runB.summary.id,screen:"L04")
        XCTAssertEqual(bridge.runDetailState,.loaded(runB))
        await fake.completePendingDelete()
        let deletionResult=await deletion.value
        XCTAssertFalse(deletionResult,"Navigation invalidates the active confirmation flow")
        XCTAssertEqual(bridge.runDetailState,.loaded(runB),"A late A response must not replace the selected B detail")
        guard case .loaded(let remaining)=bridge.runRecordsState else{XCTFail("Expected the cached list to reconcile confirmed A deletion");return}
        XCTAssertEqual(remaining.items.map(\.id),[runB.summary.id])
    }

    @MainActor func testRunDeleteResponseAfterAccountSwitchCannotMutateNewAccountState() async {
        let runA=makeRunEditNormalizationConflictDetail(id:"delete-account-a",title:"회원 A",memo:nil)
        let runB=makeRunEditNormalizationConflictDetail(id:"delete-account-b",title:"회원 B",memo:nil)
        let fake=WireframeRunRecordsEditFake(details:[runA,runB],holdsFirstDelete:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsDeleter:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L07")
        let deletion=Task{@MainActor in await bridge.deleteRunRecord(id:runA.summary.id,accountScopeID:"account-a")}
        let pending=await waitUntil{await fake.hasPendingDelete()}
        XCTAssertTrue(pending)
        bridge.accountDidChange(to:"account-b")
        await bridge.activate(feature:.runs,accountScopeID:"account-b",runID:runB.summary.id,screen:"L04")
        XCTAssertEqual(bridge.runDetailState,.loaded(runB))
        XCTAssertEqual(bridge.runRecordsState,.idle)
        await fake.completePendingDelete()
        let deletionResult=await deletion.value
        XCTAssertFalse(deletionResult)
        XCTAssertEqual(bridge.accountScopeID,"account-b")
        XCTAssertEqual(bridge.runDetailState,.loaded(runB),"A's late delete response must not cross the account boundary")
        XCTAssertEqual(bridge.runRecordsState,.idle,"The stale response cannot mutate the current account's empty list cache")
    }

    @MainActor func testRunRecordEditPatchesOneFieldAndUpdatesDetailAndList() async {
        let summary=BackendRunSummary(
            id:"edit-run-1",clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
            startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
            runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
            verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
            title:"서버 밤 러닝",memo:"그대로 둘 메모",createdAt:Date(timeIntervalSince1970:1_791_215_462),
            updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
        )
        let detail=BackendRunDetail(summary:summary,points:[],pauses:[],judgement:nil)
        let fake=WireframeRunRecordsEditFake(details:[detail],holdsFirstWrite:true)
        let loader=RunRecordsLoader(client:fake,pageSize:1)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:loader,runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:summary.id,screen:"L04")
        XCTAssertTrue(bridge.canEditRunRecord(summary.id))

        let save=Task{@MainActor in
            await bridge.saveRunRecordField(.title,value:"고요한 밤 러닝",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        }
        let writeIsPending=await waitUntil{await fake.hasPendingWrite()}
        XCTAssertTrue(writeIsPending)
        XCTAssertTrue(bridge.isSavingRunRecord)
        let duplicate=await bridge.saveRunRecordField(.memo,value:"중복 저장 불가",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertFalse(duplicate)
        let duplicateWriteCount=await fake.writeCount()
        XCTAssertEqual(duplicateWriteCount,1)

        await fake.completePendingWrite()
        let didSave=await save.value
        XCTAssertTrue(didSave)
        XCTAssertEqual(bridge.runRecordEditState,.idle)
        guard case .loaded(let updatedDetail)=bridge.runDetailState else{XCTFail("Expected updated detail");return}
        XCTAssertEqual(updatedDetail.summary.title,"고요한 밤 러닝")
        XCTAssertEqual(updatedDetail.summary.memo,"그대로 둘 메모","An omitted field stays unchanged")
        XCTAssertEqual(updatedDetail.summary.version,2)
        XCTAssertEqual(updatedDetail.points,detail.points)
        guard case .loaded(let snapshot)=bridge.runRecordsState else{XCTFail("Expected updated list");return}
        XCTAssertEqual(snapshot.items.first?.title,"고요한 밤 러닝")
        XCTAssertEqual(snapshot.nextCursor,nil)
    }

    @MainActor func testRunRecordVersionConflictRefreshesWithoutDiscardingTheDraft() async {
        let summary=BackendRunSummary(
            id:"conflict-run",clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
            startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
            runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
            verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
            title:"기존 제목",memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
            updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
        )
        let fake=WireframeRunRecordsEditFake(
            details:[BackendRunDetail(summary:summary,points:[],pauses:[],judgement:nil)],conflictsFirstWrite:true
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:summary.id,screen:"L04")

        let firstSave=await bridge.saveRunRecordField(.title,value:"내 초안",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertFalse(firstSave)
        XCTAssertEqual(bridge.runRecordEditFailure(runID:summary.id,field:.title),.versionConflict)
        guard case .loaded(let latest)=bridge.runDetailState else{XCTFail("Expected refreshed server detail");return}
        XCTAssertEqual(latest.summary.title,"변경된 제목")
        XCTAssertEqual(latest.summary.version,2)
        XCTAssertTrue(bridge.canEditRunRecord(summary.id),"The draft remains editable after an optimistic-lock conflict")

        let rebasedSave=await bridge.saveRunRecordField(.title,value:"내 초안",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertTrue(rebasedSave)
        guard case .loaded(let saved)=bridge.runDetailState else{XCTFail("Expected saved detail");return}
        XCTAssertEqual(saved.summary.title,"내 초안")
        XCTAssertEqual(saved.summary.version,3)
        let writeCount=await fake.writeCount()
        XCTAssertEqual(writeCount,2)
    }

    @MainActor func testNFCEquivalentTitleAfterVersionConflictKeepsDraftUnapplied() async {
        let draft="\u{00E9}"
        let latest="e\u{0301}"
        XCTAssertEqual(draft,latest,"Swift String equality treats canonical equivalents as equal")
        XCTAssertNotEqual(Array(draft.utf16),Array(latest.utf16))
        let detail=makeRunEditNormalizationConflictDetail(id:"unicode-title-run",title:"기존 제목",memo:"기존 메모")
        let fake=WireframeRunRecordsEditFake(
            details:[detail],conflictsFirstWrite:true,conflictTitle:latest
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L04")

        let didSave=await bridge.saveRunRecordField(.title,value:draft,runID:detail.summary.id,accountScopeID:"account-a",screen:"L04")

        XCTAssertFalse(didSave,"A canonically equivalent but byte-distinct server value must not complete the draft")
        XCTAssertEqual(bridge.runRecordEditFailure(runID:detail.summary.id,field:.title),.versionConflict)
        guard case .loaded(let refreshed)=bridge.runDetailState,let refreshedTitle=refreshed.summary.title else {
            XCTFail("Expected the server's normalized title after conflict refresh");return
        }
        XCTAssertEqual(Array(refreshedTitle.utf16),Array(latest.utf16))
        XCTAssertNotEqual(Array(refreshedTitle.utf16),Array(draft.utf16))
        XCTAssertTrue(bridge.canEditRunRecord(detail.summary.id),"The title draft remains in the inline editor after the 409")
    }

    @MainActor func testNFCEquivalentMemoAfterVersionConflictKeepsDraftUnapplied() async {
        let draft="\u{00E9}"
        let latest="e\u{0301}"
        XCTAssertEqual(draft,latest,"Swift String equality treats canonical equivalents as equal")
        XCTAssertNotEqual(Array(draft.utf16),Array(latest.utf16))
        let detail=makeRunEditNormalizationConflictDetail(id:"unicode-memo-run",title:"기존 제목",memo:"기존 메모")
        let fake=WireframeRunRecordsEditFake(
            details:[detail],conflictsFirstWrite:true,conflictMemo:latest
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:detail.summary.id,screen:"L04")

        let didSave=await bridge.saveRunRecordField(.memo,value:draft,runID:detail.summary.id,accountScopeID:"account-a",screen:"L04")

        XCTAssertFalse(didSave,"A canonically equivalent but byte-distinct server value must not complete the draft")
        XCTAssertEqual(bridge.runRecordEditFailure(runID:detail.summary.id,field:.memo),.versionConflict)
        guard case .loaded(let refreshed)=bridge.runDetailState,let refreshedMemo=refreshed.summary.memo else {
            XCTFail("Expected the server's normalized memo after conflict refresh");return
        }
        XCTAssertEqual(Array(refreshedMemo.utf16),Array(latest.utf16))
        XCTAssertNotEqual(Array(refreshedMemo.utf16),Array(draft.utf16))
        XCTAssertTrue(bridge.canEditRunRecord(detail.summary.id),"The memo draft remains in the inline editor after the 409")
    }

    @MainActor func testLateRunEditAfterReturningToListReloadsTheServerRecord() async {
        let summary=BackendRunSummary(
            id:"late-run",clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
            startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
            runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
            verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
            title:"처음 제목",memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
            updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
        )
        let fake=WireframeRunRecordsEditFake(
            details:[BackendRunDetail(summary:summary,points:[],pauses:[],judgement:nil)],holdsFirstWrite:true
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:summary.id,screen:"L04")
        let save=Task{@MainActor in
            await bridge.saveRunRecordField(.title,value:"저장 직후 이동",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        }
        let writeIsPending=await waitUntil{await fake.hasPendingWrite()}
        XCTAssertTrue(writeIsPending)
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        XCTAssertEqual(bridge.runRecordEditState,.idle)
        await fake.completePendingWrite()
        let didSave=await save.value
        XCTAssertFalse(didSave)
        let listRefreshed=await waitUntil{
            guard case .loaded(let snapshot)=bridge.runRecordsState else{return false}
            return snapshot.items.first?.title=="저장 직후 이동"
        }
        XCTAssertTrue(listRefreshed,"A completed late write on the same account refreshes the visible list")
        XCTAssertEqual(bridge.runDetailState,.idle)
    }

    @MainActor func testLateRunEditForAWhileViewingBPreservesBAndRefreshesListOnReturn() async {
        func summary(_ id:String,_ title:String)->BackendRunSummary {
            BackendRunSummary(
                id:id,clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
                startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
                runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
                verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
                title:title,memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
                updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
            )
        }
        let runA=BackendRunDetail(summary:summary("run-a","기록 A"),points:[],pauses:[],judgement:nil)
        let runB=BackendRunDetail(summary:summary("run-b","기록 B"),points:[],pauses:[],judgement:nil)
        let fake=WireframeRunRecordsEditFake(details:[runA,runB],holdsFirstWrite:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runA.summary.id,screen:"L04")
        let save=Task{@MainActor in
            await bridge.saveRunRecordField(.title,value:"기록 A 수정",runID:runA.summary.id,accountScopeID:"account-a",screen:"L04")
        }
        let writeIsPending=await waitUntil{await fake.hasPendingWrite()}
        XCTAssertTrue(writeIsPending)

        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:runB.summary.id,screen:"L04")
        XCTAssertEqual(bridge.runDetailState,.loaded(runB))
        await fake.completePendingWrite()
        let didSave=await save.value
        XCTAssertFalse(didSave)
        XCTAssertEqual(bridge.runDetailState,.loaded(runB),"A's late completion must not clear or replace B's loaded detail")
        guard case .loaded(let beforeReturn)=bridge.runRecordsState else{XCTFail("Expected the independent list cache");return}
        XCTAssertEqual(beforeReturn.items.first(where:{$0.id==runA.summary.id})?.title,"기록 A")

        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        guard case .loaded(let refreshed)=bridge.runRecordsState else{XCTFail("Expected list refresh after returning");return}
        XCTAssertEqual(refreshed.items.first(where:{$0.id==runA.summary.id})?.title,"기록 A 수정")
        XCTAssertEqual(refreshed.items.first(where:{$0.id==runB.summary.id})?.title,"기록 B")
        let listFetchCount=await fake.listFetchCount()
        XCTAssertEqual(listFetchCount,2)
    }

    @MainActor func testRunRecordNotFoundInvalidatesListAndFailedRefreshHasWorkingRetry() async {
        let summary=BackendRunSummary(
            id:"missing-run",clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
            startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
            runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
            verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
            title:"처음 제목",memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
            updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
        )
        let detail=BackendRunDetail(summary:summary,points:[],pauses:[],judgement:nil)
        let fake=WireframeRunRecordsEditFake(
            details:[detail],writeFailure:.recordNotFound
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:summary.id,screen:"L04")
        await fake.failNextListFetch()

        let didSave=await bridge.saveRunRecordField(.title,value:"남길 초안",runID:summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertFalse(didSave)
        XCTAssertEqual(bridge.runRecordEditFailure(runID:summary.id,field:.title),.recordNotFound)
        XCTAssertEqual(bridge.runRecordsState,.idle,"A PATCH 404 invalidates the loaded list cache")

        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        guard case .failed(let refreshFailure)=bridge.runRecordsState else{XCTFail("Expected an explicit refresh failure");return}
        XCTAssertEqual(refreshFailure,.serverFailure(statusCode:503,requestID:"fixture-runs-refresh"))
        XCTAssertEqual(bridge.runRecordEditState,.idle,"Leaving detail ends the inline draft; it was retained on the detail until then")
        bridge.retryRunRecords()
        let recovered=await waitUntil{
            guard case .loaded(let snapshot)=bridge.runRecordsState else{return false}
            return snapshot.items.isEmpty
        }
        XCTAssertTrue(recovered,"The existing list retry action re-reads after a failed cache refresh")
        let listFetchCount=await fake.listFetchCount()
        XCTAssertEqual(listFetchCount,3)
    }

    @MainActor func testLateMissingRecordRefreshCannotReplaceTheNextAccountList() async {
        func summary(_ id:String,_ title:String)->BackendRunSummary {
            BackendRunSummary(
                id:id,clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
                startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
                runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
                verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
                title:title,memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
                updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
            )
        }
        let accountA=BackendRunDetail(summary:summary("account-a-run","A record"),points:[],pauses:[],judgement:nil)
        let accountB=summary("account-b-run","B record")
        let gate=WireframeRemoteReadGate()
        let pages=[
            BackendRunPage(items:[accountA.summary],nextCursor:nil),
            BackendRunPage(items:[accountA.summary],nextCursor:nil),
            BackendRunPage(items:[accountB],nextCursor:nil)
        ]
        let fake=WireframeRunRecordsEditFake(
            details:[accountA],writeFailure:.recordNotFound,listPages:pages,listFetchGates:[2:gate]
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:accountA.summary.id,screen:"L04")
        _=await bridge.saveRunRecordField(.title,value:"실패 초안",runID:accountA.summary.id,accountScopeID:"account-a",screen:"L04")
        XCTAssertEqual(bridge.runRecordsState,.idle)

        let staleRefresh=Task{@MainActor in await bridge.activate(feature:.runs,accountScopeID:"account-a",screen:"L01")}
        let refreshIsWaiting=await waitUntil{await gate.isWaiting()}
        XCTAssertTrue(refreshIsWaiting)
        bridge.accountDidChange(to:"account-b")
        await bridge.activate(feature:.runs,accountScopeID:"account-b",screen:"L01")
        guard case .loaded(let currentAccount)=bridge.runRecordsState else{XCTFail("Expected account B list");return}
        XCTAssertEqual(currentAccount.items.map(\.id),[accountB.id])

        await gate.release()
        await staleRefresh.value
        XCTAssertEqual(bridge.accountScopeID,"account-b")
        XCTAssertEqual(bridge.runRecordsState,.loaded(currentAccount),"A's delayed cache refresh must not cross an account change")
    }

    @MainActor func testLateRunEditFromPreviousAccountCannotReplaceTheNewAccountDetail() async {
        func summary(_ id:String,_ title:String)->BackendRunSummary {
            BackendRunSummary(
                id:id,clientRunID:UUID(uuidString:"0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!,version:1,
                startedAt:Date(timeIntervalSince1970:1_791_213_000),endedAt:Date(timeIntervalSince1970:1_791_215_400),
                runDate:"2026-10-05",elapsedSeconds:2400,movingSeconds:2280,distanceMeters:6400,
                verdict:"VALID",verdictReason:nil,validDistanceMeters:6100,validSeconds:2150,paceSecondsPerKm:352,
                title:title,memo:nil,createdAt:Date(timeIntervalSince1970:1_791_215_462),
                updatedAt:Date(timeIntervalSince1970:1_791_215_462),pointReward:nil
            )
        }
        let accountA=BackendRunDetail(summary:summary("run-a","회원 A 제목"),points:[],pauses:[],judgement:nil)
        let accountB=BackendRunDetail(summary:summary("run-b","회원 B 제목"),points:[],pauses:[],judgement:nil)
        let fake=WireframeRunRecordsEditFake(details:[accountA,accountB],holdsFirstWrite:true)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            runRecordsLoader:RunRecordsLoader(client:fake),runRecordsUpdater:fake
        ))
        await bridge.activate(feature:.runs,accountScopeID:"account-a",runID:"run-a",screen:"L04")
        let save=Task{@MainActor in
            await bridge.saveRunRecordField(.title,value:"회원 A 늦은 응답",runID:"run-a",accountScopeID:"account-a",screen:"L04")
        }
        let writeIsPending=await waitUntil{await fake.hasPendingWrite()}
        XCTAssertTrue(writeIsPending)
        bridge.accountDidChange(to:"account-b")
        await bridge.activate(feature:.runs,accountScopeID:"account-b",runID:"run-b",screen:"L04")
        guard case .loaded(let newAccountDetail)=bridge.runDetailState else{XCTFail("Expected account B detail");return}
        XCTAssertEqual(newAccountDetail.summary.title,"회원 B 제목")

        await fake.completePendingWrite()
        let didSave=await save.value
        XCTAssertFalse(didSave)
        XCTAssertEqual(bridge.accountScopeID,"account-b")
        XCTAssertEqual(bridge.runDetailState,.loaded(accountB),"A late response must not cross an account boundary")
        XCTAssertEqual(bridge.runRecordEditState,.idle)
    }

    @MainActor func testLeavingRunListCancelsTheReadAndIgnoresItsLateResponse() async {
        let gate=WireframeRemoteReadGate()
        let mock=WireframeRunRecordsReadMock(pages:[BackendRunPage(items:[],nextCursor:nil)],firstPageGate:gate)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(runRecordsLoader:RunRecordsLoader(client:mock)))
        let request=Task{@MainActor in await bridge.activate(feature:.runs,accountScopeID:"account-a")}
        var requestIsWaiting=false
        for _ in 0..<500 {
            let waiting=await gate.isWaiting()
            if waiting {requestIsWaiting=true;break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        XCTAssertTrue(requestIsWaiting)
        request.cancel()
        await bridge.activate(feature:nil,accountScopeID:"account-a")
        await request.value
        XCTAssertEqual(bridge.runRecordsState,.idle)
        XCTAssertEqual(bridge.runDetailState,.idle)
        let cancelledCalls=await mock.observedCancelledPageCalls()
        XCTAssertEqual(cancelledCalls,1)
    }

    @MainActor func testRemotePointsBridgeDistinguishesZeroAndPaginatesPages() async {
        let first=PointsLedgerEntry(entryID:"entry-1",direction:.credit,deltaPoints:10,balanceAfterPoints:10,reasonCode:"RUN_REWARD",createdAt:Date(timeIntervalSince1970:1_800_000_000))
        let second=PointsLedgerEntry(entryID:"entry-2",direction:.debit,deltaPoints:3,balanceAfterPoints:7,reasonCode:"ITEM_PURCHASE",createdAt:Date(timeIntervalSince1970:1_800_000_100))
        let mock=WireframeRemoteReadMock(
            balanceResults:[.success(PointsBalance(balancePoints:0))],
            pageResults:[
                .success(PointsLedgerPage(entries:[first],nextCursor:"opaque-cursor")),
                .success(PointsLedgerPage(entries:[second],nextCursor:nil))
            ]
        )
        let loader=PointsWalletLoader(client:mock,pageSize:1)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:loader))

        await bridge.activate(feature:.points,accountScopeID:"account-a")
        guard case .loaded(let firstSnapshot)=bridge.pointsState else {XCTFail("Expected a loaded remote balance");return}
        XCTAssertEqual(firstSnapshot.balance.balancePoints,0)
        XCTAssertEqual(firstSnapshot.entries.map(\.entryID),["entry-1"])
        XCTAssertEqual(firstSnapshot.nextCursor,"opaque-cursor")

        bridge.loadNextPointsPage()
        for _ in 0..<200 {
            if case .loaded = bridge.pointsState { break }
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        guard case .loaded(let finalSnapshot)=bridge.pointsState else {XCTFail("Expected the next remote page");return}
        XCTAssertEqual(finalSnapshot.entries.map(\.entryID),["entry-1","entry-2"])
        XCTAssertNil(finalSnapshot.nextCursor)
        let cursors=await mock.observedEntryCursors()
        XCTAssertEqual(cursors,[nil,"opaque-cursor"])
    }

    @MainActor func testRemotePointsFailureRemainsDistinctAndExplicitRetryRecovers() async {
        let mock=WireframeRemoteReadMock(
            balanceResults:[
                .failure(.pointsUnavailable(requestID:"fixture-unavailable")),
                .success(PointsBalance(balancePoints:25))
            ],
            pageResults:[.success(PointsLedgerPage(entries:[],nextCursor:nil))]
        )
        let loader=PointsWalletLoader(client:mock)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:loader))

        await bridge.activate(feature:.points,accountScopeID:"account-a")
        XCTAssertEqual(bridge.pointsState,.failed(.pointsUnavailable(requestID:"fixture-unavailable")))
        bridge.retryPoints()
        for _ in 0..<200 {
            if case .loaded = bridge.pointsState { break }
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        guard case .loaded(let snapshot)=bridge.pointsState else {XCTFail("Expected retry to load the remote balance");return}
        XCTAssertEqual(snapshot.balance.balancePoints,25)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    @MainActor func testRemoteProfileAccountChangeClearsPreviousMemberBeforeNewRead() async {
        let mock=WireframeRemoteReadMock(profileResults:[.success(MemberProfile(nickname:"계정 A")),.success(MemberProfile(nickname:"계정 B"))])
        let loader=MemberProfileLoader(fetcher:mock)
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(memberProfileLoader:loader))

        await bridge.activate(feature:.profile,accountScopeID:"account-a")
        XCTAssertEqual(bridge.memberProfileState,.loaded(MemberProfile(nickname:"계정 A")))
        bridge.accountDidChange(to:"account-b")
        XCTAssertEqual(bridge.memberProfileState,.idle)

        await bridge.activate(feature:.profile,accountScopeID:"account-b")
        XCTAssertEqual(bridge.memberProfileState,.loaded(MemberProfile(nickname:"계정 B")))
    }

    @MainActor func testLeavingProfileOrPointsReadCancelsItsTaskAndClearsLoadingState() async {
        let profileMock=WireframeRemoteReadMock(profileResults:[.success(MemberProfile(nickname:"취소 대상"))],heldProfileCalls:[0])
        let profileBridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(memberProfileLoader:MemberProfileLoader(fetcher:profileMock)))
        let profileTask=Task{@MainActor in await profileBridge.activate(feature:.profile,accountScopeID:"account-a")}
        for _ in 0..<200 {if profileBridge.memberProfileState == .loading{break};try? await Task.sleep(nanoseconds:1_000_000)}
        XCTAssertEqual(profileBridge.memberProfileState,.loading)
        profileTask.cancel()
        await profileTask.value
        XCTAssertEqual(profileBridge.memberProfileState,.idle)
        let profileCancellations=await profileMock.observedCancelledProfileCalls()
        XCTAssertEqual(profileCancellations,1)

        let pointsMock=WireframeRemoteReadMock(balanceResults:[.success(PointsBalance(balancePoints:80))],heldBalanceCalls:[0])
        let pointsBridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:PointsWalletLoader(client:pointsMock)))
        let pointsTask=Task{@MainActor in await pointsBridge.activate(feature:.points,accountScopeID:"account-a")}
        for _ in 0..<200 {if pointsBridge.pointsState == .loading{break};try? await Task.sleep(nanoseconds:1_000_000)}
        XCTAssertEqual(pointsBridge.pointsState,.loading)
        pointsTask.cancel()
        await pointsTask.value
        XCTAssertEqual(pointsBridge.pointsState,.idle)
        let pointsCancellations=await pointsMock.observedCancelledBalanceCalls()
        XCTAssertEqual(pointsCancellations,1)
    }

    @MainActor func testDuplicatePointsRetryDoesNotInvalidateTheActiveCompletion() async {
        let retryGate=WireframeRemoteReadGate()
        let mock=WireframeRemoteReadMock(
            balanceResults:[
                .failure(.pointsUnavailable(requestID:"first-read")),
                .success(PointsBalance(balancePoints:19))
            ],
            pageResults:[.success(PointsLedgerPage(entries:[],nextCursor:nil))],
            balanceGates:[1:retryGate]
        )
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:PointsWalletLoader(client:mock)))

        await bridge.activate(feature:.points,accountScopeID:"account-a")
        XCTAssertEqual(bridge.pointsState,.failed(.pointsUnavailable(requestID:"first-read")))
        bridge.retryPoints()

        var retryIsBlocked=false
        for _ in 0..<500 {
            let calls=await mock.observedBalanceCallCount()
            let waiting=await retryGate.isWaiting()
            if calls == 2 && waiting {retryIsBlocked=true;break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        XCTAssertTrue(retryIsBlocked)
        bridge.retryPoints()
        let callsAfterDuplicate=await mock.observedBalanceCallCount()
        XCTAssertEqual(callsAfterDuplicate,2,"A duplicate retry must not issue a second loader request")
        await retryGate.release()

        for _ in 0..<500 {
            if case .loaded = bridge.pointsState {break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        guard case .loaded(let snapshot)=bridge.pointsState else {XCTFail("The first retry completion must not be invalidated");return}
        XCTAssertEqual(snapshot.balance.balancePoints,19)
    }

    @MainActor func testManualRetriesAndPaginationCancelAtScreenAndAccountBoundaries() async {
        let profileGate=WireframeRemoteReadGate()
        let profileMock=WireframeRemoteReadMock(
            profileResults:[.failure(.invalidResponse),.success(MemberProfile(nickname:"late profile"))],
            profileGates:[1:profileGate]
        )
        let profileBridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(memberProfileLoader:MemberProfileLoader(fetcher:profileMock)))
        await profileBridge.activate(feature:.profile,accountScopeID:"account-a")
        profileBridge.retryMemberProfile()
        var profileRetryIsBlocked=false
        for _ in 0..<500 {
            let calls=await profileMock.observedProfileCallCount()
            let waiting=await profileGate.isWaiting()
            if calls == 2 && waiting {profileRetryIsBlocked=true;break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        XCTAssertTrue(profileRetryIsBlocked)
        profileBridge.accountDidChange(to:"account-b")
        XCTAssertEqual(profileBridge.memberProfileState,.idle)
        for _ in 0..<500 {
            if await profileMock.observedCancelledProfileCalls() == 1 {break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        let cancelledProfileRetries=await profileMock.observedCancelledProfileCalls()
        XCTAssertEqual(cancelledProfileRetries,1,"Account changes must cancel the retry request")
        XCTAssertEqual(profileBridge.memberProfileState,.idle)

        let pointsRetryGate=WireframeRemoteReadGate()
        let pointsRetryMock=WireframeRemoteReadMock(
            balanceResults:[.failure(.pointsUnavailable(requestID:"initial")),.success(PointsBalance(balancePoints:40))],
            pageResults:[.success(PointsLedgerPage(entries:[],nextCursor:nil))],
            balanceGates:[1:pointsRetryGate]
        )
        let pointsRetryBridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:PointsWalletLoader(client:pointsRetryMock)))
        await pointsRetryBridge.activate(feature:.points,accountScopeID:"account-a",screen:"POINTS")
        pointsRetryBridge.retryPoints()
        var pointsRetryIsBlocked=false
        for _ in 0..<500 {
            let calls=await pointsRetryMock.observedBalanceCallCount()
            let waiting=await pointsRetryGate.isWaiting()
            if calls == 2 && waiting {pointsRetryIsBlocked=true;break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        XCTAssertTrue(pointsRetryIsBlocked)
        await pointsRetryBridge.activate(feature:nil,accountScopeID:"account-a")
        XCTAssertEqual(pointsRetryBridge.pointsState,.idle)
        for _ in 0..<500 {
            if await pointsRetryMock.observedCancelledBalanceCalls() == 1 {break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        let cancelledPointRetries=await pointsRetryMock.observedCancelledBalanceCalls()
        XCTAssertEqual(cancelledPointRetries,1,"Leaving the points screen must cancel its retry request")
        XCTAssertEqual(pointsRetryBridge.pointsState,.idle)

        let pageGate=WireframeRemoteReadGate()
        let first=PointsLedgerEntry(entryID:"first",direction:.credit,deltaPoints:5,balanceAfterPoints:5,reasonCode:"RUN_REWARD",createdAt:Date(timeIntervalSince1970:1_800_000_000))
        let next=PointsLedgerEntry(entryID:"next",direction:.credit,deltaPoints:7,balanceAfterPoints:12,reasonCode:"RUN_REWARD",createdAt:Date(timeIntervalSince1970:1_800_000_100))
        let pageMock=WireframeRemoteReadMock(
            balanceResults:[.success(PointsBalance(balancePoints:12))],
            pageResults:[
                .success(PointsLedgerPage(entries:[first],nextCursor:"next-cursor")),
                .success(PointsLedgerPage(entries:[next],nextCursor:nil))
            ],
            entryGates:["next-cursor":pageGate]
        )
        let pageBridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(pointsWalletLoader:PointsWalletLoader(client:pageMock,pageSize:1)))
        await pageBridge.activate(feature:.points,accountScopeID:"account-a",screen:"POINTS")
        pageBridge.loadNextPointsPage()
        var pageIsBlocked=false
        for _ in 0..<500 {
            let cursors=await pageMock.observedEntryCursors()
            let waiting=await pageGate.isWaiting()
            if cursors.count == 2 && waiting {pageIsBlocked=true;break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        XCTAssertTrue(pageIsBlocked)
        await pageBridge.activate(feature:.points,accountScopeID:"account-a",screen:"POINTS")
        let paginationStillWaitsOnSameScreen=await pageGate.isWaiting()
        XCTAssertTrue(paginationStillWaitsOnSameScreen,"Reactivating POINTS must not cancel the in-flight page request")
        let cancelledBeforeScreenChange=await pageMock.observedCancelledEntryCalls()
        XCTAssertEqual(cancelledBeforeScreenChange,0,"The request remains active while the current screen is unchanged")

        await pageBridge.activate(feature:.points,accountScopeID:"account-a",screen:"B02")
        guard case .loaded(let preservedSnapshot)=pageBridge.pointsState else {XCTFail("Leaving POINTS for B02 should retain the loaded first page");return}
        XCTAssertEqual(preservedSnapshot.entries.map(\.entryID),["first"])
        XCTAssertEqual(preservedSnapshot.nextCursor,"next-cursor")
        for _ in 0..<500 {
            if await pageMock.observedCancelledEntryCalls() == 1 {break}
            try? await Task.sleep(nanoseconds:1_000_000)
        }
        let cancelledPageCalls=await pageMock.observedCancelledEntryCalls()
        XCTAssertEqual(cancelledPageCalls,1,"Changing screens must cancel the page request")
        let pointBalanceCalls=await pageMock.observedBalanceCallCount()
        XCTAssertEqual(pointBalanceCalls,1,"Moving between points screens must not refetch the balance")
    }
}

extension ThemeTests {
    @MainActor func testAuthLogoutBridgeTreatsAlreadyClearedSessionAsSameIntentSuccess() async throws {
        let store = AuthSessionFixtureStore(snapshot: try AuthSessionFixtures.session(memberID: "41"))
        let requester = PendingSessionLogoutBridgeFake()
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(
            sessionLogoutRequester: requester,
            authSessionStore: store
        ))
        await bridge.activate(feature: nil, accountScopeID: "account-a", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(1)

        // Another in-flight request for the same logout already committed the 204.
        try store.replaceAtomically(with: nil)
        await requester.complete(0, with: .failure(.sessionChanged))
        for _ in 0..<200 {
            if bridge.sessionLogoutState == .loggedOut { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(bridge.sessionLogoutState, .loggedOut)
        XCTAssertNil(try store.loadSnapshot())
    }

    @MainActor func testAuthLogoutSessionChangedDoesNotClearANewerAccount() async throws {
        let store = AuthSessionFixtureStore(snapshot: try AuthSessionFixtures.session(memberID: "41"))
        let requester = PendingSessionLogoutBridgeFake()
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(
            sessionLogoutRequester: requester,
            authSessionStore: store
        ))
        await bridge.activate(feature: nil, accountScopeID: "account-a", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(1)
        let accountB = try AuthSessionFixtures.session(memberID: "99", refreshToken: "account-b-refresh")
        try store.replaceAtomically(with: accountB)
        await requester.complete(0, with: .failure(.sessionChanged))
        for _ in 0..<200 {
            if case .failed = bridge.sessionLogoutState { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(bridge.sessionLogoutState, .failed(.sessionChanged))
        XCTAssertEqual(try store.loadSnapshot(), accountB)
    }

    @MainActor func testAuthLogoutBridgeDeduplicatesRetriesAndAcceptsOnlyConfirmedSuccess() async {
        let requester = PendingSessionLogoutBridgeFake()
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(sessionLogoutRequester: requester))
        await bridge.activate(feature: nil, accountScopeID: "account-a", screen: "T10")

        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(1)
        let firstCallCount = await requester.callCount()
        XCTAssertEqual(firstCallCount, 1, "Duplicate taps share the active logout request")
        XCTAssertEqual(bridge.sessionLogoutState, .loggingOut)

        await requester.complete(0, with: .failure(.serviceUnavailable(requestID: "r-503")))
        for _ in 0..<200 {
            if case .failed = bridge.sessionLogoutState { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .failed(.serviceUnavailable(requestID: "r-503")))

        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(2)
        let retryCallCount = await requester.callCount()
        XCTAssertEqual(retryCallCount, 2, "Retry is allowed after a failure, but duplicate retry taps are still deduplicated")
        XCTAssertEqual(bridge.sessionLogoutState, .loggingOut)

        await requester.complete(1, with: .success(()))
        for _ in 0..<200 {
            if bridge.sessionLogoutState == .loggedOut { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .loggedOut)
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        try? await Task.sleep(for: .milliseconds(20))
        let finalCallCount = await requester.callCount()
        XCTAssertEqual(finalCallCount, 2, "A confirmed logout cannot be submitted a second time")
    }

    @MainActor func testAuthLogoutBridgeIgnoresLateResultsAfterAccountOrScreenChange() async {
        let requester = PendingSessionLogoutBridgeFake()
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(sessionLogoutRequester: requester))
        await bridge.activate(feature: nil, accountScopeID: "account-a", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(1)

        await bridge.activate(feature: nil, accountScopeID: "account-b", screen: "T10")
        XCTAssertEqual(bridge.accountScopeID, "account-b")
        XCTAssertEqual(bridge.sessionLogoutState, .idle, "Account changes cancel the previous account's pending logout state")
        bridge.requestSessionLogout(accountScopeID: "account-b", screen: "T10")
        await requester.waitForCalls(2)

        await requester.complete(0, with: .success(()))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(bridge.sessionLogoutState, .loggingOut, "A late result from account A cannot finish account B's request")

        await bridge.activate(feature: nil, accountScopeID: "account-b", screen: "A01")
        XCTAssertEqual(bridge.sessionLogoutState, .idle, "Leaving T10 cancels the visible logout state")
        await requester.complete(1, with: .success(()))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(bridge.sessionLogoutState, .idle, "A late response cannot log out after the screen changes")

        await bridge.activate(feature: nil, accountScopeID: "account-b", screen: "T10")
        bridge.requestSessionLogout(accountScopeID: "account-b", screen: "T10")
        await requester.waitForCalls(3)
        await requester.complete(2, with: .success(()))
        for _ in 0..<200 {
            if bridge.sessionLogoutState == .loggedOut { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .loggedOut, "The newly active account can complete its own request")
    }

    @MainActor func testAuthLogout500AndLostResponseStayRetryableUntil401() async {
        let requester = PendingSessionLogoutBridgeFake()
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(sessionLogoutRequester: requester))
        await bridge.activate(feature: nil, accountScopeID: "account-a", screen: "T10")

        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(1)
        await requester.complete(0, with: .failure(.serverFailure(statusCode: 500, requestID: "r-500")))
        for _ in 0..<200 {
            if case .failed = bridge.sessionLogoutState { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .failed(.serverFailure(statusCode: 500, requestID: "r-500")))

        // A sent request whose response is lost is still ambiguous; the user must retry explicitly.
        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(2)
        await requester.complete(1, with: .failure(.transport(.timedOut)))
        for _ in 0..<200 {
            if case .failed = bridge.sessionLogoutState { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .failed(.transport(.timedOut)))

        bridge.requestSessionLogout(accountScopeID: "account-a", screen: "T10")
        await requester.waitForCalls(3)
        await requester.complete(2, with: .failure(.unauthenticated))
        for _ in 0..<200 {
            if bridge.sessionLogoutState == .loggedOut { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(bridge.sessionLogoutState, .loggedOut, "A manual retry that confirms the session is already invalid completes local logout")
        let finalCallCount = await requester.callCount()
        XCTAssertEqual(finalCallCount, 3, "No request is retried automatically")
    }

    @MainActor func testAccountScopeChangeClearsReadStateAndIgnoresLateProfileResult() async {
        let fetcher = AccountScopedMemberProfileBridgeFake()
        let loader = MemberProfileLoader(fetcher: fetcher)
        let bridge = WireframeRemoteReadBridge(dependencies: WireframeRemoteReadDependencies(memberProfileLoader: loader))

        let oldAccountRequest = Task { await bridge.activate(feature: .profile, accountScopeID: "account-a", screen: "M01") }
        await fetcher.waitForCalls(1)
        XCTAssertEqual(bridge.memberProfileState, .loading)

        bridge.accountDidChange(to: "account-b")
        XCTAssertEqual(bridge.memberProfileState, .idle, "The previous account's profile snapshot is cleared")
        await bridge.activate(feature: .profile, accountScopeID: "account-b", screen: "M01")
        XCTAssertEqual(bridge.memberProfileState, .loaded(MemberProfile(nickname: "NewAccount")))

        await oldAccountRequest.value
        XCTAssertEqual(bridge.memberProfileState, .loaded(MemberProfile(nickname: "NewAccount")), "A late profile response cannot restore data from account A")
    }
}

private struct WithdrawalTokenProviderFake: AccessTokenProviding {
    let token: String?
    func accessToken() async throws -> String? { token }
}

private actor WithdrawalAccountLinkServiceFake: AccountLinkServing {
    private var proofCounter = 0
    private var holdNextPasswordReauthentication=false
    private var heldPasswordProof:CheckedContinuation<AccountLinkReauthProof,Error>?
    private var passwordReauthenticationWaiter:CheckedContinuation<Void,Never>?
    func methods() async throws -> AccountLinkMethods {
        AccountLinkMethods(localPassword:true,socialProviders:[.kakao])
    }
    func reauthenticateWithPassword(_ password:String,purpose:AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        proofCounter += 1
        let char=String(UnicodeScalar(96+(proofCounter%26)+1)!)
        let proof=AccountLinkReauthProof(reauthProof:String(repeating:char,count:43),expiresInSeconds:300)
        guard holdNextPasswordReauthentication else { return proof }
        holdNextPasswordReauthentication=false
        return try await withCheckedThrowingContinuation { continuation in
            heldPasswordProof=continuation
            passwordReauthenticationWaiter?.resume()
            passwordReauthenticationWaiter=nil
        }
    }
    func holdNextPasswordProof(){holdNextPasswordReauthentication=true}
    func waitForPasswordProof() async {
        guard heldPasswordProof == nil else { return }
        await withCheckedContinuation { passwordReauthenticationWaiter=$0 }
    }
    func resumePasswordProof(){
        guard let heldPasswordProof else{return}
        self.heldPasswordProof=nil
        heldPasswordProof.resume(returning:AccountLinkReauthProof(reauthProof:String(repeating:"x",count:43),expiresInSeconds:300))
    }
    func issueReauthChallenge(provider:AccountLinkProvider,purpose:AccountLinkPurpose) async throws -> AccountLinkChallenge {
        AccountLinkChallenge(state:"fixture-state",nonce:"fixture-nonce",expiresInSeconds:300)
    }
    func verifyReauthentication(provider:AccountLinkProvider,challenge:AccountLinkChallenge,credential:String,purpose:AccountLinkPurpose) async throws -> AccountLinkReauthProof {
        try await reauthenticateWithPassword(credential,purpose:purpose)
    }
    func issueLinkChallenge(provider:AccountLinkProvider) async throws -> AccountLinkChallenge {
        AccountLinkChallenge(state:"fixture-link-state",nonce:"fixture-link-nonce",expiresInSeconds:300)
    }
    func completeLink(provider:AccountLinkProvider,challenge:AccountLinkChallenge,credential:String,reauthProof:String,consent:Bool) async throws {}
    func unlink(provider:AccountLinkProvider,reauthProof:String,consent:Bool) async throws {}
}

private struct WithdrawalCredentialProviderFake: AccountLinkCredentialProviding {
    func credential(for provider:AccountLinkProvider,purpose:AccountLinkCredentialPurpose,challenge:AccountLinkChallenge) async throws -> String? { "fixture-credential" }
}

private actor WithdrawalFlowFake: AccountLinkFlowServing {
    private var currentProof: String?
    private var currentPurpose: AccountLinkPurpose?
    func methods() async throws -> AccountLinkMethods { AccountLinkMethods(localPassword:true,socialProviders:[.kakao]) }
    func reauthenticateWithPassword(_ password:String,purpose:AccountLinkPurpose) async throws {
        currentProof=UUID().uuidString.replacingOccurrences(of:"-",with:"")+String(repeating:"z",count:11)
        currentPurpose=purpose
    }
    func reauthenticate(using provider:AccountLinkProvider,purpose:AccountLinkPurpose) async throws {
        try await reauthenticateWithPassword("fixture",purpose:purpose)
    }
    func consumeReauthenticationProof(for purpose:AccountLinkPurpose) async throws -> String {
        guard let proof=currentProof,currentPurpose==purpose else { throw AccountLinkFailure.reauthenticationRequired }
        currentProof=nil;currentPurpose=nil
        return proof
    }
    func hasProof()->Bool { currentProof != nil }
    func link(provider:AccountLinkProvider,onMutationRequestWillSubmit:@escaping @Sendable () async -> Bool) async throws { throw AccountLinkFailure.invalidRequest }
    func unlink(provider:AccountLinkProvider,onMutationRequestWillSubmit:@escaping @Sendable () async -> Bool) async throws { throw AccountLinkFailure.invalidRequest }
    func cancel() async { currentProof=nil;currentPurpose=nil }
}

private actor WithdrawalServiceFake: MemberWithdrawalServing {
    enum Outcome: Sendable { case receipt(MemberWithdrawalReceipt), failure(MemberWithdrawalFailure), hold }
    struct Post: Equatable, Sendable { let proof:String; let confirmed:Bool }
    private let outcome: Outcome
    private var posts:[Post]=[]
    private var held:CheckedContinuation<MemberWithdrawalReceipt,Error>?
    private var postWaiters:[(Int,CheckedContinuation<Void,Never>)]=[]
    private let notice:MemberWithdrawalConfirmationNotice

    init(outcome:Outcome = .receipt(ThemeTestsWithdrawalFixtures.receipt),notice:MemberWithdrawalConfirmationNotice = ThemeTestsWithdrawalFixtures.notice) {
        self.outcome=outcome;self.notice=notice
    }
    func confirmationNotice() async throws -> MemberWithdrawalConfirmationNotice { notice }
    func requestWithdrawal(reauthProof:String,confirmed:Bool) async throws -> MemberWithdrawalReceipt {
        posts.append(Post(proof:reauthProof,confirmed:confirmed))
        let satisfied=postWaiters.filter{$0.0<=posts.count}
        postWaiters.removeAll{$0.0<=posts.count}
        satisfied.forEach{$0.1.resume()}
        switch outcome {
        case .receipt(let receipt): return receipt
        case .failure(let failure): throw failure
        case .hold: return try await withCheckedThrowingContinuation{held=$0}
        }
    }
    func waitForPosts(_ count:Int) async {
        guard posts.count<count else{return}
        await withCheckedContinuation{postWaiters.append((count,$0))}
    }
    func completeHeld(with receipt:MemberWithdrawalReceipt) {
        guard let held else{return};self.held=nil;held.resume(returning:receipt)
    }
    func capturedPosts()->[Post]{posts}
}

private enum ThemeTestsWithdrawalFixtures {
    static let notice=MemberWithdrawalConfirmationNotice(message:"탈퇴 요청과 처리 항목을 확인해 주세요.",recentReauthenticationValiditySeconds:300)
    static let receipt=MemberWithdrawalReceipt(requestId:"fixture-withdrawal-request",status:"WITHDRAWN",gpsStatus:.completed,profilePhotoStatus:.pending,communityAttachmentsStatus:.retryableFailure)
    static func response(status:Int,json:[String:Any],requestID:String?="fixture-request")->APIClientResponse {
        APIClientResponse(statusCode:status,data:(try? JSONSerialization.data(withJSONObject:json)) ?? Data(),requestID:requestID)
    }
}

private actor WithdrawalQueueFake: RunUploadEnqueueing, RunUploadOwnerScopedClearing {
    private(set) var clearedOwners:[String]=[]
    func enqueueRunUpload(_ payload:RunUploadPayload,ownerID:String) async throws {}
    func clearRunUploads(ownerID:String) async throws { clearedOwners.append(ownerID) }
    func cleared()->[String]{clearedOwners}
}

extension ThemeTests {
    func testMemberWithdrawalClientUsesFiveMinuteNoticeAndConfirmedPurposeProofContract() async throws {
        let confirmation=ThemeTestsWithdrawalFixtures.response(status:200,json:["message":ThemeTestsWithdrawalFixtures.notice.message,"recentReauthenticationValiditySeconds":300])
        let receipt=ThemeTestsWithdrawalFixtures.response(status:202,json:["requestId":"fixture-withdrawal-request","status":"WITHDRAWN","gpsStatus":"COMPLETED","profilePhotoStatus":"PENDING","communityAttachmentsStatus":"RETRYABLE_FAILURE"])
        let transport=AuthSessionFixtureTransport([.response(confirmation),.response(receipt)])
        let client=MemberWithdrawalClient(apiClient:transport,tokenProvider:WithdrawalTokenProviderFake(token:"fixture-access-token"))
        let notice=try await client.confirmationNotice()
        XCTAssertEqual(notice.recentReauthenticationValiditySeconds,300)
        let proof=String(repeating:"p",count:43)
        let accepted=try await client.requestWithdrawal(reauthProof:proof,confirmed:true)
        XCTAssertEqual(accepted.status,"WITHDRAWN")
        XCTAssertFalse(accepted.allReportedDeletionComplete,"Pending media work must not be described as fully deleted")
        let requests=await transport.requests()
        XCTAssertEqual(requests.count,2,"The client sends one confirmation read and one withdrawal POST")
        XCTAssertEqual(requests[0].path,"members/me/withdrawal/confirmation")
        XCTAssertEqual(requests[0].method,"GET")
        XCTAssertEqual(requests[0].headers["Authorization"],"Bearer fixture-access-token")
        XCTAssertEqual(requests[0].headers["Cache-Control"],"no-store")
        XCTAssertEqual(requests[1].path,"members/me/withdrawal")
        XCTAssertEqual(requests[1].method,"POST")
        XCTAssertEqual(requests[1].headers["Authorization"],"Bearer fixture-access-token")
        let body=try XCTUnwrap(requests[1].body.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]})
        XCTAssertEqual(body["reauthProof"] as? String,proof)
        XCTAssertEqual(body["confirmed"] as? Bool,true)
        do {
            _=try await client.requestWithdrawal(reauthProof:proof,confirmed:false)
            XCTFail("The client must reject an unconfirmed request before sending")
        } catch let failure as MemberWithdrawalFailure {
            XCTAssertEqual(failure,.confirmationRequired)
        }
        let requestsAfterRejectedConfirmation=await transport.requests()
        XCTAssertEqual(requestsAfterRejectedConfirmation.count,2)
    }

    func testWithdrawalProofCannotCrossPurposeAndIsConsumedOnce() async throws {
        let service=WithdrawalAccountLinkServiceFake()
        let flow=AccountLinkFlowCoordinator(service:service,credentials:WithdrawalCredentialProviderFake())
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.link)
        do {
            _=try await flow.consumeReauthenticationProof(for:.withdrawal)
            XCTFail("LINK proof cannot be used for WITHDRAWAL")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure,.reauthenticationRequired)
        }
        _=try await flow.consumeReauthenticationProof(for:.link)
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal)
        let withdrawalProof=try await flow.consumeReauthenticationProof(for:.withdrawal)
        XCTAssertEqual(withdrawalProof.count,43)
        do {
            _=try await flow.consumeReauthenticationProof(for:.withdrawal)
            XCTFail("A purpose-bound proof is one-time")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure,.reauthenticationRequired)
        }
    }

    func testCancellationDuringReauthenticationCannotRestoreLateWithdrawalProof() async throws {
        let service=WithdrawalAccountLinkServiceFake()
        await service.holdNextPasswordProof()
        let flow=AccountLinkFlowCoordinator(service:service,credentials:WithdrawalCredentialProviderFake())
        let reauthentication=Task { try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal) }
        await service.waitForPasswordProof()
        await flow.cancel()
        await service.resumePasswordProof()
        do {
            try await reauthentication.value
            XCTFail("A canceled reauthentication must not install its late proof")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure,.cancelled)
        }
        do {
            _=try await flow.consumeReauthenticationProof(for:.withdrawal)
            XCTFail("A late proof after cancellation must remain unusable")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure,.reauthenticationRequired)
        }
    }

    func testWithdrawalTransportLossAndExpiredSessionStayUnconfirmedWithoutRetry() async throws {
        let store=AuthSessionFixtureStore(snapshot:try AuthSessionFixtures.session(memberID:"41"))
        let timedOut=AuthSessionFixtureTransport([.failure(.transport(.timedOut))])
        let client=MemberWithdrawalClient(apiClient:timedOut,tokenProvider:WithdrawalTokenProviderFake(token:"fixture-access-token"))
        do {
            _=try await client.requestWithdrawal(reauthProof:String(repeating:"q",count:43),confirmed:true)
            XCTFail("A lost response cannot be accepted as success")
        } catch let failure as MemberWithdrawalFailure {
            XCTAssertTrue(failure.outcomeUnknown)
        }
        let timedOutRequests=await timedOut.requests()
        XCTAssertEqual(timedOutRequests.count,1,"No automatic retry after a possibly sent POST")
        XCTAssertNotNil(try store.loadSnapshot(),"The client has no authority to clear the local session")

        let unauthorized=AuthSessionFixtureTransport([.response(APIClientResponse(statusCode:401,data:Data(),requestID:"expired-session"))])
        let authClient=AuthSessionClient(apiClient:unauthorized,sessionStore:store)
        let expiredClient=MemberWithdrawalClient(apiClient:unauthorized,tokenProvider:authClient)
        do {
            _=try await expiredClient.requestWithdrawal(reauthProof:String(repeating:"r",count:43),confirmed:true)
            XCTFail("Expired session must not be treated as withdrawal")
        } catch let failure as MemberWithdrawalFailure {
            XCTAssertEqual(failure,.unauthenticated)
        }
        let unauthorizedRequests=await unauthorized.requests()
        XCTAssertEqual(unauthorizedRequests.count,1)
        XCTAssertNotNil(try store.loadSnapshot())
    }

    @MainActor func testWithdrawalBridgeBlocksDuplicateSubmitAndIgnoresLateResponseAfterAccountSwitch() async throws {
        let store=AuthSessionFixtureStore(snapshot:try AuthSessionFixtures.session(memberID:"41"))
        let authClient=AuthSessionClient(apiClient:AuthSessionFixtureTransport([]),sessionStore:store)
        let service=WithdrawalServiceFake(outcome:.hold)
        let flow=WithdrawalFlowFake()
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            authSessionStore:store,
            authSessionClient:authClient,
            accountLinkFlow:flow,
            memberWithdrawalService:service
        ))
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T11")
        XCTAssertEqual(bridge.memberWithdrawalState,.ready)
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal)
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T16")
        let pending=Task { @MainActor in await bridge.submitMemberWithdrawal(accountScopeID:"scope-a",screen:"T16") }
        await service.waitForPosts(1)
        let duplicate=await bridge.submitMemberWithdrawal(accountScopeID:"scope-a",screen:"T16")
        XCTAssertNil(duplicate)
        let submittedPosts=await service.capturedPosts()
        XCTAssertEqual(submittedPosts.count,1,"A second tap cannot submit a concurrent POST")

        await bridge.activate(feature:nil,accountScopeID:"scope-b",screen:"T16")
        await service.completeHeld(with:ThemeTestsWithdrawalFixtures.receipt)
        let lateResponse=await pending.value
        XCTAssertNil(lateResponse,"Late response from account A must not be applied to account B")
        XCTAssertNotNil(try store.loadSnapshot(),"A late response cannot clear the active local session")
        if case .outcomeUnknown(_)=bridge.memberWithdrawalState {} else { XCTFail("Account change during a sent request must remain outcome-unknown") }
    }

    func testConfirmedWithdrawalSessionClearIsMemberScoped() async throws {
        let accountA=try AuthSessionFixtures.session(memberID:"41")
        let store=AuthSessionFixtureStore(snapshot:accountA)
        let client=AuthSessionClient(apiClient:AuthSessionFixtureTransport([]),sessionStore:store)
        do {
            try await client.clearAfterConfirmedWithdrawal(expectedMemberID:"99")
            XCTFail("A stale confirmation cannot clear another account")
        } catch let failure as AuthSessionFailure {
            XCTAssertEqual(failure,.sessionChanged)
        }
        XCTAssertEqual(try store.loadSnapshot(),accountA)
        try await client.clearAfterConfirmedWithdrawal(expectedMemberID:"41")
        XCTAssertNil(try store.loadSnapshot())
    }

    @MainActor func testWithdrawalLocalCleanupPreservesOtherAndOwnerlessRecords() async throws {
        let suite="MovTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let memberA=RunRecord(date:Date(timeIntervalSince1970:100),title:"member A",seconds:120,kilometers:1,uploadOwnerID:"41",clientRunID:UUID())
        let memberB=RunRecord(date:Date(timeIntervalSince1970:200),title:"member B",seconds:180,kilometers:2,uploadOwnerID:"99",clientRunID:UUID())
        let ownerless=RunRecord(date:Date(timeIntervalSince1970:300),title:"ownerless",seconds:90,kilometers:0.5)
        let persistence=RunStoreOwnedRecordsFake(snapshot:.canonical([memberA,memberB]))
        let queue=WithdrawalQueueFake()
        let store=RunStore(defaults:defaults,uploadQueue:queue,ownedRecordsPersistence:persistence)
        store.records.append(ownerless)
        XCTAssertTrue(store.persist())

        let didClear=await store.clearOwnedRecords(for:"41")
        XCTAssertTrue(didClear)
        XCTAssertEqual(Set(store.records.map(\.id)),Set([memberB.id,ownerless.id]))
        XCTAssertEqual(persistence.canonicalRecords.map(\.id),[memberB.id])
        let clearedOwners=await queue.cleared()
        XCTAssertEqual(clearedOwners,["41"])
    }

    @MainActor func testWithdrawalCancellationAndBackDiscardUnusedProofWithoutPosting() async throws {
        let store=AuthSessionFixtureStore(snapshot:try AuthSessionFixtures.session(memberID:"41"))
        let authClient=AuthSessionClient(apiClient:AuthSessionFixtureTransport([]),sessionStore:store)
        let service=WithdrawalServiceFake()
        let flow=WithdrawalFlowFake()
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            authSessionStore:store,authSessionClient:authClient,accountLinkFlow:flow,memberWithdrawalService:service
        ))
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T11")
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal)
        XCTAssertTrue(bridge.cancelMemberWithdrawalFlow())
        for _ in 0..<100 {
            if !(await flow.hasProof()) { break }
            try? await Task.sleep(for:.milliseconds(2))
        }
        let proofAfterCancel=await flow.hasProof()
        XCTAssertFalse(proofAfterCancel)
        do {
            _=try await flow.consumeReauthenticationProof(for:.withdrawal)
            XCTFail("Cancellation discards the unsubmitted proof")
        } catch let failure as AccountLinkFailure {
            XCTAssertEqual(failure,.reauthenticationRequired)
        }

        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T11")
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal)
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T04")
        for _ in 0..<100 {
            if !(await flow.hasProof()) { break }
            try? await Task.sleep(for:.milliseconds(2))
        }
        let proofAfterBack=await flow.hasProof()
        XCTAssertFalse(proofAfterBack,"Navigating back out of withdrawal clears unused proof")
        let postsAfterCancel=await service.capturedPosts()
        XCTAssertTrue(postsAfterCancel.isEmpty)
        XCTAssertNotNil(try store.loadSnapshot())
    }

    @MainActor func testConfirmedWithdrawalClearsOnlyThatMembersLocalRunsAndSession() async throws {
        let suite="MovTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let memberA=RunRecord(date:Date(timeIntervalSince1970:100),title:"member A",seconds:120,kilometers:1,uploadOwnerID:"41",clientRunID:UUID())
        let memberB=RunRecord(date:Date(timeIntervalSince1970:200),title:"member B",seconds:180,kilometers:2,uploadOwnerID:"99",clientRunID:UUID())
        let ownerless=RunRecord(date:Date(timeIntervalSince1970:300),title:"ownerless",seconds:90,kilometers:0.5)
        let persistence=RunStoreOwnedRecordsFake(snapshot:.canonical([memberA,memberB]))
        let queue=WithdrawalQueueFake()
        let runStore=RunStore(defaults:defaults,uploadQueue:queue,ownedRecordsPersistence:persistence)
        runStore.records.append(ownerless)
        XCTAssertTrue(runStore.persist())

        let sessionStore=AuthSessionFixtureStore(snapshot:try AuthSessionFixtures.session(memberID:"41"))
        let authClient=AuthSessionClient(apiClient:AuthSessionFixtureTransport([]),sessionStore:sessionStore)
        let service=WithdrawalServiceFake()
        let flow=WithdrawalFlowFake()
        let bridge=WireframeRemoteReadBridge(dependencies:WireframeRemoteReadDependencies(
            authSessionStore:sessionStore,authSessionClient:authClient,accountLinkFlow:flow,memberWithdrawalService:service
        ))
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T11")
        try await flow.reauthenticateWithPassword("fixture-password",purpose:.withdrawal)
        await bridge.activate(feature:nil,accountScopeID:"scope-a",screen:"T16")
        let acceptedReceipt=await bridge.submitMemberWithdrawal(accountScopeID:"scope-a",screen:"T16")
        let receipt=try XCTUnwrap(acceptedReceipt)
        XCTAssertEqual(receipt.status,"WITHDRAWN")
        XCTAssertEqual(bridge.memberWithdrawalMemberID,"41")

        let didClear=await runStore.clearOwnedRecords(for:"41")
        XCTAssertTrue(didClear)
        try await authClient.clearAfterConfirmedWithdrawal(expectedMemberID:"41")
        XCTAssertNil(try sessionStore.loadSnapshot())
        XCTAssertEqual(Set(runStore.records.map(\.id)),Set([memberB.id,ownerless.id]))
        XCTAssertEqual(persistence.canonicalRecords.map(\.id),[memberB.id])
        let clearedOwners=await queue.cleared()
        XCTAssertEqual(clearedOwners,["41"])
    }
}
