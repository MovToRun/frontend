import Foundation
import XCTest
@testable import MovNetworking

private struct PointsTokenStub: AccessTokenProviding {
    let value: String?

    func accessToken() async throws -> String? { value }
}

private func makePointsClient(
    token: String? = "fixture-points-token",
    retryPolicy: PointsReadRetryPolicy = PointsReadRetryPolicy()
) throws -> PointsWalletClient {
    let configuration = try APIClientConfiguration(
        environment: .development,
        baseURLString: "https://api-dev.example.invalid/api/v1/",
        requestTimeout: 4,
        resourceTimeout: 9
    )
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    let apiClient = APIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
    return PointsWalletClient(
        apiClient: apiClient,
        tokenProvider: PointsTokenStub(value: token),
        retryPolicy: retryPolicy,
        sleep: { _ in }
    )
}

private func pointsBalanceBody(_ balance: Int64) -> Data {
    Data("{\"balancePoints\":\(balance)}".utf8)
}

private func pointsPageBody(entryID: String, nextCursor: String?) -> Data {
    let next = nextCursor.map { "\"\($0)\"" } ?? "null"
    return Data("""
    {"entries":[{"entryId":"\(entryID)","direction":"CREDIT","deltaPoints":10,"balanceAfterPoints":20,"reasonCode":"RUN_REWARD","createdAt":"2026-10-11T12:00:00+09:00"}],"nextCursor":\(next)}
    """.utf8)
}

private func waitForPendingURLProtocol() async -> Bool {
    for _ in 0..<500 {
        if MockURLProtocol.pendingCount > 0 { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

final class PointsReadTests: XCTestCase {
    func testZeroBalanceIsAValidSuccessfulResponse() async throws {
        MockURLProtocol.respond(statusCode: 200, data: pointsBalanceBody(0))
        let balance = try await makePointsClient().fetchBalance()
        let request = try XCTUnwrap(MockURLProtocol.requests.first)

        XCTAssertEqual(balance.balancePoints, 0)
        XCTAssertEqual(request.url?.path, "/api/v1/points/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-points-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testUnauthenticatedBalanceBecomesFailureAndNeverAZeroValue() async throws {
        MockURLProtocol.respond(statusCode: 401, data: Data("{\"code\":\"UNAUTHENTICATED\"}".utf8))
        let loader = PointsWalletLoader(client: try makePointsClient())

        await loader.load()

        let state = await loader.state
        XCTAssertEqual(state, .failed(.unauthenticated))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testUnavailablePointsServiceRetriesOnceThenRemainsUnavailable() async throws {
        let problem = Data("{\"status\":503,\"code\":\"POINT_UNAVAILABLE\",\"title\":\"private ledger detail\",\"requestId\":\"req-points-1\"}".utf8)
        MockURLProtocol.respondSequence([(503, problem), (503, problem)])
        let client = try makePointsClient(retryPolicy: PointsReadRetryPolicy(maximumAttempts: 2, delayNanoseconds: 0))

        do {
            _ = try await client.fetchBalance()
            XCTFail("Expected the unavailable points service to fail")
        } catch let failure as PointsReadFailure {
            XCTAssertEqual(failure, .pointsUnavailable(requestID: "req-points-1"))
            XCTAssertFalse(String(describing: failure).contains("private ledger detail"))
            XCTAssertFalse(failure.userMessage.contains("private ledger detail"))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testActualTaskCancellationDoesNotTriggerAutomaticRetry() async throws {
        MockURLProtocol.suspendNext()
        let client = try makePointsClient(
            retryPolicy: PointsReadRetryPolicy(maximumAttempts: 2, delayNanoseconds: 0)
        )
        let requestTask = Task { () -> PointsReadFailure? in
            do {
                _ = try await client.fetchBalance()
                return nil
            } catch let failure as PointsReadFailure {
                return failure
            } catch {
                return nil
            }
        }

        let didSuspend = await waitForPendingURLProtocol()
        XCTAssertTrue(didSuspend, "Expected URLProtocol to suspend the request")
        requestTask.cancel()

        let failure = await requestTask.value
        XCTAssertEqual(failure, .cancelled)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(MockURLProtocol.pendingCount, 0)
    }

    func testManualRetryCanRetryNonTransientTransportFailureWithoutAutomaticRetry() async throws {
        MockURLProtocol.failThenRespond(
            with: .badServerResponse,
            statusCode: 200,
            data: pointsBalanceBody(20)
        )
        let loader = PointsWalletLoader(
            client: try makePointsClient(
                retryPolicy: PointsReadRetryPolicy(maximumAttempts: 2, delayNanoseconds: 0)
            )
        )

        await loader.load()
        guard case .failed(let failure) = await loader.state else {
            XCTFail("Expected a transport failure")
            return
        }
        XCTAssertEqual(failure, .transport(.badServerResponse))
        XCTAssertTrue(failure.userMessage.contains("다시 시도"))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        MockURLProtocol.respondSequence([
            (200, pointsBalanceBody(20)),
            (200, pointsPageBody(entryID: "22", nextCursor: nil))
        ])
        await loader.retry()

        guard case .loaded(let snapshot) = await loader.state else {
            XCTFail("Expected an explicit retry to recover from the transport failure")
            return
        }
        XCTAssertEqual(snapshot.entries.map(\.entryID), ["22"])
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testMissingTokenStopsBeforeNetworkRequest() async throws {
        MockURLProtocol.reset()
        let client = try makePointsClient(token: nil)

        do {
            _ = try await client.fetchBalance()
            XCTFail("Expected an unavailable access token")
        } catch let failure as PointsReadFailure {
            XCTAssertEqual(failure, .accessTokenUnavailable)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testEntryDTOAndOpaqueCursorQueryMatchBackendContract() async throws {
        MockURLProtocol.respond(statusCode: 200, data: pointsPageBody(entryID: "23", nextCursor: nil))
        let page = try await makePointsClient().fetchEntries(cursor: "Ab_c-123", size: 1)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00+09:00"))

        XCTAssertEqual(components.path, "/api/v1/points/me/entries")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "cursor", value: "Ab_c-123"), URLQueryItem(name: "size", value: "1")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-points-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries[0].entryID, "23")
        XCTAssertEqual(page.entries[0].direction, .credit)
        XCTAssertEqual(page.entries[0].deltaPoints, 10)
        XCTAssertEqual(page.entries[0].balanceAfterPoints, 20)
        XCTAssertEqual(page.entries[0].reasonCode, "RUN_REWARD")
        XCTAssertEqual(page.entries[0].createdAt, date)
        XCTAssertNil(page.nextCursor)
    }

    func testInvalidPageSizeDoesNotSendRequest() async throws {
        MockURLProtocol.reset()
        let client = try makePointsClient()

        do {
            _ = try await client.fetchEntries(cursor: nil, size: 51)
            XCTFail("Expected invalid page size")
        } catch let failure as PointsReadFailure {
            XCTAssertEqual(failure, .invalidPageSize)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testWalletLoaderAppendsPagesAndStopsAtNullCursor() async throws {
        MockURLProtocol.respondSequence([
            (200, pointsBalanceBody(0)),
            (200, pointsPageBody(entryID: "22", nextCursor: "Mg")),
            (200, pointsPageBody(entryID: "21", nextCursor: nil))
        ])
        let loader = PointsWalletLoader(client: try makePointsClient(), pageSize: 1)

        await loader.load()
        let firstState = await loader.state
        guard case .loaded(let firstSnapshot) = firstState else {
            XCTFail("Expected the first remote page to load")
            return
        }
        XCTAssertEqual(firstSnapshot.balance.balancePoints, 0)
        XCTAssertEqual(firstSnapshot.entries.map(\.entryID), ["22"])
        XCTAssertEqual(firstSnapshot.nextCursor, "Mg")

        await loader.loadNextPage()
        let finalState = await loader.state
        guard case .loaded(let finalSnapshot) = finalState else {
            XCTFail("Expected the next remote page to load")
            return
        }
        XCTAssertEqual(finalSnapshot.entries.map(\.entryID), ["22", "21"])
        XCTAssertNil(finalSnapshot.nextCursor)

        await loader.loadNextPage()
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testPageFailurePreservesRemoteSnapshotAndExplicitRetryReusesCursor() async throws {
        let unavailable = Data("{\"status\":503,\"code\":\"POINT_UNAVAILABLE\",\"requestId\":\"req-points-page\"}".utf8)
        MockURLProtocol.respondSequence([
            (200, pointsBalanceBody(20)),
            (200, pointsPageBody(entryID: "22", nextCursor: "Mg")),
            (503, unavailable),
            (503, unavailable),
            (200, pointsPageBody(entryID: "21", nextCursor: nil))
        ])
        let loader = PointsWalletLoader(
            client: try makePointsClient(retryPolicy: PointsReadRetryPolicy(maximumAttempts: 2, delayNanoseconds: 0)),
            pageSize: 1
        )

        await loader.load()
        await loader.loadNextPage()
        let failedState = await loader.state
        guard case .failedLoadingMore(let preserved, let failure) = failedState else {
            XCTFail("Expected a page failure with the previous page preserved")
            return
        }
        XCTAssertEqual(preserved.balance.balancePoints, 20)
        XCTAssertEqual(preserved.entries.map(\.entryID), ["22"])
        XCTAssertEqual(failure, .pointsUnavailable(requestID: "req-points-page"))

        await loader.retry()
        let finalState = await loader.state
        guard case .loaded(let finalSnapshot) = finalState else {
            XCTFail("Expected retry to append the requested page")
            return
        }
        XCTAssertEqual(finalSnapshot.entries.map(\.entryID), ["22", "21"])
        let requests = MockURLProtocol.requests
        XCTAssertEqual(requests.count, 5)
        for request in requests[2...] {
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.queryItems, [URLQueryItem(name: "cursor", value: "Mg"), URLQueryItem(name: "size", value: "1")])
        }
    }

    func testCursorLoopFailsClosedWithoutAppendingRepeatedPage() async throws {
        MockURLProtocol.respondSequence([
            (200, pointsBalanceBody(20)),
            (200, pointsPageBody(entryID: "22", nextCursor: "Mg")),
            (200, pointsPageBody(entryID: "21", nextCursor: "Mg"))
        ])
        let loader = PointsWalletLoader(client: try makePointsClient(), pageSize: 1)

        await loader.load()
        await loader.loadNextPage()

        let state = await loader.state
        guard case .failedLoadingMore(let snapshot, .paginationLoop) = state else {
            XCTFail("Expected repeated cursors to stop pagination")
            return
        }
        XCTAssertEqual(snapshot.entries.map(\.entryID), ["22"])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testConcurrentLoadKeepsNewerResultWhenOlderRequestCompletesLast() async throws {
        MockURLProtocol.holdFirstThenRespondSequence([
            (200, pointsBalanceBody(99)),
            (200, pointsPageBody(entryID: "new", nextCursor: nil))
        ])
        let loader = PointsWalletLoader(client: try makePointsClient(), pageSize: 1)
        let olderLoad = Task { await loader.load() }

        let didSuspend = await waitForPendingURLProtocol()
        XCTAssertTrue(didSuspend, "Expected the older load to remain pending")
        guard didSuspend else {
            await olderLoad.value
            return
        }
        let newerLoad = Task { await loader.load() }
        await newerLoad.value

        guard case .loaded(let newerSnapshot) = await loader.state else {
            XCTFail("Expected the newer load to publish its result")
            _ = MockURLProtocol.resumeNextPending(statusCode: 200, data: pointsBalanceBody(1))
            await olderLoad.value
            return
        }
        XCTAssertEqual(newerSnapshot.balance.balancePoints, 99)
        XCTAssertEqual(newerSnapshot.entries.map(\.entryID), ["new"])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)

        XCTAssertTrue(MockURLProtocol.resumeNextPending(statusCode: 200, data: pointsBalanceBody(1)))
        await olderLoad.value

        guard case .loaded(let finalSnapshot) = await loader.state else {
            XCTFail("Expected the stale request to leave the newer state intact")
            return
        }
        XCTAssertEqual(finalSnapshot.balance.balancePoints, 99)
        XCTAssertEqual(finalSnapshot.entries.map(\.entryID), ["new"])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testExplicitRetryRecoversFromInvalidResponse() async throws {
        MockURLProtocol.respondSequence([
            (200, Data("{\"balance\":20}".utf8)),
            (200, pointsBalanceBody(20)),
            (200, pointsPageBody(entryID: "22", nextCursor: nil))
        ])
        let loader = PointsWalletLoader(client: try makePointsClient())

        await loader.load()
        guard case .failed(.invalidResponse) = await loader.state else {
            XCTFail("Expected a malformed first response to fail")
            return
        }
        XCTAssertTrue(PointsReadFailure.invalidResponse.userMessage.contains("다시 시도"))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        await loader.retry()

        guard case .loaded(let snapshot) = await loader.state else {
            XCTFail("Expected explicit retry to recover from the malformed response")
            return
        }
        XCTAssertEqual(snapshot.balance.balancePoints, 20)
        XCTAssertEqual(snapshot.entries.map(\.entryID), ["22"])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testExplicitRetryRecoversFromServerFailureSuggestedByCopy() async throws {
        MockURLProtocol.respondSequence([
            (500, Data("{\"code\":\"INTERNAL_ERROR\"}".utf8)),
            (200, pointsBalanceBody(20)),
            (200, pointsPageBody(entryID: "22", nextCursor: nil))
        ])
        let loader = PointsWalletLoader(client: try makePointsClient())

        await loader.load()
        guard case .failed(let failure) = await loader.state else {
            XCTFail("Expected the server failure to be exposed")
            return
        }
        XCTAssertEqual(failure, .serverFailure(statusCode: 500, requestID: nil))
        XCTAssertTrue(failure.userMessage.contains("다시 시도"))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        await loader.retry()

        guard case .loaded(let snapshot) = await loader.state else {
            XCTFail("Expected explicit retry to recover from the server failure")
            return
        }
        XCTAssertEqual(snapshot.balance.balancePoints, 20)
        XCTAssertEqual(snapshot.entries.map(\.entryID), ["22"])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testClientErrorCopyDoesNotSuggestRetryAndRetrySendsNoRequest() async throws {
        MockURLProtocol.respond(statusCode: 400, data: Data("{\"code\":\"BAD_REQUEST\"}".utf8))
        let loader = PointsWalletLoader(client: try makePointsClient())

        await loader.load()
        guard case .failed(let failure) = await loader.state else {
            XCTFail("Expected the client error to be exposed")
            return
        }
        XCTAssertEqual(failure, .serverFailure(statusCode: 400, requestID: nil))
        XCTAssertFalse(failure.userMessage.contains("다시 시도"))
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        await loader.retry()

        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }
}
