import Foundation
import XCTest
@testable import MovNetworking

private actor RunRecordsRecordingTransport: APIResponseSending {
    struct Request: Sendable {
        let path: String
        let method: String
        let body: Data?
        let headers: [String: String]
        let queryItems: [URLQueryItem]
    }

    private var responses: [APIClientResponse]
    private var failures: [APIClientError]
    private var requests: [Request] = []

    init(responses: [APIClientResponse], failures: [APIClientError] = []) {
        self.responses = responses
        self.failures = failures
    }

    func sendResponse(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        queryItems: [URLQueryItem]
    ) async throws -> APIClientResponse {
        requests.append(Request(path: path, method: method, body: body, headers: headers, queryItems: queryItems))
        if !failures.isEmpty { throw failures.removeFirst() }
        guard !responses.isEmpty else { throw APIClientError.unexpectedResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [Request] { requests }
}

final class RunRecordsReadTests: XCTestCase {
    private let clientRunID = "0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11"

    private func makeClient(
        _ token: String? = "run-test-token",
        attempts: Int = 1,
        transport: (any APIResponseSending)? = nil
    ) throws -> RunRecordsClient {
        let configuration = try APIClientConfiguration(
            environment: .development,
            baseURLString: "https://api-dev.example.invalid/api/v1/",
            requestTimeout: 4,
            resourceTimeout: 9
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let apiClient: any APIResponseSending = transport ?? APIClient(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
        return RunRecordsClient(
            apiClient: apiClient,
            tokenProvider: RunTokenProvider(value: token),
            retryPolicy: RunRecordsRetryPolicy(maximumAttempts: attempts, delayNanoseconds: 0)
        )
    }

    private func summary(
        id: String = "104",
        version: Int64 = 3,
        pointReward: String = #"{"status":"SETTLED","pointsAwarded":0}"#,
        titleJSON: String = #""밤 러닝""#
    ) -> String {
        #"{"id":"\#(id)","clientRunId":"\#(clientRunID)","version":\#(version),"startedAt":"2026-10-05T23:50:00+09:00","endedAt":"2026-10-06T00:30:00+09:00","runDate":"2026-10-05","elapsedSeconds":2400,"movingSeconds":2280,"distanceMeters":6400,"verdict":"VALID","verdictReason":null,"validDistanceMeters":6100,"validSeconds":2150,"paceSecondsPerKm":352,"title":\#(titleJSON),"memo":null,"pointReward":\#(pointReward),"createdAt":"2026-10-06T00:31:02+09:00","updatedAt":"2026-10-06T00:31:02+09:00"}"#
    }

    func testListUsesItemsWrapperAndPreservesOpaqueCursorAndKSTValues() async throws {
        let body = #"{"items":[\#(summary())],"nextCursor":"opaque_cursor-7"}"#
        MockURLProtocol.respond(statusCode: 200, data: Data(body.utf8))
        let page = try await makeClient().fetchRuns(size: 1)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "opaque_cursor-7")
        XCTAssertEqual(page.items[0].runDate, "2026-10-05")
        XCTAssertEqual(page.items[0].distanceMeters, 6_400)
        XCTAssertEqual(page.items[0].validDistanceMeters, 6_100)
        XCTAssertEqual(page.items[0].movingSeconds, 2_280)
        XCTAssertEqual(page.items[0].validSeconds, 2_150)
        XCTAssertEqual(page.items[0].pointReward, BackendRunPointReward(status: .settled, pointsAwarded: 0))

        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[],"nextCursor":null}"#.utf8))
        _ = try await makeClient().fetchRuns(cursor: page.nextCursor, size: 1)
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/api/v1/runs")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "cursor", value: "opaque_cursor-7"), URLQueryItem(name: "size", value: "1")])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer run-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testDetailDecodesFlattenedSummaryPointPrecisionPauseAndJudgement() async throws {
        let summaryFields=String(summary(id:"a-104").dropFirst().dropLast())
        let body = #"{\#(summaryFields),"points":[{"recordedAt":"2026-10-05T23:55:00.123+09:00","latitude":37.5,"longitude":127.0,"accuracyMeters":4.5,"altitudeMeters":12.25,"speedMetersPerSecond":2.3}],"pauses":[{"startedAt":"2026-10-06T00:00:00+09:00","endedAt":"2026-10-06T00:01:00+09:00"}],"judgement":{"algorithmVersion":"v1","exclusions":[{"reason":"VEHICLE","startedAt":"2026-10-05T23:58:00.125+09:00","endedAt":"2026-10-05T23:59:00.125+09:00","distanceMeters":9876543210,"seconds":60}],"inaccuratePoints":2,"jumpPoints":1}}"#
        MockURLProtocol.respond(statusCode: 200, data: Data(body.utf8))
        let detail = try await makeClient().fetchRun(id: "a-104")

        XCTAssertEqual(detail.summary.id, "a-104")
        XCTAssertEqual(detail.points.count, 1)
        XCTAssertEqual(detail.points[0].latitude, 37.5)
        XCTAssertEqual(detail.points[0].accuracyMeters, 4.5)
        XCTAssertEqual(detail.pauses.count, 1)
        XCTAssertEqual(detail.judgement?.exclusions.first?.distanceMeters, 9_876_543_210)
        XCTAssertEqual(detail.judgement?.algorithmVersion, "v1")
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/api/v1/runs/a-104")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testDetailAcceptsServerClearedNullableTitle() async throws {
        let fields=String(summary(titleJSON:"null").dropFirst().dropLast())
        let body=#"{\#(fields),"points":[],"pauses":[],"judgement":null}"#
        MockURLProtocol.respond(statusCode:200,data:Data(body.utf8))
        let detail=try await makeClient().fetchRun(id:"104")
        XCTAssertNil(detail.summary.title)
    }

    func testRejectsInvalidCursorPageSizeRunIDAndRewardWithoutSendingRequests() async throws {
        MockURLProtocol.reset()
        let client = try makeClient()
        do { _ = try await client.fetchRuns(size: 0); XCTFail("Expected invalid page size") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidPageSize) }
        do { _ = try await client.fetchRun(id: "../other"); XCTFail("Expected invalid run ID") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testUnauthorizedAndMissingTokenStayFailuresRatherThanEmptyPages() async throws {
        MockURLProtocol.respond(statusCode: 401, data: Data(#"{"code":"UNAUTHENTICATED"}"#.utf8))
        do {
            _ = try await makeClient(attempts: 1).fetchRuns()
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .unauthenticated)
        }
        do {
            _ = try await makeClient(nil).fetchRuns()
            XCTFail("Expected missing token failure")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .accessTokenUnavailable)
        }
    }

    func testTitleAndMemoPatchUseOnlyTheSelectedFieldAndDecodeClearedTitle() async throws {
        let transport = RunRecordsRecordingTransport(responses:[APIClientResponse(
            statusCode: 200, data: Data(summary(version: 4, titleJSON: "null").utf8), requestID: nil
        )])
        let updated = try await makeClient(transport:transport).updateRun(
            id: "104", version: 3, patch: BackendRunEditPatch(title: "")
        )
        XCTAssertNil(updated.title)
        XCTAssertEqual(updated.version, 4)

        let requests=await transport.recordedRequests()
        let request=try XCTUnwrap(requests.last)
        XCTAssertEqual(request.path,"runs/104")
        XCTAssertEqual(request.method,"PATCH")
        XCTAssertEqual(request.headers["Authorization"],"Bearer run-test-token")
        XCTAssertEqual(request.headers["Accept"],"application/json")
        XCTAssertEqual(request.headers["Cache-Control"],"no-store")
        XCTAssertEqual(request.headers["Content-Type"],"application/json")
        let requestBody = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 3)
        XCTAssertEqual(object["title"] as? String, "")
        XCTAssertNil(object["memo"], "An omitted field must remain omitted so the server preserves it.")
    }

    func testMemoPatchCanClearWithoutSendingTitle() async throws {
        let transport=RunRecordsRecordingTransport(responses:[APIClientResponse(statusCode:200,data:Data(summary(version:4).utf8),requestID:nil)])
        _ = try await makeClient(transport:transport).updateRun(id: "104", version: 3, patch: BackendRunEditPatch(memo: ""))
        let requests=await transport.recordedRequests()
        let request=try XCTUnwrap(requests.last)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(object["memo"] as? String, "")
        XCTAssertNil(object["title"])
    }

    func testPatchPreservesWhitespaceAndUnicodeWithoutNormalization() async throws {
        let rawTitle="  e\u{301}  "
        let encodedTitle=String(decoding:try JSONEncoder().encode(rawTitle),as:UTF8.self)
        let transport=RunRecordsRecordingTransport(responses:[APIClientResponse(
            statusCode:200,data:Data(summary(version:4,titleJSON:encodedTitle).utf8),requestID:nil
        )])
        let updated=try await makeClient(transport:transport).updateRun(
            id:"104",version:3,patch:BackendRunEditPatch(title:rawTitle)
        )
        XCTAssertEqual(updated.title,rawTitle)
        let requests=await transport.recordedRequests()
        let request=try XCTUnwrap(requests.last)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(request.body)) as? [String:Any])
        XCTAssertEqual(object["title"] as? String,rawTitle)
    }

    func testPatchUsesJavaUTF16LengthLimitsAndNeverAutomaticallyRetries() async throws {
        MockURLProtocol.reset()
        let client = try makeClient(attempts: 2)
        do {
            _ = try await client.updateRun(id: "104", version: 3, patch: BackendRunEditPatch(title: String(repeating: "😀", count: 21)))
            XCTFail("21 supplementary characters exceed Java String.length() limit of 40 UTF-16 units")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .invalidEdit)
        }
        do {
            _ = try await client.updateRun(id: "104", version: 3, patch: BackendRunEditPatch(memo: String(repeating: "😀", count: 151)))
            XCTFail("151 supplementary characters exceed Java String.length() limit of 300 UTF-16 units")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .invalidEdit)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)

        let memoRaw=String(repeating:"😀",count:150)
        let transport=RunRecordsRecordingTransport(responses:[
            APIClientResponse(statusCode:200,data:Data(summary(version:4).utf8),requestID:nil),
            APIClientResponse(statusCode:200,data:Data(summary(version:5).utf8),requestID:nil)
        ])
        let injectableClient=try makeClient(attempts:2,transport:transport)
        _=try await injectableClient.updateRun(id:"104",version:3,patch:BackendRunEditPatch(title:String(repeating:"😀",count:20)))
        _=try await injectableClient.updateRun(id:"104",version:4,patch:BackendRunEditPatch(memo:memoRaw))
        let captured=await transport.recordedRequests()
        let titleBody=try XCTUnwrap(captured.first?.body)
        let titlePayload=try XCTUnwrap(JSONSerialization.jsonObject(with:titleBody) as? [String:Any])
        let acceptedRequest=try XCTUnwrap(captured.last)
        let acceptedBody=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(acceptedRequest.body)) as? [String:Any])
        XCTAssertEqual((titlePayload["title"] as? String)?.utf16.count,40,"The client follows Java String.length(), not Swift grapheme count")
        XCTAssertEqual((acceptedBody["memo"] as? String)?.utf16.count,300,"Memo uses its backend Java String.length() limit")

        MockURLProtocol.respond(statusCode: 503, data: Data(#"{"code":"INTERNAL_ERROR"}"#.utf8))
        do {
            _ = try await client.updateRun(id: "104", version: 3, patch: BackendRunEditPatch(memo: "draft"))
            XCTFail("Expected server failure")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .serverFailure(statusCode: 503, requestID: nil))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1, "PATCH must not be retried automatically because a lost response may follow a committed version increment.")
    }

    func testPatchMapsVersionConflictAndDeletedOrForeignRecordToFailures() async throws {
        MockURLProtocol.respond(statusCode: 409, data: Data(#"{"code":"VERSION_CONFLICT","requestId":"req-conflict"}"#.utf8))
        do {
            _ = try await makeClient(attempts: 2).updateRun(id: "104", version: 2, patch: BackendRunEditPatch(title: "draft"))
            XCTFail("Expected version conflict")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .versionConflict)
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        MockURLProtocol.respond(statusCode: 404, data: Data(#"{"code":"NOT_FOUND"}"#.utf8))
        do {
            _ = try await makeClient().updateRun(id: "104", version: 3, patch: BackendRunEditPatch(title: "draft"))
            XCTFail("Expected missing or inaccessible record")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .recordNotFound)
        }
    }

    func testDeleteUsesVersionQueryAndRequiresExactEmpty204() async throws {
        let transport=RunRecordsRecordingTransport(responses:[APIClientResponse(statusCode:204,data:Data(),requestID:nil)])
        try await makeClient(transport:transport).deleteRun(id:"104",version:7)
        let recorded=await transport.recordedRequests()
        let request=try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.path,"runs/104")
        XCTAssertEqual(request.method,"DELETE")
        XCTAssertEqual(request.queryItems,[URLQueryItem(name:"version",value:"7")])
        XCTAssertNil(request.body)
        XCTAssertEqual(request.headers["Authorization"],"Bearer run-test-token")
        XCTAssertEqual(request.headers["Accept"],"application/json")
        XCTAssertEqual(request.headers["Cache-Control"],"no-store")
        XCTAssertNil(request.headers["Content-Type"])

        for response in [
            APIClientResponse(statusCode:200,data:Data(),requestID:nil),
            APIClientResponse(statusCode:204,data:Data("unexpected".utf8),requestID:nil)
        ] {
            let invalid=RunRecordsRecordingTransport(responses:[response])
            do { try await makeClient(transport:invalid).deleteRun(id:"104",version:7); XCTFail("Only an empty 204 confirms deletion") }
            catch { XCTAssertEqual(error as? RunRecordsFailure,.invalidResponse) }
        }
    }

    func testDeleteTreats404AsAmbiguousAndMapsVersionConflictOnlyByCode() async throws {
        let missing=RunRecordsRecordingTransport(responses:[APIClientResponse(statusCode:404,data:Data(#"{"code":"NOT_FOUND"}"#.utf8),requestID:nil)])
        do { try await makeClient(transport:missing).deleteRun(id:"104",version:3); XCTFail("A hidden-owner 404 must never mean deletion succeeded") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.recordNotFound) }

        let conflict=RunRecordsRecordingTransport(responses:[APIClientResponse(statusCode:409,data:Data(#"{"code":"VERSION_CONFLICT"}"#.utf8),requestID:nil)])
        do { try await makeClient(transport:conflict).deleteRun(id:"104",version:3); XCTFail("Expected a version conflict") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.versionConflict) }

        let otherConflict=RunRecordsRecordingTransport(responses:[APIClientResponse(statusCode:409,data:Data(#"{"code":"CONFLICT"}"#.utf8),requestID:nil)])
        do { try await makeClient(transport:otherConflict).deleteRun(id:"104",version:3); XCTFail("Unknown 409 codes must stay failures") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.serverFailure(statusCode:409,requestID:nil)) }
    }

    func testDeleteDoesNotAutoRetryLostResponseAndManualRetryUsesSameIdAndVersion() async throws {
        let transport=RunRecordsRecordingTransport(
            responses:[APIClientResponse(statusCode:204,data:Data(),requestID:nil)],
            failures:[.transport(.networkConnectionLost)]
        )
        let client=try makeClient(attempts:2,transport:transport)
        do { try await client.deleteRun(id:"104",version:9); XCTFail("The first response was lost") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.transport(.networkConnectionLost)) }
        let afterLostResponse=await transport.recordedRequests()
        XCTAssertEqual(afterLostResponse.count,1,"DELETE must not retry automatically after an uncertain transport failure")

        try await client.deleteRun(id:"104",version:9)
        let requests=await transport.recordedRequests()
        XCTAssertEqual(requests.count,2)
        XCTAssertEqual(requests.map(\.path),["runs/104","runs/104"])
        XCTAssertEqual(requests.map(\.queryItems),[[URLQueryItem(name:"version",value:"9")],[URLQueryItem(name:"version",value:"9")]])
    }

    func testDeleteRejectsUnsafeIDAndNegativeVersionWithoutSendingRequest() async throws {
        let transport=RunRecordsRecordingTransport(responses:[])
        let client=try makeClient(transport:transport)
        do { try await client.deleteRun(id:"../other",version:1); XCTFail("Expected an unsafe ID to be rejected") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.invalidDeletion) }
        do { try await client.deleteRun(id:"104",version:-1); XCTFail("Expected a negative version to be rejected") }
        catch { XCTAssertEqual(error as? RunRecordsFailure,.invalidDeletion) }
        let requests=await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testMalformedWrapperAndPointRewardAreRejected() async throws {
        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"runs":[],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("Expected wrapper mismatch") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }

        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[\#(summary(pointReward:#"{"status":"SETTLED","pointsAwarded":null}"#))],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("Expected invalid settled reward") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }

        let missingNullable=summary().replacingOccurrences(of:",\"pointReward\":{\"status\":\"SETTLED\",\"pointsAwarded\":0},",with:",")
        MockURLProtocol.respond(statusCode: 200, data: Data(#"{"items":[\#(missingNullable)],"nextCursor":null}"#.utf8))
        do { _ = try await makeClient().fetchRuns(); XCTFail("The API contract requires nullable fields to be explicit") }
        catch { XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse) }
    }

    func testLoaderAppendsPagesWithoutParsingCursorAndStopsCursorLoop() async {
        let item = Self.makeSummary()
        let reader = SequencedRunRecordsReader(pages: [
            BackendRunPage(items: [item], nextCursor: "opaque-A"),
            BackendRunPage(items: [item], nextCursor: "opaque-A")
        ])
        let loader = RunRecordsLoader(client: reader, pageSize: 1)
        await loader.load()
        await loader.loadNextPage()

        let state = await loader.state
        XCTAssertEqual(state, .failedLoadingMore(BackendRunSnapshot(items: [item], nextCursor: "opaque-A"), .paginationLoop))
        let passedCursors = await reader.passedCursors
        XCTAssertEqual(passedCursors, [nil, "opaque-A"])
    }

    func testCompleteRefreshBuildsAllPagesBeforeAtomicReplacement() async throws {
        let old = Self.makeSummary(id: "old")
        let first = Self.makeSummary(id: "new-1")
        let second = Self.makeSummary(id: "new-2")
        let reader = FullListRefreshReader(pages: [
            .success(BackendRunPage(items: [old], nextCursor: nil)),
            .success(BackendRunPage(items: [first], nextCursor: "opaque_A-2")),
            .success(BackendRunPage(items: [second], nextCursor: nil))
        ])
        let loader = RunRecordsLoader(client: reader, pageSize: 1)
        await loader.load()

        let candidate = try await loader.fetchCompleteList()
        let beforeCommit = await loader.state
        XCTAssertEqual(beforeCommit, .loaded(BackendRunSnapshot(items: [old], nextCursor: nil)))
        XCTAssertEqual(candidate.snapshot, BackendRunSnapshot(items: [first, second], nextCursor: nil))
        let applied = await loader.applyCompleteList(candidate)
        XCTAssertTrue(applied)

        let afterCommit = await loader.state
        XCTAssertEqual(afterCommit, .loaded(BackendRunSnapshot(items: [first, second], nextCursor: nil)))
        let cursors = await reader.passedCursors
        XCTAssertEqual(cursors, [nil, nil, "opaque_A-2"], "Opaque cursors pass through unchanged")
    }

    func testCompleteRefreshFailurePreservesLastSnapshotAndCanRetry() async throws {
        let old = Self.makeSummary(id: "old-cache")
        let partial = Self.makeSummary(id: "partial-new")
        let recovered = Self.makeSummary(id: "recovered")
        let reader = FullListRefreshReader(pages: [
            .success(BackendRunPage(items: [old], nextCursor: nil)),
            .success(BackendRunPage(items: [partial], nextCursor: "opaque-next")),
            .failure(.serverFailure(statusCode: 503, requestID: "second-page-outage")),
            .success(BackendRunPage(items: [recovered], nextCursor: nil))
        ])
        let loader = RunRecordsLoader(client: reader, pageSize: 1)
        await loader.load()

        do {
            _ = try await loader.fetchCompleteList()
            XCTFail("A failed later page must fail the whole refresh")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .serverFailure(statusCode: 503, requestID: "second-page-outage"))
        }
        let afterFailure = await loader.state
        XCTAssertEqual(afterFailure, .loaded(BackendRunSnapshot(items: [old], nextCursor: nil)))

        let candidate = try await loader.fetchCompleteList()
        let applied = await loader.applyCompleteList(candidate)
        XCTAssertTrue(applied)
        let afterRetry = await loader.state
        XCTAssertEqual(afterRetry, .loaded(BackendRunSnapshot(items: [recovered], nextCursor: nil)))
    }

    func testCompleteRefreshStopsRepeatedCursorsAndDuplicateIDsWithoutReplacingCache() async throws {
        let old = Self.makeSummary(id: "old")
        let first = Self.makeSummary(id: "duplicate")
        let repeatedCursorReader = FullListRefreshReader(pages: [
            .success(BackendRunPage(items: [old], nextCursor: nil)),
            .success(BackendRunPage(items: [first], nextCursor: "same-cursor")),
            .success(BackendRunPage(items: [Self.makeSummary(id: "other")], nextCursor: "same-cursor"))
        ])
        let repeatedCursorLoader = RunRecordsLoader(client: repeatedCursorReader, pageSize: 1)
        await repeatedCursorLoader.load()
        do {
            _ = try await repeatedCursorLoader.fetchCompleteList()
            XCTFail("A repeated pagination cursor must stop the read")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .paginationLoop)
        }
        let repeatedState = await repeatedCursorLoader.state
        XCTAssertEqual(repeatedState, .loaded(BackendRunSnapshot(items: [old], nextCursor: nil)))
        let repeatedCursors = await repeatedCursorReader.passedCursors
        XCTAssertEqual(repeatedCursors, [nil, nil, "same-cursor"], "The repeated cursor is never requested twice")

        let duplicateReader = FullListRefreshReader(pages: [
            .success(BackendRunPage(items: [old], nextCursor: nil)),
            .success(BackendRunPage(items: [first], nextCursor: "next")),
            .success(BackendRunPage(items: [first], nextCursor: nil))
        ])
        let duplicateLoader = RunRecordsLoader(client: duplicateReader, pageSize: 1)
        await duplicateLoader.load()
        do {
            _ = try await duplicateLoader.fetchCompleteList()
            XCTFail("Duplicate IDs across pages must reject the candidate")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .invalidResponse)
        }
        let duplicateState = await duplicateLoader.state
        XCTAssertEqual(duplicateState, .loaded(BackendRunSnapshot(items: [old], nextCursor: nil)))
    }

    func testCompleteRefreshMarksMissingCachedDetailOnlyAfterCommit() async throws {
        let staleDetail = Self.makeDetail(id: "removed-on-another-device")
        let remaining = Self.makeSummary(id: "remaining")
        let reader = FullListRefreshReader(
            pages: [.success(BackendRunPage(items: [remaining], nextCursor: nil))],
            details: [staleDetail.summary.id: staleDetail]
        )
        let loader = RunRecordsLoader(client: reader)
        await loader.loadDetail(runID: staleDetail.summary.id)
        let candidate = try await loader.fetchCompleteList()

        let beforeCommit = await loader.detailState
        XCTAssertEqual(beforeCommit, .loaded(staleDetail))
        let applied = await loader.applyCompleteList(candidate)
        XCTAssertTrue(applied)
        let afterCommit = await loader.detailState
        XCTAssertEqual(afterCommit, .failed(runID: staleDetail.summary.id, .recordNotFound))
    }

    func testCancelledCompleteRefreshPreservesLastSnapshot() async {
        let old = Self.makeSummary(id: "old-before-cancel")
        let gate = RunReadGate()
        let reader = FullListRefreshReader(
            pages: [
                .success(BackendRunPage(items: [old], nextCursor: nil)),
                .success(BackendRunPage(items: [Self.makeSummary(id: "not-committed")], nextCursor: nil))
            ],
            gates: [2: gate]
        )
        let loader = RunRecordsLoader(client: reader)
        await loader.load()
        let refresh = Task { try await loader.fetchCompleteList() }
        await gate.waitUntilEntered()
        refresh.cancel()
        await gate.release()
        do {
            _ = try await refresh.value
            XCTFail("A cancelled scan cannot produce a replacement candidate")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .cancelled)
        }
        let state = await loader.state
        XCTAssertEqual(state, .loaded(BackendRunSnapshot(items: [old], nextCursor: nil)))
    }

    func testCompleteRefreshSupersedesAnInFlightNextPageWithoutAppendingItLater() async throws {
        let old = Self.makeSummary(id: "old-first-page")
        let stalePage = Self.makeSummary(id: "stale-next-page")
        let fresh = Self.makeSummary(id: "fresh-complete-list")
        let gate = RunReadGate()
        let reader = FullListRefreshReader(
            pages: [
                .success(BackendRunPage(items: [old], nextCursor: "old-page-cursor")),
                .success(BackendRunPage(items: [stalePage], nextCursor: nil)),
                .success(BackendRunPage(items: [fresh], nextCursor: nil))
            ],
            gates: [2: gate]
        )
        let loader = RunRecordsLoader(client: reader, pageSize: 1)
        await loader.load()
        let nextPage = Task { await loader.loadNextPage() }
        await gate.waitUntilEntered()

        let candidate = try await loader.fetchCompleteList()
        let applied = await loader.applyCompleteList(candidate)
        XCTAssertTrue(applied)
        await gate.release()
        await nextPage.value

        let state = await loader.state
        XCTAssertEqual(state, .loaded(BackendRunSnapshot(items: [fresh], nextCursor: nil)))
        let cursors = await reader.passedCursors
        XCTAssertEqual(cursors, [nil, "old-page-cursor", nil])
    }

    func testEditOrDeleteInvalidatesAnInFlightFullRefresh() async throws {
        let original = Self.makeSummary(id: "local-write")
        let changed = Self.makeSummary(id: "local-write", title: "newer-title")
        let gate = RunReadGate()
        let editReader = FullListRefreshReader(
            pages: [
                .success(BackendRunPage(items: [original], nextCursor: nil)),
                .success(BackendRunPage(items: [original], nextCursor: nil))
            ],
            gates: [2: gate]
        )
        let editLoader = RunRecordsLoader(client: editReader)
        await editLoader.load()
        let pendingEditRefresh = Task { try await editLoader.fetchCompleteList() }
        await gate.waitUntilEntered()
        await editLoader.applyUpdatedSummary(changed)
        await gate.release()
        do {
            _ = try await pendingEditRefresh.value
            XCTFail("A response started before an edit cannot replace the updated list")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .cancelled)
        }
        let afterEdit = await editLoader.state
        XCTAssertEqual(afterEdit, .loaded(BackendRunSnapshot(items: [changed], nextCursor: nil)))

        let deleteGate = RunReadGate()
        let deleteReader = FullListRefreshReader(
            pages: [
                .success(BackendRunPage(items: [original], nextCursor: nil)),
                .success(BackendRunPage(items: [original], nextCursor: nil))
            ],
            gates: [2: deleteGate]
        )
        let deleteLoader = RunRecordsLoader(client: deleteReader)
        await deleteLoader.load()
        let pendingDeleteRefresh = Task { try await deleteLoader.fetchCompleteList() }
        await deleteGate.waitUntilEntered()
        await deleteLoader.applyDeletedRun(id: original.id)
        await deleteGate.release()
        do {
            _ = try await pendingDeleteRefresh.value
            XCTFail("A response started before a delete cannot restore the removed row")
        } catch {
            XCTAssertEqual(error as? RunRecordsFailure, .cancelled)
        }
        let afterDelete = await deleteLoader.state
        XCTAssertEqual(afterDelete, .loaded(BackendRunSnapshot(items: [], nextCursor: nil)))
    }

    func testStaleRunDetailResponseCannotReplaceTheNewSelection() async {
        let gate = RunReadGate()
        let reader = ControlledRunDetailReader(gate: gate)
        let loader = RunRecordsLoader(client: reader)
        let stale = Task { await loader.loadDetail(runID: "older") }
        await gate.waitUntilEntered()
        await loader.loadDetail(runID: "newer")
        await gate.release()
        await stale.value

        let detailState = await loader.detailState
        XCTAssertEqual(detailState, .loaded(Self.makeDetail(id: "newer")))
    }

    fileprivate static func makeSummary(id: String = "104", title: String? = "밤 러닝") -> BackendRunSummary {
        BackendRunSummary(
            id: id, clientRunID: UUID(uuidString: "0b8f6c1e-5a44-4d0b-9a0e-3f2f7f0c9d11")!, version: 3,
            startedAt: Date(timeIntervalSince1970: 1_791_213_000), endedAt: Date(timeIntervalSince1970: 1_791_215_400),
            runDate: "2026-10-05", elapsedSeconds: 2_400, movingSeconds: 2_280, distanceMeters: 6_400,
            verdict: "VALID", verdictReason: nil, validDistanceMeters: 6_100, validSeconds: 2_150,
            paceSecondsPerKm: 352, title: title, memo: nil, createdAt: Date(timeIntervalSince1970: 1_791_215_462),
            updatedAt: Date(timeIntervalSince1970: 1_791_215_462), pointReward: nil
        )
    }

    fileprivate static func makeDetail(id: String) -> BackendRunDetail {
        BackendRunDetail(summary: makeSummary(id: id), points: [], pauses: [], judgement: nil)
    }
}

private struct RunTokenProvider: AccessTokenProviding {
    let value: String?
    func accessToken() async throws -> String? { value }
}

private actor SequencedRunRecordsReader: RunRecordsReading {
    private var pages: [BackendRunPage]
    private(set) var passedCursors: [String?] = []

    init(pages: [BackendRunPage]) { self.pages = pages }
    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage {
        passedCursors.append(cursor)
        return pages.removeFirst()
    }
    func fetchRun(id: String) async throws -> BackendRunDetail { RunRecordsReadTests.makeDetail(id: id) }
}

private actor FullListRefreshReader: RunRecordsReading {
    private var pages: [Result<BackendRunPage, RunRecordsFailure>]
    private let details: [String: BackendRunDetail]
    private let gates: [Int: RunReadGate]
    private(set) var passedCursors: [String?] = []

    init(
        pages: [Result<BackendRunPage, RunRecordsFailure>],
        details: [String: BackendRunDetail] = [:],
        gates: [Int: RunReadGate] = [:]
    ) {
        self.pages = pages
        self.details = details
        self.gates = gates
    }

    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage {
        passedCursors.append(cursor)
        let call = passedCursors.count
        guard !pages.isEmpty else { throw RunRecordsFailure.invalidResponse }
        let result = pages.removeFirst()
        if let gate = gates[call] { await gate.wait() }
        return try result.get()
    }

    func fetchRun(id: String) async throws -> BackendRunDetail {
        guard let detail = details[id] else { throw RunRecordsFailure.recordNotFound }
        return detail
    }
}

private actor RunReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false

    func wait() async {
        if released { return }
        entered = true
        await withCheckedContinuation { continuation in
            if released { continuation.resume() }
            else { self.continuation = continuation }
        }
    }
    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }
    func release() {
        released = true
        entered = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ControlledRunDetailReader: RunRecordsReading {
    let gate: RunReadGate
    init(gate: RunReadGate) { self.gate = gate }

    func fetchRuns(cursor: String?, size: Int) async throws -> BackendRunPage { BackendRunPage(items: [], nextCursor: nil) }
    func fetchRun(id: String) async throws -> BackendRunDetail {
        if id == "older" { await gate.wait() }
        return RunRecordsReadTests.makeDetail(id: id)
    }
}
