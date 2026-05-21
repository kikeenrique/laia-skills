# Tooling — `swift package replay`

Replay ships a Swift Package Manager command plugin. All commands accept `--allow-writing-to-package-directory` to skip SwiftPM's confirmation prompt; use it in scripts.

## `status`

```bash
swift package replay status
```

Lists archives, their age, and orphans (HAR files with no matching test). Useful as a periodic hygiene check.

## `record`

```bash
swift package replay record YourSuite.fetchUser
```

Equivalent to `REPLAY_RECORD_MODE=once swift test --filter YourSuite.fetchUser`. Use `--rewrite` (or `--mode rewrite`) to force a fresh recording.

The **archive name and location** come from your `.replay("name")` trait (or the auto-derived name) — not from the `--filter` string.

## `inspect`

```bash
swift package replay inspect Tests/YourTests/Replays/fetchUser.har
```

Human-readable dump of entries: method, URL, status, headers. First thing to run when a match fails.

## `validate`

```bash
swift package replay validate Tests/YourTests/Replays/fetchUser.har
```

Checks HAR schema correctness. Run in CI if you hand-edit fixtures.

## `filter`

```bash
swift package replay filter input.har output.har \
  --headers Authorization Cookie \
  --query-params token api_key
```

Post-hoc redaction. Prefer record-time `filters:` in the trait when possible — see [redaction.md](redaction.md).

Input and output paths can be the same file to redact in place.
