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

## Watch

Use `mise watch` for rebuild loops. Add explicit `sources` to make watching and incremental checks precise.

## Windows

Use `run_windows` when a task needs different commands on Windows:

```toml
[tasks.build]
run = "cargo build"
run_windows = "cargo build --features windows"
```

## Troubleshooting

- Use `mise tasks` to check discovery.
- Use `mise --jobs 1 run <task>` when parallel output hides the real failure.
- Check `sources` and `outputs` when tasks unexpectedly skip or rerun.
- Prefer file tasks for long shell logic instead of large TOML strings.
