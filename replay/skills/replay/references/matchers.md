# Matchers

Matchers decide whether an incoming request is served by a HAR entry. They compose with **AND** — all listed matchers must pass.

## Default

`[.method, .url]` — strict, catches everything the recording captured, but breaks on any URL drift.

## Built-in matchers

| Matcher | Matches | When to use |
| --- | --- | --- |
| `.method` | HTTP method (case-insensitive) | Always include. |
| `.url` | Full `URL.absoluteString` (scheme, host, port, path, query, fragment) | Stable URLs only. |
| `.host` | URL host | Cross-environment (staging ↔ prod) tests. Rare. |
| `.path` | URL path | Most common partner to `.method` — tolerant of query noise. |
| `.query` | Query items, **order-insensitive** | Pair with `.path` when certain params matter. |
| `.fragment` | `#fragment` | Very rare. |
| `.headers([...])` | Values of named request headers (case-insensitive names) | Match on `Accept`, API version headers, tenancy IDs. |
| `.body` | Raw request body bytes | POST/PUT with deterministic payloads. |
| `.custom((URLRequest, URLRequest) -> Bool)` | Anything you can compute | Escape hatch — prefer built-ins. |

## Choosing a matcher set

- **Start** with `[.method, .path]` for most APIs. It handles pagination cursors, timestamps, and cache-busters gracefully.
- **Add `.query`** when the test genuinely depends on specific query values (e.g., pagination `page=2`).
- **Add `.headers(["X-API-Version"])`** when the endpoint's contract depends on a header.
- **Add `.body`** for writes where the payload distinguishes entries.
- **Use `.url`** only when you're sure URLs are stable — otherwise you'll chase mismatches.

## Custom matcher

```swift
.custom { incoming, candidate in
    // Example: match only if the incoming URL path starts with /v2/
    incoming.url?.path.hasPrefix("/v2/") == true &&
    incoming.url?.path == candidate.url?.path
}
```

Custom matchers receive `(request, candidate)`. Keep them pure and fast — they run for every candidate entry on every request.

## Debugging mismatches

When a test fails with "No Matching Entry in Archive":

1. Inspect the archive: `swift package replay inspect path/to/file.har`.
2. Compare the failing request line (method + URL) to the archive entries.
3. Identify the volatile piece (query param, header, body field).
4. Relax the matcher set **or** add a filter that normalizes the field during recording.

Re-recording is sometimes the right answer (the API genuinely changed). Prefer relaxing matchers when the change is cosmetic (ordering, timestamps, cursors).
