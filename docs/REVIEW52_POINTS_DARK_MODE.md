# Review52 point artwork in dark mode

The existing light appearance remains unchanged. The asset catalog selects dark variants for `PrismPoint`, `PrismArt`, `PrismEarned`, and `PrismSpent` in dark appearance. All four variants preserve their original facet paths and use lighter fills on formerly near-black facets so the artwork remains legible on the app's dark surface. The earned/spent badge also uses a dark plus/minus mark against the brighter badge fill.

The points overview CTA and selected shop category use `MovTokens.onBrand` over `MovTokens.brand` (`#5EF76D`). This is the existing semantic foreground token for brand-colored controls; it stays dark in both appearances. The B02 ledger rows receive stable identifiers for dark icon contrast checks; no other point-screen behavior changes.

`LaunchTests.testPointAccentLabelsStayDarkInDarkAppearance` checks the rendered brand fill and dark text pixels on both controls in dark mode. `testPointIconAppearanceCapture` retains light/dark selected and unselected tab captures for visual inspection. `testPointHistoryEarnedAndSpentIconsKeepContrastInDarkAppearance` samples the interior of the changed B02 polygon facet, requiring the dark variant's `#BFFFC7` range and excluding the light artwork's `#D9FFDE`. The B02 assertion is new in the current head and has not been run; H00 remains unchanged.
