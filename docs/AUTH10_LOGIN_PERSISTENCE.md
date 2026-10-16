# AUTH10 login persistence

## Contract and status

This change implements the client session storage boundary approved on 2026-10-16: one Keychain item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and Keychain synchronization disabled. The record contains the server-issued access token, refresh token, member ID, and any pending refresh request ID as one encoded value. Tokens and request IDs are not stored in `UserDefaults`, files, or logs.

The refresh behavior follows the backend contract reviewed at `MovToRun/backend` main `6c0137a08e40e5eef76562f2e190bdc994087f48` (`docs/API_CONTRACT.md`, `docs/AUTH_POLICY.md`, `docs/PROGRESS.md`): before sending a refresh, the client persists the current refresh token with one UUID request ID. A lost response or restart retries that exact pair. The server may return the same successor while the session remains valid; replay does not extend the server's rolling seven-day TTL. The client replaces the complete Keychain record only after validating a server response. A later successful rotation extends the rolling TTL according to the existing server policy.

## Implemented behavior

- `KeychainAuthSessionStore.shared` provides a production Keychain adapter. The full session snapshot is read or replaced in one Keychain item; failed writes leave the previous item intact.
- `AuthSessionClient.restoreAfterAppLaunch()` returns `nil` without network traffic when there is no saved session. When a session exists, it performs one normal refresh regardless of access-token age, preserving the server's re-entry policy.
- Refresh remains single-flight for clients sharing the store. Mutation leases and a session version prevent late refresh results from replacing a different account or a newer login/logout state.
- The social completion coordinator can receive the same `AuthSessionStoring` instance and commits only validated, server-issued token pairs. It does not create tokens.
- A refresh `401` clears the local session. Logout clears it only after `204` or already-invalid `401`. If Keychain cleanup fails, the local snapshot remains and logout reports a storage failure.
- `AuthSessionFailure.storageUnavailable` is returned on secure-storage failures; no raw token value is included in errors.

## Integration boundary

AUTH04 local login, AUTH05–07 social completion, AUTH08–09 account changes, and AUTH11 logout/reset consumers share the existing `AuthSessionStoring` boundary. This change does not configure real credentials, provider SDKs, production endpoint values, or external services. `MovApp` and the wireframe fixture do not enable a live login flow or call startup restoration; the production composition root must inject `KeychainAuthSessionStore.shared` and call `restoreAfterAppLaunch()` when that flow is approved. AUTH04–09 remain unverified as end-to-end app integrations.

## Verification

`AuthSessionPersistenceTests` uses a mock Keychain backend with unique per-test services; tests never access existing app Keychain items. Coverage includes recreation of the store across a simulated relaunch, device-only/non-synchronizing storage policy, refresh response loss and exact retry, the server's remaining TTL on a replay, one network request for concurrent refresh callers, cancellation and stale/account-changed responses, atomic replacement failure retaining the pending old token pair, social-login persistence failure retaining the old snapshot, and refresh/logout cleanup behavior.
