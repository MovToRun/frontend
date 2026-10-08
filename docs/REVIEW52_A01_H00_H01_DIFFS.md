# Review52 A01 / H00 / H01 comparison

Comparison captured 2026-10-08 against the local render of the supplied Review52 source ZIP (`dist/`), at a 390 × 790 point viewport. Source captures: `/tmp/review52-a01-alignment-source.png`, `/tmp/review52-h00-alignment-source.png`, `/tmp/review52-h01-alignment-source.png`. Final app captures: `/tmp/review52-a01-alignment-app-spacing-390x790.png`, `/tmp/review52-h00-alignment-app-final-390x790.png`, `/tmp/review52-h01-alignment-app-final-390x790.png`. The iOS simulator screenshot retains its Dynamic Island cutout while the reference capture is inside a web device frame; comparisons concern app content/layout, not a literal pixel diff of the hardware chrome.

## Confirmed differences before correction

- **A01:** The app shows a large green brand mark above the heading; Review52 starts with the heading and has no mark. The app adds a password visibility eye, absent from the reference. The password placeholder differs (`비밀번호 8자 이상` vs `8자 이상 입력`). The password field and following controls start about 22 pt too high because the gap after the email field is too small.
- **H00:** At the same capture date, the reference shows `10월 1일 목요일 · 가상 예시`, 4.82 / 20 km (24%), and the Sep 29 record. The app shows Oct 8, 0 / 20 km (0%), although its recent-record fixture is Oct 1. The live current date therefore changes the ISO week window and breaks the reference fixture. The app also omits the reference's `· 가상 예시` date qualifier and uses a different recent-record date/duration presentation.
- **H01:** The reference's GPS indicator is a neutral gray waiting state (`GPS 연결 전`); the app renders a red active-looking indicator. The app's map begins below the simulator status area but the reference map begins directly below its in-page header; this capture difference is partly system chrome. The bottom panel is vertically offset compared with the reference, so the visible map area is shorter.

## Scope

This list records observed differences before implementation. It covers only A01, H00, and H01. No unprovided screens or interactions are inferred from this comparison.

## Initial correction bundle

- A01 now reserves the original blank area instead of showing the app brand mark, uses the reference placeholder, removes the A01 password-eye control, and increases the email-to-password separation to match the reference spacing. Other authentication forms keep their existing password reveal control and spacing.
- H00's review-only fixed viewport now uses the Review52 reference date, so its fixture week includes the Sep 29 4.82 km record and shows 24%. Its date caption and recent-record detail follow the reference wording. Normal app usage continues to use the current date.
- H01 starts with the neutral gray GPS waiting indicator and exposes that state to UI accessibility tests. Its existing map panel and map drawing remain unchanged.

The simulator still shows its Dynamic Island cutout in the capture even when the status bar is hidden; reference screenshots are web device renders. This prevents a literal pixel comparison of the topmost hardware area. The capture code does not hide or move app content to conceal this device chrome. The currently reviewed set is limited to A01, H00, and H01; source-by-source review of other screens and assets is still outstanding.
