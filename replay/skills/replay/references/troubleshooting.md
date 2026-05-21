# Troubleshooting

## "Replay Archive Missing"

The test requested `Replays/<name>.har` and it's not on disk. This is the expected first-run behavior.

**Fix:** record intentionally.

```bash
REPLAY_RECORD_MODE=once swift test --filter YourSuite.yourTest
```

If you *intended* to replay an existing fixture, check:

- Is the file committed and copied into the test bundle? (SPM needs `resources: [.copy("Replays")]`.)
- Does `.replay("name")` match the file name exactly, minus `.har`?
- If using `@Suite(.playbackIsolated(replaysRootURL: …))`, is the URL resolving correctly? Print it.

## "No Matching Entry in Archive"

The archive exists but no entry matched the incoming request. Almost always a matcher problem.

**Fix flow:**

1. Inspect the archive: `swift package replay inspect path/to/file.har`.
2. Compare the logged request (method + URL) to the archive entries.
3. Identify what differs — usually a query param, header, or body field that changed between recording and now.
4. Relax the matcher: `matching: [.method, .path]` tolerates query noise.
5. If the API genuinely changed: `REPLAY_RECORD_MODE=rewrite swift test --filter …`.

## "I added `scope: .test` and my tests hang / fail"

You're still using `URLSession.shared`. Per-test scope routes via a custom HTTP header that only `Replay.session` adds. Swap:

```swift
// ❌ Before
let client = APIClient(session: .shared)

// ✅ After
let client = APIClient(session: Replay.session)
```

## Stacked `.replay(...)` traits

Don't do this:

```swift
@Test(.replay("fetchUser"), .replay("fetchPosts"))   // ❌
```

Record multiple entries into a single HAR instead. The framework treats a test as having **one** archive.

## Fixtures not found in Xcode test target

Xcode projects without SPM bundles need an explicit root URL:

```swift
private final class TestBundleToken {}

@Suite(
    .playbackIsolated(
        replaysRootURL: Bundle(for: TestBundleToken.self)
            .resourceURL?
            .appendingPathComponent("Replays")
    )
)
```

And confirm the `Replays/` folder is a resource of the test target (check Build Phases → Copy Bundle Resources).

## CI records fixtures, dev doesn't

Someone set `REPLAY_RECORD_MODE` in the CI environment. Remove it — default (`none`) is correct for CI. Recording is a dev-only action.

## `AsyncHTTPClient` requests not being intercepted

The `.replay(...)` trait uses `URLProtocol`, which AsyncHTTPClient bypasses. See [async-http-client.md](async-http-client.md) — use `ReplayHTTPClient` with dependency injection.
