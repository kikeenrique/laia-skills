# Plugins

Use this reference when installing plugins, choosing between plugins and backends, or authoring plugin guidance.

## Default Recommendation

Avoid tool plugins when a built-in backend, registry alias, aqua, github, gitlab, or language package backend can install the tool. Plugins are still useful when a tool needs custom installation logic, global env/path behavior, or version aliases that backends cannot provide.

## End-User Commands

```bash
mise plugins
mise plugins ls --urls
mise plugin install my-plugin https://github.com/username/my-plugin
mise install my-plugin:some-tool@1.0.0
mise use my-tool@latest
```

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
```

Use `mise plugin install <name> <url>` for one-off installs.

## Tool Options For Plugins

Tool options in `[tools]` are passed to plugin scripts as environment variables:

```toml
[tools]
python = { version = "3.11", virtualenv = ".venv" }
```

Plugins receive options in names like `MISE_TOOL_OPTS__VIRTUALENV`.

## Security Posture

- Review plugin repositories before recommending `mise plugin install`.
- Prefer pinned URLs or refs for team config when trust or reproducibility matters.
- Remember that plugin and template behavior can require trusted config.
