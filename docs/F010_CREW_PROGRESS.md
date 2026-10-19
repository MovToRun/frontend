# F010 Crew API Integration

## Scope and source contracts

- Frontend base: `de2ab2995261966e848f744781087bdb7c3f2c46` (PR #90).
- F010 API/UI baseline: PR #91 merged as `0761feebc5dbd2a2f0570e8ac1b0eda3d4ef1c4d`; this follow-up adds only the existing crew-post edit/delete contract.
- Backend controllers and DTOs were inspected read-only at `f13d07609dac15ccc44fc3d277c7b78847972587` (`CrewController`, `CrewBoardController`, and their services).
- Normal app composition uses the active authenticated session. UI fixtures use an in-process fake `CrewServing` implementation; API contract tests use a local mock transport. No live API, credential, infrastructure, deployment, or database change was used.
- The installed product app `com.movtorun.mov` was not opened, installed, overwritten, or removed, and product data/Keychain were not accessed. Build attempts wrote only under `/tmp`; no simulator was created, cloned, or reset.

## Implemented

- `CrewClient` uses controller-backed routes for crew create/read, member read/role update/removal, owner rejoin-restriction read/release, ownership transfer, application submit/cancel/review, and crew board create/read/rename/archive/restore. Post list/detail/create/update/delete are connected. Post updates use `PATCH /crews/{crewId}/boards/{boardId}/posts/{postId}` with only `{title, content}` and validate the returned post ID and relationships; delete uses the same resource path with `DELETE` and requires `204`. Mutations with ambiguous results are not automatically repeated.
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

- Follow-up `swift test --disable-sandbox --package-path . --scratch-path /tmp/MovToRun-F010-PostEditDelete-SwiftPM/Build`: **213 passed, 0 failed**, including mock-transport route/body/response-ID tests for PATCH and DELETE. No live API was contacted. Swift syntax parsing also passed for all changed Swift source and test files.
- Historical PR #91 evidence remains separate: its earlier build and isolation gate passed, with 12 UI cases and 2 F010 client-contract cases passing on the same iPhone17Pro UDID. These earlier results do not cover the new edit/delete changes.
- This follow-up's Xcode `build-for-testing` did not complete: `/Applications/Xcode.app/Contents/Developer` reported `CoreSimulatorService connection became invalid`, no available simulator runtimes, and `actool` failed with “No available simulator runtimes for platform iphonesimulator.” No `.xctestrun` was generated, so the new build isolation gate and UI tests were not run. The same missing-runtime error also stopped an iOS device build before completion. The dedicated UI suite now selects 16 cases and 4 Xcode client-contract cases, including edit/delete, retry, cancel, permissions, and account-scope changes; none were executed in this environment.
- The existing simulator UDID was not available to Xcode during this attempt. No simulator was created, cloned, or reset. The installed product app, product data, and Keychain were not used.

## Remaining review

- The SwiftPM networking suite passed, but app target type-check/build completion, the new Xcode-hosted contract tests, and all 16 selected UI cases remain unverified until Xcode can see the existing simulator runtime. No live backend service was connected. Independent final verification and full matched-viewport pixel/motion QA remain separate. Keep this PR draft for that review; do not merge as part of F010 implementation.
