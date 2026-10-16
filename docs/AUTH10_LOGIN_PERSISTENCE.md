# AUTH10 login persistence

## Contract and status

This change implements the client session storage boundary approved on 2026-10-16: one Keychain item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and Keychain synchronization disabled. The record contains the server-issued access token, refresh token, member ID, and any pending refresh request ID as one encoded value. Tokens and request IDs are not stored in `UserDefaults`, files, or logs.

The refresh behavior follows the backend contract reviewed at `MovToRun/backend` main `6c0137a08e40e5eef76562f2e190bdc994087f48` (`docs/API_CONTRACT.md`, `docs/AUTH_POLICY.md`, `docs/PROGRESS.md`): before sending a refresh, the client persists the current refresh token with one UUID request ID. A lost response or restart retries that exact pair. The server may return the same successor while the session remains valid; replay does not extend the server's rolling seven-day TTL. The client replaces the complete Keychain record only after validating a server response. A later successful rotation extends the rolling TTL according to the existing server policy.

## Implemented behavior

- `KeychainAuthSessionStore.shared` provides a production Keychain adapter. The full session snapshot is read or replaced in one Keychain item; failed writes leave the previous item intact.
- `AuthSessionClient.restoreAfterAppLaunch()` returns `nil` without network traffic when there is no saved session. When a session exists, it performs one normal refresh regardless of access-token age, preserving the server's re-entry policy.
- The app root now constructs one `KeychainAuthSessionStore.shared` and shares it with the login, logout, password-reset revocation, social completion, and account-link token consumers. A normal launch ignores the cached `WLocalProfile.logged` bit: only a Keychain snapshot followed by a successful refresh reaches H00/H06. A missing endpoint configuration or refresh error leaves the app at A01 and does not delete the saved snapshot; a refresh 401 clears it.
- A01 submits credentials through `AuthSessionClient.login` and enters the app only after the server response has been validated and the atomic Keychain write can be read back. A cancellation or stale screen response cannot update the visible account; login errors contain no credentials, token values, or raw server payload.
- Refresh remains single-flight for clients sharing the store. Mutation leases and a session version prevent late refresh results from replacing a different account or a newer login/logout state.
- The social completion coordinator can receive the same `AuthSessionStoring` instance and commits only validated, server-issued token pairs. It does not create tokens.
- A refresh `401` clears the local session. Logout clears it only after `204` or already-invalid `401`. If Keychain cleanup fails, the local snapshot remains and logout reports a storage failure.
- A concurrent logout that reports `sessionChanged` after another request cleared the same store is presented as the same completed logout. If the store contains a newer session, the bridge keeps it and reports the session change.
- `AuthSessionFailure.storageUnavailable` is returned on secure-storage failures; no raw token value is included in errors.

## Integration boundary

AUTH04 login, AUTH05–07 social completion, AUTH08–09 account changes, and AUTH11 logout/reset consumers now share the `AuthSessionStoring` boundary. The app still has no approved API base URL, credentials, provider SDK, production social consent catalog, or external service setup. Without the bundled endpoint configuration, the login and social entry points explain that authentication is unavailable and never set an authenticated session. Signup's local OTP preview and the local-account switch remain review-only examples; they do not establish a server account. AUTH04–09 are not marked as end-to-end integrations.

The `-wire-auth-session-flow-fixture` path exists only in Debug UI tests and requires a UUID-scoped Keychain service with the `com.movtorun.ui-fixture.auth-session.` prefix. Its static JWT-shaped values come from a mock API transport. It never reads or writes the app's shared Keychain service, and teardown removes only that fixture item. Existing screen-review fixtures continue to use their labeled local navigation demo.

## Verification

`AuthSessionPersistenceTests` uses a mock Keychain backend with unique per-test services; tests never access existing app Keychain items. Coverage includes recreation of the store across a simulated relaunch, device-only/non-synchronizing storage policy, refresh response loss and exact retry, the server's remaining TTL on a replay, one network request for concurrent refresh callers, cancellation and stale/account-changed responses, atomic replacement failure retaining the pending old token pair, social-login persistence failure retaining the old snapshot, and refresh/logout cleanup behavior. The focused iPhone 17 Pro UI fixtures exercise login, launch refresh/retry, expired-session clearing, account-identity mismatch, Keychain write failure, and confirmed logout using UUID-scoped Keychain services.
