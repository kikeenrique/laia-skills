# Environments

Use this reference when setting environment variables, loading `.env` files, using templates, exporting env, or debugging missing variables.

## Basic Env Vars

```toml
[env]
NODE_ENV = "development"
API_URL = "http://localhost:3000"
```

Unset an inherited env var with `false`:

```toml
[env]
NODE_ENV = false
```

CLI helpers:

```bash
mise set NODE_ENV=development
mise set
mise unset NODE_ENV
```

## Availability

mise env vars are available with:

- Activated shells using `mise activate`.
- `mise exec` / `mise x`.
- `mise run` tasks.
- Shims when shims are configured.
- One-off shells via `mise en`.

## Inspect And Export

```bash
mise env
mise env --json
mise env --json-extended
mise env --dotenv
mise env --redacted
```

Use these to compare what mise would export with what the current shell actually contains.

## Templates And Expansion

Use Tera templates for values derived from config or env:

```toml
[env]
MY_PROJ_LIB = "{{config_root}}/lib"
LD_LIBRARY_PATH = "/some/path:{{env.MY_PROJ_LIB}}"
```

Shell-style expansion is available through `env_shell_expand`:

```toml
[settings]
env_shell_expand = true

[env]
MY_PROJ_LIB = "{{config_root}}/lib"
LD_LIBRARY_PATH = "$MY_PROJ_LIB:${LD_LIBRARY_PATH:-}"
```

The docs note shell expansion is expected to become the default in a future release, so be explicit when behavior matters.

## Safety

Treat env directives, templates, and sourced files as code-like behavior. Review config before using `mise trust`, and avoid committing secrets in `mise.toml`. Use local files or an external secrets workflow for developer-specific secrets.
