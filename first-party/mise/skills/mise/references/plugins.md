# Plugins

Use this reference when installing plugins, choosing between plugins and backends, or authoring plugin guidance.

## Default Recommendation

Avoid tool plugins when a built-in backend or registry alias can install the tool. For release binaries prefer `packslip` when the publisher provides signed manifests, then `aqua`, then `github`/`gitlab`. Plugins are still useful when a tool needs custom installation logic, global env/path behavior, or version aliases that backends cannot provide.

New asdf and vfox tool plugins are not accepted into the mise registry.

## End-User Commands

```bash
mise plugins
mise plugins ls --urls
mise plugin install my-plugin https://github.com/username/my-plugin
mise plugin install my-plugin 'https://github.com/username/my-plugin#v1.0.0'
mise plugins install vfox:PLUGIN_NAME 'packslip:OWNER/REPO#PLUGIN_VERSION'
mise install my-plugin:some-tool@1.0.0
mise use my-tool@latest
```

Append `#<ref>` to pin a Git revision; use a commit id when the source must be immutable. The `packslip:` form installs a signed, portable plugin archive and records the resolved version, artifact digest, and signer.

## Plugin Types

Backend plugins:

- Provide multiple tools through `plugin:tool` names.
- Offer install, version listing, env, and path behavior through a plugin backend.
- Work well for modern multi-tool integrations.

Tool plugins:

- Manage one tool.
- Use hooks such as install, list versions, env, and path.
- Provide full control when standard backends are insufficient.

Environment plugins:

- Provide env vars and PATH modifications without managing tool versions.
- Activate via `[env]` using `_.<plugin-name>` syntax.

```toml
[env]
_.my-env-plugin = { api_url = "https://api.example.com", debug = true }
```

Package plugins:

- Provide a machine-global package manager for `[bootstrap.packages]`, not versioned tools.
- Register in `[bootstrap.plugins]`, or install as `package:<name>`, before declaring packages.

asdf plugins:

- Supported for compatibility.
- Usually slower and less portable than modern backends.
- Best kept as a fallback.

## Configured Plugin Sources

Use `[plugins]` to override plugin shortnames for new plugin installs:

```toml
[plugins]
elixir = "https://github.com/my-org/mise-elixir.git"
"vfox-backend:myplugin" = "https://github.com/jdx/vfox-npm"
example = "./plugins/mise-example"
```

Absolute, `~/`, and explicit `./`/`../` paths are supported; relative paths resolve against the declaring config's root, and local plugins are symlinked so edits apply immediately. `[plugins]` only affects new installs — use `mise plugins install --force <name>` to replace an existing one, or `mise plugin install <name> <url>` for a one-off.

## Tool Options For Plugins

Tool options in `[tools]` reach vfox plugin hooks as typed `ctx.options`:

```toml
[tools]
"my-plugin:mytool" = { version = "1.2.3", edition = "2024" }
```

Options are also exposed as `MISE_TOOL_OPTS__EDITION`-style variables, scoped to hook execution and not exported into the tool's environment. Prefer typed `ctx.options`, available in the download, install, and env hooks.

## Security Posture

- Review plugin repositories before recommending `mise plugin install`.
- Prefer pinned URLs or refs for team config when trust or reproducibility matters.
- Remember that plugin and template behavior can require trusted config.
