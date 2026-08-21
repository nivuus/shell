# Updating Nivuus

Nivuus checks for a new release on its own, verifies its signature, and
refuses anything it cannot authenticate. This page describes that path: what
runs, what it verifies, how to turn it off, and how to go back.

The cryptography itself — key format, what is signed, how the keyring is
rotated — lives in [SIGNING.md](SIGNING.md). This page is about the update.

## Update now

```bash
nivuus update
```

It contacts GitHub Releases, compares the latest stable tag with the installed
version, and, if there is something newer, downloads and installs it. Nothing
is written before every verification has passed.

`nivuus doctor` reports the installed version, the origin of the tree, and
whether the automatic path is enabled.

## What the update verifies, in order

1. Resolve the latest stable release on GitHub.
2. Download the release archive, its `SHA256SUMS`, and the signatures.
3. **Verify the signature of `SHA256SUMS`** against the keys shipped in `keys/`.
   Signature first: comparing a digest against an unauthenticated `SHA256SUMS`
   proves nothing.
4. Verify the SHA-256 digest of the archive against the now-authenticated
   `SHA256SUMS`.
5. Back up the current installation.
6. Install the new version.
7. Recompile the ZSH modules.

If step 3 or step 4 fails, the update is **refused** before anything is
written, and the installation is left untouched. There is no fallback, and the
signature check cannot be disabled on the automatic path.

## Configuration

In `~/.zsh_local`:

```bash
# Disable automatic updates entirely
export ENABLE_AUTOUPDATE=false

# Change how often the check runs (days)
export AUTOUPDATE_CHECK_FREQUENCY_DAYS=14

# Disables ONLY the SHA-256 comparison (discouraged). It has no effect on the
# signature check, which is never optional on the automatic path.
export NIVUUS_VERIFY_CHECKSUMS=false

# Track a fork instead of the upstream repository
export NIVUUS_GITHUB_REPO=yourfork/nivuus-shell
```

## When Nivuus came from a package

If the tree carries a `.nivuus-origin` marker with `origin=package`, Nivuus
never updates itself: the package manager owns the files. `nivuus update`
explains this and prints the command for the channel it was installed from
(`brew upgrade`, `yay -Syu`, `apt upgrade`, …), derived from the marker's
`channel=` field — never guessed from the machine.

Automatic updates are off in that mode, and the shared tree is never written
to. See [PACKAGING.md](PACKAGING.md).

## Rolling back

Every update copies the current installation aside first:

```bash
ls ~/.config/nivuus-shell-backup/
cp -r ~/.config/nivuus-shell-backup/pre-update-YYYYMMDD-HHMMSS/nivuus-shell ~/.nivuus-shell
exec zsh
```

Only the five most recent pre-update backups are kept.

This is **not** the install-time backup. The files Nivuus overwrote when it
was first installed live in `~/.local/state/nivuus/backups/`, and that is what
`nivuus uninstall` restores from.

## Releases

Nivuus follows semantic versioning (MAJOR.MINOR.PATCH): MAJOR for breaking
changes, MINOR for backward-compatible features, PATCH for fixes. The history
is in [CHANGELOG.md](../CHANGELOG.md).
