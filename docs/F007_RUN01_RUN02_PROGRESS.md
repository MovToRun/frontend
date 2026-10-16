# F-007 RUN01/RUN02 feature bundle

## Scope and starting point

- Frontend branch: `codex/f007-run01-run02-20261016`
- Base: PR #87 merge `bfb58efd7e10fe0c63612f826db455af1944af84`
- Backend contract reference: backend `main` at `8e922483e79df24c91e539a965ebc9ab375238c1`
- Existing R01/R02 wireframe, map camera behavior, panel motion, local record store, API client, and durable upload outbox were retained and connected. This bundle adds no redesign.

## Implemented

- General run sessions use CoreLocation after the OS location permission is granted. Valid samples are appended to the persisted run; samples are ignored while paused, outside the run window, or from before the active resumed segment. The map draws the saved trace in the existing Canvas wireframe.
- Pause and resume close/open moving segments and record pause intervals. A six-hour wall-clock limit includes pauses. It finishes at `startedAt + 21,600s`, including after a delayed app recovery, and points after that end time are discarded.
- A finished record and its location trace remain on-device when offline. The authenticated outbox stores the immutable payload and stable `clientRunId`, scopes it to the member who started the run, deduplicates identical enqueue requests, and replays the same body after an ambiguous transport failure. Startup recovery, network reconnection, and manual retry drain the outbox.
- The existing running map center/recenter and bottom-panel collapse/expand remain in use. The completion/detail screens show the route, local provisional distance/time, temporary splits, upload state, and retry affordance. Pending device measurements are not marked valid and do not enter server-valid statistics. Server acceptance of the POST does not replace the local record with a verdict; the separately fetched server record remains the verdict source.
- `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, and the location background mode are present for the background location capture path. No mapping SDK, map tiles, API host, or credentials were configured.

## Backend request contract

The added composition connects the existing `RunUploadClient` to the authenticated API client when both auth session dependencies and an API client are supplied. It sends the backend's `POST /api/v1/runs` body: `clientRunId`, `startedAt`, `endedAt`, integer `movingSeconds`, integer `distanceMeters`, optional title/memo, GPS `points`, and pause intervals. GPS timestamps retain fractional seconds in the request; all other timestamps use UTC ISO-8601 with fractional seconds. The backend accepts up to 21,600 points and a 5 MB body, accepts exactly six hours, associates the run to the authenticated principal, and treats same-member/same-key/same-measurement replay as idempotent. A changed payload with that key is a conflict. Offline uploads are accepted for 30 days; `RUN_IN_FUTURE` is retryable without rewriting the payload, while terminal `400`, `409`, and `413`, and deleted `410 RUN_DELETED` follow the existing uploader mapping.

No real API request was sent. UI tests used an in-memory fake sender; account credentials, host configuration, infrastructure, and deployment were not changed.

## Verification

Focused tests used only the already booted iPhone 17 Pro simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, with normal Xcode simulator signing and `-parallel-testing-enabled NO`. No simulator was created, erased, cloned, or rebooted. The fake UI run used a unique UserDefaults suite and an in-memory owner-record store, without Keychain access. Unit tests used a unique suite and a temporary directory for the local record/outbox files.

The GPS/upload regression covers fake location samples across start, pause, resume, and finish; excludes pause-period samples; offline persistence; a transport failure and retry; exact payload/client ID replay; duplicate enqueue; provisional-vs-valid statistics; and immutable route/pause data. A second test advances fake time across the six-hour wall limit. The UI flow covers start/pause/resume/finish/save, provisional detail and splits, upload error/retry, and retained route rendering. Existing map regression tests cover panel collapse/restore and map pan/recenter across regular, dark, and compact variants.

Result bundles:

- `/tmp/MovToRunF007-RUN01-RUN02-final.xcresult` — final source, including the delayed-GPS guard: 2 unit tests and 1 focused UI test passed.
- `/tmp/MovToRunF007-Viewport-regression.xcresult` — 2 existing map/panel UI regression tests passed.

Simulator installed-product file manifest had 49 entries before and after tests. The path set was unchanged; 8 digests changed as the test build and signing assets replaced the prior installed app. Manifest SHA-256: before `dba6d641629bb36c13f21efc50d602558b560bddf3978234ddc03c23367d4239`, after `cf287e384c3edcf23237b4a66b26a0532a31a9d81503e737504aefe55ee7eac7`.

Outdoor GPS reception and real-device background recording have not been validated. The simulator tests do not establish location permission prompt behavior, outdoor accuracy, or long-duration background reliability.

## Separate follow-up

PR #87's non-blocking issue remains unchanged: a failed send of the guidance `GET` is displayed as the `POST` outcome being unknown. Track that UI state/reporting correction separately; it is not part of this run-capture bundle.
