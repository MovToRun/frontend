# Integration preparation

This branch starts from remote `main` at PR #17 merge `17d1260845e5b7dfed8f845ec66951b0e63d6621`.

## App identity and existing local data

The app target Bundle ID is `com.movtorun.mov` in Debug and Release. The previous prototype used `local.mov.prototype`. iOS treats these as separate apps and data containers: existing prototype preferences and files remain with the old app and are not moved or deleted by this change. The frontend currently has no Keychain integration. This PR does not install the app and does not implement data migration. Do not remove the old prototype before deciding whether its local data should be migrated.

The change does not alter signing team, provisioning, capabilities, entitlements, URL schemes, ATS, permissions, or background modes.

The app target keeps `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` as the build settings for the build and marketing versions. `Mov/Info.plist` maps them to `CFBundleVersion` and `CFBundleShortVersionString`. After a Debug or Release compile, `scripts/verify-app-plist.sh <path-to-built-Info.plist> 1 1.0` checks both expanded values.

## API configuration and transport

The backend contract at `Mov/docs/API_CONTRACT.md` defines `/api/v1` as its base path and specifies the initial run-record routes, including `POST /api/v1/runs`, `GET /api/v1/runs`, and `GET /api/v1/runs/{runId}`. The example development and production URLs therefore include `/api/v1/`, while keeping the host reserved under `.invalid`; the real environment hosts still need to be supplied by the backend owner. The committed build xcconfigs keep their base URLs empty.

`APIClient.makeRequest(path:)` accepts an endpoint-relative path beneath the configured base URL. Pass `runs` or `runs/{runId}`; do not include a leading slash or repeat `api/v1`. For example, base URL `https://api-dev.example.invalid/api/v1/` plus path `runs` produces `https://api-dev.example.invalid/api/v1/runs`. The path argument rejects query strings; endpoints that need query parameters must add them as separately encoded URL query items when integrated, rather than concatenating them into the path. This foundation does not add endpoint calls, payload models, authentication, retries, or token behavior. No screen or app startup path constructs or sends a request.

Debug uses `Config/Development.xcconfig`; Release uses `Config/Production.xcconfig`. Each file can optionally include an untracked `Development.local.xcconfig` or `Production.local.xcconfig`.

1. Copy the matching `.example.xcconfig` to its ignored `.local.xcconfig` name.
2. Replace the reserved `.invalid` host with the host provided by the backend owner, retaining the `/api/v1` base path. Use HTTPS; ATS is unchanged.
3. Keep real deployment hosts and credentials out of committed example files. OAuth client secrets belong on the server, not in the app.

The shared transport currently builds relative requests under the configured base path, applies request/resource timeouts, returns 2xx response bodies, and maps transport, non-HTTP, and non-2xx responses to typed errors. HTTP response bodies are not included in errors. It has no auth headers, endpoint definitions, retry logic, or logging.

## Contract still needed before feature integration

Follow the backend API contract before adding calls: use its endpoint paths/methods, request/response schemas, and error behavior. The backend contract describes more than this PR integrates, and auth/session behavior, profile/photo flow, and feature-specific retry policy must be implemented in their scoped work. This foundation intentionally does not implement login, social SDKs, Naver Maps, location collection, or S3 upload.
