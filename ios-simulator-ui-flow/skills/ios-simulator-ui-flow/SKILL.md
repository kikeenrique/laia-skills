---
name: ios-simulator-ui-flow
description: Autonomous iOS Simulator UI verification flow. Use when asked to "test on simulator", "verify the UI", "check the screen", "run and screenshot", or after completing UI changes that need visual verification. Orchestrates build, deploy, launch, log capture, UI inspection, interaction (tap/swipe), screenshot, and verification — all without user intervention.
disable-model-invocation: false
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# iOS Simulator UI Verification Flow

Autonomous end-to-end flow for building, deploying, and verifying iOS UI on the simulator. Uses `xcodebuild` for builds, `xcrun simctl` for simulator control, and AXe CLI for UI interaction and inspection.

## Prerequisites

- AXe CLI installed and available in PATH
- A booted iOS Simulator (or boot one in Step 1)
- Xcode project generated (`tuist generate --no-open` for Tuist projects)

## Phase 1: Environment Setup

### 1.1 Find or boot a simulator

```bash
# List booted simulators
xcrun simctl list devices booted

# If none booted, find and boot one
xcrun simctl list devices available | grep iPhone
xcrun simctl boot <UDID>
open -a Simulator
```

### 1.2 Get simulator UDID

```bash
# Store UDID for all subsequent commands
UDID=$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['state'] == 'Booted':
            print(d['udid']); sys.exit()
")
echo "Booted simulator: $UDID"
```

Save the UDID — every AXe and simctl command needs it.

## Phase 2: Build & Deploy

### 2.1 Build for simulator

For Tuist projects:
```bash
tuist generate --no-open
tuist xcodebuild build -scheme <Scheme> \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -q -e --xcbeautify
```

The `-e` flag outputs the built `.app` path. Capture it:
```bash
APP_PATH=$(tuist xcodebuild build -scheme <Scheme> \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -e --xcbeautify | grep '\.app$' | head -1)
```

For standard Xcode projects:
```bash
xcodebuild build -workspace <Name>.xcworkspace \
  -scheme <Scheme> \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -q -e --xcbeautify
```

### 2.2 Install & launch

```bash
xcrun simctl install $UDID "$APP_PATH"
xcrun simctl launch $UDID <bundle-id>
```

If you need to terminate a running instance first:
```bash
xcrun simctl terminate $UDID <bundle-id> 2>/dev/null
```

### 2.3 Wait for app to settle

```bash
sleep 3
```

Use longer waits (5-8s) if the app does network fetches on launch.

## Phase 3: Log Capture

### 3.1 Stream logs (background)

```bash
# Start log stream in background, filter by app subsystem
xcrun simctl spawn $UDID log stream \
  --predicate 'subsystem == "<bundle-id>" OR process == "<app-name>"' \
  --level debug \
  > tmp/simulator_logs.txt 2>&1 &
LOG_PID=$!
```

### 3.2 Read logs after interaction

```bash
# Stop log capture
kill $LOG_PID 2>/dev/null

# Read captured logs
cat tmp/simulator_logs.txt
```

## Phase 4: UI Inspection & Interaction (via AXe)

### 4.1 Inspect current screen

```bash
# Full accessibility hierarchy — discover element IDs, labels, and frames
axe describe-ui --udid $UDID

# Inspect specific point
axe describe-ui --point 200,400 --udid $UDID
```

### 4.2 Take screenshot

```bash
# Save to project tmp folder (not /tmp)
axe screenshot --udid $UDID --output tmp/simulator_screenshot.png
```

Then read the screenshot with the Read tool to visually inspect it.

### 4.3 Tap on elements

Prefer accessibility selectors over coordinates:
```bash
# By accessibility identifier (most reliable)
axe tap --id "floor_panel_dismiss" --udid $UDID

# By label text
axe tap --label "Reintentar" --udid $UDID

# By coordinates (fallback — get from describe-ui frames)
axe tap -x 200 -y 400 --udid $UDID
```

### 4.4 Multi-step interaction (batch)

```bash
axe batch --udid $UDID \
  --step 'tap --label "Planta 3" --wait-timeout 5' \
  --step 'sleep 1' \
  --step 'screenshot --output tmp/after_tap.png'
```

### 4.5 Swipe and gestures

```bash
axe swipe --from 200,600 --to 200,200 --duration 0.5 --udid $UDID
axe gesture scroll-down --udid $UDID
```

### 4.6 Type text

```bash
axe type 'search query' --udid $UDID
```

## Phase 5: Verification

### 5.1 Visual verification loop

```bash
# 1. Screenshot
axe screenshot --udid $UDID --output tmp/verify.png

# 2. Read with Read tool (Claude can see images)
# Use the Read tool on tmp/verify.png

# 3. If something is wrong, inspect accessibility tree
axe describe-ui --udid $UDID

# 4. Fix code, rebuild, redeploy (back to Phase 2)
```

### 5.2 Log verification

After capturing logs (Phase 3), check for:
- Timing metrics (lines with `⏱`)
- Error messages
- Unexpected warnings
- Network request status

## Phase 6: Deep Link Navigation

If the app supports deep links or URL schemes:
```bash
xcrun simctl openurl $UDID "myapp://screen/detail?id=123"
```

## Common Patterns

### Full verify-after-change cycle
```bash
# Build
tuist xcodebuild build -scheme Application \
  -destination "platform=iOS Simulator,id=$UDID" \
  2>&1 | xcsift -f toon -q --xcbeautify

# Redeploy
xcrun simctl install $UDID "$APP_PATH"
xcrun simctl terminate $UDID <bundle-id> 2>/dev/null
xcrun simctl launch $UDID <bundle-id>
sleep 3

# Verify
axe screenshot --udid $UDID --output tmp/verify.png
```

### Screenshot naming convention
Use versioned names for iterative debugging:
```
tmp/simulator_3d_v1_initial.png
tmp/simulator_3d_v2_after_fix.png
tmp/simulator_3d_v3_final.png
```

## Limitations

- **No multi-touch**: AXe supports single-finger only (no pinch/rotate)
- **Fire-and-forget taps**: AXe confirms dispatch, not that the app processed it — always verify with `describe-ui` or `screenshot` after
- **No assertion framework**: This is observation-based verification, not automated testing. For assertions, use XCUITest.
- **Private APIs**: AXe uses Apple's private SimulatorKit + AccessibilityPlatformTranslation frameworks. May break with major Xcode updates.
