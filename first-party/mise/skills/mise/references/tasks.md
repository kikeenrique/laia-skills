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

A `[tasks.<name>]` block for a file task (`hello` matches `hello.sh` and `hello.js`; `"hello.sh"` matches one) adds metadata like `description`, `env`, `depends` and keeps the script. Adding `run`, `run_windows`, or `file` **replaces** the script: the file task stops existing under its own name.

## Task Templates

`[task_templates.<name>]` holds shared fields (`run`, `tools`, `env`, `depends`, `usage`, …); a task opts in with `extends` and overrides what differs. Templates alone are not runnable.

```toml
[task_templates.rust]
tools = { rust = "1.90" }
env = { RUST_BACKTRACE = "1" }
usage = 'flag "--release"'      # concatenated before the task's own usage

[tasks.check]
extends = "rust"
run = "cargo check"
```

File tasks use a header: `#MISE extends="rust"` (the script stays the command; the template's `run` is ignored).

Share usage flags across tasks with a `.usage.kdl` flagset: `#USAGE include file="../shared.usage.kdl"` then `#USAGE use "common"`. In file tasks, relative include paths resolve from the task file's directory, and `$NAME`/`${NAME}` env refs work (inherited env, `MISE_CONFIG_ROOT`, `MISE_PROJECT_ROOT`, `MISE_TASK_DIR`, `MISE_TASK_FILE` — not task `env`). TOML tasks use `include file="{{ config_root }}/shared.usage.kdl"`.

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

The object form of `confirm` can relabel the answers (templated like the message; piped `y`/`n` and `--yes` still work):

```toml
[tasks.deploy]
confirm = { message = "Deploy to production?", yes = "Deploy", no = "Cancel", default = "no" }
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

## Daemons

Experimental (`experimental = true`, and [pitchfork](https://pitchfork.jdx.dev/) must be installed). `[daemons]` declares long-running processes — service presets such as PostgreSQL or Redis, a `run` command, or an existing `task` — and a task can require them:

```toml
[daemons]
postgres = "18"            # preset; exports DATABASE_URL and keeps data between runs

[daemons.api]
run = "exec npm run dev"
ready_port = 3000

[tasks.dev]
daemons = "postgres"
run = "npm run dev"
```

Presets: `postgres`, `redis`, `cockroachdb`, `nats`, `spicedb` (local-development auth only). Useful keys:

```toml
[daemons.postgres]
preset = "postgres"
version = "18"
port = "auto"               # default port in the main checkout, derived offset in linked worktrees
data_dir = ".data/postgres" # per-checkout data instead of $MISE_STATE_DIR (gitignore it)

[daemons.db]                # share one server across checkouts, separate database each
provider = "local-postgres" # defined in global config as [daemon_providers.local-postgres]
```

Named preset ports are exported as `<DAEMON>_<PORT_NAME>` (e.g. `CRDB_HTTP_PORT`). Global providers support the postgres, cockroachdb, and nats presets and are managed with `mise daemons providers ls/start/stop/restart <name>`.

`mise run dev` starts and waits for the daemon, which keeps running after the task exits. Manage them with `mise daemons ls/start/stop/logs/urls`. See the Daemons doc in [sources.md](sources.md) for presets, `[daemon_groups]`, `[daemons_settings]`, and per-worktree URLs.

## Incremental Tasks

Use `sources` and `outputs` to skip work when inputs did not change:

```toml
[tasks.build]
run = "npm run build"
sources = ["src/**/*.ts", "!src/**/*.test.ts", "package.json"]
outputs = ["dist/**"]
```

If a dependency with `sources` reruns because its inputs changed, dependent tasks rerun too.

`sources` and `outputs` can use parsed usage values, resolved per invocation: with `usage = 'arg "<target>"'`, write `sources = ["src/{{usage.target}}/**"]` and `outputs = ["dist/{{usage.target}}"]`.

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

Shorten a deep root with `[monorepo.path_aliases]`, e.g. `"123" = "foo/bar/baz/abc/123"`, so `mise run //123:build` works (single segment, must point at a listed config root; the full path stays canonical).

Dependency paths starting with `./` resolve relative to the task that declares them, so `depends = [{ task = "./...:test", optional = true }]` matches the current project and its descendants. The experimental workspace graph, `--affected`, and upstream `^` dependencies are in [workspaces-and-caching.md](workspaces-and-caching.md).

## Watch

Use `mise watch` for rebuild loops. Add explicit `sources` to make watching and incremental checks precise.

```bash
mise watch build
mise watch build --glob 'src/**/*.ts'
mise watch serve --watch src --exts ts --restart
```

`mise watch` uses task `sources` by default and follows dependency sources for watched tasks. `--no-vcs-ignore`, `--no-project-ignore`, and `--no-global-ignore` widen what is watched. Extra flags are passed through to watchexec, so check `mise watch --help` for the installed version.

## OpenTelemetry

Experimental. Export traces of `mise run` (a root span with setup such as tool installs, plus per-task and monorepo-root spans) to any OTLP collector:

```toml
[settings]
otel.enabled = true   # MISE_OTEL_ENABLED
otel.logs = true      # optional: also ship task stdout/stderr as OTLP logs (privacy boundary)
```

Configure the endpoint with standard variables such as `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`; without `otel.enabled`, mise ignores them. Since 2026.10.5 exporting requires `experimental = true`, as do `git::` remote task files (`file = "git::..."`) and `git::`/`oci::` entries in `task_config.includes`: `mise run` refuses them, while `mise tasks ls/info` show the task with a warning, and gated includes are skipped.

## Secrets

Experimental (`experimental = true`, fnox 1.39.0+). A project names [fnox](https://github.com/jdx/fnox) as its secrets source, and each task receives only the keys it lists, only while it runs; output is redacted:

```toml
[secrets.fnox]          # project config only; optional profile = "dev"

[tasks.deploy]
depends = ["build"]                          # build receives nothing
secrets = ["DEPLOY_KEY", "DATABASE_URL"]     # also #MISE secrets=[...] in file tasks
run = "./deploy.sh"                          # read $DEPLOY_KEY; never put secrets in run

[tasks.migrate]
env.PGURL = "postgres://app:{{ secrets.DB_PASSWORD }}@db/app"   # only allowed in task env values
run = 'psql "$PGURL" -f schema.sql'
```

```bash
mise secrets ls [--json]                     # keys, scopes, and granted tasks; never values
mise run --secrets STRIPE_KEY deploy         # one-off grant to the named tasks, not their deps
mise run --secrets-all deploy
mise x --secrets GH_TOKEN -- gh release list # nothing is injected without the flag
```

Tasks that list secrets need trusted config, ignore `raw` (unless `raw`/`interactive` is set on the task, which disables redaction), are not artifact-cached, cannot be global or remote tasks, and are refused from hooks, daemons, `mise bootstrap`, and safe mode. `secrets` needs `min_version = "2026.10.4"`; older mise rejects the field. A user task named `secrets` now needs `mise run secrets`.

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
