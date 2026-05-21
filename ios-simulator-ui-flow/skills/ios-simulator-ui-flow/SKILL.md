---
name: ios-simulator-ui-flow
description: Autonomous iOS Simulator UI verification flow for iOS apps. Use when asked to test on simulator, verify UI, check a screen, run and screenshot, inspect the accessibility tree, interact with an app via AXe, or after UI changes that need visual verification. Orchestrates build, install, launch, log capture, AXe describe/tap/slider/swipe/drag/type/batch/screenshot/video, and postcondition checks without user intervention.
---

# iOS Simulator UI Verification Flow

Build, deploy, drive, and verify an iOS app in Simulator. This skill is verified against AXe `v1.7.0` (released 2026-05-11) and keeps the workflow command-oriented: use project-native build commands, `xcrun simctl` for lifecycle, and AXe for accessibility-tree inspection, input, screenshots, and video.

## Principles

- Keep a tight feedback loop: build, install, launch, inspect, interact, verify, then fix and repeat.
- Prefer text observation first: `axe describe-ui` is cheaper and more precise than screenshots for labels, identifiers, values, and state.
- Use screenshots for visual questions: layout, typography, color, spacing, clipping, animation frames, and anything a text tree cannot represent.
- Prefer AXe selectors over coordinates: `--id`, `--label`, `--value`, and `--element-type` survive layout changes better than raw points.
- Verify after every meaningful action. Most AXe input commands confirm dispatch, not app state. Confirm the postcondition with `describe-ui`, `describe-ui --point`, or a screenshot.
- Capture project facts once per session so commands stay consistent.

## Prerequisites

- Xcode with the target iOS Simulator runtime installed.
- AXe `v1.7.0` or newer in `PATH`: `brew install cameroncooke/axe/axe`.
- `xcsift` for Swift and Xcode build output.
- A generated Xcode project or workspace. For Tuist projects, run `tuist generate --no-open` before building.
- A project-local artifact directory such as `tmp/` for screenshots, UI dumps, logs, and video. Create it with `mkdir -p tmp` when needed.

## Capture Project Facts

Keep these values in the session and reuse them. Resolve deterministic facts from the project before asking the user.

```bash
APP_NAME="<display-name>"
BUNDLE_ID="<bundle-id>"
SCHEME="<xcode-scheme>"
PROJECT="<Name>.xcodeproj"        # or WORKSPACE="<Name>.xcworkspace"
TARGET_SIM="<device-name>"        # e.g. "iPhone 17"
UDID="<simulator-udid>"
APP_PATH="<built-app-path>"
FIRST_SCREEN_ID="<stable-launch-accessibility-id>"
```

Useful discovery commands:

```bash
axe --version
axe list-simulators
xcodebuild -list -json
```

When a target simulator is named, resolve that device rather than blindly using the first booted simulator. If the same device exists under multiple runtimes, prefer the latest runtime unless the user specified otherwise.

## 1. Simulator Setup

List devices and choose the target:

```bash
axe list-simulators
xcrun simctl list devices available
```

Boot and wait for readiness when needed:

```bash
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
open -a Simulator
```

If another simulator is already booted, do not switch targets silently. Use the UDID that matches the requested device and pass that same UDID to every AXe and `simctl` command.

## 2. Build

Always capture stderr and pipe Swift/Xcode build output through `xcsift`.

Tuist:

```bash
tuist generate --no-open
tuist xcodebuild build \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -e
```

Xcode workspace:

```bash
xcodebuild build \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -e
```

Xcode project:

```bash
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -e
```

Capture or recover the built `.app` path from the build output. If the formatter output is not enough, use `xcodebuild -showBuildSettings` for the same scheme and destination, then resolve `BUILT_PRODUCTS_DIR` plus `WRAPPER_NAME`.

Before launch, sanity-check the bundle identifier when it is easy:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist"
```

## 3. Install And Launch

Terminate the running app before install. This avoids a stale process serving pre-edit UI after a rebuild.

```bash
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
```

Wait for a real render anchor, not just a fixed sleep, when you know one:

```bash
for i in {1..40}; do
  axe describe-ui --udid "$UDID" > tmp/launch-ui.json && \
    grep -q "$FIRST_SCREEN_ID" tmp/launch-ui.json && break
  sleep 0.25
done
```

If there is no known anchor, start with a short settle wait, then inspect the tree:

```bash
sleep 2
axe describe-ui --udid "$UDID"
```

For deep links:

```bash
xcrun simctl openurl "$UDID" "myapp://screen/detail?id=123"
```

## 4. Capture Logs

Start logs before driving the UI when behavior or crashes matter:

```bash
xcrun simctl spawn "$UDID" log stream \
  --predicate 'process == "<app-name>" OR subsystem == "<bundle-id>"' \
  --level debug \
  > tmp/simulator.log 2>&1 &
LOG_PID=$!
```

Stop and inspect after the flow:

```bash
kill "$LOG_PID" 2>/dev/null
cat tmp/simulator.log
```

## 5. Observe The UI

Inspect the full accessibility tree:

```bash
axe describe-ui --udid "$UDID" > tmp/ui.json
axe describe-ui --udid "$UDID"
```

Inspect one logical point:

```bash
axe describe-ui --point 200,400 --udid "$UDID"
```

Capture a screenshot for visual review:

```bash
axe screenshot --udid "$UDID" --output tmp/simulator.png
```

Coordinates in `describe-ui` are logical points. AXe `v1.7.0` maps logical points for rotated landscape simulators and letterboxed landscape-only apps automatically, so use `describe-ui` frames directly. If you measured a coordinate from a screenshot PNG, convert pixels to logical points first and confirm with `describe-ui --point`.

## 6. Interact With AXe

### Taps

Prefer stable selectors:

```bash
axe tap --id "login_submit" --udid "$UDID"
axe tap --label "Continue" --udid "$UDID"
axe tap --value "Selected" --element-type Button --udid "$UDID"
```

Use waiting for screens and transitions:

```bash
axe tap --id "settings_button" --wait-timeout 5 --poll-interval 0.25 --udid "$UDID"
```

Fallback to coordinates only after inspecting the tree:

```bash
axe describe-ui --point 200,400 --udid "$UDID"
axe tap -x 200 -y 400 --udid "$UDID"
```

Switches and toggles are handled better in AXe `v1.7.0`: selector taps with default `--tap-style automatic` activate a contained UIKit `UISwitch` or SwiftUI `Toggle` when the matched row or label contains exactly one. Force the style only when troubleshooting:

```bash
axe tap --label "Notifications" --tap-style physical --udid "$UDID"
axe tap --label "Submit" --tap-style simulator --udid "$UDID"
```

### Sliders

Use `slider` instead of approximating with swipes:

```bash
axe slider --id "volume_slider" --value 75 --udid "$UDID"
axe slider --label "Volume" --value 40 --element-type Slider --udid "$UDID"
```

`slider` sets a 0-100 percentage and verifies the resulting `AXValue` within tolerance. It is the main AXe input command that fails when the observed state remains outside tolerance.

### Swipes, Drags, Gestures, And Touch

Use the AXe `v1.7.0` coordinate syntax:

```bash
axe swipe --start-x 200 --start-y 650 --end-x 200 --end-y 250 --duration 0.5 --udid "$UDID"
axe drag --start-x 100 --start-y 400 --end-x 300 --end-y 400 --duration 0.4 --steps 40 --udid "$UDID"
axe gesture scroll-down --udid "$UDID"
axe gesture swipe-from-left-edge --udid "$UDID"
axe touch -x 150 -y 250 --down --up --delay 1.0 --udid "$UDID"
```

### Text And Keyboard

```bash
axe type 'search query' --udid "$UDID"
axe type --file tmp/input.txt --udid "$UDID"
axe key 40 --udid "$UDID"                         # Return
axe key-combo --modifiers 227 --key 4 --udid "$UDID"  # Cmd+A
axe button home --udid "$UDID"
```

Use `--stdin` or `--file` for text with shell-sensitive characters.

## 7. Batch Multi-Step Flows

Prefer `axe batch` when the steps are known upfront:

```bash
axe batch --udid "$UDID" \
  --step 'tap --id "login_email" --wait-timeout 5' \
  --step 'type "person@example.com"' \
  --step 'tap --id "login_submit" --wait-timeout 5' \
  --step 'sleep 1' \
  --step 'screenshot --output tmp/after-login.png'
```

Rules:

- Put `--udid` on `axe batch`, not inside step lines.
- Use one step source per run: `--step`, `--file`, or `--stdin`.
- Use `--wait-timeout` for selector taps that cross screens.
- Use `--ax-cache perStep` when the UI changes between selector taps and you are not using `--wait-timeout`.
- Add `--continue-on-error` only for best-effort probing.
- Use discrete `axe slider` calls for slider verification; batch does not provide the same slider post-check.

## 8. Video

Use screenshots for normal verification. Use video when the user asks for a recording or when timing and animation matter.

```bash
axe record-video --udid "$UDID" --fps 15 --output tmp/flow.mp4
```

Stop recording with `Ctrl+C`; AXe finalizes the MP4 before exiting.

For streaming:

```bash
axe stream-video --udid "$UDID" --fps 10 --format mjpeg > tmp/stream.mjpeg
```

## 9. Verification Loop

Use this loop after UI-affecting changes:

1. Build with `xcsift`.
2. Terminate, install, and launch the app.
3. Wait for `FIRST_SCREEN_ID` or inspect `describe-ui`.
4. Capture a before screenshot if layout changed.
5. Drive the shortest flow that reaches the target screen.
6. Verify the postcondition with `describe-ui`, `describe-ui --point`, or screenshot.
7. Read logs if the behavior is unexpected.
8. Fix code and repeat until the rendered state and accessibility-tree state both match the expected result.

For existing apps, grow accessibility coverage as part of the verification work. Add `.accessibilityIdentifier` to stable leaf elements that need to be tapped, queried, or used as render anchors. Add `.accessibilityValue` when state needs to be asserted. Avoid placing a shared identifier on a root SwiftUI container when a leaf identifier would be more precise.

## Patterns Borrowed From ios-build-verify

`ios-build-verify` solves the same feedback-loop problem with a larger script bundle, per-project config, named operations, `xcbeautify`, `jq`, and project setup/calibration scripts. This skill stays lighter and command-oriented, but use these ideas:

- Keep a project facts block for app name, bundle id, scheme, target simulator, UDID, built app path, and first-screen anchor.
- Resolve the simulator by the intended device, not by whichever device happens to be booted.
- Terminate before install so a stale running app cannot hide a bad rebuild.
- Poll a known accessibility anchor after launch instead of trusting `simctl launch` or a blind sleep.
- Treat error output as a state probe. Empty trees, missing identifiers, modal dismiss regions, or home-screen app labels each point to different recovery paths.
- Prefer accessibility-tree checks for text and state, then screenshots for visual review.

Do not import `ios-build-verify` assumptions wholesale. It is SwiftUI/iOS-version opinionated, uses `xcbeautify`, ships many wrapper scripts, and has no tagged release as of the comparison. Keep this skill aligned with AXe released tags and the local project's existing build tooling.

## Troubleshooting

- **Empty or tiny accessibility tree**: The app may still be launching, crashed, be gated by a modal/onboarding view, or be showing the home screen. Check logs, screenshots, and `describe-ui`.
- **Element not found**: Refresh `describe-ui`, confirm the identifier/label exists, scroll if the row is virtualized, or add a stable accessibility identifier to the app.
- **Tap dispatch succeeds but state does not change**: Add `--wait-timeout`, `--post-delay`, or a batch `sleep`; confirm the target with `describe-ui --point`; use physical tap style for switch/toggle edge cases.
- **Coordinate taps miss**: Use logical points from `describe-ui`, not raw screenshot pixels.
- **Slider or picker is flaky**: Prefer `axe slider` for sliders. For wheel-style controls, drive with gestures or drag and verify with `describe-ui`.
- **Build output is noisy or missing errors**: Make sure stderr is captured with `2>&1` and the command is piped through `xcsift -f toon`.
- **AXe breaks after Xcode updates**: AXe uses private SimulatorKit and AccessibilityPlatformTranslation frameworks. Recheck the installed AXe release and upstream notes before assuming the app is broken.

## Exit Checklist

Before reporting success:

- The AXe upstream version used for guidance is known. Current target: `v1.7.0`.
- Every AXe simulator-interaction command includes `--udid "$UDID"`.
- No stale AXe syntax is used, especially old `swipe --from/--to` forms.
- Selector taps are preferred over coordinates where possible.
- Sliders use `axe slider --value 0-100`.
- A postcondition was verified after each input step that matters.
- Screenshots were captured when visual layout, color, typography, or spacing mattered.
- Logs were checked for crashes or unexpected runtime errors when behavior looked wrong.
