# Configuration

Use this reference when editing `mise.toml`, deciding file locations, debugging precedence, or using config environments.

## Config Files

Common project paths include:

- `mise.local.toml`: local overrides; do not commit.
- `mise.toml`: normal project config.
- `mise/config.toml`
- `.mise/config.toml`
- `.config/mise.toml`
- `.config/mise/config.toml`
- `.config/mise/conf.d/*.toml`

Dot-prefixed forms such as `.mise.toml` are also accepted. Use the CLI for the installed version's exact resolution:

```bash
mise cfg
mise config
```

## Hierarchy And Merge Behavior

mise walks up from the current directory, finds config files, and merges broad parent config with more specific child config. Closer config wins on conflicts.

Merge behavior:

- `[tools]`: additive, with child values overriding matching tools.
- `[env]`: additive, with child values overriding matching keys.
- `[tasks]`: task definitions replace by task name.
- `[settings]`: additive, with overrides.

## Core Sections

```toml
[tools]
node = "22"
python = { version = "3.12", os = ["macos", "linux"] }

[env]
NODE_ENV = "development"

[tasks.test]
description = "Run tests"
run = "npm test"

[settings]
lockfile = true
```

Use `[plugins]` only when pinning or overriding plugin repositories for future plugin installs:

```toml
[plugins]
elixir = "https://github.com/my-org/mise-elixir.git"
```

## Config Environments

Use environment-specific config files for variants such as development, test, production, or CI:

```text
mise.toml
mise.development.toml
mise.test.toml
mise.ci.toml
mise.local.toml
mise.test.local.toml
```

Activate them with:

```bash
mise -E test run test
MISE_ENV=ci mise install
```

Or set early config in `.miserc.toml`:

```toml
env = ["development"]
```

`MISE_ENV` cannot be set in `mise.toml` because it decides which config files are loaded. Multiple environments can be comma-separated, with later ones taking precedence.

Precedence for env-specific local files:

1. `mise.<env>.local.toml`
2. `mise.local.toml`
3. `mise.<env>.toml`
4. `mise.toml`

## Version Requirements

Use `min_version` when config depends on newer mise behavior:

```toml
min_version = { hard = "2026.5.0", soft = "2026.4.0" }
```

Use hard requirements sparingly; they block older clients.
