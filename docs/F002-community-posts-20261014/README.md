# Review55 C03–C05 and post comments

## Reference and scope

I compared the installed app with the Review55 community mosaic at [the existing wireframe review](https://running-wireframe-review-01.popeye0618.chatgpt.site/). The source inventory IDs are C03 = 게시판 글 목록, C04 = 게시물, and C05 = 글쓰기. This note records one C05 correction and the adjacent C03/C04 observations; it does not claim a complete audit of all 140 screens.

The code change is limited to how a new composer determines its context. A public draft has no `communityDraftCrewID`, so it must show the public board picker even if the user has a crew selected elsewhere. Crew drafts keep their explicit crew name, fixed board, and local-only notice.

## Comparison

| Screen | Review55 reference | Installed app / result |
|---|---|---|
| C03 · board posts | Community five-item navigation with Home centered, plus a floating compose action. | The app still shows a back/title header and a full-width pinned `글쓰기` action without the community bar. This is a separate visible mismatch and remains outside this small C05 change. The wireframe fixture has 4 stories while this app fixture has 1; I left fixture data unchanged. |
| C04 · post detail | Selected board name and overflow action in the header, post, comments, and replies. | The header shows `러닝 인증` and the overflow action. Multiline/long-URL comment entry and nested quoted replies (including a deleted parent quote and the post-author badge) pass their focused checks. |
| C05 · public composer | A public board selector, title/body fields, media actions, and preview/cancel controls. | Before the change, a public draft inherited `모브 강변 크루` and displayed the crew-only local notice. After the change it shows the board selector. A crew draft still shows `모브 새벽 크루`, its `러닝 일정` board, and the local notice. |

## Captures

These are screenshots attached to the focused UI test run, plus the preserved pre-change captures.

| Capture | File |
|---|---|
| C03 board list before | [C03-board-list-before.png](C03-board-list-before.png) |
| C03 board list after | [C03-board-list-after.png](C03-board-list-after.png) |
| C04 post detail | [C04-post-detail.png](C04-post-detail.png) |
| C04 nested replies | [C04-nested-replies.png](C04-nested-replies.png) |
| C04 multiline comment and long URL | [C04-multiline-comment.png](C04-multiline-comment.png) |
| C05 public composer before | [C05-public-composer-before.png](C05-public-composer-before.png) |
| C05 public composer after | [C05-public-composer-after.png](C05-public-composer-after.png) |
| C05 crew composer | [C05-crew-composer.png](C05-crew-composer.png) |

## Verification

- Base: verified `main` commit `6735450126811003a068307ea54c5e8d9350779b`.
- Installed app: `com.movtorun.mov`, version `1.0` (build `1`).
- Device: the existing iPhone 17 Pro simulator, UDID `6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, iOS 26.3.1.
- Result: 6 focused UI tests passed, 0 failed. They cover C03 board route, C04 detail/comment/replies and multiline URL input, plus public and crew C05 drafts. Result bundle: `/private/tmp/MovToRun-F002C03C05-rerun-20261014.xcresult`.
- The standard app preferences plist SHA-256 remained `bd46e3a4703bab31ffb66c3c2d82184c28348058d9c5aff54d0cf54072af49a6` before and after the run. The tests use isolated fixture suites.
- The same existing simulator was used. No simulator was created, cloned, reset, or deleted. No backend, credentials, or deployment were used.
