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

Locally, mise can authorize itself with a GitHub App device flow (`mise settings github.oauth_client_id=<id>`, then `mise token github --oauth`). `github.oauth_copy_code = true` copies the device code to the clipboard (unset: asks in a terminal). To keep the six-month refresh token out of the cache file, set both global-only `github.oauth_cache_get` (prints it) and `github.oauth_cache_set` (reads it on stdin) to password-manager commands, e.g. `pass show mise/github-oauth` / `pass insert -m -f mise/github-oauth` (2026.10.9). On a Mac with Touch ID, `[settings.github] oauth_cache_secure_enclave = true` (2026.10.10) seals the refresh token to the Secure Enclave, asking for a fingerprint once per refresh; it needs the official release binary (Homebrew and source builds warn and use the cache file).
