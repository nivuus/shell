# Porte d'entrée — vrai `curl | sh`, migration du dépôt git parasite, documentation d'installation — Plan d'implémentation (phase 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Qu'une personne qui n'a jamais entendu parler de Nivuus puisse coller **une** ligne dans son terminal, obtenir une installation vérifiée, et la retirer entièrement avec une ligne aussi visible que la première — sur Ubuntu, Debian, Arch, Fedora, Alpine, macOS et WSL, **sans `git`**, et sans qu'un dépôt git parasite ne vienne désactiver silencieusement ses mises à jour.

**Architecture :** `install.sh` devient un fichier **POSIX sh unique et bimodal**, servi à une URL stable :

| Mode | Déclencheur | Ce qu'il fait |
|---|---|---|
| **local** | un noyau (`bin/nivuus` + `lib/manifest.sh`) existe à côté du script | traduit les anciens flags et délègue à `bin/nivuus install` — comportement actuel, inchangé |
| **amorçage** | pas de noyau à côté (`curl … \| sh`) | résout la version, télécharge l'archive de release, **vérifie son empreinte (fail-closed)**, l'extrait dans un temporaire, délègue au noyau extrait, et nettoie |

Aucun `git clone`, aucun dépôt laissé derrière, aucune dépendance à `git`. À côté, deux corrections
qui ne concernent que les installations **déjà en place** : la migration du `.git` créé par
l'ancien `init_git_repo()` (qui bloque l'auto-update de tous les utilisateurs du one-liner
historique), et la reconnaissance de la strophe `.zshrc` que v3.0.0 écrivait, pour qu'une
installation de HEAD par-dessus ne source pas Nivuus deux fois.

**Tech Stack :** POSIX sh strict (`install.sh` — doit tourner sous `dash`, BusyBox `ash` et bash 3.2),
bash 3.2 (`bin/nivuus`, `lib/*.sh`), zsh (`config/20-autoupdate.zsh`), bats, `tar`/`sha256sum`/`shasum`,
`curl` ou `wget`, GitHub Releases, `file://` pour les tests hors réseau.

**Spec :** `docs/superpowers/specs/2026-08-20-installation-friction-zero-design.md` — section 1
« Architecture et surface CLI » et sa sous-section « One-liner » ; problème n° 7 (le one-liner est un
`git clone /tmp`) et n° 8 (`init_git_repo()` désactive l'auto-update) ; section 5 « Périmètre »
(suppression de `init_git_repo()` **avec migration**) ; section 6, phase 5 « Porte d'entrée » ;
section 7 « Risques » (test explicite « v3.0.0 en place → installation par-dessus → tout fonctionne »).

**Plans précédents (mergés ou en cours) :**
- `docs/superpowers/plans/2026-08-20-installation-friction-zero.md` — phases 1 et 2 : `lib/`, manifeste, `--dry-run`, `nivuus uninstall`, empreinte `$HOME`. **Mergé.**
- `docs/superpowers/plans/2026-08-21-installation-multiplateforme.md` — phase 3 : `lib/detect.sh`, `lib/deps.sh`, `--minimal`, `chsh` sûr, `lib/` sous BusyBox ash. **Mergé.**
- `docs/superpowers/plans/2026-08-21-installation-preuve-ci.md` — phase 4 : matrice CI, `tests/ci/*.sh`, `.github/matrix.json`, action composite `setup-tests`, badges. **En parallèle.**
- `docs/superpowers/plans/2026-08-21-release-signing.md` — chantier 2 : `keys/`, `lib/keys.sh`, `install.sh --verify-key`, vérification de signature dans l'auto-update. **En parallèle.**

Ce plan est écrit pour s'appliquer sur un `master` où les deux chantiers parallèles sont **déjà
mergés**. Les fichiers qu'ils possèdent ne sont pas replanifiés ici : voir « Points de contact ».

**Sortie de phase :** le one-liner installe et désinstalle proprement depuis zéro sur chaque cible.

---

## État des lieux constaté (2026-08-21)

Vérifié dans le dépôt, pas supposé depuis le spec :

1. **`init_git_repo()` n'existe plus dans le code.** `grep -rn init_git_repo` ne renvoie que des
   occurrences dans `docs/`. La fonction a disparu avec `8261f77 refactor(install): turn install.sh
   into a thin nivuus wrapper` (phase 1), et `tests/e2e/test_install_sh_compat.bats` porte déjà la
   non-régression : « install.sh no longer creates a git repo ». **Il n'y a donc rien à supprimer.**
   Tout ce qui reste de l'item « suppression de `init_git_repo` » du spec est la **migration** des
   installations existantes — c'est-à-dire l'essentiel du travail réel, puisqu'elle concerne des
   machines dont l'auto-update est cassé aujourd'hui.

2. **La signature exacte du dépôt parasite est connue** (`git show v3.0.0:install.sh`, lignes 334-346) :

   ```sh
   git init                     # dans $HOME/.nivuus-shell
   git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
   git add . ; git commit -m "Initial Nivuus Shell installation"
   git branch -M master
   git fetch origin master      # en SSH : échoue silencieusement chez la quasi-totalité des gens
   ```

   Le spec dit « `.git` sans remote de travail » : le remote existe, mais il pointe sur l'amont en
   **SSH**, jamais sur un dépôt sur lequel l'utilisateur travaille. Le critère de détection ne peut
   donc **pas** être « aucun remote » — il doit être l'empreinte complète ci-dessus (Task 6).

3. **Le `.zshrc` que v3.0.0 écrivait est connu à l'octet près** (`git show v3.0.0:install.sh`,
   lignes 257-261) et ne contient **aucun marqueur** :

   ```
   # Nivuus Shell Configuration
   export NIVUUS_SHELL_DIR="$HOME/.nivuus-shell"
   source "$NIVUUS_SHELL_DIR/.zshrc"
   ```

   `nivuus_zshrc_state` classe ce fichier `absent`, donc `nivuus_zshrc_merge` **ajoute** le bloc
   délimité sans retirer la strophe. Conséquence mesurable et non hypothétique : après une
   installation de HEAD par-dessus v3.0.0, `~/.zshrc` source Nivuus **deux fois**. C'est exactement
   le risque que la section 7 du spec demande de couvrir (Task 9).

4. **`git` est aujourd'hui une dépendance *requise*** : `NIVUUS_DEPS_REQUIRED='zsh git curl'`
   (`lib/deps.sh:6`). Un `curl | sh` qui n'a plus besoin de git mais refuse de démarrer sans lui
   serait une incohérence visible dès la première ligne de sortie (Task 5).

5. **`install.sh` est en bash** et utilise `${BASH_SOURCE[0]}` et un tableau `ARGS`. Sous
   `curl … | sh`, `BASH_SOURCE` n'existe pas et les tableaux non plus : le fichier tel quel ne
   peut pas être le script d'amorçage (Task 2).

6. **`.github/workflows/release.yml` contient déjà une étape cassée** :
   `sed -i 's/^VERSION=.*/VERSION="…"/' install.sh` suivi de `grep '^VERSION=' install.sh`. La
   variable `VERSION=` n'existe plus dans `install.sh` depuis la phase 1 : le `grep` sort en 1 et
   fait échouer l'étape (le shell par défaut d'un `run:` est `bash -e`). Aucune release n'a été
   produite depuis. Task 12 la répare en la branchant sur la vraie variable.

7. **`tar` de release** : `release.yml` produit `tar -czf … .`, donc une archive **sans répertoire
   racine**. L'archive « Source code » que GitHub génère automatiquement, elle, en a un. L'amorçage
   accepte les deux formes sans deviner (Task 4).

8. **Un seul tag existe : `v3.0.0`.** L'état « ancienne installation » est donc reproductible depuis
   le dépôt lui-même (`git archive v3.0.0`), sans binaire vendu dans les tests (Task 9).

---

## Décisions actées (ne pas rouvrir)

**URL d'amorçage.** `https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh`,
telle que le spec la fixe. Aucun domaine dédié, aucun raccourcisseur, aucun hébergement tiers :
une URL de plus, c'est une origine de plus à sécuriser et un service de plus à maintenir. La forme
épinglée `…/v<version>/install.sh` reste valide et documentée pour qui veut figer.

**Résolution de version : « latest » d'abord, plancher épinglé ensuite.** L'amorçage interroge
`$NIVUUS_GITHUB_API/repos/<repo>/releases/latest` ; en cas d'échec (réseau, quota de 60 requêtes/h
par IP — réel derrière un NAT d'entreprise ou un runner partagé) il retombe sur
`NIVUUS_PINNED_VERSION`, écrite dans `install.sh` et resynchronisée par `release.yml`. Les deux
mécanismes gagnent leur place : le premier rend `master/install.sh` toujours juste sans
resynchronisation, le second le rend utilisable sans API. `NIVUUS_VERSION=x.y.z` force.

**Format d'archive : `nivuus-shell-v<version>.tar.gz` + `SHA256SUMS`,** les artefacts que
`release.yml` produit **déjà** et que `config/20-autoupdate.zsh` consomme **déjà**. Aucun nouvel
artefact, aucun nouveau format : le chemin d'installation et le chemin de mise à jour mangent la
même chose, donc un artefact cassé casse les deux tests au lieu d'un seul.

**Vérification d'empreinte obligatoire, sans échappatoire.** Pas de `NIVUUS_VERIFY_CHECKSUMS=false`
dans l'amorçage : ce qui n'est pas vérifiable n'est pas installé. Absence de `sha256sum` **et** de
`shasum` ⇒ refus, pas contournement.

**Ce que le one-liner ne garantit pas, et qu'on écrit noir sur blanc.** Le script, l'archive, les
sommes **et** le trousseau `keys/` du chantier « signature » viennent tous de la même origine
(GitHub). Un attaquant qui contrôle cette origine les remplace tous les quatre de façon cohérente :
le one-liner protège d'un transfert corrompu ou d'un cache CDN empoisonné, **pas** d'une origine
compromise. La seule réponse honnête est un canal secondaire : `--verify-key <empreinte>`
(chantier signature, Task 10 de son plan), dont l'empreinte se publie ailleurs que sur GitHub.
Task 11 le documente en ces termes, sans euphémisme. C'est un problème d'amorçage, pas un défaut
d'implémentation ; on ne le maquille pas.

**Test hors réseau : `file://`, pas de serveur HTTP.** `NIVUUS_RELEASE_BASE_URL` et
`NIVUUS_GITHUB_API` sont surchargeables — mécanisme déjà introduit par le plan de signature, on le
réutilise tel quel. Un `file://` est servi par une copie de fichier explicite dans `nivuus_fetch`
(voir Task 3) : `curl` sait lire `file://`, `wget` ne le sait pas de façon fiable, et faire dépendre
la couverture du test du client HTTP installé sur le runner serait une couverture illusoire. La
sélection curl/wget est prouvée séparément, par de faux binaires qui journalisent leur invocation.

**Le nettoyage du dépôt parasite déplace, ne supprime pas.** `.git` part dans
`$NIVUUS_STATE_DIR/migration/<horodatage>/git/`, avec le chemin affiché. Une opération destructive
sur un répertoire qui pourrait, malgré tous les garde-fous, contenir du travail, n'a pas sa place
dans un outil dont la promesse est la réversibilité.

**`bash` reste requis pour `bin/nivuus`** (décision du spec, section 1). L'amorçage est POSIX, mais
il constate l'absence de `bash` **après extraction** et affiche la commande d'installation exacte
via `lib/deps.sh` — qui est, lui, exécutable sous ash depuis la phase 3. Zéro duplication, zéro
`sudo` implicite.

---

## Global Constraints

- **`install.sh` est POSIX sh strict.** Interdits : tableaux, `${BASH_SOURCE}`, `local`, `[[ ]]`,
  `+=`, `<<<`, substitution de processus, `echo -e`, `set -o pipefail`. Un test le vérifie
  mécaniquement (Task 2) en plus de l'exécution réelle sous `dash` et BusyBox `ash`.
- **Aucune mutation hors `lib/manifest.sh`.** La migration ne fait pas exception : le déplacement
  du `.git` passe par une primitive ajoutée à `lib/manifest.sh` (`nivuus_move_aside`), pas par un
  `mv` dans `lib/migrate.sh`. `lib/migrate.sh` ne fait que **constater**.
- **`--dry-run` reste fiable par construction**, y compris pour `nivuus migrate` et pour l'amorçage
  (qui, en dry-run, télécharge et vérifie mais ne délègue qu'un `bin/nivuus install --dry-run`).
- **Aucun `sudo` implicite**, nulle part, y compris dans les messages d'aide de l'amorçage.
- **`tests/e2e/test_reversibility.bats` doit rester vert à chaque tâche.** Aucune entrée ajoutée à
  l'allowlist d'exceptions de `tests/helpers/fingerprint.bash` sans commentaire justificatif — et
  ce plan n'en ajoute aucune.
- **TDD strict** : chaque tâche écrit le test, le voit rouge, écrit le minimum, le voit vert,
  committe. Un test qui passe du premier coup est un test qui ne teste rien : le rendre rouge
  d'abord, quitte à casser volontairement l'implémentation pour le vérifier.
- **Tâches indépendantes et mergeables.** L'ordre donné est celui des dépendances de code
  (2 → 3 → 4, 6 → 7 → 8) ; les groupes {2,3,4}, {5}, {6,7,8}, {9}, {11} sont mergeables séparément.
  Task 10 dépend de {1,4}. Task 12 se fait **en dernier**, après rebase.
- **Rien de neuf dans `keys/`, `.github/workflows/tests.yml`, `.github/matrix.json`,
  `tests/ci/`** — ces fichiers appartiennent aux chantiers parallèles.

---

### Task 1: `tests/helpers/release.bash` — fabriquer une release servie par `file://`

**Files:**
- Create: `tests/helpers/release.bash`
- Create: `tests/unit/test_helper_release.bats`

**Interfaces:**
- Produces :
  - `make_release <src_tree> <releases_dir> <version>` — écrit `<releases_dir>/v<version>/nivuus-shell-v<version>.tar.gz` et `SHA256SUMS`, dans **exactement** le format de `.github/workflows/release.yml` (archive sans répertoire racine, sommes sans préfixe `./`).
  - `make_release_api <api_dir> <repo> <version>` — écrit `<api_dir>/repos/<repo>/releases/latest`, une réponse JSON minimale `{"tag_name": "v<version>"}`.
  - `tamper_release <releases_dir> <version>` — modifie l'archive **après** génération des sommes.
- Consumers : Task 4 (unitaires d'amorçage), Task 10 (e2e `curl | sh`).

**Pourquoi un helper et pas du copier-coller.** Trois suites vont fabriquer la même fausse release.
Si chacune la fabrique à sa façon, une divergence de format entre le test et `release.yml` ne se
verra jamais — et c'est précisément la divergence qui casse le one-liner en production. Le format
est donc décrit **une fois**, ici, avec un test qui compare sa sortie à ce que `release.yml` produit.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_helper_release.bats
#!/usr/bin/env bats

load '../helpers/release'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/src/bin" "$TMP/src/config"
    printf '#!/bin/sh\necho noyau\n' > "$TMP/src/bin/nivuus"
    printf 'echo core\n' > "$TMP/src/config/00-core.zsh"
    printf 'bytecode\n' > "$TMP/src/config/00-core.zsh.zwc"
    mkdir -p "$TMP/src/.git"; printf 'ref\n' > "$TMP/src/.git/HEAD"
}

teardown() { rm -rf "$TMP"; }

@test "make_release produit l'archive et les sommes aux noms attendus" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    [ -f "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" ]
    [ -f "$TMP/rel/v9.9.9/SHA256SUMS" ]
}

@test "SHA256SUMS nomme l'archive SANS préfixe ./ (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run cat "$TMP/rel/v9.9.9/SHA256SUMS"
    [[ "$output" == *"  nivuus-shell-v9.9.9.tar.gz"* ]]
    [[ "$output" != *"./nivuus-shell"* ]]
}

@test "l'archive n'a PAS de répertoire racine (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run tar -tzf "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"
    [[ "$output" == *"./bin/nivuus"* || "$output" == *"bin/nivuus"* ]]
    # Aucune entrée du type « nivuus-shell-9.9.9/bin/nivuus »
    [[ "$output" != *"nivuus-shell-9.9.9/"* ]]
}

@test "l'archive exclut .git et les .zwc (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run tar -tzf "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"
    [[ "$output" != *".git/"* ]]
    [[ "$output" != *".zwc"* ]]
}

@test "la somme annoncée est celle de l'archive" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    expected="$(awk '{print $1}' "$TMP/rel/v9.9.9/SHA256SUMS")"
    actual="$( { sha256sum "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" 2>/dev/null \
                 || shasum -a 256 "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"; } | awk '{print $1}')"
    [ "$expected" = "$actual" ]
}

@test "tamper_release casse la correspondance sans toucher aux sommes" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    before="$(cat "$TMP/rel/v9.9.9/SHA256SUMS")"
    tamper_release "$TMP/rel" 9.9.9
    [ "$(cat "$TMP/rel/v9.9.9/SHA256SUMS")" = "$before" ]
    expected="$(awk '{print $1}' "$TMP/rel/v9.9.9/SHA256SUMS")"
    actual="$( { sha256sum "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" 2>/dev/null \
                 || shasum -a 256 "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"; } | awk '{print $1}')"
    [ "$expected" != "$actual" ]
}

@test "make_release_api écrit une réponse latest exploitable" {
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    [ -f "$TMP/api/repos/fake/nivuus/releases/latest" ]
    run cat "$TMP/api/repos/fake/nivuus/releases/latest"
    [[ "$output" == *'"tag_name"'* ]]
    [[ "$output" == *'v9.9.9'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_helper_release.bats`
Expected: FAIL — `tests/helpers/release.bash` n'existe pas (`load` échoue).

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/helpers/release.bash
# Fabrique une release Nivuus locale, servie par file://, dans EXACTEMENT le
# format que .github/workflows/release.yml publie :
#   - nivuus-shell-v<version>.tar.gz : tar -czf … . , donc pas de répertoire
#     racine, .git et *.zwc exclus ;
#   - SHA256SUMS : « <somme>  nivuus-shell-v<version>.tar.gz », sans « ./ ».
# Toute divergence avec release.yml se verrait ici et nulle part ailleurs :
# c'est la raison d'être de tests/unit/test_helper_release.bats.

_release_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

make_release() {
    local src="$1" outdir="$2" version="$3" dir archive
    dir="$outdir/v$version"
    archive="nivuus-shell-v${version}.tar.gz"
    mkdir -p "$dir"
    # --exclude AVANT la liste de fichiers : exigé par bsdtar (macOS) autant
    # que par GNU tar.
    tar --exclude='./.git' --exclude='*.zwc' -czf "$dir/$archive" -C "$src" .
    # On écrit la ligne à la main plutôt que « sha256sum *.tar.gz » : le glob
    # produit « ./nom » ou « nom » selon le shell et la version, et le client
    # d'amorçage cherche une correspondance exacte sur le nom.
    printf '%s  %s\n' "$(_release_sha256 "$dir/$archive")" "$archive" > "$dir/SHA256SUMS"
}

# Réponse minimale de l'API GitHub, servie elle aussi par file://.
# Le client (install.sh comme config/20-autoupdate.zsh) n'en lit qu'un champ.
make_release_api() {
    local api="$1" repo="$2" version="$3" dir
    dir="$api/repos/$repo/releases"
    mkdir -p "$dir"
    printf '{"tag_name": "v%s"}\n' "$version" > "$dir/latest"
}

# Modifie l'archive APRÈS coup : SHA256SUMS reste authentique et cohérent
# avec lui-même, mais ne décrit plus le contenu livré. C'est le scénario
# « CDN empoisonné » et c'est le seul que l'empreinte seule peut attraper.
tamper_release() {
    local outdir="$1" version="$2" archive
    archive="$outdir/v$version/nivuus-shell-v${version}.tar.gz"
    printf 'charge utile malveillante\n' >> "$archive"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_helper_release.bats`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add tests/helpers/release.bash tests/unit/test_helper_release.bats
git commit -m "test(helpers): build a local release in the exact release.yml format"
```

---

### Task 2: `install.sh` en POSIX sh pur — mode local inchangé

**Files:**
- Modify: `install.sh`
- Create: `tests/unit/test_install_sh_posix.bats`
- Test: `tests/e2e/test_install_sh_compat.bats` (existant — doit rester vert **sans modification**)

**Interfaces:**
- Produces : `install.sh` exécutable par `sh`, `dash`, BusyBox `ash` et `bash`, exposant :
  - `nivuus_local_root` — imprime la racine du noyau voisin, ou sort en 1 s'il n'y en a pas.
  - la traduction des anciens flags, à l'identique du wrapper bash actuel.
- Consumes : `bin/nivuus install`, `bin/nivuus doctor`.

**Pourquoi cette tâche existe.** Le wrapper actuel utilise `${BASH_SOURCE[0]}`, un tableau `ARGS` et
`set -euo pipefail` : trois constructions qui n'existent pas sous `sh`. Sous `curl … | sh`,
il ne démarre même pas. On le rend POSIX **d'abord, à comportement strictement constant**, pour que
l'ajout du mode d'amorçage (Tasks 3 et 4) se fasse sur un fichier déjà portable — et pour que la
suite de compatibilité existante serve de filet à cette réécriture, sans qu'on ait le droit d'y
toucher.

**Détection du mode : le noyau, jamais le pipe.** On ne teste pas « est-ce que stdin est un pipe » :
`sh install.sh` sur un fichier téléchargé seul n'est pas un pipe et n'a pourtant pas de noyau, et
`curl … | sh` lancé depuis un checkout en a un dans le répertoire courant. Le seul critère honnête
est **la présence effective du noyau à côté du fichier de script**, ce qui exige que `$0` soit
lui-même un fichier lisible — ce qu'il n'est pas quand `sh` lit son entrée standard.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_install_sh_posix.bats
#!/usr/bin/env bats
#
# install.sh est le SEUL fichier du dépôt qui doit tourner sous le shell que
# l'utilisateur a, pas sous celui qu'on aimerait qu'il ait : « curl | sh »
# ne choisit pas. Ce test interdit mécaniquement les bashismes et exécute
# réellement le fichier sous les shells POSIX disponibles.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "le shebang est /bin/sh" {
    run head -n1 "$SH"
    [ "$output" = "#!/bin/sh" ]
}

@test "aucun bashisme dans install.sh" {
    # Motifs choisis pour ne produire aucun faux positif sur ce fichier :
    # chacun est soit inexistant en POSIX, soit un piège avéré sous dash/ash.
    run grep -nE 'BASH_SOURCE|\blocal\b|\[\[|\]\]|\+=|<<<|\bfunction\b|pipefail|echo -e|\$\{[A-Za-z_]+\[' "$SH"
    [ "$status" -ne 0 ]
}

@test "install.sh passe le contrôle syntaxique de dash" {
    command -v dash >/dev/null 2>&1 || skip "dash indisponible"
    run dash -n "$SH"
    [ "$status" -eq 0 ]
}

@test "install.sh passe le contrôle syntaxique de busybox ash" {
    command -v busybox >/dev/null 2>&1 || skip "busybox indisponible"
    run busybox ash -n "$SH"
    [ "$status" -eq 0 ]
}

@test "install.sh --help fonctionne sous sh, dash et bash" {
    for shell in sh dash bash; do
        command -v "$shell" >/dev/null 2>&1 || continue
        run "$shell" "$SH" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"sage"* ]]
    done
}

@test "install.sh --dry-run n'écrit rien, lancé par dash" {
    command -v dash >/dev/null 2>&1 || skip "dash indisponible"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    run dash "$SH" --non-interactive --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
}

@test "nivuus_local_root trouve le noyau voisin quand il existe" {
    run sh -c ". '$SH' --source-only 2>/dev/null; nivuus_local_root"
    skip "sourcé indirectement : couvert par les tests d'exécution ci-dessus"
}

@test "une copie isolée d'install.sh ne se croit PAS en mode local" {
    # Le fichier seul, sans bin/nivuus à côté : il doit basculer en amorçage
    # (qui, sans release atteignable, échoue avec un message explicite) et
    # surtout PAS installer quoi que ce soit depuis le répertoire courant.
    cp "$SH" "$TMP/install.sh"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    run env NIVUUS_RELEASE_BASE_URL="file://$TMP/vide" NIVUUS_GITHUB_API="file://$TMP/vide" \
        sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}
```

> Le test `nivuus_local_root` marqué `skip` ci-dessus est là comme trace de l'intention : la
> fonction n'est pas testable par sourçage (le fichier s'exécute au chargement). Le comportement
> qu'elle porte est couvert par les deux tests d'exécution qui l'encadrent — c'est la bonne
> couverture, pas une couverture par introspection. Le supprimer si le `skip` gêne le comptage.

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_install_sh_posix.bats`
Expected: FAIL — shebang `#!/usr/bin/env bash`, présence de `BASH_SOURCE`, de `ARGS+=(…)`, de
`pipefail`, et `dash install.sh` refuse le fichier. Le dernier test échoue aussi : la copie isolée
utilise aujourd'hui `$ROOT` = son propre répertoire et part en erreur « bin/nivuus introuvable »
d'une façon non maîtrisée.

- [ ] **Step 3: Write minimal implementation**

```sh
#!/bin/sh
# install.sh — porte d'entrée unique de Nivuus Shell.
#
# Deux modes, un seul fichier, une seule URL :
#   local     : un noyau (bin/nivuus + lib/) est présent à côté de ce script,
#               on lui délègue -- c'est le cas du checkout et de l'archive
#               de release déjà extraite.
#   amorçage  : ce script est seul (« curl … | sh »), on résout la version,
#               on télécharge l'archive de release, on la VÉRIFIE, on
#               l'extrait dans un temporaire et on délègue au noyau extrait.
#
# POSIX sh strict : ce fichier doit tourner sous dash, BusyBox ash et
# bash 3.2. « curl | sh » ne choisit pas le shell de l'utilisateur.
# Pas de tableaux, pas de local, pas de [[ ]], pas de BASH_SOURCE.
set -eu

# Plancher de version, resynchronisé par .github/workflows/release.yml.
# Sert uniquement quand l'API GitHub est injoignable ou a rendu son quota.
NIVUUS_PINNED_VERSION="3.0.0"

usage() {
    cat <<'EOF'
install.sh — installe Nivuus Shell

Usage :
  curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
  ./install.sh [options]                      (depuis une archive extraite ou un checkout)

Options :
  --non-interactive   N'attend aucune réponse.
  --dry-run           N'écrit rien ; affiche ce qui serait fait.
  --prefix DIR        Répertoire d'installation (défaut : ~/.nivuus-shell).
  --minimal           Mode serveur / container : pas de chsh, pas d'extras.
  --no-minimal        Force le mode complet.
  --with-deps         Propose UNE commande groupée pour les dépendances.
  --health-check      Lance « nivuus doctor » après l'installation.
  --help              Affiche ceci.

Désinstallation :
  nivuus uninstall            (retire tout ce que Nivuus a écrit)
  nivuus uninstall --purge    (retire aussi l'état interne de Nivuus)

Variables d'environnement :
  NIVUUS_VERSION            Version à installer (défaut : dernière release).
  NIVUUS_RELEASE_BASE_URL   Base des artefacts de release (tests, miroirs).
  NIVUUS_GITHUB_API         Base de l'API GitHub.
EOF
}

# Racine du noyau voisin, ou échec s'il n'y en a pas.
#
# Exige que $0 soit lui-même un fichier lisible : sous « curl … | sh », $0
# vaut « sh » et n'est pas un fichier, donc on ne prendra jamais par erreur
# le répertoire courant pour une installation source -- y compris quand le
# one-liner est lancé depuis un checkout de Nivuus.
nivuus_local_root() {
    [ -f "$0" ] || return 1
    case "$0" in
        */*) _d="${0%/*}" ;;
        *)   _d="." ;;
    esac
    [ -f "$_d/bin/nivuus" ] || return 1
    [ -f "$_d/lib/manifest.sh" ] || return 1
    ( cd "$_d" && pwd )
}

# --- Traduction des anciens flags --------------------------------------
#
# Pas de tableau en POSIX sh : on fait tourner les paramètres positionnels
# autour d'une sentinelle. Tout ce qui est avant « -- » est d'origine, tout
# ce qui est après est traduit ; à la sortie de la boucle il ne reste que
# le traduit.
RUN_DOCTOR=''
set -- "$@" --
while [ "$1" != "--" ]; do
    arg="$1"; shift
    case "$arg" in
        --system)
            printf '%s\n' "L'installation système (--system) n'est pas encore disponible dans cette version." >&2
            printf '%s\n' "Utilise l'installation utilisateur (sans --system) en attendant." >&2
            exit 1
            ;;
        --non-interactive) set -- "$@" --yes ;;
        --health-check)    RUN_DOCTOR=1 ;;
        --no-backup)       : ;;   # accepté, sans effet : le manifeste sauvegarde toujours
        --dry-run|--minimal|--no-minimal|--with-deps|--yes|-y)
            set -- "$@" "$arg" ;;
        --prefix)
            [ "$1" != "--" ] || { printf "L'option --prefix attend un chemin.\n" >&2; exit 2; }
            val="$1"; shift
            set -- "$@" --prefix "$val" ;;
        # Ajoutée par le chantier « signature » (son plan, Task 10). Elle est
        # déjà sur master : la réécriture POSIX doit la porter, pas la perdre.
        --verify-key)
            [ "$1" != "--" ] || { printf "L'option --verify-key attend une empreinte.\n" >&2; exit 2; }
            val="$1"; shift
            set -- "$@" --verify-key "$val" ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Option inconnue : %s\n' "$arg" >&2; exit 2 ;;
    esac
done
shift    # retire la sentinelle

ROOT="$(nivuus_local_root || true)"
if [ -z "$ROOT" ]; then
    nivuus_bootstrap "$@"      # défini en Task 4 ; jusque-là : message d'erreur
    exit $?
fi

"$ROOT/bin/nivuus" install "$@"

if [ -n "$RUN_DOCTOR" ]; then
    "$ROOT/bin/nivuus" doctor
fi
```

> **Étape intermédiaire assumée.** Tant que Task 4 n'a pas défini `nivuus_bootstrap`, cette tâche
> livre à sa place une fonction bouchon qui explique et sort en 1 :
>
> ```sh
> nivuus_bootstrap() {
>     printf '%s\n' "Aucun noyau Nivuus à côté de ce script, et l'amorçage n'est pas encore disponible." >&2
>     printf '%s\n' "Extrais l'archive de release et relance ./install.sh depuis son répertoire." >&2
>     return 1
> }
> ```
>
> C'est exactement ce que le dernier test de l'étape 1 attend : sortie non nulle, rien d'écrit.
> Tasks 3 et 4 remplacent ce bouchon.

**Deux détails qui font échouer si on les rate :**
- `set -eu` sans `pipefail` : `pipefail` n'est pas POSIX. Aucun pipeline de ce fichier ne doit donc
  dépendre du code de retour d'un membre intermédiaire — Task 3 en tient compte.
- `--help` n'appelle plus `bin/nivuus help` : en mode amorçage, le noyau n'existe pas encore, et
  télécharger une release pour afficher une aide serait absurde. Le texte vit donc dans `install.sh`,
  et `tests/e2e/test_install_sh_compat.bats` reste vert (il ne cherche que « sage »).

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_install_sh_posix.bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_verify_key.bats`
Expected: PASS. `test_install_sh_compat.bats` n'a **pas** été modifié : c'est la preuve que la
réécriture n'a rien changé au comportement du mode local. `test_verify_key.bats` (chantier
signature) est inclus parce qu'il contient « install.sh forwards --verify-key » : c'est le seul
test qui attrape la perte de cette option pendant la réécriture.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/unit/test_install_sh_posix.bats
git commit -m "refactor(install): make install.sh POSIX sh so it can run under curl | sh"
```

---

### Task 3: Téléchargement portable — `curl`, puis `wget`, puis un refus utile

**Files:**
- Modify: `install.sh`
- Create: `tests/unit/test_install_sh_fetch.bats`

**Interfaces:**
- Produces (dans `install.sh`, POSIX) :
  - `nivuus_fetch <url> <dest>` — 0 si `<dest>` a été écrit. `file://` par copie ; sinon `curl -fsSL` ; sinon `wget -qO` ; sinon message explicite et code 127.
  - `nivuus_sha256 <fichier>` — imprime la somme, via `sha256sum` ou `shasum -a 256`. Échoue s'il n'y en a aucun.
  - `nivuus_die <message…>` — écrit sur stderr et sort en 1.

**Le `file://` par copie est une décision, pas un raccourci.** `curl` lit `file://` nativement,
`wget` non (selon les versions et les distributions). Si le test hors réseau passait par le client
HTTP, la couverture dépendrait du client installé sur le runner — c'est-à-dire qu'elle serait
différente sur Alpine, sur macOS et sur Ubuntu, sans qu'on le sache. On traite donc `file://`
explicitement, et on prouve la **sélection** curl/wget séparément, avec de faux binaires qui
journalisent leur invocation. Les deux moitiés sont testées, aucune n'est supposée.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_install_sh_fetch.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin" "$TMP/www"
    printf 'contenu servi\n' > "$TMP/www/fichier.txt"
    LOG="$TMP/appels.log"
}

teardown() { rm -rf "$TMP"; }

# Exécute une fonction d'install.sh sans déclencher l'installation : le
# fichier ne fait rien tant que NIVUUS_SOURCE_ONLY est posée.
sh_fn() {
    env NIVUUS_SOURCE_ONLY=1 "${TEST_SHELL:-sh}" -c ". '$SH'; $*"
}

# Faux curl / faux wget : ils journalisent leur ligne de commande puis
# écrivent le contenu attendu. C'est la SÉLECTION qu'on teste, pas le
# téléchargement.
fake_downloader() {
    cat > "$TMP/bin/$1" <<EOS
#!/bin/sh
printf '%s %s\n' "$1" "\$*" >> "$LOG"
# Dernier argument non-option = URL ; on écrit dans la destination demandée.
dest=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -o|-O) shift; dest="\$1" ;;
    esac
    shift
done
[ -n "\$dest" ] || exit 3
printf 'contenu servi\n' > "\$dest"
EOS
    chmod +x "$TMP/bin/$1"
}

@test "file:// est servi par copie, sans client HTTP du tout" {
    run env PATH="$TMP/bin:/usr/bin:/bin" NIVUUS_SOURCE_ONLY=1 sh -c \
        ". '$SH'; nivuus_fetch 'file://$TMP/www/fichier.txt' '$TMP/out'"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/out")" = "contenu servi" ]
    [ ! -f "$LOG" ]
}

@test "file:// inexistant échoue au lieu de produire un fichier vide" {
    run sh_fn "nivuus_fetch 'file://$TMP/www/absent.txt' '$TMP/out'"
    [ "$status" -ne 0 ]
    [ ! -f "$TMP/out" ]
}

@test "curl est préféré quand les deux sont là" {
    fake_downloader curl; fake_downloader wget
    run env PATH="$TMP/bin:/usr/bin:/bin" NIVUUS_SOURCE_ONLY=1 sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -eq 0 ]
    run cat "$LOG"
    [[ "$output" == curl* ]]
    [[ "$output" != *wget* ]]
}

@test "wget prend le relais quand curl est absent" {
    fake_downloader wget
    run env PATH="$TMP/bin:/usr/bin:/bin" NIVUUS_SOURCE_ONLY=1 sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -eq 0 ]
    run cat "$LOG"
    [[ "$output" == wget* ]]
}

@test "curl est invoqué en échec-dur (-f) et en suivant les redirections (-L)" {
    fake_downloader curl
    env PATH="$TMP/bin:/usr/bin:/bin" NIVUUS_SOURCE_ONLY=1 sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    run cat "$LOG"
    [[ "$output" == *"-fsSL"* ]]
}

@test "ni curl ni wget : refus explicite, avec la marche à suivre" {
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"wget"* ]]
    [ ! -f "$TMP/out" ]
}

@test "nivuus_sha256 donne la même somme que l'outil du système" {
    printf 'abc\n' > "$TMP/f"
    expected="$( { sha256sum "$TMP/f" 2>/dev/null || shasum -a 256 "$TMP/f"; } | awk '{print $1}')"
    run sh_fn "nivuus_sha256 '$TMP/f'"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "aucun outil sha256 : refus, jamais de contournement" {
    printf 'abc\n' > "$TMP/f"
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c ". '$SH'; nivuus_sha256 '$TMP/f'"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_install_sh_fetch.bats`
Expected: FAIL — ni `NIVUUS_SOURCE_ONLY`, ni `nivuus_fetch`, ni `nivuus_sha256` n'existent ; le
sourçage d'`install.sh` déclenche aujourd'hui la traduction des flags et l'installation.

- [ ] **Step 3: Write minimal implementation**

Ajouter dans `install.sh`, **avant** la traduction des flags :

```sh
nivuus_die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Récupère $1 vers le fichier $2.
#
# Ordre : file:// par copie, puis curl, puis wget. Aucun repli silencieux :
# si aucun client n'est disponible, on dit quoi faire à la main plutôt que
# de sortir en 0 avec un fichier vide.
nivuus_fetch() {
    _url="$1"; _dest="$2"
    case "$_url" in
        file://*)
            # curl sait lire file://, wget pas toujours. Une copie est
            # portable et rend la couverture des tests hors réseau
            # indépendante du client HTTP présent sur la machine.
            _src="${_url#file://}"
            [ -f "$_src" ] || return 1
            cp "$_src" "$_dest" || return 1
            return 0
            ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$_dest" "$_url" || { rm -f "$_dest"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$_dest" "$_url" || { rm -f "$_dest"; return 1; }
    else
        printf '%s\n' "Ni curl ni wget n'est disponible : impossible de télécharger" >&2
        printf '%s\n' "  $_url" >&2
        printf '%s\n' "Installe curl ou wget, ou télécharge l'archive de release à la main" >&2
        printf '%s\n' "puis lance ./install.sh depuis son répertoire (voir doc/INSTALL.md)." >&2
        return 127
    fi
    return 0
}

nivuus_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf '%s\n' "Aucun outil sha256 (sha256sum ou shasum) : l'archive ne peut pas être vérifiée." >&2
        printf '%s\n' "Nivuus n'installe pas ce qu'il ne peut pas vérifier." >&2
        return 1
    fi
}
```

Et, juste avant la traduction des flags, le crochet de sourçage :

```sh
# Crochet de test : sourcé avec NIVUUS_SOURCE_ONLY, ce fichier ne définit
# que ses fonctions. C'est la seule façon de tester nivuus_fetch et
# nivuus_sha256 sans réseau ni installation -- et c'est aussi ce qui rend
# possible de constater le rouge sur chacune d'elles séparément.
[ -n "${NIVUUS_SOURCE_ONLY:-}" ] && return 0 2>/dev/null || :
```

> `return` hors fonction est valide dans un fichier **sourcé** et une erreur dans un fichier
> **exécuté** ; le `|| :` protège du second cas sous les shells qui le refusent bruyamment.
> Placer cette ligne après les définitions de fonctions et avant tout effet de bord.

**Pourquoi pas `--proto '=https'` sur curl.** C'est une bonne idée en production et une mauvaise ici :
elle interdirait `NIVUUS_RELEASE_BASE_URL` en `http://` (miroir interne, proxy d'entreprise) sans
prévenir, et n'apporte rien contre l'attaque qu'on peut réellement traiter — la vérification
d'empreinte de Task 4 couvre le transfert. Documenté dans `doc/INSTALL.md` (Task 11).

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_install_sh_fetch.bats tests/unit/test_install_sh_posix.bats`
Expected: PASS. Le test « aucun bashisme » de Task 2 couvre aussi le code ajouté ici.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/unit/test_install_sh_fetch.bats
git commit -m "feat(install): portable fetch with curl, wget and a useful refusal"
```

---

### Task 4: Le mode d'amorçage — télécharger, vérifier, installer, ne rien laisser

**Files:**
- Modify: `install.sh`
- Create: `tests/unit/test_install_sh_bootstrap.bats`

**Interfaces:**
- Produces (dans `install.sh`) :
  - `nivuus_resolve_version` — imprime la version à installer : `$NIVUUS_VERSION`, sinon le `tag_name` de `<api>/repos/<repo>/releases/latest`, sinon `$NIVUUS_PINNED_VERSION`.
  - `nivuus_bootstrap <args…>` — télécharge, vérifie, extrait, délègue, nettoie. Remplace le bouchon de Task 2.
  - Variables : `NIVUUS_VERSION`, `NIVUUS_RELEASE_BASE_URL` (défaut `https://github.com/<repo>/releases/download`), `NIVUUS_GITHUB_API` (défaut `https://api.github.com`), `NIVUUS_GITHUB_REPO` (défaut `maximeallanic/nivuus-shell`).
- Consumes : `nivuus_fetch`, `nivuus_sha256` (Task 3), `bin/nivuus install` et `lib/deps.sh` **de l'archive extraite**.

**Invariants que les tests imposent :**
1. Une archive dont l'empreinte ne correspond pas n'est **jamais** extraite, et rien n'est écrit.
2. Un `SHA256SUMS` absent, illisible, ou sans ligne pour cette archive ⇒ refus. Pas de repli.
3. Le répertoire temporaire est supprimé **dans tous les cas** : succès, refus, `Ctrl-C`.
4. Rien de ce qui est installé ne contient de `.git`.
5. Une archive d'une version antérieure au nouvel installeur (pas de `bin/nivuus` dedans) produit
   un message qui **nomme la version** et dit quoi faire — pas une trace `command not found`.
6. `bash` absent ⇒ la commande d'installation exacte est affichée, via `lib/deps.sh` de l'archive
   extraite, et **jamais exécutée**.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_install_sh_bootstrap.bats
#!/usr/bin/env bats

load '../helpers/release'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    # Un TMPDIR à nous : c'est la seule façon d'affirmer « aucun temporaire
    # laissé derrière » sans se prononcer sur /tmp partagé avec le reste.
    export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"

    # Une copie isolée du script : sans noyau à côté, elle est forcément en
    # mode amorçage, quel que soit le répertoire courant.
    cp "$SH" "$TMP/install.sh"

    make_release "$ROOT" "$TMP/releases" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

boot() { run sh "$TMP/install.sh" "$@"; }

@test "amorçage nominal : installe depuis l'archive vérifiée" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
    [ -f "$TMP/target/bin/nivuus" ]
}

@test "amorçage : aucun dépôt git derrière lui" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target/.git" ]
    run find "$TMP/target" -name '.git' -maxdepth 3
    [ -z "$output" ]
}

@test "amorçage : aucun répertoire temporaire laissé derrière" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    run find "$TMPDIR" -maxdepth 1 -name 'nivuus-boot.*'
    [ -z "$output" ]
}

@test "INVARIANT: archive falsifiée -> refus, rien d'écrit, rien de laissé" {
    tamper_release "$TMP/releases" 9.9.9
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"mpreinte"* ]]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
    run find "$TMPDIR" -maxdepth 1 -name 'nivuus-boot.*'
    [ -z "$output" ]
}

@test "INVARIANT: SHA256SUMS absent -> refus, pas de repli" {
    rm -f "$TMP/releases/v9.9.9/SHA256SUMS"
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}

@test "INVARIANT: SHA256SUMS sans ligne pour cette archive -> refus" {
    printf 'deadbeef  autre-chose.tar.gz\n' > "$TMP/releases/v9.9.9/SHA256SUMS"
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}

@test "la version vient de l'API quand NIVUUS_VERSION n'est pas posée" {
    make_release "$ROOT" "$TMP/releases" 7.7.7
    make_release_api "$TMP/api" fake/nivuus 7.7.7
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/target/.version")" = "7.7.7" ] || \
      grep -q '7.7.7' "$TMP/target/.version"
}

@test "NIVUUS_VERSION l'emporte sur l'API" {
    make_release_api "$TMP/api" fake/nivuus 7.7.7
    run env NIVUUS_VERSION=9.9.9 sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/bin/nivuus" ]
}

@test "API injoignable -> repli sur la version épinglée, avec un message" {
    run env NIVUUS_GITHUB_API="file://$TMP/api-absente" \
        NIVUUS_RELEASE_BASE_URL="file://$TMP/releases" \
        sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    # La version épinglée (3.0.0) n'a pas d'archive ici : l'échec est
    # attendu, mais il doit NOMMER la version et le repli, pas planter.
    [ "$status" -ne 0 ]
    [[ "$output" == *"3.0.0"* ]]
}

@test "archive antérieure au nouvel installeur -> message qui nomme la version" {
    # Une release qui ne contient pas bin/nivuus : exactement le cas de
    # v3.0.0 si quelqu'un l'épingle.
    mkdir -p "$TMP/vieux/config"
    printf 'echo vieux\n' > "$TMP/vieux/config/00-core.zsh"
    make_release "$TMP/vieux" "$TMP/releases" 3.0.0
    run env NIVUUS_VERSION=3.0.0 sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"3.0.0"* ]]
    [ ! -e "$TMP/target" ]
}

@test "--dry-run en amorçage : télécharge, vérifie, n'écrit rien" {
    boot --non-interactive --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "bash absent : commande d'installation affichée, jamais exécutée" {
    mkdir -p "$TMP/bin"
    for c in sh cp mv rm mkdir cat tar find sed awk grep cut head chmod \
             mktemp sha256sum shasum command dirname basename id; do
        p="$(command -v "$c" 2>/dev/null)" || continue
        ln -sf "$p" "$TMP/bin/$c"
    done
    run env PATH="$TMP/bin" NIVUUS_VERSION=9.9.9 \
        NIVUUS_RELEASE_BASE_URL="file://$TMP/releases" \
        /bin/sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"bash"* ]]
    [ ! -e "$TMP/target" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_install_sh_bootstrap.bats`
Expected: FAIL — `nivuus_bootstrap` est encore le bouchon de Task 2 : il sort en 1 avec « l'amorçage
n'est pas encore disponible ». Les douze tests échouent, dont ceux qui attendent un refus (le code
de sortie est bon mais le message et l'absence d'écriture ne prouvent rien tant qu'il n'y a pas de
téléchargement à refuser).

- [ ] **Step 3: Write minimal implementation**

Remplacer le bouchon par :

```sh
: "${NIVUUS_GITHUB_REPO:=maximeallanic/nivuus-shell}"
: "${NIVUUS_GITHUB_API:=https://api.github.com}"
: "${NIVUUS_RELEASE_BASE_URL:=https://github.com/$NIVUUS_GITHUB_REPO/releases/download}"

# Version à installer : ce que l'utilisateur demande, sinon la dernière
# release publiée, sinon le plancher épinglé dans ce fichier.
#
# Le plancher n'est pas de la redondance : l'API GitHub non authentifiée
# est limitée à 60 requêtes/h et par IP, ce qui est atteint tous les jours
# derrière un NAT d'entreprise ou sur un runner partagé. Sans plancher, le
# one-liner y devient un tirage au sort.
nivuus_resolve_version() {
    if [ -n "${NIVUUS_VERSION:-}" ]; then
        printf '%s\n' "$NIVUUS_VERSION"
        return 0
    fi
    _api_tmp="$(mktemp "${TMPDIR:-/tmp}/nivuus-api.XXXXXX")" || return 1
    if nivuus_fetch "$NIVUUS_GITHUB_API/repos/$NIVUUS_GITHUB_REPO/releases/latest" "$_api_tmp"; then
        _tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' "$_api_tmp" | head -n1)"
    else
        _tag=''
    fi
    rm -f "$_api_tmp"
    if [ -n "$_tag" ]; then
        printf '%s\n' "$_tag"
    else
        printf '%s\n' "Dernière version indisponible (réseau ou quota d'API) ; repli sur la version épinglée $NIVUUS_PINNED_VERSION." >&2
        printf '%s\n' "$NIVUUS_PINNED_VERSION"
    fi
}

nivuus_bootstrap() {
    _version="$(nivuus_resolve_version)" || nivuus_die "Impossible de déterminer la version à installer."
    [ -n "$_version" ] || nivuus_die "Impossible de déterminer la version à installer."
    _archive="nivuus-shell-v${_version}.tar.gz"
    _base="$NIVUUS_RELEASE_BASE_URL/v${_version}"

    NIVUUS_BOOT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nivuus-boot.XXXXXX")" \
        || nivuus_die "Impossible de créer un répertoire temporaire."
    # Le nettoyage est posé AVANT le premier téléchargement : un refus, un
    # Ctrl-C ou une coupure réseau ne doivent pas laisser 50 Mo derrière.
    trap 'rm -rf "$NIVUUS_BOOT_TMP"' EXIT
    trap 'rm -rf "$NIVUUS_BOOT_TMP"; exit 130' INT
    trap 'rm -rf "$NIVUUS_BOOT_TMP"; exit 143' TERM HUP

    printf '%s\n' "Téléchargement de Nivuus Shell v${_version}…"
    nivuus_fetch "$_base/$_archive" "$NIVUUS_BOOT_TMP/$_archive" \
        || nivuus_die "Téléchargement impossible : $_base/$_archive"
    nivuus_fetch "$_base/SHA256SUMS" "$NIVUUS_BOOT_TMP/SHA256SUMS" \
        || nivuus_die "Sommes de contrôle indisponibles pour la v${_version}. Installation refusée."

    # Vérification fail-closed : pas d'option pour la désactiver. Ce qui
    # n'est pas vérifiable n'est pas installé.
    _expected="$(awk -v a="$_archive" '$2 == a || $2 == "./" a { print $1; exit }' "$NIVUUS_BOOT_TMP/SHA256SUMS")"
    [ -n "$_expected" ] || nivuus_die "Aucune somme de contrôle pour $_archive. Installation refusée."
    _actual="$(nivuus_sha256 "$NIVUUS_BOOT_TMP/$_archive")" \
        || nivuus_die "Installation refusée : l'archive n'a pas pu être vérifiée."
    if [ "$_expected" != "$_actual" ]; then
        printf '%s\n' "Empreinte de l'archive incorrecte. Installation refusée." >&2
        printf '%s\n' "  attendue : $_expected" >&2
        printf '%s\n' "  obtenue  : $_actual" >&2
        exit 1
    fi
    printf '%s\n' "Empreinte vérifiée."

    mkdir -p "$NIVUUS_BOOT_TMP/src"
    tar -xzf "$NIVUUS_BOOT_TMP/$_archive" -C "$NIVUUS_BOOT_TMP/src" \
        || nivuus_die "Archive illisible. Installation refusée."

    # Les archives de release n'ont pas de répertoire racine ; celles que
    # GitHub génère automatiquement en ont un. On accepte les deux formes,
    # sans deviner : on cherche le noyau.
    _src="$NIVUUS_BOOT_TMP/src"
    if [ ! -f "$_src/bin/nivuus" ]; then
        _inner="$(find "$NIVUUS_BOOT_TMP/src" -mindepth 1 -maxdepth 1 -type d | head -n1)"
        if [ -n "$_inner" ] && [ -f "$_inner/bin/nivuus" ]; then
            _src="$_inner"
        fi
    fi
    if [ ! -f "$_src/bin/nivuus" ]; then
        printf '%s\n' "La release v${_version} ne contient pas bin/nivuus : elle est antérieure au nouvel installeur." >&2
        printf '%s\n' "Installe une version plus récente (n'épingle pas NIVUUS_VERSION), ou consulte doc/INSTALL.md." >&2
        exit 1
    fi
    chmod +x "$_src/bin/"* 2>/dev/null || :

    # bin/nivuus est en bash (décision du spec) ; l'amorçage, lui, est POSIX.
    # Si bash manque, on donne la commande exacte -- calculée par lib/deps.sh
    # de l'archive, qui est exécutable sous ash depuis la phase 3 -- et on ne
    # l'exécute jamais.
    if ! command -v bash >/dev/null 2>&1; then
        printf '%s\n' "bash est requis pour l'installeur Nivuus et n'est pas présent." >&2
        if [ -f "$_src/lib/log.sh" ] && [ -f "$_src/lib/deps.sh" ]; then
            # shellcheck source=/dev/null
            . "$_src/lib/log.sh"; . "$_src/lib/deps.sh"
            printf '%s\n' "Installe-le puis relance :" >&2
            printf '  %s\n' "$(nivuus_pkg_install_cmd bash)" >&2
        fi
        exit 1
    fi

    "$_src/bin/nivuus" install "$@"
    _rc=$?
    if [ -n "$RUN_DOCTOR" ] && [ "$_rc" -eq 0 ]; then
        "$_src/bin/nivuus" doctor || :
    fi
    return "$_rc"
}
```

**Deux pièges que ces tests attrapent, et qu'il ne faut pas contourner :**

- **`exec` est interdit ici.** Remplacer le processus par `bin/nivuus` annulerait le `trap` et
  laisserait le temporaire — le test « aucun répertoire temporaire laissé derrière » tombe. On
  appelle, on garde le code de retour, on laisse le `trap` faire son travail.
- **`set -eu` et le code de retour.** `"$_src/bin/nivuus" install "$@"` en échec sortirait
  immédiatement sous `set -e`, avant le nettoyage explicite ; le `trap … EXIT` couvre ce cas, mais
  la capture `_rc=$?` n'est atteinte que si l'appel réussit. Si l'implémentation a besoin du code
  exact en cas d'échec, encadrer par `if … ; then _rc=0; else _rc=$?; fi`.

**Interaction et TTY.** Sous `curl … | sh`, l'entrée standard est le script lui-même : `confirm()`
ne doit pas y lire. `nivuus_is_tty` renvoie déjà faux dans ce cas, et `confirm` accepte alors sans
lire — comportement correct, mais silencieux. On le rend explicite : si `/dev/tty` est lisible,
l'appel à `bin/nivuus install` prend son entrée dessus, sinon on ajoute `--yes`. Une ligne, avant
l'appel :

```sh
    if [ -t 0 ]; then
        "$_src/bin/nivuus" install "$@"; _rc=$?
    elif [ -r /dev/tty ]; then
        "$_src/bin/nivuus" install "$@" < /dev/tty; _rc=$?
    else
        "$_src/bin/nivuus" install --yes "$@"; _rc=$?
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_install_sh_bootstrap.bats tests/unit/test_install_sh_fetch.bats tests/unit/test_install_sh_posix.bats tests/e2e/test_install_sh_compat.bats`
Expected: PASS. Vérifier en particulier que le test « aucun bashisme » de Task 2 est toujours vert :
le code ci-dessus n'utilise ni `local` ni tableau, d'où les variables préfixées `_`.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/unit/test_install_sh_bootstrap.bats
git commit -m "feat(install): real curl | sh bootstrap with fail-closed verification"
```

---

### Task 5: `git` n'est plus une dépendance requise

**Files:**
- Modify: `lib/deps.sh`
- Modify: `bin/healthcheck`
- Test: `tests/unit/test_lib_deps.bats` (existant, à étendre)
- Create: `tests/e2e/test_install_without_git.bats`

**Interfaces:**
- Produces : `NIVUUS_DEPS_REQUIRED='zsh curl'`, `NIVUUS_DEPS_RECOMMENDED='git fzf'`.
- Consumers : `nivuus_deps_check_required` (appelé par `cmd_install` via `nivuus_step_check_required_deps`), `bin/healthcheck`.

**Pourquoi c'est une correction et pas un assouplissement.** Après Task 4, plus rien dans le chemin
d'installation n'utilise `git` : ni le téléchargement (`curl`/`wget`), ni l'extraction (`tar`), ni
la copie (`lib/steps.sh`), ni la mise à jour (`config/20-autoupdate.zsh`, qui passe par les
releases). `git` sert au **prompt** — une fonctionnalité qui se dégrade proprement en son absence.
Le laisser en dépendance requise ferait échouer l'installation sur une image `debian:12-slim` ou
`alpine` nue pour une raison fausse, sur la première ligne de sortie du one-liner. `curl` reste
requis : l'auto-update en dépend, et le refuser reviendrait à installer un shell qui ne peut pas
se mettre à jour.

- [ ] **Step 1: Write the failing test**

```bash
# Ajouts à tests/unit/test_lib_deps.bats

@test "git n'est PAS une dépendance requise" {
    run nivuus_deps_list required
    [ "$status" -eq 0 ]
    [[ "$output" != *"git"* ]]
}

@test "zsh et curl restent requis" {
    run nivuus_deps_list required
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"curl"* ]]
}

@test "git est recommandé (prompt git), pas oublié" {
    run nivuus_deps_list recommended
    [ "$status" -eq 0 ]
    [[ "$output" == *"git"* ]]
}

@test "check_required réussit sans git" {
    fake="$TMP/bin"; mkdir -p "$fake"
    for c in zsh curl; do printf '#!/bin/sh\nexit 0\n' > "$fake/$c"; chmod +x "$fake/$c"; done
    run env PATH="$fake" bash -c ". '$LIB/log.sh'; . '$LIB/deps.sh'; nivuus_deps_check_required"
    [ "$status" -eq 0 ]
}

@test "check_required échoue toujours sans curl" {
    fake="$TMP/bin"; mkdir -p "$fake"
    printf '#!/bin/sh\nexit 0\n' > "$fake/zsh"; chmod +x "$fake/zsh"
    run env PATH="$fake" bash -c ". '$LIB/log.sh'; . '$LIB/deps.sh'; nivuus_deps_check_required"
    [ "$status" -ne 0 ]
    [[ "$output" == *"curl"* ]]
}
```

```bash
# tests/e2e/test_install_without_git.bats
#!/usr/bin/env bats
#
# Le one-liner ne clone plus rien : une machine sans git doit pouvoir
# installer, charger le shell, et désinstaller. Ce test le prouve en
# retirant git du PATH, pas en le supposant.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    # Un PATH sans git, mais avec tout le reste : on ne teste pas un
    # système amputé, on teste l'absence d'UN outil.
    NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
    for d in /usr/local/bin /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -x "$f" ] || continue
            b="${f##*/}"
            [ "$b" = "git" ] && continue
            [ -e "$NOGIT/$b" ] || ln -sf "$f" "$NOGIT/$b"
        done
    done
}

teardown() { rm -rf "$TMP"; }

@test "installation complète sans git dans le PATH" {
    run env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
    [ -f "$HOME/.zshrc" ]
}

@test "le shell charge sans git" {
    env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    run env PATH="$NOGIT" HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "install puis uninstall sans git laisse HOME bit-identique" {
    fs_fingerprint "$HOME" > "$TMP/before"
    env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    env PATH="$NOGIT" "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_deps.bats tests/e2e/test_install_without_git.bats`
Expected: FAIL — `NIVUUS_DEPS_REQUIRED` contient `git` ; `nivuus_deps_check_required` refuse de
démarrer sans lui, donc les trois tests e2e échouent avec « Dépendances requises manquantes : git ».

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/deps.sh
# git a quitté les dépendances requises : depuis la phase 5, rien dans le
# chemin d'installation ni de mise à jour ne l'utilise (téléchargement par
# curl/wget, extraction par tar, mise à jour par release). Il reste
# recommandé, parce que le prompt git est l'une des fonctions les plus
# visibles -- mais son absence dégrade, elle ne bloque pas.
NIVUUS_DEPS_REQUIRED='zsh curl'
NIVUUS_DEPS_RECOMMENDED='git fzf'
NIVUUS_DEPS_OPTIONAL='bat eza grc'
```

Dans `bin/healthcheck`, `check_command "git" "--version"` doit devenir un avertissement et non une
erreur (aligner sur le traitement déjà appliqué aux outils recommandés) — sinon `nivuus doctor`
affiche une croix rouge pour une situation supportée.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_deps.bats tests/e2e/test_install_without_git.bats tests/e2e/test_with_deps.bats tests/e2e/test_platform.bats`
Expected: PASS. `test_with_deps.bats` est inclus parce qu'il compte les paquets proposés :
déplacer `git` de `required` vers `recommended` change cette liste, et si une assertion s'y
appuyait, c'est ici qu'on le découvre.

- [ ] **Step 5: Commit**

```bash
git add lib/deps.sh bin/healthcheck tests/unit/test_lib_deps.bats tests/e2e/test_install_without_git.bats
git commit -m "feat(deps): git is no longer required to install Nivuus"
```

---

### Task 6: `lib/migrate.sh` — reconnaître le dépôt parasite, et rien d'autre

**Files:**
- Create: `lib/migrate.sh`
- Create: `tests/unit/test_lib_migrate.bats`

**Interfaces:**
- Produces (POSIX, bash 3.2 / ash), **lecture seule, aucune écriture** :
  - `nivuus_git_state <dir>` — imprime exactement un mot : `none` (pas de `.git`), `legacy` (l'empreinte de `init_git_repo()`, et elle seule), `dev` (tout le reste), `unknown` (git indisponible alors qu'un `.git` existe).
  - `nivuus_git_report <dir>` — quelques lignes lisibles décrivant ce qui a été constaté : nombre de commits, remote, modifications, fichiers non suivis.
- Consumers : `bin/nivuus` (Task 7), `bin/healthcheck` (Task 7), `config/20-autoupdate.zsh` (Task 8).

**Le critère de détection, et pourquoi il est aussi strict.** L'ancien `init_git_repo()`
(`git show v3.0.0:install.sh`, lignes 334-346) produit un dépôt dont **toutes** les propriétés
suivantes sont vraies simultanément :

| # | Propriété | Vérification |
|---|---|---|
| 1 | `.git` est un **répertoire** | `[ -d "$dir/.git" ]` et **pas** `[ -f … ]` (un `.git` fichier est un worktree ou un submodule : jamais le nôtre) |
| 2 | exactement **un** commit | `git rev-list --count HEAD` = `1` |
| 3 | son message est celui de l'installeur | `git log -1 --format=%s` = `Initial Nivuus Shell installation` |
| 4 | aucun remote, ou `origin` seul pointant sur l'amont | `git remote` ⊆ `{origin}` et son URL ∈ URLs amont connues |
| 5 | aucune modification de fichier suivi | `git status --porcelain --untracked-files=no` vide |
| 6 | aucun stash | `git stash list` vide |
| 7 | exactement une branche locale | `git for-each-ref refs/heads` = 1 ligne |

Un vrai checkout de développement échoue sur (2), (3), (5) ou (7) — le plus souvent sur les quatre.
**Au moindre doute, la réponse est `dev`** : le coût d'un faux négatif est un utilisateur qui doit
lancer une commande à la main ; le coût d'un faux positif est du travail détruit. Les fichiers
**non suivis** (`*.zwc` compilés par zsh à l'exécution) sont tolérés et comptés dans le rapport :
ce n'est pas du travail, c'est du bytecode régénérable, et l'exiger absents rendrait la détection
inopérante sur toutes les machines réelles.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_migrate.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/migrate.sh"
    TMP="$(mktemp -d)"
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

teardown() { rm -rf "$TMP"; }

# Reproduit EXACTEMENT init_git_repo() de v3.0.0 (install.sh:334-346).
make_legacy() {
    d="$1"; mkdir -p "$d"; printf 'contenu\n' > "$d/fichier"
    ( cd "$d"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

@test "pas de .git -> none" {
    mkdir -p "$TMP/vide"
    run nivuus_git_state "$TMP/vide"
    [ "$output" = "none" ]
}

@test "le dépôt de init_git_repo() -> legacy" {
    make_legacy "$TMP/legacy"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "des .zwc non suivis ne changent rien -> legacy" {
    make_legacy "$TMP/legacy"
    printf 'bytecode\n' > "$TMP/legacy/fichier.zwc"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "un fichier SUIVI modifié -> dev" {
    make_legacy "$TMP/legacy"
    printf 'edite\n' > "$TMP/legacy/fichier"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un second commit -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && printf 'x\n' > b && git add b && git commit -q -m "mon travail" ) >/dev/null
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un message de commit différent -> dev" {
    d="$TMP/autre"; mkdir -p "$d"; printf 'x\n' > "$d/f"
    ( cd "$d"; git -c init.defaultBranch=master init -q .
      git add -A .; git commit -q -m "Initial commit" ) >/dev/null 2>&1
    run nivuus_git_state "$d"
    [ "$output" = "dev" ]
}

@test "un remote qui n'est pas l'amont -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote set-url origin "https://exemple.invalide/moi/fork.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "le remote amont en HTTPS est accepté -> legacy" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote set-url origin "https://github.com/maximeallanic/nivuus-shell.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "un remote supplémentaire -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote add upstream "https://exemple.invalide/x.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "une seconde branche -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git branch feature ) >/dev/null
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un stash -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && printf 'wip\n' > fichier && git stash -q ) >/dev/null 2>&1
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un .git FICHIER (worktree, submodule) -> dev, jamais legacy" {
    mkdir -p "$TMP/wt"
    printf 'gitdir: /ailleurs/.git/worktrees/wt\n' > "$TMP/wt/.git"
    run nivuus_git_state "$TMP/wt"
    [ "$output" = "dev" ]
}

@test "le checkout de développement de Nivuus lui-même -> dev" {
    # Le garde-fou qui compte : ce dépôt-ci ne doit JAMAIS être vu legacy.
    run nivuus_git_state "${BATS_TEST_DIRNAME}/../.."
    [ "$output" = "dev" ]
}

@test "git absent alors qu'un .git existe -> unknown, jamais legacy" {
    make_legacy "$TMP/legacy"
    fake="$TMP/bin"; mkdir -p "$fake"
    for c in sh cat head awk sed grep; do
        p="$(command -v $c)" && ln -sf "$p" "$fake/$c"
    done
    run env PATH="$fake" bash -c ". '$LIB/log.sh'; . '$LIB/migrate.sh'; nivuus_git_state '$TMP/legacy'"
    [ "$output" = "unknown" ]
}

@test "nivuus_git_state n'écrit rien du tout" {
    make_legacy "$TMP/legacy"
    before="$(find "$TMP/legacy" | LC_ALL=C sort)"
    nivuus_git_state "$TMP/legacy" >/dev/null
    after="$(find "$TMP/legacy" | LC_ALL=C sort)"
    [ "$before" = "$after" ]
}

@test "nivuus_git_report décrit ce qu'il a constaté" {
    make_legacy "$TMP/legacy"
    run nivuus_git_report "$TMP/legacy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commit"* ]]
    [[ "$output" == *"origin"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_migrate.bats`
Expected: FAIL — `lib/migrate.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/migrate.sh
# Reconnaît le dépôt git que l'ancien init_git_repo() (v3.0.0,
# install.sh:334-346) créait dans ~/.nivuus-shell -- et que
# config/20-autoupdate.zsh prend pour un checkout de développement, ce qui
# désactive silencieusement l'auto-update de toutes les installations
# issues du one-liner historique.
#
# Ce module ne fait que CONSTATER. Il n'écrit rien, jamais : le
# déplacement passe par lib/manifest.sh, seule bibliothèque autorisée à
# toucher au système de fichiers.
# POSIX / bash 3.2 : sourcé par bin/nivuus, bin/healthcheck et, à la
# demande, par config/20-autoupdate.zsh.

NIVUUS_LEGACY_COMMIT_SUBJECT='Initial Nivuus Shell installation'
# Les deux formes sous lesquelles l'amont a pu être enregistré. v3.0.0
# écrivait la forme SSH ; la forme HTTPS est acceptée parce qu'un
# utilisateur a pu la corriger à la main en tentant de réparer sa mise à
# jour -- ce qui ne fait pas de son répertoire un dépôt de travail.
NIVUUS_LEGACY_REMOTES='git@github.com:maximeallanic/nivuus-shell.git
https://github.com/maximeallanic/nivuus-shell.git
https://github.com/maximeallanic/nivuus-shell'

# Imprime exactement un mot : none | legacy | dev | unknown.
# En cas de doute, « dev » -- c'est-à-dire : on ne touche à rien.
nivuus_git_state() {
    local dir="$1" subject remotes url branches

    if [ -f "$dir/.git" ]; then
        # Fichier et non répertoire : worktree lié ou submodule. Jamais le nôtre.
        printf 'dev\n'; return 0
    fi
    if [ ! -d "$dir/.git" ]; then
        printf 'none\n'; return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        printf 'unknown\n'; return 0
    fi

    # (2) exactement un commit
    [ "$(git -C "$dir" rev-list --count HEAD 2>/dev/null || printf 0)" = "1" ] \
        || { printf 'dev\n'; return 0; }

    # (3) le message de l'installeur, mot pour mot
    subject="$(git -C "$dir" log -1 --format=%s 2>/dev/null || printf '')"
    [ "$subject" = "$NIVUUS_LEGACY_COMMIT_SUBJECT" ] || { printf 'dev\n'; return 0; }

    # (4) aucun remote, ou « origin » seul et pointant sur l'amont
    remotes="$(git -C "$dir" remote 2>/dev/null || printf '')"
    if [ -n "$remotes" ]; then
        [ "$remotes" = "origin" ] || { printf 'dev\n'; return 0; }
        url="$(git -C "$dir" remote get-url origin 2>/dev/null || printf '')"
        printf '%s\n' "$NIVUUS_LEGACY_REMOTES" | grep -qxF "$url" \
            || { printf 'dev\n'; return 0; }
    fi

    # (5) aucun fichier SUIVI modifié. Les non-suivis (*.zwc compilés par
    # zsh à l'exécution) sont tolérés : ce n'est pas du travail.
    [ -z "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null || printf x)" ] \
        || { printf 'dev\n'; return 0; }

    # (6) aucun stash
    [ -z "$(git -C "$dir" stash list 2>/dev/null || printf x)" ] \
        || { printf 'dev\n'; return 0; }

    # (7) exactement une branche locale
    branches="$(git -C "$dir" for-each-ref --format='%(refname)' refs/heads 2>/dev/null | wc -l | tr -d ' ')"
    [ "$branches" = "1" ] || { printf 'dev\n'; return 0; }

    printf 'legacy\n'
}

# Ce que l'utilisateur a le droit de voir avant de décider. Lecture seule.
nivuus_git_report() {
    local dir="$1"
    [ -d "$dir/.git" ] || { printf 'Aucun dépôt git dans %s\n' "$dir"; return 0; }
    command -v git >/dev/null 2>&1 || { printf 'git indisponible : impossible de décrire %s/.git\n' "$dir"; return 0; }
    printf 'Dépôt git dans %s :\n' "$dir"
    printf '  commits            : %s\n' "$(git -C "$dir" rev-list --count HEAD 2>/dev/null || printf '?')"
    printf '  dernier message    : %s\n' "$(git -C "$dir" log -1 --format=%s 2>/dev/null || printf '?')"
    printf '  remotes            : %s\n' "$(git -C "$dir" remote -v 2>/dev/null | tr '\n' ' ' || printf 'aucun')"
    printf '  branches locales   : %s\n' "$(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | tr '\n' ' ')"
    printf '  fichiers modifiés  : %s\n' "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
    printf '  fichiers non suivis: %s\n' "$(git -C "$dir" status --porcelain --untracked-files=all 2>/dev/null | grep -c '^??' || printf 0)"
    printf '  stash              : %s\n' "$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_migrate.bats tests/unit/test_lib_posix.bats`
Expected: PASS (16 tests). `test_lib_posix.bats` vérifie que la nouvelle bibliothèque reste
exécutable sous un shell POSIX — contrainte de la phase 3, à laquelle `lib/migrate.sh` ne fait pas
exception.

- [ ] **Step 5: Commit**

```bash
git add lib/migrate.sh tests/unit/test_lib_migrate.bats
git commit -m "feat(migrate): recognise the legacy init_git_repo checkout, and nothing else"
```

---

### Task 7: `nivuus migrate` — expliquer, demander, déplacer (jamais supprimer)

**Files:**
- Modify: `lib/manifest.sh` (ajout de `nivuus_move_aside`)
- Modify: `bin/nivuus` (sous-commande `migrate`, garde dans `cmd_update`)
- Modify: `bin/healthcheck` (rapport en lecture seule)
- Create: `tests/unit/test_manifest_move_aside.bats`
- Create: `tests/e2e/test_migrate_git.bats`

**Interfaces:**
- Produces :
  - `nivuus_move_aside <src> <dst>` (`lib/manifest.sh`) — déplace `<src>` vers `<dst>` en créant les parents, honore `NIVUUS_DRY_RUN`, échoue si `<dst>` existe déjà. Imprime le chemin de destination.
  - `nivuus migrate [--dry-run] [--yes]` — constate l'état, l'explique, demande, déplace `~/.nivuus-shell/.git` vers `$NIVUUS_STATE_DIR/migration/<horodatage>/git`.
  - `nivuus update` — refuse et renvoie vers `nivuus migrate` quand l'état est `legacy`.
  - `nivuus doctor` — signale l'état `legacy` sans jamais agir.
- Consumes : `nivuus_git_state`, `nivuus_git_report` (Task 6).

**Trois décisions incorporées aux tests :**
- **Déplacer, pas supprimer.** Le chemin de destination est affiché, et la commande pour revenir en
  arrière avec. Un outil dont l'argument de vente est la réversibilité n'a pas le droit de faire
  un `rm -rf` sur un répertoire `.git`, si convaincue soit sa détection.
- **`migrate` ne touche à rien quand l'état est `dev`, `unknown` ou `none`.** Il l'explique et sort
  en 0 : ce n'est pas une erreur d'appeler `migrate` sur une installation saine.
- **`--yes` est nécessaire hors TTY.** `confirm()` accepte par défaut sans TTY, ce qui convient à une
  installation mais pas à un déplacement de `.git`. `cmd_migrate` exige donc explicitement
  `ASSUME_YES` **ou** un TTY, sinon il affiche le rapport et sort en 0 sans agir.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_manifest_move_aside.bats
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/src/sous"; printf 'x\n' > "$TMP/src/sous/f"
}

teardown() { rm -rf "$TMP"; }

@test "move_aside déplace et imprime la destination" {
    run nivuus_move_aside "$TMP/src" "$TMP/etat/migration/1/git"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/etat/migration/1/git" ]
    [ ! -e "$TMP/src" ]
    [ -f "$TMP/etat/migration/1/git/sous/f" ]
}

@test "move_aside crée les répertoires parents manquants" {
    nivuus_move_aside "$TMP/src" "$TMP/a/b/c/git"
    [ -d "$TMP/a/b/c/git" ]
}

@test "move_aside refuse d'écraser une destination existante" {
    mkdir -p "$TMP/dest"
    run nivuus_move_aside "$TMP/src" "$TMP/dest"
    [ "$status" -ne 0 ]
    [ -d "$TMP/src" ]
}

@test "move_aside échoue si la source n'existe pas" {
    run nivuus_move_aside "$TMP/absent" "$TMP/dest"
    [ "$status" -ne 0 ]
}

@test "move_aside ne déplace rien en dry-run" {
    run env NIVUUS_DRY_RUN=1 bash -c \
        ". '$LIB/log.sh'; . '$LIB/manifest.sh'; nivuus_move_aside '$TMP/src' '$TMP/dest'"
    [ "$status" -eq 0 ]
    [ -d "$TMP/src" ]
    [ ! -e "$TMP/dest" ]
}
```

```bash
# tests/e2e/test_migrate_git.bats
#!/usr/bin/env bats
#
# Le cas d'usage réel : une installation issue du one-liner historique,
# dont l'auto-update est désactivé depuis v3.0.0 parce que init_git_repo()
# y a laissé un dépôt git.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    PREFIX="$HOME/.nivuus-shell"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
}

teardown() { rm -rf "$TMP"; }

legacy_git() {
    ( cd "$PREFIX"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

@test "migrate déplace le .git parasite et dit où" {
    legacy_git
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/.git" ]
    [[ "$output" == *"migration"* ]]
    run find "$NIVUUS_STATE_DIR/migration" -maxdepth 3 -name HEAD
    [ -n "$output" ]
}

@test "migrate ne supprime rien : le dépôt reste ouvrable" {
    legacy_git
    "$NIVUUS" migrate --yes >/dev/null
    moved="$(find "$NIVUUS_STATE_DIR/migration" -maxdepth 2 -type d -name git | head -n1)"
    [ -n "$moved" ]
    run git --git-dir="$moved" log -1 --format=%s
    [ "$status" -eq 0 ]
    [ "$output" = "Initial Nivuus Shell installation" ]
}

@test "après migrate, l'installation charge toujours" {
    legacy_git
    "$NIVUUS" migrate --yes >/dev/null
    run env HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "INVARIANT: migrate ne touche PAS un vrai dépôt de développement" {
    legacy_git
    ( cd "$PREFIX" && printf 'mon travail\n' > TRAVAIL && git add TRAVAIL \
      && git commit -q -m "mon travail en cours" ) >/dev/null
    fs_fingerprint "$PREFIX" > "$TMP/before"
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    fs_fingerprint "$PREFIX" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "migrate sur une installation saine : ne fait rien, sort en 0" {
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"ien à migrer"* ]]
}

@test "migrate --dry-run ne déplace rien" {
    legacy_git
    run "$NIVUUS" migrate --yes --dry-run
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    [ ! -e "$NIVUUS_STATE_DIR/migration" ]
}

@test "migrate hors TTY et sans --yes : explique, n'agit pas" {
    legacy_git
    run "$NIVUUS" migrate < /dev/null
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    [[ "$output" == *"--yes"* ]]
}

@test "update refuse et renvoie vers migrate quand le .git est parasite" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$PREFIX" "$NIVUUS" update
    [ "$status" -ne 0 ]
    [[ "$output" == *"nivuus migrate"* ]]
}

@test "doctor signale le .git parasite sans y toucher" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$PREFIX" "$NIVUUS" doctor
    [[ "$output" == *"migrate"* ]]
    [ -d "$PREFIX/.git" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_manifest_move_aside.bats tests/e2e/test_migrate_git.bats`
Expected: FAIL — `nivuus_move_aside` n'existe pas ; `nivuus migrate` renvoie « Sous-commande
inconnue : migrate » (code 2) ; `nivuus update` délègue aveuglément à `zsh -ic nivuus-update`,
qui affiche aujourd'hui le message trompeur « Development checkout detected ».

- [ ] **Step 3: Write minimal implementation**

Dans `lib/manifest.sh` — c'est la **seule** bibliothèque autorisée à écrire, la primitive va donc
ici et pas dans `lib/migrate.sh` :

```sh
# Déplace $1 vers $2 sans jamais écraser. Utilisé par la migration du
# dépôt git parasite : on ne supprime pas, on met de côté, et on dit où.
# Volontairement absent du manifeste : ce déplacement n'est pas une
# mutation d'installation, et un uninstall ne doit surtout pas
# « restaurer » le .git qui était précisément le problème.
nivuus_move_aside() {
    local src="$1" dst="$2"
    [ -e "$src" ] || { log_error "Rien à déplacer : $src"; return 1; }
    [ -e "$dst" ] && { log_error "Destination déjà existante : $dst"; return 1; }
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "déplacerait $src vers $dst"
        printf '%s\n' "$dst"
        return 0
    fi
    nivuus_mkdir_p "$(dirname "$dst")" || return 1
    mv "$src" "$dst" || return 1
    printf '%s\n' "$dst"
}
```

Dans `bin/nivuus` — sourcer la bibliothèque, ajouter la sous-commande, poser la garde :

```sh
. "$NIVUUS_SRC_ROOT/lib/migrate.sh"
```

```sh
cmd_migrate() {
    local dir state dst
    dir="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) export NIVUUS_DRY_RUN=1 ;;
            --yes|-y)  ASSUME_YES=1 ;;
            --prefix)
                shift
                [ $# -gt 0 ] || { log_error "L'option --prefix attend un chemin."; return 2; }
                dir="$1" ;;
            *) log_error "Option inconnue : $1"; return 2 ;;
        esac
        shift
    done
    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"

    state="$(nivuus_git_state "$dir")"
    case "$state" in
        none) log_ok "Rien à migrer : aucun dépôt git dans $dir."; return 0 ;;
        dev)
            log_info "Rien à migrer : $dir/.git est un dépôt de travail, pas le dépôt créé par l'ancien installeur."
            nivuus_git_report "$dir"
            log_info "Nivuus n'y touchera pas. Si tu développes ici, utilise « git pull » plutôt que la mise à jour par release."
            return 0 ;;
        unknown)
            log_warn "Un dépôt git existe dans $dir mais git n'est pas disponible : impossible de décider."
            log_warn "Installe git puis relance « nivuus migrate »."
            return 0 ;;
    esac

    log_warn "$dir contient le dépôt git que l'installeur de la v3.0.0 créait."
    log_warn "C'est lui qui désactive silencieusement tes mises à jour : l'updater le prend"
    log_warn "pour un checkout de développement et refuse d'écraser ton travail."
    nivuus_git_report "$dir"
    log_info "La migration le DÉPLACE (elle ne le supprime pas) sous $NIVUUS_STATE_DIR/migration/."

    if [ -z "${ASSUME_YES:-}" ] && ! nivuus_is_tty; then
        log_info "Aucun terminal pour confirmer : relance avec « nivuus migrate --yes »."
        return 0
    fi
    confirm "Déplacer $dir/.git maintenant ?" || { log_info "Annulé. Rien n'a été touché."; return 0; }

    dst="$NIVUUS_STATE_DIR/migration/$(date +%Y%m%d-%H%M%S)/git"
    dst="$(nivuus_move_aside "$dir/.git" "$dst")" || { log_error "Migration impossible."; return 1; }
    log_ok "Dépôt déplacé : $dst"
    log_info "Pour revenir en arrière : mv \"$dst\" \"$dir/.git\""
    log_info "Tes mises à jour automatiques sont réactivées."
}
```

Garde dans `cmd_update`, **avant** de déléguer à zsh :

```sh
cmd_update() {
    local dir state
    dir="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}"
    state="$(nivuus_git_state "$dir")"
    if [ "$state" = "legacy" ]; then
        log_error "Les mises à jour sont bloquées par le dépôt git que l'ancien installeur a laissé dans $dir."
        log_error "Lance « nivuus migrate » pour le mettre de côté, puis relance « nivuus update »."
        return 1
    fi
    exec zsh -ic 'nivuus-update'
}
```

…et le branchement `migrate) cmd_migrate "$@" ;;` dans `main`, plus les deux lignes correspondantes
dans `usage()` (`nivuus migrate [--dry-run] [--yes]`).

Dans `bin/healthcheck`, un bloc en lecture seule, à placer près des autres contrôles
d'installation :

```bash
if [ -f "$NIVUUS_SHELL_DIR/../lib/migrate.sh" ] || [ -f "$NIVUUS_SHELL_DIR/lib/migrate.sh" ]; then
    . "$NIVUUS_SHELL_DIR/lib/migrate.sh" 2>/dev/null || true
    if command -v nivuus_git_state >/dev/null 2>&1 \
       && [ "$(nivuus_git_state "$NIVUUS_SHELL_DIR")" = "legacy" ]; then
        echo -e "${WARN} Dépôt git hérité de la v3.0.0 dans $NIVUUS_SHELL_DIR"
        echo "  Tes mises à jour automatiques sont désactivées à cause de lui."
        echo "  Correction : nivuus migrate"
    fi
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_manifest_move_aside.bats tests/unit/test_lib_migrate.bats tests/e2e/test_migrate_git.bats tests/e2e/test_nivuus_cli.bats tests/e2e/test_reversibility.bats`
Expected: PASS. `test_nivuus_cli.bats` valide que la nouvelle sous-commande est listée par `usage()`
et que les sous-commandes inconnues sortent toujours en 2 ; `test_reversibility.bats` est là parce
que `lib/manifest.sh` a été modifiée.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh bin/nivuus bin/healthcheck \
        tests/unit/test_manifest_move_aside.bats tests/e2e/test_migrate_git.bats
git commit -m "feat(migrate): nivuus migrate moves the legacy git repo aside and unblocks updates"
```

---

### Task 8: Le message honnête dans l'auto-update

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Create: `tests/unit/test_autoupdate_legacy_hint.bats`

**Interfaces:**
- Consumes : `lib/migrate.sh` (`nivuus_git_state`), sourcée **paresseusement**, uniquement dans `nivuus-update`.
- Produces : dans `nivuus-update`, le message « checkout de développement » est remplacé par le bon diagnostic quand l'état est `legacy`.

**Ce qui change, et ce qui ne change surtout pas.** `_nivuus_is_dev_checkout` continue de bloquer
l'auto-update **au démarrage** et le chemin asynchrone reste strictement inchangé : une session de
shell ne doit jamais déplacer un `.git` toute seule, ni poser de question. Le seul changement est
le texte affiché quand l'utilisateur tape `nivuus-update` **à la main** : aujourd'hui il lit
« Development checkout detected — use git pull here », un conseil faux pour lui, qui lui fait
croire que son installation est un checkout et l'envoie dans une impasse. Demain il lit ce qui se
passe réellement et la commande qui le débloque.

**Coût au démarrage : zéro.** `lib/migrate.sh` n'est sourcée qu'à l'intérieur de la fonction
`nivuus-update`, jamais au chargement du module. Le test le vérifie.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_legacy_hint.bats
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

    DIR="$TMP/install"; mkdir -p "$DIR/lib" "$DIR/config"
    cp "$ROOT/lib/log.sh" "$ROOT/lib/migrate.sh" "$DIR/lib/"
    printf '9.9.9\n' > "$DIR/.version"
    printf 'contenu\n' > "$DIR/config/00-core.zsh"
}

teardown() { rm -rf "$TMP"; }

legacy_git() {
    ( cd "$DIR"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

update() {
    run env ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$DIR" HOME="$HOME" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; nivuus-update" < /dev/null
}

@test "dépôt parasite : le message nomme nivuus migrate" {
    legacy_git
    update
    [[ "$output" == *"nivuus migrate"* ]]
    [[ "$output" != *"git pull"* ]]
}

@test "dépôt parasite : nivuus-update ne le déplace PAS tout seul" {
    legacy_git
    update
    [ -d "$DIR/.git" ]
}

@test "vrai checkout de développement : le message « git pull » est conservé" {
    legacy_git
    ( cd "$DIR" && printf 'wip\n' > wip && git add wip && git commit -q -m "mon travail" ) >/dev/null
    update
    [[ "$output" == *"git pull"* ]]
    [[ "$output" != *"nivuus migrate"* ]]
}

@test "aucun .git : le chemin de mise à jour normal n'est pas modifié" {
    update
    [[ "$output" != *"nivuus migrate"* ]]
    [[ "$output" != *"Development checkout"* ]]
}

@test "lib/migrate.sh n'est PAS sourcée au chargement du module" {
    # Le module doit se charger sans lib/migrate.sh sur le disque : la
    # dépendance est paresseuse, donc le budget de démarrage est intact.
    rm -f "$DIR/lib/migrate.sh"
    run env ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$DIR" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; echo CHARGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHARGE"* ]]
}

@test "le chemin asynchrone ne parle jamais de migration" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$DIR" HOME="$HOME" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_check_update_async; wait" < /dev/null
    [[ "$output" != *"nivuus migrate"* ]]
    [ -d "$DIR/.git" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_legacy_hint.bats`
Expected: FAIL — `nivuus-update` affiche « Development checkout detected » dans tous les cas ; les
tests 1 et 3 échouent tous les deux, ce qui est le point : le message actuel ne distingue pas les
deux situations.

- [ ] **Step 3: Write minimal implementation**

Dans `config/20-autoupdate.zsh`, remplacer **uniquement** le bloc d'entrée de `nivuus-update` :

```zsh
nivuus-update() {
    # Never run the destructive release updater on a git checkout.
    if _nivuus_is_dev_checkout; then
        # Deux situations très différentes derrière un même .git, et le
        # message générique envoyait la mauvaise dans une impasse : le
        # dépôt que l'installeur de la v3.0.0 créait ici n'est PAS un
        # checkout de développement, et « git pull » n'y donne rien
        # d'utile. lib/migrate.sh sait les distinguer ; on ne la source
        # qu'ici, jamais au démarrage.
        local _nivuus_git_kind=""
        if [[ -r "$NIVUUS_SHELL_DIR/lib/migrate.sh" ]]; then
            source "$NIVUUS_SHELL_DIR/lib/migrate.sh" 2>/dev/null
            _nivuus_git_kind="$(nivuus_git_state "$NIVUUS_SHELL_DIR" 2>/dev/null)"
        fi
        if [[ "$_nivuus_git_kind" == "legacy" ]]; then
            echo "⚠️  Un dépôt git hérité de la v3.0.0 se trouve dans $NIVUUS_SHELL_DIR."
            echo "   C'est lui qui bloque tes mises à jour depuis l'installation."
            echo "   Lance « nivuus migrate » pour le mettre de côté (il est déplacé,"
            echo "   pas supprimé), puis relance « nivuus-update »."
        else
            echo "ℹ️  Development checkout detected at $NIVUUS_SHELL_DIR"
            echo "   Use 'git pull' here instead of the release updater."
        fi
        return 0
    fi
    …
```

Ne rien changer d'autre : ni `_nivuus_is_dev_checkout`, ni la garde de démarrage, ni
`_nivuus_check_update_async`.

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_legacy_hint.bats tests/unit/test_autoupdate_*.bats tests/e2e/test_update_signature.bats`
Expected: PASS. Les suites de signature sont incluses parce que cette tâche touche le même fichier
qu'elles — c'est le point de contact le plus chaud du plan.

- [ ] **Step 5: Commit**

```bash
git add config/20-autoupdate.zsh tests/unit/test_autoupdate_legacy_hint.bats
git commit -m "fix(autoupdate): tell legacy installs what actually blocks their updates"
```

---

### Task 9: Compatibilité ascendante — v3.0.0 en place, HEAD par-dessus, tout fonctionne

**Files:**
- Create: `tests/helpers/legacy.bash`
- Create: `tests/e2e/test_upgrade_from_v3.bats`
- Modify: `lib/zshrc.sh` (reconnaissance de la strophe v3.0.0)
- Test: `tests/unit/test_lib_zshrc.bats` (existant, à étendre)

**Interfaces:**
- Produces :
  - `legacy_install <home> <prefix> <repo_root>` — recrée, depuis le tag `v3.0.0`, l'état exact qu'une installation v3.0.0 laissait : arbre, `.version`, `~/.zshrc` sans marqueurs, `~/.zsh_local`, horodatage de dernière vérification, et le dépôt git de `init_git_repo()`.
  - `nivuus_zshrc_legacy_present <fichier>` / `nivuus_zshrc_strip_legacy <fichier>` (`lib/zshrc.sh`) — reconnaissent et retirent la strophe v3.0.0, et **elle seule**.
- Consumes : le tag `v3.0.0` du dépôt (`git archive`).

**Comment on fabrique « l'ancienne installation » de façon reproductible.** Pas de blob vendu dans
`tests/`, pas de capture d'écran d'un `$HOME` : le dépôt contient déjà la v3.0.0, sous forme de tag.
`git archive v3.0.0 | tar -x` produit l'arbre exact, et les trois effets de bord que l'ancien
installeur ajoutait sont reproduits ligne par ligne depuis `git show v3.0.0:install.sh`
(`.zshrc` : lignes 257-261 ; `.zsh_local` : lignes 284+ ; `.git` : lignes 334-346), avec la
référence en commentaire. Si l'ancien installeur est un jour relu et que la reproduction diverge,
la référence dit où vérifier.

Le tag est donc une **dépendance du test**. Un runner en `fetch-depth: 1` sans tags le rend
impossible : le helper échoue avec un message qui le dit, plutôt que de `skip` en silence — un
`skip` transformerait le test exigé par la section 7 du spec en décoration. Point de contact avec
le plan CI (`fetch-tags: true`), noté en fin de document.

**Le bug que ce test met au jour.** `nivuus_zshrc_state` classe le `.zshrc` de v3.0.0 `absent`
(aucun marqueur), donc `nivuus_zshrc_merge` **ajoute** le bloc sans retirer la strophe : après une
installation de HEAD par-dessus v3.0.0, `~/.zshrc` source Nivuus **deux fois**. Ce n'est pas une
hypothèse — c'est la lecture directe de `lib/zshrc.sh:52` et de `git show v3.0.0:install.sh:257`.
Le test le constate, la correction le résout.

**La reconnaissance de la strophe est volontairement étroite.** Trois formes de ligne exactes, et
seulement si le commentaire d'en-tête `# Nivuus Shell Configuration` est présent **et** qu'aucun
bloc délimité ne l'est. Un `.zshrc` qui contiendrait par coïncidence
`source "$NIVUUS_SHELL_DIR/.zshrc"` écrit à la main par l'utilisateur n'est pas touché tant que
l'en-tête manque. La restauration reste exacte : l'écriture passe par `nivuus_write_file`, donc par
une entrée `MODIFY` avec sauvegarde, donc `uninstall` remet le fichier d'origine à l'octet près.

- [ ] **Step 1: Write the failing test**

```bash
# Ajouts à tests/unit/test_lib_zshrc.bats

@test "la strophe v3.0.0 est reconnue" {
    cat > "$TMP/zshrc" <<'EOS'
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/home/u/.nivuus-shell"
source "$NIVUUS_SHELL_DIR/.zshrc"
EOS
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -eq 0 ]
}

@test "un .zshrc quelconque n'est PAS pris pour la strophe v3.0.0" {
    printf 'alias ll="ls -la"\nexport EDITOR=vim\n' > "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "sans l'en-tête, la strophe n'est pas reconnue" {
    printf 'export NIVUUS_SHELL_DIR="/x"\nsource "$NIVUUS_SHELL_DIR/.zshrc"\n' > "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "un .zshrc déjà géré par bloc n'est pas traité comme legacy" {
    nivuus_zshrc_block "/x" > "$TMP/zshrc"
    printf '# Nivuus Shell Configuration\n' >> "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "strip_legacy retire les trois lignes et RIEN d'autre" {
    cat > "$TMP/zshrc" <<'EOS'
# mes réglages
export EDITOR=vim
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/home/u/.nivuus-shell"
source "$NIVUUS_SHELL_DIR/.zshrc"
alias ll="ls -la"
EOS
    run nivuus_zshrc_strip_legacy "$TMP/zshrc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export EDITOR=vim"* ]]
    [[ "$output" == *'alias ll="ls -la"'* ]]
    [[ "$output" == *"# mes réglages"* ]]
    [[ "$output" != *"NIVUUS_SHELL_DIR"* ]]
    [[ "$output" != *"Nivuus Shell Configuration"* ]]
}

@test "merge sur un .zshrc v3.0.0 ne produit qu'UNE source de Nivuus" {
    cat > "$TMP/zshrc" <<'EOS'
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/ancien"
source "$NIVUUS_SHELL_DIR/.zshrc"
EOS
    run nivuus_zshrc_merge "$TMP/zshrc" "/nouveau" ""
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'NIVUUS_SHELL_DIR/.zshrc')" -eq 1 ]
    [[ "$output" == *"/nouveau"* ]]
    [[ "$output" != *"/ancien"* ]]
}
```

```bash
# tests/e2e/test_upgrade_from_v3.bats
#!/usr/bin/env bats
#
# Le test que la section 7 « Risques » du spec exige nommément :
# « installation v3.0.0 en place -> nouvelle installation par-dessus ->
# tout fonctionne », complété par la désinstallation propre.

load '../helpers/fingerprint'
load '../helpers/legacy'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    PREFIX="$HOME/.nivuus-shell"
    legacy_install "$HOME" "$PREFIX" "$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "l'état de départ est bien celui de la v3.0.0" {
    [ -d "$PREFIX/.git" ]
    [ "$(cat "$PREFIX/.version")" = "3.0.0" ]
    run cat "$HOME/.zshrc"
    [[ "$output" == *"# Nivuus Shell Configuration"* ]]
    [[ "$output" != *">>> nivuus shell >>>"* ]]
    run bash -c ". '$ROOT/lib/log.sh'; . '$ROOT/lib/migrate.sh'; nivuus_git_state '$PREFIX'"
    [ "$output" = "legacy" ]
}

@test "installer HEAD par-dessus v3.0.0 réussit" {
    run "$NIVUUS" install --yes --prefix "$PREFIX"
    [ "$status" -eq 0 ]
    [ -f "$PREFIX/bin/nivuus" ]
    [ -f "$PREFIX/lib/manifest.sh" ]
}

@test "INVARIANT: après la mise à jour, ~/.zshrc ne source Nivuus qu'UNE fois" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run grep -c 'NIVUUS_SHELL_DIR/.zshrc' "$HOME/.zshrc"
    [ "$output" = "1" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "après la mise à jour, le shell démarre et charge Nivuus" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run env HOME="$HOME" zsh -ic 'echo VERSION=$NIVUUS_SHELL_DIR'
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PREFIX"* ]]
}

@test "après la mise à jour, migrate débloque les mises à jour" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    [ -d "$PREFIX/.git" ]            # l'installation ne migre pas d'elle-même
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/.git" ]
}

@test "INVARIANT: migrate puis install puis uninstall rend le HOME de départ" {
    # L'empreinte est prise APRÈS migrate : le déplacement du .git est
    # justement le changement voulu, et il n'a pas à être défait par la
    # désinstallation.
    "$NIVUUS" migrate --yes >/dev/null
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    "$NIVUUS" uninstall --yes >/dev/null
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "deux installations successives de HEAD sont idempotentes" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    fs_fingerprint "$HOME" > "$TMP/une"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    fs_fingerprint "$HOME" > "$TMP/deux"
    run diff "$TMP/une" "$TMP/deux"
    [ "$status" -eq 0 ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "les personnalisations de l'utilisateur survivent à la mise à jour" {
    printf 'export MA_VARIABLE=42\n' >> "$HOME/.zsh_local"
    printf '\nalias mien="echo mien"\n' >> "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run grep -q 'MA_VARIABLE=42' "$HOME/.zsh_local"
    [ "$status" -eq 0 ]
    run grep -q 'alias mien' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_zshrc.bats tests/e2e/test_upgrade_from_v3.bats`
Expected: FAIL, avec deux causes distinctes à constater séparément :
1. `tests/helpers/legacy.bash` n'existe pas — tous les tests e2e échouent au `load`.
2. Une fois le helper écrit (étape 3, première moitié), le test « ne source Nivuus qu'UNE fois »
   échoue avec `2` : c'est **le** bug de compatibilité ascendante, constaté et non supposé.
   Le noter dans le message de commit.

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/helpers/legacy.bash
# Reproduit, depuis le dépôt lui-même, l'état qu'une installation v3.0.0
# laissait dans $HOME. Aucun binaire vendu dans tests/ : l'arbre vient du
# tag v3.0.0, et les effets de bord de l'ancien installeur sont recopiés
# depuis `git show v3.0.0:install.sh` -- références de lignes en commentaire
# pour que la reproduction reste vérifiable.

legacy_install() {
    local home="$1" prefix="$2" root="$3"

    if ! git -C "$root" rev-parse -q --verify refs/tags/v3.0.0 >/dev/null 2>&1; then
        printf '%s\n' "Le tag v3.0.0 est requis par ce test (git fetch --tags ; en CI : fetch-tags)." >&2
        return 1
    fi

    mkdir -p "$prefix" "$home"
    git -C "$root" archive --format=tar v3.0.0 | tar -x -C "$prefix"
    # install.sh:270 -- « Created version file »
    printf '3.0.0\n' > "$prefix/.version"

    # install.sh:257-261 -- « cat > $HOME/.zshrc », sans le moindre marqueur.
    cat > "$home/.zshrc" <<EOS
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="$prefix"
source "\$NIVUUS_SHELL_DIR/.zshrc"
EOS

    # install.sh:284+ -- « create_local_config », créé s'il n'existe pas.
    if [ ! -f "$home/.zsh_local" ]; then
        cat > "$home/.zsh_local" <<'EOS'
# Nivuus Shell - Local Configuration
# This file is for your personal customizations
EOS
    fi

    # install.sh:334-346 -- « init_git_repo », la cause du problème n° 8 du spec.
    ( cd "$prefix"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1

    # install.sh:419 -- horodatage de dernière vérification.
    date +%s > "$home/.nivuus-shell-last-update-check"
}
```

Dans `lib/zshrc.sh` :

```sh
# La v3.0.0 écrivait dans ~/.zshrc trois lignes sans le moindre marqueur
# (git show v3.0.0:install.sh, lignes 257-261). nivuus_zshrc_state les
# classe donc « absent », et une installation de HEAD par-dessus AJOUTERAIT
# son bloc sans les retirer : le .zshrc sourcerait Nivuus deux fois.
#
# La reconnaissance est volontairement étroite -- en-tête exact, aucun bloc
# délimité présent, et trois formes de ligne précises. Un .zshrc écrit à la
# main qui contiendrait par hasard l'une de ces lignes n'est pas touché tant
# que l'en-tête manque.
NIVUUS_LEGACY_HEADER='# Nivuus Shell Configuration'

nivuus_zshrc_legacy_present() {
    local file="$1"
    [ -f "$file" ] || return 1
    [ "$(nivuus_zshrc_state "$file")" = "absent" ] || return 1
    grep -qxF "$NIVUUS_LEGACY_HEADER" "$file" || return 1
    grep -q '^export NIVUUS_SHELL_DIR=' "$file" || return 1
    grep -qF 'source "$NIVUUS_SHELL_DIR/.zshrc"' "$file" || return 1
    return 0
}

nivuus_zshrc_strip_legacy() {
    local file="$1"
    [ -f "$file" ] || return 0
    # Même précaution CRLF que nivuus_zshrc_strip : un .zshrc réenregistré
    # depuis Windows (WSL) ne doit pas échapper au retrait.
    awk -v h="$NIVUUS_LEGACY_HEADER" '
        { line = $0; sub(/\r$/, "", line) }
        line == h { next }
        line ~ /^export NIVUUS_SHELL_DIR=/ { next }
        line == "source \"$NIVUUS_SHELL_DIR/.zshrc\"" { next }
        { print }
    ' "$file"
}
```

…et, dans `nivuus_zshrc_merge`, avant la fusion normale du cas `absent` :

```sh
        absent)
            if nivuus_zshrc_legacy_present "$file"; then
                log_info "Configuration héritée de la v3.0.0 détectée dans $file : elle est remplacée par le bloc délimité."
                { nivuus_zshrc_strip_legacy "$file"; nivuus_zshrc_block "$install_dir" "$minimal"; }
                return 0
            fi
            …
```

> **Ne pas** appeler `nivuus_zshrc_strip_legacy` depuis `nivuus_zshrc_strip` : ce dernier sert à la
> **désinstallation**, et retirer la strophe v3.0.0 au moment de désinstaller HEAD reviendrait à
> supprimer une configuration que HEAD n'a jamais écrite. La restauration exacte est déjà assurée
> par la sauvegarde `MODIFY` — c'est ce que vérifie le test d'empreinte de cette tâche.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_lib_zshrc.bats tests/e2e/test_upgrade_from_v3.bats tests/e2e/test_reversibility.bats`
Expected: PASS. Le test d'empreinte de réversibilité est inclus parce que `lib/zshrc.sh` change,
et c'est lui qui garantit qu'un chemin de fusion supplémentaire n'a pas ouvert une fuite.

- [ ] **Step 5: Commit**

```bash
git add tests/helpers/legacy.bash tests/e2e/test_upgrade_from_v3.bats \
        tests/unit/test_lib_zshrc.bats lib/zshrc.sh
git commit -m "fix(zshrc): stop double-sourcing when installing over a v3.0.0 install"
```

---

### Task 10: E2E — `curl | sh` depuis zéro, puis désinstallation sans trace

**Files:**
- Create: `tests/e2e/test_bootstrap.bats`

**Interfaces:**
- Consumes : `tests/helpers/release.bash` (Task 1), `tests/helpers/fingerprint.bash` (existant — **on le réutilise, on n'en écrit pas un second**), `install.sh` en mode amorçage (Task 4).
- Produces : la preuve de bout en bout de la sortie de phase — « le one-liner installe et désinstalle proprement depuis zéro sur chaque cible ».

**La forme testée est celle du README, pas une approximation.** On pipe réellement le contenu du
fichier dans `sh` (`cat install.sh | sh -s -- …`), ce qui reproduit `$0 = sh`, une entrée standard
consommée par le script, et l'absence de noyau voisin. Un `sh install.sh` aurait un `$0` fichier et
ne prouverait pas la même chose.

**Ce test est le critère de « fini ».** Il tourne sur chaque cible de la matrice via le workflow de
la phase 4 : c'est là que « depuis zéro sur chaque cible » devient une observation et non une
intention.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_bootstrap.bats
#!/usr/bin/env bats
#
# Le one-liner, en vrai : le script piped dans sh, une release servie par
# file://, et l'exigence de sortie de phase -- installer ET désinstaller
# sans laisser de trace.

load '../helpers/release'
load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"
    make_release "$ROOT" "$TMP/releases" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

# Exactement la forme du README : le script est LU sur stdin par sh.
one_liner() {
    cat "$ROOT/install.sh" | env \
        HOME="$HOME" TMPDIR="$TMPDIR" NIVUUS_STATE_DIR="$NIVUUS_STATE_DIR" \
        NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        NIVUUS_GITHUB_API="$NIVUUS_GITHUB_API" NIVUUS_GITHUB_REPO="$NIVUUS_GITHUB_REPO" \
        sh -s -- "$@"
}

@test "le one-liner installe depuis zéro" {
    run one_liner --non-interactive
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
    [ -f "$HOME/.nivuus-shell/bin/nivuus" ]
    [ -f "$HOME/.zshrc" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "le one-liner sans arguments du tout fonctionne aussi" {
    # Forme littérale du README : « curl … | sh », zéro option. Sans TTY,
    # l'amorçage doit ajouter --yes de lui-même plutôt que de bloquer.
    run one_liner
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
}

@test "le shell démarre après le one-liner" {
    one_liner --non-interactive
    run env HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "INVARIANT: aucun dépôt git derrière le one-liner" {
    one_liner --non-interactive
    [ ! -e "$HOME/.nivuus-shell/.git" ]
    run find "$HOME" -name '.git' -maxdepth 4
    [ -z "$output" ]
}

@test "INVARIANT: aucun temporaire derrière le one-liner" {
    one_liner --non-interactive
    run find "$TMPDIR" -maxdepth 1 -mindepth 1
    [ -z "$output" ]
}

@test "INVARIANT: one-liner puis uninstall --purge laisse HOME bit-identique" {
    fs_fingerprint "$HOME" > "$TMP/before"
    one_liner --non-interactive
    run "$HOME/.nivuus-shell/bin/nivuus" uninstall --yes --purge
    [ "$status" -eq 0 ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "le one-liner désinstalle aussi via install.sh du répertoire extrait" {
    # La désinstallation doit être atteignable sans se souvenir d'un chemin :
    # bin/nivuus est dans le PATH une fois le shell chargé.
    one_liner --non-interactive
    run env HOME="$HOME" zsh -ic 'command -v nivuus'
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "INVARIANT: archive falsifiée -> rien d'installé, HOME intact" {
    fs_fingerprint "$HOME" > "$TMP/before"
    tamper_release "$TMP/releases" 9.9.9
    run one_liner --non-interactive
    [ "$status" -ne 0 ]
    [ ! -e "$HOME/.nivuus-shell" ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "le one-liner honore --dry-run" {
    fs_fingerprint "$HOME" > "$TMP/before"
    run one_liner --non-interactive --dry-run
    [ "$status" -eq 0 ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "le one-liner honore --minimal" {
    run one_liner --non-interactive --minimal
    [ "$status" -eq 0 ]
    run grep -c 'NIVUUS_MINIMAL=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "le one-liner honore --prefix, y compris avec un espace" {
    run one_liner --non-interactive --prefix "$HOME/mon dossier"
    [ "$status" -eq 0 ]
    [ -f "$HOME/mon dossier/config/00-core.zsh" ]
}

@test "le one-liner transmet --verify-key au noyau" {
    # Point de contact avec le chantier « signature » : l'option doit
    # traverser l'amorçage, pas seulement le mode local.
    [ -d "$ROOT/keys" ] || skip "keys/ absent (chantier signature non mergé)"
    run one_liner --non-interactive --verify-key "cafecafecafecafe"
    [ "$status" -ne 0 ]
    [ ! -e "$HOME/.nivuus-shell" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_bootstrap.bats`
Expected: FAIL si l'une des tâches 1 à 4 manque. Si elles sont toutes faites, ce test doit passer
du premier coup — auquel cas **le rendre rouge délibérément** avant de le committer : commenter la
vérification d'empreinte dans `install.sh` et vérifier que « archive falsifiée » devient rouge, puis
la remettre. Un test de bout en bout qui n'a jamais échoué ne prouve rien de ce qu'il prétend.

- [ ] **Step 3: Write minimal implementation**

Aucune implémentation attendue : Tasks 1 à 4 la portent. Si un test échoue ici, la correction va
dans `install.sh` et **pas** dans le test — en particulier, ne pas assouplir l'assertion
« aucun temporaire derrière le one-liner » : un temporaire qui survit est une fuite réelle de
plusieurs dizaines de mégaoctets par tentative.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/`
Expected: PASS, suite e2e complète (les nouveaux fichiers portent le total à environ 145 tests).

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_bootstrap.bats
git commit -m "test(e2e): prove curl | sh installs and uninstalls without a trace"
```

---

### Task 11: La documentation d'installation — et la désinstallation aussi visible

**Files:**
- Create: `doc/INSTALL.md`
- Modify: `README.md`
- Modify: `doc/CLAUDE.md` (section « Installation Testing »)
- Create: `tests/e2e/test_docs_install.bats`

**Interfaces:**
- Produces : `doc/INSTALL.md`, source unique de la procédure d'installation ; `README.md` réduit à
  la porte d'entrée (one-liner + désinstallation + lien) ; un test qui interdit à cette
  documentation de mentir.
- Consumes : `package.json` (`repository.url`, source du nom de dépôt), `bin/nivuus help` (source
  des sous-commandes existantes).

**La règle qui structure ce document.** Chaque commande citée dans la documentation doit exister, et
chaque chose qui existe doit être citée au bon endroit. Le README d'aujourd'hui recommande
`sudo ./install.sh --system` (qui sort en erreur depuis la phase 1, avec une note en dessous qui le
contredit) et un one-liner qui clone dans `/tmp`. Ce n'est pas un défaut de rédaction, c'est un
défaut testable : le test de cette tâche compare la documentation au comportement réel du binaire.

**Ordre de préférence des méthodes, arbitré ici :**

1. **One-liner** — pour tout le monde. Ne demande que `curl` (ou `wget`), `zsh`, `tar` et un outil
   sha256. Ne laisse ni dépôt git ni temporaire.
2. **Archive de release téléchargée à la main, vérifiée à la main, puis `./install.sh`** — pour qui
   refuse par principe de piper du réseau dans un shell. La documentation donne les trois commandes,
   y compris la vérification, parce qu'une méthode « plus sûre » sans étape de vérification serait
   surtout plus longue.
3. **Checkout git + `./install.sh`** — pour le développement, présentée comme telle et pas comme
   une installation. C'est le seul cas où `~/.nivuus-shell` est légitimement un dépôt git.

`--verify-key` est documentée **avec** la méthode 1 et non reléguée en annexe : c'est la seule
réponse au problème d'amorçage, et une réponse cachée n'est pas une réponse.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_docs_install.bats
#!/usr/bin/env bats
#
# Une documentation d'installation qui décrit un comportement que le
# binaire n'a pas est pire que pas de documentation : elle fait perdre du
# temps AVANT la première ligne de code exécutée. Ce test la confronte au
# binaire.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    README="$ROOT/README.md"
    INSTALL_DOC="$ROOT/doc/INSTALL.md"
    REPO="$(sed -n 's#.*github.com/\([^"]*\)\.git.*#\1#p' "$ROOT/package.json" | head -n1)"
}

@test "doc/INSTALL.md existe" {
    [ -f "$INSTALL_DOC" ]
}

@test "le README ne recommande plus un git clone dans /tmp" {
    run grep -n 'clone.*\/tmp' "$README"
    [ "$status" -ne 0 ]
}

@test "le README porte le vrai one-liner, avec le bon dépôt" {
    run grep -F 'raw.githubusercontent.com' "$README"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$REPO"* ]]
    [[ "$output" == *"install.sh"* ]]
}

@test "README et doc/INSTALL.md donnent le MÊME one-liner" {
    a="$(grep -F 'raw.githubusercontent.com' "$README" | head -n1 | tr -d ' ')"
    b="$(grep -F 'raw.githubusercontent.com' "$INSTALL_DOC" | head -n1 | tr -d ' ')"
    [ -n "$a" ]
    [ "$a" = "$b" ]
}

@test "la désinstallation est documentée dans le README, pas seulement en annexe" {
    run grep -n 'nivuus uninstall' "$README"
    [ "$status" -eq 0 ]
}

@test "la désinstallation a son propre titre de section dans le README" {
    run grep -nE '^#{2,3} .*(Uninstall|Désinstall)' "$README"
    [ "$status" -eq 0 ]
}

@test "aucune documentation ne recommande sudo ./install.sh --system" {
    run grep -rn 'sudo ./install.sh --system' "$README" "$INSTALL_DOC" "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
}

@test "toutes les sous-commandes nivuus citées dans doc/INSTALL.md existent" {
    aide="$("$ROOT/bin/nivuus" help)"
    for sub in $(grep -oE '\bnivuus [a-z-]+' "$INSTALL_DOC" | awk '{print $2}' | sort -u); do
        case "$sub" in
            shell) continue ;;   # « nivuus shell » dans une phrase, pas une commande
        esac
        printf '%s\n' "$aide" | grep -qE "nivuus +$sub" || {
            printf 'sous-commande documentée mais absente de « nivuus help » : %s\n' "$sub"
            return 1
        }
    done
}

@test "toutes les plateformes du spec sont couvertes par doc/INSTALL.md" {
    for p in Ubuntu Debian Arch Fedora Alpine macOS WSL; do
        grep -qi "$p" "$INSTALL_DOC" || { printf 'plateforme absente : %s\n' "$p"; return 1; }
    done
}

@test "doc/INSTALL.md est explicite sur ce que le one-liner ne garantit PAS" {
    run grep -niE 'amor|bootstrap|même origine|same origin' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
    run grep -F -- '--verify-key' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "doc/INSTALL.md documente l'installation sans git" {
    run grep -niE 'sans git|no git|git n.est pas' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "la version épinglée d'install.sh est celle de .version" {
    pinned="$(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' "$ROOT/install.sh" | head -n1)"
    [ -n "$pinned" ]
    [ "$pinned" = "$(cat "$ROOT/.version")" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_docs_install.bats`
Expected: FAIL — `doc/INSTALL.md` n'existe pas ; le README contient encore
`git clone … /tmp/nivuus-shell` et `sudo ./install.sh --system` ; aucune section de désinstallation.

- [ ] **Step 3: Write minimal implementation**

`doc/INSTALL.md`, structure imposée par les tests ci-dessus :

```markdown
# Installer Nivuus Shell

## En une ligne (recommandé)

    curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh

Ce que ça fait : télécharge l'archive de la dernière release, **vérifie son empreinte SHA-256**,
l'installe dans `~/.nivuus-shell`, ajoute un bloc délimité à ton `~/.zshrc`, et supprime son
répertoire temporaire. Aucun dépôt git n'est créé, rien n'est installé avec `sudo`.

Sans `curl`, `wget` fait l'affaire :

    wget -qO- https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh

### Ce que le one-liner ne garantit PAS

Le script, l'archive et les sommes de contrôle viennent tous de **la même origine** — GitHub. La
vérification d'empreinte protège d'un transfert corrompu ou d'un cache CDN empoisonné ; elle ne
protège pas d'une origine compromise, qui pourrait remplacer les trois de façon cohérente. C'est le
problème d'amorçage, et il n'a pas de solution interne au one-liner.

La seule réponse est un canal secondaire. Obtiens l'empreinte du jeu de clés de signature ailleurs
que sur GitHub (voir `SECURITY.md`), puis :

    curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh \
      | sh -s -- --verify-key <empreinte>

L'installation est refusée avant la moindre écriture si l'empreinte ne correspond pas.

### Options

    | sh -s -- --dry-run        # n'écrit rien, montre ce qui serait fait
    | sh -s -- --minimal        # serveur / container : pas de chsh, pas d'extras
    | sh -s -- --with-deps      # propose UNE commande groupée pour les outils recommandés
    | sh -s -- --prefix DIR     # installe ailleurs que dans ~/.nivuus-shell

Variables : `NIVUUS_VERSION` fige la version installée.

## Sans piper du réseau dans un shell

    VERSION=$(curl -fsSL https://api.github.com/repos/maximeallanic/nivuus-shell/releases/latest \
              | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
    BASE=https://github.com/maximeallanic/nivuus-shell/releases/download/v$VERSION
    curl -fLO $BASE/nivuus-shell-v$VERSION.tar.gz
    curl -fLO $BASE/SHA256SUMS
    sha256sum --check --ignore-missing SHA256SUMS      # macOS : shasum -a 256 -c
    mkdir nivuus && tar -xzf nivuus-shell-v$VERSION.tar.gz -C nivuus
    ./nivuus/install.sh

## Pour développer

    git clone https://github.com/maximeallanic/nivuus-shell.git
    cd nivuus-shell && ./install.sh

C'est le seul cas où `~/.nivuus-shell` est légitimement un dépôt git — et la mise à jour par
release y est alors désactivée, volontairement (`git pull` la remplace).

## Par plateforme

| Plateforme | Prérequis | Remarque |
|---|---|---|
| Ubuntu / Debian | `apt-get install zsh curl` | rien de plus |
| Fedora | `dnf install zsh curl` | |
| Arch | `pacman -S zsh curl` | |
| Alpine | `apk add zsh curl bash tar` | `bash` est requis par l'installeur, pas par le shell |
| macOS | `brew install zsh` | si zsh vient de brew, `chsh` demande d'ajouter le chemin à `/etc/shells` — la commande exacte est affichée, jamais exécutée |
| WSL | `apt-get install zsh curl` | détecté automatiquement |
| Container / serveur / SSH | idem distribution | `--minimal` est activé tout seul |

`git` **n'est pas requis** : il n'est utilisé que pour le prompt git, qui se désactive proprement
en son absence.

## Désinstaller

    nivuus uninstall              # retire tout ce que Nivuus a écrit, restaure ton .zshrc
    nivuus uninstall --purge      # retire aussi l'état interne (manifeste, sauvegardes)
    nivuus uninstall --dry-run    # montre ce qui serait retiré, sans rien faire

La désinstallation restaure chaque fichier modifié à partir de la sauvegarde enregistrée à
l'installation, à l'octet près. `~/.zsh_local` et `~/.zsh_history` ne sont jamais supprimés.

## Mettre à jour, et le cas des anciennes installations

    nivuus update

Si Nivuus a été installé avant la v3.1 par l'ancien one-liner, un dépôt git a été créé dans
`~/.nivuus-shell` et **bloque toutes les mises à jour** depuis. Pour le débloquer :

    nivuus migrate

Le dépôt est **déplacé** (jamais supprimé) sous `~/.local/state/nivuus/migration/`, et le chemin
est affiché. `nivuus doctor` signale le problème s'il est présent.

## Diagnostic

    nivuus doctor
```

Dans `README.md` : remplacer la section « One-Line Installation » et « Manual Installation » par le
one-liner, trois lignes d'explication, un lien vers `doc/INSTALL.md`, et une section
`### Uninstall` de même niveau que l'installation, avec `nivuus uninstall`. Retirer le bloc
`sudo ./install.sh --system` et sa note contradictoire.

Dans `doc/CLAUDE.md`, section « Installation Testing » : remplacer
`sudo ./install.sh --system --non-interactive` par le mode d'amorçage hors réseau, qui est ce qu'un
agent a réellement besoin de savoir lancer :

```bash
# Amorçage hors réseau (ce que fait le one-liner, sans réseau)
NIVUUS_VERSION=9.9.9 NIVUUS_RELEASE_BASE_URL="file:///chemin/vers/releases" \
  sh install.sh --non-interactive --prefix /tmp/essai
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/e2e/test_docs_install.bats`
Expected: PASS (12 tests). Le dernier (« version épinglée = `.version` ») passe tant que
`NIVUUS_PINNED_VERSION` vaut `3.0.0` et que `.version` aussi ; c'est Task 12 qui garantit qu'ils ne
divergeront pas à la prochaine release.

- [ ] **Step 5: Commit**

```bash
git add doc/INSTALL.md README.md doc/CLAUDE.md tests/e2e/test_docs_install.bats
git commit -m "docs(install): document the real one-liner, every platform, and uninstalling"
```

---

### Task 12: `release.yml` — la version épinglée cesse de diverger

> **Rebaser avant cette tâche, et la faire en dernier.** `.github/workflows/release.yml` est touché
> par le plan de signature (job de signature, Task 12 de son plan) et par le plan CI (le job `test`
> devient `uses: ./.github/workflows/matrix.yml`, Task 12 du sien). Cette tâche-ci n'y fait qu'une
> modification délimitée : ne rien toucher d'autre.

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `tests/unit/test_release_workflow_version.bats`

**Interfaces:**
- Produces : une étape de release qui écrit la nouvelle version dans `.version`, `package.json`
  **et** `NIVUUS_PINNED_VERSION` d'`install.sh`, puis échoue si l'un des trois diverge.

**Ce qu'on répare exactement.** L'étape « Update version in install.sh » fait aujourd'hui
`sed -i 's/^VERSION=.*/VERSION="…"/' install.sh` suivi de `grep '^VERSION=' install.sh`. La
variable `VERSION=` a disparu d'`install.sh` avec la phase 1 : le `sed` ne remplace rien, le `grep`
sort en 1, et l'étape échoue — sous `bash -e`, le job entier avec. C'est aussi pour cela qu'aucune
release n'a été publiée depuis. On la branche sur `NIVUUS_PINNED_VERSION`, et on ajoute la
vérification croisée qui manquait.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_release_workflow_version.bats
#!/usr/bin/env bats
#
# Le workflow de release est du YAML, pas du shell : on ne peut pas
# l'exécuter ici. On peut en revanche interdire mécaniquement les deux
# défauts qui l'ont cassé -- viser une variable qui n'existe pas, et ne
# jamais vérifier que les trois sources de version coïncident.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    WF="$ROOT/.github/workflows/release.yml"
}

@test "le workflow ne vise plus la variable VERSION= disparue d'install.sh" {
    run grep -n 's/\^VERSION=' "$WF"
    [ "$status" -ne 0 ]
}

@test "le workflow met à jour NIVUUS_PINNED_VERSION" {
    run grep -F 'NIVUUS_PINNED_VERSION' "$WF"
    [ "$status" -eq 0 ]
}

@test "le workflow met à jour .version" {
    run grep -nE '>[[:space:]]*\.version|\.version' "$WF"
    [ "$status" -eq 0 ]
}

@test "install.sh contient bien la variable que le workflow modifie" {
    run grep -nE '^NIVUUS_PINNED_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "les trois sources de version coïncident dans le dépôt" {
    v_file="$(cat "$ROOT/.version")"
    v_pkg="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/package.json" | head -n1)"
    v_sh="$(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' "$ROOT/install.sh" | head -n1)"
    [ "$v_file" = "$v_pkg" ]
    [ "$v_file" = "$v_sh" ]
}

@test "les notes de release donnent le vrai one-liner" {
    run grep -F 'raw.githubusercontent.com' "$WF"
    [ "$status" -eq 0 ]
    run grep -F '| bash' "$WF"
    [ "$status" -ne 0 ]     # le one-liner s'exécute avec sh, pas bash
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_release_workflow_version.bats`
Expected: FAIL — `s/^VERSION=` est présent, `NIVUUS_PINNED_VERSION` absent, et les notes de release
utilisent `| bash`.

- [ ] **Step 3: Write minimal implementation**

Remplacer l'étape « Update version in install.sh » par :

```yaml
      - name: Synchronise version across .version, package.json and install.sh
        run: |
          V="${{ steps.version.outputs.version }}"
          printf '%s\n' "$V" > .version
          sed -i 's/"version": ".*"/"version": "'"$V"'"/' package.json
          # Plancher de version du script d'amorçage : il ne sert que quand
          # l'API GitHub est injoignable, mais s'il diverge il envoie les
          # nouvelles installations sur une release périmée.
          sed -i 's/^NIVUUS_PINNED_VERSION=".*"/NIVUUS_PINNED_VERSION="'"$V"'"/' install.sh

          # Vérification croisée : c'est elle qui manquait, et c'est elle qui
          # aurait signalé que le sed précédent ne remplaçait plus rien.
          test "$(cat .version)" = "$V"
          test "$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' package.json | head -n1)" = "$V"
          test "$(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' install.sh | head -n1)" = "$V"
          echo "Version synchronisée : $V"
```

Adapter l'étape « Commit version updates » pour inclure `.version` :
`git add package.json install.sh .version`.

Et, dans « Generate changelog », remplacer le bloc d'installation par le vrai one-liner :

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

> `sed -i` est acceptable **ici** et nulle part ailleurs : ce script tourne exclusivement sur
> `ubuntu-latest`, jamais sur macOS ni Alpine. L'interdiction du `sed -i` porte sur `lib/`, `bin/`
> et `tests/` (contrainte de la phase 3), pas sur un job de release mono-plateforme.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_release_workflow_version.bats tests/e2e/test_docs_install.bats`
Expected: PASS. Vérifier en plus avec `actionlint .github/workflows/release.yml` si l'outil est
disponible (le plan CI l'introduit).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml tests/unit/test_release_workflow_version.bats
git commit -m "ci(release): keep the bootstrap pinned version in sync with .version"
```

---

## Vérification finale de la phase

En local, sur un checkout propre (`git clean -xdf` d'abord — les `.zwc` locaux masquent des échecs
réels, voir le problème n° 10 du spec) :

```bash
rm -f config/*.zwc
bats tests/unit/ tests/integration/ tests/e2e/

# Le one-liner, dans sa forme littérale, sur une release locale
bats tests/e2e/test_bootstrap.bats

# Le test exigé par la section 7 « Risques »
git fetch --tags && bats tests/e2e/test_upgrade_from_v3.bats

# Réversibilité : le critère de « fini »
bats tests/e2e/test_reversibility.bats

# Portabilité du script d'amorçage
dash -n install.sh && busybox ash -n install.sh
```

Contrôles mécaniques :

```bash
# init_git_repo n'existe nulle part dans le code (docs exceptées)
grep -rn "init_git_repo" --include='*.sh' --include='*.zsh' bin/ lib/ config/ install.sh
# -> aucun résultat

# install.sh est POSIX : aucun bashisme
grep -nE 'BASH_SOURCE|\blocal\b|\[\[|\+=|<<<|pipefail' install.sh
# -> aucun résultat

# Aucune mutation hors lib/manifest.sh
grep -nE '^\s*(mv|rm|cp|mkdir|chmod) ' lib/migrate.sh lib/steps.sh lib/zshrc.sh lib/detect.sh
# -> aucun résultat

# Aucun sudo implicite
grep -rn 'sudo ' install.sh bin/nivuus lib/ | grep -v 'nivuus_sudo_prefix\|log_warn\|log_info\|printf'
# -> aucun résultat

# Les trois sources de version coïncident
diff <(cat .version) <(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' install.sh)
```

Critères de sortie de phase, tels que le spec les pose :

1. **Le one-liner installe depuis zéro sur chaque cible** — `tests/e2e/test_bootstrap.bats` vert sur
   Ubuntu 22.04 et 24.04, Debian 12, Arch, Fedora 41, Alpine, macOS et le WSL simulé, via la matrice
   de la phase 4.
2. **Le one-liner désinstalle proprement sur chaque cible** — le test d'empreinte
   `one-liner puis uninstall --purge laisse HOME bit-identique` fait partie du workflow
   `uninstall-verified.yml`, donc du badge.
3. **Aucun dépôt git, aucun temporaire** laissés derrière, prouvés par assertion et pas par lecture.
4. **`init_git_repo` n'a plus d'existence**, et sa séquelle est migrable : `nivuus migrate` déplace
   le dépôt parasite, `nivuus update` et `nivuus doctor` le signalent, et un vrai dépôt de
   développement n'est jamais touché (invariant testé).
5. **Le test de compatibilité ascendante exigé par la section 7 est vert** : v3.0.0 en place →
   installation de HEAD par-dessus → un seul `source` dans `.zshrc`, shell fonctionnel →
   désinstallation qui rend le `$HOME` de départ à l'octet près.
6. **`git` n'est plus requis**, prouvé en retirant `git` du `PATH`, pas en le supposant.
7. **La documentation d'installation est vérifiée par un test**, et la désinstallation y est aussi
   visible que l'installation.

Et, sur GitHub, une fois la phase mergée :

```bash
gh workflow run Release -f bump_type=minor      # première release contenant bin/nivuus
gh run watch --exit-status
# puis, sur une machine vierge, la vraie chose :
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

> **Ordre de publication.** Tant qu'aucune release ne contient `bin/nivuus`, l'amorçage résout
> `v3.0.0`, dont l'archive n'a pas de noyau : il échoue avec le message explicite prévu en Task 4.
> Le one-liner n'est donc **annonçable** qu'après la première release publiée depuis cette phase.
> Task 11 peut être mergée avant (la documentation décrit l'état cible et le test ne dépend pas
> d'une release réelle), mais l'annonce publique attend la release. C'est le seul enchaînement du
> plan qui dépend d'un événement extérieur au dépôt.

---

## Points de contact

Aucun de ces fichiers n'appartient à ce plan ; chacun est touché en un point délimité.

- **`config/20-autoupdate.zsh`** — possédé par le plan de signature, qui y a ajouté
  `_nivuus_verify_signature`, `_nivuus_verify_release`, `_nivuus_sha256_of` et
  `NIVUUS_RELEASE_BASE_URL`. Task 8 n'y modifie **que** le bloc d'entrée de `nivuus-update` (le
  message « Development checkout detected ») et n'ajoute **aucun** appel au démarrage. Rebaser
  avant, et relancer `tests/unit/test_autoupdate_*.bats` et `tests/e2e/test_update_signature.bats`
  après : c'est le point de contact le plus chaud du plan.
- **`install.sh`** — le plan de signature y a ajouté `--verify-key` (sa Task 10). La réécriture
  POSIX de Task 2 doit la **porter**, pas la perdre ; `tests/e2e/test_verify_key.bats` contient
  l'assertion « install.sh forwards --verify-key », qui est le filet exact.
- **`bin/nivuus`** — le plan de signature y a ajouté le sourçage de `lib/keys.sh`, l'option
  `--verify-key` et `nivuus_step_check_verify_tools`. Task 7 y ajoute le sourçage de
  `lib/migrate.sh`, la sous-commande `migrate` et `cmd_update`. Deux ajouts disjoints, aucun
  conflit sémantique — seulement des conflits de contexte au rebase.
- **`NIVUUS_RELEASE_BASE_URL` et `NIVUUS_GITHUB_API`** — introduites par le plan de signature pour
  les tests hors réseau du client zsh. Ce plan les réutilise **avec la même sémantique** dans
  `install.sh` (POSIX). Si leur nom ou leur forme change là-bas, il change ici aussi : un seul
  mécanisme, deux consommateurs.
- **`.github/workflows/release.yml`** — possédé par le plan de signature (job de signature) et
  modifié par le plan CI (le job `test` devient `uses: matrix.yml`). Task 12 n'y touche qu'à la
  synchronisation de version et aux notes de release, **en dernier**, après rebase sur les deux.
- **Plan CI, `fetch-depth` / `fetch-tags`** — `tests/e2e/test_upgrade_from_v3.bats` exige le tag
  `v3.0.0`. Les jobs qui exécutent la suite e2e doivent faire
  `actions/checkout@v4` avec `fetch-tags: true` (ou `fetch-depth: 0`). À signaler au plan CI
  plutôt qu'à modifier ici. Sans cela, le test échoue avec un message explicite — il ne `skip`
  pas, délibérément.
- **`.github/matrix.json` et `tests/ci/bats-run.sh`** — les nouvelles suites e2e
  (`test_bootstrap`, `test_upgrade_from_v3`, `test_migrate_git`, `test_install_without_git`,
  `test_docs_install`) sont ramassées par le glob `tests/e2e/` existant : rien à déclarer. Seule
  exception possible : si le plan CI introduit un étiquetage `--filter-tags`, `test_bootstrap`
  appartient au niveau 2 et `test_upgrade_from_v3` au niveau 4.
- **`tests/helpers/fingerprint.bash`** — réutilisé tel quel par trois tâches. **Aucune entrée
  ajoutée à son allowlist d'exceptions par ce plan.** Si une tâche est tentée d'en ajouter une,
  c'est qu'elle a trouvé une trace réellement laissée : la corriger, pas l'excuser.

---

## Ce que ce plan ne livre pas

Délibérément hors périmètre, avec la raison :

- **La signature du script d'amorçage lui-même.** Signer `install.sh` avec une clé servie par la
  même origine ne déplace le problème d'un cran que si la clé est distribuée autrement — ce que
  `--verify-key` fait déjà, sans artefact supplémentaire. Ajouter une signature détachée sur
  `install.sh` donnerait une impression de sécurité pour un gain nul.
- **Un domaine dédié (`get.nivuus.sh`) ou un raccourcisseur.** Une origine de plus à sécuriser, un
  certificat de plus à renouveler, un point de défaillance de plus, contre un gain purement
  esthétique sur la longueur de l'URL. À reconsidérer si le projet a un jour une infrastructure.
- **Les formules `brew`, `AUR` et `.deb`.** Chantier 4 du programme d'adoption, spec à part. Le
  noyau est conçu pour (`--prefix`, `--minimal`, manifeste), mais un wrapper de paquet a ses
  propres conventions de désinstallation, qu'on ne devine pas ici.
- **`nivuus install --system`.** Toujours indisponible, toujours refusé avec un message explicite.
  Le manifeste système (`/var/lib/nivuus/`) que le spec esquisse demande un modèle de permissions
  et un test en conteneur privilégié : c'est un chantier, pas une ligne.
- **La suppression automatique du dépôt parasite pendant l'installation.** `nivuus install` ne
  migre pas de lui-même, volontairement : déplacer un `.git` est une décision, et une décision se
  prend explicitement. `install`, `update` et `doctor` la signalent ; `migrate` l'exécute.
- **La restauration d'un `.git` migré par `nivuus uninstall`.** Le déplacement n'est pas journalisé
  dans le manifeste : « restaurer » à la désinstallation le dépôt qui était précisément le problème
  serait absurde. La commande de retour en arrière est affichée, une fois, au moment de la
  migration.
- **La refonte de `nivuus doctor`** (installation partielle, `.zshrc` divergent, bloc corrompu),
  listée dans la section 5 du spec. Ce plan n'y ajoute que le signalement du dépôt parasite. La
  refonte complète mérite son propre découpage, avec ses propres cas de test — la diluer ici
  reviendrait à la bâcler.
- **Le portage de `bin/nivuus` en POSIX sh.** Décision explicite du spec (section 1) : bash 3.2,
  parce que `bin/healthcheck` et le code existant y sont déjà. Seul l'amorçage est POSIX. La
  conséquence — `bash` requis sur Alpine — est constatée, documentée et signalée à l'utilisateur
  avec la commande exacte, pas contournée.
