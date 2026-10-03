# Redaction

HAR files capture **everything** sent and received, including `Authorization` headers, session cookies, bearer tokens, and full response bodies. Treat them as sensitive until proven otherwise.

## Prefer record-time filters

Filters run while recording, so secrets never touch disk. This is the safest option.

```swift
@Test(
    .replay(
        "fetchUser",
        matching: [.method, .path],
        filters: [
            .headers(removing: ["Authorization", "Cookie", "Set-Cookie"]),
            .queryParameters(removing: ["token", "api_key", "access_token"]),
            .body(replacing: #""email":"[^"]+""#, with: #""email":"redacted@example.com""#),
        ]
    )
)
```

## Filter API reference

`Filter` is an enum with several convenience constructors:

| Form | Purpose |
| --- | --- |
| `.headers(removing: ["A","B"])` | Redact listed request + response headers (case-insensitive). Replaces value with `[FILTERED]` by default. |
| `.headers(keeping: ["Content-Type"])` | Allowlist — redact everything else. |
| `.headers("A", "B", replacement: "…")` | Variadic form with custom replacement string. |
| `.queryParameters(removing: [...])` / `keeping:` | Same, for URL query items. |
| `.body(replacing: pattern, with: replacement)` | String replacement in request and response bodies. Best for text formats. |
| `.body(decoding: Type.self, transform: { ... })` | Decode JSON to a Codable, mutate, re-encode. Use for structured redaction. |
| `.custom { entry async in ... }` | Full control over a `HAR.Entry`. |

## After-the-fact scrubbing

If you already recorded a fixture that contains secrets, use the package plugin rather than editing JSON by hand:

```bash
swift package replay filter \
  Tests/YourTests/Replays/fetchUser.har \
  Tests/YourTests/Replays/fetchUser.har \
  --headers Authorization Cookie \
  --query-params token api_key
```

Add `--allow-writing-to-package-directory` to skip the confirmation prompt.

## Commit checklist

Before `git add`-ing a new or rewritten HAR:

- [ ] Open the file. Search for `Authorization`, `Cookie`, `Set-Cookie`, `token`, `api_key`, `password`, `ssn`, `email`.
- [ ] Check response bodies for PII that wasn't in the request (real names, emails, internal IDs).
- [ ] Confirm the fixture's `url` host is one you're OK committing (staging vs. prod domains can leak infrastructure).
- [ ] If anything is sensitive, add a filter, re-record with `REPLAY_RECORD_MODE=rewrite`, and re-check.

## Browser-exported HAR files

Safari / Chrome / Firefox can export the Network tab as HAR. These exports are convenient for bootstrapping fixtures but are **particularly dangerous**: they include every header the browser sent, including auth cookies for other sites, CSRF tokens, and analytics beacons. Scrub aggressively — or prefer recording through the test runner, which only captures traffic from the code under test.
