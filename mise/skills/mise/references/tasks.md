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
mise tasks
mise tasks deps
mise tasks validate
mise --jobs 1 run test
```

`mise run` activates tools and env vars from mise config before executing.

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

## Watch

Use `mise watch` for rebuild loops. Add explicit `sources` to make watching and incremental checks precise.

```bash
mise watch build
mise watch build --glob 'src/**/*.ts'
mise watch serve --watch src --exts ts --restart
```

`mise watch` uses task `sources` by default and follows dependency sources for watched tasks. Extra flags are passed through to watchexec, so check `mise watch --help` for the installed version.

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
- Use `mise --jobs 1 run <task>` when parallel output hides the real failure.
- Check `sources` and `outputs` when tasks unexpectedly skip or rerun.
- Prefer file tasks for long shell logic instead of large TOML strings.
