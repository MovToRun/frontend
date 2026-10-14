# Community boards screen follow-up

## Finding

The Review55 wireframe mosaic's C02 board screen uses the shared community header: all-boards grid on the left, centered Mov mark, and search on the right. Its page content starts with the `게시판` heading, followed by `게시판 바로가기`, the four shortcuts, and recent posts.

The installed app before this change showed C02 with the standard back/title header (`뒤로` and centered `게시판`) and started the content at `게시판 바로가기`. That differed from the C02 wireframe and from the adjacent community feed screen. The change brings C02 onto the shared community header and adds the page heading while preserving its existing shortcuts and post list.

The header actions were checked against the existing routes: the grid opens C27 (전체 게시판), and search opens C29. C02 also observes the same scroll direction behavior as the community feed, hiding the community bar on downward scroll and restoring it on upward scroll.

## Evidence

- [C02 light mode](C02-light-boards.png)
- [C02 dark mode](C02-dark-boards.png)
- Reference: Review55 wireframe review, C02 panel in the community mosaic (`https://running-wireframe-review-01.popeye0618.chatgpt.site/`). The interactive review state was blocked by its unsaved-state prompt, so the existing C02 mosaic panel was used for the visual comparison.

The captures show the safe-area status bar, shared header with a centered brand mark, the page title and shortcuts, and all five community navigation items with the center Home item retained.

## Verification

- Base used: `b3f4b37d18efcc162bb8c83b852e52752a9eb7a0`, tree `cabb21085af5a45ac751e8f3f928a1bffacfb4a6` (PR67's verified merge to main).
- App bundle/version: `com.movtorun.mov`, version `1.0` (build `1`).
- Device: existing iPhone 17 Pro simulator, UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`.
- UI tests passed: `testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile`, `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`, and `testCommunityBoardRouteAndLocalPostPreviewPublish`. The board-route test was rerun after adding C02 scroll hide/restore assertions; it passed again.
- The run covered the light and dark C02 layouts, repeated community tab navigation, C02 → C27 → C02 and C02 → C29 → C02 routes, downward/upward C02 scrolling, and existing local post preview/publish flow.
- No simulator was created, cloned, reset, or deleted. No backend, credentials, or deployment were used.

## Revision

This follow-up is based on the exact verified main commit/tree above. The draft PR description records the final head commit and tree for this evidence set.
