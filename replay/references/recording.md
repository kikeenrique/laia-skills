# Recording workflow

## Mode matrix

| `REPLAY_RECORD_MODE` × `REPLAY_PLAYBACK_MODE` | `strict` | `passthrough` | `live` |
| --- | --- | --- | --- |
| `none` (default) | Pure playback. CI default. | Playback; fall back to network on miss. No recording. | Always live; fixtures ignored. |
| `once` | Record if archive missing, else playback strict. Dev default. | Record if missing; playback then network fallback. | Record if missing; live otherwise. |
| `rewrite` | Rewrite archive this run, then playback from it. Use after API change. | Rewrite + fallback. Rare. | Rewrite + live. Rare. |

## Typical dev loop

```bash
# 1. New test — archive missing
swift test --filter YourSuite.fetchUser          # fails with "Replay Archive Missing"

# 2. Record once
REPLAY_RECORD_MODE=once swift test --filter YourSuite.fetchUser

# 3. Inspect + redact
swift package replay inspect Tests/YourTests/Replays/fetchUser.har
# …review for secrets, add filters if needed…

# 4. Re-run normally, confirm playback
swift test --filter YourSuite.fetchUser           # passes from HAR

# 5. Commit
git add Tests/YourTests/Replays/fetchUser.har
```

## xcodebuild / Xcode projects

For `xcodebuild test`, do **not** rely on plain `REPLAY_RECORD_MODE=once xcodebuild test …`.
Apple documents a dedicated forwarding convention in `man xcodebuild`:

```text
TEST_RUNNER_<VAR>
  Set an environment variable whose name is prefixed with TEST_RUNNER_
  to have that variable passed, with its prefix stripped, to all test
  runner processes launched during a test action.
```

So Replay recording should be invoked as:

```bash
TEST_RUNNER_REPLAY_RECORD_MODE=once xcodebuild test \
  -workspace MyWorkspace.xcworkspace \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:MyTests/MySuite/myTest
```

Inside the test runner process, that becomes `REPLAY_RECORD_MODE=once`, which Replay reads from `ProcessInfo.processInfo.environment`.
The playback equivalent is `TEST_RUNNER_REPLAY_PLAYBACK_MODE`.

Avoid `build-for-testing` and manual `.xctestrun` edits solely to pass Replay env vars. They add extra moving parts and are unnecessary when `TEST_RUNNER_*` is available.

## Tuist / mise wrappers

If a repo runs tests through Tuist or a task runner that ultimately invokes `xcodebuild test`, treat that as a wrapper-specific concern rather than general `swift test` or raw `xcodebuild` usage.

Translate the simpler developer-facing variables before invoking xcodebuild:

```bash
if [[ -n "${REPLAY_RECORD_MODE:-}" && -z "${TEST_RUNNER_REPLAY_RECORD_MODE:-}" ]]; then
  export TEST_RUNNER_REPLAY_RECORD_MODE="$REPLAY_RECORD_MODE"
fi

if [[ -n "${REPLAY_PLAYBACK_MODE:-}" && -z "${TEST_RUNNER_REPLAY_PLAYBACK_MODE:-}" ]]; then
  export TEST_RUNNER_REPLAY_PLAYBACK_MODE="$REPLAY_PLAYBACK_MODE"
fi
```

Then developers can run:

```bash
REPLAY_RECORD_MODE=once mise run test MyScheme
REPLAY_RECORD_MODE=once tuist test MyScheme
```

## Re-recording after an API change

Endpoint changed shape? Rewrite:

```bash
REPLAY_RECORD_MODE=rewrite swift test --filter YourSuite.fetchUser
```

Then re-review the diff of the HAR file before committing — it's a good sanity check that the change is intentional.

## CI guarantees

- **Never** export `REPLAY_RECORD_MODE` in CI config. Default (`none`) is correct.
- **Never** run CI with `REPLAY_PLAYBACK_MODE=live` — it makes tests flaky on the network and can leak credentials through outbound traffic.
- Keep fixtures in the repo (committed), not stored as CI artifacts.

## Running against the real API locally

Handy during development:

```bash
REPLAY_PLAYBACK_MODE=live swift test --filter YourSuite.fetchUser
```

This ignores the fixture and goes to the network. Useful to confirm a test still matches real behavior before re-recording.

## Plugin-based recording

```bash
# Equivalent to REPLAY_RECORD_MODE=once swift test --filter …
swift package replay record YourSuite.fetchUser
```

Note: the argument to `record` is the test filter, but the **archive path** is determined by the `.replay("name")` trait (or the test-derived name), not the filter string.
