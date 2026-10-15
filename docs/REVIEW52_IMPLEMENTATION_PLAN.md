# Review52 화면 매핑 및 구현 순서

## 기준과 확인 상태

- 참조 기준: Review52 원본 상태 140개, 제공된 revision `commit645150b7f3a99a56279213e174ebb723baf40f7a`. 구현 추적표에는 이후 추가한 비밀번호 재설정 검수 상태 `A24–A28` 5개도 포함되어 145개 고유 항목입니다.
- 사용자가 제공한 `running-app-source.zip`의 `dist/`를 로컬 기준 원본으로 사용합니다. CSS/JS와 해당 상태 화면을 확인하고, 390×790 viewport로 렌더해 앱 캡처와 대조합니다. Mac Safari의 사용자가 열어 둔 탭 자체는 세션에서 읽을 수 없으므로 탭 화면을 직접 촬영한 것으로 표현하지 않습니다.
- 구현 상태는 실제 렌더된 내용, 동작 전이와 확인 근거를 기준으로 기록합니다. 전용 `screenView` 분기가 없다는 이유만으로 구현을 미완료 처리하지 않습니다.
- 원본 140개와 추가 검수 상태 5개, 총 145개 모두 체크리스트에 남깁니다. `L06`처럼 개발 참고용인 상태, 오류·빈 화면, 예시·전이 전용 상태는 회귀 점검 대상으로 유지하되 일반 사용자 메뉴에 노출하지 않습니다.
- 체크리스트의 `[x]`는 로컬 화면·전이 구현만 뜻합니다. 서버/API 연동은 각 화면 설명에 따로 기록하고, 원본 대비 픽셀·모션 검수 상태는 아래 coverage 표에서 분리합니다.

### 시각 대조 coverage

아래 표는 원본 렌더와 SwiftUI 실제 캡처를 비교한 범위입니다. 각 상태 목록의 `[x]`는 화면·전이의 로컬 구현 완료를 뜻하며, 시각 대조 완료와는 별도로 관리합니다.

| 시각 상태 | 화면 | 근거 |
|---|---|---|
| 대조 완료 | `A01`, `H00`, `H01` | PR #10 비교 기록·캡처 |
| 대조 완료 | `H04` | 390×790 라이트·다크 HTML/SwiftUI pair 캡처 |
| 대조 완료 | `R02`, `L01`, `L04`, `B05`, `B06` | PR #11 source/app 캡처 및 독립 Pro Max 검증 |
| 대조 완료 | `H07` | 이번 PR의 390×790 주·월 요약/달력 source/app 비교 및 iPhone 16e·17 Pro Max focused UI 테스트 |
| 대조 완료 | `H03` | 390×790 원본 화면과 SwiftUI distance/time 캡처 비교. 목표 카드/휠 배치와 행 치수 확인, 휠 테두리·선택 띠·보조 문구 색상 보정 |
| 대조 완료 | `H08`, `H09` | Review52 ZIP dist 원본을 로컬 WKWebView로 390×790 CSS/2× 렌더하고, PR #14 병합 SHA의 SwiftUI를 새 임시 iPhone 17 Pro Max 한 대에서 순차 캡처. 고정 fixture에서 거리 소수점과 주간 날짜 설명 정합. [원본/앱 캡처와 렌더 설정](REVIEW52_H08_H09_CAPTURE.md) |
| 일부 대조 완료 | 인증 `E01–E02`, `A02–A23` | E01/E02는 이번 PR에서 구현 및 focused 검증; PR20에서 A02/A03/A15 내용·구조 대조 완료. 이 세 화면의 종합 픽셀/모션 QA 및 나머지 상태는 남음 |
| 일부 대조 완료 | 기록 구간 `L05` | 제공된 CSS/JS 원본의 390×790 render와 동일 viewport SwiftUI XCTest capture를 대조; 정적 배치·copy 확인. 유효 평균 없음 표시는 사용자 확정 규칙에 따라 `0:00 /km`로 원본의 대시 표시를 덮어씀. 모션 및 통합 픽셀 QA는 미완료 |
| 남음 | 홈·목표·러닝 `H02`, `H05–H06`, `H10–H11`, `P01–P05`, `R01`, `R03–R12`, `S01–S05` | H03·H07–H09 제외 |
| 남음 | 기록·공유 `L02–L03`, `L06–L07`, `Q01–Q03` | L05는 정적 source/app 대조 완료. 다른 상태의 원본/SwiftUI 정밀 픽셀·모션 대조는 미완료 |
| 남음 | 프로필·설정·알림 `M01–M02`, `N01`, `T01–T18` | 후속 묶음 |
| 남음 | 포인트·상점 `B01–B04`, `B07–B10` | PR #11에서 확인한 B05/B06 제외 |
| 일부 완료 | 커뮤니티 `C01–C43` | `C01/C02/C03/C06/C08/C15/C32/C33` 내용·구조 대조; C32/C33은 2026-10-15 Review55 copy 정합 수정 및 앱 캡처 확인. 나머지 화면과 matched-viewport 전체 pixel/motion QA는 남음 |

전체 원본 140개 상태의 통합 시각 QA는 아직 수행하지 않았습니다. PR20에서 A02/A03/A15의 내용·구조 대조는 완료했지만, 이들을 포함한 종합 픽셀·모션 QA는 남아 있습니다. 작은 기능 묶음별 대조를 이어가며 이 coverage 표를 갱신합니다.

### 남은 로컬 UI 구현 backlog

상태 체크리스트에서 아직 미완료인 사용자 UI는 로그인 `A01`과 이메일 로그인/비밀번호 관리 및 완료 예시 `A16–A18`입니다. 체크리스트 145개 항목 중 141개가 로컬 화면·전이 구현 완료이며, 이 수에는 원본에 없던 검수 상태 `A24–A28` 5개가 포함됩니다. **이 집계는 화면 상태의 렌더·전이 coverage이며, 합의된 제품 기능의 구현률이나 기능·시각 검증 완료를 뜻하지 않습니다.** 게시글 첨부와 편집 같은 별도 요구사항은 아래 커뮤니티 backlog에서 따로 관리합니다. C06 좋아요 목록, C15–C23 크루 탐색·가입·관리·심사 흐름, C24 커뮤니티 알림, C26 작성 초안 이탈 확인, C28 설정, C29 공개 콘텐츠 검색, C30 연결, C32–C43 크루 정보·신청·멤버·관리·인기글·차단 해제·최근 활동, C10–C14 인증·코스 흐름을 로컬로 구현했습니다. 크루 상태·콘텐츠와 검색 인덱스는 로컬 fixture이며 백엔드 연결이 아닙니다. C01/C29/C41은 익명 게시판 및 크루 전용 글을 공개 피드·검색·HOT에서 제외합니다. HOT는 원본과 같이 명시된 fixture `hot` 값과 현재 목록 순서를 사용하며 점수 산정이나 실제 인기 집계는 없습니다. 위 시각 coverage 표에 남은 다른 화면들은 로컬 UI 완료 표기 상태여도 원본 대비 픽셀·모션 QA가 남아 있을 수 있습니다.

## 현재 구조 요약

`WireframeCore.swift`가 루트 화면/상태 전이와 5탭을 관리합니다. 인증, 홈·목표·통계, 러닝·기록, 프로필 설정, 포인트 상점, 공유 화면은 각각 `WireframeAuth.swift`, `WireframeHome.swift`, `WireframeRun.swift`, `WireframeProfile.swift`, `WireframePoints.swift`, `WireframeShare.swift`에 있습니다. 커뮤니티 C01 feed, C04 post, C06 liked posts, C10–C23 인증·공유 코스·크루 생성·관리·심사 흐름, C26 C05/C13 작성 초안 이탈 확인, C28 settings, C32–C40 크루 정보·신청·멤버·가입 안내·게시판·알림 관리, C42 blocked list, C43 activity history와 PR28 moderation flows는 `WireframeHome.swift` 및 `WireframeCore.swift`의 로컬 fixture/state로 동작합니다. 구현 완료는 화면 렌더, 전이 동작 및 확인 근거를 기준으로 판단합니다.

러닝 `pointReward` 모델은 확정 backend DTO의 null·PENDING·SETTLED(0 포함)·UNAVAILABLE 상태를 준비하고, 완료·기록 목록·상세에 기존 포인트 표시 체계를 재사용합니다. 로컬 예시 기록은 유지하며 API 요청이나 실제 서버 연결은 추가하지 않았습니다. [DTO 매핑과 검증 범위](RUN_POINT_REWARD_FRONTEND_CONTRACT.md)를 참고하세요. 이 화면 묶음도 전체 source 대비 픽셀·모션 QA는 남아 있습니다.

## 기능 브랜치 순서와 완료 기준

| 순서 | 브랜치 | 상태 묶음 | 완료 기준 |
|---|---|---|---|
| 1 | `feature/common-design-navigation` | 공통 토큰·타이포·적응형 레이아웃·안전영역·키보드·탭/네비 기반 | 작은~큰 iPhone, 큰 글자, 라이트/다크, safe area에서 공통 구조가 깨지지 않고 아래 화면 묶음의 기반을 제공 |
| 2 | `feature/auth-onboarding` | E01–E02, A01–A23, A24–A28(재설정 전용 검수 상태) | 가입/로그인/비밀번호 재설정/동의/인증/오류/예시 흐름, 로컬 fixture와 실제 서버 부재 표시 |
| 3 | `feature/home-run-goals` | H00–H06, H10–H11, P01–P05, R01–R12, S01–S05 | 지도, 접히는 러닝 패널, 타이머/일시정지/저장 상태, 목표, 권한·오류 상태, 반응형 전이 |
| 4 | `feature/records-stats-sharing` | H07–H09, L01–L07, Q01–Q03 | 기록/통계 빈·오류 상태, 로컬 편집·삭제, 공유 이미지 편집 및 저장 결과 예시 |
| 5 | `feature/profile-settings-notifications` | M01–M02, N01, T01–T18 | 프로필·러닝카드·설정·테마·계정·알림 흐름과 로컬 상태 |
| 6 | `feature/points-shop` | B01–B10 | 가상 잔액/내역/아이템, 구매 결과는 예시로 표시하며 실제 결제·차감 없음 |
| 7 | `feature/community-crew` | C01–C43 | 앱 별도 5탭 구조, 피드/FAB/게시글/댓글/검색/크루 흐름, 가상 데이터·서버 미연동 표시 |
| 8 | `feature/review52-visual-qa` | 전체 140 상태 × 라이트/다크 | 전체 구현 뒤 통합 시각 검수 1회. 차이는 수정 후 해당 상태만 재검수 |

PR #10(A01/H00/H01), PR #11(R02/L01/L04/B05/B06), PR #14(프로필 사진 정책)가 main에 병합했습니다. H07–H09는 같은 source/app 비교 viewport를 사용합니다. 로컬 시뮬레이션의 GPS·구매·인증·동기화 예시는 백엔드에 연결하지 않으며 서버 성공으로 오인시키지 않습니다. 기능 브랜치마다 화면을 대조하고 테스트·diff 검토 후 커밋·푸시·draft PR로 제출합니다. 다음 merge는 사용자 승인 후 진행합니다.

이번 launch 작업은 E01 정적 OS 시작 화면(라이트/다크 적응형 배경과 원본 마크)과 E02 콜드 시작 스플래시/저장된 로그인 상태별 라우팅을 구현합니다. E02는 1.04초 후 이동하며 앱 재개 시 다시 재생하지 않습니다. iOS OS 소유 시작 화면은 표시 시간을 앱에서 제어하지 않습니다. 검증은 단일 iPhone 17 Pro 시뮬레이터의 focused 테스트로 한정하며 종합 픽셀/모션 QA로 간주하지 않습니다.

반응형 기준은 320pt 안팎부터 큰 iPhone 폭, 세로 공간, safe area, 키보드, 긴 문구/줄바꿈, Dynamic Type을 포함합니다. 고정 좌표로 전체 화면을 늘리지 않고 디자인 계층을 유지합니다. 러닝 지도/접이식 패널, 커뮤니티 피드/하단바/FAB, 공유 이미지 편집기는 전용 적응형 점검을 둡니다.


### 진입 · 인증 · 온보딩 · `Auth / Onboarding`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `E01` | 네이티브 시작 | `UILaunchScreen` 정적 adaptive asset; iOS가 표시 시점을 관리 |
| [x] | `E02` | 앱 스플래시 | `WSplash` — 원본 마크/워드마크/태그라인, 로그인 저장 상태에 따른 라우팅; focused cold-start 테스트 |
| [ ] | `A01` | 로그인 | `authForm` — WireframeAuth.swift |
| [x] | `A02` | 필수 동의 | `consents` — WireframeAuth.swift; 각 내용 확인 후 해당 항목 체크, 일부 동의 차단, 전체 동의 순차 모션/취소 복구; PR20 내용·구조 비교 완료, 종합 픽셀/모션 QA 남음 |
| [x] | `A03` | 첫 프로필 | `weightProfile` — WireframeProfile.swift; 닉네임 필수/길이 검증, 검토모드 전용 fixture 충돌 점검, 선택 체중, 원본 완료 문구; PR20 내용·구조 비교 완료, 종합 픽셀/모션 QA 남음 |
| [x] | `A04` | 로그인 실패 | `loginFailure` — WireframeAuth.swift; 취소·연결 끊김 문구 및 A01 재시도 로컬 흐름 |
| [x] | `A06` | 약관·개인정보 검토 | `consentReview` — 주제별 내용 확인 후 해당 필수 동의만 반영 |
| [x] | `A07` | 이메일 회원가입 | `authForm` — 8~20자 ASCII 영문·숫자 필수, 기호 선택 |
| [x] | `A10` | 비밀번호 재설정 요청 | 재설정 전용 이메일 상태와 형식 검증 — WireframeAuth.swift |
| [x] | `A11` | 재설정 요청 확인 예시 | 메일 발송/계정 존재를 가장하지 않고 재설정 코드 검수로 이동 — WireframeInfo.swift |
| [x] | `A12` | 새 비밀번호 예시 | A24 코드 증명 필수, 공통 영문·숫자 정책과 확인값 일치, 실제 비밀번호 미변경 — WireframeAuth.swift |
| [x] | `A13` | 재설정 완료 화면 | 로컬 완료 안내, 계정 로그인 상태/비밀번호 변경 없음 — WireframeInfo.swift |
| [x] | `A14` | 소셜 인증 결과 예시 | `informationPage` — 성공·오류·취소 결과를 로컬 표시; 전용 `screenView` case는 없음 |
| [x] | `A15` | 회원가입 완료 예시 | `informationPage` — PR20 내용·구조 비교 완료, 종합 픽셀/모션 QA 남음 |
| [ ] | `A16` | 이메일 로그인 연결 | `authForm` — WireframeAuth.swift |
| [ ] | `A17` | 이메일 비밀번호 관리 | `authForm` — WireframeAuth.swift |
| [ ] | `A18` | 이메일 설정 완료 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `A19` | 회원가입 이메일 인증 | `verification` — 6자리 자동 확인, 성공 모션 후 A02 |
| [x] | `A20` | 이메일 인증 코드 오류 | `verification` — 실패 횟수 안내와 입력 복구 |
| [x] | `A21` | 이메일 인증 코드 만료 | `verification` — 5분 만료 상태와 재요청 |
| [x] | `A22` | 이메일 인증 시도 제한 | `verification` — 5회 실패 잠금 |
| [x] | `A23` | 이메일 인증 코드 재요청 | `verification` — 60초 간격, 이전 코드 폐기 |
| [x] | `A24` | 비밀번호 재설정 코드 확인 | 재설정 전용 챌린지와 회원가입 OTP UI 컴포넌트 규칙 재사용 |
| [x] | `A25` | 재설정 코드 오류 | 실패 횟수 표시 및 코드 재입력 |
| [x] | `A26` | 재설정 코드 만료 | 5분 만료와 재전송 복구 |
| [x] | `A27` | 재설정 코드 시도 제한 | 5회 잠금, 재전송 후 횟수 복구 |
| [x] | `A28` | 재설정 코드 재요청 | 60초 제한과 이전 코드 폐기 |

### 홈 · 러닝 · 목표 · `Home / Run / Goals`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `H00` | 메인 홈 | `home` — WireframeHome.swift |
| [x] | `H01` | 지도 러닝 준비 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H02` | 첫 러닝 준비 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H03` | 이번 러닝 목표 | `sessionGoal` — WireframeHome.swift; Review52 원본 대비 휠 치수·색/보조 문구 보정 및 양 목표 종류/값 보존 검증 |
| [x] | `H04` | 주간 목표 | `weeklyGoal` — WireframeHome.swift |
| [x] | `H05` | 진행 중인 러닝 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H06` | 임시 기록 복구 | `informationPage` — WireframeInfo.swift |
| [x] | `H07` | 주간·월간 요약 | `statistics` — WireframeHome.swift; 원본 대조 후 기간 선택/월간 달력 및 0일 빈 상태 정렬 |
| [x] | `H08` | 통계 데이터 없음 | `statistics` — WireframeHome.swift; 원본의 0.00 km 표기와 기준일/주간 범위 안내 정렬 |
| [x] | `H09` | 목표 초과 달성 | `statistics` — WireframeHome.swift; 원본의 두 자리 거리 표기와 기준일/주간 범위 안내 정렬 |
| [x] | `H10` | 주간 목표 삭제 | `informationPage` — WireframeInfo.swift |
| [x] | `H11` | 시간대 변경 안내 | `informationPage` — WireframeInfo.swift |
| [x] | `P01` | 위치 권한 설명 | `informationPage` — WireframeInfo.swift |
| [x] | `P02` | 위치 권한 거부 | `informationPage` — WireframeInfo.swift |
| [x] | `P03` | 정확한 위치 꺼짐 | `informationPage` — WireframeInfo.swift |
| [x] | `P04` | 설정 변경 안내 | `informationPage` — WireframeInfo.swift |
| [x] | `P05` | 시작 전 저장공간 부족 | `informationPage` — WireframeInfo.swift |
| [x] | `R01` | 위치 확인 중 | `runPanel` — WireframeRun.swift |
| [x] | `R02` | 러닝 중 | `runPanel` — WireframeRun.swift |
| [x] | `R03` | GPS 신호 약함 | `runPanel` — WireframeRun.swift |
| [x] | `R04` | 일시정지 | `runPanel` — WireframeRun.swift |
| [x] | `R05` | 종료 확인 | `runPanel` — WireframeRun.swift |
| [x] | `R06` | 러닝 상세 지표 | `runDetails` — WireframeRun.swift |
| [x] | `R07` | 지도 표시 실패 | `runPanel` — WireframeRun.swift |
| [x] | `R08` | 네트워크 연결 없음 | `runPanel` — WireframeRun.swift |
| [x] | `R09` | 재개 전 권한 확인 | `informationPage` — WireframeInfo.swift |
| [x] | `R10` | 러닝 중 저장 오류 | `runPanel` — WireframeRun.swift |
| [x] | `R11` | 기록 삭제 확인 | `informationPage` — WireframeInfo.swift |
| [x] | `R12` | 빈 러닝 종료 | `informationPage` — WireframeInfo.swift |
| [x] | `S01` | 러닝 완료 | `completion` — WireframeRun.swift |
| [x] | `S02` | 저장 중 | `completion` — WireframeRun.swift |
| [x] | `S03` | 저장 실패 | `completion` — WireframeRun.swift |
| [x] | `S04` | 동기화 대기 · 후속 | `completion` — WireframeRun.swift |
| [x] | `S05` | 유효 구간 없는 기록 | `completion` — WireframeRun.swift |

### 기록 · 통계 · 공유 · `Records / Statistics / Sharing`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `L01` | 기록 목록 | `records` — WireframeRun.swift; PR #11 Review52 source 대조 |
| [x] | `L02` | 기록 없음 | `records` — WireframeRun.swift; 빈 목록 전이 focused UI 테스트 |
| [x] | `L03` | 기록 조회 실패 | `records` — WireframeRun.swift; 조회 실패/빈 목록 구분 focused UI 테스트 |
| [x] | `L04` | 기록 상세 | `recordDetail` — WireframeRun.swift; PR #11 Review52 source 대조 |
| [x] | `L05` | 구간 기록 · 페이스 | `splits` — WireframeRun.swift; 그래프 구간 선택, 무효 평균의 `0:00 /km` 기본값, 제외 사유 copy 및 compact dark layout focused UI 테스트; 종합 픽셀/모션 대조는 남음 |
| [x] | `L06` | 기록 편집 · 개발 참고 | `recordEdit` — WireframeRun.swift; 독립 인라인 편집 focused UI 테스트 |
| [x] | `L07` | 러닝 기록 삭제 | `informationPage` — 로컬 확인/취소/삭제 전이 및 회귀 UI 테스트; 전용 `screenView` case는 없음 |
| [x] | `Q01` | 러닝 공유 만들기 | `ShareImageEditor` — `WireframeShare.swift`; 로컬 PNG 작성, 피드·스토리 캔버스와 기록 오버레이 편집. 선택 미디어 입력 검증. 무음 MP4/WebM 출력은 미구현 |
| [x] | `Q02` | 러닝 공유 저장 | `ShareOutputView` — `WireframeShare.swift`; PNG 크기 확인 및 파일 앱 저장 경로 선택. 실패 시 임시 갤러리에 보존·재시도 안내. Photos 직접 저장 및 동영상 출력은 미구현 |
| [x] | `Q03` | 이 기록의 공유 콘텐츠 | `ShareGallery`/`ShareWorkspace` — `WireframeShare.swift`; 세션 메모리 갤러리·삭제, 기록당 64MB 임시 저장 한도, 로그아웃·계정 전환 시 비움 |

### 프로필 · 설정 · 알림 · `Profile / Settings / Notifications`

이 상태 묶음은 기기 로컬 프로필·테마·알림 상태와 계정/개인정보 전이로 구현했습니다. 알림 빈 상태와 읽음 저장 재시도, 개인정보 화면에서 재확인 취소 후 원래 화면으로 복귀하는 흐름을 포함합니다. 제공자 인증, 푸시, 백엔드 동기화는 시뮬레이션 범위입니다.

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `M01` | 내 정보 · 러닝 카드 | `profile` — WireframeProfile.swift |
| [x] | `M02` | 러닝 카드 편집 | `profileEdit` — WireframeProfile.swift |
| [x] | `N01` | 알림 · 예시 | `notifications` — WireframeProfile.swift |
| [x] | `T01` | 설정 | `settings` — WireframeProfile.swift |
| [x] | `T02` | 프로필·체중 | `weightProfile` — WireframeProfile.swift |
| [x] | `T03` | 단위 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T04` | 개인정보·데이터 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T05` | 로그인 수단 관리 | `providers` — WireframeAuth.swift |
| [x] | `T06` | 로그인 수단 연결 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T07` | 기존 로그인 안내 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T08` | 로그인 연결 해제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T09` | 마지막 수단 해제 차단 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T10` | 로그아웃 확인 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T11` | 계정 삭제 확인 | `deleteAccount` — WireframeAuth.swift |
| [x] | `T12` | 삭제 완료 시뮬레이션 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T13` | 기기 데이터 삭제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T14` | 진행 중 러닝 보호 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T15` | 현재 계정 재확인 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T16` | 탈퇴 요청 처리 중 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T17` | 로그인 수단 연결 완료 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `T18` | 화면 테마 | `theme` — WireframeProfile.swift |

#### M02 프로필 사진 크기 안내 (DEC-056)

- MB는 십진 단위입니다. 사진 원본은 최대 20 MB (20,000,000 bytes), 변환 JPEG 결과는 최대 2 MB (2,000,000 bytes)입니다. 한도값은 허용하고 1 byte 초과는 거부합니다.
- 화면 안내도 MB를 십진 기준으로 표시합니다. 처리·저장은 기기 안에서만 하며 이번 변경에는 서버 업로드나 사진 권한 요청이 없습니다.

#### 후속 설정 화면 보정 — 계정 삭제 정책

- [ ] 삭제 버튼을 누르면 최종 확인 문구 `정말 탈퇴하시겠어요?`를 표시한다.
- [ ] 개인 데이터 삭제는 되돌릴 수 없음을 확인 화면에 분명히 알린다.
- [ ] 작성한 게시물과 댓글은 작성자 정보 없이 남는다고 안내한다.
- [ ] 최종 확인 시 유예 기간 없이 즉시 탈퇴 처리하고 모든 세션에서 로그아웃한다.
- [ ] 이 정책은 후속 설정 화면 보정 항목이다. 현재 화면 정렬 작업에는 계정 삭제 동작이나 백엔드 연동을 추가하지 않는다.

#### 후속 설정 화면 보정 — 프로필 사진 처리 정책

- [ ] 원본 사진은 최대 20 MB까지 선택하고 iOS 사진 선택기에서 HEIC/HEIF 등 입력 형식을 허용한다.
- [ ] 앱에서 자동 자르기·회전 보정과 메타데이터 제거를 한 뒤 JPEG로 변환한다. 출력은 최대 1024×1024, 업로드 파일은 2 MB 이하로 제한한다.
- [ ] 사진 라이브러리 권한 정책과 S3 업로드는 별도 승인·구현이 필요하다. 이 항목은 후속 정책 메모이며 이번 H03 목표 휠 수정에 포함하지 않는다.

### 포인트 · 상점 · `Points / Shop`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `B01` | 내 포인트 | `WireframePoints.swift` — 로컬 잔액, 거래 미리보기, 상점/내역/안내 이동; 다크 모드 샤드 대비와 라임 CTA 글자 대비 보정 |
| [x] | `B02` | 포인트 내역 | `WireframePoints.swift` — 기기 내 로컬 거래 목록 |
| [x] | `B03` | 포인트 내역 없음 | `WireframePoints.swift` — 빈 내역 상태 |
| [x] | `B04` | 포인트 안내 | `WireframePoints.swift` — 로컬 포인트 안내 |
| [x] | `B05` | 포인트 상점 | `WireframePoints.swift` — 예시 상품 카탈로그 및 분류; 선택 카테고리 라임 배경 글자 대비 보정 |
| [x] | `B06` | 꾸미기 아이템 상세 | `WireframePoints.swift` — 상품 상세, 미리보기, 구매 확인 |
| [x] | `B07` | 구매 완료 예시 | `WireframePoints.swift` — 로컬 구매 결과 |
| [x] | `B08` | 포인트 부족 예시 | `WireframePoints.swift` — 구매 제한 및 적립 안내 이동 |
| [x] | `B09` | 포인트 받는 방법 | `WireframePoints.swift` — 미연동 적립/광고 영역 안내 |
| [x] | `B10` | 러닝 카드 미리보기 | `WireframePoints.swift` — 현재 로컬 프로필/러닝 기록을 사용한 미리보기 |

구현 범위는 로컬 화면 이동과 예시 상태까지입니다. 상품/가격/초기 포인트는 UI 검증용 샘플이며 서버, 결제, 광고 재생, 보상 적립은 연결하지 않았습니다. PR #11에서 제공된 ZIP의 B05/B06 원본 SVG 경로와 CSS geometry를 SwiftUI로 반영하고 실제 화면을 대조했습니다. 이번 다크 모드 조정은 [포인트 에셋·대비 메모](REVIEW52_POINTS_DARK_MODE.md)를 참고합니다.

### 커뮤니티 · 크루 · `Community / Crew`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `C01` | 커뮤니티 피드 | `community` — 공개 피드·HOT 미리보기/검색 진입/좋아요; 익명·크루 전용 제외, HOT는 명시 fixture 표시만 사용; 서버 미연동 |
| [x] | `C02` | 게시판 | `communityBoards` — 원본 바로가기와 최신 글 |
| [x] | `C03` | 게시판 글 목록 | `communityBoardPosts` — 로컬 카테고리 목록 |
| [x] | `C04` | 게시물 | `communityPostDetail` — 사진·영상 첨부 목록, 사진 확대, 영상 포스터·재생/일시정지, 뷰어 종료 시 재생 정지; 좋아요·댓글·본인 글 수정/삭제; 로컬 상태 |
| [x] | `C05` | 글쓰기 | `communityCompose` — 새 글·본인 글 수정, 사진/영상 선택·순서·삭제와 C26 이탈 확인; 영상은 비동기 MP4 변환, 초안 세션 가드, 로컬 저장 |
| [x] | `C06` | 좋아요한 글 | `communityLikedPosts` — 내가 좋아요한 접근 가능한 글과 원본 빈 상태; 차단 글은 목록에서 숨김 |
| [x] | `C07` | 러닝 카드 | `communityCardPreview` — 방문/닫기, 사진 확대 |
| [x] | `C08` | 러너 프로필 (범위 구현) | 기본 프로필에 더보기 신고/차단 메뉴 연결; 차단은 로컬 콘텐츠를 숨김 |
| [x] | `C09` | 게시 미리보기 | `communityPreview` — 사진·영상 포스터를 표시하고 영상 재생 미리보기를 제공하는 로컬 게시 예시 |
| [x] | `C10` | 계정 인증 신청 | `communityVerificationForm` — 로컬 신청·중복/길이 검증; PR30 |
| [x] | `C11` | 인증 신청 상태 | `communityVerificationStatus` — 로컬 대기·승인·반려, review tool 전용 결과 예시; PR30 |
| [x] | `C12` | 공유 코스 | `communityCourseDetail` — 코스 요약·작성자·경로·따라달리기 |
| [x] | `C13` | 코스 공유 작성 | `communityCourseCompose` — 승인 로컬 계정·유효 기기 기록 선택·끝 위치 숨김·게시 미리보기 |
| [x] | `C14` | 따라달리기 미리보기 | `communityGhostRun` — 60배속 로컬 시간축, 재생/정지/처음부터/끝 위치 설정 |
| [x] | `C15` | 크루 탐색 | `communityCrewOverview` — 나의 크루/찾기, 지역·입문·주말 필터, 신청 상태 진입; 로컬 목록 예시 |
| [x] | `C16` | 크루 소개 | `communityCrewDetail` — 안내·정원·등급 조건, 가입/게시판 진입; 로컬 fixture |
| [x] | `C17` | 크루 가입 신청 | `communityCrewJoinForm` — 안내 확인, 선택 메모 300자, 취소/뒤로; 신청은 기기 내 예시 |
| [x] | `C18` | 가입 신청 상태 | `communityCrewApplicationStatus` — 로컬 대기·취소 상태 및 취소/복귀 전이; 실제 승인 결과 아님 |
| [x] | `C19` | 크루 게시판 | `communityCrewBoard` — 멤버 전용 진입, 활성 게시판별 공유 `WCommunityPost` 목록, C04 상세/수정/삭제 왕복, 안정된 크루·게시판 ID로 이름 변경·보관/복원 뒤 상태 유지 |
| [x] | `C20` | 크루 만들기·수정 | `communityCrewEditor` — 사진 로컬 선택, 이름 중복 확인, 소개·지역·등급 설정; 저장은 로컬 fixture |
| [x] | `C21` | 크루 관리 | `communityCrewManagement` — 크루·멤버 요약, 가입 안내·게시판·알림·대기 신청 관리 진입; 로컬 fixture |
| [x] | `C22` | 가입 신청 검토 | `communityCrewApplicationReview` — 신청 메모·정원·등급 확인, 로컬 승인/거절; 실제 가입·통지 아님 |
| [x] | `C23` | 신고 | 네 가지 사유와 선택 상세(최대 300자), 로컬 접수 |
| [x] | `C24` | 커뮤니티 알림 | `communityNotifications` — C08 전용 진입, 로컬 읽음 표시, C01/C04/C11/C18/C19 목적지 검증 및 접근 불가 대상 안내; 푸시·서버 미연동 |
| [x] | `C25` | 신고 접수 | 접수 완료와 작성자 차단 선택 모달 |
| [x] | `C26` | 작성 확인 참고 | C05/C13 작성 화면의 변경 스냅샷 기반 이탈 확인 — C09 미리보기 왕복은 보존; 별도 화면·메뉴 없음 |
| [x] | `C27` | 전체 게시판 | `communityAllBoards` — 분류 선택 후 해당 목록으로 이동 |
| [x] | `C28` | 커뮤니티 설정 | 원본 순서로 좋아요한 게시글·계정 인증·차단한 사용자·내 활동 기록 이동 |
| [x] | `C29` | 커뮤니티 검색 | `communitySearch` — 공개 게시물·프로필·크루별 결과, NFC·공백 정리·한국어 locale 대소문자 비교, 차단 사용자/크루 제외, 뒤로·상세/프로필/크루 복귀 때 검색어 유지; 로컬 fixture |
| [x] | `C30` | 팔로워·팔로잉 | `communityConnections` — 로컬 관계 목록과 카드 미리보기 |
| [x] | `C31` | 프로필 사진 | `communityPhotoViewer` — 등록 사진 확대 또는 빈 사진 안내 |
| [x] | `C32` | 크루 정보 | `communityCrewInformation` — Review55 표시 문구 `Lv.1`, `이메일데모`, `게시판 4/5개` 및 원본 소개·가입 안내 반영; C16/C19 진입, 화면 내 로컬 데모 안내 제거; 상태 데이터는 서버 미연결, matched-viewport pixel/motion QA 남음 |
| [x] | `C33` | 신청 중인 크루 | `communityCrewApplicationList` — 현재 사용자 대기 신청 목록, C18 상세 이동, 확인 후 로컬 취소; Review55 빈 상태 문구 유지, 화면 내 로컬 데모 안내 제거; 상태 데이터는 서버 미연결, matched-viewport pixel/motion QA 남음 |
| [x] | `C34` | 멤버 관리 | `communityCrewMemberList` — 역할별 멤버 목록, 크루장·운영자 접근 확인; 로컬 fixture |
| [x] | `C35` | 멤버 상세 관리 | `communityCrewMemberDetail` — 크루장만 운영자 지정/해제, 허용된 관리자만 주의 기록·멤버 내보내기; 로컬 fixture |
| [x] | `C36` | 가입 안내 설정 | `communityCrewGuidanceSettings` — 크루장·운영자 권한, 500자 제한, 저장/취소와 변경 폐기 확인; 로컬 fixture |
| [x] | `C37` | 게시판 관리 | `communityCrewBoardManagement` — 활성 5개 상한, 보관 목록과 복원; 글은 보존, 정원 재검사 |
| [x] | `C38` | 게시판 편집 | `communityCrewBoardEditor` — 생성·이름 수정·보관·복원; 로컬 fixture |
| [x] | `C39` | 크루 알림 관리 | `communityCrewAnnouncementEditor` — 제목 60자/내용 300자 제한, 회원 게시판에 로컬 예시로 표시; 실제 푸시 없음 |
| [x] | `C40` | 가입 신청 관리 | `communityCrewPendingApplications` — 대기 목록에서 C22 심사 후 복귀; 로컬 fixture |
| [x] | `C41` | 인기글 | `communityHotPosts` — 명시 `hot` fixture 게시물만 원래 피드 순서로 표시, 빈 상태·C04 왕복; 서버 집계 없음 |
| [x] | `C42` | 차단한 사용자 | 차단 목록 표시, 익명 차단 신원 가림, 로컬 차단 해제 |
| [x] | `C43` | 내 활동 기록 | `communityActivity` — 본인 로컬 열람 기록, 90일·최대 100개·중복 최신순; 차단 글은 숨김 |

#### 게시글 기능 backlog와 검증 구분

- C04 본인 게시글 수정은 제목·본문·게시판 등 현재 지원 데이터를 C05 초안으로 불러오고, 저장할 때 원래 게시글 ID를 갱신합니다. 변경 전 원본은 저장 전까지 유지하며 변경 없는 이탈은 바로 복귀하고, 변경 초안의 이탈은 C26 확인을 사용합니다. 예시 이미지·코스·댓글·반응 데이터는 텍스트 수정으로 덮어쓰지 않습니다. 크루 글은 `crewID`와 안정된 `crewBoardID`를 함께 갱신하고, 게시판 이름 변경에도 같은 글 ID와 관계를 유지합니다.
- C04 삭제는 확인 후 게시글과 포함된 댓글을 함께 제거합니다. 작성자는 자기 글을 수정·삭제할 수 있고, 크루장·운영자는 해당 크루 게시글·댓글만 삭제할 수 있습니다. 다른 사람의 글을 수정할 수 없습니다. 댓글 삭제는 tombstone을 남기고 답글 계층을 보존합니다.
- C19와 C04는 단일 `WireState.communityPosts`의 같은 `WCommunityPost`를 사용합니다. C19 행에서 C04 상세로 진입하고 편집·삭제 후에도 원래 크루/게시판으로 돌아옵니다. 비회원의 C19·C04 직접 접근은 내용을 숨기며, 크루 전용 글은 공개 피드·검색·HOT 결과에서 제외합니다. 보관 게시판의 글은 저장소에 남고 활성 게시판으로 복원될 때 C19에서 다시 표시됩니다.
- [x] C05/C09/C04 게시글 사진·영상 첨부의 로컬 UI를 구현했습니다. 사진은 기존 20 MB 원본/5 MB 변환 제한을 적용하고, 영상은 원본 50,000,000 bytes·15초 이하를 확인한 뒤 MP4·1080p(긴 변 1,920/짧은 변 1,080 이하)·20,000,000 bytes 이하로 변환합니다. 사진과 영상 합계는 10개/100,000,000 bytes 이하입니다. 영상 선택·중복 차단·취소 가능한 변환·포스터·재생/일시정지·닫을 때 정지, 초안/게시 파일의 게시·폐기·수정·삭제 수명주기를 지원합니다. C26은 첨부 ID와 순서를 비교하고 비동기 요청은 생성 토큰과 초안 ID를 다시 확인합니다. 데이터는 앱 전용 임시 저장소에만 있으며 서버 업로드/푸시는 연결하지 않았습니다.
- [x] 영상 처리 경계·손상 파일·요청 무효화·초안/게시 파일 수명주기와 C05→C09→영상 미리보기 및 C01→C04→영상 재생/일시정지/닫기 후 정지를 합성 fixture로 확인합니다. PhotosPicker의 실사용 취소/빠른 재선택 경쟁을 UI 자동화로 재현하지는 않았으므로 해당 OS picker 경쟁의 실제 기기 동작은 남은 검증 항목입니다. 전체 source-to-app 픽셀·모션 QA도 계속 남아 있습니다.
- 검증 상태는 분리합니다. 화면·전이 구현, 기능 테스트 통과, 원본 대조 픽셀·모션 검수는 각각 별도 기준이며, 이번 코드 변경의 기능 테스트 완료도 전체 시각 QA 완료를 뜻하지 않습니다.

신고는 네 가지 사유와 모든 사유에 사용할 수 있는 선택 상세 입력(최대 300자)을 제공하고, 접수 후 작성자 차단 선택을 표시합니다. 차단하면 해당 사용자의 글·댓글과 양방향 노출을 로컬에서 제한하고 C42에서 해제할 수 있습니다. 신고·차단 상태는 기기 내 fixture이며 서버 전송은 없습니다. C28 개인 목록은 현재 계정의 좋아요 상태와 로컬 열람 이력을 사용합니다. 열람 이력은 메모리 안의 검토 fixture로만 유지하며 실제 개인 정보나 서버 호출은 추가하지 않습니다.

C15–C19는 Review52 원본의 탐색→소개→신청→상태→회원 게시판 흐름을 로컬 예시로 구현합니다. C20–C22는 크루 생성·수정 폼, 관리 메뉴, 신청자 메모·정원·등급 확인과 로컬 승인/거절을 추가합니다. C32는 크루 소개·게시판에서 진입하는 읽기 전용 정보 화면으로 지역, 멤버/20, 가입 등급, 크루장, 게시판/5와 가입 안내를 보여 줍니다. Review55 기준 화면의 크루 레벨 `Lv.1`, 크루장 `이메일데모`, 게시판 표기를 반영합니다. 이전 `운영 기준 미정`은 구현 메모에 불과해 원본 표시보다 우선할 사용자 승인 정책이 아니므로 제거했습니다. C32/C33에서는 원본에 없는 로컬 데모 안내 문구를 제거했습니다. C33은 현재 사용자의 대기 신청만 나열하며 행을 누르면 C18로, 취소는 확인 후 해당 신청 하나의 로컬 상태만 `cancelled`로 바꿉니다. 이 앱의 신청 상태는 계속 로컬에서만 동작하며 서버에 저장·변경되지 않습니다. C34–C35는 크루장·운영자용 멤버 목록과 상세 관리를 제공합니다. 크루장만 다른 멤버의 운영자 권한을 바꿀 수 있고, 운영자는 일반 멤버만 주의 기록·내보내기할 수 있습니다. 크루장 본인·현재 사용자는 관리 대상에서 제외합니다. 주의 기록은 최대 300자이며 화면의 로컬 기록만 바뀌고 실제 전달되지 않습니다. 내보내기는 확인 후 로컬 멤버 목록과 운영자 집합에서만 제거하며 앱 재실행 시 초기화됩니다. 원본 C34–C35에 소유권 양도 동작은 없어 화면을 새로 만들지 않았습니다. 크루 사진은 기존 기기 이미지 선택 흐름으로 검증해 메모리에 보관하며 업로드하지 않습니다. 가입 신청, 크루 변경, 심사 결과와 멤버 역할·주의·내보내기는 서버에 저장·통지되지 않습니다. C36–C40은 가입 안내 편집, 게시판 생성·이름 수정·보관/복원, 로컬 알림 예시, 대기 신청 목록을 구현합니다. 게시판은 기존 backend 계약에 맞춰 삭제 대신 보관하며, 보관된 게시글을 유지하고 복원 시 활성 5개 상한을 다시 확인합니다. 알림은 회원용 게시판에 최대 3개까지 세션 내 로컬 예시로 보여 주며 실제 푸시나 서버 요청을 보내지 않습니다. 가입 안내·게시판·알림·신청 상태는 앱 재실행 시 초기화됩니다. 확정 제품 정책은 크루장 포함 총 20명 정원과 활성 게시판 최대 5개입니다. 기본 fixture는 활성 게시판 4개와 최대 5개 UI를 사용합니다. 레벨·유료 확장 정책은 미정이며 활성화하지 않습니다. 크루장·운영자 권한은 로컬 예시일 뿐, 서버 역할·권한 판정이 아닙니다. C10–C14의 인증 신청·승인과 코스 공유·재생도 실제 계정 인증, 서버 게시, GPS/위치 수집 또는 실시간 공유가 아닙니다. 실제 서비스 연결 전에는 사용자 신원·역할·가입 상태, 크루 저장, 승인/취소/알림, 멤버 전용 권한 검사의 서버 계약과 정책이 필요합니다. C32/C33의 content copy를 Review55와 대조했으며 full matched-viewport pixel/motion QA는 계속 남아 있습니다.

인증·가입·비밀번호 재설정 화면은 서버/API나 실제 이메일 발송에 연결되어 있지 않습니다. 재설정 A24–A28은 가입 A19–A23의 검수 규칙과 UI 구조를 재사용하지만 별도 세션·발급기·증명 ID를 사용하며, 가입 상태를 읽거나 변경하지 않습니다. 각 로컬 challenge 안에서 OTP 발급기는 이전에 발행한 여섯 자리 값을 재사용하지 않습니다. 실제 발급·비밀번호 변경 권위는 서버에 두어야 하며, 5분 만료·60초 재요청·5회 잠금은 로컬 검토 흐름으로 보안 인증 구현이 아닙니다. 비밀번호 재설정 완료 화면은 실제 비밀번호나 로그인 상태를 바꾸지 않습니다. 일반 사용자 흐름은 서버 닉네임 사용 가능 여부를 조회하지 않으며, 고정 닉네임 fixture 검사는 검토 모드에만 적용합니다. 실제 계정 생성이나 인증 결과로 간주하지 않습니다.
