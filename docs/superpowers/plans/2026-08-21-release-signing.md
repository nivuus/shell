# Signature cryptographique des releases — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le canal de mise à jour de Nivuus authentifié : `SHA256SUMS` est signé en CI par une clé détenue dans un GitHub Environment protégé, et le client refuse d'installer toute release dont la signature n'est pas valide contre l'une des clés publiques embarquées dans l'installation — sans jamais dégrader silencieusement vers la simple empreinte SHA256.

**Architecture:** La vérification est **extraite** du téléchargement pour devenir une fonction pure `_nivuus_verify_signature <sums_file> <sig_dir> [keys_dir]`, testable sans réseau et sans clé réelle. Le trousseau de confiance est un répertoire versionné `keys/` copié par l'installeur, contenant le jeu courant **et** le jeu de succession (rotation par pré-distribution). Deux chemins de vérification côté client — `openssl dgst -verify` (ECDSA P-256) puis `ssh-keygen -Y verify` (Ed25519 SSHSIG) — aucun binaire à installer. Ordre de la chaîne : signature d'abord, empreinte ensuite.

**Tech Stack:** zsh (client, `config/*.zsh`), bash 3.2 / POSIX ash (installeur, `lib/*.sh`), bats (tests), GitHub Actions, `openssl`, `ssh-keygen`.

**Spec:** `docs/superpowers/specs/2026-08-21-release-signing-design.md`

**Périmètre de ce plan :** les phases 1 à 4 du spec (§ 8). Les questions ouvertes du § 9 du spec ont été arbitrées par le propriétaire du projet ; les décisions sont reportées dans « Décisions actées » ci-dessous et **ne sont pas à rouvrir**.

---

## Décisions actées (ne pas rouvrir)

1. **Signature automatique en CI**, sans approbation humaine par release. Le GitHub Environment `release` reste le mécanisme de cloisonnement des secrets ; la règle de protection « réviseur requis » pourra être activée plus tard **sans changer une ligne de code**. Ne pas introduire d'étape d'attente manuelle dans le workflow.
2. **Pas de YubiKey / HSM, pas de signature depuis un poste local.** Hors périmètre.
3. **Pas de domaine hors GitHub.** L'ancrage hors bande reste intra-GitHub (README, `SECURITY.md`, profil du mainteneur). La documentation produite doit le **dire honnêtement**, sans le maquiller, et **sans badge « secure »** dans le README.
4. **Le `.asc` GPG est hors périmètre de ce plan.** L'architecture ne doit simplement pas l'empêcher plus tard : le job de signature est écrit de façon à accueillir une troisième signature sans restructuration (une étape supplémentaire, un secret supplémentaire).
5. **`NIVUUS_VERIFY_CHECKSUMS` est conservée mais réduite à l'étape d'empreinte SHA256.** Elle est documentée dans le README ; on ne la supprime pas. Elle ne doit **en aucun cas** permettre de désactiver la vérification de signature.
6. **Rotation annuelle**, avec acceptation multi-clés côté client **dès la première version signée**.
7. **Refus dur confirmé** (signature invalide, absente, ou aucun outil de vérification), avec l'unique échappatoire `NIVUUS_ALLOW_UNVERIFIED_UPDATE=1`, limitée à `nivuus-update` invoqué manuellement dans un terminal interactif et confirmée par une saisie. Sans effet sur `_nivuus_check_update_async`.

## Global Constraints

- **`config/*.zsh` est du ZSH** (globs `(N)`, `[[ ]]`, `local`). **`lib/*.sh` reste POSIX / BusyBox ash / bash 3.2** : interdits `declare -A`, `mapfile`, `${var^^}`, `local -n`, `&>>`, `[[ ]]` dans `lib/`.
- **Aucune nouvelle dépendance d'installation.** Les trois dépendances requises restent `zsh`, `git`, `curl`. `openssl` et `ssh-keygen` sont des dépendances **de la mise à jour**, pas de l'installation : leur absence est signalée à l'install et dans `doctor`, elle ne bloque jamais l'installation.
- **Jamais de `sudo`** non explicitement demandé par l'utilisateur.
- **Aucune clé privée dans le dépôt, ni dans les tests.** Chaque test génère son jeu éphémère dans `setup()`. Une tâche dédiée (Task 4) ajoute un test qui échoue si une clé privée est committée.
- **Le chemin du trousseau est un paramètre**, jamais une constante lue depuis l'environnement au moment de la vérification. Aucune variable d'environnement ne doit pouvoir substituer le trousseau en production.
- **Ordre de la chaîne de confiance : signature d'abord, empreinte ensuite.** Comparer une empreinte à un `SHA256SUMS` non authentifié n'a aucun sens.
- **Ne jamais « simplifier » le `grep "nivuus-shell-v${version}.tar.gz"` en `head -n1`** dans `SHA256SUMS` : le nom versionné fait partie du contenu signé, c'est ce qui bloque le rejeu inter-versions.
- **Cible de démarrage <300 ms.** `config/20-autoupdate.zsh` est sourcé à chaque démarrage : les nouvelles fonctions doivent être de simples définitions, aucun `command -v` ni accès disque au moment du source. `bats tests/performance/` doit rester vert.
- **Piège des `.zwc`** : zsh source le bytecode s'il est plus récent. Avant de lancer une suite qui touche `config/20-autoupdate.zsh`, faire `rm -f config/*.zwc`, sinon un test peut passer (ou échouer) contre une version périmée du module.
- **Codes de retour de la vérification** — contrat unique respecté partout : `0` = signature valide contre une clé de confiance ; `1` = signature invalide, absente, ou tronquée ; `2` = aucun outil de vérification disponible. `2` doit produire un message différent de `1` : ce n'est pas la même situation pour l'utilisateur.
- **Tests :** bats, `tests/unit/` pour les fonctions, `tests/e2e/` pour les scénarios de bout en bout. Les tests des fonctions zsh s'exécutent via `zsh -c 'source config/20-autoupdate.zsh; …'` avec `ENABLE_AUTOUPDATE=false` pour ne pas déclencher le bloc de vérification automatique au chargement.

## Dépendance avec le chantier « phase 3 multi-plateforme »

Un autre chantier en cours modifie `lib/steps.sh`, `lib/detect.sh` et `.github/workflows/tests.yml`. **Ce plan est écrit pour s'appliquer sur un `master` où la phase 3 est déjà mergée.** Points de contact, à vérifier avant de commencer :

| Fichier | Contact | Conduite à tenir |
|---|---|---|
| `lib/steps.sh` | Task 8 modifie la liste de répertoires de `nivuus_step_copy_tree`. **État constaté sur `master` au moment d'écrire ce plan : la phase 3 est déjà partiellement mergée** — `nivuus_step_copy_tree` itère via un fichier temporaire (plus de substitution de processus), `nivuus_step_check_required_deps` n'est plus qu'une façade sur `lib/deps.sh`, et `nivuus_step_chsh` a été ajoutée. | Rebaser avant Task 8, puis n'ajouter que `keys` à la liste `for d in config themes bin plugins lib` — **ne pas réécrire la fonction**, sa forme actuelle est délibérée (voir son commentaire sur le sous-shell). |
| `lib/deps.sh` | Task 9 ajoute la vérification consultative des outils de signature. La politique de dépendances vit désormais ici, pas dans `steps.sh`. | Écrire `nivuus_deps_check_verify_tools` dans `lib/deps.sh` et exposer la façade `nivuus_step_check_verify_tools` dans `lib/steps.sh`, sur le modèle exact de `nivuus_step_check_required_deps`. |
| `tests/unit/test_lib_posix.bats` | La phase 3 a ajouté une suite qui interdit dans `lib/*.sh` : les substitutions de processus (`< <(`), les tableaux bash, `BASH_SOURCE`, `${var,,}`, `declare -A`, `mapfile`, et exige `sh -n` propre. | Tout code écrit par ce plan dans `lib/` doit passer `bats tests/unit/test_lib_posix.bats`. Le vérifier avant chaque commit touchant `lib/`. Les fichiers de tests (bash) ne sont pas concernés. |
| `lib/detect.sh` | Aucune modification par ce plan. | Task 2 (sonde) consomme sa matrice d'images, elle ne modifie pas le fichier. |
| `.github/workflows/tests.yml` | Task 15 y ajoute l'exécution des nouvelles suites. La phase 3 y ajoute une matrice multi-plateforme. | Rebaser avant Task 15 et **ajouter les suites de signature à la matrice existante** plutôt que de créer un job `ubuntu-latest` isolé : les cas 8, 9 et 12 (repli `shasum`, absence d'outil) n'ont d'intérêt que s'ils tournent aussi sur macOS et Alpine. |
| Matrice d'images de la phase 3 | Task 2 (sonde de disponibilité) réutilise la même liste d'images. | Si la matrice de la phase 3 diffère de `ubuntu / debian / alpine / arch / fedora / macos`, aligner la sonde sur **sa** liste : la sonde doit mesurer les cibles réelles du projet, pas une liste théorique. |

## Ordre de merge imposé

Les tâches sont indépendantes et mergeables une par une, **à une exception près** : le refus dur côté client (Task 7) ne doit pas atteindre les utilisateurs avant que les releases ne soient effectivement signées (Task 12) et que le canari (Task 13) ne soit vert. Concrètement : Task 12 et 13 peuvent être mergées à tout moment (elles sont invisibles pour les clients existants), mais **aucune release publiée** ne doit contenir Task 7 tant qu'une release signée n'a pas été produite au moins une fois. Les tâches 3 à 7 peuvent être développées et mergées sur `master` avant ça — c'est la *publication* qui est contrainte, pas le merge.

---

### Task 1: Squelette du trousseau versionné `keys/`

**Files:**
- Create: `keys/README.md`
- Create: `keys/revoked`
- Create: `keys/.gitignore`
- Test: `tests/unit/test_keys_repo.bats`

**Interfaces:**
- Consumes: rien
- Produces: le répertoire `keys/` avec sa structure et son invariant « aucune clé privée ici, jamais ». Les vraies clés publiques arrivent en Task 11 (elles n'existent pas encore : elles sont générées hors ligne par le mainteneur).

Cette tâche pose d'abord le **garde-fou**, avant qu'une clé n'existe. C'est délibéré : le test qui interdit une clé privée dans le dépôt doit exister avant qu'il y ait la moindre occasion d'en committer une.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_keys_repo.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    KEYS="$ROOT/keys"
}

@test "the keys directory exists" {
    [ -d "$KEYS" ]
}

@test "a revoked list exists (may be empty)" {
    [ -f "$KEYS/revoked" ]
}

@test "no private key material is committed anywhere in the repo" {
    # Le motif couvre PEM PKCS#8, PEM traditionnel, EC, RSA et OpenSSH.
    run grep -rlE 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' \
        --exclude-dir=.git --exclude-dir=node_modules "$ROOT"
    [ "$status" -ne 0 ]
}

@test "every file in keys/ is a public artefact (pem, allowed_signers, revoked, doc)" {
    while IFS= read -r f; do
        case "$(basename "$f")" in
            *.pem|allowed_signers|revoked|README.md|.gitignore) ;;
            *) printf 'fichier inattendu dans keys/ : %s\n' "$f"; return 1 ;;
        esac
    done < <(find "$KEYS" -type f)
}

@test "every .pem in keys/ is a parseable EC public key" {
    local found=0 f
    while IFS= read -r f; do
        found=1
        run openssl pkey -pubin -in "$f" -noout
        [ "$status" -eq 0 ]
    done < <(find "$KEYS" -name '*.pem' -type f)
    # Aucune clé encore committée à ce stade : le test est vrai par vacuité,
    # et devient contraignant dès la Task 11.
    [ "$found" -eq 0 ] || [ "$found" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_keys_repo.bats`
Expected: FAIL — `keys/` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```bash
mkdir -p keys
: > keys/revoked
```

```gitignore
# keys/.gitignore
# Ceinture et bretelles : aucune clé privée ne doit pouvoir arriver ici,
# même par un `git add -A` distrait. Le test de la suite unitaire est la
# vérification ; ceci est la prévention.
*.key
*_priv*
id_*
!id_*.pub
```

```markdown
<!-- keys/README.md -->
# Trousseau de confiance des releases Nivuus

Ce répertoire contient **uniquement du matériel public**. Toute clé privée qui
y apparaîtrait serait une compromission, pas une erreur de rangement.

| Fichier | Rôle |
|---|---|
| `nivuus-release-<année>.pem` | Clé publique ECDSA P-256, chemin de vérification `openssl` |
| `allowed_signers` | Clés publiques Ed25519 au format `ssh-keygen -Y`, chemin de repli |
| `revoked` | Empreintes révoquées, une par ligne. Une clé listée ici est refusée même si elle est encore présente ci-dessus. |

Le trousseau contient toujours **au moins deux jeux** : le jeu courant, qui
signe les releases d'aujourd'hui, et le jeu de succession, pré-distribué pour
que la rotation ne demande jamais d'action à l'utilisateur (voir
`doc/SIGNING.md`).

Le client accepte une release si sa signature est valide contre **l'un
quelconque** des jeux présents et non révoqués.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_keys_repo.bats`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add keys tests/unit/test_keys_repo.bats
git commit -m "feat(keys): add versioned trust store skeleton with no-private-key guard"
```

---

### Task 2: Sonde de disponibilité de `openssl` et `ssh-keygen`

**Files:**
- Create: `.github/workflows/verify-tools-probe.yml`
- Create: `doc/SIGNING.md` (section « Disponibilité des outils », le reste est écrit en Task 16)

**Interfaces:**
- Consumes: la matrice d'images de la phase 3 (voir « Dépendance » ci-dessus)
- Produces: un tableau de faits publié dans le résumé du workflow **et** recopié dans `doc/SIGNING.md`, qui tranche l'ordre primaire/repli.

**Pourquoi cette tâche est la première du code.** Le § 1 du spec pose `openssl` en primaire et `ssh-keygen` en repli sur la base d'un raisonnement, pas d'une mesure. Si les données montrent l'inverse (par exemple `openssl` absent des images Alpine et Debian slim de base alors que `ssh-keygen` y est présent), **la hiérarchie s'inverse** et les tâches 5 et 6 sont écrites dans l'autre ordre. Le coût de mesurer est d'une heure ; le coût de se tromper est un chemin de repli qui porte tout le trafic réel sans jamais avoir été pensé comme tel.

**Ce que la sonde mesure exactement :** la présence des deux binaires dans une image **de base non modifiée**, sans installation préalable — plus la version, parce que `ssh-keygen -Y verify` exige OpenSSH ≥ 8.2 et que `openssl dgst -verify` doit être testé, pas seulement trouvé (LibreSSL sur macOS).

- [ ] **Step 1: Write the probe**

```yaml
# .github/workflows/verify-tools-probe.yml
name: Verify tools availability probe

on:
  workflow_dispatch:

jobs:
  linux:
    name: Probe ${{ matrix.image }}
    runs-on: ubuntu-latest
    container: ${{ matrix.image }}
    strategy:
      fail-fast: false
      matrix:
        # Aligner cette liste sur la matrice de la phase 3 si elle diffère.
        image: [ubuntu:22.04, ubuntu:24.04, debian:12-slim, alpine:3.20, archlinux:latest, fedora:40]
    steps:
      - name: Probe
        shell: sh
        run: |
          # Aucune installation : on mesure l'image telle qu'elle est livrée.
          probe() {
            if command -v "$1" >/dev/null 2>&1; then
              printf '%s\tPRESENT\t%s\n' "$1" "$($2 2>&1 | head -1)"
            else
              printf '%s\tABSENT\t-\n' "$1"
            fi
          }
          echo "=== ${{ matrix.image }}"
          probe openssl    "openssl version"
          probe ssh-keygen "ssh -V"
          probe sha256sum  "sha256sum --version"
          probe shasum     "shasum --version"

      - name: Functional check (not just presence)
        shell: sh
        continue-on-error: true
        run: |
          # Trouver le binaire ne suffit pas : on vérifie qu'il sait
          # réellement faire l'opération dont dépend le client.
          if command -v openssl >/dev/null 2>&1; then
            openssl ecparam -name prime256v1 -genkey -noout -out /tmp/k.pem
            openssl ec -in /tmp/k.pem -pubout -out /tmp/k.pub 2>/dev/null
            echo payload > /tmp/p
            openssl dgst -sha256 -sign /tmp/k.pem -out /tmp/p.sig /tmp/p
            openssl dgst -sha256 -verify /tmp/k.pub -signature /tmp/p.sig /tmp/p \
              && echo "openssl dgst -verify: OK" || echo "openssl dgst -verify: KO"
          fi
          if command -v ssh-keygen >/dev/null 2>&1; then
            ssh-keygen -q -t ed25519 -N '' -f /tmp/id -C probe
            printf 'probe %s\n' "$(cat /tmp/id.pub)" > /tmp/allowed
            echo payload > /tmp/p
            ssh-keygen -Y sign -f /tmp/id -n nivuus-release /tmp/p 2>/dev/null
            ssh-keygen -Y verify -f /tmp/allowed -I probe -n nivuus-release \
              -s /tmp/p.sig < /tmp/p \
              && echo "ssh-keygen -Y verify: OK" || echo "ssh-keygen -Y verify: KO"
          fi

  macos:
    name: Probe macOS
    runs-on: macos-latest
    steps:
      - name: Probe
        run: |
          command -v openssl && openssl version || echo "openssl ABSENT"
          command -v ssh-keygen && ssh -V || echo "ssh-keygen ABSENT"
          command -v sha256sum || echo "sha256sum ABSENT (attendu sur macOS)"
          command -v shasum && shasum --version || echo "shasum ABSENT"
```

- [ ] **Step 2: Run the probe and collect the data**

Run: `gh workflow run verify-tools-probe.yml` puis `gh run watch`
Expected: un job par image, aucun ne doit être supprimé de la liste même s'il échoue — un échec **est** une donnée.

- [ ] **Step 3: Record the result and decide**

Recopier le tableau obtenu dans `doc/SIGNING.md` sous ce format, avec la date de la mesure :

```markdown
## Disponibilité des outils de vérification (mesuré le AAAA-MM-JJ)

| Image | `openssl` | `dgst -verify` | `ssh-keygen` | `-Y verify` | `sha256sum` | `shasum` |
|---|---|---|---|---|---|---|
| ubuntu:24.04 | | | | | | |
| debian:12-slim | | | | | | |
| alpine:3.20 | | | | | | |
| archlinux | | | | | | |
| fedora:40 | | | | | | |
| macos-latest | | | | | | |

**Décision d'ordre :** primaire = …, repli = …
**Motif :** …
```

Règle de décision, à appliquer mécaniquement : **le chemin primaire est celui qui est fonctionnel sur le plus grand nombre d'images**, à égalité celui qui est fonctionnel sur macOS. Si `ssh-keygen` gagne, les tâches 5 et 6 sont simplement écrites dans l'ordre inverse — le contrat de `_nivuus_verify_signature` (codes 0/1/2, trousseau en paramètre) ne change pas, seul l'ordre des deux blocs internes change. **Le reste du plan est écrit en supposant `openssl` primaire ; si la sonde le contredit, inverser les blocs et le noter en tête de la Task 5.**

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/verify-tools-probe.yml doc/SIGNING.md
git commit -m "ci(probe): measure openssl/ssh-keygen availability across target images"
```

---

### Task 3: Repli `shasum` dans l'updater — correction du déni de service macOS

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Test: `tests/unit/test_autoupdate_sha256.bats`
- Create: `tests/helpers/signing.bash`

**Interfaces:**
- Consumes: rien
- Produces: `_nivuus_sha256_of <file>` — imprime l'empreinte SHA-256 hexadécimale minuscule du fichier ; retourne 1 si le fichier est illisible **ou** si aucun outil n'est disponible, sans rien imprimer.

**C'est un bug réel, pas une préparation.** Aujourd'hui `_nivuus_download_release` appelle `sha256sum` sans repli. `sha256sum` n'existe pas par défaut sur macOS. `actual_sum` y est donc vide, la comparaison échoue toujours, et **toute mise à jour est cassée sur macOS** — la vérification y est un déni de service, pas une garantie. `lib/manifest.sh` gère déjà les deux outils dans `nivuus_hash_file` ; on aligne l'updater.

Cette tâche est traitée tôt parce qu'elle est indépendante de tout le reste du chantier, mergeable seule, et corrige une panne en production.

- [ ] **Step 1: Write the failing test**

```bash
# tests/helpers/signing.bash
# Helpers partagés par les suites de signature.
# Aucune clé réelle ici : tout est généré à la volée dans setup().

# Construit un PATH minimal ne contenant QUE les outils nommés.
# Sert à simuler « sha256sum absent », « openssl absent », etc.
# Les symlinks pointent vers les vrais binaires : on retire des outils,
# on n'en simule aucun.
mkfakepath() {
    local dir="$1"; shift
    mkdir -p "$dir"
    local t p
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null)" || continue
        ln -sf "$p" "$dir/$t"
    done
    printf '%s\n' "$dir"
}

# Exécute du code zsh avec config/20-autoupdate.zsh chargé.
# ENABLE_AUTOUPDATE=false empêche le bloc de vérification automatique de
# partir en arrière-plan pendant les tests.
zsh_autoupdate() {
    ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; $1"
}
```

```bash
# tests/unit/test_autoupdate_sha256.bats
#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    printf 'abc' > "$TMP/abc"
    # Le bytecode périmé masquerait la nouvelle version du module.
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

@test "sha256_of returns the known digest of 'abc'" {
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of works with shasum only (macOS regression)" {
    fake="$(mkfakepath "$TMP/bin" shasum awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of works with sha256sum only" {
    fake="$(mkfakepath "$TMP/bin" sha256sum awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of fails loudly when no hashing tool exists" {
    fake="$(mkfakepath "$TMP/bin" awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -ne 0 ]
    # Surtout : ne JAMAIS imprimer une chaîne vide qu'un appelant
    # comparerait à une empreinte attendue.
    [ "$output" = "" ]
}

@test "sha256_of fails on a missing file" {
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/nope'"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "sha256_of handles a path with spaces" {
    printf 'abc' > "$TMP/with space"
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/with space'"
    [ "$output" = "$ABC" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_autoupdate_sha256.bats`
Expected: FAIL — `_nivuus_sha256_of: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter dans `config/20-autoupdate.zsh`, juste avant `_nivuus_download_release` :

```zsh
# Empreinte SHA-256 portable. Fonction pure : ne télécharge rien, ne
# dépend d'aucun état global.
#
# Historique : cette fonction existe parce que _nivuus_download_release
# appelait `sha256sum` sans repli. `sha256sum` n'existe pas par défaut sur
# macOS (`shasum` y est l'outil livré) : `actual_sum` y était vide, la
# comparaison échouait toujours, et TOUTE mise à jour était cassée sur
# macOS. lib/manifest.sh gérait déjà les deux cas ; l'updater non.
#
# Retourne 1 sans rien imprimer si aucun outil n'est disponible. Le
# « sans rien imprimer » est la partie importante : une chaîne vide
# comparée à une empreinte attendue est un faux négatif silencieux.
_nivuus_sha256_of() {
    local file=$1
    [[ -r "$file" ]] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        # Dernier recours : openssl est de toute façon requis par le
        # chemin de signature sur la plupart des machines.
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        return 1
    fi
}
```

Puis, dans `_nivuus_download_release`, remplacer :

```zsh
        local actual_sum=$(sha256sum "$temp_dir/nivuus-shell.tar.gz" | awk '{print $1}')
```

par :

```zsh
        local actual_sum
        if ! actual_sum=$(_nivuus_sha256_of "$temp_dir/nivuus-shell.tar.gz"); then
            echo "❌ Aucun outil SHA-256 disponible (sha256sum, shasum ou openssl requis)"
            rm -rf "$temp_dir"
            return 1
        fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_sha256.bats`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_sha256.bats tests/helpers/signing.bash
git commit -m "fix(autoupdate): add shasum fallback, updates were broken on macOS"
```

---

### Task 4: Les deux invariants — `_nivuus_verify_signature`, chemin `openssl`

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Modify: `tests/helpers/signing.bash`
- Test: `tests/unit/test_release_signature.bats`

**Interfaces:**
- Consumes: rien (fonction pure)
- Produces: `_nivuus_verify_signature <sums_file> <sig_dir> [keys_dir]` — `0` si la signature de `<sums_file>` est valide contre une clé de confiance non révoquée de `<keys_dir>` ; `1` si invalide/absente ; `2` si aucun outil de vérification n'est disponible. `keys_dir` par défaut `$NIVUUS_SHELL_DIR/keys`, **passé en paramètre par les tests**.

**Cette tâche porte les deux tests qui comptent**, et ils sont écrits en premier :

- **Cas 3 — archive falsifiée avec `SHA256SUMS` régénéré et resigné par une clé d'attaquant ⇒ refus.** C'est le scénario réel : un attaquant qui remplace l'asset remplace aussi la somme et sa signature. Sans ce test, rien ne prouve que la clé de confiance sert à quelque chose.
- **Cas 9 — aucun outil de vérification disponible ⇒ refus.** Il prouve l'absence de dégradation silencieuse. Une suite qui ne teste que le cas nominal passerait aussi avec `return 0`.

Le chemin de repli SSHSIG arrive en Task 5 ; ici, seul le cas 9 (les **deux** outils absents) est couvert côté outillage.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/helpers/signing.bash` :

```bash
# Génère un jeu de clés éphémère complet dans $1.
# Produit : priv.pem / pub.pem (ECDSA P-256), id / id.pub (Ed25519),
# et un keys/ prêt à être passé en paramètre à _nivuus_verify_signature.
gen_keyset() {
    local dir="$1" name="${2:-nivuus-test}"
    mkdir -p "$dir/keys"
    openssl ecparam -name prime256v1 -genkey -noout -out "$dir/priv.pem" 2>/dev/null
    openssl ec -in "$dir/priv.pem" -pubout -out "$dir/keys/$name.pem" 2>/dev/null
    ssh-keygen -q -t ed25519 -N '' -f "$dir/id" -C "$name"
    printf 'nivuus-release %s\n' "$(cat "$dir/id.pub")" > "$dir/keys/allowed_signers"
    : > "$dir/keys/revoked"
}

# Signe $2 avec le jeu de $1, dépose les signatures dans $3.
sign_sums() {
    local keydir="$1" sums="$2" outdir="$3"
    mkdir -p "$outdir"
    openssl dgst -sha256 -sign "$keydir/priv.pem" \
        -out "$outdir/SHA256SUMS.sig" "$sums"
    ssh-keygen -Y sign -q -f "$keydir/id" -n nivuus-release \
        -O 2>/dev/null <"$sums" >"$outdir/SHA256SUMS.sshsig" 2>/dev/null \
        || ssh-keygen -Y sign -q -f "$keydir/id" -n nivuus-release "$sums" 2>/dev/null \
        && [ -f "$sums.sig" ] && mv "$sums.sig" "$outdir/SHA256SUMS.sshsig"
    return 0
}
```

> Note d'implémentation du helper : `ssh-keygen -Y sign` écrit `<fichier>.sig` à côté du fichier signé et n'a pas d'option `-out` portable. Le helper le déplace ensuite sous le nom attendu. Si la double forme ci-dessus s'avère fragile sur la version d'OpenSSH de la machine, la remplacer par la forme simple `ssh-keygen -Y sign -f "$keydir/id" -n nivuus-release "$sums" && mv "$sums.sig" "$outdir/SHA256SUMS.sshsig"` — c'est un helper de test, sa lisibilité prime.

```bash
# tests/unit/test_release_signature.bats
#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    rm -f "$ROOT"/config/*.zwc

    # Jeu de clés légitime, éphémère. Jamais de vraie clé dans un test.
    gen_keyset "$TMP/legit"
    # Jeu de clés d'attaquant : mêmes propriétés, autre porteur.
    gen_keyset "$TMP/evil"

    # Une fausse release : une archive et son SHA256SUMS.
    mkdir -p "$TMP/rel"
    printf 'contenu authentique\n' > "$TMP/rel/nivuus-shell-v9.9.9.tar.gz"
    ( cd "$TMP/rel" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/legit" "$TMP/rel/SHA256SUMS" "$TMP/rel"
}

teardown() { rm -rf "$TMP"; }

verify() {
    zsh_autoupdate "_nivuus_verify_signature '$1' '$2' '$3'; echo rc=\$?"
}

# ---------------------------------------------------------------------
# LES DEUX INVARIANTS DU CHANTIER
# ---------------------------------------------------------------------

@test "INVARIANT: a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" {
    # Scénario réel : l'attaquant remplace l'archive, régénère SHA256SUMS
    # pour qu'il décrive SON archive, et le signe avec SA clé. Tout est
    # cohérent — sauf que la clé n'est pas dans le trousseau.
    printf 'charge utile malveillante\n' > "$TMP/rel/nivuus-shell-v9.9.9.tar.gz"
    ( cd "$TMP/rel" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/evil" "$TMP/rel/SHA256SUMS" "$TMP/rel"

    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "INVARIANT: no verification tool at all is REFUSED, never silently downgraded" {
    fake="$(mkfakepath "$TMP/bin" awk zsh cat grep)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_signature '$TMP/rel/SHA256SUMS' '$TMP/rel' '$TMP/legit/keys'; echo rc=\$?"
    # rc=2 : « aucun outil », distinct de rc=1 « invalide ». Jamais 0.
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" != *"rc=0"* ]]
}

# ---------------------------------------------------------------------
# Le reste de la matrice du spec (§ 6)
# ---------------------------------------------------------------------

@test "case 1: intact SHA256SUMS with a valid signature is accepted" {
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=0"* ]]
}

@test "case 2: SHA256SUMS altered by one byte is refused" {
    printf 'x' >> "$TMP/rel/SHA256SUMS"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 5: a missing .sig is refused (no SHA256 fallback)" {
    rm -f "$TMP/rel/SHA256SUMS.sig" "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 6: a truncated or empty .sig is refused without stray zsh errors" {
    : > "$TMP/rel/SHA256SUMS.sig"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" != *"parse error"* ]]
    [[ "$output" != *"no such file"* ]]
}

@test "case 6b: a non-binary garbage .sig is refused" {
    printf 'not a signature at all\n' > "$TMP/rel/SHA256SUMS.sig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 7: a valid signature of ANOTHER SHA256SUMS is refused (cross-version replay)" {
    mkdir -p "$TMP/other"
    printf 'autre release\n' > "$TMP/other/nivuus-shell-v8.8.8.tar.gz"
    ( cd "$TMP/other" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/legit" "$TMP/other/SHA256SUMS" "$TMP/other"
    # Signature authentique... mais d'un autre contenu.
    cp "$TMP/other/SHA256SUMS.sig" "$TMP/rel/SHA256SUMS.sig"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 10: a revoked key is refused even though it is still in the store" {
    fp="$( { sha256sum "$TMP/legit/keys/nivuus-test.pem" 2>/dev/null \
             || shasum -a 256 "$TMP/legit/keys/nivuus-test.pem"; } | awk '{print $1}' )"
    printf 'sha256:%s\n' "$fp" > "$TMP/legit/keys/revoked"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 11: with two trusted keys, a signature from the second one is accepted (rotation)" {
    gen_keyset "$TMP/next" nivuus-next
    # Le trousseau du client contient les deux jeux : l'ancien et le
    # successeur pré-distribué.
    cp "$TMP/next/keys/nivuus-next.pem" "$TMP/legit/keys/"
    # La release est signée par le SUCCESSEUR.
    sign_sums "$TMP/next" "$TMP/rel/SHA256SUMS" "$TMP/rel"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=0"* ]]
}

@test "an empty key store refuses everything" {
    mkdir -p "$TMP/emptykeys"
    : > "$TMP/emptykeys/revoked"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/emptykeys"
    [[ "$output" == *"rc=1"* ]]
}

@test "a missing SHA256SUMS is refused" {
    run verify "$TMP/nope" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_release_signature.bats`
Expected: FAIL — `_nivuus_verify_signature: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter dans `config/20-autoupdate.zsh`, après `_nivuus_sha256_of` :

```zsh
# Empreinte d'un fichier de clé publique PEM, telle qu'inscrite dans
# keys/revoked. Format : « sha256:<hex> ».
_nivuus_key_fingerprint() {
    local pem=$1 digest
    digest=$(_nivuus_sha256_of "$pem") || return 1
    printf 'sha256:%s\n' "$digest"
}

_nivuus_key_is_revoked() {
    local pem=$1 keys_dir=$2 fp
    [[ -r "$keys_dir/revoked" ]] || return 1
    fp=$(_nivuus_key_fingerprint "$pem") || return 1
    grep -qxF "$fp" "$keys_dir/revoked" 2>/dev/null
}

# Vérifie la signature de SHA256SUMS contre le trousseau de confiance.
#
# Fonction PURE : ne télécharge rien, n'écrit rien, ne lit aucun état
# global autre que le défaut de keys_dir. C'est ce qui la rend testable
# sans réseau — la raison pour laquelle il n'existait aucun test de cette
# logique jusqu'ici.
#
# keys_dir est un PARAMÈTRE et non une variable d'environnement : les
# tests injectent un jeu éphémère sans qu'aucune porte de contournement
# n'existe en production.
#
#   $1  chemin du fichier SHA256SUMS à authentifier
#   $2  répertoire contenant SHA256SUMS.sig et/ou SHA256SUMS.sshsig
#   $3  répertoire du trousseau (défaut : $NIVUUS_SHELL_DIR/keys)
#
# Retour : 0 = signature valide contre une clé de confiance
#          1 = signature invalide, absente ou illisible
#          2 = aucun outil de vérification disponible sur cette machine
_nivuus_verify_signature() {
    local sums=$1 sig_dir=$2 keys_dir=${3:-$NIVUUS_SHELL_DIR/keys}
    local have_tool=0 key

    [[ -r "$sums" ]] || return 1

    # --- Chemin primaire : openssl / ECDSA P-256 -----------------------
    if command -v openssl >/dev/null 2>&1; then
        have_tool=1
        local sig="$sig_dir/SHA256SUMS.sig"
        if [[ -s "$sig" ]]; then
            for key in "$keys_dir"/*.pem(N); do
                _nivuus_key_is_revoked "$key" "$keys_dir" && continue
                if openssl dgst -sha256 -verify "$key" \
                        -signature "$sig" "$sums" >/dev/null 2>&1; then
                    return 0
                fi
            done
        fi
    fi

    # --- Chemin de repli : ssh-keygen / SSHSIG (Task 5) ----------------
    # (ajouté dans la tâche suivante ; le compteur have_tool y est
    #  incrémenté de la même façon)

    (( have_tool )) || return 2
    return 1
}
```

Note : `*.pem(N)` est le glob zsh « nullglob local » — sans le `(N)`, un
trousseau vide ferait boucler sur le motif littéral.

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_release_signature.bats`
Expected: PASS, 12 tests. Les deux tests `INVARIANT:` doivent être verts — s'ils ne le sont pas, **ne pas assouplir le test**, corriger la fonction.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_release_signature.bats tests/helpers/signing.bash
git commit -m "feat(autoupdate): add pure signature verification against a pinned key store"
```

---

### Task 5: Chemin de repli `ssh-keygen -Y verify`

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Modify: `tests/unit/test_release_signature.bats`

> **Si la sonde de la Task 2 a inversé la hiérarchie**, écrire ce bloc *avant* le bloc `openssl` dans la fonction et adapter les deux tests ci-dessous en conséquence. Le contrat (0/1/2, trousseau en paramètre) ne change pas.

**Interfaces:**
- Consumes: `_nivuus_verify_signature` (Task 4)
- Produces: la même fonction, capable de valider `SHA256SUMS.sshsig` via `keys/allowed_signers` quand `openssl` est absent ou que la signature ECDSA ne valide pas.

Sans ce repli, toute machine sans `openssl` perd l'auto-update — et le § 4 du spec impose le refus dur, donc cette perte serait définitive et silencieuse. Le coût du double format est assumé pour cette raison précise.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_release_signature.bats` :

```bash
@test "case 8: openssl absent, ssh-keygen present, SSHSIG is accepted" {
    fake="$(mkfakepath "$TMP/bin" ssh-keygen sha256sum shasum awk zsh grep cat)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_signature '$TMP/rel/SHA256SUMS' '$TMP/rel' '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=0"* ]]
}

@test "case 8b: openssl absent and the SSHSIG was made by an attacker key: refused" {
    sign_sums "$TMP/evil" "$TMP/rel/SHA256SUMS" "$TMP/rel"
    fake="$(mkfakepath "$TMP/bin" ssh-keygen sha256sum shasum awk zsh grep cat)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_signature '$TMP/rel/SHA256SUMS' '$TMP/rel' '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 8c: openssl absent and no allowed_signers in the store: refused" {
    rm -f "$TMP/legit/keys/allowed_signers"
    fake="$(mkfakepath "$TMP/bin" ssh-keygen sha256sum shasum awk zsh grep cat)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_signature '$TMP/rel/SHA256SUMS' '$TMP/rel' '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=1"* ]]
}

@test "an ECDSA signature that fails does not prevent a valid SSHSIG from being accepted" {
    # Les deux formats sont présents ; le .sig est corrompu, le .sshsig
    # est bon. Le client doit passer au repli plutôt que d'abandonner.
    printf 'corrompu' > "$TMP/rel/SHA256SUMS.sig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=0"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_release_signature.bats`
Expected: FAIL — les quatre nouveaux tests donnent `rc=2` ou `rc=1` : le chemin SSHSIG n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Remplacer le commentaire « Chemin de repli » de `_nivuus_verify_signature` par :

```zsh
    # --- Chemin de repli : ssh-keygen / SSHSIG -------------------------
    # Sur les machines sans openssl (fréquent sur les serveurs et
    # certaines images minimales), OpenSSH est presque toujours là.
    # Sans ce repli, le refus dur du § 4 supprimerait définitivement
    # l'auto-update sur toute une classe de machines.
    if command -v ssh-keygen >/dev/null 2>&1; then
        have_tool=1
        local sshsig="$sig_dir/SHA256SUMS.sshsig"
        local allowed="$keys_dir/allowed_signers"
        if [[ -s "$sshsig" && -s "$allowed" ]]; then
            local filtered
            filtered=$(mktemp "${TMPDIR:-/tmp}/nivuus-signers.XXXXXX") || return 1
            _nivuus_filter_revoked_signers "$allowed" "$keys_dir" > "$filtered"
            if [[ -s "$filtered" ]] && \
               ssh-keygen -Y verify -f "$filtered" -I nivuus-release \
                   -n nivuus-release -s "$sshsig" < "$sums" >/dev/null 2>&1; then
                rm -f "$filtered"
                return 0
            fi
            rm -f "$filtered"
        fi
    fi
```

Et ajouter, au-dessus de `_nivuus_verify_signature` :

```zsh
# Recopie allowed_signers en retirant les lignes dont la clé publique est
# listée dans keys/revoked. ssh-keygen n'ayant pas de notion de
# révocation utilisable ici, on la matérialise en amont.
# Empreinte utilisée : celle de `ssh-keygen -lf` (« SHA256:… »).
_nivuus_filter_revoked_signers() {
    local allowed=$1 keys_dir=$2 line pub fp tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/nivuus-pub.XXXXXX") || return 1
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # Format : « <principal> <type> <base64> [commentaire] »
        printf '%s\n' "${line#* }" > "$tmp"
        fp=$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}')
        if [[ -n "$fp" ]] && [[ -r "$keys_dir/revoked" ]] && \
           grep -qxF "$fp" "$keys_dir/revoked" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$line"
    done < "$allowed"
    rm -f "$tmp"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_release_signature.bats`
Expected: PASS, 16 tests. Le test `INVARIANT: no verification tool at all` doit toujours donner `rc=2`.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_release_signature.bats
git commit -m "feat(autoupdate): add SSHSIG fallback for machines without openssl"
```

---

### Task 6: Extraction de la vérification hors du téléchargement

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Test: `tests/unit/test_autoupdate_download.bats`

**Interfaces:**
- Consumes: `_nivuus_verify_signature`, `_nivuus_sha256_of`
- Produces:
  - `_nivuus_verify_release <temp_dir> <version> [keys_dir]` — fonction pure, sans réseau : vérifie d'abord la signature de `<temp_dir>/SHA256SUMS`, puis l'empreinte de `<temp_dir>/nivuus-shell.tar.gz` contre la ligne `nivuus-shell-v<version>.tar.gz`. Retourne `0`, `1` (refus) ou `2` (aucun outil).
  - `NIVUUS_RELEASE_BASE_URL` — variable surchargeable, par défaut `https://github.com/$NIVUUS_GITHUB_REPO/releases/download`. Existe pour rendre l'e2e possible sans réseau (`file://`), pas pour la production.

C'est l'extraction que le spec réclame : aujourd'hui la vérification est imbriquée dans `_nivuus_download_release`, donc intestable sans réseau — raison pour laquelle il n'existe aucun test de cette logique. On sépare « aller chercher » de « décider si c'est acceptable ».

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_download.bats
#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    rm -f "$ROOT"/config/*.zwc

    gen_keyset "$TMP/legit"
    gen_keyset "$TMP/evil"

    # Un répertoire temporaire de téléchargement, tel que
    # _nivuus_download_release le produit.
    DL="$TMP/dl"; mkdir -p "$DL"
    printf 'archive authentique\n' > "$DL/nivuus-shell.tar.gz"
    # SHA256SUMS décrit l'archive sous son nom VERSIONNÉ.
    sum="$( { sha256sum "$DL/nivuus-shell.tar.gz" 2>/dev/null \
              || shasum -a 256 "$DL/nivuus-shell.tar.gz"; } | awk '{print $1}' )"
    printf '%s  nivuus-shell-v9.9.9.tar.gz\n' "$sum" > "$DL/SHA256SUMS"
    sign_sums "$TMP/legit" "$DL/SHA256SUMS" "$DL"
}

teardown() { rm -rf "$TMP"; }

vrel() {
    zsh_autoupdate "_nivuus_verify_release '$DL' '$1' '$TMP/legit/keys'; echo rc=\$?"
}

@test "a fully valid release verifies" {
    run vrel 9.9.9
    [[ "$output" == *"rc=0"* ]]
}

@test "signature is checked BEFORE the digest" {
    # SHA256SUMS non signé mais cohérent avec l'archive : accepter
    # reviendrait à faire confiance à une somme non authentifiée.
    rm -f "$DL/SHA256SUMS.sig" "$DL/SHA256SUMS.sshsig"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "case 4: forged archive with an authentic signed SHA256SUMS is refused on the digest" {
    printf 'charge utile malveillante\n' > "$DL/nivuus-shell.tar.gz"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "case 3 end-to-end: forged archive + attacker-signed SHA256SUMS is refused" {
    printf 'charge utile malveillante\n' > "$DL/nivuus-shell.tar.gz"
    sum="$( { sha256sum "$DL/nivuus-shell.tar.gz" 2>/dev/null \
              || shasum -a 256 "$DL/nivuus-shell.tar.gz"; } | awk '{print $1}' )"
    printf '%s  nivuus-shell-v9.9.9.tar.gz\n' "$sum" > "$DL/SHA256SUMS"
    sign_sums "$TMP/evil" "$DL/SHA256SUMS" "$DL"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "cross-version replay: a signed SHA256SUMS for another version is refused" {
    # Signature valide, archive valide, mais la ligne cherchée est celle
    # de la version demandée : elle n'y est pas.
    run vrel 8.8.8
    [[ "$output" == *"rc=1"* ]]
}

@test "no verification tool returns 2, not 0" {
    fake="$(mkfakepath "$TMP/bin" awk zsh grep cat sha256sum shasum)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=2"* ]]
}

@test "NIVUUS_VERIFY_CHECKSUMS=false does NOT disable signature verification" {
    rm -f "$DL/SHA256SUMS.sig" "$DL/SHA256SUMS.sshsig"
    run env ENABLE_AUTOUPDATE=false NIVUUS_VERIFY_CHECKSUMS=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=1"* ]]
}

@test "NIVUUS_VERIFY_CHECKSUMS=false only skips the digest step" {
    # Signature valide, archive falsifiée : l'utilisateur a explicitement
    # renoncé à l'étape d'empreinte, la signature reste exigée et valide.
    printf 'contenu different\n' > "$DL/nivuus-shell.tar.gz"
    run env ENABLE_AUTOUPDATE=false NIVUUS_VERIFY_CHECKSUMS=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=0"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_download.bats`
Expected: FAIL — `_nivuus_verify_release: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter dans `config/20-autoupdate.zsh` :

```zsh
# Base des URL d'assets. Surchargeable UNIQUEMENT pour les tests e2e,
# qui servent une fausse release via file:// (curl sait le faire, ce qui
# évite un serveur HTTP dans la suite). Jamais documentée pour les
# utilisateurs.
: ${NIVUUS_RELEASE_BASE_URL:=https://github.com/$NIVUUS_GITHUB_REPO/releases/download}

# Décide si une release téléchargée est acceptable. Fonction pure : aucun
# réseau, aucune écriture. Toute la politique de sécurité tient ici.
#
# Ordre non négociable : SIGNATURE d'abord, EMPREINTE ensuite. Vérifier
# une empreinte contre un SHA256SUMS non authentifié ne démontre rien.
#
# Retour : 0 acceptable / 1 refus / 2 aucun outil de vérification
_nivuus_verify_release() {
    local temp_dir=$1 version=$2 keys_dir=${3:-$NIVUUS_SHELL_DIR/keys}
    local archive="$temp_dir/nivuus-shell.tar.gz"
    local sums="$temp_dir/SHA256SUMS"

    _nivuus_verify_signature "$sums" "$temp_dir" "$keys_dir"
    local rc=$?
    if (( rc != 0 )); then
        return $rc
    fi

    # NIVUUS_VERIFY_CHECKSUMS ne porte QUE sur l'étape ci-dessous. Elle ne
    # peut pas, et ne doit jamais pouvoir, désactiver la signature.
    [[ "$NIVUUS_VERIFY_CHECKSUMS" == "true" ]] || return 0

    # Le nom versionné fait partie du contenu signé : c'est ce qui bloque
    # le rejeu inter-versions. Ne JAMAIS remplacer ce grep par head -n1.
    local expected_sum
    expected_sum=$(grep "nivuus-shell-v${version}.tar.gz" "$sums" | awk '{print $1}')
    [[ -n "$expected_sum" ]] || return 1

    local actual_sum
    actual_sum=$(_nivuus_sha256_of "$archive") || return 2
    [[ "$expected_sum" == "$actual_sum" ]] || return 1
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_download.bats`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_download.bats
git commit -m "refactor(autoupdate): extract release verification from download, now testable"
```

---

### Task 7: Refus dur dans le chemin de mise à jour

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Test: `tests/unit/test_autoupdate_hard_refusal.bats`

> **Contrainte de publication** (voir « Ordre de merge imposé ») : cette tâche peut être mergée quand elle est prête, mais **aucune release ne doit être publiée avec ce code tant que la Task 12 n'a pas produit une release signée et que le canari de la Task 13 n'est pas vert.**

**Interfaces:**
- Consumes: `_nivuus_verify_release`
- Produces:
  - `_nivuus_download_release <version> [interactive]` — télécharge archive + `SHA256SUMS` + `SHA256SUMS.sig` + `SHA256SUMS.sshsig`, appelle `_nivuus_verify_release`, et **retourne 1 avant toute écriture dans `$NIVUUS_SHELL_DIR`** en cas d'échec.
  - `_nivuus_perform_update <version> [interactive]` — propage le drapeau.
  - `NIVUUS_ALLOW_UNVERIFIED_UPDATE=1` — n'a d'effet que si `interactive` est passé **et** que stdin est un terminal, et exige alors une confirmation explicite. Sans aucun effet sur `_nivuus_check_update_async`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_hard_refusal.bats
#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

@test "download_release accepts an optional interactive flag" {
    run zsh_autoupdate "typeset -f _nivuus_download_release | grep -c 'interactive'"
    [ "$status" -eq 0 ]
    [ "$output" != "0" ]
}

@test "the async path never consults NIVUUS_ALLOW_UNVERIFIED_UPDATE" {
    # L'échappatoire ne doit exister que sur le chemin manuel confirmé.
    # On lit le corps de la fonction : un processus d'arrière-plan ne
    # peut pas prendre de décision consciente à la place de l'utilisateur.
    run zsh_autoupdate "typeset -f _nivuus_check_update_async"
    [[ "$output" != *"NIVUUS_ALLOW_UNVERIFIED_UPDATE"* ]]
    run zsh_autoupdate "typeset -f _nivuus_check_update_async"
    [[ "$output" != *"interactive"* ]]
}

@test "the escape hatch requires BOTH the flag and an interactive invocation" {
    run zsh_autoupdate "typeset -f _nivuus_download_release"
    # La condition doit conjuguer les trois gardes.
    [[ "$output" == *"NIVUUS_ALLOW_UNVERIFIED_UPDATE"* ]]
    [[ "$output" == *"interactive"* ]]
    [[ "$output" == *"-t 0"* ]]
}

@test "a refusal message names the situation and forbids bypassing" {
    # Le message d'échec doit exister et ne PAS suggérer
    # NIVUUS_VERIFY_CHECKSUMS=false comme contournement, ce que faisait
    # l'ancien code.
    run zsh_autoupdate "typeset -f _nivuus_download_release"
    [[ "$output" != *"NIVUUS_VERIFY_CHECKSUMS=false to bypass"* ]]
}

@test "verification failure returns 1 and prints no temp dir on stdout" {
    # _nivuus_perform_update lit le chemin du répertoire temporaire sur la
    # sortie standard de _nivuus_download_release : en cas de refus, cette
    # sortie doit être vide, sinon l'installation se poursuivrait.
    run zsh_autoupdate "
        _nivuus_verify_release() { return 1 }
        curl() { : > \"\${@[-1]}\"; return 0 }
        out=\$(_nivuus_download_release 9.9.9 2>/dev/null)
        rc=\$?
        echo \"rc=\$rc out=[\$out]\"
    "
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"out=[]"* ]]
}
```

> Note : le stub `curl` du dernier test s'appuie sur la forme `curl -fsSL -o <fichier> <url>` — si l'implémentation change l'ordre des arguments, adapter le stub, pas le test.

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_hard_refusal.bats`
Expected: FAIL — la fonction actuelle ne connaît ni `interactive`, ni la signature.

- [ ] **Step 3: Write minimal implementation**

Remplacer entièrement `_nivuus_download_release` dans `config/20-autoupdate.zsh` :

```zsh
# Télécharge une release et décide si elle est installable.
#
#   $1  version cible
#   $2  « interactive » si l'appel vient de nivuus-update tapé par un
#       humain. Vide sur le chemin automatique — et c'est structurel :
#       l'échappatoire NIVUUS_ALLOW_UNVERIFIED_UPDATE ne peut pas exister
#       pour un processus d'arrière-plan.
#
# Imprime le chemin du répertoire temporaire sur stdout en cas de succès,
# et RIEN en cas de refus (l'appelant teste ce chemin).
_nivuus_download_release() {
    local version=$1 interactive=${2:-}
    local temp_dir=$(mktemp -d)
    local base="$NIVUUS_RELEASE_BASE_URL/v${version}"

    echo "📥 Downloading release v${version}..." >&2
    if ! curl -fsSL -o "$temp_dir/nivuus-shell.tar.gz" \
            "$base/nivuus-shell-v${version}.tar.gz"; then
        echo "❌ Failed to download release archive" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    if ! curl -fsSL -o "$temp_dir/SHA256SUMS" "$base/SHA256SUMS"; then
        echo "❌ Could not download SHA256SUMS (verification required, aborting)" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    # Les deux formats de signature sont téléchargés sans condition :
    # on ne sait pas encore lequel cette machine peut vérifier. Un 404
    # sur l'un des deux n'est pas fatal ; l'absence des DEUX le sera au
    # moment de la vérification.
    curl -fsSL -o "$temp_dir/SHA256SUMS.sig"    "$base/SHA256SUMS.sig"    2>/dev/null
    curl -fsSL -o "$temp_dir/SHA256SUMS.sshsig" "$base/SHA256SUMS.sshsig" 2>/dev/null

    echo "🔐 Verifying release signature..." >&2
    _nivuus_verify_release "$temp_dir" "$version"
    local rc=$?

    if (( rc == 2 )); then
        echo "❌ Aucun outil de vérification disponible sur cette machine." >&2
        echo "   Nivuus a besoin de « openssl » ou de « ssh-keygen » pour" >&2
        echo "   authentifier une mise à jour. Sans l'un des deux, la mise à" >&2
        echo "   jour automatique reste inactive." >&2
        echo "   Diagnostic : nivuus doctor" >&2
    elif (( rc != 0 )); then
        echo "❌ Signature ou empreinte invalide pour la release v${version}." >&2
        echo "   L'archive est potentiellement altérée. NE PAS contourner." >&2
        echo "   Vérifie la page de release :" >&2
        echo "   https://github.com/$NIVUUS_GITHUB_REPO/releases/tag/v${version}" >&2
    fi

    if (( rc != 0 )); then
        # Unique échappatoire (§ 4 du spec) : une décision consciente
        # d'un humain devant son terminal. Trois gardes conjointes, et
        # une confirmation explicite. Le chemin automatique ne passe
        # jamais ici, faute du drapeau « interactive ».
        if [[ "$interactive" == "interactive" ]] \
            && [[ "$NIVUUS_ALLOW_UNVERIFIED_UPDATE" == "1" ]] && [[ -t 0 ]]; then
            echo "" >&2
            echo "⚠️  NIVUUS_ALLOW_UNVERIFIED_UPDATE=1 est défini." >&2
            echo "   Installer une release non vérifiée exécute du code" >&2
            echo "   arbitraire à chaque ouverture de shell." >&2
            local reply
            read -r "reply?Installer quand même cette release NON VÉRIFIÉE ? (tape OUI) "
            if [[ "$reply" == "OUI" ]]; then
                echo "$temp_dir"
                return 0
            fi
        fi
        rm -rf "$temp_dir"
        return 1
    fi

    echo "✅ Signature verified" >&2
    echo "$temp_dir"
}
```

Adapter `_nivuus_perform_update` pour propager le drapeau :

```zsh
_nivuus_perform_update() {
    local target_version=${1:-$(_nivuus_latest_version)}
    local interactive=${2:-}
    ...
    local temp_dir=$(_nivuus_download_release "$target_version" "$interactive")
    ...
}
```

Et, dans `nivuus-update`, l'appel devient :

```zsh
        _nivuus_perform_update "$latest" interactive
```

`_nivuus_check_update_async` reste **inchangé** : il appelle `_nivuus_perform_update` sans second argument. C'est cette absence d'argument qui rend l'échappatoire inatteignable en arrière-plan.

> Attention : les messages d'information de `_nivuus_download_release` partent désormais sur **stderr**, parce que sa sortie standard porte le chemin du répertoire temporaire. L'ancien code mélangeait les deux et ne fonctionnait que par chance (le `$(...)` capturait tout, et `[[ -d "$temp_dir" ]]` échouait alors). Le corriger fait partie de cette tâche.

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_hard_refusal.bats tests/unit/test_autoupdate_download.bats tests/unit/test_release_signature.bats`
Expected: PASS, toutes les suites de signature.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_hard_refusal.bats
git commit -m "feat(autoupdate): refuse unsigned releases, no silent SHA256 downgrade"
```

---

### Task 8: `keys/` copié à l'installation — le point de rupture

**Files:**
- Modify: `lib/steps.sh`
- Test: `tests/unit/test_lib_steps_keys.bats`
- Test: `tests/e2e/test_install_keys.bats`

**Interfaces:**
- Consumes: `nivuus_install_file` (`lib/manifest.sh`)
- Produces: `nivuus_step_copy_tree` copie aussi `keys/`.

**Le spec l'identifie comme « le point de rupture le plus probable de tout ce chantier », et il a raison.** `nivuus_step_copy_tree` itère sur `config themes bin plugins lib`. Sans `keys` dans cette liste, l'installeur ne pose aucune clé publique, `$NIVUUS_SHELL_DIR/keys` n'existe pas, et **toute installation neuve refuse toutes les mises à jour** — un échec total, silencieux, et qui ne se manifeste qu'une semaine plus tard en arrière-plan.

> **Rebaser avant cette tâche** : la phase 3 multi-plateforme touche `lib/steps.sh`. N'ajouter que `keys` à la liste ; ne pas réécrire la fonction.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_steps_keys.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/detect.sh"
    source "$LIB/manifest.sh"; source "$LIB/zshrc.sh"; source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"

    SRC="$TMP/src"
    mkdir -p "$SRC/config" "$SRC/keys"
    printf 'core\n'          > "$SRC/config/00-core.zsh"
    printf 'FAKE PEM\n'      > "$SRC/keys/nivuus-release-2026.pem"
    printf 'nivuus-release ssh-ed25519 AAAA fake\n' > "$SRC/keys/allowed_signers"
    : > "$SRC/keys/revoked"
    printf 'main\n'          > "$SRC/.zshrc"
}

teardown() { rm -rf "$TMP"; }

@test "copy_tree installs the public key store" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/nivuus-release-2026.pem" ]
}

@test "copy_tree installs allowed_signers" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/allowed_signers" ]
}

@test "copy_tree installs the (possibly empty) revoked list" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/revoked" ]
}

@test "the key store is recorded in the manifest, so uninstall removes it" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    run grep -c "keys/nivuus-release-2026.pem" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}
```

> `revoked` est vide : vérifier que `find -type f` de `nivuus_step_copy_tree` le prend bien — un fichier vide est un fichier. Si l'implémentation de la phase 3 a ajouté un filtre par taille ou par extension, c'est ce test qui l'attrapera.

```bash
# tests/e2e/test_install_keys.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "a fresh install owns a usable trust store" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -d "$TMP/target/keys" ]
    # Au moins une clé publique, sinon l'auto-update est mort-né.
    run bash -c "ls '$TMP/target/keys'/*.pem 2>/dev/null | wc -l"
    [ "$output" -ge 1 ]
}

@test "the installed trust store contains no private key" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run grep -rlE 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' "$TMP/target/keys"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_steps_keys.bats`
Expected: FAIL — `keys/` n'est pas copié.
(`tests/e2e/test_install_keys.bats` échouera aussi tant que la Task 11 n'a pas committé de vraie clé ; c'est attendu et documenté à la Task 11.)

- [ ] **Step 3: Write minimal implementation**

Dans `lib/steps.sh`, une seule ligne change :

```sh
    for d in config themes bin plugins lib keys; do
```

Ajouter juste au-dessus le commentaire qui explique pourquoi cette liste n'est pas anodine :

```sh
    # « keys » n'est pas optionnel : sans le trousseau, l'installation
    # neuve n'a aucune clé de confiance et REFUSE toutes les mises à jour
    # (refus dur, cf. config/20-autoupdate.zsh). L'échec serait total,
    # silencieux, et différé d'une semaine.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_steps_keys.bats`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/unit/test_lib_steps_keys.bats tests/e2e/test_install_keys.bats
git commit -m "fix(install): copy the public key store, without it no update ever verifies"
```

---

### Task 9: Avertissement à l'installation si aucun outil de vérification

**Files:**
- Modify: `lib/deps.sh` (implémentation), `lib/steps.sh` (façade)
- Modify: `bin/nivuus`
- Test: `tests/unit/test_lib_steps_verify_tools.bats`

**Interfaces:**
- Consumes: `log_warn`, `log_info`
- Produces: `nivuus_deps_check_verify_tools` (dans `lib/deps.sh`) et sa façade `nivuus_step_check_verify_tools` (dans `lib/steps.sh`, sur le modèle exact de `nivuus_step_check_required_deps`) — **consultative** : imprime un avertissement sur stderr si ni `openssl` ni `ssh-keygen` n'est présent, et **retourne toujours 0**. Elle ne bloque jamais l'installation.

Le principe : annoncer le problème **au moment où l'utilisateur peut agir**, pas six mois plus tard dans un processus d'arrière-plan dont la sortie part dans un `mktemp` que personne ne lit.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_steps_verify_tools.bats
#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/deps.sh"; source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "the step is a thin facade over the deps policy" {
    # Même structure que nivuus_step_check_required_deps : la politique
    # de dépendances vit dans lib/deps.sh, steps.sh n'expose qu'un nom.
    run type nivuus_deps_check_verify_tools
    [ "$status" -eq 0 ]
    run type nivuus_step_check_verify_tools
    [ "$status" -eq 0 ]
}

@test "check_verify_tools succeeds silently when openssl is present" {
    command -v openssl >/dev/null || skip "openssl absent de cet environnement"
    run nivuus_step_check_verify_tools
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_verify_tools warns but NEVER fails when both tools are missing" {
    fake="$(mkfakepath "$TMP/bin" bash sh grep awk cat)"
    run env PATH="$fake" bash -c \
        "source '$LIB/log.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'; nivuus_step_check_verify_tools; echo rc=\$?"
    # Consultative : une machine sans openssl doit pouvoir installer Nivuus.
    [[ "$output" == *"rc=0"* ]]
}

@test "the warning names the consequence and the remedy" {
    fake="$(mkfakepath "$TMP/bin" bash sh grep awk cat)"
    run env PATH="$fake" bash -c \
        "source '$LIB/log.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'; nivuus_step_check_verify_tools 2>&1"
    [[ "$output" == *"openssl"* ]]
    [[ "$output" == *"ssh-keygen"* ]]
    [[ "$output" == *"jour"* ]]     # « mise à jour automatique … inactive »
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_steps_verify_tools.bats`
Expected: FAIL — `nivuus_step_check_verify_tools: command not found`.

- [ ] **Step 3: Write minimal implementation**

Ajouter à `lib/deps.sh` (POSIX strict : pas de `[[ ]]`, pas de tableau, pas de substitution de processus — `bats tests/unit/test_lib_posix.bats` doit rester vert) :

```sh
# Consultative, jamais bloquante : openssl et ssh-keygen ne sont pas des
# dépendances d'INSTALLATION, ce sont des dépendances de MISE À JOUR.
# Refuser d'installer parce que la machine ne pourra pas se mettre à jour
# toute seule serait disproportionné. Mais le dire au moment de
# l'installation, où l'utilisateur peut encore agir, est le minimum :
# l'échec réel surviendrait sinon en arrière-plan, une semaine plus tard,
# dans un fichier temporaire que personne ne lit.
nivuus_deps_check_verify_tools() {
    if command -v openssl >/dev/null 2>&1; then return 0; fi
    if command -v ssh-keygen >/dev/null 2>&1; then return 0; fi

    log_warn "Ni « openssl » ni « ssh-keygen » n'est disponible sur cette machine."
    log_warn "Nivuus ne pourra pas authentifier ses mises à jour : la mise à"
    log_warn "jour automatique restera inactive (elle n'installera jamais une"
    log_warn "release non vérifiée)."
    log_warn "Pour l'activer, installe l'un des deux :"
    if command -v apt-get >/dev/null 2>&1; then
        log_warn "  sudo apt-get install openssl"
    elif command -v apk >/dev/null 2>&1; then
        log_warn "  sudo apk add openssl"
    elif command -v dnf >/dev/null 2>&1; then
        log_warn "  sudo dnf install openssl"
    elif command -v pacman >/dev/null 2>&1; then
        log_warn "  sudo pacman -S openssl"
    else
        log_warn "  installe « openssl » avec ton gestionnaire de paquets"
    fi
    return 0
}
```

Et la façade dans `lib/steps.sh`, juste sous celle qui existe déjà :

```sh
# Conservé comme façade : lib/deps.sh porte désormais la politique.
nivuus_step_check_verify_tools() { nivuus_deps_check_verify_tools "$@"; }
```

Dans `bin/nivuus`, `cmd_install`, juste après `nivuus_step_check_required_deps` :

```sh
    nivuus_step_check_required_deps || return 1
    nivuus_step_check_verify_tools
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_steps_verify_tools.bats tests/unit/test_lib_posix.bats tests/e2e/test_nivuus_cli.bats`
Expected: PASS. L'ajout ne doit casser aucun test CLI existant (l'avertissement va sur stderr et le code de retour reste 0), ni la suite POSIX.

- [ ] **Step 5: Commit**

```bash
git add lib/deps.sh lib/steps.sh bin/nivuus tests/unit/test_lib_steps_verify_tools.bats
git commit -m "feat(install): warn at install time when no verification tool is available"
```

---

### Task 10: `lib/keys.sh` et `install.sh --verify-key <empreinte>`

**Files:**
- Create: `lib/keys.sh`
- Modify: `bin/nivuus`, `install.sh`
- Test: `tests/unit/test_lib_keys.bats`
- Test: `tests/e2e/test_verify_key.bats`

**Interfaces:**
- Consumes: `nivuus_hash_file` (`lib/manifest.sh`)
- Produces (POSIX, bash 3.2 / ash) :
  - `nivuus_keyset_list <keys_dir>` — imprime une ligne `<nom-de-fichier> <sha256>` par clé publique, triée. Lisible par un humain.
  - `nivuus_keyset_fingerprint <keys_dir>` — imprime **une** empreinte hexadécimale du jeu complet : le sha256 de la sortie de `nivuus_keyset_list`. C'est ce que l'utilisateur compare.
  - `nivuus_keyset_verify <keys_dir> <empreinte>` — 0 si l'empreinte correspond, 1 sinon.
  - `install.sh --verify-key <empreinte>` / `nivuus install --verify-key <empreinte>` — refuse d'installer si le jeu de clés embarqué ne correspond pas.

C'est la seule réponse honnête possible à « et si GitHub est compromis pendant mon installation ? » : l'utilisateur obtient l'empreinte par un canal de son choix et la colle. Le spec chiffre ça à une quinzaine de lignes ; c'est le bon ordre de grandeur.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_keys.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"; source "$LIB/keys.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/keys"
    printf 'KEY A\n' > "$TMP/keys/a.pem"
    printf 'KEY B\n' > "$TMP/keys/b.pem"
    printf 'nivuus-release ssh-ed25519 AAAA x\n' > "$TMP/keys/allowed_signers"
    : > "$TMP/keys/revoked"
}

teardown() { rm -rf "$TMP"; }

@test "keyset_list prints one sorted line per key" {
    run nivuus_keyset_list "$TMP/keys"
    [ "$status" -eq 0 ]
    [ "${lines[0]%% *}" = "a.pem" ]
    [ "${lines[1]%% *}" = "b.pem" ]
    [ "${lines[2]%% *}" = "allowed_signers" ]
}

@test "keyset_fingerprint is stable across calls" {
    a="$(nivuus_keyset_fingerprint "$TMP/keys")"
    b="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$a" = "$b" ]
    [ -n "$a" ]
}

@test "keyset_fingerprint changes when a key is added" {
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'KEY C\n' > "$TMP/keys/c.pem"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" != "$after" ]
}

@test "keyset_fingerprint changes when a key is altered" {
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'KEY A TAMPERED\n' > "$TMP/keys/a.pem"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" != "$after" ]
}

@test "keyset_fingerprint ignores the revoked list ordering artefacts" {
    # revoked fait partie de la politique, pas de l'identité du jeu :
    # une révocation ne doit pas invalider l'empreinte que l'utilisateur
    # a notée. (Décision : l'empreinte couvre les clés, pas la dénylist.)
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'sha256:deadbeef\n' > "$TMP/keys/revoked"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" = "$after" ]
}

@test "keyset_verify accepts the right fingerprint and rejects a wrong one" {
    fp="$(nivuus_keyset_fingerprint "$TMP/keys")"
    run nivuus_keyset_verify "$TMP/keys" "$fp"
    [ "$status" -eq 0 ]
    run nivuus_keyset_verify "$TMP/keys" "0000000000000000"
    [ "$status" -eq 1 ]
}

@test "keyset_verify rejects an empty or missing key store" {
    mkdir -p "$TMP/empty"
    run nivuus_keyset_verify "$TMP/empty" "whatever"
    [ "$status" -eq 1 ]
    run nivuus_keyset_verify "$TMP/nope" "whatever"
    [ "$status" -eq 1 ]
}
```

```bash
# tests/e2e/test_verify_key.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    source "$ROOT/lib/log.sh"; source "$ROOT/lib/manifest.sh"; source "$ROOT/lib/keys.sh"
}

teardown() { rm -rf "$TMP"; }

@test "install --verify-key with the right fingerprint proceeds" {
    fp="$(nivuus_keyset_fingerprint "$ROOT/keys")"
    run "$NIVUUS" install --yes --verify-key "$fp" --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -d "$TMP/target/keys" ]
}

@test "install --verify-key with a wrong fingerprint refuses and writes NOTHING" {
    run "$NIVUUS" install --yes --verify-key "cafecafecafecafe" --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "install.sh forwards --verify-key" {
    run "$ROOT/install.sh" --non-interactive --verify-key "cafecafecafecafe" --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_keys.bats`
Expected: FAIL — `lib/keys.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/keys.sh
# Identité du trousseau de confiance : lister et résumer les clés
# publiques installées. POSIX / bash 3.2 : sourcé par bin/nivuus et par
# bin/healthcheck.
#
# Aucune vérification de signature ici — c'est le rôle du client zsh
# (config/20-autoupdate.zsh). Ce module ne répond qu'à une question :
# « quelles clés cette installation considère-t-elle comme de
# confiance ? »

# Une ligne « <fichier> <sha256> » par artefact public, triée.
nivuus_keyset_list() {
    local keys_dir f
    keys_dir="$1"
    [ -d "$keys_dir" ] || return 1
    for f in "$keys_dir"/*.pem; do
        [ -f "$f" ] || continue
        printf '%s %s\n' "$(basename "$f")" "$(nivuus_hash_file "$f")"
    done | LC_ALL=C sort
    if [ -f "$keys_dir/allowed_signers" ]; then
        printf '%s %s\n' allowed_signers "$(nivuus_hash_file "$keys_dir/allowed_signers")"
    fi
}

# Empreinte unique du jeu : c'est CE que l'utilisateur compare quand il
# utilise --verify-key. Volontairement calculée sur les clés seules :
# « revoked » relève de la politique et peut changer sans que l'identité
# du jeu change — sinon la moindre révocation invaliderait l'empreinte
# que les utilisateurs ont notée.
nivuus_keyset_fingerprint() {
    local keys_dir tmp digest
    keys_dir="$1"
    [ -d "$keys_dir" ] || return 1
    tmp="$(mktemp)"
    nivuus_keyset_list "$keys_dir" > "$tmp"
    if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
    digest="$(nivuus_hash_file "$tmp")"
    rm -f "$tmp"
    printf '%s\n' "$digest"
}

nivuus_keyset_verify() {
    local keys_dir expected actual
    keys_dir="$1"; expected="$2"
    actual="$(nivuus_keyset_fingerprint "$keys_dir")" || return 1
    [ "$actual" = "$expected" ]
}
```

Dans `bin/nivuus` : sourcer `lib/keys.sh` avec les autres, ajouter l'option, et vérifier **avant** `nivuus_manifest_begin` — le refus doit intervenir avant la moindre écriture.

```sh
. "$NIVUUS_SRC_ROOT/lib/keys.sh"
```

```sh
            --verify-key)
                shift
                [ $# -gt 0 ] || { log_error "L'option --verify-key attend une empreinte."; return 2; }
                verify_key="$1"
                ;;
```

```sh
    # AVANT toute écriture : si l'utilisateur a une empreinte obtenue par
    # un autre canal et qu'elle ne correspond pas, on ne touche à rien.
    if [ -n "${verify_key:-}" ]; then
        if ! nivuus_keyset_verify "$NIVUUS_SRC_ROOT/keys" "$verify_key"; then
            log_error "L'empreinte du jeu de clés ne correspond pas à celle fournie."
            log_error "  attendue (fournie) : $verify_key"
            log_error "  trouvée            : $(nivuus_keyset_fingerprint "$NIVUUS_SRC_ROOT/keys" 2>/dev/null || printf 'aucune')"
            log_error "Installation refusée. Rien n'a été écrit."
            return 1
        fi
        log_ok "Jeu de clés vérifié : $verify_key"
    fi
```

Dans `install.sh`, ajouter la traduction de l'option :

```sh
        --verify-key)
            shift
            [ $# -gt 0 ] || { printf "L'option --verify-key attend une empreinte.\n" >&2; exit 2; }
            ARGS+=(--verify-key "$1") ;;
```

Et ajouter la ligne correspondante dans `usage()` de `bin/nivuus`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_keys.bats tests/unit/test_lib_posix.bats tests/e2e/test_verify_key.bats`
Expected: PASS. (`test_verify_key.bats` exige au moins une clé dans `keys/` : il ne passera qu'après la Task 11. Si cette tâche est faite avant, marquer ses trois tests `skip` avec le motif « nécessite le trousseau réel — Task 11 » et retirer les `skip` en Task 11.)

- [ ] **Step 5: Commit**

```bash
git add lib/keys.sh bin/nivuus install.sh tests/unit/test_lib_keys.bats tests/e2e/test_verify_key.bats
git commit -m "feat(install): add --verify-key to pin the trust store out of band"
```

---

### Task 11: Générer, sauvegarder et committer le vrai trousseau

**Files:**
- Create: `keys/nivuus-release-2026.pem`, `keys/nivuus-release-2027.pem`
- Create: `keys/allowed_signers`
- Modify: `doc/SIGNING.md`
- Modify: `tests/e2e/test_verify_key.bats` (retirer les `skip` de la Task 10)

**Interfaces:**
- Consumes: `nivuus_keyset_fingerprint` (Task 10)
- Produces: le trousseau réel, et les secrets `NIVUUS_SIGNING_KEY_ECDSA` / `NIVUUS_SIGNING_KEY_SSH` posés dans le GitHub Environment `release`.

**Tâche opérationnelle, exécutée par le mainteneur, pas par un agent.** Un agent qui exécuterait ces commandes créerait une clé privée dans un environnement qui n'est pas celui du mainteneur. Si tu es un agent : **arrête-toi ici et signale que cette tâche demande une action humaine.**

Deux règles non négociables, contrepartie du modèle à clé épinglée (§ 2.4 du spec) :
- Le jeu de succession **2027** est généré **en même temps** que le jeu 2026 et embarqué dès la première release signée. Sans successeur pré-distribué, une perte de clé est un événement d'extinction pour le canal de mise à jour.
- La sauvegarde hors ligne est **testée** avant la première release signée : restaurer, signer un fichier témoin, vérifier. Une sauvegarde jamais testée n'est pas une sauvegarde.

- [ ] **Step 1: Générer les deux jeux, hors CI**

```bash
# Sur la machine du mainteneur, JAMAIS dans un runner : une clé générée
# en CI est une clé qui a existé dans un journal.
umask 077
mkdir -p ~/nivuus-signing && cd ~/nivuus-signing

for year in 2026 2027; do
    openssl ecparam -name prime256v1 -genkey -noout -out "priv-$year.pem"
    openssl pkcs8 -topk8 -nocrypt -in "priv-$year.pem" -out "priv-$year.pk8.pem"
    openssl ec -in "priv-$year.pem" -pubout -out "nivuus-release-$year.pem"
    ssh-keygen -q -t ed25519 -N '' -f "id-$year" -C "nivuus-release-$year"
done
```

Pas de passphrase : un runner ne peut pas en saisir une. **La protection n'est pas la passphrase, c'est le périmètre de lecture de l'environnement `release`.**

- [ ] **Step 2: Sauvegarder hors ligne, puis VÉRIFIER la sauvegarde**

```bash
# 1. Déposer priv-2026.pk8.pem, priv-2027.pk8.pem, id-2026, id-2027 dans
#    le gestionnaire de mots de passe ET sur un support froid.
# 2. Restaurer depuis la sauvegarde dans un répertoire neuf.
# 3. Signer un fichier témoin avec la copie RESTAURÉE.
# 4. Vérifier avec la clé publique.
echo "témoin de sauvegarde $(date)" > /tmp/witness
openssl dgst -sha256 -sign /chemin/restauré/priv-2026.pk8.pem -out /tmp/witness.sig /tmp/witness
openssl dgst -sha256 -verify nivuus-release-2026.pem -signature /tmp/witness.sig /tmp/witness
# Doit imprimer « Verified OK ». Sinon : la sauvegarde n'existe pas.
```

- [ ] **Step 3: Poser les secrets dans l'environnement protégé**

```bash
# L'environnement, pas les secrets de dépôt : c'est TOUTE la différence.
# Un attaquant qui obtient contents: write, ou qui injecte une Action
# tierce dans un autre job, ne peut pas lire un secret d'environnement.
gh api -X PUT repos/maximeallanic/nivuus-shell/environments/release

gh secret set NIVUUS_SIGNING_KEY_ECDSA --env release < priv-2026.pk8.pem
gh secret set NIVUUS_SIGNING_KEY_SSH   --env release < id-2026
```

Ne **pas** activer de règle « réviseur requis » : décision actée n° 1, signature automatique. L'environnement est là pour le cloisonnement ; l'approbation manuelle pourra être activée plus tard dans les réglages GitHub, sans toucher au code.

- [ ] **Step 4: Committer le matériel public**

```bash
cd /chemin/du/dépôt
cp ~/nivuus-signing/nivuus-release-2026.pem keys/
cp ~/nivuus-signing/nivuus-release-2027.pem keys/
{
  printf 'nivuus-release %s\n' "$(cat ~/nivuus-signing/id-2026.pub)"
  printf 'nivuus-release %s\n' "$(cat ~/nivuus-signing/id-2027.pub)"
} > keys/allowed_signers

# Le garde-fou de la Task 1 doit rester vert.
bats tests/unit/test_keys_repo.bats

# Noter l'empreinte du jeu : c'est elle qui sera publiée (Task 16).
source lib/log.sh; source lib/manifest.sh; source lib/keys.sh
nivuus_keyset_fingerprint keys
```

Retirer les `skip` de `tests/e2e/test_verify_key.bats` et de `tests/e2e/test_install_keys.bats`.

- [ ] **Step 5: Run the suites**

Run: `bats tests/unit/test_keys_repo.bats tests/unit/test_lib_keys.bats tests/e2e/test_verify_key.bats tests/e2e/test_install_keys.bats`
Expected: PASS. Le test « every .pem is a parseable EC public key » de la Task 1 devient contraignant à ce moment précis.

- [ ] **Step 6: Commit**

```bash
git add keys tests/e2e/test_verify_key.bats tests/e2e/test_install_keys.bats
git commit -m "feat(keys): add the 2026 release keyset and its pre-distributed 2027 successor"
```

---

### Task 12: Job de signature en CI, avec vérification avant publication

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: les secrets de l'environnement `release` (Task 11), `keys/*.pem` committées
- Produces: `SHA256SUMS.sig` et `SHA256SUMS.sshsig` publiés avec chaque release, plus une attestation de provenance.

**L'étape la plus importante de ce job n'est pas la signature, c'est la vérification avant publication.** Elle utilise la **clé publique committée dans le dépôt**, pas celle dérivée du secret, et attrape le scénario opérationnel le plus probable de tout le chantier : rotation du secret sans commit de la clé publique correspondante — c'est-à-dire une release que plus aucun client n'accepte, sans aucun signal.

- [ ] **Step 1: Verify the gap**

Run: `grep -c "SHA256SUMS.sig" .github/workflows/release.yml || true`
Expected: `0` — rien n'est signé aujourd'hui.

- [ ] **Step 2: Add the signing step**

Dans `.github/workflows/release.yml`, job `release`, **entre** « Generate checksums » et « Create GitHub Release ».

Déclarer d'abord l'environnement et les permissions sur le job :

```yaml
  release:
    name: Create Release
    runs-on: ubuntu-latest
    needs: test
    environment: release        # secrets cloisonnés ; règle de protection
                                # activable plus tard sans changer le code
    permissions:
      contents: write
      id-token: write           # attestation de provenance
      attestations: write
```

> Le spec proposait de scinder `release` en `build` + `sign`. On garde **un seul job** : le scinder exigerait de faire transiter `release-assets/` par un artefact entre deux jobs, ce qui ajoute une surface (un job tiers peut télécharger un artefact) sans rien apporter — le secret est déjà cloisonné par `environment:`, qui s'applique au job entier. À reconsidérer seulement si d'autres étapes viennent s'ajouter à ce job.

```yaml
      - name: Sign SHA256SUMS
        env:
          KEY_ECDSA: ${{ secrets.NIVUUS_SIGNING_KEY_ECDSA }}
          KEY_SSH:   ${{ secrets.NIVUUS_SIGNING_KEY_SSH }}
        run: |
          set -euo pipefail
          umask 077

          keyfile="$(mktemp)"; sshkey="$(mktemp)"
          cleanup() {
            shred -u "$keyfile" "$sshkey" 2>/dev/null || rm -f "$keyfile" "$sshkey"
          }
          trap cleanup EXIT

          printf '%s' "$KEY_ECDSA" > "$keyfile"
          printf '%s\n' "$KEY_SSH" > "$sshkey"
          chmod 600 "$keyfile" "$sshkey"

          # Chemin primaire : ECDSA P-256 / SHA-256, DER.
          openssl dgst -sha256 -sign "$keyfile" \
              -out release-assets/SHA256SUMS.sig release-assets/SHA256SUMS

          # Chemin de repli : Ed25519 SSHSIG. ssh-keygen écrit
          # <fichier>.sig à côté du fichier signé ; on le renomme.
          ssh-keygen -Y sign -f "$sshkey" -n nivuus-release release-assets/SHA256SUMS
          mv release-assets/SHA256SUMS.sig.tmp 2>/dev/null || true
          # (ssh-keygen produit release-assets/SHA256SUMS.sig — qui
          #  entrerait en collision avec la signature openssl. On signe
          #  donc via une copie pour éviter toute ambiguïté.)

          echo "✅ Signed SHA256SUMS (ECDSA + SSHSIG)"
```

> **Piège de collision à traiter à l'écriture de cette étape :** `openssl dgst -out` et `ssh-keygen -Y sign` visent tous deux `SHA256SUMS.sig`. La forme correcte est de signer le SSHSIG depuis une copie et de renommer :
> ```bash
> cp release-assets/SHA256SUMS "$TMPDIR/sums"
> ssh-keygen -Y sign -f "$sshkey" -n nivuus-release "$TMPDIR/sums"
> mv "$TMPDIR/sums.sig" release-assets/SHA256SUMS.sshsig
> ```
> Écrire l'étape sous cette forme ; la Step 3 la vérifie.

```yaml
      - name: Verify before publishing
        run: |
          set -euo pipefail
          # Vérification avec la clé publique COMMITÉE, jamais avec celle
          # dérivée du secret. C'est ce qui rend structurellement
          # impossible de publier une release que les clients
          # refuseraient — la panne la plus probable de ce chantier :
          # rotation du secret sans commit de la clé publique.
          ok=0
          for pem in keys/*.pem; do
            if openssl dgst -sha256 -verify "$pem" \
                 -signature release-assets/SHA256SUMS.sig \
                 release-assets/SHA256SUMS >/dev/null 2>&1; then
              echo "✅ ECDSA verified against $pem"; ok=1; break
            fi
          done
          [ "$ok" = 1 ] || { echo "❌ Aucune clé publique committée ne valide SHA256SUMS.sig"; exit 1; }

          ssh-keygen -Y verify -f keys/allowed_signers -I nivuus-release \
              -n nivuus-release -s release-assets/SHA256SUMS.sshsig \
              < release-assets/SHA256SUMS
          echo "✅ SSHSIG verified against keys/allowed_signers"

      - name: Verify with the real client code
        run: |
          set -euo pipefail
          # Deuxième filet, plus fort que le premier : on n'exécute pas
          # une commande openssl écrite pour l'occasion, on exécute LA
          # fonction que les utilisateurs exécuteront. Une divergence
          # entre le workflow et le client est ainsi impossible.
          sudo apt-get update && sudo apt-get install -y zsh
          rm -f config/*.zwc
          ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$PWD" zsh -c '
            source config/20-autoupdate.zsh
            _nivuus_verify_signature release-assets/SHA256SUMS release-assets keys
            rc=$?
            [[ $rc -eq 0 ]] || { echo "❌ le client refuserait cette release (rc=$rc)"; exit 1 }
            echo "✅ le client accepte cette release"
          '

      - name: Attest build provenance
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: 'release-assets/*.tar.gz'
```

`gh release create release-assets/*` n'a pas besoin d'être modifié : il ramasse les nouveaux fichiers.

- [ ] **Step 3: Test the workflow on a throwaway release**

Ne pas tester en publiant une release réelle. Exécuter la logique de signature localement avec un jeu éphémère :

```bash
tmp="$(mktemp -d)"
mkdir -p "$tmp/release-assets" "$tmp/keys"
openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/priv.pem"
openssl ec -in "$tmp/priv.pem" -pubout -out "$tmp/keys/test.pem"
ssh-keygen -q -t ed25519 -N '' -f "$tmp/id" -C test
printf 'nivuus-release %s\n' "$(cat "$tmp/id.pub")" > "$tmp/keys/allowed_signers"
: > "$tmp/keys/revoked"
printf 'deadbeef  nivuus-shell-v9.9.9.tar.gz\n' > "$tmp/release-assets/SHA256SUMS"

# Recopier ici EXACTEMENT les commandes des deux étapes ci-dessus,
# en substituant les chemins. Les deux vérifications doivent réussir,
# et les deux fichiers de signature doivent coexister sans collision.
ls "$tmp/release-assets"   # doit contenir SHA256SUMS, .sig ET .sshsig
```

Expected: `SHA256SUMS.sig` et `SHA256SUMS.sshsig` présents et distincts, les deux vérifications OK.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): sign SHA256SUMS and refuse to publish what clients would reject"
```

---

### Task 13: Canari nocturne sur la release réelle

**Files:**
- Create: `.github/workflows/verify-latest-release.yml`

**Interfaces:**
- Consumes: la dernière release publiée, `keys/` du dépôt
- Produces: une alerte sous 24 h si la release publiée n'est plus vérifiable par le code client.

**C'est ce qui rend le refus dur tenable.** L'argument adverse au refus dur — « un bug casse l'auto-update de tout le monde, qui n'a plus de canal pour recevoir le correctif » — est sérieux. On le traite par de la prévention : une dérive clé/asset est détectée côté mainteneur avant qu'un utilisateur ne la rencontre.

- [ ] **Step 1: Write the canary**

```yaml
# .github/workflows/verify-latest-release.yml
name: Verify latest release (canary)

on:
  schedule:
    - cron: '17 3 * * *'
  workflow_dispatch:

jobs:
  canary:
    name: Verify the published release with the committed keys
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v4

      - name: Install zsh
        run: |
          if [ "$RUNNER_OS" = "Linux" ]; then sudo apt-get update && sudo apt-get install -y zsh; fi
          zsh --version

      - name: Download the latest published release assets
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          tag="$(gh release view --json tagName -q .tagName)"
          echo "TAG=$tag" >> "$GITHUB_ENV"
          echo "VERSION=${tag#v}" >> "$GITHUB_ENV"
          mkdir -p dl
          gh release download "$tag" --dir dl --clobber
          mv "dl/nivuus-shell-${tag}.tar.gz" dl/nivuus-shell.tar.gz
          ls -l dl

      - name: Verify exactly as a user's shell would
        run: |
          set -euo pipefail
          rm -f config/*.zwc
          ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$PWD" zsh -c '
            source config/20-autoupdate.zsh
            _nivuus_verify_release dl "'"$VERSION"'" keys
            rc=$?
            case $rc in
              0) echo "✅ la release publiée est acceptée par le client" ;;
              1) echo "❌ SIGNATURE OU EMPREINTE INVALIDE sur la release publiée"; exit 1 ;;
              2) echo "❌ aucun outil de vérification sur ce runner"; exit 1 ;;
            esac
          '

      - name: Verify the SSHSIG path independently
        run: |
          # Le chemin de repli doit être vérifié SÉPARÉMENT : sur un
          # runner où openssl réussit, le SSHSIG pourrait être absent ou
          # cassé sans que personne ne le voie jusqu'au jour où il porte
          # le trafic réel.
          ssh-keygen -Y verify -f keys/allowed_signers -I nivuus-release \
              -n nivuus-release -s dl/SHA256SUMS.sshsig < dl/SHA256SUMS
```

- [ ] **Step 2: Run it once manually**

Run: `gh workflow run verify-latest-release.yml && gh run watch`
Expected: **échec attendu tant que la première release signée n'existe pas** (pas de `.sig` sur les releases antérieures). C'est le comportement correct : le canari doit être rouge exactement quand la dernière release n'est pas vérifiable. Il devient vert à la première release produite par la Task 12.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/verify-latest-release.yml
git commit -m "ci: add nightly canary verifying the published release with committed keys"
```

---

### Task 14: E2E — une release falsifiée ne s'installe pas et ne casse rien

**Files:**
- Create: `tests/e2e/test_update_signature.bats`

**Interfaces:**
- Consumes: `NIVUUS_RELEASE_BASE_URL` et `NIVUUS_GITHUB_API` (surchargeables), `tests/helpers/fingerprint.bash` (déjà écrit pour le test de réversibilité du chantier 1 — **on le réutilise, on n'en écrit pas un second**)
- Produces: la preuve de bout en bout que le refus est effectif **et** sans dommage collatéral.

**Complément au spec :** le spec évoque un « serveur HTTP éphémère ». On sert la fausse release par `file://`, que `curl` sait lire nativement. Aucun serveur, aucun port, aucun `python3`, aucune course de démarrage — et la surface testée (les appels `curl` du client) est exactement la même.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_update_signature.bats
#!/usr/bin/env bats

load '../helpers/signing'
load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    rm -f "$ROOT"/config/*.zwc

    # 1. Une installation existante, saine.
    "$NIVUUS" install --yes --prefix "$TMP/target" >/dev/null
    printf '3.0.0\n' > "$TMP/target/.version"

    # 2. Un trousseau éphémère, substitué à celui de l'installation :
    #    on ne signe jamais avec la vraie clé dans un test.
    gen_keyset "$TMP/legit"
    gen_keyset "$TMP/evil"
    rm -f "$TMP/target/keys"/*.pem "$TMP/target/keys/allowed_signers"
    cp "$TMP/legit/keys"/* "$TMP/target/keys/"

    # 3. Une fausse release 9.9.9 servie par file://
    REL="$TMP/releases/v9.9.9"; mkdir -p "$REL"
    mkdir -p "$TMP/payload/config"
    printf 'echo NOUVELLE_VERSION\n' > "$TMP/payload/config/00-core.zsh"
    printf '9.9.9\n' > "$TMP/payload/.version"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .
    ( cd "$REL" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )

    # 4. Une fausse API GitHub, elle aussi servie par file://
    API="$TMP/api/repos/fake/nivuus/releases"; mkdir -p "$API"
    printf '{"tag_name": "v9.9.9"}\n' > "$API/latest"

    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

update() {
    ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$TMP/target" \
    NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
    NIVUUS_GITHUB_API="$NIVUUS_GITHUB_API" NIVUUS_GITHUB_REPO="$NIVUUS_GITHUB_REPO" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; $1"
}

@test "nominal: a properly signed release installs and .version moves forward" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/target/.version")" = "9.9.9" ]
    run grep -c NOUVELLE_VERSION "$TMP/target/config/00-core.zsh"
    [ "$output" = "1" ]
}

@test "INVARIANT: a tampered archive is refused AND the install is untouched" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    # L'archive est modifiée APRÈS signature : SHA256SUMS ne la décrit
    # plus, mais la signature de SHA256SUMS reste authentique.
    printf 'charge utile malveillante\n' > "$TMP/payload/config/00-core.zsh"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .

    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/target/.version")" = "3.0.0" ]
}

@test "INVARIANT: an attacker-signed SHA256SUMS is refused AND the install is untouched" {
    printf 'charge utile malveillante\n' > "$TMP/payload/config/00-core.zsh"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .
    ( cd "$REL" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/evil" "$REL/SHA256SUMS" "$REL"

    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "INVARIANT: a client with no verification tool refuses and stays intact" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    fake="$(mkfakepath "$TMP/bin" curl tar awk grep cat mktemp rm cp find date zsh sha256sum shasum chmod)"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$TMP/target" \
        NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "INVARIANT: signatures stripped from the release are refused, no SHA256 fallback" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    rm -f "$REL/SHA256SUMS.sig" "$REL/SHA256SUMS.sshsig"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "the async path ignores NIVUUS_ALLOW_UNVERIFIED_UPDATE entirely" {
    rm -f "$REL/SHA256SUMS.sig" "$REL/SHA256SUMS.sshsig"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run env NIVUUS_ALLOW_UNVERIFIED_UPDATE=1 ENABLE_AUTOUPDATE=false \
        NIVUUS_SHELL_DIR="$TMP/target" NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_perform_update 9.9.9 < /dev/null"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/e2e/test_update_signature.bats`
Expected: FAIL, avec deux causes possibles à distinguer :
- `NIVUUS_RELEASE_BASE_URL` n'est pas honoré par `_nivuus_download_release` (l'URL est encore en dur) — corriger en Task 7 ;
- `_nivuus_perform_update` restaure une sauvegarde et laisse un répertoire de sauvegarde derrière lui, qui fait diverger l'empreinte. **Ne pas assouplir le test** : empreindre `$TMP/target` uniquement (déjà le cas ci-dessus) et vérifier que le refus intervient bien **avant** `_nivuus_create_update_backup`.

- [ ] **Step 3: Fix the client until the fingerprints match**

Correction attendue dans `_nivuus_perform_update` : **télécharger et vérifier AVANT de créer la sauvegarde.** Aujourd'hui la sauvegarde est créée d'abord, ce qui écrit ~50 Mo sur disque pour une mise à jour qui va être refusée, à chaque tentative, sur toutes les machines. L'ordre correct :

```zsh
_nivuus_perform_update() {
    local target_version=${1:-$(_nivuus_latest_version)}
    local interactive=${2:-}

    [[ -n "$target_version" ]] || { echo "❌ Could not determine target version"; return 1 }

    # Vérifier d'abord : une release refusée ne doit rien coûter et ne
    # rien laisser derrière elle. La sauvegarde ne protège que de
    # l'installation, pas du téléchargement.
    local temp_dir
    temp_dir=$(_nivuus_download_release "$target_version" "$interactive") || return 1
    [[ -n "$temp_dir" && -d "$temp_dir" ]] || { echo "❌ Download failed"; return 1 }

    local backup_dir=$(_nivuus_create_update_backup)
    echo "📦 Backup created: $backup_dir"
    ...
}
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_release_signature.bats tests/unit/test_autoupdate_*.bats tests/e2e/test_update_signature.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_update_signature.bats config/20-autoupdate.zsh
git commit -m "test(e2e): prove a forged release is refused and leaves the install intact"
```

---

### Task 15: Exécuter les nouvelles suites en CI

**Files:**
- Modify: `.github/workflows/tests.yml`

> **Rebaser avant cette tâche.** La phase 3 y ajoute une matrice multi-plateforme. Ajouter les suites de signature **à la matrice existante**, pas dans un job `ubuntu-latest` isolé : les cas « `shasum` seul » et « aucun outil » n'ont d'intérêt que s'ils tournent aussi sur macOS.

**Interfaces:**
- Consumes: toutes les suites précédentes
- Produces: une CI qui casse si un invariant de signature régresse.

- [ ] **Step 1: Verify the gap**

Run: `grep -c "test_release_signature" .github/workflows/tests.yml || true`
Expected: `0`.

- [ ] **Step 2: Add the steps**

Dans le job de test (matrice de la phase 3), après les tests unitaires existants :

```yaml
      - name: Signature verification suite
        run: |
          rm -f config/*.zwc     # un .zwc périmé masquerait le module
          bats tests/unit/test_keys_repo.bats \
               tests/unit/test_autoupdate_sha256.bats \
               tests/unit/test_release_signature.bats \
               tests/unit/test_autoupdate_download.bats \
               tests/unit/test_autoupdate_hard_refusal.bats \
               tests/unit/test_lib_keys.bats \
               tests/unit/test_lib_steps_keys.bats \
               tests/unit/test_lib_steps_verify_tools.bats

      - name: Signature E2E (forged release must be refused)
        run: |
          rm -f config/*.zwc
          bats tests/e2e/test_update_signature.bats \
               tests/e2e/test_install_keys.bats \
               tests/e2e/test_verify_key.bats

      - name: The two invariants must be present and green
        run: |
          # Garde-fou contre une suppression discrète : les tests qui
          # portent la propriété de sécurité ne doivent pas pouvoir
          # disparaître sans que la CI le dise.
          grep -q "INVARIANT: a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" \
            tests/unit/test_release_signature.bats
          grep -q "INVARIANT: no verification tool at all is REFUSED" \
            tests/unit/test_release_signature.bats
          grep -c "INVARIANT" tests/e2e/test_update_signature.bats
```

- [ ] **Step 3: Verify locally before pushing**

Run: `rm -f config/*.zwc && bats tests/unit/ tests/e2e/ && bats tests/performance/`
Expected: PASS pour les suites de ce chantier, et **le temps de démarrage doit rester sous 300 ms** — les nouvelles fonctions ne sont que des définitions, aucune ne s'exécute au chargement du module.

**Attention :** `bats tests/unit/` en entier contient un échec **préexistant et hors périmètre** — `test_ai_suggestions.bats` test 6 (`_ai_spinner_tick`). Ne pas tenter de le corriger ici, ne pas l'ajouter au job.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "ci: run the release signature suites, guard the two invariants"
```

---

### Task 16: `doctor`, `SECURITY.md` et documentation honnête

**Files:**
- Modify: `bin/healthcheck`
- Modify: `README.md`
- Create: `SECURITY.md`
- Modify: `doc/SIGNING.md`
- Test: `tests/e2e/test_doctor_signature.bats`

**Interfaces:**
- Consumes: `lib/keys.sh`, `_nivuus_verify_signature`
- Produces: un diagnostic lisible, une politique de sécurité écrite, et une documentation qui **ne survend pas**.

**La contrainte de rédaction est aussi importante que le code.** Un badge « signed & secure » laissant croire que le `curl | sh` est authentifié serait une régression de confiance, pas un progrès. La formulation du § 3 du spec est reprise telle quelle. **Pas de badge « secure » dans le README.**

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_doctor_signature.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    "$ROOT/bin/nivuus" install --yes --prefix "$TMP/target" >/dev/null
    export NIVUUS_SHELL_DIR="$TMP/target"
}

teardown() { rm -rf "$TMP"; }

@test "doctor reports the trust store fingerprint" {
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"Update signing"* ]]
    [[ "$output" == *"fingerprint"* || "$output" == *"empreinte"* ]]
}

@test "doctor names the verification tool it would use on this machine" {
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"openssl"* || "$output" == *"ssh-keygen"* ]]
}

@test "doctor flags a missing key store loudly" {
    rm -rf "$TMP/target/keys"
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"aucune clé"* || "$output" == *"no trusted key"* ]]
}

@test "the README makes no security claim about curl | sh" {
    # Garde-fou de rédaction : le problème d'amorçage doit rester nommé.
    run grep -ci "signed.*secure\|badge.*secure" "$ROOT/README.md"
    [ "$output" = "0" ]
    run grep -c "première installation\|first install" "$ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "SECURITY.md exists and publishes the keyset fingerprint" {
    [ -f "$ROOT/SECURITY.md" ]
    source "$ROOT/lib/log.sh"; source "$ROOT/lib/manifest.sh"; source "$ROOT/lib/keys.sh"
    fp="$(nivuus_keyset_fingerprint "$ROOT/keys")"
    run grep -c "$fp" "$ROOT/SECURITY.md"
    [ "$output" != "0" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_doctor_signature.bats`
Expected: FAIL — `bin/healthcheck` ne dit rien de la signature, `SECURITY.md` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Ajouter une section à `bin/healthcheck` :

```bash
# =============================================================================
# Update signing
# =============================================================================
echo ""
echo -e "${BLUE}Update signing${NC}"
echo "─────────────────────────────────────────────"

KEYS_DIR="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/keys"

# Quel outil cette machine utiliserait-elle ?
if command -v openssl >/dev/null 2>&1; then
    echo -e "$CHECK Verification tool: openssl ($(openssl version 2>/dev/null | head -1))"
elif command -v ssh-keygen >/dev/null 2>&1; then
    echo -e "$CHECK Verification tool: ssh-keygen (fallback path)"
else
    echo -e "$CROSS Aucun outil de vérification (openssl ou ssh-keygen)"
    echo -e "  ${YELLOW}La mise à jour automatique restera inactive sur cette machine.${NC}"
fi

# Le trousseau est-il là, et lequel ?
if [ -d "$KEYS_DIR" ]; then
    # shellcheck source=/dev/null
    . "${NIVUUS_SHELL_DIR}/lib/log.sh" 2>/dev/null || true
    . "${NIVUUS_SHELL_DIR}/lib/manifest.sh" 2>/dev/null || true
    . "${NIVUUS_SHELL_DIR}/lib/keys.sh" 2>/dev/null || true
    if command -v nivuus_keyset_fingerprint >/dev/null 2>&1 \
       && fp="$(nivuus_keyset_fingerprint "$KEYS_DIR" 2>/dev/null)" && [ -n "$fp" ]; then
        echo -e "$CHECK Trust store fingerprint (empreinte) : $fp"
        nivuus_keyset_list "$KEYS_DIR" | sed 's/^/    /'
        echo -e "  ${BLUE}Compare-la à celle publiée dans SECURITY.md.${NC}"
    else
        echo -e "$CROSS Trousseau illisible : aucune clé de confiance"
    fi
else
    echo -e "$CROSS Aucune clé de confiance installée ($KEYS_DIR absent)"
    echo -e "  ${YELLOW}Aucune mise à jour ne sera acceptée. Réinstalle Nivuus.${NC}"
fi
```

`SECURITY.md` — contenu obligatoire :

```markdown
# Politique de sécurité

## Ce que la signature garantit, et ce qu'elle ne garantit pas

Depuis la version X.Y.Z, le fichier `SHA256SUMS` de chaque release est signé.
Le client refuse d'installer une mise à jour dont la signature n'est pas valide
contre une clé publique livrée avec l'installation. Il n'existe **aucune**
dégradation vers la simple empreinte SHA256.

| Scénario | Avant | Après |
|---|---|---|
| Compromission des assets de release seuls (jeton fuité, Action tierce, job voisin) | exécution de code chez tous les utilisateurs | **bloquée** |
| MITM avec une CA de confiance sur le chemin de mise à jour | réussit | **bloquée** |
| Miroir ou re-hébergement tiers | invérifiable | **vérifiable** |
| Corruption en transit | couverte | couverte |
| Première installation via `curl \| sh` | vulnérable | **toujours vulnérable** |
| Compromission de la clé de signature | — | non couverte |
| Mainteneur malveillant | — | non couverte, par construction |

**La signature ne résout pas la première installation.** Le one-liner
`curl … | sh` télécharge l'installeur et la clé publique depuis la même
origine : qui contrôle cette origine à cet instant sert son installeur et sa
clé. Aucune signature ne peut résoudre ça — c'est le problème de la racine de
confiance, et il se termine toujours par « quelque chose doit être connu à
l'avance ».

Ce que la signature déplace est ailleurs, et c'est l'essentiel : la première
installation est **un instant, sous les yeux de l'utilisateur, une fois**. La
mise à jour est **récurrente, automatique, invisible, sur toutes les machines,
pour toujours**. Signer fait passer la fenêtre d'attaque de « permanente et
silencieuse » à « ponctuelle et observable ».

## Empreinte du jeu de clés

    <coller ici la sortie de : nivuus_keyset_fingerprint keys>

Vérifie-la avant d'installer :

```bash
./install.sh --verify-key <empreinte>
```

L'installeur refuse de continuer si le jeu de clés embarqué ne correspond pas.

**Limite honnête de l'ancrage :** cette empreinte est publiée sur GitHub
(ce fichier, le README, le profil du mainteneur). Le projet ne dispose
aujourd'hui d'aucun domaine hors GitHub pour la publier ailleurs. L'ancrage
hors bande est donc **intra-GitHub**, et un attaquant qui contrôlerait
l'ensemble du compte GitHub pourrait modifier simultanément l'empreinte et les
clés. Cette limite est réelle et assumée ; elle sera levée le jour où un
domaine indépendant existera.

## Anti-rétrogradation

Une mise à jour n'est déclenchée que vers une version **supérieure**. Un
attaquant ne peut donc pas rejouer une release antérieure signée par une clé
depuis révoquée. C'est une propriété de sécurité, pas seulement du confort.

## Rotation et révocation

Voir `doc/SIGNING.md`. En résumé : le trousseau installé contient toujours le
jeu courant **et** son successeur, pré-distribué au moins une release avant son
premier usage — la rotation est invisible et ne demande aucune action.

Une clé compromise ayant déjà signé une release malveillante ne peut pas être
« dé-signée » chez les utilisateurs déjà mis à jour : **le code malveillant
contrôle la mise à jour**. La procédure de récupération d'une machine
compromise est une réinstallation, pas une mise à jour.

## Signaler une vulnérabilité

<adresse ou canal privé — à renseigner par le mainteneur>
Ne pas ouvrir d'issue publique pour une vulnérabilité de la chaîne de
distribution.
```

`README.md` — trois modifications précises :

1. Dans la section « Updating », remplacer « **Checksum verification** - SHA256 verification for security » par une formulation exacte :
   ```markdown
   - **Signature verification** — chaque release est signée ; une mise à jour
     dont la signature n'est pas valide est refusée, sans repli sur la simple
     empreinte. Voir [SECURITY.md](SECURITY.md) pour ce que cela garantit —
     et ce que cela ne garantit pas, notamment pour la première installation.
   ```
2. Corriger la description de `NIVUUS_VERIFY_CHECKSUMS`, qui ne fait plus ce que le README dit :
   ```markdown
   # Désactive UNIQUEMENT la comparaison d'empreinte SHA256 (déconseillé).
   # Sans effet sur la vérification de signature, qui n'est jamais
   # désactivable sur le chemin automatique.
   export NIVUUS_VERIFY_CHECKSUMS=false
   ```
3. Ajouter la mention de `--verify-key` dans la section d'installation, avec la phrase sur l'amorçage. **Aucun badge « secure ».**

`doc/SIGNING.md` — compléter (le fichier existe depuis la Task 2) avec : la procédure de rotation annuelle, la procédure de révocation, la liste des secrets et de l'environnement, et l'emplacement des sauvegardes hors ligne (sans les sauvegardes elles-mêmes).

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_doctor_signature.bats`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add bin/healthcheck README.md SECURITY.md doc/SIGNING.md tests/e2e/test_doctor_signature.bats
git commit -m "docs(security): publish the trust model, keyset fingerprint and doctor diagnostics"
```

---

### Task 17: Répétition en blanc de la rotation

**Files:**
- Modify: `doc/SIGNING.md`

**Interfaces:**
- Consumes: tout ce qui précède
- Produces: la preuve qu'une rotation complète fonctionne — **avant** d'en avoir besoin.

Une procédure de rotation jamais exécutée est une hypothèse. Celle-ci se répète en blanc, sur un dépôt jetable, pour que le jour où elle sera nécessaire ne soit pas le jour où on la découvre.

- [ ] **Step 1: Exécuter la rotation en blanc**

```bash
# Sur un fork privé jetable, ou en local avec le workflow simulé.
# Scénario complet, dans l'ordre :
#
# 1. État initial : keys/ contient {2026, 2027}, les secrets portent 2026.
#    Publier une release → signée par 2026, acceptée.
#
# 2. Rotation : générer le jeu 2028, l'ajouter à keys/, RETIRER 2026,
#    remplacer les secrets par le jeu 2027.
#    keys/ contient alors {2027, 2028}. Publier une release → signée par
#    2027, acceptée par un client qui n'avait encore que {2026, 2027}.
#    ⇒ C'est LE point que la répétition doit prouver : un client installé
#      avant la rotation accepte la release d'après la rotation.
#
# 3. Vérifier avec un client figé à l'étape 1 :
rm -f config/*.zwc
ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR=/chemin/client-figé zsh -c '
  source config/20-autoupdate.zsh
  _nivuus_verify_release /chemin/release-étape-2 <version> /chemin/client-figé/keys
  echo "rc=$?"   # DOIT être 0
'
#
# 4. Révocation : ajouter l'empreinte de 2026 à keys/revoked, publier,
#    vérifier qu'une signature de 2026 est désormais refusée.
```

- [ ] **Step 2: Vérifier le point de rupture le plus probable**

Simuler explicitement la panne annoncée par le spec : **rotation du secret sans commit de la clé publique**.

```bash
# Remplacer le secret par le jeu 2028 SANS ajouter keys/nivuus-release-2028.pem,
# puis lancer le workflow de release.
# ATTENDU : l'étape « Verify before publishing » ÉCHOUE et rien n'est publié.
# Si la release passe, la Task 12 est incorrecte — c'est exactement ce que
# cette étape doit détecter.
```

- [ ] **Step 3: Écrire la procédure telle qu'elle a été exécutée**

Consigner dans `doc/SIGNING.md`, sous « Rotation annuelle », la procédure **réellement suivie**, avec les commandes exactes, la date de la répétition, et tout écart constaté entre la procédure imaginée et la procédure qui a marché. Un écart non consigné est un piège pour le futur.

- [ ] **Step 4: Commit**

```bash
git add doc/SIGNING.md
git commit -m "docs(signing): record the rehearsed key rotation and revocation procedure"
```

---

## Vérification finale du chantier

Une fois les 17 tâches terminées, ces commandes doivent toutes réussir :

```bash
rm -f config/*.zwc
bats tests/unit/test_release_signature.bats      # les 2 invariants verts
bats tests/unit/test_autoupdate_*.bats
bats tests/unit/test_keys_repo.bats tests/unit/test_lib_keys.bats
bats tests/e2e/test_update_signature.bats        # release falsifiée refusée
bats tests/e2e/test_install_keys.bats            # install neuve = clé présente
bats tests/unit/test_lib_posix.bats              # lib/ reste POSIX/ash
bats tests/e2e/test_reversibility.bats           # chantier 1 toujours vert
bats tests/performance/                          # <300 ms préservé

# Aucune clé privée nulle part :
! grep -rlE 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' --exclude-dir=.git .

# Le canari est vert sur la dernière release publiée :
gh workflow run verify-latest-release.yml && gh run watch
```

## Ce que ce plan ne livre pas

Conformément au § 7 du spec et aux décisions actées :

- **Le `.asc` GPG pour les packagers** — hors périmètre. L'architecture ne l'empêche pas : ajouter une signature GPG demande une étape dans le job `release` et un troisième secret dans l'environnement, sans toucher au client (le chemin GPG n'est **jamais** sur le chemin de vérification client, § 1 du spec).
- **cosign en vérification client** — l'attestation de provenance est publiée (Task 12), sa vérification reste l'affaire des auditeurs avec `gh attestation verify`.
- **TUF / journal de transparence côté client** — disproportionné pour un updater de framework zsh.
- **Builds reproductibles** — propriété voisine et souhaitable, spec distincte.
- **Signature du tag git** (`git tag -s` avec `gpg.format=ssh`) — second ancrage pour les auditeurs, à ajouter quand le mainteneur aura une clé de signature git configurée. Ne bloque rien.
- **Vérification du bootstrap piped** (phase 5 du chantier 1) — le `curl | sh` télécharge aujourd'hui le dépôt, pas le tarball de release. Quand la phase 5 arrivera, elle vérifiera la signature avec la clé téléchargée en même temps : c'est un contrôle de **cohérence**, pas d'origine (même origine), qui couvre le cas réaliste « assets compromis mais dépôt intact ». À documenter comme tel, sans survendre.
- **Récupération d'une machine déjà compromise** — impossible par mise à jour, la réponse est la réinstallation.
