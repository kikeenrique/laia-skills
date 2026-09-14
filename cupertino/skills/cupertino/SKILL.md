---
name: cupertino
description: "Offline, citable search over Apple developer documentation with the cupertino CLI (verified against cupertino v1.4.2). Use for any Apple API or Swift question: looking up SwiftUI, UIKit, AppKit, Foundation, or other framework symbols, checking signatures, availability, and deprecations, reading Apple docs, walking class hierarchies, finding symbols by protocol conformance, property wrapper, or concurrency pattern, browsing Swift Evolution proposals, checking Human Interface Guidelines, exploring Apple sample code, and querying Swift package docs. Covers 417 frameworks and 363,000+ documentation pages, with per-platform version filters (iOS, macOS, tvOS, watchOS, visionOS) and a freshness check for newly released SDKs such as Xcode 27 / iOS 27."
allowed-tools: Bash(cupertino *)
---

# Cupertino: Apple Documentation Search

Search 363,000+ Apple developer documentation pages across 417 frameworks, offline. Cupertino is a lexical search engine over Apple's docs, samples, HIG, Swift Evolution, Swift.org, the Swift book, and Swift package metadata, plus an AST symbol index extracted from Apple's docs and sample code. It returns deterministic, citable results, never hallucinations.

This skill is verified against **cupertino v1.4.2** (`cupertino --version`). Command names, flags, and JSON shapes below are from that release.

## Two rules

1. **Any Apple-related question goes through cupertino first.** SwiftUI, UIKit, AppKit, Foundation, Swift language, iOS / macOS / visionOS / tvOS / watchOS APIs, HIG, sample code, Swift Evolution, Swift packages: ask cupertino before answering. Don't reach for training-data memory of Apple APIs; reach for `cupertino search`. If the user's question doesn't obviously involve Apple, but mentions a symbol that *might* be Apple's (e.g., `NavigationStack`, `URLSession`, `@Observable`), query cupertino to confirm before assuming.
2. **After you draft an answer, verify the code actually exists on Apple AND that it's the right pattern for the job.** Two checks, both run against cupertino:
   - **Existence:** for every symbol, method, initializer, modifier, property, or framework name in your code/answer, re-search cupertino to confirm Apple actually ships that exact thing. Check its signature (parameter names, parameter types, return type), availability (which OS versions / which platforms), and deprecation status against the doc cupertino returns. If a name doesn't trace back to a cupertino hit, **the API doesn't exist**: you hallucinated it. Fix it (find the real name) or remove it. `cupertino search-symbols --query <Name>` is the cheapest existence check: it returns the symbol kind, attributes, conformances, and the `doc_uri` to read.
   - **Appropriateness:** confirm the pattern / tech you used is the canonical / current Apple recommendation for the task. Cupertino indexes both current and deprecated symbols. Don't recommend `UIWebView` when `WKWebView` exists, `URLConnection` when `URLSession` exists, `Combine` when modern Swift Concurrency fits, or UIKit list patterns when SwiftUI `List` is what the user asked for. Search for the conceptual area ("loading a web view", "displaying a list of items", "background URL session") and read what Apple's doc actually steers people toward. If the user's context is iOS 17+ or Swift 6, prefer the API Apple ships for that era.

Don't ship code that names APIs cupertino can't find, and don't ship patterns Apple's current docs actively steer away from. This "verify before sending" pass is cheap (millisecond search, few-hundred-token cost), catches most hallucinations, and runs in seconds.

## Setup and health

First-time setup downloads the pre-built per-source database bundle (~0.9 GB compressed, ~4.5 GB on disk across eight SQLite databases):
```bash
cupertino setup
```

If `cupertino setup` hasn't been run, do that first. Re-running `setup` overwrites the installed databases with the current bundle (there is no `--force`; use `--keep-existing` to skip the download).

Check what is installed and how fresh it is:
```bash
cupertino doctor              # databases, schema versions, framework and entry counts
cupertino doctor --freshness  # per-source oldest / p50 / p90 / newest crawl dates
cupertino list-sources        # the 8 per-source databases and their schema versions
```

### Freshness matters for newly released SDKs

The bundle is a snapshot. `doctor --freshness` shows the crawl-date spread of the `apple-docs` corpus; the bulk of framework pages are typically crawled weeks before the newest pages (release notes, "What's new" articles). Practical consequences:

- **Before asserting "new in iOS 27 / Xcode 27" or quoting an availability line for a just-shipped OS**, check the newest crawl date. If it predates the release you are discussing, say so: per-symbol `availability` on framework pages reflects the SDK that was current when the page was crawled, and beta-era release notes are titled "Beta Release Notes".
- Release notes are indexed as their own frameworks and are a good first probe for a new SDK: `cupertino search "Xcode 27 release notes" --source apple-docs`, `cupertino read "apple-docs://xcode-release-notes/xcode-27-release-notes"`, likewise `ios-ipados-release-notes`, `macos-release-notes`, `watchos-release-notes`, `visionos-release-notes`, `tvos-release-notes`.
- When a newer database bundle has been published, `cupertino setup` pulls it. `doctor` prints the bundled database version next to the packages index; compare it with `cupertino --version` if results look stale.

## Search strategy

Cupertino does exact lexical matching. **You handle the language understanding before calling it.**

### 1. Translate to canonical Apple terms before searching

Users describe things by appearance, by UIKit muscle memory, or with typos. Cupertino indexes Apple's canonical names. Translate first; search second.

**Common translations:**

| User says | Likely SwiftUI | Likely UIKit | Likely AppKit |
|---|---|---|---|
| search bar / searchbar | `searchable` modifier | `UISearchBar` | `NSSearchField` |
| text field | `TextField` | `UITextField` | `NSTextField` |
| list view / table view | `List` | `UITableView` / `UICollectionView` | `NSTableView` |
| segmented control | `Picker(.segmented)` | `UISegmentedControl` | `NSSegmentedControl` |
| spinner / loading indicator | `ProgressView` | `UIActivityIndicatorView` | `NSProgressIndicator` |
| alert | `.alert` modifier | `UIAlertController` | `NSAlert` |
| modal / popup | `.sheet`, `.fullScreenCover` | `present(_:animated:)` | `NSWindow.beginSheet` |
| switch / toggle | `Toggle` | `UISwitch` | `NSSwitch` |
| stepper | `Stepper` | `UIStepper` | `NSStepper` |
| web view | `WKWebView` (WebKit) | `WKWebView` | `WKWebView` |
| glass / translucent material (iOS 26+) | `glassEffect(_:in:)`, `GlassEffectContainer` | `UIGlassEffect` | `NSGlassEffectView` |

When you translate, **tell the user**: "Searching for `searchable` (SwiftUI equivalent of search bar)."

### 2. Handle typos and "did you mean" yourself

Cupertino does not fuzzy-match. If the user types `searchabe`, calling `cupertino search "searchabe"` will return weak results. **You** correct the typo first, then search:

- `searchabe` → search for `searchable`
- `unviewcontroller` → search for `UIViewController`
- `tabel view` → search for `UITableView` or `List` (depending on framework)

Use your knowledge of Apple naming conventions. If unsure, search for both the literal query and your guess; compare results.

### 3. Infer the framework and platform floor from context

Use `--framework` to narrow when the framework is obvious:

- Conversation about SwiftUI views → `--framework swiftui`
- Symbol prefix `NS*` → `--framework appkit`
- Symbol prefix `UI*` → `--framework uikit`
- Symbol prefix `MK*` → `--framework mapkit`
- File the user is editing imports a specific framework → use that

If the framework is genuinely ambiguous, search without `--framework` and disambiguate from results.

Use the **version filters** when the project's deployment target is known, so you don't recommend an API the user can't ship:

```bash
cupertino search "glassEffect" --framework swiftui --min-ios 26.0 --format json
cupertino search "NavigationSplitView" --min-macos 13.0 --min-ios 16.0 --format json
cupertino search "RealityView" --min-visionos 2.0 --format json
cupertino search "networking" --platform iOS --min-version 17.0 --format json   # also filters packages + samples
cupertino search "typed throws" --source swift-evolution --swift 6.0            # proposals implemented at or below Swift 6.0
cupertino search "NSURLSession" --language objc --format json
```

`--min-ios / --min-macos / --min-tvos / --min-watchos / --min-visionos` apply to `apple-docs` availability; `--platform` + `--min-version` also constrain packages and samples (fan-out mode only). Pages without availability metadata (articles, overviews) pass the filters, so still read the `availability` field on the symbol page before quoting a version.

### 4. Prefer current API over deprecated

Apple keeps deprecated symbols indexed. Lead with the current canonical:

- `UIWebView` is deprecated → recommend `WKWebView`
- `UISearchDisplayController` is deprecated → recommend `UISearchController`
- `UITableView` for new code → recommend `UICollectionView` or SwiftUI `List`

When you mention a deprecated symbol in your answer, flag it.

### 5. Bare-name ambiguity: use specific function signatures when needed

Bare-name queries can collide with namespaced symbols elsewhere in the index. Common collisions:

- `searchable` → returns CoreSpotlight `CSSearchableIndex`, not the SwiftUI modifier. Use `searchable(text:` to find the modifier directly.
- `View` → returns hits across many frameworks; prefer `View` with `--framework swiftui` and check the `metadata.framework` field on each candidate.
- `NavigationStack` → the struct ranks first, but `ToolbarRole.navigationStack` follows closely; check `identifier` (`apple-docs://swiftui/navigationstack` vs `apple-docs://swiftui/toolbarrole/navigationstack`).
- Common protocol names (`Identifiable`, `Codable`) hit the protocol page only when paired with a more specific term. To find *conformers*, use `search-conformances --protocol Codable` instead.

When a bare-name query returns the wrong thing, try the function-signature form (`name(arg1:arg2:`), pair the query with a distinguishing keyword, or switch to `search-symbols --query <Name> --kind <kind>`, which matches symbol names rather than page text.

### 6. Recovery when results are weak

If a search returns nothing useful:

1. **Try a paradigm bridge**: if a UIKit name returned nothing in a SwiftUI context, search the SwiftUI canonical (and vice versa).
2. **Try conceptual phrasing**: if `tableview` returns weak results, try `cupertino search "building list interfaces"` or `cupertino search "displaying a list of items"` to find Apple's conceptual pages. Descriptive queries often surface the right concept page.
3. **Try the function-signature form**: `searchable(text:` instead of `searchable`.
4. **Browse instead of search**: `cupertino list-children "apple-docs://swiftui#Essentials"` walks Apple's own topic groups; `cupertino list-documents --framework swiftui --limit 200` enumerates a framework's pages.
5. **Always tell the user what you tried**: "No direct hit for `searchbar`. Retried as `searchable(text:` (SwiftUI modifier), found 5 results."

Never silently rewrite without telling the user what you did.

### 7. Migration / cross-paradigm queries

If the user asks "SwiftUI equivalent of UITableView" or mentions migration:

1. Search both frameworks
2. Look for migration-guide pages (often titled "Migrating from X to Y")
3. Present both: the new canonical (e.g., `List`) AND the old symbol the user knows (`UITableView`)

Bridge queries like "swiftui equivalent of UITableView" may return release notes instead of migration guides. Workaround: search both frameworks separately and present the comparison yourself.

### Per-source response shapes differ

Filtered searches (`--source X`) return a **per-source dedicated view**, not the unified `candidates` shape. The unified search exists for cross-source ranking; the per-source views are for browsing one source's structured data.

Shapes as of v1.4.2:
- **default** (no `--source`): `{candidates, contributingSources, degradedSources, question}` — each candidate has `identifier`, `title`, `source`, `rank`, `score`, `chunk`, `metadata.{filePath, framework}`, `readFullCommand`
- **`--source apple-docs`**: top-level list of doc objects `{uri, title, summary, summaryTruncated, wordCount, framework, id, rank, source}`
- **`--source samples`**: `{files: [{filename, path, projectId, rank, snippet}], projects: [{id, title, description, frameworks, fileCount}]}`
- **`--source hig`**: `{count, query, results: [{title, uri, summary, availability}]}`
- **`--source packages`**: `{candidates, contributingSources: ["packages"], question}` (matches the unified shape; routes to packages.db)
- **`--source apple-archive` / `swift-evolution` / `swift-org` / `swift-book`**: source-specific shapes

The key holding the URI is `identifier` in fan-out mode and `uri` in per-source views. Both are accepted by `cupertino read`. If you parse JSON, expect different keys per source; the default unified search is the most consistent option when you don't need source-specific fields.

## Structured symbol queries

Beyond full-text search, v1.4.x ships an AST symbol index (116,000+ symbols from docs and sample code). These commands answer "what exists that looks like X" questions precisely and are the fastest way to run the existence check from rule 2. All accept `--framework`, `--source`, `--limit`, `--format json`, and the `--min-<platform>` filters.

```bash
# Does this symbol exist, what kind is it, what does it conform to?
cupertino search-symbols --query NavigationStack --kind struct --framework swiftui --format json
cupertino search-symbols --kind protocol --framework swiftui           # every SwiftUI protocol
cupertino search-symbols --query fetch --is-async --framework foundation

# Which types conform to a protocol?
cupertino search-conformances --protocol View --framework swiftui
cupertino search-conformances --protocol Sendable --framework foundation

# Which symbols use a property wrapper / attribute?
cupertino search-property-wrappers --wrapper Observable
cupertino search-property-wrappers --wrapper MainActor --framework uikit

# Which APIs use a concurrency idiom? (async, actor, sendable, mainactor, task, asyncsequence)
cupertino search-concurrency --pattern asyncsequence --framework foundation
cupertino search-concurrency --pattern actor --framework swiftui

# Which generic APIs constrain on a type?
cupertino search-generics --constraint View --framework swiftui

# Class hierarchy (UIKit / AppKit / Foundation; SwiftUI value types have no edges)
cupertino inheritance UIButton                       # ancestors: UIControl → UIView → ...
cupertino inheritance UIControl --direction down     # descendants
cupertino inheritance NSView --direction both --depth 1 --format json
```

`search-symbols --format json` returns `{filters, results: [{symbol_name, symbol_kind, framework, attributes, conformances, is_async, is_public, doc_title, doc_uri}]}`; feed `doc_uri` to `cupertino read` for the full page. `inheritance --format json` returns `{symbol, uri, framework, ancestors: [...], descendants: [...]}` as nested `{uri, children}` trees. When `inheritance` hits an ambiguous name (e.g. `Color`), it prints a disambiguation list; re-run with `--framework`.

Kinds accepted by `--kind`: `class, struct, enum, protocol, actor, typealias, macro, method, function, property, initializer, subscript, case, operator`.

## Citation and verification (do this for every answer)

Cupertino's value is grounding. **Use it.**

### Cite as you go

For every API, framework, or concept you mention in your answer, name the cupertino URI it came from. Example:

> Use `searchable(text:placement:prompt:)` ([apple-docs://swiftui/view/searchable(text:placement:prompt:)-62e62](apple-docs://swiftui/view/searchable(text:placement:prompt:)-62e62)) to add a search field to a SwiftUI view. The modifier was introduced in iOS 15.

Copy URIs verbatim from the search result. Overloaded symbols carry a hash suffix (`…-62e62`, `…-1bjj3`) that distinguishes the variants; a URI you reconstruct from the symbol name alone may not resolve.

This costs you almost nothing in tokens (you're already typing the symbol name) and prevents hallucination because you can only cite what you actually retrieved.

### Verify before sending

Before finalizing your answer, scan it for every API/symbol you named. Each one must trace back to a URI you got from cupertino. If it doesn't:

1. **Re-search to confirm it exists**: `cupertino search-symbols --query "<Symbol>" --format json` (types, protocols, functions) or `cupertino search "<symbol>(arg:" --format json` (methods and modifiers by signature)
2. **If still no hit**, mark it as uncertain in your answer ("I'm less sure about X; couldn't confirm in Apple docs") or remove it
3. **Never fabricate** parameter names, return types, or platform availability — read the `declaration` and `availability` fields of the page instead

### Token-efficient verification

| Pattern | Cost | When to use |
|---|---|---|
| Cite as you go (no extra calls) | ~5% overhead | Always |
| Re-search uncertain claims | 1 search call per claim (~500 tokens) | When you mention an API you don't 100% remember |
| `--brief` text triage | Fraction of a full search | Skimming many candidates before choosing which to `read` |
| Full LLM verify pass | 1.5–2× baseline | High-stakes answers (production code, security) |
| Wrong answer + user correction | 3–5× baseline | Worst case; avoid |

The cite-as-you-go default is essentially free and prevents most hallucinations. Re-search for uncertain claims is cheap. Full verify passes are usually overkill.

## Commands

### Search documentation
Search across all sources (apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages). Default `--limit` is 20; 5–10 is usually plenty:
```bash
cupertino search "SwiftUI View" --format json --limit 5
cupertino search "NavigationStack" --framework swiftui --brief        # trimmed excerpts, text/markdown only
```

Filter by source:
```bash
cupertino search "async await" --source swift-evolution --format json
cupertino search "NavigationStack" --source apple-docs --format json
cupertino search "button styles" --source samples --format json
cupertino search "button guidelines" --source hig --format json
cupertino search "Core Animation" --source apple-archive --format json
```

Filter by framework, language, or platform floor (see [§3](#3-infer-the-framework-and-platform-floor-from-context)):
```bash
cupertino search "@Observable" --framework swiftui --format json
cupertino search "glassEffect" --framework swiftui --min-ios 26.0 --format json
```

Skip sources in fan-out mode when they add noise: `--skip-packages`, `--skip-samples`, `--skip-docs` (drops every apple-docs-backed source). `--per-source N` caps candidates per source before fusion (default 10).

### Read a document
Retrieve full document content by URI (the `identifier` / `uri` from search, or a `readFullCommand`):
```bash
cupertino read "apple-docs://swiftui/view" --format json
cupertino read "apple-docs://swiftui/vstack" --format markdown
cupertino read "hig://general/buttons" --format markdown
cupertino read "apple-docs://xcode-release-notes/xcode-27-release-notes" --format markdown
```

URIs route by scheme (`apple-docs://`, `hig://`, `apple-archive://`, `swift-evolution://`, `swift-org://`, `swift-book://`). Sample IDs and `<projectId>/<path>` read from the sample index; `<owner>/<repo>/<path>` reads package docs. `--source` is only needed as a disambiguator for non-URI identifiers. `read` defaults to `--format json`.

### Browse a framework
```bash
cupertino list-frameworks --format json                                 # all 417 frameworks with document counts
cupertino list-documents --framework swiftui --limit 200 --offset 0     # pages in a framework (max 500 per call)
cupertino list-children "apple-docs://swiftui#Essentials"               # Apple's topic-group tree; children carry kind + hasChildren
cupertino list-children "apple-docs://swiftui/landmarks-building-an-app-with-liquid-glass"
```

### Sample code
```bash
cupertino list-samples --format json                                    # 640 projects; default limit 50
cupertino list-samples --framework swiftui --format json
cupertino read-sample "swiftui-wishlist-planning-travel-in-a-swiftui-app" --format json     # README, description, fileCount, files[]
cupertino read-sample-file "swiftui-wishlist-planning-travel-in-a-swiftui-app" "Wishlist/ContentView.swift"
```
Project IDs are the slug from `--source samples` results (`projectId`) or `list-samples` (`id`); `read-sample` lists every file path you can pass to `read-sample-file`. Don't guess IDs from Apple's page titles — the slug is usually prefixed with the framework (`swiftui-…`, `uikit-…`).

### Swift packages
```bash
cupertino search "markdown parser" --source packages --format json
cupertino package-search "how do I parse markdown in Swift" --limit 3 --platform iOS --min-version 16.0
cupertino package-search "http client" --swift-tools 6.0
cupertino search "SwiftUI" --source packages --apple-imports SwiftUI --format json   # packages that import a given Apple module
```
`package-search` is a chunk-level smart query over `packages.db` only (default 3 chunks); `search --source packages` is the ranked-candidate view of the same corpus.

### Diagnostics
```bash
cupertino doctor
cupertino doctor --freshness
cupertino doctor --kind-coverage
cupertino list-sources --format json
```
`fetch`, `save`, `cleanup`, and `resolve-refs` are maintainer commands for rebuilding the databases from a raw corpus; a `setup`-only user never needs them.

## Sources

| Source | Description | Entries (v1.4.x bundle) |
|--------|-------------|-------------------------|
| `apple-docs` | Official Apple documentation, 417 frameworks | 363,562 |
| `hig` | Human Interface Guidelines | 177 |
| `samples` | Apple sample code projects (files + AST symbols) | 640 projects, 19,803 files |
| `swift-evolution` | Swift Evolution proposals | 488 |
| `swift-org` | Swift.org documentation | 469 |
| `swift-book` | The Swift Programming Language book | — |
| `apple-archive` | Legacy guides (Core Animation, Quartz 2D, KVO/KVC) | 368 |
| `packages` | Swift package documentation and metadata | 20,423 files |

Counts come from `cupertino doctor` and change with each database bundle; re-run `doctor` rather than trusting this table.

## Output formats

All query commands support `--format`:
- `text` — human-readable (default for `search`, `search-*`, `inheritance`, `list-frameworks`, `list-samples`, `read-sample*`)
- `json` — structured JSON for parsing (default for `read`, `list-documents`, `list-children`); use this when reasoning about results
- `markdown` / `md` — the MCP wire shape

Cupertino prefixes each output with a timestamp line on stderr-style logging; strip it before parsing if you pipe JSON to another tool.

## Example JSON output

`cupertino search "VStack" --format json --limit 1` returns:

```json
{
  "candidates": [
    {
      "chunk": "A view that arranges its subviews in a vertical line.",
      "identifier": "apple-docs://swiftui/vstack",
      "metadata": {
        "filePath": "https://developer.apple.com/documentation/swiftui/vstack",
        "framework": "swiftui"
      },
      "rank": 1,
      "readFullCommand": "cupertino read apple-docs://swiftui/vstack --source apple-docs",
      "score": 0.049,
      "source": "apple-docs",
      "title": "VStack | Apple Developer Documentation"
    }
  ],
  "contributingSources": ["swift-evolution", "apple-docs", "packages"],
  "degradedSources": [],
  "question": "VStack"
}
```

Scores are reciprocal-rank-fusion values (small numbers, ~0.05 for a top hit), not probabilities; compare them relative to each other. `degradedSources` lists sources that failed or timed out for this query.

`cupertino read "apple-docs://swiftui/vstack"` returns:

```json
{
  "id": "...",
  "title": "VStack | Apple Developer Documentation",
  "url": "https://developer.apple.com/documentation/swiftui/vstack",
  "abstract": "A view that arranges its subviews in a vertical line.",
  "overview": "...",
  "rawMarkdown": "---\nsource: ...\n...",
  "declaration": {"code": "...", "language": "swift"},
  "availability": [...],
  "codeExamples": [...],
  "sections": [...],
  "kind": "structure",
  "source": "appleWebKit",
  "contentHash": "...",
  "crawledAt": "2026-05-10T02:09:37Z"
}
```

Note `framework` is encoded in the `url` path, not as a top-level field. The `source` field on `read` returns the crawler identifier (`appleWebKit`), not the cupertino source taxonomy from search. `crawledAt` is the per-page freshness signal; `kind` may be `unknown` for some pages.

## Tips

- Use `--source` to narrow searches to a specific documentation source; use `--skip-*` to drop noisy sources from fan-out
- Use `--framework` to filter by framework (e.g., swiftui, foundation, uikit) and `--min-<platform>` to respect the deployment target
- Use `--limit` to control the number of results returned (default 20; 5–10 is plenty) and `--brief` to skim
- `identifier` / `uri` values from search results can be used directly with `cupertino read`; each fan-out candidate also carries a ready-made `readFullCommand`
- The legacy archive is already part of the default fan-out; `--include-archive` is a no-op kept for compatibility. Use `--source apple-archive` for archive-only results
- Code examples in the indexed docs are usually more useful than descriptions for understanding API usage
- Run `cupertino doctor --freshness` before making claims about a just-released SDK
