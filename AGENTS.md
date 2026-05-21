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

## Upstream submodules

Each plugin pins the upstream project the skill documents under `<plugin>/upstream/` as a git submodule:

| Plugin | Submodule | Upstream |
|--------|-----------|----------|
| `replay` | `replay/upstream` | [`mattt/Replay`](https://github.com/mattt/Replay) |
| `ios-simulator-ui-flow` | `ios-simulator-ui-flow/upstream` | [`cameroncooke/AXe`](https://github.com/cameroncooke/AXe) |
| `mise` | `mise/upstream` | [`jdx/mise`](https://github.com/jdx/mise) |

**Rules:**
- Pin to a released tag whenever possible (detached HEAD on the tag commit). Avoid tracking `main`.
- The pin records the upstream version the skill was authored or last verified against. Bump it when you re-verify the skill against a newer release, and bump the plugin's `version` in the same commit so users see the update.
- Submodules are **only** for skill authors and CI. They are intentionally placed outside `<plugin>/skills/<name>/` so they are not scanned by the validator and not shipped to users via `/plugin install` — git does not auto-init submodules, and Claude Code's plugin install pulls only the plugin subtree (the root `.gitmodules` is not part of the install).
- Clone with submodules locally when working on a skill: `git clone --recurse-submodules` or `git submodule update --init <path>`. Skip them entirely if you only need to read the skill.
- To re-pin: `cd <plugin>/upstream && git fetch && git checkout <tag>` then `git add <plugin>/upstream` from the repo root.
