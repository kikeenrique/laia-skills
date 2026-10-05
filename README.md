# laia-skills

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) of reusable skills for iOS development workflows.

## About the name

**Laia** is a Spanish wordplay: it sounds like *"La IA"* ("the AI" in Spanish) and is also a common Spanish woman's name. So `laia-skills` reads as both "AI skills" and a personal namesake.

## Install

```text
/plugin marketplace add kikeenrique/laia-skills
/plugin install mise@laia-skills
/plugin install replay@laia-skills
/plugin install ios-simulator-ui-flow@laia-skills
/plugin install visionos-agents@laia-skills
/plugin install cupertino@laia-skills
```

Check for updates anytime with `/plugin marketplace update`.

## Plugins

| Plugin | Description |
|--------|-------------|
| [mise](first-party/mise/skills/mise/SKILL.md) | mise-en-place workflows for dev tools, project config, environments, tasks and task caching, machine bootstrap and dotfiles, plugins/backends, dependency providers, tool stubs, MCP, lockfiles, CI, and troubleshooting. |
| [ios-simulator-ui-flow](first-party/ios-simulator-ui-flow/skills/ios-simulator-ui-flow/SKILL.md) | Autonomous iOS Simulator UI verification flow verified against AXe v1.8.0: builds, installs, launches, captures logs, inspects and interacts with UI via AXe CLI, uses tap/slider/swipe/drag/batch/screenshot/video, and verifies results without user intervention. |
| [replay](first-party/replay/skills/replay/SKILL.md) | HTTP recording, playback, and stubbing for Swift tests using the [Replay](https://github.com/mattt/Replay) framework — HAR fixtures, Swift Testing traits, matcher tuning, secret redaction, and `AsyncHTTPClient` support. |
| [visionos-agents](first-party/visionos-agents/skills/visionos-agents/SKILL.md) | visionOS / Apple Vision Pro spatial computing suite (22 skills): spatial SwiftUI, RealityKit (rendering, animation/physics, audio, ECS), ARKit providers, ShaderGraph and USD authoring, SharePlay, WidgetKit, immersive media, and Swift Charts 3D. Skills vendored from [tomkrikorian/visionOSAgents](https://github.com/tomkrikorian/visionOSAgents) (MIT). |
| [cupertino](first-party/cupertino/skills/cupertino/SKILL.md) | Offline, citable Apple developer documentation search with the [cupertino](https://codeberg.org/CupertinoHQ/cupertino) CLI, verified against v1.4.2: 417 frameworks, HIG, sample code, Swift Evolution, Swift packages, AST symbol / conformance / inheritance queries, per-platform version filters, and a freshness check for newly released SDKs. Skill forked from upstream `skills/cupertino` (MIT). |

## Repository layout

| Folder | Contents |
|--------|----------|
| `first-party/` | Skills authored here and published through this marketplace, one plugin per folder |
| `third-party/` | External skill repos used here (20 sources), as git submodules pinned to releases, not published |
| `patches/` | Local fixes to third-party skills (e.g. from security audits), applied to the installed copies |
| `tools/` | Tooling: the skill validator and the `laiaskills` CLI (Swift, macOS and Linux) |
| `docs/` | Plans and design docs, e.g. [the repo and `laiaskills` design](docs/plans/skills-repo-design.md) |

## laiaskills

A small Swift CLI that tracks every skill this repo uses, first-party and third-party, and installs
them into `~/.agents/skills` (other agents' folders, such as `~/.claude/skills`, link to those copies).
Third-party sources are git submodules pinned to releases; every install records the pin it came from,
so outdated sources and drifted copies are both detected. Local fixes to third-party skills (for
example from a security audit) live in `patches/` and are re-applied on every install and re-tested on
every upgrade. `skills.json` lists the skills; `tools/config/agents.json` lists the agent folders. Runs
on macOS and Linux. Run it with [mise](https://mise.jdx.dev):

```text
mise run laiaskills list               # skills, versions, patches, and install state
mise run laiaskills check              # newer releases, drifted copies, stale patches, renamed repos, plugin updates
mise run laiaskills sync               # make installed copies match their pins (run after git pull)
mise run laiaskills add owner/repo     # add skills from a third-party repo
mise run laiaskills upgrade            # move pins to newer releases; re-checks first-party skills with an AI agent
mise run laiaskills patch <skill> -m … # save edits to an installed third-party skill as a patch
mise run laiaskills commit             # commit staged changes with generated messages (never pushes)
mise run laiaskills doctor             # problems in the config, the agent folders, and the patches
```

Also `install`, `remove`, `show`, `sources`, and `import` (with `--prune` for the `npx skills` lock
file); see `mise run laiaskills --help`. A skill can skip an agent's folder with `"skipMirrors"` in
`skills.json`, for one that agent already gets another way, and `"claudePlugins"` lists the Claude
Code plugins that should be installed, so `doctor` can spot missing or unexpected ones.

Status: the commands are implemented and tested (`mise run laiaskills:test`, 83 tests, also on Linux
CI), and all 64 installed skills (27 authored here, 37 third-party) are managed by laiaskills. Next:
`browse` (look inside a source, including repos not added yet, and add from a picker) and `find`
(search skills.sh), designed but not built yet. Design, decisions, and the roadmap of done and
pending work:
[docs/plans/skills-repo-design.md](docs/plans/skills-repo-design.md#7-roadmap).

## Versioning

Each plugin declares a semver `version` in its `.claude-plugin/plugin.json`. Claude Code uses this to surface updates when users run `/plugin marketplace update`. Bump the version whenever you change files under a plugin.
