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
```

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

## asdf Compatibility

mise reads `.tool-versions` and can use asdf plugins when needed. When migrating, prefer creating a `mise.toml` with `[tools]` because it also supports env vars, settings, tasks, options, and lockfiles.

## Auto Install

`mise exec` and `mise run` can auto-install missing tools when auto-install settings are enabled. For deterministic CI, prefer:

```bash
mise install --locked
mise run test
```
