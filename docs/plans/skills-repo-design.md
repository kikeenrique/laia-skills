# Skills repo and `laiaskills` — design

Status: **draft**, nothing implemented yet. Last updated 2026-10-03.

This repo becomes the single place where every agent skill — the ones authored here and the third-party
ones consumed — is pinned, reviewed, and installed. A small Swift CLI, `laiaskills`, does the mechanics.

## 1. Why

Skills come from many repos and are installed into several agent directories. Typical skill managers
install **untracked copies** of a skill, which causes three recurring problems:

- **Silent staleness.** A copy does not change when its source does. Update checks, where they exist,
  often cover only some install sources, so outdated skills go unnoticed.
- **Drift and debris.** Removing or replacing a skill can leave dangling symlinks and stale metadata
  behind, and the same skill can diverge across agent directories.
- **No review trail.** Updates overwrite files in place; there is no diff to review and no history to
  roll back to.

The design keeps copies but **tracks** them: sources are git submodules pinned at exact commits, each
installed copy records the pin it came from, so both "upstream is newer than the pin" and "the copy is
behind the pin" are detectable, and git history is the audit trail.

## 2. Goals and non-goals

Goals:

- One repo pins every skill source at an exact commit; upgrades are reviewed diffs and commits.
- `check` answers "what is outdated?" for third-party sources **and** for first-party plugins' `upstream/`
  pins (the manual re-verify-and-bump chore in `AGENTS.md`).
- Installs are independent of the repo: copies in `~/.agents/skills`, so the repo can be moved,
  re-cloned, or switched to another branch without affecting any agent.
- Installed copies never drift silently: every copy is traceable to its pin, and `check`/`sync` close
  the gap.
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
│   ├── laiaskills/                    Swift package (Noora UI)
│   ├── scripts/validate_skills.rb     moved from scripts/
│   └── config/
│       ├── agents.json                hub + mirror agent dirs (tool behaviour)
│       ├── recheck.json               AI agent command used to re-check first-party skills
│       ├── prompts/recheck.md         prompt template for that re-check
│       └── schemas/                   JSON Schemas for the config files
├── docs/
│   └── plans/                         committed plans and design docs (this file)
├── skills.json                       manifest: which skills come from which source
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

### 5.1 `skills.json` (root, data)

```json
{
  "$schema": "./tools/config/schemas/skills.schema.json",
  "skills": {
    "swiftui-pro": { "source": "third-party/twostraws__SwiftUI-Agent-Skill", "path": "swiftui-pro" },
    "xcode-build-fixer": { "source": "third-party/AvdLee__Xcode-Build-Optimization-Agent-Skill" },
    "axe": { "source": "first-party/ios-simulator-ui-flow/upstream" },
    "mise": { "source": "first-party" },
    "watchos": { "source": "third-party/rshankras__claude-code-apple-skills" }
  }
}
```

- **Sources live in `.gitmodules`, not here.** `url`, `branch` (what `check` compares against; default:
  the remote's default branch), and `shallow` are native submodule settings, so `skills.json` only maps
  each skill to a submodule path. One source of truth per fact.
- **The commit is the pin, versions when available.** The submodule commit recorded in this repo is the
  installed version; there is no version field. When the upstream publishes release tags (semver), the
  pin is the commit of a tag and `list`/`show` display that tag; `check` reports newer tags and
  `upgrade` moves to the newest one. Without tags, `check` compares against the tracked branch head.
  First-party `upstream/` pins follow the same rule (already the `AGENTS.md` policy).
- `first-party` resolves to `first-party/*/skills/<name>`. A source may also be an existing first-party
  `upstream/` pin, so no duplicate submodule (AXe ships its skill inside `cameroncooke/AXe`).
- `first-party` resolves to `first-party/*/skills/<name>`; `first-party:<path>` points at a pin that
  already exists, so no duplicate submodule (AXe ships its skill inside `cameroncooke/AXe`).
- **Skill identity = source + frontmatter `name`**, never the path. `path` is optional and exists only
  to settle ambiguity (e.g. twostraws repos contain both `swiftui-pro/` and a nested
  `swiftui-pro/skills/swiftui-pro/`).

### 5.2 `tools/config/agents.json` (tool behaviour)

```json
{
  "$schema": "./schemas/agents.schema.json",
  "hub": {
    "path": "~/.agents/skills",
    "description": "Only real install target; read natively by Codex, Gemini CLI, Copilot, OpenCode, Amp"
  },
  "mirrors": {
    "claude": { "path": "~/.claude/skills", "description": "Entries link to the hub" }
  }
}
```

Mistral Vibe (`~/.vibe/skills`) would be one more `mirrors` entry when needed.

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

- **Copy into the hub, link the mirrors:**

  ```
  <repo> pinned commit ──copy──▶ ~/.agents/skills/<name>/  ◀── ~/.claude/skills/<name>  (symlink)
                                        (hub, real folder)          (mirror)
  ```

  The repo is only needed to install, sync, or upgrade. Agents never read from it, so it can be moved,
  re-cloned, or left on any branch.
- **Copies come from the commit, not the checkout.** Files are exported from git at the pinned commit
  (`git archive <commit> <path>`), so a dirty submodule or half-edited first-party skill is never
  installed by accident. `install --working-tree <skill>` copies uncommitted first-party edits on
  purpose, for testing.
- **Atomic replace.** Export into a staging folder under the hub, then swap with a rename; the previous
  copy goes to `~/.agents/.laiaskills/backups/`. A failed install never leaves a half-written skill.
- **Install state** lives in `~/.agents/.laiaskills.json` (machine-local, never in the repo, next to
  the `npx skills` lock). Per skill: source submodule, skill path, commit, tag (if any), the git tree id
  of the skill folder at that commit, a per-file blob-hash manifest, and the install time.
- **Three-way status per skill**, computed by `check`/`list`:

  | State | Meaning | Fix |
  |---|---|---|
  | up to date | copy = pin = newest upstream | — |
  | **pin outdated** | upstream has a newer tag/commit than the pin | `upgrade` |
  | **not synced** | copy ≠ pin (e.g. pin moved after a `git pull` or `upgrade` on another machine) | `sync` |
  | **modified** | copy's files differ from its recorded manifest (edited in place) | `sync --force` (shows the diff first) |

  File hashes are git blob ids (`git hash-object`), so they compare directly with the pinned commit's
  tree, offline.
- Global scope only. No workspace/project-level installs.
- **Ownership**: `laiaskills` only creates, replaces, or removes hub folders recorded in its state file,
  and mirror links that point at those folders. Anything else in an agent dir (other folders, `npx skills`
  installs, other managers, links elsewhere) is foreign: reported by `doctor`, never touched.

### 5.5 Commands

Every command is fully usable non-interactively (flags, `--json`, meaningful exit codes). Noora only
renders and prompts when attached to a TTY.

| Command | Does |
|---|---|
| `laiaskills list [filter]` | Skills in `skills.json`: source, pinned commit, install state per agent, "outdated" marker from the last fetch (offline). `--all` adds foreign skills found in agent dirs |
| `laiaskills show <skill>` | Detail view: description, source, agents, every install location, rendered `SKILL.md`. `--open` reveals it in the file manager (Finder or `xdg-open`) |
| `laiaskills sources` | Configured sources: skills available vs installed, pinned commit, tracked branch |
| `laiaskills check` | `git fetch --tags` each source (third-party and first-party `upstream/`). Tagged sources: report newer release tags. Untagged: report commits on the tracked branch that touch each skill's path. Also reports copies that are **not synced** or **modified** (offline). `--exit-code` → 1 when anything needs action |
| `laiaskills sync [skill…]` | Make every installed copy match its pin: install missing, re-copy not-synced, remove skills dropped from `skills.json`. Refuses to overwrite **modified** copies without `--force`. Run after `git pull` |
| `laiaskills upgrade [skill\|source…]` | Target = newest release tag, or branch head when untagged (`--to <tag\|commit>` overrides). Show `git log` + `diff --stat` for the skill path, confirm (Noora yes/no, or `--yes`), move the submodule pointer, re-resolve paths, re-copy into the hub, `git add`. For a first-party `upstream/` pin it then runs the automated re-check (5.6; `--no-agent` skips it). Staged only; `--commit` also runs `commit`. Interactive runs end with "Commit now?" (default no) |
| `laiaskills commit` | Commit the staged changes with generated Conventional Commit messages: third-party bumps in one `chore(third-party): bump swiftui-pro to v1.3.0, axe to 4f2c1a9` commit (one body line per skill, old → new); each re-checked first-party plugin in its own `docs(<plugin>): refresh guidance for <upstream> <tag>` commit, with the plugin `version` bumped in `plugin.json` and `marketplace.json` (patch by default; asks for minor/major/breaking). Shows the messages for confirmation (or `--yes`). **Never pushes** |
| `laiaskills add <owner/repo[@skill] \| url> [--skill name…]` | Add the submodule (+ `shallow`), list its skills (Noora multiple-choice), write `skills.json` entries |
| `laiaskills install [skill…]` | Copy the skill at its pin into the hub and create mirror links. `--working-tree` copies uncommitted first-party edits for testing |
| `laiaskills remove <skill>` | Move the hub copy to the backups folder, remove mirror links and the `skills.json` entry; drop the submodule when no skill uses it |
| `laiaskills doctor` | Broken mirror links, mirror entries that bypass the hub, state-file entries whose hub folder is missing, foreign entries shadowing managed names, stale `~/.agents/.skill-lock.json` entries, sources with no skills, unresolvable or ambiguous names |
| `laiaskills import` | One-off migration from `~/.agents/.skill-lock.json` (GitHub entries directly; local-path entries via the source clone's `origin` URL); emits `skills.json` + `git submodule add` plan for review |
| `laiaskills browse <source>` | Optional (v2): Noora picker over a source's skills, preview `SKILL.md` |

### 5.6 Automated re-check of first-party skills

`AGENTS.md` requires that a first-party plugin's `upstream/` pin only moves together with a re-check of
the skill against the new release. `upgrade` automates that re-check by running an AI agent CLI
non-interactively; the tool keeps control of git, validation, and committing.

1. **Move the pin** to the new release tag and stage it.
2. **Run the agent** from `tools/config/recheck.json` with the prompt template
   `tools/config/prompts/recheck.md`, filled with the plugin, old and new tag, and paths. The template
   asks the agent to re-check the skill against the new upstream release, update it where needed,
   follow `AGENTS.md`, and not touch git.
3. **Guard the result:**
   - Only files under `first-party/<plugin>/skills/` may change; anything else is reverted and reported.
   - `tools/scripts/validate_skills.rb` must pass. If it fails, the run fails and the changes stay
     staged for inspection, uncommitted.
   - If the agent changed nothing, the commit body records "re-checked against `<tag>`, no changes
     needed".
4. **Summarize and stage**: changed files and a diff summary.
5. **`commit`** (separately, or `--commit`) bumps the plugin `version` and writes the commit.

```json
{
  "$schema": "./schemas/recheck.schema.json",
  "agent": "claude",
  "commands": {
    "claude": ["claude", "-p", "{prompt}", "--permission-mode", "acceptEdits"],
    "codex": ["codex", "exec", "{prompt}"]
  },
  "timeoutMinutes": 30
}
```

- The agent command lives in config, so a changed CLI flag is a config edit, not a code change. Exact
  flags are confirmed against each CLI's `--help` at implementation time.
- `--no-agent` skips step 2 when updating the skill by hand.
- Runs locally only: it needs the agent CLI installed and signed in, so not in CI.
- No scanning for old version strings and no hand-off brief: the agent re-checks the whole skill.

### 5.7 Technology

- Swift 6.4+, SwiftPM package at `tools/laiaskills/`. **Runs on Linux and macOS 13+.** The minimum
  matches CI: Ubuntu 26.04 only has Swift builds from 6.4 on, so CI and the minimum moved together.
- Cross-platform rules (Linux has no AppKit, CryptoKit, or Trash API):
  - Old copies go to `~/.agents/.laiaskills/backups/<name>-<timestamp>/` on both systems, never to the
    system Trash.
  - File hashes come from `git hash-object`; no CryptoKit (git is already required).
  - `show --open` uses `open -R` on macOS and `xdg-open` on Linux.
  - Only Foundation APIs available in swift-corelibs-foundation; `HOME` read from the environment.
- Noora supports Linux (its own CI builds and tests on Ubuntu).
- Dependencies: `apple/swift-argument-parser`, `tuist/Noora` pinned `.upToNextMinor` (still 0.x:
  0.57.3 on 2026-09-23). Configs are JSON read with Foundation's `JSONDecoder`: no parser dependency.
- JSON Schemas in `tools/config/schemas/` give editor completion and validation (JSON has no comments,
  so notes go in `description` fields). The validator runs matching structural checks in plain Ruby
  (no JSON Schema gem), and `laiaskills` rejects configs it cannot decode.
- Shell out to `git`; no libgit2, no GitHub API → no tokens, no rate limits, Codeberg works.
- All Noora calls behind one `UI` protocol so a breaking Noora minor touches one file.
- Run via a mise task in this repo (`mise run laiaskills check`), no install or notarization needed.
- Tests: fixture repos built in a temp dir under `tmp/` (moved, ambiguous, removed skills; foreign
  entries in agent dirs).
- CI: a job on `ubuntu-26.04` in `.github/workflows/ci.yml` installs Swift 6.4 (`SwiftyLab/setup-swift`)
  and runs `swift build` + `swift test` in `tools/laiaskills/`, with the SwiftPM build folder cached
  under a key that includes the image and Swift version. Locally, `mise run laiaskills:test-linux` runs
  the same tests in the `swift:6.4.0-resolute` (Ubuntu 26.04) Docker image.

## 6. Maintenance profile

| Driver | Frequency | Mitigation |
|---|---|---|
| Skills move/renamed inside source repos | High | Identity by name, re-discovered on every run |
| Source repo layouts vary | Medium | Generic `SKILL.md` scan, optional `path` |
| Agent directory conventions change | Medium | `tools/config/agents.json` |
| Noora 0.x breaking minors | Medium | `.upToNextMinor` pin, single `UI` layer |
| Upstream repo renamed (e.g. `everything-claude-code` → `affaan-m/ECC`) | Medium | GitHub redirects; `doctor` flags redirected submodule URLs so `.gitmodules` gets the new name |
| Upstream repo deleted | Low | Pinned commit survives locally; fork critical sources |
| Swift toolchain / strict concurrency | Low | Mostly synchronous code, subprocess git |
| AI agent CLI flags or behaviour change (re-check) | Medium | Command in `recheck.json`; result guarded by allowed paths + validator |

Estimate: MVP under ~1k lines of Swift; a few hours per month afterwards.

## 7. Phases

0. **Restructure** (section 4), one `refactor!` commit, validator green. **Done.**
1. **Read-only MVP**: `list`, `check` (including first-party upstream tags), `doctor`, plus the Linux CI
   job from day one. **Done.** Notes from implementing it:
   - `skills.json` lists the 27 first-party skills plus `axe`, taken from the existing
     `first-party/ios-simulator-ui-flow/upstream` pin. AXe ships two `axe` skills (`Skills/CLI/axe` and
     the copy bundled in `Sources/AXe/Resources/skills/axe`), so `axe` uses `path: "Skills/CLI/axe"`,
     the fuller one with `references/`.
   - When stdout is not a terminal, tables print as plain aligned columns; Noora would otherwise
     truncate cells to 80 columns.
   - `doctor` finds a Claude Code plugin's skills the way Claude Code does: the marketplace entry's
     `skills` list first, then the plugin's `plugin.json`, then its `skills/` folder.
   - Tasks run through a root `mise.toml` (mise's own format, like `.gitmodules` is git's).
2. **Write ops**: `add`, `install`, `sync`, `remove`, `upgrade`, `commit`, `show`, `sources`, `import`,
   and the automated re-check (5.6). **Done.** Notes from implementing it:
   - Install status compares git **tree ids**, not commits, so unrelated commits never mark a skill
     "not synced". Submodule skills install from the pin in the index, so a staged `upgrade` counts.
   - `add`, `remove`, and `upgrade` record what they staged in `.git/laiaskills/pending.json` (inside
     `.git/`, never committed); `commit` turns that into messages and then clears it.
   - Shallow sources read tags and branch heads with `git ls-remote`, so `check`, `add`, and `upgrade`
     never download history or one snapshot per release.
   - `recheck.json` configures Claude Code only (`claude -p … --permission-mode acceptEdits` with a
     restricted `--allowedTools` list). Codex is one more `commands` entry once its flags are verified.
   - An earlier version drained subprocess output on GCD's shared pool, which deadlocked under parallel
     tests; `Shell` now uses dedicated threads.
   - Verified end to end in a throwaway clone with a sandboxed `HOME`: sync of all 28 skills, edit
     detection, `add` of a real GitHub source, `upgrade` of the AXe pin, `remove`, and `commit` (three
     commits, plugin version bumped). The agent re-check itself is covered by tests with a stub agent.
   - That manual run is now automated: `LaiaSkillsCLITests` runs the built binary end to end (sync,
     drift, add, upgrade, remove, commit, import, doctor, and the agent re-check through a stub
     script), offline, on Linux CI as well.
3. **Migration**: import → add submodules → `sync` (replaces previously installed copies with tracked
   ones) → clean up stale lock entries (checklist in section 9).
4. **Optional**: `browse`.

## 8. Decisions

Numbers are kept stable so they can be referred to in discussion.

### Decided

- **(1) Name.** The tool is called `laiaskills`.
- **(2) How skills are installed.** Each skill is *copied* into `~/.agents/skills`. Agents never read
  from this repo, so the repo can be moved or switched to another branch without breaking anything.
- **(3) Agents with their own folder.** Folders such as `~/.claude/skills` contain links pointing to the
  copies in `~/.agents/skills`, the same way `~/.claude/skills` works today.
- **(4) What counts as a version.** A skill's version is the exact commit this repo has pinned. If the
  upstream project publishes releases (tags like `v1.4.2`), we pin to a release and upgrade from release
  to release. If it doesn't, we compare against the latest commit on its main branch.
- **(5) Very large source repos.** Repos that are big compared to the skills we use from them
  (`github/awesome-copilot` 111 MB, `affaan-m/ECC` 53 MB) are downloaded as the latest snapshot only
  (git's "shallow" mode, `shallow = true` in `.gitmodules`). When upgrading one of them, the tool first
  downloads the history it needs to show what changed. All other sources are cloned normally.
- **(6) Committing upgrades.** `upgrade` prepares the change (staged) but does not commit. Committing is
  also done from the tool, not by hand: `laiaskills commit` turns the prepared upgrades into one commit
  with a generated message, and `upgrade --commit` does both in one go. When run interactively, `upgrade`
  ends by asking whether to commit now (default: no). The tool never pushes.
- **(7) Repos that also offer a Claude Code plugin marketplace.** Everything goes through this repo
  (submodule + copy), including the 9 sources that could also be installed with `/plugin install`. One
  place to check and upgrade, for every agent. Those repos must not also be installed with `/plugin`,
  or Claude loads their skills twice; `doctor` flags it when it happens.
- **(12) Config file format.** JSON, with a schema file next to it so editors can autocomplete and the
  validator can catch mistakes.
- **(13) CI and Linux.** The tool must work on **Linux and macOS**. GitHub CI builds and tests it on
  Linux (`ubuntu-26.04`), the cheaper runner, next to the existing skill validator. See 5.7 for what
  that rules out.
- **(14) Licences.** Using third-party skills this way is fine: submodules are only references (a URL
  and a commit), so nothing is redistributed, and copies go to `~/.agents/skills`, not into the repo.
  Rule: never copy third-party files into `first-party/`.
- **(15) Per-project skills.** Not needed. Skills are installed once for the whole machine.
- **(16) Supported agents.** Only `~/.agents/skills` receives real copies. Any other agent gets links
  into it; adding one is a single line in `tools/config/agents.json`.

- **(17) Re-checking first-party skills after an upstream re-pin.** Automated: `upgrade` runs an AI agent
  to re-check and update the skill, then guards the result (allowed paths, validator). No confirmation
  prompt; you review before committing. See 5.6.

### Open questions

None right now. **(8–11)** are one-off migration items, listed in section 9.

## 9. Migration (one-off)

Checklist for moving existing installs under `laiaskills`. Remove this section once phase 3 is done.

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
| affaan-m/ECC | android-clean-architecture, compose-multiplatform-patterns, kotlin-coroutines-flows |
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
| Agent selection | Hub + mirrors in `agents.json` | Covered globally; no per-skill selection (by design) |
| Workspace / global scope | Global only | Not needed (decision 15) |
| Shows installs made by other tools | `list --all`, `doctor` | Covered |
| Online discovery (skills.sh and similar) | — | Out of scope |
| Reads Claude `marketplace.json` | — | Out of scope; `SKILL.md` scan instead, plugins via `/plugin` |
| GUI | Noora CLI | Out of scope |
