# F003 community header evidence

## Header and route captures

`C01-light-header.png` and `C01-dark-header.png` were exported from the focused iPhone 17 Pro UI run on simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`. They show the C01 header with the all-boards action at left, the Mov mark centered, search at right, and no feed title or settings gear. The same run passed the dedicated-tab navigation test, which checked the safe-area position, header action separation, all-boards and search routes, C08 profile settings, C06 liked posts, and the central H00 home tab.

The first focused batch passed 4 of 5 UI tests:

- Passed: `testCommunityDedicatedNavigationKeepsHomeCenteredAndSettingsOnProfile`
- Passed: `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`
- Passed: `testCommunityBoardRouteAndLocalPostPreviewPublish`
- Passed: `testCommunitySettingsLikedPostsRespectLikesAndBlockedMembers`
- Failed: `testCommunityNotificationProfileEntryRoutesAndBackContext`

The notification test reached C01 from C24 but did not return to C24 after tapping the notification-context back control. The captured accessibility frame for the custom chevron was only its thin stroke. The header now gives that control a 44×44 hit shape and uses one leading button for the two route contexts.

After that change, focused retests failed before reaching C01 because the candidate app process terminated with `SIGSEGV` while SwiftUI copied a `StrokeShapeView` during `WireframeRoot.rootLayers` construction. The latest candidate build compiled, but the revised back action was not verified. The same iPhone 17 Pro simulator was updated to the previously verified PR66 build afterward; it was not reset, cloned, or deleted.

## Screens and prior scroll baseline

The C02, C08, C15, C28, C06, and H00 captures are from the same successful focused UI run. They document boards, own profile, crew, settings, liked posts, and the central home route.

`PR66-community-bar-hidden.png` and `PR66-community-bar-restored.png` are carried forward from the independent PR66 verification on the same simulator and UDID. They are reference evidence for the existing down-scroll hide and up-scroll restore behavior; F003 does not change the scroll or floating-action implementation.
