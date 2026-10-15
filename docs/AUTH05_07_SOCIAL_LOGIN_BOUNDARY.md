# AUTH05–07 social login boundary

This implementation adds the frontend request and flow boundary for Kakao, Naver, and Google social login. It follows the backend contract at the exact backend revision reviewed for this work.

## Request flow

The relative API paths are `auth/social/{provider}/challenge`, `auth/social/{provider}/verify`, and `auth/social/complete` beneath the configured `/api/v1` base URL. The challenge and verify calls use the backend's 600-second state, nonce, and proof fields. Kakao and Google credentials are ID tokens; Naver credentials are authorization codes. The app does not choose or invoke a provider SDK in this change.

For an existing provider identity, completion succeeds without signup fields. The backend does not return a separate “signup required” result: a new identity's first completion returns `TERMS_NOT_ACCEPTED` (422). The coordinator maps that response to the signup branch. Signup completion reuses the attempt's proof, device ID, and request ID and adds the nickname plus the complete required terms catalog. A retry after an uncertain completion response must use the same request ID and identical payload; a changed payload after a saved receipt is a conflict.

## Injectable boundaries and limits

`SocialLoginClient` builds contract-shaped requests over `APIResponseSending`. `SocialLoginCoordinator` coordinates challenge, credential acquisition, verification, completion, cancellation, error mapping, and duplicate completion coalescing through `SocialLoginServing` and `SocialLoginCredentialProviding`.

The wireframe UI exercises the flow only when launched with `-wire-social-login-fixture`. Its mock returns fixture credentials and tokens, and signup uses the backend's test-only consent document. The regular app is not wired to a provider SDK or live social API; it does not persist the fixture tokens. No OAuth, mail, or network call was made by the tests. Provider SDK setup, production consent versions, session/Keychain storage, and Apple sign-in remain future work.

The unit tests use injected response/service mocks. The UI tests cover existing login, signup-required completion, cancellation, verification failure and retry, and duplicate submission on the configured simulator.
