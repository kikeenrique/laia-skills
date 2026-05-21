# Getting Started

Use this reference when installing mise, activating shell integration, or bootstrapping a new project.

## Install And Verify

Common install path from official docs:

```bash
curl https://mise.run | sh
~/.local/bin/mise --version
```

Package managers such as Homebrew, apt, dnf, snap, nix, and others are supported; check the official install docs when the OS or package manager matters.

## Shell Activation

For persistent shell integration, add activation near the end of the shell rc file so later `PATH` changes do not override mise-managed tools:

```bash
eval "$(mise activate zsh)"
```

Use the user's shell:

```bash
eval "$(mise activate bash)"
mise activate fish | source
```

When persistent activation is undesirable, use on-demand execution:

```bash
mise exec -- node -v
mise x -- python script.py
mise run test
```

## Project Bootstrap

Create or update project config by using `mise use`:

```bash
mise use node@22
mise use python@3.12
mise install
```

Equivalent direct config:

```toml
[tools]
node = "22"
python = "3.12"

[tasks.test]
run = "python -m pytest"
```

## Practical Defaults

- Use `mise.toml` for committed project config.
- Use `mise.local.toml` for developer-local overrides and add it to `.gitignore`.
- Run `mise install` after direct edits to install any newly configured tools.
- Run `mise run <task>` to execute with project tools and env even without shell activation.

## GitHub Rate Limits

Many tool backends resolve releases through GitHub. If installs return 4xx/rate-limit errors, configure GitHub authentication or commit a complete `mise.lock` so CI and teammates reuse resolved URLs.
