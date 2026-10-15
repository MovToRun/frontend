# F-002/F-003 live screen comparison — 2026-10-15

## Source and installed app

- Verified GitHub `main`: `a452c0e1ea9e009a6f7974adb80a8261c7b2d363`, tree `fe2e50f92f3632cd72c303cc92005af5ab24c4cd` (GitHub branch API, 2026-10-15).
- The initial comparison checkout was `56f447913ed12f150d65eeb0ae9fd063de309ca0`, with the same tree SHA as current `main`. Follow-up C32/C33 copy fixes are on `codex/f002-f003-live-review-20261015-main`.
- Existing iPhone 17 Pro simulator: `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, iOS 26.3. Installed bundle before the follow-up was `com.movtorun.mov`, version `1.0` (build `1`), Xcode build `17C529`; the bundle has no Git SHA. The C32/C33 follow-up build was installed to this same simulator and has the same bundle identity/version/build metadata.
- The originally supplied `db35b93260fa1c769c5a1ce4c28a8a10aa5e8a64` / `20043ea3b8bb7f74f3b1b6c7f9f9fb58f42e41d4` is older than the verified current `main` above.

## Live screen findings

The installed app was already present on the approved simulator. It was opened without resetting the device or clearing app data. Light mode was active.

| Area | Live observation | Review55 comparison |
| --- | --- | --- |
| H00 | One large weekly arc; distance/time selector; both goal summaries remain visible; center tab keeps Mov home. | Matches the approved 220° arc, selector, dual summaries, and center-home behavior. |
| C01 feed | Grid action at left, centered Mov mark, search at right; status bar and safe-area spacing remain clear; five-item community bar is visible. | Matches the wireframe header and dedicated Feed / Boards / Home / Crew / My Profile navigation. |
| C02 boards | Shared header, `게시판` heading, four shortcuts, and recent posts. | Matches the wireframe structure. |
| C03 board list | `러닝 질문` title and back action sit below the status safe area; the Boards item is selected in the dedicated community bar; `글쓰기` stays above the bar. | Matches the C03 board route and floating compose placement. No icon overlap was visible. |
| C15 crew | `나의 크루` / `크루 찾기` sections and application count are visible. | Matches the agreed crew navigation structure. |
| C08 own profile | Profile card, settings action, and community bar remain present. | Matches the profile destination; settings is reachable inside the community profile. |
| C28 → C06 | `좋아요한 게시글` is the first Community Settings row; opening it shows the empty-state message. | Confirms liked posts are nested inside community profile settings. |
| C32 crew information | The initial installed app had different intro, level, owner, and board-row copy plus a local-only notice. The updated screen now shows the Review55 intro, `Lv.1`, `이메일데모`, and `게시판 4/5개`, with the notice removed. | C32 matches the visible wireframe content; safe-area title and back action remain clear. Updated live capture is included. |
| C33 pending crews | The empty state reads `기다리는 가입 신청이 없어요`; the local-only application-status notice has been removed. | Empty state and visible copy now match the wireframe. Updated live capture is included. |

The live H00 values were `0.00 km / 20 km` and `0분 / 2시간`, while the current browser wireframe example showed `1.52 km / 40 km` and `9분 / 12시간`. These are different persisted example values; the layout and controls match. App data was left unchanged.

Repeated navigation was observed through Feed → Boards → center Home → Feed → Crew → My Profile → Community Settings → Liked Posts, then back to the feed. The top icons did not overlap, the selected community destination remained marked, and the center item returned to Mov home. C15 → C16 → C32 and C15 → C33 were also opened on the same simulator.

## Scroll, theme, and test evidence

- The CUA scroll gesture did not move the current Feed viewport during this session, so the current live scroll transition was not recaptured.
- The live C03 capture confirms the visible-state placement of the board bar and compose control. Hide/restore behavior remains supported by the prior PR72 captures and focused tests linked above; it was not newly exercised in this session.
- Existing current-source evidence in [`F003 community header evidence`](../F003-community-header-evidence/README.md) includes light/dark safe-area captures, hidden/restored bottom-bar captures, and the focused test results. `testCommunityBottomBarHidesOnDownScrollAndFloatsMoveWithIt` verifies downward hide, upward restore, and floating-action alignment. The C02 evidence README also records light/dark and scroll-direction checks.
- The initial default-shell `xcodebuild` attempt exited 70 before tests because the sandbox could not reach CoreSimulatorService. A read-only approved lookup then confirmed the existing iPhone 17 Pro was Booted. The approved focused rerun passed 5/5: community down/up scroll with floating controls, community dark/short-screen header and tabs, H00 selector/summaries, H08/H09 empty/over-goal presentation, and H07 repeated week/month transitions. Result bundle: `/private/tmp/Mov-F002-F003-live-review-20261015-retry.xcresult`.
- That 5/5 run used project/scheme `Mov` / UI bundle `MovUITests`, checkout commit `56f447913ed12f150d65eeb0ae9fd063de309ca0` and tree `fe2e50f92f3632cd72c303cc92005af5ab24c4cd` (same source tree as current `main` before the C32/C33 changes). The passed cases were `testCommunityBottomBarHidesOnDownScrollAndFloatsMoveWithIt`, `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`, `testReview52StatisticsEmptyAndOverGoalMatchSourcePresentation`, `testReview55HomeGoalSelectorAndPersistentSummaries`, and `testSummaryPeriodControlRepeatedTransitionsFromFreshFixture`. It is prior-source evidence, not validation of the later copy changes.
- Updated-source run used `Mov` scheme, app target `Mov`, and UI test bundle `MovUITests` from compiled source/test tree `5018edc4533aec322f3d911b8b64ff98fe3c2038`. Both C32/C33 tests passed: `testCommunityCrewInformationMatchesWireframeAndRoutesFromDetailAndBoard` and `testCommunityCrewApplicationListOpensStatusAndConfirmsLocalCancellation`. Result bundle: `/private/tmp/Mov-C32-C33-wireframe-20261015.xcresult`; build products: `/private/tmp/Mov-C32-C33-wireframe-20261015-derived/Build/Products/Debug-iphonesimulator/`.
- PR72's independent verification remains its own evidence (C03 R9/R10/R11 each passed 1/1). The focused rerun here checks the next comparison scope alongside community behavior; it is not a replacement for PR72's independent review.

## Conclusion

PR #72 already supplies the C03 board-tab and scroll-control fix on current `main`; live repeated navigation and header checks found no overlap. The former C32 “unresolved level” rationale was an implementation note, not an approved policy, and did not justify diverging from Review55. C32/C33 are now aligned to the wireframe copy, with their extra local-demo notices removed. The two updated-source UI tests pass. Direct CUA scroll gestures did not move the live feed viewport in this session; manual hide/restore capture remains unverified here, while the focused UI test passed on the same approved simulator.

## Next screen comparison scope

The implementation checklist in [`REVIEW52_IMPLEMENTATION_PLAN.md`](../REVIEW52_IMPLEMENTATION_PLAN.md) marks C32–C43 as locally rendered/interactive; those `[x]` marks do not mean visual QA is done. Its visual coverage table still lists `C01–C43` as only partially compared. After a final C32/C33 source/app recheck, continue in this order:

1. `C34–C35`: member list, role rules, member warning/removal, and back/return paths.
2. `C36–C40`: join-guidance editor, board list/editor/archive/restore, announcement editor, and application review.
3. `C41`: HOT list/empty state and `C04`/`C01` return paths.
4. `C42–C43`: blocked-user unblock/anonymous masking and recent-activity visibility/filtering.

For each group, compare the Review55 reference with the same simulator viewport, record exact copy/layout deltas before edits, then capture light/dark and scroll states where the reference provides them. The plan rows are `C34–C40` and `C41–C43` in the community checklist.

## Captures from the existing simulator

- [H00 dual-goal home](H00-dual-goal-live.png)
- [C01 community feed](C01-feed-live.png)
- [C03 board list](C03-board-list-live.png)
- [C06 liked-posts empty state](C06-liked-posts-live.png)
- [C32 before wireframe correction](C32-crew-info-before-wireframe-fix.png)
- [C33 before wireframe correction](C33-pending-crews-before-wireframe-fix.png)
- [C32 crew information](C32-crew-info-live.png)
- [C33 pending crews](C33-pending-crews-live.png)
