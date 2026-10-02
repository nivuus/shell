#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/detect.sh"
    source "$LIB/manifest.sh"; source "$LIB/zshrc.sh"; source "$LIB/deps.sh"
    source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"

    # Faux arbre source
    SRC="$TMP/src"
    mkdir -p "$SRC/config" "$SRC/themes" "$SRC/bin"
    printf 'core\n'  > "$SRC/config/00-core.zsh"
    printf 'junk\n'  > "$SRC/config/00-core.zsh.zwc"
    printf 'nord\n'  > "$SRC/themes/nord.zsh"
    printf 'hc\n'    > "$SRC/bin/healthcheck"
    printf 'main\n'  > "$SRC/.zshrc"
    printf '3.0.0\n' > "$SRC/.version"
}

teardown() { rm -rf "$TMP"; }

@test "copy_tree propagates a failure instead of reporting success" {
    # Force nivuus_install_file to fail on config/00-core.zsh: its parent
    # directory in the target ("config") is pre-created as a plain FILE, so
    # mkdir -p (and then cp) cannot possibly succeed, root or not.
    mkdir -p "$TMP/install"
    printf 'not a directory\n' > "$TMP/install/config"
    run nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ "$status" -ne 0 ]
}

@test "copy_tree tolerates a source path with glob metacharacters" {
    GLOBSRC="$TMP/weird[1]"
    mkdir -p "$GLOBSRC/config"
    printf 'core\n' > "$GLOBSRC/config/00-core.zsh"
    nivuus_step_copy_tree "$GLOBSRC" "$TMP/install2"
    # The relative path must be stripped correctly: the file lands at
    # config/00-core.zsh under the target, not re-nested under the
    # (glob-matched) source path.
    [ -f "$TMP/install2/config/00-core.zsh" ]
    [ ! -d "$TMP/install2/tmp" ]
}

@test "copy_tree copies config, themes and bin" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/config/00-core.zsh" ]
    [ -f "$TMP/install/themes/nord.zsh" ]
    [ -f "$TMP/install/bin/healthcheck" ]
    [ -f "$TMP/install/.zshrc" ]
}

@test "copy_tree excludes .zwc files" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ ! -f "$TMP/install/config/00-core.zsh.zwc" ]
}

@test "copy_tree records every copied file in the manifest" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    run grep -c "00-core.zsh" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "copy_tree is idempotent: a second run records nothing new" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    first="$(grep -c . "$NIVUUS_MANIFEST")"
    nivuus_manifest_begin user "$TMP/install"
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    second="$(grep -c . "$NIVUUS_MANIFEST")"
    [ "$second" -lt "$first" ]
}

@test "write_zshrc preserves existing user content" {
    printf 'export MINE=1\n' > "$TMP/.zshrc"
    nivuus_step_write_zshrc "$TMP/.zshrc" "$TMP/install"
    run grep -c "export MINE=1" "$TMP/.zshrc"
    [ "$output" = "1" ]
    run grep -c ">>> nivuus shell >>>" "$TMP/.zshrc"
    [ "$output" = "1" ]
}

@test "write_zshrc creates the file when absent" {
    nivuus_step_write_zshrc "$TMP/new-zshrc" "$TMP/install"
    [ -f "$TMP/new-zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$TMP/new-zshrc"
    [ "$output" = "1" ]
}

@test "write_zshrc fails on a corrupt file without modifying it" {
    printf '# >>> nivuus shell >>>\nbroken\n' > "$TMP/.zshrc"
    before="$(cat "$TMP/.zshrc")"
    run nivuus_step_write_zshrc "$TMP/.zshrc" "$TMP/install"
    [ "$status" -eq 1 ]
    [ "$(cat "$TMP/.zshrc")" = "$before" ]
}

@test "write_version writes the version file" {
    nivuus_step_write_version "$SRC" "$TMP/install"
    [ "$(cat "$TMP/install/.version")" = "3.0.0" ]
}

@test "check_required_deps succeeds when zsh, git and curl are present" {
    if ! command -v zsh >/dev/null || ! command -v git >/dev/null || ! command -v curl >/dev/null; then
        skip "dépendances absentes dans cet environnement"
    fi
    run nivuus_step_check_required_deps
    [ "$status" -eq 0 ]
}

@test "check_required_deps fails and reports when dependencies are missing" {
    mkdir -p "$TMP/emptybin"
    run bash -c "
        PATH='$TMP/emptybin'
        source '$LIB/log.sh'
        source '$LIB/steps.sh'
        nivuus_step_check_required_deps
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
}

@test "check_required_deps never executes any package manager" {
    for mgr in apt-get dnf pacman brew; do
        rm -rf "$TMP/fakebin" "$TMP"/EXECUTED-*
        mkdir -p "$TMP/fakebin"
        for tool in sudo "$mgr"; do
            printf '#!/bin/sh\n: > "%s/EXECUTED-%s"\n' "$TMP" "$tool" > "$TMP/fakebin/$tool"
            chmod +x "$TMP/fakebin/$tool"
        done
        run bash -c "
            PATH='$TMP/fakebin'
            source '$LIB/log.sh'
            source '$LIB/steps.sh'
            nivuus_step_check_required_deps
        "
        [ "$status" -eq 1 ]
        [[ "$output" == *"$mgr"* ]]          # la bonne commande est bien suggérée
        run ls "$TMP"
        [[ "$output" != *"EXECUTED-"* ]]     # ...mais jamais exécutée
    done
}

# ---------------------------------------------------------------------------
# Paquets système (nivuus_step_install_packages)
# ---------------------------------------------------------------------------

# Un faux PATH : un gestionnaire de paquets qui journalise ses appels et
# "installe" en créant un exécutable vide, un faux sudo qui journalise puis
# exécute, et les outils de base dont le code a besoin.
_fake_pkg_env() {
    local mgr="$1"
    rm -rf "$TMP/fakebin" "$TMP"/CALLS-*
    mkdir -p "$TMP/fakebin"
    cat > "$TMP/fakebin/$mgr" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-$mgr"
for a in "\$@"; do
    case "\$a" in
        -*|install|add|update|-S) ;;
        FAIL-*) exit 1 ;;
        *) printf '#!/bin/sh\n' > "$TMP/fakebin/\$a"; chmod +x "$TMP/fakebin/\$a" ;;
    esac
done
EOF
    chmod +x "$TMP/fakebin/$mgr"
    cat > "$TMP/fakebin/sudo" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-sudo"
while [ \$# -gt 0 ]; do
    case "\$1" in -u) shift 2 ;; -*) shift ;; *) break ;; esac
done
[ \$# -gt 0 ] || exit 0
exec "\$@"
EOF
    chmod +x "$TMP/fakebin/sudo"
    for t in sh env printf cat grep sed awk cut head tail tr mktemp cp mv rm mkdir dirname sha256sum shasum id date wc readlink chmod uname; do
        p="$(command -v "$t" 2>/dev/null)" || continue
        ln -sf "$p" "$TMP/fakebin/$t"
    done
}

@test "install_packages required installs the missing tools via sudo when not root" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=1000
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh git curl && nivuus_manifest_commit"
    [ "$status" -eq 0 ]
    # bats has no terminal: the sudo is the non-interactive one (-n).
    grep -q "^-n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zsh git curl$" "$TMP/CALLS-sudo"
    grep -q "^update -qq$" "$TMP/CALLS-apt-get"        # l'index est rafraîchi d'abord
    [ -x "$TMP/fakebin/zsh" ]
    run grep -c "^PKG" "$TMP/state/manifest.tsv"
    [ "$output" = "3" ]
    grep -q "^PKG	zsh	-	apt-get$" "$TMP/state/manifest.tsv"
}

@test "install_packages runs the manager directly when root" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=0
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-sudo" ]
    grep -q "install -y --no-install-recommends zsh" "$TMP/CALLS-apt-get"
}

@test "install_packages does nothing when nothing is missing" {
    _fake_pkg_env apt-get
    printf '#!/bin/sh\n' > "$TMP/fakebin/zsh"; chmod +x "$TMP/fakebin/zsh"
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=0
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-apt-get" ]
}

@test "install_packages required fails loudly with the exact command when the manager fails" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=0
    # Le faux apt-get échoue sur un paquet nommé FAIL-* : on fait passer zsh
    # pour un tel paquet via le mapping... impossible proprement ; on remplace
    # donc le faux gestionnaire par un qui échoue toujours.
    printf '#!/bin/sh\nexit 100\n' > "$TMP/fakebin/apt-get"
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"apt-get install -y --no-install-recommends zsh"* ]]
}

@test "install_packages optional keeps going past an unavailable package" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=0
    # eza indisponible (dépôts trop vieux) : le faux apt-get échoue dessus.
    cat > "$TMP/fakebin/apt-get" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-apt-get"
case "\$*" in *eza*) exit 100 ;; esac
EOF
    chmod +x "$TMP/fakebin/apt-get"
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages optional eza bat fd && nivuus_manifest_commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"eza"* ]]                          # signalé...
    ! grep -q "^PKG	eza" "$TMP/state/manifest.tsv"      # ...mais pas journalisé
    grep -q "^PKG	bat	-	apt-get$" "$TMP/state/manifest.tsv"
    grep -q "^PKG	fd-find	-	apt-get$" "$TMP/state/manifest.tsv"
}

@test "install_packages skips a tool the manager does not package instead of failing" {
    _fake_pkg_env zypper
    export NIVUUS_PKG_MANAGER=zypper NIVUUS_UID=0
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages optional timg"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-zypper" ]
}

@test "install_packages in dry-run executes nothing and reports the commands" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=1000 NIVUUS_DRY_RUN=1
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh && nivuus_step_install_packages optional bat"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-apt-get" ]
    [ ! -f "$TMP/CALLS-sudo" ]
    [[ "$output" == *"[dry-run]"*"apt-get install -y --no-install-recommends zsh"* ]]
    [[ "$output" == *"[dry-run]"*"apt-get install -y --no-install-recommends bat"* ]]
}

@test "install_packages never prefixes brew with sudo" {
    _fake_pkg_env brew
    export NIVUUS_PKG_MANAGER=brew NIVUUS_UID=1000
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-sudo" ]
    grep -q "^install zsh$" "$TMP/CALLS-brew"
}

@test "install_packages required without any package manager fails with a clear message" {
    _fake_pkg_env apt-get
    rm -f "$TMP/fakebin/apt-get"
    unset NIVUUS_PKG_MANAGER
    export NIVUUS_UID=0
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
}

# ---------------------------------------------------------------------------
# Shell de connexion (nivuus_step_chsh, nivuus_human_users)
# ---------------------------------------------------------------------------

_fake_users_env() {
    mkdir -p "$TMP/etc" "$TMP/home/alice" "$TMP/home/bob" "$TMP/fakebin"
    printf '/bin/sh\n/bin/bash\n/usr/bin/zsh\n' > "$TMP/etc/shells"
    cat > "$TMP/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1::/usr/sbin:/usr/sbin/nologin
svc:x:999:999::/nonexistent:/usr/sbin/nologin
alice:x:1000:1000::$TMP/home/alice:/bin/bash
bob:x:1001:1001::$TMP/home/bob:/usr/bin/zsh
ghost:x:1002:1002::$TMP/home/ghost:/bin/bash
locked:x:1003:1003::$TMP/home/alice:/usr/sbin/nologin
nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin
EOF
    printf 'UID_MIN 1000\nUID_MAX 60000\n' > "$TMP/login.defs"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/CALLS-chsh"\n' "$TMP" > "$TMP/fakebin/chsh"
    printf '#!/bin/sh\n' > "$TMP/fakebin/zsh"
    chmod +x "$TMP/fakebin/chsh" "$TMP/fakebin/zsh"
    export NIVUUS_ETC_DIR="$TMP/etc" NIVUUS_PASSWD="$TMP/passwd" NIVUUS_LOGIN_DEFS="$TMP/login.defs"
    export PATH="$TMP/fakebin:$PATH"
}

@test "human_users lists root and the regular accounts with a home and a real shell" {
    _fake_users_env
    run nivuus_human_users
    [ "$output" = "root
alice
bob" ]
}

@test "chsh as root switches a user to zsh and journals the previous shell" {
    _fake_users_env
    export NIVUUS_UID=0
    nivuus_step_chsh alice
    nivuus_manifest_commit
    # Le zsh retenu est un zsh listé dans /etc/shells (/usr/bin/zsh s'il
    # existe sur la machine de test, sinon le faux du PATH, ajouté à la liste).
    grep -qE "^-s /.*zsh alice$" "$TMP/CALLS-chsh"
    grep -qE "^CHSH	alice	/.*zsh	/bin/bash$" "$NIVUUS_MANIFEST"
}

@test "chsh leaves a user already on zsh alone" {
    _fake_users_env
    export NIVUUS_UID=0
    nivuus_step_chsh bob
    nivuus_manifest_commit
    [ ! -f "$TMP/CALLS-chsh" ]
    ! grep -q "^CHSH" "$NIVUUS_MANIFEST"
}

@test "chsh adds zsh to /etc/shells first when it is missing, as a journaled MODIFY" {
    _fake_users_env
    printf '/bin/sh\n/bin/bash\n' > "$TMP/etc/shells"
    export NIVUUS_UID=0
    nivuus_step_chsh alice
    nivuus_manifest_commit
    grep -qxF "$TMP/fakebin/zsh" "$TMP/etc/shells"
    grep -q "^MODIFY	$TMP/etc/shells	" "$NIVUUS_MANIFEST"
    grep -q "^CHSH	alice	" "$NIVUUS_MANIFEST"
}

@test "chsh without root and without a terminal only prints the command" {
    _fake_users_env
    export NIVUUS_UID=1000
    run bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_chsh \"\$(id -un)\"" </dev/null
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-chsh" ]
    [[ "$output" == *"chsh -s"* ]]
}

@test "chsh in dry-run executes nothing but journals the intent" {
    _fake_users_env
    export NIVUUS_UID=0 NIVUUS_DRY_RUN=1
    run nivuus_step_chsh alice
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-chsh" ]
    [[ "$output" == *"[dry-run]"*"chsh -s"*"alice"* ]]
}

@test "chsh_all_users covers every human account and nothing else" {
    _fake_users_env
    export NIVUUS_UID=0
    nivuus_step_chsh_all_users
    nivuus_manifest_commit
    run grep -c "^CHSH" "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]                              # root et alice ; bob est déjà sous zsh
    ! grep -q "svc\|daemon\|ghost\|locked\|nobody" "$TMP/CALLS-chsh"
}

@test "write_zshrc with position bottom appends the block" {
    printf 'bindkey -e\n' > "$TMP/global"
    nivuus_step_write_zshrc "$TMP/global" "$TMP/install" bottom
    [ "$(head -n1 "$TMP/global")" = "bindkey -e" ]
    [ "$(tail -n1 "$TMP/global")" = "# <<< nivuus shell <<<" ]
}

@test "install_packages never prompts again once sudo was refused (sudo -n)" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=1000 NIVUUS_SUDO_REFUSED=1
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages optional bat fd"
    [ "$status" -eq 0 ]
    ! grep -qv "^-n " "$TMP/CALLS-sudo"              # every sudo call is non-interactive
}

@test "install_packages uses a non-interactive sudo without a terminal" {
    _fake_pkg_env apt-get
    export NIVUUS_PKG_MANAGER=apt-get NIVUUS_UID=1000
    unset NIVUUS_SUDO_REFUSED
    run bash -c "PATH='$TMP/fakebin'; source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'
        NIVUUS_STATE_DIR='$TMP/state'; nivuus_manifest_begin user '$TMP/install'
        nivuus_step_install_packages required zsh" </dev/null
    [ "$status" -eq 0 ]
    grep -q "^-n env DEBIAN_FRONTEND=noninteractive apt-get install" "$TMP/CALLS-sudo"
}
