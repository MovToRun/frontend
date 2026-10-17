# F010 Crew API Integration

## Scope and source contracts

- Frontend base: `de2ab2995261966e848f744781087bdb7c3f2c46` (PR #90).
- Backend controllers and DTOs were inspected read-only at `f13d07609dac15ccc44fc3d277c7b78847972587` (`CrewController`, `CrewBoardController`, and their services).
- Normal app composition uses the active authenticated session. UI tests use an in-process fake `CrewServing` implementation. No live API, credential, infrastructure, deployment, or database change was used.
- The installed product app `com.movtorun.mov` was not built, installed, overwritten, or removed. UI tests use only the existing iPhone17Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B` and isolated `MovUITestHost` fixtures.

## Implemented

- `CrewClient` uses controller-backed routes for crew create/read, member read/role update/removal, owner rejoin-restriction read/release, ownership transfer, application submit/cancel/review, and crew board create/read/rename/archive/restore. Post list/detail/create remain connected. Payloads and response IDs/relationships are checked; mutations with ambiguous results are not automatically repeated.
- C15 reads `/crews/me` and the first public recruitment feed page. Its local search filters only the returned 20 posts. The create action enters C20 and posts only the supported name, introduction, and join-guide fields; local photo, region, and grade fields are not sent.
- C16/C17/C18 and C21/C22/C40 continue to show server-backed crew detail, application submit/cancel, pending review, and approve/reject. The backend remains the authority for capacity, membership, and roles. A 403 is surfaced and does not reveal a manager queue.
- C19 reads active boards and posts, opens post detail, and creates a post. C21 links to C34 member management and C37 board management. C34/C35 read members; owners can set/remove operator role and permitted managers can remove members. Owners can inspect and release rejoin restrictions. C37/C38 create internal boards, rename active boards, archive them without deleting posts, and restore archived boards subject to the backend's five-active-board limit.
- C32 displays only fields present in the crew DTO. The member DTO contains only member ID, role, and joined time, so C34/C35 label members by ID rather than inventing profile names. Crew edit, join-guide edit, warnings, and announcements have no matching route. Backend main does define post edit/delete routes in `CrewBoardContentController`, but this PR does not connect them; they need follow-up implementation.
- C33 always explains that the backend has no current-member application-list route, both with and without rows. It shows pending applications submitted in the current app run only. The other confirmed API gap is general crew search/filter; C15's search is local and limited to the first recruitment page.
- Account-scope changes clear crew data and application state. Per-request IDs discard stale reads, including an old account's late `/crews/me` response. Busy controls prevent repeated writes; ambiguous create/decision/mutation outcomes block automatic repeats. Leaving a screen while a request is in flight does not force late navigation.
- The community-specific bottom navigation remains on the community root; nested/detail screens retain wireframe navigation behavior.

## Contract boundaries

- The backend has no general crew search/filter endpoint and no route to list the signed-in member's pending applications. Those are the two F010 API gaps. No such endpoints or policies were invented.
- `POST /crews` exists; there is no crew-update route. F010 connects creation only; the separate wireframe edit/settings behavior is not represented as server-backed.
- The member DTO does not include a profile name. No cross-service profile lookup was introduced.
- C36 guidance editing and C39 announcements remain unconnected because the inspected backend controllers do not define those operations. Post edit/delete routes do exist in backend main, but they are not connected by this F010 PR and need follow-up implementation.

## Verification

- Shared `Mov` scheme `build-for-testing`: passed on `/Applications/Xcode.app/Contents/Developer`. It built the isolated host, test bundles, and runner; it did not produce `Mov.app`.
- Selected UI regression suite: **12 passed, 0 failed** on iPhone17Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, through `scripts/run-isolated-ui-tests.sh`. It covers C33 notice with empty and pending rows, application submit/cancel, account switch with late prior-account data, crew creation and leaving during an in-flight write, member role/removal/restrictions, owner/moderator authorization and review, board create/rename/archive/restore and capacity, post navigation, read retry, community-only tab, and adjacent profile/community regressions. Result bundle: `/tmp/MovToRun-F010-FollowupUITestsFinal3/FocusedUITests.xcresult`.
- F010 client contract tests: **2 passed, 0 failed**. They assert the confirmed route/method/DTO payloads and reject an unsupported role or non-canonical ID before sending. Result bundle: `/tmp/MovToRun-F010-FollowupUnitTestsFinal/ContractUnitTests.xcresult`.
- Isolation preflight passed before both test runs: no `Mov.app` test artifact or product app dependency path; test host, runner, bundle plists, resolved host executable, and UUID-scoped fixtures were verified. The fixtures use no product app data or Keychain.
- Independent final verification also reported **211 SwiftPM tests, 12 UI tests, and 2 API-contract tests passed**, with build and isolation gates passing. These results do not mean the complete Xcode test suite or a live backend integration was run.
- The tested destination is the existing iPhone17Pro simulator UDID above. No simulator was created, cloned, or reset; product data and Keychain were not used by the fixture flow.

## Remaining review

- This is a focused 12-case UI suite plus the 2 new client-contract unit cases; the complete Xcode test suite was not run, and no live backend service was connected. Independent final verification and full matched-viewport pixel/motion QA remain separate. Keep the PR draft for that review; do not merge as part of F010 implementation.
