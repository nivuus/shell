# Installation multi-plateforme — Plan d'implémentation (phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre l'installation de Nivuus Shell correcte et vérifiée sur macOS, Linux (glibc et musl), WSL et container : détection de plateforme complète, mode `--minimal`, `chsh` sûr et réversible, politique de dépendances sans aucun `sudo` surprise.

**Architecture:** On étend le socle des phases 1–2 sans le réécrire. `lib/detect.sh` (aujourd'hui 4 fonctions) devient le seul endroit qui sait *où* on tourne ; un nouveau `lib/deps.sh` sait *ce qui manque* et *quelle commande le corrigerait* — sans jamais l'exécuter ; `lib/steps.sh` gagne l'étape `chsh` ; `bin/nivuus` reste le seul à décider et à demander. Toute mutation continue de passer par `lib/manifest.sh`, y compris le `chsh` (action `CHSH`) et les paquets installés sur demande explicite (action `PKG`).

**Tech Stack:** bash 3.2 (plancher macOS), BusyBox ash (plancher Alpine) pour `lib/`, zsh (cible installée), bats (tests), GitHub Actions, Docker.

**Spec:** `docs/superpowers/specs/2026-08-20-installation-friction-zero-design.md` (section 6, phase 3)

**Plan précédent (déjà mergé) :** `docs/superpowers/plans/2026-08-20-installation-friction-zero.md` — phases 1 et 2. Ce plan en suppose l'existant : `lib/log.sh`, `lib/detect.sh`, `lib/manifest.sh`, `lib/zshrc.sh`, `lib/steps.sh`, `bin/nivuus`, `install.sh` wrapper, `tests/unit/test_lib_*.bats`, `tests/e2e/*.bats`, `tests/helpers/fingerprint.bash`.

**Sortie de phase :** installation vérifiée sur macOS et Alpine ; `chsh` tracé et restauré ; aucun `sudo` implicite ; test d'empreinte `$HOME` toujours vert, désormais empreinte du shell de connexion incluse.

## Global Constraints

- **Deux planchers d'interpréteur.** `bin/nivuus` et `install.sh` sont en **bash 3.2** (macOS système). Le contenu de `lib/*.sh` doit en plus être **sourçable et exécutable par BusyBox ash** (Alpine) : pas de tableaux (`arr=()`, `arr+=()`), pas de tableaux associatifs, pas de `mapfile`/`readarray`, pas de `${var,,}`/`${var^^}`, pas de `[[ ]]`, pas de substitution de processus `< <(...)`, pas de `local -n`, pas de `${BASH_SOURCE[0]}`. `local` seul est autorisé (supporté par ash/dash/busybox).
- **Pas d'utilitaire GNU-only.** Ce qui doit tourner sous BusyBox *et* sous les coreutils BSD de macOS : pas de `sed -i` (les deux dialectes sont incompatibles), pas de `date +%s%N`, pas de `grep -P`, pas de `readlink -f`, pas de `stat` sans double forme (`-c` GNU / `-f` BSD, cf. `tests/helpers/fingerprint.bash`), pas de `sort -V`, pas de `cp -a`.
- **Toute mutation du système de fichiers passe par `lib/manifest.sh`.** Aucun `cp`, `mv`, `rm`, `mkdir`, `>` ailleurs. Un `chsh` est une mutation : il est journalisé (`CHSH<TAB>$HOME<TAB>-<TAB><shell d'origine>`) avant d'être exécuté, et restauré à la désinstallation. Un paquet installé sur demande explicite est journalisé (`PKG<TAB><paquet><TAB>-<TAB><gestionnaire>`) et **jamais** désinstallé.
- **Aucun `sudo` implicite.** `lib/deps.sh` ne fait qu'établir un constat et *imprimer* une commande. Seul `bin/nivuus`, et seulement sous `--with-deps`, peut exécuter cette commande, après **une** confirmation groupée. Sans `--with-deps` : une ligne copiable, et on continue.
- **`NIVUUS_DRY_RUN=1` garantit zéro écriture disque**, y compris pas de `chsh`, pas d'appel au gestionnaire de paquets, pas d'écriture dans `~/.local/state/nivuus/`.
- **`~/.zsh_history` n'est jamais touché**, quelles que soient les options.
- **Chemins système paramétrables.** Toute lecture d'un chemin système dans `lib/detect.sh` passe par une variable à défaut (`: "${NIVUUS_X:=/chemin}"`), comme `NIVUUS_DOCKERENV` et `NIVUUS_CGROUP` déjà en place — c'est ce qui rend la détection testable sans conteneur.
- **Tests :** bats. `tests/unit/` pour les bibliothèques, `tests/e2e/` pour les scénarios d'installation. Le test d'empreinte `tests/e2e/test_reversibility.bats` doit rester **vert à chaque tâche**, pas seulement à la fin.
- **Aucun test ne modifie le vrai système** : pas de `chsh` réel, pas d'appel réel à un gestionnaire de paquets. Les tests injectent des faux binaires en tête de `PATH` et vérifient qu'ils n'ont **pas** été appelés quand ils ne doivent pas l'être.

---

### Task 1: Distribution et architecture — `nivuus_detect_distro`, `nivuus_detect_arch`

**Files:**
- Modify: `lib/detect.sh`
- Test: `tests/unit/test_lib_detect_platform.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_detect_os` (existant)
- Produces :
  - `nivuus_detect_distro` — imprime l'`ID` de `/etc/os-release` (`ubuntu`, `debian`, `alpine`, `arch`, `fedora`, `opensuse-leap`…), `macos` sur Darwin, `unknown` si indéterminable. Chemin surchargeable par `NIVUUS_OS_RELEASE`.
  - `nivuus_detect_distro_like` — imprime `ID_LIKE` (`debian`, `rhel fedora`…) ou chaîne vide.
  - `nivuus_detect_arch` — imprime `arm64`, `x86_64`, ou la sortie brute de `uname -m`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_detect_platform.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    source "$LIB/detect.sh"
}

teardown() { rm -rf "$TMP"; }

@test "detect_distro reads ID from os-release" {
    printf 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "ubuntu" ]
}

@test "detect_distro strips quotes around ID" {
    printf 'ID="alpine"\nVERSION_ID=3.20\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "alpine" ]
}

@test "detect_distro ignores a commented or later ID-like key" {
    printf '# ID=decoy\nID_LIKE=debian\nID=debian\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "debian" ]
}

@test "detect_distro returns unknown without os-release" {
    run bash -c "NIVUUS_OS_RELEASE='$TMP/absent'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "unknown" ]
}

@test "detect_distro_like returns ID_LIKE or empty" {
    printf 'ID=fedora\nID_LIKE="rhel centos"\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro_like"
    [ "$output" = "rhel centos" ]

    printf 'ID=arch\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro_like"
    [ "$output" = "" ]
}

@test "detect_arch normalises the common machine names" {
    run nivuus_detect_arch
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Une des deux valeurs normalisées sur toutes les cibles du projet.
    [[ "$output" = "arm64" || "$output" = "x86_64" || "$output" = "$(uname -m)" ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_detect_platform.bats`
Expected: FAIL — `nivuus_detect_distro: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/detect.sh`, après les défauts existants :

```sh
: "${NIVUUS_OS_RELEASE:=/etc/os-release}"

# Première affectation non commentée de la clé demandée dans un fichier
# style os-release. awk plutôt qu'un `source` : ce fichier appartient au
# système, on ne l'exécute pas.
_nivuus_os_release_key() {
    local key="$1"
    [ -r "$NIVUUS_OS_RELEASE" ] || return 0
    awk -F= -v k="$key" '
        /^[[:space:]]*#/ { next }
        $1 == k { sub(/^[^=]*=/, "", $0); gsub(/^["\047]|["\047]$/, "", $0); print; exit }
    ' "$NIVUUS_OS_RELEASE" 2>/dev/null
}

nivuus_detect_distro() {
    local id=''
    if [ "$(nivuus_detect_os)" = "macos" ]; then
        printf 'macos\n'
        return 0
    fi
    id="$(_nivuus_os_release_key ID)"
    [ -n "$id" ] || id='unknown'
    printf '%s\n' "$id"
}

nivuus_detect_distro_like() {
    [ "$(nivuus_detect_os)" = "macos" ] && return 0
    _nivuus_os_release_key ID_LIKE
}

nivuus_detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64\n' ;;
        x86_64|amd64)  printf 'x86_64\n' ;;
        *)             uname -m ;;
    esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_detect_platform.bats tests/unit/test_lib_detect.bats`
Expected: PASS — 6 nouveaux tests, et les 6 tests existants de `test_lib_detect.bats` toujours verts.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/unit/test_lib_detect_platform.bats
git commit -m "feat(detect): identify distro and architecture"
```

---

### Task 2: WSL, SSH, headless et `--minimal` automatique

**Files:**
- Modify: `lib/detect.sh`
- Test: `tests/unit/test_lib_detect_session.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_detect_os`, `nivuus_is_container`, `nivuus_is_tty` (existants)
- Produces :
  - `nivuus_is_wsl` — code 0 sous WSL. Marqueurs : `$WSL_DISTRO_NAME`, `$WSL_INTEROP`, ou `microsoft`/`WSL` dans `$NIVUUS_PROC_VERSION` (défaut `/proc/version`).
  - `nivuus_is_ssh` — code 0 si `$SSH_CONNECTION`, `$SSH_CLIENT` ou `$SSH_TTY` est défini.
  - `nivuus_is_headless` — code 0 si la machine n'a probablement pas de terminal graphique où installer une police (ni `$DISPLAY` ni `$WAYLAND_DISPLAY`) ; toujours faux sous macOS et sous WSL, où les polices sont gérées par l'hôte.
  - `nivuus_should_minimal` — **étendu** : `NIVUUS_NO_MINIMAL` force le mode complet (priorité maximale), `NIVUUS_MINIMAL` force le mode minimal, sinon container, absence de TTY, SSH ou headless déclenchent le mode minimal.

Note d'arbitrage : `nivuus_is_headless` vrai sur une console Linux sans serveur graphique est **voulu** — c'est exactement la machine où une nerd font n'a nulle part où s'installer. `NIVUUS_NO_MINIMAL=1` / `--no-minimal` (Task 8) reste l'échappatoire.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_detect_session.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    # L'environnement neutre (ni container, ni WSL, ni SSH, ni X) est
    # construit dans le helper `detect` ci-dessous, via env -u.
}

teardown() { rm -rf "$TMP"; }

detect() {   # detect "<env>" "<appel>"
    run env -u container -u WSL_DISTRO_NAME -u WSL_INTEROP \
            -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
            -u DISPLAY -u WAYLAND_DISPLAY -u NIVUUS_MINIMAL -u NIVUUS_NO_MINIMAL \
            NIVUUS_DOCKERENV="$TMP/absent" NIVUUS_CGROUP="$TMP/absent" \
            NIVUUS_PROC_VERSION="$TMP/absent" \
            bash -c "$1 source '$LIB/detect.sh'; $2"
}

@test "is_wsl is true when /proc/version mentions Microsoft" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    detect "NIVUUS_PROC_VERSION='$TMP/proc_version';" "nivuus_is_wsl"
    [ "$status" -eq 0 ]
}

@test "is_wsl is true when WSL_DISTRO_NAME is set" {
    detect "WSL_DISTRO_NAME=Ubuntu;" "nivuus_is_wsl"
    [ "$status" -eq 0 ]
}

@test "is_wsl is false on a plain Linux kernel" {
    printf 'Linux version 6.6.0-generic\n' > "$TMP/proc_version"
    detect "NIVUUS_PROC_VERSION='$TMP/proc_version';" "nivuus_is_wsl"
    [ "$status" -eq 1 ]
}

@test "is_ssh reacts to each of the three markers" {
    detect "SSH_CONNECTION='1.2.3.4 22';" "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect "SSH_CLIENT='1.2.3.4';"       "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect "SSH_TTY='/dev/pts/0';"       "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect ""                            "nivuus_is_ssh"; [ "$status" -eq 1 ]
}

@test "is_headless is false when a graphical session is present" {
    detect "DISPLAY=':0';"          "nivuus_is_headless"; [ "$status" -eq 1 ]
    detect "WAYLAND_DISPLAY=wl-0;"  "nivuus_is_headless"; [ "$status" -eq 1 ]
}

@test "is_headless is false under WSL even without DISPLAY" {
    detect "WSL_DISTRO_NAME=Ubuntu;" "nivuus_is_headless"
    [ "$status" -eq 1 ]
}

@test "is_headless is true on a bare Linux console" {
    detect "" "nivuus_is_headless"
    [ "$status" -eq 0 ]
}

@test "should_minimal is forced on by NIVUUS_MINIMAL" {
    detect "NIVUUS_MINIMAL=1; DISPLAY=':0';" "nivuus_should_minimal"
    [ "$status" -eq 0 ]
}

@test "NIVUUS_NO_MINIMAL wins over every automatic trigger" {
    detect "NIVUUS_NO_MINIMAL=1; NIVUUS_MINIMAL=1; container=podman;" "nivuus_should_minimal"
    [ "$status" -eq 1 ]
}

@test "should_minimal is true over SSH even with a graphical session" {
    detect "SSH_CONNECTION='1.2.3.4 22'; DISPLAY=':0';" "nivuus_should_minimal"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_detect_session.bats`
Expected: FAIL — `nivuus_is_wsl: command not found`, et `NIVUUS_NO_MINIMAL` sans effet.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/detect.sh` et **remplacer** `nivuus_should_minimal` :

```sh
: "${NIVUUS_PROC_VERSION:=/proc/version}"

nivuus_is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
    [ -n "${WSL_INTEROP:-}" ] && return 0
    grep -qi 'microsoft\|wsl' "$NIVUUS_PROC_VERSION" 2>/dev/null && return 0
    return 1
}

nivuus_is_ssh() {
    [ -n "${SSH_CONNECTION:-}" ] && return 0
    [ -n "${SSH_CLIENT:-}" ] && return 0
    [ -n "${SSH_TTY:-}" ] && return 0
    return 1
}

# « Pas d'endroit où installer une police » plutôt que « pas d'écran » :
# macOS et WSL ont toujours un terminal hôte, même sans $DISPLAY côté Unix.
nivuus_is_headless() {
    [ "$(nivuus_detect_os)" = "macos" ] && return 1
    nivuus_is_wsl && return 1
    [ -n "${DISPLAY:-}" ] && return 1
    [ -n "${WAYLAND_DISPLAY:-}" ] && return 1
    return 0
}

# Ordre délibéré : la surcharge explicite de l'utilisateur passe AVANT
# toute heuristique, dans les deux sens.
nivuus_should_minimal() {
    [ -n "${NIVUUS_NO_MINIMAL:-}" ] && return 1
    [ -n "${NIVUUS_MINIMAL:-}" ] && return 0
    nivuus_is_container && return 0
    nivuus_is_tty || return 0
    nivuus_is_ssh && return 0
    nivuus_is_headless && return 0
    return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_detect*.bats`
Expected: PASS — les tests existants de `test_lib_detect.bats` (dont « should_minimal is true when there is no TTY ») restent verts.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/unit/test_lib_detect_session.bats
git commit -m "feat(detect): detect WSL, SSH and headless sessions"
```

---

### Task 3: macOS — préfixe Homebrew, chemin de zsh, shell de connexion

**Files:**
- Modify: `lib/detect.sh`
- Test: `tests/unit/test_lib_detect_macos.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_detect_os`, `nivuus_detect_arch`
- Produces :
  - `nivuus_brew_prefix` — imprime le préfixe Homebrew (`brew --prefix` s'il est dans le `PATH`, sinon `$NIVUUS_BREW_ARM` = `/opt/homebrew` puis `$NIVUUS_BREW_INTEL` = `/usr/local` s'ils contiennent un `bin/brew` exécutable) ; code 1 et rien sur stdout si Homebrew est absent.
  - `nivuus_zsh_path` — chemin absolu du zsh à utiliser : celui de Homebrew s'il existe (plus récent que le zsh 5.9 système d'Apple), sinon `command -v zsh` ; code 1 si aucun.
  - `nivuus_current_login_shell` — shell de connexion réel de l'utilisateur : `$NIVUUS_LOGIN_SHELL_FILE` si défini (crochet de test, voir Task 7), sinon `getent passwd`, sinon `dscl` (macOS), sinon `$SHELL`.
  - `nivuus_shell_is_listed <path>` — code 0 si `<path>` figure ligne à ligne dans `$NIVUUS_ETC_SHELLS` (défaut `/etc/shells`). **C'est le test qui manquait et qui cassait `chsh` sur macOS + Homebrew zsh.**

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_detect_macos.bats
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_detect_macos.bats`
Expected: FAIL — `nivuus_brew_prefix: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/detect.sh` :

```sh
: "${NIVUUS_ETC_SHELLS:=/etc/shells}"
: "${NIVUUS_BREW_ARM:=/opt/homebrew}"
: "${NIVUUS_BREW_INTEL:=/usr/local}"

nivuus_brew_prefix() {
    local p
    if command -v brew >/dev/null 2>&1; then
        p="$(brew --prefix 2>/dev/null)"
        [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
    fi
    for p in "$NIVUUS_BREW_ARM" "$NIVUUS_BREW_INTEL"; do
        if [ -x "$p/bin/brew" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# Le zsh de Homebrew est préféré au /bin/zsh d'Apple : c'est celui que
# l'utilisateur macOS met à jour, et celui qu'il attend comme shell de
# connexion. C'est aussi celui qui n'est PAS dans /etc/shells par défaut --
# d'où nivuus_shell_is_listed juste en dessous.
nivuus_zsh_path() {
    local prefix
    prefix="$(nivuus_brew_prefix 2>/dev/null)" || prefix=''
    if [ -n "$prefix" ] && [ -x "$prefix/bin/zsh" ]; then
        printf '%s\n' "$prefix/bin/zsh"
        return 0
    fi
    command -v zsh 2>/dev/null || return 1
}

nivuus_shell_is_listed() {
    local shell_path="$1"
    [ -r "$NIVUUS_ETC_SHELLS" ] || return 1
    grep -qxF "$shell_path" "$NIVUUS_ETC_SHELLS" 2>/dev/null
}

# $NIVUUS_LOGIN_SHELL_FILE : crochet de test. Quand il est défini, il fait
# autorité -- c'est aussi ce que le faux `chsh` des tests écrit, et ce que
# l'empreinte de réversibilité relit (tests/helpers/fingerprint.bash).
nivuus_current_login_shell() {
    local user shell_path=''
    if [ -n "${NIVUUS_LOGIN_SHELL_FILE:-}" ]; then
        if [ -f "$NIVUUS_LOGIN_SHELL_FILE" ]; then
            head -n1 "$NIVUUS_LOGIN_SHELL_FILE"
        else
            printf '%s\n' "${SHELL:-}"
        fi
        return 0
    fi
    user="$(id -un 2>/dev/null)"
    if [ -n "$user" ] && command -v getent >/dev/null 2>&1; then
        shell_path="$(getent passwd "$user" 2>/dev/null | awk -F: 'NR==1 {print $NF}')"
    fi
    if [ -z "$shell_path" ] && [ "$(nivuus_detect_os)" = "macos" ] \
        && command -v dscl >/dev/null 2>&1; then
        shell_path="$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk 'NR==1 {print $2}')"
    fi
    [ -n "$shell_path" ] || shell_path="${SHELL:-}"
    printf '%s\n' "$shell_path"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_detect*.bats`
Expected: PASS, 9 nouveaux tests.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/unit/test_lib_detect_macos.bats
git commit -m "feat(detect): resolve brew prefix, zsh path and login shell"
```

---

### Task 4: `lib/deps.sh` — constater, jamais exécuter

**Files:**
- Create: `lib/deps.sh`
- Modify: `lib/steps.sh` (la fonction `nivuus_step_check_required_deps` déménage), `bin/nivuus` (sourcer `lib/deps.sh`)
- Test: `tests/unit/test_lib_deps.bats` (nouveau), `tests/unit/test_lib_steps.bats` (les 3 tests de dépendances y sont retirés)

**Interfaces:**
- Consumes: `log_*`, `nivuus_detect_distro`, `nivuus_brew_prefix`
- Produces :
  - `nivuus_pkg_manager` — imprime `apt-get`, `dnf`, `yum`, `pacman`, `apk`, `zypper` ou `brew` (premier trouvé, `brew` en dernier pour ne pas court-circuiter le gestionnaire système sur Linuxbrew) ; chaîne vide et code 1 si aucun.
  - `nivuus_sudo_prefix` — imprime `sudo ` si l'élévation est nécessaire *et* disponible, rien si on est déjà root ou si le gestionnaire est `brew` (Homebrew refuse `sudo`).
  - `nivuus_pkg_install_cmd <pkg...>` — imprime la commande exacte et copiable pour la plateforme détectée. **N'exécute rien.**
  - `nivuus_deps_list <level>` — imprime la liste de paquets du niveau (`required` = `zsh git curl`, `recommended` = `fzf`, `optional` = `bat eza grc`).
  - `nivuus_deps_missing <level>` — imprime, un par ligne, les paquets du niveau dont la commande est absente du `PATH`.
  - `nivuus_deps_check_required` — code 0 si tout est là ; sinon message d'erreur + commande exacte + code 1.
  - `nivuus_deps_suggest <level>` — imprime une suggestion non bloquante (`log_info`) avec la commande copiable ; code 0 toujours, silencieux si rien ne manque.
- `lib/steps.sh` conserve `nivuus_step_check_required_deps` comme alias d'une ligne vers `nivuus_deps_check_required`, pour ne casser ni `bin/nivuus` ni les installations en cours de migration.

Note d'arbitrage : le spec listait `lib/deps.sh` dès la phase 1 ; le plan des phases 1–2 avait délibérément gardé une fonction unique dans `steps.sh` en annonçant ce déménagement ici. C'est ce que fait cette tâche. Les noms de paquets ne sont **pas** traduits par gestionnaire (`eza` n'existe pas sur les vieux Debian, `bat` s'appelle `batcat` une fois installé) : Nivuus n'exécute rien, donc une commande imparfaite reste une suggestion lisible et corrigeable, alors qu'une table de traduction serait une dette à maintenir pour six gestionnaires.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_deps.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin"
}

teardown() { rm -rf "$TMP"; }

# Fabrique un PATH ne contenant QUE les commandes nommées.
fake_path() {
    rm -rf "$TMP/bin"; mkdir -p "$TMP/bin"
    local c
    for c in "$@"; do
        printf '#!/bin/sh\n: > "%s/EXECUTED-%s"\n' "$TMP" "$c" > "$TMP/bin/$c"
        chmod +x "$TMP/bin/$c"
    done
}

deps() {   # deps "<commandes du PATH>" "<appel>"
    fake_path $1
    run env PATH="$TMP/bin" bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; \
                                     source '$LIB/deps.sh'; $2"
}

@test "pkg_manager finds each supported manager" {
    deps "apt-get" "nivuus_pkg_manager"; [ "$output" = "apt-get" ]
    deps "dnf"     "nivuus_pkg_manager"; [ "$output" = "dnf" ]
    deps "pacman"  "nivuus_pkg_manager"; [ "$output" = "pacman" ]
    deps "apk"     "nivuus_pkg_manager"; [ "$output" = "apk" ]
    deps "zypper"  "nivuus_pkg_manager"; [ "$output" = "zypper" ]
    deps "brew"    "nivuus_pkg_manager"; [ "$output" = "brew" ]
}

@test "pkg_manager prefers the system manager over brew" {
    deps "apt-get brew" "nivuus_pkg_manager"
    [ "$output" = "apt-get" ]
}

@test "pkg_manager fails when there is none" {
    deps "" "nivuus_pkg_manager"
    [ "$status" -eq 1 ]
}

@test "install_cmd emits the exact command per manager" {
    deps "apt-get sudo id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"apt-get install"* ]]
    [[ "$output" == *"fzf"* ]]

    deps "apk sudo id" "nivuus_pkg_install_cmd fzf bat"
    [[ "$output" == *"apk add"* ]]
    [[ "$output" == *"fzf bat"* ]]

    deps "pacman sudo id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"pacman -S"* ]]
}

@test "install_cmd never prefixes brew with sudo" {
    deps "brew id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"brew install fzf"* ]]
    [[ "$output" != *"sudo"* ]]
}

@test "install_cmd omits sudo when sudo is unavailable" {
    # Pas de sudo dans le PATH : la commande reste copiable, sans préfixe
    # inventé. (Le cas root est couvert par la même branche : id -u = 0.)
    deps "apt-get" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"apt-get install"* ]]
    [[ "$output" != *"sudo"* ]]
}

@test "deps_missing lists only what is absent" {
    deps "zsh git" "nivuus_deps_missing required"
    [ "$output" = "curl" ]
}

@test "check_required fails, names every missing package and shows the command" {
    deps "apt-get sudo" "nivuus_deps_check_required 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"apt-get install"* ]]
}

@test "check_required succeeds when everything is present" {
    deps "zsh git curl" "nivuus_deps_check_required"
    [ "$status" -eq 0 ]
}

@test "nothing in deps.sh ever executes a package manager or sudo" {
    for mgr in apt-get dnf pacman apk zypper brew; do
        rm -f "$TMP"/EXECUTED-*
        deps "$mgr sudo" "nivuus_deps_check_required; nivuus_deps_suggest recommended; \
                          nivuus_deps_suggest optional; true"
        run ls "$TMP"
        [[ "$output" != *"EXECUTED-"* ]]
    done
}

@test "deps_suggest is silent when nothing is missing" {
    deps "zsh git curl fzf" "nivuus_deps_suggest recommended"
    [ "$output" = "" ]
}
```

Retirer de `tests/unit/test_lib_steps.bats` les trois tests `check_required_deps …` (ils sont remplacés ci-dessus), et **ajouter** à leur place le seul test qui reste pertinent pour `steps.sh` :

```bash
@test "step_check_required_deps still delegates to deps.sh" {
    run bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/deps.sh'; \
                 source '$LIB/steps.sh'; PATH=''; nivuus_step_check_required_deps"
    [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_deps.bats`
Expected: FAIL — `lib/deps.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/deps.sh
# Constate les dépendances et PROPOSE une commande. N'en exécute jamais
# aucune : c'est la seule garantie qui rend « pas de sudo surprise »
# vérifiable en test (voir tests/unit/test_lib_deps.bats).
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.

NIVUUS_DEPS_REQUIRED='zsh git curl'
NIVUUS_DEPS_RECOMMENDED='fzf'
NIVUUS_DEPS_OPTIONAL='bat eza grc'

# brew en dernier : sur une machine Linux avec Linuxbrew, le gestionnaire
# système reste le bon choix pour zsh/git/curl.
nivuus_pkg_manager() {
    local m
    for m in apt-get dnf yum pacman apk zypper brew; do
        if command -v "$m" >/dev/null 2>&1; then
            printf '%s\n' "$m"
            return 0
        fi
    done
    return 1
}

nivuus_sudo_prefix() {
    local mgr="${1:-}"
    [ "$mgr" = "brew" ] && return 0          # Homebrew refuse d'être lancé en root
    [ "$(id -u 2>/dev/null)" = "0" ] && return 0
    command -v sudo >/dev/null 2>&1 && printf 'sudo '
    return 0
}

nivuus_pkg_install_cmd() {
    local mgr sudo_p pkgs="$*"
    mgr="$(nivuus_pkg_manager)" || {
        printf 'installe %s avec le gestionnaire de paquets de ta plateforme\n' "$pkgs"
        return 0
    }
    sudo_p="$(nivuus_sudo_prefix "$mgr")"
    case "$mgr" in
        apt-get) printf '%sapt-get install -y %s\n' "$sudo_p" "$pkgs" ;;
        dnf)     printf '%sdnf install -y %s\n'     "$sudo_p" "$pkgs" ;;
        yum)     printf '%syum install -y %s\n'     "$sudo_p" "$pkgs" ;;
        pacman)  printf '%spacman -S --noconfirm %s\n' "$sudo_p" "$pkgs" ;;
        apk)     printf '%sapk add --no-cache %s\n' "$sudo_p" "$pkgs" ;;
        zypper)  printf '%szypper install -y %s\n'  "$sudo_p" "$pkgs" ;;
        brew)    printf 'brew install %s\n' "$pkgs" ;;
    esac
}

nivuus_deps_list() {
    case "$1" in
        required)    printf '%s\n' "$NIVUUS_DEPS_REQUIRED" ;;
        recommended) printf '%s\n' "$NIVUUS_DEPS_RECOMMENDED" ;;
        optional)    printf '%s\n' "$NIVUUS_DEPS_OPTIONAL" ;;
        *)           return 1 ;;
    esac
}

nivuus_deps_missing() {
    local level="$1" c list
    list="$(nivuus_deps_list "$level")" || return 1
    for c in $list; do
        command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"
    done
    return 0
}

nivuus_deps_check_required() {
    local missing
    missing="$(nivuus_deps_missing required | tr '\n' ' ')"
    missing="${missing% }"
    [ -n "$missing" ] || return 0
    log_error "Dépendances requises manquantes : $missing"
    log_error "Installe-les avec :"
    log_error "  $(nivuus_pkg_install_cmd $missing)"
    return 1
}

nivuus_deps_suggest() {
    local level="$1" missing
    missing="$(nivuus_deps_missing "$level" | tr '\n' ' ')"
    missing="${missing% }"
    [ -n "$missing" ] || return 0
    case "$level" in
        recommended) log_info "Recommandé (Nivuus fonctionne sans, en mode dégradé) : $missing" ;;
        *)           log_info "Optionnel (confort supplémentaire) : $missing" ;;
    esac
    log_info "  $(nivuus_pkg_install_cmd $missing)"
    return 0
}
```

Dans `lib/steps.sh`, **remplacer** tout le corps de `nivuus_step_check_required_deps` par :

```sh
# Conservé comme façade : lib/deps.sh porte désormais la politique.
nivuus_step_check_required_deps() { nivuus_deps_check_required "$@"; }
```

Dans `bin/nivuus`, ajouter la source après `lib/detect.sh` :

```sh
. "$NIVUUS_SRC_ROOT/lib/deps.sh"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_deps.bats tests/unit/test_lib_steps.bats tests/e2e/test_nivuus_cli.bats`
Expected: PASS — aucune régression sur la CLI.

- [ ] **Step 5: Commit**

```bash
git add lib/deps.sh lib/steps.sh bin/nivuus tests/unit/test_lib_deps.bats tests/unit/test_lib_steps.bats
git commit -m "feat(deps): extract dependency policy into lib/deps.sh"
```

---

### Task 5: `--with-deps` — une seule confirmation groupée, journalisée en `PKG`

**Files:**
- Modify: `bin/nivuus`, `install.sh`
- Test: `tests/e2e/test_with_deps.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_deps_missing`, `nivuus_pkg_install_cmd`, `nivuus_pkg_manager`, `nivuus_deps_suggest`, `confirm`, `nivuus_manifest_record`
- Produces : dans `bin/nivuus`, l'option `--with-deps` et la fonction interne `install_optional_deps` :
  - sans `--with-deps` : `nivuus_deps_suggest recommended` puis `optional` en fin d'installation (une ligne copiable chacune), rien d'exécuté ;
  - avec `--with-deps` : **une** commande, **une** confirmation, puis exécution, puis un `PKG` par paquet ;
  - en `--minimal` : niveaux 2 et 3 entièrement sautés, sans question ni suggestion ;
  - en `--dry-run` : la commande est affichée via `log_dry`, jamais exécutée.
- `install.sh` accepte et transmet `--with-deps`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_with_deps.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME" "$TMP/bin"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # Faux gestionnaire de paquets : trace son appel, n'installe rien.
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/APT_CALLS"\n' "$TMP" > "$TMP/bin/apt-get"
    chmod +x "$TMP/bin/apt-get"
    printf '#!/bin/sh\nshift 0\nexec "$@"\n' > "$TMP/bin/sudo"
    chmod +x "$TMP/bin/sudo"
    export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "without --with-deps nothing is ever installed" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
}

@test "without --with-deps the missing extras are still suggested as a copyable line" {
    run "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    [[ "$output" == *"apt-get install"* ]]
}

@test "--with-deps runs one grouped command and records a PKG entry per package" {
    run "$NIVUUS" install --yes --no-minimal --with-deps --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/APT_CALLS" ]
    # Une seule invocation, groupée.
    [ "$(wc -l < "$TMP/APT_CALLS" | tr -d ' ')" -eq 1 ]
    run grep -c "^PKG" "$NIVUUS_STATE_DIR/manifest.tsv"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "--with-deps in --dry-run installs nothing and writes no manifest" {
    run "$NIVUUS" install --yes --no-minimal --with-deps --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
    [ ! -e "$NIVUUS_STATE_DIR" ]
    [[ "$output" == *"dry-run"* ]]
}

@test "--minimal skips the extras entirely, even with --with-deps" {
    run "$NIVUUS" install --yes --minimal --with-deps --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
    [[ "$output" != *"apt-get install"* ]]
}

@test "uninstall never removes a package it recorded" {
    "$NIVUUS" install --yes --no-minimal --with-deps --prefix "$TMP/target"
    rm -f "$TMP/APT_CALLS"
    run "$NIVUUS" uninstall --yes --purge
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
}

@test "install.sh forwards --with-deps" {
    run "$ROOT/install.sh" --non-interactive --with-deps
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_with_deps.bats`
Expected: FAIL — « Option inconnue : --with-deps ».

- [ ] **Step 3: Write minimal implementation**

Dans `bin/nivuus`, ajouter aux options de `cmd_install` (et à `usage`) :

```sh
            --with-deps)   WITH_DEPS=1 ;;
```

Ajouter la fonction, au-dessus de `cmd_install` :

```sh
# Niveaux 2 et 3 de la politique de dépendances (spec §3). Deux modes, et
# aucun troisième : soit on imprime une ligne copiable, soit on demande une
# seule fois l'autorisation d'exécuter UNE commande groupée. Nivuus
# n'installe jamais rien sans passer par ici.
install_optional_deps() {
    local missing cmd pkg
    if [ -n "${MINIMAL:-}" ]; then
        log_info "Mode minimal : dépendances recommandées et optionnelles ignorées."
        return 0
    fi
    if [ -z "${WITH_DEPS:-}" ]; then
        nivuus_deps_suggest recommended
        nivuus_deps_suggest optional
        return 0
    fi

    missing="$( { nivuus_deps_missing recommended; nivuus_deps_missing optional; } | tr '\n' ' ')"
    missing="${missing% }"
    [ -n "$missing" ] || { log_info "Rien à installer : tout est déjà là."; return 0; }

    cmd="$(nivuus_pkg_install_cmd $missing)"
    log_info "Une seule commande privilégiée sera exécutée :"
    log_info "  $cmd"
    confirm "L'exécuter maintenant ?" || { log_info "Ignoré. Tu peux la lancer plus tard."; return 0; }

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "exécuterait : $cmd"
        return 0
    fi

    if sh -c "$cmd"; then
        for pkg in $missing; do
            nivuus_manifest_record PKG "$pkg" '-' "$(nivuus_pkg_manager || printf 'inconnu')"
        done
        log_ok "Dépendances installées : $missing"
    else
        # Non fatal : Nivuus fonctionne en mode dégradé sans elles.
        log_warn "L'installation des dépendances a échoué. Nivuus continue sans."
    fi
    return 0
}
```

Appeler `install_optional_deps` dans `cmd_install`, **après** les étapes de copie et **avant** `nivuus_manifest_commit` (les entrées `PKG` doivent entrer dans le manifeste committé) :

```sh
    install_optional_deps
    nivuus_manifest_commit
```

Dans `install.sh`, ajouter au `case` :

```sh
        --with-deps)       ARGS+=(--with-deps) ;;
        --no-minimal)      ARGS+=(--no-minimal) ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_with_deps.bats tests/e2e/test_reversibility.bats`
Expected: PASS — et l'empreinte `$HOME` toujours identique (les `PKG` ne créent rien dans `$HOME`).

- [ ] **Step 5: Commit**

```bash
git add bin/nivuus install.sh tests/e2e/test_with_deps.bats
git commit -m "feat(install): add --with-deps with one grouped confirmation"
```

---

### Task 6: `chsh` sûr — vérifier `/etc/shells`, journaliser, ne jamais forcer

**Files:**
- Modify: `lib/steps.sh`, `bin/nivuus`
- Test: `tests/unit/test_lib_steps_chsh.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_zsh_path`, `nivuus_current_login_shell`, `nivuus_shell_is_listed` (Task 3), `nivuus_manifest_record`, `log_*`
- Produces : `nivuus_step_chsh [zsh_path]` — retourne **toujours 0** (un `chsh` raté n'annule pas une installation réussie) et :
  1. sans chemin de zsh utilisable → avertit, ne fait rien ;
  2. si le shell de connexion est déjà ce zsh → ne fait rien, ne journalise rien ;
  3. si ce zsh n'est **pas** dans `/etc/shells` → affiche la commande privilégiée exacte à lancer (`echo … | sudo tee -a /etc/shells`) et **s'arrête là**. Aucun `sudo`, aucune édition de `/etc/shells` par Nivuus ;
  4. sinon → journalise `CHSH<TAB>$HOME<TAB>-<TAB><shell d'origine>` **avant** d'agir, puis exécute `chsh -s <zsh>` (ou `log_dry` en dry-run) ;
  5. si `chsh` échoue → avertit et donne la commande manuelle ; l'entrée `CHSH` reste, inoffensive (la restauration ne fait rien quand le shell courant est déjà l'original).
- `bin/nivuus` appelle `nivuus_step_chsh` seulement si non-`--minimal` et après un `confirm` dédié.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_steps_chsh.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin"
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
        bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 source '$LIB/steps.sh'; nivuus_step_chsh '' 2>&1"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_steps_chsh.bats`
Expected: FAIL — `nivuus_step_chsh: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/steps.sh` :

```sh
# Change le shell de connexion -- une mutation système comme une autre,
# donc journalisée AVANT d'agir. Ne retourne jamais autre chose que 0 :
# l'installation elle-même a réussi, le shell de connexion est un confort.
nivuus_step_chsh() {
    local zsh_path="${1:-}" current
    [ -n "$zsh_path" ] || zsh_path="$(nivuus_zsh_path 2>/dev/null || true)"
    if [ -z "$zsh_path" ]; then
        log_warn "zsh introuvable : shell de connexion inchangé."
        return 0
    fi

    current="$(nivuus_current_login_shell)"
    if [ "$current" = "$zsh_path" ]; then
        log_info "zsh est déjà ton shell de connexion."
        return 0
    fi

    # LE cas qui casse macOS + Homebrew : /opt/homebrew/bin/zsh n'est pas
    # dans /etc/shells, chsh refuse. On ne modifie PAS /etc/shells nous-mêmes
    # (fichier système, sudo non demandé) : on donne la commande exacte.
    if ! nivuus_shell_is_listed "$zsh_path"; then
        log_warn "$zsh_path n'est pas listé dans $NIVUUS_ETC_SHELLS : chsh le refuserait."
        log_warn "Pour l'autoriser puis changer de shell, lance ces deux commandes :"
        log_warn "  echo $zsh_path | sudo tee -a $NIVUUS_ETC_SHELLS"
        log_warn "  chsh -s $zsh_path"
        return 0
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "chsh -s $zsh_path (shell actuel : $current)"
        return 0
    fi

    nivuus_manifest_record CHSH "$HOME" '-' "$current"
    if chsh -s "$zsh_path" >/dev/null 2>&1; then
        log_ok "Shell de connexion : $zsh_path (ouvre un nouveau terminal pour l'appliquer)"
    else
        log_warn "chsh a échoué. Change-le à la main avec : chsh -s $zsh_path"
    fi
    return 0
}
```

Dans `bin/nivuus`, dans `cmd_install`, juste avant `install_optional_deps` :

```sh
    if [ -z "${MINIMAL:-}" ]; then
        if confirm "Faire de zsh ton shell de connexion ?"; then
            nivuus_step_chsh
        else
            log_info "Shell de connexion inchangé."
        fi
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_steps_chsh.bats tests/e2e/test_nivuus_cli.bats tests/e2e/test_reversibility.bats`
Expected: PASS. Note : sous bats, `nivuus_should_minimal` est vrai (pas de TTY), donc les e2e existants ne déclenchent pas `chsh` — c'est le comportement voulu et c'est ce qui garde l'empreinte `$HOME` stable.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh bin/nivuus tests/unit/test_lib_steps_chsh.bats
git commit -m "feat(install): safe chsh with /etc/shells verification"
```

---

### Task 7: Réversibilité du `chsh` — restauration effective et empreinte du shell de connexion

**Files:**
- Modify: `lib/manifest.sh` (branche `CHSH` de `nivuus_restore_entry`), `tests/helpers/fingerprint.bash`
- Test: `tests/unit/test_lib_manifest_restore.bats` (complété), `tests/e2e/test_reversibility.bats` (complété)

**Interfaces:**
- Consumes: `nivuus_current_login_shell`, `nivuus_shell_is_listed` (dépendance douce, via `command -v` : `lib/manifest.sh` doit rester sourçable seule, comme aujourd'hui pour `nivuus_zshrc_state`)
- Produces :
  - branche `CHSH` **restauratrice** : si le shell de connexion courant est déjà l'original, ne rien faire ; sinon exécuter `chsh -s <original>` quand c'est possible sans privilège, et retomber sur un message d'instruction si `chsh` échoue ou est absent ; `log_dry` en dry-run.
  - `fs_login_shell` dans `tests/helpers/fingerprint.bash`, et son intégration dans l'empreinte de réversibilité.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_lib_manifest_restore.bats` :

```bash
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
        bash -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; source '$LIB/manifest.sh'; \
                 nivuus_restore_entry CHSH '$HOME' '-' '/bin/bash' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chsh -s /bin/bash"* ]]
}
```

Ajouter à `tests/e2e/test_reversibility.bats` (le test central de la phase) :

```bash
@test "install then uninstall restores the login shell too" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$2" > "%s/loginshell"\n' "$TMP" > "$TMP/bin/chsh"
    chmod +x "$TMP/bin/chsh"
    printf '/bin/bash\n' > "$TMP/loginshell"
    printf '/bin/bash\n%s\n' "$(command -v zsh || echo /usr/bin/zsh)" > "$TMP/shells"

    export PATH="$TMP/bin:$PATH"
    export NIVUUS_LOGIN_SHELL_FILE="$TMP/loginshell"
    export NIVUUS_ETC_SHELLS="$TMP/shells"
    # --no-minimal : sous bats il n'y a pas de TTY, donc pas de chsh par défaut.
    printf 'export MINE=1\n' > "$HOME/.zshrc"

    before_shell="$(fs_login_shell)"
    fs_fingerprint "$HOME" > "$TMP/before"

    "$NIVUUS" install --yes --no-minimal --prefix "$HOME/.nivuus-shell"
    [ "$(fs_login_shell)" != "$before_shell" ]      # le chsh a bien eu lieu

    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"

    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
    [ "$(fs_login_shell)" = "$before_shell" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_manifest_restore.bats tests/e2e/test_reversibility.bats`
Expected: FAIL — la branche `CHSH` actuelle ne fait qu'imprimer un message ; `fs_login_shell: command not found`.

- [ ] **Step 3: Write minimal implementation**

Dans `tests/helpers/fingerprint.bash`, ajouter :

```bash
# Shell de connexion. Le spec exige qu'il fasse partie de l'empreinte de
# réversibilité : un chsh non restauré est une trace laissée derrière.
# $NIVUUS_LOGIN_SHELL_FILE fait autorité quand il est défini -- c'est le
# crochet que les tests utilisent pour ne jamais toucher au vrai système.
fs_login_shell() {
    if [ -n "${NIVUUS_LOGIN_SHELL_FILE:-}" ] && [ -f "$NIVUUS_LOGIN_SHELL_FILE" ]; then
        head -n1 "$NIVUUS_LOGIN_SHELL_FILE"
    else
        printf '%s\n' "${SHELL:-}"
    fi
}
```

Dans `lib/manifest.sh`, **remplacer** la branche `CHSH` de `nivuus_restore_entry` :

```sh
        CHSH)
            # Dépendance douce (command -v) : lib/manifest.sh reste
            # sourçable seule, comme pour nivuus_zshrc_state.
            if command -v nivuus_current_login_shell >/dev/null 2>&1; then
                current="$(nivuus_current_login_shell)"
            else
                current="${SHELL:-}"
            fi
            if [ "$current" = "$ref" ]; then
                return 0        # déjà restauré (ou jamais changé)
            fi
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "restaurerait le shell de connexion : $ref"
                return 0
            fi
            if command -v chsh >/dev/null 2>&1 && chsh -s "$ref" >/dev/null 2>&1; then
                log_ok "Shell de connexion restauré : $ref"
            else
                # Jamais de sudo, jamais d'édition de /etc/passwd : on
                # explique. Une entrée CHSH non appliquée n'est pas un
                # survivant au sens du manifeste (aucun fichier en jeu).
                log_warn "Shell de connexion non restauré automatiquement."
                log_warn "Restaure-le avec : chsh -s $ref"
            fi
            ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_manifest_restore.bats tests/e2e/test_reversibility.bats`
Expected: PASS — dont tous les tests d'empreinte préexistants.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/helpers/fingerprint.bash tests/unit/test_lib_manifest_restore.bats tests/e2e/test_reversibility.bats
git commit -m "feat(uninstall): restore the original login shell and fingerprint it"
```

---

### Task 8: `--minimal` de bout en bout — installeur, bloc `.zshrc`, prompt

**Files:**
- Modify: `bin/nivuus`, `lib/zshrc.sh`, `lib/steps.sh`, `config/05-prompt.zsh`, `install.sh`
- Test: `tests/unit/test_lib_zshrc.bats` (complété), `tests/unit/test_prompt_minimal.bats` (nouveau), `tests/e2e/test_minimal_mode.bats` (nouveau)

**Interfaces:**
- Consumes: `nivuus_should_minimal`
- Produces :
  - `nivuus_zshrc_block <install_dir> [minimal]` — ajoute `export NIVUUS_MINIMAL=1` dans le bloc quand le second argument est non vide ;
  - `nivuus_step_write_zshrc <target> <install_dir> [minimal]` — transmet le drapeau ;
  - `bin/nivuus` : `--minimal` / `--no-minimal`, sinon auto via `nivuus_should_minimal` ; la variable interne `MINIMAL` pilote `chsh` (Task 6) et les dépendances (Task 5) ; un `log_info` annonce le mode choisi ;
  - `config/05-prompt.zsh` : quatre glyphes passent par des variables surchargeables, en repli ASCII quand `NIVUUS_MINIMAL` est défini.

Note d'arbitrage : le spec dit « pas de glyphes dans le prompt » en `--minimal`. Le prompt n'utilise **aucune nerd font** — seulement `○ ● ▶ ⏸` (Unicode standard). Le seul réellement risqué sur une console sans police riche est `⏸` (U+23F8). On garde donc le rendu actuel par défaut et on ne dégrade en ASCII que sous `NIVUUS_MINIMAL`, via des variables : c'est la plus petite modification de `config/` compatible avec « ce chantier ne change pas ce que fait Nivuus ».

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_prompt_minimal.bats
#!/usr/bin/env bats

setup() { ROOT="${BATS_TEST_DIRNAME}/../.."; }

load_prompt() {   # load_prompt "<env>" "<expr>"
    run zsh -c "export NIVUUS_SHELL_DIR='$ROOT'; $1 \
                source '$ROOT/themes/nord.zsh'; source '$ROOT/config/05-prompt.zsh'; $2"
}

@test "the prompt glyphs are Unicode by default" {
    load_prompt "" 'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN$NIVUUS_GLYPH_JOB_STOPPED"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"●"* ]]
    [[ "$output" == *"⏸"* ]]
}

@test "NIVUUS_MINIMAL falls back to pure ASCII glyphs" {
    load_prompt "export NIVUUS_MINIMAL=1;" \
        'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN|$NIVUUS_GLYPH_GIT_DIRTY|$NIVUUS_GLYPH_JOB_RUNNING|$NIVUUS_GLYPH_JOB_STOPPED"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"●"* ]]
    [[ "$output" != *"○"* ]]
    [[ "$output" != *"▶"* ]]
    [[ "$output" != *"⏸"* ]]
}

@test "the glyphs stay user-overridable" {
    load_prompt "export NIVUUS_GLYPH_GIT_CLEAN=OK;" 'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN"'
    [ "$output" = "OK" ]
}

@test "git_prompt_info uses the ASCII glyph under NIVUUS_MINIMAL" {
    run zsh -c "export NIVUUS_SHELL_DIR='$ROOT'; export NIVUUS_MINIMAL=1; \
                source '$ROOT/themes/nord.zsh'; source '$ROOT/config/05-prompt.zsh'; \
                cd '$ROOT'; git_prompt_info"
    [ "$status" -eq 0 ]
    [[ "$output" != *"●"* && "$output" != *"○"* ]]
}
```

```bash
# tests/e2e/test_minimal_mode.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n: > "%s/CHSH_RAN"\n' "$TMP" > "$TMP/bin/chsh"; chmod +x "$TMP/bin/chsh"
    export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "minimal mode is chosen automatically without a TTY" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"minimal"* ]]
    [ ! -f "$TMP/CHSH_RAN" ]
}

@test "the minimal block exports NIVUUS_MINIMAL" {
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    run grep -c 'export NIVUUS_MINIMAL=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "a full install writes no NIVUUS_MINIMAL export" {
    "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    run grep -c 'NIVUUS_MINIMAL' "$HOME/.zshrc"
    [ "$output" = "0" ]
}

@test "switching from minimal to full rewrites the block, not the file" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    run grep -c 'NIVUUS_MINIMAL' "$HOME/.zshrc"
    [ "$output" = "0" ]
    run grep -c 'export MINE=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "a minimal install stays fully reversible" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ "$(cat "$HOME/.zshrc")" = "export MINE=1" ]
}

@test "a minimal install still starts a working shell" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    run zsh -i -c 'echo MINIMAL_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MINIMAL_OK"* ]]
}
```

Ajouter à `tests/unit/test_lib_zshrc.bats` :

```bash
@test "the block carries NIVUUS_MINIMAL only when asked" {
    run bash -c "source '$LIB/zshrc.sh'; nivuus_zshrc_block /opt/nivuus"
    [[ "$output" != *"NIVUUS_MINIMAL"* ]]
    run bash -c "source '$LIB/zshrc.sh'; nivuus_zshrc_block /opt/nivuus 1"
    [[ "$output" == *"export NIVUUS_MINIMAL=1"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_prompt_minimal.bats tests/e2e/test_minimal_mode.bats`
Expected: FAIL — `NIVUUS_GLYPH_GIT_CLEAN` vide, pas d'`export NIVUUS_MINIMAL` dans le bloc, `--no-minimal` inconnue.

- [ ] **Step 3: Write minimal implementation**

`lib/zshrc.sh` — remplacer `nivuus_zshrc_block` :

```sh
nivuus_zshrc_block() {
    local install_dir="$1" minimal="${2:-}"
    printf '%s\n' "$NIVUUS_BLOCK_BEGIN"
    printf '%s\n' '# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.'
    printf '%s\n' "# Pour tes personnalisations, crée ~/.zsh_local (il n'existe pas par défaut)"
    printf 'export NIVUUS_SHELL_DIR="%s"\n' "$install_dir"
    [ -n "$minimal" ] && printf '%s\n' 'export NIVUUS_MINIMAL=1'
    printf '%s\n' 'source "$NIVUUS_SHELL_DIR/.zshrc"'
    printf '%s\n' "$NIVUUS_BLOCK_END"
}
```

et propager le second argument dans `nivuus_zshrc_merge` :

```sh
nivuus_zshrc_merge() {
    local file="$1" install_dir="$2" minimal="${3:-}" state
    ...
        missing)  nivuus_zshrc_block "$install_dir" "$minimal" ;;
        present)  nivuus_zshrc_block "$install_dir" "$minimal"; nivuus_zshrc_strip "$file" ;;
        absent)   nivuus_zshrc_block "$install_dir" "$minimal"; cat "$file"; ... ;;
```

`lib/steps.sh` :

```sh
nivuus_step_write_zshrc() {
    local target="$1" install_dir="$2" minimal="${3:-}" merged
    ...
    merged="$(nivuus_zshrc_merge "$target" "$install_dir" "$minimal")" || return 1
```

`bin/nivuus`, dans `cmd_install` — ajouter les options et la résolution du mode :

```sh
            --minimal)     FORCE_MINIMAL=1 ;;
            --no-minimal)  FORCE_FULL=1 ;;
```

puis, après la boucle d'options et avant `nivuus_step_check_required_deps` :

```sh
    # Le mode se décide ici, une fois, et se transmet ensuite explicitement
    # (jamais relu depuis l'environnement au fond d'une étape).
    if [ -n "${FORCE_FULL:-}" ]; then
        MINIMAL=''
        export NIVUUS_NO_MINIMAL=1
    elif [ -n "${FORCE_MINIMAL:-}" ]; then
        MINIMAL=1
        export NIVUUS_MINIMAL=1
    elif nivuus_should_minimal; then
        MINIMAL=1
    else
        MINIMAL=''
    fi
    if [ -n "$MINIMAL" ]; then
        log_info "Mode minimal (serveur, container, SSH ou sans TTY) : pas de chsh, pas d'extras."
    fi
```

et transmettre au bloc :

```sh
        || ! nivuus_step_write_zshrc "$HOME/.zshrc" "$prefix" "$MINIMAL"; then
```

`config/05-prompt.zsh` — en tête du fichier :

```zsh
# Glyphes du prompt. Aucun n'est une nerd font ; en mode minimal (serveur,
# container, console sans police riche) on retombe malgré tout sur de l'ASCII
# pur. Surchargeables individuellement par l'utilisateur.
if [[ -n "${NIVUUS_MINIMAL:-}" ]]; then
    : ${NIVUUS_GLYPH_GIT_DIRTY:=o}
    : ${NIVUUS_GLYPH_GIT_CLEAN:=+}
    : ${NIVUUS_GLYPH_JOB_RUNNING:=>}
    : ${NIVUUS_GLYPH_JOB_STOPPED:=_}
else
    : ${NIVUUS_GLYPH_GIT_DIRTY:=○}
    : ${NIVUUS_GLYPH_GIT_CLEAN:=●}
    : ${NIVUUS_GLYPH_JOB_RUNNING:=▶}
    : ${NIVUUS_GLYPH_JOB_STOPPED:=⏸}
fi
```

puis remplacer les quatre littéraux (`○`, `●` dans `git_prompt_info` ; `▶`, `⏸` dans `background_jobs_info`) par `${NIVUUS_GLYPH_*}`.

`install.sh` : `--minimal` est déjà transmis ; `--no-minimal` a été ajouté en Task 5.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_prompt_minimal.bats tests/unit/test_prompt.bats tests/unit/test_lib_zshrc.bats tests/e2e/test_minimal_mode.bats tests/e2e/test_reversibility.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/nivuus lib/zshrc.sh lib/steps.sh config/05-prompt.zsh tests/unit/test_prompt_minimal.bats tests/unit/test_lib_zshrc.bats tests/e2e/test_minimal_mode.bats
git commit -m "feat(install): make --minimal effective end to end"
```

---

### Task 9: `lib/` exécutable par BusyBox ash (cible Alpine)

**Files:**
- Modify: `lib/steps.sh` (suppression de la substitution de processus), tout `lib/*.sh` si le test révèle un autre bashisme
- Test: `tests/unit/test_lib_posix.bats` (nouveau)

**Interfaces:**
- Consumes: rien
- Produces : garantie exécutable — chaque `lib/*.sh` passe `sh -n`, se source sans erreur sous `sh` (dash ou BusyBox), et ses fonctions pures y répondent correctement. `bin/nivuus` et `install.sh` restent bash (décision du spec) et sont hors de ce test.

Note d'arbitrage : le spec choisit bash 3.2 comme langage. La cible Alpine ne remet pas ce choix en cause (`bash` est un prérequis d'installation sur Alpine, comme `zsh`) mais `lib/` a vocation à être réutilisé par le bootstrap POSIX du one-liner en phase 5 — d'où la contrainte, imposée ici pendant qu'elle coûte une seule ligne. `lib/steps.sh` viole aujourd'hui cette règle avec `done < <(find …)` ; le remplacement par un fichier temporaire préserve la propriété qui avait motivé la substitution de processus (la boucle ne tourne **pas** dans un sous-shell, donc un `return 1` d'échec d'écriture remonte bien).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_posix.bats
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_posix.bats`
Expected: FAIL — `no lib file uses a process substitution` échoue (`lib/steps.sh:20`), et le test de sourçage POSIX échoue à l'analyse de `steps.sh`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/steps.sh`, remplacer la boucle de copie :

```sh
    local d f list
    list="$(mktemp)"
    for d in config themes bin plugins lib; do
        [ -d "$src/$d" ] || continue
        # Fichier temporaire plutôt que `< <(find ...)` (bash-only) ou
        # `find ... | while` : le pipe mettrait la boucle dans un sous-shell,
        # où un `return 1` sur échec d'écriture (disque plein, EPERM) serait
        # perdu à la sortie du sous-shell et l'installation se croirait
        # réussie. Le fichier temporaire préserve les deux propriétés :
        # POSIX, et pas de sous-shell.
        find "$src/$d" -type f ! -name '*.zwc' ! -path '*/.git/*' > "$list"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rel="${f#"$src"/}"
            if ! nivuus_install_file "$f" "$dst/$rel"; then
                rm -f "$list"
                return 1
            fi
        done < "$list"
    done
    rm -f "$list"
```

Corriger tout autre bashisme que le test signale dans `lib/` (à ce jour : aucun autre — `bin/nivuus` et `install.sh` ne sont pas concernés).

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_posix.bats tests/unit/test_lib_steps.bats tests/e2e/`
Expected: PASS — copie et réversibilité inchangées.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/unit/test_lib_posix.bats
git commit -m "fix(lib): keep every library runnable under a POSIX shell"
```

---

### Task 10: Tests portables macOS/BusyBox — supprimer les `sed -i`

**Files:**
- Create: `tests/helpers/portable.bash`
- Modify: `tests/unit/test_lib_zshrc.bats`, `tests/e2e/test_reversibility.bats`
- Test: `tests/unit/test_helpers_portable.bats` (nouveau)

**Interfaces:**
- Consumes: rien
- Produces :
  - `pt_prepend_line <file> <text>` — insère une ligne en tête, sans `sed -i` ;
  - `pt_to_crlf <file>` — convertit le fichier en CRLF, sans `sed -i`.
- Motif : `sed -i` n'a pas la même signature sous GNU (`sed -i 's/…/`) et sous BSD/macOS (`sed -i '' 's/…/`). Les deux usages actuels (`test_lib_zshrc.bats:117,135` et `test_reversibility.bats:114`) font échouer toute la suite sur le runner `macos-latest`, qui est précisément la sortie de cette phase.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_helpers_portable.bats
#!/usr/bin/env bats

load '../helpers/portable'

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

@test "pt_prepend_line inserts at the top and keeps the rest byte-for-byte" {
    printf 'b\nc\n' > "$TMP/f"
    pt_prepend_line "$TMP/f" 'a'
    run cat "$TMP/f"
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
    [ "${lines[2]}" = "c" ]
}

@test "pt_prepend_line preserves the file permissions" {
    printf 'b\n' > "$TMP/f"; chmod 600 "$TMP/f"
    pt_prepend_line "$TMP/f" 'a'
    run bash -c "stat -c '%a' '$TMP/f' 2>/dev/null || stat -f '%Lp' '$TMP/f'"
    [ "$output" = "600" ]
}

@test "pt_to_crlf ends every line with CR LF" {
    printf 'a\nb\n' > "$TMP/f"
    pt_to_crlf "$TMP/f"
    run od -c "$TMP/f"
    [[ "$output" == *'\r'*'\n'* ]]
}

@test "no test file uses sed -i" {
    run grep -rn 'sed -i' "${BATS_TEST_DIRNAME}/../unit" "${BATS_TEST_DIRNAME}/../e2e"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_helpers_portable.bats`
Expected: FAIL — `tests/helpers/portable.bash` n'existe pas, et `grep 'sed -i'` trouve trois occurrences.

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/helpers/portable.bash
# Édition de fichiers dans les tests, sans `sed -i` : GNU sed veut
# `sed -i 's/…/'`, BSD/macOS veut `sed -i '' 's/…/'`. Les deux formes sont
# mutuellement exclusives -- toute suite qui en utilise une échoue sur
# l'autre plateforme. On n'en utilise donc aucune.

pt_prepend_line() {
    local file="$1" text="$2" tmp
    tmp="$(mktemp)"
    { printf '%s\n' "$text"; cat "$file"; } > "$tmp"
    # cat > "$file" (et non mv) : préserve permissions et inode.
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

pt_to_crlf() {
    local file="$1" tmp
    tmp="$(mktemp)"
    awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}
```

Dans `tests/unit/test_lib_zshrc.bats` : ajouter `load '../helpers/portable'` en tête, remplacer les deux `sed -i 's/$/\r/' "$TMP/.zshrc"` par `pt_to_crlf "$TMP/.zshrc"`.

Dans `tests/e2e/test_reversibility.bats` : ajouter `load '../helpers/portable'`, remplacer `sed -i '1i alias early=1' "$HOME/.zshrc"` par `pt_prepend_line "$HOME/.zshrc" 'alias early=1'`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_helpers_portable.bats tests/unit/test_lib_zshrc.bats tests/e2e/test_reversibility.bats`
Expected: PASS — comportement identique, sans `sed -i`.

- [ ] **Step 5: Commit**

```bash
git add tests/helpers/portable.bash tests/unit/test_helpers_portable.bats tests/unit/test_lib_zshrc.bats tests/e2e/test_reversibility.bats
git commit -m "test: replace sed -i with portable helpers for macOS"
```

---

### Task 11: E2E de plateforme — WSL simulé, gestionnaire absent, container Alpine

**Files:**
- Create: `tests/e2e/test_platform.bats`
- Test: le fichier lui-même

**Interfaces:**
- Consumes: `bin/nivuus`, `lib/detect.sh`
- Produces : la preuve de bout en bout que les branches ajoutées se comportent comme annoncé, sur des marqueurs injectés (WSL) et dans un vrai container Alpine quand Docker est disponible (sinon `skip`).

Note : le job WSL est une **simulation** — il valide la branche de code, pas l'environnement. Le spec l'assume explicitement (§4).

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_platform.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
}

teardown() { rm -rf "$TMP"; }

@test "install works with WSL markers injected" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    run env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/.zshrc" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "uninstall reverts a WSL install completely" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" install --yes --prefix "$TMP/target"
    env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" uninstall --yes --purge
    [ "$(cat "$HOME/.zshrc")" = "export MINE=1" ]
}

@test "install fails with a copyable command when a required dep is missing" {
    mkdir -p "$TMP/bin"
    # PATH sans zsh, mais avec de quoi tourner.
    for c in cat cp mv rm mkdir rmdir find awk sed grep printf id uname dirname \
             head tail wc tr sort cut mktemp chmod stat sha256sum shasum touch ls date git curl; do
        p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$TMP/bin/$c"
    done
    run env PATH="$TMP/bin" "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [ ! -e "$TMP/target" ]
    [ ! -e "$NIVUUS_STATE_DIR/manifest.tsv" ]
}

@test "install then uninstall is clean inside an Alpine container" {
    command -v docker >/dev/null 2>&1 || skip "docker unavailable"
    run docker run --rm -v "$ROOT:/src:ro" alpine:3.20 sh -c '
        set -e
        apk add --no-cache bash zsh git curl >/dev/null
        cp -r /src /work && cd /work
        export HOME=/root
        ./bin/nivuus install --yes --prefix "$HOME/.nivuus-shell"
        test -f "$HOME/.nivuus-shell/.zshrc"
        grep -q ">>> nivuus shell >>>" "$HOME/.zshrc"
        zsh -i -c "echo ALPINE_SHELL_OK"
        ./bin/nivuus uninstall --yes --purge
        test ! -e "$HOME/.nivuus-shell"
        echo ALPINE_CLEAN_OK
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALPINE_SHELL_OK"* ]]
    [[ "$output" == *"ALPINE_CLEAN_OK"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_platform.bats`
Expected: FAIL — au minimum le test Alpine (BusyBox `find`/`stat`, absence de coreutils GNU) et/ou le test « dépendance manquante » si un artefact partiel subsiste.

- [ ] **Step 3: Write minimal implementation**

Corriger ce que les tests révèlent, en respectant les contraintes globales. Points connus à vérifier en priorité :
- `nivuus_step_check_required_deps` doit échouer **avant** `nivuus_manifest_begin` (c'est déjà l'ordre dans `cmd_install` : ne pas l'inverser), sinon un `$NIVUUS_STATE_DIR` orphelin reste derrière.
- BusyBox : `find -type f`, `stat -c`, `sha256sum`, `awk`, `sed '1!G;h;$!d'`, `tail -n +N`, `cp -p`, `mktemp -d` sont tous disponibles ; `readlink -f`, `sed -i` (dialecte GNU), `stat --format` ne le sont pas de manière fiable — les proscrire.
- Ne rien ajouter au conteneur au-delà de `bash zsh git curl` : le but de la cible Alpine est de valider le chemin **sans** coreutils GNU.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_platform.bats`
Expected: PASS (le test Alpine `skip` si Docker est absent en local ; il est bloquant en CI, Task 12).

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_platform.bats lib bin
git commit -m "test(e2e): cover WSL markers, missing deps and Alpine"
```

---

### Task 12: CI — macOS et Alpine deviennent bloquants

**Files:**
- Modify: `.github/workflows/tests.yml`
- Test: le workflow lui-même (vérifié par une exécution réelle sur la PR)

**Interfaces:**
- Consumes: les suites `tests/unit/test_lib_*.bats`, `tests/unit/test_helpers_portable.bats`, `tests/e2e/*.bats`
- Produces : deux jobs supplémentaires — `e2e-macos` (runner `macos-latest`) et `e2e-alpine` (`container: alpine:3.20`) — exécutés sur chaque PR.

Note de périmètre : la matrice complète (Ubuntu 22.04/24.04, Debian, Arch, Fedora, WSL, découpage PR/nightly/release, badges) relève de la **phase 4**. Ici on n'ajoute que les deux cibles qui constituent la sortie de la phase 3.

- [ ] **Step 1: Write the failing test**

Ajouter à `.github/workflows/tests.yml`, après le job `e2e` existant :

```yaml
  e2e-macos:
    name: Installation E2E (macOS)
    runs-on: macos-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install zsh and bats
        run: brew install bats-core zsh

      - name: Setup test environment
        run: echo "NIVUUS_SHELL_DIR=$GITHUB_WORKSPACE" >> $GITHUB_ENV

      - name: Library unit tests
        run: bats tests/unit/test_lib_*.bats tests/unit/test_helpers_portable.bats

      - name: Install / uninstall E2E
        run: bats tests/e2e/test_nivuus_cli.bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_minimal_mode.bats

      - name: Reversibility (HOME must be bit-identical)
        run: bats tests/e2e/test_reversibility.bats

  e2e-alpine:
    name: Installation E2E (Alpine / musl, no GNU coreutils)
    runs-on: ubuntu-latest
    container:
      image: alpine:3.20

    steps:
      - name: Install the minimum (deliberately no GNU coreutils)
        run: apk add --no-cache bash zsh git curl ncurses

      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install bats
        run: |
          git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
          /tmp/bats/install.sh /usr/local

      - name: Setup test environment
        run: echo "NIVUUS_SHELL_DIR=$GITHUB_WORKSPACE" >> $GITHUB_ENV

      - name: Library unit tests
        run: bats tests/unit/test_lib_*.bats tests/unit/test_helpers_portable.bats

      - name: Install / uninstall E2E
        run: bats tests/e2e/test_nivuus_cli.bats tests/e2e/test_minimal_mode.bats

      - name: Reversibility (HOME must be bit-identical)
        run: bats tests/e2e/test_reversibility.bats
```

Ajouter aussi, au job `e2e` existant (Ubuntu), les nouvelles suites :

```yaml
      - name: Platform, deps and minimal-mode E2E
        run: bats tests/e2e/test_platform.bats tests/e2e/test_with_deps.bats tests/e2e/test_minimal_mode.bats
```

- [ ] **Step 2: Run test to verify it fails**

Pousser la branche et regarder l'exécution : `gh run watch` (ou `gh run list --limit 1`).
Expected: FAIL — au premier passage, au moins une différence de plateforme (BSD `stat`, `sed`, `find`, ou permissions par défaut) fait échouer un job.

- [ ] **Step 3: Write minimal implementation**

Corriger les échecs réels, dans `lib/`, `bin/nivuus` ou les tests selon la cause, en respectant les contraintes globales. Ne **jamais** neutraliser un test d'empreinte pour faire passer un runner : si l'empreinte diverge sur macOS ou Alpine, c'est une trace réellement laissée par l'installeur sur cette plateforme.

- [ ] **Step 4: Run test to verify it passes**

`gh run watch` : les jobs `test`, `e2e`, `e2e-macos`, `e2e-alpine` et `lint` sont tous verts.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "ci: make macOS and Alpine installation tests blocking"
```

---

## Vérification finale de la phase

Une fois les 12 tâches terminées, ces commandes doivent toutes réussir :

```bash
bats tests/unit/test_lib_*.bats tests/unit/test_helpers_portable.bats tests/unit/test_prompt_minimal.bats
bats tests/e2e/                                   # dont réversibilité, minimal, plateforme, deps
./bin/nivuus install --dry-run --yes              # n'écrit rien, décrit tout, ne demande aucun privilège
grep -rn 'sed -i' tests/                          # aucun résultat
grep -rn '< *<(' lib/                             # aucun résultat
```

Et, sur la CI de la PR : `test`, `e2e`, `e2e-macos`, `e2e-alpine`, `lint` verts.

Critères de sortie de phase, tels que définis par le spec :

1. Installation et désinstallation vérifiées sur **macOS** (runner réel) et **Alpine** (container réel, sans coreutils GNU).
2. Aucun `sudo` n'est exécuté sans `--with-deps` **et** une confirmation explicite — prouvé par les faux binaires de `tests/unit/test_lib_deps.bats` et `tests/e2e/test_with_deps.bats`.
3. `chsh` vérifie `/etc/shells` avant d'agir, est journalisé au manifeste, et est restauré à la désinstallation — prouvé par l'empreinte du shell de connexion.
4. `--minimal` est automatique en container/SSH/headless, forçable dans les deux sens, et effectif sur `chsh`, les dépendances et le prompt.

## Ce que ce plan ne livre pas

Reporté aux plans suivants, conformément au spec :

- **Phase 4** — matrice CI complète (Ubuntu 22.04/24.04, Debian 12, Arch, Fedora 41, job WSL dédié), découpage PR / nightly / release, badges du README dont « uninstall verified ».
- **Phase 5** — vrai one-liner `curl | sh` (bootstrap POSIX + tarball de release), suppression de `init_git_repo` avec migration, refonte de `doctor` (installation partielle, `.zshrc` divergent, bloc corrompu), documentation d'installation.
- **Mode `--system`** (`/etc/nivuus-shell`, `/var/lib/nivuus`, `/etc/skel`) : toujours refusé avec un message explicite par `install.sh`. Le manifeste le prévoit (`mode`, `NIVUUS_STATE_DIR`), rien ne l'active.
- **Nerd fonts** : aucune installation de police, sur aucune plateforme. `--minimal` se contente de ne pas *supposer* qu'il y en a une ; le mode complet ne fait rien de plus. À trancher au chantier 4 (paquets natifs) si le besoin se confirme.
- **Vendoring de `fzf-tab`** : l'ancien `install.sh` faisait un `git clone` dans `~/.nivuus-shell/plugins/`. Non réintroduit ici : cloner une arborescence entière contourne le manifeste (des dizaines de fichiers créés hors journal, donc non réversibles). Le rétablir demande de cloner dans un répertoire temporaire puis de placer chaque fichier via `nivuus_install_file` — faisable, mais c'est une tâche à part entière, et `fzf-tab` reste facultatif (`fzf` seul suffit à la dégradation gracieuse). À traiter au chantier 4 ou dans un plan dédié.
- **`date +%s%N` dans `tests/performance/`** : GNU-only, donc cette suite ne tourne pas sur `macos-latest`. Hors périmètre : les jobs macOS et Alpine ajoutés ici n'exécutent que `tests/unit/test_lib_*` et `tests/e2e/`. À corriger en phase 4 si la matrice complète doit inclure les performances hors Ubuntu.
- **Le template `~/.zsh_local`** disparu avec `create_local_config` (relevé en fin du plan des phases 1–2) : le bloc `.zshrc` a été reformulé pour dire « crée `~/.zsh_local` », ce qui referme l'incohérence sans créer de fichier que `--purge` ne pourrait pas reprendre. Point clos, aucune action ici.
- **Les suggestions de fin d'installation** (`suggest_optional_tools` de l'ancien installeur) sont, elles, bien réintroduites — par `nivuus_deps_suggest` (Tasks 4 et 5).
