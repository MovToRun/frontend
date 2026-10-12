# PR62 UI regression review

This work was performed in the isolated `task-34/frontend` checkout on branch `codex/ui-regressions-pr62`, starting at `495a2e054c9347b4eb7c7b5921fe9e08d14d5b69` (`7ce9579e031c9e13d4ecdbf3ee947558d84b5c4e`). The original `/Users/seunghwan/Documents/Mov` checkout and the other author checkout were not edited. No `AGENTS.md` or `.agents/skills` files were present. The repository README and user review guide were read; the existing wireframe and `com.movtorun.mov` app identifier were retained.

## Findings

| Regression | Finding | Change and evidence |
|---|---|---|
| Fixed run panel | Product layout issue. R05 adds a title and delete action; the panel's intrinsic stack then grew and shifted the lower actions from the R02 y=693pt position to y=697pt. | Keep the panel handle and metrics in the fixed panel stack and anchor the action group to the panel bottom. The three pause/finish/cancel cycles, collapsed/expanded transitions, and 320×568 viewport now retain the same measured frames and hittable buttons. The original ±0.5pt frame checks remain unchanged. See [run finish after](ui-regression-evidence/after-run-finish.png). |
| Accessibility-size tab alignment | Product layout issue. At Accessibility3 the tabs used different intrinsic icon heights, producing the measured 1pt vertical mismatch (773.33pt vs 774.33pt). | Give each tab the same 26×26pt icon slot and the same 64pt button height. Captions and tab routes are unchanged. See [tab alignment after](ui-regression-evidence/after-tab-alignment.png). |
| C01 local recovery route | Test expectation was stale. The “내 러닝 카드 보기” label is absent from C01's visible/accessibility controls. The actual `tab-4` “내 정보” control routes to M01. | The route test now taps the existing accessibility identifier and still asserts that M01 appears within five seconds. No product route or auth behavior changed. |
| Review52 seeded week | Test expectation was stale. The app's weekly header is the ISO Monday–Sunday range for the October 1 fixture: `9.28 — 10.4 · 가상 예시`; the old assertion expected a single weekday string. The seeded record metadata also includes its start time. | Use the existing fixed reference-week fixture argument and assert the rendered weekly label, progress, and exact current metadata. A stable `homeWeekLabel` identifier supports that check. See [reference week after](ui-regression-evidence/after-reference-week.png). |
| Review55 Accessibility3 clipping check | The failure was produced by the test gesture. The supplied head result reports `summary.frame.minY = 184.1667pt` against the strict lower bound `scroll.frame.minY - 1 = 230pt`. The compact scroll viewport itself was 320×437.3pt in that run; 184pt was the summary's frame after repeated fixed 240pt drags, not the scroll area's height. The screenshots show the page is scrollable and the summary content reflows. | Replace fixed 240pt gestures with viewport-relative, low-velocity drags, wait for layout to settle, and leave an 8pt viewport inset. The existing summary containment, no-overlap, and hittability assertions remain. The passing compact viewport is 320×440pt, and the complete summary frame is required to remain inside it. See [before top](ui-regression-evidence/before-accessibility3-compact-top.png), [after top](ui-regression-evidence/after-accessibility3-compact-top.png), [before long summary](ui-regression-evidence/before-accessibility3-long-summary.png), and [after long summary](ui-regression-evidence/after-accessibility3-long-summary.png). |

The Review55 before/after images are captures from the supplied head result bundle and the passing final run. All horizontal bounds, overlap, viewport containment, selected goal, and hittability checks remain active. No expected value was deleted and no tolerance was widened.

## Verification

All simulator runs used Xcode at `/Applications/Xcode.app/Contents/Developer`, the existing iPhone 17 Pro simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, and the existing app ID.

- Focused UI regressions passed: `testFixedRunPanelUserFlow` (1/1), `testHomeTabAlignmentAtAccessibilityTextSize` (1/1), `testLocalRecoveryPrivacyAndCancellationRoutes` (1/1), `testReview52H00ReferenceWeekShowsSeededGoalProgress` (1/1), and `testReview55HomeGoalSelectorAccessibility3ReflowsWithoutClipping` (1/1). The tab and date tests also passed together (2/2); the date test was rerun after adding its screenshot attachment (1/1).
- Full `MovTests`: 184/184 passed.
- Network/session fixture subset (`AuthSessionClientSessionTests`, profile transport failure, and run-upload transport cases): 22/22 passed. The project has no separate Networking target or scheme.
- `xcodebuild build`: succeeded.
- Result bundles are under `/tmp/mov-pr62-*.xcresult` on the execution host. No live server, sign-in policy, shop policy, or production data was used.

## Evidence files

Screenshots are in [`ui-regression-evidence`](ui-regression-evidence/). The supplied failing result bundles remain read-only at `/Users/seunghwan/Documents/Codex/2026-10-12/task-30/results/`; passing result bundles were written under `/tmp`.
