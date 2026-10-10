# Test verification history

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
