# Advanced

Use this reference for lockfiles, release-age policy, trust, settings, CI, monorepos, MCP, dependency providers, and complex troubleshooting.

## Lockfiles

`mise.lock` pins exact versions, download URLs, checksums, and supported platform metadata. Lockfiles are not created automatically; generate them intentionally.

```toml
[settings]
lockfile = true
```

```bash
mise lock
mise lock --platform linux-x64,macos-arm64
mise lock --upgrade                     # migrate a legacy (version 0) lockfile
mise lock --bump [tool] [--dry-run --json]
mise install --locked
```

New lockfiles use `lockfile_version = 1`, which records each original request in `specifiers` so overlapping requests such as `"1"` and `"1.0.0"` resolve reliably. Unversioned lockfiles stay at version 0 until `mise lock --upgrade`.

`mise lock --bump` re-resolves fuzzy selectors (`latest`, `lts`, `"22"`) against the newest matching versions and rewrites the lockfile without installing anything and without touching `mise.toml`. Exact pins are untouched — use `mise upgrade --bump` for those. `--global`/`--local` pick the lockfile; `--json` emits machine-readable changes for scheduled dependency-bump PRs.

Monorepos can use one root lockfile with `[monorepo] lockfile = true`. Per-subproject lockfiles start warning in mise 2026.12.0 and the unset default flips to root lockfiles in 2027.6.0.

Commit:

- `mise.lock`
- `mise.<env>.lock`

Gitignore:

- `mise.local.toml`
- `mise.*.local.toml`
- `mise.local.lock`
- `mise.*.local.lock`

Strict mode:

```bash
MISE_LOCKED=1 mise install
```

or:

```toml
[settings]
locked = true
```

Invocation-wide `locked` applies to project, user-global, and system config. Narrow it with the global-only `locked_scopes` setting (default `["project", "global", "system"]`), which project config cannot weaken:

```toml
# ~/.config/mise/config.toml
[settings]
locked = true
locked_scopes = ["project"]
```

To require lockfile resolution for one config root only, use `[tool_config]` instead — it is scoped to configs sharing that root and stays enforced even when its scope is excluded from `locked_scopes`:

```toml
[tool_config]
locked = true

[tools]
node = "24"
```

## Trust

Trust gates config features that can execute code: templates, env directives, tool-option tables, and `path:` plugin versions.

- **Safe files load without trust**: those containing only `min_version`, `[tools]` entries with plain version strings or arrays, and `[tasks]` without templates or tool options.
- **Auto-trust**: in normal mode `mise run`, a naked `mise <task>`, `mise install`, `mise exec`, and `mise watch` automatically trust the active config, because they exist to execute project-defined behavior. Other commands still require trust.
- **Worktrees**: trust is shared across git worktrees when the equivalent path in the main checkout is trusted. Paranoid mode disables that sharing and requires explicit content-bound trust everywhere.
- **CI**: detected CI assumes configs are trusted unless paranoid mode is on.
- **Monorepos**: trusting a monorepo root also trusts descendant configs in normal mode.

```bash
mise trust --show
mise trust
mise trust --all       # current dir, parents, and subdirectories
mise trust --untrust
mise trust --ignore
```

`mise doctor` lists untrusted configs under "problems". Review config before trusting, especially in a new checkout or external repository.

## Safe Mode

`MISE_SAFE=1` (or the global-only `[settings] safe`) is for automation that must read configuration it does not control — a bot resolving versions on a pull-request branch:

```bash
MISE_SAFE=1 mise lock --bump --dry-run --json
```

Safe mode **refuses** template `exec()`/`read_file()`, task execution, tool `postinstall` and `install_env`, and asdf plugin scripts or plugin installation. It **ignores** shell and install hooks, project `[env]`/env directives/`[shell_alias]`, project `[settings]`, and `_.source` everywhere. It loads otherwise-untrusted config without prompting, since those features are off. Operator-owned global and system config still applies.

Safe mode is not an OS sandbox and does not make a command read-only.

## Sandboxing

`mise exec` and `mise run` can restrict what the child command may do. Any `--deny-*`/`--allow-*` flag enables that restriction.

```bash
mise exec --deny-net -- npm run build
mise exec --deny-all --allow-read=. --allow-write=./dist -- node build.js
```

Defaults for every invocation:

```toml
[settings.sandbox]
deny_all = true
```

`--deny-all` keeps implicit access to system libraries and tool dirs; it is not an empty container. Enforcement uses the host OS and differs between Linux and macOS; **Windows does not enforce filesystem or network restrictions**. Configuration evaluation and tool installation happen outside the child's sandbox — use safe mode for untrusted config.

## CI Pattern

The docs' primary pattern is a committed wrapper so no separate install step is needed:

```bash
mise generate install-script -l -w    # once, locally; commit bin/mise, gitignore .mise/
```

```bash
./bin/mise install --locked
./bin/mise exec -- npm ci
./bin/mise exec -- npm test
```

Set `MISE_VERSION` to select a release; the wrapper otherwise defaults to the version that generated it. On GitHub Actions use `jdx/mise-action@v4`, adding `install_args: --locked` when a lockfile is committed.

Cache installed tools with a key covering runner OS/arch, mise config, and the lockfile, and still run `mise install` after restoring. Use `mise lock --platform ...` beforehand if lockfiles lack the CI platform, and configure GitHub authentication for uncached release metadata.

For untrusted PR config, run bots under `MISE_SAFE=1`.

## Release-Age And Provenance Policy

`minimum_release_age` defaults to **`24h`**. Raise it when the project wants a longer soak on moving versions; `"0s"` disables the delay entirely.

```toml
[settings]
minimum_release_age = "7d"
minimum_release_age_excludes = ["trivy", "npm:*"]

[tools.trivy]
version = "latest"
minimum_release_age = "1d"
```

Precedence: `--minimum-release-age` CLI flag > per-tool option > global setting. Exclusions accept backend wildcards (`npm:*`), shorthands, or full IDs, and merge across config files.

It only affects fuzzy resolution (`node@24`, `latest`); explicit pins bypass it, and already-installed fuzzy matches stay eligible. This pairs well with lockfiles: the delay postpones adoption, then `mise.lock` records the vetted version and URLs. `npm:` and `pipx:` also forward the cutoff into transitive dependency resolution.

For higher assurance, `paranoid = true` asks mise to verify provenance during installs regardless of lockfile contents when backend support exists:

```toml
[settings]
paranoid = true
```

## Important Settings

Set through `mise settings key=value`, env vars, or config:

```toml
[settings]
jobs = 8
lockfile = true
locked = false
experimental = false
env_shell_expand = true   # already the default
minimum_release_age = "7d"  # raises the 24h default

task.output = "interleave"
task.quiet = true
task.timeout = "10m"
task.timings = true
```

Task settings now live under a `task.` table. The flat `task_output`, `task_timeout`, `task_timings`, `task_skip`, `task_disable_paths`, `task_run_auto_install`, `task_show_full_cmd`, `task_skip_depends`, and `task_remote_no_cache` spellings are deprecated: they warn from mise 2026.8.0 and are removed in 2027.2.0.

Useful env vars:

```bash
MISE_JOBS=1
MISE_ENV=ci
MISE_LOCKED=1
MISE_SAFE=1
MISE_NO_CONFIG=1
MISE_NO_ENV=1
MISE_NO_HOOKS=1
MISE_EXPERIMENTAL=1
```

Self-update is separate from `mise upgrade`. For standalone installs, `mise settings auto_update=true` (global-only, skipped in CI) checks periodically before eligible interactive commands. Organizations can point self-updates at a mirror:

```toml
[settings.self_update]
repository = "myorg/mise-mirror"
```

## MCP And Dependency Providers

`mise mcp` is experimental and requires `MISE_EXPERIMENTAL=1`. It exposes read-only resources such as tools, tasks, env, and config, and can run mise tasks through MCP-compatible assistants.

```bash
MISE_EXPERIMENTAL=1 mise mcp
```

- `list_commands` reports each mise command's help plus its declared effect: `read`, `write`, or `destructive`. Every CLI doc page now carries the same `Effect:` line. The declarations describe commands; they do not enforce client approval policy.
- `run_task` runs a task with its normal dependencies and environment, non-interactively with `MISE_YES=1`, bounded by `task.timeout`. Output is captured, not streamed.
- `install_tool` is advertised but returns "not yet implemented" — install tools with `mise install` outside MCP.

`mise deps` is also experimental and the docs now require `[settings] experimental = true`. Use it when the user explicitly wants mise to manage project dependency installs such as `npm install`, `uv sync`, `go mod download`, or custom generated outputs based on hashed sources.

```toml
[settings]
experimental = true

[deps.npm]
auto = true

[deps.codegen]
sources = ["schema/*.graphql", "codegen.yml"]
outputs = ["src/generated/"]
run = "npm run codegen"
```

```bash
mise deps install --list
mise deps install npm --explain
mise deps add npm:react
```

`[deps] disable = ["npm"]` turns a provider off; providers also accept `depends`, `timeout`, and `dir`. Auto providers run before `mise x` and `mise run`; keep this explicit because dependency installs can execute package-manager code and affect task latency.

## Monorepos

Basic monorepo tasks are **stable**. See [tasks.md](tasks.md) for target syntax and [workspaces-and-caching.md](workspaces-and-caching.md) for the experimental workspace graph, `--affected`, and task artifact caching.

```toml
monorepo_root = true

[monorepo]
config_roots = [
  "packages/frontend",
  "packages/backend",
  "services/*",
]
```

`experimental_monorepo_root` was renamed to `monorepo_root`. Prefer explicit `[monorepo].config_roots`; automatic discovery is deprecated. Discovery tuning lives in `task.monorepo_depth`, `task.monorepo_exclude_dirs`, and `task.monorepo_respect_gitignore`.

```bash
mise install --monorepo        # union of tools from every config root
mise ls --monorepo
```

## Performance And Debugging

- Use `MISE_JOBS=1` or `mise --jobs 1 ...` for deterministic install/task ordering while debugging.
- Use `mise config` to inspect the merged config and loaded files.
- Use `mise env --json-extended` to inspect env source details.
- Use `MISE_NO_CONFIG=1`, `MISE_NO_ENV=1`, or `MISE_NO_HOOKS=1` to isolate config, env, or hook problems.
- Put `mise activate` late in shell rc files unless intentionally allowing later `PATH` changes to override mise.
