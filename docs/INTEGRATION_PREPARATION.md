# Integration preparation

This branch starts from remote `main` at PR #17 merge `17d1260845e5b7dfed8f845ec66951b0e63d6621`.

## App identity and existing local data

The app target Bundle ID is `com.movtorun.mov` in Debug and Release. The previous prototype used `local.mov.prototype`. iOS treats these as separate apps and data containers: existing prototype preferences and files remain with the old app and are not moved or deleted by this change. The frontend currently has no Keychain integration. This PR does not install the app and does not implement data migration. Do not remove the old prototype before deciding whether its local data should be migrated.

The change does not alter signing team, provisioning, capabilities, entitlements, URL schemes, ATS, permissions, or background modes.

## API configuration and transport

The frontend repository contains no server API contract or assigned development/production host yet. The configuration therefore leaves `MOV_API_BASE_URL` empty. The client refuses to initialize without a configured HTTPS URL, and no screen or app startup path constructs or sends a request. No endpoint names, payloads, authentication mechanism, retries, or token behavior are assumed here.

Debug uses `Config/Development.xcconfig`; Release uses `Config/Production.xcconfig`. Each file can optionally include an untracked `Development.local.xcconfig` or `Production.local.xcconfig`.

1. Copy the matching `.example.xcconfig` to its ignored `.local.xcconfig` name.
2. Replace the reserved `.invalid` example host with the host provided by the backend owner. Use HTTPS; ATS is unchanged.
3. Keep real deployment hosts and credentials out of committed example files. OAuth client secrets belong on the server, not in the app.

The shared transport currently builds relative requests under the configured base path, applies request/resource timeouts, returns 2xx response bodies, and maps transport, non-HTTP, and non-2xx responses to typed errors. HTTP response bodies are not included in errors. It has no auth headers, endpoint definitions, retry logic, or logging.

## Contract still needed before feature integration

Coordinate and document the actual API contract before adding calls: environment host(s); endpoint paths/methods; request/response schemas; error body rules; access and refresh-token issuance, rotation and revocation; logout/account deletion behavior; profile/photo representation and upload flow; and timeout/retry limits. This foundation intentionally does not implement login, social SDKs, Naver Maps, location collection, or S3 upload.
