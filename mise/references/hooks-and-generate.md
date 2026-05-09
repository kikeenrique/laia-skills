# Hooks And Generate

Use this reference when configuring lifecycle hooks, file watchers, or generated support files for CI, devcontainers, docs, and stubs.

## Hooks

Hooks are configured in `mise.toml`. Most hooks require `mise activate`; `preinstall` and `postinstall` also run without shell activation.

```toml
[hooks]
enter = "echo entering project"
leave = "echo leaving project"
cd = "echo directory changed"
preinstall = "echo before install"
postinstall = "echo after install"
```

Use hooks sparingly. They run code automatically, so treat them as trust-sensitive and prefer explicit tasks for complex setup.

## Tool-Level Postinstall

Run a command immediately after a specific tool installs:

```toml
[tools]
node = { version = "22", postinstall = "corepack enable" }
```

Tool-level postinstall commands receive:

- `MISE_TOOL_NAME`
- `MISE_TOOL_VERSION`
- `MISE_TOOL_INSTALL_PATH`

Project-level `postinstall` receives `MISE_INSTALLED_TOOLS` as JSON.

## Task Hooks

Prefer task references when hook logic belongs in the task system:

```toml
[tasks.setup]
run = "echo setting up project"
depends = ["install-deps"]

[hooks]
enter = { task = "setup" }
```

Arrays can mix inline scripts and task references:

```toml
[hooks]
enter = ["echo entering", { task = "setup" }]
```

## Watch Files

Run a script or task when files change during an activated session:

```toml
[[watch_files]]
patterns = ["src/**/*.rs"]
run = "cargo fmt"

[[watch_files]]
patterns = ["uv.lock"]
task = "sync-deps"
```

Each `[[watch_files]]` entry should set either `run` or `task`, not both. Watch hooks receive `MISE_WATCH_FILES_MODIFIED`.

## Shell Hooks

Shell hooks execute in the current shell:

```toml
[hooks.enter]
shell = "bash"
script = "source completions.sh"
```

Do not use shell hooks for state that must be cleaned up on leave. Use `[env]` when mise should manage environment changes.

## Generate

`mise generate` creates files for related tools and services:

```bash
mise generate bootstrap
mise generate config --dry-run
mise generate devcontainer
mise generate git-pre-commit
mise generate github-action
mise generate task-docs
mise generate task-stubs
mise generate tool-stub ./bin/my-tool
```

Use `--dry-run` when available before writing generated files. Review generated CI/devcontainer files for project-specific paths, shells, and lockfile expectations.
