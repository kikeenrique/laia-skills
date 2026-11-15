# AXe 2.0 Features

Features added in AXe `v2.0` that the main flow routes here. For full option lists, run `axe <command> --help` or use the `axe` skill.

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

`axe agent "<goal>"` is a separate, experimental command that pursues a plain-language goal with a hosted model and needs `TYPESAFE_API_KEY`. Don't use it unless the user asks.

## Structured Output And Errors

```bash
axe --output json tap --id "login_submit" --udid "$UDID"
```

- `--output json` goes before the command and prints one `axe.output.command-result` object: `command`, `data.result`, `didError`, and `error.code` when it failed.
- Branch on `error.code`, never on the message or `nextSteps`. Common codes: `invalidArguments`, `targetNotFound`, `notBooted`, `busy`, `timeout`, `elementNotFound`, `ambiguousElement`, `elementNotHittable`, `rejectedBeforeInput`, `inputFailed`, `inputUnavailable`, `cleanupUncertain`, `quarantined` (a touch or key may still be held; check the device before more input), `screenChanged`, `captureFailed`.
- After `screenshot` and `record-video`, the command's own `--output` is still the file path.
- A failure never repeats input. `--verbose` adds detail without changing the exit status or code.

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
- `--input-mode selected` with `--screen-id` and `--screen-uuid` (from `displays`) refuses to act if another screen becomes active.
- `axe shutdown --udid "$UDID"` shuts down exactly one simulator.
- `axe doctor --udid "$UDID"` checks that the target is ready.
- AXe also drives paired physical iPhones and iPads by hardware UDID (`axe list-devices`); this flow targets simulators, so use the `axe` skill for devices.
