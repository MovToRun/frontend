# Review52 H08/H09 source comparison

The reference captures come from the user-provided `running-app-source.zip` (SHA-256 `b01bf3d4aa3185f4e65c5a5b14e14124507a096c1b7ca9dd53ce2d5a455ef353`). The local entry point is `dist/index.html`; the screen inventory is in `dist/screens.js` and markup/state rendering is in `dist/app.js`. The document loads `style.css`, `auth-flow.css`, `theme.css`, `run-panel.css`, `points.css`, `share-ui.css`, `record-baseline.css`, `baseline.css`, and `community.css`, plus local Pretendard and Cafe24 Ssurround font files from `dist/assets/fonts/`.

The source renderer loaded the ZIP's `dist/index.html` with a local-file WKWebView. It switched from atlas to prototype mode, opened `H08` or `H09`, and enabled reduced motion. The viewport was 390×790 CSS pixels at device pixel ratio 2. `WKSnapshotConfiguration.snapshotWidth` was 390, producing 780×1580 PNGs.

The final viewport CSS injected into the source page was:

```css
html,body{width:390px!important;height:790px!important;min-width:390px!important;min-height:790px!important;margin:0!important;overflow:hidden!important;background:#fff!important}
body>*{display:none!important}
#prototype-view{display:block!important;position:fixed!important;inset:0!important;width:390px!important;height:790px!important}
.prototype{display:block!important;position:static!important;width:390px!important;height:790px!important;min-height:0!important;margin:0!important;padding:0!important}
.stage{display:block!important;position:static!important;width:390px!important;height:790px!important;min-width:0!important;margin:0!important;padding:0!important}
#device{display:flex!important;position:fixed!important;left:0!important;top:0!important;width:390px!important;height:790px!important;min-height:790px!important;margin:0!important;border:0!important;border-radius:0!important;box-shadow:none!important;transform:none!important}
```

The SwiftUI captures use `-wire-fixture -wire-reset -wire-capture-viewport -wire-review-size -wire-reduced -appearance light`, with `-wire-screen H08` and `-wire-screen H09` run sequentially. The app was built from PR #14 merge SHA `00c56aba206d0d592ef7f94fbbdfb79b8b638225` and captured on a newly created iPhone 17 Pro Max simulator running iOS 26.3.1. No pre-existing simulator was used.

The focused UI test checks both distance values, the reference-week note, and its two-line block height. The focused unit test checks two-decimal formatting, non-finite values, and ISO week boundaries. Both passed sequentially on the same temporary Pro Max. Full 140-state QA was not run.
