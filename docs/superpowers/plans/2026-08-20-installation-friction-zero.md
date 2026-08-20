# Installation « friction zéro » — Plan d'implémentation (phases 1–2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre l'installation de Nivuus Shell tracée, auditable en `--dry-run`, et intégralement réversible par `nivuus uninstall`, sans jamais écraser le `.zshrc` de l'utilisateur.

**Architecture:** Extraction de `install.sh` en bibliothèques bash à responsabilité unique sous `lib/`, pilotées par une CLI unique `bin/nivuus`. Toute mutation du système de fichiers passe par `lib/manifest.sh`, qui journalise l'action et le hash de l'original dans `~/.local/state/nivuus/manifest.tsv` avant d'écrire — ce qui rend `--dry-run` fiable par construction et la désinstallation exacte. Le `.zshrc` de l'utilisateur est fusionné via un bloc délimité, jamais remplacé.

**Tech Stack:** bash 3.2, zsh (cible installée), bats (tests), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-20-installation-friction-zero-design.md`

**Périmètre de ce plan :** phases 1 (socle) et 2 (réversibilité) du spec. Les phases 3 (multi-plateforme), 4 (matrice CI) et 5 (one-liner `curl | sh`) feront l'objet de plans distincts.

## Global Constraints

- **bash 3.2** est le plancher (macOS système). Interdits : `declare -A` / tableaux associatifs, `mapfile` / `readarray`, `${var^^}` / `${var,,}`, `&>>`, `local -n`. Utiliser `while IFS= read -r` pour itérer.
- **Aucune dépendance hors** `coreutils`, `git`, `curl`, et le shell. Pas de `jq`, pas de `python`.
- **`set -euo pipefail`** en tête de chaque exécutable ; les bibliothèques `lib/*.sh` ne le fixent pas elles-mêmes (elles sont sourcées).
- **Toute mutation du système de fichiers** passe par `lib/manifest.sh`. Aucun `cp`, `mv`, `rm`, `mkdir`, `>` direct ailleurs que dans `lib/manifest.sh`.
- **`NIVUUS_DRY_RUN=1`** doit garantir zéro écriture disque, y compris dans `~/.local/state/nivuus/`.
- **Jamais de `sudo`** non explicitement demandé par l'utilisateur.
- **`~/.zsh_history` n'est jamais supprimé ni modifié**, quelles que soient les options.
- **Format du manifeste :** TSV à 4 colonnes séparées par une tabulation littérale, actions `CREATE`, `MODIFY`, `MKDIR`, `CHSH`, `PKG`.
- **Chemins d'état :** `NIVUUS_STATE_DIR` vaut `${XDG_STATE_HOME:-$HOME/.local/state}/nivuus` en mode user, `/var/lib/nivuus` en mode `--system`.
- **Tests :** bats, dans `tests/unit/` pour les bibliothèques et `tests/e2e/` pour les scénarios d'installation.

---

### Task 1: Bibliothèque de sortie `lib/log.sh`

**Files:**
- Create: `lib/log.sh`
- Test: `tests/unit/test_lib_log.bats`

**Interfaces:**
- Consumes: rien
- Produces: `log_info(msg)`, `log_ok(msg)`, `log_warn(msg)`, `log_error(msg)`, `log_dry(msg)` — `log_warn` et `log_error` écrivent sur **stderr** (convention Unix), les trois autres sur stdout ; honorent `NIVUUS_QUIET=1` (seuls `log_warn`/`log_error` survivent) et désactivent les couleurs si stdout n'est pas un TTY ou si `NO_COLOR` est défini.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_log.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    unset NIVUUS_QUIET NO_COLOR
}

@test "log_info writes to stdout" {
    source "$LIB/log.sh"
    run log_info "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "log_error writes to stderr, not stdout" {
    source "$LIB/log.sh"
    run bash -c "source '$LIB/log.sh'; log_error 'boom' 2>/dev/null"
    [ "$output" = "" ]
}

@test "NIVUUS_QUIET silences log_info but not log_error" {
    run bash -c "export NIVUUS_QUIET=1; source '$LIB/log.sh'; log_info 'quiet'"
    [ "$output" = "" ]
    run bash -c "export NIVUUS_QUIET=1; source '$LIB/log.sh'; log_error 'loud' 2>&1"
    [[ "$output" == *"loud"* ]]
}

@test "no ANSI escapes when not a TTY" {
    run bash -c "source '$LIB/log.sh'; log_ok 'plain'"
    [[ "$output" != *$'\033'* ]]
}

@test "NO_COLOR disables color" {
    run bash -c "export NO_COLOR=1; source '$LIB/log.sh'; log_warn 'nc' 2>&1"
    [[ "$output" != *$'\033'* ]]
}

@test "log_dry prefixes with dry-run marker" {
    run bash -c "source '$LIB/log.sh'; log_dry 'would write /tmp/x'"
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"/tmp/x"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_log.bats`
Expected: FAIL — `lib/log.sh` n'existe pas (« No such file or directory »).

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/log.sh
# Sortie utilisateur. Aucune connaissance du métier.
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _C_RED=$'\033[0;31m'; _C_GREEN=$'\033[0;32m'
    _C_YELLOW=$'\033[0;33m'; _C_BLUE=$'\033[0;34m'
    _C_DIM=$'\033[2m'; _C_OFF=$'\033[0m'
else
    _C_RED=''; _C_GREEN=''; _C_YELLOW=''; _C_BLUE=''; _C_DIM=''; _C_OFF=''
fi

log_info()  { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_BLUE}·${_C_OFF} $*"; }
log_ok()    { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_GREEN}✓${_C_OFF} $*"; }
log_warn()  { printf '%s\n' "${_C_YELLOW}!${_C_OFF} $*" >&2; }
log_error() { printf '%s\n' "${_C_RED}✗${_C_OFF} $*" >&2; }
log_dry()   { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_DIM}[dry-run]${_C_OFF} $*"; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_log.bats`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/log.sh tests/unit/test_lib_log.bats
git commit -m "feat(lib): add log.sh output library"
```

---

### Task 2: Hachage portable dans `lib/manifest.sh`

**Files:**
- Create: `lib/manifest.sh`
- Test: `tests/unit/test_lib_manifest_hash.bats`

**Interfaces:**
- Consumes: rien
- Produces: `nivuus_hash_file <path>` — imprime le sha256 hexadécimal en minuscules, ou `-` si le fichier n'existe pas ; retourne 0 dans les deux cas. Utilise `sha256sum` (GNU) ou `shasum -a 256` (macOS/BSD).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_manifest_hash.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus_hash_file returns the known sha256 of an empty file" {
    : > "$TMP/empty"
    run nivuus_hash_file "$TMP/empty"
    [ "$status" -eq 0 ]
    [ "$output" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "nivuus_hash_file returns the known sha256 of 'abc'" {
    printf 'abc' > "$TMP/abc"
    run nivuus_hash_file "$TMP/abc"
    [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}

@test "nivuus_hash_file returns dash for a missing file" {
    run nivuus_hash_file "$TMP/nope"
    [ "$status" -eq 0 ]
    [ "$output" = "-" ]
}

@test "nivuus_hash_file handles paths with spaces" {
    printf 'abc' > "$TMP/with space"
    run nivuus_hash_file "$TMP/with space"
    [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_manifest_hash.bats`
Expected: FAIL — `lib/manifest.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/manifest.sh
# Journal des mutations et restauration.
# SEULE bibliothèque autorisée à écrire sur le système de fichiers.

nivuus_hash_file() {
    local path="$1"
    [ -f "$path" ] || { printf '%s\n' '-'; return 0; }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | cut -d' ' -f1
    else
        log_error "Aucun outil sha256 disponible (sha256sum ou shasum requis)"
        return 1
    fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_manifest_hash.bats`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/unit/test_lib_manifest_hash.bats
git commit -m "feat(lib): add portable sha256 hashing"
```

---

### Task 3: Journal du manifeste — ouverture, enregistrement, validation atomique

**Files:**
- Modify: `lib/manifest.sh`
- Test: `tests/unit/test_lib_manifest_journal.bats`

**Interfaces:**
- Consumes: `nivuus_hash_file` (Task 2), `log_error` (Task 1)
- Produces:
  - `nivuus_manifest_begin <mode> <install_dir>` — initialise un manifeste temporaire ; définit `NIVUUS_STATE_DIR`, `NIVUUS_MANIFEST`, `NIVUUS_BACKUP_DIR` s'ils ne le sont pas déjà.
  - `nivuus_manifest_record <action> <path> <hash> <ref>` — ajoute une ligne ; refuse (code 1) un chemin contenant une tabulation ou un saut de ligne.
  - `nivuus_manifest_commit` — remplace atomiquement le manifeste définitif par le temporaire.
  - `nivuus_manifest_each <callback>` — appelle `callback action path hash ref` pour chaque entrée, en **ordre inverse** d'écriture (pour que la désinstallation défasse dans l'ordre inverse de l'installation).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_manifest_journal.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
}

teardown() { rm -rf "$TMP"; }

@test "manifest_begin creates the state dir and a header line" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_commit
    [ -f "$NIVUUS_MANIFEST" ]
    run head -1 "$NIVUUS_MANIFEST"
    [[ "$output" == "#nivuus-manifest v1"* ]]
    [[ "$output" == *"mode=user"* ]]
    [[ "$output" == *"dir=$TMP/install"* ]]
}

@test "manifest_record appends a tab-separated line" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "deadbeef" "-"
    nivuus_manifest_commit
    run grep -c . "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]
    run tail -1 "$NIVUUS_MANIFEST"
    [ "$output" = "$(printf 'CREATE\t/tmp/a\tdeadbeef\t-')" ]
}

@test "manifest_record rejects a path containing a tab" {
    nivuus_manifest_begin user "$TMP/install"
    run nivuus_manifest_record CREATE "$(printf 'bad\tpath')" "x" "-"
    [ "$status" -eq 1 ]
}

@test "manifest is not visible until commit" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    [ ! -f "$NIVUUS_MANIFEST" ]
    nivuus_manifest_commit
    [ -f "$NIVUUS_MANIFEST" ]
}

@test "manifest_each iterates entries in reverse order, skipping the header" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record MKDIR "/tmp/d" "-" "-"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    nivuus_manifest_commit
    collect() { printf '%s:%s ' "$1" "$2"; }
    run nivuus_manifest_each collect
    [ "$output" = "CREATE:/tmp/a MKDIR:/tmp/d " ]
}

@test "dry-run writes nothing to disk" {
    export NIVUUS_DRY_RUN=1
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    nivuus_manifest_commit
    [ ! -d "$NIVUUS_STATE_DIR" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_manifest_journal.bats`
Expected: FAIL — `nivuus_manifest_begin: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/manifest.sh`, après `nivuus_hash_file` :

```bash
NIVUUS_TAB="$(printf '\t')"

nivuus_manifest_begin() {
    local mode="$1" install_dir="$2"
    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"
    NIVUUS_MANIFEST="$NIVUUS_STATE_DIR/manifest.tsv"
    NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"
    NIVUUS_MANIFEST_TMP="$NIVUUS_STATE_DIR/.manifest.tsv.new"

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        NIVUUS_MANIFEST_TMP="$(mktemp)"
    else
        mkdir -p "$NIVUUS_STATE_DIR" "$NIVUUS_BACKUP_DIR"
    fi

    printf '#nivuus-manifest v1\tinstalled_at=%s\tmode=%s\tdir=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$install_dir" \
        > "$NIVUUS_MANIFEST_TMP"
}

nivuus_manifest_record() {
    local action="$1" path="$2" hash="$3" ref="$4"
    case "$path" in
        *"$NIVUUS_TAB"*|*'
'*)
            log_error "Chemin non supporté (tabulation ou saut de ligne) : $path"
            return 1
            ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$action" "$path" "$hash" "$ref" >> "$NIVUUS_MANIFEST_TMP"
}

nivuus_manifest_commit() {
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$NIVUUS_MANIFEST_TMP"
        return 0
    fi
    mv "$NIVUUS_MANIFEST_TMP" "$NIVUUS_MANIFEST"
}

nivuus_manifest_each() {
    local callback="$1"
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    # tail -r n'existe pas partout ; on inverse avec sed.
    grep -v '^#' "$NIVUUS_MANIFEST" | sed '1!G;h;$!d' | while IFS="$NIVUUS_TAB" read -r a p h r; do
        [ -n "$a" ] || continue
        "$callback" "$a" "$p" "$h" "$r"
    done
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_manifest_journal.bats`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/unit/test_lib_manifest_journal.bats
git commit -m "feat(lib): add manifest journal with atomic commit"
```

---

### Task 4: Mutations tracées — `nivuus_mkdir_p`, `nivuus_install_file`

**Files:**
- Modify: `lib/manifest.sh`
- Test: `tests/unit/test_lib_manifest_mutations.bats`

**Interfaces:**
- Consumes: `nivuus_manifest_record`, `nivuus_hash_file`
- Produces:
  - `nivuus_store_backup <path>` — copie le fichier dans `$NIVUUS_BACKUP_DIR/<sha256>` et imprime le sha ; imprime `-` si le fichier n'existe pas.
  - `nivuus_mkdir_p <dir>` — crée le répertoire s'il manque et enregistre `MKDIR` (une entrée par niveau créé, du plus profond au plus superficiel non existant) ; ne fait rien s'il existe déjà.
  - `nivuus_install_file <src> <dst>` — enregistre `CREATE` si `dst` n'existait pas, `MODIFY` (avec backup de l'original) sinon ; **`SKIP` silencieux si le contenu est déjà identique** (idempotence) ; respecte `NIVUUS_DRY_RUN`.
  - `nivuus_write_file <dst>` — même contrat, mais le contenu est lu depuis stdin (utilisé pour `.zshrc` et `.version`).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_manifest_mutations.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"
}

teardown() { rm -rf "$TMP"; }

@test "install_file creates the destination and records CREATE" {
    printf 'hello' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    [ "$(cat "$TMP/dst")" = "hello" ]
    nivuus_manifest_commit
    run grep -c "^CREATE" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "install_file over an existing file records MODIFY and backs up the original" {
    printf 'old' > "$TMP/dst"
    printf 'new' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    [ "$(cat "$TMP/dst")" = "new" ]
    nivuus_manifest_commit
    run grep -c "^MODIFY" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
    # le backup de 'old' est retrouvable par son hash
    old_hash="$(printf 'old' | { command -v sha256sum >/dev/null && sha256sum || shasum -a 256; } | cut -d' ' -f1)"
    [ -f "$NIVUUS_BACKUP_DIR/$old_hash" ]
    [ "$(cat "$NIVUUS_BACKUP_DIR/$old_hash")" = "old" ]
}

@test "install_file is idempotent: identical content records nothing" {
    printf 'same' > "$TMP/src"
    printf 'same' > "$TMP/dst"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    nivuus_manifest_commit
    run grep -c "^CREATE\|^MODIFY" "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
}

@test "mkdir_p records MKDIR only for levels it creates" {
    nivuus_mkdir_p "$TMP/a/b"
    [ -d "$TMP/a/b" ]
    nivuus_manifest_commit
    run grep -c "^MKDIR" "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]
}

@test "mkdir_p on an existing dir records nothing" {
    mkdir -p "$TMP/exists"
    nivuus_mkdir_p "$TMP/exists"
    nivuus_manifest_commit
    run grep -c "^MKDIR" "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
}

@test "write_file takes content from stdin" {
    printf 'from stdin' | nivuus_write_file "$TMP/out"
    [ "$(cat "$TMP/out")" = "from stdin" ]
}

@test "dry-run mutates nothing on disk" {
    export NIVUUS_DRY_RUN=1
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/never"
    nivuus_mkdir_p "$TMP/never-dir"
    [ ! -e "$TMP/never" ]
    [ ! -e "$TMP/never-dir" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_manifest_mutations.bats`
Expected: FAIL — `nivuus_install_file: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/manifest.sh` :

```bash
nivuus_store_backup() {
    local path="$1" hash
    hash="$(nivuus_hash_file "$path")"
    [ "$hash" = "-" ] && { printf '%s\n' '-'; return 0; }
    if [ -z "${NIVUUS_DRY_RUN:-}" ] && [ ! -f "$NIVUUS_BACKUP_DIR/$hash" ]; then
        cp -p "$path" "$NIVUUS_BACKUP_DIR/$hash"
    fi
    printf '%s\n' "$hash"
}

nivuus_mkdir_p() {
    local dir="$1" missing='' d
    d="$dir"
    # Collecte les niveaux manquants, du plus profond au plus superficiel.
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
        missing="$missing$d
"
        d="$(dirname "$d")"
    done
    [ -n "$missing" ] || return 0

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "mkdir -p $dir"
    else
        mkdir -p "$dir"
    fi
    printf '%s' "$missing" | while IFS= read -r level; do
        [ -n "$level" ] && nivuus_manifest_record MKDIR "$level" '-' '-'
    done
}

# Coeur partagé : $1 = destination, contenu déjà présent dans $2 (fichier source).
_nivuus_place() {
    local src="$1" dst="$2" existed=0 backup='-' new_hash

    [ -f "$dst" ] && existed=1
    if [ "$existed" -eq 1 ] && [ "$(nivuus_hash_file "$src")" = "$(nivuus_hash_file "$dst")" ]; then
        return 0   # idempotent : rien à faire, rien à journaliser
    fi

    if [ "$existed" -eq 1 ]; then
        backup="$(nivuus_store_backup "$dst")"
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        if [ "$existed" -eq 1 ]; then log_dry "modifierait $dst"; else log_dry "créerait $dst"; fi
        new_hash="$(nivuus_hash_file "$src")"
    else
        nivuus_mkdir_p "$(dirname "$dst")"
        cp -p "$src" "$dst"
        new_hash="$(nivuus_hash_file "$dst")"
    fi

    if [ "$existed" -eq 1 ]; then
        nivuus_manifest_record MODIFY "$dst" "$new_hash" "$backup"
    else
        nivuus_manifest_record CREATE "$dst" "$new_hash" '-'
    fi
}

nivuus_install_file() { _nivuus_place "$1" "$2"; }

nivuus_write_file() {
    local dst="$1" tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    _nivuus_place "$tmp" "$dst"
    rm -f "$tmp"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_manifest_mutations.bats`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/unit/test_lib_manifest_mutations.bats
git commit -m "feat(lib): add tracked filesystem mutations with dry-run support"
```

---

### Task 5: Fusion du `.zshrc` — `lib/zshrc.sh`

**Files:**
- Create: `lib/zshrc.sh`
- Test: `tests/unit/test_lib_zshrc.bats`

**Interfaces:**
- Consumes: `log_error` (Task 1)
- Produces (toutes pures : écrivent sur stdout, ne touchent pas au disque) :
  - `nivuus_zshrc_state <file>` — imprime `missing`, `absent`, `present` ou `corrupt`.
  - `nivuus_zshrc_block <install_dir>` — imprime le bloc délimité.
  - `nivuus_zshrc_merge <file> <install_dir>` — imprime le contenu fusionné complet ; échoue (code 1) si l'état est `corrupt`.
  - `nivuus_zshrc_strip <file>` — imprime le contenu sans le bloc.
  - `nivuus_zshrc_detect_framework <file>` — imprime le nom des frameworks concurrents détectés, un par ligne.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_zshrc.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/zshrc.sh"
    TMP="$(mktemp -d)"
    DIR="/home/u/.nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "state is missing when the file does not exist" {
    run nivuus_zshrc_state "$TMP/nope"
    [ "$output" = "missing" ]
}

@test "state is absent for a zshrc without the block" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "absent" ]
}

@test "state is present when both markers exist" {
    nivuus_zshrc_block "$DIR" > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "present" ]
}

@test "state is corrupt when the closing marker is missing" {
    printf '# >>> nivuus shell >>>\nsource x\n' > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "corrupt" ]
}

@test "block references the install dir and .zsh_local" {
    run nivuus_zshrc_block "$DIR"
    [[ "$output" == *"$DIR"* ]]
    [[ "$output" == *".zsh_local"* ]]
}

@test "merge into a missing file yields the block alone" {
    run nivuus_zshrc_merge "$TMP/nope" "$DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> nivuus shell >>>"* ]]
}

@test "merge inserts the block at the top, preserving user content" {
    printf 'export FOO=1\nalias ll=ls\n' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run head -1 "$TMP/out"
    [ "$output" = "# >>> nivuus shell >>>" ]
    run grep -c "export FOO=1" "$TMP/out"
    [ "$output" = "1" ]
    run grep -c "alias ll=ls" "$TMP/out"
    [ "$output" = "1" ]
}

@test "merge is idempotent: twice yields exactly one block" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/once"
    cp "$TMP/once" "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/twice"
    run grep -c ">>> nivuus shell >>>" "$TMP/twice"
    [ "$output" = "1" ]
    run diff "$TMP/once" "$TMP/twice"
    [ "$status" -eq 0 ]
}

@test "merge replaces only the block content, leaving the rest intact" {
    { printf '# >>> nivuus shell >>>\nOLD CONTENT\n# <<< nivuus shell <<<\n'; \
      printf 'export KEEP=1\n'; } > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run grep -c "OLD CONTENT" "$TMP/out"
    [ "$status" -ne 0 ]
    run grep -c "export KEEP=1" "$TMP/out"
    [ "$output" = "1" ]
}

@test "merge refuses a corrupt file" {
    printf '# >>> nivuus shell >>>\nbroken\n' > "$TMP/.zshrc"
    run nivuus_zshrc_merge "$TMP/.zshrc" "$DIR"
    [ "$status" -eq 1 ]
}

@test "merge handles a file with no trailing newline" {
    printf 'export FOO=1' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run grep -c "export FOO=1" "$TMP/out"
    [ "$output" = "1" ]
}

@test "strip removes the block and restores the original content" {
    printf 'export FOO=1\n' > "$TMP/orig"
    nivuus_zshrc_merge "$TMP/orig" "$DIR" > "$TMP/.zshrc"
    nivuus_zshrc_strip "$TMP/.zshrc" > "$TMP/back"
    run diff "$TMP/orig" "$TMP/back"
    [ "$status" -eq 0 ]
}

@test "strip on a file without the block is a no-op" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    nivuus_zshrc_strip "$TMP/.zshrc" > "$TMP/out"
    run diff "$TMP/.zshrc" "$TMP/out"
    [ "$status" -eq 0 ]
}

@test "detect_framework finds oh-my-zsh" {
    printf 'source $ZSH/oh-my-zsh.sh\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [[ "$output" == *"oh-my-zsh"* ]]
}

@test "detect_framework finds starship" {
    printf 'eval "$(starship init zsh)"\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [[ "$output" == *"starship"* ]]
}

@test "detect_framework outputs nothing for a plain zshrc" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [ "$output" = "" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_zshrc.bats`
Expected: FAIL — `lib/zshrc.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/zshrc.sh
# Lecture, fusion et retrait du bloc Nivuus dans un .zshrc.
# Toutes les fonctions sont pures : elles écrivent sur stdout.

NIVUUS_BLOCK_BEGIN='# >>> nivuus shell >>>'
NIVUUS_BLOCK_END='# <<< nivuus shell <<<'

nivuus_zshrc_state() {
    local file="$1" has_begin=0 has_end=0
    [ -f "$file" ] || { printf 'missing\n'; return 0; }
    grep -qF "$NIVUUS_BLOCK_BEGIN" "$file" && has_begin=1
    grep -qF "$NIVUUS_BLOCK_END" "$file" && has_end=1
    if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ]; then
        printf 'present\n'
    elif [ "$has_begin" -eq 0 ] && [ "$has_end" -eq 0 ]; then
        printf 'absent\n'
    else
        printf 'corrupt\n'
    fi
}

nivuus_zshrc_block() {
    local install_dir="$1"
    cat <<EOF
$NIVUUS_BLOCK_BEGIN
# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.
# Mets tes personnalisations dans ~/.zsh_local
export NIVUUS_SHELL_DIR="$install_dir"
source "\$NIVUUS_SHELL_DIR/.zshrc"
$NIVUUS_BLOCK_END
EOF
}

nivuus_zshrc_strip() {
    local file="$1"
    [ -f "$file" ] || return 0
    awk -v b="$NIVUUS_BLOCK_BEGIN" -v e="$NIVUUS_BLOCK_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip   { print }
    ' "$file"
}

nivuus_zshrc_merge() {
    local file="$1" install_dir="$2" state
    state="$(nivuus_zshrc_state "$file")"
    case "$state" in
        corrupt)
            log_error "Marqueurs Nivuus incohérents dans $file (bloc ouvert sans fermeture)."
            log_error "Répare-le à la main ou restaure une sauvegarde ; Nivuus n'y touchera pas."
            return 1
            ;;
        missing)
            nivuus_zshrc_block "$install_dir"
            ;;
        present)
            # Remplace le bloc, conserve le reste tel quel.
            nivuus_zshrc_block "$install_dir"
            nivuus_zshrc_strip "$file"
            ;;
        absent)
            nivuus_zshrc_block "$install_dir"
            cat "$file"
            # Garantit une newline finale si le fichier n'en avait pas.
            [ -n "$(tail -c 1 "$file")" ] && printf '\n'
            ;;
    esac
}

nivuus_zshrc_detect_framework() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -qF 'oh-my-zsh' "$file" && printf 'oh-my-zsh\n'
    grep -qF 'prezto' "$file" && printf 'prezto\n'
    grep -qF 'zinit' "$file" && printf 'zinit\n'
    grep -qF 'starship init' "$file" && printf 'starship\n'
    grep -qF 'powerlevel10k' "$file" && printf 'powerlevel10k\n'
    return 0
}
```

Note d'implémentation : dans le cas `present`, le bloc est ré-émis **en tête** puis le reste du fichier dépouillé est concaté. Un bloc qui était au milieu du fichier remonte donc en tête — c'est voulu et cohérent avec la règle « ce qui vient après gagne » du spec.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_zshrc.bats`
Expected: PASS, 16 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/zshrc.sh tests/unit/test_lib_zshrc.bats
git commit -m "feat(lib): add zshrc block merge, never overwrite user config"
```

---

### Task 6: Détection de plateforme minimale — `lib/detect.sh`

**Files:**
- Create: `lib/detect.sh`
- Test: `tests/unit/test_lib_detect.bats`

**Interfaces:**
- Consumes: rien
- Produces: `nivuus_detect_os` (imprime `linux` ou `macos`), `nivuus_is_container` (code 0 si container), `nivuus_is_tty` (code 0 si stdin ET stdout sont des TTY), `nivuus_should_minimal` (code 0 si le mode minimal doit s'appliquer : container ou absence de TTY).

Note de périmètre : la détection WSL, la distro et le préfixe Homebrew relèvent de la **phase 3** et ne sont pas implémentés ici. Ce module ne couvre que ce dont les phases 1–2 ont besoin.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_detect.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/detect.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "detect_os returns linux or macos" {
    run nivuus_detect_os
    [[ "$output" = "linux" || "$output" = "macos" ]]
}

@test "is_container is true when /.dockerenv exists" {
    export NIVUUS_DOCKERENV="$TMP/.dockerenv"
    : > "$NIVUUS_DOCKERENV"
    run nivuus_is_container
    [ "$status" -eq 0 ]
}

@test "is_container is false without any container marker" {
    export NIVUUS_DOCKERENV="$TMP/absent"
    export NIVUUS_CGROUP="$TMP/absent"
    unset container
    run nivuus_is_container
    [ "$status" -eq 1 ]
}

@test "is_container is true when the container env var is set" {
    export NIVUUS_DOCKERENV="$TMP/absent"
    export NIVUUS_CGROUP="$TMP/absent"
    export container=podman
    run nivuus_is_container
    [ "$status" -eq 0 ]
}

@test "is_tty is false under bats (no controlling terminal)" {
    run nivuus_is_tty
    [ "$status" -eq 1 ]
}

@test "should_minimal is true when there is no TTY" {
    run nivuus_should_minimal
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_detect.bats`
Expected: FAIL — `lib/detect.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/detect.sh
# Détection de plateforme. Ne connaît pas le système de fichiers cible.
# Les chemins système sont paramétrables pour rester testables.

: "${NIVUUS_DOCKERENV:=/.dockerenv}"
: "${NIVUUS_CGROUP:=/proc/1/cgroup}"

nivuus_detect_os() {
    case "$(uname -s)" in
        Darwin) printf 'macos\n' ;;
        *)      printf 'linux\n' ;;
    esac
}

nivuus_is_container() {
    [ -f "$NIVUUS_DOCKERENV" ] && return 0
    [ -n "${container:-}" ] && return 0
    grep -qE '(docker|lxc|containerd)' "$NIVUUS_CGROUP" 2>/dev/null && return 0
    return 1
}

nivuus_is_tty() {
    [ -t 0 ] && [ -t 1 ]
}

nivuus_should_minimal() {
    nivuus_is_container && return 0
    nivuus_is_tty || return 0
    return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_detect.bats`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/unit/test_lib_detect.bats
git commit -m "feat(lib): add minimal platform detection"
```

---

### Task 7: Étapes d'installation — `lib/steps.sh`

**Files:**
- Create: `lib/steps.sh`
- Test: `tests/unit/test_lib_steps.bats`

**Interfaces:**
- Consumes: `nivuus_install_file`, `nivuus_write_file`, `nivuus_mkdir_p` (Task 4) ; `nivuus_zshrc_merge`, `nivuus_zshrc_detect_framework` (Task 5) ; `log_*` (Task 1)
- Produces:
  - `nivuus_step_copy_tree <src_root> <install_dir>` — copie `config/`, `themes/`, `bin/`, `plugins/`, `.zshrc`, `.vimrc.nord`, en ignorant les `.zwc` et `.git`.
  - `nivuus_step_write_zshrc <target_zshrc> <install_dir>` — fusionne le bloc via `nivuus_zshrc_merge`.
  - `nivuus_step_write_version <src_root> <install_dir>` — écrit `.version`.
  - `nivuus_step_check_required_deps` — vérifie `zsh`, `git`, `curl` ; imprime la commande d'installation adaptée et retourne 1 si l'un manque. **N'installe rien.**

**Écart assumé avec le spec :** le spec prévoit un module `lib/deps.sh` distinct. Les phases 1–2 n'ont besoin que du constat des dépendances requises (une fonction), pas de la politique `--with-deps` complète. Créer un fichier pour une seule fonction serait prématuré : `lib/deps.sh` sera extrait en phase 3, quand `--with-deps`, les niveaux recommandé/optionnel et la demande de privilège groupée arriveront. La fonction déménagera alors sans changer de nom.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_steps.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/detect.sh"
    source "$LIB/manifest.sh"; source "$LIB/zshrc.sh"; source "$LIB/steps.sh"
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
    if ! command -v zsh >/dev/null || ! command -v git >/dev/null; then
        skip "dépendances absentes dans cet environnement"
    fi
    run nivuus_step_check_required_deps
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_steps.bats`
Expected: FAIL — `lib/steps.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/steps.sh
# Étapes d'installation, chacune idempotente.
# N'écrit jamais en direct : tout passe par lib/manifest.sh.

nivuus_step_copy_tree() {
    local src="$1" dst="$2" rel
    nivuus_mkdir_p "$dst"

    # Répertoires copiés récursivement, en excluant .zwc et .git.
    local d
    for d in config themes bin plugins; do
        [ -d "$src/$d" ] || continue
        find "$src/$d" -type f \
            ! -name '*.zwc' \
            ! -path '*/.git/*' | while IFS= read -r f; do
            rel="${f#$src/}"
            nivuus_install_file "$f" "$dst/$rel"
        done
    done

    # Fichiers à la racine.
    local f
    for f in .zshrc .vimrc.nord; do
        [ -f "$src/$f" ] && nivuus_install_file "$src/$f" "$dst/$f"
    done
    return 0
}

nivuus_step_write_zshrc() {
    local target="$1" install_dir="$2" merged

    local fw
    fw="$(nivuus_zshrc_detect_framework "$target")"
    if [ -n "$fw" ]; then
        log_warn "Ton .zshrc charge déjà : $(printf '%s' "$fw" | tr '\n' ' ')"
        log_warn "Deux prompts risquent de se marcher dessus. Nivuus n'y touche pas."
    fi

    merged="$(nivuus_zshrc_merge "$target" "$install_dir")" || return 1
    printf '%s\n' "$merged" | nivuus_write_file "$target"
}

nivuus_step_write_version() {
    local src="$1" dst="$2"
    [ -f "$src/.version" ] || return 0
    nivuus_install_file "$src/.version" "$dst/.version"
}

nivuus_step_check_required_deps() {
    local missing='' c
    for c in zsh git curl; do
        command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
    done
    [ -n "$missing" ] || return 0

    log_error "Dépendances requises manquantes :$missing"
    if command -v apt-get >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo apt-get install$missing"
    elif command -v dnf >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo dnf install$missing"
    elif command -v pacman >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo pacman -S$missing"
    elif command -v brew >/dev/null 2>&1; then
        log_error "Installe-les avec : brew install$missing"
    else
        log_error "Installe-les avec ton gestionnaire de paquets :$missing"
    fi
    return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_steps.bats`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/unit/test_lib_steps.bats
git commit -m "feat(lib): add idempotent installation steps"
```

---

### Task 8: Restauration depuis le manifeste

**Files:**
- Modify: `lib/manifest.sh`
- Test: `tests/unit/test_lib_manifest_restore.bats`

**Interfaces:**
- Consumes: `nivuus_manifest_each`, `nivuus_hash_file`, `log_*`
- Produces: `nivuus_restore_entry <action> <path> <hash> <ref>` — applique les quatre règles de désinstallation du spec ; `nivuus_manifest_rollback` — appelle `nivuus_restore_entry` sur chaque entrée en ordre inverse.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_manifest_restore.bats
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

@test "PKG entries are ignored by rollback" {
    nivuus_manifest_record PKG fzf - apt-get
    nivuus_manifest_commit
    run nivuus_manifest_rollback
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_manifest_restore.bats`
Expected: FAIL — `nivuus_manifest_rollback: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/manifest.sh` :

```bash
nivuus_restore_entry() {
    local action="$1" path="$2" hash="$3" ref="$4" current

    case "$action" in
        CREATE)
            current="$(nivuus_hash_file "$path")"
            if [ "$current" = "-" ]; then
                return 0                      # déjà absent
            elif [ "$current" = "$hash" ]; then
                if [ -n "${NIVUUS_DRY_RUN:-}" ]; then log_dry "supprimerait $path"
                else rm -f "$path"; fi
            else
                log_warn "Conservé (modifié depuis l'installation) : $path"
            fi
            ;;
        MODIFY)
            current="$(nivuus_hash_file "$path")"
            if [ "$current" != "$hash" ]; then
                log_warn "Conservé (modifié depuis l'installation) : $path"
                log_warn "Sauvegarde d'origine disponible : $NIVUUS_BACKUP_DIR/$ref"
                return 0
            fi
            if [ ! -f "$NIVUUS_BACKUP_DIR/$ref" ]; then
                log_warn "Sauvegarde introuvable pour $path, fichier conservé"
                return 0
            fi
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then log_dry "restaurerait $path"
            else cp -p "$NIVUUS_BACKUP_DIR/$ref" "$path"; fi
            ;;
        MKDIR)
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "supprimerait le répertoire (si vide) $path"
            else
                rmdir "$path" 2>/dev/null || true   # non vide : on le laisse
            fi
            ;;
        CHSH)
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "restaurerait le shell de connexion : $ref"
            else
                log_info "Shell de connexion d'origine : $ref"
                log_info "Restaure-le avec : chsh -s $ref"
            fi
            ;;
        PKG)
            return 0    # jamais désinstallé
            ;;
    esac
    return 0
}

nivuus_manifest_rollback() {
    nivuus_manifest_each nivuus_restore_entry
}
```

Note : `CHSH` n'exécute pas `chsh` lui-même — cette commande peut exiger un mot de passe et bloquer une désinstallation non interactive. On affiche la commande exacte.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_manifest_restore.bats`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/unit/test_lib_manifest_restore.bats
git commit -m "feat(lib): add manifest-driven rollback"
```

---

### Task 9: CLI `bin/nivuus` — `install`, `uninstall`, `--dry-run`

**Files:**
- Create: `bin/nivuus`
- Test: `tests/e2e/test_nivuus_cli.bats`

**Interfaces:**
- Consumes: toutes les bibliothèques `lib/*.sh`
- Produces: l'exécutable `bin/nivuus` avec les sous-commandes `install`, `uninstall`, `update`, `doctor`, `help`. `update` et `doctor` délèguent respectivement à la fonction shell existante `nivuus-update` et à `bin/healthcheck` (leur refonte relève de la phase 5).

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_nivuus_cli.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus is executable" {
    [ -x "$NIVUUS" ]
}

@test "help exits 0 and lists the subcommands" {
    run "$NIVUUS" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "an unknown subcommand exits non-zero" {
    run "$NIVUUS" bogus
    [ "$status" -ne 0 ]
}

@test "install --dry-run touches nothing" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$TMP/state" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "install --dry-run reports what it would do" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [[ "$output" == *"dry-run"* ]]
}

@test "install creates the target and a zshrc block" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
    [ -f "$TMP/target/.zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "install never creates a git repo in the target" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}

@test "install twice is idempotent" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    cp "$HOME/.zshrc" "$TMP/zshrc.first"
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    run diff "$TMP/zshrc.first" "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}

@test "install preserves a pre-existing zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run grep -c "export MINE=42" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "uninstall removes the install dir and restores the zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [ ! -d "$TMP/target" ]
    [ "$(cat "$HOME/.zshrc")" = "export MINE=42" ]
}

@test "uninstall never deletes zsh_history" {
    printf 'precious\n' > "$HOME/.zsh_history"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$HOME/.zsh_history" ]
    [ "$(cat "$HOME/.zsh_history")" = "precious" ]
}

@test "uninstall --dry-run changes nothing" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --dry-run --yes
    [ "$status" -eq 0 ]
    [ -d "$TMP/target" ]
}

@test "uninstall without a manifest exits cleanly with a message" {
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"aucune installation"* ]] || [[ "$output" == *"Aucune installation"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_nivuus_cli.bats`
Expected: FAIL — `bin/nivuus` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# bin/nivuus — point d'entrée unique de gestion de Nivuus Shell.
set -euo pipefail

NIVUUS_SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$NIVUUS_SRC_ROOT/lib/log.sh"
. "$NIVUUS_SRC_ROOT/lib/detect.sh"
. "$NIVUUS_SRC_ROOT/lib/manifest.sh"
. "$NIVUUS_SRC_ROOT/lib/zshrc.sh"
. "$NIVUUS_SRC_ROOT/lib/steps.sh"

usage() {
    cat <<'EOF'
nivuus — gestion de Nivuus Shell

Usage :
  nivuus install   [--dry-run] [--yes] [--prefix DIR] [--minimal]
  nivuus uninstall [--dry-run] [--yes] [--purge]
  nivuus update
  nivuus doctor
  nivuus help

Options :
  --dry-run   N'écrit rien ; affiche ce qui serait fait.
  --yes       Ne pose aucune question.
  --prefix    Répertoire d'installation (défaut : ~/.nivuus-shell).
  --minimal   Mode serveur/container : pas de chsh, pas d'extras.
  --purge     (uninstall) supprime aussi ~/.zsh_local et l'état.
              ~/.zsh_history n'est JAMAIS supprimé.
EOF
}

confirm() {
    [ -n "${ASSUME_YES:-}" ] && return 0
    nivuus_is_tty || return 0
    printf '%s [Y/n] ' "$1"
    local reply; read -r reply
    case "$reply" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

cmd_install() {
    local prefix="$HOME/.nivuus-shell"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) export NIVUUS_DRY_RUN=1 ;;
            --yes|-y)  ASSUME_YES=1 ;;
            --minimal) export NIVUUS_MINIMAL=1 ;;
            --prefix)  shift; prefix="$1" ;;
            *) log_error "Option inconnue : $1"; return 2 ;;
        esac
        shift
    done

    nivuus_step_check_required_deps || return 1
    confirm "Installer Nivuus Shell dans $prefix ?" || { log_info "Annulé."; return 0; }

    nivuus_manifest_begin user "$prefix"
    nivuus_step_copy_tree "$NIVUUS_SRC_ROOT" "$prefix"
    nivuus_step_write_version "$NIVUUS_SRC_ROOT" "$prefix"
    nivuus_step_write_zshrc "$HOME/.zshrc" "$prefix" || { log_error "Installation interrompue."; return 1; }
    nivuus_manifest_commit

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_info "Aucune modification effectuée (--dry-run)."
    else
        log_ok "Nivuus Shell installé dans $prefix"
        log_info "Lance « exec zsh » pour démarrer."
    fi
}

cmd_uninstall() {
    local purge=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) export NIVUUS_DRY_RUN=1 ;;
            --yes|-y)  ASSUME_YES=1 ;;
            --purge)   purge=1 ;;
            *) log_error "Option inconnue : $1"; return 2 ;;
        esac
        shift
    done

    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"
    NIVUUS_MANIFEST="$NIVUUS_STATE_DIR/manifest.tsv"
    NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"

    if [ ! -f "$NIVUUS_MANIFEST" ]; then
        log_info "Aucune installation Nivuus tracée ; rien à faire."
        return 0
    fi

    confirm "Désinstaller Nivuus Shell et restaurer la configuration d'origine ?" \
        || { log_info "Annulé."; return 0; }

    nivuus_manifest_rollback

    if [ -n "$purge" ] && [ -z "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$HOME/.zsh_local"
        rm -rf "$NIVUUS_STATE_DIR"
        log_info "Configuration personnelle supprimée (--purge). L'historique est conservé."
    elif [ -z "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$NIVUUS_MANIFEST"
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_info "Aucune modification effectuée (--dry-run)."
    else
        log_ok "Nivuus Shell désinstallé."
    fi
}

main() {
    local cmd="${1:-help}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
        install)   cmd_install "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        update)    exec zsh -ic 'nivuus-update' ;;
        doctor)    exec "$NIVUUS_SRC_ROOT/bin/healthcheck" ;;
        help|--help|-h) usage ;;
        *) log_error "Sous-commande inconnue : $cmd"; usage >&2; return 2 ;;
    esac
}

main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bin/nivuus && bats tests/e2e/test_nivuus_cli.bats`
Expected: PASS, 13 tests.

- [ ] **Step 5: Commit**

```bash
git add bin/nivuus tests/e2e/test_nivuus_cli.bats
git commit -m "feat(cli): add nivuus install/uninstall with dry-run"
```

---

### Task 10: `install.sh` devient un wrapper rétrocompatible

**Files:**
- Modify: `install.sh` (remplacement complet du contenu)
- Test: `tests/e2e/test_install_sh_compat.bats`

**Interfaces:**
- Consumes: `bin/nivuus` (Task 9)
- Produces: `install.sh` acceptant les anciens flags `--system`, `--non-interactive`, `--health-check`, `--no-backup`, `--help` et les traduisant vers `nivuus install`.

Note : `--system` n'est pas encore implémenté côté CLI (phase 3). Le wrapper doit échouer explicitement avec un message clair plutôt que d'ignorer silencieusement le flag.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_install_sh_compat.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "install.sh --help still works" {
    run "$ROOT/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"sage"* ]]
}

@test "install.sh --non-interactive installs without prompting" {
    run "$ROOT/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
}

@test "install.sh --system fails with an explicit message" {
    run "$ROOT/install.sh" --system --non-interactive
    [ "$status" -ne 0 ]
    [[ "$output" == *"--system"* ]]
}

@test "install.sh --no-backup is accepted" {
    run "$ROOT/install.sh" --non-interactive --no-backup --prefix "$TMP/target"
    [ "$status" -eq 0 ]
}

@test "install.sh no longer creates a git repo" {
    "$ROOT/install.sh" --non-interactive --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_install_sh_compat.bats`
Expected: FAIL — l'ancien `install.sh` ne connaît pas `--prefix` et crée un dépôt git.

- [ ] **Step 3: Write minimal implementation**

Remplacer intégralement `install.sh` par :

```bash
#!/usr/bin/env bash
# install.sh — wrapper rétrocompatible autour de « nivuus install ».
# La logique vit dans bin/nivuus et lib/. Ce fichier ne fait que traduire
# les anciennes options.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --system)
            printf '%s\n' "L'installation système (--system) n'est pas encore disponible dans cette version." >&2
            printf '%s\n' "Utilise l'installation utilisateur (sans --system) en attendant." >&2
            exit 1
            ;;
        --non-interactive) ARGS="$ARGS --yes" ;;
        --health-check)    RUN_DOCTOR=1 ;;
        --no-backup)       : ;;   # accepté, sans effet : le manifeste sauvegarde toujours
        --dry-run)         ARGS="$ARGS --dry-run" ;;
        --minimal)         ARGS="$ARGS --minimal" ;;
        --prefix)          shift; ARGS="$ARGS --prefix $1" ;;
        --help|-h)         exec "$ROOT/bin/nivuus" help ;;
        *) printf 'Option inconnue : %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

# shellcheck disable=SC2086
"$ROOT/bin/nivuus" install $ARGS

if [ -n "${RUN_DOCTOR:-}" ]; then
    "$ROOT/bin/nivuus" doctor
fi
```

Note : `--no-backup` est accepté sans effet et documenté comme tel — avec le manifeste, la sauvegarde est le mécanisme même de la réversibilité et la désactiver n'aurait plus de sens. Le flag reste accepté pour ne casser aucun script existant.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_install_sh_compat.bats`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/e2e/test_install_sh_compat.bats
git commit -m "refactor(install): turn install.sh into a thin nivuus wrapper"
```

---

### Task 11: Test de réversibilité par empreinte de `$HOME`

**Files:**
- Create: `tests/helpers/fingerprint.bash`
- Create: `tests/e2e/test_reversibility.bats`

**Interfaces:**
- Consumes: `bin/nivuus` (Task 9)
- Produces: `fs_fingerprint <dir>` — imprime une ligne triée `chemin<TAB>permissions<TAB>sha256` par fichier, plus une ligne `DIR<TAB>chemin` par répertoire.

C'est le test qui garantit la promesse centrale du spec. Il doit rester vert en permanence.

- [ ] **Step 1: Write the failing test**

```bash
# tests/helpers/fingerprint.bash
# Empreinte reproductible d'une arborescence : chemin, permissions, contenu.

fs_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fs_perms() {
    # -c GNU, -f BSD/macOS
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

fs_fingerprint() {
    local root="$1"
    { find "$root" -type d | while IFS= read -r d; do
          printf 'DIR\t%s\t%s\n' "${d#$root}" "$(fs_perms "$d")"
      done
      find "$root" -type f | while IFS= read -r f; do
          printf 'FILE\t%s\t%s\t%s\n' "${f#$root}" "$(fs_perms "$f")" "$(fs_hash "$f")"
      done
    } | LC_ALL=C sort
}
```

```bash
# tests/e2e/test_reversibility.bats
#!/usr/bin/env bats

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
}

teardown() { rm -rf "$TMP"; }

@test "install then uninstall leaves HOME bit-identical (empty HOME)" {
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install then uninstall leaves HOME bit-identical (populated HOME)" {
    mkdir -p "$HOME/projects/app"
    printf 'export MINE=42\nalias ll="ls -la"\n' > "$HOME/.zshrc"
    printf 'my history\n' > "$HOME/.zsh_history"
    printf 'code\n' > "$HOME/projects/app/main.py"
    chmod 600 "$HOME/.zshrc"

    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"

    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install then uninstall leaves HOME bit-identical (oh-my-zsh present)" {
    mkdir -p "$HOME/.oh-my-zsh"
    printf 'export ZSH="$HOME/.oh-my-zsh"\nsource $ZSH/oh-my-zsh.sh\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "dry-run install leaves HOME bit-identical" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --dry-run --yes --prefix "$HOME/.nivuus-shell"
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "a double install then a single uninstall still reverts fully" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_reversibility.bats`
Expected: FAIL. Deux causes probables, toutes deux à corriger dans `lib/`, jamais en assouplissant le test :
- le répertoire d'état `~/.local/state` subsiste après `--purge` (n'était pas là avant) ;
- une seconde installation réenregistre des entrées qui perturbent le rollback.

- [ ] **Step 3: Fix the libraries until the fingerprint matches**

Correction attendue dans `cmd_uninstall` (`bin/nivuus`) : après `--purge`, retirer aussi les répertoires parents d'état devenus vides, sans jamais utiliser `rm -rf` sur un chemin non enregistré.

```bash
    # dans cmd_uninstall, après le rm -rf "$NIVUUS_STATE_DIR"
    rmdir "$(dirname "$NIVUUS_STATE_DIR")" 2>/dev/null || true   # ~/.local/state
    rmdir "$HOME/.local" 2>/dev/null || true
```

Pour la double installation : `nivuus_manifest_begin` repart d'un manifeste neuf à chaque `install`, et la seconde installation n'enregistre rien pour les fichiers identiques (idempotence, Task 4). Le manifeste final ne contient donc plus les entrées `CREATE` de la première passe. **C'est le bug à corriger :** `cmd_install` doit, lorsqu'un manifeste existe déjà, reprendre ses entrées comme base plutôt que de les perdre.

```bash
# dans lib/manifest.sh — à ajouter et appeler depuis cmd_install avant les étapes
nivuus_manifest_inherit() {
    # Reprend les entrées d'un manifeste existant dans le manifeste en cours,
    # pour qu'une réinstallation ne perde pas la trace de la première.
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    grep -v '^#' "$NIVUUS_MANIFEST" >> "$NIVUUS_MANIFEST_TMP" || true
}
```

Appel dans `cmd_install`, juste après `nivuus_manifest_begin` :

```bash
    nivuus_manifest_begin user "$prefix"
    nivuus_manifest_inherit
```

Puis dédupliquer dans `nivuus_manifest_each` pour ne pas traiter deux fois le même chemin :

```bash
nivuus_manifest_each() {
    local callback="$1" seen
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    seen="$(mktemp)"
    grep -v '^#' "$NIVUUS_MANIFEST" | sed '1!G;h;$!d' | while IFS="$NIVUUS_TAB" read -r a p h r; do
        [ -n "$a" ] || continue
        if grep -qxF "$p" "$seen" 2>/dev/null; then continue; fi
        printf '%s\n' "$p" >> "$seen"
        "$callback" "$a" "$p" "$h" "$r"
    done
    rm -f "$seen"
}
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `bats tests/unit/ tests/e2e/`
Expected: PASS, tous les tests des tâches 1 à 11.

- [ ] **Step 5: Commit**

```bash
git add tests/helpers/fingerprint.bash tests/e2e/test_reversibility.bats lib/manifest.sh bin/nivuus
git commit -m "test(e2e): prove uninstall leaves HOME bit-identical"
```

---

### Task 12: Exécuter les nouvelles suites en CI

**Files:**
- Modify: `.github/workflows/tests.yml`
- Modify: `.gitignore`
- Delete: `config/*.zwc`

**Interfaces:**
- Consumes: toutes les suites précédentes
- Produces: un job CI qui exécute `tests/unit/` **et** `tests/e2e/`, aujourd'hui jamais lancé pour `e2e/`.

- [ ] **Step 1: Verify the gap**

Run: `grep -c "tests/e2e" .github/workflows/tests.yml || true`
Expected: `0` — confirme que les tests e2e ne tournent jamais en CI.

- [ ] **Step 2: Remove the committed bytecode**

```bash
git rm --cached config/*.zwc
printf '\n# Bytecode ZSH compilé — jamais commité\n*.zwc\n' >> .gitignore
```

- [ ] **Step 3: Add the e2e job**

Ajouter dans `.github/workflows/tests.yml`, au même niveau que les jobs existants :

```yaml
  e2e:
    name: Installation E2E
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y zsh bats

      - name: Library unit tests
        run: bats tests/unit/test_lib_*.bats

      - name: Install / uninstall E2E
        run: bats tests/e2e/test_nivuus_cli.bats tests/e2e/test_install_sh_compat.bats

      - name: Reversibility (HOME must be bit-identical)
        run: bats tests/e2e/test_reversibility.bats
```

- [ ] **Step 4: Verify locally before pushing**

Run: `bats tests/unit/ tests/e2e/`
Expected: PASS. Vérifier ensuite qu'aucun `.zwc` n'est suivi par git :

Run: `git ls-files '*.zwc' | wc -l`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/tests.yml .gitignore
git commit -m "ci: run library and installation E2E suites, drop committed .zwc"
```

---

## Vérification finale de la phase

Une fois les 12 tâches terminées, ces commandes doivent toutes réussir :

```bash
bats tests/unit/ tests/e2e/          # toutes les suites
./bin/nivuus install --dry-run --yes # n'écrit rien, décrit tout
git ls-files '*.zwc' | wc -l         # 0
grep -rn "init_git_repo" install.sh  # aucun résultat
```

## Ce que ce plan ne livre pas

Reporté aux plans des phases suivantes, conformément au spec :

- **Phase 3** — détection WSL et macOS, préfixe Homebrew, `--minimal` complet, `chsh` sûr avec vérification de `/etc/shells`, politique `--with-deps` et installation de fzf/fzf-tab, mode `--system`.
- **Phase 4** — matrice CI multi-distributions et macOS, découpage PR/nightly/release, badges du README.
- **Phase 5** — vrai one-liner `curl | sh` avec téléchargement du tarball de release, migration des installations existantes portant un `.git` parasite, refonte de `doctor`, documentation d'installation.

`nivuus update` et `nivuus doctor` délèguent pour l'instant à l'existant (`nivuus-update`, `bin/healthcheck`) sans changement de comportement.
