# Review52 H07 source comparison

Reference: the supplied `running-app-source.zip` local render, H07 at 390×790, with the same fixed local run fixture and September reference month. No GPS, backend, or remote content was involved.

## Differences found before editing

- The SwiftUI period selector was limited to 200 pt and rendered as a charcoal pill. The source uses the full 342 pt content width, a soft outer track, a raised white selected segment, and muted unselected text.
- The monthly calendar omitted its run-day summary (`9월 1일 달렸어요`) and the green-dot `달린 날` legend shown above the month navigation.
- The empty selected-day helper copy differed from the source wording.
- The focused UI test did not pass the fixed-viewport fixture argument, so its initial capture had zero weekly metrics instead of the source fixture's 4.82 km / 30:08. The production view already used the deterministic review clock; the capture setup was incomplete.

## Corrections

- Made the period selector fill its content width, restored the selected/unselected treatment, and added the short selection transition while respecting reduced-motion settings.
- Added the monthly run-day count and legend, restored the source helper copy, and aligned the selected-day heading and empty state.
- Added the fixed viewport launch argument and assertions for the source fixture values, 165 pt segment width, month summary, legend, and helper copy.

## Verification boundary

- Source and app captures were reviewed at 390×790. The app capture uses the fixed September fixture.
- Focused `testSummaryMovingPeriodAndCalendarPreservation` passed on iPhone 16e / iOS 26.3.1.
- iPhone 17 Pro Max execution was attempted twice after CoreSimulator startup errors. Xcode launched the test runner, but the sandbox run did not finish a valid `.xcresult`; it is not counted as a pass.
- This is a focused H07 check. The 140-state integrated visual QA remains outstanding. H03 goal-wheel behavior has unit coverage, but its source/app visual comparison remains outstanding.
