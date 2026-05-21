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
```

Check for updates anytime with `/plugin marketplace update`.

## Plugins

| Plugin | Description |
|--------|-------------|
| [mise](mise/skills/mise/SKILL.md) | mise-en-place workflows for dev tools, project config, environments, tasks, plugins/backends, lockfiles, CI, and troubleshooting. |
| [ios-simulator-ui-flow](ios-simulator-ui-flow/skills/ios-simulator-ui-flow/SKILL.md) | Autonomous iOS Simulator UI verification flow: builds, deploys, launches, captures logs, inspects and interacts with UI via AXe CLI, takes screenshots, and verifies results — all without user intervention. |
| [replay](replay/skills/replay/SKILL.md) | HTTP recording, playback, and stubbing for Swift tests using the [Replay](https://github.com/mattt/Replay) framework — HAR fixtures, Swift Testing traits, matcher tuning, secret redaction, and `AsyncHTTPClient` support. |

## Versioning

Each plugin declares a semver `version` in its `.claude-plugin/plugin.json`. Claude Code uses this to surface updates when users run `/plugin marketplace update`. Bump the version whenever you change files under a plugin.
