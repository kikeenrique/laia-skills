# Dotfiles

Use this reference when mise should track, copy, link, template, or edit configuration files such as `~/.zshrc` or `~/.gitconfig`. This is stable, and it is configured in a **top-level `[dotfiles]` table**, not under `[bootstrap]`.

Commands live under `mise dotfiles` (alias `mise dot`, the spelling upstream docs use). `mise bootstrap dotfiles` is the same command mounted a second time; since 2026.10.5 it is hidden from help and the CLI reference but keeps working. Prefer `mise dot` in new instructions.

## Two Uses

- **Track in place**: keep the file where it is and save a version history of it.
- **Manage from a source**: mise creates the target from a source file you maintain.

Track an existing file:

```bash
mise dot track ~/.zshrc
```

which records in the global config:

```toml
[dotfiles]
"~/.zshrc" = { mode = "track" }
```

## Modes

| Mode | Apply behavior |
| --- | --- |
| `symlink` | Link one file or a whole directory. Default. |
| `symlink-each` | Create directories and link each file inside them. |
| `copy` | Copy, overwriting matching files at the target. |
| `template` | Render the source with the Tera template engine. |
| `track` | Leave the file in place, save its history only. |
| `track-local` | Like `track`, but the history stays on this machine and is never synced. |
| `absent` | Remove a file or symlink at the target; takes no source. |

```toml
[dotfiles]
"~/.config/nvim" = { source = "dotfiles/nvim", mode = "symlink" }
"~/.config/app.conf" = { source = "dotfiles/app.conf", mode = "copy" }
```

`dotfiles.root` (default `~/.dotfiles`) is where `add` saves captured sources; `dotfiles.default_mode` (default `symlink`) is what `add` applies. In `copy` mode, `apply` overwrites edits made directly to the target — run `add` first to capture them.

More entry keys:

```toml
[settings]
dotfiles.relative_symlinks = true   # Stow-style relative links; per-entry `relative = false` overrides

[dotfiles]
# dot-bashrc -> ~/.bashrc (Stow --dotfiles); needs a directory source with symlink-each or copy
"~" = { source = "home", mode = "symlink-each", dot_prefix = true, exclude = ["README.md"] }
"~/.netrc" = { source = "netrc.tera", mode = "template", permissions = "0600" }
"~/.ssh" = { permissions = "0700" }   # manage only the mode, not the contents

# one source, a different destination per platform (most specific variant wins)
[dotfiles."vscode/settings.json"]
source = "dotfiles/vscode/settings.json"
mode = "copy"
variants = [
  { os = "macos", target = "~/Library/Application Support/Code/User/settings.json" },
  { os = "linux", target = "~/.config/Code/User/settings.json" },
]
```

Variant selectors are `os` (optionally with arch), `profile` (a mise env), and `default = true`; no match skips the entry. Templates can read declared `[bootstrap.secrets]` inputs with `{{ secret(name="logical_name") }}`; pass `--prompt-secrets` to prompt for missing values.

## Edit Entries

Edit entries manage one block or line inside a file, keyed by target path plus an id. mise delimits them with `# >>> mise:<id> >>>` markers.

```toml
[dotfiles]
"~/.zshrc/activate" = { block = 'eval "$(mise activate zsh)"' }
"/etc/hosts/dev" = { line = "127.0.0.1 dev.local" }
"/etc/zshrc/zdotdir" = { line = 'ZDOTDIR=$HOME/.config/zsh/', position = "prepend" }
"~/.gitconfig/identity" = { source = "snippets/git-identity.tmpl", template = "tera" }
```

For an edit entry, `source` must be paired with `template = "tera"` or `merge`; a table with only `source` is a whole-file entry using `dotfiles.default_mode`.

**Merge entries** own only some keys of a JSON, TOML, or YAML file that an application also writes (Codex, Claude Code settings). The format comes from the target's extension:

```toml
[dotfiles]
"~/.codex/config.toml/shared" = { source = "codex/shared.toml", merge = true }    # enforce these keys
"~/.codex/config.toml/defaults" = { source = "codex/defaults.toml", merge = "missing" }  # only fill absent keys
"~/.claude/settings.json/shared" = { merge = true }   # source inferred: <dotfiles.root>/.claude/settings.json
```

Tables merge recursively; scalars and arrays are replaced; keys only the target has, and keys later removed from the source, are left alone. `merge = "missing"` never overrides a value the app chose. `status`/`diff` report drift only in owned keys; TOML/YAML keep comments and formatting; an unparseable target (including JSON with comments) is never overwritten; `unapply` leaves merged keys in place. If the target is a symlink to the entry's own source, `apply` replaces it with a copy first, so switching from `symlink` to `merge` keeps the app's state.

## Groups

`[dotfile_groups.<name>]` deploys a Stow-style tree without listing files; a machine picks the groups it applies:

```toml
[dotfile_groups.home]
root = "home"            # relative to dotfiles.root; target defaults to ~
dot_prefix = true        # dot-config/ deploys as .config/
exclude = ["README.md"]  # also: target, mode (symlink-each default, copy, symlink), manifest, relative

[dotfile_groups.home.entries]   # [dotfiles] syntax, cut out of the walk
"~/.config/kitty" = { mode = "symlink" }
"~/.gitconfig" = { source = "git/config.tmpl", mode = "template" }

[bootstrap]
dotfile_groups = ["home"]   # unset: every group applies
```

Two selected groups writing the same path fail before anything is written. `mise dot status` lists files from deselected or shrunk groups as `orphaned`; `mise dot apply --prune` removes them and `mise dot unapply --group <name>` removes one group's files. `mise dot add`/`edit` route a file under a group's target into its root (`--group` when ambiguous).

## Commands

```bash
mise dot status            # tracked/applied/missing/differs/orphaned per entry
mise dot status --missing  # exit 1 if anything is out of sync
mise dot diff [target]
mise dot apply --dry-run --verbose
mise dot apply [--yes|--force|--prune]
mise dot unapply [--dry-run|--force|--group <name>]
mise dot track|untrack ~/.zshrc
mise dot add ~/.zshrc [--mode copy|--no-apply|--group <name>]
mise dot add --changed     # capture all changed copy-mode files
mise dot edit [--apply] ~/.zshrc
mise dot save              # checkpoint tracked files now
mise dot history [show latest|diff 11 12]
mise dot paths
mise dot notify            # send a test notification (sync-conflict alerts only)
```

Tracking options:

```bash
mise dot track --dry-run ~/.codex             # file count/size and what is left out; writes nothing
mise dot track ~/.config/app/credentials --encrypt   # needs [history.encryption].recipients
mise dot track --allow-plaintext ~/notes-token.md    # saves allow_plaintext = true; --yes does not imply it
mise dot exclude '~/.codex/sessions/**'       # global [history] exclude; `include` removes it again
mise dot track --local ~/.config/app/state.json   # mode = "track-local"
mise dot track --machine ~/.config/hypr/monitors.lua   # variants = [{ machine = true }]
```

- **`track-local`** keeps a separate history under `$MISE_STATE_DIR/history-local` that is never synced, even inside a shared tracked directory. `save`, `watch`, and `capture` cover both histories; commands naming a path route to the right one, and `mise dot --local history|undo` selects the local one (`sync`, `pull`, `origin`, `conflicts` are refused there). No `encrypt` or `variants`.
- **Machine variant** gives each machine its own version of a tracked file (monitor layouts, hardware quirks): synced to the origin but never applied on another machine. Names come from `[history] machine = "desk"` in that machine's global config, or a generated hostname-plus-suffix. It must be the only variant, cannot be encrypted, and every machine sharing the setup must run a mise that understands it.

Scope a tracked directory per entry with `exclude` or `include` lists (patterns relative to it; `/x` anchors to the root, use `**` to cross directories): `"~/.codex" = { mode = "track", include = ["config.toml", "rules/**"] }`.

`apply` also runs as phase 9 of `mise bootstrap`, wrapped by the `pre-dotfiles` / `post-dotfiles` hooks. `mise install` and `mise bootstrap packages` leave dotfiles alone.

## History And Sync

Every mutating run records a checkpoint pair (tracked files before and after) plus a journal of changes; dry runs record nothing. To save edits automatically instead of running `save` by hand, add the watcher service:

```toml
[bootstrap.services.mise-history]
builtin = "history-watch"
```

then `mise bootstrap services apply`.

Synchronization pushes checkpoints to a Git remote so another machine can restore them with `mise bootstrap --adopt <repo>`. Use a **private** repository: sync sends earlier checkpoints too, so temporary edits become part of the shared history. Configure encryption before first saving files that need it.

Before a push, mise refuses to publish earlier plaintext versions of now-encrypted paths, and (since 2026.10.5) unpublished versions with a line that looks like a secret — provider tokens (`ghp_`, `sk-`, `AKIA…`), private key blocks, or `*_KEY`/`*_TOKEN`/`*_SECRET`/`*_PASSWORD` assignments. Removing the line from the file does not remove it from saved versions; encrypt the file instead. Override both checks once with `mise dot sync --allow-plaintext-history`, or always with `[settings.history] allow_plaintext_history = true` (global config only) — both publish the old content.

On a machine whose files differ from the setup repository, `mise bootstrap --adopt <url> --take-remote-all` (or `mise dot pull --take-remote-all` after adopting) takes the repository's versions and saves the replaced local files first, so `mise dot undo` restores them. `--adopt <url> --replace-history --take-remote-all` discards this machine's own checkpoints and adopts the origin's history (mise setup repositories only; back up first); without `--take-remote-all` it refuses when files differ.

`history.notify` desktop notifications cover only sync conflicts that pause sharing; `mise doctor` and `mise dot status` show whether they can be delivered (Homebrew builds on macOS never notify), and `mise dot notify` triggers the macOS permission prompt.

## Working Rules

- Put the entries in the global config (`~/.config/mise/config.toml`) for personal dotfiles; project configs should only manage project-scoped files.
- Preview with `apply --dry-run --verbose` before the first apply on a machine that already has the files.
- Never sync dotfiles containing secrets to a public repository.
