# Backend progress and weekly-goal read boundary

## Contract checked

The contract was read from `MovToRun/backend` at pinned commit
`089dc2a7d94c791f493718213b18fc7b60cb6aa6` (`ProgressController`,
`WeeklyGoalController`, response DTOs, services, and `docs/API_CONTRACT.md`).
The frontend implementation is read-only and matches these routes:

| Request | Use |
| --- | --- |
| `GET /api/v1/progress` | Grade, rolling 90-day progress window, lifetime totals |
| `GET /api/v1/progress/daily?from=YYYY-MM-DD&to=YYYY-MM-DD` | Inclusive daily records for a selected week or month; at most 366 days |
| `GET /api/v1/goals/weekly` | Current Monday–Sunday KST goal status and actual valid weekly totals |

Weekly goal axes are independent. A missing axis has `goal*` and `remaining*`
set to `null`, `achieved` false, and still reports the actual weekly `done*`
total. An achieved axis may report more done than its goal; remaining stays
zero. The client validates those relationships and does not translate a null
goal or a failed read into a zero target.

## Implementation boundary

`ProgressGoalsClient` performs authenticated GET requests only. It validates
the backend date ranges, Monday-based week, required nullable fields, grade
shape, daily ordering and goal arithmetic. `RunningProgressLoader` loads the
home overview as progress plus weekly-goal reads and loads daily records by an
explicit range. The optional loader is injected through
`WireframeRemoteReadDependencies`; the app's default composition still has no
network client, token provider, host, or credential source.

`H00` uses the existing home ring and dual-goal selector. `H07`–`H09` use
server daily results for period totals and calendar marks. The remote path is
read-only, displays loading and failure distinctly, and never substitutes local
totals after a failed request. Device-saved recent runs remain local and are
labeled accordingly. No endpoint writes, upload, push, or persistence were
added.

## Verification boundary

Networking tests use mock URL responses. Bridge and UI tests use in-memory
readers with synthetic values and a uniquely named local fixture suite. The
UI test copy uses the already booted designated iPhone 17 Pro simulator and
unique bundle IDs. These tests do not contact the backend. Full Review52
pixel/motion comparison for this slice remains open.

## Verification run (2026-10-11)

- `swift test`: 50 passed, 0 failed (20 API client, 15 points, 8 progress/goals,
  and 7 run-record networking tests). Final run included the missing-nullable-
  weekly-field regression case.
- Focused `MovTests/ThemeTests` bridge run: 3 passed, 0 failed on iPhone 17 Pro,
  iOS 26.3.1. It covered account reset, duplicate activation during a pending
  read, and separate daily-range aggregation.
- Focused `MovUITests/LaunchTests` run: 2 passed, 0 failed on iPhone 17 Pro,
  iOS 26.3.1. It checked that remote home and weekly summary values agree, goal
  editing is disabled, local records remain labeled as device data, and overview
  or daily failures do not fall back to local metrics.
- UI app/unit/UI-test bundle IDs in the temporary project copy were
  `local.mov.prototype.Mov.progressgoals`,
  `local.mov.prototype.MovTests.progressgoals`, and
  `local.mov.prototype.MovUITests.progressgoals`. Fixture values were synthetic
  and isolated to unique `UserDefaults` suites.
- The focused unit `.xcresult` remains at
  `/tmp/mov-progress-goals-unit.xcresult`. The successful UI run summary was
  captured as 2/2 before removing temporary Xcode artifacts to recover disk
  space; no UI `.xcresult` is retained.
- The user-facing prototype was not reset or deleted. No simulator was created.

## Follow-up

The production session/composition owner must inject `ProgressGoalsClient`
with the app's authorized `APIClient` and access-token provider before real
backend reads are available. Daily range refresh, retry, account-scope reset,
and duplicate screen activation remain covered by mock-based verification;
production session behavior is outside this boundary.
