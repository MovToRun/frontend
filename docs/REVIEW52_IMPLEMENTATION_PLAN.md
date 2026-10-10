# Review52 화면 매핑 및 구현 순서

## 기준과 확인 상태

- 참조 기준: Review52, 140개 화면/상태, 제공된 원본 revision `commit645150b7f3a99a56279213e174ebb723baf40f7a`.
- 사용자가 제공한 `running-app-source.zip`의 `dist/`를 로컬 기준 원본으로 사용합니다. CSS/JS와 해당 상태 화면을 확인하고, 390×790 viewport로 렌더해 앱 캡처와 대조합니다. Mac Safari의 사용자가 열어 둔 탭 자체는 세션에서 읽을 수 없으므로 탭 화면을 직접 촬영한 것으로 표현하지 않습니다.
- 현재 구현 경로는 기준점 커밋 `0201a5a1ae90ca1cdd356ec243077b75ecf47995`의 `WireframeCore.screenView` 분기와 대상 파일을 기준으로 기록했습니다. 전용 분기가 없는 상태는 `informationPage` 기본 분기로 표시했습니다. ID 문자열이 코드/테스트에 있더라도 전용 UI 구현으로 간주하지 않습니다.
- 140개 모두 체크리스트에 남깁니다. `L06`처럼 개발 참고용인 상태, 오류·빈 화면, 예시·전이 전용 상태는 회귀 점검 대상으로 유지하되 일반 사용자 메뉴에 노출하지 않습니다.

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
| 남음 | 인증 `E01–E02`, `A02–A23` | `A01`, `A02`, `A03`, `A04` 로컬 구현 제외; A02/A03 캡처 대조는 남음 |
| 남음 | 홈·목표·러닝 `H02`, `H05–H06`, `H10–H11`, `P01–P05`, `R01`, `R03–R12`, `S01–S05` | H03·H07–H09 제외 |
| 남음 | 기록·공유 `L02–L03`, `L05–L07`, `Q01–Q03` | PR #11에서 확인한 L01/L04 제외 |
| 남음 | 프로필·설정·알림 `M01–M02`, `N01`, `T01–T18` | 후속 묶음 |
| 남음 | 포인트·상점 `B01–B04`, `B07–B10` | PR #11에서 확인한 B05/B06 제외 |
| 제외 | 커뮤니티 `C01–C43` | 사용자가 이번 작업에서 신규 커뮤니티 기능을 제외함 |

전체 140개 상태의 통합 시각 QA는 아직 수행하지 않았습니다. 작은 기능 묶음별 대조를 이어가며 이 coverage 표를 갱신합니다.

## 현재 구조 요약

`WireframeCore.swift`가 루트 화면/상태 전이와 5탭을 관리합니다. 인증, 홈·목표·통계, 러닝·기록, 프로필 설정, 포인트 상점, 공유 화면은 각각 `WireframeAuth.swift`, `WireframeHome.swift`, `WireframeRun.swift`, `WireframeProfile.swift`, `WireframePoints.swift`, `WireframeShare.swift`에 있습니다. 커뮤니티 `C01–C43`의 신규 구현은 현재 범위에서 제외합니다. 라우트 표시는 전용 UI 구현과 미구현 상태를 구분하는 기준입니다.

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

반응형 기준은 320pt 안팎부터 큰 iPhone 폭, 세로 공간, safe area, 키보드, 긴 문구/줄바꿈, Dynamic Type을 포함합니다. 고정 좌표로 전체 화면을 늘리지 않고 디자인 계층을 유지합니다. 러닝 지도/접이식 패널, 커뮤니티 피드/하단바/FAB, 공유 이미지 편집기는 전용 적응형 점검을 둡니다.


### 진입 · 인증 · 온보딩 · `Auth / Onboarding`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [ ] | `E01` | 네이티브 시작 | `BrandMark` — WireframeCore.swift |
| [ ] | `E02` | 앱 스플래시 | `WSplash` — WireframeCore.swift |
| [ ] | `A01` | 로그인 | `authForm` — WireframeAuth.swift |
| [x] | `A02` | 필수 동의 | `consents` — WireframeAuth.swift; 각 내용 확인 후 해당 항목 체크, 일부 동의 차단, 전체 동의 순차 모션/취소 복구 |
| [x] | `A03` | 첫 프로필 | `weightProfile` — WireframeProfile.swift; 닉네임 필수/길이 검증, 검토모드 전용 fixture 충돌 점검, 선택 체중, 원본 완료 문구 |
| [x] | `A04` | 로그인 실패 | `loginFailure` — WireframeAuth.swift; 취소·연결 끊김 문구 및 A01 재시도 로컬 흐름 |
| [x] | `A06` | 약관·개인정보 검토 | `consentReview` — 주제별 내용 확인 후 해당 필수 동의만 반영 |
| [x] | `A07` | 이메일 회원가입 | `authForm` — 8~20자 ASCII 영문·숫자 필수, 기호 선택 |
| [x] | `A10` | 비밀번호 재설정 요청 | 재설정 전용 이메일 상태와 형식 검증 — WireframeAuth.swift |
| [x] | `A11` | 재설정 요청 확인 예시 | 메일 발송/계정 존재를 가장하지 않고 재설정 코드 검수로 이동 — WireframeInfo.swift |
| [x] | `A12` | 새 비밀번호 예시 | A24 코드 증명 필수, 공통 영문·숫자 정책과 확인값 일치, 실제 비밀번호 미변경 — WireframeAuth.swift |
| [x] | `A13` | 재설정 완료 화면 | 로컬 완료 안내, 계정 로그인 상태/비밀번호 변경 없음 — WireframeInfo.swift |
| [ ] | `A14` | 소셜 인증 결과 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A15` | 회원가입 완료 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
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
| [ ] | `L02` | 기록 없음 | `records` — WireframeRun.swift |
| [ ] | `L03` | 기록 조회 실패 | `records` — WireframeRun.swift |
| [x] | `L04` | 기록 상세 | `recordDetail` — WireframeRun.swift; PR #11 Review52 source 대조 |
| [ ] | `L05` | 구간 기록 · 페이스 | `splits` — WireframeRun.swift |
| [ ] | `L06` | 기록 편집 · 개발 참고 | `recordEdit` — WireframeRun.swift |
| [ ] | `L07` | 러닝 기록 삭제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
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
| [ ] | `C01` | 커뮤니티 피드 | `community` — WireframeCore.swift (현재 안내/placeholder) |
| [ ] | `C02` | 게시판 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C03` | 게시판 글 목록 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C04` | 게시물 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C05` | 글쓰기 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C06` | 좋아요한 글 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C07` | 러닝 카드 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C08` | 러너 프로필 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C09` | 게시 미리보기 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C10` | 계정 인증 신청 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C11` | 인증 신청 상태 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C12` | 공유 코스 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C13` | 코스 공유 작성 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C14` | 따라달리기 미리보기 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C15` | 크루 탐색 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C16` | 크루 소개 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C17` | 크루 가입 신청 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C18` | 가입 신청 상태 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C19` | 크루 게시판 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C20` | 크루 만들기·수정 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C21` | 크루 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C22` | 가입 신청 검토 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C23` | 신고 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C24` | 커뮤니티 알림 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C25` | 신고 접수 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C26` | 작성 확인 참고 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C27` | 전체 게시판 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C28` | 커뮤니티 설정 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C29` | 커뮤니티 검색 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C30` | 팔로워·팔로잉 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C31` | 프로필 사진 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C32` | 크루 정보 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C33` | 신청 중인 크루 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C34` | 멤버 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C35` | 멤버 상세 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C36` | 가입 안내 설정 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C37` | 게시판 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C38` | 게시판 편집 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C39` | 크루 알림 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C40` | 가입 신청 관리 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C41` | 인기글 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C42` | 차단한 사용자 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `C43` | 내 활동 기록 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |

인증·가입·비밀번호 재설정 화면은 서버/API나 실제 이메일 발송에 연결되어 있지 않습니다. 재설정 A24–A28은 가입 A19–A23의 검수 규칙과 UI 구조를 재사용하지만 별도 세션·발급기·증명 ID를 사용하며, 가입 상태를 읽거나 변경하지 않습니다. 각 로컬 challenge 안에서 OTP 발급기는 이전에 발행한 여섯 자리 값을 재사용하지 않습니다. 실제 발급·비밀번호 변경 권위는 서버에 두어야 하며, 5분 만료·60초 재요청·5회 잠금은 로컬 검토 흐름으로 보안 인증 구현이 아닙니다. 비밀번호 재설정 완료 화면은 실제 비밀번호나 로그인 상태를 바꾸지 않습니다. 일반 사용자 흐름은 서버 닉네임 사용 가능 여부를 조회하지 않으며, 고정 닉네임 fixture 검사는 검토 모드에만 적용합니다. 실제 계정 생성이나 인증 결과로 간주하지 않습니다.
