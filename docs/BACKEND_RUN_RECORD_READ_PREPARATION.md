# Backend run record reads and title/memo edits

This document keeps the read-integration baseline and records the optional
title/memo edit seam added from frontend `main` `4efc9498a9fbdb461f986ab1418194790ced35ac`
against backend `main` `d545fd91f0c7d5d73863ee49396b95b6d629830e`. The edit
contract was confirmed in its earlier backend revision
`b362098389f70734dc7ef58f4c109200b587f5e6`; the intervening main commit only
adds member-erasure dispatch and leaves the run edit contract unchanged.

## Read slice provenance

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

The current write endpoint is `PATCH /api/v1/runs/{runId}` with a required
`version`. The title and memo are sent independently: an omitted field remains
unchanged, `null` also remains unchanged, and `""` clears the field. The client
omits the unedited property and sends the current detail version. A successful
response must carry the same run ID and version plus one. The backend applies
the Java `String.length()` limits (40 UTF-16 code units for title, 300 for
memo); the inline editor keeps its existing grapheme-based visual behavior for
local records and uses UTF-16 counts for remote fields. Remote text is sent
without trimming or normalization, matching the server's empty-string-only
clear rule.

## Composition and UI boundary

`RunRecordsClient` receives an `APIResponseSending` transport and injected
`AccessTokenProviding` dependency; app composition can use the existing
`APIClient`, and tests can inject a recording fake. Read calls send
bearer-authenticated GET requests with `Accept: application/json` and
`Cache-Control: no-store`. It also implements `RunRecordsUpdating`, but the
writer is a separate optional
`WireframeRemoteReadDependencies.runRecordsUpdater`; the default app entry does
not provide one, and no production host or token provider is composed here.
PATCH includes `Content-Type: application/json` and is never automatically
retried because a lost response can follow a committed version increment.
`RunRecordsLoader` exposes explicit list/detail loading, loaded, and
failure states, appends list pages in server order, stops cursor loops, and
ignores older completions after a newer list or detail generation begins.
`WireframeRemoteReadBridge` adds run reads and optional writes to the existing
dependency composition. It admits one edit at a time, checks account/screen/run
scope before applying responses, cancels in-flight work on navigation or
account change, and ignores late responses from the old scope. A late edit
response only refreshes the run list when that list is still active; it cannot
replace a different run detail currently on screen. Otherwise the list is
marked stale and reloads when the user returns to it. The reload applies only
to the activation generation and account that requested it.

Remote list rows and detail are rendered separately from `RunStore.records`.
A supplied updater reuses the detail's existing per-field pencil → edit →
complete inline control; no separate editor flow is introduced. A failed save
keeps its draft visible. `404` is shown without revealing whether a record is
missing, deleted, or owned by another member. On `409 VERSION_CONFLICT`, the
bridge fetches the current detail and keeps the draft. It treats the conflict
as completed only when the fetched field's UTF-16 code units exactly equal the
draft; canonically equivalent NFC/decomposed values remain conflicts so the
draft is not discarded. Otherwise the user must press complete again to apply
the draft against the refreshed version. A PATCH `404` retains the draft in the
current detail and marks the cached list stale; the list reloads on return or
retry, and a failed reload remains a retryable read failure. A detail-read
`404` also marks the list stale. Read-only compositions keep the existing
read-only detail. Deletion transport and confirmation are prepared separately
in [`BACKEND_RUN_RECORD_DELETE_PREPARATION.md`](BACKEND_RUN_RECORD_DELETE_PREPARATION.md).
A request failure remains an error with a retry action where supported; it
never becomes an empty successful list. The default app entry still injects no
remote loader. A caller must provide both the configured transport and an
authenticated token provider before real reads can be enabled. The UI-test
reader fixture is explicitly enabled by `-wire-run-records-fixture`; the
optional updater additionally requires `-wire-run-records-edit-fixture`. Both
use in-memory synthetic values.

The detail response includes stored GPS points, but this integration does not
request device location, render coordinates, submit tracks, upload files, or
send notifications. It shows point and pause counts only. No host, credential,
session refresh, live server write, or persistent remote cache was added.

## Verification and limits

- Swift package suite: 67/67 passed using request-capturing fake transport and
  `MockURLProtocol`. Run edit cases cover PATCH path/headers/body, per-field
  omission and empty-string clearing, explicit-null response decoding, Java
  UTF-16 length boundaries, 409 conflict, generic 404 and disabled write retry.
- Focused Xcode bridge/read regression: 10/10 passed on the existing iPhone 17 Pro
  simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). It covers
  read-only list/detail composition, one-field update, list/detail refresh,
  simultaneous-save blocking, conflict refresh and draft resubmission,
  navigation with a late response, account-scope isolation, a late A edit while
  B is active, `404` list invalidation and retry after a failed reload, and
  rejecting a late old-account list response. Title and memo conflict tests
  verify that canonically equivalent but code-unit-distinct server values do
  not close the draft editor. Result bundle:
  `/tmp/task12-run-edit-normalization-bridge.xcresult`.
- Focused Xcode UI regression: 4/4 passed on the same simulator. It covers the
  unchanged pencil → edit → complete flow, draft retention on conflict and
  service failure, title/memo saves, preserved run metrics, the existing
  read-only/list-failure path, and draft retention after a simulated `404`
  followed by list refresh. Each UI test used a unique
  `-wire-test-store-suite`; fixture reset stayed within that suite. Result
  bundle: `/tmp/task12-run-edit-normalization-ui.xcresult`.
- App build succeeded for the same simulator destination.
- No live backend request or server write was sent; no real credential or GPS
  capture was used. The app remains unwired to a production host or token
  provider.
  Full wireframe pixel and motion QA remains open.

## Follow-up

The future authenticated session/composition owner must supply the production
host and token provider and decide how server records coexist with local records
in the product flow. This preparation adds no live credential or production
composition.
