#!/usr/bin/env bats
# lib/ doit rester exécutable par un shell POSIX minimal (BusyBox ash sur
# Alpine), pas seulement par bash. bin/nivuus, lui, reste bash.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    POSIX_SH=""
    for c in dash busybox sh; do
        if command -v "$c" >/dev/null 2>&1; then POSIX_SH="$c"; break; fi
    done
}

teardown() { rm -rf "$TMP"; }

posix_sh() {
    if [ "$POSIX_SH" = "busybox" ]; then busybox sh "$@"; else "$POSIX_SH" "$@"; fi
}

@test "every lib file parses under sh -n" {
    for f in "$LIB"/*.sh; do
        run sh -n "$f"
        [ "$status" -eq 0 ] || { echo "sh -n failed on $f: $output"; false; }
    done
}

@test "no lib file uses a process substitution" {
    run grep -n '< *<(' "$LIB"/*.sh
    [ "$status" -ne 0 ]
}

@test "no lib file uses bash arrays or bash-only expansions" {
    run grep -nE '\+=\(|\$\{[A-Za-z_]+\[|\$\{[A-Za-z_]+,,|\$\{[A-Za-z_]+\^\^|BASH_SOURCE|declare -A|mapfile|readarray' "$LIB"/*.sh
    [ "$status" -ne 0 ]
}

@test "the libraries source and run under a POSIX shell" {
    [ -n "$POSIX_SH" ] || skip "no POSIX shell available"
    cat > "$TMP/probe.sh" <<EOF
. "$LIB/log.sh"
. "$LIB/detect.sh"
. "$LIB/deps.sh"
. "$LIB/manifest.sh"
. "$LIB/zshrc.sh"
. "$LIB/steps.sh"
nivuus_detect_os
nivuus_detect_arch
nivuus_hash_file "$TMP/probe.sh" >/dev/null
nivuus_zshrc_block /opt/nivuus | head -n1
EOF
    run posix_sh "$TMP/probe.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus shell"* ]]
}

@test "copy_tree still reports a write failure under a POSIX shell" {
    [ -n "$POSIX_SH" ] || skip "no POSIX shell available"
    mkdir -p "$TMP/src/config" "$TMP/dst"
    printf 'x\n' > "$TMP/src/config/a.zsh"
    cat > "$TMP/probe2.sh" <<EOF
. "$LIB/log.sh"
. "$LIB/manifest.sh"
. "$LIB/steps.sh"
# Écriture impossible : la copie doit retourner 1, pas 0.
nivuus_install_file() { return 1; }
nivuus_mkdir_p() { return 0; }
nivuus_step_copy_tree "$TMP/src" "$TMP/dst"
EOF
    run posix_sh "$TMP/probe2.sh"
    [ "$status" -eq 1 ]
}
