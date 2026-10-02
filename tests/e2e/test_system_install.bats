#!/usr/bin/env bats
# Installation système (--system) : tout se joue dans une fausse racine
# ($TMP/root) via les variables NIVUUS_* de lib/detect.sh. Rien ici ne
# touche /etc, /usr ni /var, et rien ne demande de vrai privilège : sudo et
# chsh sont des faux qui journalisent leurs appels.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    R="$TMP/root"
    mkdir -p "$R/etc/zsh" "$R/home/alice" "$TMP/home" "$TMP/fakebin"
    printf '# distro defaults\nbindkey -e\n' > "$R/etc/zsh/zshrc"
    printf '/bin/sh\n/bin/bash\n/usr/bin/zsh\n' > "$R/etc/shells"
    cat > "$TMP/passwd" <<EOP
root:x:0:0:root:/root:/bin/bash
svc:x:999:999::/nonexistent:/usr/sbin/nologin
alice:x:1000:1000::$R/home/alice:/bin/bash
EOP
    printf 'UID_MIN 1000\nUID_MAX 60000\n' > "$TMP/login.defs"
    # Fake chsh: journals the call and, like the real one, updates the
    # (fake) passwd so a later uninstall sees the shell Nivuus set.
    cat > "$TMP/fakebin/chsh" <<EOP
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-chsh"
[ "\$1" = "-s" ] && [ -n "\$3" ] || exit 0
awk -F: -v OFS=: -v u="\$3" -v s="\$2" '\$1 == u { \$7 = s } 1' "$TMP/passwd" > "$TMP/passwd.new" \\
    && mv "$TMP/passwd.new" "$TMP/passwd"
EOP
    cat > "$TMP/fakebin/sudo" <<EOP
#!/bin/sh
# Faux sudo : journalise, saute ses options (-n, -v, -E, -u USER...) et
# exécute la commande tel quel. « sudo -v » / « sudo -n true » réussissent.
printf '%s\n' "\$*" >> "$TMP/CALLS-sudo"
while [ \$# -gt 0 ]; do
    case "\$1" in
        -u) shift 2 ;;
        -*) shift ;;
        *)  break ;;
    esac
done
[ \$# -gt 0 ] || exit 0
exec "\$@"
EOP
    cat > "$TMP/fakebin/apt-get" <<EOP
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-apt-get"
EOP
    chmod +x "$TMP/fakebin/chsh" "$TMP/fakebin/sudo" "$TMP/fakebin/apt-get"
    export PATH="$TMP/fakebin:$PATH"
    export HOME="$TMP/home"
    export NIVUUS_ETC_DIR="$R/etc"
    export NIVUUS_SYSTEM_PREFIX="$R/usr/local/share/nivuus-shell"
    export NIVUUS_SYSTEM_STATE_DIR="$R/var/lib/nivuus"
    export NIVUUS_PASSWD="$TMP/passwd"
    export NIVUUS_LOGIN_DEFS="$TMP/login.defs"
    export NIVUUS_PKG_MANAGER=apt-get
    unset NIVUUS_STATE_DIR NIVUUS_SYSTEM_ZSHRC NIVUUS_DRY_RUN NIVUUS_MINIMAL
    export NIVUUS_UID=0
}

teardown() { rm -rf "$TMP"; }

@test "install --system lands in the system prefix and the global zshrc, after the distro defaults" {
    run "$NIVUUS" install --system --yes --minimal
    [ "$status" -eq 0 ]
    [ -f "$R/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    [ -f "$R/usr/local/share/nivuus-shell/lib/deps.sh" ]
    [ "$(head -n1 "$R/etc/zsh/zshrc")" = "# distro defaults" ]
    run grep -c ">>> nivuus shell >>>" "$R/etc/zsh/zshrc"
    [ "$output" = "1" ]
    grep -q "NIVUUS_SHELL_DIR=\"$R/usr/local/share/nivuus-shell\"" "$R/etc/zsh/zshrc"
    # Le ~/.zshrc de l'utilisateur courant n'est pas touché : tout passe par le global.
    [ ! -e "$HOME/.zshrc" ]
    head -n1 "$R/var/lib/nivuus/manifest.tsv" | grep -q "mode=system"
}

@test "install --system falls back to /etc/zshrc when /etc/zsh does not exist" {
    rm -rf "$R/etc/zsh"
    run "$NIVUUS" install --system --yes --minimal
    [ "$status" -eq 0 ]
    run grep -c ">>> nivuus shell >>>" "$R/etc/zshrc"
    [ "$output" = "1" ]
}

@test "install --system gives zsh to every human account, journaled" {
    run "$NIVUUS" install --system --yes
    [ "$status" -eq 0 ]
    grep -q "alice$" "$TMP/CALLS-chsh"
    grep -q "root$" "$TMP/CALLS-chsh"
    ! grep -q "svc" "$TMP/CALLS-chsh"
    run grep -c "^CHSH" "$R/var/lib/nivuus/manifest.tsv"
    [ "$output" = "2" ]
}

@test "install --system installs the optional tools with the package manager" {
    run "$NIVUUS" install --system --yes --no-chsh
    [ "$status" -eq 0 ]
    grep -q "install -y --no-install-recommends fzf" "$TMP/CALLS-apt-get"
    grep -q "install -y --no-install-recommends fd-find" "$TMP/CALLS-apt-get"
    grep -q "^PKG	fzf	-	apt-get$" "$R/var/lib/nivuus/manifest.tsv"
}

@test "install --system --minimal touches neither login shells nor optional tools" {
    run "$NIVUUS" install --system --yes --minimal
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-chsh" ]
    [ ! -f "$TMP/CALLS-apt-get" ]
}

@test "install --system --no-chsh keeps every login shell" {
    run "$NIVUUS" install --system --yes --no-chsh
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-chsh" ]
}

@test "a plain install is a system install when root" {
    run "$NIVUUS" install --yes --minimal
    [ "$status" -eq 0 ]
    [[ "$output" == *"tous les utilisateurs"* ]]
    [ -f "$R/usr/local/share/nivuus-shell/.zshrc" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "a plain install re-runs itself through sudo when not root and sudo is available" {
    export NIVUUS_UID=1000
    run "$NIVUUS" install --yes --minimal
    [ "$status" -eq 0 ]
    grep -q "bin/nivuus install --system" "$TMP/CALLS-sudo"
    grep -q "NIVUUS_UID=0" "$TMP/CALLS-sudo"           # jamais de relance en boucle
    [ -f "$R/usr/local/share/nivuus-shell/.zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$R/etc/zsh/zshrc"
    [ "$output" = "1" ]
}

@test "install --prefix is always a user install, without sudo" {
    export NIVUUS_UID=1000
    run "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-sudo" ]
    [ -f "$TMP/target/.zshrc" ]
    [ -f "$HOME/.zshrc" ]
}

@test "install --user never escalates even as root" {
    run "$NIVUUS" install --user --yes --minimal
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-sudo" ]
    [ -f "$HOME/.nivuus-shell/.zshrc" ]
    [ ! -e "$R/usr" ]
}

@test "a plain install is a user install when sudo is unavailable" {
    export NIVUUS_UID=1000
    rm -f "$TMP/fakebin/sudo"
    # Un vrai sudo peut traîner derrière dans le PATH : on le masque par un
    # faux qui refuse tout (sudo -n échoue, et le mode passe en user).
    printf '#!/bin/sh\nexit 1\n' > "$TMP/fakebin/sudo"; chmod +x "$TMP/fakebin/sudo"
    run "$NIVUUS" install --yes --minimal </dev/null
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/.zshrc" ]
    [ ! -e "$R/usr" ]
}

@test "install --system --dry-run never calls sudo nor writes anything" {
    export NIVUUS_UID=1000
    fs_fingerprint "$R" > "$TMP/before"
    run "$NIVUUS" install --system --dry-run --yes
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/CALLS-sudo" ]
    [ ! -f "$TMP/CALLS-chsh" ]
    [ ! -f "$TMP/CALLS-apt-get" ]
    [[ "$output" == *"dry-run"* ]]
    fs_fingerprint "$R" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install --system twice is idempotent" {
    "$NIVUUS" install --system --yes --minimal
    cp "$R/etc/zsh/zshrc" "$TMP/zshrc.first"
    run "$NIVUUS" install --system --yes --minimal
    [ "$status" -eq 0 ]
    run diff "$TMP/zshrc.first" "$R/etc/zsh/zshrc"
    [ "$status" -eq 0 ]
}

@test "uninstall auto-detects a system install and leaves the fake root bit-identical" {
    fs_fingerprint "$R" > "$TMP/before"
    "$NIVUUS" install --system --yes
    run "$NIVUUS" uninstall --yes --purge
    [ "$status" -eq 0 ]
    [[ "$output" == *"tous les utilisateurs"* ]]
    fs_fingerprint "$R" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
    # Les shells de connexion sont vraiment restaurés (root : chsh ne demande rien).
    grep -q "^-s /bin/bash alice$" "$TMP/CALLS-chsh"
    grep -q "^-s /bin/bash root$" "$TMP/CALLS-chsh"
}

@test "uninstall --system re-runs itself through sudo when not root" {
    "$NIVUUS" install --system --yes --minimal
    export NIVUUS_UID=1000
    run "$NIVUUS" uninstall --system --yes
    [ "$status" -eq 0 ]
    grep -q "bin/nivuus uninstall --system" "$TMP/CALLS-sudo"
    ! grep -q ">>> nivuus shell >>>" "$R/etc/zsh/zshrc"
}

@test "the installed system CLI works standalone" {
    "$NIVUUS" install --system --yes --minimal
    run "$R/usr/local/share/nivuus-shell/bin/nivuus" uninstall --dry-run --yes
    [ "$status" -eq 0 ]
}

# A fresh machine has no zsh, hence no /etc/zsh yet: the global zshrc must be
# chosen AFTER the zsh package is installed, or the block lands in /etc/zshrc,
# which Debian's zsh never reads. The PATH is rebuilt without zsh and the fake
# apt-get "installs" it, creating /etc/zsh/zshrc as the package does.
@test "install --system on a machine without zsh picks the global zshrc the new package creates" {
    rm -rf "$R/etc/zsh"
    mkdir -p "$TMP/nozsh"
    for t in bash sh env cat grep sed awk cut head tail tr mktemp cp mv rm mkdir rmdir dirname \
             sha256sum shasum id date wc readlink chmod chown find uname getent sort touch ls ln; do
        p="$(command -v "$t" 2>/dev/null)" || continue
        ln -sf "$p" "$TMP/nozsh/$t"
    done
    cat > "$TMP/nozsh/apt-get" <<EOP
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/CALLS-apt-get"
case "\$*" in *zsh*)
    printf '#!/bin/sh\n' > "$TMP/nozsh/zsh"; chmod +x "$TMP/nozsh/zsh"
    mkdir -p "$R/etc/zsh"; printf '# shipped by the zsh package\n' > "$R/etc/zsh/zshrc" ;;
esac
EOP
    chmod +x "$TMP/nozsh/apt-get"
    cp "$TMP/fakebin/chsh" "$TMP/nozsh/chsh"
    PATH="$TMP/nozsh" run "$NIVUUS" install --system --yes --no-chsh
    [ "$status" -eq 0 ]
    grep -q "install -y --no-install-recommends zsh" "$TMP/CALLS-apt-get"
    grep -q "^PKG	zsh	-	apt-get$" "$R/var/lib/nivuus/manifest.tsv"
    [ "$(head -n1 "$R/etc/zsh/zshrc")" = "# shipped by the zsh package" ]
    run grep -c ">>> nivuus shell >>>" "$R/etc/zsh/zshrc"
    [ "$output" = "1" ]
    [ ! -e "$R/etc/zshrc" ]
}

@test "install --system gives the copied files to root, whoever made the clone" {
    [ "$(id -u)" -eq 0 ] || skip "needs real root to create a foreign-owned source tree"
    cp -r "$ROOT" "$TMP/clone"
    find "$TMP/clone" -name '*.zwc' -delete
    chown -R 65534:65534 "$TMP/clone"
    run "$TMP/clone/bin/nivuus" install --system --yes --minimal
    [ "$status" -eq 0 ]
    [ "$(stat -c '%u' "$R/usr/local/share/nivuus-shell/.zshrc")" = "0" ]
    [ "$(stat -c '%u' "$R/usr/local/share/nivuus-shell/config/00-core.zsh")" = "0" ]
}
