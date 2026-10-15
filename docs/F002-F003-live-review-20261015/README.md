# F-002/F-003 live screen comparison — 2026-10-15

## Source and installed app

- Verified GitHub `main`: `a452c0e1ea9e009a6f7974adb80a8261c7b2d363`, tree `fe2e50f92f3632cd72c303cc92005af5ab24c4cd` (GitHub branch API, 2026-10-15).
- The local review checkout is at `56f447913ed12f150d65eeb0ae9fd063de309ca0`, with the same tree SHA as current `main`. Its commit ancestry differs because it is the earlier PR #72 head; no source files were modified during this review.
- Existing iPhone 17 Pro simulator: `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, iOS 26.3. Installed app metadata: `com.movtorun.mov`, version `1.0` (build `1`), Xcode build `17C529`. The app bundle does not contain a Git SHA, so the exact source revision of the installed binary cannot be proven from metadata alone.
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
| C32 crew information | Crew name, description, area, member count, grade, owner, board count, and welcome message render below the safe-area header. | The content structure matches. Values differ: reference `Lv.1` / `이메일데모` / `게시판 4/5개`; app `운영 기준 미정` / `새벽러너` / `활성 게시판 4/5개`. App also explains that the data and level policy are local/unconnected. |
| C33 pending crews | Safe-area title and back action; empty state reads `기다리는 가입 신청이 없어요`. | The empty-state copy matches. App adds a local-only application-status notice absent from the mosaic. |

The live H00 values were `0.00 km / 20 km` and `0분 / 2시간`, while the current browser wireframe example showed `1.52 km / 40 km` and `9분 / 12시간`. These are different persisted example values; the layout and controls match. App data was left unchanged.

Repeated navigation was observed through Feed → Boards → center Home → Feed → Crew → My Profile → Community Settings → Liked Posts, then back to the feed. The top icons did not overlap, the selected community destination remained marked, and the center item returned to Mov home. C15 → C16 → C32 and C15 → C33 were also opened on the same simulator.

## Scroll, theme, and test evidence

- The CUA scroll gesture did not move the current Feed viewport during this session, so the current live scroll transition was not recaptured.
- The live C03 capture confirms the visible-state placement of the board bar and compose control. Hide/restore behavior remains supported by the prior PR72 captures and focused tests linked above; it was not newly exercised in this session.
- Existing current-source evidence in [`F003 community header evidence`](../F003-community-header-evidence/README.md) includes light/dark safe-area captures, hidden/restored bottom-bar captures, and the focused test results. `testCommunityBottomBarHidesOnDownScrollAndFloatsMoveWithIt` verifies downward hide, upward restore, and floating-action alignment. The C02 evidence README also records light/dark and scroll-direction checks.
- The initial default-shell `xcodebuild` attempt exited 70 before tests because the sandbox could not reach CoreSimulatorService. A read-only approved lookup then confirmed the existing iPhone 17 Pro was Booted. The approved focused rerun passed 5/5: community down/up scroll with floating controls, community dark/short-screen header and tabs, H00 selector/summaries, H08/H09 empty/over-goal presentation, and H07 repeated week/month transitions. Result bundle: `/private/tmp/Mov-F002-F003-live-review-20261015-retry.xcresult`.
- PR72's independent verification remains its own evidence (C03 R9/R10/R11 each passed 1/1). The focused rerun here checks the next comparison scope alongside community behavior; it is not a replacement for PR72's independent review.

## Conclusion

The reported navigation, scroll, and header issues were not present in the current app. PR #72 already supplies the C03 board-tab and scroll-control fix on current `main`. C32/C33 have the value/copy differences listed above; the C32 level display and both screen notices reflect the existing local-demo boundary documented in the plan, so this review records them without changing product behavior. No source change is justified from the requested issue set. The attached captures and focused test result provide current-main evidence.

## Captures from the existing simulator

- [H00 dual-goal home](H00-dual-goal-live.png)
- [C01 community feed](C01-feed-live.png)
- [C03 board list](C03-board-list-live.png)
- [C06 liked-posts empty state](C06-liked-posts-live.png)
- [C32 crew information](C32-crew-info-live.png)
- [C33 pending crews](C33-pending-crews-live.png)
