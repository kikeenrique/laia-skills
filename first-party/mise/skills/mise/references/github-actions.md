# GitHub Actions (`jdx/mise-action`)

Use this reference when installing mise and project tools in a GitHub Actions workflow. Verified against `jdx/mise-action` **v5.0.1**; confirm current inputs in the action's [`action.yml`](https://github.com/jdx/mise-action/blob/main/action.yml) when behavior matters.

## Minimal Workflow

The action installs mise, runs `mise install` from the repo's `mise.toml` / `.tool-versions`, caches the mise data dir, and exports tool PATHs and `[env]` to later steps.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v5
      - run: mise run test
```

Prefer `mise run <task>` in later steps so CI and local runs share one definition. Plain commands (`node`, `npm test`) also work because the action exports PATH entries.

`mise generate github-action` scaffolds a workflow like this, but mise v2026.10.2 still emits `jdx/mise-action@v3` and sets `MISE_EXPERIMENTAL: true`. Bump the tag to `@v5` and drop the experimental flag unless a task needs it.

## Key Inputs

| Input | Default | Use |
| --- | --- | --- |
| `version` | newest release ≥ `minimum_release_age` | Pin the mise binary, e.g. `2026.10.2`. Takes precedence over the release-age delay. |
| `minimum_release_age` | `24h` | Soak time for an unpinned mise binary (`7d`, `6mo`, ISO date; `0s` disables). Applies to the mise binary only, not to tools. |
| `sha256` | — | Checksum of the mise binary; also lets a cached binary of an older release (no signed checksums) be reused. |
| `install` | `true` | `false` installs mise only; run `mise install` yourself. |
| `install_args` | — | Extra `mise install` args, e.g. `"node python"` to install a subset. |
| `bootstrap` / `bootstrap_skip` / `bootstrap_args` | `false` | Run `mise bootstrap` instead of `mise install`. `install_args` cannot be combined with it. |
| `working_directory` | `.` | Directory mise runs in (monorepo subproject). |
| `mise_toml` / `tool_versions` | — | Write inline config into the working directory instead of using committed files. |
| `cache` / `cache_save` | `true` / `true` | Disable the cache, or restore-only (e.g. on PRs). |
| `cache_key_prefix` / `cache_key` | `mise-v1` | Bump the prefix to invalidate; or override the full key (templates below). |
| `env` / `export_path` | `true` / `true` | Export mise env vars / PATH entries (including `[env] _.path`) to later steps. |
| `github_token` | `${{ github.token }}` | Authenticates GitHub release lookups to avoid the 60 req/h anonymous limit. |
| `experimental` | `false` | Sets `MISE_EXPERIMENTAL`. |
| `reshim` / `add_shims_to_path` | `false` / `true` | Rebuild shims; or keep the shims dir off PATH. |
| `log_level` | `info` | `debug` when diagnosing installs. |

Output: `cache-hit` (boolean).

## Lockfiles

When a repo lockfile (`mise.lock`) exists in the working directory or a parent, the action **automatically** runs `mise install --locked` (or `mise --locked bootstrap`). Do not add `--locked` to `install_args` by hand — it is appended unless already present. Auto-locking is skipped when config comes from the `mise_toml` / `tool_versions` inputs.

Make sure the lockfile covers the runner platforms before relying on it:

```bash
mise lock --platform linux-x64,linux-arm64,macos-arm64
```

## Caching

The default cache key combines the prefix, platform (OS, arch, and runner image such as `linux-x64-ubuntu24`, or `self-hosted`), mise version, config-file hash, `MISE_ENV`, install args, and bootstrap settings. Override with templates when needed:

```yaml
- uses: jdx/mise-action@v5
  with:
    cache_key: "{{default}}-${{ hashFiles('package-lock.json') }}"
```

Template variables: `{{version}}`, `{{cache_key_prefix}}`, `{{platform}}`, `{{file_hash}}`, `{{mise_env}}`, `{{install_args_hash}}`, `{{bootstrap_hash}}`, `{{default}}`, `{{env.VAR_NAME}}`, plus Handlebars conditionals (`{{#if version}}…{{/if}}`).

Rust installed through mise uses `rustup` and interacts badly with the cache; see [jdx/mise-action#215](https://github.com/jdx/mise-action/issues/215).

## Common Patterns

Matrix over OS with a pinned mise and restore-only cache on PRs:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
runs-on: ${{ matrix.os }}
steps:
  - uses: actions/checkout@v6
  - uses: jdx/mise-action@v5
    with:
      version: 2026.10.2
      cache_save: ${{ github.event_name != 'pull_request' }}
  - run: mise run ci
```

Config environment for CI (loads `mise.ci.toml`):

```yaml
env:
  MISE_ENV: ci
steps:
  - uses: jdx/mise-action@v5
```

Untrusted pull-request config (forks, bots): set `MISE_SAFE: 1` in the job `env` so template `exec()`, project `[env]`, hooks, and `postinstall` from the PR are refused or ignored. Safe mode also refuses `mise run`, so invoke commands directly in those jobs (see [advanced.md](advanced.md#safe-mode)).

Monorepo subproject: set `working_directory: services/api`, or use `mise run --affected` (see [workspaces-and-caching.md](workspaces-and-caching.md)), which reads GitHub Actions PR metadata for its base/head.

Remote task cache writes from GitHub OIDC need `permissions: id-token: write`; see [workspaces-and-caching.md](workspaces-and-caching.md).

## Upgrading From v4

v5 is breaking in one way: without `version`, the action now installs the newest stable mise release **at least 24 hours old** (previously the latest). Set `minimum_release_age: 0s` to restore v4 behavior, or pin `version` for reproducibility. v5.0.1 also verifies any cached/pre-installed mise binary against signed release checksums (or `sha256`) before running it, and reinstalls on mismatch instead of `mise self-update`.

## Without The Action

For runners where a third-party action is unwanted, commit a wrapper (`mise generate install-script -l -w`, see [advanced.md](advanced.md)) or install directly:

```yaml
- run: |
    curl https://mise.run | sh
    echo "$HOME/.local/share/mise/bin" >> "$GITHUB_PATH"
    echo "$HOME/.local/share/mise/shims" >> "$GITHUB_PATH"
- run: mise install --locked
```

## Troubleshooting

- `HTTP 403` / rate limit during install: ensure `github_token` is passed (default works unless overridden or the job's `permissions` strip it), or commit `mise.lock` so resolved URLs are reused.
- Fresh mise release not picked up: expected under the 24h `minimum_release_age`; pin `version` or set `0s`.
- `--locked` failure: the lockfile lacks the runner platform or a tool; run `mise lock --platform ...` locally and commit.
- Stale tools after config change: the config hash is in the key, so this usually means a custom `cache_key` omitted `{{file_hash}}`; bump `cache_key_prefix`.
- Env vars missing in later steps: check `env: true` and that the variable is set in `[env]` for the active `MISE_ENV`.
