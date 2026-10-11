# Backend profile read preparation

## Scope

This branch prepares one read-only integration unit for the confirmed
`GET /api/v1/members/me/profile` endpoint. The frontend base is
`46d60f85f0b744a9228cc1046bb1d36085bec07e`; the backend contract and controller
were checked on backend `main` at `e8e1729a8bf6cba30a5f5611ce3e6842432a9009`.
The response DTO contains only `nickname`; it does not expose a member ID.

The existing `APIClient` remains the only transport. This change adds an
HTTP-response form for endpoint-specific mapping while preserving the existing
2xx-only `send` behavior. `MemberProfileClient` decodes the profile DTO,
requests `Cache-Control: no-store`, and reads an access token from an injected
`AccessTokenProviding` boundary. It does not store, refresh, revoke, or log the
token. `MemberProfileLoader` exposes `idle`, `loading`, `loaded`, and `failed`
states plus an explicit retry after failure. Neither type is connected to a
SwiftUI screen yet, so existing local profile data remains the app's source of
truth.

## Error and retry behavior

- `401` maps to `unauthenticated` and is not retried here. The future session
  coordinator must perform the contract's single refresh attempt and decide
  whether to return to login; this preparation layer does not own that policy.
- `503 AUTH_UNAVAILABLE` maps to a generic service-unavailable state and is
  retried at most once because the request is read-only. No token or local
  profile state is changed. Other `503` responses are not retried.
- Transient URL transport failures are retried at most once. Cancellation,
  malformed JSON, `404`, and other HTTP errors are not retried.
- Problem response parsing only keeps `code` and `requestId` for mapping and
  correlation. Raw server titles, validation details, and exception text are
  never surfaced as app errors.

## Verification boundaries

The `MovNetworkingTests` package passed 18/18 tests using `MockURLProtocol`
fixtures for the request, DTO mapping, `401`/`503` behavior, bounded retry, and
loader states. `APIClient.swift` also passed an iOS Simulator SDK 26.2
cross-target typecheck under Xcode 26.3. Neither check calls a live backend.

An app-target `xcodebuild` was attempted against the designated iPhone 17 Pro,
then a generic iOS Simulator destination. Both were blocked because
CoreSimulatorService could not discover an available simulator runtime in this
execution environment. No app was installed and no simulator data was changed.
Visual integration and end-to-end authentication remain unverified.

The app still has no Keychain token provider or session refresh flow; the
committed environment examples use reserved `.invalid` hosts. No real service
host, account credential, environment setting, or user profile data was used or
changed. This branch does not use the run-reward endpoint or depend on
unconfirmed PR #69 work.
