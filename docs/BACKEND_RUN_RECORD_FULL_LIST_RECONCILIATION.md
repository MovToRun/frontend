# Backend run record full-list reconciliation

Frontend `main` `2e553882f8dc99f7e42bc42f1a3f0413d129a4dd` and backend `main`
`d545fd91f0c7d5d73863ee49396b95b6d629830e` are the source revisions for this
preparation.

## Contract boundary

Backend DEC-014 uses a fresh `GET /api/v1/runs` list to learn about changes from
another device. It does not define a delta endpoint, sync cursor, or tombstone
feed. The existing `cursor` and `nextCursor` are opaque keyset pagination values
for that list. A record absent from a completed list read has been deleted from
the account's server records.

Deletion physically removes run, track, and verdict rows. Its tombstone retains
only member ID, run ID, `clientRunId`, and deletion time. It is not exposed to the
client. The `410 RUN_DELETED` response belongs to upload synchronization: the
backend contract says a future app upload queue should remove that pending item
without retrying it. This read integration has no upload queue and does not
interpret `410` as a local-record deletion command.

## Client reconciliation

- List re-entry and pull-to-refresh start from a nil cursor and read pages in
  order, passing each opaque `nextCursor` unchanged.
- Pages are accumulated in a temporary candidate. The visible in-memory remote
  snapshot changes only after a terminal page succeeds. An error, cancellation,
  repeated cursor, duplicate run ID, oversized page, or the defensive 1,000-page
  ceiling keeps the previous visible list intact and allows another read.
- The bridge owns the refresh task and cancels it when the list screen or account
  changes; cancellation of the pull-to-refresh caller is forwarded as well. The
  loader checks cancellation after each page response and before requesting the
  next cursor. Operation IDs prevent a late task from clearing a replacement
  refresh's state.
- The backend does not promise snapshot isolation across pages. This client does
  not claim that a scan is a point-in-time server snapshot.
- A completed scan marks a cached detail missing from the result as
  `recordNotFound`, so stale detail content cannot be displayed as current.
- The reconciliation applies only to the optional in-memory remote loader. It
  does not mutate `RunStore.records`, built-in samples, points balance, or any
  persistent local cache.

## Verification scope

The synthetic fixture can remove its run on the next list read to exercise a
different-device deletion. Tests use injected fake transports and isolated
UserDefaults suites; they do not call a server, use a production token, or delete
real user data.

- SwiftPM package suite: 79/79 passed (including 25 `RunRecordsReadTests`).
- Xcode `build-for-testing`: succeeded for scheme `Mov` and the existing iPhone
  17 Pro simulator `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`.
- Focused Xcode bridge and UI regressions: 11/11 passed on iOS 26.3.1 with
  parallel testing disabled, including parent cancellation, explicit retry
  cancellation, and stale-task/new-operation isolation. Result bundle:
  `/tmp/task15-run-refresh-cancel-tests.xcresult`.
- Simulator device state was not reset. UI fixtures used unique UserDefaults
  suites and synthetic remote records.
