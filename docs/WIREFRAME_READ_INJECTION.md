# Wireframe read-state injection

## Scope

This slice connects the existing read-only `MemberProfileLoader` and
`PointsWalletLoader` to the profile (`M01`) and points (`POINTS`, `B02`)
screens through an explicit composition boundary. `RootView` and
`WireframeRoot` accept optional `WireframeRemoteReadDependencies`; the app's
default `RootView()` supplies none, so its current local profile and
`WPointsStore` remain the only data sources unless a caller deliberately
injects a loader.

Injected profile and points values are shown in separate, read-only panels.
The saved running card, local points balance, shop and local sample ledger are
left intact. Zero is rendered as a successful remote balance. Errors keep the
existing loader's safe user copy and expose retry only where the points loader
allows it. The points history shows remote rows and opaque-cursor pagination
separately from the local fixture rows.

## Lifecycle and account scope

The bridge mirrors the existing actors; it does not add a second persistent
store or transport. A screen-keyed SwiftUI task owns the initial read. The
bridge owns one manual retry/page task at a time; another tap while that task
is active is ignored without changing the screen generation. Screen entry,
exit, and account changes cancel the bridge-owned task, while the screen task
cancels its own initial read. A generation check ignores stale completions.
Leaving the screen clears its mirrored state. Login/logout and local account
switching rotate an in-memory account scope and clear both mirrored reads
before the next load.

No loader is constructed by the production app entry point in this change. A
future session/composition owner must explicitly provide the appropriate
`APIClient`, token provider, and loaders before remote reads can occur. This
slice does not configure a host, supply credentials, persist remote data, or
change authentication/session policy.

## Verification boundary

The bridge tests use scripted in-memory protocol mocks for default-local mode,
valid zero balance and page continuation, failure/retry, duplicate retry taps,
account-scope reset, screen exit, and cancellation of initial/retry/page
requests. The existing `MovNetworkingTests` use mock URL responses. These
checks do not contact a backend. Functional tests do not establish wireframe
pixel or motion parity; that comparison remains open.
