# F003 community header evidence

## Baseline and cause

The iPhone 17 Pro simulator (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`) initially had `com.movtorun.mov` version `1.0` (build `1`). The bundle does not embed a Git SHA, so its version alone cannot identify the source revision. The source used for this review is the verified current `main`: commit `876a2debc72136b0aa897428f9ecde6e0cb4d383`, tree `46fa6fb1300e57d87869d069b15c93397c710e3e`. The earlier supplied `db35b93260fa1c769c5a1ce4c28a8a10aa5e8a64` resolves to tree `20043ea3b8bb7f74f3b1b6c7f9f9fb58f42e41d4` and is not the current `main` tree.

At that `main` revision, C01 used the generic root `WHeader` with the title “커뮤니티” and a search-plus-settings trailing group. The Review 55 C01 wireframe instead shows the all-boards grid at left, Mov centered, and search at right; community settings belong inside the own-profile screen. That mismatch accounts for the title/icon crowding and the misplaced settings action.

The dedicated five-item community bar and feed scroll hide/restore behavior were already present in PRs #65 and #66 at the verified `main` revision. The focused final run confirms those behaviors on the selected simulator. Because the installed app bundle has no source SHA, this review cannot prove whether an earlier `1.0` (build `1`) install contained those commits.

## Change

The C01 feed header now follows the existing C01 wireframe: a 44×44 all-boards action at left, the centered Mov mark, and search at right. When the feed is opened from C24 notifications, the left action becomes a 44×44 back control that returns to C24. The header keeps the existing safe-area canvas and divider. The view is a small standalone component to keep the root community view composition stable.

## Final simulator verification

`xcodebuild test` passed 6 of 6 selected UI tests on iPhone 17 Pro, iOS 26.3.1, using the existing simulator only. The run used a unique `-wire-test-store-suite` fixture and did not reset the simulator or re-enter the previous Korean IME test text.

- `testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile`: repeated transitions among feed, boards, crew, profile, likes in profile settings, and the central Mov home; C01 all-boards and search routes; no feed title/gear; safe-area and control hit targets.
- `testCommunityBottomBarHidesOnDownScrollAndFloatsMoveWithIt`: hides on downward scroll, restores on upward scroll, and keeps both floating actions aligned with the bar.
- `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`: dark appearance, all four community destinations, and short-screen layouts.
- `testCommunityCanvasFillsTopAndBottomSafeAreasInLightAndDark`: light and dark top/bottom safe-area fill.
- `testCommunityNotificationProfileEntryRoutesAndBackContext`: returns from the feed to the notification list at C24.
- `testCommunitySettingsLikedPostsRespectLikesAndBlockedMembers`: liked posts and block controls remain within C28 profile settings.

The full result bundle is `/tmp/MovToRun-F003-Final.xcresult`. Its attachments were exported into `/tmp/MovToRun-F003-Attachments`; the PNGs in this directory are from that final run. The older `PR66-community-bar-*` images remain only as historical reference captures.

## Captures

- `C01-light-header.png`, `C01-dark-header.png`: feed header and dedicated community tabs.
- `C01-light-safe-area.png`, `C01-dark-safe-area.png`: safe-area canvas in both appearances.
- `C01-bottom-bar-hidden-light.png`, `C01-bottom-bar-restored-light.png`: current down-scroll and up-scroll behavior.
- `C02-light-boards.png`, `C15-light-crew.png`, `C08-light-profile.png`: primary community destinations.
- `C28-light-settings.png`, `C06-light-liked-posts.png`: profile settings and its liked-posts destination.
- `H00-central-home.png`: center Mov tab returns to the home screen.
