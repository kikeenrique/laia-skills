# Environments

Use this reference when setting environment variables, loading `.env` files, using templates, exporting env, or debugging missing variables.

## Basic Env Vars

```toml
[env]
NODE_ENV = "development"
API_URL = "http://localhost:3000"
```

Unset an inherited env var with `false`, or supply a fallback with `default`:

```toml
[env]
NODE_ENV = false
LOG_LEVEL = { default = "info" }
```

`{ default = ... }` keeps an existing non-empty value and only sets the variable when it is unset or empty. Values may be strings or integers.

## Env Directives

Structured directives live under the `_` table:

```toml
[env]
_.file = ".env"
_.file = { path = ".env.json", expand = true }
_.path = ["{{config_root}}/node_modules/.bin"]
_.python.venv = { path = ".venv", create = true }
```

Shell-style expansion is disabled by default inside structured JSON/YAML/TOML files so literal `$` survives; `expand = true` re-enables it. `_.file = { path = ".env", tools = true }` loads the file after tools define their env.

`_.file` resolves a relative path against the config root. Since 2026.10.12, `find_up = true` loads it from the current directory and every parent instead (root first, so a closer file wins; no effect on absolute paths). It works from global config, so one entry covers every project:

```toml
# ~/.config/mise/config.toml
[env]
_.file = [{ path = ".env", find_up = true }, { path = ".env.local", find_up = true }]
```

Dotenv quoting works as in a shell: single-quoted text is literal (backslashes included), adjacent quoted and unquoted parts are joined (`'it'\''s'` → `it's`), and an unpaired quote such as `O'Brien` is kept as written. Single-quote values that must keep their own quotes, such as JSON: `CONFIG='{"debug": true}'`. YAML values are read as written (`VERSION: 1.10` stays `1.10`, `ZIP: 02134` keeps its zero).

Deprecated spellings — do not emit these:

| Deprecated | Use | Removed |
| --- | --- | --- |
| `env.mise.*` | `env._.*` | 2026.12.0 |
| `value` / `values` in `_.file`/`_.path`/`_.source` | `path` (string or array) | 2026.12.0 |
| top-level `env_file`, `dotenv`, `env_path` | `env._.file`, `env._.path` | 2027.4.0 |
| `virtualenv` tool option | `env._.python.venv` | future release |

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
mise env --paths         # PATH entries mise manages (tool bin dirs, _.path), in PATH order (2026.10.11)
```

Use these to compare what mise would export with what the current shell actually contains.

## Templates And Expansion

Use Tera templates for values derived from config or env:

```toml
[env]
MY_PROJ_LIB = "{{config_root}}/lib"
LD_LIBRARY_PATH = "/some/path:{{env.MY_PROJ_LIB}}"
```

Useful vars: `config_root` (the project directory) and `config_source` (the template's own config file as an absolute path, unresolved through symlinks — pipe through `canonicalize` for the real file).

Platform functions: `arch()`, `os()`, `os_family()`, and since 2026.10.9 `libc()` (`gnu`/`musl`, honoring the `libc` setting) and `avx2()` (`yes`/`no`; non-x86-64 reports `yes`). Keywords rename the result, e.g. `{{ libc(gnu="", musl="-musl") }}` or `{{ avx2(yes="", no="-baseline") }}` in an `http:` URL. Both also work in `.miserc.toml`.

### Prompted `[vars]`

Since 2026.10.6 a `[vars]` entry with `prompt` is a per-machine answer, asked once and saved in `$MISE_STATE_DIR/vars.toml` (never in config or dotfiles history):

```toml
[vars.git_name]
default = "Ada Lovelace"
prompt = "Git author name"

[vars.git_email]
required = "Run mise vars prompt to set git_email"
prompt = "Git email"
```

```bash
mise vars                  # list vars and their sources (also `mise vars ls`)
mise vars prompt           # ask for every unanswered prompt var (`mise vars prompt git_name` for one)
mise vars git_name=Ada     # save an answer without a terminal
mise vars unset git_name   # forget it, to be asked again
```

Only `mise vars prompt` and `mise bootstrap --prompt-vars` ask; everything else uses the saved answer, then `default`, or fails like any `required` var. Precedence: process env > higher-precedence config value > saved answer > `default`. `prompt` works only in `[vars]`, not `[env]`.

Shell-style expansion (`$VAR`, `${VAR}`, `${VAR:-default}`) runs after Tera rendering and is **on by default**. `env_shell_expand = false` disables it:

```toml
[settings]
env_shell_expand = false
```

Undefined variables without a default are left unexpanded and warn.

### Tera v2

mise renders templates with Tera v2. v1 compatibility helpers start warning in mise 2026.10.0 and are removed in 2027.4.0. Common migrations: `trim_start_matches` → `trim_start`, `trim_end_matches` → `trim_end`, `slice(start=0, end=2)` → `items[0:2]`, `map(attribute="name")` → `[item.name for item in items]`, `as_str` → `str`, `escape` → `escape_html`.

Tera v2 adds slices, spread (`[first, ...rest]`), comprehensions, optional chaining (`env?.NODE_ENV or "development"`), and ternaries. Undefined-variable access is stricter and v1 macros are unsupported.

Escape hatch, preferred in shared config because older mise reads it as an ordinary variable:

```toml
[env]
MISE_TERA_V1 = true
```

The `[settings] tera_v1 = true` form also works. Both are removed in mise 2027.4.0.

## Safety

Treat env directives, templates, and sourced files as code-like behavior. Review config before using `mise trust`, and avoid committing secrets in `mise.toml`. Use local files or an external secrets workflow for developer-specific secrets. For per-task grants from fnox (`[secrets.fnox]`, task `secrets`, `mise run --secrets`), see the Secrets section in [tasks.md](tasks.md); `{{ secrets.X }}` is rejected in `[env]` and `[vars]`.
