# Advanced

Use this reference for lockfiles, trust, settings, CI, monorepos, and complex troubleshooting.

## Lockfiles

`mise.lock` pins exact versions, download URLs, checksums, and supported platform metadata. Lockfiles are not created automatically; generate them intentionally.

```toml
[settings]
lockfile = true
```

```bash
mise lock
mise lock --platform linux-x64,macos-arm64
mise install --locked
```

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

Be careful setting `locked = true` in project config: mise settings are global in scope and can affect globally configured tools too.

## Trust

Trusted config enables potentially dangerous features such as env vars, templates, and `path:` plugin versions.

```bash
mise trust --show
mise trust
mise trust --untrust
mise trust --ignore
```

Review config before trusting, especially from a new checkout or external repository.

## CI Pattern

```bash
mise --version
mise install --locked
mise run test
```

Use `mise lock --platform ...` before CI if lockfiles do not include the CI platform. Configure GitHub authentication when resolving uncached release metadata.

## Important Settings

Set through `mise settings key=value`, env vars, or config:

```toml
[settings]
jobs = 8
lockfile = true
locked = false
env_shell_expand = true
```

Useful env vars:

```bash
MISE_JOBS=1
MISE_ENV=ci
MISE_LOCKED=1
MISE_NO_CONFIG=1
MISE_NO_ENV=1
MISE_NO_HOOKS=1
```

## Monorepo Tasks

Monorepo tasks are experimental and require the experimental setting/env for current releases.

```toml
experimental_monorepo_root = true

[monorepo]
config_roots = [
  "packages/frontend",
  "packages/backend",
  "services/*",
]
```

Run namespaced tasks:

```bash
mise //packages/frontend:build
mise //...:test
mise '//packages/frontend:*'
```

Use `:` from inside a config root:

```bash
mise :build
```

Prefer explicit `[monorepo].config_roots`; automatic discovery is deprecated in the docs.

## Performance And Debugging

- Use `MISE_JOBS=1` or `mise --jobs 1 ...` for deterministic install/task ordering while debugging.
- Use `mise config` to inspect the merged config and loaded files.
- Use `mise env --json-extended` to inspect env source details.
- Use `MISE_NO_CONFIG=1`, `MISE_NO_ENV=1`, or `MISE_NO_HOOKS=1` to isolate config, env, or hook problems.
- Put `mise activate` late in shell rc files unless intentionally allowing later `PATH` changes to override mise.
