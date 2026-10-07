# 모브 · 원본 HTML 기반 SwiftUI 프로토타입

최신 수정과 검증은 [최종 감사 보고](Evidence/Refinement20261004/report.md), [85개 상태 검수표](Evidence/Refinement20261004/inventory.md), [원본/앱 비교](Evidence/Refinement20261004/compare.html)에 기록합니다. 이전 보고와 캡처는 `Evidence/FinalAudit20261004`와 `Evidence/Fidelity20261004`에 보존했습니다. 이번 수정은 알려진 25개 화면과 공유 컴포넌트에 집중했고, 37개 상태의 양 테마 캡처 74장을 갱신했습니다.

앱 화면은 SwiftUI와 Canvas입니다. HTML을 앱 안에서 표시하거나 WKWebView로 감싸지 않았습니다. 원본 v32 단일 HTML의 auth-flow, theme, run-panel 등 최종 override 및 Review33 실제 화면을 기준으로 구현합니다. aperture 로고·등급·제공자 이미지와 Pretendard/Cafe24 폰트는 원본 자산입니다. 지도는 원본 SVG 좌표와 최종 테마 색을 Canvas로 포팅했습니다.

## 실행

아래 명령은 `/Users/seunghwan/Documents/Mov/frontend`에서 실행합니다.

`Mov.xcodeproj`의 `Mov` scheme을 iPhone 17 시뮬레이터에서 실행합니다. 전역 CLT나 서명 설정 변경 없이 다음 명령을 사용할 수 있습니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Mov.xcodeproj -scheme Mov \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/MovFidelityNative \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

## 로컬 동작 범위

85개 원본 상태에 대응하는 로컬 화면 라우트가 있습니다. 로그인·가입·코드 인증·약관·프로필·로그인 수단·알림·목표·러닝·기록·설정·삭제/취소는 로컬 상태와 입력 검증으로 동작합니다. 실제 서버, 이메일 발송, OAuth, GPS/센서 수집, 원격 push, 외부 배포는 연결하지 않았습니다. 서명 설정도 변경하지 않았습니다.

실제 거리 측정값을 만들지 않습니다. 일반 진입의 새 러닝은 경과 시간만 기록하고 거리는 0입니다. 새 로컬 프로필에 예시 기록을 자동으로 넣지 않습니다. `-wire-fixture -wire-reset`은 별도 검토 저장소에만 명시적 예시 데이터를 넣습니다. `-wire-screen ID`는 비교할 상태에 직접 진입하고, `-wire-review-size`는 HTML 캡처와 같은 388×764 비교 영역을 사용합니다. 일반 진입 회귀에는 `-wire-screen`을 사용하지 않습니다.

거리 목표는 1–500km, 0.5km 단위입니다. 주간 거리/시간 목표는 독립 선택하며 거리 1–500km, 시간 10분 단위·최대 100시간입니다. 표시 시간은 원본처럼 분:초이며, 2시간 23분 45초는 `143:45`입니다. 로컬 기록·목표·프로필은 기기에 저장합니다. 실제 인증 성공이나 실측 성공을 의미하지 않습니다.

## 승인된 원본 예외

- H04: 선택한 거리/시간 헤더는 `#5EF76D`, 미선택은 중립색.
- T05: 자체 로그인에 원본 모브 심벌.
- T06/T17: “Google을 연결할까요” / “Google이 연결됐어요”.
- T12: 좌상단 모브 글자 제거.
- T01: 바깥 중복 탈퇴 제거, T04 개인정보·데이터 안의 탈퇴 유지.
- R01 라이트 GPS 상자: `#E5E5E5`, 1px.
- R05: 상단바 제거.

캡처 존재나 테스트 통과를 85개 상태의 픽셀·모션 일치 완료로 취급하지 않습니다. 상태별 검증 범위와 남은 차이는 최신 검수표를 참고하세요. 이전 README는 최종 증거 폴더의 `README.previous.md`에 보존합니다.


## 2026-10-04 계정·온보딩 검수

[33개 상태 결과 및 남은 차이](Evidence/AuthOnboarding20261004/report.md), [원본/앱 양 테마 비교](Evidence/AuthOnboarding20261004/compare.html). 새 시각 대조 29개와 기존 4개의 변경 영향을 확인했습니다. 계정 전용 테스트 10개 통과. 모든 화면·모션의 완전일치 판정은 아니며, 계정 분리 저장 보완은 승인 검토로 미적용입니다. 실제 인증·이메일·OAuth·서버·GPS·외부 배포는 연결하지 않았습니다. 가짜 fixture만으로 검증했습니다.
