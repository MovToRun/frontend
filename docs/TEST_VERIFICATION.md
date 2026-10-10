# Test verification history

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
