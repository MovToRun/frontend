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
