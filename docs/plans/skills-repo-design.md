# Skills repo and `skillctl` — design

Status: **draft**, nothing implemented yet. Last updated 2026-10-03.

This repo becomes the single place where every agent skill — the ones authored here and the third-party
ones consumed — is pinned, reviewed, and installed. A small Swift CLI, `skillctl`, does the mechanics.

## 1. Why

Skills come from many repos and are installed into several agent directories. Typical skill managers
install **copies** of a skill, which causes three recurring problems:

- **Silent staleness.** A copy does not change when its source does. Update checks, where they exist,
  often cover only some install sources, so outdated skills go unnoticed.
- **Drift and debris.** Removing or replacing a skill can leave dangling symlinks and stale metadata
  behind, and the same skill can diverge across agent directories.
- **No review trail.** Updates overwrite files in place; there is no diff to review and no history to
  roll back to.

The design removes copies: sources are git submodules pinned at exact commits, installs are symlinks
into them, and git history is the audit trail.

## 2. Goals and non-goals

Goals:

- One repo pins every skill source at an exact commit; upgrades are reviewed diffs and commits.
- `check` answers "what is outdated?" for third-party sources **and** for first-party plugins' `upstream/`
  pins (the manual re-verify-and-bump chore in `AGENTS.md`).
- Installed state cannot drift from the repo: agent skill dirs hold symlinks into the working tree.
- Low maintenance: depend on `git` and a stable `SKILL.md` convention, not on catalogs or APIs.

Non-goals (v1):

- Online catalogs (skills.sh, ClawHub). Their APIs are undocumented and scrape-prone.
- Managing Claude Code plugins/marketplaces — leave that to `/plugin`.
- MCP servers, GUI, menu bar, daemon.
- Distribution to other users. The tool runs from this repo only.

## 3. Folder tree

```
laia-skills/
├── .claude-plugin/marketplace.json   Claude Code marketplace — must stay at the root
├── first-party/                      skills authored here and published
│   ├── mise/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── skills/mise/SKILL.md       (+ references/, assets/, agents/openai.yaml)
│   │   └── upstream/                  submodule: the project the skill documents (jdx/mise)
│   ├── replay/
│   ├── ios-simulator-ui-flow/
│   ├── cupertino/
│   └── visionos-agents/
├── third-party/                      external skill repos consumed, never published
│   └── <owner>__<repo>/               one submodule per source repo
├── tools/
│   ├── skillctl/                      Swift package (Noora UI)
│   ├── scripts/validate_skills.rb     moved from scripts/
│   └── config/agents.toml             agent install targets (tool behaviour)
├── docs/
│   └── plans/                         committed plans and design docs (this file)
├── skills.toml                       manifest: which skills, from which source, to which agents
├── .gitmodules
├── AGENTS.md
├── README.md
└── tmp/                              untracked scratch (never in .gitignore)
```

Naming rules:

- Domains are named by **ownership**, not packaging. A skill ships as a Claude plugin, a Codex skill
  (`agents/openai.yaml`), or a plain folder; `first-party/` and `third-party/` stay true for all three.
- `first-party/<name>/skills/<name>/` repeats the name by design: the plugin wrapper and its main skill
  must match (validator rule).
- `third-party/<owner>__<repo>` uses the canonical GitHub casing; sources are de-duplicated
  case-insensitively (`Dimillian/Skills` = `dimillian/skills`).
- First-party `upstream/` pins stay with their plugin. They are documented projects, not consumed skills.

## 4. Repo restructure (phase 0)

| File | Change |
|---|---|
| plugin dirs | `git mv <plugin> first-party/<plugin>` ×5 (moves submodules too) |
| `.gitmodules` | Rewritten by `git mv`: `first-party/<plugin>/upstream` |
| `.claude-plugin/marketplace.json` | `skills` paths → `./first-party/<plugin>/skills/<skill>`; install ids unchanged |
| `scripts/validate_skills.rb` | Move to `tools/scripts/`; fix `ROOT`; globs `ROOT/*/…` → `ROOT/first-party/*/…` |
| `.github/workflows/ci.yml` | `ruby tools/scripts/validate_skills.rb` |
| `README.md`, `AGENTS.md` | Links, submodule table, "each top-level dir is a plugin" rule, re-pin and add-plugin steps |
| `plugin.json` ×5 | No change (paths are plugin-relative) |

Commit as `refactor!:` with a `BREAKING CHANGE:` footer — `/plugin install <name>@laia-skills` keeps
working, but deep links and path-based installs (`npx skills add …/mise/skills/mise`) move. No plugin
`version` bumps (content unchanged). Move untracked `downloads/` and `replay-workspace/` into `tmp/`.

## 5. Specs

### 5.1 `skills.toml` (root, data)

```toml
[sources."twostraws/SwiftUI-Agent-Skill"]
url = "https://github.com/twostraws/SwiftUI-Agent-Skill"
branch = "main"                        # tracked branch; the submodule commit is the version
shallow = true

[sources."AvdLee/Xcode-Build-Optimization-Agent-Skill"]
url = "https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill"
branch = "main"

[skills]
swiftui-pro = { source = "twostraws/SwiftUI-Agent-Skill", path = "swiftui-pro" }  # path only to break ties
xcode-build-fixer = { source = "AvdLee/Xcode-Build-Optimization-Agent-Skill" }
axe = { source = "first-party:ios-simulator-ui-flow/upstream" }   # reuse an existing upstream pin
mise = { source = "first-party" }
watchos = { source = "rshankras/claude-code-apple-skills" }
```

- A source maps 1:1 to a submodule at `third-party/<owner>__<repo>`.
- `first-party` resolves to `first-party/*/skills/<name>`; `first-party:<path>` points at a pin that
  already exists, so no duplicate submodule (AXe ships its skill inside `cameroncooke/AXe`).
- **Skill identity = source + frontmatter `name`**, never the path. `path` is optional and exists only
  to settle ambiguity (e.g. twostraws repos contain both `swiftui-pro/` and a nested
  `swiftui-pro/skills/swiftui-pro/`).

### 5.2 `tools/config/agents.toml` (tool behaviour)

```toml
[hub]
path = "~/.agents/skills"              # the only real install target; read natively by Codex,
                                       # Gemini CLI, Copilot, OpenCode, Amp, …

[mirrors.claude]
path = "~/.claude/skills"              # entries link to the hub, as today

# [mirrors.vibe]
# path = "~/.vibe/skills"              # enable when used
```

- **Only `~/.agents/skills` is supported as a target.** Agents that read it natively need nothing else.
- An agent with its own directory is a **mirror**: each entry is a relative symlink to the hub entry
  (`~/.claude/skills/<name>` → `../../.agents/skills/<name>`), the layout `~/.claude/skills` already uses.
- Every managed skill goes to the hub and to every mirror; no per-skill agent selection in v1.
- Adding an agent or following a changed agent directory is a config edit, not a code change.

### 5.3 Discovery

- Scan the source tree for `SKILL.md`, parse frontmatter `name`.
- Skip `.git/`, `node_modules/`, `upstream/` (inside first-party), and `evals/`/`tests/` fixtures.
- 0 matches → error "skill moved or removed", listing nearby names. >1 match → error listing candidate
  paths; the user sets `path`.
- Re-run on every `check`/`upgrade`, so a skill that moves inside its repo is found again
  (precedent: `update-swiftui-apis` moved to `.agents/skills/`).

### 5.4 Install model

- Two hops, one source of truth:

  ```
  ~/.claude/skills/<name>  →  ~/.agents/skills/<name>  →  <repo>/third-party/<owner>__<repo>/<path>
        (mirror)                    (hub)                    or <repo>/first-party/<plugin>/skills/<name>
  ```

- Installed content always equals the checked-out commit; there is nothing to copy or hash. Upgrading a
  skill only moves the submodule pointer; neither link changes unless the skill moved inside its repo.
- Global scope only. No workspace/project-level installs.
- **Ownership**: `skillctl` only creates, replaces, or removes hub links that resolve into this repo, and
  mirror links that point at a hub entry it owns.
  Anything else in an agent dir (real folders, `npx skills` installs, other managers, links elsewhere) is
  foreign: reported by `doctor`, never touched.
- No lock file of its own: the submodule commits are the lock; symlinks are derived state that
  `install` can always rebuild.

### 5.5 Commands

Every command is fully usable non-interactively (flags, `--json`, meaningful exit codes). Noora only
renders and prompts when attached to a TTY.

| Command | Does |
|---|---|
| `skillctl list [filter]` | Skills in `skills.toml`: source, pinned commit, install state per agent, "outdated" marker from the last fetch (offline). `--all` adds foreign skills found in agent dirs |
| `skillctl show <skill>` | Detail view: description, source, agents, every install location, rendered `SKILL.md`. `--open` reveals in Finder |
| `skillctl sources` | Configured sources: skills available vs installed, pinned commit, tracked branch |
| `skillctl check` | `git fetch` each source; report commits on the tracked branch that touch each skill's path. For `first-party/*/upstream`, report newer release tags. `--exit-code` → 1 when anything is outdated |
| `skillctl upgrade [skill\|source…]` | Show `git log` + `diff --stat` for the skill path, confirm (Noora yes/no, or `--yes`), move the submodule pointer, re-resolve paths, relink, `git add`. `--commit` writes a `chore(third-party): bump …` commit. **Never pushes** |
| `skillctl add <owner/repo[@skill] \| url> [--skill name…]` | Add the submodule (+ `shallow`), list its skills (Noora multiple-choice), write `skills.toml` entries |
| `skillctl install [skill…]` | Create/repair symlinks for the configured agents |
| `skillctl remove <skill>` | Remove our symlinks and the `skills.toml` entry; drop the submodule when no skill uses it |
| `skillctl doctor` | Broken symlinks (hub or mirror), mirror entries that bypass the hub, foreign entries shadowing managed names, stale `~/.agents/.skill-lock.json` entries, sources with no skills, unresolvable or ambiguous names |
| `skillctl import` | One-off migration from `~/.agents/.skill-lock.json` (GitHub entries directly; local-path entries via the source clone's `origin` URL); emits `skills.toml` + `git submodule add` plan for review |
| `skillctl browse <source>` | Optional (v2): Noora picker over a source's skills, preview `SKILL.md` |

### 5.6 Technology

- Swift 6, macOS 13+, SwiftPM package at `tools/skillctl/`.
- Dependencies: `apple/swift-argument-parser`, `tuist/Noora` pinned `.upToNextMinor` (still 0.x:
  0.57.3 on 2026-09-23), Swift TOML parser (to choose).
- Shell out to `git`; no libgit2, no GitHub API → no tokens, no rate limits, Codeberg works.
- All Noora calls behind one `UI` protocol so a breaking Noora minor touches one file.
- Run via a mise task in this repo (`mise run skills:check`), no install or notarization needed.
- Tests: fixture repos built in a temp dir under `tmp/` (moved, ambiguous, removed skills; foreign
  entries in agent dirs).

## 6. Maintenance profile

| Driver | Frequency | Mitigation |
|---|---|---|
| Skills move/renamed inside source repos | High | Identity by name, re-discovered on every run |
| Source repo layouts vary | Medium | Generic `SKILL.md` scan, optional `path` |
| Agent directory conventions change | Medium | `tools/config/agents.toml` |
| Noora 0.x breaking minors | Medium | `.upToNextMinor` pin, single `UI` layer |
| Upstream repo deleted | Low | Pinned commit survives locally; fork critical sources |
| Swift toolchain / strict concurrency | Low | Mostly synchronous code, subprocess git |

Estimate: MVP under ~1k lines of Swift; a few hours per month afterwards.

## 7. Phases

0. **Restructure** (section 4), one `refactor!` commit, validator green.
1. **Read-only MVP**: `list`, `check` (including first-party upstream tags), `doctor`.
2. **Write ops**: `add`, `install`, `remove`, `upgrade`, `import`.
3. **Migration**: import → add submodules → switch agent dirs to symlinks → remove previously installed
   copies and stale lock entries (checklist in section 9).
4. **Optional**: `browse`, CI job building and testing `skillctl`.

## 8. Pending decisions

| # | Decision | Options | Leaning |
|---|---|---|---|
| 1 | Tool name | `skillctl` (already used by `nibzard/skillctl`, `agent-rt/skillctl` on GitHub) vs another | Rename to avoid confusion, or accept since it's never distributed |
| 2 | First-party symlinks target | Live working tree vs a `git worktree` on `main` | Worktree on `main`, so half-done edits are not live everywhere |
| 3 | ~~Claude links~~ | **Decided:** mirrors link to the hub (`~/.agents/skills`), as Claude does today | — |
| 4 | Version tracking for third-party | Branch + pinned commit vs tags | Branch; most skill repos never tag |
| 5 | Large sources (`github/awesome-copilot`, `affaan-m/everything-claude-code`, `wshobson/agents`) | Shallow submodule vs sparse checkout vs fork-and-trim | Shallow first; sparse only if size hurts |
| 6 | Does `upgrade` commit? | Stage only vs `--commit` opt-in vs always | Stage by default, `--commit` opt-in |
| 7 | Repos that publish a Claude marketplace (9 sources) | Submodule here vs `/plugin` | Submodule here, one mechanism; avoid installing both (duplicate skills) |
| 8–11 | Migration specifics | See section 9 | — |
| 12 | TOML parser dependency | Which Swift package | Evaluate in phase 1 |
| 13 | CI for `skillctl` | None vs macOS runner build + test | None until phase 4 |
| 14 | Third-party licenses | Submodules (no redistribution) are enough? | Yes, as long as nothing is copied into `first-party/` |
| 15 | ~~Workspace scope~~ | **Decided:** global only, not needed for now | — |
| 16 | ~~Extra install targets~~ | **Decided:** only `~/.agents/skills` is a target; other agents are mirrors linking into it (Mistral Vibe = one config line when needed) | — |

## 9. Migration (one-off)

Checklist for moving existing installs under `skillctl`. Remove this section once phase 3 is done.

| # | Item | Plan |
|---|---|---|
| 8 | Other skill managers already installed | Keep for discovery only; never let them adopt or replace managed skills |
| 9 | `~/.agents/.skill-lock.json` (`npx skills`) | Prune entries for managed names so other tools stop updating them |
| 10 | Skills with no known source: `android-ci-cd-release-playstore`, `mobile-android-design`, `swiftui-twostraws` | Find a source; drop if none |
| 11 | Replaced or orphaned: `formatting-build-output` (superseded by the `xcsift` plugin), `skill-creator` | Drop the first; re-source `skill-creator` from `anthropics/skills` |

Third-party sources (21 repos; 20 new submodules, since AXe reuses an existing pin):

| Source repo | Skills |
|---|---|
| AvdLee/Xcode-Build-Optimization-Agent-Skill | spm-build-analysis, xcode-build-benchmark, xcode-build-fixer, xcode-build-orchestrator, xcode-compilation-analyzer, xcode-project-analyzer |
| AvdLee/SwiftUI-Agent-Skill | swiftui-expert-skill, update-swiftui-apis (lives under `.agents/skills/`) |
| AvdLee/swift-concurrency-agent-skill | swift-concurrency |
| Dimillian/Skills | swiftui-liquid-glass, swiftui-ui-patterns, swiftui-view-refactor, swiftui-performance-audit |
| twostraws/SwiftUI-Agent-Skill | swiftui-pro |
| twostraws/Swift-Concurrency-Agent-Skill | swift-concurrency-pro |
| twostraws/Swift-Testing-Agent-Skill | swift-testing-pro |
| twostraws/swiftdata-agent-skill | swiftdata-pro |
| dpearson2699/swift-ios-skills | debugging-instruments, ios-simulator |
| tuist/agent-skills | debug-generated-project, using-tuist-generated-projects |
| cameroncooke/AXe | axe (reuse `first-party/ios-simulator-ui-flow/upstream`) |
| dadederk/iOS-Accessibility-Agent-Skill | ios-accessibility |
| ehmo/platform-design-skills | macos-design-guidelines, visionos-design-guidelines |
| rshankras/claude-code-apple-skills | watchos |
| affaan-m/everything-claude-code | android-clean-architecture, compose-multiplatform-patterns, kotlin-coroutines-flows |
| krutikjain/android-agent-skills | android-gradle-build-logic |
| jamesrochabrun/skills | apple-hig-designer |
| github/awesome-copilot | apple-appstore-reviewer |
| nextlevelbuilder/ui-ux-pro-max-skill | ui-ux-pro-max |
| wshobson/agents | protocol-reverse-engineering |
| anthropics/skills | skill-creator |

First-party skills (`mise`, `replay`, `ios-simulator-ui-flow`, `cupertino`, `visionos-agents`) come from
`first-party/` and need no submodule beyond their existing `upstream/` pins.

## 10. Feature coverage

What a typical GUI skill manager offers, and where each feature lands here.

| Feature | Here | Status |
|---|---|---|
| Check for updates | `check` | Covered, across all sources plus first-party `upstream/` pins |
| Update one / update all | `upgrade` | Covered, with diff review and a commit as the record |
| "Update available" badge | `list` outdated marker | Covered |
| Installed list + search | `list [filter]` | Covered |
| Detail: slug, agents, locations | `show` | Covered |
| Instructions (`SKILL.md`) view | `show` | Covered |
| Reveal in Finder | `show --open` | Covered |
| Delete | `remove` | Covered |
| Sources / marketplaces list | `sources` | Covered |
| Per-source grid with Installed / Install | `browse` (v2), `add` picker | Deferred to v2 |
| Install from `owner/repo@skill`, URL, path | `add` | Covered; local paths only for first-party |
| Agent selection | Hub + mirrors in `agents.toml` | Covered globally; no per-skill selection (by design) |
| Workspace / global scope | Global only | Not needed (decision 15) |
| Shows installs made by other tools | `list --all`, `doctor` | Covered |
| Online discovery (skills.sh and similar) | — | Out of scope |
| Reads Claude `marketplace.json` | — | Out of scope; `SKILL.md` scan instead, plugins via `/plugin` |
| GUI | Noora CLI | Out of scope |
