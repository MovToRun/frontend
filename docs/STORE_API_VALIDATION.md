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
- 앱 테스트: 지정된 기존 iPhone 17 Pro UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`로 `xcodebuild test`를 시도했습니다(`-parallel-testing-enabled NO`). CoreSimulatorService가 device set을 초기화하지 못해 destination 조회가 실패했고 테스트는 시작되지 않았습니다. 새 simulator를 만들거나 기존 기기를 초기화하지 않았습니다.
- 실제 서버, 인증 토큰, Keychain, 환경 설정 또는 인프라는 연결하지 않았습니다.

## F009 상점 UI 연결 추가 검증

- FE 작업 기준을 사용자 지정 최신 main `116037423e27e7f91de46eac05214e4c7d7e6c99`로 갱신했습니다. 원본 `/Users/seunghwan/Documents/Mov`는 열거나 수정하지 않았습니다.
- BE 계약 기준은 `MovToRun/backend` main `f13d07609dac15ccc44fc3d277c7b78847972587`의 `docs/API_CONTRACT.md`입니다.
- 상점의 상품 목록·상세·계정 잔액 조회, 구매 확인, 보유 목록 및 장착 조회·변경을 `CosmeticStoreFlow`에 연결했습니다. 상품 가격, 보유 상태, 잔액, 영수증 및 장착 슬롯은 서비스 응답에서만 표시하고 로컬 구매 차감 코드는 제거했습니다. 포인트 개요/내역의 기존 예시 데이터는 상점 구매에 쓰이지 않는다고 화면에 표시합니다.
- 미리보기는 구매 확인과 별도 화면이며 현재 상품의 허용된 accent color를 이용한 예시 그림만 보여 줍니다. 계약상 `assetId`는 불투명한 값이고 실제 asset URL/리소스 매핑 계약은 없습니다.
- 부족한 잔액이면 구매를 막고, 구매 중복 제출은 잠급니다. 전송/취소/불완전 응답/5xx 등 결과를 모르는 상태에서는 자동 재구매하지 않습니다. 사용자가 확인을 누르면 원래 idempotency key로만 재전송해 서버의 멱등 영수증을 확인합니다. 409 잔액 부족은 잔액을 다시 읽고, 이미 보유/판매 종료는 카탈로그·보유 정보를 다시 읽습니다. 계정 scope 변경 시 기존 계정 데이터와 결과를 지웁니다.
- fixture 테스트는 `-wire-cosmetic-store-fixture`와 UUID형 `-wire-test-store-suite`를 함께 준 DEBUG 검토 실행에서만 주입합니다. 상점 API fixture 자체는 메모리 전용이며 Keychain이나 실제 transport를 사용하지 않습니다. UI Host의 사용자 기본값 격리와 기존 fixtureKeychain 구현은 그대로 유지했습니다. 제품 앱의 기본 경로는 기존 인증 transport/session과 client를 사용합니다.
- 순수 상태 테스트 추가: 잔액 부족에서 무전송, 결과 유실 후 명시적 동일 key 재확인, 서버 영수증 잔액 권위성, 보유 상품 장착/해제, 계정 데이터 정리를 다룹니다. UI 집중 테스트는 샘플 잔액과 fixture 잔액 분리, 상세/미리보기/구매/장착/해제, 부족 잔액, 결과 유실 재확인을 다룹니다.
- 실제 서버/제품 API를 호출하지 않았고 S3, 자격증명, 환경 변수 또는 인프라 설정을 바꾸지 않았습니다. 실제 앱 설치/화면 실행은 독립 검증자 작업으로 남겼습니다.
- 서비스 연결 전 확인이 남았습니다: backend가 포인트 조회 gate를 활성화하고 상품 카탈로그를 제공해야 합니다. 출시 전에는 인증이 연결된 계정에서 실제 API가 활성화된 환경의 별도 검증이 필요합니다. 프로필/커뮤니티 러닝 카드에 장착 스타일을 반영하는 별도 쓰기/스냅샷 흐름은 API 계약 범위가 아니어서 연결하지 않았습니다.

### F009 로컬 검사

- 독립 검토에서 발견한 컴파일 오류를 수정했습니다. associated-value 실패 enum을 패턴 매칭하고, `ThemeTests`에서 제거된 로컬 상점 구매 API를 호출하던 테스트를 샘플 잔액/내역 보존 검증으로 바꿨습니다.
- Xcode 26.3 Swift toolchain에서 전체 `swift test` — 203 tests passed, 0 failures. `--filter CosmeticStore` — 19 tests passed, 0 failures.
- iOS Simulator SDK Debug `xcodebuild build-for-testing` — 성공.
- 최적화된 Release `xcodebuild build-for-testing` — `ENABLE_TESTABILITY=YES` 명령행 재정의로 성공. 테스트 타깃이 `@testable import MovUITestHost`를 사용하므로 해당 설정이 필요하며 프로젝트 설정은 변경하지 않았습니다.
- Debug 및 Release 제품 경로에서 `scripts/verify-ui-test-isolation.sh` — 모두 성공. MovUITestHost/runner와 UUID 격리 fixture 구성을 확인했고, Mov 제품 앱 산출물 및 `DependentProductPaths` 참조가 없음을 확인했습니다.
- UI 테스트 실행, 실제 앱 설치/실행, 실제 서버 호출은 하지 않았습니다. 첫 검증 기록의 Command Line Tools/XCTest 제한은 Xcode developer directory를 지정한 이번 재검증으로 해소됐습니다.
