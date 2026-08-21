# Nivuus Shell

> **A complete ZSH environment in one command — and one command to remove it,
> byte for byte.**

[![Version](https://img.shields.io/github/v/release/maximeallanic/nivuus-shell?label=version)](https://github.com/maximeallanic/nivuus-shell/releases)
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
[![Matrix](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)
<!-- badge-proof: tests/performance/test_startup.bats -->
[![startup <300ms](https://img.shields.io/badge/startup-<300ms-brightgreen.svg)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

It verifies a SHA-256 checksum, writes a delimited block into your `~/.zshrc`,
needs no `sudo` and no `git`. Add `--dry-run` to see everything it would touch
without touching it. What this **cannot** protect you from is documented, in
plain terms, in [SECURITY.md](SECURITY.md#first-install).

## Uninstall

```bash
nivuus uninstall              # restores every file it touched
nivuus uninstall --purge      # also removes its own state (manifest, backups)
nivuus uninstall --dry-run    # shows what it would remove, changes nothing
```

Every modified file is restored from a content-addressed backup recorded at
install time in `~/.local/state/nivuus/backups/`. `~/.zsh_local` and
`~/.zsh_history` are never deleted. This is checked nightly on every target
below — that is the *uninstall verified* badge.

Then restart your terminal, or `exec zsh`.

## What you get

- **Removable.** `nivuus uninstall` restores every file it touched from a content-addressed backup. Verified nightly on the whole matrix — see the badge. → [doc/INSTALL.md](doc/INSTALL.md)
- **Fast, and held to it.** A CI test fails the build if an interactive shell takes more than 300ms to start. → [doc/FEATURES.md](doc/FEATURES.md)
- **No plugin manager.** Pure ZSH modules, no oh-my-zsh, no framework underneath. → [doc/CLAUDE.md](doc/CLAUDE.md)
- **Optional AI, your key, your provider.** Gemini, OpenAI or Anthropic — `??`, `why`, `explain`, and a command-not-found that names the package to install. Nivuus works fully without it. → [doc/FEATURES.md](doc/FEATURES.md)
- **A prompt you can re-lay-out.** Themes and a token-based prompt format, no code change. → [doc/PROMPT.md](doc/PROMPT.md)
- **Signed releases.** An update whose signature does not verify is refused outright, with no fallback. → [SECURITY.md](SECURITY.md)

## Proof

Eight targets. Install, uninstall, and a `$HOME` fingerprint that must come
back bit-identical — every night, and on every release.

| Target | Install | Uninstall |
|---|---|---|
| Ubuntu 22.04 | yes | yes |
| Ubuntu 24.04 | yes | yes |
| Debian 12 | yes | yes |
| Arch Linux | yes | yes |
| Fedora 41 | yes | yes |
| Alpine 3.20 (musl) | yes | yes |
| Ubuntu (GitHub runner) | yes | yes |
| macOS 14 (arm64) | yes | yes |

The startup budget is enforced, not observed: the build fails past **300ms**.
Typical times measured on that matrix: 26–46 ms, see [tests/performance/](tests/performance/).

The target list is not written here by hand: it comes from
[.github/matrix.json](.github/matrix.json), and
`tests/unit/test_readme_badges.bats` fails when this table and that file
disagree.

## Configure

Nothing here is required. Put what you want in `~/.zsh_local`; Nivuus never
writes to it.

```bash
# ~/.zsh_local
export NIVUUS_THEME=dracula                # nord (default) or dracula
export NIVUUS_PROMPT_FORMAT='{path}{git} ' # {ssh} {root} {status} {path} {venv} {cloud} {git} {jobs}
export AI_BACKEND=anthropic                # gemini (default), openai, anthropic
export ANTHROPIC_API_KEY=sk-ant-...
export ENABLE_AI_SUGGESTIONS=false         # every feature has an off switch
export ENABLE_AUTOUPDATE=false
```

Full list of tokens, themes and toggles: [doc/PROMPT.md](doc/PROMPT.md) and
[doc/FEATURES.md](doc/FEATURES.md).

## Everyday commands

```bash
nivuus doctor      # diagnose an installation that misbehaves
nivuus update      # fetch and verify the next signed release
nivuus enable      # activate Nivuus for this user (after a package install)
nivuus disable     # deactivate it, leaving the tree alone
nivuus help        # all of the above, with their flags
```

## Documentation

Everything is in [doc/](doc/README.md), which is an index the CI keeps honest.

- [doc/INSTALL.md](doc/INSTALL.md) — every installation route, per platform, and how to verify the signing keyring
- [doc/FEATURES.md](doc/FEATURES.md) — the complete feature reference
- [doc/PROMPT.md](doc/PROMPT.md) — prompt tokens, themes, layout (in French)
- [doc/UPDATING.md](doc/UPDATING.md) — how updates are verified, applied and rolled back
- [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md) — when `nivuus doctor` is not enough
- [doc/PACKAGING.md](doc/PACKAGING.md) — package mode, for maintainers (in French)
- [doc/CLAUDE.md](doc/CLAUDE.md) — architecture and conventions
- [doc/TESTING.md](doc/TESTING.md) — the four test levels and how to run them

## Contributing · Security · License

Read [CONTRIBUTING.md](CONTRIBUTING.md) first: this repository tests its own
documentation, and a pull request that reads well can still fail the build.

Security policy, threat model and keyring fingerprint: [SECURITY.md](SECURITY.md).

MIT — see [LICENSE](LICENSE).

## Credits

Colour palette after [Nord](https://www.nordtheme.com/). AI features talk to
Google Gemini, OpenAI or Anthropic, with your key and your choice.
