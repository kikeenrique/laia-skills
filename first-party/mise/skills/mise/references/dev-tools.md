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

`os = "unix"` matches every platform except Windows.

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

By default any workflow of the repository may sign a GitHub release. Pin the signing workflow on tags with `workflow` (a file name, or a list when the project moved its release workflow); it cannot be combined with `pubkey`, `identity`, `identity_prefix`, or `issuer`:

```toml
[tools]
"packslip:github.com/aubepkg/aube" = { version = "latest", workflow = ["release-plz.yml", "release.yml"] }
```

The experimental `pkgx:` backend was removed in mise 2026.9.13; move those tools to `packslip`, `aqua`, or `github`. The experimental `spinel:` backend (2026.10.2) compiles a Ruby CLI from GitHub source into a native binary and needs the `spinel` compiler and a C compiler; since 2026.10.5 its installs require `experimental = true`. It may be removed, so avoid it for team config.

### GitHub Asset Selection

```toml
[tools]
"github:oxc-project/oxc" = { version = "apps_v1.69.0", matching = "oxlint", rename_exe = "oxlint" }
```

- `matching` narrows candidates by case-sensitive substring while keeping platform autodetection; `matching_regex` does the same with a regex. Both are ignored (silently) when `asset_pattern` is set, because that replaces autodetection entirely.
- `additional_asset_patterns` overlays supplemental archives onto the primary asset's install directory.
- `github_attestations = false` disables attestation verification; `version_order = "semver"` changes tag ordering.

### Other Backend Options

```toml
[tools]
"aqua:domcyrus/rustnet" = { version = "latest", libc = "musl" }   # or "glibc"/"gnu"; strict, no fallback
"gem:internal-cli" = { version = "latest", source = "https://{{ env.GEM_TOKEN }}@gems.example.com/acme" }
"npm:@gmickel/gno" = { version = "2.3.0", allow_exotic_deps = ["xlsx"] }   # git/file/tarball deps aube blocks
"http:my-tool" = { version = "1.0.0", url = "file:///opt/archives/my-tool.tar.gz", checksum = "sha256:..." }
"http:polaris" = { version = "0.9.2", url = "https://ghcr.io/v2/acme/polaris/blobs/sha256:...", headers = { Authorization = "Bearer {{ env.GITHUB_TOKEN | b64_encode }}" } }
"npm:github:owner/repo" = "v1.2.0"   # git+https://, git://, github:, gitlab:, bitbucket:; version is the git ref
"pypi:azure-cli" = { version = "latest", with = ["pip"], dependency_prereleases = "allow" }
"pypi:ansible" = { version = "latest", expose = ["ansible-core"] }   # expose extra packages' entry points
```

- `pypi:` is the Python CLI backend (uv first, pipx fallback); `pipx:` remains a supported alias but is a distinct tool identity. `with`, `expose` (uv 0.8.5+), and `dependency_prereleases` (`disallow`/`allow`/`if-necessary`/`explicit`) need uv; `uvx = false` switches the tool to pipx.
- Git subdirectories use pip's fragment, quoted, with the ref after `@`: `mise use 'pypi:git+https://github.com/o/repo#subdirectory=cli@main'` (the `.git` suffix is optional; GitHub shorthand works too).
- aqua `libc` overrides the `libc` setting for that tool and is recorded in the lockfile; reinstall with `mise install --force` to switch an installed version.
- A `file://` URL is recorded in `mise.lock` as written, so it only works where that path exists.
- `http:` `headers` (templated values, e.g. bearer or `X-Api-Key`) go to the artifact, `version_list_url`, and `checksum_url` requests on the `url` host only; they are dropped on a cross-host redirect unless listed per header in `headers_forward = { X-Api-Key = ["cdn.example.com", "*.assets.example.com"] }`. Changing a token does not reinstall the tool.
- `npm:` git installs: `latest` is the repository's default branch; `mise.lock` does not pin it to a commit.

Find and filter: `mise search npm:<name>` also queries that package registry (`npm:`, `cargo:`, `gem:`, `dotnet:`), `mise search --all` searches every backend; `mise ls --backend go --backend cargo` filters and `mise ls --grouped` groups by backend.

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

`prune.exclude = ["node", "aqua:BurntSushi/ripgrep"]` (`MISE_PRUNE_EXCLUDE`) keeps every version of those tools from `mise prune`, `ls --prunable`, and post-upgrade pruning — for tools something outside mise reaches by install path (a virtualenv, an editor SDK). `mise uninstall` is unaffected.

Global tools can keep themselves current with the per-tool `auto_update` option, in **global config only**:

```toml
# ~/.config/mise/config.toml
[tools]
claude = { version = "latest", auto_update = true }   # every tool_update.check_duration (24h)
node = { version = "22", auto_update = "6h" }         # stays within 22.x; minimum 1h
```

When a shim or `mise x` is about to run the tool and the interval has passed, mise upgrades it first (warning and running the installed version on failure). Exact pins, offline, CI, and `locked = true` never update; tasks, `hook-env`, and plain PATH lookups under activation never update. A project that sets its own version of the tool is not updated. For background updates instead, declare `[bootstrap.services.mise-tool-update] builtin = "tool-update"` and run `mise bootstrap services apply`. Failures show in `mise doctor`. `mise use -g --tool-option auto_update=true node@22` writes the option.

### Install Layout

Experimental and opt-in: `install_layout = "identity"` (plus `experimental = true`) names each installation `installs/<label>-<hash>/` by backend, version, platform, and install-affecting options, with `installs/<tool>/<version>` kept as a link. Shorthand and full backend spellings then share one install, and variants of one version can coexist. Existing installs stay put; `mise installs migrate [--dry-run] [tool@version]` reinstalls them into the new layout. `mise installs ls [tool] [--json]` lists installations (`selected`, `pinned`, `shared`) and `mise installs select <installation>` picks the one requests without a lockfile use. `http:`, `rust`, and `dotnet` keep the legacy layout.

## Version Files

mise reads `.tool-versions` and can use asdf plugins when needed. When migrating, prefer a `mise.toml` with `[tools]` because it also supports env vars, settings, tasks, options, and lockfiles.

Idiomatic version files (`.python-version`, `.nvmrc`, `package.json`, …) are disabled by default:

```bash
mise settings add idiomatic_version_file_enable_tools node
mise settings add idiomatic_version_file_disable_files node:package.json
```

mise reads fields that state the version a project is *built with*, not compatibility floors. `package.json` `devEngines` and `packageManager` are read; `engines` is not. In `go.mod` (and `go.work`, which wins when a workspace is active), `toolchain goX.Y.Z` is read while the `go X.Y` floor is deprecated and removed in mise 2026.11.0 (as is `cmake_minimum_required`); `idiomatic_version_file_ignore_minimum_versions` opts into the final behavior early.

## Ruby

mise installs a precompiled Ruby binary when one exists and otherwise falls back to compiling with `ruby-build`. Set `ruby.compile=false` on hosts without a build toolchain so installs fail loudly instead of falling back; `ruby.compile=true` forces source builds.

## Java

**Breaking in 2026.10.5:** versions without a vendor prefix (`java@21`, `lts`, `latest`) now install Eclipse Temurin builds — `java.shorthand_vendor` defaults to `temurin` instead of `openjdk`, whose jdk.java.net builds stop at the next feature release (`java@21` was stuck on 21.0.2). Installed OpenJDK versions keep working, but `mise install --locked` fails on old shorthand lock entries. Keep OpenJDK with `java.shorthand_vendor = "openjdk"` or `java = "openjdk-21"`; move to Temurin with `mise lock --bump java` and commit. Temurin has no Java 9, 10, or 12–15 builds (use `openjdk-12` etc.), and shorthand versions now carry its build suffix (`21.0.12+101.0.LTS`).

## Auto Install

`mise exec` and `mise run` can auto-install missing tools when auto-install settings are enabled. The shell "command not found" handler (`not_found_auto_install`, default on) installs configured registry tools; `not_found_auto_install_registry = true` (default off) also installs an *unconfigured* tool when exactly one registry entry provides the command, adding it to the global config. For deterministic CI, prefer:

```bash
mise install --locked
mise run test
```
