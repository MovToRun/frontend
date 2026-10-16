# F008 MEDIA01 / SHARE01 / COMM03

## Scope and source contracts

- Frontend base: `b5f67250c4fe607d5198e405f714a139594ad138` (PR #88 / F007).
- Backend contract checked at `main`: `8e922483e79df24c91e539a965ebc9ab375238c1`.
- No real API, S3, OAuth provider, account, credential, infrastructure, or deployment was used. Upload and community clients accept protocol fakes; the SwiftPM tests use in-memory request/response actors.
- Existing share workspace, image editor, drag/resize/color/date/time presentation, and local PNG export remain in place. The output screen adds a route to attach its selected PNG to a free-board draft.

## Implemented

- `MediaUploadClient` follows the upload-batch contract: authenticated batch creation and completion, unauthenticated signed HTTPS PUT with the ticket content type and exact length, READY receipt validation, profile-photo GET with `no-store`, and bounded one-time refresh for an expired signed URL or 24-hour batch.
- Media preflight uses the documented decimal MB limits and JPEG/PNG/MP4 signatures. Existing photo import converts within the documented 20 MB source and 5 MB post-output limits; profile crop produces a 1024 px JPEG within 2 MB. The UI surfaces permission errors, invalid/oversized input, picker cancellation, transfer cancellation, retryable failures, and expiry.
- `CommunityMediaClient` creates supported free, anonymous, and running-verification posts, updates existing remote posts, performs full-list attachment replacement with version-conflict reconciliation, reads JPEG/PNG bytes back, and decodes run-share-card data. A transport/decode-ambiguous post-create response is held as unknown and cannot be blindly replayed because the API has no create idempotency key.
- A generated share PNG is stored in the existing local draft attachment store, then uploaded as `POST_ATTACHMENT` and connected to the created post. The app reads the attached bytes back before reporting local publication complete. Existing local-only and crew flows remain available.
- Community publish now captures the authenticated member, remote account scope, draft session, and operation ID before sending. Upload and post clients are rebound to a member-bound token provider; account changes cancel the task, clear its temporary composer draft, and prevent late results from mutating the new account's screen.
- Each member has a durable pending-operation journal under Application Support, including draft text, attachment bytes, upload asset IDs, create phase, and any known post ID/version. The journal is written before the non-idempotent create POST. A restart with a known post ID resumes update/attachment verification without another create; an ambiguous create remains blocked to avoid duplicates.
- Any HTTP 5xx from a post-create request is treated as result-unknown and is not manually retryable. The existing API has no create idempotency key or reliable lookup contract, so the client preserves the operation instead of replaying it.
- Video upload stays fail-closed with the backend's documented 503/provider limitation.
- Xcode explicit project references include the networking clients and the durable operation store. `Mov/Info.plist` and product bundle ID `com.movtorun.mov` remain unchanged; unit/UI test runners now use the separate `MovUITestHost` app (`local.mov.prototype.MovUITestHost`).

## PR #89 follow-up hardening

- A C09 share-preview draft captures its authenticated member and remote account-scope ID when the composer starts. A scope change now resets community composer state from any screen, including preview, and publish checks the captured binding against both the active member and live auth snapshot before sending.
- Separate `WindowGroup` stores/services now share a process-wide, root-and-member keyed execution lease. Lease generations prevent stale scene cleanup from releasing a newer operation. The lease remains held through upload/create/attachment verification, and a durable compare-and-set writes `creatingPost` immediately before the non-idempotent create request.
- Successful operation cleanup writes a compact completion tombstone before deleting draft text and attachment bytes. A stale scene cannot recreate the same completed operation ID; a new operation ID can proceed normally.
- Unit and UI tests now depend on `MovUITestHost` instead of `Mov.app`. Its bundle ID is separate, while the product remains `com.movtorun.mov`. Fixed UI-test UserDefaults suites and fixture Keychain service names were changed to per-run UUID scopes. A fail-closed pre-test script checks the host/runner identities and suite/service patterns before an Xcode TestAction starts.

## Backend decisions still needed

- `MEDIA_S3_ENABLED` and `POST_ATTACHMENT_S3_ENABLED` default to false and require separate manual schema/configuration handoff. No storage adapter was enabled here.
- No standalone share-image generation/storage/public URL API exists. The implemented share image is generated and kept locally, and may be uploaded only as a post attachment.
- Profile-photo removal has no backend endpoint; the remote profile editor reports that limitation instead of claiming that a server photo was deleted.
- Add a create idempotency key or a reliable member-scoped lookup/reconciliation API before attempting automatic recovery from an ambiguous create. Until then, an unknown create intentionally cannot be retried, even if that leaves the user needing server-side support to resolve it.
- Keep deployment policy decisions open: D-06's S3 cost alert/lifecycle operations and any future share-image retention/template/URL policy. The implementation does not choose a budget, retention period, or public URL policy.

## Verification

- `swift test` under Xcode 26.3, with all SwiftPM scratch/module caches in `/tmp`: **191 tests passed, 0 failures**. Regressions cover draft member/scope binding, account switch/cancel/late create response, independent-store lease exclusion and generation safety, one create POST across two services, completed-operation replay rejection, 5xx as unknown, restart recovery, and journal persistence failures.
- Install-free, signing-disabled iOS-device-SDK Release builds of both the product app and separate `MovUITestHost` **passed** with derived data under `/tmp`. This also compiled the app asset catalog for the device SDK; neither app was installed or launched.
- `plutil -lint` accepted `Mov.xcodeproj/project.pbxproj` and `Mov/Info.plist`; the shared Xcode scheme parsed as XML. The product Info.plist has no diff, and its resolved product bundle ID remains `com.movtorun.mov`.
- The UI-test isolation script is installed as a TestAction preflight but was intentionally not run in this turn. No UI/host test, simulator launch, app install, or simulator-device mutation was performed. The preflight and suite/service isolation remain for independent review before focused UI work.
- No real API, S3, OAuth provider, account, credential, infrastructure, or deployment was used. The original `/Users/seunghwan/Documents/Mov` checkout and product data were not edited.

## Follow-up list

- Preserve PR87's separate error-classification follow-up: a failed nonblocking notification `GET` must not be surfaced as an ambiguous POST result; it does not establish that the post-create `POST` result is unknown.
- Independently review the isolated host and UUID suite/service preflight before focused UI review.
