# Review55 C08 내 프로필 헤더

## 기준과 확인

- Review55 C08 화면을 실제 브라우저 렌더로 확인했습니다: [전체 화면 와이어프레임](https://running-wireframe-review-01.popeye0618.chatgpt.site/).
- 기준 main은 전달받은 PR69 병합 커밋 `e229f9f2e3c2a7d812312544af13b24d8563fc64`입니다. 로컬에 있는 PR69 최종 커밋 `2259e272a276fb3325845e4fa74ab43a8b9bc4b2`의 tree는 `bd7a5cb4159ffe6b5b56b930ee2191f56da26dfd`이며, 앞선 확인에서 main과 171개 파일이 일치한 기준입니다. 병합 커밋 객체는 로컬 체크아웃에 없어서 feature branch는 이 tree에서 시작했습니다.
- 설치 앱은 `com.movtorun.mov` `1.0 (1)`, 기존 iPhone 17 Pro 시뮬레이터 `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B` (iOS 26.3.1)에서 확인했습니다.

## 확인된 차이와 수정

기존 C08 본인 프로필은 왼쪽에 앱 로고, 가운데 `내 정보` 제목, 오른쪽에 알림과 설정을 표시했습니다. Review55는 제목을 두지 않고 로고를 화면 중앙에 배치하며 알림·설정을 오른쪽에 둡니다. 본인 프로필 C08에만 중앙 로고 구성을 적용했습니다. 알림은 C24, 설정은 C28로 이동하며 두 화면의 뒤로가기는 C08로 돌아옵니다.

게시글·팔로워·팔로잉 지표는 기준 화면과 일치했습니다. 본인 fixture는 `0 / 1 / 0`이고, 타인 fixture는 `2 / 2 / 2`입니다. 타인 프로필에는 이름, 뒤로가기, 더보기, 팔로우 동작을 유지하고 본인 프로필의 알림·설정 액션은 표시하지 않습니다. 타인 프로필에서 연결 목록으로 이동한 뒤에는 C08, 카드 미리보기 C07, 원 게시물 C04로 돌아옵니다. 정책 변경은 하지 않았습니다.

## 캡처

실제 UI 테스트의 첨부 화면입니다.

| 화면 | 파일 |
|---|---|
| 본인 프로필 · 라이트 | [C08-own-profile-light.png](C08-own-profile-light.png) |
| 본인 프로필 · 다크 | [C08-own-profile-dark.png](C08-own-profile-dark.png) |
| 타인 프로필 · 라이트 | [C08-other-profile-light.png](C08-other-profile-light.png) |

## 검증

- `testCommunityOwnProfileHeaderMatchesReview55AndKeepsActions`: 중앙 위치, 알림/설정 비중첩, 지표, C24/C28 복귀, 다크 모드를 확인했습니다.
- `testCommunityProfilePreviewVisitPhotoFollowAndProfileContent`: 타인 프로필 지표와 팔로우, C30/C08/C07/C04 복귀를 확인했습니다.
- 최종 실행은 2개 모두 통과했습니다. 결과 번들: `/tmp/MovToRun-C08-CommunityProfile-20261014-Final.xcresult`.
- 테스트는 고유 `UserDefaults` fixture suite를 사용했습니다. 표준 앱 설정 plist의 SHA-256이 실행 전후 `bd46e3a4703bab31ffb66c3c2d82184c28348058d9c5aff54d0cf54072af49a6`로 같았고, 재실행 뒤에도 저장된 앱 화면 정보가 유지됨을 확인했습니다.
