#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"
}

teardown() { rm -rf "$TMP"; }

@test "CREATE is removed when the hash still matches" {
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/created"
    nivuus_manifest_commit
    nivuus_manifest_rollback
    [ ! -e "$TMP/created" ]
}

@test "CREATE is kept when the user modified it" {
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/created"
    nivuus_manifest_commit
    printf 'user edit' > "$TMP/created"
    nivuus_manifest_rollback
    [ -f "$TMP/created" ]
    [ "$(cat "$TMP/created")" = "user edit" ]
}

@test "MODIFY restores the original content" {
    printf 'original' > "$TMP/target"
    printf 'nivuus'   > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/target"
    nivuus_manifest_commit
    [ "$(cat "$TMP/target")" = "nivuus" ]
    nivuus_manifest_rollback
    [ "$(cat "$TMP/target")" = "original" ]
}

@test "MODIFY leaves the file alone when it diverged after install" {
    printf 'original' > "$TMP/target"
    printf 'nivuus'   > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/target"
    nivuus_manifest_commit
    printf 'user edit' > "$TMP/target"
    nivuus_manifest_rollback
    [ "$(cat "$TMP/target")" = "user edit" ]
}

@test "MKDIR is removed only when empty" {
    nivuus_mkdir_p "$TMP/d/e"
    nivuus_manifest_commit
    nivuus_manifest_rollback
    [ ! -d "$TMP/d/e" ]
    [ ! -d "$TMP/d" ]
}

@test "MKDIR survives when it holds a foreign file" {
    nivuus_mkdir_p "$TMP/d"
    nivuus_manifest_commit
    printf 'foreign' > "$TMP/d/keep"
    nivuus_manifest_rollback
    [ -d "$TMP/d" ]
    [ -f "$TMP/d/keep" ]
}

@test "CHSH restoration runs chsh itself but never sudo" {
    mkdir -p "$TMP/fakebin"
    printf '#!/bin/sh\n: > "%s/EXECUTED-chsh"\n' "$TMP" > "$TMP/fakebin/chsh"
    printf '#!/bin/sh\n: > "%s/EXECUTED-sudo"\n' "$TMP" > "$TMP/fakebin/sudo"
    chmod +x "$TMP/fakebin/chsh" "$TMP/fakebin/sudo"
    printf '/usr/bin/zsh\n' > "$TMP/loginshell"

    nivuus_manifest_record CHSH "$HOME" - /bin/bash
    nivuus_manifest_commit

    # Le vrai PATH reste accessible (nivuus_manifest_each dépend de grep/sed
    # externes) mais fakebin passe devant : le faux chsh masque le vrai.
    run bash -c "
        PATH='$TMP/fakebin:$PATH'
        NIVUUS_LOGIN_SHELL_FILE='$TMP/loginshell'
        source '$LIB/log.sh'
        source '$LIB/detect.sh'
        source '$LIB/manifest.sh'
        NIVUUS_MANIFEST='$NIVUUS_MANIFEST'
        NIVUUS_BACKUP_DIR='$NIVUUS_BACKUP_DIR'
        nivuus_manifest_rollback
    "
    [ "$status" -eq 0 ]
    run ls "$TMP"
    [[ "$output" == *"EXECUTED-chsh"* ]]   # la restauration est effective...
    [[ "$output" != *"EXECUTED-sudo"* ]]   # ...sans jamais élever les privilèges
}

@test "PKG entries are ignored by rollback without warning" {
    nivuus_manifest_record PKG fzf - apt-get
    nivuus_manifest_commit
    run nivuus_manifest_rollback
    [ "$status" -eq 0 ]
    [[ "$output" != *"inconnue"* ]]
}

@test "an unknown manifest action warns but does not abort rollback" {
    nivuus_manifest_record BOGUS "$TMP/whatever" - -
    nivuus_manifest_commit
    run nivuus_manifest_rollback
    [ "$status" -eq 0 ]
    [[ "$output" == *"inconnue"* ]]
}

@test "CHSH restore puts the original login shell back" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$2" > "%s/loginshell"\n' "$TMP" > "$TMP/bin/chsh"
    chmod +x "$TMP/bin/chsh"
    printf '/usr/bin/zsh\n' > "$TMP/loginshell"
    printf '/bin/bash\n/usr/bin/zsh\n' > "$TMP/shells"

    run env PATH="$TMP/bin:$PATH" \
        NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" NIVUUS_ETC_SHELLS="$TMP/shells" \
        bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 nivuus_restore_entry CHSH '$HOME' '-' '/bin/bash' 2>&1"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/loginshell")" = "/bin/bash" ]
}

@test "CHSH restore is a no-op when the login shell is already the original" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n: > "%s/CHSH_RAN"\n' "$TMP" > "$TMP/bin/chsh"; chmod +x "$TMP/bin/chsh"
    printf '/bin/bash\n' > "$TMP/loginshell"
    run env PATH="$TMP/bin:$PATH" NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" \
        bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 nivuus_restore_entry CHSH '$HOME' '-' '/bin/bash'"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CHSH_RAN" ]
}

@test "CHSH restore in dry-run changes nothing" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n: > "%s/CHSH_RAN"\n' "$TMP" > "$TMP/bin/chsh"; chmod +x "$TMP/bin/chsh"
    printf '/usr/bin/zsh\n' > "$TMP/loginshell"
    run env PATH="$TMP/bin:$PATH" NIVUUS_DRY_RUN=1 NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" \
        bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 nivuus_restore_entry CHSH '$HOME' '-' '/bin/bash' 2>&1"
    [ ! -f "$TMP/CHSH_RAN" ]
    [[ "$output" == *"dry-run"* ]]
}

@test "CHSH restore explains what to do when chsh is unavailable" {
    mkdir -p "$TMP/emptybin"
    printf '/usr/bin/zsh\n' > "$TMP/loginshell"
    run env PATH="$TMP/emptybin" NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell" \
        "$(command -v bash)" -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 nivuus_restore_entry CHSH '$HOME' '-' '/bin/bash' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chsh -s /bin/bash"* ]]
}
