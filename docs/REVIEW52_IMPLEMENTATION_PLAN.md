# Review52 화면 매핑 및 구현 순서

## 기준과 확인 상태

- 참조 기준: Review52, 140개 화면/상태, 제공된 원본 revision `commit645150b7f3a99a56279213e174ebb723baf40f7a`.
- 상태명은 읽기 전용 Review52 Site의 화면 트리에서 확인했습니다. 원본 ZIP(`running-app-source.zip`, Library v0, 16,645,141 bytes)과 HTML(v51)은 Library 공식 Mac materialization이 각각 HTTP 403을 반환해 아직 로컬에서 읽지 못했습니다. 따라서 CSS/JS, 화면 내부 세부, 원본 모션 값을 대조하지 못한 상태이며 이를 확인한 것으로 취급하지 않습니다.
- 현재 구현 경로는 기준점 커밋 `0201a5a1ae90ca1cdd356ec243077b75ecf47995`의 `WireframeCore.screenView` 분기와 대상 파일을 기준으로 기록했습니다. 전용 분기가 없는 상태는 `informationPage` 기본 분기로 표시했습니다. ID 문자열이 코드/테스트에 있더라도 전용 UI 구현으로 간주하지 않습니다.
- 140개 모두 체크리스트에 남깁니다. `L06`처럼 개발 참고용인 상태, 오류·빈 화면, 예시·전이 전용 상태는 회귀 점검 대상으로 유지하되 일반 사용자 메뉴에 노출하지 않습니다.

## 현재 구조 요약

`WireframeCore.swift`가 루트 화면/상태 전이와 5탭을 관리합니다. 포인트와 상점 루트는 현재 빈 placeholder이며, 커뮤니티 루트는 `C01` 안내 상태만 갖습니다. 인증, 홈/러닝, 기록, 프로필 구현은 각각 `WireframeAuth.swift`, `WireframeHome.swift`/`WireframeRun.swift`, `WireframeRun.swift`, `WireframeProfile.swift`에 있습니다. 따라서 이 문서의 라우트 표시는 실제 전용 UI가 있는지를 확인하는 기준이며, 미구현 행을 숨기지 않습니다.

## 기능 브랜치 순서와 완료 기준

| 순서 | 브랜치 | 상태 묶음 | 완료 기준 |
|---|---|---|---|
| 1 | `feature/common-design-navigation` | 공통 토큰·타이포·적응형 레이아웃·안전영역·키보드·탭/네비 기반 | 작은~큰 iPhone, 큰 글자, 라이트/다크, safe area에서 공통 구조가 깨지지 않고 아래 화면 묶음의 기반을 제공 |
| 2 | `feature/auth-onboarding` | E01–E02, A01–A23 | 가입/로그인/동의/인증/오류/빈/예시 흐름, 로컬 fixture와 실제 서버 부재 표시 |
| 3 | `feature/home-run-goals` | H00–H06, H10–H11, P01–P05, R01–R12, S01–S05 | 지도, 접히는 러닝 패널, 타이머/일시정지/저장 상태, 목표, 권한·오류 상태, 반응형 전이 |
| 4 | `feature/records-stats-sharing` | H07–H09, L01–L07, Q01–Q03 | 기록/통계 빈·오류 상태, 로컬 편집·삭제, 공유 이미지 편집 및 저장 결과 예시 |
| 5 | `feature/profile-settings-notifications` | M01–M02, N01, T01–T18 | 프로필·러닝카드·설정·테마·계정·알림 흐름과 로컬 상태 |
| 6 | `feature/points-shop` | B01–B10 | 가상 잔액/내역/아이템, 구매 결과는 예시로 표시하며 실제 결제·차감 없음 |
| 7 | `feature/community-crew` | C01–C43 | 앱 별도 5탭 구조, 피드/FAB/게시글/댓글/검색/크루 흐름, 가상 데이터·서버 미연동 표시 |
| 8 | `feature/review52-visual-qa` | 전체 140 상태 × 라이트/다크 | 전체 구현 뒤 통합 시각 검수 1회. 차이는 수정 후 해당 상태만 재검수 |

현재 `feature/home-running-goals-ui` 구현은 31개 대상 상태를 로컬 시뮬레이션 범위에서 완료했습니다. 완료 표시는 화면·전이·기기 로컬 상태 구현을 뜻하며 실제 GPS 센서/위치 권한 요청, 백엔드 저장·동기화는 포함하지 않습니다. 러닝 지도는 가상 사용자 위치와 화면 이동(pan)·재중심화를 지원하며, 재중심화와 패널 열림/닫힘 시 사용자가 보이는 지도 영역의 가운데를 유지합니다. 각 기능 브랜치는 기준점 `main`에서 분기해 해당 상태만 수정합니다. 기능 단위 빌드/자동 테스트와 diff 검토 후 커밋·푸시하고 draft PR을 만든 뒤 exact head/diff/검증 결과를 부모 검토에 넘깁니다. 부모 검토를 통과한 PR만 머지하고 다음 브랜치로 진행합니다. 포인트/구매·인증·소셜·위치·동기화는 백엔드/API 연결 없이 교체 가능한 로컬 상태로만 표현하며 서버 성공으로 오인시키지 않습니다.

반응형 기준은 320pt 안팎부터 큰 iPhone 폭, 세로 공간, safe area, 키보드, 긴 문구/줄바꿈, Dynamic Type을 포함합니다. 고정 좌표로 전체 화면을 늘리지 않고 디자인 계층을 유지합니다. 러닝 지도/접이식 패널, 커뮤니티 피드/하단바/FAB, 공유 이미지 편집기는 전용 적응형 점검을 둡니다.


### 진입 · 인증 · 온보딩 · `Auth / Onboarding`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [ ] | `E01` | 네이티브 시작 | `BrandMark` — WireframeCore.swift |
| [ ] | `E02` | 앱 스플래시 | `WSplash` — WireframeCore.swift |
| [ ] | `A01` | 로그인 | `authForm` — WireframeAuth.swift |
| [ ] | `A02` | 필수 동의 | `consents` — WireframeAuth.swift |
| [ ] | `A03` | 첫 프로필 | `weightProfile` — WireframeProfile.swift |
| [ ] | `A04` | 로그인 실패 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A06` | 약관·개인정보 검토 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A07` | 이메일 회원가입 | `authForm` — WireframeAuth.swift |
| [ ] | `A10` | 비밀번호 재설정 요청 | `authForm` — WireframeAuth.swift |
| [ ] | `A11` | 재설정 요청 확인 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A12` | 새 비밀번호 예시 | `authForm` — WireframeAuth.swift |
| [ ] | `A13` | 재설정 완료 화면 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A14` | 소셜 인증 결과 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A15` | 회원가입 완료 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A16` | 이메일 로그인 연결 | `authForm` — WireframeAuth.swift |
| [ ] | `A17` | 이메일 비밀번호 관리 | `authForm` — WireframeAuth.swift |
| [ ] | `A18` | 이메일 설정 완료 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `A19` | 회원가입 이메일 인증 | `verification` — WireframeAuth.swift |
| [ ] | `A20` | 이메일 인증 코드 오류 | `verification` — WireframeAuth.swift |
| [ ] | `A21` | 이메일 인증 코드 만료 | `verification` — WireframeAuth.swift |
| [ ] | `A22` | 이메일 인증 시도 제한 | `verification` — WireframeAuth.swift |
| [ ] | `A23` | 이메일 인증 코드 재요청 | `verification` — WireframeAuth.swift |

### 홈 · 러닝 · 목표 · `Home / Run / Goals`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [x] | `H00` | 메인 홈 | `home` — WireframeHome.swift |
| [x] | `H01` | 지도 러닝 준비 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H02` | 첫 러닝 준비 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H03` | 이번 러닝 목표 | `sessionGoal` — WireframeHome.swift |
| [x] | `H04` | 주간 목표 | `weeklyGoal` — WireframeHome.swift |
| [x] | `H05` | 진행 중인 러닝 | `ready` — WireframeHome.swift / WireframeRun.swift |
| [x] | `H06` | 임시 기록 복구 | `informationPage` — WireframeInfo.swift |
| [ ] | `H07` | 주간·월간 요약 | `statistics` — WireframeHome.swift |
| [ ] | `H08` | 통계 데이터 없음 | `statistics` — WireframeHome.swift |
| [ ] | `H09` | 목표 초과 달성 | `statistics` — WireframeHome.swift |
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
| [ ] | `L01` | 기록 목록 | `records` — WireframeRun.swift |
| [ ] | `L02` | 기록 없음 | `records` — WireframeRun.swift |
| [ ] | `L03` | 기록 조회 실패 | `records` — WireframeRun.swift |
| [ ] | `L04` | 기록 상세 | `recordDetail` — WireframeRun.swift |
| [ ] | `L05` | 구간 기록 · 페이스 | `splits` — WireframeRun.swift |
| [ ] | `L06` | 기록 편집 · 개발 참고 | `recordEdit` — WireframeRun.swift |
| [ ] | `L07` | 러닝 기록 삭제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [x] | `Q01` | 러닝 공유 만들기 | `ShareImageEditor` — `WireframeShare.swift`; 로컬 PNG 작성, 피드·스토리 캔버스와 기록 오버레이 편집. 선택 미디어 입력 검증. 무음 MP4/WebM 출력은 미구현 |
| [x] | `Q02` | 러닝 공유 저장 | `ShareOutputView` — `WireframeShare.swift`; PNG 크기 확인 및 파일 앱 저장 경로 선택. 실패 시 임시 갤러리에 보존·재시도 안내. Photos 직접 저장 및 동영상 출력은 미구현 |
| [x] | `Q03` | 이 기록의 공유 콘텐츠 | `ShareGallery`/`ShareWorkspace` — `WireframeShare.swift`; 세션 메모리 갤러리·삭제, 기록당 64MB 임시 저장 한도, 로그아웃·계정 전환 시 비움 |

### 프로필 · 설정 · 알림 · `Profile / Settings / Notifications`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [ ] | `M01` | 내 정보 · 러닝 카드 | `profile` — WireframeProfile.swift |
| [ ] | `M02` | 러닝 카드 편집 | `profileEdit` — WireframeProfile.swift |
| [ ] | `N01` | 알림 · 예시 | `notifications` — WireframeInfo.swift |
| [ ] | `T01` | 설정 | `settings` — WireframeProfile.swift |
| [ ] | `T02` | 프로필·체중 | `weightProfile` — WireframeProfile.swift |
| [ ] | `T03` | 단위 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T04` | 개인정보·데이터 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T05` | 로그인 수단 관리 | `providers` — WireframeAuth.swift |
| [ ] | `T06` | 로그인 수단 연결 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T07` | 기존 로그인 안내 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T08` | 로그인 연결 해제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T09` | 마지막 수단 해제 차단 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T10` | 로그아웃 확인 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T11` | 계정 삭제 확인 | `deleteAccount` — WireframeAuth.swift |
| [ ] | `T12` | 삭제 완료 시뮬레이션 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T13` | 기기 데이터 삭제 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T14` | 진행 중 러닝 보호 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T15` | 현재 계정 재확인 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T16` | 탈퇴 요청 처리 중 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T17` | 로그인 수단 연결 완료 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `T18` | 화면 테마 | `theme` — WireframeProfile.swift |

### 포인트 · 상점 · `Points / Shop`

| 완료 | 상태 | 화면명 | 현재 SwiftUI 경로(기준점) |
|---|---|---|---|
| [ ] | `B01` | 내 포인트 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B02` | 포인트 내역 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B03` | 포인트 내역 없음 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B04` | 포인트 안내 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B05` | 포인트 상점 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B06` | 꾸미기 아이템 상세 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B07` | 구매 완료 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B08` | 포인트 부족 예시 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B09` | 포인트 받는 방법 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |
| [ ] | `B10` | 러닝 카드 미리보기 | `informationPage` 기본 분기 — 전용 `screenView` case 없음 |

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
