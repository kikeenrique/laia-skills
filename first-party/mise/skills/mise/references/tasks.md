# Tasks

Use this reference when defining, running, debugging, or optimizing mise tasks.

## Define Tasks

Simple inline tasks:

```toml
[tasks]
build = "npm run build"
test = "npm test"
```

Expanded task form:

```toml
[tasks.build]
description = "Build the project"
run = "npm run build"
```

Standalone file tasks can live in `mise-tasks/`, which is useful for real shell scripts with syntax highlighting and linting:

```text
mise-tasks/build
mise-tasks/test
```

## Run Tasks

```bash
mise run build
mise r test
mise run --all              # interactive selector across the whole monorepo
mise tasks
mise tasks deps --compact
mise tasks validate
mise --jobs 1 run test
mise run --timeout 5m build
```

`mise run` activates tools and env vars from mise config before executing.

## Output Style vs Verbosity

These are two independent axes:

- **Style** — `task.output` setting, `--output`, `MISE_TASK_OUTPUT`, or a per-task `output`. Values: `prefix` (default), `interleave`, `keep-order`, `replacing`, `timed`.
- **Verbosity** — `task.quiet`/`task.silent` settings, `--quiet`/`--silent`, or per-task `quiet`/`silent`.

They combine: `--output prefix --quiet` keeps task-name prefixes while hiding mise's own messages. `--quiet` no longer forces un-prefixed output — use `--output interleave --quiet` for that. `--jobs 1` already forces `interleave`.

```toml
[settings]
task.output = "interleave"
task.quiet = true
```

The `quiet` *value* of `output` is deprecated (warns from mise 2026.9.3, removed 2027.9.3); combine `interleave` with a quiet option instead. All flat `task_*` settings are deprecated in favour of the `task.*` table.

## Task Shell

Set a config-scoped default shell without touching global settings:

```toml
[task_config]
shell = "bash -c"
cascade = true    # also apply to descendant config roots
```

A task's own `shell` wins. When the shell is PowerShell, mise passes `-NoProfile` so a profile cannot shadow the task's tools; `windows_powershell_no_profile = false` opts out.

## Dependencies

```toml
[tasks.build]
run = "npm run build"

[tasks.test]
depends = ["build"]
run = "npm test"
```

Dependencies can include args or env:

```toml
[tasks.test]
depends = [
  { task = "setup", env = { NODE_ENV = "test" } }
]
run = "npm test"
```

Use `depends_post` for follow-up tasks and `wait_for` for optional coordination with tasks that may already be running.

Set `optional = true` on a structured dependency so a name or pattern that matches nothing is not an error (an invalid pattern still is):

```toml
[tasks.test]
depends = [{ task = "//...:test", optional = true }]
```

`confirm` guards only the task's own `run` command. Dependencies run before the confirmation prompt unless you model them as `run = [{ task = "..." }]` or put `confirm` on the dependency tasks too.

## Structured Runs

Use `run` arrays to combine commands and task references:

```toml
[tasks.ci]
run = [
  { task = "lint" },
  { tasks = ["test:unit", "test:integration"] },
  "echo done"
]
```

## Task Env And Tools

Task-specific env does not automatically pass to dependencies:

```toml
[tasks.test]
env.NODE_ENV = "test"
tools.node = "22"
run = "npm test"
```

## Incremental Tasks

Use `sources` and `outputs` to skip work when inputs did not change:

```toml
[tasks.build]
run = "npm run build"
sources = ["src/**/*.ts", "!src/**/*.test.ts", "package.json"]
outputs = ["dist/**"]
```

If a dependency with `sources` reruns because its inputs changed, dependent tasks rerun too.

Source exclusions use the same `!` convention as gitignore and watchexec. Entries are evaluated in order, so later positive entries can re-include a path. Escape a literal leading bang as `"\\!important.txt"` in TOML.

`{{ task_source_files(only_changed=true) }}` narrows a run to sources written since mise last considered the task up to date — useful for linters. A failing run does not advance the baseline, and the filter never narrows to nothing.

For content-addressed reuse of results across input switches and deleted outputs, see the experimental artifact cache in [workspaces-and-caching.md](workspaces-and-caching.md).

## Monorepo Tasks

Basic monorepo tasks are stable. Declare the root and its project directories:

```toml
monorepo_root = true

[monorepo]
config_roots = ["packages/frontend", "packages/backend", "services/*"]
```

```bash
mise //packages/frontend:build
mise //...:test
mise '//packages/frontend:*'
mise :build          # current config root
```

Dependency paths starting with `./` resolve relative to the task that declares them, so `depends = [{ task = "./...:test", optional = true }]` matches the current project and its descendants. The experimental workspace graph, `--affected`, and upstream `^` dependencies are in [workspaces-and-caching.md](workspaces-and-caching.md).

## Watch

Use `mise watch` for rebuild loops. Add explicit `sources` to make watching and incremental checks precise.

```bash
mise watch build
mise watch build --glob 'src/**/*.ts'
mise watch serve --watch src --exts ts --restart
```

`mise watch` uses task `sources` by default and follows dependency sources for watched tasks. `--no-vcs-ignore`, `--no-project-ignore`, and `--no-global-ignore` widen what is watched. Extra flags are passed through to watchexec, so check `mise watch --help` for the installed version.

## Windows

Use `run_windows` when a task needs different commands on Windows:

```toml
[tasks.build]
run = "cargo build"
run_windows = "cargo build --features windows"
```

## Troubleshooting

- Use `mise tasks` to check discovery.
- Use `mise tasks deps <task>` to inspect the task graph.
- Use `mise tasks validate` before committing larger task refactors.
- Use `mise --jobs 1 run <task>` when parallel output hides the real failure; it forces `interleave`.
- If output is confusing, set the style and verbosity separately: `mise run --output interleave --quiet <task>`.
- Check `sources` and `outputs` when tasks unexpectedly skip or rerun; with artifact caching on, use `--task-cache off --force`.
- Deprecation warnings about `task_output`, `task_timeout`, and friends mean the flat setting names — move them under the `task.` table.
- Prefer file tasks for long shell logic instead of large TOML strings.
