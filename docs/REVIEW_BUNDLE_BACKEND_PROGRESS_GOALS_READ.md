# Review bundle: backend progress and weekly goals read

## Scope

Add a read-only adapter for backend progress, daily progress, and current-week
goal status. Inject it optionally into the existing home and statistics views;
leave the default local prototype composition intact.

Backend reference: `MovToRun/backend@089dc2a7d94c791f493718213b18fc7b60cb6aa6`.
Frontend base: `main` at `f5870477a9ffe87438cb3d0edde99c68141a7de2` when this branch
was created.

## Review points

- `Mov/Networking/ProgressGoalsClient.swift` owns authenticated GET-only
  requests, DTO validation, KST date ranges, and separate `/progress`, weekly
  goal, and daily load states.
- `Mov/App/WireframeCore.swift` exposes the optional injection boundary and
  account/screen generation handling. Repeating activation for the same
  account/screen/run is idempotent so an in-flight read is not invalidated.
- `Mov/App/WireframeHome.swift` keeps the existing home arc/dual-goal selector
  and summary layout. Home rings and summaries read the weekly-goal state; a
  failed `/progress` request cannot hide those values. Errors do not display
  local totals as a fallback.
- `MovTests/ThemeTests.swift` exercises default-local mode, account reset,
  independent endpoint failures and retries, cancellation and reload, stale
  account responses, duplicate activation, and H08/H09 range movement.
- `MovUITests/LaunchTests.swift` checks successful remote totals and explicit
  no-fallback failure states with in-memory synthetic fixtures.
- `docs/BACKEND_PROGRESS_GOALS_READ_PREPARATION.md` records the pinned contract,
  source mapping, current test evidence, and follow-up boundary.

## Verification recorded before the independent-state follow-up

- SwiftPM mock networking suite: **50 passed, 0 failed**.
- Focused app bridge tests: **3 passed, 0 failed**.
- Focused UI flow tests: **2 passed, 0 failed** on iPhone 17 Pro / iOS 26.3.1.
- Simulator tests used only the already-booted device, a temporary source copy
  with unique app/unit/UI bundle IDs, and unique fixture suites. No backend
  endpoint or real credential was used.
- The app unit `.xcresult` is `/tmp/mov-progress-goals-unit.xcresult`. The UI
  run's 2/2 summary was recorded before temporary Xcode artifacts were removed
  to recover disk space; the UI `.xcresult` itself is not retained.
- Functional coverage is not full Review52 pixel or motion QA. That comparison
  remains open.

## Independent-state follow-up status

- A non-building Swift parser check passed for the changed networking, bridge,
  home view, and bridge-test sources.
- The new SwiftPM and Xcode bridge/UI tests were not executed. The volume had
  222 MiB free, and CoreSimulatorService was unavailable for listing the
  designated iPhone 17 Pro. No simulator was created or reset, and no other
  session cache or user data was removed.
- The previous test counts above refer to the pre-follow-up PR head and do not
  verify the independent-state changes.

## Follow-up boundary

The production session/composition owner still needs to inject the app's
authorized `APIClient`, access-token provider, and `ProgressGoalsClient`. No
server write, upload, push, or remote persistence is part of this PR.
