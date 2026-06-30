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
| `visionos-agents` | `visionos-agents/upstream` | [`tomkrikorian/visionOSAgents`](https://github.com/tomkrikorian/visionOSAgents) |

**Rules:**
- Pin to a released tag whenever possible (detached HEAD on the tag commit). Avoid tracking `main`.
- The pin records the upstream version the skill was authored or last verified against. Bump it when you re-verify the skill against a newer release, and bump the plugin's `version` in the same commit so users see the update.
- Submodules are **only** for skill authors and CI. They are intentionally placed outside `<plugin>/skills/<name>/` so they are not scanned by the validator and not shipped to users via `/plugin install` — git does not auto-init submodules, and Claude Code's plugin install pulls only the plugin subtree (the root `.gitmodules` is not part of the install).
- Clone with submodules locally when working on a skill: `git clone --recurse-submodules` or `git submodule update --init <path>`. Skip them entirely if you only need to read the skill.
- To re-pin: `cd <plugin>/upstream && git fetch && git checkout <tag>` then `git add <plugin>/upstream` from the repo root.

## Adding a plugin

Each top-level directory is a plugin: `<plugin>/.claude-plugin/plugin.json` + `<plugin>/skills/` + `<plugin>/upstream/` (submodule, see above).

To add an external skill repo as a plugin:

1. Vendor the source: `git submodule add <repo-url> <plugin>/upstream` (pin per the rules above).
2. Materialize the skills into `<plugin>/skills/` as real directories — each with its `SKILL.md`, `references/`, and `assets/`.
3. Write `<plugin>/.claude-plugin/plugin.json` (model it on `replay/`). Skill paths are relative to the plugin dir: `"skills": ["./skills/<skill>", ...]`.
4. Register the plugin in `.claude-plugin/marketplace.json`. Skill paths there are relative to the repo root: `"skills": ["./<plugin>/skills/<skill>", ...]`.
5. Add a `/plugin install <plugin>@laia-skills` line and a Plugins-table row to `README.md`.
6. Run `ruby scripts/validate_skills.rb` and fix any errors before committing.

### Validator conventions (`scripts/validate_skills.rb`)

- **Plugin name must match a skill.** Every plugin needs a skill directory named after it (`<plugin>/skills/<plugin>/SKILL.md`) plus a README link to that file. For a multi-skill bundle, add a **router** `SKILL.md` with that name (see `visionos-agents/skills/visionos-agents/SKILL.md`).
- **Links and asset paths must resolve.** Local Markdown links in each `SKILL.md` and the icon paths in each `agents/openai.yaml` are checked. Fix broken references in the vendored copy under `<plugin>/skills/`; leave `upstream/` pristine.
- **Quote long `description` frontmatter values** — a third-party skill manager's YAML parser breaks on long unquoted strings.

### Codex sidecar (`agents/openai.yaml`)

Each skill keeps an `agents/openai.yaml` sidecar — [OpenAI Codex's tool-specific format](https://developers.openai.com/codex/skills) for UI metadata (`display_name`, icons, `brand_color`, `default_prompt`), invocation policy, and tool dependencies. It is **not** a vendor-neutral standard: the cross-tool standard is the `SKILL.md` frontmatter (`name` + `description`), which Claude Code reads and which every skill already has. Claude Code ignores the sidecar; it exists so the same skills work in Codex. The validator enforces its schema only when present (`agents/openai.yaml` is optional).
