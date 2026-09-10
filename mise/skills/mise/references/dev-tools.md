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
node = { version = "22", postinstall = "corepack enable", install_env = { CFLAGS = "-O2" } }
aws-cli = { version = "latest", symlink_bins = true }
"npm:prettier" = { version = "latest", allow_builds = ["esbuild"] }
```

`install_env` applies during download, install, and that tool's `postinstall`. `mise use --tool-option k=v <tool>` sets an option from the CLI.

Per-tool release-age policy overrides the global setting:

```toml
[settings]
minimum_release_age = "7d"

[tools.trivy]
version = "latest"
minimum_release_age = "1d"
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

Backend preference order:

1. `packslip` — Tier 1 and stable. Preferred when the publisher ships signed release manifests; verifies signer and artifact digests with no plugin and no separate package manager.
2. `aqua` — curated registry metadata, SLSA verification, per-version logic.
3. `github` / `gitlab` — release-based CLIs not in aqua.
4. Language package backends (`npm`, `pipx`, `cargo`, `go`, `gem`, `spm`, …) for ecosystem tools.
5. asdf or vfox plugins, only when no backend can model the tool.

```toml
[tools]
"packslip:github.com/jdx/hk" = "latest"
```

`packslip:` takes a host and path without `https://`; GitHub may be abbreviated (`packslip:jdx/hk`). Releases can carry version-matched completions, man pages, and agent skills. mise remembers accepted signers; inspect with `mise packslip pins` and reset one with `mise packslip forget <project>` only after confirming the publisher announced the change.

The `pkgx:` backend is experimental (`[settings] experimental = true`) and installs pantry packages by project name: `"pkgx:stedolan.github.io/jq" = "1.7.1"`.

### GitHub Asset Selection

```toml
[tools]
"github:oxc-project/oxc" = { version = "apps_v1.69.0", matching = "oxlint", rename_exe = "oxlint" }
```

- `matching` narrows candidates by case-sensitive substring while keeping platform autodetection; `matching_regex` does the same with a regex. Both are ignored (silently) when `asset_pattern` is set, because that replaces autodetection entirely.
- `additional_asset_patterns` overlays supplemental archives onto the primary asset's install directory.
- `github_attestations = false` disables attestation verification; `version_order = "semver"` changes tag ordering.

## npm Backend Safety

The `npm:` backend installs one global package at a time. The default `npm.package_manager = "auto"` uses mise's **embedded** `aube` — in-process, no node or package-manager CLI required. Setting it to `aube_cli`, `bun`, `pnpm`, or `npm` shells out to that tool, which must then be installed. `npm.shell_out = true` forces the npm CLI for metadata and installs.

Lifecycle scripts are install-time code execution. The backend-neutral approval option is `allow_builds`:

```toml
[tools]
"npm:some-tool" = { version = "latest", allow_builds = ["esbuild", "sharp"] }
```

How it is applied per package manager:

- `aube` (default) and `aube_cli`: written to the install's `aube.allowBuilds`. `allow_builds = true` allows every dependency build script.
- `pnpm`: one `--allow-build=<pkg>` flag per package (pnpm v10.4.0+). `allow_builds = true` passes `--dangerously-allow-all-builds`.
- `npm` 11.16.0+: passed as `--allow-scripts=<pkg>`; `allow_builds = true` passes `--dangerously-allow-all-scripts`. Older npm keeps `--ignore-scripts=true`.
- `bun`: `allow_builds` has no effect. mise never adds `--trust`; pass `bun_args = "--trust"` only when broad Bun trust is intended.

`aube_args` is **ignored** under the default embedded installer and only forwarded in `aube_cli` mode. `pnpm_args`, `bun_args`, and `npm_args` are raw extra args for their own package manager. Use `npm_args = "--ignore-scripts=false"` only when every package in the install graph may run lifecycle scripts.

Other aube-only options:

- `trust_policy_excludes = ["undici@^5"]` — reviewed exceptions to aube's `trustPolicy=no-downgrade`.
- `allow_low_downloads = true` — admit a package below aube's weekly-download threshold. A tool resolved from `mise.lock` is already exempt.

`minimum_release_age` is forwarded into transitive dependency resolution by the `npm:` and `pipx:` backends; the embedded aube installer honors it natively.

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
- `--checksum-algorithm sha256` when a consumer needs SHA256 (default is `blake3`); it cannot be combined with `--lock` or `--skip-download`.
- `--bootstrap` when the stub should install mise before running.
- `mise tool-stub ./bin/tool -- --version` for direct troubleshooting.

A `.cmd` launcher is written beside the stub whenever the stub could run on Windows, on every host platform, so a committed stub works for a Windows clone. Executing a stub tracks it in `~/.local/state/mise/tracked-stubs`, and `mise prune` keeps the tool versions a tracked stub needs.

For a machine-wide catalogue of ordinary tools the docs now steer to `lazy = true` in `[tools]` rather than standalone stubs; stubs remain right when the executable file itself must carry a portable tool definition.

## Lazy Tools And Wrappers

`lazy = true` installs a tool the first time one of its commands runs instead of during `mise install`:

```toml
[tools]
node = { version = "24", lazy = true }
"github:example/acme" = { version = "1.2.3", lazy = true, lazy_bins = ["acme", "acmectl"] }
```

Registry shorthands get bootstrap shims from registry `bins` metadata; explicit backends must list `lazy_bins`. A bare `mise install` skips lazy tools — use `mise install --include-lazy` or name the tool. Run `mise reshim` after editing a lazy declaration by hand.

`[wrappers]` routes a command through another program while keeping its name:

```toml
[wrappers]
terraform = "tofu"

[wrappers.python]
command = "uv"
args = ["run", "python"]
```

Run `mise reshim` after adding or removing a wrapper.

## Upgrade And Prune

```bash
mise upgrade                 # replaced versions are pruned after upgrade.prune_after (24h)
mise upgrade --no-prune      # keep the old install; same as upgrade.auto_prune = false
mise upgrade --prune         # uninstall the replaced version immediately
mise ls --prunable
mise prune --dry-run         # prints the exact paths that would be removed
mise install --include-task-tools
```

`-l` on `mise upgrade` is a deprecated shorthand for `--bump`; it becomes `--local` after mise 2027.8.5. Use `-b`/`--bump`.

## Version Files

mise reads `.tool-versions` and can use asdf plugins when needed. When migrating, prefer a `mise.toml` with `[tools]` because it also supports env vars, settings, tasks, options, and lockfiles.

Idiomatic version files (`.python-version`, `.nvmrc`, `package.json`, …) are disabled by default:

```bash
mise settings add idiomatic_version_file_enable_tools node
mise settings add idiomatic_version_file_disable_files node:package.json
```

mise reads fields that state the version a project is *built with*, not compatibility floors. `package.json` `devEngines` and `packageManager` are read; `engines` is not. In `go.mod`, `toolchain goX.Y.Z` is read while the `go X.Y` floor is deprecated and removed in mise 2026.11.0 (as is `cmake_minimum_required`); `idiomatic_version_file_ignore_minimum_versions` opts into the final behavior early.

## Ruby

mise installs a precompiled Ruby binary when one exists and otherwise falls back to compiling with `ruby-build`. Set `ruby.compile=false` on hosts without a build toolchain so installs fail loudly instead of falling back; `ruby.compile=true` forces source builds.

## Auto Install

`mise exec` and `mise run` can auto-install missing tools when auto-install settings are enabled. For deterministic CI, prefer:

```bash
mise install --locked
mise run test
```
