# Preuve — matrice CI, quatre niveaux, badges — Plan d'implémentation (phase 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que l'installation, la désinstallation et la réversibilité de Nivuus Shell soient **prouvées en continu** sur toutes les cibles du spec, avec un découpage PR / nightly / release qui tienne dans le budget, et des badges de README qu'il soit *impossible* de laisser verts pendant que la chose testée est cassée.

**Architecture :** trois workflows aux rôles distincts, et un seul endroit qui sait installer les dépendances de test.

| Workflow | Déclencheur | Rôle | Badge |
|---|---|---|---|
| `.github/workflows/tests.yml` | PR + push master | Boucle rapide : niveaux 1, 2 (Ubuntu + macOS) et 4 local | « Tests » |
| `.github/workflows/uninstall-verified.yml` | PR + push master + nightly | Niveau 3 seul, sur Ubuntu / macOS / Alpine | **« uninstall verified »** |
| `.github/workflows/matrix.yml` | nightly + `workflow_dispatch` + `workflow_call` (release) | Matrice exhaustive : 6 conteneurs + 2 runners, niveaux 2, 3, 4 | « Matrix » |

Sous ces trois workflows, une seule brique partagée : `tests/ci/install-deps.sh` (script POSIX sh,
testable en local sous Docker) enveloppé par l'action composite `.github/actions/setup-tests`.
Aucun workflow n'installe plus zsh, bats ou git lui-même. La liste des cibles vit dans
`.github/matrix.json`, **source unique** consommée à la fois par `matrix.yml` (`fromJSON`) et par le
tableau « Plateformes testées » du README — dont la cohérence est vérifiée par un test.

**Tech Stack :** GitHub Actions (matrix + `container:` + `workflow_call` + action composite locale),
Docker (rejeu local des jobs de conteneur), bats 1.11.1 épinglé (`--count`, `--formatter tap13`,
`--filter-tags`, `--jobs`), GNU parallel, `jq`, `actionlint`, bash 3.2 / POSIX sh pour les scripts.

**Spec :** `docs/superpowers/specs/2026-08-20-installation-friction-zero-design.md`, section 4
« Tests et CI » (quatre niveaux, budget CI, badges) et section 6, phase 4 « Preuve ».

**Plans précédents (mergés) :**
- `docs/superpowers/plans/2026-08-20-installation-friction-zero.md` — phases 1 et 2 (`lib/`, manifeste, `--dry-run`, `nivuus uninstall`, empreinte `$HOME`).
- `docs/superpowers/plans/2026-08-21-installation-multiplateforme.md` — phase 3 (`lib/detect.sh` complet, `lib/deps.sh`, `--minimal`, `chsh` sûr, jobs CI macOS et Alpine).

**Sortie de phase :** toutes les cibles du spec vertes, découpage PR / nightly / release en place,
badge « uninstall verified » actif et adossé à un workflow bloquant.

---

## État des lieux mesuré (2026-08-21)

Chiffres relevés sur la machine de développement (à citer, pas à re-mesurer) :

| Suite | Tests | Durée série | Durée `--jobs 4` |
|---|---|---|---|
| `tests/unit/` | 606 | **25 s** | 30 s (*plus lent* : surcoût par fichier > gain) |
| `tests/integration/` | 195 (2 `skip`) | **29 s** | non mesuré, même profil que `unit` |
| `tests/e2e/` | 112 | **60 s** | **26 s** |
| `tests/performance/` | 10 | 2 s | ne doit **pas** être parallélisé |

Détail e2e en série : `test_nivuus_cli` 19 s, `test_reversibility` 15 s, `test_benchmark` 5 s,
`test_minimal_mode` 5 s, `test_with_deps` 5 s, `test_platform` 4 s, le reste ≤ 3 s.
Un runner GitHub est environ 2× plus lent ; les jobs `container:` ajoutent 30 à 60 s de
`pull` + installation de paquets.

Problèmes que ce plan corrige, tels qu'ils existent aujourd'hui dans `tests.yml` :

1. Le comptage `bats … | head -1 | sed 's/1\.\.//'` **relance toute la suite** pour compter, et casse
   dès que la première ligne n'est pas le plan TAP (`--formatter pretty` est le défaut hors TTY… mais
   pas partout). Le seuil `total ≥ 100` est trivialement vrai (616) : il ne protège de rien.
2. L'installation de zsh + bats est **dupliquée dans six jobs**, avec des versions de bats différentes
   selon la distribution (Ubuntu 22.04 : bats 1.2.1, sans `--formatter` ni `--count` ; Ubuntu 24.04 :
   1.10 ; Alpine : clone git sur `master`, donc non reproductible).
3. `tests/integration/` (195 tests) n'est **exécuté par aucun workflow**.
4. L'étape « Validate startup time requirement » accepte explicitement le `skip` — elle ne valide
   rien, tout en affichant « ✅ Startup time requirement met ».
5. Le job `e2e-macos` a été **écrit mais jamais exécuté** : aucun push depuis son ajout.
6. Le seul badge de CI du README pointe sur `workflows/Tests/badge.svg` — syntaxe héritée, sans
   `?branch=master`, donc il reflète le dernier run *toutes branches confondues*.

---

## Global Constraints

- **Une seule source d'installation de dépendances.** `tests/ci/install-deps.sh`. Interdit à tout
  workflow d'appeler `apt-get`, `apk`, `pacman`, `dnf` ou `brew` directement — un test le vérifie
  (Task 2).
- **bats épinglé à `v1.11.1` partout**, installé depuis le dépôt bats-core, jamais depuis le
  gestionnaire de paquets de la distribution. Les paquets distro sont trop anciens et hétérogènes ;
  les options `--count`, `--filter-tags`, `--formatter tap13` et `--jobs` sont utilisées par ce plan.
- **Scripts en POSIX sh** pour ce qui tourne dans un conteneur Alpine avant toute installation
  (`tests/ci/*.sh`) ; bash 3.2 pour `bin/*`. Mêmes interdits GNU-only que la phase 3 : pas de
  `sed -i`, `date +%s%N`, `grep -P`, `readlink -f`, `stat` mono-dialecte, `sort -V`, `cp -a`.
- **Aucun step de CI ne peut « réussir » sans preuve.** Interdits dans un workflow qui porte un
  badge : `continue-on-error: true`, `|| true` en fin de commande de test, `exit 0` inconditionnel,
  et tout step qui *interprète* la sortie d'un test déjà exécuté par bats. Si bats sort en 0, le job
  est vert ; sinon il est rouge. Rien entre les deux.
- **Constater le rouge avant d'écrire le vert, y compris pour du YAML.** Trois moyens, par ordre de
  préférence : (a) rejouer le job en local dans un vrai conteneur Docker, comme la phase 3 l'a fait
  pour Alpine ; (b) un test bats qui lit le fichier de workflow et échoue sur l'état actuel ;
  (c) `actionlint`. Un « je pousse et je verrai » n'est acceptable que là où l'environnement n'est pas
  reproductible en local (le runner macOS — Task 6).
- **Le test d'empreinte `tests/e2e/test_reversibility.bats` doit rester vert à chaque tâche.**
- **Ne jamais neutraliser un test pour faire passer un runner.** Une divergence d'empreinte sur une
  plateforme est une trace réellement laissée par l'installeur sur cette plateforme.
- **`.github/workflows/release.yml` n'appartient pas à ce plan.** Un plan de signature des releases
  est rédigé en parallèle et touche ce fichier. Voir « Points de contact » en fin de document : une
  seule tâche (Task 12) y touche, en une modification délimitée, à appliquer en dernier.

---

### Task 1: `tests/ci/install-deps.sh` — une seule façon d'installer les dépendances de test

**Files:**
- Create: `tests/ci/install-deps.sh`
- Create: `tests/e2e/test_ci_deps_script.bats`

**Interfaces:**
- Produces : `tests/ci/install-deps.sh` — installe `zsh`, `git`, `curl`, `jq`, `parallel` (best-effort),
  `procps` puis bats-core `v1.11.1` sous `$PREFIX` (défaut `/usr/local`). Idempotent. Sortie finale :
  une ligne `install-deps: <zsh --version>, <bats --version>, <git --version>`.
- Variables : `BATS_VERSION` (défaut `v1.11.1`), `PREFIX` (défaut `/usr/local`).
- Consumers : l'action composite (Task 2) et tous les workflows.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_ci_deps_script.bats
#!/usr/bin/env bats
#
# Rejoue en local, dans un vrai conteneur, ce que la CI fera de install-deps.sh.
# Marqué `docker` : exclu des runs de PR via --filter-tags (voir tests/ci/bats-run.sh).

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

# Un conteneur vierge, le dépôt monté en lecture seule, le script, puis la
# preuve qu'on peut réellement lancer des tests derrière.
run_in() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c '
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh
        bats --version | grep -q "1.11.1"
        bats --count tests/unit/test_lib_detect.bats
        command -v zsh >/dev/null
    '
}

# bats test_tags=docker
@test "install-deps works on debian:12" {
    run run_in debian:12
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on fedora:41" {
    run run_in fedora:41
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on archlinux:latest" {
    run run_in archlinux:latest
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on alpine:3.20 (musl, no GNU coreutils)" {
    run run_in alpine:3.20
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps is idempotent (second run is a no-op that still succeeds)" {
    run docker run --rm -v "$ROOT:/src:ro" debian:12 sh -c '
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/install-deps.sh
    '
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_ci_deps_script.bats`
Expected: FAIL — `./tests/ci/install-deps.sh: not found` sur les cinq tests.

- [ ] **Step 3: Write minimal implementation**

```sh
# tests/ci/install-deps.sh
#!/bin/sh
# =============================================================================
# Dépendances de la suite de tests Nivuus, pour toutes les cibles de la matrice.
# =============================================================================
# POSIX sh : ce script tourne dans un conteneur Alpine *avant* que bash n'existe.
# C'est le SEUL endroit du dépôt qui appelle un gestionnaire de paquets pour la
# CI ; les workflows passent par .github/actions/setup-tests.
set -eu

BATS_VERSION="${BATS_VERSION:-v1.11.1}"
PREFIX="${PREFIX:-/usr/local}"

# `sudo` seulement si nécessaire : dans un conteneur on est root et sudo n'existe pas.
SUDO=''
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO='sudo'
fi

# Best-effort : GNU parallel n'est pas dans tous les dépôts par défaut, et son
# absence ne fait que désactiver `bats --jobs` (voir tests/ci/bats-run.sh).
_optional() { "$@" >/dev/null 2>&1 || true; }

install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
            zsh git curl ca-certificates jq procps
        _optional env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq parallel
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache bash zsh git curl ncurses jq procps
        _optional $SUDO apk add --no-cache parallel
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm --needed zsh git curl jq procps-ng
        _optional $SUDO pacman -S --noconfirm --needed parallel
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf -y --setopt=install_weak_deps=False install zsh git curl jq procps-ng
        _optional $SUDO dnf -y install parallel
    elif command -v brew >/dev/null 2>&1; then
        # macOS fournit déjà zsh, git, curl. jq est présent sur les runners GitHub.
        _optional brew install --quiet parallel
        command -v jq >/dev/null 2>&1 || brew install --quiet jq
    else
        echo "install-deps: aucun gestionnaire de paquets connu" >&2
        exit 1
    fi
}

# bats depuis le dépôt amont, à version épinglée : les paquets distro vont de
# 1.2.1 (Ubuntu 22.04) à 1.10, et n'ont ni --count, ni --filter-tags, ni --formatter.
install_bats() {
    if command -v bats >/dev/null 2>&1 &&
       bats --version 2>/dev/null | grep -q "${BATS_VERSION#v}"; then
        echo "install-deps: bats ${BATS_VERSION} déjà présent"
        return 0
    fi
    tmp="$(mktemp -d)"
    git clone --quiet --depth 1 --branch "$BATS_VERSION" \
        https://github.com/bats-core/bats-core.git "$tmp/bats-core"
    $SUDO "$tmp/bats-core/install.sh" "$PREFIX" >/dev/null
    rm -rf "$tmp"
}

install_packages
install_bats

echo "install-deps: $(zsh --version), $(bats --version), $(git --version)"
```

```bash
chmod +x tests/ci/install-deps.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_ci_deps_script.bats`
Expected: PASS — 5 tests. Compter 3 à 6 minutes (téléchargement des quatre images).
Si `archlinux:latest` échoue sur une base de données de paquets périmée, c'est `pacman -Sy` qui doit
rester `-Sy` (et non `-S`) : ne pas passer à `-Syu`, qui reconstruit toute l'image.

- [ ] **Step 5: Commit**

```bash
git add tests/ci/install-deps.sh tests/e2e/test_ci_deps_script.bats
git commit -m "test(ci): single source for test dependencies, pinned bats"
```

---

### Task 2: Action composite `setup-tests` et interdiction de l'installation ad hoc

**Files:**
- Create: `.github/actions/setup-tests/action.yml`
- Create: `tests/unit/test_ci_workflows.bats`
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Produces : action composite locale `./.github/actions/setup-tests`, entrée optionnelle
  `bats-version` (défaut `v1.11.1`). Elle appelle `tests/ci/install-deps.sh` puis exporte
  `NIVUUS_SHELL_DIR=$GITHUB_WORKSPACE` dans `$GITHUB_ENV`.
- Produces : `tests/unit/test_ci_workflows.bats` — lint maison des workflows, exécuté avec les
  tests unitaires, donc sur chaque PR.

Contrainte d'ordonnancement à connaître : l'action est **locale**, donc `actions/checkout` doit
passer *avant* elle. Dans les conteneurs sans `git` (Arch, Fedora), `actions/checkout@v4` bascule
automatiquement sur le téléchargement REST — c'est supporté et suffisant. Si un jour une image
refuse ce chemin, l'échappatoire est une ligne inline `run:` d'installation de `git` avant le
checkout, et rien d'autre : l'exception se documente dans le workflow, elle ne se généralise pas.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_ci_workflows.bats
#!/usr/bin/env bats
#
# Lint maison des workflows. Objet : empêcher la CI de redevenir artisanale.
# Ces règles sont des invariants du plan de phase 4, pas des préférences.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    WF="$ROOT/.github/workflows"
}

@test "no workflow installs packages itself — everything goes through install-deps.sh" {
    # On tolère les lignes de commentaire et le bootstrap documenté d'un
    # conteneur sans git (voir Task 2), marqué par le mot-clé BOOTSTRAP.
    offenders=""
    for f in "$WF"/*.yml; do
        while IFS= read -r line; do
            case "$line" in
                *BOOTSTRAP*) continue ;;
                \#*|*"#"[[:space:]]*) ;;
            esac
            case "$line" in
                *apt-get*install*|*apk\ add*|*pacman\ -S*|*dnf*install*|*brew\ install*)
                    offenders="$offenders$f: $line"$'\n' ;;
            esac
        done < "$f"
    done
    [ -z "$offenders" ] || { echo "$offenders"; false; }
}

@test "no workflow clones bats-core itself" {
    run grep -rn "bats-core" "$WF"
    [ "$status" -ne 0 ]
}

@test "the composite action exists and calls install-deps.sh" {
    [ -f "$ROOT/.github/actions/setup-tests/action.yml" ]
    grep -q "tests/ci/install-deps.sh" "$ROOT/.github/actions/setup-tests/action.yml"
}

@test "every job that runs bats uses the composite action" {
    # Un job qui lance bats sans setup-tests utiliserait un bats non épinglé.
    missing=""
    for f in "$WF"/*.yml; do
        grep -q "bats " "$f" || continue
        grep -q "./.github/actions/setup-tests" "$f" || missing="$missing $f"
    done
    [ -z "$missing" ] || { echo "sans setup-tests:$missing"; false; }
}

@test "no workflow parses a bats plan line with sed" {
    run grep -rn "sed 's/1\\\\\\.\\\\\\.//'" "$WF"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_workflows.bats`
Expected: FAIL — les cinq tests échouent : `tests.yml` installe zsh/bats à la main dans six jobs,
clone `bats-core` dans le job Alpine, l'action composite n'existe pas, et le comptage `sed` est là.

- [ ] **Step 3: Write minimal implementation**

```yaml
# .github/actions/setup-tests/action.yml
name: Setup Nivuus test environment
description: >
  Installe zsh, git, curl, jq, GNU parallel et bats (version épinglée) sur
  n'importe quelle cible de la matrice, puis exporte NIVUUS_SHELL_DIR.
  Toute la logique vit dans tests/ci/install-deps.sh, rejouable en local
  sous Docker — cette action n'est qu'un point d'entrée pour Actions.

inputs:
  bats-version:
    description: Tag bats-core à installer
    required: false
    default: v1.11.1

runs:
  using: composite
  steps:
    - name: Install test dependencies
      shell: sh
      env:
        BATS_VERSION: ${{ inputs.bats-version }}
      run: ./tests/ci/install-deps.sh

    - name: Export NIVUUS_SHELL_DIR
      shell: sh
      run: echo "NIVUUS_SHELL_DIR=$GITHUB_WORKSPACE" >> "$GITHUB_ENV"
```

Puis remplacer, dans **chaque** job de `.github/workflows/tests.yml`, le bloc d'installation
(« Install ZSH » + « Install bats » + « Setup test environment », ou son équivalent `brew`/`apk`)
par les deux steps :

```yaml
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup test environment
        uses: ./.github/actions/setup-tests
```

Le job `e2e-alpine` perd son `apk add` inline et son clone de bats-core. Le job `lint` garde son
`zsh -n`, mais obtient zsh par l'action comme les autres.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_ci_workflows.bats`
Expected: PASS — 5 tests. (Le test « no sed plan parsing » passe déjà si Task 3 est faite avant ;
sinon retirer temporairement les steps de comptage — ils sont réécrits en Task 3.)

Vérifier aussi que le chemin conteneur tient toujours, en rejouant Alpine localement :

```bash
docker run --rm -v "$PWD:/src:ro" alpine:3.20 sh -c '
  cp -r /src /work && cd /work && ./tests/ci/install-deps.sh &&
  bats tests/e2e/test_reversibility.bats'
```

- [ ] **Step 5: Commit**

```bash
git add .github/actions/setup-tests/action.yml .github/workflows/tests.yml tests/unit/test_ci_workflows.bats
git commit -m "ci: factor test setup into a composite action"
```

---

### Task 3: Comptage fiable et garde-fou anti-régression (`bin/test-count`)

**Files:**
- Create: `bin/test-count`
- Create: `tests/baseline-counts.tsv`
- Create: `tests/unit/test_test_count.bats`
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Produces : `bin/test-count` :
  - sans argument — imprime `<suite>\t<n>` par suite, plus `total\t<n>` ;
  - `--check` — compare à la baseline, **échoue si un compte a baissé**, réussit s'il est égal ou
    supérieur, et imprime la commande de mise à jour quand il est supérieur ;
  - `--update` — réécrit la baseline.
- Le comptage utilise `bats --count`, qui **n'exécute aucun test** : c'est instantané et ce n'est
  pas une seconde exécution de la suite (contrairement au `sed` actuel, qui relançait tout).
- Variables d'override, pour que le test puisse travailler sur des fixtures :
  `NIVUUS_TESTS_DIR`, `NIVUUS_COUNT_BASELINE`, `NIVUUS_COUNT_SUITES`.

Arbitrage inscrit ici : le seuil absolu `≥ 100` est remplacé par un **cliquet**. Un seuil absolu
devient faux dès que la suite grossit ; un cliquet reste vrai pour toujours et attrape le cas réel —
quelqu'un supprime ou commente des tests pour faire passer la CI.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_test_count.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    COUNT="$ROOT/bin/test-count"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/tests/alpha" "$TMP/tests/beta"
    printf '#!/usr/bin/env bats\n@test "a" { true; }\n@test "b" { true; }\n' > "$TMP/tests/alpha/x.bats"
    printf '#!/usr/bin/env bats\n@test "c" { true; }\n' > "$TMP/tests/beta/y.bats"
    export NIVUUS_TESTS_DIR="$TMP/tests"
    export NIVUUS_COUNT_BASELINE="$TMP/baseline.tsv"
    export NIVUUS_COUNT_SUITES="alpha beta"
}

teardown() { rm -rf "$TMP"; }

@test "counts tests from the bats plan, not from grep" {
    run "$COUNT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha	2"* ]]
    [[ "$output" == *"beta	1"* ]]
    [[ "$output" == *"total	3"* ]]
}

@test "counting does not execute the tests" {
    printf '#!/usr/bin/env bats\n@test "side effect" { touch "%s/ran"; }\n' "$TMP" \
        > "$TMP/tests/alpha/z.bats"
    run "$COUNT"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/ran" ]
}

@test "--update writes the baseline" {
    run "$COUNT" --update
    [ "$status" -eq 0 ]
    grep -q '^alpha	2$' "$NIVUUS_COUNT_BASELINE"
    grep -q '^beta	1$'  "$NIVUUS_COUNT_BASELINE"
}

@test "--check passes when counts are unchanged" {
    "$COUNT" --update
    run "$COUNT" --check
    [ "$status" -eq 0 ]
}

@test "--check fails when a suite loses tests" {
    "$COUNT" --update
    rm "$TMP/tests/alpha/x.bats"
    run "$COUNT" --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"2"* ]]
}

@test "--check passes and tells how to update when a suite gains tests" {
    "$COUNT" --update
    printf '#!/usr/bin/env bats\n@test "new" { true; }\n' > "$TMP/tests/beta/new.bats"
    run "$COUNT" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-count --update"* ]]
}

@test "--check fails loudly when a whole suite disappears" {
    "$COUNT" --update
    rm -rf "$TMP/tests/beta"
    run "$COUNT" --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"beta"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_test_count.bats`
Expected: FAIL — `bin/test-count: No such file or directory` sur les sept tests.

- [ ] **Step 3: Write minimal implementation**

```bash
# bin/test-count
#!/usr/bin/env bash
# =============================================================================
# Compte les tests par suite et interdit toute régression du nombre de tests.
# =============================================================================
# Le compte vient de `bats --count`, qui lit les fichiers sans les exécuter.
# La garde est un cliquet, pas un seuil : un seuil absolu périme, un cliquet
# attrape le vrai risque — des tests supprimés pour faire passer la CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${NIVUUS_TESTS_DIR:-$ROOT/tests}"
BASELINE="${NIVUUS_COUNT_BASELINE:-$ROOT/tests/baseline-counts.tsv}"
SUITES="${NIVUUS_COUNT_SUITES:-unit integration e2e performance}"

count_suite() {   # count_suite <suite> -> nombre de tests, 0 si la suite a disparu
    local dir="$TESTS_DIR/$1"
    [ -d "$dir" ] || { printf '0\n'; return 0; }
    local files
    files="$(find "$dir" -name '*.bats' -type f | LC_ALL=C sort)"
    [ -n "$files" ] || { printf '0\n'; return 0; }
    # shellcheck disable=SC2086
    bats --count $files
}

emit_counts() {
    local total=0 n suite
    for suite in $SUITES; do
        n="$(count_suite "$suite")"
        printf '%s\t%s\n' "$suite" "$n"
        total=$((total + n))
    done
    printf 'total\t%s\n' "$total"
}

baseline_for() {   # baseline_for <suite> -> compte enregistré, 0 si absent
    [ -f "$BASELINE" ] || { printf '0\n'; return 0; }
    awk -F'\t' -v s="$1" '$1 == s { print $2; found = 1 } END { if (!found) print 0 }' "$BASELINE"
}

case "${1:-}" in
    --update)
        emit_counts | grep -v '^total	' > "$BASELINE"
        echo "baseline mise à jour : $BASELINE"
        cat "$BASELINE"
        ;;
    --check)
        status=0
        grew=0
        for suite in $SUITES; do
            now="$(count_suite "$suite")"
            was="$(baseline_for "$suite")"
            if [ "$now" -lt "$was" ]; then
                echo "RÉGRESSION: $suite est passé de $was à $now tests" >&2
                status=1
            elif [ "$now" -gt "$was" ]; then
                echo "$suite: $was -> $now tests"
                grew=1
            else
                echo "$suite: $now tests"
            fi
        done
        if [ "$grew" -eq 1 ] && [ "$status" -eq 0 ]; then
            echo "La suite a grossi. Fige le nouveau plancher : ./bin/test-count --update"
        fi
        exit "$status"
        ;;
    ''|--print)
        emit_counts
        ;;
    *)
        echo "usage: test-count [--print|--check|--update]" >&2
        exit 2
        ;;
esac
```

```bash
chmod +x bin/test-count
./bin/test-count --update      # fige la baseline réelle : unit 606, integration 195, e2e 112+, performance 10
```

Dans `.github/workflows/tests.yml`, supprimer les steps « Test count validation » et le comptage
dans « Generate test summary », et les remplacer par :

```yaml
      - name: Test count must never regress
        run: ./bin/test-count --check

      - name: Test summary
        if: always()
        run: |
          {
            echo "## Tests"
            echo
            echo '```'
            ./bin/test-count
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
```

Note : `if: always()` est ici sur un step de **résumé** qui n'exécute aucun test et dont l'échec
n'est pas absorbé — c'est le seul usage autorisé par les contraintes globales.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_test_count.bats && ./bin/test-count --check`
Expected: PASS — 7 tests, puis `unit: 606`, `integration: 195`, `e2e: …`, `performance: 10`, sortie 0.

- [ ] **Step 5: Commit**

```bash
git add bin/test-count tests/baseline-counts.tsv tests/unit/test_test_count.bats .github/workflows/tests.yml
git commit -m "test(ci): replace the fragile test count with a no-regression ratchet"
```

---

### Task 4: Le test de performance devient réel en CI (ou disparaît) — il ne peut plus se taire

**Files:**
- Modify: `tests/performance/measure_startup.sh`
- Modify: `tests/performance/test_startup.bats`
- Create: `tests/unit/test_perf_is_enforced.bats`
- Modify: `.github/workflows/tests.yml`

**Décision, et pourquoi.** Le `skip` en CI se justifiait par « bats ajoute 400-500 ms de surcoût ».
C'est faux : `measure_startup.sh` mesure *à l'intérieur* de zsh, entre deux lectures de
`$EPOCHREALTIME` encadrant le `source .zshrc`. Ni bats, ni le fork de zsh, ni le runner n'entrent
dans le nombre. Mesure locale : **25 ms** pour un budget de 300. Il n'y a donc aucune raison de sauter
le test — et une bonne raison de ne pas le faire : c'est la seule vérification automatique du chiffre
que le README affiche.

Donc : **on rend le test fiable en CI**, et on supprime l'étape « Validate startup time requirement »,
qui ne faisait que relancer bats pour interpréter sa sortie et déclarer « ✅ » même sur un `skip`.
Deux corrections rendent la mesure robuste au bruit d'un runner partagé :

1. **médiane** de 10 mesures au lieu de la moyenne (une seule mesure aberrante due à un voisin bruyant
   ruine une moyenne, pas une médiane) ;
2. budget **paramétrable** par `NIVUUS_STARTUP_BUDGET_MS` (défaut 300), pour que le README, le test
   et la CI citent tous le même nombre — vérifié par le test de badges (Task 11).

Le reste de `tests/performance/` utilise `date +%s%N` (GNU-only) et `ps -o rss=` : cette suite reste
**Ubuntu seulement**. Seul le test critique est marqué `# bats test_tags=portable` et tourne partout.

**Interfaces:**
- `measure_startup.sh` — imprime la **médiane** en millisecondes ; `NIVUUS_STARTUP_RUNS` (défaut 10).
- `test_startup.bats` — le test `CRITICAL` ne saute plus jamais ; seuil `NIVUUS_STARTUP_BUDGET_MS`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_perf_is_enforced.bats
#!/usr/bin/env bats
#
# Garde-fou : le budget de démarrage doit être VRAIMENT vérifié en CI.
# Un test de performance qui se saute silencieusement est pire que pas de test :
# il produit un vert qui ne prouve rien.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    export NIVUUS_SHELL_DIR="$ROOT"
}

@test "the startup test does not skip itself under CI" {
    run env CI=true GITHUB_ACTIONS=true \
        bats --formatter tap13 --filter-tags portable "$ROOT/tests/performance/test_startup.bats"
    [ "$status" -eq 0 ]
    [[ "$output" != *"# skip"* ]]
    [[ "$output" != *"# SKIP"* ]]
}

@test "no test file skips itself merely because CI is set" {
    # Le motif exact qu'on vient de retirer ; il ne doit pas revenir ailleurs.
    run grep -rn 'skip "Skipped in CI' "$ROOT/tests"
    [ "$status" -ne 0 ]
}

@test "measure_startup reports a median over several runs" {
    grep -q 'median' "$ROOT/tests/performance/measure_startup.sh"
    run env NIVUUS_STARTUP_RUNS=3 "$ROOT/tests/performance/measure_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "the enforced budget is 300 ms and comes from one variable" {
    grep -q 'NIVUUS_STARTUP_BUDGET_MS' "$ROOT/tests/performance/test_startup.bats"
    run env NIVUUS_STARTUP_BUDGET_MS=1 bats --filter-tags portable "$ROOT/tests/performance/test_startup.bats"
    [ "$status" -ne 0 ]   # un budget absurde DOIT faire échouer : la garde mord
}

@test "no workflow interprets bats output to decide if performance passed" {
    run grep -rn "Validate startup time requirement" "$ROOT/.github/workflows"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_perf_is_enforced.bats`
Expected: FAIL — 5/5. Le test se saute sous `CI=true`, `measure_startup.sh` calcule une moyenne,
`NIVUUS_STARTUP_BUDGET_MS` n'existe pas, et `tests.yml` (comme `release.yml`) contient encore
« Validate startup time requirement ».

- [ ] **Step 3: Write minimal implementation**

Dans `tests/performance/measure_startup.sh`, remplacer l'accumulation et la moyenne par une collecte
puis une **médiane** :

```bash
runs="${NIVUUS_STARTUP_RUNS:-10}"
samples=""

for i in $(seq 1 "$runs"); do
    # ... (bloc de mesure existant, inchangé : EPOCHREALTIME autour du source)
    samples="$samples$result
"
done

# Médiane, pas moyenne : sur un runner partagé une seule mesure aberrante
# ruine une moyenne. `sort -n` suffit, aucune option GNU-only ici.
median_us=$(printf '%s' "$samples" | grep -v '^$' | sort -n | awk '
    { v[NR] = $1 }
    END { print (NR % 2) ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1]) / 2) }')

echo "$((median_us / 1000))"
```

Dans `tests/performance/test_startup.bats`, remplacer le test critique :

```bash
# bats test_tags=portable
@test "CRITICAL: Full shell startup time is under the budget (median of 10 runs)" {
    # La mesure est prise DANS zsh, entre deux $EPOCHREALTIME autour du
    # `source .zshrc` : ni bats, ni le fork, ni le runner n'entrent dans le
    # nombre. C'est pourquoi ce test ne se saute plus en CI.
    budget_ms="${NIVUUS_STARTUP_BUDGET_MS:-300}"
    median_ms=$("$BATS_TEST_DIRNAME/measure_startup.sh")

    echo "# Startup (median): ${median_ms}ms — budget: ${budget_ms}ms" >&3

    [ "$median_ms" -lt "$budget_ms" ]
}
```

Dans `.github/workflows/tests.yml`, supprimer entièrement le step « Validate startup time
requirement » et laisser le seul step qui exécute réellement la suite :

```yaml
      - name: Performance (startup budget is enforced, not observed)
        run: bats tests/performance/
```

Le même step existe dans `release.yml` : il est traité en Task 12 (point de contact).

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_perf_is_enforced.bats && bats tests/performance/`
Expected: PASS — 5 + 10 tests, avec une ligne `# Startup (median): ~25ms — budget: 300ms`.

- [ ] **Step 5: Commit**

```bash
git add tests/performance/measure_startup.sh tests/performance/test_startup.bats \
        tests/unit/test_perf_is_enforced.bats .github/workflows/tests.yml
git commit -m "test(perf): enforce the 300ms budget in CI instead of skipping it"
```

---

### Task 5: `tests/ci/bats-run.sh` — parallélisation là où elle paie, et nulle part ailleurs

**Files:**
- Create: `tests/ci/bats-run.sh`
- Create: `tests/unit/test_ci_bats_run.bats`
- Modify: `.github/workflows/tests.yml`

**Mesures qui dictent la décision** (relevées sur la machine de développement) :

| Suite | Série | `--jobs 4` | Décision |
|---|---|---|---|
| `unit` (606) | 25 s | **30 s** | série — la parallélisation coûte plus qu'elle ne rapporte |
| `integration` (195) | 29 s | même profil | série |
| `e2e` (112) | 60 s | **26 s** | `--jobs 4` |
| `performance` (10) | 2 s | — | série, obligatoirement : mesurer sous charge n'a aucun sens |

`--jobs` exige GNU parallel. Le script le détecte et retombe en série sinon : un runner sans parallel
doit rester vert, juste plus lent.

**Interfaces:**
- `tests/ci/bats-run.sh <suite-dir>… ` — lance bats avec `--formatter tap13`, `--jobs` si pertinent,
  et exclut les tests marqués `docker` sauf si `NIVUUS_CI_DOCKER=1`.
- Variables : `NIVUUS_BATS_JOBS` (défaut 4), `NIVUUS_CI_DOCKER` (défaut vide).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_ci_bats_run.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    RUN="$ROOT/tests/ci/bats-run.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/suite"
    printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$TMP/suite/a.bats"
    printf '#!/usr/bin/env bats\n# bats test_tags=docker\n@test "dockery" { false; }\n' \
        > "$TMP/suite/b.bats"
}

teardown() { rm -rf "$TMP"; }

@test "docker-tagged tests are excluded by default" {
    run "$RUN" "$TMP/suite"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dockery"* ]]
}

@test "NIVUUS_CI_DOCKER=1 includes them (and they can then fail)" {
    run env NIVUUS_CI_DOCKER=1 "$RUN" "$TMP/suite"
    [ "$status" -ne 0 ]
    [[ "$output" == *"dockery"* ]]
}

@test "output is TAP13 so counts can be read from the plan line" {
    run "$RUN" "$TMP/suite"
    [[ "${lines[0]}" == "TAP version 13" ]]
    [[ "${lines[1]}" =~ ^1\.\.[0-9]+$ ]]
}

@test "falls back to serial when GNU parallel is missing" {
    mkdir -p "$TMP/bin"
    for c in bash sh env cat cp mv rm mkdir find awk sed grep printf head tail wc sort cut \
             mktemp chmod ls date bats zsh dirname basename tr id; do
        p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$TMP/bin/$c"
    done
    run env PATH="$TMP/bin" "$RUN" "$TMP/suite"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_bats_run.bats`
Expected: FAIL — `tests/ci/bats-run.sh: No such file or directory` (4 tests).

- [ ] **Step 3: Write minimal implementation**

```sh
# tests/ci/bats-run.sh
#!/bin/sh
# =============================================================================
# Lance une suite bats comme la CI le fait.
# =============================================================================
# - TAP13, pour que le plan (`1..N`) soit toujours lisible en tête de sortie.
# - --jobs seulement si GNU parallel est là ET si la suite y gagne (mesuré :
#   e2e 60s -> 26s ; unit 25s -> 30s, donc unit reste en série).
# - Les tests marqués `docker` sont exclus par défaut : ils tirent des images
#   entières et n'ont leur place que dans la matrice nightly.
set -eu

JOBS="${NIVUUS_BATS_JOBS:-4}"
ARGS="--formatter tap13"

if [ "${NIVUUS_CI_DOCKER:-}" != "1" ]; then
    ARGS="$ARGS --filter-tags !docker"
fi

# La parallélisation ne s'applique qu'aux suites où elle a été mesurée gagnante.
wants_jobs=no
for d in "$@"; do
    case "$d" in
        *e2e*) wants_jobs=yes ;;
    esac
done

if [ "$wants_jobs" = yes ] && command -v parallel >/dev/null 2>&1; then
    ARGS="$ARGS --jobs $JOBS"
fi

# shellcheck disable=SC2086
exec bats $ARGS "$@"
```

```bash
chmod +x tests/ci/bats-run.sh
```

Dans `tests.yml`, remplacer les appels `bats tests/<suite>/` par `./tests/ci/bats-run.sh tests/<suite>/`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_ci_bats_run.bats && time ./tests/ci/bats-run.sh tests/e2e/`
Expected: PASS — 4 tests ; la suite e2e sort en ~26 s au lieu de ~60 s, avec le même nombre de `ok`.

- [ ] **Step 5: Commit**

```bash
git add tests/ci/bats-run.sh tests/unit/test_ci_bats_run.bats .github/workflows/tests.yml
git commit -m "test(ci): parallelise the e2e suite, keep the rest serial"
```

---

### Task 6: `tests.yml` devient le workflow de PR — rapide, complet sur l'essentiel, et enfin exécuté sur macOS

**Files:**
- Modify: `.github/workflows/tests.yml`

**Ce que fait cette tâche.** `tests.yml` cesse d'être « tout ce qu'on a su écrire » pour devenir la
**boucle rapide** décrite par le budget CI du spec : unitaires + intégration + lint + installation /
désinstallation sur Ubuntu et macOS. Les conteneurs Alpine/Debian/Arch/Fedora **quittent ce fichier**
pour `matrix.yml` (Task 8) — sauf Alpine, qui reste ici : c'est la seule cible sans coreutils GNU, et
c'est là que se cassent les régressions de portabilité, pour 90 secondes de conteneur.

**C'est aussi la première exécution réelle du job macOS.** Il a été écrit en phase 3 et jamais lancé.
Il faut donc pousser la branche et regarder — et prévoir que ce soit rouge.

Budget visé, en temps mur : ~5 min. Facturation : le job macOS est facturé ×10, il reste donc
volontairement étroit (pas de `tests/integration/`, pas de `tests/performance/`).

- [ ] **Step 1: Write the failing test**

Deux façons de constater le rouge, dans cet ordre.

(a) En local, `actionlint` sur le fichier réécrit — il attrape les fautes de syntaxe, les
`needs:` orphelins et les expressions invalides sans rien pousser :

```bash
# Installation ponctuelle (binaire statique, rien à laisser dans le dépôt) :
bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
./actionlint .github/workflows/*.yml
```

(b) La partie non reproductible en local — le runner macOS — se constate en poussant :

```bash
git push -u origin "$(git branch --show-current)"
gh run watch --exit-status
```

Expected: FAIL. Sur macOS, s'attendre notamment à : `stat` BSD (déjà géré par
`tests/helpers/fingerprint.bash`, mais vérifier les nouveaux chemins), `sed -i` sans argument de
suffixe, `date +%s%N` qui renvoie littéralement `1755...N`, `sha256sum` absent (`shasum -a 256`),
`find -printf` absent, `readlink -f` absent, `mktemp -d` sans gabarit, `/etc/shells` au contenu
différent, `zsh` 5.9 système vs `zsh` Homebrew, `$TMPDIR` en `/var/folders/...` (chemin long,
avec un lien symbolique `/var -> /private/var` qui peut faire diverger une empreinte), et surtout un
**système de fichiers insensible à la casse**.

- [ ] **Step 2: Run test to verify it fails**

`gh run watch --exit-status` sort non nul, ou `actionlint` signale une erreur. Noter précisément
chaque échec macOS avant de corriger : ce sont les vraies découvertes de cette tâche.

- [ ] **Step 3: Write minimal implementation**

D'abord corriger les échecs constatés — dans `lib/`, `bin/nivuus` ou les helpers de test selon la
cause, en respectant les interdits GNU-only des contraintes globales. **Ne jamais** désactiver un
test pour verdir macOS.

Ensuite, la forme finale du fichier :

```yaml
name: Tests

on:
  push:
    branches: [ master, main, develop ]
  pull_request:
    branches: [ master, main, develop ]

concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  # Niveau 1 (unitaire) + intégration + niveau 4 local. ~2 min.
  unit:
    name: Unit + integration
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests

      - name: Smoke
        run: ./tests/ci/bats-run.sh tests/unit/test_smoke.bats

      - name: Unit
        run: ./tests/ci/bats-run.sh tests/unit/

      - name: Integration
        run: ./tests/ci/bats-run.sh tests/integration/

      - name: Performance (budget enforced)
        run: ./tests/ci/bats-run.sh tests/performance/

      - name: Test count must never regress
        run: ./bin/test-count --check

      - name: Test summary
        if: always()
        run: |
          {
            echo "## Tests"
            echo
            echo '```'
            ./bin/test-count
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

  # Niveau 2 + 4 sur la plateforme de référence. ~2 min.
  e2e:
    name: Installation E2E (Ubuntu)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: End-to-end
        run: ./tests/ci/bats-run.sh tests/e2e/

  # Niveau 2 sur macOS : étroit, car facturé x10.
  e2e-macos:
    name: Installation E2E (macOS)
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: Library unit tests
        run: ./tests/ci/bats-run.sh tests/unit/test_lib_*.bats tests/unit/test_helpers_portable.bats
      - name: Install / uninstall
        run: |
          ./tests/ci/bats-run.sh \
            tests/e2e/test_nivuus_cli.bats \
            tests/e2e/test_install_sh_compat.bats \
            tests/e2e/test_minimal_mode.bats

  # Alpine reste sur la boucle rapide : seule cible sans coreutils GNU,
  # c'est là que les régressions de portabilité se voient en premier.
  e2e-alpine:
    name: Installation E2E (Alpine / musl)
    runs-on: ubuntu-latest
    container:
      image: alpine:3.20
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: Library unit tests
        run: ./tests/ci/bats-run.sh tests/unit/test_lib_*.bats tests/unit/test_helpers_portable.bats
      - name: Install / uninstall
        run: ./tests/ci/bats-run.sh tests/e2e/test_nivuus_cli.bats tests/e2e/test_minimal_mode.bats

  lint:
    name: Syntax validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests

      - name: ZSH syntax
        run: |
          zsh -n .zshrc
          for file in config/*.zsh themes/*.zsh; do
            zsh -n "$file"
          done

      - name: Workflow syntax
        uses: raven-actions/actionlint@v2
```

Le job `coverage` disparaît : il relançait chaque fichier de test pour en compter les cas, c'est-à-dire
exactement ce que `bin/test-count` fait désormais sans rien exécuter, et son artefact n'était consulté
par personne.

`actions/checkout` avant l'action composite dans le job Alpine : le conteneur n'a pas `git`, le
checkout bascule alors sur le téléchargement REST, ce qui est supporté. Si ce chemin échoue un jour,
l'échappatoire documentée est une seule ligne inline marquée `BOOTSTRAP` (le lint de Task 2 la tolère).

- [ ] **Step 4: Run test to verify it passes**

```bash
./actionlint .github/workflows/*.yml
git push && gh run watch --exit-status
```
Expected: PASS — `unit`, `e2e`, `e2e-macos`, `e2e-alpine`, `lint` verts. Relever les durées réelles
dans le résumé du run et les comparer au budget : cible ≤ 5 min de temps mur.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/tests.yml lib bin tests
git commit -m "ci: turn tests.yml into the fast PR loop, first real macOS run"
```

---

### Task 7: `.github/matrix.json` — la liste des cibles devient une donnée, pas une duplication

**Files:**
- Create: `.github/matrix.json`
- Create: `tests/unit/test_ci_matrix_data.bats`

**Interfaces:**
- Produces : `.github/matrix.json`, source unique consommée par `matrix.yml` (Task 8, via `fromJSON`)
  et par le tableau « Plateformes testées » du README (Task 11).
- Schéma : `containers[]` (`id`, `image`, `label`) et `runners[]` (`id`, `runs-on`, `label`).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_ci_matrix_data.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    MATRIX="$ROOT/.github/matrix.json"
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
}

@test "matrix.json is valid JSON" {
    run jq empty "$MATRIX"
    [ "$status" -eq 0 ]
}

@test "every container target has id, image and label" {
    run jq -e 'all(.containers[]; has("id") and has("image") and has("label"))' "$MATRIX"
    [ "$status" -eq 0 ]
}

@test "the spec's container targets are all present" {
    for image in ubuntu:22.04 ubuntu:24.04 debian:12 archlinux:latest fedora:41 alpine:3.20; do
        run jq -e --arg i "$image" 'any(.containers[]; .image == $i)' "$MATRIX"
        [ "$status" -eq 0 ] || { echo "cible manquante: $image"; false; }
    done
}

@test "the spec's runner targets are all present" {
    for r in ubuntu-latest macos-latest; do
        run jq -e --arg r "$r" 'any(.runners[]; .["runs-on"] == $r)' "$MATRIX"
        [ "$status" -eq 0 ] || { echo "runner manquant: $r"; false; }
    done
}

@test "ids are unique and usable as job names" {
    run jq -e '[.containers[].id] | (length == (unique | length))' "$MATRIX"
    [ "$status" -eq 0 ]
    run jq -e 'all(.containers[].id; test("^[a-z0-9-]+$"))' "$MATRIX"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_matrix_data.bats`
Expected: FAIL — `jq: error: Could not open .github/matrix.json` (5 tests).

- [ ] **Step 3: Write minimal implementation**

```json
{
  "_comment": "Source unique des cibles CI. Consommée par .github/workflows/matrix.yml (fromJSON) et par le tableau 'Plateformes testées' du README, dont la cohérence est vérifiée par tests/unit/test_readme_badges.bats.",
  "containers": [
    { "id": "ubuntu-2204", "image": "ubuntu:22.04",     "label": "Ubuntu 22.04" },
    { "id": "ubuntu-2404", "image": "ubuntu:24.04",     "label": "Ubuntu 24.04" },
    { "id": "debian-12",   "image": "debian:12",        "label": "Debian 12" },
    { "id": "arch",        "image": "archlinux:latest", "label": "Arch Linux" },
    { "id": "fedora-41",   "image": "fedora:41",        "label": "Fedora 41" },
    { "id": "alpine-320",  "image": "alpine:3.20",      "label": "Alpine 3.20 (musl)" }
  ],
  "runners": [
    { "id": "ubuntu-runner", "runs-on": "ubuntu-latest", "label": "Ubuntu (GitHub runner)" },
    { "id": "macos",         "runs-on": "macos-latest",  "label": "macOS 14 (arm64)" }
  ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_ci_matrix_data.bats`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add .github/matrix.json tests/unit/test_ci_matrix_data.bats
git commit -m "ci: declare the test matrix as data"
```

---

### Task 8: `matrix.yml` — la matrice exhaustive, nightly + release, jamais sur PR

**Files:**
- Create: `.github/workflows/matrix.yml`
- Create: `tests/ci/run-target.sh`
- Modify: `tests/unit/test_ci_workflows.bats`

**Découpage par déclencheur** (application directe du budget CI du spec) :

| Déclencheur | Ce qui tourne | Temps mur visé |
|---|---|---|
| `pull_request` | `tests.yml` uniquement (Task 6) | ~5 min |
| `push: master` | `tests.yml` + `uninstall-verified.yml` | ~7 min |
| `schedule` (nightly 03:17 UTC) | `matrix.yml` complet : 6 conteneurs + 2 runners, niveaux 2, 3, 4, tests marqués `docker` inclus | ~25 min (jobs parallèles) |
| `workflow_dispatch` | idem nightly, à la demande | — |
| `workflow_call` (depuis `release.yml`) | idem nightly, **bloquant** | ~25 min |

La matrice ne tourne **jamais** sur PR : six `pull` d'images plus six installations de paquets par PR
coûteraient plus que tout le reste réuni, pour une information que le nightly donne déjà avec un jour
de retard au pire.

**Interfaces:**
- Produces : `tests/ci/run-target.sh` — exécute, sur la cible courante, la séquence « niveau 2 + 3 + 4 »
  (installation réelle, shell interactif réel, désinstallation, empreinte). Un seul script, appelé à
  l'identique par le workflow et par un rejeu local sous Docker : c'est ce qui rend la tâche testable
  avant tout push.
- Produces : `matrix.yml`, avec un job `prepare` qui lit `.github/matrix.json` et l'expose en sortie.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_ci_workflows.bats` :

```bash
@test "the full matrix never runs on pull_request" {
    # Six pulls d'image par PR : le budget CI du spec l'interdit explicitement.
    run grep -n "pull_request" "$WF/matrix.yml"
    [ "$status" -ne 0 ]
}

@test "the full matrix runs nightly, on demand, and can be called by a release" {
    grep -q "schedule:" "$WF/matrix.yml"
    grep -q "workflow_dispatch:" "$WF/matrix.yml"
    grep -q "workflow_call:" "$WF/matrix.yml"
}

@test "the matrix reads its targets from matrix.json, not from an inline list" {
    grep -q "matrix.json" "$WF/matrix.yml"
    grep -q "fromJSON" "$WF/matrix.yml"
    # Aucune image de conteneur écrite en dur dans le workflow.
    run grep -nE "image: (ubuntu|debian|fedora|archlinux|alpine):" "$WF/matrix.yml"
    [ "$status" -ne 0 ]
}

@test "the matrix does not fail-fast — one broken distro must not hide the others" {
    grep -q "fail-fast: false" "$WF/matrix.yml"
}
```

Et le rejeu local, qui est le vrai test de la logique :

```bash
# Ajouter à tests/e2e/test_ci_deps_script.bats

# bats test_tags=docker
@test "run-target.sh installs, runs a real interactive shell and reverts, on debian:12" {
    run docker run --rm -v "$ROOT:/src:ro" debian:12 sh -c '
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-target.sh
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"REAL_SHELL_OK"* ]]
}

# bats test_tags=docker
@test "run-target.sh works on alpine:3.20 too" {
    run docker run --rm -v "$ROOT:/src:ro" alpine:3.20 sh -c '
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-target.sh
    '
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_workflows.bats && NIVUUS_CI_DOCKER=1 ./tests/ci/bats-run.sh tests/e2e/test_ci_deps_script.bats`
Expected: FAIL — `matrix.yml` n'existe pas ; `run-target.sh: not found` dans les conteneurs.

- [ ] **Step 3: Write minimal implementation**

```sh
# tests/ci/run-target.sh
#!/bin/sh
# =============================================================================
# La séquence « preuve » d'une cible de la matrice : niveaux 2, 3 et 4.
# =============================================================================
# Exécuté à l'identique par .github/workflows/matrix.yml et par un rejeu
# local `docker run … ./tests/ci/run-target.sh`. Aucune logique de preuve ne
# vit dans le YAML : c'est ce qui rend la matrice testable avant tout push.
set -eu

NIVUUS_SHELL_DIR="${NIVUUS_SHELL_DIR:-$(pwd)}"
export NIVUUS_SHELL_DIR

echo "== Niveau 2 : installation réelle puis shell interactif réel =="
./tests/ci/bats-run.sh \
    tests/e2e/test_nivuus_cli.bats \
    tests/e2e/test_install_sh_compat.bats \
    tests/e2e/test_minimal_mode.bats \
    tests/e2e/test_platform.bats

# Un shell réellement interactif, hors bats : la preuve que l'installation
# produit un shell utilisable et silencieux sur stderr.
work="$(mktemp -d)"
HOME="$work/home"; export HOME; mkdir -p "$HOME"
NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"; export NIVUUS_STATE_DIR

"$NIVUUS_SHELL_DIR/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell"
zsh -i -c 'echo REAL_SHELL_OK' 2> "$work/stderr"
if [ -s "$work/stderr" ]; then
    echo "stderr non vide au démarrage du shell :" >&2
    cat "$work/stderr" >&2
    exit 1
fi
"$NIVUUS_SHELL_DIR/bin/nivuus" uninstall --yes --purge
rm -rf "$work"

echo "== Niveau 3 : réversibilité (empreinte de HOME bit-exacte) =="
./tests/ci/bats-run.sh tests/e2e/test_reversibility.bats

echo "== Niveau 4 : dry-run, double install, oh-my-zsh, cohabitation =="
./tests/ci/bats-run.sh tests/e2e/test_with_deps.bats tests/e2e/test_shell_load.bats

echo "== Cible OK =="
```

```bash
chmod +x tests/ci/run-target.sh
```

```yaml
# .github/workflows/matrix.yml
name: Matrix

# Matrice exhaustive : coûteuse, donc jamais sur PR (voir le budget CI du spec).
# La boucle de PR est .github/workflows/tests.yml.
on:
  schedule:
    - cron: '17 3 * * *'
  workflow_dispatch:
  workflow_call:

concurrency:
  group: matrix-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: read

jobs:
  prepare:
    name: Read matrix targets
    runs-on: ubuntu-latest
    outputs:
      containers: ${{ steps.read.outputs.containers }}
      runners: ${{ steps.read.outputs.runners }}
    steps:
      - uses: actions/checkout@v4
      - id: read
        run: |
          echo "containers=$(jq -c '.containers' .github/matrix.json)" >> "$GITHUB_OUTPUT"
          echo "runners=$(jq -c '.runners' .github/matrix.json)" >> "$GITHUB_OUTPUT"

  containers:
    name: ${{ matrix.target.label }}
    needs: prepare
    runs-on: ubuntu-latest
    container:
      image: ${{ matrix.target.image }}
    strategy:
      fail-fast: false
      matrix:
        target: ${{ fromJSON(needs.prepare.outputs.containers) }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: Prove install, uninstall and reversibility
        run: ./tests/ci/run-target.sh

  runners:
    name: ${{ matrix.target.label }}
    needs: prepare
    runs-on: ${{ matrix.target['runs-on'] }}
    strategy:
      fail-fast: false
      matrix:
        target: ${{ fromJSON(needs.prepare.outputs.runners) }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: Prove install, uninstall and reversibility
        run: ./tests/ci/run-target.sh

  # Les tests qui pilotent eux-mêmes Docker (install-deps, run-target rejoués
  # dans quatre images) : trop lourds pour une PR, à leur place ici.
  docker-tagged:
    name: Docker-tagged tests
    needs: prepare
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: Container-driving tests
        env:
          NIVUUS_CI_DOCKER: '1'
        run: ./tests/ci/bats-run.sh tests/e2e/test_ci_deps_script.bats

  full-suite:
    name: Full suite (unit + integration + e2e + performance)
    needs: prepare
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - run: ./tests/ci/bats-run.sh tests/unit/
      - run: ./tests/ci/bats-run.sh tests/integration/
      - run: ./tests/ci/bats-run.sh tests/e2e/
      - run: ./tests/ci/bats-run.sh tests/performance/
      - run: ./bin/test-count --check
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_ci_workflows.bats tests/unit/test_ci_matrix_data.bats
NIVUUS_CI_DOCKER=1 ./tests/ci/bats-run.sh tests/e2e/test_ci_deps_script.bats
./actionlint .github/workflows/*.yml
gh workflow run Matrix --ref "$(git branch --show-current)" && gh run watch --exit-status
```
Expected: PASS — les rejeux Docker locaux verts, puis les 6 jobs de conteneur + 2 jobs de runner +
`docker-tagged` + `full-suite` verts sur GitHub. Chaque cible qui casse ici est une vraie découverte
(Fedora et Arch n'ont jamais été exercées) : corriger la cause, pas le test.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/matrix.yml tests/ci/run-target.sh tests/unit/test_ci_workflows.bats tests/e2e/test_ci_deps_script.bats
git commit -m "ci: exhaustive nightly matrix, driven by matrix.json"
```

---

### Task 9: `uninstall-verified.yml` — le workflow que le badge peut vraiment refléter

**Files:**
- Create: `.github/workflows/uninstall-verified.yml`
- Modify: `tests/unit/test_ci_workflows.bats`

**Pourquoi un workflow séparé.** Un badge affiche l'état d'**un workflow**, pas d'un job. Tant que la
réversibilité est un step parmi trente dans `tests.yml`, le seul badge honnête qu'on puisse afficher
est « Tests ». Pour un badge « uninstall verified » qui veut dire quelque chose, il faut un workflow
dont *toute* la raison d'être est le niveau 3 — sur les trois plateformes où on sait le faire tourner
en moins de deux minutes.

**Ce qui garantit qu'il ne peut pas rester vert à tort**, quatre conditions cumulées :

1. Il tourne sur `push: master` — sans cela, le badge `?branch=master` fige la dernière valeur connue
   indéfiniment (c'est le défaut actuel du badge « Tests »).
2. Il tourne aussi sur `pull_request` et figure dans les **required status checks** de la branche
   protégée (Task 12) : rien ne peut atterrir sur master en le cassant.
3. Il ne contient ni `continue-on-error`, ni `|| true`, ni step qui interprète une sortie —
   `tests/unit/test_ci_workflows.bats` le vérifie, et ce test tourne sur chaque PR.
4. Il tourne aussi la nuit : une casse due à l'environnement (image, runner) et non à un commit est
   détectée sans attendre la prochaine PR.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_ci_workflows.bats` :

```bash
@test "the uninstall-verified workflow exists and only does reversibility" {
    f="$WF/uninstall-verified.yml"
    [ -f "$f" ]
    grep -q "tests/e2e/test_reversibility.bats" "$f"
}

@test "uninstall-verified runs on push to master, on PRs and nightly" {
    f="$WF/uninstall-verified.yml"
    grep -q "push:" "$f"
    grep -q "master" "$f"
    grep -q "pull_request:" "$f"
    grep -q "schedule:" "$f"
}

@test "uninstall-verified covers ubuntu, macOS and alpine" {
    f="$WF/uninstall-verified.yml"
    grep -q "ubuntu-latest" "$f"
    grep -q "macos-latest" "$f"
    grep -q "alpine" "$f"
}

@test "no badge-backing workflow can swallow a failure" {
    for f in "$WF/uninstall-verified.yml" "$WF/tests.yml" "$WF/matrix.yml"; do
        run grep -n "continue-on-error" "$f"
        [ "$status" -ne 0 ] || { echo "$f contient continue-on-error"; false; }
        # `|| true` sur une ligne qui lance des tests : le vert deviendrait gratuit.
        run grep -nE "bats.*\|\| true|bats-run.sh.*\|\| true" "$f"
        [ "$status" -ne 0 ] || { echo "$f absorbe un échec de test"; false; }
    done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_workflows.bats`
Expected: FAIL — `.github/workflows/uninstall-verified.yml` n'existe pas (3 tests ; le quatrième
passe déjà si Task 6 est faite).

- [ ] **Step 3: Write minimal implementation**

```yaml
# .github/workflows/uninstall-verified.yml
name: uninstall verified

# Ce workflow existe pour porter un badge, et il ne fait qu'une chose :
# prouver le niveau 3 du spec — empreinte de $HOME avant installation,
# égale bit pour bit à l'empreinte après désinstallation.
#
# Ne jamais y ajouter un autre test : un badge qui rougit pour une raison
# étrangère à la désinstallation ne veut plus rien dire. Et ne jamais y
# ajouter `continue-on-error` : un badge décoratif est pire que pas de badge.

on:
  push:
    branches: [ master ]
  pull_request:
    branches: [ master ]
  schedule:
    - cron: '47 3 * * *'
  workflow_dispatch:

concurrency:
  group: uninstall-verified-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ubuntu:
    name: Reversibility (Ubuntu)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - run: ./tests/ci/bats-run.sh tests/e2e/test_reversibility.bats

  macos:
    name: Reversibility (macOS)
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - run: ./tests/ci/bats-run.sh tests/e2e/test_reversibility.bats

  alpine:
    name: Reversibility (Alpine / musl)
    runs-on: ubuntu-latest
    container:
      image: alpine:3.20
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - run: ./tests/ci/bats-run.sh tests/e2e/test_reversibility.bats
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_ci_workflows.bats
./actionlint .github/workflows/*.yml
git push && gh run watch --exit-status
```
Expected: PASS — les trois jobs verts, ~2 min de temps mur.

Vérifier aussi que le workflow **sait rougir** — un badge dont on n'a jamais vu le rouge n'est pas
prouvé :

```bash
git switch -c tmp/prove-red
# Casser volontairement la réversibilité : laisser une trace derrière soi.
printf '\ntouch "$HOME/.nivuus-trace"\n' >> lib/steps.sh
git commit -am "tmp: prove the uninstall badge can fail" && git push -u origin tmp/prove-red
gh run watch --exit-status   # DOIT sortir non nul
git switch - && git branch -D tmp/prove-red && git push origin --delete tmp/prove-red
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/uninstall-verified.yml tests/unit/test_ci_workflows.bats
git commit -m "ci: dedicated, blocking uninstall-verified workflow"
```

---

### Task 10: Niveau 4 — mise à jour depuis la release précédente

**Files:**
- Create: `tests/e2e/test_upgrade_from_release.bats`
- Modify: `.github/workflows/matrix.yml`

**Ce qui manque aujourd'hui.** Le niveau 4 du spec est couvert à trois quarts par l'existant :
`--dry-run` sans mutation, double installation, oh-my-zsh survivant, tous dans
`tests/e2e/test_reversibility.bats` et `test_nivuus_cli.bats`. Le quatrième scénario — « installation
de la release précédente puis `update` vers HEAD » — n'existe pas. C'est le seul qui attrape une
rupture de compatibilité du manifeste entre deux versions.

Il demande le réseau (téléchargement du tarball de release), donc il est marqué `network` et ne
tourne que dans la matrice nightly, jamais sur PR.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_upgrade_from_release.bats
#!/usr/bin/env bats
#
# Niveau 4 du spec : la dernière release publiée doit pouvoir être installée,
# puis mise à jour vers HEAD, sans rien casser ni rien laisser derrière.
# Marqué `network` : dépend de github.com, donc réservé à la matrice nightly.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    load "${BATS_TEST_DIRNAME}/../helpers/fingerprint.bash"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    command -v curl >/dev/null 2>&1 || skip "curl indisponible"
}

teardown() { rm -rf "$TMP"; }

fetch_previous_release() {
    tag="$(curl -fsSL https://api.github.com/repos/maximeallanic/nivuus-shell/releases/latest \
           | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
    [ -n "$tag" ] || return 1
    mkdir -p "$TMP/prev"
    curl -fsSL "https://github.com/maximeallanic/nivuus-shell/archive/refs/tags/${tag}.tar.gz" \
        | tar -xz -C "$TMP/prev" --strip-components=1
}

# bats test_tags=network
@test "the previous release installs, then HEAD installs over it" {
    fetch_previous_release || skip "release précédente indisponible"

    before="$(fs_fingerprint "$HOME")"

    "$TMP/prev/install.sh" --non-interactive
    [ -f "$HOME/.zshrc" ]

    # Mise à jour vers HEAD : c'est le chemin qu'empruntent les installations
    # existantes le jour où cette version sort.
    "$ROOT/bin/nivuus" install --yes
    run zsh -i -c 'echo UPGRADED_SHELL_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPGRADED_SHELL_OK"* ]]

    # Un seul bloc Nivuus : la mise à jour remplace, elle n'empile pas.
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]

    "$ROOT/bin/nivuus" uninstall --yes --purge
    after="$(fs_fingerprint "$HOME")"
    [ "$before" = "$after" ]
}

# bats test_tags=network
@test "the previous release's own uninstall path is not required for HEAD to clean up" {
    fetch_previous_release || skip "release précédente indisponible"
    "$TMP/prev/install.sh" --non-interactive
    run "$ROOT/bin/nivuus" uninstall --yes
    [ "$status" -eq 0 ]
    [ ! -d "$HOME/.nivuus-shell" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats --filter-tags network tests/e2e/test_upgrade_from_release.bats`
Expected: FAIL. L'échec attendu est réel, pas un fichier manquant : la release publiée est antérieure
aux phases 1-3, son `install.sh` écrase `~/.zshrc` et n'écrit aucun manifeste, donc l'empreinte
diverge après le `uninstall` de HEAD. C'est exactement le scénario de migration que le spec veut voir
couvert (« risques », section 7).

- [ ] **Step 3: Write minimal implementation**

Faire passer la migration côté produit, pas côté test :
- `nivuus install` par-dessus une installation *sans manifeste* doit adopter l'existant : sauvegarder
  le `~/.zshrc` courant dans le store de backups et l'enregistrer en `MODIFY`, puis écrire le bloc
  délimité — de sorte que le `uninstall` suivant restaure le fichier d'avant la release précédente
  seulement s'il l'a lui-même sauvegardé, et laisse intact ce qu'il n'a pas créé sinon.
- Si l'égalité stricte de l'empreinte n'est pas atteignable pour un artefact que la release
  précédente a créé et que HEAD n'a jamais enregistré, **ne pas** l'ajouter à l'allowlist en silence :
  le spec exige un commentaire justificatif par entrée, et cette justification doit dire pourquoi
  aucun autre chemin n'était possible.

Puis exclure ces tests de la boucle rapide et les câbler au nightly, dans `matrix.yml`, job
`full-suite` :

```yaml
      - name: Level 4 — upgrade from the previous release (network)
        env:
          NIVUUS_CI_NETWORK: '1'
        run: bats --formatter tap13 --filter-tags network tests/e2e/test_upgrade_from_release.bats
```

et, dans `tests/ci/bats-run.sh`, ajouter `network` aux tags exclus par défaut, à côté de `docker` :

```sh
if [ "${NIVUUS_CI_DOCKER:-}" != "1" ]; then
    ARGS="$ARGS --filter-tags !docker"
fi
if [ "${NIVUUS_CI_NETWORK:-}" != "1" ]; then
    ARGS="$ARGS --filter-tags !network"
fi
```

Attention : `--filter-tags A --filter-tags B` est un **ou** chez bats. Pour cumuler deux exclusions,
utiliser une seule option : `--filter-tags '!docker,!network'`. Corriger `bats-run.sh` en conséquence
et compléter `tests/unit/test_ci_bats_run.bats` avec un cas qui vérifie qu'un test `network` et un
test `docker` sont tous deux exclus par défaut.

- [ ] **Step 4: Run test to verify it passes**

Run: `NIVUUS_CI_NETWORK=1 bats --filter-tags network tests/e2e/test_upgrade_from_release.bats`
Expected: PASS — 2 tests, ou `skip` explicite et motivé si aucune release n'est publiée.

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_upgrade_from_release.bats tests/ci/bats-run.sh \
        tests/unit/test_ci_bats_run.bats .github/workflows/matrix.yml lib bin
git commit -m "test(e2e): prove an upgrade from the previous release"
```

---

### Task 11: Badges du README, et le test qui interdit un badge décoratif

**Files:**
- Modify: `README.md`
- Create: `tests/unit/test_readme_badges.bats`

**Les badges retenus**, tous adossés à un workflow qui existe, tourne sur `master` et est bloquant :

```markdown
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
[![Matrix](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)
```

Trois arbitrages inscrits dans le README :

- **`?branch=master` est obligatoire.** Sans lui, un badge affiche le dernier run toutes branches
  confondues, y compris celui d'une PR de fork : c'est le défaut du badge « Tests » actuel.
- **Le badge « plateformes testées » n'est pas un shield statique.** Une pastille
  `platforms-macOS|Linux|WSL` est un texte que personne ne met à jour : c'est de la décoration. À la
  place, le badge « Matrix » (qui rougit si une cible casse) est doublé d'un **tableau** dont les
  lignes sont vérifiées contre `.github/matrix.json` par un test.
- **Le badge de performance devient vérifiable.** `startup-<100ms` n'était adossé à rien (mesure
  réelle : 25 ms, budget appliqué : 300 ms). Il est remplacé par un badge qui annonce le budget
  *effectivement appliqué* par `tests/performance/test_startup.bats`, et un test vérifie que les deux
  nombres coïncident.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_readme_badges.bats
#!/usr/bin/env bats
#
# Un badge décoratif est pire que pas de badge : il transforme une absence de
# preuve en apparence de preuve. Ces tests rendent cela impossible.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    README="$ROOT/README.md"
    WF="$ROOT/.github/workflows"
}

badge_workflows() {   # imprime le nom de fichier de chaque workflow référencé par un badge
    grep -o 'actions/workflows/[a-z0-9._-]*/badge.svg' "$README" \
        | sed 's|actions/workflows/||; s|/badge.svg||' | LC_ALL=C sort -u
}

@test "every workflow badge points at a workflow file that exists" {
    n=0
    for wf in $(badge_workflows); do
        [ -f "$WF/$wf" ] || { echo "badge orphelin: $wf"; false; }
        n=$((n + 1))
    done
    [ "$n" -ge 3 ]
}

@test "every workflow badge is pinned to master" {
    # Sans ?branch=master, le badge montre le dernier run toutes branches.
    while IFS= read -r line; do
        case "$line" in *badge.svg*) ;; *) continue ;; esac
        [[ "$line" == *"badge.svg?branch=master"* ]] || { echo "non épinglé: $line"; false; }
    done < "$README"
}

@test "every badge-backing workflow actually runs on master" {
    for wf in $(badge_workflows); do
        grep -q "push:" "$WF/$wf" || { echo "$wf ne tourne pas sur push"; false; }
        grep -q "master" "$WF/$wf" || { echo "$wf ne cible pas master"; false; }
    done
}

@test "no badge-backing workflow can swallow a failure" {
    for wf in $(badge_workflows); do
        run grep -n "continue-on-error" "$WF/$wf"
        [ "$status" -ne 0 ] || { echo "$wf: continue-on-error"; false; }
    done
}

@test "the uninstall badge is backed by the reversibility test" {
    grep -q "uninstall-verified.yml/badge.svg" "$README"
    grep -q "tests/e2e/test_reversibility.bats" "$WF/uninstall-verified.yml"
}

@test "the tested-platforms table matches .github/matrix.json exactly" {
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
    for label in $(jq -r '(.containers[], .runners[]) | .label | gsub(" "; "_")' "$ROOT/.github/matrix.json"); do
        want="$(printf '%s' "$label" | tr '_' ' ')"
        grep -qF "$want" "$README" || { echo "cible absente du README: $want"; false; }
    done
}

@test "the startup badge states the budget that is actually enforced" {
    budget="$(grep -o 'NIVUUS_STARTUP_BUDGET_MS:-[0-9]*' "$ROOT/tests/performance/test_startup.bats" \
              | head -1 | sed 's/.*-//')"
    [ -n "$budget" ]
    grep -q "startup-<${budget}ms" "$README" || {
        echo "le badge n'annonce pas le budget appliqué (${budget}ms)"; false; }
}

@test "no legacy badge syntax remains" {
    # `workflows/Tests/badge.svg` : ancienne forme, non épinglable à une branche.
    run grep -n "workflows/Tests/badge.svg" "$README"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_badges.bats`
Expected: FAIL — 6 tests sur 8 : le README n'a qu'un badge de workflow, en syntaxe héritée, sans
`?branch=master`, sans tableau de plateformes, et son badge de performance annonce `<100ms` alors que
le budget appliqué est 300.

- [ ] **Step 3: Write minimal implementation**

Remplacer le bloc de badges en tête de `README.md` :

```markdown
[![Version](https://img.shields.io/github/v/release/maximeallanic/nivuus-shell?label=version)](https://github.com/maximeallanic/nivuus-shell/releases)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-ZSH-green.svg)
![Startup](https://img.shields.io/badge/startup-<300ms-brightgreen.svg)
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
[![Matrix](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)
```

Et ajouter une section, après « Quick Start » :

```markdown
## Plateformes testées

Chaque nuit, et avant chaque release, Nivuus est installé puis désinstallé sur chacune de ces
cibles ; l'empreinte de `$HOME` doit être identique bit pour bit avant et après. Le badge
**uninstall verified** ci-dessus rougit dès qu'une trace subsiste.

| Cible | Niveau de preuve |
|---|---|
| Ubuntu 22.04 | installation, shell réel, désinstallation, empreinte |
| Ubuntu 24.04 | installation, shell réel, désinstallation, empreinte |
| Debian 12 | installation, shell réel, désinstallation, empreinte |
| Arch Linux | installation, shell réel, désinstallation, empreinte |
| Fedora 41 | installation, shell réel, désinstallation, empreinte |
| Alpine 3.20 (musl) | installation, shell réel, désinstallation, empreinte — valide le chemin sans coreutils GNU |
| Ubuntu (GitHub runner) | matrice complète, quatre niveaux |
| macOS 14 (arm64) | installation, désinstallation, empreinte |
| WSL2 | **simulé** : marqueurs `/proc/version` et `WSL_DISTRO_NAME` injectés dans un conteneur Ubuntu. Valide la branche de code, pas l'environnement. |

Cette liste est vérifiée contre `.github/matrix.json` par `tests/unit/test_readme_badges.bats` :
ajouter une cible à la matrice sans l'ajouter ici fait échouer la CI, et inversement.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_readme_badges.bats`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_badges.bats
git commit -m "docs: badges backed by real, blocking workflows"
```

---

### Task 12: Checks requis, alerte nightly, et point de contact avec `release.yml`

**Files:**
- Create: `tests/ci/required-checks.sh`
- Modify: `.github/workflows/matrix.yml`
- Modify: `.github/workflows/release.yml` *(point de contact — voir l'avertissement)*
- Modify: `tests/unit/test_ci_workflows.bats`

**⚠️ Cette tâche touche `release.yml`, que le plan de signature des releases modifie en parallèle.**
La faire **en dernier**, dans un commit qui ne touche à ce fichier que pour deux choses : remplacer le
job `test` par un appel à `matrix.yml`, et supprimer le step « Validate startup time requirement »
(le même théâtre que celui retiré de `tests.yml` en Task 4). Aucune autre ligne de `release.yml` ne
doit bouger. Si le plan de signature a déjà atterri, rebaser dessus et vérifier que le job `release`
dépend bien du nouveau `test`.

**Trois choses à mettre en place :**

1. **Checks requis.** Un badge n'est bloquant que si le check l'est. Les checks à exiger sur `master` :
   `Unit + integration`, `Installation E2E (Ubuntu)`, `Installation E2E (macOS)`,
   `Installation E2E (Alpine / musl)`, `Syntax validation`, `Reversibility (Ubuntu)`,
   `Reversibility (macOS)`, `Reversibility (Alpine / musl)`.
2. **Alerte nightly.** Un nightly rouge que personne ne regarde ne prouve rien : `matrix.yml` ouvre
   (ou met à jour) une issue en cas d'échec sur une exécution programmée.
3. **Release bloquante.** La matrice complète devient la condition de sortie d'une release, comme
   l'exige le spec (« aucune release ne sort si un uninstall laisse une trace »).

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_ci_workflows.bats` :

```bash
@test "release.yml runs the full matrix, not a hand-rolled subset" {
    grep -q "uses: ./.github/workflows/matrix.yml" "$WF/release.yml"
}

@test "release.yml no longer interprets performance output" {
    run grep -n "Validate startup time requirement" "$WF/release.yml"
    [ "$status" -ne 0 ]
}

@test "the release job still depends on the tests passing" {
    grep -q "needs: test" "$WF/release.yml"
}

@test "a failed nightly matrix opens an issue" {
    grep -q "github.event_name == 'schedule'" "$WF/matrix.yml"
    grep -q "issues: write" "$WF/matrix.yml"
}

@test "the required checks list is declared and matches the job names" {
    list="$ROOT/tests/ci/required-checks.sh"
    [ -f "$list" ]
    for job in "Unit + integration" "Installation E2E (Ubuntu)" "Installation E2E (macOS)" \
               "Reversibility (Ubuntu)" "Reversibility (macOS)" "Reversibility (Alpine / musl)"; do
        grep -qF "$job" "$list" || { echo "check requis manquant: $job"; false; }
        grep -qF "$job" "$WF/tests.yml" "$WF/uninstall-verified.yml" \
            || { echo "aucun job ne s'appelle: $job"; false; }
    done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_workflows.bats`
Expected: FAIL — 5 tests : `release.yml` exécute encore sa propre poignée de tests avec son
« Validate startup time requirement », `matrix.yml` n'alerte pas, et `required-checks.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/ci/required-checks.sh
#!/usr/bin/env bash
# =============================================================================
# Les checks qui doivent être exigés sur `master`.
# =============================================================================
# Ce fichier est la déclaration ; `--apply` la pousse sur GitHub. Il existe
# pour une raison précise : un badge n'est bloquant que si le check qui le
# nourrit est requis. Sinon le badge dit « rouge » pendant qu'on merge quand même.
set -euo pipefail

REPO="${NIVUUS_REPO:-maximeallanic/nivuus-shell}"
BRANCH="${NIVUUS_BRANCH:-master}"

CHECKS=(
    "Unit + integration"                    # tests.yml
    "Installation E2E (Ubuntu)"             # tests.yml
    "Installation E2E (macOS)"              # tests.yml
    "Installation E2E (Alpine / musl)"      # tests.yml
    "Syntax validation"                     # tests.yml
    "Reversibility (Ubuntu)"                # uninstall-verified.yml
    "Reversibility (macOS)"                 # uninstall-verified.yml
    "Reversibility (Alpine / musl)"         # uninstall-verified.yml
)

if [ "${1:-}" != "--apply" ]; then
    printf '%s\n' "${CHECKS[@]}"
    echo
    echo "Pour appliquer sur $REPO@$BRANCH : $0 --apply  (nécessite gh + droits admin)"
    exit 0
fi

contexts="$(printf '"%s",' "${CHECKS[@]}" | sed 's/,$//')"
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
    --input - <<EOF
{
  "required_status_checks": { "strict": true, "contexts": [$contexts] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
echo "Checks requis appliqués sur $REPO@$BRANCH"
```

```bash
chmod +x tests/ci/required-checks.sh
./tests/ci/required-checks.sh --apply     # une fois, avec des droits admin sur le dépôt
```

Ajouter à `matrix.yml`, en fin de fichier :

```yaml
  notify:
    name: Report a failed nightly
    needs: [containers, runners, docker-tagged, full-suite]
    if: failure() && github.event_name == 'schedule'
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const title = 'Nightly matrix is red';
            const url = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            const body = `La matrice nightly a échoué : ${url}\n\nUne cible de la matrice ne prouve plus l'installation ou la désinstallation. Le badge « uninstall verified » peut rester vert (il ne couvre que trois plateformes) : ce n'est pas une raison d'attendre.`;
            const existing = await github.rest.issues.listForRepo({
              owner: context.repo.owner, repo: context.repo.repo,
              state: 'open', labels: 'ci',
            });
            const hit = existing.data.find(i => i.title === title);
            if (hit) {
              await github.rest.issues.createComment({
                owner: context.repo.owner, repo: context.repo.repo,
                issue_number: hit.number, body,
              });
            } else {
              await github.rest.issues.create({
                owner: context.repo.owner, repo: context.repo.repo,
                title, body, labels: ['ci'],
              });
            }
```

Dans `release.yml` — **la seule modification autorisée par ce plan** — remplacer tout le job `test`
(du `test:` jusqu'au step « Validate ZSH syntax » inclus) par :

```yaml
jobs:
  # Aucune release ne sort si une cible de la matrice ne prouve plus
  # l'installation ou la désinstallation (spec, section 4, budget CI).
  test:
    name: Full matrix
    uses: ./.github/workflows/matrix.yml
```

Le job `release` conserve son `needs: test`.

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_ci_workflows.bats
./actionlint .github/workflows/*.yml
./tests/ci/required-checks.sh          # affiche la liste
gh api "repos/maximeallanic/nivuus-shell/branches/master/protection" \
  | jq -r '.required_status_checks.contexts[]'    # doit refléter la même liste
```
Expected: PASS — 5 tests, et les deux listes identiques.

- [ ] **Step 5: Commit**

```bash
git add tests/ci/required-checks.sh .github/workflows/matrix.yml \
        .github/workflows/release.yml tests/unit/test_ci_workflows.bats
git commit -m "ci: make the matrix blocking for releases and alert on a red nightly"
```

---

## Vérification finale de la phase

Une fois les 12 tâches terminées, ces commandes doivent toutes réussir :

```bash
# La suite entière, en local
./tests/ci/bats-run.sh tests/unit/
./tests/ci/bats-run.sh tests/integration/
./tests/ci/bats-run.sh tests/e2e/
./tests/ci/bats-run.sh tests/performance/
./bin/test-count --check

# Les rejeux de conteneur (lents : ~6 min)
NIVUUS_CI_DOCKER=1 ./tests/ci/bats-run.sh tests/e2e/test_ci_deps_script.bats

# Les workflows
./actionlint .github/workflows/*.yml

# Aucune installation de paquet hors install-deps.sh
grep -rnE "apt-get install|apk add|pacman -S|dnf .*install|brew install" .github/ | grep -v BOOTSTRAP
# -> aucun résultat

# Aucun comptage de tests artisanal
grep -rn "sed 's/1\.\.//'" .github/
# -> aucun résultat
```

Et, sur GitHub :

```bash
gh run watch --exit-status                        # tests.yml + uninstall-verified.yml sur la PR
gh workflow run Matrix && gh run watch --exit-status
```

Critères de sortie de phase, tels que définis par le spec :

1. **Matrice complète verte** : Ubuntu 22.04 et 24.04, Debian 12, Arch, Fedora 41, Alpine, macOS,
   WSL simulé, mode headless/minimal.
2. **Quatre niveaux câblés** : niveau 1 → `tests/unit/` (606) ; niveau 2 → `tests/e2e/` + `run-target.sh`
   avec un `zsh -i` réel sur chaque cible ; niveau 3 → `tests/e2e/test_reversibility.bats` dans son
   workflow dédié ; niveau 4 → dry-run, double installation, oh-my-zsh, mise à jour depuis la release
   précédente.
3. **Découpage par déclencheur respecté** : la matrice ne tourne jamais sur PR ; la PR reste sous
   ~5 min ; la release exécute la matrice entière et est bloquée par elle.
4. **Badge « uninstall verified » actif**, adossé à `uninstall-verified.yml`, épinglé sur `master`,
   présent dans les checks requis, et dont on a **vu le rouge** au moins une fois (Task 9, Step 4).
5. **Le job macOS a réellement tourné** et est vert (il ne l'avait jamais fait).
6. **Le budget de 300 ms est appliqué en CI**, pas observé : plus aucun `skip` conditionné à `CI`.

---

## Points de contact

- **`.github/workflows/release.yml`** — modifié uniquement par Task 12, en deux points (le job `test`
  devient `uses: ./.github/workflows/matrix.yml` ; le step « Validate startup time requirement »
  disparaît). Le plan de signature des releases, rédigé en parallèle, possède ce fichier : faire
  Task 12 en dernier, rebaser dessus, et ne rien toucher d'autre.
- **`config/20-autoupdate.zsh`** — non touché ici. Le test « mise à jour depuis la release
  précédente » (Task 10) passe par `bin/nivuus install`, pas par le chemin d'auto-update : si le plan
  de signature ajoute une vérification de signature à l'auto-update, ce test devra être étendu, dans
  ce plan-là.
- **Allowlist d'exceptions de l'empreinte** (`tests/helpers/fingerprint.bash`) — Task 10 peut être
  tentée d'y ajouter une entrée. Le spec exige un commentaire justificatif par entrée ; l'ajout
  silencieux vide de sens tout le niveau 3, donc tout le badge.

---

## Ce que ce plan ne livre pas

Délibérément hors périmètre, avec la raison :

- **Un vrai runner WSL2.** Il n'en existe pas chez GitHub. Le job reste une **simulation** par
  injection de `/proc/version` et `WSL_DISTRO_NAME`, et le README le dit en toutes lettres. Prétendre
  couvrir WSL2 serait précisément le genre de badge décoratif que ce plan combat.
- **Le portage de `tests/performance/` hors Ubuntu.** Six des dix tests utilisent `date +%s%N` et
  `ps -o rss=`, GNU-only. Seul le test critique est marqué `portable` et tourne partout ; la suite
  reste Ubuntu. La rendre portable est une tâche à part, sans valeur de preuve pour l'installation.
- **Une mesure de couverture de code.** Le job `coverage` supprimé en Task 6 ne mesurait pas la
  couverture : il comptait des tests. `bin/test-count` fait ce comptage correctement. Une vraie
  couverture de shell (`kcov`, `bashcov`) est un chantier propre, à décider séparément.
- **La mise en cache des images de conteneur** entre exécutions nightly. Gain estimé : 20 à 30 s par
  cible, contre une complexité de cache et un risque d'image périmée. À reconsidérer si le nightly
  dépasse 45 min.
- **La parallélisation de `tests/unit/` et `tests/integration/`.** Mesurée perdante (25 s → 30 s) :
  le surcoût de démarrage par fichier dépasse le gain sur 606 tests courts. Rien à faire.
- **Le remplacement de `bin/test`.** Le lanceur historique en zsh reste le point d'entrée des
  développeurs ; `tests/ci/bats-run.sh` est celui de la CI. Les unifier demanderait de reprendre le
  parsing de sortie de `bin/test`, sans bénéfice pour la preuve.
- **La signature ou l'attestation des artefacts de release** (chantier 2, plan en parallèle).
- **Le one-liner `curl | sh` et la suppression de `init_git_repo`** (phase 5), donc aussi les tests
  de niveau 2 qui installeront depuis un tarball de release plutôt que depuis un checkout.
