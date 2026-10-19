# F010 Crew API Integration

## Scope and source contracts

- Frontend base: `de2ab2995261966e848f744781087bdb7c3f2c46` (PR #90).
- F010 API/UI baseline: PR #91 merged as `0761feebc5dbd2a2f0570e8ac1b0eda3d4ef1c4d`; this follow-up adds only the existing crew-post edit/delete contract.
- Backend controllers and DTOs were inspected read-only at `f13d07609dac15ccc44fc3d277c7b78847972587` (`CrewController`, `CrewBoardController`, and their services).
- Normal app composition uses the active authenticated session. UI fixtures use an in-process fake `CrewServing` implementation; API contract tests use a local mock transport. No live API, credential, infrastructure, deployment, or database change was used.
- The installed product app `com.movtorun.mov` was not opened, installed, overwritten, or removed, and product data/Keychain were not accessed. Build attempts wrote only under `/tmp`; no simulator was created, cloned, or reset.

## Implemented

- `CrewClient` uses controller-backed routes for crew create/read, member read/role update/removal, owner rejoin-restriction read/release, ownership transfer, application submit/cancel/review, and crew board create/read/rename/archive/restore. Post list/detail/create/update/delete are connected. Post updates use `PATCH /crews/{crewId}/boards/{boardId}/posts/{postId}` with only `{title, content}` and validate the returned post ID and relationships; delete uses the same resource path with `DELETE` and requires `204`. Unexpected 2xx statuses on edit/delete are treated as unknown outcomes, so the UI will not offer an explicit retry that could duplicate a mutation.
- C15 reads `/crews/me` and the first public recruitment feed page. Its local search filters only the returned 20 posts. The create action enters C20 and posts only the supported name, introduction, and join-guide fields; local photo, region, and grade fields are not sent.
- C16/C17/C18 and C21/C22/C40 continue to show server-backed crew detail, application submit/cancel, pending review, and approve/reject. The backend remains the authority for capacity, membership, and roles. A 403 is surfaced and does not reveal a manager queue.
- C19 reads active boards and posts, opens post detail, creates and edits an author's post, and deletes an author's post or a post a crew owner/operator may moderate. Recruitment-board post creation/editing is owner/operator-only; an owner/operator still cannot edit a different author's post. An author may delete their own post on either board kind. Edit drafts confirm before discard; delete confirms before sending. Duplicate taps are locked, known failures can be retried explicitly, ambiguous results are blocked, and late responses cannot navigate into a different account or board. A successful edit updates the same post ID in detail and the board list; delete removes that ID and returns to the board. C21 links to C34 member management and C37 board management. C34/C35 read members; owners can set/remove operator role and permitted managers can remove members. Owners can inspect and release rejoin restrictions. C37/C38 create internal boards, rename active boards, archive them without deleting posts, and restore archived boards subject to the backend's five-active-board limit.
- C32 displays only fields present in the crew DTO. The member DTO contains only member ID, role, and joined time, so C34/C35 label members by ID rather than inventing profile names. Crew edit, join-guide edit, warnings, and announcements have no matching route. Backend service policy allows post edits only by the author, with recruitment-board edits additionally requiring owner/operator; deletes are allowed to the author or crew moderator on either board kind. Manager status alone does not reveal an edit action for another member's post.
- C33 always explains that the backend has no current-member application-list route, both with and without rows. It shows pending applications submitted in the current app run only. The other confirmed API gap is general crew search/filter; C15's search is local and limited to the first recruitment page.
- Account-scope changes clear crew data and application state. Per-request IDs discard stale reads, including an old account's late `/crews/me` response. Busy controls prevent repeated writes; ambiguous create/decision/mutation outcomes block automatic repeats. Leaving a screen while a request is in flight does not force late navigation.
- The community-specific bottom navigation remains on the community root; nested/detail screens retain wireframe navigation behavior.

## Contract boundaries

- The backend has no general crew search/filter endpoint and no route to list the signed-in member's pending applications. Those are the two F010 API gaps. No such endpoints or policies were invented.
- `POST /crews` exists; there is no crew-update route. F010 connects creation only; the separate wireframe edit/settings behavior is not represented as server-backed.
- The member DTO does not include a profile name. No cross-service profile lookup was introduced.
- C36 guidance editing and C39 announcements remain unconnected because the inspected backend controllers do not define those operations. Post edit/delete use the already existing backend routes; no new API, policy, or database change was introduced.

## Verification

- Follow-up Swift package suite, using Xcode 26.3 (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`) and a `/tmp` Clang module cache: **213 passed, 0 failed**, including mock-transport route/body/response-ID and unexpected-2xx mutation tests for PATCH and DELETE. No live API was contacted. Swift syntax parsing and `git diff --check` also passed for the changed source/test files.
- Historical PR #91 evidence remains separate: its earlier build and isolation gate passed, with 12 UI cases and 2 F010 client-contract cases passing on the same iPhone17Pro UDID. These earlier results do not cover the new edit/delete changes.
- Xcode 26.3 `build-for-testing` succeeded for `MovUITestHost`, `MovTests`, and `MovUITests`; it excluded `Mov.app`. The isolation gate confirmed the host, runner, test bundles, `TEST_HOST`, `.xctestrun` dependency paths, and UUID-scoped fixtures before every test run.
- The isolated Xcode run on the existing iPhone17Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B` passed **16 UI tests and 4 Xcode-hosted contract tests, 0 failures**. It covers request-in-flight navigation, application cancel and queue permissions, author/moderator post permissions, exact TextEditor replacement, delete confirmation cancel/retry, conflict retry, account changes, and community navigation. Result bundle: `/tmp/MovToRun-PR92-Fix-20261019-Run2/FocusedUITests.xcresult`.
- No simulator was created, cloned, or reset. Tests ran inside the separate `local.mov.prototype.MovUITestHost` host and UUID-scoped fixtures. The installed product app `com.movtorun.mov`, its data container, and product Keychain were not targeted; no live API was contacted.

## Remaining review

- Independent final verification and full matched-viewport pixel/motion QA remain separate from this implementation run. No live backend service was connected. Keep this PR draft for that review; do not merge as part of F010 implementation.
