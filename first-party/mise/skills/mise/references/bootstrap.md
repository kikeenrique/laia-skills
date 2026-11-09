# Bootstrap

Use this reference when mise should set up a whole machine — OS packages, shell activation, repos, services, macOS defaults — not just a project's `[tools]`.

`mise bootstrap` (alias `bs`) is stable and is **not** the same as `mise generate install-script` (the old `mise generate bootstrap`, which only emits a script that downloads mise). See [hooks-and-generate.md](hooks-and-generate.md) for that generator.

`mise bootstrap` is declared `Effect: destructive`. It only runs when invoked explicitly; nothing here happens during `mise install` or `mise run`.

## Safety Workflow

Always in this order. Before trusting, read the config you are about to apply: its `[bootstrap.*]` hooks, `[tasks.bootstrap]`, `[dotfiles]`, remote `include` entries, and any `--from` repository. Bootstrap can install packages, add package repositories, write system files with `sudo`, and run those hooks, so trust is consent to all of it. Never run `mise trust` on config you have not reviewed with the user.

```bash
# 1. review the config (above), then:
mise trust
mise bootstrap --dry-run
mise bootstrap plan
mise bootstrap
mise bootstrap status
```

- A dry run inspects state and prints proposed actions; hooks and the `bootstrap` task do not execute.
- `--yes` skips confirmation prompts for unattended runs. As an agent, never add `--yes`, `--force-dotfiles`, or `--prune-dotfiles` on your own: show the user the plan and let them approve those flags explicitly.
- Bootstrap is a sequence, not a transaction. If a later phase fails, earlier changes stay applied; fix and re-run.
- Declarative parts converge, but hooks and `[tasks.bootstrap]` run on every apply, so make them idempotent.
- Dotfile conflicts are refused by default; `--force-dotfiles` replaces conflicting whole-file targets. `--prune-dotfiles` (2026.10.15) removes orphaned group files at the end of the dotfiles phase, like `mise dot apply --prune`.
- The `bootstrap` task runs only when it and every task it reaches come from global config or a trusted project (a task-only project file loads untrusted but could shadow it by name). Otherwise trust the project, run from another directory, or `--skip task`.

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
| `[bootstrap.apt.sources]` | Extra apt repositories and PPAs (2026.10.9) |
| `[bootstrap.plugins]` | Package-manager plugins (register before their packages) |
| `[bootstrap.repos]` | Git repos cloned before dotfiles apply |
| `[dotfiles]` | Dotfiles — top level, not under `[bootstrap]`; see [dotfiles.md](dotfiles.md) |
| `[bootstrap.mise_shell_activate]` | Activation snippets in shell startup files |
| `[bootstrap.macos.defaults]`, `[bootstrap.macos.launchd.agents]`, `[bootstrap.macos.login_items]` | macOS preferences, LaunchAgents, and Open-at-Login apps |
| `[bootstrap.linux.systemd.units]`, `[bootstrap.linux.firewall]` | Linux user units and host firewall |
| `[bootstrap.files]`, `[bootstrap.directories]` | Managed paths, content, ownership, permissions |
| `[bootstrap.users]`, `[bootstrap.groups]` | Linux service accounts and groups |
| `[bootstrap.services]`, `[bootstrap.compose]` | User services (including `builtin = "history-watch"` / `"tool-update"`); Docker Compose projects |
| `[bootstrap] dotfile_groups` | Which `[dotfile_groups.*]` this machine applies; see [dotfiles.md](dotfiles.md) |
| `[bootstrap.secrets]` | Names of secret inputs used by managed file templates |
| `[bootstrap.user]` | Current-user settings such as `login_shell` |
| `[bootstrap.hooks]` | Commands at named bootstrap phases |
| `[tasks.bootstrap]` | Imperative setup that no declarative section covers |

`[system.*]` and `mise system` were 2026.6.4 spellings and no longer exist. Never emit them; mise now warns on legacy command spellings.

Since 2026.10.5 a config `include` (`git::`/`oci::` fragment) may carry `[bootstrap]`: it ranks below the including file key by key (lists get the shared entries first) and runs with the including file's trust. Under `MISE_SAFE=1`, project `[bootstrap]` and `[dotfiles]` are ignored.

## Packages

Entries are `"manager:package" = "<version>"`; `"latest"` accepts an already-installed version rather than upgrading. Table form adds `os` (same names as `[tools]`) and, for some managers, `state = "absent"`.

```toml
[bootstrap.packages]
"apt:build-essential" = "latest"
"brew:postgresql@17" = "latest"
"brew-cask:font-jetbrains-mono" = { os = ["linux", "macos"] }
"winget:BurntSushi.ripgrep.MSVC" = { os = "windows" }
```

Managers: `apk`, `apt`, `aur`, `choco` (2026.10.20), `dnf`, `zypper`, `pacman`, `brew`, `brew-cask`, `macos-app`, `flatpak`, `flatpak-user`, `nix`, `mas`, `scoop`, `snap` (2026.10.10), `winget`, plus package plugins. Entries for a manager unavailable on the current platform are skipped, so one config works everywhere. `pacman`, `scoop`, `snap`, and `zypper` support `state = "absent"`.

`snap` needs snapd (mise does not install it) and uses sudo. snapd refreshes snaps itself, so version pins are skipped with a warning; set `channel` (`"<track>/<risk>"`, e.g. `"22/stable"`; drift is fixed with `snap refresh --channel`) and `classic = true` for classic-confinement snaps: `"snap:node" = { channel = "22/stable", classic = true }`. Commands land in `/snap/bin`, not mise shims.

`choco:` needs Chocolatey already installed and `apply`/`upgrade` run from an elevated terminal (mise never bypasses UAC; `status` needs no elevation). Use the exact package ID; a pin is passed as `--version` (with `--allow-downgrade`). No `state = "absent"`, `import`, or `prune` — uninstall with `choco uninstall`. Use `scoop` for per-user apps.

`"dnf:@development-tools"` (a leading `@`) is a dnf package group; use `"latest"` (environment groups `@^name` are unsupported). On Fedora Atomic hosts (Silverblue, Bazzite, …) `dnf:` entries fail with an explanation by default; `system_packages.ostree = "layer"` (2026.10.9) layers them in one `rpm-ostree install` transaction instead (reboot needed, pins skipped, `upgrade` refused).

Since 2026.10.10 `[bootstrap.dnf.repos]` enables COPR projects before `dnf:` packages install or upgrade, writing the same `/etc/yum.repos.d/_copr:…repo` file `dnf copr enable` does (no copr plugin needed; works on layering Atomic hosts). It asks before enabling without `--yes`, and never disables or removes a COPR — use `dnf copr remove`.

```toml
[bootstrap.dnf.repos]
ghostty = { copr = "scottames/ghostty" }
caddy = { copr = "@caddy/caddy" }    # group project
```

Package managers that need root run through `sudo`; since 2026.10.9 mise falls back to `run0` (systemd 256+) and then `doas` when `sudo` is missing, and `system_packages.elevate_with = "run0"` (or `"doas"`) pins one — in global config or `MISE_SYSTEM_PACKAGES_ELEVATE_WITH` only since 2026.10.20 (a project value is ignored). `system_packages.sudo = false` forbids elevation.

Since 2026.10.9 `[bootstrap.apt.sources]` adds apt repositories before `apt:` packages install, writing `/etc/apt/sources.list.d/mise-<name>.sources` with the key embedded in `Signed-By` (apt 2.4+) and running `apt-get update` once when a source changes. PPAs are added only on Ubuntu and derivatives; other sources need `uris`, `key`, and `fingerprint` (`suites`, `components`, `architectures` optional). A declared source also replaces an already-installed package from elsewhere (unless pinned or arch-qualified). mise never removes sources; delete the file yourself.

```toml
[bootstrap.apt.sources]
git-core = { ppa = "git-core/ppa" }

[bootstrap.apt.sources.docker]
uris = "https://download.docker.com/linux/ubuntu"
components = "stable"
key = "https://download.docker.com/linux/ubuntu/gpg"
fingerprint = "9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
```

`brew`/`brew-cask` do **not** require Homebrew to be installed: mise pours bottles into the canonical prefix itself. Third-party taps use the fully qualified name; add non-inferable tap URLs under `[bootstrap.brew.taps]`. A cask entry can set its own install directory: `"brew-cask:1password" = { appdir = "/Applications" }`. Casks mise installs are invisible to Homebrew unless `[bootstrap.brew] homebrew_metadata = true` (2026.10.20), after which Homebrew owns their upgrades. `mise bootstrap packages prune --manager brew-cask` removes only casks it can prove unchanged; it names the rest, and `--force` (2026.10.21) removes them anyway.

`macos-app` installs a `.app` with no cask from a pinned download (all four fields required; no `latest`, no pruning):

```toml
[bootstrap.packages."macos-app:example"]
version = "1.2.3"
url = "https://example.com/Example-{{version}}-arm64.dmg"
sha256 = "<64 hex chars>"
artifact = "Example.app"
os = "macos/arm64"
```

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

`zsh = true` expands to `zprofile = "shims"` + `zshrc = "activate"`. `fish = "auto"` writes an `if status is-interactive` block to `config.fish`: full activation at the prompt, shims for scripts (fish-only; `auto` elsewhere is ignored with a warning). Blocks are written with the same markers dotfile edit entries use. `mise` must already be on the startup file's PATH; open a new shell afterwards.

## Phases

Order (abbreviated): accounts → plugins → packages → files/directories → services → firewall → compose → repos → dotfiles → shell activation → macOS defaults → LaunchAgents → systemd units → user → `mise install` for `[tools]` → plugin packages → `mise run bootstrap` → `[bootstrap.hooks.final]`.

Select or exclude phases with `--only` / `--skip` (repeatable or comma-separated, mutually exclusive). Part names: `accounts`, `plugins`, `packages`, `files`, `services`, `firewall`, `compose`, `repos`, `dotfiles`, `mise-shell-activate`, `macos-defaults`, `macos-launchd-agents`, `linux-systemd-units`, `user`, `tools`, `task`, `final-hook`.

```bash
mise bootstrap --only dotfiles,tools --dry-run
mise bootstrap --skip tools,task
mise bootstrap --update          # fast-forward the global config checkout (2026.11.0), refresh package metadata and declared repos first
mise bootstrap --upgrade         # also upgrade installed packages and tools (2026.10.11)
```

`--upgrade` runs the equivalent of `mise bootstrap packages upgrade` in the packages phase and `mise upgrade` (no `--bump`) in the tools phase, respecting pins and version ranges. It does not update mise, repositories, or container images; `--dry-run` previews upgrades only for things already installed.

`--only` does not pull in prerequisites: `--only services` will not install the packages that provide them.

For apt, prefer `[bootstrap.apt.sources]`. Other files and directories a package manager needs (keyrings, repo definitions) can run early with `phase = "pre-packages"` on their `[bootstrap.files."<path>"]` / `[bootstrap.directories."<path>"]` entry: they apply after accounts and plugins, before the `pre-packages` hook (default phase is `"post-packages"`). Follow with `mise bootstrap --update` to refresh package metadata.

Files and directories also accept the packages' `os` selector, so one config can write different paths per platform; a non-matching entry is skipped as if undeclared:

```toml
[bootstrap.files."/etc/docker/daemon.json"]
os = "linux"
source = "./files/docker-daemon.json"
```

## Platform Units And Defaults

- Compose project values render Tera, e.g. `project_dir = "{{ config_root }}/mempalace"`, so shared config needs no machine-specific paths (no `exec()`).
- systemd units support `state = "absent"` and `mise bootstrap unapply`.
- systemd units (`[bootstrap.linux.systemd.units.<name>]`) accept `before`, `binds_to`, `part_of`, and `conflicts` (lists of unit names) next to `after`/`wants`/`requires`, and service-only `exec_start_pre` / `exec_start_post` lists (one `ExecStartPre=`/`ExecStartPost=` line each).
- LaunchAgents accept `process_type` = `Background`, `Standard`, `Adaptive`, or `Interactive` (exact launchd spelling; anything else is an error), and since 2026.10.20 `launch_events` (launchd `LaunchEvents`, tables keyed by quoted stream then event name, properties in launchd's case), e.g. `[bootstrap.macos.launchd.agents.usb-handler.launch_events."com.apple.iokit.matching".apple-usb]` with `IOProviderClass = "IOUSBHostDevice"`. The program must consume the stream (`xpc_set_event_stream_handler`).
- To start and enable a systemd **user** unit a package already ships (e.g. `gnome-keyring-daemon`), declare `[bootstrap.services.<unit>]` with `scope = "user"`, `state = "running"`, `enabled = true` and no `command`/`builtin` (2026.10.20, Linux-only; no root needed; a bare name gets `.service`).
- `[bootstrap.macos.login_items] apps = ["/Applications/Ghostty.app", "~/Applications/Example.app"]` (2026.10.9) declares Open-at-Login apps. It is additive by default; `exclusive = true` makes `apply` remove undeclared entries too. Applied with the macOS defaults.
- For `defaults -currentHost` preferences, use an explicit entry with `host = "current"` (default `"any"`):

```toml
[[bootstrap.macos.defaults_entries]]
domain = "NSGlobalDomain"
key = "com.apple.mouse.tapBehavior"
host = "current"
value = 1
```

## Hooks

Phases: `pre/post-packages`, `pre/post-repos`, `pre/post-dotfiles`, `pre/post-defaults`, `pre/post-user`, `pre/post-tools`, and `final`. Values are a command string, an array of strings, or a table with `run`. Hooks run in the current process environment, so wrap tool usage in `mise exec --`.

```toml
[bootstrap.hooks.post-tools]
run = ["mise exec -- node --version"]

[bootstrap.hooks]
post-defaults = "killall Dock || true"
```

Since 2026.10.18 a hook table may set `run_windows`, which replaces `run` on Windows; a table with only `run_windows` does nothing elsewhere. Since 2026.10.22 a table's `description` is printed in place of the command; otherwise mise prints only the command's first line (`--verbose` and `--dry-run` print it in full).

## Login Shell

`[bootstrap.user] login_shell` takes an absolute path or, since 2026.10.17, a bare name (`login_shell = "fish"`) resolved after packages install, from `PATH` (never shims) then the usual package-manager dirs; the resolved path goes into `/etc/shells` and `chsh`. It is also a template (`"{{ system_brew_prefix }}/bin/zsh"`, no `exec()`). Shells from package-manager *plugins* install after the user phase, so on a first run use `mise bootstrap --skip user` then `mise bootstrap user apply`.

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

`--from` clones into `$MISE_DATA_DIR/bootstrap-repo` (`--from-dir` overrides; append `?ref=<branch|tag|commit>` to the URL to check out a ref, e.g. `git::https://github.com/example/dotfiles.git?ref=v1`) and trusts the supplied repository for that invocation — review it first. `--adopt` clones into `$MISE_CONFIG_DIR`; since 2026.10.10 `--adopt '<repo>?ref=<branch>'` adopts another branch (a branch only — tags and commits are refused; an existing checkout is never switched, and `--update` fast-forwards the branch it is on). Both accept `-E <env>` to select `mise.<env>.toml` / `config.<env>.toml`, and `--update` to fast-forward an existing checkout. The old `--from-git` alias was removed in 2026.10.0; use `--from`. Use `--from` for a setup project you apply but don't make your own (your global config still loads alongside it); use `--adopt` when the repository becomes this machine's own config. On a fresh machine without `git` (or `ssh` for an SSH URL), mise offers to install them with the host package manager before cloning (`--yes` accepts; `--dry-run` only reports).

To share your own setup, the docs now start with `mise dot track ~/.config/mise` plus an origin, adopted elsewhere with `--adopt`. To keep mise's config inside your own dotfiles checkout instead, `--config-dir` (2026.10.21, requires `--from`) links `~/.config/mise` to a directory in the checkout and bootstraps from it; the target must be missing, empty, or already that link:

```bash
mise bootstrap --from https://github.com/you/dotfiles.git --from-dir ~/.dotfiles --config-dir .config/mise
mise bootstrap --update   # later: fast-forwards the checkout the link (or an --adopt checkout) points into, then re-runs
```

`mise use -g` and `mise dot add` then write into the checkout through the link. With `--update` and neither `--from` nor `--adopt`, only a fast-forward is accepted. `--save-env` (2026.11.1) saves the `-E`/`MISE_ENV` selection to `miserc.local.toml` so later runs need no `-E` (see `[env_sets]` in [config.md](config.md)).

`--prompt-vars` asks for `[vars]` entries with a `prompt` and no saved answer (see [environments.md](environments.md)), which is how `--adopt` answers per-machine values on a fresh machine. `[bootstrap.repos]` keys may render vars, e.g. `"{{ vars.repos_dir }}/project-a" = { url = "..." }` (2026.10.9), so each machine picks its own checkout base. Since 2026.10.13 `url` and `ref` also render vars and `env.NAME` (not `[env]` values), and optional clone options shape the first clone of a missing repo only: `filter` (e.g. `"blob:none"`), `depth` (not with a full SHA or `refs/` ref), `submodules = true`:

```toml
[bootstrap.repos]
"~/src/large" = { url = "git@github.com:example/large.git", ref = "{{ vars.branch }}", filter = "blob:none", depth = 1 }
```

To drop an optional module, `mise bootstrap unapply <env>… [--dry-run]` removes the managed files, directories, user services, and dotfile entries that config environment contributes (based on the current config, not run history).

## Remote

`mise bootstrap remote --host <host> --source .` applies a configuration to an SSH target; `--install-mise` installs mise there first.

## Working Rules

- Treat `mise bootstrap` as destructive: trust, `--dry-run`, `plan`, then apply.
- Never suggest it as part of a project workflow; project tooling belongs in `[tools]`/`[tasks]`.
- Keep machine setup in `[bootstrap.*]` and project tools in `[tools]` even in the same file.
- Prefer declarative sections over `[tasks.bootstrap]`; the task re-runs every time.
