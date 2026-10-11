# Backend points read preparation

## Confirmed contract

This branch starts from frontend `main` at
`bb5b497fd3c40b3d6e1276a50acc4f2fc2fa72d6`. It was prepared against backend
`main` at `f47da2589d0d3b75fcebe176ec8e0ea1ca7346b8`, which includes PR #70.
The backend contract is `docs/API_CONTRACT.md`, section 13; the response shape
was also checked against `PointWalletController` and `PointWalletApiTests`.

- `GET /api/v1/points/me` requires bearer authentication and returns
  `{ "balancePoints": <integer> }`. A successful `0` is valid when no wallet
  row exists.
- `GET /api/v1/points/me/entries?size=20` returns `{ "entries": [...],
  "nextCursor": null }`. Entries are in descending `id` order and expose only
  `entryId`, `direction`, `deltaPoints`, `balanceAfterPoints`, `reasonCode`, and
  `createdAt`. Direction values are `CREDIT` and `DEBIT`.
- Cursor values are opaque and URL-safe. Page size defaults to 20 and must be
  between 1 and 50. Omit `cursor` on the first page; include it only when the
  server returned a next cursor. Both endpoints return `Cache-Control: no-store`.
- `401 UNAUTHENTICATED` means the request failed authentication. A closed
  feature gate or unavailable wallet/ledger store returns `503 POINT_UNAVAILABLE`.

## Implementation boundary

The existing `APIClient` remains the only transport. It now accepts separately
encoded `URLQueryItem`s so the opaque cursor is never concatenated into a path.
`PointsWalletClient` decodes dedicated remote balance and ledger types and uses
the existing injected `AccessTokenProviding` protocol. It does not persist the
remote result, update `WPointsStore`, or convert server rows into local
`WPointEntry` values.

`PointsWalletLoader` exposes `idle`, `loading`, `loaded`, `loadingMore`,
`failed`, and `failedLoadingMore` states. It appends pages in server order,
preserves the last successful page when a later page temporarily fails, and
stops on a repeated cursor. A page retry reuses that cursor; a cursor loop starts
a fresh first-page load.

The only successful balance value represented as zero is the decoded
`balancePoints: 0` response. Missing/invalid credentials, `401`, malformed
responses, and `503 POINT_UNAVAILABLE` remain typed failures with no zero-value
fallback. `401` is not retried here; the future session coordinator owns the
single refresh attempt. `503 POINT_UNAVAILABLE` and selected transient transport
failures receive at most one automatic retry. Raw problem titles and backend
exception details are not surfaced to the UI. The loader's explicit retry action
also retries malformed responses, cursor-loop recovery, and server failures
with 5xx status codes, and allows a user-initiated retry for any transport
failure. Its user-facing copy offers retry only for failures that the action can
retry; 4xx responses, invalid page sizes, and auth-state failures do not suggest
the loader retry action. This does not expand the automatic retry policy.

Restricting authorization-bearing requests across redirects remains a transport
hardening follow-up. No cross-host redirect was demonstrated or is claimed as a
confirmed vulnerability in this change.

The existing SwiftUI points screens and `WPointsStore` are unchanged. Their
UserDefaults-backed entries and sample fixture remain local and visually
separate from the new remote models; this preparation does not replace or
migrate them. No Keychain provider, session refresh, purchase mutation, real
server host, or live request is included.

## Verification boundaries

`MovNetworkingTests` passed 35/35 with `MockURLProtocol` fixtures, including
zero-vs-auth-failure, point-service unavailability, DTO/date mapping, query
encoding, page-size bounds, cursor progression/loop handling, manual-retry copy
consistency, concurrent load ordering, actual task cancellation, and
preservation of the prior remote page after a temporary error. The network
source passed an iOS Simulator SDK 26.2 cross-target typecheck under Xcode 26.3.
No live backend request or full app/UI test was run. Pixel/motion QA and wiring
the remote loader to an authenticated UI flow remain unverified.
