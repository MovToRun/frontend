# Backend run record reads

## Pinned contract

- Frontend base: merged `main` at `b522494ea367ba792e093379287be0df925ebbd7` (PR #49).
- Backend contract source: `MovToRun/backend` commit
  `089dc2a7d94c791f493718213b18fc7b60cb6aa6`.
- Confirmed source files: `docs/API_CONTRACT.md`, `RunService.java`,
  `RunCursor.java`, `RunSummaryResponse.java`, `RunListResponse.java`,
  `RunDetailResponse.java`, and `RunController.java`.

The authenticated read endpoints are `GET /api/v1/runs?size=20[&cursor=…]`
and `GET /api/v1/runs/{runId}`. The list response is
`{ "items": [...], "nextCursor": null }`; the detail response flattens all
summary fields and adds `points`, `pauses`, and nullable `judgement`. A list
cursor is treated as an opaque value and passed as a query item without parsing
or reconstruction. The client uses the backend page default (20) and bounds
page size to 1–50.

The summary decoder follows the backend field names and requires nullable
contract fields to be present as explicit `null` values. Distances, seconds,
versions, and point counts are decoded as 64-bit integers. `distanceMeters` and
`movingSeconds` are the original submitted measurements; `validDistanceMeters`
and `validSeconds` are server judgement values. The UI displays both pairs and
converts metres to decimal kilometres only at the presentation layer. `runDate`
is kept as the server's KST calendar date. Timestamp strings must carry the
backend's `+09:00` offset; display formatters also pin to KST, including
fractional-second track timestamps in the detail model.

`pointReward` preserves the contract distinction between a missing reward
(`null`), pending/unavailable with a null amount, and settled with an amount of
zero or more. The UI uses the existing reward labels and does not synthesize a
reward when the field is null.

## Composition and UI boundary

`RunRecordsClient` receives the existing `APIClient` and injected
`AccessTokenProviding` dependency. It sends bearer-authenticated GET requests
with `Accept: application/json` and `Cache-Control: no-store`; it has no write
method. `RunRecordsLoader` exposes explicit list/detail loading, loaded, and
failure states, appends list pages in server order, stops cursor loops, and
ignores older completions after a newer list or detail generation begins.
`WireframeRemoteReadBridge` adds run reads to the existing optional dependency
composition. Screen task cancellation, account scope changes, and selected
detail ID changes invalidate stale results.

Remote list rows and detail are rendered separately from `RunStore.records`.
A request failure remains an error with a retry action where supported; it
never becomes an empty successful list. The default app entry still injects no
remote loader. A caller must provide both the configured transport and an
authenticated token provider before real reads can be enabled. The UI-test
fixture is explicitly enabled only by `-wire-run-records-fixture`; it uses an
in-memory reader with synthetic values.

The detail response includes stored GPS points, but this read slice does not
request device location, render coordinates, submit tracks, upload files, or
send notifications. It shows point and pause counts only. No host, credential,
session refresh, server write, or persistent remote cache was added.

## Verification and limits

- `swift test`: 42/42 passed using `MockURLProtocol` and scripted readers.
  Coverage includes list wrapper and flattened detail mapping, opaque cursor
  query, fractional timestamp parsing, 64-bit exclusion distance, reward-zero
  semantics, explicit-null validation, 401/missing-token failures, invalid
  page size/ID, pagination loop, and stale detail completion.
- Focused Xcode run: 3/3 passed on the already booted iPhone 17 Pro simulator,
  iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`), from a temporary source
  copy with unique app, unit-test, and UI-test bundle IDs and an isolated
  UserDefaults fixture. It covered injected list/detail, local record
  preservation on a server error, bridge account/screen scope, and cancellation
  of an initial list read. Result bundle:
  `/tmp/mov-run-records-focused-final.xcresult`.
- No live backend request, real credential, real GPS capture, or write request
  was used. Full wireframe pixel and motion QA remains open.

## Follow-up

The future authenticated session/composition owner must supply the production
host and token provider and decide how server records coexist with local records
in the product flow. This branch does not infer a merge/migration policy, add
record editing/deletion, or configure a production backend.
