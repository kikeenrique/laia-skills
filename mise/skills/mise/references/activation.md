# Activation

Use this reference when deciding how mise should load tools, PATH, and environment variables in shells, scripts, IDEs, or CI.

## Choose The Activation Mode

| Mode | Best For | Notes |
| --- | --- | --- |
| `mise activate <shell>` | Interactive terminals | Runs shell hooks so PATH and env update as directories/config change. |
| `mise activate <shell> --shims` | IDEs, login shells, simple non-interactive PATH setup | Adds shims to PATH; env vars and most hooks have limitations. |
| `mise exec -- <cmd>` / `mise x -- <cmd>` | Scripts, CI, one-off commands | Runs one command inside the mise context without relying on prompt hooks. |
| `mise env -s <shell>` | Integrating with another tool | Prints shell code to evaluate for a one-time activation. |
| `mise run <task>` | Project workflows | Runs tasks with mise tools and env loaded. |

## Interactive Shells

Put normal activation near the end of the interactive shell rc file:

```bash
eval "$(mise activate zsh)"
```

For bash and zsh, the docs recommend combining shims in profile/login files with PATH activation in interactive rc files when non-interactive contexts also need tool shims:

```bash
eval "$(mise activate zsh --shims)" # e.g. ~/.zprofile
eval "$(mise activate zsh)"         # e.g. ~/.zshrc
```

`mise activate` removes the shim directory from PATH when it takes over, so this combination is intentional.

## Shims

Shims are small executables under the mise shims directory, commonly `~/.local/share/mise/shims`. They route commands through mise so the correct tool version is selected.

Use shims when:

- An IDE or GUI app needs a stable PATH.
- A non-interactive shell will not display prompts.
- You only need tool binaries, not full shell-hook behavior.

Limitations:

- Env vars from `[env]` are loaded when a shim is called, not into the shell by itself.
- `cd`, `enter`, `leave`, and `watch_files` hooks require `mise activate`; `preinstall` and `postinstall` do not.
- `which node` may show the shim; use `mise which node` to find the real executable.

Run `mise reshim` only when the shim directory is missing expected executables. mise normally updates shims during installs, updates, and removals.

## Non-Interactive Shells

`mise activate` works by running `mise hook-env` around shell prompts. In scripts, prompts are not displayed, so prefer:

```bash
mise exec -- npm test
mise x -- ./script.sh
mise run test
```

If a script genuinely needs to mutate its current shell environment, explicitly evaluate `mise env` or `mise hook-env`, but prefer `mise exec`/`mise run` for simpler behavior.

## Debugging Activation

```bash
mise doctor
mise config
mise env --json-extended
mise which node
mise hook-env
```

If activation appears stale after editing config, trigger a new prompt, change directories, or run a fresh `mise exec -- <command>`.
