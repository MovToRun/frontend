# Review bundle: authenticated run record reads

## Review target

- Branch: `feature/backend-run-record-read`
- Base: `main` at `b522494ea367ba792e093379287be0df925ebbd7`
- API source pinned for this implementation: backend commit
  `089dc2a7d94c791f493718213b18fc7b60cb6aa6`
- Feature entry points: `Mov/Networking/RunRecordsClient.swift`,
  `Mov/App/WireframeCore.swift`, and `Mov/App/WireframeRun.swift`.

## What to review

1. Confirm list and flattened detail decoding against the pinned backend
   contract, especially explicit nullable fields, opaque cursors, KST dates,
   and nullable `pointReward` amounts.
2. Confirm cancellation, account scope, selected detail ID, and retry behavior
   cannot apply stale responses to the current screen.
3. Confirm remote rows/details remain distinct from `RunStore.records` and
   failures do not appear as a successful empty list.
4. Confirm the feature adds only authenticated `GET` requests; it does not add
   uploads, device location reads, notifications, or persistent remote cache.

## Verification evidence

- Networking package: 42/42 tests passed. URL protocol fixtures cover list
  wrapper, flattened detail, authorization, cursor forwarding, fractional
  timestamps, 64-bit values, reward-zero semantics, explicit nulls, failures,
  paging loops, and stale detail completions.
- Isolated simulator run: 3/3 focused tests passed on the already booted
  iPhone 17 Pro, iOS 26.3.1. The run used a temporary source copy, unique
  bundle IDs, an isolated fixture suite, and synthetic in-memory responses.
- Result bundle: `/tmp/mov-run-records-focused-final.xcresult`.
- No live backend, real credentials, or real GPS were used. Full pixel and
  motion comparison remains open.

## Deliberate follow-up boundary

The production host and authenticated token provider are not configured in
this UI-only slice. Remote reads remain disabled unless a caller injects both.
The feature does not decide how remote and local records should be merged or
migrated.
