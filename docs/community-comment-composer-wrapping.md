# Community comment composer wrapping follow-up

Branch: `codex/community-comment-input-wrapping-20261013`, based on the
community UI branch at `ba488c6ad4c84d59fbb0085b35072ac9747bd78c`.

The composer uses a vertically growing SwiftUI `TextField` capped at eight
visible lines. Its text remains the entered value: visual wrapping does not add
line breaks. These fixture-backed UI regressions were added to
`MovUITests/LaunchTests.swift`:

- Paste 300 unbroken Korean characters, verify the value has no inserted line
  breaks, the field grows, and the send button stays visible above the keyboard;
  submit and verify the input clears.
- Paste text containing explicit newlines, a long English token, and a URL;
  verify those explicit newlines are preserved, then submit and verify clear.
- Reply to a crew comment with a long reply; verify the reply target remains
  selected while the composer grows, then verify the reply is posted and the
  target and input reset.

The UI tests have **not been run** in this follow-up because the independent
verification of PR #65 is still in progress. Do not run builds, launch the app,
or use the simulator until that verification finishes.

Before merging, run the focused tests and manually inspect a long entry beyond
eight visual lines on the existing iPhone 17 Pro. Confirm the caret and final
line remain visible while editing, and check Korean IME composition, light and
dark appearance, and multiline paste. The screenshot attachments in the first
two tests preserve the keyboard-open layout for review.

Separate review follow-up: published comments and replies currently support
local addition and deletion, but no edit action. Keep that out of this wrapping
change and scope it separately if comment editing is required.
