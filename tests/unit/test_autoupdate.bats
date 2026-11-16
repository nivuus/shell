#!/usr/bin/env bats
# End-to-end tests of the release updater (config/20-autoupdate.zsh and
# config/20-autoupdate-release.zsh). A fake curl serves a release from a
# local tree laid out like GitHub, a fake gh answers `gh attestation verify`
# from a list of attested digests, and the real nivuus-update runs against an
# install in a throwaway HOME.

setup() {
    UPDATER="${BATS_TEST_DIRNAME}/../../config/20-autoupdate.zsh"
    WORK="$(mktemp -d)"
    export HOME="$WORK/home"
    export TMPDIR="$WORK/tmp"
    export NIVUUS_SHELL_DIR="$HOME/.nivuus-shell"
    export XDG_STATE_HOME="$HOME/.local/state"
    export ENABLE_AUTOUPDATE=false
    export FAKE_SERVER="$WORK/server"
    mkdir -p "$HOME" "$TMPDIR" "$WORK/bin" "$FAKE_SERVER/attested"

    mkdir -p "$NIVUUS_SHELL_DIR/config"
    chmod 0755 "$NIVUUS_SHELL_DIR"
    echo "3.0.0" > "$NIVUUS_SHELL_DIR/.version"
    echo "old" > "$NIVUUS_SHELL_DIR/config/marker.zsh"
    echo "MY_SETTING=1" > "$NIVUUS_SHELL_DIR/.zsh_local"

    # Serves https://<host>/<path> from $FAKE_SERVER/<host>/<path>; a missing
    # file answers like `curl -f` on a 404.
    cat > "$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" url=""
while (( $# )); do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -H) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
file="$FAKE_SERVER/${url#https://}"
[[ -f "$file" ]] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
if [[ -n "$out" ]]; then cp "$file" "$out"; else cat "$file"; fi
EOF
    # `gh attestation verify <file> ...`: records its arguments, succeeds when
    # the file's digest was attested by publish_release.
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_SERVER/gh-args"
[[ "$1 $2" == "attestation verify" ]] || exit 2
sum=$(sha256sum "$3" | cut -d' ' -f1)
[[ -f "$FAKE_SERVER/attested/$sum" ]] && { echo "Loaded 1 attestation"; exit 0; }
echo "Error: no attestations found for subject" >&2
exit 1
EOF
    chmod +x "$WORK/bin/curl" "$WORK/bin/gh"
    export PATH="$WORK/bin:$PATH"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# Publish a release the way the shared nivuus/.github workflow does:
# <repo-name>-<version>.tar.gz of a flat tree, SHA256SUMS, and a build
# provenance attestation of the archive.
publish_release() {
    local version=$1
    local api="$FAKE_SERVER/api.github.com/repos/nivuus/shell/releases"
    local assets="$FAKE_SERVER/github.com/nivuus/shell/releases/download/v${version}"
    mkdir -p "$api" "$assets" "$WORK/tree/config"
    printf '{\n  "tag_name": "v%s",\n  "name": "v%s"\n}\n' "$version" "$version" > "$api/latest"
    echo "$version" > "$WORK/tree/.version"
    echo "# entry" > "$WORK/tree/.zshrc"
    echo "# core" > "$WORK/tree/config/00-core.zsh"
    echo "new" > "$WORK/tree/config/marker.zsh"
    seal_release "$version"
}

# (Re)build the archive, its checksum and its attestation from $WORK/tree.
seal_release() {
    local version=$1
    local assets="$FAKE_SERVER/github.com/nivuus/shell/releases/download/v${version}"
    tar -czf "$assets/shell-${version}.tar.gz" -C "$WORK/tree" .
    (cd "$assets" && sha256sum -- "shell-${version}.tar.gz" > SHA256SUMS)
    touch "$FAKE_SERVER/attested/$(sha256sum "$assets/shell-${version}.tar.gz" | cut -d' ' -f1)"
}

run_update() {
    run zsh -c "source '$UPDATER' && nivuus-update"
}

assert_old_install_intact() {
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "3.0.0" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/config/marker.zsh")" = "old" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/.zsh_local")" = "MY_SETTING=1" ]
    # No staging or previous tree left next to the install.
    [ -z "$(ls -A "$HOME" | grep '^\.nivuus-shell\.update\.' | grep -v '\.lock$')" ]
}

@test "updates the install to the latest release" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "9.9.9" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/config/marker.zsh")" = "new" ]
}

@test "shows download progress, checksum and provenance verification" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading release v9.9.9"* ]]
    [[ "$output" == *"Checksum verified"* ]]
    [[ "$output" == *"Provenance verified"* ]]
}

@test "the attestation is checked against the release workflow and main" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    local args
    args="$(tr '\n' ' ' < "$FAKE_SERVER/gh-args")"
    [[ "$args" == "attestation verify "*" --repo nivuus/shell "* ]]
    [[ "$args" == *" --signer-workflow nivuus/.github/.github/workflows/release.yml "* ]]
    [[ "$args" == *" --source-ref refs/heads/main "* ]]
    [[ "$args" == *" --deny-self-hosted-runners "* ]]
}

@test "keeps the user's .zsh_local" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ "$(cat "$NIVUUS_SHELL_DIR/.zsh_local")" = "MY_SETTING=1" ]
}

@test "leaves no temporary or staging directory behind" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$TMPDIR")" ]
    [ -z "$(ls -A "$HOME" | grep '^\.nivuus-shell\.update\.' | grep -v '\.lock$')" ]
}

@test "the new tree keeps the mode of the install it replaces" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$NIVUUS_SHELL_DIR")" = "755" ]
}

@test "aborts on a checksum mismatch and keeps the old version" {
    publish_release 9.9.9
    echo "0000000000000000000000000000000000000000000000000000000000000000  shell-9.9.9.tar.gz" \
        > "$FAKE_SERVER/github.com/nivuus/shell/releases/download/v9.9.9/SHA256SUMS"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum verification failed"* ]]
    assert_old_install_intact
}

@test "aborts on an archive without a provenance attestation" {
    # Archive and SHA256SUMS replaced together: the checksum still matches,
    # only the attestation can tell.
    publish_release 9.9.9
    rm "$FAKE_SERVER/attested/"*
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum verified"* ]]
    [[ "$output" == *"Build provenance verification failed"* ]]
    [[ "$output" == *"no attestations found"* ]]
    assert_old_install_intact
}

@test "aborts when gh is not there to verify the provenance" {
    publish_release 9.9.9
    rm "$WORK/bin/gh"
    if command -v gh >/dev/null; then skip "a real gh is installed on this machine"; fi
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"GitHub CLI (gh) is not installed"* ]]
    assert_old_install_intact
}

@test "provenance verification can be turned off explicitly, and says so" {
    publish_release 9.9.9
    rm "$FAKE_SERVER/attested/"*
    run zsh -c "NIVUUS_VERIFY_ATTESTATION=false; source '$UPDATER' && nivuus-update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Provenance NOT verified"* ]]
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "9.9.9" ]
}

@test "reports a missing archive and keeps the old version" {
    publish_release 9.9.9
    rm "$FAKE_SERVER/github.com/nivuus/shell/releases/download/v9.9.9/shell-9.9.9.tar.gz"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to download release archive"* ]]
    assert_old_install_intact
}

@test "an archive that does not extract leaves the install untouched" {
    publish_release 9.9.9
    local assets="$FAKE_SERVER/github.com/nivuus/shell/releases/download/v9.9.9"
    head -c 200 "$assets/shell-9.9.9.tar.gz" > "$WORK/truncated"
    mv "$WORK/truncated" "$assets/shell-9.9.9.tar.gz"
    (cd "$assets" && sha256sum -- shell-9.9.9.tar.gz > SHA256SUMS)
    touch "$FAKE_SERVER/attested/$(sha256sum "$assets/shell-9.9.9.tar.gz" | cut -d' ' -f1)"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to extract release archive"* ]]
    [[ "$output" == *"v3.0.0 is still installed"* ]]
    assert_old_install_intact
}

@test "a release missing an entry file is refused before the swap" {
    publish_release 9.9.9
    rm "$WORK/tree/config/00-core.zsh"
    seal_release 9.9.9
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"has no config/00-core.zsh"* ]]
    assert_old_install_intact
}

@test "a release with a module that does not parse is refused before the swap" {
    publish_release 9.9.9
    echo 'if [[ x; then' > "$WORK/tree/config/marker.zsh"
    seal_release 9.9.9
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"config/marker.zsh does not compile"* ]]
    assert_old_install_intact
}

@test "a release tag that is not X.Y.Z is refused" {
    publish_release 9.9.9
    printf '{\n  "tag_name": "v9.9.9/../../evil"\n}\n' \
        > "$FAKE_SERVER/api.github.com/repos/nivuus/shell/releases/latest"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not fetch latest version"* ]]
    assert_old_install_intact
}

@test "a failed swap puts the previous installation back" {
    # mv fails only when moving the staged tree into place.
    local real_mv
    real_mv="$(command -v mv)"
    cat > "$WORK/bin/mv" <<EOF2
#!/usr/bin/env bash
case "\${@: -2:1}" in */new) echo "mv: simulated failure" >&2; exit 1 ;; esac
exec "$real_mv" "\$@"
EOF2
    chmod +x "$WORK/bin/mv"
    publish_release 9.9.9
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" != *"Installation complete"* ]]
    [[ "$output" == *"Previous installation put back"* ]]
    assert_old_install_intact
}

@test "says when it is already up to date" {
    publish_release 3.0.0
    run_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date"* ]]
}

# --- One update at a time ---

# Hold the update lock from another process for $1 seconds.
hold_update_lock() {
    touch "${NIVUUS_SHELL_DIR}.update.lock"
    zsh -c "zmodload zsh/system; zsystem flock -f fd '${NIVUUS_SHELL_DIR}.update.lock' || exit 1; touch '$WORK/locked'; sleep $1" &
    local i
    for i in $(seq 50); do [ -e "$WORK/locked" ] && return 0; sleep 0.1; done
    return 1
}

@test "nivuus-update refuses to run while another update holds the lock" {
    publish_release 9.9.9
    hold_update_lock 5
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Another update of $NIVUUS_SHELL_DIR is already running"* ]]
    assert_old_install_intact
}

@test "an automatic update leaves at once while another update holds the lock" {
    publish_release 9.9.9
    hold_update_lock 5
    run zsh -c "source '$UPDATER' && _nivuus_auto_update"
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_STATE_HOME/nivuus-shell/update.log" ]
    assert_old_install_intact
}

@test "two automatic updates started together install the release once" {
    publish_release 9.9.9
    zsh -c "source '$UPDATER' && _nivuus_auto_update" &
    zsh -c "source '$UPDATER' && _nivuus_auto_update" &
    wait
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "9.9.9" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/config/marker.zsh")" = "new" ]
    [ "$(ls -1d "$HOME/.config/nivuus-shell-backup"/pre-update-* | wc -l)" -eq 1 ]
}

# --- Unattended failures are reported ---

@test "a failed automatic update is reported at the next terminal start" {
    publish_release 9.9.9
    rm "$FAKE_SERVER/attested/"*
    run zsh -c "source '$UPDATER' && _nivuus_auto_update"
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_STATE_HOME/nivuus-shell/update.status")" = "failed 9.9.9" ]
    grep -q "Build provenance verification failed" "$XDG_STATE_HOME/nivuus-shell/update.log"
    assert_old_install_intact

    run zsh -c "nivuus_has_terminal() { return 0 }; source '$UPDATER'"
    [[ "$output" == *"automatic update to v9.9.9 failed; v3.0.0 is still installed"* ]]
    [[ "$output" == *"$XDG_STATE_HOME/nivuus-shell/update.log"* ]]
}

@test "a successful update clears the failure report" {
    publish_release 9.9.9
    mkdir -p "$XDG_STATE_HOME/nivuus-shell"
    echo "failed 9.9.9" > "$XDG_STATE_HOME/nivuus-shell/update.status"
    run_update
    [ "$status" -eq 0 ]
    run zsh -c "nivuus_has_terminal() { return 0 }; source '$UPDATER'"
    [[ "$output" != *"failed"* ]]
}

# --- Pre-update backups ---

@test "backup rotation keeps the five newest, including the one just made" {
    local base="$HOME/.config/nivuus-shell-backup" stamp
    for stamp in 20240101-000000 20240201-000000 20240301-000000 \
                 20240401-000000 20240501-000000 20240601-000000; do
        mkdir -p "$base/pre-update-$stamp"
    done
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    local made="${output#*Backup created: }"
    made="${made%%$'\n'*}"
    [ -d "$made/nivuus-shell" ]
    [ ! -d "$base/pre-update-20240101-000000" ]
    [ ! -d "$base/pre-update-20240201-000000" ]
    [ -d "$base/pre-update-20240601-000000" ]
    [ "$(ls -1d "$base"/pre-update-* | wc -l)" -eq 5 ]
}
