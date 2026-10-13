# Safe-area background follow-up

Branch: `codex/safe-area-background-20261013`, based on PR #65 head
`ba488c6ad4c84d59fbb0085b35072ac9747bd78c`.

## Findings

The reported symptom is a background mismatch at the top and bottom edges, not
evidence of clipped text or controls. Existing dark Community captures show
the status-bar and home-indicator regions black while the app canvas is dark
gray. In light appearance, those regions blend into the white canvas, which
explains why the mismatch is less visible.

In `WireframeRoot.rootStyledLayers`, the theme-aware `W.paper` background was
attached before `WScreenClip`. The clip wraps the root view, so it also cuts
off background extensions into the status-bar and home-indicator safe areas.
`WHeader` already extends its own background at the top, but that extension is
inside the same root clip; the app has no equivalent shared bottom background.

The fix moves the root canvas to a background layer outside the route clip and
lets only that color layer ignore the container safe area. Screen content,
navigation and controls continue to use the normal safe-area layout. The
background uses `W.paper`, so light/dark theme colors follow the existing
design tokens. The existing route clip and its full-screen running-map
exception are preserved.

The current Simulator observation showed the onboarding consent page, not the
reported Community state, so it did not confirm the issue on that live screen.
The existing local dark Community capture at
`../evidence/community-feed-dark-C01.png` is supporting historical evidence,
not a post-fix result.

## Deferred visual verification

After independent verification of PR #65 ends, use the existing iPhone 17 Pro
simulator only. Capture the same screen in light and dark appearance and inspect
the status-bar and home-indicator regions on a page with a gray content
surface. Confirm those regions match the surrounding screen background,
buttons and content remain inside the safe area, and running maps still draw
through both safe areas. Also check a short screen and a route transition for
clipping or flashes. No build, test, app launch, or Simulator interaction was
performed for this follow-up.
