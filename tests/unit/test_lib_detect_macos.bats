#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/brew/bin" "$TMP/emptybin"
    printf '#!/bin/sh\n:\n' > "$TMP/brew/bin/brew"; chmod +x "$TMP/brew/bin/brew"
    printf '#!/bin/sh\n:\n' > "$TMP/brew/bin/zsh";  chmod +x "$TMP/brew/bin/zsh"
}

teardown() { rm -rf "$TMP"; }

@test "brew_prefix falls back to the arm64 location when brew is not in PATH" {
    run bash -c "PATH='$TMP/emptybin'; NIVUUS_BREW_ARM='$TMP/brew'; NIVUUS_BREW_INTEL='$TMP/none'; \
                 source '$LIB/detect.sh'; nivuus_brew_prefix"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/brew" ]
}

@test "brew_prefix fails cleanly when Homebrew is absent" {
    run bash -c "PATH='$TMP/emptybin'; NIVUUS_BREW_ARM='$TMP/none'; NIVUUS_BREW_INTEL='$TMP/none2'; \
                 source '$LIB/detect.sh'; nivuus_brew_prefix"
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "zsh_path prefers the Homebrew zsh over the system one" {
    mkdir -p "$TMP/sysbin"
    printf '#!/bin/sh\n:\n' > "$TMP/sysbin/zsh"; chmod +x "$TMP/sysbin/zsh"
    run bash -c "PATH='$TMP/sysbin'; NIVUUS_BREW_ARM='$TMP/brew'; NIVUUS_BREW_INTEL='$TMP/none'; \
                 source '$LIB/detect.sh'; nivuus_zsh_path"
    [ "$output" = "$TMP/brew/bin/zsh" ]
}

@test "zsh_path falls back to PATH when Homebrew is absent" {
    mkdir -p "$TMP/sysbin"
    printf '#!/bin/sh\n:\n' > "$TMP/sysbin/zsh"; chmod +x "$TMP/sysbin/zsh"
    run bash -c "PATH='$TMP/sysbin'; NIVUUS_BREW_ARM='$TMP/none'; NIVUUS_BREW_INTEL='$TMP/none2'; \
                 source '$LIB/detect.sh'; nivuus_zsh_path"
    [ "$output" = "$TMP/sysbin/zsh" ]
}

@test "zsh_path fails when no zsh exists at all" {
    run bash -c "PATH='$TMP/emptybin'; NIVUUS_BREW_ARM='$TMP/none'; NIVUUS_BREW_INTEL='$TMP/none2'; \
                 source '$LIB/detect.sh'; nivuus_zsh_path"
    [ "$status" -eq 1 ]
}

@test "shell_is_listed matches whole lines only" {
    printf '/bin/sh\n/bin/bash\n/opt/homebrew/bin/zsh\n' > "$TMP/shells"
    run bash -c "NIVUUS_ETC_SHELLS='$TMP/shells'; source '$LIB/detect.sh'; \
                 nivuus_shell_is_listed /opt/homebrew/bin/zsh"
    [ "$status" -eq 0 ]
    run bash -c "NIVUUS_ETC_SHELLS='$TMP/shells'; source '$LIB/detect.sh'; \
                 nivuus_shell_is_listed /usr/local/bin/zsh"
    [ "$status" -eq 1 ]
    # Le cas macOS + Homebrew : /bin/zsh est listé, pas celui de brew.
    run bash -c "NIVUUS_ETC_SHELLS='$TMP/shells'; source '$LIB/detect.sh'; \
                 nivuus_shell_is_listed /bin/zsh"
    [ "$status" -eq 1 ]
}

@test "shell_is_listed is false when /etc/shells does not exist" {
    run bash -c "NIVUUS_ETC_SHELLS='$TMP/absent'; source '$LIB/detect.sh'; \
                 nivuus_shell_is_listed /bin/zsh"
    [ "$status" -eq 1 ]
}

@test "current_login_shell honours the test hook file" {
    printf '/bin/bash\n' > "$TMP/loginshell"
    run bash -c "NIVUUS_LOGIN_SHELL_FILE='$TMP/loginshell'; source '$LIB/detect.sh'; \
                 nivuus_current_login_shell"
    [ "$output" = "/bin/bash" ]
}

@test "current_login_shell falls back to SHELL when nothing else answers" {
    run bash -c "NIVUUS_LOGIN_SHELL_FILE='$TMP/absent'; SHELL=/bin/fallbacksh; \
                 source '$LIB/detect.sh'; nivuus_current_login_shell"
    [ "$output" = "/bin/fallbacksh" ]
}
