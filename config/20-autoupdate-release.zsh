#!/usr/bin/env zsh
# =============================================================================
# Nivuus Shell - Release Installation (part of config/20-autoupdate.zsh)
# =============================================================================
# Downloads one release, proves where it comes from, stages it beside the
# install and swaps it in. config/20-autoupdate.zsh sources this file and
# decides WHEN to call it; this file only knows HOW.
#
# The install is never modified in place:
#   1. the archive is downloaded into a work directory next to the install
#      (same filesystem, so the swap below is a rename, not a copy);
#   2. its SHA256SUMS entry and its GitHub artifact attestation are checked,
#      failing closed;
#   3. it is extracted into <work>/new and proven there: the entry files
#      exist, every module parses and compiles;
#   4. the live tree is renamed to <work>/old and <work>/new renamed into its
#      place. If the second rename fails the first is undone;
#   5. only then is <work> (and the previous tree in it) removed.
# A failure at any step before 4 leaves the live tree untouched; the window in
# step 4 is two renames long.
# =============================================================================

: ${NIVUUS_VERIFY_CHECKSUMS:=true}
# Every release of this organisation is published by the shared release
# workflow of nivuus/.github, which records a SLSA build provenance
# attestation for the archive (actions/attest-build-provenance). The checksum
# only proves the archive is the one the release lists; the attestation proves
# the release was built by that workflow from this repository's main branch.
: ${NIVUUS_VERIFY_ATTESTATION:=true}
: ${NIVUUS_RELEASE_SIGNER_WORKFLOW:=nivuus/.github/.github/workflows/release.yml}
: ${NIVUUS_RELEASE_SOURCE_REF:=refs/heads/main}

zmodload -F zsh/stat b:zstat 2>/dev/null

# lib/ of the tree this file belongs to, for the gh install command.
typeset -g _NIVUUS_UPDATE_LIB="${${(%):-%x}:A:h:h}/lib"

# One command that removes the cause of the last failure, when there is one
# the person can run (set by _nivuus_verify_attestation, read by
# config/20-autoupdate.zsh for the report at the next terminal start).
typeset -g NIVUUS_UPDATE_REMEDY=""

# What to run to install gh and retry, from the installer's package table
# (lib/deps.sh); a pointer to its install page when no known package manager
# here ships it.
_nivuus_gh_remedy() {
    local cmd
    cmd=$(source "$_NIVUUS_UPDATE_LIB/detect.sh" && source "$_NIVUUS_UPDATE_LIB/deps.sh" &&
        nivuus_pkg_hint_cmd "$(nivuus_pkg_manager)" gh)
    if [[ -n "$cmd" ]]; then
        print -r -- "$cmd && nivuus-update"
    else
        print -r -- "install the GitHub CLI (https://cli.github.com), then nivuus-update"
    fi
}

# Release versions are plain X.Y.Z: anything else is refused before it is
# used in a URL or a path.
_nivuus_valid_version() {
    [[ "$1" == <->.<->.<-> ]]
}

# Paths of the work directory and the lock, both next to the install so the
# swap is a rename on one filesystem.
_nivuus_update_lock_file() {
    print -r -- "${NIVUUS_SHELL_DIR}.update.lock"
}

# Take the update lock without waiting. Sets $_NIVUUS_UPDATE_LOCK_FD; the
# lock lasts until _nivuus_update_unlock or the end of the process.
_nivuus_update_lock() {
    zmodload zsh/system || return 1
    typeset -g _NIVUUS_UPDATE_LOCK_FD
    local lock_file
    lock_file=$(_nivuus_update_lock_file)
    # zsystem flock opens an existing file only.
    [[ -e "$lock_file" ]] || : >> "$lock_file" || return 1
    zsystem flock -t 0 -f _NIVUUS_UPDATE_LOCK_FD "$lock_file" 2>/dev/null
}

_nivuus_update_unlock() {
    [[ -n "${_NIVUUS_UPDATE_LOCK_FD:-}" ]] || return 0
    zsystem flock -u "$_NIVUUS_UPDATE_LOCK_FD"
    unset _NIVUUS_UPDATE_LOCK_FD
}

# _nivuus_download_release <version> <work dir>
# Leaves <work>/release.tar.gz, verified, or fails with the reason on stderr.
_nivuus_download_release() {
    local version=$1 work=$2
    # The shared nivuus/.github release workflow names the archive after the
    # repository: <repo-name>-<version>.tar.gz (e.g. shell-3.2.1.tar.gz).
    local archive_name="${NIVUUS_GITHUB_REPO##*/}-${version}.tar.gz"
    local base_url="https://github.com/$NIVUUS_GITHUB_REPO/releases/download/v${version}"
    local archive="$work/release.tar.gz"

    echo "📥 Downloading release v${version}..." >&2
    if ! curl -fsSL -o "$archive" "$base_url/$archive_name"; then
        echo "❌ Failed to download release archive" >&2
        return 1
    fi

    # Verification fails CLOSED: being unable to fetch or match a checksum or
    # an attestation aborts the install, so a network failure cannot be used
    # to skip it.
    if [[ "$NIVUUS_VERIFY_CHECKSUMS" == "true" ]]; then
        echo "🔐 Verifying checksums..." >&2
        if ! curl -fsSL -o "$work/SHA256SUMS" "$base_url/SHA256SUMS"; then
            echo "❌ Could not download checksums (verification required, aborting)" >&2
            echo "   Set NIVUUS_VERIFY_CHECKSUMS=false to bypass at your own risk." >&2
            return 1
        fi
        local expected_sum actual_sum
        expected_sum=$(awk -v name="$archive_name" '$2 == name {print $1}' "$work/SHA256SUMS")
        if [[ -z "$expected_sum" ]]; then
            echo "❌ No checksum found for ${archive_name} (aborting)" >&2
            return 1
        fi
        actual_sum=$(sha256sum "$archive" | awk '{print $1}')
        if [[ "$expected_sum" != "$actual_sum" ]]; then
            echo "❌ Checksum verification failed!" >&2
            echo "   Expected: $expected_sum" >&2
            echo "   Got:      $actual_sum" >&2
            return 1
        fi
        echo "✅ Checksum verified" >&2
    fi

    _nivuus_verify_attestation "$archive"
}

# The checksum comes from the same release as the archive: whoever can
# replace one can replace both. The attestation is signed through Sigstore
# with the identity of the workflow run that built the archive, so it is
# checked against the expected signer workflow and source branch.
_nivuus_verify_attestation() {
    local archive=$1
    if [[ "$NIVUUS_VERIFY_ATTESTATION" != "true" ]]; then
        echo "⚠️  Provenance NOT verified (NIVUUS_VERIFY_ATTESTATION=$NIVUUS_VERIFY_ATTESTATION)" >&2
        return 0
    fi
    echo "🔏 Verifying build provenance..." >&2
    if ! (( $+commands[gh] )); then
        NIVUUS_UPDATE_REMEDY=$(_nivuus_gh_remedy)
        echo "❌ Cannot verify the release provenance: the GitHub CLI (gh) is not installed (aborting)" >&2
        echo "   Run: $NIVUUS_UPDATE_REMEDY (or set NIVUUS_VERIFY_ATTESTATION=false to bypass at your own risk)" >&2
        return 1
    fi
    local report rc=0
    report=$(gh attestation verify "$archive" \
            --repo "$NIVUUS_GITHUB_REPO" \
            --signer-workflow "$NIVUUS_RELEASE_SIGNER_WORKFLOW" \
            --source-ref "$NIVUUS_RELEASE_SOURCE_REF" \
            --deny-self-hosted-runners 2>&1) || rc=$?
    # gh exits 4 when it has no credentials: the attestation API needs them.
    if (( rc == 4 )); then
        NIVUUS_UPDATE_REMEDY="gh auth login && nivuus-update"
        echo "❌ Cannot verify the release provenance: gh is not logged in to GitHub (aborting)" >&2
        echo "   Run: $NIVUUS_UPDATE_REMEDY" >&2
        return 1
    fi
    if (( rc != 0 )); then
        echo "❌ Build provenance verification failed (aborting):" >&2
        print -r -- "$report" | sed 's/^/   /' >&2
        return 1
    fi
    echo "✅ Provenance verified: built by $NIVUUS_RELEASE_SIGNER_WORKFLOW from $NIVUUS_GITHUB_REPO@$NIVUUS_RELEASE_SOURCE_REF" >&2
}

# _nivuus_stage_release <version> <work dir>
# Extracts <work>/release.tar.gz into <work>/new and proves it can replace
# the live tree.
_nivuus_stage_release() {
    local version=$1 work=$2
    local new="$work/new"

    mkdir "$new" || return 1
    # --no-same-owner: as root, tar would otherwise keep the uid of the
    # release builder, handing root's shell files to whichever local account
    # has that uid.
    if ! tar -xzf "$work/release.tar.gz" --no-same-owner -C "$new"; then
        echo "❌ Failed to extract release archive" >&2
        return 1
    fi

    local entry
    for entry in .zshrc config/00-core.zsh; do
        if [[ ! -f "$new/$entry" ]]; then
            echo "❌ The release archive has no $entry: not a Nivuus Shell tree (aborting)" >&2
            return 1
        fi
    done
    if ! zsh -n "$new/.zshrc"; then
        echo "❌ The release's .zshrc does not parse (aborting)" >&2
        return 1
    fi

    # User files that live inside the install survive the swap.
    if [[ -f "$NIVUUS_SHELL_DIR/.zsh_local" ]]; then
        cp -p "$NIVUUS_SHELL_DIR/.zsh_local" "$new/.zsh_local" || return 1
    fi
    print -r -- "$version" > "$new/.version" || return 1

    if [[ -d "$new/bin" ]]; then
        chmod +x "$new/bin"/*(N.) || return 1
    fi

    # zcompile parses each module: a module that fails here would fail in
    # every shell after the swap.
    local file
    for file in "$new"/**/*.zsh(N.); do
        if ! zcompile "$file"; then
            echo "❌ ${file#$new/} does not compile (aborting)" >&2
            return 1
        fi
    done

    # The work directory is created 0700; the tree that replaces the install
    # takes the install's own mode (0755 for a system install that every
    # user's shell reads).
    local -a mode
    zstat -A mode +mode "$NIVUUS_SHELL_DIR" || return 1
    chmod $(( [##8] mode[1] & 8#7777 )) "$new" || return 1
}

# _nivuus_swap_release <work dir>
# Renames the live tree to <work>/old and <work>/new into its place.
_nivuus_swap_release() {
    local work=$1
    if ! mv -- "$NIVUUS_SHELL_DIR" "$work/old"; then
        echo "❌ Could not move the current installation aside; nothing was changed" >&2
        return 1
    fi
    if ! mv -- "$work/new" "$NIVUUS_SHELL_DIR"; then
        echo "❌ Could not move the new release into place" >&2
        if mv -- "$work/old" "$NIVUUS_SHELL_DIR"; then
            echo "↩️  Previous installation put back" >&2
        else
            echo "❌ Could not put the previous installation back: it is at $work/old, move it to $NIVUUS_SHELL_DIR by hand" >&2
        fi
        return 1
    fi
}

# _nivuus_install_release <version>
# Download, verify, stage and swap. The caller holds the update lock.
_nivuus_install_release() {
    local version=$1

    if ! _nivuus_valid_version "$version"; then
        echo "❌ Refusing release version '$version': not X.Y.Z" >&2
        return 1
    fi
    # Refuse to replace a git checkout, whatever the caller did.
    if _nivuus_is_dev_checkout; then
        echo "❌ Refusing to overwrite a git checkout at $NIVUUS_SHELL_DIR" >&2
        return 1
    fi

    local work
    if ! work=$(mktemp -d "${NIVUUS_SHELL_DIR}.update.XXXXXX"); then
        echo "❌ Cannot create a work directory next to $NIVUUS_SHELL_DIR" >&2
        return 1
    fi

    local -i rc=0
    _nivuus_install_release_in "$version" "$work" || rc=$?
    # A failed swap whose undo failed too leaves the only copy of the
    # previous tree in <work>/old: that directory is the user's install now.
    if [[ -d "$work/old" && ! -e "$NIVUUS_SHELL_DIR" ]]; then
        return rc
    fi
    if ! rm -rf -- "$work"; then
        echo "⚠️  Could not remove the work directory $work" >&2
    fi
    return rc
}

_nivuus_install_release_in() {
    local version=$1 work=$2
    _nivuus_download_release "$version" "$work" || return 1
    echo "📦 Installing Nivuus Shell v${version}..."
    _nivuus_stage_release "$version" "$work" || return 1
    _nivuus_swap_release "$work" || return 1
    echo "✅ Installation complete!"
}
