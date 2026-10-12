# 상점 API 클라이언트 검증 기록

## 기준 계약

- FE 기준: `MovToRun/frontend` main commit `155afc49282d39b0cfc43781341ff777ab5fb085`, tree `99b162966e9567ba878e82e362a645b0c2bd61aa`.
- 가져온 원본 bundle SHA-256: `4a9dce8d5e3fe0c52f19eec49a259d988ce25c251989e8eac777b600a3adf1f2`. 추출 파일 145개의 경로·mode·blob SHA를 GitHub recursive tree(200 entries, `truncated: false`)와 대조했고 차이가 없었습니다.
- BE 기준: `MovToRun/backend` main commit `3caf2e11b7ffd890fcfcae25ee7d9caac2f07efd`.
- `docs/API_CONTRACT.md`와 해당 commit의 `CosmeticStoreController`/DTO 및 카테고리 enum을 확인했습니다. 목록·상세·구매·보유목록·장착조회/교체/해제의 필드, HTTP 상태, 오류 코드 및 카테고리 순서를 반영했습니다.

## 변경 범위

- `CosmeticStoreClient`와 화면 DI용 `CosmeticStoreServing` 계약, DTO 및 응답 검증을 추가했습니다.
- 기존 API transport와 세션 provider를 재사용합니다. 매 요청의 현재 세션으로 인증하고, 성공 응답 직전 계정이 바뀌면 이전 계정 결과를 반환하지 않습니다.
- 상품 가격·잔액·소유·슬롯 권한은 서버 응답만 사용합니다. 구매 요청은 productId와 호출자가 전달한 idempotency key만 보냅니다. 자동 구매 재시도 및 환불 API는 없습니다.
- URLProtocol fixture 기반 테스트는 성공/재생, 401·403·404·409·503, 잔액 부족, 중복·키 충돌, 취소, 계정 전환, 잘못되거나 안전하지 않은 응답을 확인합니다.
- UI/와이어프레임 변경은 없습니다.

## 검증 결과

- Swift package: 113 tests passed, 0 failures (기존 100 + 신규 상점 13).
- Xcode 앱 빌드: asset catalog 처리 중 `No available simulator runtimes for platform iphonesimulator`로 중단됐습니다. CoreSimulatorService 및 `simdiskimaged`가 연결되지 않아 발생한 실행 환경 제한입니다.
- 앱 테스트: 지정된 기존 iPhone 17 Pro simulator도 CoreSimulatorService가 기기 목록 조회 요청을 거부해 사용할 수 없었습니다. 새 simulator를 만들거나 기존 기기를 초기화하지 않았습니다.
- 실제 서버, 인증 토큰, Keychain, 환경 설정 또는 인프라는 연결하지 않았습니다.
