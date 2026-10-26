# Plugin Development

Use this reference when creating or reviewing mise plugins. For ordinary tool installation, prefer built-in registry/backends first; plugin development is for custom tool families, private tools, complex installation logic, or environment integrations.

## Choose Plugin Type

| Type | Use For | Key Files |
| --- | --- | --- |
| Backend plugin | One plugin manages multiple tools with `plugin:tool` names | `hooks/backend_list_versions.lua`, `hooks/backend_install.lua`, `hooks/backend_exec_env.lua` |
| Tool plugin | One plugin manages one tool with custom lifecycle hooks | `hooks/available.lua`, `hooks/pre_install.lua`, install/env hooks |
| Environment plugin | Provide env vars and PATH entries without tool versions | `hooks/mise_env.lua`, optional `hooks/mise_path.lua` |
| Package plugin | A machine-global manager for `[bootstrap.packages]` | `hooks/package_installed.lua`, `hooks/package_install.lua`, optional `package_upgrade`/`package_uninstall` |
| asdf plugin | An existing shell-based tool integration | asdf `bin/` scripts |

Prefer vfox-style plugins for new plugin work. vfox is cross-platform, uses Lua through mise's built-in runtime, and provides modules for common operations.

## Backend Plugins

Backend plugins support `plugin:tool` format:

```bash
mise plugin install my-plugin https://github.com/org/my-plugin
mise use my-plugin:some-tool@1.0.0
```

Minimal structure:

```text
my-backend-plugin/
├── metadata.lua
└── hooks/
    ├── backend_list_versions.lua
    ├── backend_install.lua
    └── backend_exec_env.lua
```

Implementation notes:

- `BackendListVersions` must return versions sorted ascending, oldest to newest. mise does not sort them afterward. An entry may be a table `{ version = "2.1.0", created_at = "2026-01-31T12:00:00Z" }` (RFC 3339) so `minimum_release_age` and `--before` apply — undated versions are never held back, so return dates when the registry has them. Moving names go in `aliases = { recommended = "9.10.3" }` next to `versions`; mise resolves `tool@recommended` to that version and locks it (older mise ignores the key).
- `BackendInstall` receives `ctx.tool`, `ctx.version`, `ctx.install_path`, `ctx.download_path`, and `ctx.options`.
- `BackendExecEnv` returns env vars such as PATH entries for the installed tool.
- Optional hooks: `BackendListTools` (`hooks/backend_list_tools.lua`, a small `{tools = {{name, description}}}` catalog surfaced in `mise search`, completion, and the `mise use` selector), `BackendSearchTools` (per-query search of a large catalog via `ctx.query`), and `BackendUninstall` (`hooks/backend_uninstall.lua`, cleanup outside `install_path` on uninstall/upgrade/prune; an error keeps the install).
- Shelling out: prefer `cmd.exec` (captured, never blocks parallel installs; accepts `{ timeout = 30 }` in seconds and raises on expiry). `os.execute` streams output and `cmd.stream` also connects stdin for interactive children; both hold mise's terminal lock.
- Use the official template when creating a new repository.

## Tool Plugins

Tool plugins manage one tool and fit custom installs, source builds, legacy version files, aliases, or complex env setup.

Required hooks include version listing and pre-install/download behavior. Use rolling release metadata and checksums when a channel like `nightly` or `stable` keeps the same version name but changes content.

Tool plugins can support attestations for downloaded artifacts; record verification in lockfiles when available. For SLSA provenance from a reusable workflow, also return `slsa_source_repository` (the publisher's `owner/repo`) and `slsa_source_tag` so another repository's or an older release's provenance cannot pass.

`Available` entries take an optional `created_at` (RFC 3339) release date for `minimum_release_age`. `PreInstall` may return a `headers` table (e.g. `Authorization`) next to `url`; mise sends it only to that URL's origin, drops it on cross-origin redirects, and never records it in `mise.lock`.

Every hook can use `RUNTIME.cacheDirPath` (2026.10.17), a per-plugin directory under `$MISE_CACHE_DIR/plugins/<name>` that survives plugin reinstalls but is wiped by `mise cache clear` — cope with it being empty or `nil`.

`ctx.options` carries typed tool options in the download, install, and env hooks. Declare build prerequisites so mise can report or install them (gated by the `system_deps` setting):

```lua
PLUGIN = {
  name = "php",
  systemDependencies = {
    { bin = "bison", version = ">=3.0",
      packages = { brew = "bison", apt = "bison", dnf = "bison" } },
    { pkgconfig = "libxml-2.0",
      packages = { brew = "libxml2", apt = "libxml2-dev", dnf = "libxml2-devel" } },
  },
}
```

Each entry names exactly one of `bin`, `pkgconfig`, `sharedlib`, or `command`; `packages` is a per-manager install hint.

## Package Plugins

A package plugin is a vfox plugin that manages host-owned state for `[bootstrap.packages]` rather than installing versioned tools under mise's data directory.

```text
mise-vscode-extensions/
├── metadata.lua
├── mise.plugin.toml          # [package-manager] declaration
└── hooks/
    ├── package_installed.lua
    ├── package_install.lua
    ├── package_upgrade.lua
    └── package_uninstall.lua
```

The `package_installed` + `package_install` pair is what identifies the repository as a package plugin; with only one it stays an ordinary vfox plugin, and adding `backend_install.lua` makes it a tool backend instead — package and tool-backend plugins must live in separate repositories.

Contracts: `PackageInstalled` must report state without prompting or making changes, versions are opaque strings, and the plugin must not use `sudo`.

## Environment Plugins

Environment plugins are activated from `[env]`:

```toml
[env]
_.my-env-plugin = {
  api_url = "https://prod.api.example.com",
  debug = false,
}
```

Minimal structure:

```text
my-env-plugin/
├── metadata.lua
└── hooks/
    ├── mise_env.lua
    └── mise_path.lua
```

`MiseEnv(ctx)` returns env var entries. `MisePath(ctx)` returns PATH directories. `ctx.options` contains the TOML options from `mise.toml`.

For expensive env plugins, return cache metadata and require users to enable env cache:

```toml
[settings]
env_cache = true
```

## Local Development

Use link/install commands against a local plugin checkout, then test all lifecycle operations:

```bash
mise plugin link my-plugin /path/to/my-plugin
mise ls-remote my-plugin:tool
mise use my-plugin:tool@1.0.0
mise exec -- tool --version
mise --debug install my-plugin:tool@1.0.0
```

For single-tool plugins, adjust command names to the plugin's non-`plugin:tool` format.

## Security

- Review plugin code before trusting or recommending it.
- Pin plugin repository URLs or refs for team config where reproducibility matters.
- Prefer backends or aqua/github registry entries when plugin behavior is unnecessary.
- Keep network calls, shell execution, and secret handling explicit and auditable.
