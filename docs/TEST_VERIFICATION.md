# Test verification history

## Wireframe profile and points read-state injection

- Branch: `feature/wireframe-read-injection`, based on merged main
  `05fdb5c845caaa8cbeb9d9a195678b291bbb58be`.
- App target build: `xcodebuild build` completed successfully with Xcode 26.3
  and the iOS Simulator SDK 26.2.
- Five focused `MovTests` passed (5/5, 0 failures) on the existing iPhone 17
  Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). Tests
  used a temporary source copy with unique app, unit-test, and UI-test bundle
  identifiers; parallel simulator testing was disabled. The cases cover
  default-local mode and screen mapping, successful zero balance and cursor
  paging, failure and manual retry, clearing the previous member on account
  change, and cancellation/idle cleanup for both loaders.
- Result bundle: `/tmp/mov-wireframe-read-injection-tests.xcresult`.
- The independent `MovNetworkingTests` package passed 35/35 using fixture
  `MockURLProtocol` responses. No real host or credentials were configured.
- Only the focused read-bridge unit tests were run; no new UI navigation test
  or full-app regression suite was run. Functional verification does not
  establish full source/app pixel or motion parity; that QA remains open.

### PR #48 independent review follow-up

- The independent review found two lifecycle races: a duplicate points retry
  could invalidate the first retry's bridge generation, and button-created
  retry/page tasks were not cancelled with their screen/account scope.
- The bridge now gives manual operations one task owner per active screen
  scope. Duplicate retry/page taps are ignored while an operation is active;
  screen changes and account changes cancel the tracked request before state
  is cleared. A cancelled retry returns to idle so a later screen activation
  starts a fresh load; a cancelled page operation restores its prior snapshot.
  Retry and paging buttons call the bridge directly instead of creating
  detached tasks.
- Two mock-backed regressions cover duplicate retry completion and actual
  cancellation of profile retry, points retry, and points paging on account
  or screen exit. The points history transition cancels the in-flight page
  request while preserving the already loaded first page. The focused bridge
  set now passes 7/7 on the existing iPhone 17 Pro using the unique-bundle
  temporary source copy. The follow-up `.xcresult` is at
  `/tmp/mov-wireframe-read-injection-followup-tests-final.xcresult`.
- Initial app reads remain owned by SwiftUI `.task(id:)`; the follow-up did not
  change layouts, local stores, server configuration, or simulator setup.

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
- Historical focused suite before the Review55 copy correction: 69/69 passed (67 `ThemeTests` + 2 UI tests) on the existing iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). It used a temporary source copy with unique app/unit/UI bundle IDs and isolated fixture storage.
- Its former `testCommunityCrewInformationUsesCurrentLocalPolicyAndRoutesFromDetailAndBoard` checked the implementation's then-current unresolved-level label. The follow-up test below replaces that expectation with the Review55 screen copy. `testCommunityCrewApplicationListOpensStatusAndConfirmsLocalCancellation` still checks current-user filtering, C18 round trip, dismissal without mutation, and confirmed local cancellation.
- Result bundle: `/tmp/mov-community-crew-info-suite.xcresult`.
- Historical note: `운영 기준 미정` was an implementation assumption, not user-approved product policy. It does not override the Review55 C32 value `Lv.1`; the follow-up below corrects that display and removes the C32/C33 local-demo notices that are absent from the wireframe. C33 state changes remain local and do not contact or notify a server.

### Historical Review55 C32/C33 wireframe follow-up (2026-10-15)

- The C32 copy now matches the wireframe: introduction `가볍게 하루를 여는 사람들`, level `Lv.1`, crew owner `이메일데모`, and row label `게시판 4/5개`. The C32 local-only notice and C33 local-application notice were removed. C32/C33 layout, safe-area title, and C33 empty text were checked on the existing iPhone 17 Pro (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`); captures are in `docs/F002-F003-live-review-20261015/`.
- `Mov` scheme built app target `Mov` and UI test bundle target `MovUITests` from the updated checkout. Compiled source/test tree: `5018edc4533aec322f3d911b8b64ff98fe3c2038`; product app: `/private/tmp/Mov-C32-C33-wireframe-20261015-derived/Build/Products/Debug-iphonesimulator/Mov.app`. The installed bundle reports `com.movtorun.mov`, version `1.0` (build `1`), Xcode build `17C529`.
- Focused UI run: 2/2 passed, including `testCommunityCrewInformationMatchesWireframeAndRoutesFromDetailAndBoard` and `testCommunityCrewApplicationListOpensStatusAndConfirmsLocalCancellation`. Result bundle: `/private/tmp/Mov-C32-C33-wireframe-20261015.xcresult`.
- The earlier 5/5 bundle `/private/tmp/Mov-F002-F003-live-review-20261015-retry.xcresult` was built before these C32/C33 changes, from checkout commit `56f447913ed12f150d65eeb0ae9fd063de309ca0` (tree `fe2e50f92f3632cd72c303cc92005af5ab24c4cd`, identical to then-current `main`). It covers navigation/scroll, dark/short-screen community layout, and H00/H07–H09 behavior, not the corrected C32 copy.

The follow-up above was superseded after review found its exact wireframe sample values had entered the default crew fixture. The current patch uses selected crew data for C32 and keeps those examples behind isolated `-wire-fixture` launch arguments.

### Data-driven C32 follow-up (2026-10-15)

- `WCommunityCrew` now carries optional level data. C32 renders introduction, level, owner name, active-board count, and other values from the selected crew and owner records. The normal crew fixture retains its own introduction and does not contain Review55 sample values.
- The Review55 sample is created only by `-wire-community-review55-crew-info` in the isolated review launch; a separate test fixture changes the selected crew introduction, level, owner ID, and board list to verify those values are data-driven. Existing crew edits preserve the optional level.
- Focused UI run passed 3/3 on the existing iPhone 17 Pro `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, with `-parallel-testing-enabled NO`: selected/default crew data in light mode and altered selected-crew data in dark mode, isolated Review55 fixture with C16/C19 routes, and C33 application status/cancellation. Tested source subtree `Mov`: `a72644e20bf0441c52dc6a127abf1384bc90f957`; UI-test subtree `MovUITests`: `64d68001a31323692816e9b1cd0863d8c39b7e1a`. Result bundle: `/private/tmp/Mov-C32-data-driven-20261015-final2.xcresult`.
- Normal installed-app C32 was opened in light mode and captured on the same simulator without clearing app data. Captures for the live selected crew, isolated Review55 fixture, and altered selected-data fixture in dark mode are in `docs/F002-F003-live-review-20261015/`.

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

## Community composer discard confirmation (C26)

- Branch: `feature/community-draft-discard-c26`, based on merged main `3e7ed97b2eadba67df4360fe91c04e02245c740a`.
- Clean isolated Xcode run: 74/74 passed (70 unit tests and 4 focused UI tests), 0 failed/skipped, on the existing iPhone 17 Pro simulator / iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). The temporary source copy used unique app/unit/UI bundle IDs and fixture-only storage. Result bundle: `/tmp/mov-c26-final.xcresult`.
- A focused follow-up passed the C13 discard/preview test with a changed selected run record and hide-ends setting: `/tmp/mov-c26-field-regressions.xcresult` (`testCommunityCourseCancelAndBackPreserveOnlyUnpublishedDraft`, 1 passed). The other exploratory follow-up tried to drive the C05 board picker from a direct screen fixture, but that fixture did not expose the picker identifier; it is not counted as a pass. C05 board is included in the draft snapshot comparison, though board-picker interaction is not separately verified here.
- C05 snapshots board, crew context, title and body; C13 snapshots selected record, title, introduction and hide-ends setting. Back, cancel, route and root-tab exits compare current values with the entry snapshot. No-change and reverted drafts leave immediately; changed drafts can continue without losing values or discard to the pending destination. C09 preview and return preserve the draft without confirmation.
- Existing crew edit exit and post text-limit/back tests passed in the clean C26 run. At that branch's final head, C04 had no post-edit action and C05 had no attachment control/state; this is historical evidence for PR #40, before the following C04 edit/delete implementation. A future media picker must add its media list to the C26 snapshot.
- Drafts and outcomes stay in local WireState. This verifies functional paths only; complete source/app pixel and motion QA remains open.

## Community post edit and delete (C04/C05)

- Base: merged C26 commit `33da6398b348e1f686dc847259e95eaf06a284ac`.
- Edit is author-only. It loads the existing post's supported title, body and board into C05, leaves the saved model unchanged until C09 save, and updates the same ID. Existing fixture image, course snapshot, comments, likes and view count remain attached. C26 snapshots the edit target ID along with board, crew context, title and body.
- An unchanged edit exits without a discard alert. Changed edits keep or discard through the existing C26 dialog; preview/back-to-edit retains the unsaved draft. Delete requires a separate confirmation, removes the post and nested comments, clears likes/recent activity/view de-duplication, and returns to the previous list/profile/notification route. A stale notification remains visibly unavailable and cannot reopen deleted detail. Comment deletion continues to use its existing tombstone.
- Authors can edit/delete their own post. Crew owners/operators can delete C04 posts associated with their crew; they cannot edit another member's post and do not gain delete rights on public posts. The role UI test uses a crew-linked C04 fixture. At PR #41 verification time, C19 still had a separate post model; the following C19 slice resolves that gap.
- Clean isolated final run: 81/81 passed (77 unit tests and 4 focused C04 UI tests), 0 failures/skips, on iPhone 17 Pro / iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). App, unit-test, and UI-test bundle IDs were unique in the temporary source copy; UI scenarios used fixture-only stores. Result bundle: `/tmp/mov-c04-final.xcresult`.
- At that PR, photo/video attachments were a separate unimplemented feature; static fixture images and attached course data were preserved by text edits. Functional tests do not count as source/app pixel or motion QA; full visual comparison remains open.
- Post changes remain local in-memory WireState, so this does not verify server persistence and current fixture state resets with a fresh launch. Independent parent validation is still pending.

## C19 crew post detail, editing, deletion, and moderation

- Branch: `feature/community-crew-post-detail-management`, based on merged PR #41 (`d69e71e47daf7d50103464c05e3e016b33689d2d`).
- Clean isolated Xcode run: 87/87 passed (80 unit tests + 7 focused UI tests, 0 failed, 0 skipped) on the existing iPhone 17 Pro simulator, iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). Tests used `/tmp/mov-c19-post-detail-20261010` with unique app/unit/UI bundle identifiers and fixture-only storage; user app state was not reset.
- UI coverage: C19 post creation → same-ID C04 detail → C19 return; author edit with same-ID update and board return; crew owner deletion with board return; manager deletion of another member's crew post/comment while edit remains author-only; reply preservation after comment tombstone; non-member direct C04 denial; existing C19 membership restriction; existing C36–C40 rename/archive/restore and local announcement flow.
- Policy coverage: shared post/board identity and invalid metadata rejection, member-only crew scope, manager-only crew comment moderation with preserved descendants, and exclusion of crew posts from public feed/search/HOT.
- Result bundle: `/tmp/mov-c19-post-detail-20261010/C19-post-detail-focused.xcresult`. `git diff --check` passed after the run.
- C19 and C04 now read/write the same in-memory `WireState.communityPosts` and preserve stable `crewID`/`crewBoardID` references across board renames. Posts remain stored during board archive and reappear when restored. No server calls or media attachments were added; the app's local fixture state resets on process restart.
- The existing PhotosPicker main-actor/sendable warning in `WireframeProfile.swift` remains unrelated. Full source/app pixel and motion QA remains open; functional tests do not claim visual completion. Parent independent verification is pending.

## Community post photo attachments (C05/C09/C04)

- Branch: `feature/community-post-photo-attachments`, based on main `2722e27c21eed7cac1a453f885e02560f89f11e9`.
- Clean isolated Xcode run: 84/84 passed (81 `ThemeTests` + 3 focused UI tests, 0 failed, 0 skipped) on the existing iPhone 17 Pro simulator / iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). The temporary source copy used app bundle ID `local.mov.prototype.Mov.communityphotos`, unit-test bundle ID `local.mov.prototype.MovTests.communityphotos`, UI-test bundle ID `local.mov.prototype.MovUITests.communityphotos`, and fixture-only storage.
- Result bundle: `/tmp/mov-community-photos.iGge9r/C05-photo-final-clean.xcresult`.
- Policy coverage includes 10-photo count, 20 MB source cap, 5 MB converted-image cap, 100 MB aggregate cap, PNG alpha preservation, GPS metadata removal, EXIF orientation normalization, long-edge/pixel resizing, and draft/published file cleanup. UI coverage exercises C05 photo ordering and preview, C26 discard confirmation, photo-only publishing, C04 photo navigation/zoom/delete, and edit discard versus save cleanup.
- Photos are converted and retained in app-owned local temporary storage; posts and attachments are not sent to a server and the local fixture resets on a fresh launch. At PR #43, C05/C09/C04 video attachment and playback were not implemented; see the following verification section for the follow-up. Full source/app pixel and motion QA remains open; functional tests do not claim visual completion. Parent independent verification was pending at that PR.

## Community post video attachments (C05/C09/C04)

- Branch: `feature/community-post-video-attachments`, based on merged PR #43 (`ad851bf246cb023d8ef1c856bba6ccb2fe23f553`).
- Clean isolated Xcode run: 91/91 passed (86 unit tests + 5 focused UI tests, 0 failed, 0 skipped) on the existing iPhone 17 Pro / iOS 26.3.1 simulator (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). The temporary source copy was `/tmp/mov-community-video-review`, with unique app/unit/UI bundle IDs `local.mov.prototype.Mov.communityvideos`, `local.mov.prototype.MovTests.communityvideos`, and `local.mov.prototype.MovUITests.communityvideos`; test attachments are synthetic fixtures.
- Result bundle: `/tmp/mov-community-video-final-isolated.xcresult`. Xcode emitted a post-run simulator-diagnostics collection warning because the helper could not resolve `simctl`; all selected tests completed successfully. The existing PhotosPicker sendability warning in `WireframeProfile.swift` is unrelated to this change.
- Policy coverage checks the 50 MB / 15-second source bounds, 20 MB MP4 output and 1920×1080 long/short-edge limits, mixed 10-item / 100 MB cap, corrupt source rejection, stale request invalidation, synthetic transcoding, poster creation, and draft/published cleanup. Focused UI coverage checks C05 draft-preview playback and C04 play/pause/stop-on-close, plus three photo-only attachment regression flows.
- Video import copies the selected source into app-owned temporary storage, converts asynchronously to MP4, and only appends after the current picker generation and draft session still match. PhotosPicker cancellation/rapid-selection races are covered by generation-policy tests but were not replayed through a UI test. Publishing, editing and deletion only affect local in-memory posts and device-local files; no server upload is connected, and the local fixture resets on a fresh launch.
- Full source/app pixel and motion QA remains open. Functional tests do not claim visual completion; parent independent verification is pending.

## PhotosPicker request lifetime and Sendable capture

- Branch: `feature/profile-photo-picker-safety`, based on merged PR #44 main SHA `6c17470921b42c1f7f19ed8f2f2320573ad7b894`.
- Draft PR: #45.
- The prior Xcode warning at `WireframeProfile.swift:156` came from the PhotosPicker label closure reading the MainActor `data` binding. The view now snapshots the `hasPhoto` Boolean before creating that closure. A simulator build then completed without that warning.
- Profile and crew photo imports now retain a per-view request token, invalidate it when selection changes or the picker owner disappears, and apply decoded bytes/errors only while the request remains current and its task is not cancelled. This prevents a late old selection or an import finishing after editor exit from replacing current view state. The existing post-photo importer already checks its generation and draft-session ID after each asynchronous load; its FileRepresentation reads/converts bytes while the received temporary URL is in scope, then stores app-owned draft data.
- Clean isolated run: 91/91 passed (88 `ThemeTests` + 3 focused UI tests, 0 failed/skipped) on the existing iPhone 17 Pro / iOS 26.3.1 (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`). Temporary source copy `/tmp/mov-photo-picker-safety-20261010` used unique app/unit/UI bundle IDs `local.mov.prototype.Mov.photosafety`, `local.mov.prototype.MovTests.photosafety`, and `local.mov.prototype.MovUITests.photosafety`, with fixture-only UI data. Result bundle: `/tmp/mov-photo-picker-safety-final.xcresult`.
- Unit coverage rejects late profile/crew results after rapid reselection and after view-owner invalidation. Focused UI coverage checks the crew editor entry, synthetic post-photo draft reorder/discard, and profile crop flow. The system PhotosPicker was not used to choose an asset: loading a synthetic asset into this shared simulator's photo library would mutate shared Photos state, while selecting from its existing library could expose user photos. Thus actual OS-picker selection/reselection remains unverified in UI; no Photos library or permissions were changed.
- The fix changes no photo limits, crop behavior, or storage flow. Upload/push remain disconnected. Full source/app pixel and motion QA remains open; functional tests do not claim visual completion.


## F-006 member withdrawal and account-error wiring

- Frontend base: merged main `6104c1ad41119ebd904e787f4e23771579aaf00b`; review reference PR #86 is merge `6104c1ad41119ebd904e787f4e23771579aaf00b`. The implementation is submitted as draft PR #87.
- Backend contract was read from current `main` SHA `8e922483e79df24c91e539a965ebc9ab375238c1` (read-only). Confirmation is fetched from `GET /api/v1/members/me/withdrawal/confirmation`; its contract requires a 300-second reauthentication validity. Final request is `POST /api/v1/members/me/withdrawal` with a member/session-bound, one-time `WITHDRAWAL` proof and `confirmed: true`; `LINK` and `UNLINK` proofs are not interchangeable. Only a valid `202` body containing a `WITHDRAWN` receipt is accepted as confirmation for local cleanup.
- A confirmed receipt clears only that member's locally owned running records and the matching member's Keychain session. Cleanup persistence errors retain the session and allow local-only cleanup retry. Failed, expired-proof, session-expired, cancelled, account-switched, stale-response, and duplicate-submit cases retain safe state. A lost POST response is explicitly outcome-unknown: the client neither treats it as success nor resubmits automatically and keeps local data/session.
- Current backend main has no durable withdrawal operation-status lookup or idempotency replay contract for recovery after an accepted response is lost. The client therefore cannot safely resolve that state; the API needs a durable operation key with receipt replay after revocation or an equivalent status/recovery endpoint before a safe manual server retry can be offered.
- The backend repository reports its erasure adapter gate disabled/incomplete. No live API, deployment, credential, infrastructure, or real account deletion was exercised. The mock fixture is DEBUG-only and requires a UUID defaults suite plus UUID Keychain service; test settings do not use product defaults, Keychain services, or running records.
- The previous focused 9-test pass was run on a local working tree based at `0548d19966d25a6ee0d6fd9a95b101f5e406b904`, not on the then-published PR #87 head `84db871993c4c9f964d78683df40fe49a43b35e4`. That published blob was truncated and has now been replaced. Do not attribute the earlier pass to the old PR SHA.
- Corrected source verification on the existing iPhone 17 Pro / iOS 26.3.1 simulator (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`): 11 focused `ThemeTests` + 5 focused `LaunchTests` passed (16/16; 0 failures, 0 skips), using `-parallel-testing-enabled NO`. Result: `/tmp/movtorun-f006-final3.xcresult`.
- The simulator verification copy used unique app/unit/UI bundle IDs `local.mov.prototype.Mov.f006withdrawal`, `local.mov.prototype.MovTests.f006withdrawal`, and `local.mov.prototype.MovUITests.f006withdrawal`, plus UUID UserDefaults suites and UUID Keychain service names. Simulator default signing was enabled; no `CODE_SIGNING_ALLOWED=NO` override was used. No real API, credentials, account deletion, deployment, or infrastructure was involved.
- UI coverage includes known failure → fresh reauthentication → success/login screen; expired proof → fresh reauthentication → success; lost response → no retry and session retained across relaunch; cancel before POST → session retained; and backing from T11 → T15 → settings with unused proof discarded. Unit coverage also includes purpose isolation, `confirmed`, 300-second notice, duplicate submit, late account-switch response, session expiry, cleanup storage failure and local-only retry, and member-scoped run/session cleanup.
- Product app data-container manifests (relative path, byte size, SHA-256 only) were saved at `/tmp/movtorun-f006-product-manifest-before-final3-ui.tsv` and `/tmp/movtorun-f006-product-manifest-after-final3-ui.tsv`; both contained 2,417 files and compared identical. No product app file changed.
- Pixel/motion QA is not included. The current backend’s no-status/no-idempotent-recovery gap after a lost accepted response remains open, and its real erasure gate is disabled/incomplete.
