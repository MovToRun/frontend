# Review52 point artwork in dark mode

The existing light appearance remains unchanged. The asset catalog now selects `points-dark.svg` for `PrismPoint` and `prism-art-dark.svg` for `PrismArt` in dark appearance. Both variants preserve the original facet paths and use lighter fills on the formerly near-black facet so the shard remains legible on the app's dark surface.

The points overview CTA and selected shop category use `MovTokens.onBrand` over `MovTokens.brand` (`#5EF76D`). This is the existing semantic foreground token for brand-colored controls; it stays dark in both appearances. Other point screens and unrelated controls are unchanged.

`LaunchTests.testPointAccentLabelsStayDarkInDarkAppearance` checks the rendered brand fill and dark text pixels on both controls in dark mode. `testPointIconAppearanceCapture` retains light/dark selected and unselected tab captures for visual inspection. H00 remains unchanged.
