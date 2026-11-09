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
mise lock --sidecars [--json]           # list native dependency sidecar dirs; writes nothing
mise backends switch [tool] [--dry-run] # move lock entries to the registry's new backend
```

New lockfiles use the current format (`lockfile_version = 3`); older lockfiles keep their format during ordinary updates so collaborators on older mise can still read them, until `mise lock --upgrade`. Version 1 records each original request in `specifiers` so overlapping requests such as `"1"` and `"1.0.0"` resolve reliably; version 2 references native npm (aube) and uv dependency graphs in sidecar directories (`.mise/locks/<tool>/<version>/` next to `mise.lock` — commit them); version 3 records forge repository IDs for Packslip signatures. Older mise rejects newer lockfile versions.

When you name platforms (`--platform` or `lockfile_platforms`), `mise lock` warns since 2026.10.12 for each tool version with no build for one of them (`apko@0.30.0 is not available for windows-x64; it will not install there`); exit status is unchanged.

Commit `mise.lock` (and `.mise/locks/`) for CI and Docker builds too: with a matching entry mise skips the version-list lookup a fresh runner or Docker layer would otherwise make per tool. In a Dockerfile, copy `mise.lock` (and `.mise/locks/` when it records graphs) with `mise.toml` before `mise install --locked`. Without a lockfile, `install`/`use`/`run` reuse a cached version list for the tool's `minimum_release_age` minus an hour (1–24h; 23h by default), while `outdated`/`upgrade`/`ls-remote`/`lock`/`latest` refetch after `fetch_remote_versions_cache` (1h); `mise cache clear <tool>` forces a refresh.

When the registry moves a tool to another backend, mise keeps installing from the backend recorded in `mise.lock` and warns; `mise backends switch` relocks and reinstalls from the new backend (`--global` for the global lockfile).

`mise lock --bump` re-resolves fuzzy selectors (`latest`, `lts`, `"22"`) against the newest matching versions and rewrites the lockfile without installing anything and without touching `mise.toml`. Exact pins are untouched — use `mise upgrade --bump` for those. `--global`/`--local` pick the lockfile; `--json` emits machine-readable changes for scheduled dependency-bump PRs.

Since 2026.10.19 `lockfile_mode` defaults to `generate`: lockfile writes (including automatic locking during `mise install`/`mise use`) rebuild the whole lockfile from the current requests, reusing unchanged entries and locking the other recorded platforms. Set `lockfile_mode = "merge"` (`MISE_LOCKFILE_MODE`) to go back to updating entries one at a time as tools install. Neither mode creates a lockfile. `merge` is deprecated since 2026.10.24 (warns from 2027.4.0, removed in 2027.10.0); migrate by deleting the setting.

Full lock runs drop top-level tools the active config no longer declares. For a shared lockfile (e.g. `mise lock --global` used by profiles that configure different tools), set `lockfile_auto_prune = false` to keep unreferenced entries.

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

Since 2026.11.0 locked mode also **requires a lockfile checksum** for every artifact it downloads for the current platform (additional GitHub assets included) and fails before downloading when one is missing (`No lockfile checksum found for … (--locked mode)`). Backends that lock no download URL (`cargo`, `go`, `gem`, asdf, …) are unaffected. CI with URL-only entries (hand-written or from an older mise) fixes it with one `mise lock`, which hashes artifacts whose release publishes no checksum. `locked_require_checksum = false` (`MISE_LOCKED_REQUIRE_CHECKSUM=0`) allows URL-only entries; `merge` mode is exempt unless it is `true`. The setting is transitional (warns from 2027.10.0).

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

- **Safe files load without trust**: those containing only `min_version`, `[tools]` entries with plain version strings or arrays, and `[tasks]` without templates or tool options. Since mise 2026.10.0, inline options in a tool name (`"tool[opt=value]"`, also in `.tool-versions`) and remote `include` entries require trust too. Since 2026.10.9 a `path:<dir>` tool version (`node = "path:./local"`, or `node path:./local` in `.tool-versions`) also requires trust, so an untrusted clone can no longer put its own `bin/` first on `PATH` at `cd`; trusted configs work as before.
- **Untrusted settings and lockfiles**: since 2026.10.13 mise ignores the `[settings]` of an untrusted project config. Since 2026.10.19 an untrusted project's `mise.lock` only pins versions and checksums — entries that switch backend or add options are ignored, and downloads use the backend's normal URLs.
- **Auto-trust**: in normal mode `mise run`, a naked `mise <task>`, `mise install`, `mise exec`, and `mise watch` automatically trust the active config, because they exist to execute project-defined behavior. Other commands still require trust. Since 2026.10.19, `--help` on those commands, the `mise x` a shim runs, and the `mise run` of a task hook record no trust. Writing config with `mise use`/`mise set` trusts the whole config root, so mise first asks about any other untrusted file there (`mise.local.toml`, `mise.<env>.toml`); in safe mode writes record no trust.
- **Worktrees**: trust is shared across git worktrees when the equivalent path in the main checkout is trusted. The repository must list the worktree at its current location (run `git worktree repair` after moving one by hand), and a main-checkout path through a symlink shares nothing. Paranoid mode disables that sharing and requires explicit content-bound trust everywhere.
- **Nested checkouts**: a `mise/`, `.mise/`, or `.config/` directory that is its own git checkout is a separate project, trusted on its own.
- **CI**: detected CI assumes configs are trusted unless paranoid mode is on.
- **Monorepos**: trusting a monorepo root also trusts descendant configs in normal mode, only while the root stays trusted.

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

Safe mode **refuses** template `exec()`/`read_file()`/`read_json|yaml|toml()`/`get_env()` (and the file-inspecting filters and tests), task execution, tool `postinstall` and `install_env`, spm `install_command`, S3 requests, and asdf plugin scripts or plugin installation. It **ignores** shell and install hooks, project `[env]`/env directives/`[shell_alias]`, project `[settings]`, project `[deps]`, project lazy tools and `path:` versions, a project `[tool_alias]` redirecting a globally declared tool, project `[bootstrap]` and `[dotfiles]`, `watch_files` hooks, and `_.source` everywhere. Since 2026.10.19 project templates also see an empty `env`, and hosts a project config names (`api_url`, download URLs) get none of your forge tokens or netrc credentials, so private forges set only in project config cannot be reached. It loads otherwise-untrusted config without prompting, since those features are off. Operator-owned global and system config still applies.

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

`--deny-all` keeps implicit access to system libraries and tool dirs; it is not an empty container. Enforcement uses the host OS and differs between Linux and macOS; **Windows does not enforce filesystem or network restrictions**. Per-host `--allow-net=<host>` (task `allow_net`) is unsupported on both Linux and macOS and fails with an error; use `--deny-net` to block all network. Since 2026.10.19: on Linux, write restrictions (`--deny-write`, `--allow-write`, `--deny-all`) need kernel 6.2+ and fail on older kernels instead of running weaker; `--deny-net` also blocks io_uring (programs that need it won't run); an allowed path that goes through a symlink in the project leading out of it is an error (name the target directly); an empty allowed path allows nothing but still restricts. Configuration evaluation and tool installation happen outside the child's sandbox — use safe mode for untrusted config.

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

Set `MISE_VERSION` to select a release; the wrapper otherwise defaults to the version that generated it. On GitHub Actions use `jdx/mise-action@v5`, which adds `--locked` automatically when a `mise.lock` is committed; see [github-actions.md](github-actions.md).

Cache installed tools with a key covering runner OS/arch, mise config, and the lockfile, and still run `mise install` after restoring. Use `mise lock --platform ...` beforehand if lockfiles lack the CI platform, and configure GitHub authentication for uncached release metadata.

Since 2026.10.7 mise keeps finished downloads in a content-addressed cache, `$MISE_CACHE_DIR/downloads-cas` (`download_cache`, default on; `download_cache_max_size`, default `2GiB`, `0` = unlimited, LRU eviction). A file is reused when the server answers `304 Not Modified` or when a checksum is pinned in tool options or `mise.lock`. With `locked` or `paranoid`, only pinned downloads are stored or reused, so restoring `downloads-cas` in CI is a cache you can trust — unlike a restored `installs/`, which mise cannot verify against the lockfile. `always_keep_download` is deprecated (warns from 2026.11.0, removed in 2027.11.0); it now only matters for files an asdf plugin script downloads itself.

For untrusted PR config, run bots under `MISE_SAFE=1`.

## Release-Age And Provenance Policy

`minimum_release_age` defaults to **`24h`**, and since 2026.10.15 the default applies to every backend (previously asdf, vfox, conda, dotnet, http, s3, and spinel had none). Only versions with a known release date can be held back; installing an undated one warns that the cutoff could not be checked (switch backend or add the tool to `minimum_release_age_excludes`). Take one release early with `mise upgrade --minimum-release-age 0s gh`; a later upgrade will not downgrade it. Raise it when the project wants a longer soak on moving versions; `"0s"` disables the delay entirely.

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

For higher assurance, `paranoid = true` (global-only; `MISE_PARANOID=1`) turns on every protection. Since 2026.10.14 it also takes a list of categories (`MISE_PARANOID=config,env_files`; unknown names error):

| Category | Requires |
| --- | --- |
| `config` | Content-bound approval of every project config (and its task files and local aqua registries); no auto/CI trust, no worktree or monorepo sharing |
| `env_files` | Content-bound approval of files `env._.file`, `env._.source`, and the `env_file` setting load from a repository (`mise trust .env`; plain `mise trust` covers the config plus its env files) |
| `plugins` | Refuses unregistered community plugins by short name |
| `provenance` | Re-verifies provenance on every install regardless of lockfile, and confirms a mise-versions "no attestations" answer with GitHub |

```toml
# ~/.config/mise/config.toml
[settings]
paranoid = ["env_files"]   # e.g. approve find_up .env files without changing project trust
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

Settings that have no effect are now deprecated — remove them: `plugin_autoupdate_last_check_duration`, `sops.age_recipients` (use `mise set --age-encrypt --age-recipient <r> KEY=value`), `task.cache.stats_report`, and `idiomatic_version_file` / `legacy_version_file*` (use `idiomatic_version_file_enable_tools`). `mise settings set` now refuses to write a setting where mise would ignore it: early-init settings (`env`, `auto_env`, `env_conf_d`, `ceiling_paths`, `ignored_config_paths`, `override_*_filenames`) belong in `miserc.toml` or env vars, and global-only ones (`yes`, `paranoid`, `trusted_config_paths`, …) cannot take `--local`.

Global-only hardening settings added in 2026.10.19: `github.enterprise_hosts = ["github.mycompany.com"]` lists GitHub Enterprise Server hosts that may receive your GitHub token on `/api/v3` URLs (otherwise only `api.github.com`, `api.*.ghe.com`, and a tool's own `api_url` origin get it), and `extract_max_ratio` (default `100`, `0` = unlimited) fails an install whose archive unpacks past 256 MiB and that many times its download size. Since 2026.10.20 `system_packages.elevate_with` is global-only too (a project value is ignored with a warning).

Network settings: `extra_ca_certs` (2026.10.24; `MISE_EXTRA_CA_CERTS`) is a PEM bundle mise's HTTP clients trust in addition to the usual roots — e.g. a TLS-inspecting proxy's CA; `ipv4_only = true` (2026.10.22) connects over IPv4 only, for hosts that fail over IPv6.

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

Self-update is separate from `mise upgrade`. For standalone installs, `self_update.auto = true` (`MISE_SELF_UPDATE_AUTO`; global-only, skipped in CI) checks every `self_update.check_duration` before eligible interactive commands. These replaced `auto_update` and `auto_update_check_duration` in 2026.10.4; the old names still work (warning from 2027.4.0, removed in 2028.4.0) and older mise ignores a settings file with unknown `self_update.*` keys, so keep the old spelling while old clients must read the config. The per-tool `auto_update` option is a different feature (see [dev-tools.md](dev-tools.md)). `mise self-update` and the `mise.run` installer pick the newest stable release at least 24h old: override with `self_update.minimum_release_age`, `MISE_SELF_UPDATE_MINIMUM_RELEASE_AGE=7d`, or `--minimum-release-age`. Organizations can point self-updates at a mirror:

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
- `install_tool` (`{"tool": "node", "version": "22"}`) installs like `mise install`; without `version` it installs the configured version, or latest. No time limit.
- Since 2026.10.5 `run_task` and `install_tool` refuse untrusted projects and ask the user to run `mise trust <path>`; the server never trusts config on a client's behalf.
- The `mise://tasks` resource's `env` field is now an array of directive strings (as in `mise tasks ls --json`), not an object.

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

Basic monorepo tasks are **stable**. See [tasks.md](tasks.md) for target syntax and [workspaces-and-caching.md](workspaces-and-caching.md) for the workspace graph, `--affected` (stable since 2026.10.6), and the experimental task artifact cache.

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
- Table cells and task command lines are truncated to terminal width; `truncate = false` (`MISE_TRUNCATE=0`) or a per-command `--no-truncate` shows full values. AI agents already get untruncated output.

### Project Diagnostics

`mise doctor` diagnoses mise itself; `mise doctor project [--json]` runs checks the project declares, with its tools and env (never automatically, not sandboxed, output discarded — put guidance in `hint`):

```toml
[doctor.checks.openssl]
description = "OpenSSL development files are discoverable"
run = "pkg-config --exists openssl"
hint = "Run `mise bootstrap packages apply`."
timeout = "5s"              # default 10s
os = ["linux", "macos"]     # also: dir, shell

[doctor.checks."openssl:headers"]
depends = ["openssl"]       # 2026.10.18: runs only after openssl passes, else reported `blocked`
run = "test -f {{ vars.openssl_include | quote }}/ssl.h"
```

Since 2026.10.17 `run`, `description`, and `hint` render as templates (`vars`, `env`, …; `quote` paths in `run`). A `depends` dependency that ends `fail`, `error`, `skipped`, or `blocked` blocks its dependents; `blocked` alone does not fail the run. An unknown name or a cycle in `depends` is an error and no check runs.
