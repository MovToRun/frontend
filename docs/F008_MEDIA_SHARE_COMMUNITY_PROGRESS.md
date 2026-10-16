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
- Video upload stays fail-closed with the backend's documented 503/provider limitation.
- Xcode explicit project references include the two new networking clients. `Mov/Info.plist`, bundle identifiers, and test-host settings were not changed.

## Backend decisions still needed

- `MEDIA_S3_ENABLED` and `POST_ATTACHMENT_S3_ENABLED` default to false and require separate manual schema/configuration handoff. No storage adapter was enabled here.
- No standalone share-image generation/storage/public URL API exists. The implemented share image is generated and kept locally, and may be uploaded only as a post attachment.
- Profile-photo removal has no backend endpoint; the remote profile editor reports that limitation instead of claiming that a server photo was deleted.
- Keep deployment policy decisions open: D-06's S3 cost alert/lifecycle operations and any future share-image retention/template/URL policy. The implementation does not choose a budget, retention period, or public URL policy.

## Verification

- `swift test` under the Xcode toolchain, with a SwiftPM scratch/cache directory in `/tmp`: **176 tests passed, 0 failures**. This was the package's pure unit-test target; no Xcode host test or simulator test was run.
- A signing-disabled, install-free `xcodebuild` on a temporary `/tmp` checkout copy compiled the iOS app source successfully. Its asset-catalog resource phase was excluded only in that temporary copy because the host has no available iOS Simulator runtime; the `.app` remained in `/tmp` and was not installed. A normal project build reached `actool` and stopped with `No available simulator runtimes for platform iphonesimulator`.
- No simulator device was started, installed, created, copied, reset, or deleted. Build/test outputs and caches stayed under `/tmp`; the original `/Users/seunghwan/Documents/Mov` checkout and product data were not edited.

## Follow-up list

- Preserve PR87's known error-classification issue: a failed nonblocking notification `GET` can still be surfaced as an ambiguous POST result. It is not part of this change and must not be re-described as an actual POST result-unknown event.
- Re-run full asset-catalog packaging on a host with an already available iOS Simulator runtime, then perform the separately planned isolated UI review only after its test-host and UUID-suite isolation checks.
