import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WCommunityPhotoAttachment:Identifiable,Equatable {
    let id:String
    let path:String
    let byteCount:Int
    var url:URL { URL(fileURLWithPath:path) }
}

struct WCommunityPhotoSource:Identifiable {
    let id:String
    let imageName:String?
    let attachment:WCommunityPhotoAttachment?
    init(imageName:String){self.id="fixture-\(imageName)";self.imageName=imageName;self.attachment=nil}
    init(attachment:WCommunityPhotoAttachment){self.id=attachment.id;self.imageName=nil;self.attachment=attachment}
}

enum WCommunityPhotoError:LocalizedError,Equatable {
    case inputTooLarge
    case unsupportedImage
    case outputTooLarge
    case storageUnavailable
    case unmanagedFile

    var errorDescription:String? {
        switch self {
        case .inputTooLarge:return "사진 원본은 20 MB 이하로 선택해 주세요."
        case .unsupportedImage:return "열 수 있는 JPEG, PNG, HEIC 또는 HEIF 사진을 선택해 주세요."
        case .outputTooLarge:return "사진을 5 MB 이하로 줄이지 못했어요. 다른 사진을 선택해 주세요."
        case .storageUnavailable:return "사진을 이 기기에 임시 저장하지 못했어요."
        case .unmanagedFile:return "이 게시물에서 관리하는 사진을 찾지 못했어요."
        }
    }
}

enum WCommunityPhotoPolicy {
    static let maximumAttachments=10
    static let maximumOriginalBytes=20_000_000
    static let maximumPhotoBytes=5_000_000
    static let maximumAggregateBytes=100_000_000
    static let maximumEdge=8_192
    static let maximumPixels=40_000_000

    static func canAppend(currentCount:Int,currentBytes:Int,addingCount:Int,addingBytes:Int)->Bool {
        currentCount>=0 && currentBytes>=0 && addingCount>0 && addingBytes>0 &&
        currentCount+addingCount<=maximumAttachments && currentBytes+addingBytes<=maximumAggregateBytes
    }

    static func convertedBytes(from original:Data)throws->Data {
        guard original.count>0 else{throw WCommunityPhotoError.unsupportedImage}
        guard original.count<=maximumOriginalBytes else{throw WCommunityPhotoError.inputTooLarge}
        guard let source=CGImageSourceCreateWithData(original as CFData,nil),
              let identifier=CGImageSourceGetType(source),
              let type=UTType(identifier as String),type.conforms(to:.image),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let rawWidth=(properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight=(properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth>0,rawHeight>0 else{throw WCommunityPhotoError.unsupportedImage}
        let orientation=(properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions=[5,6,7,8].contains(orientation)
        let width=swapsDimensions ? rawHeight:rawWidth
        let height=swapsDimensions ? rawWidth:rawHeight
        let edgeScale=min(1,Double(maximumEdge)/Double(max(width,height)))
        let pixelScale=min(1,sqrt(Double(maximumPixels)/(Double(width)*Double(height))))
        let baseScale=min(edgeScale,pixelScale)
        let thumbnailEdge=max(1,Int((Double(max(width,height))*baseScale).rounded(.down)))
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:thumbnailEdge,kCGImageSourceShouldCacheImmediately:true]
        guard let rawCGImage=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else{throw WCommunityPhotoError.unsupportedImage}
        let image=UIImage(cgImage:rawCGImage,scale:1,orientation:.up)
        let outputWidth=rawCGImage.width,outputHeight=rawCGImage.height
        let hasAlpha:Bool
        switch rawCGImage.alphaInfo {
        case .first,.last,.premultipliedFirst,.premultipliedLast:hasAlpha=true
        default:hasAlpha=false
        }

        let outputScale=min(1,min(Double(maximumEdge)/Double(max(outputWidth,outputHeight)),sqrt(Double(maximumPixels)/(Double(outputWidth)*Double(outputHeight)))))
        var scale=outputScale
        while scale>=0.2 {
            let outputSize=CGSize(width:max(1,Int((Double(outputWidth)*scale).rounded())),height:max(1,Int((Double(outputHeight)*scale).rounded())))
            let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque = !hasAlpha
            let normalized=UIGraphicsImageRenderer(size:outputSize,format:format).image { context in
                if !hasAlpha { context.cgContext.setFillColor(UIColor.white.cgColor);context.cgContext.fill(CGRect(origin:.zero,size:outputSize)) }
                image.draw(in:CGRect(origin:.zero,size:outputSize))
            }
            guard let cgImage=normalized.cgImage else{throw WCommunityPhotoError.unsupportedImage}
            if hasAlpha {
                if let png=normalized.pngData(),png.count<=maximumPhotoBytes{return png}
            } else {
                for quality in [0.9,0.82,0.74,0.66,0.58,0.5,0.42,0.34] {
                    let output=NSMutableData()
                    guard let destination=CGImageDestinationCreateWithData(output as CFMutableData,UTType.jpeg.identifier as CFString,1,nil) else{continue}
                    CGImageDestinationAddImage(destination,cgImage,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
                    if CGImageDestinationFinalize(destination) {
                        let jpeg=output as Data
                        if jpeg.count<=maximumPhotoBytes{return jpeg}
                    }
                }
            }
            scale *= 0.82
        }
        throw WCommunityPhotoError.outputTooLarge
    }
}

@MainActor final class WCommunityAttachmentStore {
    let rootURL:URL
    private let fileManager:FileManager
    private var draftURL:URL { rootURL.appendingPathComponent("draft",isDirectory:true) }
    private var publishedURL:URL { rootURL.appendingPathComponent("published",isDirectory:true) }

    init(rootURL:URL?=nil,fileManager:FileManager = .default,clearOnCreate:Bool=true) {
        self.fileManager=fileManager
        if let rootURL { self.rootURL=rootURL }
        else {
            let bundle=Bundle.main.bundleIdentifier ?? "com.movtorun.mov"
            self.rootURL=fileManager.temporaryDirectory.appendingPathComponent("MovCommunityAttachments",isDirectory:true).appendingPathComponent(bundle,isDirectory:true)
        }
        if clearOnCreate { try? fileManager.removeItem(at:self.rootURL) }
    }

    func saveDraft(_ data:Data,id:String=UUID().uuidString)throws->WCommunityPhotoAttachment {
        guard data.count>0,data.count<=WCommunityPhotoPolicy.maximumPhotoBytes else{throw WCommunityPhotoError.outputTooLarge}
        let folder=draftURL
        do {
            try fileManager.createDirectory(at:folder,withIntermediateDirectories:true)
            let url=folder.appendingPathComponent(id).appendingPathExtension(Self.fileExtension(for:data))
            try data.write(to:url,options:.atomic)
            return WCommunityPhotoAttachment(id:id,path:url.path,byteCount:data.count)
        } catch { throw WCommunityPhotoError.storageUnavailable }
    }

    func commit(_ attachments:[WCommunityPhotoAttachment],forPost postID:String)throws->[WCommunityPhotoAttachment] {
        let postFolder=publishedURL.appendingPathComponent(Self.safeComponent(postID),isDirectory:true)
        var committed:[WCommunityPhotoAttachment]=[]
        var moved:[(URL,URL)]=[]
        do {
            for item in attachments {
                guard isOwned(item.url),fileManager.fileExists(atPath:item.path) else{throw WCommunityPhotoError.unmanagedFile}
                let current=item.url.standardizedFileURL
                if current.path.hasPrefix(postFolder.standardizedFileURL.path+"/") {
                    committed.append(item);continue
                }
                guard current.path.hasPrefix(draftURL.standardizedFileURL.path+"/") else{throw WCommunityPhotoError.unmanagedFile}
                try fileManager.createDirectory(at:postFolder,withIntermediateDirectories:true)
                let destination=postFolder.appendingPathComponent(current.lastPathComponent)
                try fileManager.moveItem(at:current,to:destination)
                moved.append((current,destination))
                committed.append(WCommunityPhotoAttachment(id:item.id,path:destination.path,byteCount:item.byteCount))
            }
            return committed
        } catch {
            for (source,destination) in moved.reversed() {
                try? fileManager.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? fileManager.moveItem(at:destination,to:source)
            }
            if let error=error as? WCommunityPhotoError{throw error}
            throw WCommunityPhotoError.storageUnavailable
        }
    }

    func discardDraft(_ attachments:[WCommunityPhotoAttachment]) {
        for item in attachments where isDraft(item.url) { try? fileManager.removeItem(at:item.url) }
    }

    func releaseRemovedPublished(_ previous:[WCommunityPhotoAttachment],keeping current:[WCommunityPhotoAttachment]) {
        let kept=Set(current.map(\.id))
        for item in previous where !kept.contains(item.id) && isPublished(item.url) { try? fileManager.removeItem(at:item.url) }
    }

    func deletePublished(_ attachments:[WCommunityPhotoAttachment]) {
        for item in attachments where isPublished(item.url) { try? fileManager.removeItem(at:item.url) }
    }

    func isDraft(_ url:URL)->Bool { url.standardizedFileURL.path.hasPrefix(draftURL.standardizedFileURL.path+"/") && isOwned(url) }
    func isPublished(_ url:URL)->Bool { url.standardizedFileURL.path.hasPrefix(publishedURL.standardizedFileURL.path+"/") && isOwned(url) }
    func contains(_ url:URL)->Bool { isOwned(url) && fileManager.fileExists(atPath:url.path) }
    func cleanup(){try? fileManager.removeItem(at:rootURL)}

    func makeReviewFixtures(count:Int=2)throws->[WCommunityPhotoAttachment] {
        try (0..<count).map { index in
            let format=UIGraphicsImageRendererFormat.default();format.scale=1;format.opaque=true
            let image=UIGraphicsImageRenderer(size:CGSize(width:320,height:240),format:format).image { context in
                let color=index==0 ? UIColor(red:0.2,green:0.65,blue:0.4,alpha:1):UIColor(red:0.15,green:0.45,blue:0.85,alpha:1)
                context.cgContext.setFillColor(color.cgColor);context.cgContext.fill(CGRect(x:0,y:0,width:320,height:240))
                context.cgContext.setFillColor(UIColor.white.cgColor);context.cgContext.fillEllipse(in:CGRect(x:48+index*60,y:56,width:100,height:100))
            }
            guard let jpeg=image.jpegData(compressionQuality:0.85) else{throw WCommunityPhotoError.unsupportedImage}
            return try saveDraft(jpeg,id:"review-photo-\(index)")
        }
    }

    private func isOwned(_ url:URL)->Bool { url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path+"/") }
    private static func safeComponent(_ value:String)->String {
        let safe=value.filter{$0.isASCII && ($0.isLetter || $0.isNumber || $0=="-" || $0=="_")}
        return safe.isEmpty ? UUID().uuidString:safe
    }
    private static func fileExtension(for data:Data)->String { data.starts(with:[0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A]) ? "png":"jpg" }
}

struct WImportedCommunityPhoto:Transferable {
    let convertedData:Data
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.image) { received in
            let attributes=try received.file.resourceValues(forKeys:[.fileSizeKey])
            guard let fileSize=attributes.fileSize,fileSize>0,fileSize<=WCommunityPhotoPolicy.maximumOriginalBytes else{throw WCommunityPhotoError.inputTooLarge}
            let original=try Data(contentsOf:received.file,options:.mappedIfSafe)
            return WImportedCommunityPhoto(convertedData:try WCommunityPhotoPolicy.convertedBytes(from:original))
        }
    }
}

@MainActor struct WCommunityPhotoPickerControl:View {
    @Binding var attachments:[WCommunityPhotoAttachment]
    @Binding var error:String
    var store:WCommunityAttachmentStore
    @State private var selection:[PhotosPickerItem]=[]

    var body:some View {
        PhotosPicker(selection:$selection,maxSelectionCount:max(1,WCommunityPhotoPolicy.maximumAttachments-attachments.count),matching:.images){
            Label("사진 추가",systemImage:"photo").font(W.font(13,.medium)).padding(.horizontal,14).frame(height:42).background(W.soft,in:RoundedRectangle(cornerRadius:10))
        }
        .disabled(attachments.count>=WCommunityPhotoPolicy.maximumAttachments)
        .accessibilityIdentifier("communityComposeAddPhotos")
        .task(id:selection){await importSelection(selection)}
    }

    private func importSelection(_ items:[PhotosPickerItem])async {
        guard !items.isEmpty else{return}
        let initialBytes=attachments.reduce(0){$0+$1.byteCount}
        guard WCommunityPhotoPolicy.canAppend(currentCount:attachments.count,currentBytes:initialBytes,addingCount:items.count,addingBytes:1) else {
            error="사진은 최대 10장까지 첨부할 수 있어요."
            selection=[]
            return
        }
        error=""
        for item in items {
            do {
                guard let imported=try await item.loadTransferable(type:WImportedCommunityPhoto.self) else{throw WCommunityPhotoError.unsupportedImage}
                guard !Task.isCancelled else{return}
                let currentBytes=attachments.reduce(0){$0+$1.byteCount}
                guard WCommunityPhotoPolicy.canAppend(currentCount:attachments.count,currentBytes:currentBytes,addingCount:1,addingBytes:imported.convertedData.count) else{throw WCommunityPhotoError.outputTooLarge}
                attachments.append(try store.saveDraft(imported.convertedData))
            } catch {if !Task.isCancelled{self.error=error.localizedDescription}}
        }
        if selection==items{selection=[]}
    }
}
