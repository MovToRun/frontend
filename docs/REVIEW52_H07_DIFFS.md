# Review52 H07 source comparison

Reference: the supplied `running-app-source.zip` local render, H07 at 390×790, with the same fixed local run fixture and September reference month. No GPS, backend, or remote content was involved.

## Differences found before editing

- The SwiftUI period selector was limited to 200 pt and rendered as a charcoal pill. The source uses the full 342 pt content width, a soft outer track, a raised white selected segment, and muted unselected text.
- The monthly calendar omitted its run-day summary (`9월 1일 달렸어요`) and the green-dot `달린 날` legend shown above the month navigation.
- A month with zero run days omitted the source empty state `이 달에 저장된 러닝 기록이 없어요` below the calendar grid.
- The empty selected-day helper copy differed from the source wording.
- The selected-day title and record count inherited the same accessibility identifier, so a single-element query could match both.
- The focused UI test did not pass the fixed-viewport fixture argument, so its initial capture had zero weekly metrics instead of the source fixture's 4.82 km / 30:08. The production view already used the deterministic review clock; the capture setup was incomplete.

## Corrections

- Made the period selector fill its content width, restored the selected/unselected treatment, and added the short selection transition while respecting reduced-motion settings.
- Added the monthly run-day count and legend, restored the source helper copy, and aligned the selected-day heading and empty state.
- Added the source empty-month message and gave the selected-day title and count separate accessibility identifiers.
- Added the fixed viewport launch argument and assertions for the source fixture values, 165 pt segment width, month summary, legend, and helper copy.
- Extended the fixed fixture test through September's saved Sep 29 run and August's zero-run month.

## Verification boundary

- Source and app captures were reviewed at 390×790. The app capture uses the fixed September fixture.
- Focused `testSummaryMovingPeriodAndCalendarPreservation` passed on iPhone 16e and iPhone 17 Pro Max / iOS 26.3.1 after adding the empty-month and selected-day assertions.
- This is a focused H07 check. The 140-state integrated visual QA remains outstanding. H03 goal-wheel behavior has unit coverage, but its source/app visual comparison remains outstanding.
