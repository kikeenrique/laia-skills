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
- Is it in the directory Replay actually looked in? Resolution is ordered (`rootURL:` → `replaysRootURL:` → next to the test source → `replaysFrom:` bundle → any loaded bundle → cwd); an override earlier in that list shadows the file you committed. Print the override URL if you set one.

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

Xcode projects without SPM bundles register the test bundle as the playback fallback:

```swift
private final class TestBundleToken {}

@Suite(.playbackIsolated(replaysFrom: Bundle(for: TestBundleToken.self)))
struct YourSuite { /* ... */ }
```

Use `replaysFrom:`, **not** `replaysRootURL: Bundle(for:).resourceURL?.appendingPathComponent("Replays")`. `replaysRootURL:` is an unconditional directory override (step 2 of resolution) that applies to recording as well, so it writes new fixtures into DerivedData. `replaysFrom:` is a bundle, which is playback-only (step 4) and sits *after* the source tree — so playback still finds copied resources in CI while recording lands in your project.

Also confirm `Replays/` is added to the test target as a **folder reference** (name preserved) and appears in Build Phases → Copy Bundle Resources.

## Recorded HAR disappeared after a rebuild

The archive was written into a build product. Bundles are regenerated on every build, so it's gone.

Causes:

- `.playbackIsolated(replaysRootURL: someBundle.resourceURL?…)` — the directory override applies to recording. Switch to `.playbackIsolated(replaysFrom: someBundle)`.
- A `rootURL:` on the `.replay(...)` trait pointing into DerivedData. Drop it.
- Replay older than 0.6.0, where a `replaysFrom:` bundle was also used for recording. Upgrade to 0.6.0.

With 0.6.0 and neither override set, recording always writes `Replays/` next to the test's source file (creating the directory if needed) — check there first before assuming it failed.

## `.headers` matcher never matches my stubs

`Matcher.headers([...])` compares *request* headers, but a `Stub`'s `headers:` argument is the **response** headers. A stub has no expected request headers by default, so the matcher only passes when the named header is absent from the incoming request — i.e. it always misses on a real request.

```swift
.get("https://example.com/greeting", 200, ["Content-Type": "text/plain"], { "Hello!" })
    .matchingRequestHeaders(["Accept": "text/plain"])   // ✅ compared against the request
```

Only the names you list in `.headers([...])` are compared, so setting extra headers here is harmless. (HAR-based playback is unaffected — recorded entries carry real request headers.)

## Auth challenge delegate never called during record / live

A custom `urlSession(_:didReceive challenge:…)` (server-trust pinning, self-signed staging cert, client certificate) doesn't fire when the request goes through Replay's live/record/streaming path.

Fixed in **0.6.0**: both session-level and task-level `URLAuthenticationChallenge`s from Replay's internal proxy session are forwarded to the `URLProtocol` client, so the caller's delegate is consulted. Before 0.6.0 they were silently answered with default handling. **Fix:** upgrade to 0.6.0.

Note this only applies to traffic that actually reaches the network. Pure playback from a HAR never establishes a TLS connection, so no challenge is raised — that's expected, not a bug.

## Last resort: pinning the archive root to `#filePath`

Only needed when source-file resolution (step 3) can't work **and** you need recording — e.g. the test source tree isn't present on the machine that runs the tests. Rare; try the plain setup first, because 0.6.0 already does source-relative resolution internally.

```swift
// Tests/YourTests/Support/ReplayTestSupport.swift
import Foundation
import Replay
import Testing

private let replaysRootURL: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support/
    .deletingLastPathComponent()  // YourTests/
    .appendingPathComponent("Replays", isDirectory: true)

extension Trait where Self == ReplayTrait {
    static func replayFromSource(
        _ name: String,
        matchers: [Matcher] = .default,
        filters: [Filter] = [],
        scope: ReplayScope = .global
    ) -> Self {
        ReplayTrait(name, matchers: matchers, filters: filters, rootURL: replaysRootURL, scope: scope)
    }
}
```

Adjust the `.deletingLastPathComponent()` hops to match where the support file sits relative to `Replays/`. `#filePath` is baked in at compile time, so the path belongs to whichever machine compiled the binary — fine when CI compiles its own tests, wrong only if you copy a built test bundle to another machine.

## CI records fixtures, dev doesn't

Someone set `REPLAY_RECORD_MODE` in the CI environment. Remove it — default (`none`) is correct for CI. Recording is a dev-only action.

## `AsyncHTTPClient` requests not being intercepted

The `.replay(...)` trait uses `URLProtocol`, which AsyncHTTPClient bypasses. See [async-http-client.md](async-http-client.md) — use `ReplayHTTPClient` with dependency injection.
