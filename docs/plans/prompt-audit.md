# Prompt audit of the Claude Code configuration

Status: **done 2026-10-08**. The audit looked for instructions that no longer fit the model, the
repo, or each other, using the `/claude-api prompt-audit` method. Every finding with a proposed edit
is fixed. The rest are flags, recorded below for the next audit. Re-run the audit at the next model
release or after a large skill upgrade.

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

The always-loaded files were in good shape. `AGENTS.md` names only paths and tasks that exist, and
the global `CLAUDE.md` and `RTK.md` contain only reasoned constraints. Almost all findings were in
skills:

1. **Instructions that pointed at nothing.**
   - Ten first-party visionOS skills handed off to five skills that exist nowhere (`build-run-debug`, `signing-entitlements`, `telemetry`, `test-triage`, `spatial-preview-developer`). Upstream ships them as part of a larger plugin; this install only takes a subset.
   - `debugging-instruments` and the two Android skills routed to skills that aren't installed.
   - Every `ui-ux-pro-max` command used a plugin-only path (`${CLAUDE_PLUGIN_ROOT}/.claude/skills/…`), so none of them ran.
   - The Android skills told the agent to run upstream-only `examples/` and `scripts/`.
2. **Skills contradicting newer skills.** `apple-hig-designer`, `watchos`, and `macos-design-guidelines` modelled SwiftUI APIs that `swiftui-pro` and `swiftui-expert-skill` call deprecated: `foregroundColor`, `cornerRadius`, `tabItem`, `PreviewProvider`, `sizeCategory`, `.navigationBarTrailing`. The model copies examples.
3. **Third-party skills against the global rules.** They told the agent to `cd`, use `/tmp` or `mktemp`, call `find`/`rg`, or open pull requests, which push.

| Group | Findings |
|---|---|
| Group 1, dated prompt text | 12 |
| Group 2, brittle configuration | 25, plus 12 flags |
| Group 3, trigger descriptions | 3 |
| Group 4, request config | not applicable (no file builds API requests) |

## Done

All on 2026-10-08.

| What | Where |
|---|---|
| Audit of 64 skills, the global config, and the subagent | this file |
| First-party fixes: findings H1, H7, M2–M7. Includes a placeholder link in the `tkr-skill-writer` template, which the validator rejected. Plugins: `visionos-agents` 0.1.1, `cupertino` 0.2.1, `ios-simulator-ui-flow` 0.3.2 | `485f425` |
| Third-party fixes: findings H2–H6, H8–H11, M8–M18, as 13 patches, one commit each | `7fa1c02`..`c8bb1f5`, `patches/<skill>/` |
| Apple Watch touch target checked against the HIG with cupertino (`hig://general/accessibility`, Mobility; crawled 2026-06-21): default 44x44 pt, minimum 28x28 pt. Both skills were wrong (">44pt", "minimum 38pt"); both now say so | patches for `watchos`, `apple-hig-designer` |
| Third-party skills made to follow the global rules: `debug-generated-project` (project `tmp/` instead of `mktemp`, absolute paths and `--package-path` instead of `cd`, `ls -t` instead of `find`, PRs prepared locally for the owner to open), `swiftui-ui-patterns` (the Grep tool instead of `rg`), `swiftui-expert-skill` (trace stop-file in the project `tmp/`) | `cfebadf`, `cb608ae`, `e08a77d` |
| `visionos-engineer` subagent (M1): the scripted restate/inspect/plan/implement steps removed; the review, build, and simulator flow kept | `~/.claude/agents/` (outside the repo) |
| `update-swiftui-apis` removed. It is a maintainer-only skill from `AvdLee/SwiftUI-Agent-Skill` that edits that repo's own files, needs the Sosumi MCP, and opens PRs. It came in with the 2026-10-04 migration | `1520dc8` |
| Rule to quote long `description` values dropped from `AGENTS.md`. It guarded against Commander's YAML parser, and Commander is deleted. The memory note was rewritten as retired | `235e6d7` |
| `ios-simulator-ui-flow` compared with [ios-build-verify](https://github.com/vermont42/ios-build-verify), the skill its verification approach draws on. Added a *Credits* section (MIT, Josh Adams), so M4 could drop the "Patterns Borrowed" section without losing the attribution. Also added a troubleshooting entry for AXe's post-boot accessibility-bridge lag: an empty tree or a "fullscreen dialog" error for 10–25 s after `simctl boot` | `5e1df6a` |
| When to commit: the global `CLAUDE.md` now says to commit locally when a task finishes, without asking. The project memory note that said the same was deleted | `~/.claude/CLAUDE.md` |
| `laiaskills` runtime refusals (`--yes` needed, not in `skills.json`, not checked out, patches that no longer apply) are printed as `Error: …` alone. As `ValidationError`s they were followed by the root command's usage, which read as a typing mistake and, in a piped run, could be all that was visible | `03673c6` |
| The proposed diffs, once applied, were removed from the repo and its unpushed history. The commits and `patches/` are the record | — |

## Findings

Every finding below with an action is fixed (see *Done*). Line numbers are from before the fixes.

### High confidence

| # | Location | Evidence | Pattern | Why | Action |
|---|---|---|---|---|---|
| H1 | `first-party/visionos-agents/skills/`: `arkit-camera-access-providers:40-41`, `arkit-visionos-developer:18-19`, `coding-standards-enforcer:49-52`, `realitykit-visionos-developer:3,32,38,57`, `shareplay-developer:45-50`, `spatial-app-architecture:40,52-53,72`, `spatial-swiftui-developer:19,61-62`, `usdkit-runtime-developer:21` | "use `$signing-entitlements` or `$build-run-debug`", "Switch to `telemetry`", "`spatial-preview-developer`" | G2 volatile specifics | The five target skills exist nowhere: not in the repo, upstream, `~/.agents/skills`, or `skills.json` | Rewritten as plain guidance |
| H2 | `ui-ux-pro-max/SKILL.md:39,42,78…186` | `python "${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/scripts/search.py"` | G2 | The path only exists in a plugin install; this copy has `scripts/search.py` | Rewritten to `<skill-dir>/scripts/search.py` |
| H3 | `ui-ux-pro-max/SKILL.md:45` | "see README for install instructions" | G2 | The skill folder has no README | Rewritten |
| H4 | `android-gradle-build-logic/SKILL.md:42-53,27,57`, `android-ci-cd-release-playstore/SKILL.md:42-53,27,57` | "`cd examples/orbittasks-compose && ./gradlew …`", "`python3 scripts/eval_triggers.py`" | G2 | Upstream-only maintainer files; the install has only `scripts/run_examples.sh` | Removed or rewritten |
| H5 | `android-gradle-build-logic:19-21`, `android-ci-cd-release-playstore:19-21` | "`android-modernization-upgrade`", "`android-security-best-practices`" | G2 | The hand-off targets aren't installed | Rewritten |
| H6 | `debugging-instruments/SKILL.md:3,8-9,160-161` | "use ios-memgraph-analysis … ios-ettrace-performance", "`metrickit` skill" | G2 | The description routed requests to skills that aren't installed | Rewritten (installing those three skills was the alternative) |
| H7 | `first-party/visionos-agents/skills/tkr-skill-writer/SKILL.md:31-34,60,79-111,160-161` | "Description and Goals / What This Skill Should Do / …", "`system.md`" | G2 | No skill in the plugin uses that layout | Rewritten to the layout the plugin uses |
| H8 | `watchos/SKILL.md:263-290` | `import ClockKit` … `CLKComplicationDataSource` | G2 drift | The skill's own `complications.md` says ClockKit was removed in watchOS 11 | Rewritten as a pointer to WidgetKit |
| H9 | `watchos/SKILL.md:99-102` | `@Environment(\.sizeCategory)` | G2 contradiction | `swiftui-expert-skill` `latest-apis.md:35` says to use `dynamicTypeSize` | Rewritten |
| H10 | `apple-hig-designer/SKILL.md` (15× `foregroundColor`, :110, :130-145, :347, :679-690, :835) | `.foregroundColor(`, `.navigationBarTrailing`, `.tabItem`, `.cornerRadius(12)`, `PreviewProvider`, `UIImpactFeedbackGenerator` | G2 contradiction, G1c example over-indexing | `swiftui-pro` `references/api.md` and `views.md` call each of these deprecated | Rewritten, API by API |
| H11 | `apple-hig-designer/SKILL.md:932`, `watchos/SKILL.md:36` | ">44pt", "minimum 38pt" | G2 contradiction | Both wrong. HIG: default 44x44 pt, minimum 28x28 pt | Both rewritten |

### Medium confidence

| # | Location | Evidence | Pattern | Action |
|---|---|---|---|---|
| M1 | `~/.claude/agents/visionos-engineer.md:48-53,72` | "1. **Restate** … 2. **Inspect** … 3. **Plan** … 4. **Implement** in small, verifiable steps." | G1b plan-before-acting, G1c choreography | Steps 1–4 and "A brief plan" removed; the review, build, and simulator flow kept |
| M2 | `first-party/cupertino/skills/cupertino/SKILL.md:17` | "**the API doesn't exist**: you hallucinated it" | G1a pressure; G2 contradiction with :38-44, :218 | Rewritten: no hit means unverified; check freshness |
| M3 | `cupertino/SKILL.md:221-231` | "Full LLM verify pass \| 1.5–2× baseline" | G1c strategy coaching | Removed |
| M4 | `first-party/ios-simulator-ui-flow/skills/ios-simulator-ui-flow/SKILL.md:321-332` | "Patterns Borrowed From ios-build-verify" | G2 history narrative, G1c repetition | Removed; the credit lives in *Credits* |
| M5 | `ios-simulator-ui-flow/SKILL.md:249,341` | "On Xcode 27 Beta 3, `axe drag` acknowledged …" | G2 history, recency trap | Rewritten to the lasting rule |
| M6 | `ios-simulator-ui-flow/SKILL.md:219,304,355` | "handled better in AXe `v1.8.0`", "old `swipe --from/--to` forms" | G1d migration-relative | Rewritten or removed |
| M7 | `realitykit-animation-physics:56-57`, `realitykit-audio-spatial:48-49`, `realitykit-rendering-materials:54-55`, `usdkit-runtime-developer:47-48`, `arkit-rendering-context-providers:50`, `spatial-swiftui-developer:65-68` | "Treat visionOS 27 … additions as beta API", "New in 27" | G2 time-sensitive, G1d | Rewritten as re-check notes |
| M8 | `swiftui-pro/SKILL.md:29` | "iOS 26 exists, and is the default deployment target" | G1d knowledge-cutoff patch, G2 stale | Rewritten |
| M9 | `swiftui-ui-patterns/SKILL.md:78,81` | "**Build and verify no compiler errors before proceeding.**", "read the error message carefully" | G1c choreography, padding | Removed or rewritten (this also dropped its list of common compile errors) |
| M10 | `swiftui-view-refactor/SKILL.md:202` | "split it aggressively" | G1a | Rewritten to "split it" |
| M11 | `ui-ux-pro-max/SKILL.md:127` | "exactly as it was before (no behavior change)" | G1d migration-relative | Rewritten |
| M12 | `watchos/SKILL.md:166` vs :63-65 | "// Use NavigationStack (watchOS 9+)" | G1c duplicated rules disagree | Rewritten |
| M13 | `macos-design-guidelines/SKILL.md:545` | `.cornerRadius(6)` | G2 contradiction (`swiftui-pro`) | Rewritten |
| M14 | `mobile-android-design/SKILL.md:21-23`, plus three unlinked references | "Moved to `references/details.md` to fit Codex's 8 KB …" | G2 history narrative | Rewritten as a References list |
| M15 | `android-gradle-build-logic`, `android-ci-cd-release-playstore`: Workflow and Done checklist | "Apply the smallest change that improves correctness…", "local heroics" | G1c generic template, coaching | Removed |
| M16 | `android-gradle-build-logic:3`, `android-ci-cd-release-playstore:3`, `apple-appstore-reviewer:3` | Descriptions with no use-when clause | G3 under-described trigger | Descriptions rewritten |
| M17 | `apple-appstore-reviewer/SKILL.md:306-313` | "What You Should Do First When Run 1. … 4." | G1c second script | Removed |
| M18 | `android-clean-architecture/SKILL.md:48` | "**Critical**: `domain` must NEVER depend…" | G1a | Rewritten with the reason |

### Flags (no edit; for the next audit)

- **Third-party skills against the global rules:** fixed on the owner's decision (see *Done*).
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
