#!/usr/bin/env bats
# End-to-end tests of the release updater (config/20-autoupdate.zsh).
# A fake curl serves a release from a local tree laid out like GitHub, so the
# real nivuus-update runs against an install in a throwaway HOME.

setup() {
    UPDATER="${BATS_TEST_DIRNAME}/../../config/20-autoupdate.zsh"
    WORK="$(mktemp -d)"
    export HOME="$WORK/home"
    export TMPDIR="$WORK/tmp"
    export NIVUUS_SHELL_DIR="$HOME/.nivuus-shell"
    export ENABLE_AUTOUPDATE=false
    export FAKE_SERVER="$WORK/server"
    mkdir -p "$HOME" "$TMPDIR" "$WORK/bin" "$FAKE_SERVER"

    mkdir -p "$NIVUUS_SHELL_DIR/config"
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
    chmod +x "$WORK/bin/curl"
    export PATH="$WORK/bin:$PATH"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# Publish a release the way the shared nivuus/.github workflow does:
# <repo-name>-<version>.tar.gz of a flat tree, plus SHA256SUMS.
publish_release() {
    local version=$1
    local api="$FAKE_SERVER/api.github.com/repos/nivuus/shell/releases"
    local assets="$FAKE_SERVER/github.com/nivuus/shell/releases/download/v${version}"
    mkdir -p "$api" "$assets" "$WORK/tree/config"
    printf '{\n  "tag_name": "v%s",\n  "name": "v%s"\n}\n' "$version" "$version" > "$api/latest"
    echo "$version" > "$WORK/tree/.version"
    echo "new" > "$WORK/tree/config/marker.zsh"
    tar -czf "$assets/shell-${version}.tar.gz" -C "$WORK/tree" .
    (cd "$assets" && sha256sum -- "shell-${version}.tar.gz" > SHA256SUMS)
}

run_update() {
    run zsh -c "source '$UPDATER' && nivuus-update"
}

@test "updates the install to the latest release" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "9.9.9" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/config/marker.zsh")" = "new" ]
}

@test "shows download progress and checksum verification" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading release v9.9.9"* ]]
    [[ "$output" == *"Checksum verified"* ]]
}

@test "keeps the user's .zsh_local" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ "$(cat "$NIVUUS_SHELL_DIR/.zsh_local")" = "MY_SETTING=1" ]
}

@test "leaves no temporary directory behind" {
    publish_release 9.9.9
    run_update
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "aborts on a checksum mismatch and keeps the old version" {
    publish_release 9.9.9
    echo "0000000000000000000000000000000000000000000000000000000000000000  shell-9.9.9.tar.gz" \
        > "$FAKE_SERVER/github.com/nivuus/shell/releases/download/v9.9.9/SHA256SUMS"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum verification failed"* ]]
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "3.0.0" ]
    [ "$(cat "$NIVUUS_SHELL_DIR/config/marker.zsh")" = "old" ]
}

@test "reports a missing archive and keeps the old version" {
    publish_release 9.9.9
    rm "$FAKE_SERVER/github.com/nivuus/shell/releases/download/v9.9.9/shell-9.9.9.tar.gz"
    run_update
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to download release archive"* ]]
    [ "$(cat "$NIVUUS_SHELL_DIR/.version")" = "3.0.0" ]
}

@test "says when it is already up to date" {
    publish_release 3.0.0
    run_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date"* ]]
}
