# Backend run record deletion preparation

This is an optional client integration seam with in-memory fixtures. The app's
default composition still supplies no delete dependency. The change does not
configure a production host or token provider and does not delete real records.

## Backend contract checked

The backend `main` commit `d545fd91f0c7d5d73863ee49396b95b6d629830e` defines
`DELETE /api/v1/runs/{runId}?version={version}`. A confirmed deletion returns an
empty `204`. The service checks the current record version and returns
`409 VERSION_CONFLICT` when it changed. A same-member retry after deletion
recognizes the run tombstone and also returns `204`. `404 NOT_FOUND` deliberately
hides whether a run is absent or belongs to another member, so the client keeps
the outcome unknown. Other `409` codes are not interpreted as a version
conflict.

Deletion removes the run, its GPS tracks, and verdict data while retaining a
tombstone keyed by member and `clientRunId`. The tombstone blocks re-upload from
restoring the deleted run. Previously awarded points are not clawed back; the
server's recorded reward and duplicate-settlement information remain unchanged.
The client therefore never adjusts point balance locally.

## Client behavior

`RunRecordsDeleting` is injected independently through
`WireframeRemoteReadDependencies.runRecordsDeleter`. `RunRecordsClient` sends a
version query, no body, and no automatic retry. Only an empty `204` is success.
After transport uncertainty, the user may explicitly retry the same run ID and
version; backend tombstone idempotency resolves a committed deletion whose
response was lost. The client does not retry `404` or `409` as success.

The existing red delete action and confirmation screen remain. Only confirmed
success removes the selected server row and detail from the in-memory loader;
the list is marked for refresh and progress summaries are invalidated. Failures
keep the record visible and explain that deletion was not confirmed. `404`
uses an unknown-or-inaccessible message. In-flight work is guarded by account,
screen, selected run, and request generation. Navigation prevents an old
response from changing the next detail; a confirmed same-account late success
can reconcile the list, while a response from a prior account cannot affect the
current account. Local records and local sample data are separate and unchanged.

`410 RUN_DELETED` handling belongs to a future authenticated upload queue. When
that queue is implemented, it should remove only the pending upload for the
same account and `clientRunId`, as required by the backend upload contract. This
read/delete seam does not add an upload queue or change a device-local run.

## Synthetic test fixtures

The UI fake is opt-in with `-wire-run-records-delete-fixture`. Additional
scenarios use `-wire-run-records-delete-404`,
`-wire-run-records-delete-response-lost`, or
`-wire-run-records-delete-fail`. These modes use a synthetic record and never
call the backend.

Verification for this branch:

- SwiftPM request-capturing networking tests: 17 passed.
- Focused Xcode bridge/edit/read tests: 8 passed.
- Focused Xcode confirmation UI tests: 3 passed.
- Xcode `build-for-testing` succeeded for the existing iPhone 17 Pro simulator
  `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, with parallel testing disabled and
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Fixture resets used unique `-wire-test-store-suite` UserDefaults suites.
  There was no live API request, production token, or real record deletion.
