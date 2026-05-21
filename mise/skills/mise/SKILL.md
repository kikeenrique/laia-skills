---
name: mise
description: Manage mise-en-place (`mise`) workflows for dev tool versions, project configuration, shell activation/shims, environment variables, task runner setup, hooks, generated CI/devcontainer files, plugins/backends, lockfiles, CI, and troubleshooting. Use when the user mentions mise, `mise.toml`, `.mise.toml`, `.tool-versions`, `.miserc.toml`, `mise.lock`, `mise use/install/exec/run/tasks/config/env/trust/plugins/generate`, migrating from asdf, configuring project dev environments, writing or debugging mise tasks, setting env vars, enabling config environments, managing tool backends, or creating reusable mise guidance.
---

# mise

Use this skill to work with mise as a unified dev-tool manager, environment loader, and task runner. Prefer the repo's existing `mise.toml`, `mise.lock`, tasks, and local conventions before adding new structure.

This skill is agent-neutral. Keep operational guidance in `SKILL.md` and `references/*.md`; do not rely on vendor-specific sidecar metadata for essential behavior.

## First Checks

Start with local state before changing files:

```bash
mise --version
mise doctor
mise config
mise ls --current
mise tasks
```

If a command option matters, verify with `mise <subcommand> --help` because mise changes quickly. For current docs, use the official pages linked in [references/sources.md](references/sources.md).

## Decision Tree

| User need | Read |
| --- | --- |
| Install mise, activate shells, or get a project started | [getting-started.md](references/getting-started.md) |
| Choose between `mise activate`, shims, `mise exec`, `mise env`, and `mise run` | [activation.md](references/activation.md) |
| Edit `mise.toml`, config precedence, local files, or config environments | [config.md](references/config.md) |
| Manage tool versions, backends, registry tools, or `.tool-versions` migration | [dev-tools.md](references/dev-tools.md) |
| Add env vars, dotenv loading, templates, or exported env output | [environments.md](references/environments.md) |
| Define, run, debug, or optimize `mise run` tasks | [tasks.md](references/tasks.md) |
| Install or author plugins; choose plugins vs aqua/github/backends | [plugins.md](references/plugins.md) |
| Create backend, tool, or environment plugins | [plugin-development.md](references/plugin-development.md) |
| Add hooks, watch files, bootstrap files, CI files, or generated docs/stubs | [hooks-and-generate.md](references/hooks-and-generate.md) |
| Apply Node.js or Python cookbook patterns | [language-cookbooks.md](references/language-cookbooks.md) |
| Lockfiles, trust, CI, monorepos, settings, and advanced safeguards | [advanced.md](references/advanced.md) |

## Working Rules

- Use `mise use <tool>@<version>` when the user wants to update project or global config and install the tool in one step.
- Use `mise install` when config already exists and tools need to be installed without changing config.
- Use `mise exec -- <command>` or `mise x -- <command>` when shell activation is unavailable or a one-off command should run inside the mise environment.
- Use `mise run <task>` for project workflows; it activates mise tools and env vars before running the task.
- Keep committed project config in `mise.toml`; put developer-local overrides in `mise.local.toml` and gitignore local config and local lockfiles.
- Prefer exact or major versions that match the repo's existing conventions. Use `latest` only when the project already accepts moving versions.
- Prefer registry, aqua, github, or language backends before asdf-style plugins. Plugins are powerful but carry more trust and maintenance risk.
- Treat templates, env directives, and `path:` plugin versions as trust-sensitive. Check `mise trust --show` before telling users to trust config.

## Common Edits

Create a project config:

```toml
[tools]
node = "22"
python = "3.12"

[env]
NODE_ENV = "development"

[tasks.test]
description = "Run tests"
run = "npm test"
```

Add task dependencies and incremental rebuild checks:

```toml
[tasks.build]
description = "Build the project"
run = "npm run build"
sources = ["src/**/*.ts", "package.json", "tsconfig.json"]
outputs = ["dist/**"]

[tasks.test]
depends = ["build"]
run = "npm test"
```

Use config environments:

```bash
mise -E test run test
MISE_ENV=ci mise install
```

with files such as:

```text
mise.toml
mise.test.toml
mise.ci.toml
mise.local.toml
```

Enable reproducible installs:

```toml
[settings]
lockfile = true
```

Then run:

```bash
mise lock
mise install --locked
```

## Troubleshooting

- If the wrong tool version is active, run `mise config` and `mise ls --current` from the exact directory where the command fails.
- If activation does not work, inspect shell setup and prefer `mise exec -- <command>` as a reliable temporary path.
- If task output is confusing under parallel execution, retry with `mise --jobs 1 run <task>` or set an explicit task output style.
- If installs hit GitHub rate limits, configure GitHub authentication or use `mise.lock` so resolved URLs are reused.
- If config is ignored or prompts for trust, run `mise trust --show`; do not blanket-trust unknown config without reviewing it.
- If env vars are missing, compare `mise env --json`, `mise env --dotenv`, and the shell's activation state.

## Validation

After changing mise config:

```bash
mise config
mise install --dry-run
mise tasks
mise run <changed-task>
```

For CI changes, prefer `mise install --locked` when a complete `mise.lock` is committed.
