import AVFoundation
import AVKit
import CryptoKit
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WCommunityVideoAttachment:Identifiable,Equatable {
    let id:String
    let path:String
    let posterPath:String
    let byteCount:Int
    let duration:Double
    let width:Int
    let height:Int
    let sourceIdentifier:String?
    let sourceFingerprint:String
    var url:URL{URL(fileURLWithPath:path)}
    var posterURL:URL{URL(fileURLWithPath:posterPath)}
}

enum WCommunityVideoError:LocalizedError,Equatable {
    case inputTooLarge
    case duration
    case noVideoTrack
    case invalidVideo
    case outputTooLarge
    case outputDimensions
    case conversionFailed
    case storageUnavailable
    case duplicate
    case aggregateTooLarge

    var errorDescription:String? {
        switch self {
        case .inputTooLarge:return "영상 원본은 50 MB 이하로 선택해 주세요."
        case .duration:return "영상은 15초 이하만 선택해 주세요."
        case .noVideoTrack:return "영상 트랙을 찾지 못했어요. 재생할 수 있는 동영상을 선택해 주세요."
        case .invalidVideo:return "영상이 손상됐거나 재생할 수 없어요. 다른 동영상을 선택해 주세요."
        case .outputTooLarge:return "변환한 영상이 20 MB를 넘어요. 더 짧은 영상을 선택해 주세요."
        case .outputDimensions:return "변환 영상의 해상도를 1080p 이하로 맞추지 못했어요. 다른 영상을 선택해 주세요."
        case .conversionFailed:return "영상 변환에 실패했어요. 다른 동영상을 선택해 주세요."
        case .storageUnavailable:return "변환 영상을 이 기기에 임시 저장하지 못했어요."
        case .duplicate:return "이미 첨부한 영상이에요."
        case .aggregateTooLarge:return "첨부한 사진과 영상의 전체 크기는 100 MB 이하여야 해요."
        }
    }
}

enum WCommunityVideoPolicy {
    static let maximumOriginalBytes=50_000_000
    static let maximumDuration:Double=15
    static let maximumConvertedBytes=20_000_000
    static let maximumLongEdge=1_920
    static let maximumShortEdge=1_080
    static let maximumAggregateBytes=100_000_000

    static func validateSource(size:Int,duration:Double,videoTrackCount:Int)throws {
        guard size>0 else{throw WCommunityVideoError.invalidVideo}
        guard size<=maximumOriginalBytes else{throw WCommunityVideoError.inputTooLarge}
        guard videoTrackCount>0 else{throw WCommunityVideoError.noVideoTrack}
        guard duration.isFinite,duration>0 else{throw WCommunityVideoError.invalidVideo}
        guard duration<=maximumDuration else{throw WCommunityVideoError.duration}
    }

    static func validateOutput(size:Int,width:Int,height:Int)throws {
        guard size>0 else{throw WCommunityVideoError.conversionFailed}
        guard size<=maximumConvertedBytes else{throw WCommunityVideoError.outputTooLarge}
        guard width>0,height>0,max(width,height)<=maximumLongEdge,min(width,height)<=maximumShortEdge else{throw WCommunityVideoError.outputDimensions}
    }

    static func canAppend(currentCount:Int,currentBytes:Int,addingCount:Int,addingBytes:Int)->Bool {
        currentCount>=0 && currentBytes>=0 && addingCount>=0 && addingBytes>=0 && currentCount+addingCount<=WCommunityPhotoPolicy.maximumAttachments && currentBytes+addingBytes<=maximumAggregateBytes
    }

    static func isDuplicate(_ candidate:WCommunityVideoAttachment,in attachments:[WCommunityAttachment])->Bool {
        attachments.contains { item in
            guard let existing=item.video else{return false}
            return (candidate.sourceIdentifier != nil && candidate.sourceIdentifier==existing.sourceIdentifier) || candidate.sourceFingerprint==existing.sourceFingerprint
        }
    }
}

@MainActor @Observable final class WCommunityVideoPlaybackController {
    private(set) var playingIDs:Set<String>=[]
    private var players:[String:AVPlayer]=[:]

    func player(for video:WCommunityVideoAttachment)->AVPlayer {
        if let player=players[video.id]{return player}
        let player=AVPlayer(url:video.url);player.actionAtItemEnd = .pause;players[video.id]=player;return player
    }

    func isPlaying(_ video:WCommunityVideoAttachment)->Bool{playingIDs.contains(video.id)}

    func toggle(_ video:WCommunityVideoAttachment) {
        let player=player(for:video)
        if playingIDs.contains(video.id){player.pause();playingIDs.remove(video.id)}else{player.play();playingIDs.insert(video.id)}
    }

    func stop(_ video:WCommunityVideoAttachment) {
        players[video.id]?.pause();players[video.id]?.seek(to:.zero);players.removeValue(forKey:video.id);playingIDs.remove(video.id)
    }

    func stopAll(){for player in players.values{player.pause();player.seek(to:.zero)};players.removeAll();playingIDs=[]}
}

@MainActor struct WCommunityVideoPlaybackView:View {
    let video:WCommunityVideoAttachment
    let controller:WCommunityVideoPlaybackController
    @State private var player:AVPlayer?

    var body:some View {
        ZStack(alignment:.bottomTrailing){
            Group {
                if let player {WCommunityVideoSurface(player:player).accessibilityIdentifier("communityVideoPlayback").accessibilityHidden(true)}
                else if let image=UIImage(contentsOfFile:video.posterPath){Image(uiImage:image).resizable().scaledToFit()}
                else{Color.black}
            }
            Button {controller.toggle(video)} label:{Label(controller.isPlaying(video) ? "일시정지":"재생",systemImage:controller.isPlaying(video) ? "pause.fill":"play.fill").font(W.font(12,.semibold)).foregroundStyle(.white).padding(.horizontal,14).frame(height:40).background(.black.opacity(0.72),in:Capsule())}
                .padding(12).accessibilityIdentifier(controller.isPlaying(video) ? "communityVideoPause":"communityVideoPlay")
        }
        .accessibilityElement(children:.contain)
        .accessibilityIdentifier("communityVideoViewer")
        .onAppear{player=controller.player(for:video)}
        .onDisappear{controller.stop(video);player=nil}
    }
}

private struct WCommunityVideoSurface:UIViewRepresentable {
    let player:AVPlayer
    func makeUIView(context:Context)->WCommunityVideoLayerView{let view=WCommunityVideoLayerView();view.playerLayer.player=player;return view}
    func updateUIView(_ view:WCommunityVideoLayerView,context:Context){view.playerLayer.player=player}
}

private final class WCommunityVideoLayerView:UIView {
    override class var layerClass:AnyClass{AVPlayerLayer.self}
    var playerLayer:AVPlayerLayer{layer as! AVPlayerLayer}
    override init(frame:CGRect){super.init(frame:frame);playerLayer.videoGravity = .resizeAspect;isAccessibilityElement=false;accessibilityElementsHidden=true}
    required init?(coder:NSCoder){super.init(coder:coder);playerLayer.videoGravity = .resizeAspect;isAccessibilityElement=false;accessibilityElementsHidden=true}
}

enum WCommunityVideoFixtureFactory {
    static func writeMP4(to url:URL)throws {
        let writer:AVAssetWriter
        do{writer=try AVAssetWriter(outputURL:url,fileType:.mp4)}catch{throw WCommunityVideoError.conversionFailed}
        let settings:[String:Any]=[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:350_000,AVVideoExpectedSourceFrameRateKey:12]]
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:settings);input.expectsMediaDataInRealTime=false
        let pixelAttributes:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:240,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:pixelAttributes)
        guard writer.canAdd(input) else{throw WCommunityVideoError.conversionFailed}
        writer.add(input)
        guard writer.startWriting() else{throw WCommunityVideoError.conversionFailed}
        writer.startSession(atSourceTime:.zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {if writer.status == .failed{throw WCommunityVideoError.conversionFailed};Thread.sleep(forTimeInterval:0.001)}
            guard let pool=adaptor.pixelBufferPool else{throw WCommunityVideoError.conversionFailed}
            var optionalBuffer:CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,pool,&optionalBuffer)==kCVReturnSuccess,let buffer=optionalBuffer else{throw WCommunityVideoError.conversionFailed}
            CVPixelBufferLockBaseAddress(buffer,[])
            defer{CVPixelBufferUnlockBaseAddress(buffer,[])}
            guard let base=CVPixelBufferGetBaseAddress(buffer),let context=CGContext(data:base,width:320,height:240,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue) else{throw WCommunityVideoError.conversionFailed}
            context.setFillColor(UIColor(red:0.1,green:0.35+CGFloat(frame%12)/30,blue:0.7,alpha:1).cgColor);context.fill(CGRect(x:0,y:0,width:320,height:240))
            context.setFillColor(UIColor.white.cgColor);context.fillEllipse(in:CGRect(x:CGFloat(frame)*9,y:82,width:72,height:72))
            guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:12)) else{throw writer.error ?? WCommunityVideoError.conversionFailed}
        }
        input.markAsFinished()
        let semaphore=DispatchSemaphore(value:0)
        writer.finishWriting{semaphore.signal()}
        guard semaphore.wait(timeout:.now()+20) == .success,writer.status == .completed else{throw writer.error ?? WCommunityVideoError.conversionFailed}
    }
}

@MainActor @Observable final class WCommunityMediaImportCoordinator {
    private(set) var generation=0
    private var exportSession:AVAssetExportSession?

    @discardableResult func beginRequest()->Int {
        generation &+= 1
        exportSession?.cancelExport()
        exportSession=nil
        return generation
    }

    func accepts(_ request:Int)->Bool{request==generation}

    @discardableResult func register(_ session:AVAssetExportSession,for request:Int)->Bool {
        guard accepts(request) else{session.cancelExport();return false}
        exportSession=session
        return true
    }

    func unregister(_ session:AVAssetExportSession,for request:Int) {
        guard accepts(request),exportSession === session else{return}
        exportSession=nil
    }

    func invalidate(){_ = beginRequest()}
}

enum WCommunityVideoTemporaryFiles {
    static var rootURL:URL {
        let bundle=Bundle.main.bundleIdentifier ?? "com.movtorun.mov"
        return FileManager.default.temporaryDirectory.appendingPathComponent("MovCommunityAttachments",isDirectory:true).appendingPathComponent(bundle,isDirectory:true)
    }
    static var draftURL:URL{rootURL.appendingPathComponent("draft",isDirectory:true)}

    static func importedSourceURL(for source:URL)throws->URL {
        let folder=draftURL
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let ext=source.pathExtension.filter{$0.isASCII && ($0.isLetter || $0.isNumber)}
            let url=folder.appendingPathComponent("source-\(UUID().uuidString)").appendingPathExtension(ext.isEmpty ? "movie":ext)
            try FileManager.default.copyItem(at:source,to:url)
            return url
        } catch {throw WCommunityVideoError.storageUnavailable}
    }

    static func removeImportedSource(_ url:URL?) {
        guard let url else{return}
        let candidate=url.standardizedFileURL
        guard candidate.deletingLastPathComponent()==draftURL.standardizedFileURL,candidate.lastPathComponent.hasPrefix("source-") else{return}
        try? FileManager.default.removeItem(at:candidate)
    }
}

struct WCommunityVideoMetadata:Equatable {
    let size:Int
    let duration:Double
    let width:Int
    let height:Int
}

@MainActor enum WCommunityVideoTranscoder {
    private static let exportPresets=[AVAssetExportPreset1920x1080,AVAssetExportPreset1280x720,AVAssetExportPreset640x480,AVAssetExportPresetLowQuality]

    static func inspectSource(_ url:URL)async throws->WCommunityVideoMetadata {
        let values=try? url.resourceValues(forKeys:[.fileSizeKey])
        guard let size=values?.fileSize else{throw WCommunityVideoError.invalidVideo}
        let asset=AVURLAsset(url:url)
        let duration:Double
        do{duration=try await asset.load(.duration).seconds}catch{throw WCommunityVideoError.invalidVideo}
        let tracks:[AVAssetTrack]
        do{tracks=try await asset.loadTracks(withMediaType:.video)}catch{throw WCommunityVideoError.invalidVideo}
        guard let track=tracks.first else{throw WCommunityVideoError.noVideoTrack}
        let naturalSize:CGSize,transform:CGAffineTransform
        do{naturalSize=try await track.load(.naturalSize);transform=try await track.load(.preferredTransform)}catch{throw WCommunityVideoError.invalidVideo}
        let transformed=CGRect(origin:.zero,size:naturalSize).applying(transform).standardized
        let width=Int(transformed.width.rounded()),height=Int(transformed.height.rounded())
        try WCommunityVideoPolicy.validateSource(size:size,duration:duration,videoTrackCount:tracks.count)
        guard width>0,height>0 else{throw WCommunityVideoError.invalidVideo}
        return WCommunityVideoMetadata(size:size,duration:duration,width:width,height:height)
    }

    static func inspectOutput(_ url:URL)async throws->WCommunityVideoMetadata {
        let values=try? url.resourceValues(forKeys:[.fileSizeKey])
        guard let size=values?.fileSize else{throw WCommunityVideoError.conversionFailed}
        let asset=AVURLAsset(url:url)
        let duration:Double
        do{duration=try await asset.load(.duration).seconds}catch{throw WCommunityVideoError.conversionFailed}
        let tracks:[AVAssetTrack]
        do{tracks=try await asset.loadTracks(withMediaType:.video)}catch{throw WCommunityVideoError.conversionFailed}
        guard let track=tracks.first else{throw WCommunityVideoError.conversionFailed}
        let naturalSize:CGSize,transform:CGAffineTransform
        do{naturalSize=try await track.load(.naturalSize);transform=try await track.load(.preferredTransform)}catch{throw WCommunityVideoError.conversionFailed}
        let transformed=CGRect(origin:.zero,size:naturalSize).applying(transform).standardized
        let width=Int(transformed.width.rounded()),height=Int(transformed.height.rounded())
        try WCommunityVideoPolicy.validateOutput(size:size,width:width,height:height)
        guard duration.isFinite,duration>0,duration<=WCommunityVideoPolicy.maximumDuration else{throw WCommunityVideoError.duration}
        return WCommunityVideoMetadata(size:size,duration:duration,width:width,height:height)
    }

    static func sourceFingerprint(_ url:URL)async throws->String {
        try await Task.detached(priority:.utility){
            let handle=try FileHandle(forReadingFrom:url)
            defer{try? handle.close()}
            var hasher=SHA256()
            while let chunk=try handle.read(upToCount:1_048_576),!chunk.isEmpty{hasher.update(data:chunk)}
            return hasher.finalize().map{String(format:"%02x",Int($0))}.joined()
        }.value
    }

    static func convert(sourceURL:URL,sourceIdentifier:String?,store:WCommunityAttachmentStore,coordinator:WCommunityMediaImportCoordinator,request:Int)async throws->WCommunityVideoAttachment {
        defer{store.removeTemporaryVideoFile(sourceURL)}
        _ = try await inspectSource(sourceURL)
        try Task.checkCancellation()
        guard coordinator.accepts(request) else{throw CancellationError()}
        let asset=AVURLAsset(url:sourceURL)
        let fingerprint=try await sourceFingerprint(sourceURL)
        try Task.checkCancellation()
        guard coordinator.accepts(request) else{throw CancellationError()}
        var exported=false
        var lastFailure:WCommunityVideoError = .conversionFailed

        for preset in exportPresets {
            try Task.checkCancellation()
            guard coordinator.accepts(request) else{throw CancellationError()}
            guard let session=AVAssetExportSession(asset:asset,presetName:preset) else{continue}
            let outputURL:URL
            do{outputURL=try store.makeVideoWorkingURL()}catch{throw WCommunityVideoError.storageUnavailable}
            defer{store.removeTemporaryVideoFile(outputURL)}
            guard session.supportedFileTypes.contains(.mp4) else{continue}
            session.outputURL=outputURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse=true
            session.metadata=[]
            guard coordinator.register(session,for:request) else{throw CancellationError()}
            do{try await export(session)}catch{
                coordinator.unregister(session,for:request)
                if Task.isCancelled || !coordinator.accepts(request){throw CancellationError()}
                lastFailure = .conversionFailed
                continue
            }
            coordinator.unregister(session,for:request)
            try Task.checkCancellation()
            guard coordinator.accepts(request) else{throw CancellationError()}
            exported=true
            do {
                let output=try await inspectOutput(outputURL)
                let poster=try await makePoster(from:outputURL)
                try Task.checkCancellation()
                guard coordinator.accepts(request) else{throw CancellationError()}
                return try store.stageConvertedVideo(at:outputURL,posterData:poster,metadata:output,sourceIdentifier:sourceIdentifier,fingerprint:fingerprint)
            } catch let error as WCommunityVideoError {
                if error == .outputTooLarge || error == .outputDimensions{lastFailure=error;continue}
                throw error
            }
        }
        if exported && lastFailure == .outputTooLarge{throw WCommunityVideoError.outputTooLarge}
        if exported && lastFailure == .outputDimensions{throw WCommunityVideoError.outputDimensions}
        throw lastFailure
    }

    private static func export(_ session:AVAssetExportSession)async throws {
        let cancellationBox=WCommunityExportSessionBox(session)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation{continuation in
                session.exportAsynchronously {
                    switch cancellationBox.session.status {
                    case .completed:continuation.resume()
                    case .cancelled:continuation.resume(throwing:CancellationError())
                    default:continuation.resume(throwing:cancellationBox.session.error ?? WCommunityVideoError.conversionFailed)
                    }
                }
            }
        } onCancel:{cancellationBox.session.cancelExport()}
    }

    private static func makePoster(from url:URL)async throws->Data {
        let asset=AVURLAsset(url:url),generator=AVAssetImageGenerator(asset:asset)
        generator.appliesPreferredTrackTransform=true
        generator.maximumSize=CGSize(width:320,height:320)
        do {
            let result=try await generator.image(at:.zero)
            guard let data=UIImage(cgImage:result.image).jpegData(compressionQuality:0.82),!data.isEmpty else{throw WCommunityVideoError.conversionFailed}
            return data
        } catch {throw WCommunityVideoError.conversionFailed}
    }
}

private final class WCommunityExportSessionBox:@unchecked Sendable {
    let session:AVAssetExportSession
    init(_ session:AVAssetExportSession){self.session=session}
}
