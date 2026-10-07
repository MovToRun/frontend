import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import Observation

enum ShareCanvasFormat: String, CaseIterable, Identifiable {
    case feed, story
    var id: String { rawValue }
    var title: String { self == .feed ? "피드 4:5" : "스토리 9:16" }
    var aspect: CGFloat { self == .feed ? 4.0/5.0 : 9.0/16.0 }
}
enum ShareOverlay: String, CaseIterable, Identifiable { case route, metrics
    var id:String{rawValue};var title:String{self == .route ? "코스" : "기록 정보"}
}
struct ShareDraft: Equatable {
    var format:ShareCanvasFormat = .feed
    var overlay:ShareOverlay = .metrics
    var routeColor=0xB9FF35
    var description=""
    var imageData:Data?
    var videoURL:URL?
    var routeOffset=CGSize.zero
    var metricsOffset=CGSize.zero
    var routeScale:CGFloat=1
    var metricsScale:CGFloat=1
}
struct ShareImageOutput:Identifiable,Equatable {
    var id=UUID();var recordID:UUID;var data:Data;var createdAt=Date()
}

@MainActor @Observable final class ShareWorkspace {
    private(set) var drafts:[UUID:ShareDraft]=[:]
    private(set) var outputs:[UUID:[ShareImageOutput]]=[:]
    var errorMessage:String?
    var selectedOutputID:UUID?
    func draft(for record:UUID)->ShareDraft { drafts[record] ?? ShareDraft() }
    func update(_ record:UUID,_ change:(inout ShareDraft)->Void){let previous=drafts[record]?.videoURL;var draft=draft(for:record);change(&draft);drafts[record]=draft;if let previous,previous != draft.videoURL{try? FileManager.default.removeItem(at:previous)}}
    func restoreDraft(_ draft:ShareDraft,for record:UUID){if let previous=drafts[record]?.videoURL,previous != draft.videoURL{try? FileManager.default.removeItem(at:previous)};drafts[record]=draft}
    func insertPNG(_ data:Data,for record:UUID)->ShareImageOutput? {
        guard data.count<=2*1024*1024 else{errorMessage="PNG가 2MB를 넘어요. 캔버스를 줄이거나 사진을 바꿔 주세요.";return nil}
        if let existing=outputs[record]?.first(where:{$0.data==data}){return existing}
        let used=(outputs[record] ?? []).reduce(0){$0+$1.data.count}
        guard used+data.count<=64*1024*1024 else{errorMessage="이 기록의 임시 공유 이미지가 64MB에 도달했어요. 기존 이미지를 지운 뒤 다시 저장해 주세요.";return nil}
        let output=ShareImageOutput(recordID:record,data:data);outputs[record,default:[]].insert(output,at:0);errorMessage=nil;return output
    }
    func delete(_ output:UUID,for record:UUID){outputs[record,default:[]].removeAll{$0.id==output}}
    func output(_ id:UUID?,for record:UUID)->ShareImageOutput? {
        guard let values=outputs[record] else{return nil}
        return id.flatMap{id in values.first{$0.id==id}} ?? values.first
    }
    func clear(){for url in drafts.values.compactMap(\.videoURL){try? FileManager.default.removeItem(at:url)};drafts=[:];outputs=[:];selectedOutputID=nil;errorMessage=nil}
}

enum ShareMediaError:LocalizedError {
    case tooLarge,invalidImage,tooManyPixels,invalidVideo,duration,resolution
    var errorDescription:String?{switch self{case .tooLarge:"지원되는 이미지(20MB 이하) 또는 동영상(50MB 이하)을 선택해 주세요.";case .invalidImage:"열 수 있는 이미지가 아니에요. 다른 파일을 선택해 주세요.";case .tooManyPixels:"이미지는 25MP 이하만 사용할 수 있어요.";case .invalidVideo:"재생할 수 있는 동영상 파일이 아니에요.";case .duration:"동영상은 15초 이하만 사용할 수 있어요.";case .resolution:"동영상은 4K 이하만 사용할 수 있어요."}}
}
enum ShareMediaValidation {
    static func image(_ data:Data)throws->UIImage {
        guard data.count<=20*1024*1024 else{throw ShareMediaError.tooLarge}
        guard let image=UIImage(data:data),let cg=image.cgImage else{throw ShareMediaError.invalidImage}
        guard Int64(cg.width)*Int64(cg.height)<=25_000_000 else{throw ShareMediaError.tooManyPixels}
        return image
    }
    static func video(_ url:URL)async throws {
        let values=try? url.resourceValues(forKeys:[.fileSizeKey])
        guard let size=values?.fileSize,size<=50*1024*1024 else{throw ShareMediaError.tooLarge}
        let asset=AVURLAsset(url:url)
        guard let duration=try? await asset.load(.duration),duration.seconds.isFinite,duration.seconds>0 else{throw ShareMediaError.invalidVideo}
        guard duration.seconds<=15 else{throw ShareMediaError.duration}
        guard let tracks=try? await asset.loadTracks(withMediaType:.video),let track=tracks.first else{throw ShareMediaError.invalidVideo}
        let dimensions=try? await track.load(.naturalSize),transform=try? await track.load(.preferredTransform)
        guard let dimensions,let transform else{throw ShareMediaError.invalidVideo}
        let box=CGRect(origin:.zero,size:dimensions).applying(transform).standardized
        guard box.width<=3840,box.height<=3840 else{throw ShareMediaError.resolution}
    }
}
enum ShareElapsed {
    static func string(_ seconds:Double)->String {
        let total=max(0,Int(seconds.rounded(.down))),h=total/3600,m=(total%3600)/60,s=total%60
        if h>0{return "\(h)h\(m)m\(s)s"};return "\(m)m\(s)s"
    }
}
enum ShareGestureBounds {
    static func offset(_ offset:CGSize,canvas:CGSize)->CGSize {CGSize(width:min(canvas.width*0.36,max(-canvas.width*0.36,offset.width)),height:min(canvas.height*0.32,max(-canvas.height*0.32,offset.height)))}
    static func scale(_ value:CGFloat,minimum:CGFloat=0.6,maximum:CGFloat=1.8)->CGFloat{min(maximum,max(minimum,value))}
}

private struct ImportedShareMovie:Transferable {
    var url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.movie){received in
            let destination=FileManager.default.temporaryDirectory.appendingPathComponent("mov-share-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at:received.file,to:destination)
            return ImportedShareMovie(url:destination)
        }
    }
}
struct SharePNGDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.png]}
    var data:Data
    init(data:Data){self.data=data}
    init(configuration:ReadConfiguration)throws{data=configuration.file.regularFileContents ?? Data()}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:data)}
}

struct ShareImageCanvas:View {
    var record:RunRecord;var draft:ShareDraft;var previewImage:UIImage?
    var body:some View {
        GeometryReader{geometry in let size=geometry.size
            ZStack {
                Color(red:0.09,green:0.12,blue:0.10)
                if let previewImage {Image(uiImage:previewImage).resizable().scaledToFill().frame(width:size.width,height:size.height).clipped()}
                else {Image("MapRoute").resizable().scaledToFill().frame(width:size.width,height:size.height).clipped().opacity(0.42)}
                LinearGradient(colors:[.black.opacity(0.04),.black.opacity(0.18),.black.opacity(0.78)],startPoint:.top,endPoint:.bottom)
                VStack(alignment:.leading,spacing:0){
                    HStack(spacing:7){Image("BrandMark").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24);Text("mov").font(.system(size:19,weight:.bold,design:.rounded)).accessibilityIdentifier("shareMovLogo")}.foregroundStyle(.white)
                    Spacer(minLength:10)
                    if !draft.description.isEmpty{Text(draft.description).font(.system(size:14,weight:.medium)).foregroundStyle(.white).lineLimit(3).padding(.bottom,10)}
                    HStack(spacing:18){Text(record.date.formatted(.dateTime.year().month().day()));Text(ShareElapsed.string(record.seconds))}.font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(.white.opacity(0.88))
                }.padding(size.width*0.07)
                ShareRouteShape().stroke(Color(hex:draft.routeColor),style:StrokeStyle(lineWidth:max(3,size.width*0.014),lineCap:.round,lineJoin:.round)).frame(width:size.width*0.62,height:size.height*0.34).scaleEffect(draft.routeScale).offset(draft.routeOffset).accessibilityIdentifier("shareRouteOverlay")
                VStack(alignment:.leading,spacing:size.width*0.018){Text("\(MovNumber.display(record.kilometers))").font(.system(size:size.width*0.115,weight:.bold,design:.rounded)).monospacedDigit()+Text(" km").font(.system(size:size.width*0.045,weight:.semibold,design:.rounded));HStack(spacing:14){Label(ShareElapsed.string(record.seconds),systemImage:"clock");Label(record.pace+" /km",systemImage:"figure.run")}.font(.system(size:size.width*0.038,weight:.semibold,design:.rounded))}.foregroundStyle(.white).padding(size.width*0.045).background(.black.opacity(0.35),in:RoundedRectangle(cornerRadius:16)).scaleEffect(draft.metricsScale).offset(draft.metricsOffset).position(x:size.width*0.50+draft.metricsOffset.width,y:size.height*0.67+draft.metricsOffset.height).accessibilityIdentifier("shareMetricsOverlay")
                if !draft.description.isEmpty{Text(" ").hidden().accessibilityHidden(true)}
            }.frame(width:size.width,height:size.height).clipped()
        }.aspectRatio(draft.format.aspect,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityElement(children:.contain).accessibilityIdentifier("shareCanvas")
    }
}
private struct ShareRouteShape:Shape {
    func path(in rect:CGRect)->Path {var p=Path();p.move(to:CGPoint(x:rect.width*0.08,y:rect.height*0.72));p.addCurve(to:CGPoint(x:rect.width*0.42,y:rect.height*0.54),control1:CGPoint(x:rect.width*0.23,y:rect.height*0.68),control2:CGPoint(x:rect.width*0.30,y:rect.height*0.28));p.addCurve(to:CGPoint(x:rect.width*0.70,y:rect.height*0.43),control1:CGPoint(x:rect.width*0.56,y:rect.height*0.80),control2:CGPoint(x:rect.width*0.57,y:rect.height*0.30));p.addCurve(to:CGPoint(x:rect.width*0.92,y:rect.height*0.16),control1:CGPoint(x:rect.width*0.82,y:rect.height*0.56),control2:CGPoint(x:rect.width*0.78,y:rect.height*0.20));return p}
}
private extension Color {init(hex:Int){self.init(.sRGB,red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,opacity:1)}}

struct ShareImageEditor:View {
    var record:RunRecord;@Bindable var workspace:ShareWorkspace;var back:()->Void;var openOutput:()->Void
    @State private var item:PhotosPickerItem?;@State private var message="";@State private var showDescription=false;@State private var descriptionDraft="";@State private var baseline=ShareDraft();@State private var routeStart=CGSize.zero;@State private var metricsStart=CGSize.zero;@State private var scaleStart:CGFloat=1
    private var draft:ShareDraft{workspace.draft(for:record.id)}
    private var previewImage:UIImage?{draft.imageData.flatMap(UIImage.init(data:))}
    var body:some View {
        VStack(spacing:0) {
            WHeader(title:"러닝 공유 만들기",back:{cancelAndBack()})
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack {
                        Button("피드 4:5"){workspace.update(record.id){$0.format = .feed}}.buttonStyle(WButtonStyle(kind:draft.format == .feed ? 0:1)).accessibilityIdentifier("shareFormatFeed")
                        Button("스토리 9:16"){workspace.update(record.id){$0.format = .story}}.buttonStyle(WButtonStyle(kind:draft.format == .story ? 0:1)).accessibilityIdentifier("shareFormatStory")
                    }
                    canvas
                    Text("편집할 요소").font(W.font(13,.medium))
                    HStack {
                        ForEach(ShareOverlay.allCases) { overlay in
                            Button(overlay.title){workspace.update(record.id){$0.overlay=overlay}}
                                .buttonStyle(WButtonStyle(kind:draft.overlay == overlay ? 0:1))
                                .accessibilityIdentifier("shareSelect-\(overlay.rawValue)")
                        }
                    }
                        Button("요소 위치·크기 초기화") { workspace.update(record.id){$0.routeOffset = .zero;$0.metricsOffset = .zero;$0.routeScale = 1;$0.metricsScale = 1};routeStart = .zero;metricsStart = .zero;scaleStart=1 }
                        .buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("shareResetOverlay")
                    if draft.overlay == .route {
                        HStack {
                            Text("코스 색").font(W.font(12))
                            ForEach([0xB9FF35,0x34D399,0x60A5FA,0xF472B6],id:\.self) { color in
                                Button { workspace.update(record.id){$0.routeColor=color} } label: {
                                    Circle().fill(Color(hex:color)).frame(width:30,height:30)
                                        .overlay(Circle().stroke(draft.routeColor == color ? W.ink:.clear,lineWidth:2))
                                }.accessibilityLabel("코스 색 \(color)")
                            }
                        }
                    }
                    HStack {
                        PhotosPicker(selection:$item,matching:.any(of:[.images,.videos])) {
                            Label("사진·영상 선택",systemImage:"photo").font(W.font(13,.medium)).frame(maxWidth:.infinity,minHeight:48)
                                .background(W.paper,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line))
                        }.accessibilityIdentifier("sharePickMedia")
                        Button { descriptionDraft=draft.description;showDescription=true } label: {
                            Label("설명",systemImage:"text.alignleft").font(W.font(13,.medium)).frame(maxWidth:.infinity,minHeight:48)
                                .background(W.paper,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(W.line))
                        }.accessibilityIdentifier("shareDescription")
                    }
                    if draft.videoURL != nil { WNotice(text:"동영상은 확인된 첫 화면으로 PNG에 반영돼요. 무음 MP4 내보내기는 이 빌드에서 제공하지 않습니다.") }
                    if !message.isEmpty { WNotice(text:message,danger:true).accessibilityIdentifier("shareMediaError") }
                    if let workspaceError=workspace.errorMessage { WNotice(text:workspaceError,danger:true) }
                    WText(text:"이미지·코스·기록은 이 기기에서만 처리해요. 공유 서비스로 전송하지 않습니다.",small:true)
                }.padding(20)
            }
            HStack {
                Button("취소"){cancelAndBack()}.buttonStyle(WButtonStyle(kind:1))
                Button("이미지 만들기"){makeImage()}.buttonStyle(WButtonStyle()).accessibilityIdentifier("shareCreateImage")
            }.padding(16).background(W.paper)
        }
        .onAppear{baseline=draft}
        .onChange(of:draft.overlay){_,overlay in scaleStart=overlay == .route ? draft.routeScale:draft.metricsScale}
        .task(id:item){await load(item)}
        .sheet(isPresented:$showDescription) {
            NavigationStack {
                VStack {
                    TextEditor(text:$descriptionDraft).padding(12).accessibilityIdentifier("shareDescriptionInput")
                    Text("설명은 이미지 안쪽에 표시됩니다.").font(W.font(11)).foregroundStyle(W.muted)
                }.navigationTitle("설명").toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("취소"){showDescription=false}}
                    ToolbarItem(placement:.confirmationAction){Button("완료"){workspace.update(record.id){$0.description=String(descriptionDraft.prefix(180))};showDescription=false}}
                }
            }.presentationDetents([.medium,.large])
        }
    }
    private var canvas:some View {
        GeometryReader{geo in let w=geo.size.width,h=geo.size.height
            ZStack{ShareImageCanvas(record:record,draft:draft,previewImage:previewImage)
                if draft.overlay == .route {Rectangle().fill(.clear).contentShape(Rectangle()).frame(width:w*0.65,height:h*0.36).position(x:w*0.5+draft.routeOffset.width,y:h*0.45+draft.routeOffset.height).gesture(DragGesture().onChanged{v in workspace.update(record.id){$0.routeOffset=ShareGestureBounds.offset(CGSize(width:routeStart.width+v.translation.width,height:routeStart.height+v.translation.height),canvas:geo.size)}}.onEnded{_ in routeStart=draft.routeOffset}).simultaneousGesture(MagnificationGesture().onChanged{factor in workspace.update(record.id){$0.routeScale=ShareGestureBounds.scale(scaleStart*factor)}}.onEnded{_ in scaleStart=draft.routeScale}).accessibilityIdentifier("shareDrag-route").accessibilityValue("\(Int(draft.routeOffset.width)),\(Int(draft.routeOffset.height)),\(draft.routeScale)")}
                else {Rectangle().fill(.clear).contentShape(Rectangle()).frame(width:w*0.84,height:h*0.24).position(x:w*0.5+draft.metricsOffset.width,y:h*0.67+draft.metricsOffset.height).gesture(DragGesture().onChanged{v in workspace.update(record.id){$0.metricsOffset=ShareGestureBounds.offset(CGSize(width:metricsStart.width+v.translation.width,height:metricsStart.height+v.translation.height),canvas:geo.size)}}.onEnded{_ in metricsStart=draft.metricsOffset}).simultaneousGesture(MagnificationGesture().onChanged{factor in workspace.update(record.id){$0.metricsScale=ShareGestureBounds.scale(scaleStart*factor,minimum:0.65,maximum:1.7)}}.onEnded{_ in scaleStart=draft.metricsScale}).accessibilityIdentifier("shareDrag-metrics").accessibilityValue("\(Int(draft.metricsOffset.width)),\(Int(draft.metricsOffset.height)),\(draft.metricsScale)")}
            }
        }.aspectRatio(draft.format.aspect,contentMode:.fit).frame(maxWidth:.infinity).accessibilityIdentifier("shareCanvasGestures")
    }
    private func cancelAndBack(){workspace.restoreDraft(baseline,for:record.id);back()}
    private func load(_ selected:PhotosPickerItem?)async {
        guard let selected else{return};message=""
        var temporaryMovie:URL?
        do {
            if selected.supportedContentTypes.contains(where:{$0.conforms(to:.image)}) {
                guard let data=try await selected.loadTransferable(type:Data.self)else{throw ShareMediaError.invalidImage}
                let image=try ShareMediaValidation.image(data)
                workspace.update(record.id){$0.imageData=image.jpegData(compressionQuality:0.92) ?? data;$0.videoURL=nil};return
            }
            guard selected.supportedContentTypes.contains(where:{$0.conforms(to:.movie)}),let movie=try await selected.loadTransferable(type:ImportedShareMovie.self)else{throw ShareMediaError.invalidVideo}
            temporaryMovie=movie.url
            try await ShareMediaValidation.video(movie.url)
            let asset=AVURLAsset(url:movie.url),generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
            let frame=try await generator.image(at:.zero).image,bitmap=UIImage(cgImage:frame)
            let bytes=bitmap.jpegData(compressionQuality:0.88) ?? Data()
            guard !bytes.isEmpty else{throw ShareMediaError.invalidImage}
            workspace.update(record.id){$0.imageData=bytes;$0.videoURL=movie.url};temporaryMovie=nil;return
        } catch {if let temporaryMovie{try? FileManager.default.removeItem(at:temporaryMovie)};message=(error as? LocalizedError)?.errorDescription ?? "선택한 미디어를 열 수 없어요. 지원되는 파일을 다시 선택해 주세요."}
    }
    @MainActor private func makeImage(){
        let width:CGFloat=360,height=width/draft.format.aspect
        var png:Data?
        for scale:CGFloat in [3,2.5,2,1.5,1] {
            let renderer=ImageRenderer(content:ShareImageCanvas(record:record,draft:draft,previewImage:previewImage).frame(width:width,height:height))
            renderer.scale=scale
            if let candidate=renderer.uiImage?.pngData(),candidate.count<=2*1024*1024 {png=candidate;break}
        }
        guard let png,let output=workspace.insertPNG(png,for:record.id)else{message=workspace.errorMessage ?? "이미지를 2MB 이하로 줄이지 못했어요. 더 작은 사진을 선택해 주세요.";return}
        workspace.errorMessage=nil;workspace.selectedOutputID=output.id;openOutput()
    }
}

struct ShareGallery:View {
    var record:RunRecord;@Bindable var workspace:ShareWorkspace;var back:()->Void;var create:()->Void;var open:(UUID)->Void
    @State private var deleteTarget:ShareImageOutput?
    @State private var showDeleteAlert=false
    var body:some View {
        VStack(spacing:0) {
            WHeader(title:"이 기록의 공유 콘텐츠",back:back)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(record.date.formatted(.dateTime.year().month().day())).font(W.font(14,.medium))
                    let outputs=workspace.outputs[record.id,default:[]]
                    if outputs.isEmpty {
                        VStack(alignment:.leading,spacing:10) {
                            Text("아직 만든 이미지가 없어요").font(W.font(19,.semibold))
                            WText(text:"이 화면에서 만든 공유 이미지는 앱을 종료하면 함께 사라져요.",small:true)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(20)
                            .background(W.soft,in:RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("shareGalleryEmpty")
                    } else {
                        ForEach(outputs) { output in
                            VStack(alignment:.leading,spacing:8) {
                                Button { open(output.id) } label: {
                                    Image(uiImage:UIImage(data:output.data) ?? UIImage()).resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius:12))
                                }.buttonStyle(.plain).accessibilityIdentifier("shareOutput-\(output.id)")
                                HStack {
                                    Text("PNG · \(ByteCountFormatter.string(fromByteCount:Int64(output.data.count),countStyle:.file))").font(W.font(12))
                                    Spacer()
                                    Button("삭제"){deleteTarget=output;showDeleteAlert=true}.foregroundStyle(.red).accessibilityIdentifier("deleteShare-\(output.id)")
                                }
                            }.padding(12).background(W.soft,in:RoundedRectangle(cornerRadius:16))
                        }
                    }
                }.padding(20)
            }
            Button("새 공유 이미지 만들기",action:create).buttonStyle(WButtonStyle()).padding(16).accessibilityIdentifier("shareNewImage")
        }
        .alert("이 이미지를 삭제할까요?",isPresented:$showDeleteAlert,presenting:deleteTarget) { output in
            Button("삭제",role:.destructive) {
                workspace.delete(output.id,for:record.id)
                if workspace.selectedOutputID==output.id {workspace.selectedOutputID=workspace.outputs[record.id]?.first?.id}
            }
            Button("취소",role:.cancel){}
        } message:{_ in Text("삭제한 이미지는 이 기기 임시 갤러리에서 제거돼요.")}
    }
}

struct ShareOutputView:View {
    var record:RunRecord;@Bindable var workspace:ShareWorkspace;var back:()->Void;var gallery:()->Void
    @State private var exporting=false;@State private var saveMessage:String?
    private var output:ShareImageOutput?{workspace.output(workspace.selectedOutputID,for:record.id)}
    var body:some View {VStack(spacing:0){WHeader(title:"러닝 공유 저장",back:back);ScrollView{VStack(alignment:.leading,spacing:16){if let output,let image=UIImage(data:output.data){Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18)).accessibilityIdentifier("shareOutputPreview");Text("PNG · \(output.data.count) bytes · \(image.cgImage?.width ?? Int(image.size.width)) × \(image.cgImage?.height ?? Int(image.size.height)) px").font(W.font(12)).foregroundStyle(W.muted);WText(text:"파일 앱에서 저장 위치를 선택해요. SNS에 게시하거나 서버로 전송하지 않습니다.",small:true)}else{WNotice(text:"이미지를 찾을 수 없어요. 공유 갤러리에서 다시 선택해 주세요.",danger:true)};if let saveMessage{WNotice(text:saveMessage,danger:true).accessibilityIdentifier("shareSaveFailure")};if let error=workspace.errorMessage{WNotice(text:error,danger:true)};Button("이 기록의 이미지 목록",action:gallery).buttonStyle(WButtonStyle(kind:1)).accessibilityIdentifier("shareOpenGallery")}.padding(20)};Button("파일 앱에 PNG 저장"){exporting=true}.buttonStyle(WButtonStyle()).disabled(output==nil).accessibilityIdentifier("shareSavePNG")}.fileExporter(isPresented:$exporting,document:SharePNGDocument(data:output?.data ?? Data()),contentType:.png,defaultFilename:"mov-run-share") {result in switch result{case .success:saveMessage="PNG 파일을 저장했어요.";case .failure:saveMessage="저장하지 못했어요. 이미지가 임시 갤러리에 남아 있으니 다시 시도해 주세요."}}}
}
