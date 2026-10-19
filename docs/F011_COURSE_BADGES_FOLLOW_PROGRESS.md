# F011 Course Badges and Follow Runs

## Scope and contract source

- Frontend base: `8ed435766ea4649a53ba428424a73a8d1028e0f9` (local `main` after PR #94).
- Backend contract was read directly from `de51d83a79a5d63f5d754c5c952001919a15b9b3`: `CourseCertificationController`, `CourseCertificationService.ApplicationView`, `CourseFollowSessionController`, `CourseFollowSessionService.SessionView` / `ComparisonView`, and `CourseShareService.CourseView`. The backend source was fetched read-only for inspection; no backend files or runtime were changed or called.
- Certification and follow endpoints remain behind the signed-in member API. Existing local wireframe fixtures remain available when the remote course service is unavailable.
- No credentials, deployment, infrastructure, schema, or database work was used. The product app `com.movtorun.mov`, its app data and Keychain, were not accessed, installed, removed, or opened. UI tests used only the existing iPhone 17 Pro simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`; no simulator was created, cloned, or reset.

## Implemented

- C10–C11 read and submit the signed-in member's certification request, validate HTTPS evidence URLs, withdraw pending requests, and recover accepted submissions after a lost response by fetching the current request instead of posting again. A fetched `WITHDRAWN` status now confirms a withdrawal whose `204` response was lost; a missing request (`404`) also remains a valid recovery result.
- C44–C45 load the service-operator pending queue and review details, paginate by the contract cursor, approve or reject pending applications, and surface 403/empty/error states. Crew manager roles do not grant service-operator access; the backend remains authoritative.
- C13 creates a private draft from the member's own current `VALID` server run. Users set start/end masks, review the saved draft, and provide explicit public consent before the second action publishes the course. Public course responses contain only the masked route and summary fields.
- C12 lists and opens published courses. C14 starts or resumes a route-version-pinned follow session, persists per-member/course/revision idempotency keys for the existing run upload ID, writes scalar-only bounded progress, and binds comparison to that same saved run. An unavailable/revised pinned course stops follow continuation.
- Follow-session decoding now mirrors the server `SessionView`: `sessionId`, `status`, `routeVersion`, `progressMeters`, `elapsedSeconds`, nullable `runId`, `courseAvailable`, `course`, and nullable `comparison`. The DTO no longer requires a top-level `courseId` or models client IDs the server does not return.
- The comparison endpoint's response is a `SessionView`; its `comparison` object uses `runId`, `validDistanceMeters`, `validSeconds`, `paceSecondsPerKm`, `distanceDeltaMeters`, `secondsDelta`, and `paceDeltaSecondsPerKm`. The client decodes that nested object, and the UI combines the saved course distance with the server's valid run values.
- Added the dedicated `MovUITestHost` Xcode scheme. Its build/test graph includes only `MovUITestHost`, `MovTests`, and `MovUITests`; it does not reference the product `Mov` target. The isolation verifier and focused test wrapper now require the host scheme's `.xctestrun` file and verify its resolved host paths before execution.

## Verified response contract

- `GET /course-certifications/me` maps a missing application to 404: `CourseCertificationController.own` delegates to `getOwn`, which throws `NOT_FOUND` when no application exists. `DELETE /course-certifications/me` returns 204 after the service sets the stored status to `WITHDRAWN` and deletes its evidence. A later GET can therefore return a `WITHDRAWN` application; the flow handles both that response and 404 as confirmed withdrawal after a lost DELETE response.
- Start, fetch, progress, and compare all return `CourseFollowSessionService.SessionView`. Comparison is nested in the returned session. Regression fixtures now use these exact controller response shapes and contain no invented top-level `courseId` or flat comparison fields.
- The isolated tests use local fixture transports only. API credentials and a live backend were not used; runtime status behavior was not exercised against a deployed service.
- Service-operator grants remain provisioned out-of-band. No operator credentials were used. The separate “my courses” management list and UI unpublish action are outside this slice.

## Verification

- Full SwiftPM suite: `234 passed, 0 failed` with `CLANG_MODULE_CACHE_PATH=/tmp/mov-f011-modulecache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/mov-f011-modulecache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox --build-path /tmp/mov-f011-swiftpm-build`. Swift and module caches were redirected to `/tmp` for the restricted workspace.
- `MovUITestHost` `build-for-testing`: succeeded on the existing iPhone 17 Pro simulator. `scripts/verify-ui-test-isolation.sh` passed and confirmed the absence of `Mov.app`, isolated host/runner/test bundle identifiers, resolved `TEST_HOST`, host-only test dependencies, and UUID-scoped fixtures.
- Focused isolated F011 Xcode run: `13 passed, 0 failed` (7 UI tests and 6 hosted flow tests), including lost certification-submit recovery, lost withdrawal-response recovery from `WITHDRAWN`, operator review, masked route display, pinned revision loss, and same-run comparison. Result bundle: `/tmp/mov-f011-contract-ui/RunFinal3/FocusedUITests.xcresult`.
- No live backend/API calls or simulator state reset/clone occurred. Full SwiftPM and focused UI/flow suites were run; matched-viewport wireframe/pixel/motion comparison remains outside this contract verification.

## Review state

Draft PR [#95](https://github.com/MovToRun/frontend/pull/95) remains open for independent final verification. Do not merge until the separate reviewer completes validation.
