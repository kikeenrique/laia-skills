# AXe 2.x Features

Features added in AXe `v2.0`, `v2.1`, and `v2.2` that the main flow routes here. For full option lists, run `axe <command> --help` or use the `axe` skill.

## Agent Mode

`--agent` works on `describe-ui`, `tap`, `type`, `swipe`, `drag`, `key`, `key-combo`, `key-sequence`, `slider`, `touch`, `gesture double-tap`, `gesture pinch`, and `batch`, on simulators only. It needs no model or API key.

```bash
axe describe-ui --agent --view navigation --udid "$UDID"
axe tap --agent --view navigation --udid "$UDID" --snapshot-id "$SNAPSHOT_ID" --ref e12
axe type 'Ada' --agent --focus --udid "$UDID" --snapshot-id "$SNAPSHOT_ID" --ref e7
axe batch --agent --udid "$UDID" --steps-json '{"snapshotID":"<SNAPSHOT_ID>","steps":[{"action":"type","ref":"e7","text":"Ada","focus":true},{"action":"tap","ref":"e12"}]}'
```

- A capture returns a `snapshotID` and rows `ref|actions|role|label|value` (e.g. `e12|tap|button|Save|`). Refs belong to one snapshot and expire after 60 seconds.
- `--view navigation` lists controls; `reading` (default) adds visible text; `full` is the complete schema.
- A successful action returns the settled screen as a new capture: plan from it instead of running `describe-ui` again. Success still proves delivery, not the app effect, so check the effect in that capture.
- A refusal sends no input and carries a typed code (`screenChanged`, `targetCovered`, `keyboardCovered`, `busy`, …). Change something before acting again; never resend a batch that stopped after completed steps.
- Selectors work in agent mode too (`--label 'Save' --element-type Button`), plus `--label-contains` and `--label-regex`, for controls that move.
- `batch --agent` takes 1–8 `tap`/`type` steps from one snapshot; only the last step may leave the screen.
- Results are JSON by default; `--output text` prints them compactly. `AXE_TIMING=1` prints a phase table to stderr.
- Agent `type` waits for the text and returns the screen with it. It checks the field's focus before the first key, after Return, Tab, a shortcut or a delay, and every 16th key otherwise (`v2.2`), so if focus moves mid-text it stops within 16 keys: check what the field holds in the returned capture.

### A Tap That Does Nothing: Semantic Press (v2.2)

A tap is a real touch at the control's centre. When a row is one Button with its real action on a small button at one edge (a contact row with "Call"), the tap succeeds and the screen stays unchanged. Only then, press the control through accessibility, as VoiceOver does:

```bash
axe tap --agent --semantic-press --view navigation --udid "$UDID" --snapshot-id "$SNAPSHOT_ID" --ref e12
axe tap --semantic-press --id "contact_row" --udid "$UDID"
```

- Simulator only; takes one `--ref` (with its snapshot) or an exact `--id`, and the control needs a unique accessibility ID (`pressNeedsID` otherwise) and a native Button or CheckBox role. It sends no touch. Not a batch step.
- `buttonPressAccepted` means the app took the press, not that anything happened: check the returned capture (agent replies carry the action kind `press` and the receipt's `targetRole`).
- Never press first: a press can run an action no finger could reach, so it can hide a real hit-target bug.

### Web Pages (v2.1)

A WKWebView (in any app, inspectable or not), Safari, SFSafariViewController, or an ASWebAuthenticationSession sign-in sheet shows up as one area. Add `--web` to list the page's controls as `w` refs:

```bash
axe describe-ui --agent --web --view navigation --udid "$UDID"
axe tap --agent --udid "$UDID" --snapshot-id "$SNAPSHOT_ID" --ref w3
axe type 'ada@example.com' --agent --focus --udid "$UDID" --snapshot-id "$SNAPSHOT_ID" --ref w2
```

- Lists links, buttons, pop-up buttons (their options come back as `w` rows to tap), text fields, checkboxes and switches, sliders, and search suggestions; Safari sheets add Back, Forward, Reload, Share, Open in Safari and the keyboard's Previous/Next/Done. Only controls a tap would reach now are listed: read page text from a screenshot, and tap click-only text and a Safari sheet's Close button by coordinates.
- `w` refs take `tap`, `type --focus` (plain `type --ref wN` refuses with `unsupportedReference`), `key`, `key-combo`, and `key-sequence`; keys tap the field first. Batches do not take `w` refs. Scroll with the web view's own `swipe` row (an `e` ref).
- Actions on a `--web` snapshot keep returning `w` rows. A `--web` capture costs roughly twice a plain one, and works in portrait only.

`axe agent "<goal>"` is a separate, experimental command that pursues a plain-language goal with a hosted model and needs `TYPESAFE_API_KEY`. Don't use it unless the user asks.

## Structured Output And Errors

```bash
axe --output json tap --id "login_submit" --udid "$UDID"
```

- `--output json` goes before the command and prints one `axe.output.command-result` object: `command`, `data.result`, `didError`, and `error.code` when it failed.
- Branch on `error.code`, never on the message or `nextSteps`. Common codes: `invalidArguments`, `targetNotFound`, `notBooted`, `busy`, `timeout`, `elementNotFound`, `ambiguousElement`, `elementNotHittable`, `rejectedBeforeInput`, `inputFailed`, `inputUnavailable`, `cleanupUncertain`, `quarantined` (a touch or key may still be held; check the device before more input), `screenChanged`, `captureFailed`, `unsupportedDevice` (v2.1: an Apple TV simulator; AXe supports iPhone and iPad simulators only).
- After `screenshot` and `record-video`, the command's own `--output` is still the file path.
- A failure never repeats input. `--verbose` adds detail without changing the exit status or code.

## Serve: Many Commands In One Process (v2.1)

For a harness that sends many commands, `axe serve` keeps one process open and skips per-command setup (reading the screen and tapping took about 176 ms instead of 290 ms):

```bash
printf '%s\n' 'describe-ui --minimal-keys' 'tap --label General' 'ping' | axe serve --udid "$UDID"
```

- One command per standard-input line, written as after `axe` but without `--udid`. Each line gets one stdout line: the JSON `axe --output json <command>` prints. A ready line comes first; logs go to stderr; serve exits when stdin closes.
- Commands: `describe-ui`, `displays`, `screenshot`, `tap`, `swipe`, `drag`, `draw`, `type`, `button`, `key`, `key-sequence`, `key-combo`, `touch`, `gesture`, `slider`, `rotate`, `hinge`, and `ping` (answers without touching the simulator). A failed line gets its error reply and serve carries on.
- Each command takes the same route and checks as the one-off command; other `axe` commands can still use the simulator meanwhile.

## Settings (Xcode 27)

```bash
axe settings show --udid "$UDID"
axe settings set --udid "$UDID" --appearance dark --text-size accessibility-large
axe settings set --udid "$UDID" --increase-contrast on --reduce-motion on
axe settings location set --latitude 37.7749 --longitude -122.4194 --udid "$UDID"
axe settings location clear --udid "$UDID"
axe settings status-bar preset screenshot --udid "$UDID"
axe settings status-bar clear --udid "$UDID"
```

- `set` also takes `--reduce-transparency`, `--show-borders`, `--liquid-glass-opacity`, `--color-filter`, `--color-filter-intensity`, and `--voiceover`. It validates every value before changing anything.
- Use it to verify a screen in dark mode or at accessibility text sizes; restore the original values afterwards.
- Turning VoiceOver on shows a one-time alert that blocks input until its OK button is tapped.

## iPhone Duo, Rotation, And Other Commands

- `axe displays --udid "$UDID"` shows each screen's role, size in points, orientation, the active screen, and the hinge angle. Coordinates are in those units.
- `axe hinge set tabletop --udid "$UDID"` (`0...180`, `closed`, `tabletop`, `open`) and `axe rotate left|right --udid "$UDID"` change the Duo's fold and orientation; read the UI again after either.
- Since `v2.1`, plain `describe-ui`, `tap --id`, and `tap --label` on the Duo read only the active screen, as agent mode does. On one of the two screens the Home-screen icons drawn there are missing from the tree; tap them by coordinates from a screenshot.
- `--input-mode selected` with `--screen-id` and `--screen-uuid` (from `displays`) refuses to act if another screen becomes active.
- `axe shutdown --udid "$UDID"` shuts down exactly one simulator.
- `axe doctor --udid "$UDID"` checks that the target is ready.
- `axe remote` (Apple silicon, macOS 14.5+) connects the AXe Mirror app on a paired iPhone or iPad to this Mac: `axe remote pair` once, then `axe remote` lets the app open, boot, or create simulators, `axe remote mirror --udid "$UDID"` hosts one simulator, and `axe remote build` / `publish` offer an Ad Hoc build to install on the device. It runs until Ctrl+C and is for a person, not for this flow; use the `axe` skill for details. Since `v2.2` it replaces `axe mirror` (the old commands still run; `axe mirror viewers` is now `axe remote devices`).
- AXe also drives paired physical iPhones and iPads by hardware UDID (`axe list-devices`); this flow targets simulators, so use the `axe` skill for devices.
