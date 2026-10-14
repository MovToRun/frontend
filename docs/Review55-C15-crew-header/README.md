# Review55 C15 crew header

## Comparison

The Review55 C15 wireframe places the Mov mark and search action in a shared community header, then shows the crew title and a compact “크루 만들기” action above the crew tabs. The installed app on main showed a back/title header and a large “새 크루 만들기” button below the crew list.

This change aligns C15 with the wireframe while keeping the existing crew tabs, fixture content, five-item community bar, and centered Mov home destination.

| State | Evidence |
| --- | --- |
| Before | [C15-light-crew.png](../F003-community-header-evidence/C15-light-crew.png) |
| After, light | [C15-light-after.png](C15-light-after.png) |
| After, dark | [C15-dark-after.png](C15-dark-after.png) |

The two after screenshots are from `com.movtorun.mov` 1.0 (1) on the existing iPhone 17 Pro simulator (iOS 26.3). Both show the header below the status safe area, separate logo/search targets, the title/action row, and the selected Crew item in the five-item bar. The dark screenshot used a test-only appearance launch argument and isolated defaults suite.

## Profile comparison note

Review55 C08 omits a centered “내 정보” title in the shared header; the installed app shows one. That difference is recorded for a separate follow-up.

## Build and test evidence

- The app target built successfully for the arm64 iOS Simulator architecture.
- `testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile` passed in 39.739 seconds. It checks repeated community tab switches, the C15 search route and return, the centered home tab, and the profile settings and liked-posts route.
- `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar` started but did not finish. The temporary filesystem ran out of space while Xcode was writing simulator test results; its result bundle was incomplete. The C15 dark screen was then launched with an isolated fixture suite and visually captured above. This is not a passing result for that test.
- `git diff --check` passed.

The install changed the app data-container identifier. Before and after snapshots contained 1,781 and 1,784 regular files. 1,779 existing path/checksum pairs matched exactly; the two missing paths were OS SplashBoard snapshots. Three added preference files belong to isolated test suites. The standard `com.movtorun.mov` preferences file retained the same SHA-256, and the canonical owned-run-record sidecar was absent in both snapshots. The previous container directory no longer exists.

Independent verification remains pending. This is a focused C15 correction, not completion of the full F002/F003 community scope.
