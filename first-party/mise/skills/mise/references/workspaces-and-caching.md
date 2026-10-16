# Workspaces And Task Caching

Use this reference for monorepo workspace inference, affected-task selection, and the artifact cache for tasks. Monorepo basics (`monorepo_root`, `[monorepo].config_roots`, `//path:task` syntax) are in [tasks.md](tasks.md).

The artifact cache (local and remote) is **experimental** and requires `[settings] experimental = true` (or `MISE_EXPERIMENTAL=1`). Since 2026.10.6 the workspace project graph, `mise tasks graph`, `--affected`, `[monorepo.task_defaults]`, `[monorepo.projects]`, and `task.auto_infer` are stable and need no experimental flag.

## Task Artifact Caching

Two different mechanisms:

| Mechanism | Compares | On a hit |
| --- | --- | --- |
| Freshness (`sources`/`outputs`) | Modification times | Leaves outputs in place, skips the task. |
| Artifact cache (`cache`) | Declared input contents and other key material | Restores declared outputs and replays captured logs. |

Artifact caching needs `experimental = true`, at least one matching `sources` entry, and either explicit `outputs` paths or `outputs = []`. `outputs = { auto = true }`, absolute outputs, and patterns escaping the task directory are unsupported.

```toml
[settings]
experimental = true

[tasks.build]
run = "npm run build"
sources = ["package.json", "src/**"]
outputs = ["dist"]
cache = { enabled = true, env = ["NODE_ENV"] }
```

`outputs = []` caches the result and logs without filesystem artifacts — right for lint, test, and typecheck. It asserts the task has no filesystem side effect a hit must reproduce.

### Key Composition

The key covers source contents, the task definition and arguments, resolved task environment, the values of variables named in `cache.env`, `cache.command_inputs` output, resolved tool versions, dependency artifact keys, and OS/arch. Ambient env vars are ignored unless named in `cache.env`.

- `cache.command_inputs = ["node --version"]` runs before lookup and hashes command text plus stdout/stderr. Commands must be fast, deterministic, side-effect free.
- `pass_through_env` (or `task_config.global_pass_through_env`) passes a value to the task **without** affecting the key — use it for short-lived credentials, never for anything that changes outputs.
- `task_config.global_env` adds ambient variable names to every enabled cache in scope.

Declare dependency manifests and lockfiles as inputs so dependency updates invalidate the cache:

```toml
[task_config]
global_inputs = ["@group:node-dependencies"]

[task_config.input_groups]
node-dependencies = ["package.json", "pnpm-lock.yaml"]
```

Scope defaults with `[task_config.cache]`; a task-local `cache` overrides them. Only tasks that already qualify inherit the default.

### Run Modes

```bash
mise run --task-cache read-only test    # use hits, never publish (untrusted PRs)
mise run --task-cache write-only build  # warm the cache, always execute
mise run --task-cache off --force build # diagnose without cache reads or writes
mise run --task-cache local-only build  # skip any configured remote
```

`read-write` is the default. `MISE_TASK_CACHE` is the env equivalent. These affect only the artifact cache; `--no-cache` is about remote task *definitions*.

### Inspect And Clear

```bash
mise run --task-cache-explain <task>
mise run --dry-run --task-cache-explain-json <task>
mise run --task-cache-stats <task>
mise cache task <task> [--json]
mise cache clear --task <task>
```

There is no `mise tasks cache` command group. Storage lives under `MISE_CACHE_DIR/task-artifacts/v2`; bound it with `task.cache_dir`, `task.cache_max_size`, and `task.cache_max_age`.

### Remote Cache

```toml
[settings]
experimental = true
task.cache.remote_url = "https://cache.example.com/mise/"
task.cache.remote_namespace = "acme/widgets"
task.cache.remote_mode = "read-write"
```

The namespace is routing metadata, not a secret. The client only permits remote writes from recognized protected-branch push jobs in GitHub Actions or GitLab; the server must enforce authorization itself. Credentials come from `MISE_TASK_CACHE_REMOTE_TOKEN`, then `MISE_TASK_CACHE_REMOTE_TOKEN_FILE`, then GitHub OIDC (`id-token: write` plus `MISE_TASK_CACHE_REMOTE_OIDC_AUDIENCE`). Prefer the env var over the global-only `task.cache.remote_token` setting.

### Correctness

Enabling `cache` is a correctness assertion: identical key material must yield equivalent logs and outputs. Do not cache tasks that depend on wall-clock time, randomness, mutable network responses, or undeclared files. Cache entries contain captured stdout/stderr and every declared output, so they are not secret-free. Give untrusted PR jobs read-only access and a separate namespace.

On Linux, `cache = { enabled = true, audit = true }` uses `strace` to report undeclared reads/writes; it is advisory and needs `mise run --force` because cached tasks do not execute.

## Workspace Project Graph

mise can infer a provider-neutral project graph from ecosystem workspace metadata (node/pnpm/yarn/bun, cargo, uv, go, and since 2026.10.12 gradle). This is separate from `[monorepo].config_roots`: a project needs no `mise.toml` to appear in the graph.

```toml
monorepo_root = true

[monorepo]
config_roots = ["apps/*", "packages/*"]
```

```bash
mise tasks graph
mise tasks graph --explain   # which provider inferred each project, edge, and task
mise tasks graph --json
```

Override inferred values with `[monorepo.projects."node:@acme/web"]`; shared task defaults go in `[monorepo.task_defaults.<task>]`. `task.auto_infer` selects which ecosystems are inferred.

Gradle projects come from literal `include` directives in the root `settings.gradle(.kts)` (Gradle is never run); IDs are Gradle paths, so `:app` is `gradle::app` and the root project `gradle::`. Edges come only from literal `project(":lib")` references in a top-level `dependencies {}` block — add ones from `subprojects {}`, `allprojects {}`, or convention plugins with `depends_add`. Non-literal or conditional `include`s are an error.

If a provider cannot read its workspace (such as that Gradle error), `mise tasks graph` and `--affected` fail with it. Declaring any project in that provider's namespace under `[monorepo.projects]` (e.g. `[monorepo.projects."gradle::app"] root = "app"`) takes over: the error is ignored and the declared projects become the provider's whole contribution.

## Affected Tasks

```bash
mise run --affected build
mise run --affected --affected-base origin/main --affected-head HEAD test
mise run --affected --affected-explain --dry-run build
mise run --affected --affected-json build
mise run --affected --affected-committed build                          # ignore the working tree
mise run --affected --affected-uncommitted --affected-untracked build   # only what is not committed yet
```

mise selects projects owning changed paths, then follows reverse dependencies so downstream projects are included. Workspace-global paths and `task_config.global_inputs` select the whole workspace. Defaults are `HEAD~1`..`HEAD` locally; `MISE_AFFECTED_BASE`/`MISE_AFFECTED_HEAD` override, and GitHub Actions / GitLab MR metadata supply CI defaults.

Since 2026.10.6 a change is the committed `<base>...<head>` range **plus** staged/unstaged edits to tracked files and untracked, unignored files — the working tree counts only when the head revision is the checked-out commit. Naming any of `--affected-committed`, `--affected-uncommitted`, `--affected-untracked` (env `MISE_AFFECTED_COMMITTED`/`_UNCOMMITTED`/`_UNTRACKED`) limits selection to those sources; the working-tree flags error with a different `--affected-head`. Use `--affected-committed` in CI jobs that write untracked files before running `--affected`.

Normal task dependencies expand after selection, so a selected task can still pull a prerequisite from an unchanged project.

## Upstream Dependencies

Inside a workspace, a `^` prefix in `depends` refers to the same task in upstream project dependencies. It is only valid in `depends`, not `depends_post` or `wait_for`. Missing upstream tasks are skipped.

```toml
[monorepo.task_defaults.build]
depends = ["^build"]
```
