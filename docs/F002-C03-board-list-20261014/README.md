# 커뮤니티 게시판 화면 검수

검수일: 2026-10-14

앱: `com.movtorun.mov` · 설치된 버전 1.0 (build 1)

시뮬레이터: iPhone 17 Pro (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`)

기준 main: `db35b93260fa1c769c5a1ce4c28a8a10aa5e8a64` · tree `20043ea3b8bb7f74f3b1b6c7f9f9fb58f42e41d4`

## 원인과 수정

실행 중인 앱은 1.0 (1)이었습니다. 기준 main의 커뮤니티 전용 탭 판정에는 피드(C01), 게시판(C02), 크루(C15), 내 프로필(C08)만 포함되어 상세 게시판(C03) 진입 시 전용 하단바가 사라졌습니다. C03의 게시판 선택 상태도 연결되지 않았습니다. 글쓰기 버튼은 페이지 하단 고정 영역에 있어 하단바의 숨김/복귀에 맞춰 움직이지 않았습니다.

C03을 전용 커뮤니티 탭의 게시판 경로로 묶고, 게시판 화면의 스크롤에 따라 전용 바를 숨기고 복귀시킵니다. 글쓰기와 맨 위로 버튼은 같은 하단 기준에 맞춰 움직이며, 게시글 발행 또는 취소 후 선택한 C03 게시판으로 돌아옵니다. C01 피드와 C02 게시판은 기존 와이어프레임 구성으로 확인했습니다. 중앙 홈은 실제 Mov 홈 화면으로 이동하고, 좋아요 목록은 프로필 설정 경로 안에서 확인했습니다.

C01과 C03 캡처에서 상태 표시줄 아래 안전 영역, 헤더 아이콘 배치, 제목과 아이콘의 분리를 확인했습니다. C01 헤더는 전체 게시판·브랜드·검색 아이콘이 각각 한 번씩 나타납니다. C03은 뒤로가기 아이콘 하나와 게시판 제목이 안전 영역 아래 표시됩니다.

## 실제 화면 캡처

| 화면 | 증거 |
| --- | --- |
| 피드 헤더 (라이트) | [C01-community-feed-header-light.png](C01-community-feed-header-light.png) |
| 게시판 (라이트 / 다크) | [C02-community-boards-light.png](C02-community-boards-light.png) · [C02-community-boards-dark.png](C02-community-boards-dark.png) |
| 게시판 글 목록 (다크) | [C03-board-posts-dark.png](C03-board-posts-dark.png) |
| C03 하단바 표시 / 숨김 / 복귀 | [C03-board-compose-visible.png](C03-board-compose-visible.png) · [C03-board-compose-hidden.png](C03-board-compose-hidden.png) · [C03-board-compose-restored.png](C03-board-compose-restored.png) |
| 중앙 홈 실제 화면 | [H00-mov-home-centered.png](H00-mov-home-centered.png) |
| 크루 / 내 프로필 / 프로필 설정 / 좋아요 목록 | [C15-community-crew.png](C15-community-crew.png) · [C08-community-profile.png](C08-community-profile.png) · [C28-community-profile-settings.png](C28-community-profile-settings.png) · [C06-community-liked-posts.png](C06-community-liked-posts.png) |

캡처는 지정된 iPhone 17 Pro 시뮬레이터에서 UI 테스트 중 저장했습니다. 테스트 전후 앱 설정 데이터 해시는 `bd46e3a4703bab31ffb66c3c2d82184c28348058d9c5aff54d0cf54072af49a6`로 같았습니다.

## 검증

최종 C03 구현으로 지정 시뮬레이터에서 수행한 집중 UI 테스트:

- R9 `testCommunityC03BarFloatingComposeAndBoardReturnFlows`: 1/1 통과 — 반복 글 작성·취소·발행, 게시판 목록 스크롤, 하단바 숨김/복귀, 글쓰기/맨 위로 버튼 위치.
- R10 `testCommunityC03BackStackSurvivesNestedBoardsAndRootTabs`: 1/1 통과 — 중첩 게시판 뒤로가기, 커뮤니티 중앙 홈, 앱 루트 커뮤니티 탭 전환.
- R11 `testCommunityPrimaryTabsDarkAndShortScreensKeepHeaderAndBottomBar`: 1/1 통과 — 라이트/다크 커뮤니티 경로, 짧은 화면, C03 안전 영역 및 헤더 확인.

결과 번들: `/private/tmp/MovToRun-F002-C03-BoardUI-R9-20261014.xcresult`, `/private/tmp/MovToRun-F002-C03-BoardUI-R10-20261014.xcresult`, `/private/tmp/MovToRun-F002-C03-BoardUI-R11-20261014.xcresult`.

전체 테스트 스위트는 실행하지 않았습니다. 서버 연결, 자격 증명, 배포는 사용하지 않았습니다.
