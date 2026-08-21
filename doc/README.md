# Documentation

Everything Nivuus documents, and nothing else. The README is the front door;
this is the reference. `tests/unit/test_docs_index.bats` fails the build when
this index and the directory disagree — in either direction.

## Install and remove

- **[INSTALL.md](INSTALL.md)** — every installation route, per platform, plus `--dry-run`, `--minimal`, `--prefix`, version pinning, and how to verify the signing keyring

## Use

- **[FEATURES.md](FEATURES.md)** — the complete feature reference, with examples
- **[PROMPT.md](PROMPT.md)** — prompt tokens, themes, and layout (in French)
- **[nivuus.1](nivuus.1)** — the man page, kept in sync with `nivuus help` by `tests/unit/test_manpage.bats`

## Distribute

- **[PACKAGING.md](PACKAGING.md)** — package mode, `.nivuus-origin`, `nivuus enable` / `disable` (in French)
- **[SIGNING.md](SIGNING.md)** — how a release is signed and what the verification refuses (in French)

## Contribute

- **[CLAUDE.md](CLAUDE.md)** — architecture, module layout, conventions
- **[TESTING.md](TESTING.md)** — the four test levels, how to run them, what each one proves

See also, at the repository root: [SECURITY.md](../SECURITY.md) (threat model),
[CHANGELOG.md](../CHANGELOG.md).
