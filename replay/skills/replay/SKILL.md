---
name: replay
description: "HTTP recording, playback, and stubbing for Swift tests using the Replay framework (HAR fixtures + Swift Testing traits). Use whenever the user mentions Replay, the .replay(...) trait, HAR fixtures, VCR-style testing in Swift, stubbing URLSession / AsyncHTTPClient, recording network traffic for tests, redacting secrets from fixtures, parallel test execution / scope .test / .playbackIsolated / Replay.session isolation, or troubleshooting 'No Matching Entry in Archive' / 'Replay Archive Missing' errors. Also use for questions about archive resolution — where HAR files are written or read from, recordings landing in DerivedData or vanishing after a rebuild, replaysFrom: vs replaysRootURL: — and about TLS trust / client-certificate / auth-challenge delegates during recording or live mode. Also use when writing or reviewing a Swift @Test that hits the network, when adding fixtures under Replays/, when parallelizing a Replay-using test suite, or when configuring REPLAY_RECORD_MODE / REPLAY_PLAYBACK_MODE for CI."
disable-model-invocation: false
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Replay — HTTP Recording & Playback for Swift Tests

[Replay](https://github.com/mattt/Replay) intercepts HTTP traffic in Swift Testing via HAR fixtures. This skill covers:

1. **Writing tests** with the `.replay(...)` trait
2. **Recording** HAR fixtures (record modes, CI gates)
3. **Redacting** secrets before committing
4. **Matcher troubleshooting** when playback mismatches
5. **Stubs** and **AsyncHTTPClient** when `URLProtocol` interception can't work

Replay ships as a Swift Package. It is a **test-only** dependency — never add it to an app target. Minimums: Swift 6.1+, macOS 10.15+ / iOS 15+.

Current version: **0.6.0**.

---

## Quick decision tree

| User situation | Go to |
| --- | --- |
| Adding Replay to a project for the first time | [Setup](#setup) |
| Writing a new `@Test` that calls the network | [Authoring tests](#authoring-tests) |
| "Replay Archive Missing" on first run | [Recording](#recording-fixtures) |
| "No Matching Entry in Archive" on subsequent runs | [Matchers](references/matchers.md) |
| "Where did my HAR go?" / recordings land in DerivedData or vanish on rebuild | [Archive resolution order](#archive-resolution-order) |
| HAR file contains `Authorization` / cookies / PII | [Redaction](references/redaction.md) |
| Tests need to run in parallel | [Parallel tests](#parallel-execution-scope-test) |
| Code uses `AsyncHTTPClient` (external SwiftNIO-based HTTP client), not `URLSession` | [AsyncHTTPClient](references/async-http-client.md) |
| TLS pinning / client-cert / `didReceive challenge` delegate under Replay | [Live / streaming](#live--streaming-traffic-and-auth-challenges) |
| Managing fixtures from the command line | [Tooling](references/tooling.md) |

---

## Setup

### Swift Package Manager

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mattt/Replay.git", from: "0.6.0")
],
targets: [
    .testTarget(
        name: "YourTests",
        dependencies: [.product(name: "Replay", package: "Replay")],
        resources: [.copy("Replays")]   // ship HAR files into the test bundle
    )
]
```

HAR files live in `Tests/YourTests/Replays/`. You don't have to create the directory by hand — recording creates it next to the test source file if it's missing.

### Xcode (no Package.swift)

Add the package under **File → Add Packages…**, attach `Replay` to the **test target only**, then add `Replays/` to the test target as a **folder reference** (not a group) so it's copied into the bundle with its name intact. Confirm it appears in Build Phases → Copy Bundle Resources.

Then point the suite at the test bundle:

```swift
private final class TestBundleToken {}

@Suite(.playbackIsolated(replaysFrom: Bundle(for: TestBundleToken.self)))
struct YourSuite { /* ... */ }
```

Use `replaysFrom:`, **not** `replaysRootURL: Bundle(for:).resourceURL?…`. The bundle passed to `replaysFrom:` is a *playback fallback* only: when the test's source file exists on the machine running the tests, Replay reads (and always records) `Replays/` next to that source file instead. `replaysRootURL:` is an unconditional directory override that wins for recording too, so it writes fixtures into DerivedData where the next build erases them.

That's all most Xcode, xcodebuild and Tuist projects need — no `#filePath` helper. Replay derives the source directory from the compile-time absolute path in `sourceLocation`, so recording lands in the project tree by itself.

### Archive resolution order

Replay resolves `<name>.har` in this order (`Replays` is the default `directory:`):

1. `rootURL:` passed to the `.replay(...)` trait.
2. A directory from `.playbackIsolated(replaysRootURL:)` — used for **playback and recording alike**.
3. `Replays/` next to the test's source file, when that file is present on this machine. **Recording always writes here**; playback reads here when the archive exists.
4. A bundle from `.playbackIsolated(replaysFrom:)` — playback fallback (copied resources, typically CI).
5. Any loaded bundle carrying `Replays/<name>.har` as a resource.
6. `Replays/` under the current working directory (Linux, or when the source location is unavailable).

Steps 1 and 2 are the only ones that can redirect **recording** away from the source tree — which is why `replaysRootURL:` pointed at a bundle is a trap. Steps 3 and 6 create the directory when recording.

### Why a test-only dependency

Replay's `URLProtocol` interception and Swift Testing traits are only useful in tests, and shipping it in a release binary would pull in unused record/capture code. Keep it scoped.

---

## Authoring tests

Preferred shape — inject `URLSession` into your client so tests can swap it for `Replay.session` when needed. Accepting a session also unlocks parallel test execution later.

```swift
import Foundation
import Testing
import Replay

@Suite(.playbackIsolated(replaysFrom: Bundle.module))
struct UserAPITests {
    @Test(.replay("fetchUser"))
    func fetchUser() async throws {
        let user = try await APIClient.shared.fetchUser(id: 42)
        #expect(user.id == 42)
    }
}
```

**What this does:**

- `@Suite(.playbackIsolated(replaysFrom: Bundle.module))` registers the test bundle's `Replays/` resources as the **playback fallback**. An archive next to the test source still wins, and recording always goes there — see [Archive resolution order](#archive-resolution-order). For Xcode projects without SPM modules, use `Bundle(for: TestBundleToken.self)`.
- `.replay("fetchUser")` loads `Replays/fetchUser.har` and intercepts any HTTP traffic during the test.
- Omitting the name (`.replay()`) derives it from the test name — convenient but less greppable. Prefer explicit names.

### One archive per test

Each HAR file can hold many request/response entries. If a test makes three requests, record them all into one file — do **not** stack multiple `.replay(...)` traits. Stacking is invalid and the framework will reject it.

### Default behavior

- **Playback mode** defaults to `strict`: a missing archive or an unmatched request fails the test.
- **Record mode** defaults to `none`: recording is explicit, not accidental. This is intentional — it prevents a passing CI run from silently rewriting fixtures.

---

## Recording fixtures

The first run of a new test fails with "Replay Archive Missing". That is the signal to record:

```bash
REPLAY_RECORD_MODE=once swift test --filter YourSuite.fetchUser
```

**xcodebuild / Xcode users:** do not rely on plain `REPLAY_RECORD_MODE=… xcodebuild test`.
Apple documents `TEST_RUNNER_<VAR>` in `man xcodebuild`: xcodebuild passes those variables to every test runner process with the prefix stripped. This is standard xcodebuild behavior (not Replay-specific), so prefix Replay's env vars with `TEST_RUNNER_`:

```bash
TEST_RUNNER_REPLAY_RECORD_MODE=once xcodebuild test \
  -workspace … -scheme … -destination … \
  -only-testing:MyTests/MySuite/myTest
```

The test process receives `REPLAY_RECORD_MODE=once` and Replay reads it normally. The same applies to `TEST_RUNNER_REPLAY_PLAYBACK_MODE`. `swift test` passes env vars directly and doesn't need the prefix. Avoid `build-for-testing` / `.xctestrun` editing just to pass Replay env vars; use those only when the project already needs a separate build/test split for other reasons.

**Tuist / mise wrappers:** if a repo runs tests through Tuist or a task runner that ultimately invokes `xcodebuild test`, keep that guidance separate from plain `swift test` and raw `xcodebuild` examples. Prefer making the wrapper translate the developer-facing variables before invoking xcodebuild:

```bash
if [[ -n "${REPLAY_RECORD_MODE:-}" && -z "${TEST_RUNNER_REPLAY_RECORD_MODE:-}" ]]; then
  export TEST_RUNNER_REPLAY_RECORD_MODE="$REPLAY_RECORD_MODE"
fi

if [[ -n "${REPLAY_PLAYBACK_MODE:-}" && -z "${TEST_RUNNER_REPLAY_PLAYBACK_MODE:-}" ]]; then
  export TEST_RUNNER_REPLAY_PLAYBACK_MODE="$REPLAY_PLAYBACK_MODE"
fi
```

That keeps commands ergonomic while still using Apple's documented xcodebuild mechanism:

```bash
REPLAY_RECORD_MODE=once mise run test MyScheme
REPLAY_RECORD_MODE=once tuist test MyScheme
```

Modes:

| `REPLAY_RECORD_MODE` | Behavior |
| --- | --- |
| `none` (default) | Never record. CI should always use this. |
| `once` | Record only if the archive is missing. Safe default for dev. |
| `rewrite` | Overwrite the archive from scratch. Use when the API changed. |

| `REPLAY_PLAYBACK_MODE` | Behavior |
| --- | --- |
| `strict` (default) | Fixtures required; unmatched requests fail. |
| `passthrough` | Use fixtures when available, otherwise hit the real network. |
| `live` | Ignore fixtures; always hit the real network. |

**CI rule of thumb:** never set `REPLAY_RECORD_MODE` in CI. Recording is a developer action. If CI records, the fixture becomes whatever the API returned that day — and secrets may land in the archive.

**Preferred workflow:**

1. Write the test.
2. Run it — it fails with "Replay Archive Missing".
3. Run again with `REPLAY_RECORD_MODE=once` → fixture is created.
4. Inspect the HAR (`swift package replay inspect …`), redact, commit.
5. Subsequent runs replay from disk in `strict` mode.

See [references/redaction.md](references/redaction.md) before committing — HAR files very often carry `Authorization`, `Cookie`, or response bodies with PII.

---

## Matchers (the short version)

By default, Replay matches requests on HTTP method + full URL string. That's strict — any volatile query param (timestamp, cursor, cache-buster) causes a miss. When you see "No Matching Entry in Archive", relaxing the matcher is usually the right call:

```swift
@Test(.replay("fetchUser", matching: [.method, .path]))
```

Full matcher list and guidance in [references/matchers.md](references/matchers.md). Matchers compose with AND — all must match.

---

## Redaction (the short version)

Prefer redacting at record time via `filters:` so secrets never touch disk:

```swift
@Test(
    .replay(
        "fetchUser",
        matching: [.method, .path],
        filters: [
            .headers(removing: ["Authorization", "Cookie", "Set-Cookie"]),
            .queryParameters(removing: ["token", "api_key"]),
        ]
    )
)
```

For body-level redaction and after-the-fact scrubbing via the `swift package replay filter` plugin, see [references/redaction.md](references/redaction.md).

---

## Stubs (no HAR file)

For trivial cases — a single predictable response, or error paths you can't easily reproduce against the real API — use inline stubs instead of a HAR file:

```swift
@Test(
    .replay(stubs: [
        .get("https://example.com/greeting", 200,
             ["Content-Type": "text/plain"], { "Hello, world!" })
    ])
)
func greeting() async throws { /* ... */ }
```

HAR files are better when the response is realistic or large; stubs are better when the response is trivial or must be crafted (e.g., 500s, malformed payloads).

**Combining stubs with the `.headers` matcher:** a `Stub`'s `headers:` are the *response* headers. It has no expected **request** headers by default, so `.headers(["Accept"])` will only match requests where `Accept` is absent — i.e. it always misses. Attach them explicitly:

```swift
@Test(
    .replay(
        stubs: [
            .get("https://example.com/greeting", 200, ["Content-Type": "text/plain"], { "Hello, world!" })
                .matchingRequestHeaders(["Accept": "text/plain"])
        ],
        matching: [.method, .path, .headers(["Accept"])]
    )
)
```

Only the names listed in `.headers([...])` are compared, so it's safe to set more in `matchingRequestHeaders(_:)` than you match on.

---

## Parallel execution (`scope: .test`)

By default Replay uses global `URLProtocol` registration with a lock — tests run serialized. To parallelize, opt into per-test isolation:

```swift
@Suite(.playbackIsolated(replaysFrom: Bundle.module))
struct ParallelTests {
    @Test(.replay("fetchUser", matching: [.method, .path], scope: .test))
    func fetchUser() async throws {
        // MUST use Replay.session, not URLSession.shared
        let client = APIClient(session: Replay.session)
        _ = try await client.fetchUser(id: 42)
    }
}
```

Why the session swap matters: per-test scope routes via a custom HTTP header, and only `Replay.session` (or `Replay.makeSession()`) attaches it. `URLSession.shared` silently falls back to the global store and you'll get cross-test bleed.

`Bundle.module` here is still correct — it's the playback fallback. Recording under this setup lands in `Replays/` next to the test source file, not in the bundle.

---

## Live / streaming traffic and auth challenges

Whenever Replay actually hits the network — `REPLAY_PLAYBACK_MODE=live`, `passthrough` on a miss, recording, or streaming responses such as SSE — it proxies through an internal `URLSession`. Since 0.6.0 both session-level and task-level `URLAuthenticationChallenge`s from that proxy are forwarded to the `URLProtocol` client, so a custom `urlSession(_:didReceive challenge:…)` delegate on the caller's session (server-trust pinning, self-signed staging certs, client certificates) is consulted as it would be without Replay.

Before 0.6.0 those challenges were silently answered with default handling — pinning delegates never fired and self-signed hosts failed. If a test relies on custom TLS trust, require 0.6.0.

---

## Using Replay without Swift Testing

XCTest or manual control is supported via lower-level APIs — `Playback.session(configuration:)`, `Capture.session(configuration:)`, `HAR.load(from:)` / `HAR.save(_:to:)`. See the framework README for full signatures. The trait-based API covers 95% of cases; reach for these only when Swift Testing isn't available.

---

## Reference files

- [references/matchers.md](references/matchers.md) — full matcher table, when to relax `.url`, custom matchers
- [references/redaction.md](references/redaction.md) — record-time filters, body redaction, plugin-based scrubbing, commit checklist
- [references/recording.md](references/recording.md) — record/playback mode matrix, CI gates, re-recording after API changes
- [references/async-http-client.md](references/async-http-client.md) — opt-in support for [AsyncHTTPClient](https://github.com/swift-server/async-http-client) (an **external** SwiftNIO-based HTTP client, not bundled with Replay); enabled via the `AsyncHTTPClient` SwiftPM package trait
- [references/tooling.md](references/tooling.md) — `swift package replay` subcommands (status / record / inspect / validate / filter)
- [references/troubleshooting.md](references/troubleshooting.md) — common errors and their fixes

---

## Things not to do

- **Don't** ship Replay in an app target. It's for tests.
- **Don't** commit HAR files without reading them. Browser-exported HARs and re-recorded fixtures routinely contain cookies, bearer tokens, and PII.
- **Don't** stack `.replay(...)` traits on one test. One archive per test; record multiple entries into it.
- **Don't** set `REPLAY_RECORD_MODE` in CI. Recording is a local dev action.
- **Don't** use `URLSession.shared` with `scope: .test`. Use `Replay.session`.
- **Don't** pass a bundle's resource directory to `.playbackIsolated(replaysRootURL:)`. It overrides recording too, so fixtures land in DerivedData and die with the next build. Use `replaysFrom:`.
- **Don't** reach for `.custom(...)` matchers before trying `.method + .path + .query`. Built-in matchers cover almost everything.
