# Configuration

Use this reference when editing `mise.toml`, deciding file locations, debugging precedence, or using config environments.

## Config Files

Project paths, highest precedence first:

- `mise.local.toml`: local overrides; do not commit.
- `mise.toml`: normal project config.
- `mise/config.toml`
- `mise/conf.d/*.toml`
- `.mise/config.toml`
- `.mise/conf.d/*.toml`
- `.config/mise.toml`
- `.config/mise/config.toml`
- `.config/mise/conf.d/*.toml`

All non-hidden TOML files in a `conf.d/` directory load in alphabetical order. Dotted fragment names such as `x.base.toml` are deprecated — rename them with hyphens before mise 2027.8.10, when the suffix after the first dot starts selecting an environment.

A folder inside any `conf.d/` (global, system, or project) is also a fragment: mise reads only its `mise.toml`, `mise.local.toml`, `mise.<env>.toml`, and `mise.<env>.local.toml` (not recursively), and the folder is the config root for its relative paths, `{{ config_root }}`, and tasks. Folder fragments load after single-file fragments in the same directory. It replaces the deprecated `[bootstrap].config_roots` (move `bundles/git` to `mise/conf.d/git`, or symlink it).

`include` merges a remote fragment into the including file, ranked just below it:

```toml
include = [
  "git::https://github.com/myorg/platform.git//mise.toml?ref=main",
  "oci::ghcr.io/myorg/platform-config@sha256:<digest>",
]
```

Included files cannot nest `include`, set `[settings]` or monorepo keys, or define `[tasks]` (use `task_config.includes`). They follow the including file's trust; paranoid mode requires a full commit sha or OCI digest. Fetched fragments are cached under `MISE_CACHE_DIR`.

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
- `[tasks]`: task definitions replace by task name. A metadata-only definition overlays an existing task instead of replacing its command.
- `[settings]`: additive, with overrides.

## Target File For Writes

`mise use`, `mise set`, and `mise unset` write to the **lowest-precedence file in the highest-precedence directory**. With both `mise.toml` and `mise.local.toml` present, writes go to `mise.toml`. Agents get this wrong often.

```bash
mise use node@22              # writes mise.toml
mise use --env local node@20  # writes mise.local.toml
mise use --path ./sub/mise.toml node@22
```

`mise config get` / `mise config set` instead default to the highest-precedence loaded TOML file, which can be `mise.local.toml`; use their `-f`/`--file` flag to pick one. `mise set`/`mise unset` also take `--file`, and `mise unuse` takes `--path` (aliased `--file`) and defaults to the first loaded config declaring the tool. `mise use` is the exception: it has only `-p`/`--path` — `-f` there is `--force`.

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
"vfox-backend:myplugin" = "https://github.com/jdx/vfox-npm"
```

`[plugins]` replaces the deprecated `settings.shorthands_file` / `MISE_SHORTHANDS_FILE` mechanism. Put shared shortname-to-backend or shortname-to-URL entries here; use `mise plugin install <name> <url>` for one-off local installs.

Use `[tool_alias]` for version aliases and `[shell_alias]` for shell aliases. The old `[alias]` spelling still works but is deprecated:

```toml
[tool_alias.node.versions]
lts = "22"

[shell_alias]
dev = "mise run dev"
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

For a personal selection, use an untracked `.miserc.local.toml` in the project (add it to your global git ignore), or `miserc.local.toml` in `MISE_CONFIG_DIR` for the whole machine. Local files override only the fields they set (`env` replaces the list; `env = []` clears it). Lookup order: each directory upward (`.miserc.local.toml`, `.miserc.toml`, `.config/miserc.toml`), then `~/.config/mise/miserc.local.toml`, `~/.config/mise/miserc.toml`, `/etc/mise/miserc.toml`. `-E`/`MISE_ENV` still win, and `--no-config` skips miserc discovery.

Precedence for env-specific local files:

1. `mise.<env>.local.toml`
2. `mise.local.toml`
3. `mise.<env>.toml`
4. `mise.toml`

### conf.d Environments

Environment suffixes inside `conf.d/` are opt-in until mise 2027.8.10. Enable with `env_conf_d = true` in a `.miserc.toml` (or `MISE_ENV_CONF_D=true`) — it controls config discovery, so setting it in `mise.toml` is too late:

```text
mise/conf.d/tools.toml                    # always loaded
mise/conf.d/tools.local.toml              # always loaded, usually gitignored
mise/conf.d/tools.development.toml        # MISE_ENV=development
mise/conf.d/tools.development.local.toml  # MISE_ENV=development, gitignored
```

Set `env_conf_d = false` explicitly to keep the old behavior without the deprecation warning.

### Platform Environments

With `auto_env` enabled, mise treats `{os_family}` (`unix`), `{os}` (`linux`/`macos`/`windows`), and `{os}-{arch}` (`macos-arm64`, `linux-x64`, …) as active environments, loading `mise.macos-arm64.toml` and selecting the matching lockfile. Precedence is `unix` < `{os}` < `{os}-{arch}` < explicit `MISE_ENV`.

`auto_env` is disabled by default, warns about newly loadable platform files from 2026.12.0, and becomes default-on in 2027.6.0. Like `MISE_ENV`, it must be set in `.miserc.toml` or via `MISE_AUTO_ENV`. Platform environments affect only config/lockfile discovery — they are not added to `MISE_ENV` or `{{ mise_env }}`.

## Version Requirements

Use `min_version` when config depends on newer mise behavior:

```toml
min_version = "2026.5.0"
# or
min_version = { hard = "2026.5.0", soft = "2026.9.0" }
```

A plain string or a soft-only table (`{ soft = "2026.9.0" }`) is also valid. A soft minimum warns and continues; a hard minimum errors. Use hard requirements sparingly; they block older clients.
