# Bootstrap

Use this reference when mise should set up a whole machine — OS packages, shell activation, repos, services, macOS defaults — not just a project's `[tools]`.

`mise bootstrap` (alias `bs`) is stable and is **not** the same as `mise generate install-script` (the old `mise generate bootstrap`, which only emits a script that downloads mise). See [hooks-and-generate.md](hooks-and-generate.md) for that generator.

`mise bootstrap` is declared `Effect: destructive`. It only runs when invoked explicitly; nothing here happens during `mise install` or `mise run`.

## Safety Workflow

Always in this order:

```bash
mise trust
mise bootstrap --dry-run
mise bootstrap plan
mise bootstrap
mise bootstrap status
```

- A dry run inspects state and prints proposed actions; hooks and the `bootstrap` task do not execute.
- `--yes` skips confirmation prompts for unattended runs.
- Bootstrap is a sequence, not a transaction. If a later phase fails, earlier changes stay applied; fix and re-run.
- Declarative parts converge, but hooks and `[tasks.bootstrap]` run on every apply, so make them idempotent.
- Dotfile conflicts are refused by default; `--force-dotfiles` replaces conflicting whole-file targets.

## Minimal Dev Machine

```toml
[bootstrap.mise_shell_activate]
zprofile = "shims"
zshrc = "activate"

[bootstrap.packages]
"brew:ripgrep" = "latest"
"brew-cask:firefox" = { os = "macos" }

[tools]
node = "24"

[tasks.bootstrap]
run = "node --version"
```

Machine-wide software goes in `[bootstrap.packages]`; per-project, version-switched tools stay in `[tools]`. Bootstrap packages get no shims and are not swapped when changing directories.

## Section Map

| Config | Use for |
| --- | --- |
| `[bootstrap.packages]` | OS packages, keyed `"manager:package"` |
| `[bootstrap.plugins]` | Package-manager plugins (register before their packages) |
| `[bootstrap.repos]` | Git repos cloned before dotfiles apply |
| `[dotfiles]` | Dotfiles — top level, not under `[bootstrap]`; see [dotfiles.md](dotfiles.md) |
| `[bootstrap.mise_shell_activate]` | Activation snippets in shell startup files |
| `[bootstrap.macos.defaults]`, `[bootstrap.macos.launchd.agents]` | macOS preferences and LaunchAgents |
| `[bootstrap.linux.systemd.units]`, `[bootstrap.linux.firewall]` | Linux user units and host firewall |
| `[bootstrap.files]`, `[bootstrap.directories]` | Managed paths, content, ownership, permissions |
| `[bootstrap.users]`, `[bootstrap.groups]` | Linux service accounts and groups |
| `[bootstrap.services]`, `[bootstrap.compose]` | User services; Docker Compose projects |
| `[bootstrap.secrets]` | Names of secret inputs used by managed file templates |
| `[bootstrap.user]` | Current-user settings such as `login_shell` |
| `[bootstrap.hooks]` | Commands at named bootstrap phases |
| `[tasks.bootstrap]` | Imperative setup that no declarative section covers |

`[system.*]` and `mise system` were 2026.6.4 spellings and no longer exist. Never emit them.

## Packages

Entries are `"manager:package" = "<version>"`; `"latest"` accepts an already-installed version rather than upgrading. Table form adds `os` (same names as `[tools]`) and, for pacman, `state = "absent"`.

```toml
[bootstrap.packages]
"apt:build-essential" = "latest"
"brew:postgresql@17" = "latest"
"brew-cask:font-jetbrains-mono" = { os = ["linux", "macos"] }
"winget:BurntSushi.ripgrep.MSVC" = { os = "windows" }
```

Managers: `apk`, `apt`, `aur`, `dnf`, `pacman`, `brew`, `brew-cask`, `flatpak`, `flatpak-user`, `nix`, `mas`, `winget`, plus package plugins. Entries for a manager unavailable on the current platform are skipped, so one config works everywhere.

`brew`/`brew-cask` do **not** require Homebrew to be installed: mise pours bottles into the canonical prefix itself. Third-party taps use the fully qualified name; add non-inferable tap URLs under `[bootstrap.brew.taps]`.

```bash
mise bootstrap packages status --missing
mise bootstrap packages apply --manager brew --dry-run
mise bootstrap packages upgrade
mise bootstrap packages prune --manager <plugin>
```

## Shell Activation

```toml
[bootstrap.mise_shell_activate]
zprofile = "shims"     # ~/.zprofile: mise activate zsh --shims
zshrc = "activate"     # ~/.zshrc:    mise activate zsh
bashrc = "activate"
fish = "activate"
```

`zsh = true` expands to `zprofile = "shims"` + `zshrc = "activate"`. Blocks are written with the same markers dotfile edit entries use. `mise` must already be on the startup file's PATH; open a new shell afterwards.

## Phases

Order (abbreviated): accounts → plugins → packages → files/directories → services → firewall → compose → repos → dotfiles → shell activation → macOS defaults → LaunchAgents → systemd units → user → `mise install` for `[tools]` → plugin packages → `mise run bootstrap` → `[bootstrap.hooks.final]`.

Select or exclude phases with `--only` / `--skip` (repeatable or comma-separated, mutually exclusive). Part names: `accounts`, `plugins`, `packages`, `files`, `services`, `firewall`, `compose`, `repos`, `dotfiles`, `mise-shell-activate`, `macos-defaults`, `macos-launchd-agents`, `linux-systemd-units`, `user`, `tools`, `task`, `final-hook`.

```bash
mise bootstrap --only dotfiles,tools --dry-run
mise bootstrap --skip tools,task
mise bootstrap --update          # refresh package metadata and declared repos first
```

`--only` does not pull in prerequisites: `--only services` will not install the packages that provide them.

## Hooks

Phases: `pre/post-packages`, `pre/post-repos`, `pre/post-dotfiles`, `pre/post-defaults`, `pre/post-user`, `pre/post-tools`, and `final`. Values are a command string, an array of strings, or a table with `run`. Hooks run in the current process environment, so wrap tool usage in `mise exec --`.

```toml
[bootstrap.hooks.post-tools]
run = ["mise exec -- node --version"]

[bootstrap.hooks]
post-defaults = "killall Dock || true"
```

## Status And Plan

```bash
mise bootstrap status --json
mise bootstrap status --missing     # whole declarative surface
mise bootstrap plan --json
mise bootstrap plan --detailed-exitcode   # 0 no change, 2 changes, 1 failure/unknown
mise bootstrap <part> status
```

Every mutating run records a pair of history checkpoints (tracked files before and after, plus a journal). Dry runs record nothing.

## Starting From A Repository

| Repository contents | Command |
| --- | --- |
| A bootstrap project with its own `mise.toml` | `mise bootstrap --from <git-url>` |
| Global mise config (`config.toml`, `conf.d/`, `tasks/`) | `mise bootstrap --adopt <repo>` |
| Tracked dotfile history (setup repository) | `mise bootstrap --adopt <repo>` |

`--from` clones into `$MISE_DATA_DIR/bootstrap-repo` (`--from-dir` overrides) and trusts the supplied repository for that invocation — review it first. `--adopt` clones into `$MISE_CONFIG_DIR`. Both accept `-E <env>` to select `mise.<env>.toml` / `config.<env>.toml`, and `--update` to fast-forward an existing checkout.

## Remote

`mise bootstrap remote --host <host> --source .` applies a configuration to an SSH target; `--install-mise` installs mise there first.

## Working Rules

- Treat `mise bootstrap` as destructive: trust, `--dry-run`, `plan`, then apply.
- Never suggest it as part of a project workflow; project tooling belongs in `[tools]`/`[tasks]`.
- Keep machine setup in `[bootstrap.*]` and project tools in `[tools]` even in the same file.
- Prefer declarative sections over `[tasks.bootstrap]`; the task re-runs every time.
