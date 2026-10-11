# AUTH11 logout implementation note

This note records the feature behavior chosen for this implementation. It is not a general authentication or security policy.

## Contract and behavior

The frontend contract was checked against backend main commit `b362098389f70734dc7ef58f4c109200b587f5e6` (`docs/API_CONTRACT.md`, `docs/AUTH_POLICY.md`). `POST /api/v1/auth/logout` revokes the current device session. A `204` confirms logout. A `401 UNAUTHENTICATED` means the session is already invalid. `503 AUTH_UNAVAILABLE` means the backend cannot confirm/revoke the session and the client keeps the user logged in.

For `500`, other unexpected responses, unavailable local access token, and transport failures (including a request whose response was lost), the server outcome is not confirmed. Keep the local login state and the user on T10, show a short retry message, and wait for an explicit user retry. Do not retry automatically. On a later retry, `204` or `401` clears the local login state and routes to A01.

Logout remains limited to the current device session. Existing run records and other user data are not deleted. Changing account scope clears account-specific remote read state, cancels bridge-managed work, and advances generation guards so already-running reads cannot publish late results. Logout rotates that scope through the existing login-state transition.

## Integration boundary

The logout client is optional dependency injection over the existing transport and token-provider protocols. This change does not configure a production API endpoint, provide real tokens, integrate a social provider, or access Keychain credentials. The in-memory requester exists only as a review/test fixture.

## Verification coverage

- Client contract tests cover POST, no request body, current Bearer token, 204, 401, 503, 500, and transport failures.
- Bridge tests cover duplicate taps, 503 retry, 500 retention, lost-response retry followed by 401, account changes, and stale results after account or screen changes.
- UI tests use isolated UserDefaults suites to cover retry, login-screen persistence after relaunch, and a delayed response after leaving T10.
