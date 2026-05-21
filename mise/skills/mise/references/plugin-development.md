# Plugin Development

Use this reference when creating or reviewing mise plugins. For ordinary tool installation, prefer built-in registry/backends first; plugin development is for custom tool families, private tools, complex installation logic, or environment integrations.

## Choose Plugin Type

| Type | Use For | Key Files |
| --- | --- | --- |
| Backend plugin | One plugin manages multiple tools with `plugin:tool` names | `hooks/backend_list_versions.lua`, `hooks/backend_install.lua`, `hooks/backend_exec_env.lua` |
| Tool plugin | One plugin manages one tool with custom lifecycle hooks | `hooks/available.lua`, `hooks/pre_install.lua`, install/env hooks |
| Environment plugin | Provide env vars and PATH entries without tool versions | `hooks/mise_env.lua`, optional `hooks/mise_path.lua` |

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

- `BackendListVersions` must return versions sorted ascending, oldest to newest. mise does not sort them afterward.
- `BackendInstall` receives `ctx.tool`, `ctx.version`, `ctx.install_path`, `ctx.download_path`, and `ctx.options`.
- `BackendExecEnv` returns env vars such as PATH entries for the installed tool.
- Use the official template when creating a new repository.

## Tool Plugins

Tool plugins manage one tool and fit custom installs, source builds, legacy version files, aliases, or complex env setup.

Required hooks include version listing and pre-install/download behavior. Use rolling release metadata and checksums when a channel like `nightly` or `stable` keeps the same version name but changes content.

Tool plugins can support attestations for downloaded artifacts; record verification in lockfiles when available.

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
