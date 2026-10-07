# Skills repo and `laiaskills` — design

Status: **phases 0–4 done**: the tool is implemented and tested (macOS and Linux CI), every installed
skill (64) is managed by it, third-party skills can carry local patches (5.8), and `browse` and `find`
replace Commander for looking at and discovering skills (5.9). See the [roadmap](#7-roadmap). Last
updated 2026-10-05.

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

- Online catalogs (skills.sh, ClawHub) in the core. Their APIs are undocumented and scrape-prone. Since
  decision 20, `find` is the one optional command that searches skills.sh; nothing else depends on it.
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
├── patches/                          local fixes to third-party skills (5.8)
│   └── <skill>/NNNN-<slug>.patch      applied to the installed copy, in file-name order
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
- **Skill identity = source + frontmatter `name`**, never the path. `path` is optional and exists only
  to settle ambiguity (e.g. twostraws repos contain both `swiftui-pro/` and a nested
  `swiftui-pro/skills/swiftui-pro/`).
- **`skipMirrors`** (optional) lists mirrors from `agents.json` that get no link, e.g.
  `"skipMirrors": ["claude"]` for a skill Claude already gets another way (decision 18). The skill is
  still pinned, checked, upgraded, and copied into the hub; `sync` removes an existing link to it from
  those mirrors and leaves anything else there alone.
- **`claudePlugins`** (optional, top level) lists the Claude Code plugins expected to be installed, as
  `<plugin>@<marketplace>` (today `swift-lsp@claude-plugins-official`). `doctor` reports declared ones
  that are missing and installed ones that aren't declared; `check` reports newer versions in their
  marketplaces. Installing stays with `/plugin`. Leaving the key out turns tracking off.

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
- Every managed skill goes to the hub and to every mirror, unless it opts out of a mirror (decision 18).
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
- **Copies come from the commit, not the checkout.** Files are read from git's object store at the
  pinned commit (`git ls-tree` + `git cat-file`, keeping executable bits and symlinks), so a dirty
  submodule or half-edited first-party skill is never installed by accident. First-party skills install
  from `HEAD`; submodule skills from the pin recorded in the index, so a staged `upgrade` counts. `install --working-tree <skill>` copies uncommitted first-party edits on
  purpose, for testing.
- **One skill per copy.** A Claude plugin manifest (`.claude-plugin/`) and any subfolder holding another
  `SKILL.md` are left out. Some upstreams make a skill folder double as a plugin with a nested copy of
  the skill (`twostraws/SwiftUI-Agent-Skill` since v1.1.0); copied whole, Claude Code loads that copy
  as a second skill (`swiftui-pro:swiftui-pro`). A copy that still holds those files counts as not synced.
- **Atomic replace.** Export into a staging folder under the hub, then swap with a rename; the previous
  copy goes to `~/.agents/.laiaskills/backups/`. A failed install never leaves a half-written skill.
- **Install state** lives in `~/.agents/.laiaskills.json` (machine-local, never in the repo, next to
  the `npx skills` lock). Per skill: source submodule, skill path, commit, tag (if any), the git tree id
  of the skill folder at that commit, a per-file blob-hash manifest, and the install time.
- **Status per skill**, computed by `check`/`list`:

  | State | Meaning | Fix |
  |---|---|---|
  | up to date | copy = pin = newest upstream | — |
  | **pin outdated** | upstream has a newer tag/commit than the pin | `upgrade` |
  | **not synced** | copy ≠ pin (e.g. pin moved after a `git pull` or `upgrade` on another machine) | `sync` |
  | **modified** | copy's files differ from its recorded manifest (edited in place) | `sync --force` |
  | installed by another tool | a folder in the hub that laiaskills didn't install | `sync` replaces it (backed up) |
  | working tree | installed with `install --working-tree` from uncommitted edits | `sync` |

  Comparisons use git **tree ids** of the skill folder, not commits, so unrelated commits never mark a
  skill "not synced". File hashes are git blob ids (`git hash-object`), so edits are detected offline.
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
| `laiaskills check` | `git fetch --tags` each source (third-party and first-party `upstream/`); shallow sources use `git ls-remote` instead. Tagged sources: report newer release tags. Untagged: report commits on the tracked branch that touch each skill's path. Also reports copies that are **not synced** or **modified** (offline), local patches that won't apply to, or are already in, the newest version (5.8), upstream repos that were renamed or transferred (their web page redirects; skipped with `--offline`), and Claude plugins with a newer marketplace version. `--offline`; `--exit-code` → 1 when anything needs action |
| `laiaskills sync [skill…]` | Make every installed copy match its pin: install missing, re-copy not-synced, replace other tools' copies, remove skills dropped from `skills.json`, repair mirror links (add missing ones, remove ones a skill skips). Refuses to overwrite **modified** copies without `--force`. Asks before replacing or removing (`--yes` skips; without a terminal it stops instead of guessing). `--dry-run`. Run after `git pull` |
| `laiaskills upgrade [skill\|source…]` | Target = newest release tag, or branch head when untagged (`--to <tag\|commit>` overrides). Show `git log` + `diff --stat` for the skill path, confirm (Noora yes/no, or `--yes`), move the submodule pointer, re-resolve paths, re-copy into the hub, `git add`. For a first-party `upstream/` pin it then runs the automated re-check (5.6; `--no-agent` skips it). Staged only; `--commit` also runs `commit`. Interactive runs end with "Commit now?" (default no) |
| `laiaskills commit` | Commit the staged changes with generated Conventional Commit messages: third-party bumps in one `chore(third-party): bump swiftui-pro to v1.3.0, axe to 4f2c1a9` commit (one body line per skill, old → new); each re-checked first-party plugin in its own `docs(<plugin>): refresh guidance for <upstream> <tag>` commit, with the plugin `version` bumped in `plugin.json` and `marketplace.json` (patch by default; asks for minor/major/breaking). Shows the messages for confirmation (or `--yes`). **Never pushes** |
| `laiaskills add <owner/repo[@skill] \| url> [--skill name…]` | Add the submodule pinned to its newest release (`--shallow` for large repos), list its skills (Noora multiple-choice, or `--skill`), write `skills.json` entries, install (`--no-install` skips). When a repo has several copies of a skill, the shortest path wins; `--path <folder>` picks one explicitly. URLs may be `https://`, `git@host:`, or `file://`; owner/repo are the last two path segments |
| `laiaskills install [skill…]` | Copy the skill at its pin into the hub and create mirror links. `--working-tree` copies uncommitted first-party edits for testing |
| `laiaskills remove <skill>` | Move the hub copy to the backups folder, remove mirror links and the `skills.json` entry; drop the submodule when no skill uses it |
| `laiaskills doctor` | Broken mirror links, mirror entries that bypass the hub, missing mirror links, links in mirrors a skill skips, `skipMirrors` naming an unknown mirror, state-file entries whose hub folder is missing, foreign entries shadowing managed names, stale `~/.agents/.skill-lock.json` entries, sources with no skills, unresolvable or ambiguous names, local patches that don't apply or are no longer needed (5.8), Claude plugins declared in `claudePlugins` but not installed or installed but not declared |
| `laiaskills patch <skill> -m <reason>` | Save the edits to a third-party skill's installed copy as `patches/<skill>/NNNN-<slug>.patch` (or `--from <file>`), stage it, and reinstall with it (5.8) |
| `laiaskills import` | One-off migration from `~/.agents/.skill-lock.json` (GitHub entries directly; local-path entries via the source clone's `origin` URL). Prints the plan; `--apply` adds the sources and skills (staged, not installed), `--shallow owner/repo` for large ones. After `sync`, `--prune` removes the lock entries of skills laiaskills installed and of skills no longer installed (asks first, or `--yes`; backs the lock file up to the backups folder). Entries for skills other tools still install stay |
| `laiaskills browse [source]` | A source's skills with status and description; preview `SKILL.md` and scripts; mark and add from a picker (5.9). Sources not added yet are read from a throwaway clone in `tmp/laiaskills-browse/`, deleted on exit. Without `source`, pick one from the sources table. `--skill`, `--shallow` |
| `laiaskills find <query>` | Search skills.sh, then browse a result (5.9). `--limit`, `--shallow`. The only command that calls an online catalog |

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
   - `tools/scripts/validate_skills.rb` must pass. If it fails, the run stops: the pin stays staged,
     the agent's edits stay in the working tree (unstaged) for inspection, and nothing is committed.
   - If the agent changed nothing, the commit body records "re-checked against `<tag>`, no changes
     needed".
4. **Summarize and stage**: changed files and a diff summary.
5. **`commit`** (separately, or `--commit`) bumps the plugin `version` and writes the commit.

```json
{
  "$schema": "./schemas/recheck.schema.json",
  "agent": "claude",
  "commands": {
    "claude": [
      "claude", "-p", "{prompt}",
      "--permission-mode", "acceptEdits",
      "--allowedTools", "Read", "Grep", "Glob", "Edit", "Write",
      "Bash(git log:*)", "Bash(git diff:*)", "Bash(git show:*)", "Bash(git tag:*)"
    ]
  },
  "timeoutMinutes": 30
}
```

- The agent command lives in config, so a changed CLI flag is a config edit, not a code change. The
  Claude Code flags were checked against `claude --help`. Codex is not configured yet: it isn't
  installed on the authoring machine, so its flags are unverified; it is one more `commands` entry.
- The agent runs attached to the terminal (its output streams live) and is stopped after
  `timeoutMinutes`.
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
- Tests (97, offline: 76 library, 21 end to end): `LaiaSkillsKitTests` covers the library with real git repos and submodules;
  `LaiaSkillsCLITests` runs the built binary end to end with a fake `HOME`, a shell script standing in
  for the AI agent. Shared fixtures live in `LaiaSkillsTestSupport`, under the repo's
  `tmp/laiaskills-tests/`, and give every git process an identity so commits work on CI.
- CI: a job on `ubuntu-26.04` in `.github/workflows/ci.yml` installs Swift 6.4 (`SwiftyLab/setup-swift`)
  and runs `swift build` + `swift test` in `tools/laiaskills/`, with the SwiftPM build folder cached
  under a key that includes the image and Swift version. Locally, `mise run laiaskills:test-linux` runs
  the same tests in the `swift:6.4.0-resolute` (Ubuntu 26.04) Docker image.

### 5.8 Local patches (security fixes and similar)

Security audits of third-party skills can require changing them before upstream does (decision 19).
Submodules stay untouched; the fix is a patch applied to the installed copy.

- **Where:** `patches/<skill>/NNNN-<slug>.patch`, a unified diff relative to the skill folder (`a/` and
  `b/` prefixes) with a short header (`Reason:`, `Date:`) that `git apply` ignores. Found by folder; no
  `skills.json` key. Committed and reviewed like any other change.
- **Create:** edit the installed copy in the hub, then `laiaskills patch <skill> -m "<reason>"`. The diff
  against the pin plus the earlier patches becomes the next patch file, staged; the skill is reinstalled
  with it, and `commit` writes `fix(<skill>): <reason>`. `--from <file>` takes an existing patch instead.
  First-party skills are edited directly, never patched.
- **Install:** export the pin, apply the patches in file-name order in the staging folder, then swap. A
  patch that doesn't apply fails the install with the patch named. The install record keeps each
  patch's blob id, so adding, editing, or deleting one makes the copy "not synced".
- **Upgrade:** after the pin moves, each patch is tried on the new version. One the new version already
  contains (it reverse-applies) is deleted, staged, and listed in the upgrade commit. One that no longer
  applies stops the upgrade: the pin stays staged, the skill keeps its old copy, and the patch has to be
  updated or deleted before `sync` and `commit`.
- **Visibility:** `list` shows `<version> + N patches`; `show` lists each patch with its reason;
  `check` tests patches against the newest version when it has been fetched (not for shallow
  sources); `doctor` flags patches that don't apply to the pin, patches the pin already contains,
  patches for first-party skills, and patches for skills not in `skills.json`.
- Sending a fix upstream stays manual; the patch file can be attached to an upstream issue or PR as is.

### 5.9 Browse and discovery (phase 4, done 2026-10-05)

Commander was the browsing and discovery tool next to `laiaskills` (decisions 8–11). It was deleted on
2026-10-05, so `laiaskills` takes over both jobs (decision 20): `browse` looks inside a source,
`find` searches skills.sh. Both are read-only until you choose to add something, and adding always goes
through the existing `add` flow (staged, recorded in `pending.json`, committed with `commit`).

**`laiaskills browse [source]`**

- No argument: the sources table (as in `sources`), then a picker to open one. Without a terminal it
  prints the table only.
- `source` is a submodule path, `owner/repo`, or a git URL. `owner/repo` matches an existing submodule
  ignoring case. Anything else is opened as a **preview** (below), without adding a submodule.
- One row per skill in the source, sorted by name: name, status, and description (from the `SKILL.md`
  frontmatter, including `>` and `|` block scalars; shortened in the table, full in `--json`). When a
  name has several copies, the row shows the copy `add` would pick (shortest path, as in
  `Adder.find`) and how many copies there are.
- Status values:

  | Status | Meaning |
  |---|---|
  | `installed` | In `skills.json` from this source and installed (with `not synced` / `modified` as in `list`) |
  | `in skills.json` | Listed but not installed (run `sync`) |
  | `name taken` | A managed skill with the same name comes from another source; adding would conflict |
  | `other tool` | The hub or a mirror has an unmanaged entry with this name (as in `list --all`) |
  | `—` | Available |

- **Interactive loop** (Noora single choice, `/` filters): pick a skill, which prints its `SKILL.md`,
  its file count, and any executables or `scripts/` (anything an audit should read first, see 5.8).
  Then choose *Mark to add* (or *Unmark*), *Back*, or *Done*. On *Done* with skills marked, confirm
  "Add X, Y from owner/repo?" and run the add flow (`addChosen`, shared with `add`; `--shallow`
  passes through). Skills that are `installed`, `in skills.json`, or `name taken` cannot be marked,
  and nothing can be added from a first-party `upstream/` pin. Marked skills show a ✓ in the list.
- **Non-interactive:** the table and a hint, or `--json`. `--skill <name>` (or `owner/repo@skill`)
  prints that skill's `SKILL.md` and files instead. Adding stays explicit: `laiaskills add`.

**Preview clones** (sources not added yet)

A repo that isn't a submodule yet still has to be read to list its skills. Adding and then removing it
would touch `.gitmodules` and the index just to look, and reading files over HTTP would break the
no-GitHub-API rule (5.7) and Codeberg. So `browse` makes a throwaway clone that lasts only for the run.

- **Location:** `<repo>/tmp/laiaskills-browse/<owner>__<repo>-<random>/`, in the repo's untracked
  `tmp/` (the same convention as the test fixtures; never the system temp folder). With `--repo`, it
  goes in that repo's `tmp/`. The random suffix keeps two browses of the same repo apart. The validator
  only scans `first-party/`, so the nested clone is never picked up.
- **Small download:** `git clone --depth 1 --filter=blob:none --no-checkout` at the newest release tag
  (found with `git ls-remote`, as `add` does), or the default branch head when there are no tags. Then
  `git sparse-checkout set --no-cone SKILL.md` and `git checkout`, so a single batched fetch brings
  just the `SKILL.md` files (6 KB for `twostraws/SwiftUI-Agent-Skill`). Existing discovery
  (`Adder.skills(under:)`) works on that folder unchanged. A skill's file list and executable bits come
  from `git ls-tree` (mode `100755`) without downloading the files. Rows show the version as
  `v1.2.0 (preview)`.
- **Lifetime:** deleted when `browse` exits, including on errors, along with `tmp/laiaskills-browse/`
  once it is empty. Whatever a crash or Ctrl-C leaves behind is deleted by a later `browse` once it is
  more than an hour old (so a browse running in another terminal keeps its clone); no signal handler is
  needed. Nothing is reused or cached, so there is no `--refresh` or `--clean`. Browsing an unadded repo
  again re-clones it, which takes a few seconds. `add` clones the submodule normally and never reuses
  the preview.
- **Letter case:** `owner/repo` is stored as the host spells it today (AGENTS.md rule). For GitHub,
  `browse` reads the canonical name from the repository page's `og:url` meta tag (one `curl`, the
  same way `check` detects renames). If that fails it falls back to the name as typed. The preview
  folder and any later `add` use the canonical name.

**`laiaskills find <query>`**

- Searches skills.sh: `GET https://skills.sh/api/search?q=<query>&limit=<n>` through `curl`, the
  same way the rename check calls out. The response is decoded with `JSONDecoder`, so there is no new
  dependency. The endpoint is undocumented. As observed on 2026-10-05 it returns
  `{query, searchType, skills: [{id, source, skillId, name, installs}], count}`. A query under 2
  characters gets a 400, and the search is fuzzy, so a query with no real match still returns loosely
  related skills. Only `source` and `skillId` are required when decoding; everything else is optional.
- Table, in API (relevance) order: skill (`skillId`), source (`owner/repo`), installs, and status:
  `managed` when the skill is in `skills.json` from that repo, `name taken` when the name comes from
  another source, `source added` when only its repo is a submodule, `not a repo` for results whose
  source is a website (skills.sh also lists `.well-known` endpoints, e.g. `uizze.sh`), `—`
  otherwise. `--limit` (default 20), `--json`.
- Interactive: pick a result to open `browse <source>` with that skill's `SKILL.md` already shown.
  Non-interactive: the table plus a hint (`laiaskills browse owner/repo` or
  `laiaskills add owner/repo@skill`).
- **Isolation:** `find` is the only code that touches skills.sh. If the API changes or goes away, only
  `find` breaks, with an error that points to `browse owner/repo`. `check`, `doctor`, and everything
  else stay offline-capable and catalog-free (goal: no catalog dependency for the core).
- skills.sh lowercases `source`. Status matching ignores case, and adding goes through `browse`, which
  resolves the canonical name.
- Install counts are popularity, not trust. A result is unvetted until previewed; the preview's
  executables line is the prompt to audit.
- The endpoint can be overridden with `LAIASKILLS_CATALOG_URL`, for tests only (`file://` fixtures;
  curl ignores the query string there), so the suite stays offline.

**Code layout**

| File | Contents |
|---|---|
| `LaiaSkillsKit/Browser.swift` | `BrowseRow` and `BrowseStatus` (with `canAdd`), `Browser.rows`, `Browser.files` (`ls-tree`), `Browser.canonical` (`og:url`), and `PreviewClone` (make, remove, `cleanLeftovers`) |
| `LaiaSkillsKit/Catalog.swift` | skills.sh client: URL building, `curl`, lenient decoding, status matching |
| `laiaskills/BrowseCommands.swift` | `browse`, `find`, and `BrowseSession` (resolve the source, list, preview, interactive loop, add) |
| `laiaskills/UI.swift` | `pick(_:options:)` (Noora `singleChoicePrompt`, filter toggled with `/`) |
| `laiaskills/SourceCommands.swift` | `addChosen`, the tail of `add` shared with `browse`; `SourcesCommand.rows`/`render`, reused by `browse` without an argument |

`Adder.skills(under:)` takes a folder, so previews and submodules share discovery.

**Tests:** 14 new, all offline (97 in total: 76 library, 21 end to end). Status rows (name taken,
available, other tool, listed, installed, duplicate copies, a folded description). Preview clones from
a local origin: newest tag vs branch head, only `SKILL.md` checked out, `ls-tree` file list with the
executable bit, deletion after the run, and leftover cleanup by age. `og:url` parsing and frontmatter
block scalars. Catalog decoding (full, partial, garbage), query encoding, too-short queries, and
case-insensitive status. End to end: `browse` of an added source and of an unadded repo (JSON, table,
`--skill`, an unknown skill, the repo left untouched), and `find` against a `file://` fixture, including
the failure message. The interactive loop has no automated test (Noora needs a terminal); it was run
by hand in a pseudo-terminal: preview, *Mark to add*, *Done*, confirm, and the skill was staged and
installed in a throwaway repo.

## 6. Maintenance profile

| Driver | Frequency | Mitigation |
|---|---|---|
| Skills move/renamed inside source repos | High | Identity by name, re-discovered on every run |
| Source repo layouts vary | Medium | Generic `SKILL.md` scan, optional `path` |
| Agent directory conventions change | Medium | `tools/config/agents.json` |
| Noora 0.x breaking minors | Medium | `.upToNextMinor` pin, single `UI` layer |
| Upstream repo renamed (e.g. `everything-claude-code` → `affaan-m/ECC`) | Medium | GitHub redirects old URLs and git follows them silently; `check` requests each repo's web page and reports a redirect to another path, with the `git submodule set-url` command to apply it |
| Repos ship several copies of a skill (translations, per-agent folders) | Medium | `add` prefers the shortest path (`skills/<name>`); `path` in `skills.json` overrides |
| A skill folder turns into a Claude plugin (nested copy, `.claude-plugin/`) | Low | Copies leave both out (5.4) |
| Local patches go stale when upstream changes | Medium | `check` warns ahead; `upgrade` drops patches upstream absorbed and stops on conflicts (5.8) |
| Upstream repo deleted | Low | Pinned commit survives locally; fork critical sources |
| Swift toolchain / strict concurrency | Low | Mostly synchronous code, subprocess git |
| AI agent CLI flags or behaviour change (re-check) | Medium | Command in `recheck.json`; result guarded by allowed paths + validator |
| skills.sh search API changes or disappears (`find`) | Medium | Undocumented endpoint, isolated in `find`; lenient decoding; `browse owner/repo` keeps working (5.9) |

Size after phase 4: about 4,300 lines of Swift (including doc comments) plus 1,700 lines of tests, well over the original "under 1k" estimate, mostly from the write commands, guards,
and cross-platform handling. Expected upkeep is still a few hours per month, plus the routine upgrade
of third-party sources.

## 7. Roadmap

### Done

| When | Milestone |
|---|---|
| 2026-10-03 | **Phase 0, restructure**: plugins moved to `first-party/`, validator to `tools/scripts/`, docs to `docs/` (section 4) |
| 2026-10-03 | **Phase 1, read-only CLI**: `list`, `check` (including first-party `upstream/` tags), `doctor`; `skills.json`, `agents.json`, JSON Schemas, mise tasks, Linux CI job |
| 2026-10-03 | **CI on Ubuntu 26.04 with Swift 6.4**, pinned ahead of the `ubuntu-latest` switch; minimum Swift raised to 6.4 to match |
| 2026-10-03 | **Phase 2, write commands**: `sync`, `install`, `remove`, `add`, `upgrade`, `commit`, `show`, `sources`, `import`, and the automated AI re-check of first-party skills (5.6) |
| 2026-10-04 | **End-to-end CLI tests**: the built binary is tested against fixture repos with a fake `HOME` |
| 2026-10-04 | **Decision 18**: `skill-creator` left to the claude.ai sync (old copy removed); `formatting-build-output` managed as a skill, `xcsift` Claude plugin and its `PreToolUse` hook uninstalled |
| 2026-10-04 | **Per-skill mirror opt-out** (`skipMirrors`, 5.1) and **`import --prune`**; `sync` also repairs mirror links |
| 2026-10-04 | **Phase 3, migration** (section 9): 20 third-party sources and 36 skills imported, four under their current GitHub names; `sync` replaced 40 copies (backed up) and installed 24; `visionos-agents` Claude plugin uninstalled; `import --prune` emptied `~/.agents/.skill-lock.json`. All 64 skills up to date and linked. Snapshot in `tmp/migration-snapshot-2026-10-04/` |
| 2026-10-04 | **Fixes found during the migration**: names match ignoring case (`watchos` says `name: watchOS`); copies leave out plugin manifests and nested skills (duplicate `swiftui-pro:swiftui-pro`); `add` prefers the canonical `skills/<name>` copy (ECC skills had come from their Japanese translations) |
| 2026-10-04 | **Local patches** (decision 19, 5.8): `laiaskills patch`, applied on install, re-tested on upgrade, reported by `check` and `doctor`. First patch: `apple-hig-designer`, `printf -v` instead of `eval` on user input |
| 2026-10-04 | **Test suite**: 76 tests (61 library, 15 end-to-end CLI), all offline; green on macOS and Linux CI through `7e09a92` |
| 2026-10-04 | **Second patch**: `formatting-build-output` calls `xcsift` from PATH instead of `/usr/local/bin` |
| 2026-10-04 | **First live AI re-check**: mise v2026.9.4 → v2026.10.2 (16 releases); plugin 0.3.0 → 0.4.0. The agent fixed what had gone stale (`pkgx` removed, trust rules, version pins) and added daemons, remote `include`, and `conf.d` folders, but skipped smaller features to keep the length. A second pass, checked against upstream docs, covered them in the reference files and fixed two more stale lines (`mise dot`, lockfile version 3). The prompt now separates the compact `SKILL.md` from reference files that may grow |
| 2026-10-04 | **First routine third-party upgrade**: `ldomaradzki/xcsift` v1.5.1 → v1.5.2 and `wshobson/agents` (2 commits); no skill content changed. The xcsift patch was re-tested on the new version and kept |
| 2026-10-05 | **Source health**: `check` reports renamed upstream repos (a 301 from the repo's web page; git follows it silently) and Claude plugin updates; `add --path` picks one of several copies; `claudePlugins` in `skills.json` declares the expected Claude plugins (`swift-lsp`), and `doctor` reports missing and undeclared ones. 83 tests (67 library, 16 end to end) |
| 2026-10-05 | **Pushed** through `c9b7891`; CI runs the validator and tests on every push |
| 2026-10-05 | **Phase 4 designed** (5.9, decision 20): Commander was deleted, so `browse` (a source's skills with status and previews; unadded repos read from a throwaway blobless clone in `tmp/laiaskills-browse/`) and `find` (skills.sh search, isolated) move into `laiaskills`. The skills.sh endpoint and GitHub's canonical casing (`og:url`) were checked live |
| 2026-10-05 | **Phase 4 built**: `browse` and `find` (5.9). Tried on real repos (an added source, a recased `owner/repo`, unadded `anthropics/skills`, a live skills.sh search) and interactively in a pseudo-terminal, adding a skill in a throwaway repo. Surfaced and fixed: block-scalar descriptions (`>`, `|-`) read as the marker only; skills.sh lists websites as sources (`not a repo`). 97 tests (76 library, 21 end to end) |
| 2026-10-05 | **Phase 4 pushed, CI green on Linux** (run 37333321744): the `browse` and `find` tests pass on Ubuntu 26.04. Local Docker or Podman runs are dropped from the roadmap; CI is the Linux check (`laiaskills:test-linux` stays for anyone who has a container runtime) |
| 2026-10-07 | **First real `find` run** (`find tuist`) surfaced three prompt problems, all fixed: the header ("Which skill?") didn't say what the list was, there was no way out, and Noora's "enter confirm" hint didn't say what enter does. Pickers now have descriptive headers, `Quit` on the top-level lists, and hints that name the action (`enter preview`, `enter open`) |

### Pending

In priority order.

| # | Task | Who | Notes |
|---|---|---|---|
| 1 | Report upstream | owner | `jamesrochabrun/skills`: `eval` on user input in `apple-hig-designer` (our patch 0001). `ldomaradzki/xcsift`: the plugin hook returns `allow` for every Bash command, and the skill hardcodes `/usr/local/bin/xcsift` (our patch 0001). Both patches drop themselves on upgrade once upstream has the fix |
| 2 | Upgrade routine for third-party sources | owner | `check` then `upgrade` per source; 7 of the 20 have no releases and track a branch head. Decide a cadence (e.g. monthly), possibly as a scheduled task running `check --exit-code` |
| 3 | Try `browse` interactively | owner | The picker loop has no automated test (Noora needs a terminal); it was only driven with scripted keystrokes. One real run, e.g. `mise run laiaskills browse anthropics/skills` |
| 4 | Re-check first-party pins as their upstreams release | tool + owner | All five were current on 2026-10-04. When `check` shows one behind: `upgrade` without `--commit`, verify against upstream, `commit --bump` as fits. The updated prompt should make a second pass unnecessary; confirm on the next run |
| 5 | Codex in `recheck.json` | tool | Blocked: Codex is not installed. Verify its flags first once it is |
| 6 | Optional: Claude Code sandbox | owner | Not enabled on this machine (checked 2026-10-05). If turned on, the network allowlist needs at least `github.com`, `codeberg.org`, and (for `find`) `skills.sh` |
| 7 | Optional: delete `tmp/migration-snapshot-2026-10-04/` | owner | Once the migrated skills have been in use for a while |

### Implementation notes

0. **Restructure** (section 4), one `refactor!` commit, validator green.
1. **Read-only MVP**: `list`, `check` (including first-party upstream tags), `doctor`, plus the Linux CI
   job from day one. Notes from implementing it:
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
   and the automated re-check (5.6). Notes from implementing it:
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
   - Writing those tests surfaced two bugs, both fixed: `add` rejected `file://` and nested-group URLs
     (owner/repo are now the last two path segments), and library tests that commit only passed on
     machines with a global git identity (fixtures now set one for the whole test process).
3. **Migration prep**: the per-skill mirror opt-out and `import --prune`. Notes from implementing it:
   - `sync` used to compare only the hub copy, so a deleted mirror link or a new `skipMirrors` entry
     went unnoticed. An up-to-date copy whose links don't match now gets a `relink` step.
   - `uninstall` now removes only mirror links that point at the hub copy, so a skill's own folder or
     link in a mirror it skips (e.g. one from a Claude plugin) is never touched.
   - `doctor` reads `claude` as the mirror Claude Code uses: a skill that skips it is left out of the
     duplicate-plugin check.
   - The lock file is rewritten pretty-printed with sorted keys, the layout `npx skills` writes, with
     unknown top-level keys kept.
4. **Migration and what it surfaced**: notes from running it on the real machine.
   - `import` only knows the names in the lock file. Four repos had since been renamed or recased, so
     they were added first with `add` under their current names; `import` then skips skills already
     in `skills.json`.
   - Comparing the pre-migration snapshot with the new copies (20 identical, 5 packaging-only, 13 real
     upgrades) found three problems, all fixed: the Japanese ECC copies (alphabetical choice among
     duplicates), the nested `swiftui-pro` plugin copy, and the lost `printf -v` audit fix that led to
     local patches.
   - Patches are applied with `git apply` in a plain folder. `GIT_CEILING_DIRECTORIES` stops git from
     discovering an enclosing repository (the test fixtures live inside this one), which would make it
     read patch paths relative to that repository.
   - Commit by hand only with a pathspec (`git commit -- <paths>`): `laiaskills` stages its own
     changes (patches, `skills.json`, pins), and a bare `git commit` sweeps them into an unrelated
     commit.
5. **Browse and find** (5.9): notes from implementing them.
   - A `--no-checkout` clone followed by `sparse-checkout set` alone leaves the working tree empty; an
     explicit `git checkout` is what fetches the `SKILL.md` blobs, in one batch.
   - `curl` ignores the query string of a `file://` URL, so one fixture file serves any search and
     `find` is tested end to end offline.
   - Noora appends its own colon to a prompt's question, so questions carry none.
   - Discovery returns folders in path order, which put translated copies (`docs/ja/…`) first; browse
     rows are sorted by name instead.

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
- **(18) Skills that Claude already gets another way.** Decided 2026-10-04, case by case:
  - **`skill-creator`: not managed.** It is Claude-specific, and Claude already gets a newer copy through
    the claude.ai account sync (`anthropic-skills:skill-creator`). The copy in `~/.agents/skills` from
    the old install is removed.
  - **`formatting-build-output`: managed as a skill; the `xcsift` Claude plugin is uninstalled.** This is
    xcsift's own skill (upstream's frontmatter says `name: formatting-build-output`; the folder is
    `xcsift`, so the plugin shows it as `xcsift:xcsift`). The plugin adds a `PreToolUse` hook that
    rewrites every `xcodebuild` / `swift build` / `swift test` call to pipe through `xcsift`. That is too
    risky to keep: a bug in xcsift would then break every build, and in 1.0.3 the hook also returns
    `permissionDecision: "allow"` for every other Bash command, which skips the permission prompt.
    The skill tells the agent to pipe through `xcsift` itself, and every agent gets it.
  - **The per-skill mirror opt-out is still built**, as a general feature for a skill that other agents
    need but Claude already gets another way:
    `"<skill>": { "source": "…", "skipMirrors": ["claude"] }`. The skill stays fully managed (pinned,
    checked, upgraded, copied into `~/.agents/skills`) but gets no `~/.claude/skills` link.

- **(19) Local patches for third-party skills.** Decided 2026-10-04. Security audits can require fixing
  a third-party skill before upstream does (the first: `apple-hig-designer`'s component script passed
  user input through `eval`). Fixes are patch files in `patches/<skill>/`, applied to the installed copy
  on every install; submodules stay pristine and nothing third-party is copied into the repo. A patch
  the new upstream version already contains is dropped on upgrade; one that no longer applies stops the
  upgrade instead of silently losing the fix. See 5.8.
- **(20) Browsing and discovery move into `laiaskills`.** Decided 2026-10-05, after Commander was
  deleted. `browse` covers a source's skills, including repos not added yet (as a preview clone), and
  `find` searches skills.sh. That reverses the old non-goal for that one command only: the catalog call
  is isolated, so if it breaks only `find` breaks. Adding still goes through `add`. See 5.9.
- **(8–11) Migration items.** Other skill managers (Commander, `npx skills`) stay for discovery only and never install or update managed skills (Commander has since been deleted, see decision 20); `~/.agents/.skill-lock.json` was pruned; the skills missing from it were added by hand; `skill-creator` and `formatting-build-output` follow decision 18.

## 9. Migration (done 2026-10-04)

Every skill installed by other tools is now managed by laiaskills: 20 third-party sources and 36 skills,
plus the 28 first-party ones, 64 in total. Four sources are added under their current GitHub names
rather than the ones in the old lock file (`affaan-m/ECC`, `krutikJain/android-agent-skills`,
`AvdLee/Swift-Concurrency-Agent-Skill`, `twostraws/SwiftData-Agent-Skill`). The pre-migration snapshot
is in `tmp/migration-snapshot-2026-10-04/`; per-skill backups and the old lock file are in
`~/.agents/.laiaskills/backups/`.

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
| Per-source grid with Installed / Install | `browse`, `add` picker | Covered (5.9), including repos not added yet |
| Install from `owner/repo@skill`, URL, path | `add` | Covered; local paths only for first-party |
| Agent selection | Hub + mirrors in `agents.json` | Covered globally, with a per-skill mirror opt-out (decision 18) |
| Workspace / global scope | Global only | Not needed (decision 15) |
| Shows installs made by other tools | `list --all`, `doctor` | Covered |
| Local modifications that survive updates | `patch`, `patches/` | Covered beyond typical managers: re-tested on every upgrade (5.8) |
| Online discovery (skills.sh and similar) | `find` | Covered (5.9): skills.sh only, isolated |
| Reads Claude `marketplace.json` | — | Out of scope; `SKILL.md` scan instead, plugins via `/plugin` |
| GUI | Noora CLI | Out of scope |
