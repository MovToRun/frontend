# Community UI follow-up

## Baseline and findings

The requested main snapshot at the start of this review was
`db35b93260fa1c769c5a1ce4c28a8a10aa5e8a64` (tree
`20043ea3b8bb7f74f3b1b6c7f9f9fb58f42e41d4`). While the review was in
progress, PR #65 was merged as `b7568b51213bc88d8de74097ff2021ae41cf7294`
(tree `ed11c1a88501c2f3eb4ff5dd2c5cc911fa491f32`); this follow-up is based on
that current main commit.

The app bundle remains `com.movtorun.mov`, version `1.0` (build `1`). The
installed bundle does not contain a source commit identifier, so its exact
source revision cannot be inferred from that version string. The initial
simulator foreground showed the onboarding consent page rather than
Community. An earlier dark Community capture showed black status-bar and
home-indicator bands against the dark-gray canvas.

In `WireframeRoot.rootStyledLayers`, the theme-aware `W.paper` canvas was
inside the route clip. The route clip therefore cut the canvas off at the
safe-area edges. The fix puts the theme-aware background outside the route
clip and extends only that background through the container safe areas; the
content retains its safe-area layout and the running-map clip exception stays
in place. The Community header layout is verified below to stay below the
status bar, with non-overlapping brand/search/settings elements.

## Verified behavior

On the existing iPhone 17 Pro simulator
`6EB4A7AD-63C1-471F-BB5F-9147DEEC404B`, using the existing app ID and ad-hoc
signing, the focused UI checks covered:

- The dedicated Community tabs for Feed, Boards, Home, Crew, and My Profile;
  the Mov Home tab remains centered. Repeated tab transitions preserve the
  community bar, and liked posts open inside Community Profile Settings.
- Downward scrolling hides the bottom bar, upward scrolling restores it, and
  the compose and scroll-to-top actions move with the freed bar area.
- Light and dark theme colors fill the status-bar and home-indicator safe
  areas. Pixel checks cover both top and bottom edges.
- A 300-character unbroken Korean comment wraps to at most eight visible
  lines, accepts editing at the end, preserves its text value, keeps the send
  button above the keyboard, and clears after sending. Multiline text, a long
  token, a URL, and a crew reply are also covered.
- The seeded H00 home summary and running-map viewport gestures remain intact.

Eight selected UI test methods passed together in the final focused run; the
running-map viewport test also passed in a separate run. Two test-only issues
were corrected before that final focused run:
the reply-target query originally matched both its label and cancel button,
and its expected reply string retained a trailing space that submit correctly
trims. The checks were run in focused Xcode result bundles under `/tmp` rather
than as a full application suite.

## Captures

Screenshots from the same simulator run are retained locally in the ignored
`evidence/community-followup/screenshots/` directory. They include light/dark
safe-area, Community tab, hidden/restored bar, long-comment keyboard, liked
posts settings, H00, and running-map captures. These files are intentionally
not added to the source PR because the repository ignores local test captures.
