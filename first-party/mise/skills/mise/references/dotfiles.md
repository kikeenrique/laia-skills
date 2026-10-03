# Dotfiles

Use this reference when mise should track, copy, link, template, or edit configuration files such as `~/.zshrc` or `~/.gitconfig`. This is stable, and it is configured in a **top-level `[dotfiles]` table**, not under `[bootstrap]`.

Commands live under `mise bootstrap dotfiles`. The top-level `mise dotfiles` command is deprecated and hidden; it begins warning in mise 2027.2.0 and is removed in 2028.2.0.

## Two Uses

- **Track in place**: keep the file where it is and save a version history of it.
- **Manage from a source**: mise creates the target from a source file you maintain.

Track an existing file:

```bash
mise bootstrap dotfiles track ~/.zshrc
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

```toml
[dotfiles]
"~/.config/nvim" = { source = "dotfiles/nvim", mode = "symlink" }
"~/.config/app.conf" = { source = "dotfiles/app.conf", mode = "copy" }
```

`dotfiles.root` (default `~/.dotfiles`) is where `add` saves captured sources; `dotfiles.default_mode` (default `symlink`) is what `add` applies. In `copy` mode, `apply` overwrites edits made directly to the target — run `add` first to capture them.

## Edit Entries

Edit entries manage one block or line inside a file, keyed by target path plus an id. mise delimits them with `# >>> mise:<id> >>>` markers.

```toml
[dotfiles]
"~/.zshrc/activate" = { block = 'eval "$(mise activate zsh)"' }
"/etc/hosts/dev" = { line = "127.0.0.1 dev.local" }
"/etc/zshrc/zdotdir" = { line = 'ZDOTDIR=$HOME/.config/zsh/', position = "prepend" }
"~/.gitconfig/identity" = { source = "snippets/git-identity.tmpl", template = "tera" }
```

For an edit entry, `source` must be paired with `template = "tera"`; a table with only `source` is a whole-file entry using `dotfiles.default_mode`.

## Commands

```bash
mise bootstrap dotfiles status            # tracked/applied/missing/differs per entry
mise bootstrap dotfiles status --missing  # exit 1 if anything is out of sync
mise bootstrap dotfiles diff [target]
mise bootstrap dotfiles apply --dry-run --verbose
mise bootstrap dotfiles apply [--yes|--force]
mise bootstrap dotfiles unapply [--dry-run|--force]
mise bootstrap dotfiles track|untrack ~/.zshrc
mise bootstrap dotfiles add ~/.zshrc [--mode copy|--no-apply]
mise bootstrap dotfiles add --changed     # capture all changed copy-mode files
mise bootstrap dotfiles edit [--apply] ~/.zshrc
mise bootstrap dotfiles save              # checkpoint tracked files now
mise bootstrap dotfiles history [show latest|diff 11 12]
mise bootstrap dotfiles paths
```

`apply` also runs as phase 9 of `mise bootstrap`, wrapped by the `pre-dotfiles` / `post-dotfiles` hooks. `mise install` and `mise bootstrap packages` leave dotfiles alone.

## History And Sync

Every mutating run records a checkpoint pair (tracked files before and after) plus a journal of changes; dry runs record nothing. To save edits automatically instead of running `save` by hand, add the watcher service:

```toml
[bootstrap.services.mise-history]
builtin = "history-watch"
```

then `mise bootstrap services apply`.

Synchronization pushes checkpoints to a Git remote so another machine can restore them with `mise bootstrap --adopt <repo>`. Use a **private** repository: sync sends earlier checkpoints too, so temporary edits become part of the shared history. Configure encryption before first saving files that need it.

## Working Rules

- Put the entries in the global config (`~/.config/mise/config.toml`) for personal dotfiles; project configs should only manage project-scoped files.
- Preview with `apply --dry-run --verbose` before the first apply on a machine that already has the files.
- Never sync dotfiles containing secrets to a public repository.
