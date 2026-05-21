# Dev Tools

Use this reference when managing language runtimes, CLIs, tool versions, registry entries, backends, or migration from asdf.

## Common Commands

```bash
mise use node@22          # install and write local mise.toml
mise use -g node@22       # install and write global config
mise install              # install all tools in active config
mise install node@22      # install one tool version without changing config
mise exec -- node -v      # run with active mise environment
mise x python@3.12 -- python script.py
mise ls --current
mise ls-remote node
mise latest node@22
mise generate tool-stub ./bin/gh --url https://example.com/gh.tar.gz
```

`mise use` is usually the best user-facing command because it installs, activates for the current directory, and updates config.

## Tool Config

```toml
[tools]
node = "22"
python = "3.12"
ruby = "latest"
"pipx:ruff" = { version = "latest", depends = ["python"] }
```

Use object form for install options:

```toml
[tools]
node = { version = "22", postinstall = "corepack enable" }
aws-cli = { version = "latest", symlink_bins = true }
"npm:prettier" = { version = "latest", npm_args = "--ignore-scripts=false" }
```

`depends` controls install ordering for tools in the current config; it does not add hook-time PATH entries for vfox plugin hooks.

Use `os` restrictions for platform-specific tools:

```toml
[tools]
mytool = { version = "latest", os = ["linux/x64", "macos/arm64"] }
```

## Backends

Prefer registry names when available:

```bash
mise use aws-cli
```

Use full backend names when a registry alias does not exist:

```toml
[tools]
"aqua:hashicorp/terraform" = "1.8"
"github:cli/cli" = "latest"
"npm:prettier" = "latest"
"pipx:black" = "latest"
"cargo:cargo-edit" = "latest"
```

Backend guidance:

- Prefer `aqua` for new registry-backed tools because it avoids plugins and supports strong verification features.
- Use `github` or `gitlab` for release-based CLIs not available in aqua.
- Use language package backends (`npm`, `pipx`, `cargo`, `go`, `gem`, `spm`, etc.) for ecosystem tools.
- Use asdf or vfox plugins when a backend cannot model the tool or the plugin must provide custom env/path behavior.

## npm Backend Safety

The `npm:` backend installs one global package at a time. With the default package manager setting, mise uses `aube` when available and otherwise falls back to `npm`.

Lifecycle scripts are install-time code execution:

- `aube` follows a package-level build approval model. Pass reviewed builds with `aube_args = "--allow-build=<pkg>"`.
- `pnpm` supports package-level build approvals via `pnpm_args = "--allow-build=<pkg>"` on supported versions.
- `bun` does not get `--trust` automatically. Add `bun_args = "--trust"` only when broad Bun trust is intended.
- `npm` gets `--ignore-scripts=true` by default. Add `npm_args = "--ignore-scripts=false"` only when every package in the install graph may run lifecycle scripts.

```toml
[settings]
minimum_release_age = "7d"

[tools]
"npm:some-tool" = { version = "latest", aube_args = "--allow-build=esbuild" }
"npm:legacy-tool" = { version = "latest", npm_args = "--ignore-scripts=false" }
```

When `minimum_release_age` is set, current npm backend paths forward the cutoff into package-manager dependency resolution when the selected package manager supports it.

## Tool Stubs

Tool stubs are executable files with embedded TOML interpreted by `mise tool-stub`. They are useful for lazy-loading project-local tools and HTTP-distributed binaries.

```bash
mise generate tool-stub ./bin/rg \
  --platform-url linux-x64:https://example.com/rg-linux.tar.gz \
  --platform-url https://example.com/rg-aarch64-apple-darwin.tar.gz
mise generate tool-stub ./bin/rg --lock
```

Generated HTTP stubs can include platform URLs, checksums, binary paths, and a `[lock]` section. Use:

- `--fetch` to fill missing checksums/sizes for an existing stub.
- `--lock` to pin exact version and platform URLs/checksums.
- `--bootstrap` when the stub should install mise before running.
- `mise tool-stub ./bin/tool -- --version` for direct troubleshooting.

## asdf Compatibility

mise reads `.tool-versions` and can use asdf plugins when needed. When migrating, prefer creating a `mise.toml` with `[tools]` because it also supports env vars, settings, tasks, options, and lockfiles.

## Auto Install

`mise exec` and `mise run` can auto-install missing tools when auto-install settings are enabled. For deterministic CI, prefer:

```bash
mise install --locked
mise run test
```
