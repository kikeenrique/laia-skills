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

## Release-Age And Provenance Policy

Use release-age policy with moving versions to avoid resolving brand-new upstream releases:

```toml
[settings]
minimum_release_age = "7d"
```

This pairs well with lockfiles: `minimum_release_age` delays adoption, then `mise.lock` records the vetted exact version and URLs. Some backends, including current `npm:` and `pipx:` paths, forward the cutoff into transitive dependency resolution when the selected package manager supports it.

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
env_shell_expand = true
minimum_release_age = "7d"
```

Useful env vars:

```bash
MISE_JOBS=1
MISE_ENV=ci
MISE_LOCKED=1
MISE_NO_CONFIG=1
MISE_NO_ENV=1
MISE_NO_HOOKS=1
MISE_EXPERIMENTAL=1
```

## MCP And Dependency Providers

`mise mcp` is experimental and requires `MISE_EXPERIMENTAL=1`. It exposes read-only resources such as tools, tasks, env, and config, and can run mise tasks through MCP-compatible assistants.

```bash
MISE_EXPERIMENTAL=1 mise mcp
```

`mise deps` is also experimental. Use it when the user explicitly wants mise to manage project dependency installs such as `npm install`, `uv sync`, `go mod download`, or custom generated outputs based on hashed sources.

```toml
[deps.npm]
auto = true

[deps.codegen]
sources = ["schema/*.graphql", "codegen.yml"]
outputs = ["src/generated/"]
run = "npm run codegen"
```

Auto providers run before `mise x` and `mise run`; keep this explicit because dependency installs can execute package-manager code and affect task latency.

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
