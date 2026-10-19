import Foundation
import XCTest
@testable import MovNetworking

final class CommunityMediaClientTests: XCTestCase {
    private let postID="42"
    private let assetID="B74F045C-0EC2-4EB0-9C68-621C9F4D4E51"
    private let jpeg=Data([0xFF,0xD8,0xFF,0x00,0x01])

    func testCreatesPostReplacesAttachmentAndReadsBackBytes() async throws {
        let api=RecordingCommunityAPI(steps:[
            .init(path:"community/boards/free/posts",method:"POST",response:.init(statusCode:201,data:post(board:"free",version:0,attachments:[]))),
            .init(path:"community/posts/42/attachments",method:"PUT",response:.init(statusCode:200,data:attachmentSet(version:1))),
            .init(path:"community/posts/42/attachments/\(assetID.lowercased())",method:"GET",response:.init(statusCode:200,data:jpeg))
        ])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())

        let post=try await client.createPost(board:.free,title:"Morning run",content:"A short update",idempotencyKey:"operation-42")
        let updated=try await client.replaceAttachments(postID:post.postID,expectedVersion:post.attachmentVersion,assetIDs:[assetID.lowercased()])
        let read=try await client.readAttachment(postID:post.postID,attachment:try XCTUnwrap(updated.attachments.first))

        XCTAssertEqual(post.postID,"42")
        XCTAssertEqual(updated.attachmentVersion,1)
        XCTAssertEqual(read,jpeg)
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.map(\.path),[
            "community/boards/free/posts","community/posts/42/attachments",
            "community/posts/42/attachments/\(assetID.lowercased())"
        ])
        XCTAssertTrue(requests.allSatisfy{$0.headers["Authorization"]=="Bearer fake-token"})
        XCTAssertEqual(requests[0].headers["Idempotency-Key"],"operation-42")
        let createBody=try XCTUnwrap(requests[0].body)
        let createObject=try XCTUnwrap(JSONSerialization.jsonObject(with:createBody) as? [String:String])
        XCTAssertEqual(createObject,["title":"Morning run","content":"A short update"])
        let replacementBody=try XCTUnwrap(requests[1].body)
        let replacementObject=try XCTUnwrap(JSONSerialization.jsonObject(with:replacementBody) as? [String:Any])
        XCTAssertEqual(replacementObject["attachmentVersion"] as? Int,0)
        XCTAssertEqual(replacementObject["assetIds"] as? [String],[assetID.lowercased()])
        XCTAssertEqual(requests[2].headers["Accept"],"image/jpeg")
        XCTAssertEqual(requests[2].headers["Cache-Control"],"no-store")
    }

    func testCreatePostTransportFailureIsUnknownAndMustNotBeBlindlyRetried() async {
        let api=RecordingCommunityAPI(steps:[.init(path:"community/boards/free/posts",method:"POST",response:nil,transportFailure:true)])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())
        do {
            _=try await client.createPost(board:.free,title:"Morning run",content:"A short update",idempotencyKey:"operation-42")
            XCTFail("a lost POST response must be treated as unknown")
        } catch let failure as CommunityMediaFailure {
            XCTAssertEqual(failure,.postCreationResultUnknown)
            XCTAssertFalse(failure.canManuallyRetry)
        } catch { XCTFail("unexpected error: \(error)") }
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.count,1)
    }

    func testCreatePostAnyFiveHundredResponseIsUnknownAndNonRetryable() async {
        for statusCode in [500, 503, 599] {
            let api=RecordingCommunityAPI(steps:[
                .init(path:"community/boards/free/posts",method:"POST",response:.init(statusCode:statusCode,data:Data()))
            ])
            let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())
            do {
                _=try await client.createPost(board:.free,title:"Morning run",content:"A short update",idempotencyKey:"operation-42")
                XCTFail("HTTP \(statusCode) after keyed create is an ambiguous outcome")
            } catch let failure as CommunityMediaFailure {
                XCTAssertEqual(failure,.postCreationResultUnknown)
                XCTAssertFalse(failure.canManuallyRetry)
            } catch { XCTFail("unexpected error: \(error)") }
            let requests=await api.recordedRequests()
            XCTAssertEqual(requests.count,1)
        }
    }

    func testCreatePostAcceptsIdempotentReplay200() async throws {
        let api=RecordingCommunityAPI(steps:[
            .init(path:"community/boards/free/posts",method:"POST",response:.init(statusCode:200,data:post(board:"free",version:0,attachments:[])))
        ])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())

        let post=try await client.createPost(board:.free,title:"Morning run",content:"A short update",idempotencyKey:"operation-42")

        XCTAssertEqual(post.postID,postID)
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.first?.headers["Idempotency-Key"],"operation-42")
    }

    func testCreatePostMapsPayloadConflictAndDeletedReceipt() async {
        for (status,code,expected) in [
            (409,"COMMUNITY_POST_REQUEST_CONFLICT",CommunityMediaFailure.postCreationRequestConflict),
            (410,"COMMUNITY_POST_RESULT_UNAVAILABLE",CommunityMediaFailure.postCreationReceiptUnavailable)
        ] {
            let body=try! JSONSerialization.data(withJSONObject:["code":code])
            let api=RecordingCommunityAPI(steps:[
                .init(path:"community/boards/free/posts",method:"POST",response:.init(statusCode:status,data:body))
            ])
            let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())
            do {
                _=try await client.createPost(board:.free,title:"Morning run",content:"A short update",idempotencyKey:"operation-42")
                XCTFail("expected keyed create failure")
            } catch let failure as CommunityMediaFailure {
                XCTAssertEqual(failure,expected)
            } catch { XCTFail("unexpected error: \(error)") }
        }
    }

    func testPostCreationResultUsesNoStoreAndMaps404410And409() async throws {
        let conflict=try JSONSerialization.data(withJSONObject:["code":"COMMUNITY_POST_REQUEST_CONFLICT"])
        let gone=try JSONSerialization.data(withJSONObject:["code":"COMMUNITY_POST_RESULT_UNAVAILABLE"])
        let api=RecordingCommunityAPI(steps:[
            .init(path:"community/me/post-creation-result",method:"GET",response:.init(statusCode:404,data:Data())),
            .init(path:"community/me/post-creation-result",method:"GET",response:.init(statusCode:409,data:conflict)),
            .init(path:"community/me/post-creation-result",method:"GET",response:.init(statusCode:410,data:gone)),
            .init(path:"community/me/post-creation-result",method:"GET",response:.init(statusCode:200,data:post(board:"free",version:0,attachments:[])))
        ])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())

        do { _=try await client.fetchPostCreationResult(idempotencyKey:"operation-42"); XCTFail("expected missing receipt") }
        catch let failure as CommunityMediaFailure { XCTAssertEqual(failure,.postCreationResultMissing) }
        do { _=try await client.fetchPostCreationResult(idempotencyKey:"operation-42"); XCTFail("expected key conflict") }
        catch let failure as CommunityMediaFailure { XCTAssertEqual(failure,.postCreationRequestConflict) }
        do { _=try await client.fetchPostCreationResult(idempotencyKey:"operation-42"); XCTFail("expected deleted receipt") }
        catch let failure as CommunityMediaFailure { XCTAssertEqual(failure,.postCreationReceiptUnavailable) }
        let result=try await client.fetchPostCreationResult(idempotencyKey:"operation-42")

        XCTAssertEqual(result.postID,postID)
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.count,4)
        XCTAssertTrue(requests.allSatisfy{$0.headers["Idempotency-Key"]=="operation-42" && $0.headers["Cache-Control"]=="no-store"})
    }

    func testAttachmentVersionConflictReadsCurrentStateBeforeRetry() async throws {
        let conflict=try JSONSerialization.data(withJSONObject:["code":"VERSION_CONFLICT"])
        let api=RecordingCommunityAPI(steps:[
            .init(path:"community/posts/42/attachments",method:"PUT",response:.init(statusCode:409,data:conflict)),
            .init(path:"community/posts/42",method:"GET",response:.init(statusCode:200,data:post(board:"free",version:2,attachments:[]))),
            .init(path:"community/posts/42/attachments",method:"PUT",response:.init(statusCode:200,data:attachmentSet(version:3)))
        ])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())

        let result=try await client.replaceAttachments(postID:postID,expectedVersion:1,assetIDs:[assetID.lowercased()])

        XCTAssertEqual(result.attachmentVersion,3)
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.map(\.method),["PUT","GET","PUT"])
        let retryBody=try XCTUnwrap(requests[2].body)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:retryBody) as? [String:Any])
        XCTAssertEqual(object["attachmentVersion"] as? Int,2)
    }

    func testLostAttachmentResponseReconcilesWithoutRepeatingAppliedPut() async throws {
        let api=RecordingCommunityAPI(steps:[
            .init(path:"community/posts/42/attachments",method:"PUT",response:nil,transportFailure:true),
            .init(path:"community/posts/42",method:"GET",response:.init(statusCode:200,data:post(board:"free",version:1,attachments:[attachmentRow()])))
        ])
        let client=CommunityMediaClient(apiClient:api,tokenProvider:CommunityTestTokenProvider())

        let result=try await client.replaceAttachments(postID:postID,expectedVersion:0,assetIDs:[assetID.lowercased()])

        XCTAssertEqual(result.attachmentVersion,1)
        XCTAssertEqual(result.assetIDs,[assetID.lowercased()])
        let requests=await api.recordedRequests()
        XCTAssertEqual(requests.map(\.method),["PUT","GET"])
    }

    private func post(board:String,version:Int,attachments:[[String:Any]])->Data {
        try! JSONSerialization.data(withJSONObject:[
            "postId":postID,"boardKey":board,"title":"Morning run","content":"A short update",
            "attachmentVersion":version,"attachments":attachments
        ])
    }

    private func attachmentSet(version:Int)->Data {
        try! JSONSerialization.data(withJSONObject:["attachmentVersion":version,"items":[attachmentRow()]])
    }

    private func attachmentRow()->[String:Any] {
        ["assetId":assetID,"kind":"PHOTO","contentType":"image/jpeg","bytes":jpeg.count,
         "widthPixels":1,"heightPixels":1,"position":0]
    }
}

private struct CommunityTestTokenProvider:AccessTokenProviding {
    func accessToken() async throws->String? {"fake-token"}
}

private actor RecordingCommunityAPI:APIResponseSending {
    struct Step:Sendable {
        let path:String
        let method:String
        let response:APIClientResponse?
        var transportFailure=false
        init(path:String,method:String,response:APIClientResponse?,transportFailure:Bool=false){
            self.path=path;self.method=method;self.response=response;self.transportFailure=transportFailure
        }
    }
    struct Request:Sendable {
        let path:String
        let method:String
        let body:Data?
        let headers:[String:String]
    }
    private var steps:[Step]
    private var requests:[Request]=[]
    init(steps:[Step]){self.steps=steps}

    func sendResponse(path:String,method:String,body:Data?,headers:[String:String],queryItems:[URLQueryItem]) async throws->APIClientResponse {
        requests.append(Request(path:path,method:method,body:body,headers:headers))
        guard !steps.isEmpty else{throw APIClientError.unexpectedResponse}
        let step=steps.removeFirst()
        guard step.path==path,step.method==method,queryItems.isEmpty else{throw APIClientError.unexpectedResponse}
        if step.transportFailure{throw APIClientError.transport(.timedOut)}
        guard let response=step.response else{throw APIClientError.unexpectedResponse}
        return response
    }

    func recordedRequests()->[Request]{requests}
}
