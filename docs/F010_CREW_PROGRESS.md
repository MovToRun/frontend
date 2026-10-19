# F010 Crew API Integration

## Scope and source contracts

- Frontend base: `8d98039fb5345bc35f827f837ec061052bb152c1` (current `main`, after the PR #90 baseline and merged PR #92 post-edit/delete work).
- Backend main reference supplied for this task: `f13d07609dac15ccc44fc3d277c7b78847972587`. The read-only BE117 contract snapshot inspected for the controller/service routes was `de51d83a79a5d63f5d754c5c952001919a15b9b3`. The confirmed contract exposes `GET /crews` with `q/cursor/size`, `GET /crews/me/applications` with `cursor/size`, `DELETE /crews/{crewId}/applications/{applicationId}`, and `PUT /crews/{crewId}` with `{name,introduction,joinGuide}`.
- Search returns active crews, matches normalized query text in name or introduction, accepts a 1–50 page size and numeric keyset cursor, and limits the query to 30 graphemes. My applications returns only the signed-in member's PENDING applications, with `applicationId`, `crewId`, `crewName`, `note`, `grade`, `status`, `createdAt`, and `updatedAt`; it intentionally has no `memberId`. Crew update is allowed to OWNER/OPERATOR and returns the existing crew DTO. Server authorization and validation remain authoritative.
- There is no standalone guidance-only endpoint; C20 edits the persisted `joinGuide` field through the existing BE117 PUT. Region, level, photo, warning, and announcement endpoints are not part of this change. Region and level are not searchable or editable through BE117. No API or policy was invented.
- Normal app composition uses the active authenticated session. UI fixtures use an in-process fake `CrewServing`; API contract tests use a local mock transport. No live API, credentials, infrastructure, deployment, or database change was used.
- The installed product app `com.movtorun.mov` was not opened, installed, overwritten, or removed. No simulator was created, cloned, or reset. UI execution is restricted to existing iPhone17Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B` inside the isolated test host; the product app data and Keychain are outside the test host.

## Implemented

- C15 keeps the my-crews view and replaces local recruitment-post filtering with the BE117 server crew directory. Search is debounced, limited to 30 graphemes in the UI, and searches only name/introduction. Cursor pagination deduplicates crew IDs and stops repeated cursors. Latest-query and account-scope request IDs discard delayed stale results.
- C16–C18 load persistent pending applications from the signed-in member route, submit an application, show its server status, and cancel it through the confirmed DELETE route. C33 reads the same server list across app runs, handles empty/loading/error states, paginates with duplicate-ID and cursor-loop protection, and removes a row only after successful cancellation. Failed known outcomes remain available for explicit retry; duplicate taps are locked and ambiguous mutation results remain blocked.
- C32 now exposes “정보 수정” only to an OWNER or OPERATOR. C20 reuses the existing form to edit name, introduction, and join guide through BE117's PUT replacement request. Optional values are sent as explicit JSON nulls when cleared. Validation and failures preserve the draft. A clean exit returns without a prompt; a changed draft uses the existing discard confirmation, restores the snapshot when discarded, and sends no request. A successful update refreshes the selected crew and my-crews row.
- Existing C21/C22/C40 approval and rejection, C34/C35 member permissions, and C19 board/post behavior remain on the previously confirmed routes. The community-only bottom bar remains on community root screens and is absent from nested application/detail screens.

## Contract boundaries

- Search is server-backed by crew name/introduction only. Region/level filters are not supported by this contract; recruitment-post title/content are not part of this search.
- Application summary responses do not expose `memberId`; the UI uses the returned crew name and application metadata. The backend restricts the page to the authenticated member and PENDING status.
- Crew information update is full replacement with `{name,introduction,joinGuide}`. It does not change status, region, level, photo, or membership. OWNER/OPERATOR visibility in the UI is only a usability guard; backend authorization remains required.
- The separate C36 guidance-settings screen remains a local example, while its persisted `joinGuide` field is editable through C20's confirmed PUT. C39 announcements have no matching route and remain a local example. Member profile names remain unavailable in the member DTO and are shown as IDs.

## Verification

- `swift test`: 218 passed, 0 failures. Regression coverage exercises unexpected 2xx responses across all 16 crew write operations and malformed success bodies across all 9 decoded write operations; each asserts one request only. Application cancellation accepts the confirmed 200 response.
- Xcode `build-for-testing` succeeded with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The build contains `MovUITestHost`, `MovTests`, and `MovUITests`; it does not embed `Mov.app`.
- `scripts/verify-ui-test-isolation.sh` passed immediately before the final run: no product app test artifact or `DependentProductPaths` reference, and the test host, runner, `TEST_HOST`, and UUID-scoped fixtures were verified.
- Final isolated Xcode result: 24 passed, 0 failed (20 UI tests and 4 hosted contract tests) on the existing iPhone 17 Pro simulator, UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, iOS 26.3.1. Result bundle: `/tmp/MovToRun-F010-Unknown-Run-20261019-Final4/FocusedUITests.xcresult`.
- UI scenarios cover ambiguous application submit with duplicate retry blocked, slow-query cancellation, cursor pagination and duplicate rows, account-switch stale responses, pending application pagination/cancel/retry/reentry, manager approve/reject authorization, info-edit permission and dirty-draft discard, request-in-flight navigation, empty/error recovery, board/post flows, and the community-only bottom bar.
- All UI and contract verification used in-process fakes/local mock transport. No live backend was called. Pixel/motion comparison against the wireframe, and behavior against a running backend, remain unverified.

## Review state

Draft PR [#93](https://github.com/MovToRun/frontend/pull/93) is open on `codex/f010-be117-search-applications-info-20261019`. It is not merged. A separate final verification and review remain required before merge.
