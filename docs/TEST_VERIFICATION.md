# Test verification history

## Community discovery and HOT feed (C29, C41)

- Branch: `feature/community-feed-discovery`, based on merged PR #36 main SHA `3d52e241e3010cfadc4c461707c8b416ed9ea730`.
- Clean build and unit suite: 72/72 unit tests passed on the existing iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). Focused C29/C41 UI suite: 3/3 passed on the same simulator. Both used a temporary source copy with unique app/unit/UI bundle identifiers and fixture-only storage.
- UI coverage: C01 search entry → C29 query groups → C04 post detail → search return; C29 → C07 profile preview → query return; C29 → C16 crew intro → query return; all-empty search results; C01 → C41 → C04 and back; empty HOT preview/list; and anonymous-post exclusion from public feed, HOT, and search while anonymous detail and block-list masking stay intact.
- Policy coverage: trimmed NFC normalization and Korean-locale case-insensitive matching, blank-query safety, public-only post search, blocked-profile/crew-owner exclusion, anonymous/crew-only visibility filtering, and explicit HOT flags retaining input order with no score/fallback.
- Result bundles: `/tmp/mov-community-discovery.rLTh71/CommunityDiscovery-focused.xcresult` (3 passed, 0 failed, 0 skipped); `/tmp/mov-community-discovery.rLTh71/CommunityDiscovery-final3.xcresult` (72 unit tests passed; broad UI run subsequently reported an unrelated auth test failure and was stopped while an unrelated UI case was in progress).
- At the time of this C29/C41 run, `testAuthenticationConsentAndProviderProtection` failed because it expected a `홈으로` control after signup, while the completion screen exposes `시작하기` and has already routed to H00. The same isolated failure reproduced with the merged-main Swift sources and unchanged test method (`/tmp/mov-community-baseline-check/AuthBaseline.xcresult`), confirming baseline behavior rather than a discovery regression. The follow-up in the next section resolves the stale selector and passes the test.
- The reference `community-model.js` defines HOT as the public feed filtered by its existing `hot` marker and does not compute a rank. The local screen follows that fixture-only policy; live search and popularity aggregation remain unconnected. This run verifies functional flows, not source/app pixel or motion parity; full visual QA remains open.

## Authentication success action and UI-test maintenance

- Branch: `feature/fix-auth-success-accessibility`, based on merged PR #37 main SHA `78f84e1f3e87f27b8b0da1ccc1e4a6e07ea75c47`.
- Draft PR: #38.
- A15's existing `시작하기` button now has the stable accessibility ID `signupCompletionStart`; its visible copy and route to H00 are unchanged. The regression uses the ID and separately asserts the visible label.
- Updated stale auth-test expectations to the current empty-email copy, made password entry replace any existing value, and aligned the ordinary user reset test with the actual `reset-email` field and fixture-only code visibility. Ordinary user flow covers reset entry/cancel/back; complete reset, code resend, password policy, and return-to-login are covered in the dedicated fixture-backed reset UI tests.
- Verification: 80/80 passed (72 unit tests + 8 focused auth UI tests, 0 failed, 0 skipped) on the existing iPhone 17 Pro, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). The temporary source copy used unique app, unit-test, and UI-test bundle IDs with isolated fixture storage.
- Result bundle: `/tmp/mov-auth-selector-fix/AuthRegression-final.xcresult`.
- The pre-existing Swift concurrency warning for the PhotosPicker sendable closure referencing main-actor profile data in `WireframeProfile.swift:156` remains a separate follow-up and is outside this test-maintenance patch. These functional tests do not constitute full source/app pixel or motion QA.

## Crew information and member application list (C32–C33)

- Branch: `feature/community-crew-info-applications`, based on merged PR #35 main SHA `b682c19f34eb9169e3121eb14ed92fa8a0e8a076`.
- Final focused suite: 69/69 passed (67 `ThemeTests` + 2 UI tests) on the existing iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). It used a temporary source copy with unique app/unit/UI bundle IDs and isolated fixture storage.
- UI coverage: `testCommunityCrewInformationUsesCurrentLocalPolicyAndRoutesFromDetailAndBoard` checks C16/C19 entry, current member/board policy values, join guidance and the unresolved level label; `testCommunityCrewApplicationListOpensStatusAndConfirmsLocalCancellation` checks current-user filtering, C18 round trip, dismissal without mutation, and confirmed local cancellation.
- Result bundle: `/tmp/mov-community-crew-info-suite.xcresult`.
- C32 shows `운영 기준 미정` because crew-level rules are unresolved; it does not infer a level. C33 cancellation only changes the in-memory fixture and does not contact or notify a server. These screens are locally implemented, server-unconnected, and still need source/app pixel and motion comparison.

## Crew settings and board lifecycle (C36–C40)

- Branch: `feature/community-crew-settings`, based on merged PR #34 main SHA `d0e7ddb95999306d7f000affd9d1d2777c6f1c21`.
- Clean isolated Xcode build: 70/70 passed (67 `ThemeTests`, 3 focused UI tests) on the already-booted iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). The temporary source copy used unique app/unit/UI test bundle identifiers; no user app data was reset.
- UI coverage: C36 guidance edit; C37/C38 board create, archive and restore against the active five-board limit; restored populated board post preservation; local C39 announcement display; C40 pending-application review round trip through C22; and existing member-management role flows.
- Policy unit coverage: archive/restore capacity, backend-compatible board name grapheme bounds and archived rename restriction, guidance/announcement length and manager access.
- Result bundle: `/tmp/mov-crew-settings-derived-final2/Logs/Test/Test-Mov-2026.10.11_03-09-26-+0900.xcresult`.
- All changes remain local fixtures. Announcements do not send push notifications, board archive preserves posts, and changes reset when the app process restarts. Full source/app pixel and motion QA remains open.

## PR #23 — launch screen and startup routing

- Tested commit: `f462a17319ca2417a8fd70d8f7e076159a87314d`
- Merged as: `29c8ee4aafca8343580f4b71ed09e565f8b352f8`
- During verification, one run failed while waiting for the Settings button.
- The affected test was then rerun by itself and passed; it was also rerun in the combined suite and passed.
- Final verification status: passing after both reruns. The initial single failure is retained here as test history.

The Settings-button wait failure was transient; it did not remain as a failing test after the isolated and combined reruns.

## Records UI follow-up

- Target: iPhone 17 Pro simulator, iOS 26.3.1.
- Focused run: 1 unit test and 5 UI tests passed, covering legacy local record decoding, L02/L03 empty/error distinction, L05 invalid split copy and exclusion reason, chart touch selection, compact dark viewport, and record edit/delete regression. The no-average label follows the user-confirmed `0:00 /km` placeholder rule.
- The L05 valid chart test was rerun with the source's 390×790 review viewport and passed. Its screenshot was compared with the local source render for static layout and content. The no-average display intentionally follows the user's confirmed `0:00 /km` rule, overriding the source's dash placeholder. Motion and comprehensive pixel QA remain open.
- The independent title/memo edit-and-discard UI test was also rerun alone and passed.

## Community feed-to-post slice

- Branch: `feature/community-feed-posts`, based on merged PR #24 tree `f13ec45c3359e6ba08563ada03487b8307887ae9`.
- One iPhone 17 Pro simulator, iOS 26.3.1: 2 focused UI tests passed together.
- `testCommunityFeedOpensPostAndAddsLocalComment` covers C01 → C04, local like count, comment entry, and updated comment count.
- `testCommunityBoardRouteAndLocalPostPreviewPublish` covers C01 → C02 → C27 → C03 and C03 → C05 → C09 → C01, including preserving the selected board and local post appearance.
- The tests launch with `-wire-fixture`; community examples, likes, comments, and new posts remain in WireState memory and do not alter saved profile or running records.
- The original ZIP's community review/model/CSS/markup and `riverside-morning.webp` were consulted. The image was converted to JPEG for the asset catalog. This was not a full rendered source/app pixel or motion comparison; that remains open.

### PR #25 interaction and view-count correction

- One iPhone 17 Pro simulator: `testCommunityViewCountPolicyUsesMemberPostAndKSTDayAndSkipsAuthor` passed, covering KST midnight rollover, per-member/per-post de-duplication, own-post exclusion, and 60/2,000/300 character limit functions.
- UI regressions cover feed-photo and blank-card-area detail navigation, detail photo zoom/close, first-vs-repeat detail view increments, empty-action disabled states, 61/2,001/301-character input attempts, and draft preservation after backing out of preview.
- The view count remains a review-only in-memory provider. The server remains authoritative; list and preview rendering do not record views.

### PR #38 independent verification outcome

- Independently reviewed PR #38 head `be503b0d8170cde6733a782cecc9c8848eff7862` (tree `31ce66f184f14b1ce7886d974c7f3c730613388e`) on the existing iPhone 17 Pro / iOS 26.3.1, using a temporary source copy, unique app/test bundle identifiers and isolated fixture storage.
- Unit suite: 72/72 passed.
- Focused authentication UI run: 7/8 passed on the first run. `testPasswordResetCompleteFlowAndPasswordPolicy()` failed at the A13 password guidance copy assertion; that same test passed when rerun alone. The independent report did not record a clean combined rerun, so this remains an initial-run failure followed by an isolated pass.
- This is separate from the author’s 80/80 report in the PR #38 implementation entry above. The independent run did not merge the PR. Full UI and pixel/motion QA remain open.

## Community notifications (C24)

- Branch: `feature/community-notifications-c24`, based on merged PR #38 main SHA `043cd0498b8783df47bc13dc22f73de15cb7a511`.
- Final focused run: 75/75 passed (70 `ThemeTests` + 5 focused UI tests, 0 failed, 0 skipped) on the existing iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). It used a temporary source copy, unique app/unit/UI bundle identifiers and isolated fixture storage.
- UI coverage: C08 notification entry/badge, C24 empty and read states, C01 feed, C04 post, C11 verification, C18 application and C19 crew-board destinations, back to C24/C08 context, and deleted-target handling. Existing N01 read/retry and profile regressions also passed.
- Community notifications are session-local examples. Verification submission, crew application and crew announcement actions append local rows; read state and notifications reset when the process restarts. No push or server notification is sent. C01 keeps its existing search action and has no notification bell.
- Result bundle: `/tmp/mov-c24-verified-20261010.xcresult`. The original C24 row/title/body spacing was used as the layout reference; full source/app pixel and motion QA remains open.
- Compact 320 pt dark appearance is exercised by the feed/photo/detail-image UI test. Full pixel/motion QA is not part of this correction.

### Community nested comment replies

- Base tree: merged PR #25 (`0488ef30e17085ec7b1a820b0f7b6dcfa8b1478a`).
- One existing iPhone 17 Pro simulator: the focused reply-policy unit test and nested-reply UI test passed; the pre-existing local comment-add UI test also passed on rerun.
- Coverage: three-level reply chain, parent quote/connector accessibility node, author-only local deletion marker, and preserved descendants after deletion. All data remains in WireState memory.
- `git diff --check` passed. Full pixel/motion QA remains open.
- PR #26 follow-up regression: deleting a comment clears display name and member ID, while nested replies stay attached; tombstone row/quote expose only the deletion marker. The post-author badge is based on stable member ID and is hidden for tombstones.

### Community runner profile slice

- Focused iPhone 17 Pro / iOS 26.3.1 run passed 3/3: `testCommunityFollowProviderUpdatesFollowerAndFollowingCounts`, `testCommunityProfilePreviewVisitPhotoFollowAndProfileContent`, and `testCommunityOwnProfileEditsLocallyAndRendersRunningCard`.
- Coverage includes C07 card preview and its two actions, empty-photo zoom/close at C31, visiting C08, local follow/unfollow count updates, C30 navigation, and editing/saving the viewer's own running card.
- Follow edges use a local fixture provider; the viewer's profile uses the existing local profile store. No backend sync is included.
- C08's original report/block menu and screens C23/C42 remain follow-up work and are not marked complete. Pixel/motion QA is not included.

### PR #27 local profile discard confirmation

- iPhone 17 Pro / iOS 26.3.1: the focused snapshot unit test and three UI regressions passed (4/4 total).
- The draft comparison covers nickname, introduction, region, and profile photo, including reverting changed values to the saved state.
- UI coverage verifies cancel → continue editing preserves text, discard leaves the saved profile unchanged, unchanged drafts close without an alert, settings/tab navigation requests confirmation, and successful save closes without another prompt.
- `go` and `back` both guard profile-edit exits; root tab switching preserves its pending destination until confirmation. `git diff --check` passed.

### Community report and block management

- iPhone 17 Pro simulator: 2 unit tests and 2 UI tests passed on the focused run.
- Unit coverage checks all four report reasons, optional details through 300 characters, rejection above the limit, self/unknown/duplicate block rejection, anonymous-block identity masking, symmetric content hiding, and visibility restoration after unblock.
- UI coverage follows post detail → report → receipt/block prompt and post detail → block → C28 → C42 → unblock → feed restoration.
- The report and block provider stores local in-memory fixture state only. No report is sent to a service. C28 exposes the blocked-user management entry for this slice; other community settings remain outside this implementation.
- `git diff --check` passed. Independent verification and full pixel/motion QA remain pending.
