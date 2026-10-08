# Prompt audit of the Claude Code configuration

Status: **audit done 2026-10-08; fixes pending**. The audit looked for instructions that no longer fit
the model, the repo, or each other, using the `/claude-api prompt-audit` method. Findings are below;
the proposed edits are unified diffs in [`prompt-audit/`](prompt-audit/). Re-run the audit at the
next model release or after a large skill upgrade.

## Scope and assumptions

- **Audited** (the configuration Claude Code loads in this project):
  - `AGENTS.md`
  - `~/.claude/CLAUDE.md` and its import `~/.claude/RTK.md`
  - `~/.claude/agents/visionos-engineer.md`
  - the 64 skills linked from `~/.claude/skills/` (installed copies in `~/.agents/skills/`, managed by `laiaskills`): `SKILL.md` frontmatter and body only, not `references/`.
- **Not audited:**
  - the `CLAUDE.md`/`AGENTS.md` files inside submodules (vendored upstream repos, never edited)
  - claude.ai-synced skills (`~/.claude/skills/synced/`, managed by claude.ai)
  - the `swift-lsp` plugin (it has no skills, commands, or agents)
  - settings files and MCP configuration (can hold secrets)
  - auto-memory
- **Target model:** Claude Opus 5.5.
- **Where fixes go:**
  - **First-party skills:** edit the source in `first-party/…`, then `mise run validate` and `mise run laiaskills sync`. Bump the plugin `version` (AGENTS.md rule).
  - **Third-party skills:** edit the installed copy, then `mise run laiaskills patch <skill> -m "<reason>"` and `commit`. Never edit `third-party/`. Patches are re-tested on every upgrade.
  - **Files under `~/.claude/`:** outside the repo, and they affect every project.

## Summary

The always-loaded files are in good shape. `AGENTS.md` names only paths and tasks that exist, and the
global `CLAUDE.md` and `RTK.md` contain only reasoned constraints. Almost all findings are in skills:

1. **Instructions that point at nothing.**
   - Ten first-party visionOS skills hand off to five skills that exist nowhere (`build-run-debug`, `signing-entitlements`, `telemetry`, `test-triage`, `spatial-preview-developer`). Upstream ships them as part of a larger plugin; this install only takes a subset.
   - `debugging-instruments` and the two Android skills route to skills that aren't installed.
   - Every `ui-ux-pro-max` command uses a plugin-only path (`${CLAUDE_PLUGIN_ROOT}/.claude/skills/…`), so none of them runs.
   - The Android skills tell the agent to run upstream-only `examples/` and `scripts/`.
2. **Skills contradicting newer skills.** `apple-hig-designer`, `watchos`, and `macos-design-guidelines` model SwiftUI APIs that `swiftui-pro` and `swiftui-expert-skill` call deprecated: `foregroundColor`, `cornerRadius`, `tabItem`, `PreviewProvider`, `sizeCategory`, `.navigationBarTrailing`. The model copies examples.
3. **Third-party skills against the global rules.** They tell the agent to `cd`, use `/tmp` or `mktemp`, call `find`/`rg`, or open pull requests, which push.

Counts:

| Group | Findings |
|---|---|
| Group 1, dated prompt text | 12 |
| Group 2, brittle configuration | 25, plus 12 flags |
| Group 3, trigger descriptions | 3 |
| Group 4, request config | not applicable (no file builds API requests) |

## Done

| When | What |
|---|---|
| 2026-10-08 | Audit of 64 skills, the global config, and the subagent; report and 84 proposed hunks in [`prompt-audit/`](prompt-audit/) |
| 2026-10-08 | Apple Watch touch target checked against the HIG with cupertino (`hig://general/accessibility`, Mobility; crawled 2026-06-21): default 44x44 pt, minimum 28x28 pt. Both skills were wrong (">44pt", "minimum 38pt"); `design.diff` corrects both |
| 2026-10-08 | `update-swiftui-apis` removed (`1520dc8`). It is a maintainer-only skill from `AvdLee/SwiftUI-Agent-Skill` that edits that repo's own files, needs the Sosumi MCP, and opens PRs. It came in with the 2026-10-04 migration |
| 2026-10-08 | `ios-simulator-ui-flow` compared with [ios-build-verify](https://github.com/vermont42/ios-build-verify), the skill its verification approach draws on: added a *Credits* section crediting it (MIT, Josh Adams), and a troubleshooting entry for AXe's post-boot accessibility-bridge lag (an empty tree or a "fullscreen dialog" error for 10–25 s after `simctl boot`). With the credit in place, M4 can drop the "Patterns Borrowed" section without losing the attribution. Plugin 0.3.0 → 0.3.1 |
| 2026-10-08 | Rule to quote long `description` values dropped from `AGENTS.md` (`235e6d7`). It guarded against Commander's YAML parser, and Commander is deleted. The memory note was rewritten as retired |

## Pending

In priority order.

| # | Task | Who | Notes |
|---|---|---|---|
| 1 | Apply `first-party.diff` (31 hunks, 15 files) | tool + owner | Findings H1, H7, M2–M7. Edit the sources, `mise run validate`, `mise run laiaskills sync`, and bump `visionos-agents`, `cupertino`, and `ios-simulator-ui-flow`. Diverges the vendored visionOS copies from upstream, which AGENTS.md allows |
| 2 | Patch `ui-ux-pro-max` (`design.diff`) | tool + owner | H2, H3, M11. The highest-impact third-party fix: today none of its commands runs |
| 3 | Patch the Android and tooling skills (`android.diff`, 12 hunks, 6 skills) | tool + owner | H4–H6, M14–M18. For `debugging-instruments`, the alternative is to install `ios-memgraph-analysis`, `ios-ettrace-performance`, and `metrickit` from the same source |
| 4 | Patch the design skills (`design.diff`: `apple-hig-designer`, `watchos`, `macos-design-guidelines`) | tool + owner | H8–H11, M12, M13 |
| 5 | Patch the Swift skills (`swift.diff`, 4 hunks) | tool + owner | M8–M10. Hunk 3 also drops `swiftui-ui-patterns`' list of common compile errors; keep it if wanted |
| 6 | Apply `user-level.diff` to `~/.claude/agents/visionos-engineer.md` | owner | M1. Outside the repo; affects every project |
| 7 | Decide the third-party skills that conflict with the global rules | owner | See *Flags*: `debug-generated-project`, `swiftui-ui-patterns`, `swiftui-expert-skill`. Patch them, accept the conflict, or remove the skill |
| 8 | Settle when to commit | owner | Auto-memory says "commit after each task without asking"; the global `CLAUDE.md` says "commit locally when asked". One should change |
| 9 | `laiaskills commit` without a terminal | tool | Without `--yes` it prints a bare usage line and fails; it should say that `--yes` is needed, as `remove` does |

## Findings

### High confidence

| # | Location | Evidence | Pattern | Why | Action |
|---|---|---|---|---|---|
| H1 | `first-party/visionos-agents/skills/`: `arkit-camera-access-providers:40-41`, `arkit-visionos-developer:18-19`, `coding-standards-enforcer:49-52`, `realitykit-visionos-developer:3,32,38,57`, `shareplay-developer:45-50`, `spatial-app-architecture:40,52-53,72`, `spatial-swiftui-developer:19,61-62`, `usdkit-runtime-developer:21` | "use `$signing-entitlements` or `$build-run-debug`", "Switch to `telemetry`", "`spatial-preview-developer`" | G2 volatile specifics | The five target skills exist nowhere: not in the repo, upstream, `~/.agents/skills`, or `skills.json` | rewrite (`first-party.diff`) |
| H2 | `ui-ux-pro-max/SKILL.md:39,42,78…186` | `python "${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/scripts/search.py"` | G2 | The path only exists in a plugin install; this copy has `scripts/search.py` | rewrite to `<skill-dir>/scripts/search.py` (`design.diff`) |
| H3 | `ui-ux-pro-max/SKILL.md:45` | "see README for install instructions" | G2 | The skill folder has no README | rewrite (`design.diff`) |
| H4 | `android-gradle-build-logic/SKILL.md:42-53,27,57`, `android-ci-cd-release-playstore/SKILL.md:42-53,27,57` | "`cd examples/orbittasks-compose && ./gradlew …`", "`python3 scripts/eval_triggers.py`" | G2 | Upstream-only maintainer files; the install has only `scripts/run_examples.sh` | remove/rewrite (`android.diff`) |
| H5 | `android-gradle-build-logic:19-21`, `android-ci-cd-release-playstore:19-21` | "`android-modernization-upgrade`", "`android-security-best-practices`" | G2 | The hand-off targets aren't installed | rewrite (`android.diff`) |
| H6 | `debugging-instruments/SKILL.md:3,8-9,160-161` | "use ios-memgraph-analysis … ios-ettrace-performance", "`metrickit` skill" | G2 | The description routes requests to skills that aren't installed | rewrite (`android.diff`), or install them |
| H7 | `first-party/visionos-agents/skills/tkr-skill-writer/SKILL.md:31-34,60,79-111,160-161` | "Description and Goals / What This Skill Should Do / …", "`system.md`" | G2 | No skill in the plugin uses that layout | rewrite to the layout the plugin uses (`first-party.diff`) |
| H8 | `watchos/SKILL.md:263-290` | `import ClockKit` … `CLKComplicationDataSource` | G2 drift | The skill's own `complications.md` says ClockKit was removed in watchOS 11 | rewrite as a pointer to WidgetKit (`design.diff`) |
| H9 | `watchos/SKILL.md:99-102` | `@Environment(\.sizeCategory)` | G2 contradiction | `swiftui-expert-skill` `latest-apis.md:35` says to use `dynamicTypeSize` | rewrite (`design.diff`) |
| H10 | `apple-hig-designer/SKILL.md` (15× `foregroundColor`, :110, :130-145, :347, :679-690, :835) | `.foregroundColor(`, `.navigationBarTrailing`, `.tabItem`, `.cornerRadius(12)`, `PreviewProvider`, `UIImpactFeedbackGenerator` | G2 contradiction, G1c example over-indexing | `swiftui-pro` `references/api.md` and `views.md` call each of these deprecated | rewrite, one hunk per API (`design.diff`) |
| H11 | `apple-hig-designer/SKILL.md:932`, `watchos/SKILL.md:36` | ">44pt", "minimum 38pt" | G2 contradiction | Both are wrong. HIG: default 44x44 pt, minimum 28x28 pt | rewrite both (`design.diff`) |

### Medium confidence

| # | Location | Evidence | Pattern | Action |
|---|---|---|---|---|
| M1 | `~/.claude/agents/visionos-engineer.md:48-53,72` | "1. **Restate** … 2. **Inspect** … 3. **Plan** … 4. **Implement** in small, verifiable steps." | G1b plan-before-acting, G1c choreography | Remove steps 1–4 and "A brief plan"; keep the review, build, and simulator flow (`user-level.diff`) |
| M2 | `first-party/cupertino/skills/cupertino/SKILL.md:17` | "**the API doesn't exist**: you hallucinated it" | G1a pressure; G2 contradiction with :38-44, :218 | Rewrite: no hit means unverified; check freshness (`first-party.diff`) |
| M3 | `cupertino/SKILL.md:221-231` | "Full LLM verify pass \| 1.5–2× baseline" | G1c strategy coaching | Remove (`first-party.diff`) |
| M4 | `first-party/ios-simulator-ui-flow/skills/ios-simulator-ui-flow/SKILL.md:321-332` | "Patterns Borrowed From ios-build-verify" | G2 history narrative, G1c repetition | Remove (`first-party.diff`) |
| M5 | `ios-simulator-ui-flow/SKILL.md:249,341` | "On Xcode 27 Beta 3, `axe drag` acknowledged …" | G2 history, recency trap | Rewrite to the lasting rule (`first-party.diff`) |
| M6 | `ios-simulator-ui-flow/SKILL.md:219,304,355` | "handled better in AXe `v1.8.0`", "old `swipe --from/--to` forms" | G1d migration-relative | Rewrite or remove (`first-party.diff`) |
| M7 | `realitykit-animation-physics:56-57`, `realitykit-audio-spatial:48-49`, `realitykit-rendering-materials:54-55`, `usdkit-runtime-developer:47-48`, `arkit-rendering-context-providers:50`, `spatial-swiftui-developer:65-68` | "Treat visionOS 27 … additions as beta API", "New in 27" | G2 time-sensitive, G1d | Rewrite with a re-check note (`first-party.diff`) |
| M8 | `swiftui-pro/SKILL.md:29` | "iOS 26 exists, and is the default deployment target" | G1d knowledge-cutoff patch, G2 stale | Rewrite (`swift.diff`) |
| M9 | `swiftui-ui-patterns/SKILL.md:78,81` | "**Build and verify no compiler errors before proceeding.**", "read the error message carefully" | G1c choreography, padding | Remove or rewrite (`swift.diff`) |
| M10 | `swiftui-view-refactor/SKILL.md:202` | "split it aggressively" | G1a | Rewrite to "split it" (`swift.diff`) |
| M11 | `ui-ux-pro-max/SKILL.md:127` | "exactly as it was before (no behavior change)" | G1d migration-relative | Rewrite (`design.diff`) |
| M12 | `watchos/SKILL.md:166` vs :63-65 | "// Use NavigationStack (watchOS 9+)" | G1c duplicated rules disagree | Rewrite (`design.diff`) |
| M13 | `macos-design-guidelines/SKILL.md:545` | `.cornerRadius(6)` | G2 contradiction (`swiftui-pro`) | Rewrite (`design.diff`) |
| M14 | `mobile-android-design/SKILL.md:21-23`, plus three unlinked references | "Moved to `references/details.md` to fit Codex's 8 KB …" | G2 history narrative | Rewrite as a References list (`android.diff`) |
| M15 | `android-gradle-build-logic`, `android-ci-cd-release-playstore`: Workflow and Done checklist | "Apply the smallest change that improves correctness…", "local heroics" | G1c generic template, coaching | Remove (`android.diff`) |
| M16 | `android-gradle-build-logic:3`, `android-ci-cd-release-playstore:3`, `apple-appstore-reviewer:3` | Descriptions with no use-when clause | G3 under-described trigger | Rewrite the descriptions (`android.diff`) |
| M17 | `apple-appstore-reviewer/SKILL.md:306-313` | "What You Should Do First When Run 1. … 4." | G1c second script | Remove (`android.diff`) |
| M18 | `android-clean-architecture/SKILL.md:48` | "**Critical**: `domain` must NEVER depend…" | G1a | Rewrite with the reason (`android.diff`) |

### Flags (no edit proposed)

- **Third-party skills against the global rules.** A fix would mean patching third-party skills because of a file outside the repo, so the owner decides (pending task 7):
  - `debug-generated-project`: `cd` at :40, 69, 97, 103, 141; `mktemp -d` at :39, 67; `find` at :193; opens a PR at :106.
  - `swiftui-ui-patterns:15`: `rg`.
  - `swiftui-expert-skill:57,60`: `/tmp/stop-trace`.
- **`~/.claude/CLAUDE.md`, "Avoiding permission prompts":** recommends the `Grep`/`Glob` tools, which a session doesn't always have. The repo can't verify this. Low.
- **`axe` (vendored upstream):**
  - :84 "Every command includes `--udid`" contradicts :8.
  - Trigger-phrase list in the description (Low).
  - Step headings over reference material (Low).
- **Low, idiom only or unverifiable:**
  - Codex `$skill` syntax, including `$skill-creator` (`tkr-skill-writer:175`; `skill-creator` exists as a claude.ai-synced skill).
  - Duplicated Quick Start and Workflow lists in the visionOS skills (they agree).
  - `mise:10`: a maintainer note.
  - `cupertino`: "tell the user what you tried" is stated three times.
  - `formatting-build-output:126`: the plugin-hook line.
  - `xcode-build-orchestrator`: "agent mode".
  - Body "When to Use" sections that repeat the descriptions.
  - `apple-appstore-reviewer`: the no-edit rule is stated three times.
  - `protocol-reverse-engineering`: `ssl.*` filter names, and nested fences that break rendering.
  - `compose-multiplatform-patterns:201`: Accompanist.
  - `apple-hig-designer`: dated HIG facts (Clarity/Deference/Depth, the icon size list).

### Clean

- **Always-loaded files:** `AGENTS.md`, `~/.claude/CLAUDE.md` (apart from the low flag), `RTK.md`.
- **Skills:** replay, mise, the visionos-agents router, arkit-hand-tracking-provider, arkit-reference-tracking-providers, arkit-spatial-tracking-providers, realitykit-ecs-systems, shadergraph-editor, swiftui-chart3d-developer, usd-editor, visionos-immersive-media-developer, visionos-widgetkit-developer, visionos-design-guidelines, ios-simulator, kotlin-coroutines-flows, xcode-build-fixer, swift-concurrency, ios-accessibility, swift-concurrency-pro, using-tuist-generated-projects, swiftui-performance-audit, swiftdata-pro, swift-testing-pro, spm-build-analysis, swiftui-liquid-glass, xcode-compilation-analyzer, xcode-build-benchmark, xcode-project-analyzer.

## The diffs

| File | Hunks | Applies to |
|---|---|---|
| [`first-party.diff`](prompt-audit/first-party.diff) | 31 | repo sources under `first-party/` (repo-relative headers) |
| [`design.diff`](prompt-audit/design.diff) | 36 | `~/.agents/skills/{ui-ux-pro-max,watchos,apple-hig-designer,macos-design-guidelines}/SKILL.md` |
| [`android.diff`](prompt-audit/android.diff) | 12 | six Android and tooling skills in `~/.agents/skills/` |
| [`swift.diff`](prompt-audit/swift.diff) | 4 | `swiftui-pro`, `swiftui-ui-patterns`, `swiftui-view-refactor` |
| [`user-level.diff`](prompt-audit/user-level.diff) | 2 | `~/.claude/agents/visionos-engineer.md` |

Apply `first-party.diff` from the repo root with `git apply -p0` (its paths have no `a/` prefix). The
diffs were made against the installed copies on 2026-10-08. After a `laiaskills upgrade` of a
source, re-check that its hunks still apply before using them. Mark a finding done here (move it to
*Done*) when its hunks are applied.
