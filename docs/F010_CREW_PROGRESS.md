# F010 Crew API Integration

## Scope and source contracts

- Frontend base: `de2ab2995261966e848f744781087bdb7c3f2c46` (PR #90).
- Backend contract inspected read-only at `f13d07609dac15ccc44fc3d277c7b78847972587`.
- Existing wireframe screens remain the design basis. Normal app composition binds the crew service to the current authenticated session. Debug UI tests inject an in-process fake `CrewServing` implementation.
- No live API, user account, credential, infrastructure, deployment, or database change was used. The installed `com.movtorun.mov` product app was not built, installed, overwritten, or removed.

## Implemented

- `CrewClient` follows confirmed paths for `GET /crews/me`, crew detail, public recruitment posts, application create/cancel, manager pending-application read and approve/reject, crew board/post list/detail/create. Requests use the active bearer token and `Cache-Control: no-store`; response IDs, roles, and payload relationships are validated.
- C15 lists the authenticated member's crews and searches the first public recruitment-feed page in memory by crew/post text. Selecting a recruitment post opens C16. C16 displays contract-backed crew information and only offers actions allowed by the returned role/status/capacity. C17/C18 provide application submit, status, and confirmed cancellation; C33 shows pending applications submitted during the current in-memory app run.
- C21/C40 load the manager queue and C22 posts approve/reject decisions. The UI gates management actions from the server-provided role, and a forbidden API response is shown without exposing the queue. The server remains authoritative for permissions.
- C32 displays only crew fields actually present in the API response. C19 loads active boards and posts, opens post detail, and creates a post.
- Account-scope changes clear crew data and application state. Per-request IDs discard stale reads. Busy controls prevent repeated writes; ambiguous create/decision outcomes are not retried automatically and remain blocked. Leaving an application/review screen does not make a late response force navigation.
- The community-specific bottom navigation remains on C15; the nested/detail flows use the existing wireframe navigation behavior.

## Contract boundaries and remaining decisions

- There is no crew-search endpoint. C15's recruitment search is a local filter over the first 20 public feed items; it does not implement region, level, or multi-page search. A backend search/filter contract is needed for those capabilities.
- There is no endpoint to list the current member's pending applications. C33 therefore only displays submissions made during the current app run; previously submitted applications cannot be recovered after relaunch or account-scope reset. A member-scoped application-list/status endpoint is needed to complete cross-session C33 and reliable reconciliation after an ambiguous create/cancel.
- The crew DTO has no region, rank/level, or owner name/ID. C32 intentionally omits those values rather than inventing them. The app does not infer a manager from a local fixture in normal mode.
- Crew create/edit and settings/member/board-management flows remain local because the checked backend contract does not provide those operations. No notification is fabricated. C19 supports only the post operations the contract exposes; edit/delete and board-management APIs are not inferred.
- No unapproved eligibility, retry, or 24-hour rejection-cooldown policy was added in the client. The backend's documented error response is surfaced as returned.

## Verification

- Swift package tests: **211 passed, 0 failures**. Coverage includes API paths/headers, auth scope changes during an in-flight read, explicit read retry, write ambiguity/no duplicate retry, application lifecycle, manager 403, and board/post contract requests.
- `Mov` shared-scheme `build-for-testing`: **passed**. The actual build-for-testing products include the isolated `MovUITestHost`, unit/UI test bundles, and runner; they contain no `Mov.app` artifact. `scripts/verify-ui-test-isolation.sh` passed immediately before the focused UI run.
- Focused isolated UI suite on existing iPhone17Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`: **9 passed, 0 failures**. Cases cover application search/submit/cancel/empty state and community tabs, manager approval/rejection and member 403, in-flight double tap/back navigation plus board/post create, explicit read-error retry, and five existing community/profile regressions. Result bundle: `/tmp/MovToRun-F010-VerifiedUITests5/FocusedUITests.xcresult`.
- The wrapper created separate test-run DerivedData and `.xcresult` paths. Its preflight verified host/runner/test bundle IDs and dependencies, UUID-scoped test stores, and absence of the product app immediately before execution.
- Product and user data were not touched; no simulator was created, cloned, or reset.

## Scope deferred from F010

F010 connects the supported read/write contract as a coherent crew slice. It does not mark every C15–C40 wireframe as server-backed or complete the full community feature set. Cross-session applications, full crew discovery, owner/region/rank presentation, crew management mutations, moderation, notifications, and full pixel/motion comparison remain open as described above or in the broader implementation plan.
