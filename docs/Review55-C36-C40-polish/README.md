# Review55 C36–C40 crew settings polish

This change aligns C36, C39, and C40 with the existing Review55 crew settings layout. It does not alter C37/C38 board archive and restore policy or C22 approval and rejection behavior.

## Changes

- C36 keeps the WField character counter and removes the second counter and local-only notice.
- C39 removes the extra audience line and review-only notice; the existing local announcement flow and result remain intact.
- C40 removes the pending-count summary, local-only notice, row avatar, and bottom management button. Applicant name, memo, row navigation, and the page back action remain.

## Simulator evidence

Captured by the focused UI tests on the existing iPhone 17 Pro simulator (`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`), with app bundle ID `com.movtorun.mov`.

- [C36 가입 안내](test-attachments/6D06FABC-B3B0-4CAA-82BE-DA6CDD525834.png)
- [C39 크루 알림](test-attachments/CF69384E-6245-47F6-9984-D9AB82D6FBCA.png)
- [C40 가입 신청](test-attachments/15B00D6A-D815-4CCA-A0A4-CFCC6A574423.png)

## Verification

Two focused UI tests passed (2/2, zero failures) using the existing `/tmp/c34-c35-derived` build cache. Coverage includes the single C36 counter, C39 notice removal and local send feedback, C40 approval/rejection, plus the existing C37/C38 archive/restore and restored-post preservation flow. The result bundle is `/tmp/c36-c40-review55.xcresult`.

The installed app reported version `1.0 (1)` before and after testing.

## App data manifest note

A file-by-file SHA-256 manifest was captured before testing at `/tmp/c36-c40-appdata-before.manifest` (1,894 files, data-container ID `FB82ECA0-53D6-40C4-96C7-425E09392163`). After `xcodebuild test`, the same app ID resolved to data-container ID `F5D089DF-6C9B-4E3C-B9FD-463B61361777`; the old container path no longer existed. The current container manifest is `/tmp/c36-c40-appdata-current.manifest` (1,896 files).

Comparing manifests by relative path found 1,892 shared files with identical sizes and hashes. The two removed and two added files are SplashBoard snapshots with identical content hashes but newly generated names; the other two additions are unique `community-<UUID>` preferences suites created by the isolated UI test fixtures. No shared file contents changed. The test launch used a unique fixture defaults suite.
