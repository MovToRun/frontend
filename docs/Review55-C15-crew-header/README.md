# Review55 C15 crew header

## Comparison

The Review55 C15 wireframe places the Mov mark at the horizontal center of the shared community header, with search on the right. Below it are the crew title and a compact “크루 만들기” action above the crew tabs. The materialized reference implements a centered logo with an absolute center anchor and a 44pt minimum-height text action.

This change aligns C15 with the wireframe while keeping the existing crew tabs, fixture content, five-item community bar, and centered Mov home destination.

| State | Evidence |
| --- | --- |
| Before | [C15-light-crew.png](../F003-community-header-evidence/C15-light-crew.png) |
| After, light | [C15-light-after.png](C15-light-after.png) |
| After, dark | [C15-dark-after.png](C15-dark-after.png) |
| After, compact width and accessibility text | [C15-compact-large-after.png](C15-compact-large-after.png) |

All three after screenshots were captured by the final focused UI run on the existing iPhone 17 Pro simulator (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). They show the centered Mov mark, search on the right, and the selected Crew item in the five-item bar. The compact screenshot uses a 320×568 review frame and accessibility text size; its create action remains separate from the title and opens C20 when tapped. Test launches used unique fixture defaults suites.

## Profile comparison note

Review55 C08 omits a centered “내 정보” title in the shared header; the installed app shows one. That difference is recorded for a separate follow-up.

## Build and test evidence

- `git diff --check` passed.
- The final serial `xcodebuild test` run passed all four selected tests: `testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile`, `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`, `testCommunityCrewHeaderAndCreateTargetAtCompactLargeText`, and `testCommunityCrewCreateAndEditEntryStaysLocal`.
- The compact/large-text test checks the mark's center against the app frame, separation from search, no intersection between the crew title and create action, a 44pt minimum touch target (with 0.01pt accessibility-frame rounding tolerance), and the actual C20 route after tapping.
- Final result bundle: `/tmp/MovToRun-PR69-C15-CenteredHeader-Final.xcresult`; full log: `/tmp/MovToRun-PR69-C15-CenteredHeader-Final.log`. The initial run and its subpixel assertion result remain preserved at `/tmp/MovToRun-PR69-C15-CenteredHeader.xcresult`; the focused retest is at `/tmp/MovToRun-PR69-C15-CenteredHeader-LargeText.xcresult`.

An earlier install/data-container snapshot found that the install changed the app data-container identifier. Before and after snapshots contained 1,781 and 1,784 regular files. 1,779 existing path/checksum pairs matched exactly; the two missing paths were OS SplashBoard snapshots. Three added preference files belonged to isolated test suites. The standard `com.movtorun.mov` preferences file retained the same SHA-256, and the canonical owned-run-record sidecar was absent in both snapshots. The current focused test runs use unique fixture suites and did not erase simulator data.

Independent verification remains pending. This is a focused C15 correction, not completion of the full F002/F003 community scope.
