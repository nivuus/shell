# Distribution par gestionnaires de paquets — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre Nivuus **empaquetable** — un arbre partagé en lecture seule posé par un gestionnaire de paquets, une activation par utilisateur qui reste le seul acte journalisé au manifeste — puis livrer les trois canaux (Homebrew, AUR, `.deb`) et leur automatisation.

**Architecture:** Deux inventaires qui ne se recouvrent jamais. Le gestionnaire est autoritatif sur `/usr/share/nivuus-shell` (ou `libexec` pour brew) ; `lib/manifest.sh` reste autoritatif, inchangé, sur le domaine de l'utilisateur (`~/.zshrc`, `chsh`, `~/.local/state/nivuus`). La bascule entre les deux régimes tient dans **un fichier marqueur** `$NIVUUS_SHELL_DIR/.nivuus-origin`, posé par la recette de paquet et par elle seule ; son **absence vaut `origin=source`**, c'est-à-dire le comportement d'aujourd'hui, mot pour mot.

**Tech Stack:** zsh (`config/*.zsh`), bash 3.2 / POSIX ash (`bin/nivuus`, `lib/*.sh`), bats (tests), GitHub Actions, Homebrew (Ruby DSL), `makepkg`/`namcap`, `dpkg-deb`/`lintian`.

**Spec:** `docs/superpowers/specs/2026-08-21-packaging-design.md` — elle fait autorité ; en cas de divergence avec ce plan, c'est la spec qui gagne.

---

## Comment lire ce plan : deux parties, deux régimes

| | Partie A | Partie B |
|---|---|---|
| Contenu | Noyau du mode paquet (phase 0 de la spec § 8) | Les trois formats, leur CI, leur gouvernance |
| Dépendances externes | **aucune** | comptes, dépôts, secrets, arbitrages |
| Exécutable | **immédiatement, de bout en bout** | partiellement (chaque tâche dit jusqu'où aller sans le blocage) |
| Livre un paquet ? | non — et c'est délibéré | oui |

**La partie A est auto-suffisante et doit être exécutée en premier.** Elle est utile seule : elle corrige trois défauts qui cassent déjà des installations réelles aujourd'hui (bloc `.zshrc` non gardé après un `rm -rf` manuel, `.zwc` orphelins, racine mal calculée derrière un lien).

La partie B ne doit pas être commencée avant que **toutes** les tâches de la partie A ne soient mergées : chaque format en dépend, et la spec (§ 3) l'exige explicitement (« cette phase … doit être mergée avant tout format »).

---

## Décisions actées (ne pas rouvrir)

1. **`nivuus enable` / `nivuus disable` sont retenus comme noms publics**, avec surcharge d'`install`/`uninstall` en mode paquet (spec § 2.3). Le nom est une API publique : si le propriétaire du projet veut trancher autrement (question ouverte n° 1 de la spec), il doit le faire **avant la Task A9** ; passé ce point, le renommage coûte une dépréciation. Voir « Blocages » en tête de partie B.
2. **L'absence de `.nivuus-origin` vaut `origin=source`.** Aucune installation existante ne change de comportement. Une valeur inconnue vaut également `source` (permissif) — c'est le garde-fou d'inscriptibilité, indépendant, qui porte la sûreté dans ce cas.
3. **`bin/nivuus install` n'écrit jamais `origin=package`.** Le seul producteur de cette valeur est une recette de paquet. Un test l'interdit (Task A1).
4. **Refus d'auto-update en mode paquet, sans variable d'échappement.** La règle l'emporte sur `ENABLE_AUTOUPDATE=true`. Ne pas introduire de `NIVUUS_FORCE_UPDATE`, ni d'équivalent.
5. **`nivuus update` en mode paquet sort en 0.** L'utilisateur a posé une question légitime et reçoit la réponse exacte ; ce n'est pas un échec. Le seul cas d'erreur conservé reste le dépôt git hérité de la v3.0.0.
6. **La garde `[ -r … ] && source …` du bloc `.zshrc` est émise dans TOUS les modes**, pas seulement en mode paquet. Un bloc identique partout est un bloc dont le comportement est prouvé une fois.
7. **Aucune sonde réseau par défaut en mode paquet** (spec § 1.4). `NIVUUS_PACKAGE_UPDATE_NOTIFY=1` est le seul opt-in, et il **notifie sans installer**. Hors périmètre de la partie A ; ne pas l'ajouter par anticipation.
8. **On ne livre pas de `.zwc` dans les paquets.** Le repli « cache par utilisateur sous `${XDG_CACHE_HOME:-~/.cache}/nivuus-shell/zwc/` » est **conçu mais non écrit** : il n'est livré que si la mesure de la Task A8 montre que le budget de 300 ms saute.
9. **Pas de manifeste système** (`/var/lib/nivuus/`). La base du gestionnaire *est* son manifeste.
10. **`uninstall` n'appelle jamais le gestionnaire de paquets** à la place de l'utilisateur, et ne supprime jamais un fichier de son domaine.

## Contraintes globales

- **`config/*.zsh` est du ZSH** (globs `(N)`, `[[ ]]`, `print -r --`). **`lib/*.sh` et `install.sh` restent POSIX / BusyBox ash / bash 3.2** : interdits `declare -A`, `mapfile`, `${var^^}`, `local -n`, `&>>`, `[[ ]]`, `BASH_SOURCE`, substitutions de processus `< <(`. `bats tests/unit/test_lib_posix.bats` doit rester vert après chaque commit touchant `lib/`.
- **Réversibilité bit-exacte préservée.** `bats tests/e2e/test_reversibility.bats` est le test central du projet : il doit rester vert à chaque commit. Toute écriture côté utilisateur passe par `lib/manifest.sh`, sans exception.
- **Aucune mutation hors `lib/manifest.sh`** dans le domaine de l'utilisateur, **aucun `sudo` implicite**, jamais.
- **Cible de démarrage <300 ms**, mesurée par `./bin/benchmark` (~35 ms aujourd'hui) et gardée par `bats tests/performance/`. Les nouvelles fonctions zsh doivent être de **simples définitions** : aucun `command -v`, aucun `fork`, aucun accès disque au moment du `source`. Le seul coût ajouté au chemin de démarrage est **un `[[ -r ]]`** sur `.nivuus-origin` (qui ne forke pas quand le fichier est absent — le cas de 100 % des installations existantes).
- **Piège des `.zwc`** : zsh source le bytecode s'il est plus récent que la source. Avant toute suite qui touche `config/*.zsh`, faire `rm -f config/*.zwc`, sinon un test peut passer (ou échouer) contre une version périmée du module.
- **Chiffres de référence à ne pas dégrader** (0 échec partout) :

  | Suite | Tests | Skips |
  |---|---|---|
  | `bats tests/unit/` | 742 | 0 |
  | `bats tests/integration/` | 195 | 2 |
  | `bats tests/e2e/` | 173 | 4 |
  | `bats tests/performance/` | 10 | 0 |

  Ce plan **ajoute** des tests ; ces nombres ne peuvent que croître. Après chaque tâche, relancer la suite concernée et vérifier qu'aucun test **existant** ne bascule au rouge ni ne devient `skip`. Si un test existant échoue, c'est une régression du plan, pas un chiffre à mettre à jour.
- **Tests :** bats. `tests/unit/` pour les fonctions pures, `tests/integration/` pour les modules combinés, `tests/e2e/` pour les scénarios complets. Les fonctions zsh se testent via `zsh -c 'ENABLE_AUTOUPDATE=false source config/20-autoupdate.zsh; …'` — sans `ENABLE_AUTOUPDATE=false`, le bloc de vérification automatique se déclenche au chargement.
- **Un commit par tâche**, message conventionnel en anglais (convention du dépôt : `feat(scope): …`, `fix(scope): …`). Les tâches sont indépendantes et mergeables une par une, sauf mention contraire explicite.
- **Documentation en français**, code et messages de commit en anglais, messages utilisateur en français (convention constatée du dépôt).

## Point de contact : le chantier « phase 4 CI » en cours de fusion

Un autre chantier réécrit `.github/workflows/tests.yml`, ajoute `.github/matrix.json`, `tests/ci/*.sh`, une action composite `.github/actions/setup-tests` et les badges du README. **Ce plan est écrit pour s'appliquer sur un `master` où la phase 4 est déjà mergée.**

| Élément | Conduite à tenir |
|---|---|
| `.github/workflows/tests.yml` | Task A13 y ajoute les nouvelles suites et le garde-fou `grep` des invariants. **Rebaser avant A13**, puis ajouter les suites à la structure de jobs de la phase 4 plutôt que de créer un job isolé. Si le fichier a été remplacé par des jobs pilotés par `.github/matrix.json`, ajouter les suites au job unitaire existant. |
| `.github/matrix.json` | Task B7 le consomme (`debian:12`, `ubuntu:24.04`, `archlinux:latest`, `macos-latest`). Ne pas le dupliquer, ne pas le modifier : si une cible manque, l'ajouter dans le chantier phase 4, pas ici. |
| `tests/ci/run-target.sh`, `tests/ci/bats-run.sh` | Task B7 écrit `tests/ci/run-package-target.sh` **sur le même modèle** (toute la logique de preuve dans le script, rien dans le YAML, rejouable en local par `docker run`). Lire `run-target.sh` avant d'écrire, et en copier la structure (arguments, codes de sortie, journalisation). |
| `.github/actions/setup-tests` | Réutilisée telle quelle par Task B7/B8. Ne pas la modifier. |
| Badges README | Task A14 et B11 touchent le README. Rebaser avant, et **ne pas toucher aux badges** posés par la phase 4. |

Si la phase 4 **n'est pas** mergée au moment d'exécuter la partie A : rien ne bloque. Seule la Task A13 doit alors s'appliquer au `tests.yml` actuel (jobs `test`, `e2e`, `e2e-macos`), en ajoutant les nouvelles suites au job `e2e` existant et le `grep` des invariants à côté de l'étape « The two invariants must be present and green » qui existe déjà pour la signature.

---

# PARTIE A — Livrable tout de suite

Aucune de ces quatorze tâches ne demande un compte, un secret ou un arbitrage externe. À la fin de la partie A : un arbre posé **à la main** sous `/usr/share/nivuus-shell` avec un `.nivuus-origin` se comporte déjà correctement (auto-update refusé, `nivuus update` explicatif et vert, `.zwc` non écrits, `enable`/`disable` réversibles) — prouvé par un test e2e **sans aucun gestionnaire de paquets**. Et les installations par le one-liner sont bit-pour-bit inchangées.

**Ordre recommandé :** A1 → A2 → A3 → A4 → A5 → A6 → A7 → A8 → A9 → A10 → A11 → A12 → A13 → A14. Les tâches A1 à A7 sont mutuellement indépendantes sauf A4/A5/A6 qui consomment A1 (côté zsh, la lecture du marqueur est réimplémentée en ligne — voir A4 — donc même cette dépendance est faible). A12 consomme A1 à A9. A13 consomme toutes les suites créées.

---

### Task A1: `lib/origin.sh` — d'où vient cette installation ?

**Files:**
- Create: `lib/origin.sh`
- Modify: `bin/nivuus` (sourcer le nouveau module)
- Test: `tests/unit/test_lib_origin.bats`

**Interfaces:**
- Consumes: rien.
- Produces: `nivuus_origin_field <dir> <clé>`, `nivuus_origin <dir>`, `nivuus_origin_is_package <dir>`, `nivuus_origin_channel <dir>`, `nivuus_origin_update_command <dir>`, `nivuus_origin_tree_writable <dir>`.

Ce module est la **seule** lecture du marqueur côté sh. Il ne connaît rien d'autre : ni le manifeste, ni le `.zshrc`, ni le réseau. Le côté zsh (Task A4) le réimplémente délibérément en trois lignes plutôt que de le sourcer, pour ne pas alourdir le chemin de démarrage.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_origin.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"
    . "$ROOT/lib/origin.sh"
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

@test "no marker at all means origin=source (comportement d'aujourd'hui)" {
    run nivuus_origin "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "source" ]
}

@test "no marker at all means not a package install" {
    run nivuus_origin_is_package "$DIR"
    [ "$status" -ne 0 ]
}

@test "origin=package is recognised" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run nivuus_origin "$DIR"
    [ "$output" = "package" ]
    run nivuus_origin_is_package "$DIR"
    [ "$status" -eq 0 ]
}

@test "an unknown origin value degrades to source, never to package" {
    marker 'origin=chaussette'
    run nivuus_origin "$DIR"
    [ "$output" = "source" ]
    run nivuus_origin_is_package "$DIR"
    [ "$status" -ne 0 ]
}

@test "a marker with no origin= line degrades to source" {
    marker 'channel=aur' 'version=3.2.0'
    run nivuus_origin "$DIR"
    [ "$output" = "source" ]
}

@test "an unreadable marker degrades to source, it does not crash" {
    marker 'origin=package'
    chmod 000 "$DIR/.nivuus-origin"
    run nivuus_origin "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "source" ]
    chmod 644 "$DIR/.nivuus-origin"
}

@test "fields are read individually" {
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell' 'version=3.2.0'
    run nivuus_origin_field "$DIR" channel
    [ "$output" = "aur" ]
    run nivuus_origin_field "$DIR" version
    [ "$output" = "3.2.0" ]
    run nivuus_origin_field "$DIR" package
    [ "$output" = "nivuus-shell" ]
}

@test "only the first occurrence of a key is used" {
    marker 'channel=aur' 'channel=deb'
    run nivuus_origin_field "$DIR" channel
    [ "$output" = "aur" ]
}

@test "an absent field fails, it does not print garbage" {
    marker 'origin=package'
    run nivuus_origin_field "$DIR" channel
    [ -z "$output" ]
}

@test "channel defaults to unknown when the marker says package but names no channel" {
    marker 'origin=package'
    run nivuus_origin_channel "$DIR"
    [ "$output" = "unknown" ]
}

@test "the update command is derived from the channel, never guessed" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"brew upgrade nivuus-shell"* ]]

    marker 'origin=package' 'channel=deb' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"apt"* ]]

    # On ne présume pas de yay plutôt que paru : les deux sont nommés.
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"yay"* ]] || [[ "$output" == *"paru"* ]]
}

@test "an unknown channel still yields a usable sentence, never an empty one" {
    marker 'origin=package' 'channel=chaussette' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [ -n "$output" ]
}

@test "a writable tree is reported writable" {
    run nivuus_origin_tree_writable "$DIR"
    [ "$status" -eq 0 ]
}

@test "a read-only tree is reported non writable" {
    # Inopérant en root (root écrit partout) : c'est précisément pour ça que
    # le marqueur existe en plus du garde-fou. On saute plutôt que de mentir.
    [ "$(id -u)" -ne 0 ] || skip "root ignore les permissions d'écriture"
    chmod 500 "$DIR"
    run nivuus_origin_tree_writable "$DIR"
    [ "$status" -ne 0 ]
    chmod 700 "$DIR"
}

@test "a missing tree is reported non writable" {
    run nivuus_origin_tree_writable "$TMP/nexistepas"
    [ "$status" -ne 0 ]
}

@test "INVARIANT: nivuus install never writes origin=package" {
    # Le seul producteur de cette valeur est une recette de paquet. Si cette
    # ligne apparaît un jour dans bin/nivuus, lib/ ou install.sh, le mode
    # paquet devient auto-proclamable et le refus d'auto-update se retourne
    # contre les installations par le one-liner.
    run grep -rn 'origin=package' "$ROOT/bin" "$ROOT/lib" "$ROOT/install.sh"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_origin.bats`
Expected: FAIL — `lib/origin.sh` n'existe pas, toutes les fonctions sont introuvables.

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/origin.sh
# D'où vient cette installation ? Ce module ne connaît rien d'autre.
#
# Source de vérité : $dir/.nivuus-origin, fichier texte clé=valeur posé par
# la recette de paquet et par elle seule. Son ABSENCE vaut origin=source,
# c'est-à-dire le comportement d'aujourd'hui : c'est ce qui garantit qu'une
# régression de ce module ne peut pas atteindre le canal principal.
#
# POSIX strict (BusyBox ash, bash 3.2) : ni [[ ]], ni tableaux, ni BASH_SOURCE.

nivuus_origin_field() {
    local dir="$1" key="$2" value
    [ -r "$dir/.nivuus-origin" ] || return 1
    value="$(sed -n "s/^$key=//p" "$dir/.nivuus-origin" 2>/dev/null | head -n1)"
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

# Toujours 0, toujours une valeur : « source » ou « package ». Une valeur
# inconnue vaut source (permissif) -- la sûreté, dans ce cas, est portée par
# nivuus_origin_tree_writable, qui est indépendant du marqueur.
nivuus_origin() {
    local value
    value="$(nivuus_origin_field "$1" origin 2>/dev/null || printf 'source')"
    case "$value" in
        package) printf 'package\n' ;;
        *)       printf 'source\n' ;;
    esac
}

nivuus_origin_is_package() { [ "$(nivuus_origin "$1")" = "package" ]; }

nivuus_origin_channel() {
    nivuus_origin_field "$1" channel 2>/dev/null || printf 'unknown\n'
}

# La commande affichée est DÉRIVÉE du champ channel=, jamais devinée à partir
# du chemin d'installation ni du gestionnaire présent sur la machine.
nivuus_origin_update_command() {
    local dir="$1" channel pkg
    channel="$(nivuus_origin_channel "$dir")"
    pkg="$(nivuus_origin_field "$dir" package 2>/dev/null || printf 'nivuus-shell')"
    case "$channel" in
        homebrew) printf 'brew upgrade %s\n' "$pkg" ;;
        aur)      printf '%s\n' "yay -Syu $pkg   (ou paru -Syu $pkg, selon ton assistant AUR)" ;;
        deb)      printf '%s\n' "apt upgrade $pkg   (ou, pour un .deb téléchargé à la main, la page de release du projet)" ;;
        *)        printf '%s\n' "la commande de mise à jour de ton gestionnaire de paquets" ;;
    esac
}

# Garde-fou SECONDAIRE, indépendant du marqueur : il couvre le cas « un tiers
# a empaqueté Nivuus sans poser le marqueur », qui arrivera, parce que l'AUR
# et les taps sont ouverts à tous. Inopérant en root -- c'est assumé, et
# c'est pour ça que le marqueur existe en plus. Le marqueur porte le MESSAGE,
# le garde-fou porte la SÛRETÉ ; aucun des deux ne suffit seul.
nivuus_origin_tree_writable() { [ -d "$1" ] && [ -w "$1" ]; }
```

Puis, dans `bin/nivuus`, ajouter la ligne de source **après** `lib/log.sh` (le module n'en dépend pas, mais l'ordre du fichier reste alphabétiquement cohérent avec le reste) :

```bash
. "$NIVUUS_SRC_ROOT/lib/detect.sh"
. "$NIVUUS_SRC_ROOT/lib/deps.sh"
. "$NIVUUS_SRC_ROOT/lib/origin.sh"
. "$NIVUUS_SRC_ROOT/lib/manifest.sh"
```

**Ne pas** ajouter `origin` à la liste de `nivuus_step_copy_tree` : `lib` y figure déjà en entier, le nouveau module est copié sans modification.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_lib_origin.bats
bats tests/unit/test_lib_posix.bats
bats tests/unit/test_lib_steps.bats tests/unit/test_smoke.bats
```
Expected: PASS — 16 tests pour la nouvelle suite, aucune régression sur les autres.

- [ ] **Step 5: Commit**

```bash
git add lib/origin.sh bin/nivuus tests/unit/test_lib_origin.bats
git commit -m "feat(origin): read the .nivuus-origin marker, absent means source"
```

---

### Task A2: `bin/nivuus` résout les liens symboliques

**Files:**
- Modify: `bin/nivuus`
- Test: `tests/unit/test_lib_selfpath.bats`

**Interfaces:**
- Consumes: rien.
- Produces: `NIVUUS_SRC_ROOT` correct derrière un lien, un lien de lien, et un lien relatif.

Aujourd'hui `NIVUUS_SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`. Sous `/usr/bin/nivuus -> /usr/share/nivuus-shell/bin/nivuus`, `BASH_SOURCE` vaut **le lien**, donc la racine calculée est `/usr` et le premier `. "$NIVUUS_SRC_ROOT/lib/log.sh"` échoue. C'est le mode d'installation par défaut d'un `PKGBUILD` et de `bin.install_symlink` : deux formats sur trois cassés dès le premier essai.

`readlink -f` n'est pas une option (absent des BSD/macOS avant coreutils). Boucle de résolution POSIX **bornée**, pour ne pas tourner indéfiniment sur un cycle de liens.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_selfpath.bats
#!/usr/bin/env bats
# La racine de bin/nivuus doit survivre à un lien symbolique : c'est le mode
# d'installation par défaut d'un PKGBUILD (ln -s) et de bin.install_symlink.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

# Imprime la racine que bin/nivuus calcule pour lui-même, sans exécuter
# la moindre sous-commande : on injecte une sortie juste après le calcul.
root_seen_from() {
    NIVUUS_PRINT_SRC_ROOT=1 "$1" help >/dev/null 2>&1
    NIVUUS_PRINT_SRC_ROOT=1 "$1" __srcroot 2>/dev/null
}

@test "direct invocation yields the repository root" {
    run root_seen_from "$ROOT/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "an absolute symlink yields the real root, not the symlink's parent" {
    mkdir -p "$TMP/usr/bin"
    ln -s "$ROOT/bin/nivuus" "$TMP/usr/bin/nivuus"
    run root_seen_from "$TMP/usr/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "a symlink to a symlink still yields the real root" {
    mkdir -p "$TMP/a" "$TMP/b"
    ln -s "$ROOT/bin/nivuus" "$TMP/a/nivuus"
    ln -s "$TMP/a/nivuus" "$TMP/b/nivuus"
    run root_seen_from "$TMP/b/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "a RELATIVE symlink is resolved against the link's own directory" {
    # Le cas que readlink naïf rate : le lien pointe « ../real/bin/nivuus »,
    # ce qui n'a de sens que relativement au répertoire du lien.
    mkdir -p "$TMP/real/bin" "$TMP/real/lib" "$TMP/usr/bin"
    cp "$ROOT/bin/nivuus" "$TMP/real/bin/nivuus"
    cp "$ROOT"/lib/*.sh "$TMP/real/lib/"
    ln -s "../../real/bin/nivuus" "$TMP/usr/bin/nivuus"
    run root_seen_from "$TMP/usr/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/real" ]
}

@test "a symlinked nivuus can actually source its libraries and run help" {
    # La preuve fonctionnelle, pas seulement le chemin : c'est ce qui casse
    # aujourd'hui (« . /usr/lib/log.sh: No such file or directory »).
    mkdir -p "$TMP/usr/bin"
    ln -s "$ROOT/bin/nivuus" "$TMP/usr/bin/nivuus"
    run "$TMP/usr/bin/nivuus" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "a symlink loop is bounded and does not hang" {
    mkdir -p "$TMP/loop"
    ln -s "$TMP/loop/b" "$TMP/loop/a"
    ln -s "$TMP/loop/a" "$TMP/loop/b"
    run timeout 10 env NIVUUS_PRINT_SRC_ROOT=1 "$TMP/loop/a" __srcroot
    # Peu importe le code de retour : ce qui compte est que ça TERMINE.
    [ "$status" -ne 124 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_selfpath.bats`
Expected: FAIL — la sous-commande `__srcroot` n'existe pas, et le cas du lien absolu donne le mauvais chemin.

- [ ] **Step 3: Write minimal implementation**

Dans `bin/nivuus`, remplacer la ligne de calcul de racine :

```bash
#!/usr/bin/env bash
# bin/nivuus — point d'entrée unique de gestion de Nivuus Shell.
set -euo pipefail

# Racine de l'arbre Nivuus, liens symboliques résolus.
#
# Sans cette résolution, un /usr/bin/nivuus -> /usr/share/nivuus-shell/bin/nivuus
# donnerait BASH_SOURCE=/usr/bin/nivuus, donc une racine /usr, et le premier
# « . $NIVUUS_SRC_ROOT/lib/log.sh » échouerait. C'est exactement ce que
# produisent bin.install_symlink (Homebrew) et le ln -s usuel d'un PKGBUILD.
#
# readlink -f est écarté : absent des BSD et de macOS avant coreutils. La
# boucle est BORNÉE (32 sauts) pour terminer même sur un cycle de liens.
_nivuus_self="${BASH_SOURCE[0]}"
_nivuus_hops=0
while [ -L "$_nivuus_self" ] && [ "$_nivuus_hops" -lt 32 ]; do
    _nivuus_link="$(ls -ld -- "$_nivuus_self" | sed 's/.*-> //')"
    case "$_nivuus_link" in
        /*) _nivuus_self="$_nivuus_link" ;;
        # Un lien relatif n'a de sens que depuis le répertoire du lien.
        *)  _nivuus_self="$(dirname -- "$_nivuus_self")/$_nivuus_link" ;;
    esac
    _nivuus_hops=$((_nivuus_hops + 1))
done
NIVUUS_SRC_ROOT="$(cd -- "$(dirname -- "$_nivuus_self")/.." && pwd)"
unset _nivuus_self _nivuus_link _nivuus_hops

# Crochet de test : imprime la racine calculée et sort, avant tout source.
# Aucune valeur en production ; il n'apparaît pas dans usage().
if [ "${NIVUUS_PRINT_SRC_ROOT:-}" = "1" ] && [ "${1:-}" = "__srcroot" ]; then
    printf '%s\n' "$NIVUUS_SRC_ROOT"
    exit 0
fi

# shellcheck source=/dev/null
. "$NIVUUS_SRC_ROOT/lib/log.sh"
```

Le reste du fichier est inchangé.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_lib_selfpath.bats
bats tests/e2e/test_nivuus_cli.bats
bats tests/e2e/test_reversibility.bats
```
Expected: PASS — 6 nouveaux tests, aucune régression.

- [ ] **Step 5: Commit**

```bash
git add bin/nivuus tests/unit/test_lib_selfpath.bats
git commit -m "fix(cli): resolve symlinks when computing the Nivuus root"
```

---

### Task A3: le bloc `.zshrc` survit à la disparition de l'arbre

**Files:**
- Modify: `lib/zshrc.sh` (`nivuus_zshrc_block`)
- Modify: `tests/unit/test_lib_zshrc.bats` (assertions sur le contenu du bloc)
- Test: `tests/unit/test_zshrc_block_guard.bats`

**Interfaces:**
- Consumes: rien.
- Produces: un bloc `.zshrc` dont la ligne de source est gardée par `[ -r … ] &&`, **dans tous les modes**.

Le paquet peut partir alors que le bloc reste — c'est le cas **normal** : `brew uninstall` n'a aucun moyen de savoir qui a activé quoi. Le bloc actuel casserait alors tous les shells de tous les utilisateurs encore activés, à chaque prompt, sans rapport visible avec l'action faite. La garde couvre aussi le `rm -rf ~/.nivuus-shell` à la main, qui arrive déjà aujourd'hui et produit exactement le même shell cassé.

Contrepartie assumée : la garde **masque** une installation cassée au lieu de la signaler. C'est pour cela que `nivuus doctor` doit détecter « bloc présent, arbre absent » — c'est la Task A10. **Ne pas merger A3 sans planifier A10.**

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_zshrc_block_guard.bats
#!/usr/bin/env bats
# Le bloc écrit dans ~/.zshrc doit survivre à la disparition de l'arbre
# Nivuus : c'est le cas NORMAL après un « brew uninstall » ou un « apt purge »
# alors que des utilisateurs ont encore le bloc.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"
    . "$ROOT/lib/zshrc.sh"
}

teardown() { rm -rf "$TMP"; }

@test "the block guards its source line with a readability test" {
    run nivuus_zshrc_block "/usr/share/nivuus-shell"
    [ "$status" -eq 0 ]
    [[ "$output" == *'[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"'* ]]
}

@test "the block NEVER contains a bare, unguarded source line" {
    run nivuus_zshrc_block "$HOME/.nivuus-shell"
    while IFS= read -r line; do
        [ "$line" != 'source "$NIVUUS_SHELL_DIR/.zshrc"' ]
    done <<< "$output"
}

@test "the guard is emitted in minimal mode too (one block, proven once)" {
    run nivuus_zshrc_block "/usr/share/nivuus-shell" 1
    [[ "$output" == *'[ -r "$NIVUUS_SHELL_DIR/.zshrc" ]'* ]]
    [[ "$output" == *'export NIVUUS_MINIMAL=1'* ]]
}

@test "a zsh reading the block with a MISSING tree prints nothing on stderr" {
    # LA propriété : arbre absent, bloc présent, shell silencieux.
    nivuus_zshrc_block "$TMP/nexistepas" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc' 2>'$TMP/err'; exit 0"
    [ "$status" -eq 0 ]
    [ ! -s "$TMP/err" ]
}

@test "a zsh reading the block with a PRESENT tree still sources it" {
    mkdir -p "$TMP/tree"
    printf 'export NIVUUS_PROOF=sourced\n' > "$TMP/tree/.zshrc"
    nivuus_zshrc_block "$TMP/tree" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc'; print -r -- \$NIVUUS_PROOF"
    [ "$status" -eq 0 ]
    [ "$output" = "sourced" ]
}

@test "an unreadable tree .zshrc is treated as absent, not as an error" {
    [ "$(id -u)" -ne 0 ] || skip "root lit tout"
    mkdir -p "$TMP/tree"
    printf 'echo nope\n' > "$TMP/tree/.zshrc"
    chmod 000 "$TMP/tree/.zshrc"
    nivuus_zshrc_block "$TMP/tree" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc' 2>'$TMP/err'; exit 0"
    [ ! -s "$TMP/err" ]
    chmod 644 "$TMP/tree/.zshrc"
}

@test "the block is still stripped cleanly by nivuus_zshrc_strip" {
    # La garde ne doit pas casser le retrait : c'est lui qui porte la
    # réversibilité bit-exacte.
    printf 'export MINE=1\n' > "$TMP/zshrc"
    { nivuus_zshrc_block "$TMP/tree"; cat "$TMP/zshrc"; } > "$TMP/merged"
    run nivuus_zshrc_strip "$TMP/merged"
    [ "$output" = "export MINE=1" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_zshrc_block_guard.bats`
Expected: FAIL — le bloc contient encore `source "$NIVUUS_SHELL_DIR/.zshrc"` nu ; le test « stderr vide avec arbre absent » échoue avec `no such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/zshrc.sh`, une seule ligne change dans `nivuus_zshrc_block` :

```sh
nivuus_zshrc_block() {
    local install_dir="$1" minimal="${2:-}"
    printf '%s\n' "$NIVUUS_BLOCK_BEGIN"
    printf '%s\n' '# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.'
    printf '%s\n' "# Pour tes personnalisations, crée ~/.zsh_local (il n'existe pas par défaut)"
    printf 'export NIVUUS_SHELL_DIR="%s"\n' "$install_dir"
    [ -n "$minimal" ] && printf '%s\n' 'export NIVUUS_MINIMAL=1'
    # La garde est émise dans TOUS les modes, pas seulement en mode paquet.
    # Trois raisons : elle couvre aussi le « rm -rf ~/.nivuus-shell » à la
    # main ; un bloc identique dans les quatre canaux est un bloc dont le
    # comportement est prouvé une fois (une variante par canal serait une
    # variante non testée) ; et son coût est un [ -r ] par ouverture de
    # shell, sous le seuil de mesure.
    #
    # Elle MASQUE une installation cassée au lieu de la signaler : c'est
    # « nivuus doctor » qui détecte « bloc présent, arbre absent » et donne
    # la commande de réparation. Silence au démarrage, diagnostic à la demande.
    printf '%s\n' '[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"'
    printf '%s\n' "$NIVUUS_BLOCK_END"
    return 0
}
```

Puis mettre à jour les assertions de `tests/unit/test_lib_zshrc.bats` qui vérifient le contenu littéral du bloc :

```bash
grep -rn 'source "\$NIVUUS_SHELL_DIR/.zshrc"' tests/ doc/ README.md
```

Pour chaque occurrence dans un **test**, remplacer l'assertion par la ligne gardée. Pour chaque occurrence dans la **documentation**, la mettre à jour aussi (Task A14 s'en charge pour le fond ; ici, seule la cohérence littérale du bloc compte). Ne **pas** toucher aux occurrences dans `nivuus_zshrc_strip_legacy` : elles décrivent le format de la v3.0.0, qui n'a jamais eu de garde et qu'il faut continuer à reconnaître à l'identique.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_zshrc_block_guard.bats
bats tests/unit/test_lib_zshrc.bats
bats tests/e2e/test_reversibility.bats tests/e2e/test_upgrade_from_v3.bats
bats tests/e2e/test_installation.bats tests/e2e/test_shell_load.bats
```
Expected: PASS — 7 nouveaux tests ; `test_reversibility` et `test_upgrade_from_v3` restent verts (le bloc change de contenu, mais il est écrit et retiré par le même code).

- [ ] **Step 5: Commit**

```bash
git add lib/zshrc.sh tests/unit/test_zshrc_block_guard.bats tests/unit/test_lib_zshrc.bats
git commit -m "fix(zshrc): guard the source line so a removed tree cannot break shells"
```

---

### Task A4: refus de l'auto-update en mode paquet

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Test: `tests/unit/test_autoupdate_package_mode.bats`

**Interfaces:**
- Consumes: le format de `.nivuus-origin` (Task A1) — **relu en ligne, sans sourcer `lib/origin.sh`**.
- Produces: `_nivuus_origin`, `_nivuus_is_package_install`, `_nivuus_origin_channel`, et le troisième terme de la garde du bloc de démarrage.

**Pourquoi ne pas sourcer `lib/origin.sh` ici.** Aucun module de `config/` ne source `lib/*.sh` sur le chemin de démarrage aujourd'hui (`nivuus-update` le fait pour `lib/migrate.sh`, mais seulement à l'appel manuel), et le budget de 300 ms est un test qui bloque les PR. Le coût ajouté ici doit être **un `[[ -r ]]`** — qui ne forke pas quand le fichier est absent, c'est-à-dire dans 100 % des installations existantes. La duplication de trois lignes est le prix, elle est assumée et commentée des deux côtés.

`_nivuus_is_package_install` rejoint `_nivuus_is_dev_checkout` : deux gardes de même nature, au même endroit, pour la même raison — « l'updater est destructif, il ne doit pas s'exécuter là où il détruirait autre chose que lui-même ». La symétrie n'est pas cosmétique : elle garantit qu'on ne peut pas corriger l'une en oubliant l'autre.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_package_mode.bats
#!/usr/bin/env bats
# En mode paquet, la mise à jour automatique est désactivée. Sans exception,
# sans variable d'échappement, et même contre ENABLE_AUTOUPDATE=true.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    # Le bytecode périmé masque la source : il ferait passer (ou échouer) ce
    # test contre une version qui n'est pas celle qu'on modifie.
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

# Charge le module avec l'auto-update DÉSACTIVÉ, puis évalue une expression.
probe() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        source '$DIR/config/20-autoupdate.zsh'
        $1
    "
}

@test "no marker: origin is source" {
    run probe '_nivuus_origin'
    [ "$output" = "source" ]
}

@test "no marker: not a package install" {
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "no" ]
}

@test "origin=package: recognised as a package install" {
    marker 'origin=package' 'channel=deb'
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "yes" ]
}

@test "an unknown origin value is NOT a package install" {
    marker 'origin=chaussette'
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "no" ]
}

@test "the channel is readable from zsh too" {
    marker 'origin=package' 'channel=homebrew'
    run probe '_nivuus_origin_channel'
    [ "$output" = "homebrew" ]
}

@test "INVARIANT: a package install never schedules an async update check" {
    # La preuve observable : le fichier d'horodatage n'est jamais écrit.
    # S'il apparaît, c'est que _nivuus_check_update_async a tourné -- donc
    # que l'updater destructif a pu partir contre un arbre appartenant à
    # dpkg / pacman / brew.
    marker 'origin=package' 'channel=deb'
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 1   # laisse une éventuelle tâche &! le temps d'écrire
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "INVARIANT: the package rule wins over ENABLE_AUTOUPDATE=true" {
    # Corollaire assumé de la spec § 1.1 : il n'existe aucune façon
    # d'honorer ce réglage qui ne produise pas un système incohérent.
    marker 'origin=package' 'channel=homebrew'
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 1
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "a SOURCE install still schedules the check (no regression on the main path)" {
    # Le canal principal ne doit voir strictement aucun changement.
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 2
    [ -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "there is NO escape hatch variable for package mode" {
    # Toute variable qui rétablirait l'auto-update en mode paquet
    # réintroduirait l'échec silencieux hebdomadaire que ce chantier ferme.
    run grep -nE 'NIVUUS_(FORCE|ALLOW)_(PACKAGE_)?UPDATE' "$ROOT/config/20-autoupdate.zsh"
    [ "$status" -ne 0 ]
}

@test "reading the marker costs no fork when it is absent" {
    # Le chemin de démarrage de 100% des installations existantes : le
    # [[ -r ]] échoue et on ne doit PAS avoir lancé sed.
    run probe '_nivuus_origin'
    [ "$output" = "source" ]
    # Le corps de la fonction doit sortir avant tout appel externe.
    run grep -A3 '_nivuus_origin()' "$ROOT/config/20-autoupdate.zsh"
    [[ "$output" == *'[[ -r'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_autoupdate_package_mode.bats`
Expected: FAIL — `_nivuus_origin` n'existe pas, et les deux invariants échouent (le fichier d'horodatage est écrit même avec `origin=package`).

- [ ] **Step 3: Write minimal implementation**

Dans `config/20-autoupdate.zsh`, juste **après** `_nivuus_is_dev_checkout` :

```zsh
# Detect a package-manager install (spec § 1.2).
#
# Source de vérité : $NIVUUS_SHELL_DIR/.nivuus-origin, posé par la recette de
# paquet. Son ABSENCE vaut « source » : c'est le comportement d'aujourd'hui,
# mot pour mot, donc une régression ici ne peut pas atteindre le canal
# principal.
#
# Volontairement réimplémenté ici plutôt que sourcé depuis lib/origin.sh :
# aucun module de config/ ne source lib/*.sh sur le chemin de démarrage, et
# le budget de 300 ms est un test qui bloque les PR. Coût ajouté quand le
# marqueur est absent : un [[ -r ]], et rien d'autre -- pas de fork.
_nivuus_origin() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- source; return 0 }
    v="${$(sed -n 's/^origin=//p' "$f" 2>/dev/null | head -n1):-source}"
    [[ "$v" == "package" ]] && { print -r -- package; return 0 }
    print -r -- source
}

_nivuus_origin_channel() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- unknown; return 0 }
    v="${$(sed -n 's/^channel=//p' "$f" 2>/dev/null | head -n1):-unknown}"
    print -r -- "$v"
}

_nivuus_origin_package_name() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- nivuus-shell; return 0 }
    v="${$(sed -n 's/^package=//p' "$f" 2>/dev/null | head -n1):-nivuus-shell}"
    print -r -- "$v"
}

_nivuus_origin_package_version() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || return 1
    v="$(sed -n 's/^version=//p' "$f" 2>/dev/null | head -n1)"
    [[ -n "$v" ]] || return 1
    print -r -- "$v"
}

# Jumelle de _nivuus_is_dev_checkout : deux gardes de même nature, au même
# endroit, pour la même raison -- l'updater est destructif, il ne doit pas
# s'exécuter là où il détruirait autre chose que lui-même. La symétrie
# garantit qu'on ne peut pas corriger l'une en oubliant l'autre.
_nivuus_is_package_install() { [[ "$(_nivuus_origin)" == "package" ]] }
```

Puis, dans le bloc de démarrage (« Main Auto-Update Logic ») :

```zsh
# Only run if enabled — never against a git checkout (dev mode), where a
# destructive release install would delete .git and any uncommitted work,
# and never against a package install, where it would rewrite files owned
# by dpkg / pacman / brew (spec § 1.1). La règle du mode paquet l'emporte
# délibérément sur ENABLE_AUTOUPDATE=true : il n'existe aucune façon
# d'honorer ce réglage qui ne produise pas un système incohérent.
if [[ "$ENABLE_AUTOUPDATE" == "true" ]] \
   && ! _nivuus_is_dev_checkout \
   && ! _nivuus_is_package_install; then
    days_since_check=$(_nivuus_days_since_check)

    if (( days_since_check >= AUTOUPDATE_CHECK_FREQUENCY_DAYS )); then
        _nivuus_check_update_async
    fi
    unset days_since_check
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_autoupdate_package_mode.bats
bats tests/unit/test_autoupdate_download.bats tests/unit/test_autoupdate_hard_refusal.bats \
     tests/unit/test_autoupdate_sha256.bats tests/unit/test_autoupdate_legacy_hint.bats
bats tests/performance/
./bin/benchmark | grep -A1 '^Average'
```
Expected: PASS — 10 nouveaux tests ; les suites d'auto-update existantes restent vertes ; le benchmark reste au même ordre de grandeur (~35 ms) : le marqueur est absent dans un checkout de développement, donc le `[[ -r ]]` échoue sans forker.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_package_mode.bats
git commit -m "feat(autoupdate): refuse automatic updates on a package install"
```

---

### Task A5: garde-fou secondaire — un arbre non inscriptible n'est jamais réécrit

**Files:**
- Modify: `config/20-autoupdate.zsh` (`_nivuus_perform_update`)
- Test: `tests/unit/test_autoupdate_readonly_tree.bats`

**Interfaces:**
- Consumes: rien (indépendant du marqueur — **c'est le point**).
- Produces: un refus dur, avec message, avant tout téléchargement et toute sauvegarde.

Ce garde-fou couvre le cas « un tiers a empaqueté Nivuus **sans** poser le marqueur » — qui arrivera, parce que l'AUR et les taps sont ouverts à tous. **Le marqueur porte le message ; le garde-fou porte la sûreté. Aucun des deux ne suffit seul.** Il est volontairement placé **avant** `_nivuus_download_release` : une mise à jour qu'on va refuser ne doit rien coûter et ne rien laisser derrière elle.

Limite connue et assumée : inopérant pour un shell **root** sur une machine paquetée — c'est-à-dire faux exactement dans le cas dangereux. C'est le marqueur qui couvre celui-là.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_readonly_tree.bats
#!/usr/bin/env bats
# Garde-fou secondaire, INDÉPENDANT du marqueur : un arbre que l'utilisateur
# courant ne peut pas écrire n'est jamais réécrit par l'updater.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    printf '3.0.0\n' > "$DIR/.version"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { chmod -R u+w "$DIR" 2>/dev/null || true; rm -rf "$TMP"; }

perform() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        source '$DIR/config/20-autoupdate.zsh'
        _nivuus_perform_update 9.9.9
    " 2>&1
}

@test "a read-only tree makes the destructive update refuse" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout : c'est le marqueur qui couvre ce cas"
    chmod 500 "$DIR"
    run perform
    [ "$status" -ne 0 ]
    [[ "$output" == *"$DIR"* ]]
}

@test "the refusal names the tree and does not pretend to have updated" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR"
    run perform
    [[ "$output" != *"Restart your shell"* ]]
}

@test "the refusal happens BEFORE any download or backup" {
    # Un refus doit être gratuit : ni tarball téléchargé, ni copie de ~50 Mo.
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR"
    run perform
    [[ "$output" != *"Backup created"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "the guard does not depend on the marker (no marker, read-only tree)" {
    # C'est LE cas visé : un tiers empaquette sans poser .nivuus-origin.
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    [ ! -f "$DIR/.nivuus-origin" ]
    chmod 500 "$DIR"
    run perform
    [ "$status" -ne 0 ]
}

@test "a writable tree is NOT refused by this guard" {
    # Preuve que le garde-fou ne bloque pas le canal principal : on échoue
    # plus loin (réseau injoignable), pas sur l'inscriptibilité.
    run env NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
        _nivuus_perform_update 9.9.9
    "
    [[ "$output" != *"lecture seule"* ]]
    [[ "$output" != *"read-only"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_autoupdate_readonly_tree.bats`
Expected: FAIL — l'updater tente le téléchargement au lieu de refuser.

- [ ] **Step 3: Write minimal implementation**

Dans `config/20-autoupdate.zsh`, en **tout premier** dans `_nivuus_perform_update` :

```zsh
_nivuus_perform_update() {
    local target_version=${1:-$(_nivuus_latest_version)}
    local interactive=${2:-}

    # Garde-fou SECONDAIRE (spec § 1.2, règle 3), indépendant du marqueur.
    # Il couvre le cas « un tiers a empaqueté Nivuus sans poser
    # .nivuus-origin » -- qui arrivera, parce que l'AUR et les taps sont
    # ouverts à tous. Placé AVANT le téléchargement : un refus doit être
    # gratuit et ne rien laisser derrière lui.
    #
    # Limite assumée : inopérant pour un shell root sur machine paquetée,
    # c'est-à-dire faux exactement dans le cas dangereux. C'est le marqueur
    # qui couvre celui-là. Le marqueur porte le MESSAGE, ce garde-fou porte
    # la SÛRETÉ ; aucun des deux ne suffit seul.
    if [[ ! -w "$NIVUUS_SHELL_DIR" ]]; then
        echo "❌ Mise à jour refusée : $NIVUUS_SHELL_DIR n'est pas inscriptible par $(whoami)."
        echo "   Nivuus ne réécrit jamais un arbre qu'il ne possède pas — il appartient"
        echo "   probablement à un gestionnaire de paquets ou à un montage en lecture seule."
        if _nivuus_is_package_install; then
            echo "   Mets-le à jour avec ton gestionnaire : $(_nivuus_origin_channel)"
        fi
        return 1
    fi

    if [[ -z "$target_version" ]]; then
        echo "❌ Could not determine target version"
        return 1
    fi
    ...
```

Le reste de la fonction est inchangé.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_autoupdate_readonly_tree.bats
bats tests/unit/test_autoupdate_*.bats
bats tests/e2e/test_update_signature.bats
```
Expected: PASS — 5 nouveaux tests, aucune régression sur la chaîne de mise à jour signée.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_readonly_tree.bats
git commit -m "feat(autoupdate): never rewrite a tree the current user cannot write"
```

---

### Task A6: `nivuus update` en mode paquet — la commande du gestionnaire, et code 0

**Files:**
- Modify: `config/20-autoupdate.zsh` (`nivuus-update`)
- Modify: `bin/nivuus` (`cmd_update`)
- Test: `tests/unit/test_update_package_message.bats`
- Test: `tests/e2e/test_nivuus_update_package.bats`

**Interfaces:**
- Consumes: `lib/origin.sh` (côté `bin/nivuus`), `_nivuus_origin*` (côté zsh).
- Produces: le message de refus utile, et **le code de sortie 0**.

Le message est la moitié de la décision : un refus sans issue est un bug d'UX. **Code 0** parce que l'utilisateur a posé une question légitime et a reçu la réponse exacte ; un code non nul ferait crier les scripts et les tâches planifiées qui appellent `nivuus update`, sans rien apprendre à personne.

`bin/nivuus update` doit répondre **sans** déléguer à `zsh -ic 'nivuus-update'` : le message est le même, mais il ne doit pas dépendre d'un shell interactif qui pourrait ne pas exister (conteneur, CI, cron). Les deux chemins portent donc le message ; le test e2e exerce le chemin `bin/nivuus`, le test unitaire exerce le chemin zsh.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_update_package_message.bats
#!/usr/bin/env bats
# En mode paquet, « nivuus update » affiche la commande du gestionnaire,
# ne télécharge rien, et SORT EN 0.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    printf '3.2.0\n' > "$DIR/.version"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

update() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
        nivuus-update
    " 2>&1
}

@test "INVARIANT: nivuus-update exits 0 on a package install" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [ "$status" -eq 0 ]
}

@test "the homebrew channel prints the brew command" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"brew upgrade nivuus-shell"* ]]
}

@test "the aur channel names both assistants, presuming neither" {
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"yay"* ]]
    [[ "$output" == *"paru"* ]]
}

@test "the deb channel prints an apt command" {
    marker 'origin=package' 'channel=deb' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"apt"* ]]
}

@test "the installed version is shown" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"3.2.0"* ]]
}

@test "the way back to automatic updates is offered, not hidden" {
    # Un refus sans issue est un bug d'UX : on donne la sortie exacte.
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"brew uninstall nivuus-shell"* ]]
    [[ "$output" == *"install.sh"* ]]
}

@test "nothing is downloaded: no temp tree, no backup" {
    marker 'origin=package' 'channel=deb' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" != *"Downloading"* ]]
    [[ "$output" != *"Backup created"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "a SOURCE install is unaffected (no regression on the main path)" {
    run update
    [[ "$output" != *"gère les mises à jour"* ]]
}
```

```bash
# tests/e2e/test_nivuus_update_package.bats
#!/usr/bin/env bats
# Le chemin bin/nivuus doit répondre sans déléguer à un shell interactif :
# en conteneur, en CI et en cron, « zsh -ic » n'est pas garanti.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    DIR="$TMP/share/nivuus-shell"
    mkdir -p "$DIR"
    cp -a "$ROOT"/lib "$ROOT"/bin "$DIR"/
    printf '3.2.0\n' > "$DIR/.version"
}

teardown() { rm -rf "$TMP"; }

@test "INVARIANT: bin/nivuus update exits 0 on a package install" {
    printf 'origin=package\nchannel=aur\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$DIR/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$DIR" "$DIR/bin/nivuus" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus-shell"* ]]
}

@test "bin/nivuus update does not need an interactive zsh in package mode" {
    printf 'origin=package\nchannel=deb\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$DIR/.nivuus-origin"
    # PATH sans zsh : si le code déléguait à « exec zsh -ic », il échouerait.
    run env NIVUUS_SHELL_DIR="$DIR" PATH="/usr/bin:/bin" "$DIR/bin/nivuus" update
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bats tests/unit/test_update_package_message.bats tests/e2e/test_nivuus_update_package.bats
```
Expected: FAIL — `nivuus-update` tente de contacter GitHub et sort en erreur ; `bin/nivuus update` délègue à `zsh -ic`.

- [ ] **Step 3: Write minimal implementation**

Dans `config/20-autoupdate.zsh`, au **début** de `nivuus-update`, juste avant la garde `_nivuus_is_dev_checkout` :

```zsh
nivuus-update() {
    # Mode paquet : le gestionnaire est autoritatif, on lui rend la main
    # avec la commande exacte -- et on sort en 0. L'utilisateur a posé une
    # question légitime et a reçu la réponse exacte ; ce n'est pas un échec.
    # Un code non nul ferait crier les scripts et les tâches planifiées qui
    # appellent nivuus update, sans rien apprendre à personne.
    if _nivuus_is_package_install; then
        local channel pkg version
        channel="$(_nivuus_origin_channel)"
        pkg="$(_nivuus_origin_package_name)"
        version="$(_nivuus_origin_package_version 2>/dev/null || _nivuus_current_version)"
        case "$channel" in
            homebrew) print -r -- "Nivuus a été installé par Homebrew ; c'est lui qui gère les mises à jour." ;;
            aur)      print -r -- "Nivuus a été installé depuis l'AUR ; c'est ton gestionnaire qui gère les mises à jour." ;;
            deb)      print -r -- "Nivuus a été installé par un paquet Debian ; c'est apt qui gère les mises à jour." ;;
            *)        print -r -- "Nivuus a été installé par un gestionnaire de paquets ; c'est lui qui gère les mises à jour." ;;
        esac
        print -r -- ""
        case "$channel" in
            homebrew) print -r -- "    brew upgrade $pkg" ;;
            aur)      print -r -- "    yay -Syu $pkg      (ou paru -Syu $pkg, selon ton assistant AUR)" ;;
            deb)      print -r -- "    apt upgrade $pkg   (ou, pour un .deb téléchargé à la main, la page de release du projet)" ;;
            *)        print -r -- "    la commande de mise à jour de ton gestionnaire de paquets" ;;
        esac
        print -r -- ""
        print -r -- "Version installée : $version"
        print -r -- "Pour repasser aux mises à jour automatiques de Nivuus :"
        case "$channel" in
            homebrew) print -r -- "    brew uninstall $pkg" ;;
            aur)      print -r -- "    sudo pacman -Rns $pkg" ;;
            deb)      print -r -- "    sudo apt remove $pkg" ;;
            *)        print -r -- "    retire le paquet avec ton gestionnaire" ;;
        esac
        print -r -- "    curl -fsSL https://raw.githubusercontent.com/${NIVUUS_GITHUB_REPO}/master/install.sh | sh"
        return 0
    fi

    # Never run the destructive release updater on a git checkout.
    if _nivuus_is_dev_checkout; then
        ...
```

Dans `bin/nivuus`, `cmd_update` répond **avant** de déléguer :

```bash
cmd_update() {
    local dir state channel pkg version
    dir="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}"

    # Mode paquet : on répond ici, sans déléguer à « zsh -ic ». En conteneur,
    # en CI et en cron, un zsh interactif n'est pas garanti -- et le message
    # doit sortir quand même. Code 0 : ce n'est pas un échec (spec § 1.3).
    if nivuus_origin_is_package "$dir"; then
        channel="$(nivuus_origin_channel "$dir")"
        pkg="$(nivuus_origin_field "$dir" package 2>/dev/null || printf 'nivuus-shell')"
        version="$(nivuus_origin_field "$dir" version 2>/dev/null || printf 'inconnue')"
        log_info "Nivuus a été installé par un gestionnaire de paquets ($channel) ;"
        log_info "c'est lui qui gère les mises à jour."
        printf '\n    %s\n\n' "$(nivuus_origin_update_command "$dir")"
        log_info "Version installée : $version"
        log_info "Pour repasser aux mises à jour automatiques de Nivuus, retire le paquet"
        log_info "puis relance l'installeur :"
        log_info "  curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh"
        return 0
    fi

    state="$(nivuus_git_state "$dir")"
    if [ "$state" = "legacy" ]; then
        ...
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_update_package_message.bats
bats tests/e2e/test_nivuus_update_package.bats
bats tests/unit/test_autoupdate_legacy_hint.bats tests/e2e/test_nivuus_cli.bats
```
Expected: PASS — 8 + 2 nouveaux tests ; le message « dépôt git hérité » reste intact (c'est le seul cas d'erreur conservé).

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh bin/nivuus \
        tests/unit/test_update_package_message.bats \
        tests/e2e/test_nivuus_update_package.bats
git commit -m "feat(update): point package installs at their manager and exit 0"
```

---

### Task A7: pas de `.zwc` dans un arbre qu'on ne possède pas

**Files:**
- Modify: `config/99-cleanup.zsh`
- Test: `tests/unit/test_cleanup_zwc_ownership.bats`

**Interfaces:**
- Consumes: `_nivuus_origin` (Task A4) — avec un repli autonome si `config/20-autoupdate.zsh` n'a pas été chargé.
- Produces: la compilation `.zwc` de l'arbre partagé n'a lieu **que si** l'arbre est inscriptible **ET** l'origine est `source`.

Deux conditions plutôt qu'une, et c'est la partie importante : l'**inscriptibilité** protège l'utilisateur normal (l'écriture échouerait de toute façon, silencieusement, dans un `&>/dev/null`) ; l'**origine** protège le shell **root** sur machine paquetée — le cas où l'écriture *réussirait* et laisserait sous `/usr/share` des orphelins qu'`apt purge` ne nettoie pas. Le projet exige « aucune trace après désinstallation » : ce serait une trace.

La compilation de `$HOME/.zshrc` et de `$HOME/.zsh_local` n'est **pas** concernée : ces fichiers appartiennent à l'utilisateur dans tous les modes.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_cleanup_zwc_ownership.bats
#!/usr/bin/env bats
# Nivuus ne compile jamais de bytecode dans un arbre qu'il ne possède pas :
# sous /usr/share, un shell root laisserait des orphelins qu'apt purge ne
# nettoie pas -- une trace, alors que le projet promet l'absence de trace.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/99-cleanup.zsh" "$DIR/config/"
    printf '# test module\nexport NIVUUS_TESTMOD=1\n' > "$DIR/config/50-test.zsh"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    printf '# user zshrc\n' > "$HOME/.zshrc"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { chmod -R u+w "$DIR" 2>/dev/null || true; rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

cleanup_run() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        source '$DIR/config/99-cleanup.zsh'
    " >/dev/null 2>&1
    # La compilation des modules est lancée en tâche de fond (&!) : on
    # laisse le temps d'écrire avant de conclure à une absence.
    sleep 1
}

@test "a source install with a writable tree still compiles (no regression)" {
    cleanup_run
    [ -f "$DIR/config/50-test.zsh.zwc" ]
}

@test "INVARIANT: a package install compiles NOTHING in the shared tree" {
    marker 'origin=package' 'channel=deb'
    cleanup_run
    [ ! -f "$DIR/config/50-test.zsh.zwc" ]
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "a package install leaves no .zwc even when the tree IS writable" {
    # Le cas du shell root sur machine paquetée : l'écriture réussirait.
    marker 'origin=package' 'channel=aur'
    [ -w "$DIR/config" ]
    cleanup_run
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "a read-only tree compiles nothing, marker or not" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR/config"
    cleanup_run
    chmod 700 "$DIR/config"
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "the user's own ~/.zshrc is still compiled in package mode" {
    # Ce fichier appartient à l'utilisateur dans TOUS les modes.
    marker 'origin=package' 'channel=homebrew'
    cleanup_run
    [ -f "$HOME/.zshrc.zwc" ]
}

@test "NIVUUS_NO_COMPILE=1 still disables everything" {
    NIVUUS_NO_COMPILE=1 NIVUUS_SHELL_DIR="$DIR" zsh -c "
        source '$DIR/config/99-cleanup.zsh'
    " >/dev/null 2>&1
    sleep 1
    run find "$DIR" "$HOME" -name '*.zwc'
    [ -z "$output" ]
}

@test "cleanup does not crash when config/20-autoupdate.zsh was never loaded" {
    # 99-cleanup doit être autonome : il ne peut pas présumer que
    # _nivuus_origin a été définie par un autre module.
    marker 'origin=package'
    run env NIVUUS_SHELL_DIR="$DIR" zsh -c "source '$DIR/config/99-cleanup.zsh'"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_cleanup_zwc_ownership.bats`
Expected: FAIL — les `.zwc` sont créés dans l'arbre même avec `origin=package`.

- [ ] **Step 3: Write minimal implementation**

Dans `config/99-cleanup.zsh`, remplacer le bloc de compilation :

```zsh
# Skip compilation in dev mode for faster iteration
if [[ "${NIVUUS_NO_COMPILE:-0}" != "1" ]]; then
    # Compile .zshrc if not already compiled or if source is newer.
    # Ce fichier appartient à l'utilisateur dans TOUS les modes : il est
    # compilé même en mode paquet.
    if [[ -f "$HOME/.zshrc" ]] && [[ (! -f "$HOME/.zshrc.zwc" || "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc") ]]; then
        zcompile "$HOME/.zshrc" &>/dev/null
    fi

    # Bytecode de l'arbre Nivuus : DEUX conditions, et c'est délibéré.
    #
    #  - inscriptibilité : protège l'utilisateur normal, pour qui l'écriture
    #    sous /usr/share échouerait de toute façon en silence (&>/dev/null) ;
    #  - origine : protège le shell ROOT sur machine paquetée -- le cas où
    #    l'écriture RÉUSSIRAIT et laisserait des orphelins qu'apt purge ne
    #    nettoie pas. Le projet promet « aucune trace » : c'en serait une.
    #
    # Autonome : ce module peut être sourcé sans config/20-autoupdate.zsh
    # (tests, chargement partiel), donc il relit le marqueur lui-même quand
    # _nivuus_origin n'existe pas. Coût quand le marqueur est absent : un
    # [[ -r ]], sans fork.
    _nivuus_cleanup_owns_tree() {
        [[ -w "$NIVUUS_SHELL_DIR" ]] || return 1
        [[ -w "$NIVUUS_SHELL_DIR/config" ]] || return 1
        local origin
        if (( $+functions[_nivuus_origin] )); then
            origin="$(_nivuus_origin)"
        elif [[ -r "$NIVUUS_SHELL_DIR/.nivuus-origin" ]]; then
            origin="${$(sed -n 's/^origin=//p' "$NIVUUS_SHELL_DIR/.nivuus-origin" 2>/dev/null | head -n1):-source}"
        else
            origin=source
        fi
        [[ "$origin" != "package" ]]
    }

    if [[ -d "$NIVUUS_SHELL_DIR/config" ]] && _nivuus_cleanup_owns_tree; then
        for config_file in "$NIVUUS_SHELL_DIR"/config/*.zsh; do
            if [[ (! -f "${config_file}.zwc" || "$config_file" -nt "${config_file}.zwc") ]]; then
                { zcompile "$config_file" &>/dev/null } &!
            fi
        done
    fi

    # Compile .zsh_local if exists (domaine de l'utilisateur, tous modes).
    if [[ -f "$HOME/.zsh_local" ]] && [[ (! -f "$HOME/.zsh_local.zwc" || "$HOME/.zsh_local" -nt "$HOME/.zsh_local.zwc") ]]; then
        zcompile "$HOME/.zsh_local" &>/dev/null
    fi
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_cleanup_zwc_ownership.bats
bats tests/integration/test_module_loading.bats
bats tests/performance/
```
Expected: PASS — 7 nouveaux tests, aucune régression.

- [ ] **Step 5: Commit**

```bash
git add config/99-cleanup.zsh tests/unit/test_cleanup_zwc_ownership.bats
git commit -m "fix(cleanup): never compile .zwc into a tree Nivuus does not own"
```

---

### Task A8: mesurer le coût de démarrage **sans** `.zwc` — livrable de la phase 0

**Files:**
- Create: `tests/performance/test_startup_without_zwc.bats`
- Create: `doc/PACKAGING.md` (section « Coût de démarrage sans bytecode » ; le reste du fichier est écrit en Task A14)

**Interfaces:**
- Consumes: Task A7 (c'est elle qui crée le cas « arbre jamais compilé »), `./bin/benchmark`.
- Produces: **un chiffre**, publié, et la décision qu'il commande.

C'est le seul point de la spec (§ 3.2, question ouverte n° 5) délibérément laissé ouvert **sur une donnée** plutôt que sur une préférence. La performance est un test bloquant dans ce projet ; elle ne se traite pas à l'estime.

**Ce qu'on mesure exactement.** Le temps de démarrage d'un shell complet, avec et sans bytecode, mesuré par `./bin/benchmark` (qui source `$NIVUUS_SHELL_DIR/.zshrc` cinq fois et donne une moyenne) :

```bash
# Référence AVEC bytecode (l'état d'aujourd'hui : ~35 ms)
rm -f config/*.zwc .zshrc.zwc
zsh -c 'NIVUUS_SHELL_DIR="$PWD" source ./.zshrc' >/dev/null 2>&1   # 1er passage : compile
sleep 2                                                            # la compilation est en &!
NIVUUS_SHELL_DIR="$PWD" ./bin/benchmark | sed -n '/^Average/p'

# Mesure SANS bytecode (l'état d'un paquet)
rm -f config/*.zwc .zshrc.zwc
NIVUUS_NO_COMPILE=1 NIVUUS_SHELL_DIR="$PWD" ./bin/benchmark | sed -n '/^Average/p'
```

**Règle de décision, écrite avant la mesure** (pour qu'elle ne soit pas ajustée après coup) :

| Moyenne sans `.zwc` | Décision |
|---|---|
| **< 150 ms** | Rien à faire. On ne livre pas de `.zwc` dans les paquets, et on ne livre pas non plus le repli. Consigner le chiffre dans `doc/PACKAGING.md` et clore la question ouverte n° 5. |
| **150–250 ms** | Rien à livrer, mais consigner le chiffre **et** la marge restante, et ajouter une ligne de veille dans `doc/PACKAGING.md` : si un futur module ajoute 50 ms, le repli devient nécessaire. |
| **> 250 ms** (ou > 300 ms sur une seule cible de la matrice) | **Le repli « cache par utilisateur » devient une tâche de la partie A** : compiler dans `${XDG_CACHE_HOME:-$HOME/.cache}/nivuus-shell/zwc/<version-zsh>/<version-nivuus>/` et **sourcer explicitement le `.zwc`** (zsh sait sourcer un `.zwc` directement, ce qui contourne la règle « le bytecode doit être à côté du source »). Le cache est inscriptible, versionné par la version de zsh **et** par celle de Nivuus, et sa suppression est déjà couverte par `uninstall --purge` (`~/.cache/nivuus-shell` y est déjà traité). Écrire alors la tâche A8bis sur le modèle des autres, avec son test de non-régression de performance. |

**Où mesurer.** Localement d'abord (poste du mainteneur, cible informative), puis sur les cibles réelles du projet : les six conteneurs de la matrice de test. Tant que la Task B7 n'existe pas, la mesure conteneurisée se fait à la main :

```bash
for img in debian:12 ubuntu:22.04 ubuntu:24.04 archlinux:latest alpine:3.20 fedora:40; do
  echo "=== $img"
  docker run --rm -v "$PWD:/src:ro" "$img" sh -c '
    (command -v apk && apk add --no-cache zsh) >/dev/null 2>&1 || \
    (command -v apt-get && apt-get update -qq && apt-get install -y -qq zsh) >/dev/null 2>&1 || \
    (command -v pacman && pacman -Sy --noconfirm zsh) >/dev/null 2>&1 || \
    (command -v dnf && dnf install -y -q zsh) >/dev/null 2>&1
    cp -a /src /tmp/nivuus && cd /tmp/nivuus
    rm -f config/*.zwc .zshrc.zwc
    NIVUUS_NO_COMPILE=1 NIVUUS_SHELL_DIR=/tmp/nivuus ./bin/benchmark 2>/dev/null | sed -n "/^Average/p"
  '
done
```

- [ ] **Step 1: Write the failing test**

```bash
# tests/performance/test_startup_without_zwc.bats
#!/usr/bin/env bats
# Un paquet ne livre AUCUN .zwc et n'en compile aucun (spec § 3.2). Le budget
# de 300 ms doit donc tenir sans bytecode -- sinon le repli « cache par
# utilisateur » devient obligatoire. Ce test est le garde-fou de cette
# décision : il échoue le jour où le mode paquet passe au-dessus du budget.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    command -v zsh >/dev/null || skip "zsh absent"
    rm -f "$ROOT"/config/*.zwc "$ROOT"/.zshrc.zwc
}

teardown() { rm -rf "$TMP"; rm -f "$ROOT"/config/*.zwc; }

# Moyenne de 5 démarrages complets, en millisecondes (entier).
startup_ms_no_zwc() {
    zsh -c "
        zmodload zsh/datetime
        export NIVUUS_SHELL_DIR='$ROOT'
        export NIVUUS_NO_COMPILE=1
        local total=0 i start end
        for i in {1..5}; do
            start=\$EPOCHREALTIME
            source '$ROOT/.zshrc' >/dev/null 2>&1
            end=\$EPOCHREALTIME
            total=\$(( total + (end - start) * 1000 ))
        done
        printf '%d' \$(( total / 5 ))
    "
}

@test "CRITICAL: startup stays under 300ms with no bytecode at all" {
    [ -z "${CI:-}" ] || skip "mesure de temps non fiable sur runner partagé (voir bin/benchmark en local)"
    local ms
    ms="$(startup_ms_no_zwc)"
    echo "startup sans .zwc : ${ms}ms (budget : 300ms)"
    [ "$ms" -lt 300 ]
}

@test "the measured figure is recorded in doc/PACKAGING.md" {
    # La spec fait de la mesure un LIVRABLE, pas un exercice : le chiffre
    # doit être publié, daté et attribué à une plateforme.
    grep -q 'sans bytecode' "$ROOT/doc/PACKAGING.md"
    grep -qE '[0-9]+ *ms' "$ROOT/doc/PACKAGING.md"
}

@test "no .zwc is committed to the repository" {
    run git -C "$ROOT" ls-files '*.zwc'
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/performance/test_startup_without_zwc.bats`
Expected: FAIL — `doc/PACKAGING.md` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Exécuter les mesures ci-dessus, **puis** consigner les chiffres réels (ne pas recopier ceux d'exemple : les remplacer par ce que la machine dit).

```markdown
<!-- doc/PACKAGING.md — section « Coût de démarrage sans bytecode » -->
# Empaquetage de Nivuus

## Coût de démarrage sans bytecode

Un paquet ne livre aucun `.zwc` et n'en compile aucun (voir « Pourquoi »
ci-dessous). L'arbre partagé n'est donc **jamais** compilé, et le budget de
démarrage de 300 ms doit tenir sans bytecode.

**Mesure du <!-- AAAA-MM-JJ -->** (`./bin/benchmark`, moyenne de 5 démarrages) :

| Cible | Avec `.zwc` | Sans `.zwc` | Écart |
|---|---|---|---|
| poste de développement (<!-- distro, version de zsh -->) | <!-- … --> ms | <!-- … --> ms | <!-- … --> ms |
| `debian:12` | | | |
| `ubuntu:22.04` | | | |
| `ubuntu:24.04` | | | |
| `archlinux:latest` | | | |
| `alpine:3.20` | | | |
| `fedora:40` | | | |

**Décision prise sur ce chiffre :** <!-- « sous 150 ms : rien à faire »,
« 150-250 ms : veille », ou « au-dessus : repli livré, voir Task A8bis ». -->

Le garde-fou automatique est `tests/performance/test_startup_without_zwc.bats` :
il échoue si le mode paquet repasse au-dessus du budget.

### Pourquoi aucun `.zwc` dans les paquets

- Un `.zwc` porte une version de format. Compilé sur le runner de build avec
  une version de zsh, il peut être inutilisable sur la machine cible : un
  bytecode ignoré est au mieux inutile, au pire un bug rapporté comme
  « Nivuus ne charge pas mon module ».
- Un paquet dont le contenu dépend de la version de zsh du runner de build
  n'est plus `Architecture: all` en pratique.
- Sous `/usr/share`, un shell **root** réussirait l'écriture et laisserait des
  orphelins qu'`apt purge` ne nettoie pas — une trace, alors que le projet
  promet l'absence de trace.

### Repli conçu, livré seulement si le chiffre l'exige

Compiler dans un cache **par utilisateur**,
`${XDG_CACHE_HOME:-$HOME/.cache}/nivuus-shell/zwc/<version-zsh>/<version-nivuus>/`,
et **sourcer explicitement le `.zwc`** — zsh sait sourcer un `.zwc`
directement, ce qui contourne la règle « le bytecode doit être à côté du
source ». Le cache est inscriptible, versionné sur les deux axes qui peuvent
l'invalider, et sa suppression est déjà couverte par `nivuus uninstall --purge`.
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/performance/test_startup_without_zwc.bats
bats tests/performance/
./bin/benchmark | sed -n '/^Average/p'
```
Expected: PASS — 3 nouveaux tests ; `tests/performance/` passe de 10 à 13 tests, toujours 0 échec.

- [ ] **Step 5: Commit**

```bash
git add doc/PACKAGING.md tests/performance/test_startup_without_zwc.bats
git commit -m "perf(packaging): measure and record startup cost without bytecode"
```

---

### Task A9: `nivuus enable` / `nivuus disable`, et la surcharge en mode paquet

**Files:**
- Modify: `bin/nivuus` (`usage`, `cmd_enable`, `cmd_disable`, `cmd_install`, `cmd_uninstall`, `main`)
- Modify: `lib/manifest.sh` (ajout de `nivuus_manifest_rollback_activation`)
- Test: `tests/unit/test_manifest_rollback_activation.bats`
- Test: `tests/e2e/test_enable_disable.bats`

**Interfaces:**
- Consumes: `nivuus_origin_is_package` (A1), le bloc gardé (A3).
- Produces: deux verbes publics, et le tableau de comportements de la spec § 2.3 :

| Commande | En mode source | En mode paquet |
|---|---|---|
| `nivuus install` | inchangé (copie l'arbre + écrit le bloc) | **équivaut à `enable`** : n'écrit que le bloc, et le dit |
| `nivuus enable` | écrit le bloc `.zshrc` (+ `chsh` optionnel), sans copier d'arbre | identique |
| `nivuus disable` | retire le bloc, laisse l'arbre | identique |
| `nivuus uninstall` | inchangé | équivaut à `disable` + la phrase sur les fichiers du gestionnaire |

**Pourquoi surcharger `install` plutôt qu'exiger le nouveau verbe :** un utilisateur qui vient de taper `brew install nivuus-shell` tapera `nivuus install`. Lui répondre « commande invalide » serait une friction gratuite, dans un programme dont le nom est « friction zéro ». Les verbes explicites existent pour les scripts, la documentation et les `caveats`, où l'ambiguïté coûte plus que la verbosité.

**Ce que `disable` ne fait pas :** il ne supprime jamais l'arbre, même en mode source (c'est le travail d'`uninstall`), et il n'appelle jamais le gestionnaire de paquets.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_manifest_rollback_activation.bats
#!/usr/bin/env bats
# « disable » ne rejoue QUE la part activation du manifeste (le bloc .zshrc
# et le chsh), jamais les fichiers de l'arbre.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/zshrc.sh"; . "$ROOT/lib/manifest.sh"
    NIVUUS_ROLLBACK_SURVIVORS="$(mktemp)"
    NIVUUS_KEPT_BACKUP_REFS="$(mktemp)"
}

teardown() { rm -rf "$TMP"; rm -f "$NIVUUS_ROLLBACK_SURVIVORS" "$NIVUUS_KEPT_BACKUP_REFS"; }

@test "activation rollback restores .zshrc and leaves tree files alone" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    mkdir -p "$HOME/tree"
    printf 'shared\n' > "$HOME/tree/file"

    nivuus_manifest_begin user "$HOME/tree"
    printf '%s\n' "$(nivuus_zshrc_block "$HOME/tree")" > "$TMP/block"
    { cat "$TMP/block"; cat "$HOME/.zshrc"; } | nivuus_write_file "$HOME/.zshrc"
    nivuus_manifest_record CREATE "$HOME/tree/file" "$(nivuus_hash_file "$HOME/tree/file")" '-'
    nivuus_manifest_commit

    nivuus_manifest_rollback_activation

    run cat "$HOME/.zshrc"
    [ "$output" = "export MINE=1" ]
    # L'arbre n'a PAS été touché : c'est la propriété centrale de disable.
    [ -f "$HOME/tree/file" ]
}

@test "activation rollback drops the replayed entries from the manifest" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    mkdir -p "$HOME/tree"; printf 'shared\n' > "$HOME/tree/file"
    nivuus_manifest_begin user "$HOME/tree"
    { nivuus_zshrc_block "$HOME/tree"; cat "$HOME/.zshrc"; } | nivuus_write_file "$HOME/.zshrc"
    nivuus_manifest_record CREATE "$HOME/tree/file" "$(nivuus_hash_file "$HOME/tree/file")" '-'
    nivuus_manifest_commit

    nivuus_manifest_rollback_activation

    run grep -c 'MODIFY' "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
    run grep -c 'CREATE' "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "activation rollback on an empty manifest is a no-op, not an error" {
    run nivuus_manifest_rollback_activation
    [ "$status" -eq 0 ]
}
```

```bash
# tests/e2e/test_enable_disable.bats
#!/usr/bin/env bats
# L'activation est un acte PAR UTILISATEUR, et c'est le seul acte journalisé
# au manifeste quand l'arbre appartient à un gestionnaire de paquets.

load '../helpers/fingerprint'

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # Arbre « partagé » posé à la main : aucun gestionnaire de paquets requis.
    SHARED="$TMP/share/nivuus-shell"
    mkdir -p "$SHARED"
    cp -a "$ROOT"/config "$ROOT"/themes "$ROOT"/lib "$ROOT"/bin "$ROOT"/keys "$SHARED"/ 2>/dev/null || true
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    NIVUUS="$SHARED/bin/nivuus"
}

teardown() { rm -rf "$TMP"; }

pkg_marker() {
    printf 'origin=package\nchannel=%s\npackage=nivuus-shell\nversion=3.2.0\n' \
        "${1:-deb}" > "$SHARED/.nivuus-origin"
}

@test "enable writes the block and nothing else" {
    pkg_marker
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    grep -qF "$SHARED" "$HOME/.zshrc"
}

@test "enable copies NO tree: the manifest has no CREATE entry" {
    pkg_marker
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run grep -c 'CREATE' "$NIVUUS_STATE_DIR/manifest.tsv"
    [ "$status" -ne 0 ]
}

@test "INVARIANT: enable then disable leaves HOME bit-identical" {
    pkg_marker
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "disable never touches the shared tree" {
    pkg_marker
    fs_fingerprint "$SHARED" > "$TMP/tree_before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    fs_fingerprint "$SHARED" > "$TMP/tree_after"
    run diff "$TMP/tree_before" "$TMP/tree_after"
    [ "$status" -eq 0 ]
}

@test "install on a package tree behaves as enable and says so" {
    pkg_marker homebrew
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" install --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    # Aucun arbre recopié dans le HOME : le paquet possède déjà le sien.
    [ ! -d "$HOME/.nivuus-shell" ]
    [[ "$output" == *"activ"* ]]
}

@test "uninstall on a package tree says the shared files were not touched" {
    pkg_marker homebrew
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew uninstall"* ]]
    [ -f "$SHARED/.zshrc" ]
}

@test "uninstall on a package tree never invokes the package manager" {
    # Appeler « sudo apt remove » depuis nivuus uninstall violerait la règle
    # « aucun sudo non demandé » au moment où l'utilisateur est le moins
    # attentif.
    run grep -nE 'sudo (apt|pacman|dpkg)|brew (uninstall|remove) [^"]*\$' "$ROOT/bin/nivuus"
    [ "$status" -ne 0 ]
}

@test "enable is idempotent: twice yields one block" {
    pkg_marker
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "enable in SOURCE mode works too (no tree copy, block only)" {
    # Utile pour ré-écrire un bloc perdu sans réinstaller l'arbre.
    rm -f "$SHARED/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
}

@test "disable with no manifest says so and exits 0" {
    pkg_marker
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bats tests/unit/test_manifest_rollback_activation.bats tests/e2e/test_enable_disable.bats
```
Expected: FAIL — `nivuus_manifest_rollback_activation` et les sous-commandes `enable`/`disable` n'existent pas.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/manifest.sh`, à côté de `nivuus_manifest_rollback` :

```sh
# Rejoue UNIQUEMENT la part « activation » du manifeste : le bloc délimité
# d'un fichier de l'utilisateur (MODIFY) et le shell de connexion (CHSH).
# Les entrées CREATE / MKDIR / PKG -- l'arbre et ses dépendances -- ne sont
# jamais rejouées : en mode paquet elles n'existent pas, et en mode source
# c'est le travail d'« uninstall », pas de « disable ».
#
# Les entrées effectivement rejouées sont RETIRÉES du manifeste : sans cela,
# un « uninstall » ultérieur tenterait de restaurer une sauvegarde déjà
# consommée et signalerait à tort un fichier divergé.
nivuus_manifest_rollback_activation() {
    local filtered kept header
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    header="$(head -n1 "$NIVUUS_MANIFEST")"
    filtered="$(mktemp)"
    kept="$(mktemp)"
    awk -F"$NIVUUS_TAB" '$1=="MODIFY" || $1=="CHSH"' "$NIVUUS_MANIFEST" > "$filtered"
    awk -F"$NIVUUS_TAB" '!/^#/ && $1!="MODIFY" && $1!="CHSH"' "$NIVUUS_MANIFEST" > "$kept"

    nivuus_manifest_each nivuus_restore_entry "$filtered"

    if [ -z "${NIVUUS_DRY_RUN:-}" ]; then
        # Les entrées que le rejeu n'a PAS pu appliquer (fichier divergé,
        # sauvegarde absente) sont des survivants : elles doivent rester au
        # manifeste, exactement comme dans cmd_uninstall.
        {
            printf '%s\n' "$header"
            cat "$kept"
            [ -s "${NIVUUS_ROLLBACK_SURVIVORS:-/dev/null}" ] && cat "$NIVUUS_ROLLBACK_SURVIVORS"
        } > "$NIVUUS_MANIFEST"
    fi
    rm -f "$filtered" "$kept"
    return 0
}
```

Dans `bin/nivuus` : refactoriser la partie « écriture du bloc » de `cmd_install` en une fonction partagée, ajouter les deux verbes, brancher la surcharge.

```bash
# Écrit le bloc .zshrc (et propose chsh) SANS copier d'arbre. C'est le seul
# acte journalisé au manifeste quand l'arbre appartient à un gestionnaire de
# paquets : l'activation est, et reste, un acte par utilisateur.
cmd_enable() {
    local prefix="${NIVUUS_SHELL_DIR:-$NIVUUS_SRC_ROOT}" MINIMAL='' FORCE_MINIMAL='' FORCE_FULL=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) export NIVUUS_DRY_RUN=1 ;;
            --yes|-y)  ASSUME_YES=1 ;;
            --minimal)    FORCE_MINIMAL=1 ;;
            --no-minimal) FORCE_FULL=1 ;;
            --prefix)
                shift
                [ $# -gt 0 ] || { log_error "L'option --prefix attend un chemin."; return 2; }
                prefix="$1" ;;
            *) log_error "Option inconnue : $1"; return 2 ;;
        esac
        shift
    done

    if [ ! -r "$prefix/.zshrc" ]; then
        log_error "Aucun arbre Nivuus lisible dans $prefix."
        log_error "Installe d'abord Nivuus (paquet ou installeur), puis relance « nivuus enable »."
        return 1
    fi

    if [ -n "${FORCE_FULL:-}" ]; then
        MINIMAL=''; export NIVUUS_NO_MINIMAL=1
    elif [ -n "${FORCE_MINIMAL:-}" ]; then
        MINIMAL=1; export NIVUUS_MINIMAL=1
    elif nivuus_should_minimal; then
        MINIMAL=1
    fi

    confirm "Activer Nivuus Shell dans ton shell (bloc ajouté à ~/.zshrc) ?" \
        || { log_info "Annulé."; return 0; }

    nivuus_manifest_begin user "$prefix"
    nivuus_manifest_inherit
    if ! nivuus_step_write_zshrc "$HOME/.zshrc" "$prefix" "$MINIMAL"; then
        log_error "Activation interrompue."
        nivuus_manifest_abort
        return 1
    fi
    if [ -z "${MINIMAL:-}" ]; then
        if confirm "Faire de zsh ton shell de connexion ?"; then
            nivuus_step_chsh
        else
            log_info "Shell de connexion inchangé."
        fi
    fi
    nivuus_manifest_commit

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_info "Aucune modification effectuée (--dry-run)."
    else
        log_ok "Nivuus Shell activé pour cet utilisateur ($prefix)."
        log_info "Lance « exec zsh » pour démarrer."
    fi
}

# Retire le bloc et restaure le shell de connexion. Ne touche JAMAIS à
# l'arbre : en mode paquet il appartient au gestionnaire, en mode source
# c'est le travail d'« uninstall ».
cmd_disable() {
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
        log_info "Aucune activation Nivuus tracée ; rien à faire."
        return 0
    fi

    confirm "Désactiver Nivuus pour cet utilisateur (le bloc de ~/.zshrc est retiré) ?" \
        || { log_info "Annulé."; return 0; }

    NIVUUS_ROLLBACK_SURVIVORS="$(mktemp)"
    NIVUUS_KEPT_BACKUP_REFS="$(mktemp)"
    nivuus_manifest_rollback_activation
    rm -f "$NIVUUS_ROLLBACK_SURVIVORS" "$NIVUUS_KEPT_BACKUP_REFS"

    if [ -n "$purge" ] && [ -z "${NIVUUS_DRY_RUN:-}" ]; then
        # Artefacts d'exécution, reconnus par leur nom exact -- jamais par un
        # motif large, jamais de rm -rf sur un répertoire partagé.
        rm -f "$HOME/.nivuus-shell-last-update-check"
        if [ -d "$HOME/.cache/nivuus-shell" ]; then
            find "$HOME/.cache/nivuus-shell" -type f -exec rm -f {} + 2>/dev/null || true
            find "$HOME/.cache/nivuus-shell" -depth -type d -exec rmdir {} + 2>/dev/null || true
        fi
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_info "Aucune modification effectuée (--dry-run)."
    else
        log_ok "Nivuus Shell désactivé pour cet utilisateur."
        log_info "L'arbre Nivuus n'a pas été touché."
    fi
}
```

Surcharge dans `cmd_install`, tout au début du corps (après l'analyse des options, avant `nivuus_manifest_begin`) :

```bash
    # Mode paquet : l'arbre appartient au gestionnaire, « install » ne peut
    # donc rien copier. Plutôt que de répondre « commande invalide » à un
    # utilisateur qui vient de taper « brew install nivuus-shell », on fait
    # ce qu'il voulait -- activer -- et on le dit (spec § 2.3).
    if nivuus_origin_is_package "${NIVUUS_SHELL_DIR:-$NIVUUS_SRC_ROOT}"; then
        log_info "Nivuus est déjà installé pour la machine par ton gestionnaire de paquets."
        log_info "« install » se limite donc à l'activation pour cet utilisateur."
        cmd_enable "$@"
        return $?
    fi
```

Surcharge dans `cmd_uninstall`, juste avant le `log_ok` final :

```bash
    if nivuus_origin_is_package "${NIVUUS_SHELL_DIR:-$NIVUUS_SRC_ROOT}"; then
        log_info "Les fichiers partagés appartiennent à ton gestionnaire de paquets et n'ont pas été touchés."
        log_info "Pour les retirer aussi :  $(nivuus_origin_update_command_remove "${NIVUUS_SHELL_DIR:-$NIVUUS_SRC_ROOT}")"
    fi
```

Ce qui demande une fonction de plus dans `lib/origin.sh` (ajoutée ici, testée par le test e2e ci-dessus qui attend `brew uninstall`) :

```sh
nivuus_origin_update_command_remove() {
    local dir="$1" channel pkg
    channel="$(nivuus_origin_channel "$dir")"
    pkg="$(nivuus_origin_field "$dir" package 2>/dev/null || printf 'nivuus-shell')"
    case "$channel" in
        homebrew) printf 'brew uninstall %s\n' "$pkg" ;;
        aur)      printf 'sudo pacman -Rns %s\n' "$pkg" ;;
        deb)      printf 'sudo apt purge %s\n' "$pkg" ;;
        *)        printf '%s\n' "retire le paquet avec ton gestionnaire" ;;
    esac
}
```

Enfin, `main` et `usage` :

```bash
        install)   cmd_install "$@" ;;
        enable)    cmd_enable "$@" ;;
        disable)   cmd_disable "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
```

```
  nivuus enable    [--dry-run] [--yes] [--prefix DIR] [--minimal|--no-minimal]
  nivuus disable   [--dry-run] [--yes] [--purge]
...
  enable      Active Nivuus pour CET utilisateur : ajoute le bloc délimité à
              ~/.zshrc (et propose chsh). Ne copie aucun fichier : c'est la
              commande à utiliser après une installation par paquet.
  disable     Retire le bloc de ~/.zshrc et restaure le shell de connexion.
              L'arbre Nivuus n'est jamais touché.
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_manifest_rollback_activation.bats
bats tests/e2e/test_enable_disable.bats
bats tests/unit/test_lib_manifest_*.bats tests/unit/test_lib_origin.bats
bats tests/e2e/test_reversibility.bats tests/e2e/test_installation.bats tests/e2e/test_nivuus_cli.bats
bats tests/unit/test_lib_posix.bats
```
Expected: PASS — 3 + 10 nouveaux tests ; la réversibilité et l'installation classique restent vertes.

- [ ] **Step 5: Commit**

```bash
git add bin/nivuus lib/manifest.sh lib/origin.sh \
        tests/unit/test_manifest_rollback_activation.bats \
        tests/e2e/test_enable_disable.bats
git commit -m "feat(cli): add nivuus enable/disable and overload install in package mode"
```

---

### Task A10: `doctor` apprend le mode paquet

**Files:**
- Modify: `bin/healthcheck`
- Test: `tests/e2e/test_doctor_package.bats`

**Interfaces:**
- Consumes: `lib/origin.sh` (A1), la garde du bloc (A3).
- Produces: l'affichage de l'origine, du canal, de la version du paquet et de l'état d'activation, plus le diagnostic des trois nouveaux cas.

C'est la contrepartie de la Task A3 : la garde **masque** une installation cassée au lieu de la signaler. Le silence au démarrage doit être payé par un diagnostic à la demande.

Trois cas, et **aucun n'est réparé automatiquement** — `doctor` diagnostique, il n'agit pas (règle déjà appliquée au dépôt git hérité) :

1. **bloc présent, arbre absent** — la garde a fait son travail, le shell est silencieux, mais Nivuus ne se charge plus. Réparation : réinstaller le paquet, ou `nivuus disable` pour retirer le bloc.
2. **paquet installé, jamais activé** — `nivuus enable`.
3. **arbre paquet altéré** — renvoyer vers `dpkg -V` / `pacman -Qkk` / `brew reinstall`, sans réparer soi-même.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_doctor_package.bats
#!/usr/bin/env bats
# doctor doit NOMMER la situation en mode paquet : la garde du bloc rend le
# démarrage silencieux, donc le diagnostic à la demande est le seul endroit
# où une installation cassée devient visible.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    SHARED="$TMP/share/nivuus-shell"
    mkdir -p "$SHARED"
    cp -a "$ROOT"/config "$ROOT"/lib "$ROOT"/bin "$SHARED"/
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    DOCTOR="$SHARED/bin/healthcheck"
}

teardown() { rm -rf "$TMP"; }

pkg_marker() {
    printf 'origin=package\nchannel=%s\npackage=nivuus-shell\nversion=3.2.0\n' \
        "${1:-homebrew}" > "$SHARED/.nivuus-origin"
}

block() {
    printf '# >>> nivuus shell >>>\nexport NIVUUS_SHELL_DIR="%s"\n[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"\n# <<< nivuus shell <<<\n' \
        "$1" > "$HOME/.zshrc"
}

@test "doctor reports origin source when there is no marker" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"source"* ]]
}

@test "doctor reports the channel and the package version" {
    pkg_marker aur
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"aur"* ]]
    [[ "$output" == *"3.2.0"* ]]
}

@test "doctor names 'package installed, never activated'" {
    pkg_marker
    : > "$HOME/.zshrc"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"nivuus enable"* ]]
}

@test "doctor names 'block present, tree gone' and gives the way out" {
    pkg_marker deb
    block "$TMP/share/nivuus-shell"
    rm -rf "$SHARED"
    run env NIVUUS_SHELL_DIR="$TMP/share/nivuus-shell" "$ROOT/bin/healthcheck"
    [[ "$output" == *"nivuus disable"* ]] || [[ "$output" == *"réinstall"* ]]
}

@test "doctor points at the package manager for a tampered tree, and repairs nothing" {
    pkg_marker homebrew
    block "$SHARED"
    printf 'tampered\n' >> "$SHARED/config/00-core.zsh"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"brew"* ]] || [[ "$output" == *"reinstall"* ]]
    # Rien n'a été réparé : le fichier altéré est toujours là, tel quel.
    grep -q 'tampered' "$SHARED/config/00-core.zsh"
}

@test "doctor mentions that auto-update is disabled in package mode" {
    pkg_marker deb
    block "$SHARED"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"apt"* ]]
}

@test "doctor exits 0 on a healthy package install" {
    pkg_marker homebrew
    block "$SHARED"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_doctor_package.bats`
Expected: FAIL — `doctor` ne connaît pas le marqueur.

- [ ] **Step 3: Write minimal implementation**

Dans `bin/healthcheck`, dans la section « Nivuus Shell », après l'affichage de `Location:` :

```bash
# Origine de l'installation : information, jamais réparation. Le marqueur est
# posé par la recette de paquet ; son absence vaut « source », c'est-à-dire le
# comportement historique.
NIVUUS_ORIGIN_LIB="$NIVUUS_DIR/lib/origin.sh"
[[ -r "$NIVUUS_ORIGIN_LIB" ]] || NIVUUS_ORIGIN_LIB="$(dirname "$0")/../lib/origin.sh"
if [[ -r "$NIVUUS_ORIGIN_LIB" ]]; then
    # shellcheck source=/dev/null
    . "$NIVUUS_ORIGIN_LIB"
    origin="$(nivuus_origin "$NIVUUS_DIR")"
    echo "  Origine: $origin"
    if [[ "$origin" == "package" ]]; then
        echo "  Canal: $(nivuus_origin_channel "$NIVUUS_DIR")"
        echo "  Version du paquet: $(nivuus_origin_field "$NIVUUS_DIR" version 2>/dev/null || echo inconnue)"
        echo -e "  ${INFO} Mises à jour automatiques désactivées : c'est le gestionnaire qui les gère."
        echo "     $(nivuus_origin_update_command "$NIVUUS_DIR")"
        if ! nivuus_origin_tree_writable "$NIVUUS_DIR"; then
            echo -e "  ${CHECK} Arbre en lecture seule (attendu pour un paquet)."
        fi
    fi
fi

# Cas 1 : bloc présent, arbre absent. La garde du bloc rend ce cas SILENCIEUX
# au démarrage (c'est voulu : un brew uninstall ne doit casser le shell de
# personne). C'est donc ici, et seulement ici, qu'il devient visible.
if [[ -f "$HOME/.zshrc" ]] && grep -q '>>> nivuus shell >>>' "$HOME/.zshrc" 2>/dev/null; then
    if [[ ! -r "$NIVUUS_DIR/.zshrc" ]]; then
        echo -e "  ${WARN} Bloc Nivuus présent dans ~/.zshrc, mais aucun arbre lisible dans $NIVUUS_DIR."
        echo "     Ton shell démarre sans erreur (la garde du bloc fait son travail) mais Nivuus ne se charge pas."
        echo "     Réinstalle Nivuus, ou retire le bloc :  nivuus disable"
    fi
# Cas 2 : paquet installé, jamais activé.
elif [[ -r "$NIVUUS_DIR/.zshrc" ]]; then
    echo -e "  ${WARN} Nivuus est installé mais n'est pas activé pour cet utilisateur."
    echo "     Pour l'activer :  nivuus enable"
fi

# Cas 3 : arbre paquet altéré. On NE répare PAS -- le gestionnaire est
# autoritatif sur son domaine, et lui seul sait remettre l'arbre en état.
if [[ -r "$NIVUUS_DIR/.nivuus-origin" ]] && command -v nivuus_origin_channel >/dev/null 2>&1; then
    case "$(nivuus_origin_channel "$NIVUUS_DIR")" in
        deb)      echo "  Vérifier l'intégrité de l'arbre :  dpkg -V nivuus-shell" ;;
        aur)      echo "  Vérifier l'intégrité de l'arbre :  pacman -Qkk nivuus-shell" ;;
        homebrew) echo "  Vérifier l'intégrité de l'arbre :  brew reinstall nivuus-shell" ;;
    esac
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/e2e/test_doctor_package.bats
bats tests/e2e/test_healthcheck.bats tests/e2e/test_doctor_signature.bats
```
Expected: PASS — 7 nouveaux tests, aucune régression.

- [ ] **Step 5: Commit**

```bash
git add bin/healthcheck tests/e2e/test_doctor_package.bats
git commit -m "feat(doctor): diagnose package mode, orphan block and tampered tree"
```

---

### Task A11: page de manuel `nivuus.1`

**Files:**
- Create: `doc/nivuus.1`
- Modify: `lib/steps.sh` (copier `doc/nivuus.1` dans l'arbre installé)
- Test: `tests/unit/test_manpage.bats`

**Interfaces:**
- Consumes: la sortie de `nivuus help` (source de vérité du contenu).
- Produces: `doc/nivuus.1`, installé dans `/usr/share/man/man1/` par les trois formats en partie B.

C'est le **seul fichier réellement nouveau** que ce chantier ajoute à l'arbre. Motif immédiat : `lintian` signalera `binary-without-manpage` sur le `.deb` (Task B6), et une page de manuel écrite après coup, sous la pression d'un avertissement, est une page de manuel fausse. On l'écrit ici, avec un test qui la maintient synchronisée avec `nivuus help`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_manpage.bats
#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    MAN="$ROOT/doc/nivuus.1"
}

@test "the man page exists" { [ -f "$MAN" ]; }

@test "the man page is section 1 and names the command" {
    head -n5 "$MAN" | grep -q '^\.TH NIVUUS 1'
}

@test "the man page renders without groff warnings" {
    command -v groff >/dev/null || skip "groff absent"
    run groff -man -Tascii -ww "$MAN"
    [ "$status" -eq 0 ]
    [[ "$output" != *"warning"* ]]
}

@test "every subcommand of nivuus help is documented in the man page" {
    # Le garde-fou anti-dérive : une sous-commande ajoutée sans sa ligne de
    # manuel fait échouer ce test, pas un rapport d'utilisateur six mois plus tard.
    for cmd in install uninstall enable disable migrate update doctor help; do
        grep -q "^\.B $cmd$" "$MAN" || {
            echo "sous-commande absente du manuel : $cmd"
            return 1
        }
    done
}

@test "the man page documents that package installs disable auto-update" {
    grep -qi 'paquet' "$MAN"
    grep -q 'nivuus enable' "$MAN"
}

@test "the man page is copied into an installed tree" {
    grep -q 'nivuus.1' "$ROOT/lib/steps.sh"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_manpage.bats`
Expected: FAIL — `doc/nivuus.1` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```roff
.\" doc/nivuus.1 — page de manuel de l'outil de gestion de Nivuus Shell.
.\" Source de vérité du contenu : la sortie de « nivuus help ».
.TH NIVUUS 1 "2026-08-21" "Nivuus Shell" "Manuel de l'utilisateur"
.SH NOM
nivuus \- gestion de Nivuus Shell
.SH SYNOPSIS
.B nivuus
.I sous-commande
.RI [ options ]
.SH DESCRIPTION
.B nivuus
installe, active, met à jour et retire Nivuus Shell, un environnement ZSH
sans configuration.
.PP
Nivuus distingue deux domaines qui ne se recouvrent jamais : l'arbre partagé
(installé par un gestionnaire de paquets ou par l'installeur) et le domaine
de l'utilisateur (le bloc délimité de
.IR ~/.zshrc ,
le shell de connexion, l'état sous
.IR ~/.local/state/nivuus ).
Toute écriture dans le second est journalisée et réversible à l'octet près.
.SH SOUS-COMMANDES
.TP
.B install
Installe l'arbre Nivuus et l'active pour l'utilisateur courant. Lorsque
Nivuus a été installé par un gestionnaire de paquets, cette commande se
limite à l'activation (équivalente à
.BR enable ).
.TP
.B enable
Active Nivuus pour l'utilisateur courant : ajoute le bloc délimité à
.I ~/.zshrc
et propose de changer le shell de connexion. Ne copie aucun fichier.
.TP
.B disable
Retire le bloc de
.I ~/.zshrc
et restaure le shell de connexion. L'arbre Nivuus n'est jamais touché.
.TP
.B uninstall
Rejoue le journal d'installation et restaure la configuration d'origine.
Ne supprime jamais un fichier appartenant à un gestionnaire de paquets.
.TP
.B update
Met à jour Nivuus depuis la dernière release signée. Lorsque Nivuus provient
d'un paquet, affiche la commande du gestionnaire et sort en 0 sans rien
télécharger.
.TP
.B migrate
Met de côté le dépôt git que l'installeur de la v3.0.0 laissait dans
.IR ~/.nivuus-shell .
Le dépôt est déplacé, jamais supprimé.
.TP
.B doctor
Diagnostic complet : origine de l'installation, canal, version, état de
l'activation, dépendances. Ne répare rien.
.TP
.B help
Affiche l'aide.
.SH OPTIONS
.TP
.B \-\-dry\-run
N'écrit rien ; affiche ce qui serait fait.
.TP
.B \-\-yes
Ne pose aucune question.
.TP
.BI \-\-prefix " RÉPERTOIRE"
Répertoire d'installation (défaut :
.IR ~/.nivuus\-shell ).
.TP
.B \-\-minimal
Mode serveur ou conteneur : pas de changement de shell, pas d'extras.
.TP
.B \-\-with\-deps
Propose une commande groupée pour installer les dépendances recommandées.
.TP
.BI \-\-verify\-key " EMPREINTE"
Empreinte attendue du jeu de clés de signature embarqué. Si elle ne
correspond pas, l'installation est refusée avant toute écriture.
.TP
.B \-\-purge
Pour
.B uninstall
et
.BR disable :
supprime aussi l'état Nivuus. Ne supprime que ce que Nivuus a créé.
.SH INSTALLATIONS PAR PAQUET
Lorsque Nivuus provient d'un gestionnaire de paquets, l'arbre partagé porte
un fichier
.I .nivuus\-origin
et la mise à jour automatique est désactivée : c'est le gestionnaire qui
gère les versions. L'activation reste un acte par utilisateur
.RB ( nivuus " " enable ),
et c'est le seul acte journalisé.
.SH FICHIERS
.TP
.I ~/.zshrc
Contient le bloc délimité Nivuus, gardé : si l'arbre disparaît, le shell
démarre sans erreur.
.TP
.I ~/.zsh_local
Personnalisations de l'utilisateur. Jamais écrit ni supprimé par Nivuus.
.TP
.I ~/.local/state/nivuus/manifest.tsv
Journal des mutations, base de la réversibilité.
.TP
.I $NIVUUS_SHELL_DIR/.nivuus\-origin
Marqueur d'origine posé par une recette de paquet. Son absence vaut
.IR origin=source .
.SH VOIR AUSSI
La documentation complète du projet, notamment
.I doc/INSTALL.md
et
.IR doc/PACKAGING.md .
.SH AUTEUR
Maxime Allanic.
```

Dans `lib/steps.sh`, ajouter `doc/nivuus.1` aux fichiers copiés — **sans réécrire** `nivuus_step_copy_tree`, dont la forme actuelle est délibérée :

```sh
    # Fichiers à la racine.
    for f in .zshrc .vimrc.nord; do
        if [ -f "$src/$f" ]; then
            nivuus_install_file "$src/$f" "$dst/$f" || return 1
        fi
    done
    # Page de manuel : installée dans /usr/share/man/man1 par les paquets,
    # simplement copiée avec l'arbre pour une installation par l'installeur.
    if [ -f "$src/doc/nivuus.1" ]; then
        nivuus_install_file "$src/doc/nivuus.1" "$dst/doc/nivuus.1" || return 1
    fi
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_manpage.bats
bats tests/unit/test_lib_steps.bats tests/e2e/test_reversibility.bats
bats tests/unit/test_markdown.bats
```
Expected: PASS — 6 nouveaux tests ; la réversibilité reste verte (le fichier est copié via `nivuus_install_file`, donc journalisé).

- [ ] **Step 5: Commit**

```bash
git add doc/nivuus.1 lib/steps.sh tests/unit/test_manpage.bats
git commit -m "docs(man): add nivuus.1 and install it with the tree"
```

---

### Task A12: preuve e2e du mode paquet, **sans aucun gestionnaire de paquets**

**Files:**
- Create: `tests/e2e/test_package_mode.bats`

**Interfaces:**
- Consumes: A1 à A9.
- Produces: la sortie de la phase 0 telle que la spec la définit — « un arbre posé à la main sous `/usr/share` avec un `.nivuus-origin` se comporte déjà correctement ; c'est un test e2e, sans aucun gestionnaire de paquets ».

**Cette tâche porte les deux invariants du chantier.** Ils sont ici exercés sans `dpkg`, sans `pacman` et sans `brew` : la Task B7 les rejouera à l'identique **avec** les vrais gestionnaires, mais ils doivent déjà être verts sur une PR, sur n'importe quel runner, en moins de dix secondes.

1. **Invariant n° 1** — trois shells interactifs sur une installation `origin=package`, puis `~/.nivuus-shell-last-update-check` **n'existe pas**. C'est la preuve observable que `_nivuus_check_update_async` ne s'est jamais exécuté.
2. **Invariant n° 2** — paquet retiré alors que l'activation subsiste ⇒ **stderr vide** à l'ouverture d'un shell interactif. C'est ce qui paie la garde du bloc.

Si ces deux-là passent, la propriété existe ; s'ils manquent, le reste est décoratif. D'où le garde-fou `grep` de la Task A13.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_package_mode.bats
#!/usr/bin/env bats
# La sortie de la phase 0 : un arbre posé À LA MAIN sous un préfixe partagé,
# avec un .nivuus-origin, se comporte déjà comme un paquet -- sans dpkg, sans
# pacman, sans brew. Les deux INVARIANT: ci-dessous sont les propriétés
# centrales du chantier ; tests.yml vérifie par grep qu'ils n'ont pas disparu.

load '../helpers/fingerprint'

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    command -v zsh >/dev/null || skip "zsh absent"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    SHARED="$TMP/usr/share/nivuus-shell"
    mkdir -p "$SHARED"
    # Copie bit-pour-bit de l'arbre de release : aucune disposition
    # spécifique à un canal (spec § 3.3).
    cp -a "$ROOT"/config "$ROOT"/themes "$ROOT"/lib "$ROOT"/bin "$ROOT"/keys "$SHARED"/ 2>/dev/null || true
    cp -a "$ROOT"/doc "$SHARED"/ 2>/dev/null || true
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    rm -f "$SHARED"/config/*.zwc
    printf 'origin=package\nchannel=deb\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$SHARED/.nivuus-origin"
    # Le lien symbolique que pose un PKGBUILD : il doit fonctionner.
    mkdir -p "$TMP/usr/bin"
    ln -s "$SHARED/bin/nivuus" "$TMP/usr/bin/nivuus"
    NIVUUS="$TMP/usr/bin/nivuus"
}

teardown() { rm -rf "$TMP"; }

# Ouvre un vrai shell interactif zsh lisant le ~/.zshrc de ce HOME.
interactive_shell() {
    env HOME="$HOME" NIVUUS_SHELL_DIR="$SHARED" \
        zsh -i -c 'print -r -- OK' 2>"$1"
}

@test "the symlinked nivuus works (PKGBUILD-style ln -s)" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" help
    [ "$status" -eq 0 ]
}

@test "doctor reports origin package and the deb channel" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" doctor
    [[ "$output" == *"package"* ]]
    [[ "$output" == *"deb"* ]]
}

@test "nivuus update prints the manager command, exits 0, downloads nothing" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "INVARIANT: three interactive shells leave no update-check timestamp" {
    # Preuve observable que _nivuus_check_update_async ne s'est JAMAIS
    # exécuté sur une installation par paquet. Si ce fichier apparaît,
    # l'updater destructif a pu partir contre un arbre appartenant à
    # dpkg / pacman / brew : la base du gestionnaire devient fausse et la
    # mise à jour système suivante écrase Nivuus sans prévenir.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    local i
    for i in 1 2 3; do interactive_shell "$TMP/err$i" >/dev/null || true; done
    sleep 2   # laisse une éventuelle tâche &! le temps d'écrire
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "INVARIANT: package removed while the activation remains leaves stderr empty" {
    # Le cas NORMAL, pas le cas dégradé : « brew uninstall » / « apt purge »
    # n'ont aucun moyen de savoir qui a activé quoi. Sans la garde du bloc,
    # ce scénario casse le shell de tous les utilisateurs encore activés, à
    # chaque prompt, sans rapport visible avec l'action faite.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    rm -rf "$TMP/usr"                       # le « paquet » est retiré
    run env HOME="$HOME" zsh -i -c 'print -r -- OK' 2>"$TMP/err"
    [ "$status" -eq 0 ]
    run cat "$TMP/err"
    [ -z "$output" ]
}

@test "an interactive shell on a healthy package install has empty stderr too" {
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    interactive_shell "$TMP/err" >/dev/null
    run cat "$TMP/err"
    [ -z "$output" ]
}

@test "no .zwc is written into the shared tree by an interactive shell" {
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    interactive_shell "$TMP/err" >/dev/null
    sleep 2
    run find "$SHARED" -name '*.zwc'
    [ -z "$output" ]
}

@test "enable then disable leaves HOME bit-identical" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "the manifest contains no CREATE entry in package mode" {
    # La sûreté vient de l'ABSENCE d'entrées, pas d'une exception : la règle
    # « CREATE : suppression seulement si le hash correspond » n'a même pas
    # l'occasion de s'exécuter sur un fichier du gestionnaire.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run grep -c 'CREATE' "$NIVUUS_STATE_DIR/manifest.tsv"
    [ "$status" -ne 0 ]
}

@test "the shared tree is never modified by enable/disable/update/doctor" {
    fs_fingerprint "$SHARED" > "$TMP/tree_before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" update >/dev/null
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" doctor >/dev/null 2>&1 || true
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    fs_fingerprint "$SHARED" > "$TMP/tree_after"
    run diff "$TMP/tree_before" "$TMP/tree_after"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_package_mode.bats`
Expected: si A1–A9 sont mergées, cette suite passe **directement** — c'est un test d'intégration des tâches précédentes, pas d'une nouvelle fonctionnalité. Si un test échoue, **c'est une régression d'une tâche précédente** : ne pas l'affaiblir, corriger la tâche concernée. Pour vérifier que la suite est bien discriminante, la lancer une fois sur un `git stash` de la Task A3 : le test « package removed while the activation remains » doit alors échouer.

- [ ] **Step 3: Write minimal implementation**

Aucune implémentation nouvelle. Si un test échoue, corriger la tâche d'origine (A3 pour la garde, A4 pour l'invariant n° 1, A7 pour les `.zwc`, A9 pour le manifeste) et **rejouer la suite complète** de cette tâche.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/e2e/test_package_mode.bats
bats tests/e2e/
```
Expected: PASS — 10 nouveaux tests ; `tests/e2e/` reste à 0 échec (4 skips préexistants, plus d'éventuels skips liés à l'absence de zsh sur la machine).

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_package_mode.bats
git commit -m "test(package): prove package mode end-to-end without any package manager"
```

---

### Task A13: la CI exécute les nouvelles suites et protège les deux invariants

**Files:**
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: toutes les suites créées par la partie A.
- Produces: exécution sur PR + garde-fou `grep` contre la suppression discrète des invariants.

**Rebaser sur la phase 4 CI avant de commencer** (voir « Point de contact » en tête de plan). Le dépôt possède déjà ce garde-fou pour la signature — étape « The two invariants must be present and green » — et il faut l'**étendre**, pas le dupliquer ailleurs.

Coût CI ajouté : les suites de la partie A sont toutes unitaires ou e2e locales, sans conteneur ni réseau. Ordre de grandeur : moins de 30 secondes. C'est ce qui autorise leur exécution sur chaque PR (le découpage « PR rapide, matrice la nuit » du chantier 1 reste respecté).

- [ ] **Step 1: Write the failing test**

Le test est ici le workflow lui-même. Le rendre vérifiable localement d'abord, en écrivant le script de garde-fou tel qu'il sera appelé :

```bash
# Vérification locale, à exécuter avant de modifier le YAML : elle doit
# ÉCHOUER tant que l'étape n'est pas ajoutée au workflow.
grep -q 'test_package_mode.bats' .github/workflows/tests.yml
```

- [ ] **Step 2: Run test to verify it fails**

Run: `grep -q 'test_package_mode.bats' .github/workflows/tests.yml; echo $?`
Expected: `1` — le workflow ignore les nouvelles suites.

- [ ] **Step 3: Write minimal implementation**

Ajouter, dans le job unitaire (ou celui qui joue `tests/unit/` après la phase 4) :

```yaml
      - name: Packaging core unit suites
        run: |
          # Le bytecode périmé masque la source : une suite qui touche
          # config/*.zsh doit toujours partir d'un arbre non compilé.
          rm -f config/*.zwc
          bats tests/unit/test_lib_origin.bats \
               tests/unit/test_lib_selfpath.bats \
               tests/unit/test_zshrc_block_guard.bats \
               tests/unit/test_autoupdate_package_mode.bats \
               tests/unit/test_autoupdate_readonly_tree.bats \
               tests/unit/test_update_package_message.bats \
               tests/unit/test_cleanup_zwc_ownership.bats \
               tests/unit/test_manifest_rollback_activation.bats \
               tests/unit/test_manpage.bats
```

Puis, dans le job e2e :

```yaml
      - name: Package mode E2E (no package manager involved)
        run: |
          rm -f config/*.zwc
          bats tests/e2e/test_package_mode.bats \
               tests/e2e/test_enable_disable.bats \
               tests/e2e/test_doctor_package.bats \
               tests/e2e/test_nivuus_update_package.bats

      - name: The two packaging invariants must be present and green
        run: |
          # Garde-fou contre une suppression discrète : les tests qui portent
          # les propriétés du chantier ne doivent pas pouvoir disparaître sans
          # que la CI le dise. Même dispositif que pour la signature.
          grep -q "INVARIANT: three interactive shells leave no update-check timestamp" \
            tests/e2e/test_package_mode.bats
          grep -q "INVARIANT: package removed while the activation remains leaves stderr empty" \
            tests/e2e/test_package_mode.bats
          grep -q "INVARIANT: a package install never schedules an async update check" \
            tests/unit/test_autoupdate_package_mode.bats
          grep -q "INVARIANT: nivuus-update exits 0 on a package install" \
            tests/unit/test_update_package_message.bats
          grep -q "INVARIANT: nivuus install never writes origin=package" \
            tests/unit/test_lib_origin.bats
          grep -c "INVARIANT" tests/e2e/test_package_mode.bats
```

Et l'étape de performance, qui doit couvrir le cas « sans bytecode » :

```yaml
      - name: Startup budget holds without bytecode (package mode)
        run: |
          rm -f config/*.zwc
          bats tests/performance/test_startup_without_zwc.bats
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
grep -q 'test_package_mode.bats' .github/workflows/tests.yml
# Rejouer localement, exactement comme la CI :
rm -f config/*.zwc
bats tests/unit/ && bats tests/integration/ && bats tests/e2e/ && bats tests/performance/
```
Expected: PASS — les quatre suites vertes, 0 échec, et les chiffres de référence en hausse (uniquement par ajout).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "ci: run packaging core suites and guard the two packaging invariants"
```

---

### Task A14: documentation du mode paquet (sans encore annoncer un canal)

**Files:**
- Modify: `doc/PACKAGING.md` (compléter la section écrite en A8)
- Modify: `doc/INSTALL.md`
- Modify: `SECURITY.md`
- Modify: `README.md`
- Modify: `doc/CLAUDE.md`
- Test: `tests/e2e/test_docs_packaging.bats`

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: la documentation du **mode** paquet — pas encore celle des canaux, qui n'existent pas (Task B11).

Point délicat : **ne rien annoncer qui n'existe pas encore.** À ce stade, `brew install nivuus-shell` n'existe pas. La documentation décrit ce qu'un paquet *peut* faire et ce que Nivuus garantit en face ; elle ne donne aucune commande d'installation par canal. Une documentation en avance sur la réalité coûte plus cher qu'une documentation absente.

La **politique d'abandon d'un canal doit être écrite maintenant**, avant le premier abandon — c'est la mitigation n° 2 du risque le plus grave du chantier (« un canal abandonné est pire que pas de canal », parce que le mode paquet désactive délibérément l'auto-update, donc un utilisateur sur un canal mort est figé, sans mise à jour de sécurité, et sans avertissement).

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_docs_packaging.bats
#!/usr/bin/env bats
# La documentation du mode paquet doit exister, être exacte, et ne rien
# promettre qui n'existe pas encore.

setup() { ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "doc/PACKAGING.md documents the two-domain rule" {
    grep -qi 'manifeste' "$ROOT/doc/PACKAGING.md"
    grep -qi 'gestionnaire' "$ROOT/doc/PACKAGING.md"
}

@test "doc/PACKAGING.md documents the .nivuus-origin format exactly" {
    grep -q 'origin=package' "$ROOT/doc/PACKAGING.md"
    grep -q 'channel=' "$ROOT/doc/PACKAGING.md"
    grep -qi "absence" "$ROOT/doc/PACKAGING.md"
}

@test "doc/PACKAGING.md contains the channel abandonment policy" {
    # Écrite AVANT le premier abandon : c'est la mitigation du risque le
    # plus grave du chantier.
    grep -qi 'abandon' "$ROOT/doc/PACKAGING.md"
    grep -qi 'deux releases' "$ROOT/doc/PACKAGING.md"
}

@test "doc/INSTALL.md explains nivuus enable for package installs" {
    grep -q 'nivuus enable' "$ROOT/doc/INSTALL.md"
}

@test "SECURITY.md says a third-party channel INCREASES the attack surface" {
    # Le dire plutôt que de laisser croire que trois canaux valent mieux
    # qu'un du point de vue de la sécurité.
    grep -qi 'surface' "$ROOT/SECURITY.md"
}

@test "no channel install command is promised before the channel exists" {
    # Tant que le tap et l'AUR ne sont pas publiés, aucune commande
    # d'installation par canal ne doit figurer dans la documentation.
    run grep -rn 'brew install .*nivuus\|yay -S nivuus\|apt install nivuus' \
        "$ROOT/README.md" "$ROOT/doc/INSTALL.md"
    [ "$status" -ne 0 ]
}

@test "the guarded block is documented as guarded" {
    run grep -rn 'source "\$NIVUUS_SHELL_DIR/.zshrc"' "$ROOT/doc" "$ROOT/README.md"
    # Toute occurrence documentée doit montrer la garde.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == *'[ -r'* ]]
    done <<< "$output"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_docs_packaging.bats`
Expected: FAIL — la politique d'abandon et les sections de `doc/INSTALL.md` / `SECURITY.md` n'existent pas.

- [ ] **Step 3: Write minimal implementation**

Compléter `doc/PACKAGING.md` (au-dessus de la section « Coût de démarrage » écrite en A8) :

```markdown
## Deux inventaires qui ne se recouvrent jamais

Un paquet système et un logiciel qui se met à jour tout seul sont deux
autorités qui revendiquent les mêmes fichiers. Nivuus les sépare :

- **Domaine du gestionnaire** — l'arbre partagé (`/usr/share/nivuus-shell`,
  ou le `libexec` d'une formule Homebrew) et `/usr/bin/nivuus`. Inventaire :
  la base `dpkg` / `pacman` / `brew`. Mise à jour : la commande du
  gestionnaire. **Nivuus ne le réécrit jamais.**
- **Domaine de l'utilisateur** — le bloc délimité de `~/.zshrc`, le shell de
  connexion, `~/.cache/nivuus-shell`, `~/.local/state/nivuus`. Inventaire :
  `lib/manifest.sh`, inchangé. Activation : `nivuus enable`, retrait :
  `nivuus disable`.

Le manifeste d'une installation par paquet ne contient **aucune** ligne
`CREATE` : rien n'a été créé dans l'arbre partagé. La sûreté vient de
l'absence d'entrées, pas d'une exception dans le code.

## Le marqueur `.nivuus-origin`

Fichier texte `clé=valeur` posé par la recette de paquet, à la racine de
l'arbre partagé, et inventorié par le gestionnaire comme n'importe quel
autre fichier du paquet (donc supprimé avec lui) :

```
origin=package
channel=homebrew          # homebrew | aur | deb
package=nivuus-shell
version=3.2.0
```

Trois règles qui le rendent sûr :

1. **L'absence du fichier vaut `origin=source`** — le comportement
   historique, mot pour mot. Toutes les installations existantes, et toutes
   les futures installations par `install.sh`, ne voient aucun changement.
2. `bin/nivuus install` **n'écrit jamais** `origin=package` (un test
   l'interdit). Le seul producteur de cette valeur est une recette de paquet.
   Une valeur inconnue est traitée comme `source`.
3. **Garde-fou secondaire, indépendant du marqueur** : la mise à jour
   destructive est refusée si l'arbre n'est pas inscriptible par
   l'utilisateur courant. Il couvre le cas « un tiers a empaqueté Nivuus sans
   poser le marqueur ». Le marqueur porte le **message**, le garde-fou porte
   la **sûreté** ; aucun des deux ne suffit seul.

## Ce qu'une recette de paquet doit faire — et ne pas faire

**Doit :**

- copier l'arbre de release **bit-pour-bit**, sans renommer ni déplacer quoi
  que ce soit (un `.zshrc` caché sous `/usr/share` est inhabituel et
  parfaitement légal ; le renommer coûterait une divergence permanente) ;
- écrire `.nivuus-origin` avec le bon `channel` ;
- installer `doc/nivuus.1` dans `/usr/share/man/man1/` ;
- **afficher** une seule ligne en post-installation :
  `Pour activer Nivuus dans ton shell : nivuus enable`.

**Ne doit jamais :**

- écrire dans un `$HOME`, ni parcourir `/home` ;
- appeler `chsh` ;
- écrire dans `/etc/zsh/zshrc` (le drop-in administrateur est documenté,
  jamais automatique) ;
- livrer des fichiers `.zwc`.

## Politique d'abandon d'un canal

Un canal abandonné est **pire** qu'un canal absent, parce que le mode paquet
désactive délibérément l'auto-update : un utilisateur sur un canal mort est
figé sur une version, sans mise à jour de sécurité, et sans avertissement.
La procédure est donc écrite **avant** d'en avoir besoin :

1. Le canal est annoncé mort **deux releases à l'avance**.
2. Le dernier paquet publié sur ce canal affiche la migration dans son
   `postinst` / ses `caveats` — c'est le seul canal de communication qui
   atteigne réellement l'utilisateur d'un paquet.
3. `doctor` nomme la situation à partir du champ `channel=` et donne la
   sortie : retirer le paquet, puis relancer l'installeur.
4. **Le one-liner ne bouge jamais.** Il reste la porte de sortie universelle,
   et c'est une raison de plus de ne pas laisser les canaux dicter des
   changements d'architecture.
```

Dans `doc/INSTALL.md`, ajouter une section :

```markdown
## Installation par un gestionnaire de paquets

Quand Nivuus est installé par un paquet, l'arbre appartient au gestionnaire
et **l'activation reste un acte par utilisateur** :

    nivuus enable      # ajoute le bloc à ~/.zshrc (et propose chsh)
    nivuus disable     # retire le bloc, sans toucher à l'arbre

Les mises à jour automatiques sont alors désactivées : c'est le gestionnaire
qui les gère. `nivuus update` affiche sa commande exacte et sort en 0.

`nivuus install` fait la même chose que `nivuus enable` dans ce mode, et le
dit — il n'y a rien à copier, le paquet a déjà tout posé.

Le bloc écrit dans `~/.zshrc` est **gardé** :

    [ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"

Si le paquet est retiré alors que le bloc subsiste, le shell démarre sans la
moindre erreur. `nivuus doctor` nomme ce cas et donne la commande de
réparation.
```

Dans `SECURITY.md` :

```markdown
## Canaux de distribution tiers

Un canal de distribution tiers est un **point de confiance supplémentaire** :
l'ajouter **augmente** la surface d'attaque. Les empreintes publiées dans une
formule ou un `PKGBUILD` proviennent exclusivement d'un `SHA256SUMS`
authentifié par signature (jamais d'un `sha256sum` recalculé sur un fichier
retéléchargé), et les jetons de publication vivent dans un environnement CI
`packaging` **distinct** de l'environnement `release` : la compromission d'un
jeton de canal permet de publier une mauvaise recette, ce qui est grave, mais
**pas** de produire une release signée, ce qui serait fatal.

Ce que ce dispositif ne protège pas : un utilisateur qui installe depuis un
canal déjà compromis. C'est la limite du modèle, et elle est dite ici plutôt
que maquillée — trois canaux ne valent pas mieux qu'un du point de vue de la
sécurité.
```

Dans `README.md`, une phrase dans la section d'installation (sans commande de canal) :

```markdown
> Nivuus est conçu pour être empaqueté : quand il provient d'un gestionnaire
> de paquets, les mises à jour automatiques se désactivent et l'activation
> reste un acte par utilisateur (`nivuus enable`). Voir `doc/PACKAGING.md`.
```

Dans `doc/CLAUDE.md`, ajouter aux invariants du projet :

```markdown
- **Mode paquet** : `.nivuus-origin` absent ⇒ `origin=source` (comportement
  historique). `bin/nivuus install` n'écrit jamais `origin=package`. En mode
  paquet, aucune mise à jour automatique, aucune écriture dans l'arbre
  partagé, aucun `.zwc`. Le bloc `.zshrc` est **toujours** gardé.
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/e2e/test_docs_packaging.bats
bats tests/e2e/test_docs_install.bats
bats tests/unit/test_markdown.bats
```
Expected: PASS — 7 nouveaux tests, aucune régression.

- [ ] **Step 5: Commit**

```bash
git add doc/PACKAGING.md doc/INSTALL.md SECURITY.md README.md doc/CLAUDE.md \
        tests/e2e/test_docs_packaging.bats
git commit -m "docs(packaging): document package mode, marker format and channel policy"
```

---

## Fin de la partie A — critères de sortie

Avant de commencer la partie B, vérifier **tous** ces points :

```bash
rm -f config/*.zwc
bats tests/unit/          # ≥ 742 + ~60 nouveaux, 0 échec
bats tests/integration/   # 195, 2 skips, 0 échec
bats tests/e2e/           # ≥ 173 + ~34 nouveaux, 4 skips, 0 échec
bats tests/performance/   # ≥ 13, 0 échec
./bin/benchmark | sed -n '/^Average/p'   # < 300 ms, idéalement ~35 ms
```

- [ ] Les quatre suites sont vertes, aucun test **existant** n'a régressé ni basculé en `skip`.
- [ ] `bats tests/e2e/test_reversibility.bats` est vert : la réversibilité bit-exacte est intacte.
- [ ] Une installation par le one-liner est **bit-pour-bit inchangée** par rapport à avant la partie A, à l'exception de la ligne gardée du bloc `.zshrc` et du fichier `doc/nivuus.1`.
- [ ] Le chiffre de la mesure sans `.zwc` est consigné dans `doc/PACKAGING.md`, et la décision qu'il commande est prise et écrite.
- [ ] Aucun fichier `.nivuus-origin` n'est committé dans le dépôt (`git ls-files | grep nivuus-origin` doit être vide) : ce fichier n'existe que dans un paquet.


---

# PARTIE B — Bloquée sur des décisions ou des comptes externes

Chaque tâche de cette partie indique **ce qui manque**, **ce qu'on peut faire quand même sans l'élément manquant** (souvent : presque tout), et **ce que l'arrivée de l'élément rend mécanique**.

Principe directeur : **aller aussi loin que possible sans le blocage.** Une formule Homebrew peut être écrite, lintée et installée en local (`brew install --formula ./Formula/nivuus-shell.rb`) sans aucun tap publié ; un `PKGBUILD` peut être construit et `namcap`é dans un conteneur Arch sans compte AUR. Ce qui est bloqué, c'est la **publication**, presque jamais l'écriture.

## Registre des blocages

| # | Élément manquant | Nature | Bloque | Ce qui reste faisable sans lui |
|---|---|---|---|---|
| **BL-1** | Dépôt `maximeallanic/homebrew-tap` (créé, vide, accessible en écriture) | compte / dépôt | B2 | B1 en entier : écrire la formule, `brew style`, `brew audit --strict`, `brew install --build-from-source ./Formula/…` en local |
| **BL-2** | Secret `HOMEBREW_TAP_TOKEN` (jeton à portée *write* sur ce seul dépôt) | secret CI | B2, B8 | tout le corps du job, testable par `workflow_dispatch` sur un fork |
| **BL-3** | Compte AUR + clé SSH de déploiement, et **réservation du nom `nivuus-shell`** | compte | B5 | B3 en entier : `PKGBUILD`, `.SRCINFO`, `.install`, `makepkg` + `namcap` en conteneur |
| **BL-4** | Identité GPG de release : quelle clé, publiée où, liée à quelle identité vérifiable ? (question ouverte n° 3 de la spec) | arbitrage + secret | B4, et la ligne `validpgpkeys` de B3 | B4 peut être écrite avec une clé de test générée en CI ; **sans réponse, `validpgpkeys` est retiré du `PKGBUILD` et on se rabat sur `sha256sums` seul — dégradation acceptable mais à décider consciemment** |
| **BL-5** | Environnement GitHub `packaging` (créé, distinct de `release`) | configuration | B8 | écrire le workflow, le lancer sur un fork sans environnement |
| **BL-6** | Confirmation des noms `enable` / `disable` (question ouverte n° 1 de la spec) | arbitrage | — (déjà tranché par défaut en A9) | tout ; le renommage après A9 coûterait une dépréciation, d'où l'urgence de confirmer **avant** A9 |
| **BL-7** | Identité mainteneur (`Maintainer:` du `.deb`, `packager` AUR) : nom + adresse publiable | arbitrage mineur | la ligne exacte de B6/B3 | tout le reste ; un placeholder explicite suffit pour construire et linter |
| **BL-8** | Phase 4 CI mergée (`tests/ci/`, `.github/matrix.json`, `setup-tests`) | dépendance interne | B7 | B1, B3, B6 en local ; B7 est la seule à en dépendre vraiment |
| **BL-9** | Canaux réellement publiés | conséquence de BL-1/2/3 | B9, B10, B11 | écrire les workflows et la documentation, les garder derrière un `workflow_dispatch` tant qu'aucun canal ne vit |

**Ordre recommandé :** B1 → B3 → B6 (les trois recettes, toutes écrivables et testables en local, dans l'ordre de valeur décroissante de la spec § 8) → B7 (script de preuve unique) → B4 → B8 → B2 / B5 (publication, dès que BL-1/BL-2/BL-3 arrivent) → B9 → B10 → B11.

**Pourquoi Homebrew d'abord** (spec § 8) : l'audience est là où vise le produit ; une seule formule sert macOS **et** Linuxbrew ; et un tap est un simple dépôt git, sans revue externe. Si la partie A a débordé, échanger B1 et B3 est sans conséquence — elles ne dépendent que de la partie A, pas l'une de l'autre. Debian reste en dernier dans les deux cas : c'est le canal au plus faible rapport valeur/travail, puisqu'il n'apporte pas de mise à jour automatique et que son public est exactement celui que le one-liner sert déjà le mieux.

---

### Task B1: formule Homebrew, écrite et prouvée **en local**

**Bloqué par :** rien pour l'écriture et le test. **BL-1** bloque uniquement la publication (Task B2).

**Files:**
- Create: `Formula/nivuus-shell.rb`
- Test: `tests/unit/test_formula_homebrew.bats`

**Interfaces:**
- Consumes: l'arbre de release, `.nivuus-origin` (A1), `nivuus enable` (A9).
- Produces: une formule installable localement, `brew style` et `brew audit --strict` propres.

Choix acté : **tap dédié, pas `homebrew-core`** — `core` impose des critères de notoriété que le projet n'a pas encore et qui ne dépendent pas de la qualité du code, et chaque version y passerait par une PR avec sa file d'attente, faisant du canal le facteur limitant de la cadence de release. **Le fichier de formule est le même dans les deux cas** : migrer vers `core` plus tard est un déplacement de fichier.

`write_env_script` plutôt que `install_symlink` : le script fixe `NIVUUS_SHELL_DIR` et évite de dépendre de la résolution de lien — qu'on a corrigée par ailleurs (Task A2), ceinture et bretelles, parce que ce chemin-là est celui que `brew audit` exerce.

`uses_from_macos "zsh"` et non `depends_on "zsh"` : macOS fournit zsh ; sur Linux, brew l'installe. Un `depends_on` inconditionnel imposerait un zsh brew aux macOS, donc le problème `/etc/shells` + `chsh` que le chantier 1 a passé du temps à rendre inoffensif.

`fzf`, `git`, `bat`, `eza`, `grc` **ne sont pas** des dépendances : la politique du projet est la dégradation gracieuse ; en faire des `depends_on` transformerait `brew install nivuus-shell` en installation de cinq paquets non demandés. Ils vont dans les `caveats`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_formula_homebrew.bats
#!/usr/bin/env bats
# La formule est vérifiable sans Homebrew (structure, invariants de politique)
# et avec (style, audit, installation locale).

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    F="$ROOT/Formula/nivuus-shell.rb"
}

@test "the formula exists" { [ -f "$F" ]; }

@test "the formula writes the origin marker with channel=homebrew" {
    grep -q 'origin=package' "$F"
    grep -q 'channel=homebrew' "$F"
}

@test "the formula installs a bit-for-bit tree into libexec" {
    grep -q 'libexec.install' "$F"
}

@test "the formula uses write_env_script, not install_symlink" {
    grep -q 'write_env_script' "$F"
    run grep -q 'install_symlink' "$F"
    [ "$status" -ne 0 ]
}

@test "zsh comes from uses_from_macos, never from a hard depends_on" {
    grep -q 'uses_from_macos "zsh"' "$F"
    run grep -E '^\s*depends_on "zsh"' "$F"
    [ "$status" -ne 0 ]
}

@test "INVARIANT: optional tools are NEVER formula dependencies" {
    # La dégradation gracieuse est une politique du projet : « brew install
    # nivuus-shell » ne doit pas installer cinq paquets non demandés.
    for tool in fzf bat eza grc; do
        run grep -E "^\s*depends_on \"$tool\"" "$F"
        [ "$status" -ne 0 ]
    done
}

@test "the caveats tell the user to run nivuus enable" {
    grep -q 'nivuus enable' "$F"
}

@test "the caveats say updates go through brew" {
    grep -q 'brew upgrade' "$F"
}

@test "there is no head block (origin=package would be false or absent)" {
    run grep -E '^\s*head do' "$F"
    [ "$status" -ne 0 ]
}

@test "the sha256 is a real 64-hex digest, not a placeholder" {
    run grep -E 'sha256 "[0-9a-f]{64}"' "$F"
    [ "$status" -eq 0 ]
}

@test "brew style is clean" {
    command -v brew >/dev/null || skip "brew absent"
    run brew style "$F"
    [ "$status" -eq 0 ]
}

@test "brew audit --strict is clean" {
    command -v brew >/dev/null || skip "brew absent"
    run brew audit --strict --formula "$F"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_formula_homebrew.bats`
Expected: FAIL — `Formula/nivuus-shell.rb` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```ruby
# Formula/nivuus-shell.rb
class NivuusShell < Formula
  desc "Modern zero-config ZSH environment"
  homepage "https://github.com/maximeallanic/nivuus-shell"
  url "https://github.com/maximeallanic/nivuus-shell/releases/download/v3.2.0/nivuus-shell-v3.2.0.tar.gz"
  # Empreinte reprise du SHA256SUMS **vérifié par signature** (job `verify`
  # de packaging.yml), jamais recalculée sur un fichier retéléchargé.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  # macOS fournit zsh ; sur Linux, brew l'installe. Un depends_on "zsh"
  # inconditionnel imposerait un zsh brew aux macOS, donc le problème
  # /etc/shells + chsh que le projet a passé du temps à rendre inoffensif.
  uses_from_macos "zsh"

  # fzf, git, bat, eza, grc ne sont PAS des dépendances : la politique du
  # projet est la dégradation gracieuse. Ils sont mentionnés en caveats.

  def install
    # Arbre bit-pour-bit : aucune disposition spécifique au canal.
    libexec.install Dir["*"]
    (libexec/".nivuus-origin").write <<~EOS
      origin=package
      channel=homebrew
      package=nivuus-shell
      version=#{version}
    EOS
    # write_env_script et non install_symlink : le script fixe
    # NIVUUS_SHELL_DIR et n'a pas à dépendre de la résolution de lien.
    (bin/"nivuus").write_env_script libexec/"bin/nivuus",
                                    NIVUUS_SHELL_DIR: libexec
    man1.install libexec/"doc/nivuus.1" if (libexec/"doc/nivuus.1").exist?
  end

  def caveats
    <<~EOS
      Pour activer Nivuus dans ton shell :
          nivuus enable

      Les mises à jour passent par Homebrew :
          brew upgrade nivuus-shell

      Outils optionnels (Nivuus fonctionne sans, en mode dégradé) :
          brew install fzf git bat eza grc
    EOS
  end

  test do
    assert_match "nivuus", shell_output("#{bin}/nivuus help")
    assert_match "package", (libexec/".nivuus-origin").read
    assert_match "homebrew", (libexec/".nivuus-origin").read
    # Le chemin qui casse le plus souvent : un shell qui source l'arbre.
    system "zsh", "-c", "NIVUUS_SHELL_DIR=#{libexec} source #{libexec}/.zshrc"
    # Et le refus d'auto-update, qui est la raison d'être du marqueur.
    assert_match "brew upgrade", shell_output("#{bin}/nivuus update")
  end
end
```

**Tant que la première release signée n'existe pas**, l'empreinte est un placeholder et le test correspondant échoue : générer alors une release **fixture** locale (`tests/helpers/release.bash` sait déjà en fabriquer une servie en `file://`) et pointer `url` dessus le temps de la mise au point, ou marquer ce test `skip` avec un motif explicite. **Ne pas committer une empreinte fausse sans le dire.**

Preuve locale, sans tap :

```bash
brew style Formula/nivuus-shell.rb
brew audit --strict --formula Formula/nivuus-shell.rb
brew install --build-from-source --formula ./Formula/nivuus-shell.rb
nivuus help && nivuus doctor && nivuus update    # doit sortir en 0
nivuus enable && zsh -i -c 'print OK'
nivuus disable
brew uninstall nivuus-shell
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_formula_homebrew.bats`
Expected: PASS — 12 tests (les deux derniers `skip` si `brew` est absent de la machine).

- [ ] **Step 5: Commit**

```bash
git add Formula/nivuus-shell.rb tests/unit/test_formula_homebrew.bats
git commit -m "feat(homebrew): add the nivuus-shell formula, linted and locally installable"
```

---

### Task B2: publication du tap

**Bloqué par : BL-1** (dépôt `maximeallanic/homebrew-tap` créé et accessible) **et BL-2** (secret `HOMEBREW_TAP_TOKEN`, portée *write* sur ce seul dépôt).

**Ce qui reste faisable maintenant :** écrire intégralement le job (ci-dessous), le valider par `actionlint`, et le lancer sur un fork avec un dépôt de tap factice. **Ce que l'arrivée du dépôt et du jeton rend mécanique :** remplacer deux chaînes et retirer le `if: false`.

**Files:**
- Modify: `.github/workflows/packaging.yml` (créé en Task B8 ; si B8 n'est pas encore faite, créer le fichier avec ce seul job)

**Interfaces:**
- Consumes: le job `verify` (B8) qui produit l'empreinte **authentifiée**.
- Produces: une PR (ou un push direct) dans le tap, à chaque release.

- [ ] **Step 1: Write the failing test**

```bash
# Vérification locale : le job existe, il consomme `verify`, il vit dans
# l'environnement `packaging`, et il ne recalcule JAMAIS l'empreinte.
grep -q 'homebrew:' .github/workflows/packaging.yml
grep -A5 'homebrew:' .github/workflows/packaging.yml | grep -q 'needs: verify'
grep -A6 'homebrew:' .github/workflows/packaging.yml | grep -q 'environment: packaging'
! grep -B5 -A20 'homebrew:' .github/workflows/packaging.yml | grep -q 'sha256sum .*tar.gz'
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — le job n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```yaml
  homebrew:
    name: Publish the Homebrew formula
    needs: verify
    runs-on: ubuntu-latest
    # BLOQUÉ (BL-1, BL-2) : retirer cette ligne dès que le dépôt du tap
    # existe et que HOMEBREW_TAP_TOKEN est en place dans l'environnement.
    if: false
    environment: packaging
    steps:
      - uses: actions/checkout@v4

      - name: Récupérer l'empreinte AUTHENTIFIÉE produite par verify
        uses: actions/download-artifact@v4
        with: { name: verified-digests }

      - name: Générer la formule à partir de la release publiée
        run: |
          set -euo pipefail
          VERSION="${{ needs.verify.outputs.version }}"
          # L'empreinte vient du SHA256SUMS vérifié par signature, JAMAIS
          # d'un sha256sum recalculé sur un fichier retéléchargé : sinon le
          # packager devient le maillon faible du dispositif de signature.
          SHA="$(cat digest.tarball)"
          sed -e "s|/download/v[0-9.]*/|/download/v${VERSION}/|" \
              -e "s|nivuus-shell-v[0-9.]*\.tar\.gz|nivuus-shell-v${VERSION}.tar.gz|" \
              -e "s|sha256 \"[0-9a-f]*\"|sha256 \"${SHA}\"|" \
              Formula/nivuus-shell.rb > /tmp/nivuus-shell.rb
          diff -u Formula/nivuus-shell.rb /tmp/nivuus-shell.rb || true

      - name: Pousser dans le tap
        env:
          # BL-2 : jeton à portée write sur le SEUL dépôt du tap.
          TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          set -euo pipefail
          # BL-1 : remplacer par le vrai dépôt une fois créé.
          TAP_REPO="maximeallanic/homebrew-tap"
          git clone "https://x-access-token:${TAP_TOKEN}@github.com/${TAP_REPO}.git" /tmp/tap
          mkdir -p /tmp/tap/Formula
          cp /tmp/nivuus-shell.rb /tmp/tap/Formula/nivuus-shell.rb
          cd /tmp/tap
          git config user.name  "nivuus-packaging[bot]"
          git config user.email "packaging@users.noreply.github.com"
          git add Formula/nivuus-shell.rb
          git diff --cached --quiet && { echo "Rien à publier"; exit 0; }
          git commit -m "nivuus-shell ${{ needs.verify.outputs.version }}"
          git push

      - name: Ouvrir une issue si la publication a échoué
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            // Un canal rouge ne rétracte pas une release : elle est signée,
            // vérifiée, et les utilisateurs du one-liner en dépendent déjà.
            // Le mainteneur apprend la panne ; l'utilisateur, non.
            const title = `packaging: le canal Homebrew a échoué pour ${{ needs.verify.outputs.version }}`;
            const found = await github.rest.search.issuesAndPullRequests({
              q: `repo:${context.repo.owner}/${context.repo.repo} is:issue is:open label:packaging in:title "${title}"`
            });
            if (found.data.total_count === 0) {
              await github.rest.issues.create({
                owner: context.repo.owner, repo: context.repo.repo,
                title, labels: ['packaging'],
                body: `Le job \`homebrew\` a échoué. La release reste publiée et valide.\nRe-jouable seul : workflow_dispatch sur \`packaging.yml\` avec \`version\`.`
              });
            }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `actionlint .github/workflows/packaging.yml` puis les quatre `grep` du Step 1.
Expected: PASS. La preuve fonctionnelle demande BL-1 et BL-2 ; jusque-là, valider sur un fork avec un tap factice.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/packaging.yml
git commit -m "ci(packaging): publish the Homebrew formula to the tap (gated on BL-1/BL-2)"
```

---

### Task B3: `PKGBUILD`, `.SRCINFO` et `.install` AUR, construits et `namcap`és en local

**Bloqué par : BL-4** pour la seule ligne `validpgpkeys` (et **BL-7** pour la ligne `# Maintainer:`). **BL-3** bloque uniquement la publication (Task B5).

**Ce qui reste faisable maintenant :** tout le reste — écrire le `PKGBUILD`, générer le `.SRCINFO`, construire dans un conteneur `archlinux:latest` et passer `namcap`. **Sans réponse à BL-4, `validpgpkeys` est retiré et on se rabat sur `sha256sums` seul** : dégradation acceptable (l'empreinte est lue dans le `PKGBUILD` que l'utilisateur peut inspecter), mais **à décider consciemment**, pas par omission.

**Files:**
- Create: `packaging/aur/PKGBUILD`
- Create: `packaging/aur/nivuus-shell.install`
- Create: `packaging/aur/.SRCINFO`
- Test: `tests/unit/test_pkgbuild_aur.bats`

**Interfaces:**
- Consumes: l'arbre de release, `.nivuus-origin` (A1), `doc/nivuus.1` (A11).
- Produces: un paquet Arch installable, `namcap` muet.

**Un seul paquet, pas de couple `nivuus-shell` / `nivuus-shell-bin`.** La convention `-bin` distingue une compilation locale d'un binaire précompilé ; Nivuus n'a pas de binaire — le tarball de release et les « sources » sont le même fichier. Publier les deux, ce serait deux paquets identiques, deux `.SRCINFO` à tenir et une question récurrente sur le forum. **`nivuus-shell-git` est hors périmètre** (cible mouvante, invérifiable en CI, et il attirerait des rapports de bug sur du code non publié).

Nivuus a bien une vraie étape de build — la compilation `.zwc` — mais la Task A7 a décidé de ne pas l'exécuter. Le `build()` reste donc **vide, et documenté comme tel** plutôt que caché.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_pkgbuild_aur.bats
#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    P="$ROOT/packaging/aur/PKGBUILD"
    S="$ROOT/packaging/aur/.SRCINFO"
    I="$ROOT/packaging/aur/nivuus-shell.install"
}

@test "the PKGBUILD, .SRCINFO and .install all exist" {
    [ -f "$P" ] && [ -f "$S" ] && [ -f "$I" ]
}

@test "the PKGBUILD is valid shell" {
    run bash -n "$P"
    [ "$status" -eq 0 ]
}

@test "arch is any and zsh is the only hard dependency" {
    grep -q "arch=('any')" "$P"
    grep -q "depends=('zsh')" "$P"
}

@test "optional tools are optdepends, never depends" {
    grep -q 'optdepends=' "$P"
    for tool in fzf bat eza grc; do
        run grep -E "^depends=.*$tool" "$P"
        [ "$status" -ne 0 ]
    done
}

@test "the package writes the origin marker with channel=aur" {
    grep -q 'origin=package' "$P"
    grep -q 'channel=aur' "$P"
}

@test "the tree is copied bit-for-bit under /usr/share/nivuus-shell" {
    grep -q 'usr/share/nivuus-shell' "$P"
    grep -qE 'cp -a' "$P"
}

@test "the man page is installed" { grep -q 'nivuus.1' "$P"; }

@test "the .install file only PRINTS, it never touches a HOME" {
    grep -q 'nivuus enable' "$I"
    run grep -nE '\$HOME|/home/|chsh|\.zshrc' "$I"
    [ "$status" -ne 0 ]
}

@test "build() is empty and says why" {
    # La compilation .zwc existe mais n'est délibérément pas exécutée : le
    # dire dans le PKGBUILD plutôt que de le cacher.
    grep -q 'zwc' "$P"
}

@test "INVARIANT: .SRCINFO matches the PKGBUILD" {
    # Panne n°1 des paquets AUR automatisés, silencieuse jusqu'à ce que
    # l'AUR refuse le push ou, pire, l'accepte avec des métadonnées fausses.
    command -v makepkg >/dev/null || skip "makepkg absent (cible: conteneur archlinux)"
    cd "$ROOT/packaging/aur"
    makepkg --printsrcinfo > "$BATS_TEST_TMPDIR/.SRCINFO.regen"
    run diff -u "$S" "$BATS_TEST_TMPDIR/.SRCINFO.regen"
    [ "$status" -eq 0 ]
}

@test "namcap is quiet on the PKGBUILD" {
    command -v namcap >/dev/null || skip "namcap absent (cible: conteneur archlinux)"
    run namcap "$P"
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_pkgbuild_aur.bats`
Expected: FAIL — les trois fichiers n'existent pas.

- [ ] **Step 3: Write minimal implementation**

```bash
# packaging/aur/PKGBUILD
# Maintainer: <BL-7 : nom + adresse publiable du mainteneur>
pkgname=nivuus-shell
pkgver=3.2.0
pkgrel=1
pkgdesc="Modern zero-config ZSH environment"
arch=('any')
url="https://github.com/maximeallanic/nivuus-shell"
license=('MIT')
depends=('zsh')
optdepends=('fzf: complétion et recherche d'"'"'historique interactives'
            'git: segment git du prompt'
            'bat: coloration de cat'
            'eza: coloration de ls'
            'grc: coloration de commandes')
source=("$pkgname-$pkgver.tar.gz::$url/releases/download/v$pkgver/nivuus-shell-v$pkgver.tar.gz")
sha256sums=('SKIP')
# BL-4 — décommenter dès que l'identité GPG de release est arrêtée. makepkg
# vérifie alors nativement la signature de l'ARCHIVE (et non seulement de
# SHA256SUMS), ce que les utilisateurs Arch attendent. Sans réponse, on reste
# sur sha256sums seul : dégradation acceptable, décidée consciemment.
#   source+=("$pkgname-$pkgver.tar.gz.asc::$url/releases/download/v$pkgver/nivuus-shell-v$pkgver.tar.gz.asc")
#   sha256sums+=('SKIP')
#   validpgpkeys=('<empreinte longue de la clé GPG de release>')
install=nivuus-shell.install

build() {
  # Volontairement vide. Nivuus a bien une étape de build -- la compilation
  # des modules zsh en .zwc -- mais un paquet ne doit PAS la faire : un .zwc
  # porte une version de format, et compilé sur le runner de build il peut
  # être inutilisable sur la machine cible (au mieux inutile, au pire un bug
  # rapporté comme « Nivuus ne charge pas mon module »). Le shell de
  # l'utilisateur ne compile rien non plus dans un arbre qu'il ne possède
  # pas : voir config/99-cleanup.zsh.
  :
}

package() {
  install -d "$pkgdir/usr/share/nivuus-shell"
  # Arbre bit-pour-bit : aucune disposition spécifique au canal, pour qu'un
  # seul script de preuve couvre les trois formats.
  cp -a "$srcdir/$pkgname-$pkgver/." "$pkgdir/usr/share/nivuus-shell/"
  printf 'origin=package\nchannel=aur\npackage=%s\nversion=%s\n' \
      "$pkgname" "$pkgver" > "$pkgdir/usr/share/nivuus-shell/.nivuus-origin"
  install -d "$pkgdir/usr/bin"
  ln -s /usr/share/nivuus-shell/bin/nivuus "$pkgdir/usr/bin/nivuus"
  install -Dm644 "$pkgdir/usr/share/nivuus-shell/doc/nivuus.1" \
      "$pkgdir/usr/share/man/man1/nivuus.1"
  install -Dm644 "$srcdir/$pkgname-$pkgver/LICENSE" \
      "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

```bash
# packaging/aur/nivuus-shell.install
# N'AFFICHE que. Un .install qui touche à $HOME est contraire aux règles de
# packaging Arch -- et à la règle « aucun sudo que l'utilisateur n'a pas
# demandé », vue depuis l'autre bout.
post_install() {
    cat <<'MSG'
Nivuus est installé pour la machine. Pour l'activer dans ton shell :
    nivuus enable

Les mises à jour passent par ton gestionnaire de paquets.
MSG
}

post_upgrade() {
    post_install
}
```

`.SRCINFO` est **généré**, jamais écrit à la main :

```bash
docker run --rm -v "$PWD/packaging/aur:/pkg" -w /pkg archlinux:latest sh -c '
  pacman -Sy --noconfirm --needed base-devel namcap >/dev/null
  useradd -m builder && chown -R builder /pkg
  su builder -c "makepkg --printsrcinfo" > /pkg/.SRCINFO
'
```

Preuve de construction complète (`makepkg` **exige un utilisateur non-root**, d'où le compte `builder`) :

```bash
docker run --rm -v "$PWD:/src:ro" archlinux:latest bash -c '
  set -euo pipefail
  pacman -Sy --noconfirm --needed base-devel namcap zsh >/dev/null
  useradd -m builder
  cp -a /src/packaging/aur /home/builder/build && chown -R builder /home/builder/build
  # Release fixture servie en file:// (aucun réseau) : voir tests/helpers/release.bash
  su builder -c "cd /home/builder/build && makepkg -f --skipchecksums"
  namcap /home/builder/build/*.pkg.tar.zst
  pacman -U --noconfirm /home/builder/build/*.pkg.tar.zst
  command -v nivuus && nivuus doctor && nivuus update
'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_pkgbuild_aur.bats` (les deux derniers tests `skip` hors conteneur Arch — les rejouer dans le conteneur ci-dessus).
Expected: PASS — 11 tests.

- [ ] **Step 5: Commit**

```bash
git add packaging/aur tests/unit/test_pkgbuild_aur.bats
git commit -m "feat(aur): add PKGBUILD, .SRCINFO and install file, built and namcap-clean"
```

---

### Task B4: signature GPG détachée **de l'archive** dans `release.yml`

**Bloqué par : BL-4** — quelle clé, publiée où, liée à quelle identité vérifiable ?

**Ce qui reste faisable maintenant :** écrire l'étape complète et la prouver avec une **clé de test générée dans le job**, sur un `workflow_dispatch`. **Ce que la réponse rend mécanique :** remplacer la clé de test par le secret, et décommenter `validpgpkeys` dans le `PKGBUILD` (Task B3).

`makepkg` vérifie nativement une signature GPG **de l'archive elle-même**, alors que le dispositif actuel ne signe que `SHA256SUMS`. C'est une étape de quatre lignes dans un job qui manipule déjà une clé, et **c'est le mécanisme natif que les utilisateurs Arch attendent**.

**Files:**
- Modify: `.github/workflows/release.yml`
- Test: `tests/unit/test_release_workflow_asc.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_release_workflow_asc.bats
#!/usr/bin/env bats

setup() { ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; W="$ROOT/.github/workflows/release.yml"; }

@test "release.yml produces a detached .asc for the archive" {
    grep -q 'tar.gz.asc' "$W"
}

@test "the GPG signing step lives in the release environment" {
    # Cloisonnement : la clé de signature ne sort pas de `release`.
    grep -q 'environment: release' "$W"
}

@test "the .asc is uploaded as a release asset" {
    grep -qE 'gh release upload|files:.*asc' "$W"
}

@test "the .asc signs the ARCHIVE, not SHA256SUMS" {
    # Le point : makepkg vérifie l'archive elle-même.
    grep -qE 'gpg .*--detach-sign.*nivuus-shell-v.*\.tar\.gz' "$W"
}

@test "the GPG key never appears outside a secret reference" {
    run grep -nE 'BEGIN PGP PRIVATE' "$W"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_release_workflow_asc.bats`
Expected: FAIL — aucune étape GPG dans `release.yml`.

- [ ] **Step 3: Write minimal implementation**

Dans le job de release **déjà** protégé par `environment: release`, après la production de `SHA256SUMS` et sa signature ECDSA/SSHSIG :

```yaml
      - name: Signature GPG détachée de l'archive (pour validpgpkeys / makepkg)
        env:
          # BL-4 : identité GPG à arrêter. Tant qu'elle n'existe pas, ce pas
          # est validable sur workflow_dispatch avec une clé générée à la
          # volée -- mais il ne doit PAS publier de .asc de test.
          GPG_PRIVATE_KEY: ${{ secrets.RELEASE_GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE:  ${{ secrets.RELEASE_GPG_PASSPHRASE }}
        run: |
          set -euo pipefail
          [ -n "${GPG_PRIVATE_KEY:-}" ] || { echo "::warning::BL-4 non résolu : pas de .asc produit"; exit 0; }
          printf '%s' "$GPG_PRIVATE_KEY" | gpg --batch --import
          for f in nivuus-shell-v*.tar.gz; do
            gpg --batch --yes --pinentry-mode loopback \
                --passphrase "$GPG_PASSPHRASE" \
                --armor --detach-sign --output "$f.asc" "$f"
            # Vérifier ce qu'on vient de produire : une signature non
            # vérifiée est une signature qu'on ne sait pas valide.
            gpg --batch --verify "$f.asc" "$f"
          done

      - name: Publier le .asc comme asset de release
        run: |
          set -euo pipefail
          ls nivuus-shell-v*.tar.gz.asc >/dev/null 2>&1 || exit 0
          gh release upload "v${VERSION}" nivuus-shell-v*.tar.gz.asc --clobber
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Documenter dans `doc/SIGNING.md` : deux signatures, deux publics. `SHA256SUMS.sig` (ECDSA/SSHSIG) est ce que **le client Nivuus** vérifie ; le `.asc` GPG de l'archive est ce que **`makepkg`** vérifie. Elles ne se remplacent pas.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_release_workflow_asc.bats && actionlint .github/workflows/release.yml`
Expected: PASS — 5 tests. La preuve de bout en bout demande BL-4.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml doc/SIGNING.md tests/unit/test_release_workflow_asc.bats
git commit -m "feat(release): attach a detached GPG signature of the archive for makepkg"
```

---

### Task B5: réservation du nom AUR et job de publication

**Bloqué par : BL-3** — compte AUR, clé SSH de déploiement, et **réservation du nom `nivuus-shell`**.

> **Action à mener hors code, tout de suite, indépendamment du reste :** le nom sur l'AUR est **premier arrivé, premier servi**. Se le faire prendre par un tiers bien intentionné coûte infiniment plus cher que les dix minutes que prend la réservation. C'est la seule tâche de ce plan qui a une urgence propre, sans lien avec l'avancement du code.

**Ce qui reste faisable maintenant :** écrire le job (ci-dessous) et le valider par `actionlint`. **Ce que le compte rend mécanique :** ajouter le secret et retirer le `if: false`.

**Files:**
- Modify: `.github/workflows/packaging.yml`

- [ ] **Step 1: Write the failing test**

```bash
grep -q 'aur:' .github/workflows/packaging.yml
grep -A20 'aur:' .github/workflows/packaging.yml | grep -q 'printsrcinfo'
grep -A20 'aur:' .github/workflows/packaging.yml | grep -q 'diff'
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — le job n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```yaml
  aur:
    name: Publish to the AUR
    needs: verify
    runs-on: ubuntu-latest
    container: archlinux:latest
    # BLOQUÉ (BL-3) : retirer dès que le compte AUR et AUR_SSH_KEY existent,
    # et que le nom `nivuus-shell` est réservé.
    if: false
    environment: packaging
    steps:
      - uses: actions/checkout@v4

      - name: Outils de build
        run: pacman -Sy --noconfirm --needed base-devel namcap openssh git

      - name: Mettre à jour le PKGBUILD avec la version et l'empreinte vérifiées
        run: |
          set -euo pipefail
          VERSION="${{ needs.verify.outputs.version }}"
          SHA="$(cat digest.tarball)"     # produit par `verify`, authentifié
          sed -i -e "s/^pkgver=.*/pkgver=${VERSION}/" \
                 -e "s/^pkgrel=.*/pkgrel=1/" \
                 -e "s/^sha256sums=.*/sha256sums=('${SHA}')/" \
                 packaging/aur/PKGBUILD

      - name: Régénérer le .SRCINFO et COMPARER avant de pousser
        run: |
          set -euo pipefail
          useradd -m builder
          chown -R builder packaging/aur
          su builder -c "cd packaging/aur && makepkg --printsrcinfo" > /tmp/.SRCINFO
          # Panne n°1 des paquets AUR automatisés : un .SRCINFO divergent est
          # soit refusé par l'AUR, soit -- pire -- accepté avec des
          # métadonnées fausses. On compare, on ne fait pas confiance.
          if ! diff -u packaging/aur/.SRCINFO /tmp/.SRCINFO; then
            cp /tmp/.SRCINFO packaging/aur/.SRCINFO
            echo "::notice::.SRCINFO régénéré"
          fi

      - name: Construire et vérifier avant publication
        run: |
          set -euo pipefail
          su builder -c "cd packaging/aur && makepkg -f"
          namcap packaging/aur/*.pkg.tar.zst

      - name: Pousser vers aur.archlinux.org
        env:
          AUR_SSH_KEY: ${{ secrets.AUR_SSH_KEY }}   # BL-3
        run: |
          set -euo pipefail
          mkdir -p ~/.ssh && chmod 700 ~/.ssh
          printf '%s\n' "$AUR_SSH_KEY" > ~/.ssh/aur && chmod 600 ~/.ssh/aur
          ssh-keyscan aur.archlinux.org >> ~/.ssh/known_hosts
          export GIT_SSH_COMMAND="ssh -i ~/.ssh/aur"
          git clone ssh://aur@aur.archlinux.org/nivuus-shell.git /tmp/aur
          cp packaging/aur/PKGBUILD packaging/aur/.SRCINFO \
             packaging/aur/nivuus-shell.install /tmp/aur/
          cd /tmp/aur
          git config user.name "nivuus-packaging"
          git config user.email "packaging@users.noreply.github.com"
          git add -A
          git diff --cached --quiet && { echo "Rien à publier"; exit 0; }
          git commit -m "nivuus-shell ${{ needs.verify.outputs.version }}"
          git push
```

- [ ] **Step 4: Run test to verify it passes**

Run: `actionlint .github/workflows/packaging.yml` + les trois `grep`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/packaging.yml
git commit -m "ci(packaging): publish to the AUR with a .SRCINFO consistency gate (gated on BL-3)"
```

---

### Task B6: `.deb` par arbre de staging et `dpkg-deb`, `lintian` propre

**Bloqué par : BL-7 seulement** (la ligne `Maintainer:`). **C'est la tâche la moins bloquée de la partie B :** elle est intégralement écrivable, constructible et testable en local dès aujourd'hui.

**Arbitrage acté : `.deb` attaché à la release GitHub, pas de dépôt APT.** Un vrai dépôt APT est un engagement d'infrastructure permanent — une **seconde** clé de signature (un dépôt APT signe son `InRelease`, pas les artefacts), un paquet `nivuus-shell-keyring` à maintenir sous peine d'apprendre à des utilisateurs le `apt-key add` déprécié, et surtout la promesse implicite que l'URL vivra des années (un `sources.list` cassé produit une erreur à chaque `apt update` de chaque machine, indéfiniment). Ce qu'on perd : la mise à jour automatique côté Debian — acceptable **précisément parce que le mode paquet la désactive de toute façon**. Le public du `.deb` est le déploiement par configuration système (Ansible, image de base, poste managé), où l'automatisme est justement indésirable.

Construction : **arbre de staging + `dpkg-deb --build --root-owner-group`**, sans `debhelper` ni `debian/rules`. La cérémonie d'un paquet source Debian n'achète quelque chose *que* si l'on vise l'archive officielle ; pour un binaire `Architecture: all` sans compilation, elle ajoute une chaîne d'outils en CI et zéro garantie.

**Files:**
- Create: `packaging/deb/build.sh`
- Create: `packaging/deb/control.in`
- Create: `packaging/deb/postinst`
- Create: `packaging/deb/prerm`
- Test: `tests/unit/test_deb_package.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_deb_package.bats
#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    D="$ROOT/packaging/deb"
}

@test "the build script and maintainer scripts exist" {
    [ -x "$D/build.sh" ] && [ -f "$D/control.in" ] && [ -x "$D/postinst" ] && [ -x "$D/prerm" ]
}

@test "shellcheck is clean on the maintainer scripts" {
    command -v shellcheck >/dev/null || skip "shellcheck absent"
    run shellcheck "$D/build.sh" "$D/postinst" "$D/prerm"
    [ "$status" -eq 0 ]
}

@test "zsh is the only hard dependency; curl and fzf are not" {
    grep -q '^Depends: zsh' "$D/control.in"
    run grep -E '^Depends:.*(curl|fzf)' "$D/control.in"
    [ "$status" -ne 0 ]
    grep -q '^Recommends:' "$D/control.in"
}

@test "architecture is all and section is shells" {
    grep -q '^Architecture: all' "$D/control.in"
    grep -q '^Section: shells' "$D/control.in"
}

@test "INVARIANT: postinst writes nothing, walks no HOME, calls no chsh" {
    # Un postinst qui échoue laisse le paquet en half-configured et bloque
    # apt : bien plus grave que l'absence du message. Il ne fait donc
    # qu'afficher, et il ne peut pas échouer.
    run grep -nE '\$HOME|/home/|chsh|update-shells|\.zshrc' "$D/postinst"
    [ "$status" -ne 0 ]
    grep -q 'nivuus enable' "$D/postinst"
}

@test "prerm mentions nivuus disable but does NOT remove the activation" {
    # C'est la garde du bloc .zshrc qui rend l'oubli inoffensif.
    grep -q 'nivuus disable' "$D/prerm"
    run grep -nE 'sed -i|rm .*zshrc' "$D/prerm"
    [ "$status" -ne 0 ]
}

@test "the build script writes the origin marker with channel=deb" {
    grep -q 'origin=package' "$D/build.sh"
    grep -q 'channel=deb' "$D/build.sh"
}

@test "the build script uses --root-owner-group (reproducible ownership)" {
    grep -q 'root-owner-group' "$D/build.sh"
}

@test "the man page is installed under /usr/share/man/man1" {
    grep -q 'usr/share/man/man1' "$D/build.sh"
}

@test "a .deb builds and lintian is quiet" {
    command -v dpkg-deb >/dev/null || skip "dpkg-deb absent"
    run "$D/build.sh" "$BATS_TEST_TMPDIR" 3.2.0
    [ "$status" -eq 0 ]
    ls "$BATS_TEST_TMPDIR"/nivuus-shell_3.2.0_all.deb
    command -v lintian >/dev/null || skip "lintian absent"
    run lintian --no-tag-display-limit "$BATS_TEST_TMPDIR"/nivuus-shell_*.deb
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_deb_package.bats`
Expected: FAIL — `packaging/deb/` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```
# packaging/deb/control.in
Package: nivuus-shell
Version: @VERSION@
Architecture: all
Section: shells
Priority: optional
Depends: zsh
Recommends: git, curl
Suggests: fzf, bat, eza, grc
Maintainer: @MAINTAINER@
Homepage: https://github.com/maximeallanic/nivuus-shell
Description: Modern zero-config ZSH environment
 Nivuus Shell is a fast, opinionated ZSH environment with a Nord theme,
 AI-assisted suggestions and a sub-300ms startup budget.
 .
 The package installs a shared, read-only tree. Activation stays a
 per-user action: run "nivuus enable".
```

```sh
#!/bin/sh
# packaging/deb/postinst
# N'ÉCRIT RIEN. Aucun parcours de /home, aucun chsh, aucun update-shells (le
# paquet zsh s'en charge déjà). Idempotent, et il ne peut pas échouer -- un
# postinst qui échoue laisse le paquet en half-configured et bloque apt, ce
# qui est une bien plus grosse panne que l'absence du message.
set -e
case "$1" in
  configure)
    echo "Nivuus est installé pour la machine."
    echo "Pour l'activer dans ton shell :  nivuus enable"
    ;;
esac
exit 0
```

```sh
#!/bin/sh
# packaging/deb/prerm
# Rappelle que l'activation par utilisateur subsiste. Il ne la retire PAS :
# le bloc écrit dans ~/.zshrc est gardé, donc l'oubli est inoffensif -- le
# shell démarre sans erreur même si l'arbre a disparu.
set -e
case "$1" in
  remove|deconfigure)
    echo "Le bloc Nivuus reste dans le ~/.zshrc des utilisateurs qui l'ont activé."
    echo "Chacun peut le retirer avec :  nivuus disable"
    echo "(sans quoi rien ne casse : le bloc est gardé.)"
    ;;
esac
exit 0
```

```sh
#!/bin/sh
# packaging/deb/build.sh — arbre de staging + dpkg-deb, sans debhelper.
# Usage : build.sh <répertoire-de-sortie> <version> [<racine-source>]
set -eu

OUT="${1:?répertoire de sortie attendu}"
VERSION="${2:?version attendue}"
SRC="${3:-$(cd "$(dirname "$0")/../.." && pwd)}"
MAINTAINER="${DEB_MAINTAINER:-Maxime Allanic <packaging@example.invalid>}"  # BL-7

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

install -d "$STAGE/DEBIAN" "$STAGE/usr/share/nivuus-shell" \
           "$STAGE/usr/bin" "$STAGE/usr/share/man/man1" \
           "$STAGE/usr/share/doc/nivuus-shell"

# Arbre bit-pour-bit, .zwc et .git exclus : un bytecode compilé sur le
# runner de build peut être inutilisable sur la machine cible, et il
# survivrait au purge.
tar -C "$SRC" -cf - \
    --exclude='.git' --exclude='*.zwc' --exclude='.worktrees' --exclude='docs' \
    config themes lib bin keys plugins doc .zshrc .version LICENSE 2>/dev/null \
  | tar -C "$STAGE/usr/share/nivuus-shell" -xf -

printf 'origin=package\nchannel=deb\npackage=nivuus-shell\nversion=%s\n' \
    "$VERSION" > "$STAGE/usr/share/nivuus-shell/.nivuus-origin"

ln -s /usr/share/nivuus-shell/bin/nivuus "$STAGE/usr/bin/nivuus"
install -m644 "$SRC/doc/nivuus.1" "$STAGE/usr/share/man/man1/nivuus.1"
gzip -9n "$STAGE/usr/share/man/man1/nivuus.1"
install -m644 "$SRC/LICENSE" "$STAGE/usr/share/doc/nivuus-shell/copyright"

sed -e "s/@VERSION@/$VERSION/" -e "s|@MAINTAINER@|$MAINTAINER|" \
    "$(dirname "$0")/control.in" > "$STAGE/DEBIAN/control"
install -m755 "$(dirname "$0")/postinst" "$STAGE/DEBIAN/postinst"
install -m755 "$(dirname "$0")/prerm"    "$STAGE/DEBIAN/prerm"

install -d "$OUT"
# --root-owner-group : pas de dépendance à fakeroot, et une propriété de
# fichiers déterministe.
dpkg-deb --build --root-owner-group "$STAGE" \
    "$OUT/nivuus-shell_${VERSION}_all.deb"
```

Preuve locale :

```bash
./packaging/deb/build.sh /tmp/out 3.2.0
lintian /tmp/out/nivuus-shell_3.2.0_all.deb
docker run --rm -v /tmp/out:/out debian:12 sh -c '
  apt-get update -qq && apt-get install -y -qq /out/nivuus-shell_3.2.0_all.deb
  command -v nivuus && nivuus doctor && nivuus update
  dpkg -V nivuus-shell && echo "base dpkg cohérente"
  apt-get purge -y -qq nivuus-shell
  [ ! -e /usr/share/nivuus-shell ] && echo "aucune trace"
'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_deb_package.bats`
Expected: PASS — 10 tests (ceux qui exigent `dpkg-deb`/`lintian` se `skip` hors Debian).

- [ ] **Step 5: Commit**

```bash
git add packaging/deb tests/unit/test_deb_package.bats
git commit -m "feat(deb): build an Architecture: all package with a staging tree and dpkg-deb"
```

---

### Task B7: un seul script de preuve pour les trois formats

**Bloqué par : BL-8** (phase 4 CI mergée : `tests/ci/run-target.sh` sert de modèle, `tests/ci/bats-run.sh` et `.github/matrix.json` sont réutilisés **sans modification**).

**Ce qui reste faisable sans BL-8 :** écrire le script et le rejouer en local par `docker run` — il ne dépend de la phase 4 que pour son **intégration** au workflow et pour l'alignement de la liste d'images.

**Files:**
- Create: `tests/ci/run-package-target.sh`

**Interfaces:**
- Consumes: `packaging/deb/build.sh` (B6), `packaging/aur/PKGBUILD` (B3), `Formula/nivuus-shell.rb` (B1), `tests/helpers/fingerprint.bash`, `tests/helpers/release.bash`.
- Produces: la séquence de preuve en dix étapes de la spec § 6.1, paramétrée par le format.

C'est le § 3.3 (arbre identique dans les trois formats) qui rend un **script unique** possible : un bug reproduit sur Debian se reproduit sur Arch. Toute la logique de preuve vit dans le script, rien dans le YAML, donc `docker run … ./tests/ci/run-package-target.sh deb` le rejoue en local.

Les étapes **5** et **9** sont aux paquets ce que le refus d'archive falsifiée est à la signature : si elles passent, la propriété existe ; si elles manquent, le reste est décoratif. Elles portent donc un commentaire `INVARIANT:` et `tests.yml` vérifie par `grep` qu'elles n'ont pas disparu (extension du garde-fou posé en Task A13).

- [ ] **Step 1: Write the failing test**

Le script **est** le test. Écrire d'abord la vérification de sa présence et de ses invariants, appelée depuis `tests.yml` :

```bash
[ -x tests/ci/run-package-target.sh ]
grep -q 'INVARIANT: aucun horodatage de vérification de mise à jour' tests/ci/run-package-target.sh
grep -q 'INVARIANT: paquet retiré, activation restante, stderr vide' tests/ci/run-package-target.sh
shellcheck tests/ci/run-package-target.sh
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — le script n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```sh
#!/bin/sh
# tests/ci/run-package-target.sh — preuve de bout en bout d'un canal de paquet.
#
# Usage : ./tests/ci/run-package-target.sh <deb|aur|homebrew>
#
# Modèle : tests/ci/run-target.sh. Toute la logique de preuve vit ICI, rien
# dans le YAML -- donc rejouable en local :
#   docker run --rm -v "$PWD:/src" debian:12 /src/tests/ci/run-package-target.sh deb
#
# La séquence est IDENTIQUE pour les trois formats : c'est l'arbre
# bit-pour-bit (aucune disposition spécifique à un canal) qui le permet.
set -eu

FORMAT="${1:?format attendu : deb | aur | homebrew}"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(cat "$SRC/.version" 2>/dev/null || echo 0.0.0-test)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$SRC/tests/helpers/fingerprint.bash"

fail() { printf 'ÉCHEC : %s\n' "$1" >&2; exit 1; }
step() { printf '\n=== [%s] %s\n' "$FORMAT" "$1"; }

# --- 1. Construire depuis une release FIXTURE servie en file:// -------------
step "1. construction du paquet (sans réseau)"
case "$FORMAT" in
  deb)
    "$SRC/packaging/deb/build.sh" "$WORK" "$VERSION"
    PKG="$WORK/nivuus-shell_${VERSION}_all.deb"
    PREFIX=/usr/share/nivuus-shell
    ;;
  aur)
    # makepkg EXIGE un utilisateur non-root : on crée le compte ici plutôt
    # que dans le YAML, pour que le script reste rejouable en local.
    id builder >/dev/null 2>&1 || useradd -m builder
    cp -a "$SRC/packaging/aur" "$WORK/build"
    cp -a "$SRC" "$WORK/build/nivuus-shell-$VERSION"
    chown -R builder "$WORK/build"
    su builder -c "cd '$WORK/build' && makepkg -f --skipchecksums --skippgpcheck"
    PKG="$(ls "$WORK"/build/*.pkg.tar.zst)"
    PREFIX=/usr/share/nivuus-shell
    ;;
  homebrew)
    PKG="$SRC/Formula/nivuus-shell.rb"
    PREFIX="$(brew --prefix)/opt/nivuus-shell/libexec"
    ;;
  *) fail "format inconnu : $FORMAT" ;;
esac
[ -e "$PKG" ] || fail "le paquet n'a pas été construit"

# --- 2. Installer avec le VRAI gestionnaire --------------------------------
step "2. installation avec le gestionnaire réel"
case "$FORMAT" in
  deb)      apt-get install -y "$PKG" ;;
  aur)      pacman -U --noconfirm "$PKG" ;;
  homebrew) brew install --formula "$PKG" ;;
esac

# --- 3. Le binaire est là, doctor est sain, l'origine est correcte ---------
step "3. command -v nivuus, doctor, origine"
command -v nivuus >/dev/null || fail "nivuus introuvable dans le PATH"
nivuus doctor > "$WORK/doctor.out" 2>&1 || true
grep -q 'package' "$WORK/doctor.out" || fail "doctor ne voit pas l'origine package"
grep -q "$FORMAT" "$WORK/doctor.out" \
  || [ "$FORMAT" = homebrew ] \
  || fail "doctor ne nomme pas le canal $FORMAT"

# --- 4. nivuus update explique et SORT EN 0 -------------------------------
step "4. nivuus update"
nivuus update > "$WORK/update.out" 2>&1 || fail "nivuus update doit sortir en 0"
grep -qE 'brew upgrade|pacman|yay|paru|apt' "$WORK/update.out" \
  || fail "nivuus update ne donne pas la commande du gestionnaire"
[ ! -d "$HOME/.nivuus-backups" ] || fail "nivuus update a téléchargé quelque chose"

# --- 5. INVARIANT: aucun horodatage de vérification de mise à jour ---------
step "5. trois shells interactifs, puis absence de l'horodatage"
# INVARIANT: aucun horodatage de vérification de mise à jour n'apparaît après
# trois shells interactifs sur une installation par paquet. C'est la preuve
# OBSERVABLE que _nivuus_check_update_async ne s'est jamais exécuté : s'il
# tournait, il réécrirait des fichiers appartenant à dpkg / pacman / brew,
# la base du gestionnaire deviendrait fausse, et la mise à jour système
# suivante écraserait Nivuus sans prévenir.
nivuus enable --yes
for _ in 1 2 3; do zsh -i -c 'true' >/dev/null 2>&1 || true; done
sleep 2
[ ! -f "$HOME/.nivuus-shell-last-update-check" ] \
  || fail "INVARIANT 1 violé : l'updater automatique a tourné en mode paquet"

# --- 6. Empreinte, activation, shell fonctionnel --------------------------
step "6. empreinte de \$HOME, puis shell interactif"
nivuus disable --yes >/dev/null 2>&1 || true
fs_fingerprint "$HOME" > "$WORK/home.before"
nivuus enable --yes
zsh -i -c 'print -r -- OK' > "$WORK/shell.out" 2>"$WORK/shell.err"
[ -s "$WORK/shell.err" ] && { cat "$WORK/shell.err" >&2; fail "stderr non vide après enable"; }
grep -q OK "$WORK/shell.out" || fail "le shell n'a pas démarré"

# --- 7. disable rend le HOME à l'octet près -------------------------------
step "7. disable, puis égalité stricte des empreintes"
nivuus disable --yes
fs_fingerprint "$HOME" > "$WORK/home.after"
diff -u "$WORK/home.before" "$WORK/home.after" || fail "\$HOME n'est pas revenu à l'identique"

# --- 8. Retirer le paquet : aucune trace, base cohérente ------------------
step "8. suppression du paquet"
case "$FORMAT" in
  deb)      apt-get purge -y nivuus-shell; dpkg -V nivuus-shell 2>/dev/null || true ;;
  aur)      pacman -Rns --noconfirm nivuus-shell ;;
  homebrew) brew uninstall nivuus-shell ;;
esac
[ ! -e "$PREFIX" ] || fail "des fichiers subsistent sous $PREFIX après suppression"

# --- 9. INVARIANT: paquet retiré, activation restante, stderr vide --------
step "9. réactivation, suppression du paquet, shell interactif"
# INVARIANT: paquet retiré, activation restante, stderr vide. C'est le cas
# NORMAL, pas le cas dégradé : « brew uninstall » et « apt purge » n'ont
# aucun moyen de savoir qui a activé quoi. Sans la garde du bloc .zshrc, ce
# scénario casse le shell de TOUS les utilisateurs encore activés, à chaque
# prompt, sans rapport visible avec l'action faite.
case "$FORMAT" in
  deb)      apt-get install -y "$PKG" ;;
  aur)      pacman -U --noconfirm "$PKG" ;;
  homebrew) brew install --formula "$PKG" ;;
esac
nivuus enable --yes
case "$FORMAT" in
  deb)      apt-get purge -y nivuus-shell ;;
  aur)      pacman -Rns --noconfirm nivuus-shell ;;
  homebrew) brew uninstall nivuus-shell ;;
esac
zsh -i -c 'true' 2>"$WORK/orphan.err" || true
[ -s "$WORK/orphan.err" ] && { cat "$WORK/orphan.err" >&2; fail "INVARIANT 2 violé : stderr non vide"; }

# --- 10. Aucun .zwc laissé par un shell root (deb et aur) -----------------
if [ "$FORMAT" != homebrew ]; then
  step "10. shell root sur machine paquetée : aucun .zwc"
  case "$FORMAT" in
    deb) apt-get install -y "$PKG" ;;
    aur) pacman -U --noconfirm "$PKG" ;;
  esac
  zsh -i -c 'true' >/dev/null 2>&1 || true
  sleep 2
  found="$(find "$PREFIX" -name '*.zwc' 2>/dev/null || true)"
  [ -z "$found" ] || fail "des .zwc orphelins ont été créés sous $PREFIX : $found"
fi

printf '\n✓ [%s] les dix étapes de preuve sont passées\n' "$FORMAT"
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
shellcheck tests/ci/run-package-target.sh
docker run --rm -v "$PWD:/src" debian:12 sh -c 'apt-get update -qq && apt-get install -y -qq zsh && /src/tests/ci/run-package-target.sh deb'
docker run --rm -v "$PWD:/src" archlinux:latest sh -c 'pacman -Sy --noconfirm base-devel zsh && /src/tests/ci/run-package-target.sh aur'
# macOS (runner ou poste) : ./tests/ci/run-package-target.sh homebrew
```
Expected: PASS sur les trois formats.

- [ ] **Step 5: Commit**

```bash
git add tests/ci/run-package-target.sh
git commit -m "test(ci): single ten-step proof script covering deb, aur and homebrew"
```

---

### Task B8: `packaging.yml` — le job `verify` et le cloisonnement des secrets

**Bloqué par : BL-5** (environnement GitHub `packaging`) et, pour les jobs enfants, BL-1/BL-2/BL-3.

**Ce qui reste faisable maintenant :** écrire le workflow complet et le valider ; le job `verify` est même exécutable dès qu'une release signée existe, **sans aucun secret** (les clés publiques sont commitées dans le dépôt).

**Le job `verify` est le pivot du chantier.** L'ordre est **non négociable, identique à celui du client** : signature d'abord, empreinte ensuite. Comparer une empreinte à un `SHA256SUMS` non authentifié n'a aucun sens. Si `verify` échoue, **aucun canal n'est publié** — fail-closed, comme partout ailleurs dans ce projet.

**Environnement `packaging`, distinct de `release`.** Mettre les jetons de packaging dans `release` dissoudrait la propriété centrale du dispositif de signature : un canal compromis pourrait alors signer. Avec deux environnements, la compromission d'un jeton de tap permet de publier une **mauvaise formule** — grave — mais **pas** de produire une release signée — fatal.

**Files:**
- Create/Modify: `.github/workflows/packaging.yml`
- Test: `tests/unit/test_packaging_workflow.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_packaging_workflow.bats
#!/usr/bin/env bats

setup() { ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; W="$ROOT/.github/workflows/packaging.yml"; }

@test "packaging.yml exists and is triggered by workflow_run and workflow_dispatch" {
    [ -f "$W" ]
    grep -q 'workflow_run' "$W"
    grep -q 'workflow_dispatch' "$W"
}

@test "workflow_dispatch takes a version input (republishing must take a minute)" {
    grep -A6 'workflow_dispatch' "$W" | grep -q 'version'
}

@test "INVARIANT: verify checks the SIGNATURE before the digest" {
    # Ordre non négociable, identique à celui du client. Comparer une
    # empreinte à un SHA256SUMS non authentifié n'a aucun sens.
    sig_line=$(grep -n 'openssl dgst -sha256 -verify' "$W" | head -1 | cut -d: -f1)
    sum_line=$(grep -n 'sha256sum -c' "$W" | head -1 | cut -d: -f1)
    [ -n "$sig_line" ] && [ -n "$sum_line" ]
    [ "$sig_line" -lt "$sum_line" ]
}

@test "INVARIANT: the digest is never recomputed from a re-downloaded file" {
    # Un packager qui recalcule un sha256 sans vérifier la signature annule
    # tout le dispositif en trois lignes de YAML.
    run grep -nE 'sha256sum [^-].*tar\.gz *>' "$W"
    [ "$status" -ne 0 ]
}

@test "every publishing job needs verify" {
    for job in homebrew aur deb; do
        grep -A4 "^  $job:" "$W" | grep -q 'needs: verify'
    done
}

@test "every publishing job runs in the packaging environment, never release" {
    for job in homebrew aur deb; do
        grep -A6 "^  $job:" "$W" | grep -q 'environment: packaging'
    done
    run grep -n 'environment: release' "$W"
    [ "$status" -ne 0 ]
}

@test "a failing channel does not retract the release" {
    # « aucune release ne sort si un test est rouge » porte sur le
    # PRÉ-publication. La synchronisation des canaux est POST-publication :
    # ce n'est pas la même transaction.
    grep -q 'fail-fast: false' "$W" || grep -q 'if: failure()' "$W"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_packaging_workflow.bats`
Expected: FAIL — le workflow n'existe pas (ou n'a que les jobs des tâches B2/B5).

- [ ] **Step 3: Write minimal implementation**

```yaml
# .github/workflows/packaging.yml
name: Packaging

on:
  workflow_run:
    workflows: ["Release"]
    types: [completed]
  workflow_dispatch:
    inputs:
      version:
        description: "Version à (re)publier, sans le v — republier un canal doit prendre une minute"
        required: true
        type: string

permissions:
  contents: read

jobs:
  verify:
    name: Vérifier la release avant d'empaqueter quoi que ce soit
    runs-on: ubuntu-latest
    # Aucun secret : les clés PUBLIQUES sont commitées dans le dépôt.
    outputs:
      version: ${{ steps.resolve.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Résoudre la version
        id: resolve
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          if [ -n "${{ inputs.version }}" ]; then
            v="${{ inputs.version }}"
          else
            v="$(gh release view --json tagName -q .tagName | sed 's/^v//')"
          fi
          echo "version=$v" >> "$GITHUB_OUTPUT"

      - name: Télécharger les artefacts de release
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          gh release download "v${{ steps.resolve.outputs.version }}" \
            -p 'nivuus-shell-v*.tar.gz' -p 'SHA256SUMS*'

      - name: 1. Authenticité — la MÊME vérification que le client utilisateur
        run: |
          set -euo pipefail
          # ORDRE NON NÉGOCIABLE : signature d'abord. Comparer une empreinte
          # à un SHA256SUMS non authentifié n'a aucun sens.
          ok=0
          for key in keys/*.pem; do
            if openssl dgst -sha256 -verify "$key" \
                 -signature SHA256SUMS.sig SHA256SUMS 2>/dev/null; then
              ok=1; break
            fi
          done
          [ "$ok" -eq 1 ] || { echo "::error::signature invalide — aucun canal ne sera publié"; exit 1; }

      - name: 2. Intégrité — et SEULEMENT ensuite
        id: digest
        run: |
          set -euo pipefail
          V="${{ steps.resolve.outputs.version }}"
          # Le nom versionné fait partie du contenu signé : c'est ce qui
          # bloque le rejeu inter-versions. Ne jamais « simplifier » ce grep
          # en head -n1.
          grep "nivuus-shell-v${V}.tar.gz" SHA256SUMS | sha256sum -c -
          # L'empreinte publiée dans les trois recettes vient d'ICI, du
          # SHA256SUMS authentifié — jamais d'un sha256sum recalculé sur un
          # fichier retéléchargé sans vérification.
          grep "nivuus-shell-v${V}.tar.gz" SHA256SUMS | cut -d' ' -f1 > digest.tarball

      - uses: actions/upload-artifact@v4
        with:
          name: verified-digests
          path: digest.tarball

  # Les trois canaux sont indépendants : un canal rouge ne rétracte pas une
  # release publiée, signée et vérifiée, dont les utilisateurs du one-liner
  # dépendent déjà. Chacun est re-jouable seul par workflow_dispatch.
  homebrew:
    needs: verify
    environment: packaging          # BL-5 — distinct de `release`
    # … corps : voir Task B2

  aur:
    needs: verify
    environment: packaging
    # … corps : voir Task B5

  deb:
    name: Attacher le .deb à la release
    needs: verify
    runs-on: ubuntu-latest
    environment: packaging
    steps:
      - uses: actions/checkout@v4
      - name: Construire
        run: ./packaging/deb/build.sh dist "${{ needs.verify.outputs.version }}"
      - name: Linter
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq lintian
          lintian dist/nivuus-shell_*.deb
      - name: Attacher à la release
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: gh release upload "v${{ needs.verify.outputs.version }}" dist/nivuus-shell_*.deb --clobber
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_packaging_workflow.bats && actionlint .github/workflows/packaging.yml`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/packaging.yml tests/unit/test_packaging_workflow.bats
git commit -m "ci(packaging): verify-then-publish pipeline in an isolated packaging environment"
```

---

### Task B9: `packaging-drift.yml` — la sonde anti-pourrissement

**Bloqué par : BL-9** (les canaux doivent exister pour qu'une dérive soit mesurable).

**Ce qui reste faisable maintenant :** écrire le workflow entier ; il est sans secret et en lecture seule. Le laisser en `workflow_dispatch` seul tant qu'aucun canal ne vit, puis activer le `schedule`.

**Pourquoi c'est nécessaire et pas cosmétique :** un canal figé est **pire** qu'un canal absent, parce que le mode paquet y désactive l'auto-update par conception. Un utilisateur sur un canal mort est figé sur une version, sans mise à jour de sécurité, et sans avertissement. La péremption est donc surveillée **côté projet**, pas côté machine utilisateur : c'est au mainteneur de l'apprendre, pas à chaque shell de chaque utilisateur de le découvrir.

**Files:**
- Create: `.github/workflows/packaging-drift.yml`

- [ ] **Step 1: Write the failing test**

```bash
[ -f .github/workflows/packaging-drift.yml ]
grep -q 'schedule' .github/workflows/packaging-drift.yml
grep -q 'aur.archlinux.org/rpc' .github/workflows/packaging-drift.yml
! grep -qE 'secrets\.[A-Z_]*(TOKEN|KEY)' .github/workflows/packaging-drift.yml
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```yaml
# .github/workflows/packaging-drift.yml
name: Packaging drift

# Nocturne, sans secret, lecture seule. Pendant exact du canari de release :
# le mainteneur apprend la panne, pas l'utilisateur.
on:
  schedule:
    - cron: "17 4 * * *"
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - name: Version de la dernière release
        id: latest
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          v="$(gh release view -R maximeallanic/nivuus-shell --json tagName -q .tagName | sed 's/^v//')"
          echo "version=$v" >> "$GITHUB_OUTPUT"
          echo "Release : $v"

      - name: Version dans le tap Homebrew
        id: brew
        continue-on-error: true
        run: |
          set -euo pipefail
          # Lecture brute du fichier : aucune dépendance à brew.
          url="https://raw.githubusercontent.com/maximeallanic/homebrew-tap/main/Formula/nivuus-shell.rb"
          v="$(curl -fsSL "$url" | sed -n 's|.*/download/v\([0-9][0-9.]*\)/.*|\1|p' | head -1)"
          echo "version=${v:-absent}" >> "$GITHUB_OUTPUT"

      - name: Version dans l'AUR
        id: aur
        continue-on-error: true
        run: |
          set -euo pipefail
          v="$(curl -fsSL 'https://aur.archlinux.org/rpc/v5/info?arg=nivuus-shell' \
                | sed -n 's/.*"Version":"\([0-9][0-9.]*\)-[0-9]*".*/\1/p')"
          echo "version=${v:-absent}" >> "$GITHUB_OUTPUT"

      - name: Présence du .deb de cette version dans les assets
        id: deb
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          V="${{ steps.latest.outputs.version }}"
          if gh release view "v$V" -R maximeallanic/nivuus-shell --json assets \
               -q '.assets[].name' | grep -q "nivuus-shell_${V}_all.deb"; then
            echo "version=$V" >> "$GITHUB_OUTPUT"
          else
            echo "version=absent" >> "$GITHUB_OUTPUT"
          fi

      - name: Échouer bruyamment sur toute divergence
        run: |
          set -euo pipefail
          V="${{ steps.latest.outputs.version }}"
          bad=0
          for c in "homebrew=${{ steps.brew.outputs.version }}" \
                   "aur=${{ steps.aur.outputs.version }}" \
                   "deb=${{ steps.deb.outputs.version }}"; do
            name="${c%%=*}"; got="${c#*=}"
            if [ "$got" != "$V" ]; then
              echo "::error::canal $name en retard : $got (release : $V)"
              bad=1
            else
              echo "canal $name à jour : $got"
            fi
          done
          # Un canal en retard de plus de 24 h est une panne du mainteneur,
          # pas un aléa : le job doit être rouge, visiblement.
          exit "$bad"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `actionlint .github/workflows/packaging-drift.yml` + les quatre `grep`.
Expected: PASS. Le job lui-même sera rouge tant que les canaux n'existent pas — c'est correct : il dit la vérité. Le garder en `workflow_dispatch` seul (commenter le `schedule`) jusqu'à la publication du premier canal, avec un commentaire disant pourquoi.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/packaging-drift.yml
git commit -m "ci(packaging): nightly drift probe across the three channels"
```

---

### Task B10: test hebdomadaire d'installation **depuis les vrais canaux**

**Bloqué par : BL-9** (les canaux doivent être publiés).

**Pourquoi cette tâche existe :** installer une formule **localement** ne prouve pas que le tap est correctement publié, ni que `brew install user/tap/nivuus-shell` fonctionne. Un `makepkg` local ne prouve pas que l'AUR a accepté le push. Ces deux angles morts sont explicitement nommés par la spec § 6.3 — il faut les couvrir, ou les dire.

**Files:**
- Create: `.github/workflows/packaging-live.yml`

- [ ] **Step 1: Write the failing test**

```bash
[ -f .github/workflows/packaging-live.yml ]
grep -q 'maximeallanic/tap/nivuus-shell' .github/workflows/packaging-live.yml
grep -q 'run-package-target.sh' .github/workflows/packaging-live.yml
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```yaml
# .github/workflows/packaging-live.yml
name: Packaging (canaux réels)

# Hebdomadaire. Installer localement ne prouve PAS que le canal publié
# fonctionne : c'est le seul endroit où cette question est posée.
on:
  schedule:
    - cron: "23 5 * * 1"
  workflow_dispatch:

jobs:
  homebrew-live:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Installer depuis le VRAI tap
        run: |
          set -euo pipefail
          brew install maximeallanic/tap/nivuus-shell
          nivuus doctor
          nivuus update            # doit sortir en 0 et parler de brew
          nivuus enable --yes
          zsh -i -c 'print OK' 2>/tmp/err
          [ ! -s /tmp/err ]
          nivuus disable --yes
          brew uninstall nivuus-shell

  aur-live:
    runs-on: ubuntu-latest
    container: archlinux:latest
    steps:
      - uses: actions/checkout@v4
      - name: Installer depuis le VRAI AUR
        run: |
          set -euo pipefail
          pacman -Sy --noconfirm --needed base-devel git zsh
          useradd -m builder
          su builder -c '
            git clone https://aur.archlinux.org/nivuus-shell.git /tmp/aur
            cd /tmp/aur && makepkg -s --noconfirm
          '
          pacman -U --noconfirm /tmp/aur/*.pkg.tar.zst
          nivuus doctor && nivuus update

  deb-live:
    runs-on: ubuntu-latest
    container: debian:12
    steps:
      - uses: actions/checkout@v4
      - name: Installer le .deb ATTACHÉ à la dernière release
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          apt-get update -qq && apt-get install -y -qq curl zsh gh
          gh release download -R maximeallanic/nivuus-shell -p 'nivuus-shell_*_all.deb'
          apt-get install -y ./nivuus-shell_*_all.deb
          nivuus doctor && nivuus update
          apt-get purge -y nivuus-shell
          [ ! -e /usr/share/nivuus-shell ]

  ouvrir-une-issue:
    needs: [homebrew-live, aur-live, deb-live]
    if: failure()
    runs-on: ubuntu-latest
    permissions: { issues: write }
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner, repo: context.repo.repo,
              title: "packaging: un canal réel est cassé",
              labels: ['packaging'],
              body: "Le test hebdomadaire d'installation depuis les canaux publiés a échoué."
            });
```

Documenter aussi, dans `doc/PACKAGING.md`, **ce que les tests ne prouvent pas** (spec § 6.3) : aucun test ne couvre le cas d'une machine où **un autre** gestionnaire a déjà installé Nivuus. Ce cas « deux installations concurrentes » est traité par `doctor` (diagnostic), pas par la CI — et cela doit être écrit, comme la CI dit déjà que le job WSL est une simulation.

- [ ] **Step 4: Run test to verify it passes**

Run: `actionlint .github/workflows/packaging-live.yml` + les trois `grep`.
Expected: PASS. Exécution réelle possible dès BL-9.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/packaging-live.yml doc/PACKAGING.md
git commit -m "ci(packaging): weekly install test from the published channels"
```

---

### Task B11: documentation d'installation par canal

**Bloqué par : BL-9** — ne rien annoncer avant que la commande ne fonctionne réellement. Une documentation en avance sur la réalité coûte plus cher qu'une documentation absente : elle produit des rapports de bug sur une commande qui n'a jamais existé.

**Files:**
- Modify: `doc/INSTALL.md`, `README.md`, `doc/PACKAGING.md`
- Test: `tests/e2e/test_docs_channels.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_docs_channels.bats
#!/usr/bin/env bats
# Une commande d'installation par canal n'est documentée QUE si le canal est
# publié. Le test lit un fichier d'état pour savoir quels canaux sont vivants.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIVE="$ROOT/packaging/CHANNELS"      # une ligne par canal publié
}

channel_live() { [ -f "$LIVE" ] && grep -qx "$1" "$LIVE"; }

@test "homebrew is documented if and only if it is published" {
    if channel_live homebrew; then
        grep -q 'brew install maximeallanic/tap/nivuus-shell' "$ROOT/doc/INSTALL.md"
    else
        run grep -rn 'brew install .*nivuus-shell' "$ROOT/README.md" "$ROOT/doc/INSTALL.md"
        [ "$status" -ne 0 ]
    fi
}

@test "aur is documented if and only if it is published" {
    if channel_live aur; then
        grep -qE 'yay -S nivuus-shell|paru -S nivuus-shell' "$ROOT/doc/INSTALL.md"
    else
        run grep -rn 'yay -S nivuus-shell' "$ROOT/README.md" "$ROOT/doc/INSTALL.md"
        [ "$status" -ne 0 ]
    fi
}

@test "every documented channel tells the user to run nivuus enable next" {
    grep -q 'nivuus enable' "$ROOT/doc/INSTALL.md"
}

@test "every documented channel says auto-update is off there" {
    grep -qi 'gestionnaire' "$ROOT/doc/INSTALL.md"
}

@test "the one-liner stays the first documented option" {
    # Il ne bouge jamais : c'est la porte de sortie universelle, et la
    # raison de ne pas laisser les canaux dicter l'architecture.
    curl_line=$(grep -n 'install.sh | sh' "$ROOT/doc/INSTALL.md" | head -1 | cut -d: -f1)
    brew_line=$(grep -n 'brew install' "$ROOT/doc/INSTALL.md" | head -1 | cut -d: -f1)
    [ -z "$brew_line" ] || [ "$curl_line" -lt "$brew_line" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_docs_channels.bats`
Expected: FAIL — `packaging/CHANNELS` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `packaging/CHANNELS`, **vide** tant qu'aucun canal ne vit :

```
# packaging/CHANNELS — un canal publié par ligne (homebrew, aur, deb).
# Un canal n'est ajouté ici QUE lorsque sa commande d'installation
# fonctionne réellement pour un tiers. C'est ce fichier qui autorise la
# documentation à en parler (tests/e2e/test_docs_channels.bats).
```

Puis, **à chaque publication effective d'un canal**, ajouter sa ligne et la section correspondante de `doc/INSTALL.md` dans le même commit :

```markdown
### Homebrew (macOS et Linuxbrew)

    brew install maximeallanic/tap/nivuus-shell
    nivuus enable

Les mises à jour passent par Homebrew (`brew upgrade nivuus-shell`) : la mise
à jour automatique de Nivuus est désactivée sur ce canal.

### AUR (Arch Linux)

    yay -S nivuus-shell        # ou : paru -S nivuus-shell
    nivuus enable

### Debian / Ubuntu (.deb attaché à la release)

Télécharge `nivuus-shell_<version>_all.deb` depuis la page de release, puis :

    sudo apt install ./nivuus-shell_<version>_all.deb
    nivuus enable

Il n'y a **pas** de dépôt APT : ce canal sert le déploiement par
configuration système (Ansible, image de base, poste managé), où
l'automatisme est justement indésirable. Pour des mises à jour automatiques
sur Debian/Ubuntu, utilise le one-liner.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_docs_channels.bats tests/e2e/test_docs_packaging.bats`
Expected: PASS — 5 nouveaux tests (les deux premiers vérifient l'**absence** de promesse tant que `packaging/CHANNELS` est vide).

- [ ] **Step 5: Commit**

```bash
git add packaging/CHANNELS doc/INSTALL.md README.md doc/PACKAGING.md \
        tests/e2e/test_docs_channels.bats
git commit -m "docs(channels): gate per-channel install docs on actual publication"
```

---

## Silences de la spec, comblés par ce plan

Ces points n'étaient pas tranchés par la spec. Les décisions prises ici sont **révisables** — mais elles devaient l'être pour que le plan soit exécutable.

1. **Comment `disable` retire le bloc sans toucher à l'arbre.** La spec pose le comportement, pas le mécanisme. Le manifeste rejoue *tout* aujourd'hui. Choix : une fonction `nivuus_manifest_rollback_activation` qui ne rejoue que les entrées `MODIFY` et `CHSH` et les retire du manifeste, en réutilisant `nivuus_manifest_each` et `nivuus_restore_entry` inchangés. Alternative écartée : un second manifeste « activation », qui aurait créé un troisième inventaire là où la spec en veut exactement deux.
2. **Quel préfixe `enable` utilise par défaut.** Non dit. Choix : `${NIVUUS_SHELL_DIR:-$NIVUUS_SRC_ROOT}` — c'est-à-dire l'arbre depuis lequel `nivuus` est exécuté, ce qui fonctionne pour le wrapper Homebrew (qui exporte `NIVUUS_SHELL_DIR`) comme pour le symlink AUR/deb (résolu par la Task A2).
3. **`bin/nivuus update` doit-il déléguer à `zsh -ic`, comme aujourd'hui ?** La spec ne parle que du message. Choix : répondre **avant** la délégation, parce que le test « sort en 0 » doit pouvoir tourner dans un conteneur sans zsh interactif, et parce qu'un `exec zsh -ic` qui échoue produirait un code non nul en contradiction directe avec l'invariant.
4. **Le crochet de test pour la racine résolue.** La spec donne la boucle POSIX mais pas le moyen de l'observer. Choix : une sous-commande cachée `__srcroot`, gardée par `NIVUUS_PRINT_SRC_ROOT=1`, absente de `usage()`. Alternative écartée : tester indirectement par `nivuus help`, qui ne discrimine pas assez (il passerait aussi avec une racine fausse mais un `lib/` accessible).
5. **Où vivent les recettes dans l'arbre.** Non dit. Choix : `Formula/nivuus-shell.rb` à la racine (convention Homebrew, exigée par `brew install ./Formula/…`), `packaging/aur/` et `packaging/deb/` pour les deux autres. Les recettes ne sont **pas** copiées dans l'arbre installé (`nivuus_step_copy_tree` ne les liste pas) : elles n'ont rien à faire chez l'utilisateur.
6. **Quel `channel=` pour un empaqueteur tiers.** La spec liste `homebrew | aur | deb`. Choix : une valeur inconnue produit un message générique utilisable (« la commande de mise à jour de ton gestionnaire de paquets ») plutôt qu'un message vide ou une erreur — un tiers qui empaquette Nivuus correctement ne doit pas obtenir une sortie cassée.
7. **Comment mesurer « le temps de démarrage sur les six conteneurs, avec et sans `.zwc` »**, la spec l'exigeant comme livrable sans dire comment. Choix : `./bin/benchmark` (existant, cinq passages, moyenne) avec `NIVUUS_NO_COMPILE=1` pour le cas « sans », plus **une règle de décision écrite avant la mesure** (trois seuils, Task A8) pour qu'elle ne soit pas ajustée après coup, et un test de performance permanent qui garde le budget.
8. **Le format exact du fichier d'état des canaux publiés.** Rien dans la spec ; nécessaire pour que « ne rien annoncer qui n'existe pas » soit vérifiable par un test plutôt que par la vigilance. Choix : `packaging/CHANNELS`, une ligne par canal vivant, lu par `tests/e2e/test_docs_channels.bats`.
9. **Où `nivuus.1` vit dans le dépôt.** La spec dit qu'il est installé dans `/usr/share/man/man1/` par les trois formats, pas où il est écrit. Choix : `doc/nivuus.1`, copié dans l'arbre par `nivuus_step_copy_tree` pour que les trois recettes le trouvent au même endroit relatif — corollaire du § 3.3 (arbre identique).
10. **Que fait `disable --purge`.** Non dit. Choix : le même périmètre que `uninstall --purge` **moins** le manifeste lui-même (qui peut encore décrire un arbre installé en mode source) : horodatage de vérification de mise à jour et `~/.cache/nivuus-shell`, reconnus par leur nom exact, jamais par un motif large.
