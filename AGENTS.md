# Agent guidelines

Guidance for AI coding agents (Claude Code, Cursor, etc.) working in this repo.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[scope][!]: <description>`

Common types:
- `feat` — new skill, new plugin, or user-visible capability
- `fix` — bug fix in a skill, reference, validator, or CI
- `docs` — README, references, SKILL.md prose
- `refactor` — restructuring without behavior change
- `chore` — tooling, deps, repo housekeeping
- `ci` — `.github/workflows/` changes

Rules:
- Add `!` after the type (and a `BREAKING CHANGE:` footer) when paths, frontmatter keys, plugin layout, or install identifiers change in a way users must react to.
- Use a scope when changes are confined to one plugin: `feat(replay): ...`, `docs(mise): ...`.
- Bump the affected plugin's `version` in `.claude-plugin/plugin.json` (semver) whenever its files change — Claude Code uses this to surface updates via `/plugin marketplace update`.
- Do not add `Co-Authored-By:` trailers for AI agents.

Example:

```
feat(mise): add lockfile troubleshooting reference

Documents recovery steps for corrupted mise.lock files and how to
regenerate without losing tool versions.
```

## Repository layout

Top-level folders are grouped by ownership, not packaging:

| Folder | Contents |
|--------|----------|
| `first-party/` | Skills authored here and published through the marketplace. Each subfolder is one plugin. |
| `third-party/` | External skill repos used here, as git submodules (`third-party/<owner>__<repo>`), added with `laiaskills add`. Never published, never copied into `first-party/`. |
| `patches/` | Local fixes to third-party skills (e.g. from security audits), one folder per skill, applied to the installed copy by `laiaskills`; submodules stay untouched. Create them with `laiaskills patch <skill> -m <reason>`. |
| `tools/` | Tooling: `tools/scripts/validate_skills.rb`, the `laiaskills` CLI (`tools/laiaskills/`), and its configs (`tools/config/`). |
| `docs/` | Committed plans and design docs. See [`docs/plans/skills-repo-design.md`](docs/plans/skills-repo-design.md). |
| `tmp/` | Untracked scratch space. Not in `.gitignore`; never commit it. |

`.claude-plugin/marketplace.json` stays at the repo root, where Claude Code expects it.

## Upstream submodules

Each plugin pins the upstream project the skill documents under `first-party/<plugin>/upstream/` as a git submodule:

| Plugin | Submodule | Upstream |
|--------|-----------|----------|
| `replay` | `first-party/replay/upstream` | [`mattt/Replay`](https://github.com/mattt/Replay) |
| `ios-simulator-ui-flow` | `first-party/ios-simulator-ui-flow/upstream` | [`cameroncooke/AXe`](https://github.com/cameroncooke/AXe) |
| `mise` | `first-party/mise/upstream` | [`jdx/mise`](https://github.com/jdx/mise) |
| `visionos-agents` | `first-party/visionos-agents/upstream` | [`tomkrikorian/visionOSAgents`](https://github.com/tomkrikorian/visionOSAgents) |
| `cupertino` | `first-party/cupertino/upstream` | [`CupertinoHQ/cupertino`](https://codeberg.org/CupertinoHQ/cupertino) (Codeberg) |

The submodule *names* in `.gitmodules` (e.g. `replay/upstream`) predate the move to `first-party/` and are internal identifiers only; always refer to submodules by *path*.

**Rules:**
- Pin to a released tag whenever possible (detached HEAD on the tag commit). Avoid tracking `main`.
- The pin records the upstream version the skill was authored or last verified against. Bump it when you re-verify the skill against a newer release, and bump the plugin's `version` in the same commit so users see the update. `laiaskills upgrade` does both: it moves the pin, has an AI agent re-check the skill, and `laiaskills commit` bumps the version (see the `laiaskills` section below).
- Submodules are **only** for skill authors and CI. They are intentionally placed outside `first-party/<plugin>/skills/<name>/` so they are not scanned by the validator and not shipped to users via `/plugin install` — git does not auto-init submodules, and Claude Code's plugin install pulls only the plugin subtree (the root `.gitmodules` is not part of the install).
- Clone with submodules locally when working on a skill: `git clone --recurse-submodules` or `git submodule update --init <path>`. Skip them entirely if you only need to read the skill.
- To re-pin: `mise run laiaskills upgrade first-party/<plugin>/upstream` (add `--to <tag>` for a specific release, `--no-agent` to update the skill by hand), then `mise run laiaskills commit`. By hand: `git -C first-party/<plugin>/upstream fetch --tags && git -C first-party/<plugin>/upstream checkout <tag>`, then `git add first-party/<plugin>/upstream`.

## Adding a plugin

Each folder under `first-party/` is a plugin: `first-party/<plugin>/.claude-plugin/plugin.json` + `first-party/<plugin>/skills/` + `first-party/<plugin>/upstream/` (submodule, see above).

To add an external skill repo as a plugin:

1. Vendor the source: `git submodule add <repo-url> first-party/<plugin>/upstream` (pin per the rules above).
2. Materialize the skills into `first-party/<plugin>/skills/` as real directories — each with its `SKILL.md`, `references/`, and `assets/`.
3. Write `first-party/<plugin>/.claude-plugin/plugin.json` (model it on `first-party/replay/`). Skill paths are relative to the plugin dir: `"skills": ["./skills/<skill>", ...]`.
4. Register the plugin in `.claude-plugin/marketplace.json`. Skill paths there are relative to the repo root: `"skills": ["./first-party/<plugin>/skills/<skill>", ...]`.
5. Add a `/plugin install <plugin>@laia-skills` line and a Plugins-table row to `README.md`.
6. List each of its skills in `skills.json` as `{ "source": "first-party" }` (the validator warns about first-party skills that are missing).
7. Run `mise run validate` (or `ruby tools/scripts/validate_skills.rb`) and fix any errors before committing.

## laiaskills

Swift package in `tools/laiaskills/` (Swift 6.4+, must build and pass tests on **Linux and macOS**; CI runs it on Ubuntu 26.04). Design, decisions, and roadmap: [`docs/plans/skills-repo-design.md`](docs/plans/skills-repo-design.md). Update the roadmap there when you finish or add work.

- `LaiaSkillsKit` holds all logic and is what the tests cover; the `laiaskills` target only parses arguments and renders. All Noora calls go through `UI.swift`.
- No macOS-only APIs (AppKit, CryptoKit, the Trash API). Shell out to `git` instead of using libgit2 or the GitHub API.
- Tests build their fixtures (including real git repos) under the repo's `tmp/laiaskills-tests/`, never the system temp folder. Three targets: `LaiaSkillsKitTests` (library), `LaiaSkillsCLITests` (runs the built binary end to end with a fake `HOME`; a shell script stands in for the AI agent), and the shared fixtures in `LaiaSkillsTestSupport`. Everything is offline: local git repos stand in for GitHub.
- Fixtures set git identity and `protocol.file.allow` for the whole test process through `GIT_CONFIG_*` variables, so commits work on CI machines without a git identity. Don't rely on your own global git config in tests.
- Tasks: `mise run laiaskills <command>`, `mise run laiaskills:test`, and `mise run laiaskills:test-linux` (Docker or Podman).
- Never block on GCD's shared pool (`DispatchQueue.global()`) while waiting for it: tests run in parallel on that pool and it deadlocks. `Shell` uses dedicated threads for this.
- Manual end-to-end runs: point `HOME` at a folder under `tmp/` and use `--repo` with a throwaway clone under `tmp/`, so your real agent folders and this repo are never touched.
- Re-pinning a first-party `upstream/` is done with `laiaskills upgrade` (it re-checks the skill with the agent in `tools/config/recheck.json`, prompt in `tools/config/prompts/recheck.md`) and `laiaskills commit` (bumps the plugin version).
- `add`, `remove`, `upgrade`, `import --apply`, and `patch` stage their changes and record them in `.git/laiaskills/pending.json`; `laiaskills commit` writes the messages. When committing anything else by hand, always use a pathspec (`git commit -m … -- <paths>`): a bare `git commit` sweeps those staged changes into the wrong commit.
- Patch-related code lives in `Patches.swift`. `git apply` runs with `GIT_CEILING_DIRECTORIES` so it never discovers an enclosing repo (fixtures live inside this one).
- `browse` and `find` live in `Browser.swift`, `Catalog.swift`, and `BrowseCommands.swift`. `find` is the only code that calls skills.sh (undocumented API); keep it that way, so nothing else depends on a catalog. Its tests point `LAIASKILLS_CATALOG_URL` at a `file://` fixture. `browse` reads repos that aren't added yet from a throwaway clone in `tmp/laiaskills-browse/`, deleted on exit.
- `find`, `browse`, and the root command are `AsyncParsableCommand` (Noora's spinner is async); everything else is synchronous. Slow work in their interactive paths goes through `ui.progress`, never with `--json`. Their screens have no automated test (Noora needs a terminal): drive them in a pseudo-terminal (`script`) and have a person try them before calling a change done. Stay within Noora's API; where it has a gap (no Esc to go back in its list picker), use a menu row rather than wrapping its internals. Start child processes that read the terminal (the pager) with `posix_spawn`, not `Process`, which puts them in a background process group.

## Third-party skills

Third-party skills are never copied into the repo; `skills.json` maps each to a submodule under `third-party/`, and `laiaskills` installs copies into `~/.agents/skills`.

- **Discover:** `mise run laiaskills find [query]` searches skills.sh (in a terminal, browse results and search again); `mise run laiaskills browse <owner>/<repo>` lists a repo's skills (descriptions, status, scripts to audit) without adding it, and can add from its picker in a terminal. Read a skill's scripts before adding it.
- **Add:** `mise run laiaskills add <owner>/<repo> --skill <name>` (pins the newest release; `--shallow` for large repos), then `mise run laiaskills commit`. Use the repo's current GitHub name and casing. When a repo has several copies of a skill (translations, per-agent folders), the shortest path wins; check the `path` written to `skills.json`, or pick one with `--path <folder>`.
- **Renamed upstream:** `laiaskills check` reports sources whose repo moved; apply it with `git submodule set-url -- <path> <new-url>` and commit `.gitmodules` with a pathspec.
- **Claude plugins:** list the ones that should be installed in `claudePlugins` in `skills.json`; `doctor` reports missing and undeclared ones, `check` reports updates.
- **Upgrade:** `mise run laiaskills check`, then `mise run laiaskills upgrade <skill-or-source>` and `commit`.
- **Fix (e.g. after a security audit):** edit the installed copy in `~/.agents/skills/<skill>/`, then `mise run laiaskills patch <skill> -m "<reason>"` and `commit`. Never edit files under `third-party/`. Patches live in `patches/<skill>/` and are re-tested on every upgrade.
- **Skip an agent:** `"skipMirrors": ["claude"]` on a `skills.json` entry when that agent already gets the skill another way (decision 18 in the design doc).
- Don't install the same skills through a Claude plugin as well; `doctor` reports duplicates.

### Validator conventions (`tools/scripts/validate_skills.rb`)

- **Plugin name must match a skill.** Every plugin needs a skill directory named after it (`first-party/<plugin>/skills/<plugin>/SKILL.md`) plus a README link to that file. For a multi-skill bundle, add a **router** `SKILL.md` with that name (see `first-party/visionos-agents/skills/visionos-agents/SKILL.md`).
- **Marketplace skill paths must exist.** Every path in a plugin's `skills` array in `marketplace.json` must point at a folder containing `SKILL.md`.
- **Links and asset paths must resolve.** Local Markdown links in each `SKILL.md` and the icon paths in each `agents/openai.yaml` are checked. Fix broken references in the vendored copy under `first-party/<plugin>/skills/`; leave `upstream/` pristine.
- **Quote long `description` frontmatter values** — a third-party skill manager's YAML parser breaks on long unquoted strings.

### Codex sidecar (`agents/openai.yaml`)

Each skill keeps an `agents/openai.yaml` sidecar — [OpenAI Codex's tool-specific format](https://developers.openai.com/codex/skills) for UI metadata (`display_name`, icons, `brand_color`, `default_prompt`), invocation policy, and tool dependencies. It is **not** a vendor-neutral standard: the cross-tool standard is the `SKILL.md` frontmatter (`name` + `description`), which Claude Code reads and which every skill already has. Claude Code ignores the sidecar; it exists so the same skills work in Codex. The validator enforces its schema only when present (`agents/openai.yaml` is optional).
