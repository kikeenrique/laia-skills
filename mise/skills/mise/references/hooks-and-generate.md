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

Rules that catch agents out:

- `run` and `run_windows` must be **strings**. `run = ["echo one", "echo two"]` is not supported — use multiple hook entries, or one multiline `run` string for a single subprocess.
- Every matching hook from every loaded config runs, highest-precedence config first (so `conf.d/c.toml` before `conf.d/a.toml`). Put order-dependent hooks in one array.
- Add `shell = "bash -c"` to a `run` table to pick the inline shell; the value must include the eval argument.

```toml
[hooks]
postinstall = { run = "pwd", run_windows = "cd" }
```

On Windows mise uses `run_windows` when set; elsewhere a hook with only `run_windows` is skipped.

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

Project-level `postinstall` receives `MISE_INSTALLED_TOOLS` as JSON. It also runs when `mise install` finds nothing to install, with `MISE_INSTALLED_TOOLS="[]"` — guard on that if the hook should only act on real installs.

`preinstall`/`postinstall` run with the project root as cwd; the invocation directory stays in `MISE_ORIGINAL_CWD`.

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

[[watch_files]]
patterns = ["scripts/*.sh"]
run = "shellcheck scripts/*.sh"
shell = "bash -c"
```

Each `[[watch_files]]` entry should set either `run` or `task`, not both. Watch hooks receive `MISE_WATCH_FILES_MODIFIED`.

## Shell Hooks

Shell hooks execute in the current shell:

```toml
[hooks.enter]
shell = "bash"
script = ["source completions.sh", "export PROJECT_READY=1"]
```

Here `shell` is a shell **name** (`bash`, `zsh`, `fish`), not an inline shell command, and `script`/`scripts` may be arrays. mise only emits the script when the active `mise activate` shell matches. Only `enter`, `leave`, and `cd` can be current-shell hooks.

On `preinstall`/`postinstall`, `script`/`scripts` are deprecated legacy aliases for `run`, and a `shell` set alongside them is ignored with a warning. Use `run = "..."` with `shell = "bash -c"` there.

Do not use shell hooks for state that must be cleaned up on leave. Use `[env]` when mise should manage environment changes.

## Generate

`mise generate` creates files for related tools and services:

```bash
mise generate install-script --write ./bin/mise
mise generate install-script -l -w            # localize state under .mise/, write ./bin/mise
mise generate install-script --write ./bin/mise --windows
mise generate config --dry-run
mise generate devcontainer
mise generate git-pre-commit
mise generate github-action
mise generate task-docs
mise generate task-stubs
mise generate tool-stub ./bin/my-tool --url https://example.com/tool.tar.gz
mise generate tool-stub ./bin/my-tool --lock
mise generate tool-stub ./bin/bootstrap-tool --url https://example.com/tool.tar.gz --bootstrap --bootstrap-version 2026.9.4
```

`mise generate install-script` writes a committable wrapper that downloads mise for contributors who do not have it. It was renamed from `mise generate bootstrap`; the old name still works but is deprecated and removed in mise 2027.9.0.

It is **not** `mise bootstrap`, which is declarative machine setup — see [bootstrap.md](bootstrap.md). `--windows` additionally writes a `<WRITE>.cmd` launcher (requires `--write`, generated on any host). `-l/--localize` keeps mise's binary, tools, cache, and state under `.mise/`; gitignore that directory.

Use `--dry-run` when available before writing generated files. Review generated CI/devcontainer files for project-specific paths, shells, and lockfile expectations.

For HTTP tool stubs, `mise generate tool-stub` can download archives to detect checksums and binary paths, append platform-specific URLs to existing stubs, fetch missing checksum data with `--fetch`, embed locked platform data with `--lock`, and choose `--checksum-algorithm sha256` instead of the default `blake3`.
