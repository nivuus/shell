#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin" "$TMP/emptybin"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    # zsh factice, et faux chsh qui écrit le shell demandé au lieu de muter le système.
    printf '#!/bin/sh\n:\n' > "$TMP/bin/zsh"; chmod +x "$TMP/bin/zsh"
    printf '#!/bin/sh\nprintf "%%s\\n" "$2" > "%s/loginshell"\n' "$TMP" > "$TMP/bin/chsh"
    chmod +x "$TMP/bin/chsh"
    printf '/bin/bash\n' > "$TMP/loginshell"
    printf '/bin/sh\n/bin/bash\n%s/bin/zsh\n' "$TMP" > "$TMP/shells"
    export NIVUUS_MANIFEST_TMP="$TMP/manifest.tsv"; : > "$NIVUUS_MANIFEST_TMP"
}

teardown() { rm -rf "$TMP"; }

chsh_run() {   # chsh_run "<préambule>" -> exécute nivuus_step_chsh
    run env PATH="$TMP/bin:$PATH" HOME="$HOME" \
        NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" \
        NIVUUS_ETC_SHELLS="$TMP/shells" \
        NIVUUS_MANIFEST_TMP="$NIVUUS_MANIFEST_TMP" \
        NIVUUS_BREW_ARM="$TMP/none" NIVUUS_BREW_INTEL="$TMP/none2" \
        bash -c "$1 source '$LIB/log.sh'; source '$LIB/detect.sh'; \
                 source '$LIB/manifest.sh'; source '$LIB/steps.sh'; \
                 nivuus_step_chsh '$TMP/bin/zsh' 2>&1"
}

@test "chsh switches the login shell and records the original" {
    chsh_run ""
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/loginshell")" = "$TMP/bin/zsh" ]
    run grep -c "^CHSH" "$NIVUUS_MANIFEST_TMP"
    [ "$output" = "1" ]
    run grep "^CHSH" "$NIVUUS_MANIFEST_TMP"
    [[ "$output" == *"/bin/bash"* ]]
}

@test "chsh does nothing when zsh is not listed in /etc/shells" {
    printf '/bin/sh\n/bin/bash\n' > "$TMP/shells"
    chsh_run ""
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/loginshell")" = "/bin/bash" ]     # inchangé
    [ ! -s "$NIVUUS_MANIFEST_TMP" ]                  # rien journalisé
    [[ "$output" == *"/etc/shells"* || "$output" == *"shells"* ]]
    [[ "$output" == *"tee"* ]]                       # la commande exacte est donnée
}

@test "chsh never runs sudo by itself" {
    printf '/bin/sh\n' > "$TMP/shells"
    printf '#!/bin/sh\n: > "%s/SUDO_RAN"\n' "$TMP" > "$TMP/bin/sudo"; chmod +x "$TMP/bin/sudo"
    chsh_run ""
    [ ! -f "$TMP/SUDO_RAN" ]
}

@test "chsh is a no-op when zsh is already the login shell" {
    printf '%s/bin/zsh\n' "$TMP" > "$TMP/loginshell"
    chsh_run ""
    [ "$status" -eq 0 ]
    [ ! -s "$NIVUUS_MANIFEST_TMP" ]
}

@test "chsh in dry-run changes nothing and records nothing" {
    chsh_run "export NIVUUS_DRY_RUN=1;"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/loginshell")" = "/bin/bash" ]
    [ ! -s "$NIVUUS_MANIFEST_TMP" ]
    [[ "$output" == *"dry-run"* ]]
}

@test "a failing chsh is reported but never fails the install" {
    printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/chsh"; chmod +x "$TMP/bin/chsh"
    chsh_run ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"chsh"* ]]
}

@test "chsh warns and returns 0 when no zsh exists" {
    run env PATH="$TMP/emptybin" HOME="$HOME" \
        NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" NIVUUS_ETC_SHELLS="$TMP/shells" \
        NIVUUS_MANIFEST_TMP="$NIVUUS_MANIFEST_TMP" \
        NIVUUS_BREW_ARM="$TMP/none" NIVUUS_BREW_INTEL="$TMP/none2" \
        "$(command -v bash)" -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 source '$LIB/steps.sh'; nivuus_step_chsh '' 2>&1"
    [ "$status" -eq 0 ]
}
