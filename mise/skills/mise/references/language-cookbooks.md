# Language Cookbooks

Use this reference when applying official cookbook patterns to Node.js or Python projects. Prefer existing repo package manager, lockfile, and task names over copying examples directly.

## Node.js

Install Node locally or globally:

```bash
mise use node@22
mise use -g node@22
```

Expose local `node_modules/.bin` tools without `npx`:

```toml
[env]
_.path = ["{{config_root}}/node_modules/.bin"]
```

Typical Node project shape:

```toml
[tools]
node = "{{ env.NODE_VERSION | default(value='22') }}"

[env]
_.path = ["{{config_root}}/node_modules/.bin"]
NODE_ENV = "{{ env.NODE_ENV | default(value='development') }}"

[tasks.install]
alias = "i"
description = "Install npm dependencies"
run = "npm install"

[tasks.test]
alias = "t"
run = "npm test"

[tasks.build]
alias = "b"
run = "npm run build"
```

For pnpm/corepack workflows, use a postinstall hook or task to enable package-manager setup, then make dev/test/build tasks depend on an install task with `sources`/`outputs` tied to the lockfile:

```toml
[tools]
node = "22"

[hooks]
postinstall = "corepack enable"

[tasks.pnpm-install]
run = "pnpm install"
sources = ["package.json", "pnpm-lock.yaml", "mise.toml"]
outputs = ["node_modules/.pnpm/lock.yaml"]

[tasks.dev]
depends = ["pnpm-install"]
run = "pnpm dev"
```

## Python

For a plain Python project, use mise-managed Python plus a virtualenv env directive:

```toml
[tools]
python = "{{ get_env(name='PYTHON_VERSION', default='3.12') }}"
ruff = "latest"

[env]
_.python.venv = { path = ".venv", create = true }

[tasks.install]
alias = "i"
run = "uv pip install -r requirements.txt"

[tasks.test]
run = "pytest tests/"

[tasks.lint]
run = "ruff check src/"
```

For `uv` projects, mise detects `.python-version` but does not automatically use uv's virtualenv unless configured. Use one of:

```toml
[settings]
python.uv_venv_auto = "source"
# or:
# python.uv_venv_auto = "create|source"
```

or:

```toml
[env]
_.python.venv = { path = ".venv" }
```

Sync mise's Python with uv's `.python-version` when needed:

```bash
mise sync python --uv
```

Use `uv run --script` shebangs in TOML tasks or file tasks for script-local dependencies.

## General Pattern

- Put runtime versions in `[tools]`.
- Put local bin paths and virtualenv behavior in `[env]`.
- Put install/build/test/lint workflows in `[tasks]`.
- Use `sources` and `outputs` for dependency-install tasks so they skip when lockfiles are unchanged.
