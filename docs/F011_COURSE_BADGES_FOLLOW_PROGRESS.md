# F011 Course Badges and Follow Runs

## Scope and contract source

- Frontend base: `8ed435766ea4649a53ba428424a73a8d1028e0f9` (local `main` after PR #94).
- Backend contract read-only reference: `de51d83a79a5d63f5d754c5c952001919a15b9b3`, `docs/API_CONTRACT.md` (BE-COURSE-01/02, DEC-096/097). No backend source or runtime was modified or called.
- This slice connects C10–C14 and the operations-only C44–C45 review screens to the course-certification, masked-course, and follow-session endpoints documented by the backend. Existing wireframe fixtures remain usable when the remote course service is unavailable.
- No credentials, deployment, infrastructure, schema, or database work was used. The product app `com.movtorun.mov` was not installed, removed, or opened. UI tests used the existing iPhone 17 Pro simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B` only, through `MovUITestHost`; no simulator was created, cloned, or reset.

## Implemented

- C10–C11 read and submit the signed-in member's certification request, validate HTTPS evidence URLs, withdraw pending requests, and recover an accepted submission after a lost response by fetching the current request rather than posting again. Account changes discard stale responses and form contents.
- C44–C45 load the service-operator pending queue and review details, paginate by the contract cursor, approve or reject pending applications, and surface 403/empty/error states. Crew manager roles do not grant service-operator access; the backend remains authoritative.
- C13 creates a private draft from the member's own current `VALID` server run. Users set start/end masks, review the saved draft, and provide explicit public-consent before the second action publishes the course. Public course responses contain only the masked route and summary fields.
- C12 lists and opens published courses. C14 starts or resumes a route-version-pinned follow session, persists per-member/course/revision idempotency keys for the existing run upload ID, writes scalar-only bounded progress, and binds comparison to that same saved run. An unavailable/revised pinned course stops follow continuation.
- C10–C14 and C44–C45 retain the community-only bottom bar. Leaving a screen during an in-flight request does not redirect the user when the response arrives, and busy actions prevent repeated taps.
- A private draft creation result that becomes ambiguous is stored as a member/run marker and blocks another create for that pair after flow reconstruction. The backend contract has no draft lookup, creation idempotency key, or draft-cancel route, so creating a replacement after an unknown result would risk duplicate drafts.

## Contract boundaries and unresolved response details

- The backend API contract describes the member's current certification status but does not state the HTTP response for a member with no current application. The current client treats `GET /course-certifications/me` 404 as absence; a running backend or an explicit empty-state response contract is required to verify that mapping.
- The contract documents `DELETE /course-certifications/me` as withdrawing a pending request but does not name its success status. The client currently expects 204; this remains to confirm against the backend implementation/runtime.
- The contract lists course comparison semantics and run binding but not a complete JSON response schema for comparison. Current DTO field names are exercised with local mock responses and require confirmation against the backend response shape.
- There is no owner-course listing route in this contract. Draft creation/publish is connected; a separate “my courses” management list and UI unpublish action are not part of this slice.
- Service-operator grants are provisioned out-of-band. No real operator credentials were used. Review authorization was exercised through local fixtures and client 403 mapping.
- API status/error behavior and visual fidelity against the wireframe remain unverified against a live backend and a matched-viewport design review.

## Verification

- `swift test --filter CourseCommunityClientTests`: 6 passed, 0 failed. The cases cover certification request shape/HTTPS checks, operator pagination and decisions, masked course draft/publish, scalar follow progress, idempotency-key reuse, and validation/error mapping.
- Xcode `build-for-testing` uses `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, existing iPhone 17 Pro destination, and builds the isolated `MovUITestHost` + test runner. The isolation script checks the absence of a `Mov.app` test artifact and confirms the resolved host and fixtures.
- Final focused isolated Xcode run: 12 passed, 0 failed (7 UI tests and 5 hosted flow tests) using `scripts/run-isolated-ui-tests.sh` selection `f011-community-course` on the existing simulator, UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`. Result bundle: `/tmp/mov-f011-run-verified-20261019/FocusedUITests.xcresult`.
- Combined focused evidence: 18 passed, 0 failed (6 Swift package client tests, 5 hosted flow tests, 7 UI tests). UI cases cover in-flight navigation, duplicate request locking, submit/withdraw recovery, operator-only approval/rejection, empty/error states, masked route display, pinned revision loss, same-run follow comparison, explicit consent, and the community-only bottom bar.
- The isolation check passed before execution. Tests used local fixture servers/mock transport only; no live backend was called. The full suite, live API response mapping, and matched-viewport wireframe/pixel/motion comparison were not run.

## Review state

The implementation is submitted as a draft PR for independent final verification. Do not merge until the documented response-contract gaps are resolved or explicitly accepted and the separate reviewer completes validation.
