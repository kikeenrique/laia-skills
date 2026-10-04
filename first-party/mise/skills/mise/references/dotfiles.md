# Dotfiles

Use this reference when mise should track, copy, link, template, or edit configuration files such as `~/.zshrc` or `~/.gitconfig`. This is stable, and it is configured in a **top-level `[dotfiles]` table**, not under `[bootstrap]`.

Commands live under `mise dotfiles` (alias `mise dot`, the spelling upstream docs use since 2026.9.8) and also under `mise bootstrap dotfiles`; both expose the same subcommands.

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

Tracking options:

```bash
mise dot track --dry-run ~/.codex             # file count/size and what is left out; writes nothing
mise dot track ~/.config/app/credentials --encrypt   # needs [history.encryption].recipients
mise dot track --allow-plaintext ~/notes-token.md    # saves allow_plaintext = true; --yes does not imply it
mise dot exclude '~/.codex/sessions/**'       # global [history] exclude; `include` removes it again
```

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

Before a push, mise refuses to publish earlier plaintext versions of now-encrypted paths. Override once with `mise dot sync --allow-plaintext-history`, or always with `[settings.history] allow_plaintext_history = true` (global config only) — both publish the old plaintext. `mise bootstrap --adopt <url> --replace-history --yes` discards local checkpoints and takes the origin's history (mise setup repositories only; back up first).

## Working Rules

- Put the entries in the global config (`~/.config/mise/config.toml`) for personal dotfiles; project configs should only manage project-scoped files.
- Preview with `apply --dry-run --verbose` before the first apply on a machine that already has the files.
- Never sync dotfiles containing secrets to a public repository.
