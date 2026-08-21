# Installation système (`nivuus install --system`) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Qu'un administrateur puisse poser **une** copie de Nivuus pour toute une machine — là où aucun gestionnaire de paquets n'est visé (Fedora, RHEL, openSUSE, Alpine, images de conteneur, machines hors ligne) — sans jamais toucher au `$HOME` de personne, et la retirer en rendant `/etc`, `/usr/local` et `/var/lib` **bit-identiques** à ce qu'ils étaient avant.

**Architecture :** le modèle du chantier packaging, appliqué au canal « aucun gestionnaire ». Deux domaines, deux inventaires qui ne se recouvrent **jamais** :

| Domaine | Contenu | Inventaire | Qui écrit |
|---|---|---|---|
| **root** | `/usr/local/share/nivuus-shell/`, `/usr/local/bin/nivuus`, `/usr/local/share/man/man1/nivuus.1`, `/etc/skel/.zshrc` (opt-in), `/etc/zsh/zshrc.d/10-nivuus.zsh` + une ligne du rc global (opt-in) | `/var/lib/nivuus/manifest.tsv` (`mode=system`) | `nivuus install --system`, en root, jamais un shell |
| **utilisateur** | bloc délimité de `~/.zshrc`, `~/.zsh_local`, `~/.cache/nivuus-shell`, `chsh` | `~/.local/state/nivuus/manifest.tsv` (`mode=user`) | `nivuus enable` / `nivuus disable`, sans privilège |

La bascule est portée par `.nivuus-origin` (chantier packaging, Task A1) qui gagne une troisième valeur : `origin=system`. Le mode système **ne réinvente rien** de `enable`/`disable`, de la garde `[ -r … ] && source` du bloc `.zshrc`, de la résolution des liens symboliques dans `bin/nivuus`, ni de la non-compilation `.zwc` hors arbre possédé : il les **consomme**.

**Tech Stack :** bash 3.2 / POSIX ash (`bin/nivuus`, `lib/*.sh`), POSIX sh strict (`install.sh`, `tests/ci/*.sh`), zsh (`config/*.zsh`, `.zshrc`), bats, Docker (conteneurs de `.github/matrix.json`), `useradd`/`su`.

**Spec :** `docs/superpowers/specs/2026-08-21-installation-systeme-design.md` — elle fait autorité ; en cas de divergence avec ce plan, c'est la spec qui gagne.

**Chantiers dont ce plan dépend :**
- `docs/superpowers/plans/2026-08-21-packaging.md` **partie A** (phase 0 de sa spec) : `lib/origin.sh`, `nivuus enable`/`disable`, bloc `.zshrc` gardé, `bin/nivuus` derrière un lien, `.zwc` hors arbre possédé, `doctor` enrichi, `doc/nivuus.1`. **En cours d'implémentation en parallèle.** Ce plan est écrit en supposant la partie A mergée ; chaque endroit où les deux se touchent est listé dans « Points de contact » et **n'est pas replanifié ici**.
- `docs/superpowers/plans/2026-08-21-installation-preuve-ci.md` (phase 4) : `tests/ci/`, `.github/matrix.json`, `.github/actions/setup-tests`, `bin/test-count`. **Mergé** — vérifié sur `master` au commit `ced7e05` : les fichiers existent, `.github/workflows/matrix.yml` consomme `matrix.json`, et le tag bats `docker` est déjà en usage. La réserve du § 7.3 de la spec est donc **levée**.
- `docs/superpowers/plans/2026-08-21-installation-porte-entree.md` (phase 5) : `install.sh` POSIX bimodal, `nivuus_bootstrap`. **Mergé.**

**Sortie de phase :** sur une machine à deux comptes réels, une installation système est posée, alice l'active, bob ne l'a pas, carol (créée après `--skel`) l'a, l'activation machine couvre bob sans qu'il ne fasse rien, une installation utilisateur par-dessus gagne avec **un seul** `source`, et la désinstallation rend `/etc`, `/usr/local` et `/var/lib` **bit-identiques** — uid, gid et liens symboliques compris.

---

## État des lieux constaté (2026-08-21, commit `ced7e05`, branche `master`)

Vérifié dans le dépôt, pas supposé depuis la spec :

1. **Le seul code vivant de `--system` est un refus.** `install.sh:44` (ligne d'aide) et `install.sh:268-271` (le `case` qui affiche deux lignes et `exit 1`). `grep -rn 'system' bin/nivuus lib/` ne renvoie **rien** de pertinent : ni `INSTALL_MODE`, ni `/etc/skel`, ni `/etc/nivuus-shell`.

2. **Le format du manifeste porte déjà `mode=`.** `lib/manifest.sh:33` : `nivuus_manifest_begin() { local mode="$1" install_dir="$2" … }`, et l'en-tête écrit `mode=%s`. Le seul appelant, `bin/nivuus` `cmd_install`, passe `user` **en dur**. Rien à inventer dans le format : il attend sa seconde valeur.

3. **`NIVUUS_STATE_DIR` est déjà le seul point qui décide où vit l'état** (`lib/manifest.sh:34-37`, et `cmd_uninstall` qui le relit à l'identique). Le mode système le fixe à `/var/lib/nivuus`. **Aucune nouvelle variable de localisation d'état.**

4. **`nivuus_manifest_begin` en `--dry-run` écrit déjà dans un `mktemp` et ne crée aucun état** (`lib/manifest.sh:39-41`). Le chemin `--dry-run --system` sans root est donc **déjà** non privilégié par construction : la Task 9 le prouve et interdit sa régression, elle ne le construit pas.

5. **`tests/e2e/test_installation.bats:60-63` est un vestige sans valeur** : `grep -E '(--system|system.mode)' install.sh`. Il ne passe au vert **que** parce que le mot figure dans le message de refus, et il repasserait au rouge dès que ce message disparaît. Task 3.

6. **`tests/e2e/test_install_sh_compat.bats:24-27` est un test utile** : « install.sh --system fails with an explicit message », qui exerce le vrai comportement. Il est **transformé** par la Task 7, pas supprimé.

7. **`tests/e2e/test_docs_install.bats:47-50` est une garde inverse à conserver** : aucune doc ne doit recommander `sudo ./install.sh --system`. Task 22 l'étend à la forme nouvelle.

8. **`fs_fingerprint` (`tests/helpers/fingerprint.bash`) ne capture ni uid, ni gid, ni liens symboliques.** Elle capture `DIR`/`FILE`, chemin relatif, mode octal et sha256. La limite « les liens sont invisibles ici » est **déjà écrite en commentaire dans le fichier**, avec la consigne « ajouter `-type l` AVANT de se fier au vert de ce test ». Sur `/etc` et `/usr/local`, un `chown` ou un lien remplacé passerait inaperçu : **c'est un prérequis bloquant**, Task 1.

9. **Le dépôt n'a aucun `useradd`, aucun `su`, aucun test root.** `grep -rn 'useradd\|su -l' tests/` ne renvoie rien. Toute la suite est conçue pour tourner sans privilège avec `$HOME` déplacé. La brique multi-utilisateurs est neuve, Task 2.

10. **`config/99-cleanup.zsh:20-38` compile les `.zsh` à côté des sources**, sans condition d'inscriptibilité ni d'origine. Le correctif est la **Task A7 du chantier packaging** ; ce plan en dépend et l'exerce (étape 8 du script de preuve), il ne le replanifie pas.

11. **`config/20-autoupdate.zsh:460-471`** fait `find … -exec rm -rf` puis `cp -r` dans `$NIVUUS_SHELL_DIR`, protégé du seul cas « dépôt git » (`_nivuus_is_dev_checkout`). C'est ce chemin que le § 5.3 de la spec interdit d'emprunter sur un arbre système (Task 20).

12. **`install.sh` sait déjà télécharger, vérifier et déléguer** (`nivuus_bootstrap`, lignes 107-198), et bascule en mode local dès qu'un noyau existe à côté (`nivuus_local_root`, ligne 64). `sudo nivuus update` réutilise ce chemin (Task 20) — il ne réécrit pas un téléchargeur.

13. **Le tag bats `docker` est en usage et exclu par défaut** (`tests/ci/bats-run.sh`, `--filter-tags '!docker'`), avec un job nightly dédié `docker-tagged` dans `.github/workflows/matrix.yml`. Les 7 tests `docker` actuels vivent dans `tests/e2e/test_ci_deps_script.bats`. C'est le modèle exact que la Task 13 suit.

14. **`.github/matrix.json` porte six conteneurs** (`ubuntu-2204`, `ubuntu-2404`, `debian-12`, `arch`, `fedora-41`, `alpine-320`) et deux runners. `tests/unit/test_readme_badges.bats` n'y lit que `.label` : **ajouter une clé aux entrées est sans risque** pour lui.

15. **`doc/FEATURES.md:453-460`** publie encore `curl … | sudo bash -s -- --system` avec un démenti trois lignes plus bas. **`doc/CLAUDE.md:50` et `:235-237`** décrivent le modèle historique (`/etc/nivuus-shell`, `/etc/skel`, « temporairement indisponible »). **`README.md` ne mentionne plus `--system`** — vérifié. Task 22.

16. **Compteurs de référence** (`tests/baseline-counts.tsv`, à jour) : `unit 799`, `integration 195`, `e2e 181`, `performance 10`. Les 181 e2e comprennent les **7 tests `docker`** exclus par défaut : une exécution ordinaire en montre 174, dont 4 skips.

---

## Décisions actées (ne pas rouvrir)

1. **`/usr/local/share/nivuus-shell` est la racine, `/usr/local/bin/nivuus` le point d'entrée.** FHS 3.0 § 4.11 (`/usr/local` = installé localement, hors gestionnaire) et non-collision avec le futur `.deb` qui vise `/usr/share`. `/etc/nivuus-shell` **reste réservé** pour une future configuration de site (hors périmètre) : `install --system` refuse de s'installer par-dessus un arbre hérité qui s'y trouve, et ne le supprime jamais.
2. **Deux inventaires, jamais un troisième.** `/var/lib/nivuus/manifest.tsv` pour le domaine root, `~/.local/state/nivuus/manifest.tsv` pour chaque utilisateur. `/var/lib/nivuus/manifest.tsv` et un paquet Nivuus **ne coexistent jamais légitimement** : `doctor` le dit, il ne répare pas.
3. **`uninstall --system` ne touche à aucun `$HOME`, et ne les lit même pas.** Ni celui de `$SUDO_USER`. La seule lecture d'autrui est `doctor --system --scan-users`, opt-in explicite et en lecture seule.
4. **Aucun `chsh` en mode système, pour personne.** Aucune ligne `CHSH` ne peut apparaître dans un manifeste système ; un test l'interdit.
5. **`--skel` et `--activate-all` sont opt-in, jamais des défauts.** Et `--skel` **nomme sa limite** dans son message de succès, avec le nombre de comptes existants qu'il ne couvre pas.
6. **L'activation machine est vérifiée empiriquement ou annulée.** Un `/etc` modifié sans effet est pire qu'un refus. La preuve est un zsh interactif lancé dans un environnement vierge ; sans elle, `nivuus_manifest_abort` défait l'écriture et l'administrateur reçoit le chemin exact à ajouter à la main.
7. **Deux mécanismes anti-double-`source`, deux rôles.** Le `grep` du drop-in **choisit** (l'utilisateur gagne, toujours) ; la garde de réentrance de `.zshrc` **protège**. La garde est une variable **non exportée** (`_nivuus_sourced`) : `NIVUUS_SHELL_LOADED` est `export`ée et s'en servir désactiverait Nivuus dans tout zsh imbriqué.
8. **`sudo nivuus update` est une réinstallation vérifiée.** Il n'appelle **jamais** `_nivuus_perform_update` : ce serait une écriture massive hors manifeste dans le domaine root. Un test l'interdit mécaniquement.
9. **Refus avant toute écriture sans root**, avec la commande exacte. **Jamais** de `exec sudo "$0"`.
10. **`--dry-run --system` fonctionne sans root** et produit le rapport complet. C'est le pendant de « `curl … | sh --dry-run` sans jamais demander de privilège » : on doit pouvoir auditer avant de décider d'élever.
11. **Modes imposés, jamais hérités de l'umask** : `0755` répertoires, `0644` fichiers, `0755` exécutables, `root:root`. Un `sudo` avec `umask 077` produirait une installation « réussie » que personne ne peut lire.
12. **L'installeur recommande le `.deb` là où il existe.** Conséquence assumée de « redondant à ~90 % sur Debian/Ubuntu ». Ce n'est **pas un refus** : une information affichée une fois, avant toute écriture, suivie d'une confirmation.
13. **Aucun ordonnanceur.** Ni timer systemd, ni cron, ni unité. `sudo nivuus update` est idempotente et à code de retour propre ; l'automatiser appartient à l'administrateur.

---

## Contraintes globales

- **`lib/*.sh`, `install.sh` et `tests/ci/*.sh` restent POSIX** (BusyBox ash / bash 3.2). Interdits : `[[ ]]`, `declare -A`, `mapfile`, `${var^^}`, `local -n`, `&>>`, `BASH_SOURCE`, `< <(…)`. `bats tests/unit/test_lib_posix.bats` doit rester vert après chaque commit touchant `lib/`. `config/*.zsh` et `.zshrc` sont du zsh.
- **Aucune écriture hors `lib/manifest.sh`.** Le mode système ne fait **aucune** exception : `/etc/skel/.zshrc`, le drop-in, la ligne du rc global, l'arbre et le lien passent tous par `nivuus_install_file`, `nivuus_write_file`, `nivuus_mkdir_p` ou `nivuus_manifest_record`. `lib/system.sh` **décide** des chemins et **constate** ; il n'écrit pas. Un test le vérifie mécaniquement (`grep -nE '^\s*(mv|rm|cp|mkdir|chmod|ln) ' lib/system.sh` doit être vide).
- **Réversibilité bit-exacte préservée dans les deux domaines.** `bats tests/e2e/test_reversibility.bats` (domaine utilisateur) doit rester vert **à chaque commit**, y compris après l'extension de `fs_fingerprint`. Le domaine root est prouvé par `tests/ci/run-system-target.sh`.
- **Aucun `sudo` implicite, nulle part**, y compris dans les messages. `grep -rn 'sudo ' install.sh bin/nivuus lib/ | grep -v 'nivuus_sudo_prefix\|log_warn\|log_info\|log_error\|printf'` doit rester vide.
- **Budget de démarrage <300 ms** (`./bin/benchmark`, ~35 ms aujourd'hui), gardé par `tests/performance/`. Le seul coût ajouté au chemin de démarrage par ce plan est la garde de réentrance : **deux lignes, aucun fork, aucun accès disque**. Le `grep` du drop-in ne s'exécute que sur les machines qui ont opté pour l'activation machine, et il est mesuré comme le reste.
- **Piège des `.zwc`** : avant toute suite qui touche `config/*.zsh` ou `.zshrc`, faire `rm -f config/*.zwc .zshrc.zwc`. Un bytecode périmé fait passer (ou échouer) un test contre une version qui n'existe plus.
- **Chiffres de référence à ne pas dégrader** (0 échec partout) :

  | Suite | Tests | Remarque |
  |---|---|---|
  | `bats tests/unit/` | **799** | 0 skip |
  | `bats tests/integration/` | **195** | 2 skips |
  | `bats tests/e2e/` | **181** au compte, **~174** exécutés | 4 skips, 7 tests `docker` exclus par défaut |
  | `bats tests/performance/` | **10** | 0 skip |

  Ce plan **ajoute** des tests ; ces nombres ne peuvent que croître. Si un test **existant** bascule au rouge ou en `skip`, c'est une régression du plan, pas un chiffre à mettre à jour.
- **`./bin/test-count --check` doit sortir en 0.** Toute tâche qui ajoute des tests termine par `./bin/test-count --update` et committe `tests/baseline-counts.tsv` **dans le même commit**. Toute tâche qui **retire** un test doit en fournir un meilleur dans le même commit : le cliquet est là pour ça.
- **TDD strict** : écrire le test, le voir **rouge**, écrire le minimum, le voir vert, committer. Un test qui passe du premier coup est un test qui ne teste rien : le rendre rouge d'abord, quitte à casser volontairement l'implémentation pour le vérifier.
- **La couche PR reste entièrement non privilégiée.** Tout ce qui est testable sans root l'est via les crochets `NIVUUS_SYSTEM_PREFIX`, `NIVUUS_SYSTEM_STATE_DIR`, `NIVUUS_ETC_DIR`, `NIVUUS_UID` — dans la lignée de `NIVUUS_ETC_SHELLS`, `NIVUUS_LOGIN_SHELL_FILE`, `NIVUUS_OS_RELEASE`, `NIVUUS_STATE_DIR` qui existent déjà. Le seul test qui exige root et `useradd` est `tests/ci/run-system-target.sh`, isolé, marqué `docker`, jamais exécuté sur un runner.
- **Un commit par tâche**, message conventionnel **en anglais** (`feat(system): …`, `test(helpers): …`). Documentation et commentaires **en français**, messages utilisateur **en français** (convention constatée du dépôt).
- **Tâches indépendantes et mergeables.** Groupes mergeables séparément : `{1,2,3}` (outillage), `{4…14}` (phase 1), `{15}` (phase 2), `{16,17,18}` (phase 3), `{19,20,21,22}` (phase 4). À l'intérieur d'un groupe, l'ordre donné est celui des dépendances de code.

---

## Points de contact avec le chantier packaging (partie A, en cours)

Aucun de ces éléments n'appartient à ce plan. Chacun est **consommé**, jamais réécrit. Rebaser sur la partie A avant d'entamer le groupe concerné.

| Élément (partie A) | Ce que ce plan en fait | Tâche |
|---|---|---|
| `lib/origin.sh` — `nivuus_origin`, `nivuus_origin_is_package`, `nivuus_origin_channel`, `nivuus_origin_update_command`, `nivuus_origin_tree_writable` | Ajoute la valeur `system` : `.nivuus-origin` écrit par `install --system` porte `origin=system`, `channel=selfhosted`. `nivuus_origin_is_package` **doit rester faux** pour `system` (le message diffère) ; le test de refus d'auto-update devient `nivuus_origin != source`. **Si A1 n'est pas mergée, la Task 6 crée `lib/origin.sh` avec la seule fonction `nivuus_origin` et A1 l'étend ensuite** — ne pas dupliquer le module. | 6, 19 |
| `nivuus enable` / `nivuus disable` (A9) | Consommés tels quels : c'est **la** surface d'activation par défaut du mode système. Ce plan n'ajoute que `enable --all` (activation machine) et `enable --all --print`. | 17 |
| Bloc `.zshrc` gardé `[ -r … ] && source` (A3) | Consommé tel quel, y compris dans `/etc/skel/.zshrc` et dans le drop-in. C'est **la** raison pour laquelle `uninstall --system` peut se permettre de ne pas toucher aux `$HOME` : aucun shell ne casse. | 15, 16 |
| `bin/nivuus` derrière un lien symbolique (A2) | **Prérequis dur** : `/usr/local/bin/nivuus -> /usr/local/share/nivuus-shell/bin/nivuus` est exactement le cas qu'A2 corrige. Sans A2, l'installation système est cassée dès le premier appel. Une assertion de la Task 6 le vérifie explicitement plutôt que de le supposer. | 6 |
| `.zwc` hors arbre possédé (A7) | Consommé et **exercé** : l'étape 8 du script de preuve ouvre un shell **root** sur l'arbre système et exige `find … -name '*.zwc'` vide. C'est le cas où l'écriture *réussirait*. | 13 |
| `doctor` enrichi (A10) | Étendu, pas réécrit : ce plan ajoute l'origine `system`, la double installation, l'héritage `/etc/nivuus-shell`, le conffile modifié et `--scan-users`. | 21 |
| `doc/nivuus.1` (A11) | Consommé : installé dans `/usr/local/share/man/man1/` par `install --system`, inventorié comme le reste. Si A11 n'est pas mergée, la Task 6 **saute silencieusement** la page absente (le fichier source n'existe pas) — sans échouer, et sans la réinventer. | 6 |
| Garde-fou `grep` des invariants dans `tests.yml` (A13) | **Étendu**, jamais dupliqué : les quatre invariants de ce plan rejoignent l'étape « The two invariants must be present and green » qui existe déjà pour la signature. | 14 |
| Décision A « pas de manifeste système » | **Rouverte pour `--system` seulement**, et de façon cohérente : la règle est « un inventaire, jamais deux ». En mode paquet il y en a un (`dpkg`) ; en mode `--system` il y en a zéro, en créer un porte le total à un. La phrase de la spec packaging reste vraie **mot pour mot pour les paquets**. | 6 |
| `.github/matrix.json`, `tests/ci/run-target.sh`, `setup-tests` (phase 4, mergée) | `run-system-target.sh` est écrit **sur le modèle de `run-target.sh`** (toute la logique de preuve dans le script, rien dans le YAML, rejouable par `docker run`). `matrix.json` reçoit une clé `"system": true` sur les cibles concernées — additive, lue par personne d'autre. | 13, 14 |

**Si la partie A n'est pas mergée au moment d'exécuter le groupe 1 :** rien ne bloque pour les Tasks 1 à 5 et 9 à 12. Les Tasks 6, 15, 16 et 17 dépendent réellement d'A2, A3 et A9 — les entamer avant coûterait un conflit sémantique, pas seulement un conflit de contexte.

---

# GROUPE 0 — Outillage de preuve

Trois tâches, aucun code produit, aucune dépendance à la partie A. Elles conditionnent **tout** le reste : sans elles, le mode dont l'intérêt entier est « plusieurs utilisateurs » ne serait prouvé par rien, et l'empreinte censée démontrer le retrait bit-exact laisserait passer un `chown`.

---

### Task 1: `fs_fingerprint` capture le propriétaire, le groupe et les liens symboliques

**Files:**
- Modify: `tests/helpers/fingerprint.bash`
- Create: `tests/unit/test_helper_fingerprint.bats`
- Test (doit rester vert **sans modification**) : `tests/e2e/test_reversibility.bats`

**Interfaces:**
- Produces : `fs_owner <chemin>` (uid:gid numériques, sans suivre les liens) ; `fs_fingerprint <racine>` étendue avec deux colonnes (`uid:gid`) sur `DIR` et `FILE`, et une troisième catégorie de ligne, `LINK`.
- Consumers : Task 13 (`run-system-target.sh`, empreintes de `/etc`, `/usr/local`, `/var/lib`), et les six suites e2e existantes qui l'utilisent déjà.

**Pourquoi cette tâche est un prérequis bloquant.** La promesse du mode système est « `/etc` et `/usr/local` bit-identiques après retrait ». L'empreinte actuelle capture `DIR`/`FILE`, chemin, mode octal et sha256 : un `chown root:staff` sur `/usr/local/share`, ou un `/usr/local/bin/nivuus` laissé en lien mort, produirait **exactement la même empreinte** avant et après. Le fichier porte déjà l'aveu en commentaire (« LIMITE CONNUE : les liens symboliques sont invisibles ici […] ajouter `-type l` ici AVANT de se fier au vert de ce test »). C'est le moment.

**Pourquoi l'extension ne casse aucun usage existant.** Les six suites qui l'appellent comparent **deux empreintes produites par la même version** de la fonction (`diff "$TMP/before" "$TMP/after"`). Ajouter des colonnes change les deux côtés identiquement. Le seul risque réel serait qu'une des nouvelles colonnes soit **instable entre deux appels** dans un `$HOME` non privilégié — d'où le test « deux empreintes consécutives d'un arbre inchangé sont identiques », qui est la vraie non-régression.

**Trois pièges de portabilité, tranchés ici :**
- `stat -c` (GNU) contre `stat -f` (BSD/macOS) : le fichier a déjà le motif, on le suit (`fs_perms`).
- **Ni GNU `stat` ni BSD `stat` ne suivent un lien par défaut** — c'est ce qu'on veut : le propriétaire du lien, pas celui de la cible.
- Les **modes** d'un lien symbolique ne sont pas portables (Linux les ignore, BSD non) : on ne les capture pas. Ce qu'un lien porte réellement, c'est sa **cible** (qui fait office de contenu) et son **propriétaire** (qu'un `chown -h` change pour de bon).

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_helper_fingerprint.bats
#!/usr/bin/env bats
#
# L'empreinte est le seul instrument de mesure de la promesse centrale du
# projet (« aucune trace après désinstallation »). Un instrument qui ne
# mesure pas ce qu'on croit est pire qu'aucun instrument : il transforme une
# absence de preuve en preuve. Ces tests décrivent ce qu'il DOIT voir.

load '../helpers/fingerprint'

setup() {
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/arbre/sous"
    printf 'contenu\n' > "$TMP/arbre/fichier"
}

teardown() { rm -rf "$TMP"; }

@test "l'empreinte capture uid et gid des fichiers et des répertoires" {
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    ids="$(id -u):$(id -g)"
    [[ "$output" == *"$ids"* ]]
    # Une ligne FILE porte : type, chemin, mode, uid:gid, sha256 -> 5 colonnes.
    n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="FILE"{print NF; exit}')"
    [ "$n" -eq 5 ]
    # Une ligne DIR porte : type, chemin, mode, uid:gid -> 4 colonnes.
    n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="DIR"{print NF; exit}')"
    [ "$n" -eq 4 ]
}

@test "un lien symbolique apparaît, avec sa cible" {
    ln -s fichier "$TMP/arbre/lien"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINK"* ]]
    [[ "$output" == *"/lien"* ]]
    printf '%s\n' "$output" | awk -F'\t' '$1=="LINK" && $NF=="fichier"{ok=1} END{exit !ok}'
}

@test "un lien mort apparaît aussi (il ne se cache pas derrière sa cible absente)" {
    ln -s /nulle/part "$TMP/arbre/mort"
    run fs_fingerprint "$TMP/arbre"
    [[ "$output" == *"/mort"* ]]
    # Et il n'est PAS compté comme un fichier : find -type f ne le voit pas,
    # find -type l si. Un lien mort laissé derrière est une trace.
    printf '%s\n' "$output" | awk -F'\t' '$2=="/mort" && $1=="LINK"{ok=1} END{exit !ok}'
}

@test "remplacer un fichier par un lien vers un contenu identique CHANGE l'empreinte" {
    # Le mode d'échec que l'ancienne empreinte laissait passer : le sha256
    # de la cible est le même, donc rien ne bougeait.
    fs_fingerprint "$TMP/arbre" > "$TMP/avant"
    printf 'contenu\n' > "$TMP/ailleurs"
    rm "$TMP/arbre/fichier"
    ln -s "$TMP/ailleurs" "$TMP/arbre/fichier"
    fs_fingerprint "$TMP/arbre" > "$TMP/apres"
    run diff "$TMP/avant" "$TMP/apres"
    [ "$status" -ne 0 ]
}

@test "la cible d'un lien est lue SANS être suivie" {
    ln -s /etc "$TMP/arbre/vers_etc"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    # Si le lien était suivi, l'empreinte contiendrait le contenu de /etc.
    [[ "$output" != *"/vers_etc/"* ]]
}

@test "deux empreintes consécutives d'un arbre inchangé sont identiques" {
    # LA non-régression des six suites qui comparent before/after : si une
    # colonne était instable, tests/e2e/test_reversibility.bats deviendrait
    # rouge de façon intermittente, ce qui est pire qu'un échec franc.
    ln -s fichier "$TMP/arbre/lien"
    fs_fingerprint "$TMP/arbre" > "$TMP/un"
    fs_fingerprint "$TMP/arbre" > "$TMP/deux"
    run diff "$TMP/un" "$TMP/deux"
    [ "$status" -eq 0 ]
}

@test "fs_owner ne suit pas le lien" {
    ln -s fichier "$TMP/arbre/lien"
    run fs_owner "$TMP/arbre/lien"
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -u):$(id -g)" ]
}

@test "la sortie reste triée et stable (LC_ALL=C)" {
    mkdir -p "$TMP/arbre/Z" "$TMP/arbre/a"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    trie="$(printf '%s\n' "$output" | LC_ALL=C sort)"
    [ "$output" = "$trie" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_helper_fingerprint.bats`
Expected: FAIL — `fs_owner` n'existe pas ; aucune ligne `LINK` ; les lignes `FILE` n'ont que 4 colonnes.

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/helpers/fingerprint.bash  (remplacer l'en-tête et fs_fingerprint)

# Empreinte reproductible d'une arborescence : chemin, permissions,
# propriétaire, contenu — et les liens symboliques, cible comprise.
#
# Pourquoi uid/gid : le mode système écrit en root dans /etc et /usr/local.
# Un chown qui survit à la désinstallation est une trace, et sans ces deux
# colonnes il serait strictement invisible.
# Pourquoi les liens : /usr/local/bin/nivuus EST un lien. Sans -type l, un
# lien mort laissé derrière ne ferait échouer aucun test.
#
# Non capturés, et c'est délibéré : les attributs étendus, les ACL, les
# contextes SELinux (restorecon est best-effort, cf. le plan) et les mtimes
# (la promesse porte sur le contenu, les chemins et les droits).
# Les MODES d'un lien symbolique ne sont pas capturés : ils ne sont pas
# portables (Linux les ignore, BSD non). Ce qu'un lien porte réellement,
# c'est sa cible et son propriétaire.

fs_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fs_perms() {
    # -c GNU, -f BSD/macOS
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# uid:gid NUMÉRIQUES : un nom d'utilisateur dépend de /etc/passwd, qui
# diffère d'un conteneur à l'autre ; un uid ne dépend de rien.
# Ni `stat -c` (GNU) ni `stat -f` (BSD) ne suivent un lien symbolique par
# défaut -- c'est exactement ce qu'on veut ici.
fs_owner() {
    stat -c '%u:%g' "$1" 2>/dev/null || stat -f '%u:%g' "$1"
}

fs_fingerprint() {
    local root="$1"
    { find "$root" -type d | while IFS= read -r d; do
          printf 'DIR\t%s\t%s\t%s\n' "${d#$root}" "$(fs_perms "$d")" "$(fs_owner "$d")"
      done
      find "$root" -type f | while IFS= read -r f; do
          printf 'FILE\t%s\t%s\t%s\t%s\n' "${f#$root}" "$(fs_perms "$f")" "$(fs_owner "$f")" "$(fs_hash "$f")"
      done
      find "$root" -type l | while IFS= read -r l; do
          # La cible fait office de « contenu » : c'est tout ce qu'un lien
          # transporte. readlink (sans -f) ne résout PAS la chaîne : on veut
          # ce que le lien dit, pas où il finit.
          printf 'LINK\t%s\t%s\t%s\n' "${l#$root}" "$(fs_owner "$l")" "$(readlink "$l")"
      done
    } | LC_ALL=C sort
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_helper_fingerprint.bats     # 8 tests verts
rm -f config/*.zwc .zshrc.zwc
bats tests/e2e/test_reversibility.bats           # inchangé, vert
bats tests/e2e/test_bootstrap.bats tests/e2e/test_upgrade_from_v3.bats \
     tests/e2e/test_install_without_git.bats tests/e2e/test_migrate_git.bats \
     tests/e2e/test_verify_key.bats tests/e2e/test_update_signature.bats
```
Expected: PASS partout. Les six suites consommatrices ne sont **pas** modifiées : c'est la démonstration que l'extension est neutre.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add tests/helpers/fingerprint.bash tests/unit/test_helper_fingerprint.bats tests/baseline-counts.tsv
git commit -m "test(helpers): fingerprint owner, group and symlinks"
```

---

### Task 2: `tests/helpers/users.bash` — alice, bob et carol, jetables

**Files:**
- Create: `tests/helpers/users.bash`
- Create: `tests/e2e/test_helper_users.bats` (marqué `docker`)

**Interfaces:**
- Produces : `users_require_root` (skip explicite sinon), `mk_user <nom> [shell]`, `user_home <nom>`, `as_user <nom> <commande…>`, `rm_user <nom>`, `count_regular_users`.
- Consumers : Task 13, 15, 18 (`run-system-target.sh`).

**Pourquoi une brique neuve, et pourquoi elle est petite.** Le dépôt n'a **aucun** `useradd`, `su` ni test root : toute la suite tourne sans privilège avec `$HOME` déplacé. Le mode système est le premier à avoir besoin de comptes réels — et il en a besoin **absolument**, puisque son intérêt entier est « plusieurs utilisateurs ». On isole donc tout le privilège dans un helper unique, appelé seulement depuis un script de conteneur.

**Le piège Alpine.** `useradd` est GNU/shadow ; BusyBox fournit `adduser`, avec une syntaxe différente (`-D` au lieu de `-m`, pas de `--`). Alpine est une cible de la matrice **et** un des deux cas d'usage centraux de `--system` (§ 1.1 de la spec) : le helper doit couvrir les deux, ou la moitié du périmètre n'est pas testée.

**`su -l` et non `su -c`.** `su -l` recharge l'environnement de l'utilisateur cible (`$HOME`, `$USER`, `$SHELL`) : c'est le seul moyen d'exercer réellement « ce que voit alice quand elle ouvre un shell ». Un `su -c` hériterait du `$HOME` de root et prouverait le contraire de ce qu'on cherche.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_helper_users.bats
#!/usr/bin/env bats
#
# Le helper qui porte TOUTE la partie privilégiée de la preuve système.
# Marqué `docker` : il crée de vrais comptes, il n'a rien à faire sur un
# runner ni sur le poste de quelqu'un (voir tests/ci/bats-run.sh).

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

# Rejoue le helper dans un conteneur : c'est le seul contexte où créer un
# compte est acceptable.
in_image() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c "
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null 2>&1 || true
        . ./tests/helpers/users.bash
        $2
    "
}

# bats test_tags=docker
@test "mk_user / as_user / rm_user sur debian:12 (useradd)" {
    run in_image debian:12 '
        mk_user alice
        test -d "$(user_home alice)"
        as_user alice "id -un" | grep -qx alice
        as_user alice "printf %s \"\$HOME\"" | grep -q "/home/alice"
        rm_user alice
        ! id alice >/dev/null 2>&1
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "mk_user / as_user / rm_user sur alpine:3.20 (adduser BusyBox)" {
    run in_image alpine:3.20 '
        mk_user bob
        test -d "$(user_home bob)"
        as_user bob "id -un" | grep -qx bob
        rm_user bob
        ! id bob >/dev/null 2>&1
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "mk_user est idempotent (rejouer un script de preuve ne doit pas échouer)" {
    run in_image debian:12 'mk_user alice; mk_user alice; rm_user alice'
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "as_user n'hérite PAS du HOME de root" {
    # Le piège qui invaliderait toute la preuve : su -c au lieu de su -l.
    run in_image debian:12 '
        mk_user alice
        as_user alice "printf %s \"\$HOME\"" | grep -qv "^/root$"
        rm_user alice
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "count_regular_users compte les comptes humains, sans lire /home" {
    run in_image debian:12 '
        avant="$(count_regular_users)"
        mk_user alice; mk_user bob
        apres="$(count_regular_users)"
        test "$apres" -eq "$((avant + 2))"
        rm_user alice; rm_user bob
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "users_require_root skippe proprement sans privilège" {
    run in_image debian:12 '
        useradd -m -s /bin/sh nobody2
        su -l nobody2 -c "cd /work && . ./tests/helpers/users.bash; users_require_root && echo NON_ATTENDU || echo REFUS_OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUS_OK"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `NIVUUS_CI_DOCKER=1 bats tests/e2e/test_helper_users.bats`
Expected: FAIL — `tests/helpers/users.bash` n'existe pas (le `.` échoue dans le conteneur).
(Sans docker : les tests `skip`, ce qui n'est **pas** un vert. Exécuter cette tâche sur une machine avec docker.)

- [ ] **Step 3: Write minimal implementation**

```bash
# tests/helpers/users.bash
# Comptes jetables pour la preuve du mode système.
#
# C'est la SEULE brique privilégiée du dépôt. Elle n'est appelée que par
# tests/ci/run-system-target.sh, qui ne tourne que dans un conteneur
# jetable -- jamais sur un runner, jamais sur un poste. Chaque fonction
# refuse d'agir sans root plutôt que d'échouer à moitié.

users_require_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    printf '%s\n' "Ce test exige root et un conteneur jetable (useradd/su)." >&2
    return 1
}

# useradd (shadow, GNU) OU adduser (BusyBox, Alpine) : deux syntaxes
# incompatibles, et Alpine est à la fois une cible de la matrice et l'un des
# deux cas d'usage centraux de --system. Couvrir les deux n'est pas un luxe.
mk_user() {
    _u="$1"; _sh="${2:-/bin/zsh}"
    id "$_u" >/dev/null 2>&1 && return 0     # idempotent : un script de preuve se rejoue
    if command -v useradd >/dev/null 2>&1; then
        useradd -m -s "$_sh" "$_u"
    elif command -v adduser >/dev/null 2>&1; then
        adduser -D -h "/home/$_u" -s "$_sh" "$_u"
    else
        printf '%s\n' "Ni useradd ni adduser : impossible de créer $_u." >&2
        return 1
    fi
}

# Le HOME tel que le SYSTÈME le connaît, jamais deviné à partir du nom :
# /etc/skel, useradd et adduser peuvent tous le placer ailleurs.
user_home() {
    getent passwd "$1" 2>/dev/null | cut -d: -f6
}

# su -l, pas su -c : -l recharge HOME, USER et SHELL de la cible. Avec su -c,
# $HOME resterait /root et l'on prouverait exactement le contraire de ce
# qu'on cherche (« alice voit son propre HOME »).
as_user() {
    _u="$1"; shift
    su -l "$_u" -c "$*"
}

rm_user() {
    _u="$1"
    id "$_u" >/dev/null 2>&1 || return 0
    if command -v userdel >/dev/null 2>&1; then
        userdel -r "$_u" 2>/dev/null || userdel "$_u"
    elif command -v deluser >/dev/null 2>&1; then
        deluser --remove-home "$_u" 2>/dev/null || deluser "$_u"
    fi
}

# Comptes humains : uid >= 1000, shell non nologin/false. Lu dans
# /etc/passwd -- JAMAIS en parcourant /home, qui déclencherait l'automonteur
# sur un parc NFS (cf. § 3.3 de la spec) et lirait des répertoires d'autrui.
count_regular_users() {
    awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { n++ } END { print n + 0 }' \
        "${NIVUUS_PASSWD_FILE:-/etc/passwd}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `NIVUUS_CI_DOCKER=1 bats tests/e2e/test_helper_users.bats`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add tests/helpers/users.bash tests/e2e/test_helper_users.bats tests/baseline-counts.tsv
git commit -m "test(helpers): disposable users for the system-mode proof"
```

---

### Task 3: retirer le vestige `--system` de `tests/e2e/test_installation.bats`

**Files:**
- Modify: `tests/e2e/test_installation.bats`

**Interfaces:**
- Consumes: rien.
- Produces: un test de l'**aide** à la place d'un test de la **présence d'un mot**.

**Pourquoi c'est une tâche à part entière.** `tests/e2e/test_installation.bats:60-63` fait `grep -E '(--system|system.mode)' install.sh`. Il ne passe au vert que parce que le mot `--system` figure dans le **message de refus**. Il ne teste donc rien du comportement : il testerait aussi bien un fichier qui contient le mot dans un commentaire. Pire, il deviendra **faussement rassurant** dès la Task 7 — vert sur une fonctionnalité qu'il n'exerce pas. Le laisser jusqu'à la réactivation reviendrait à le transformer en preuve fantôme au moment exact où une vraie preuve devient possible.

**Ce qui le remplace, et pourquoi ce test-là.** Une assertion sur l'**aide** : `install.sh --help` doit nommer `--system`. Elle est vraie aujourd'hui (l'aide décrit l'option, ligne 44) et vraie après la Task 7 (l'aide décrit le nouveau comportement). Elle survit donc à la bascule sans être ajustée pour l'occasion — ce qui est précisément la propriété qui manquait à l'ancienne. Et elle exerce le script au lieu de le lire.

Le compte de tests reste inchangé (un test retiré, un test ajouté) : le cliquet de `bin/test-count` n'a rien à dire, et il n'y a rien à mettre à jour.

- [ ] **Step 1: Write the failing test**

Remplacer le bloc `tests/e2e/test_installation.bats:60-63` par :

```bash
@test "l'aide d'install.sh documente --system" {
    # Une assertion sur le COMPORTEMENT (le script s'exécute et répond),
    # pas sur la présence d'un mot dans le fichier. L'ancienne version de
    # ce test faisait « grep --system install.sh » et ne passait au vert
    # que grâce au message de refus : elle serait restée verte en
    # n'exerçant rien du tout une fois --system réactivé.
    run "$NIVUUS_SHELL_DIR/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--system"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Vérifier d'abord que le remplacement teste bien quelque chose, en cassant volontairement l'aide :

```bash
sed -i.bak 's/^  --system .*/  --sysXXX  (cassé exprès)/' install.sh
bats tests/e2e/test_installation.bats -f "aide d'install.sh documente"
# Expected: FAIL
mv install.sh.bak install.sh
```

- [ ] **Step 3: Write minimal implementation**

Aucune implémentation : la suppression du vestige **est** le travail. Vérifier qu'il ne subsiste nulle part :

```bash
grep -rn "system.mode" tests/    # -> aucun résultat
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/e2e/test_installation.bats
./bin/test-count --check          # e2e inchangé : 181
```
Expected: PASS, et `--check` sort en 0 sans annoncer de croissance ni de régression.

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/test_installation.bats
git commit -m "test(install): drop the --system grep vestige for a real help assertion"
```

---

# GROUPE 1 — Arbre système et réversibilité (phase 1 de la spec)

Onze tâches. Aucune activation automatique : ni `/etc/skel`, ni activation machine. À la fin du groupe, `nivuus install --system` pose un arbre partagé, `nivuus enable` l'active pour qui le demande, `nivuus uninstall --system` rend `/etc`, `/usr/local` et `/var/lib` **bit-identiques** — et deux utilisateurs réels le prouvent dans un conteneur.

**Ordre de dépendance :** 4 → 5 → 6 → 7 → {8, 9, 10, 11} → 12 → 13 → 14 → 15. Les tâches 8 à 11 sont mutuellement indépendantes une fois 7 mergée.

---

### Task 4: `lib/system.sh` — les chemins, les crochets, et le refus de privilège

**Files:**
- Create: `lib/system.sh`
- Modify: `bin/nivuus` (sourcer le nouveau module)
- Create: `tests/unit/test_lib_system.bats`
- Create: `tests/unit/test_system_privileges.bats`

**Interfaces:**
- Consumes: `lib/log.sh`, `lib/detect.sh` (`nivuus_detect_os`, `nivuus_detect_distro`, `nivuus_detect_distro_like`).
- Produces:
  - `nivuus_system_tree`, `nivuus_system_bin`, `nivuus_system_man`, `nivuus_system_state_dir`
  - `nivuus_system_skel`, `nivuus_system_dropin`, `nivuus_system_global_rc`
  - `nivuus_system_is_root`, `nivuus_system_require_root <action>`
  - `nivuus_system_legacy_tree`
  - `nivuus_system_package_channel`
- Consumers: Tasks 7 à 23.

**Ce module décide et constate ; il n'écrit jamais.** Toute écriture passe par `lib/manifest.sh`, sans exception, y compris dans `/etc`. Un test le vérifie mécaniquement.

**Les crochets d'environnement, et pourquoi ils rendent la couche PR non privilégiée.** Le dépôt a déjà ce motif (`NIVUUS_ETC_SHELLS`, `NIVUUS_LOGIN_SHELL_FILE`, `NIVUUS_OS_RELEASE`, `NIVUUS_STATE_DIR`, `NIVUUS_DOCKERENV`). On l'étend, on ne l'invente pas :

| Crochet | Défaut | Ce qu'il rend testable sans root |
|---|---|---|
| `NIVUUS_SYSTEM_PREFIX` | `/usr/local` | l'arbre, le lien, la page de manuel |
| `NIVUUS_SYSTEM_STATE_DIR` | `/var/lib/nivuus` | le manifeste système |
| `NIVUUS_ETC_DIR` | `/etc` | `skel`, drop-in, rc global |
| `NIVUUS_UID` | `$(id -u)` | **le refus sans root, et le succès avec** — sans jamais être root |
| `NIVUUS_PASSWD_FILE` | `/etc/passwd` | le comptage des comptes existants (Task 16) |

**Pourquoi `NIVUUS_SYSTEM_PREFIX` vaut `/usr/local` et non l'arbre complet.** La spec nomme la variable sans dire ce qu'elle contient. Trois chemins en dépendent (`share/nivuus-shell`, `bin/nivuus`, `share/man/man1`) et ils doivent bouger **ensemble** : un test qui déplacerait l'arbre sans déplacer le lien prouverait une configuration qui n'existe pas. La variable porte donc le **préfixe FHS**, et trois fonctions en dérivent les chemins. C'est un silence de la spec, comblé ici et signalé en fin de plan.

**Le rc global n'est pas devinable, il est détecté.** `/etc/zsh/zshrc` (Debian, Ubuntu, Arch) contre `/etc/zshrc` (Fedora, RHEL, macOS) : le fichier réellement lu dépend du `--enable-etcdir` de compilation de zsh. La fonction choisit sur l'**existence du répertoire `/etc/zsh`**, et la Task 18 ne se contente pas de ce choix : elle le **vérifie empiriquement** avant de croire que l'activation a marché.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_lib_system.bats
#!/usr/bin/env bats
#
# lib/system.sh décide où vont les fichiers du domaine root. Chaque chemin
# est un crochet : c'est ce qui permet à toute cette couche d'être prouvée
# sur une PR, sans conteneur, sans root et sans toucher au vrai /etc.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "les trois chemins du préfixe bougent ensemble" {
    [ "$(nivuus_system_tree)" = "$TMP/usr/local/share/nivuus-shell" ]
    [ "$(nivuus_system_bin)"  = "$TMP/usr/local/bin/nivuus" ]
    [ "$(nivuus_system_man)"  = "$TMP/usr/local/share/man/man1/nivuus.1" ]
}

@test "l'état système vit dans /var/lib/nivuus, pas dans l'arbre qu'il décrit" {
    [ "$(nivuus_system_state_dir)" = "$TMP/var/lib/nivuus" ]
    case "$(nivuus_system_state_dir)" in
        "$(nivuus_system_tree)"*) false ;;   # le journal ne vit jamais dans ce qu'il doit pouvoir supprimer
        *) true ;;
    esac
}

@test "les défauts sont ceux de la spec quand aucun crochet n'est posé" {
    ( unset NIVUUS_SYSTEM_PREFIX NIVUUS_SYSTEM_STATE_DIR NIVUUS_ETC_DIR
      . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
      [ "$(nivuus_system_tree)" = "/usr/local/share/nivuus-shell" ]
      [ "$(nivuus_system_bin)" = "/usr/local/bin/nivuus" ]
      [ "$(nivuus_system_state_dir)" = "/var/lib/nivuus" ]
      [ "$(nivuus_system_skel)" = "/etc/skel/.zshrc" ]
      [ "$(nivuus_system_dropin)" = "/etc/zsh/zshrc.d/10-nivuus.zsh" ] )
}

@test "le rc global est /etc/zsh/zshrc quand /etc/zsh existe (Debian, Arch)" {
    mkdir -p "$TMP/etc/zsh"
    [ "$(nivuus_system_global_rc)" = "$TMP/etc/zsh/zshrc" ]
}

@test "le rc global est /etc/zshrc sinon (Fedora, RHEL, macOS)" {
    mkdir -p "$TMP/etc"
    [ "$(nivuus_system_global_rc)" = "$TMP/etc/zshrc" ]
}

@test "l'arbre hérité /etc/nivuus-shell est détecté, jamais supprimé" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo core\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run nivuus_system_legacy_tree
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/etc/nivuus-shell" ]
    # Aucune suppression : on ne restaure pas ce qu'on n'a pas sauvegardé.
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]
}

@test "un /etc/nivuus-shell vide ou absent n'est pas un arbre hérité" {
    run nivuus_system_legacy_tree
    [ "$status" -ne 0 ]
    mkdir -p "$TMP/etc/nivuus-shell"
    run nivuus_system_legacy_tree
    [ "$status" -ne 0 ]
}

@test "le canal deb est annoncé sur Debian et Ubuntu" {
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ "$status" -eq 0 ]
    [ "$output" = "deb" ]
}

@test "aucun canal n'est annoncé sur Fedora ou Alpine (le coeur du périmètre)" {
    printf 'ID=fedora\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ -z "$output" ]
    printf 'ID=alpine\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ -z "$output" ]
}

@test "lib/system.sh n'écrit rien : aucune mutation hors lib/manifest.sh" {
    run grep -nE '^[[:space:]]*(mv|rm|cp|mkdir|chmod|chown|ln|touch|tee)[[:space:]]' "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}

@test "lib/system.sh reste POSIX (bashismes interdits)" {
    run grep -nE 'BASH_SOURCE|\[\[|\+=|<<<|declare -|mapfile|\$\{[A-Za-z_]+\^\^' "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}
```

```bash
# tests/unit/test_system_privileges.bats
#!/usr/bin/env bats
#
# « Nivuus n'exécute jamais un sudo que l'utilisateur n'a pas demandé » ne
# devient pas faux parce que le mode entier suppose du root : le mode
# EXIGE le privilège, il ne l'ACQUIERT jamais. Ces tests tiennent la
# distinction, sans jamais être root.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "sans root, le refus arrive AVANT toute écriture" {
    NIVUUS_UID=1000 run nivuus_system_require_root "installer pour la machine"
    [ "$status" -ne 0 ]
    # Rien n'a été créé : c'est la moitié la plus importante de l'assertion.
    [ ! -e "$TMP/usr" ]
    [ ! -e "$TMP/var" ]
    [ ! -e "$TMP/etc" ]
}

@test "le refus donne la commande exacte à taper" {
    NIVUUS_UID=1000 run nivuus_system_require_root "installer pour la machine"
    [[ "$output" == *"sudo nivuus install --system"* ]]
}

@test "INVARIANT: Nivuus ne se ré-exécute JAMAIS sous sudo tout seul" {
    # Le mode d'échec qu'on refuse par principe : un « exec sudu $0 » qui
    # élèverait le privilège au nom de l'utilisateur. Le grep couvre
    # lib/system.sh, bin/nivuus et install.sh d'un coup.
    run grep -rnE '(exec|sh|bash)[[:space:]]+sudo|sudo[[:space:]]+"?\$0' \
        "$ROOT/lib/" "$ROOT/bin/nivuus" "$ROOT/install.sh"
    [ "$status" -ne 0 ]
}

@test "avec root, la fonction laisse passer sans rien dire" {
    NIVUUS_UID=0 run nivuus_system_require_root "installer pour la machine"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "nivuus_system_is_root lit NIVUUS_UID quand il est posé" {
    NIVUUS_UID=0    run nivuus_system_is_root; [ "$status" -eq 0 ]
    NIVUUS_UID=1000 run nivuus_system_is_root; [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_lib_system.bats tests/unit/test_system_privileges.bats`
Expected: FAIL — `lib/system.sh` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```sh
# lib/system.sh
# Domaine root : où vont les fichiers, et qui a le droit de les y mettre.
#
# Ce module DÉCIDE et CONSTATE. Il n'écrit rien : toute mutation, y compris
# dans /etc, passe par lib/manifest.sh -- c'est ce qui rend le mode système
# réversible à l'octet près, et un test l'interdit mécaniquement.
#
# Tous les chemins sont paramétrables, non par goût de la configuration mais
# parce que c'est la seule façon de prouver cette couche sur une PR, sans
# conteneur et sans root.

: "${NIVUUS_SYSTEM_PREFIX:=/usr/local}"
: "${NIVUUS_SYSTEM_STATE_DIR:=/var/lib/nivuus}"
: "${NIVUUS_ETC_DIR:=/etc}"

# Le préfixe porte la RACINE FHS, pas l'arbre : les trois chemins qui en
# dérivent doivent bouger ensemble. Un test qui déplacerait l'arbre sans
# déplacer le lien prouverait une configuration qui n'existe pas.
nivuus_system_tree()      { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/share/nivuus-shell"; }
nivuus_system_bin()       { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/bin/nivuus"; }
nivuus_system_man()       { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/share/man/man1/nivuus.1"; }

# /var/lib et non /etc/nivuus-shell : même raison qu'au chantier 1 pour
# ~/.local/state -- le journal ne doit pas vivre dans ce qu'il doit pouvoir
# supprimer, sinon une installation cassée est irréparable.
nivuus_system_state_dir() { printf '%s\n' "$NIVUUS_SYSTEM_STATE_DIR"; }

nivuus_system_skel()      { printf '%s\n' "$NIVUUS_ETC_DIR/skel/.zshrc"; }
nivuus_system_dropin()    { printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc.d/10-nivuus.zsh"; }

# Il n'existe PAS de zshrc.d standard, et le fichier lu par tout zsh
# interactif dépend du --enable-etcdir de compilation : /etc/zsh/zshrc
# (Debian, Ubuntu, Arch) ou /etc/zshrc (Fedora, RHEL, macOS). On choisit
# sur l'existence du répertoire -- et la Task 18 ne CROIT pas ce choix :
# elle le vérifie en lançant un vrai zsh interactif.
nivuus_system_global_rc() {
    if [ -d "$NIVUUS_ETC_DIR/zsh" ]; then
        printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc"
    else
        printf '%s\n' "$NIVUUS_ETC_DIR/zshrc"
    fi
}

# $NIVUUS_UID : le crochet qui rend le refus de privilège testable sans
# privilège. En production il n'est jamais posé et `id -u` fait foi.
nivuus_system_is_root() {
    [ "${NIVUUS_UID:-$(id -u)}" -eq 0 ]
}

# EXIGER du root n'est pas EN ACQUÉRIR. Aucun « exec sudo "$0" » ici, ni
# nulle part : on refuse, on donne la commande, l'humain décide.
nivuus_system_require_root() {
    nivuus_system_is_root && return 0
    log_error "L'opération « ${1:-cette opération} » écrit dans $NIVUUS_SYSTEM_PREFIX et $NIVUUS_ETC_DIR : elle exige root."
    log_error "Rien n'a été écrit. Relance :"
    log_error "  sudo nivuus install --system"
    log_error "Pour auditer d'abord, sans aucun privilège :"
    log_error "  nivuus install --system --dry-run"
    return 1
}

# Une installation faite par l'ancien --system (avant 8261f77) a laissé un
# arbre complet dans /etc/nivuus-shell, SANS manifeste, donc sans
# réversibilité possible. On le NOMME. On ne le supprime jamais : on ne
# restaure pas ce qu'on n'a pas sauvegardé.
nivuus_system_legacy_tree() {
    _legacy="$NIVUUS_ETC_DIR/nivuus-shell"
    [ -d "$_legacy" ] || return 1
    # Un répertoire vide (ou la future configuration de site) n'est pas un
    # arbre hérité : la signature, c'est config/00-core.zsh.
    [ -f "$_legacy/config/00-core.zsh" ] || return 1
    printf '%s\n' "$_legacy"
}

# Sur Debian et Ubuntu, apt install ./nivuus-shell_*.deb couvre 90 % de ce
# que --system apporte, et le couvre MIEUX (inventaire dpkg, dpkg -V, purge
# transactionnelle). On le dit avant d'écrire (Task 9). Ailleurs -- Fedora,
# RHEL, openSUSE, Alpine, conteneurs -- il n'y a rien à recommander : c'est
# exactement la raison d'être de ce mode.
nivuus_system_package_channel() {
    _id="$(nivuus_detect_distro)"
    _like="$(nivuus_detect_distro_like)"
    case "$_id" in
        debian|ubuntu|raspbian|linuxmint|pop) printf 'deb\n'; return 0 ;;
    esac
    case " $_like " in
        *" debian "*|*" ubuntu "*) printf 'deb\n'; return 0 ;;
    esac
    return 0
}
```

Et dans `bin/nivuus`, après `. "$NIVUUS_SRC_ROOT/lib/detect.sh"` :

```bash
. "$NIVUUS_SRC_ROOT/lib/system.sh"
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_lib_system.bats tests/unit/test_system_privileges.bats
bats tests/unit/test_lib_posix.bats           # lib/system.sh est POSIX
bats tests/e2e/test_nivuus_cli.bats           # bin/nivuus démarre toujours
sh -n lib/system.sh
```
Expected: PASS (16 nouveaux tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/system.sh bin/nivuus tests/unit/test_lib_system.bats \
        tests/unit/test_system_privileges.bats tests/baseline-counts.tsv
git commit -m "feat(system): paths, environment hooks and privilege refusal"
```

---

### Task 5: modes imposés — l'umask sous `sudo` ne décide de rien

**Files:**
- Modify: `lib/manifest.sh` (`_nivuus_place`, `nivuus_mkdir_p`, ajout de `_nivuus_enforce_modes`)
- Modify: `lib/system.sh` (ajout de `nivuus_system_restorecon`)
- Create: `tests/unit/test_manifest_modes.bats`

**Interfaces:**
- Produces : `NIVUUS_INSTALL_DIR_MODE`, `NIVUUS_INSTALL_FILE_MODE`, `NIVUUS_INSTALL_OWNER` — trois variables lues par le **seul écrivain du projet** ; `nivuus_system_restorecon <chemin…>`.
- Consumers: Task 7.

**Le bug réel que cette tâche ferme, et il n'est pas hypothétique.** `_nivuus_place` fait `cp -p "$src" "$dst"` (`lib/manifest.sh:346`). `-p` préserve le mode **et le propriétaire** quand on est root. Une installation système lancée par `sudo nivuus install --system` depuis un checkout appartenant à `maxime` poserait donc `/usr/local/share/nivuus-shell` **appartenant à `maxime`** — un arbre système que son propriétaire peut réécrire, et que l'auto-update de son shell considérerait comme inscriptible. Le garde-fou d'inscriptibilité de la partie A (Task A5) serait contourné **par l'installation elle-même**. Et sans les colonnes uid/gid de la Task 1, aucun test ne le verrait.

Le second mode d'échec est celui que la spec nomme : `sudo` avec `umask 077` produit un arbre `0700` que **personne** ne peut lire — une installation « réussie » qui casse tous les shells de la machine.

**Pourquoi dans `lib/manifest.sh` et pas ailleurs.** C'est la seule bibliothèque autorisée à écrire. Normaliser les modes après coup depuis `lib/system.sh` violerait la règle centrale du projet et, pire, produirait une fenêtre pendant laquelle les fichiers sont dans le mauvais état. Les trois variables sont **vides par défaut** : le mode utilisateur ne change pas d'un octet.

**`restorecon` est une exception, assumée et bornée.** Il ne crée ni ne supprime rien : il **rétablit l'étiquette que la politique SELinux prescrit déjà** pour ce chemin. Il n'a donc rien à journaliser (le retrait du fichier emporte l'étiquette). Son absence est signalée, jamais fatale — c'est un `command -v` et un message.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_manifest_modes.bats
#!/usr/bin/env bats
#
# Une installation « réussie » que personne ne peut lire est un échec plus
# coûteux qu'un refus : elle casse tous les shells de la machine, et elle
# le fait après avoir dit « OK ». L'umask de l'administrateur ne décide de
# rien ; les modes finaux sont imposés.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/manifest.sh"
    printf 'contenu\n' > "$TMP/src"
    printf '#!/bin/sh\n' > "$TMP/exec"; chmod 700 "$TMP/exec"
    nivuus_manifest_begin system "$TMP/tree"
}

teardown() { rm -rf "$TMP"; }

@test "sans les crochets, rien ne change (le mode utilisateur est intact)" {
    umask 077
    nivuus_install_file "$TMP/src" "$TMP/tree/fichier"
    # cp -p a préservé le mode de la source : comportement historique.
    [ "$(fs_perms "$TMP/tree/fichier")" = "$(fs_perms "$TMP/src")" ]
}

@test "NIVUUS_INSTALL_FILE_MODE impose le mode, quel que soit l'umask" {
    umask 077
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/src" "$TMP/tree/fichier"
    [ "$(fs_perms "$TMP/tree/fichier")" = "644" ]
}

@test "un exécutable reste exécutable, et lisible par tous" {
    umask 077
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/exec" "$TMP/tree/bin/nivuus"
    [ "$(fs_perms "$TMP/tree/bin/nivuus")" = "755" ]
}

@test "les répertoires créés en chemin reçoivent le mode imposé" {
    umask 077
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/src" "$TMP/tree/a/b/fichier"
    [ "$(fs_perms "$TMP/tree/a")" = "755" ]
    [ "$(fs_perms "$TMP/tree/a/b")" = "755" ]
}

@test "nivuus_mkdir_p honore le mode imposé" {
    umask 077
    NIVUUS_INSTALL_DIR_MODE=755 nivuus_mkdir_p "$TMP/tree/x/y"
    [ "$(fs_perms "$TMP/tree/x/y")" = "755" ]
}

@test "nivuus_write_file honore le mode imposé" {
    umask 077
    printf 'bloc\n' | NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_write_file "$TMP/tree/etc/skel-zshrc"
    [ "$(fs_perms "$TMP/tree/etc/skel-zshrc")" = "644" ]
}

@test "en --dry-run, aucun mode n'est appliqué parce que rien n'est écrit" {
    NIVUUS_DRY_RUN=1 NIVUUS_INSTALL_FILE_MODE=644 \
        nivuus_install_file "$TMP/src" "$TMP/tree/rien"
    [ ! -e "$TMP/tree/rien" ]
}

@test "NIVUUS_INSTALL_OWNER échoue en silence quand on n'est pas root" {
    # Un test unitaire tourne sans privilège : chown DOIT être non fatal,
    # sinon toute la couche PR devient inexécutable. Le vrai chown est
    # prouvé par tests/ci/run-system-target.sh, en root, dans un conteneur.
    run env NIVUUS_INSTALL_OWNER=root:root NIVUUS_INSTALL_FILE_MODE=644 \
        bash -c ". '$ROOT/lib/log.sh'; . '$ROOT/lib/manifest.sh'
                 NIVUUS_STATE_DIR='$TMP/state2' nivuus_manifest_begin system '$TMP/t2'
                 nivuus_install_file '$TMP/src' '$TMP/t2/f'"
    [ "$status" -eq 0 ]
    [ -f "$TMP/t2/f" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_manifest_modes.bats`
Expected: FAIL sur tous les tests qui posent un crochet : `cp -p` a préservé `700`/`600`, pas `644`/`755`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/manifest.sh`, ajouter avant `_nivuus_place` :

```sh
# Modes et propriétaire IMPOSÉS, jamais hérités de l'umask ni de la source.
#
# Deux modes d'échec réels, tous deux invisibles en test non-root :
#   1. « cp -p » préserve le propriétaire quand on est root : un sudo lancé
#      depuis un checkout appartenant à quelqu'un poserait /usr/local/share
#      appartenant à cette personne -- donc inscriptible par elle, donc
#      contournant le garde-fou d'inscriptibilité de l'auto-update.
#   2. Un sudo avec umask 077 produirait un arbre 0700 que PERSONNE ne peut
#      lire : une installation « réussie » qui casse tous les shells.
#
# Les trois variables sont VIDES par défaut : le mode utilisateur ne change
# pas d'un octet.
_nivuus_enforce_modes() {
    local path="$1" kind="${2:-file}"
    [ -n "${NIVUUS_DRY_RUN:-}" ] && return 0
    [ -e "$path" ] || return 0
    if [ "$kind" = "dir" ]; then
        [ -n "${NIVUUS_INSTALL_DIR_MODE:-}" ] && chmod "$NIVUUS_INSTALL_DIR_MODE" "$path" 2>/dev/null
    else
        if [ -x "$path" ]; then
            # Un exécutable reste exécutable : le mode fichier imposé ne doit
            # pas transformer bin/nivuus en fichier de données.
            [ -n "${NIVUUS_INSTALL_DIR_MODE:-}" ] && chmod "$NIVUUS_INSTALL_DIR_MODE" "$path" 2>/dev/null
        else
            [ -n "${NIVUUS_INSTALL_FILE_MODE:-}" ] && chmod "$NIVUUS_INSTALL_FILE_MODE" "$path" 2>/dev/null
        fi
    fi
    # chown échoue sans privilège : NON FATAL, sinon toute la couche de
    # tests unitaires (qui tourne sans root) deviendrait inexécutable. Le
    # vrai chown est prouvé en conteneur, en root, par run-system-target.sh.
    [ -n "${NIVUUS_INSTALL_OWNER:-}" ] && chown "$NIVUUS_INSTALL_OWNER" "$path" 2>/dev/null
    return 0
}
```

Dans `nivuus_mkdir_p`, après `mkdir -p "$dir"`, appliquer le mode à **chaque niveau créé** (jamais aux niveaux préexistants — on ne modifie pas les droits de `/usr/local` ni de `/etc`) :

```sh
        mkdir -p "$dir"
        # Uniquement les niveaux que NOUS venons de créer : $missing les
        # contient exactement. Toucher aux modes de /usr/local ou de /etc,
        # qui préexistent, serait une mutation non journalisée d'un chemin
        # qui ne nous appartient pas.
        printf '%s\n' "$missing" | while IFS= read -r level; do
            [ -n "$level" ] && _nivuus_enforce_modes "$level" dir
        done
```

Dans `_nivuus_place`, juste après l'écriture (`cp -p` / `cat`) et **avant** le calcul de `new_hash` :

```sh
        _nivuus_enforce_modes "$dst" file
        new_hash="$(nivuus_hash_file "$dst")"
```

Dans `lib/system.sh` :

```sh
# SELinux : rétablit l'étiquette que la politique prescrit DÉJÀ pour ces
# chemins. Ne crée ni ne supprime rien, donc rien à journaliser -- le
# retrait du fichier emporte son étiquette. Son absence est signalée, jamais
# fatale : la majorité des cibles n'a pas SELinux du tout.
nivuus_system_restorecon() {
    if ! command -v restorecon >/dev/null 2>&1; then
        [ -d /sys/fs/selinux ] && log_warn "SELinux est actif mais restorecon est absent : étiquettes non rétablies."
        return 0
    fi
    for _p in "$@"; do
        [ -e "$_p" ] || continue
        restorecon -F -R "$_p" >/dev/null 2>&1 || log_warn "restorecon a échoué sur $_p (non fatal)."
    done
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_manifest_modes.bats
bats tests/unit/                      # 799 + nouveaux, aucun existant au rouge
rm -f config/*.zwc .zshrc.zwc
bats tests/e2e/test_reversibility.bats
```
Expected: PASS. La réversibilité utilisateur est **intacte** : sans crochet posé, `_nivuus_enforce_modes` ne fait rien.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/manifest.sh lib/system.sh tests/unit/test_manifest_modes.bats tests/baseline-counts.tsv
git commit -m "feat(manifest): enforce final modes and owner instead of inheriting umask"
```

---

### Task 6: `nivuus_install_symlink` — un lien est une mutation comme une autre

**Files:**
- Modify: `lib/manifest.sh` (`nivuus_install_symlink`, branche `SYMLINK` de `nivuus_restore_entry`)
- Create: `tests/unit/test_manifest_symlink.bats`

**Interfaces:**
- Produces : `nivuus_install_symlink <cible> <chemin_du_lien>` ; entrée `SYMLINK<TAB><chemin><TAB><cible><TAB>-` ; restauration.
- Consumers: Task 7 (`/usr/local/bin/nivuus`).

**Pourquoi une primitive et pas un `ln -s`.** `/usr/local/bin/nivuus` est un lien vers l'arbre : c'est la forme qu'attend un `PATH` standard, et c'est exactement le cas que la Task A2 du chantier packaging corrige côté lecture. Côté écriture, le projet n'a **aucune** primitive de lien — le commentaire de `fs_fingerprint` le disait : « rien dans `bin/nivuus` ni `lib/` ne crée de lien ». Ce plan est le premier à en créer un. Le faire avec un `ln -s` direct violerait « aucune écriture hors `lib/manifest.sh` » et, surtout, laisserait le lien **hors du journal** : `uninstall --system` ne le retirerait jamais.

**Les quatre règles de restauration s'appliquent, transposées.** Un `CREATE` se supprime si son hash n'a pas bougé ; un lien se supprime si **sa cible n'a pas bougé**. S'il pointe ailleurs, quelqu'un l'a changé : il survit, il est signalé, et il est enregistré comme survivant — exactement le traitement d'un fichier divergé.

**Le piège de l'écrasement.** Si un fichier ordinaire (ou un autre lien) occupe déjà le chemin, on ne l'écrase pas en silence : on le sauvegarde d'abord (`MODIFY`) ou on refuse. `/usr/local/bin/nivuus` peut très bien être un script écrit à la main par l'administrateur.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_manifest_symlink.bats
#!/usr/bin/env bats
#
# /usr/local/bin/nivuus est un lien. C'est la première mutation de type
# « lien » du projet : sans journalisation, uninstall ne le retirerait
# jamais, et l'empreinte (depuis la Task 1) le VERRAIT rester.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/manifest.sh"
    mkdir -p "$TMP/tree/bin"; printf '#!/bin/sh\n' > "$TMP/tree/bin/nivuus"
    nivuus_manifest_begin system "$TMP/tree"
}

teardown() { rm -rf "$TMP"; }

@test "le lien est créé et journalisé avec sa cible" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ -L "$TMP/usr/bin/nivuus" ]
    [ "$(readlink "$TMP/usr/bin/nivuus")" = "$TMP/tree/bin/nivuus" ]
    grep -q "SYMLINK" "$NIVUUS_MANIFEST_TMP"
}

@test "la restauration retire un lien intact" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ ! -e "$TMP/usr/bin/nivuus" ]
    [ ! -L "$TMP/usr/bin/nivuus" ]
}

@test "un lien DÉTOURNÉ vers autre chose survit et est signalé" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    ln -sf /bin/sh "$TMP/usr/bin/nivuus"
    NIVUUS_ROLLBACK_SURVIVORS="$TMP/survivants"
    run nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ -L "$TMP/usr/bin/nivuus" ]
    [ "$(readlink "$TMP/usr/bin/nivuus")" = "/bin/sh" ]
    grep -q "SYMLINK" "$TMP/survivants"
}

@test "un lien déjà absent ne fait pas échouer la restauration" {
    run nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ "$status" -eq 0 ]
}

@test "un fichier ordinaire déjà en place est sauvegardé, pas écrasé en silence" {
    mkdir -p "$TMP/usr/bin"
    printf 'script maison\n' > "$TMP/usr/bin/nivuus"
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ -L "$TMP/usr/bin/nivuus" ]
    grep -q "MODIFY" "$NIVUUS_MANIFEST_TMP"
    # La sauvegarde existe et contient le script d'origine.
    ref="$(awk -F'\t' '$1=="MODIFY"{print $4; exit}' "$NIVUUS_MANIFEST_TMP")"
    grep -q "script maison" "$NIVUUS_BACKUP_DIR/$ref"
}

@test "en --dry-run, aucun lien n'est créé" {
    NIVUUS_DRY_RUN=1 nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ ! -e "$TMP/usr/bin/nivuus" ]
}

@test "le lien réapparaît dans l'empreinte, et disparaît après restauration" {
    mkdir -p "$TMP/usr/bin"
    fs_fingerprint "$TMP/usr" > "$TMP/avant"
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    fs_fingerprint "$TMP/usr" > "$TMP/pendant"
    ! diff -q "$TMP/avant" "$TMP/pendant"
    nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    fs_fingerprint "$TMP/usr" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_manifest_symlink.bats`
Expected: FAIL — `nivuus_install_symlink: command not found`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/manifest.sh`, après `nivuus_write_file` :

```sh
# Un lien symbolique est une mutation comme une autre : journalisée avant
# d'exister, restaurée par la même règle que les autres. C'est la PREMIÈRE
# du projet (cf. le commentaire de tests/helpers/fingerprint.bash) : sans
# journal, uninstall ne la retirerait jamais, et l'empreinte -- qui voit
# désormais les liens -- le dirait.
nivuus_install_symlink() {
    local target="$1" link="$2" backup='-' existed=0

    # Le chemin peut déjà porter un script écrit à la main par
    # l'administrateur : on ne l'écrase pas en silence, on le sauvegarde.
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        existed=1
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "lierait $link -> $target"
        nivuus_manifest_record SYMLINK "$link" "$target" '-'
        return 0
    fi

    if [ "$existed" -eq 1 ]; then
        backup="$(nivuus_store_backup "$link")" || return 1
        rm -f "$link" || return 1
        nivuus_manifest_record MODIFY "$link" '-' "$backup" || return 1
    fi

    nivuus_mkdir_p "$(dirname "$link")"
    ln -sfn "$target" "$link" || return 1
    [ -n "${NIVUUS_INSTALL_OWNER:-}" ] && chown -h "$NIVUUS_INSTALL_OWNER" "$link" 2>/dev/null
    # La CIBLE tient lieu de hash : c'est tout ce qu'un lien transporte.
    nivuus_manifest_record SYMLINK "$link" "$target" '-'
}
```

Dans `nivuus_restore_entry`, ajouter la branche :

```sh
        SYMLINK)
            if [ ! -L "$path" ]; then
                # Absent, ou remplacé par un fichier ordinaire : dans les
                # deux cas, ce n'est plus notre lien. On ne touche à rien.
                [ -e "$path" ] && log_warn "$path n'est plus un lien : laissé en place."
                return 0
            fi
            current="$(readlink "$path")"
            if [ "$current" != "$hash" ]; then
                log_warn "$path pointe désormais vers $current (au lieu de $hash) : laissé en place."
                _nivuus_record_survivor SYMLINK "$path" "$hash" "$ref"
                return 0
            fi
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "retirerait le lien $path"
            else
                rm -f "$path"
            fi
            ;;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_manifest_symlink.bats
bats tests/unit/ tests/e2e/test_reversibility.bats
```
Expected: PASS (7 nouveaux tests), aucun existant au rouge.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/manifest.sh tests/unit/test_manifest_symlink.bats tests/baseline-counts.tsv
git commit -m "feat(manifest): journal and restore symlinks"
```

---

### Task 7: `nivuus install --system` — l'arbre partagé et son manifeste

**Files:**
- Modify: `bin/nivuus` (`usage`, `cmd_install`)
- Modify: `lib/manifest.sh` (`nivuus_manifest_begin` : `NIVUUS_BACKUP_DIR_MODE`, `NIVUUS_MANIFEST_MODE`)
- Modify: `lib/steps.sh` (`nivuus_step_write_origin`, `nivuus_step_install_man`)
- Create: `tests/integration/test_install_system.bats`

**Interfaces:**
- Consumes: `lib/system.sh` (Task 4), les modes imposés (Task 5), `nivuus_install_symlink` (Task 6), `lib/origin.sh` (packaging A1), `nivuus_step_copy_tree`, `nivuus_manifest_*`.
- Produces: `nivuus install --system [--dry-run] [--yes]`, l'arbre, le lien, la page de manuel, `.nivuus-origin` (`origin=system`), et `/var/lib/nivuus/manifest.tsv` avec `mode=system`.

**Ce que cette tâche installe, et ce qu'elle n'installe surtout pas.**

| Écrit | Pas écrit, et pourquoi |
|---|---|
| `/usr/local/share/nivuus-shell/` (l'arbre de release) | **aucun `~/.zshrc`**, pas même celui de `$SUDO_USER` — c'est le défaut central de l'ancien `--system` |
| `/usr/local/bin/nivuus` (lien) | **aucun `chsh`**, pour personne — root changeant le shell de connexion d'autrui est hors de question |
| `/usr/local/share/man/man1/nivuus.1` (si `doc/nivuus.1` existe) | **aucun `/etc/skel`** (Task 16, opt-in) |
| `$tree/.nivuus-origin` (`origin=system`, `channel=selfhosted`) | **aucune activation machine** (Tasks 17-18, opt-in) |
| `/var/lib/nivuus/manifest.tsv` (`mode=system`, 0644) et `backups/` (0700) | **aucun `~/.cache`, aucun `MKDIR` dans un `$HOME`** |

**`mode=system` n'est pas cosmétique.** `cmd_install` appelle `nivuus_manifest_begin user` **en dur** aujourd'hui. Le champ existe depuis le chantier 1 et n'a jamais eu de seconde valeur ; c'est lui qui permettra à `uninstall` (Task 13) et à `doctor` (Task 22) de savoir quel domaine ils manipulent, sans le déduire d'un chemin.

**`backups/` en 0700, et le manifeste en 0644.** Le store est adressé par contenu : il peut contenir la copie d'un fichier de `/etc` dont le mode d'origine était restrictif. Élargir ses droits élargirait ceux du contenu sauvegardé. Le manifeste, lui, ne contient que des chemins et des empreintes : un utilisateur non privilégié doit pouvoir lancer `nivuus doctor` et comprendre d'où vient son arbre partagé.

**Le mode minimal est forcé, et ce n'est pas un raccourci.** `--system` implique `MINIMAL=1` : pas de `chsh`, pas d'extras interactifs. Un test vérifie qu'**aucune ligne `CHSH` ne peut apparaître dans un manifeste système**.

**L'arbre hérité bloque avant d'écrire.** Si `/etc/nivuus-shell/config/00-core.zsh` existe, l'installation **refuse** : il vient de l'ancien `--system`, il n'a pas de manifeste, donc pas de réversibilité, et l'écraser rendrait la situation irréparable. La procédure manuelle est affichée (Task 23 la documente).

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_install_system.bats
#!/usr/bin/env bats
#
# L'installation système en entier, SANS root et SANS conteneur : les
# crochets de lib/system.sh déplacent /usr/local, /etc et /var/lib dans un
# répertoire temporaire. Ce qui exige vraiment root (chown, useradd, su)
# est prouvé ailleurs, par tests/ci/run-system-target.sh.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0            # « comme si » root : on ne l'est pas
    export NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1   # neutralise la reco .deb (Task 9)
    mkdir -p "$TMP/etc"
}

teardown() { rm -rf "$TMP"; }

install_system() { "$ROOT/bin/nivuus" install --system --yes "$@"; }

@test "l'arbre est posé sous /usr/local/share/nivuus-shell" {
    run install_system
    [ "$status" -eq 0 ]
    [ -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    [ -f "$TMP/usr/local/share/nivuus-shell/.zshrc" ]
    [ -x "$TMP/usr/local/share/nivuus-shell/bin/nivuus" ]
}

@test "INVARIANT: une installation pour la machine ne touche AUCUN \$HOME" {
    fs_fingerprint "$HOME" > "$TMP/avant"
    install_system
    fs_fingerprint "$HOME" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
    [ ! -f "$HOME/.zshrc" ]
    [ ! -d "$HOME/.local/state/nivuus" ]
}

@test "/usr/local/bin/nivuus est un lien vers l'arbre, et il fonctionne" {
    install_system
    [ -L "$TMP/usr/local/bin/nivuus" ]
    # Le cas que corrige la Task A2 du chantier packaging : derrière un
    # lien, NIVUUS_SRC_ROOT doit valoir l'arbre, pas /usr/local.
    run "$TMP/usr/local/bin/nivuus" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "le manifeste système vit dans /var/lib/nivuus et porte mode=system" {
    install_system
    [ -f "$TMP/var/lib/nivuus/manifest.tsv" ]
    run head -n1 "$TMP/var/lib/nivuus/manifest.tsv"
    [[ "$output" == *"mode=system"* ]]
    [[ "$output" == *"dir=$TMP/usr/local/share/nivuus-shell"* ]]
}

@test "le manifeste est lisible par tous, les sauvegardes ne le sont pas" {
    install_system
    [ "$(fs_perms "$TMP/var/lib/nivuus/manifest.tsv")" = "644" ]
    [ "$(fs_perms "$TMP/var/lib/nivuus/backups")" = "700" ]
}

@test "l'arbre est en 0755/0644 quel que soit l'umask du sudo" {
    ( umask 077; install_system )
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell")" = "755" ]
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh")" = "644" ]
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell/bin/nivuus")" = "755" ]
}

@test ".nivuus-origin déclare origin=system et channel=selfhosted" {
    install_system
    run cat "$TMP/usr/local/share/nivuus-shell/.nivuus-origin"
    [[ "$output" == *"origin=system"* ]]
    [[ "$output" == *"channel=selfhosted"* ]]
    [[ "$output" == *"prefix=$TMP/usr/local/share/nivuus-shell"* ]]
}

@test "INVARIANT: aucune ligne CHSH ne peut apparaître dans un manifeste système" {
    install_system
    run grep -c CHSH "$TMP/var/lib/nivuus/manifest.tsv"
    [ "$output" = "0" ]
}

@test "aucune entrée du manifeste système ne vise un \$HOME" {
    install_system
    run awk -F'\t' -v h="$HOME" 'NR>1 && index($2, h) == 1 { print; n++ } END { exit n>0 }' \
        "$TMP/var/lib/nivuus/manifest.tsv"
    [ "$status" -eq 0 ]
}

@test "la page de manuel est installée si elle existe dans les sources" {
    if [ ! -f "$ROOT/doc/nivuus.1" ]; then
        skip "doc/nivuus.1 arrive avec la Task A11 du chantier packaging"
    fi
    install_system
    [ -f "$TMP/usr/local/share/man/man1/nivuus.1" ]
}

@test "une seconde installation est idempotente et n'ajoute pas de doublon" {
    install_system
    n1="$(wc -l < "$TMP/var/lib/nivuus/manifest.tsv")"
    fs_fingerprint "$TMP/usr/local" > "$TMP/un"
    install_system
    fs_fingerprint "$TMP/usr/local" > "$TMP/deux"
    diff "$TMP/un" "$TMP/deux"
    n2="$(wc -l < "$TMP/var/lib/nivuus/manifest.tsv")"
    [ "$n2" -le "$((n1 * 2))" ]     # l'héritage recopie, il ne multiplie pas
}

@test "un arbre hérité /etc/nivuus-shell bloque l'installation, sans rien supprimer" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo legacy\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run install_system
    [ "$status" -ne 0 ]
    [[ "$output" == *"/etc/nivuus-shell"* ]]
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]   # jamais supprimé
    [ ! -d "$TMP/usr/local/share/nivuus-shell" ]        # rien écrit
}

@test "sans root, le refus arrive avant toute écriture" {
    NIVUUS_UID=1000 run install_system
    [ "$status" -ne 0 ]
    [[ "$output" == *"sudo nivuus install --system"* ]]
    [ ! -e "$TMP/usr/local/share/nivuus-shell" ]
    [ ! -e "$TMP/var/lib/nivuus" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/integration/test_install_system.bats`
Expected: FAIL — `Option inconnue : --system`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/manifest.sh`, `nivuus_manifest_begin`, après `mkdir -p "$NIVUUS_BACKUP_DIR"` :

```sh
        # Le store de sauvegardes peut contenir la copie d'un fichier de
        # /etc dont le mode d'origine était restrictif : élargir ses droits
        # élargirait ceux du contenu sauvegardé. Le manifeste, lui, ne
        # contient que des chemins et des empreintes -- il doit rester
        # lisible par un utilisateur non privilégié qui lance « doctor ».
        [ -n "${NIVUUS_BACKUP_DIR_MODE:-}" ] && chmod "$NIVUUS_BACKUP_DIR_MODE" "$NIVUUS_BACKUP_DIR" 2>/dev/null
```

et, juste après l'écriture de l'en-tête dans `$NIVUUS_MANIFEST_TMP` :

```sh
    [ -n "${NIVUUS_MANIFEST_MODE:-}" ] && chmod "$NIVUUS_MANIFEST_MODE" "$NIVUUS_MANIFEST_TMP" 2>/dev/null
```

Dans `lib/steps.sh` :

```sh
# Le marqueur d'origine : lu par lib/origin.sh (côté sh) et par
# config/20-autoupdate.zsh (côté zsh, relu en ligne). C'est lui qui fait
# qu'un shell utilisateur sait qu'il tourne sur un arbre qu'il ne possède
# pas -- et qu'il doit donc refuser de se mettre à jour tout seul.
nivuus_step_write_origin() {
    local dst="$1" origin="$2" channel="$3" version=''
    [ -f "$dst/.version" ] && version="$(cat "$dst/.version" 2>/dev/null)"
    printf 'origin=%s\nchannel=%s\nprefix=%s\nversion=%s\n' \
        "$origin" "$channel" "$dst" "${version:-inconnue}" \
        | nivuus_write_file "$dst/.nivuus-origin"
}

# Page de manuel : installée si elle existe dans les sources. Elle arrive
# avec la Task A11 du chantier packaging ; tant qu'elle n'est pas là, on
# ne la réinvente pas et on n'échoue pas pour autant.
nivuus_step_install_man() {
    local src="$1" dst="$2"
    [ -f "$src/doc/nivuus.1" ] || return 0
    nivuus_install_file "$src/doc/nivuus.1" "$dst"
}
```

Dans `lib/system.sh`, un **talon** pour la recommandation de canal, que la Task 8 remplace (le poser ici garde la Task 7 exécutable seule, et le commentaire empêche qu'on l'oublie) :

```sh
# TALON — remplacé par la Task 8 (« recommander le .deb là où il existe »).
# Ne dit rien, n'empêche rien : le comportement complet arrive avec son test.
nivuus_system_recommend_package() { return 0; }
```

Dans `bin/nivuus`, `cmd_install` — parsing puis bascule, **avant** toute écriture :

```bash
            --system)  SYSTEM=1 ;;
```

```bash
    # --- Mode système : le domaine root -------------------------------
    # Tout est décidé ICI, avant la première écriture : les chemins, le
    # journal, les modes, et le droit d'agir. Aucune étape ne relit ce
    # choix depuis l'environnement.
    if [ -n "${SYSTEM:-}" ]; then
        prefix="$(nivuus_system_tree)"
        NIVUUS_STATE_DIR="$(nivuus_system_state_dir)"; export NIVUUS_STATE_DIR
        # L'umask de l'administrateur ne décide de rien : un sudo en 077
        # produirait un arbre que personne ne peut lire.
        umask 022
        NIVUUS_INSTALL_DIR_MODE=755;  export NIVUUS_INSTALL_DIR_MODE
        NIVUUS_INSTALL_FILE_MODE=644; export NIVUUS_INSTALL_FILE_MODE
        NIVUUS_BACKUP_DIR_MODE=700;   export NIVUUS_BACKUP_DIR_MODE
        NIVUUS_MANIFEST_MODE=644;     export NIVUUS_MANIFEST_MODE
        nivuus_system_is_root && { NIVUUS_INSTALL_OWNER=root:root; export NIVUUS_INSTALL_OWNER; }
        # Ni chsh, ni extras interactifs : le shell de connexion d'autrui
        # ne nous regarde pas (l'admin a usermod -s et useradd -s).
        FORCE_MINIMAL=1

        legacy="$(nivuus_system_legacy_tree || true)"
        if [ -n "$legacy" ]; then
            log_error "$legacy contient une installation faite par l'ancien --system."
            log_error "Elle n'a pas de manifeste : Nivuus ne peut pas la retirer sans risque, et refuse"
            log_error "d'installer par-dessus. Procédure manuelle : voir doc/INSTALL.md, section « héritage »."
            return 1
        fi

        # La recommandation du canal de paquets (Task 8) parle AVANT le
        # refus de privilège : un administrateur sans sudo sous la main
        # doit quand même apprendre que le .deb existe.
        nivuus_system_recommend_package || { log_info "Annulé."; return 0; }

        # --dry-run n'exige rien : on doit pouvoir auditer avant d'élever.
        if [ -z "${NIVUUS_DRY_RUN:-}" ]; then
            nivuus_system_require_root "installer Nivuus pour la machine" || return 1
        fi
    fi
```

Le corps de l'installation, dans `cmd_install`, se dédouble sur un seul point (le `.zshrc` de l'utilisateur, qui n'existe pas en mode système) :

```bash
    nivuus_manifest_begin "${SYSTEM:+system}${SYSTEM:-user}" "$prefix"
    nivuus_manifest_inherit
    if [ -z "${SYSTEM:-}" ]; then
        [ -d "$HOME/.cache" ] || nivuus_manifest_record MKDIR "$HOME/.cache" '-' '-'
    fi
    if [ -n "${SYSTEM:-}" ]; then
        if ! nivuus_step_copy_tree "$NIVUUS_SRC_ROOT" "$prefix" \
            || ! nivuus_step_write_version "$NIVUUS_SRC_ROOT" "$prefix" \
            || ! nivuus_step_write_origin "$prefix" system selfhosted \
            || ! nivuus_step_install_man "$NIVUUS_SRC_ROOT" "$(nivuus_system_man)" \
            || ! nivuus_install_symlink "$prefix/bin/nivuus" "$(nivuus_system_bin)"; then
            log_error "Installation interrompue."
            nivuus_manifest_abort
            return 1
        fi
        nivuus_system_restorecon "$prefix" "$(nivuus_system_bin)"
    else
        …  # chemin utilisateur existant, inchangé
    fi
```

et la question du `chsh` devient :

```bash
    if [ -z "${MINIMAL:-}" ] && [ -z "${SYSTEM:-}" ]; then
```

Message de fin, en mode système :

```bash
        log_ok "Nivuus Shell installé pour la machine dans $prefix"
        log_info "Aucun ~/.zshrc n'a été modifié : l'activation est un acte par utilisateur."
        log_info "Chacun lance, sans privilège :  nivuus enable"
```

Et dans `usage()` :

```
  nivuus install   [--dry-run] [--yes] [--prefix DIR] [--minimal|--no-minimal]
                   [--with-deps] [--verify-key EMPREINTE] [--system]
…
  --system    Installe pour TOUTE la machine (exige root) : arbre partagé
              sous /usr/local/share/nivuus-shell, inventorié dans
              /var/lib/nivuus. N'écrit dans AUCUN $HOME et ne fait de chsh
              pour personne : chaque utilisateur lance « nivuus enable ».
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/integration/test_install_system.bats
bats tests/unit/ tests/integration/
rm -f config/*.zwc .zshrc.zwc && bats tests/e2e/test_reversibility.bats
```
Expected: PASS (13 nouveaux tests), aucun existant au rouge.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/nivuus lib/manifest.sh lib/steps.sh \
        tests/integration/test_install_system.bats tests/baseline-counts.tsv
git commit -m "feat(system): install a shared tree under /usr/local with its own manifest"
```

---

### Task 8: recommander le `.deb` là où il existe — une information, pas un refus

**Files:**
- Modify: `lib/system.sh` (remplace le talon `nivuus_system_recommend_package` par `nivuus_system_package_notice`)
- Modify: `bin/nivuus` (`cmd_install` : le site d'appel devient une question)
- Create: `tests/unit/test_system_package_notice.bats`

**Interfaces:**
- Consumes: `nivuus_system_package_channel` (Task 4), `confirm` (`bin/nivuus`).
- Produces: `nivuus_system_package_notice` — imprime le message et **sort en 0 s'il y a quelque chose à dire**, en 1 sinon ; crochet `NIVUUS_SYSTEM_ASSUME_NO_PACKAGE` pour les tests.

**Pourquoi cette tâche existe.** La spec conclut, sans détour, que `--system` est **redondant à ~90 % sur Debian et Ubuntu**, et que le paquet fait mieux : inventaire tenu par `dpkg`, vérification `dpkg -V`, retrait transactionnel, `apt purge`. Une conclusion pareille ne peut pas rester dans un document : soit l'outil la dit à l'endroit où elle sert (avant d'écrire), soit elle n'a servi à rien. Et c'est **testable**, ce qui est la vraie raison de l'écrire ici plutôt que dans la documentation.

**Ce n'est pas un refus, et la nuance est le cœur de la tâche.** Un administrateur peut légitimement préférer un arbre sous `/usr/local` qu'aucune mise à jour de distribution ne touchera, ou refuser d'ajouter un paquet non officiel à son inventaire `dpkg`. Le message informe **une fois**, avant toute écriture, et la réponse par défaut est **oui** (`[Y/n]`). Transformer une information en obstacle serait un « friction zéro » retourné contre son propre principe.

**Là où il n'y a rien à recommander, on se tait.** Fedora, RHEL, openSUSE, Alpine, images de base : c'est le périmètre *propre* de `--system`, celui qu'aucun canal de paquet ne servira jamais. Un message « installe plutôt le paquet » y serait faux.

**Le talon de la Task 7 disparaît dans ce commit.** Il n'a existé que pour rendre la Task 7 exécutable seule ; le laisser serait un mensonge silencieux.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_system_package_notice.bats
#!/usr/bin/env bats
#
# « --system est redondant à ~90 % sur Debian/Ubuntu » est une conclusion de
# la spec. Une conclusion qui ne change pas le comportement de l'outil n'a
# servi à rien : ce test est la forme exécutable de cette phrase.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_OS_RELEASE="$TMP/os-release"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "sur Debian, le message nomme le paquet et ce que dpkg apporte en plus" {
    printf 'ID=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt install"* ]]
    [[ "$output" == *"dpkg"* ]]
}

@test "sur Ubuntu (ID_LIKE=debian), même message" {
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt install"* ]]
}

@test "sur Fedora, RIEN n'est dit : c'est le périmètre propre de --system" {
    printf 'ID=fedora\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "sur Alpine non plus" {
    printf 'ID=alpine\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "le message n'est PAS un refus : il n'y a ni « refusé » ni « impossible »" {
    printf 'ID=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [[ "$output" != *"refus"* ]]
    [[ "$output" != *"impossible"* ]]
}

@test "NIVUUS_SYSTEM_ASSUME_NO_PACKAGE fait taire la recommandation (crochet de test)" {
    printf 'ID=debian\n' > "$TMP/os-release"
    NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 run nivuus_system_package_notice
    [ "$status" -ne 0 ]
}

@test "le talon de la Task 7 n'existe plus" {
    run grep -n "TALON" "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}
```

Et, dans `tests/integration/test_install_system.bats`, ajouter :

```bash
@test "sur Debian, l'installation système informe du .deb avant d'écrire" {
    printf 'ID=debian\n' > "$TMP/os-release"
    unset NIVUUS_SYSTEM_ASSUME_NO_PACKAGE
    NIVUUS_OS_RELEASE="$TMP/os-release" run install_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt install"* ]]
    [ -d "$TMP/usr/local/share/nivuus-shell" ]      # informé, PAS bloqué
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_system_package_notice.bats`
Expected: FAIL — `nivuus_system_package_notice` n'existe pas ; et le test « le talon n'existe plus » échoue.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh`, remplacer le talon par :

```sh
# Sur Debian et Ubuntu, « apt install ./nivuus-shell_*.deb » couvre 90 % de
# ce que --system apporte, et le couvre MIEUX (inventaire dpkg, dpkg -V,
# purge transactionnelle). On le dit -- une fois, avant toute écriture.
#
# Ce n'est PAS un refus : un administrateur peut légitimement préférer un
# arbre sous /usr/local qu'aucune mise à jour de distribution ne touchera.
# Là où aucun canal n'existe (Fedora, RHEL, openSUSE, Alpine, images de
# base), on se tait : c'est le périmètre propre de ce mode.
#
# Sort en 0 quand il y a quelque chose à dire, en 1 sinon -- l'appelant en
# fait une question.
nivuus_system_package_notice() {
    [ -n "${NIVUUS_SYSTEM_ASSUME_NO_PACKAGE:-}" ] && return 1
    _chan="$(nivuus_system_package_channel)"
    [ -n "$_chan" ] || return 1
    case "$_chan" in
        deb)
            log_info "Nivuus est disponible en paquet sur cette distribution :"
            log_info "    apt install ./nivuus-shell_<version>_all.deb      (release GitHub)"
            log_info "Le paquet est inventorié par dpkg -- vérifiable par « dpkg -V », retiré par"
            log_info "« apt purge » -- ce que --system doit refaire lui-même dans /var/lib/nivuus."
            log_info "--system garde deux avantages : un arbre sous /usr/local qu'aucune mise à jour"
            log_info "de distribution ne touche, et les activations machine (--skel, --activate-all)."
            return 0
            ;;
    esac
    return 1
}
```

Dans `bin/nivuus`, `cmd_install`, remplacer l'appel au talon :

```bash
        if nivuus_system_package_notice; then
            confirm "Continuer avec --system quand même ?" \
                || { log_info "Annulé. Rien n'a été écrit."; return 0; }
        fi
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_system_package_notice.bats tests/integration/test_install_system.bats
```
Expected: PASS (8 nouveaux tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/system.sh bin/nivuus tests/unit/test_system_package_notice.bats \
        tests/integration/test_install_system.bats tests/baseline-counts.tsv
git commit -m "feat(system): recommend the .deb where a channel exists, without refusing"
```

---

### Task 9: `install.sh --system` délègue au lieu de refuser

**Files:**
- Modify: `install.sh` (traduction des anciens flags, aide)
- Modify: `tests/e2e/test_install_sh_compat.bats` (le test de refus devient un test de délégation)
- Create: `tests/unit/test_install_sh_system.bats`

**Interfaces:**
- Consumes: `bin/nivuus install --system` (Task 7).
- Produces: `install.sh --system` qui **transmet** le drapeau, en mode local comme en mode amorçage.

**C'est ici que le dernier vestige meurt.** `install.sh:268-271` est le seul code vivant de `--system` sur `master` : deux `printf` et un `exit 1`. Il est remplacé par une ligne de traduction, comme `--dry-run` ou `--minimal`. La ligne d'aide (`install.sh:44`, « Indisponible dans cette version ») devient la description réelle.

**Le test de `test_install_sh_compat.bats:24-27` est transformé, pas supprimé.** Il exerçait un vrai comportement (le script sort en erreur avec un message explicite). Il exerce maintenant l'autre vrai comportement : sans root, le script **refuse avant d'écrire** et nomme la commande — ce qui reste un échec, mais pour la bonne raison. Le test garde donc sa forme (`status != 0`, message explicite) et gagne une assertion : le message doit contenir `sudo nivuus install --system`, pas « pas encore disponible ».

**Le drapeau traverse aussi l'amorçage.** `curl … | sudo sh -s -- --system` doit fonctionner : `nivuus_bootstrap` passe `"$@"` au noyau extrait, donc `--system` arrive tel quel dès qu'il est dans la liste traduite. Le test le prouve avec une release servie par `file://` (`tests/helpers/release.bash`), sans réseau.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_install_sh_system.bats
#!/usr/bin/env bats
#
# install.sh ne connaît pas le mode système : il le TRANSMET. Toute logique
# de mode qui remonterait dans ce fichier serait un second endroit où la
# décision se prend -- exactement ce que le refus historique était.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "install.sh ne contient plus le message « pas encore disponible »" {
    run grep -n "pas encore disponible" "$SH"
    [ "$status" -ne 0 ]
}

@test "install.sh ne décide RIEN du mode système (il ne fait que traduire)" {
    # Aucun chemin système en dur dans le script d'amorçage : les chemins
    # vivent dans lib/system.sh, un seul endroit.
    run grep -nE '/usr/local/share/nivuus-shell|/var/lib/nivuus|/etc/skel' "$SH"
    [ "$status" -ne 0 ]
}

@test "--system est transmis au noyau voisin" {
    mkdir -p "$TMP/bin" "$TMP/lib"
    cp "$SH" "$TMP/install.sh"
    printf '' > "$TMP/lib/manifest.sh"
    # Faux noyau : il journalise ses arguments et ne fait rien d'autre.
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\n' "$TMP" > "$TMP/bin/nivuus"
    chmod +x "$TMP/bin/nivuus"
    run sh "$TMP/install.sh" --system --non-interactive
    [ "$status" -eq 0 ]
    grep -qx -- "--system" "$TMP/args"
    grep -qx -- "--yes" "$TMP/args"
}

@test "--system --dry-run est transmis lui aussi, dans le bon ordre" {
    mkdir -p "$TMP/bin" "$TMP/lib"
    cp "$SH" "$TMP/install.sh"; printf '' > "$TMP/lib/manifest.sh"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\n' "$TMP" > "$TMP/bin/nivuus"
    chmod +x "$TMP/bin/nivuus"
    run sh "$TMP/install.sh" --system --dry-run
    [ "$status" -eq 0 ]
    grep -qx -- "--system" "$TMP/args"
    grep -qx -- "--dry-run" "$TMP/args"
}

@test "l'aide décrit --system au lieu de le démentir" {
    run sh "$SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--system"* ]]
    [[ "$output" != *"Indisponible"* ]]
}

@test "install.sh reste POSIX après la modification" {
    run grep -nE 'BASH_SOURCE|\blocal\b|\[\[|\]\]|\+=|<<<|pipefail' "$SH"
    [ "$status" -ne 0 ]
    command -v dash >/dev/null 2>&1 && dash -n "$SH"
    command -v busybox >/dev/null 2>&1 && busybox ash -n "$SH"
    true
}
```

Et dans `tests/e2e/test_install_sh_compat.bats`, **remplacer** le test des lignes 24-27 par :

```bash
@test "install.sh --system refuse sans root, en nommant la commande exacte" {
    # Ce test exerçait le refus « fonctionnalité indisponible ». Il exerce
    # maintenant le refus qui reste légitime -- l'absence de privilège --
    # et vérifie qu'il donne une issue au lieu d'une impasse.
    [ "$(id -u)" -ne 0 ] || skip "ce test décrit le cas NON privilégié"
    run "$ROOT/install.sh" --system --non-interactive
    [ "$status" -ne 0 ]
    [[ "$output" == *"--system"* ]]
    [[ "$output" == *"sudo nivuus install --system"* ]]
    [[ "$output" != *"pas encore disponible"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_install_sh_system.bats tests/e2e/test_install_sh_compat.bats`
Expected: FAIL — le message « pas encore disponible » est toujours là, et `--system` n'est jamais transmis.

- [ ] **Step 3: Write minimal implementation**

Dans `install.sh`, supprimer le bloc `--system)` du refus et l'ajouter à la liste des drapeaux **transmis tels quels** :

```sh
        --dry-run|--minimal|--no-minimal|--with-deps|--yes|-y|--system)
            set -- "$@" "$arg" ;;
```

et remplacer la ligne d'aide :

```
  --system            Installe pour toute la machine (exige root).
                      Voir « nivuus install --help » et doc/INSTALL.md.
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_install_sh_system.bats
bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_installation.bats
sh -n install.sh
grep -rn "pas encore disponible" .    # -> aucun résultat
```
Expected: PASS (6 nouveaux tests, le test transformé vert).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add install.sh tests/unit/test_install_sh_system.bats \
        tests/e2e/test_install_sh_compat.bats tests/baseline-counts.tsv
git commit -m "feat(install): forward --system to the kernel instead of refusing it"
```

---

### Task 10: `--dry-run --system` complet, et sans le moindre privilège

**Files:**
- Create: `tests/integration/test_system_dry_run.bats`
- Modify: `bin/nivuus` (uniquement si une régression est constatée)

**Interfaces:**
- Consumes: Task 7.
- Produces: la **non-régression** d'une propriété déjà vraie par construction.

**Cette tâche ne construit rien : elle empêche.** `nivuus_manifest_begin` en `--dry-run` écrit déjà dans un `mktemp` et ne crée aucun état (`lib/manifest.sh:39-41`), et la Task 7 place le `nivuus_system_require_root` **derrière** un `[ -z "$NIVUUS_DRY_RUN" ]`. La propriété existe donc déjà au moment où on écrit ce test. C'est exactement pour cela qu'il faut l'écrire : une propriété vraie par accident se perd au premier refactor, en silence, et personne ne s'en aperçoit avant qu'un administrateur ne se voie réclamer `sudo` pour **lire** ce qu'un outil ferait.

C'est le pendant exact de « `curl … | sh --dry-run` sans jamais demander de privilège » : **on doit pouvoir auditer avant de décider d'élever.**

**Comment on rend le test rouge d'abord** (obligatoire, sans quoi il ne teste rien) : déplacer temporairement le `nivuus_system_require_root` avant le test de `--dry-run`, constater l'échec, remettre.

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_system_dry_run.bats
#!/usr/bin/env bats
#
# Auditer ne demande pas de privilège. Cette suite ne construit rien : elle
# interdit à une propriété déjà vraie de se perdre au prochain refactor.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    export NIVUUS_UID=1000        # explicitement NON root
}

teardown() { rm -rf "$TMP"; }

@test "--dry-run --system fonctionne sans root et sort en 0" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [ "$status" -eq 0 ]
}

@test "--dry-run --system produit le rapport COMPLET" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [[ "$output" == *"$TMP/usr/local/share/nivuus-shell"* ]]
    [[ "$output" == *"$TMP/usr/local/bin/nivuus"* ]]
    # Un rapport qui ne nomme que deux chemins n'est pas un audit.
    n="$(printf '%s\n' "$output" | grep -c "$TMP/usr/local/share/nivuus-shell")"
    [ "$n" -ge 10 ]
}

@test "--dry-run --system n'écrit RIEN, nulle part" {
    fs_fingerprint "$TMP" > "$TMP.avant"
    "$ROOT/bin/nivuus" install --system --dry-run --yes >/dev/null 2>&1
    fs_fingerprint "$TMP" > "$TMP.apres"
    diff "$TMP.avant" "$TMP.apres"
    [ ! -e "$TMP/usr" ]
    [ ! -e "$TMP/var" ]
    [ ! -e "$HOME/.local/state/nivuus" ]
}

@test "--dry-run --system ne réclame jamais sudo" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [[ "$output" != *"sudo nivuus install"* ]]
}

@test "sans --dry-run, le même appel refuse : la différence est bien le mode audit" {
    run "$ROOT/bin/nivuus" install --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"sudo nivuus install --system"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
# Casser volontairement l'ordre : le refus AVANT le test de --dry-run.
# (déplacer l'appel nivuus_system_require_root hors du « if [ -z "$NIVUUS_DRY_RUN" ] »)
bats tests/integration/test_system_dry_run.bats
# Expected: FAIL -- quatre des cinq tests refusent.
git checkout bin/nivuus
```

- [ ] **Step 3: Write minimal implementation**

Aucune, si l'ordre de la Task 7 est intact. Si le rapport `--dry-run` s'avère incomplet (moins de dix chemins nommés), c'est que `nivuus_step_copy_tree` court-circuite en dry-run : le corriger **là**, pas ici.

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/integration/test_system_dry_run.bats
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add tests/integration/test_system_dry_run.bats tests/baseline-counts.tsv
git commit -m "test(system): auditing --system never requires a privilege"
```

---

### Task 11: la sonde de fin d'installation — un arbre qu'aucun shell ne peut charger est annulé

**Files:**
- Modify: `lib/system.sh` (`nivuus_system_probe_tree`)
- Modify: `bin/nivuus` (`cmd_install`, en fin de chemin système)
- Create: `tests/integration/test_system_probe.bats`

**Interfaces:**
- Consumes: `nivuus_manifest_abort`.
- Produces: `nivuus_system_probe_tree <arbre>` — lance un zsh **non privilégié** dans un environnement vierge, exige que l'arbre se charge, sort en 1 sinon ; crochet `NIVUUS_SYSTEM_PROBE_USER`.

**Trois façons d'obtenir un arbre en place que les shells ne peuvent pas charger**, toutes réelles, toutes invisibles d'un `install` qui se contente de vérifier ses codes de retour : un `umask` restrictif sous `sudo` (couvert par la Task 5, mais on ne se croit pas sur parole), SELinux sans `restorecon`, et `/usr/local` monté `noexec` ou `nosuid` sur un parc durci. Dans les trois cas, l'installation dit « OK » et **tous les shells de la machine** cassent à la première activation.

**« Une installation qui ne peut pas être prouvée est annulée. »** C'est la règle de la spec, et elle est appliquée littéralement : `nivuus_manifest_abort` défait ce que cette installation a écrit — et **seulement** ce qu'elle a écrit, grâce à la marque post-héritage déjà en place dans `lib/manifest.sh`, qui protège une installation précédente ayant réussi.

**Pourquoi un utilisateur non privilégié.** Root peut lire un arbre `0700` : sonder en root prouverait exactement ce qu'on ne cherche pas. La sonde utilise `nobody` s'il existe (c'est le cas sur toutes les cibles de la matrice), sinon l'utilisateur courant, en le disant. La spec ne tranche pas ce point : il est comblé ici et signalé en fin de plan.

**Le `$HOME` de la sonde est un temporaire jetable**, jamais celui de quelqu'un : le mode système ne lit aucun `$HOME`, y compris pour se tester lui-même.

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_system_probe.bats
#!/usr/bin/env bats
#
# Une installation « réussie » que personne ne peut charger est le mode
# d'échec le plus coûteux de ce chantier : elle casse tous les shells de la
# machine APRÈS avoir affiché OK. On ne se croit donc pas sur parole -- on
# charge réellement l'arbre, depuis un environnement non privilégié.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    export NIVUUS_SYSTEM_PROBE_USER=''      # sonder en tant que soi-même
}

teardown() { rm -rf "$TMP"; }

@test "un arbre sain passe la sonde" {
    "$ROOT/bin/nivuus" install --system --yes
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    run nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    [ "$status" -eq 0 ]
}

@test "un arbre illisible échoue à la sonde" {
    "$ROOT/bin/nivuus" install --system --yes
    chmod 000 "$TMP/usr/local/share/nivuus-shell/.zshrc"
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    [ "$(id -u)" -ne 0 ] || skip "root lit tout : la sonde n'a de sens que non privilégiée"
    run nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    [ "$status" -ne 0 ]
}

@test "la sonde utilise un HOME jetable, jamais celui de quelqu'un" {
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    "$ROOT/bin/nivuus" install --system --yes
    before="$(ls -A "$HOME" | wc -l)"
    nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    after="$(ls -A "$HOME" | wc -l)"
    [ "$before" -eq "$after" ]
}

@test "une installation dont la sonde échoue est ANNULÉE par le manifeste" {
    # On simule l'arbre illisible en forçant un mode fichier impossible :
    # l'installation écrit, la sonde refuse, l'abort défait.
    [ "$(id -u)" -ne 0 ] || skip "root lit tout"
    run env NIVUUS_INSTALL_FILE_MODE=000 "$ROOT/bin/nivuus" install --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"annulée"* ]] || [[ "$output" == *"Annul"* ]]
    # L'arbre a disparu : le manifeste a rejoué ses propres entrées.
    [ ! -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    [ ! -L "$TMP/usr/local/bin/nivuus" ]
}

@test "l'échec de sonde donne le diagnostic, pas seulement le verdict" {
    [ "$(id -u)" -ne 0 ] || skip "root lit tout"
    run env NIVUUS_INSTALL_FILE_MODE=000 "$ROOT/bin/nivuus" install --system --yes
    [[ "$output" == *"umask"* ]] || [[ "$output" == *"SELinux"* ]] || [[ "$output" == *"noexec"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/integration/test_system_probe.bats`
Expected: FAIL — `nivuus_system_probe_tree` n'existe pas ; une installation illisible se termine par « installé ».

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# Charge RÉELLEMENT l'arbre, depuis un environnement vierge et non
# privilégié. Trois façons d'obtenir un arbre en place que les shells ne
# peuvent pas charger -- umask restrictif sous sudo, SELinux sans
# restorecon, /usr/local monté noexec -- et toutes les trois passent
# inaperçues d'un installeur qui ne lit que des codes de retour.
#
# Root peut lire un arbre 0700 : sonder en root prouverait exactement ce
# qu'on ne cherche pas. On sonde donc en tant que « nobody » quand il
# existe (toutes les cibles de la matrice l'ont), et on le dit sinon.
nivuus_system_probe_tree() {
    _tree="$1"
    command -v zsh >/dev/null 2>&1 || { log_warn "zsh absent : arbre non sondé."; return 0; }
    _probe_home="$(mktemp -d)" || return 1
    _as="${NIVUUS_SYSTEM_PROBE_USER-nobody}"
    if [ -n "$_as" ] && ! id "$_as" >/dev/null 2>&1; then _as=''; fi
    if [ -z "$_as" ] && nivuus_system_is_root; then
        log_warn "Aucun compte non privilégié pour la sonde : elle est moins probante en root."
    fi

    _cmd="env -i HOME=$_probe_home PATH=$PATH TERM=dumb ZDOTDIR=$_probe_home \
          zsh -ic 'source $_tree/.zshrc >/dev/null 2>&1; print -r -- \${NIVUUS_SHELL_LOADED:-none}'"
    if [ -n "$_as" ] && nivuus_system_is_root; then
        chmod 0755 "$_probe_home" 2>/dev/null
        _out="$(su -s /bin/sh "$_as" -c "$_cmd" 2>/dev/null | tail -n1)"
    else
        _out="$(sh -c "$_cmd" 2>/dev/null | tail -n1)"
    fi
    rm -rf "$_probe_home"

    [ "$_out" = "1" ] || [ "$_out" = "true" ] && return 0
    log_error "L'arbre $_tree est en place mais AUCUN shell ne peut le charger."
    log_error "Causes usuelles : umask restrictif sous sudo, SELinux sans restorecon,"
    log_error "ou $NIVUUS_SYSTEM_PREFIX monté noexec. Vérifie :  ls -ld $_tree"
    return 1
}
```

Dans `bin/nivuus`, `cmd_install`, chemin système, **après** les étapes et **avant** `nivuus_manifest_commit` :

```bash
        if [ -z "${NIVUUS_DRY_RUN:-}" ] && ! nivuus_system_probe_tree "$prefix"; then
            log_error "Installation annulée : ce qui ne peut pas être prouvé n'est pas laissé en place."
            nivuus_manifest_abort
            return 1
        fi
```

- [ ] **Step 4: Run test to verify it passes**

```bash
rm -f config/*.zwc .zshrc.zwc
bats tests/integration/test_system_probe.bats tests/integration/test_install_system.bats
```
Expected: PASS (5 nouveaux tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/system.sh bin/nivuus tests/integration/test_system_probe.bats tests/baseline-counts.tsv
git commit -m "feat(system): abort an installation no shell can actually load"
```

---

### Task 12: la garde de réentrance — non exportée, délibérément

**Files:**
- Modify: `.zshrc` (en tête)
- Create: `tests/unit/test_zshrc_reentrancy.bats`
- Test: `tests/performance/test_startup.bats` (doit rester vert, sans modification)

**Interfaces:**
- Produces: `_nivuus_sourced` (garde, non exportée), `_nivuus_source_attempts` et `_nivuus_load_count` (compteurs observables, non exportés).
- Consumers: Task 19 (étape 12 du script de preuve, INVARIANT n° 3).

**Deux mécanismes, deux rôles — et celui-ci est le second.** Le `grep` du drop-in (Task 17) **choisit** qui gagne : l'utilisateur, toujours. Il ne suffit pas, pour deux raisons concrètes. D'abord un `~/.zshrc` peut sourcer Nivuus par un autre chemin que le bloc délimité (un `source /usr/local/share/nivuus-shell/.zshrc` écrit à la main, une strophe v3.0.0 rémanente). Ensuite le drop-in est lu **avant** `~/.zshrc` : au moment où il décide, il ne peut pas savoir ce que la suite fera. La garde de réentrance **protège** ce que le `grep` ne peut pas choisir.

**Pourquoi pas `NIVUUS_SHELL_LOADED`.** Elle est posée par `config/99-cleanup.zsh` et elle est **`export`ée**. S'en servir comme garde casserait tout zsh imbriqué dans une session Nivuus : le shell fils hériterait de la variable, croirait Nivuus déjà chargé, et démarrerait **sans** Nivuus. C'est un mode d'échec silencieux et permanent (tmux, `zsh` lancé à la main, `make shell`, un `zsh -i` dans un script). La garde **doit** être locale au processus.

**Ce que ça coûte au démarrage :** deux affectations `typeset -g`, aucun fork, aucun accès disque. Le budget de 300 ms n'est pas remis en cause, et le test de performance existant le vérifie sans modification.

**Le compteur n'est pas décoratif.** `_nivuus_load_count` est ce qui rend l'INVARIANT n° 3 (« jamais de double `source` ») **observable** au lieu d'être déduit d'une absence de symptôme. L'étape 12 du script de preuve le lit.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_zshrc_reentrancy.bats
#!/usr/bin/env bats
#
# Nivuus enregistre des hooks, des widgets ZLE et des precmd : les charger
# deux fois les DOUBLE. La garde qui l'empêche doit être locale au
# processus -- une variable exportée désactiverait Nivuus dans tout zsh
# imbriqué, ce qui est pire que le problème qu'elle résout.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc "$ROOT/.zshrc.zwc"
}

teardown() { rm -rf "$TMP"; }

zrun() { zsh -c "NIVUUS_SHELL_DIR='$ROOT' ENABLE_AUTOUPDATE=false; $1"; }

@test "sourcer deux fois ne charge qu'une fois" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "$_nivuus_load_count"'
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "1" ]
}

@test "les deux tentatives sont bien comptées (le test précédent ne triche pas)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "$_nivuus_source_attempts"'
    [ "${lines[-1]}" = "2" ]
}

@test "INVARIANT: la garde n'est PAS exportée" {
    # Le mode d'échec qu'on refuse : un zsh imbriqué qui hériterait de la
    # garde démarrerait SANS Nivuus, en silence et pour toujours.
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "${(t)_nivuus_sourced}"'
    [[ "${lines[-1]}" != *"export"* ]]
}

@test "INVARIANT: un zsh imbriqué charge bien Nivuus (la garde ne fuit pas)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              zsh -c "NIVUUS_SHELL_DIR=$ROOT ENABLE_AUTOUPDATE=false
                      source \$NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
                      print -r -- \$_nivuus_load_count"'
    [ "${lines[-1]}" = "1" ]
}

@test "NIVUUS_SHELL_LOADED reste exportée (on ne l'a pas détournée)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "${(t)NIVUUS_SHELL_LOADED}"'
    [[ "${lines[-1]}" == *"export"* ]]
}

@test "la garde n'ajoute aucun fork au démarrage" {
    # Deux typeset -g, rien d'autre : ni command -v, ni test de fichier,
    # ni sous-shell. Le budget de 300 ms est un test bloquant du projet.
    run head -n 20 "$ROOT/.zshrc"
    [[ "$output" != *'$('* ]] || {
        # une substitution de commande dans les 20 premières lignes serait
        # un fork sur le chemin de démarrage de CHAQUE shell.
        printf 'substitution de commande en tête de .zshrc\n'; false
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc .zshrc.zwc && bats tests/unit/test_zshrc_reentrancy.bats`
Expected: FAIL — `_nivuus_load_count` est vide (aucune garde), et le second `source` recharge tout.

- [ ] **Step 3: Write minimal implementation**

En tête de `.zshrc`, **avant** `zmodload zsh/datetime` :

```zsh
# =============================================================================
# Garde de réentrance
# =============================================================================
# Une seule fois par PROCESSUS. Nivuus enregistre des hooks, des widgets ZLE
# et des precmd : les charger deux fois les double (deux prompts, deux
# suggestions, deux titres de terminal).
#
# Variable NON exportée, délibérément. NIVUUS_SHELL_LOADED (posée par
# config/99-cleanup.zsh) est export'ée : s'en servir comme garde
# désactiverait Nivuus dans tout zsh IMBRIQUÉ dans une session Nivuus --
# un mode d'échec silencieux et permanent. La garde doit rester locale au
# processus.
#
# Les deux compteurs sont ce qui rend « jamais de double source »
# OBSERVABLE plutôt que déduit d'une absence de symptôme : le script de
# preuve système les lit (INVARIANT n° 3).
typeset -g _nivuus_source_attempts=$(( ${_nivuus_source_attempts:-0} + 1 ))
if [[ -n "${_nivuus_sourced:-}" ]]; then
    return 0
fi
typeset -g _nivuus_sourced=1
typeset -g _nivuus_load_count=$(( ${_nivuus_load_count:-0} + 1 ))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
rm -f config/*.zwc .zshrc.zwc
bats tests/unit/test_zshrc_reentrancy.bats
bats tests/performance/                   # 10 tests, budget intact
./bin/benchmark | sed -n '/^Average/p'    # < 300 ms, ~35 ms attendu
zsh -n .zshrc
```
Expected: PASS (6 nouveaux tests), performance inchangée.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add .zshrc tests/unit/test_zshrc_reentrancy.bats tests/baseline-counts.tsv
git commit -m "feat(shell): non-exported re-entrancy guard, with an observable load counter"
```

---

### Task 13: `nivuus uninstall --system` — le manifeste système, et rien d'autre

**Files:**
- Modify: `bin/nivuus` (`cmd_uninstall`, `usage`)
- Modify: `lib/system.sh` (`nivuus_system_manifest_has_home`)
- Create: `tests/integration/test_uninstall_system.bats`

**Interfaces:**
- Consumes: `nivuus_manifest_rollback`, `nivuus_system_state_dir`, `nivuus_system_require_root`.
- Produces: `nivuus uninstall --system [--dry-run] [--yes] [--purge]`.

**La règle, énoncée telle que la spec l'écrit :** *`nivuus uninstall --system`, lancé en root, ne touche à aucun `$HOME`. Jamais. Il ne les lit même pas.* Il rejoue le manifeste système, et rien d'autre. Le fait qu'un humain ait tapé `sudo` ne change rien : il a consenti pour **sa machine**, pas au nom des quatorze personnes qui y ont un compte.

**Un garde-fou en plus de la discipline.** Un manifeste système qui contiendrait une entrée sous `/home` ou `/Users` est **corrompu ou fabriqué** : `install --system` n'en écrit jamais (Task 7 le teste). Plutôt que de faire confiance à cette propriété au moment le plus dangereux — un rejeu en root — `uninstall --system` **pré-scanne** le manifeste et refuse en bloc s'il en trouve une. C'est deux lignes d'`awk` contre la classe entière des scénarios « manifeste trafiqué » et « bug d'une version future ».

**Ce que ça laisse derrière, et pourquoi ce n'est pas une trace.** Des blocs `.zshrc` chez les utilisateurs activés, pointant vers un arbre disparu. Ils appartiennent à chaque utilisateur, sont inscrits à **son** manifeste, et `nivuus disable` les retire à l'octet près. La garde du bloc (`[ -r … ] && source`, chantier packaging A3) les rend **inoffensifs** : aucun shell ne casse, pour personne. Et `doctor` les nomme. C'est la contrepartie exacte du refus de parcourir `/home`, et le message de fin le dit sans compter ni scanner.

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_uninstall_system.bats
#!/usr/bin/env bats
#
# La propriété centrale du projet, vue depuis le domaine root : ce que
# l'installation a écrit est rendu à l'octet près, et RIEN d'autre n'est
# touché -- surtout pas les $HOME, qui appartiennent à d'autres.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc" "$TMP/usr/local/bin"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
}

teardown() { rm -rf "$TMP"; }

@test "INVARIANT: retrait bit-exact de /usr/local, /etc et /var/lib" {
    # Des fichiers préexistants dans les trois arbres : ils doivent survivre
    # exactement, y compris leurs modes et leurs propriétaires.
    printf 'script maison\n' > "$TMP/usr/local/bin/outil"; chmod 755 "$TMP/usr/local/bin/outil"
    printf 'zsh global\n' > "$TMP/etc/zshrc"
    mkdir -p "$TMP/var/lib/autre"; printf 'x\n' > "$TMP/var/lib/autre/etat"
    fs_fingerprint "$TMP/usr/local" > "$TMP/local.avant"
    fs_fingerprint "$TMP/etc"       > "$TMP/etc.avant"
    fs_fingerprint "$TMP/var/lib"   > "$TMP/var.avant"

    "$ROOT/bin/nivuus" install   --system --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge

    fs_fingerprint "$TMP/usr/local" > "$TMP/local.apres"
    fs_fingerprint "$TMP/etc"       > "$TMP/etc.apres"
    fs_fingerprint "$TMP/var/lib"   > "$TMP/var.apres"
    diff "$TMP/local.avant" "$TMP/local.apres"
    diff "$TMP/etc.avant"   "$TMP/etc.apres"
    diff "$TMP/var.avant"   "$TMP/var.apres"
}

@test "INVARIANT: la désinstallation système ne touche AUCUN \$HOME" {
    printf 'export PERSO=1\n' > "$HOME/.zshrc"
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$HOME" > "$TMP/home.avant"
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$HOME" > "$TMP/home.apres"
    diff "$TMP/home.avant" "$TMP/home.apres"
    grep -q "PERSO" "$HOME/.zshrc"
}

@test "le lien /usr/local/bin/nivuus disparaît (et l'empreinte le voit)" {
    "$ROOT/bin/nivuus" install --system --yes
    [ -L "$TMP/usr/local/bin/nivuus" ]
    "$ROOT/bin/nivuus" uninstall --system --yes
    [ ! -L "$TMP/usr/local/bin/nivuus" ]
    [ ! -e "$TMP/usr/local/bin/nivuus" ]
}

@test "le message dit ce qui reste, sans compter ni scanner les comptes" {
    "$ROOT/bin/nivuus" install --system --yes
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [[ "$output" == *"nivuus disable"* ]]
    [[ "$output" == *"appartiennent"* ]]
    # Aucun nombre de comptes : le compter supposerait de les lire.
    [[ "$output" != *"comptes activés"* ]]
}

@test "un manifeste système qui décrit un \$HOME est REFUSÉ en bloc" {
    "$ROOT/bin/nivuus" install --system --yes
    printf 'MODIFY\t%s/.zshrc\t-\t-\n' "$HOME" >> "$TMP/var/lib/nivuus/manifest.tsv"
    printf 'garde-moi\n' > "$HOME/.zshrc"
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"corrompu"* ]] || [[ "$output" == *"refus"* ]]
    grep -q "garde-moi" "$HOME/.zshrc"
    [ -d "$TMP/usr/local/share/nivuus-shell" ]     # rien n'a été défait non plus
}

@test "sans root, le refus arrive avant toute suppression" {
    "$ROOT/bin/nivuus" install --system --yes
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -ne 0 ]
    [ -d "$TMP/usr/local/share/nivuus-shell" ]
}

@test "--dry-run --system n'exige rien et ne défait rien" {
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$TMP/usr/local" > "$TMP/avant"
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" uninstall --system --dry-run --yes
    [ "$status" -eq 0 ]
    fs_fingerprint "$TMP/usr/local" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "un fichier système DIVERGÉ survit et est signalé" {
    "$ROOT/bin/nivuus" install --system --yes
    printf 'modifié par l administrateur\n' >> "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh"
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    grep -q "administrateur" "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh"
}

@test "sans manifeste système, la commande le dit et ne fait rien" {
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"rien à faire"* ]] || [[ "$output" == *"Aucune"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/integration/test_uninstall_system.bats`
Expected: FAIL — `Option inconnue : --system`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# Un manifeste système qui décrit un $HOME est corrompu ou fabriqué :
# install --system n'en écrit JAMAIS (un test l'interdit). Plutôt que de
# faire confiance à cette propriété au moment le plus dangereux -- un rejeu
# en root -- on la vérifie. Deux lignes d'awk contre la classe entière des
# scénarios « manifeste trafiqué » et « bug d'une version future ».
nivuus_system_manifest_has_home() {
    _m="$1"
    [ -f "$_m" ] || return 1
    awk -F"$NIVUUS_TAB" 'NR > 1 && ($2 ~ /^\/home\// || $2 ~ /^\/Users\//) { found = 1 } END { exit !found }' "$_m"
}
```

Dans `bin/nivuus`, `cmd_uninstall` — parsing `--system`, puis, avant la lecture du manifeste :

```bash
    if [ -n "${SYSTEM:-}" ]; then
        NIVUUS_STATE_DIR="$(nivuus_system_state_dir)"; export NIVUUS_STATE_DIR
        umask 022
        if [ -z "${NIVUUS_DRY_RUN:-}" ]; then
            nivuus_system_require_root "retirer l'installation système" || return 1
        fi
    fi
    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"
    NIVUUS_MANIFEST="$NIVUUS_STATE_DIR/manifest.tsv"
    NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"

    if [ -n "${SYSTEM:-}" ] && nivuus_system_manifest_has_home "$NIVUUS_MANIFEST"; then
        log_error "Le manifeste système décrit des chemins dans un \$HOME : il est corrompu."
        log_error "Nivuus refuse de le rejouer en root. Rien n'a été touché."
        log_error "Inspecte-le :  $NIVUUS_MANIFEST"
        return 1
    fi
```

Et, à la fin du chemin système, le message :

```bash
        log_ok "Arbre système retiré ($(nivuus_system_tree)), rien d'autre n'a été touché."
        log_info "Les activations par utilisateur subsistent -- elles appartiennent à chaque compte."
        log_info "Leurs shells ne casseront pas (le bloc .zshrc est gardé). Chacun peut faire :"
        log_info "  nivuus disable"
```

Dans `usage()` : `nivuus uninstall [--dry-run] [--yes] [--purge] [--system]`.

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/integration/test_uninstall_system.bats tests/integration/test_install_system.bats
bats tests/unit/ tests/integration/
rm -f config/*.zwc .zshrc.zwc && bats tests/e2e/test_reversibility.bats
```
Expected: PASS (9 nouveaux tests), réversibilité utilisateur intacte.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/nivuus lib/system.sh tests/integration/test_uninstall_system.bats tests/baseline-counts.tsv
git commit -m "feat(system): uninstall replays the system manifest and never touches a HOME"
```

---

### Task 14: `origin=system` consommé — pas d'auto-update dans les shells des utilisateurs

**Files:**
- Modify: `config/20-autoupdate.zsh`
- Modify: `bin/nivuus` (`cmd_update`)
- Modify: `lib/origin.sh` (chantier packaging A1 — ajout de `nivuus_origin_is_managed`)
- Create: `tests/unit/test_autoupdate_system_mode.bats`
- Create: `tests/integration/test_update_system_message.bats`

**Interfaces:**
- Consumes: `.nivuus-origin` posé par la Task 7, `_nivuus_origin` (packaging A4, relu en ligne côté zsh).
- Produces: refus d'auto-update quand `origin != source` ; message de `nivuus update` **dérivé de `origin`**, jamais deviné ; **code de sortie 0**.

**Pourquoi cette tâche est dans le groupe 1 et non dans le groupe 4.** Les étapes 6 et 7 du script de preuve (la commande `update` d'alice, et l'absence de `~alice/.nivuus-shell-last-update-check` après trois shells) font partie de la **sortie de la phase 1** telle que la spec la définit. Elles exercent ce code. L'écrire plus tard obligerait soit à retarder deux étapes du script, soit à y poser des assertions vouées à échouer — deux façons de casser le TDD. Le **contenu** de `sudo nivuus update` (la réinstallation vérifiée) reste, lui, en phase 4 (Task 21) : ici, seuls le **refus** et le **message** existent.

**Un seul test au lieu de deux.** Le chantier packaging introduit `_nivuus_is_package_install`. `origin=system` n'est **pas** `package` : le message diffère (l'administrateur a une commande, l'utilisateur d'un paquet a son gestionnaire), mais la décision est la même. La condition devient `_nivuus_origin != source` — un `[[ -r ]]` au démarrage, inchangé, et **aucun** coût ajouté pour les installations existantes, qui n'ont pas de marqueur du tout.

**Les trois arguments contre l'auto-update, examinés un par un** (§ 5.2 de la spec) : « sans root, échec silencieux hebdomadaire » **s'applique** — d'où la désactivation dans les shells utilisateurs ; « `dpkg -V` diverge » **ne s'applique pas** (aucun gestionnaire ne revendique `/usr/local`) ; « le gestionnaire fait déjà ce travail » **ne s'applique pas** (il n'y en a pas). D'où la dissymétrie assumée : l'utilisateur non, l'administrateur oui.

**Code de sortie 0.** L'utilisateur a posé une question légitime et reçoit la réponse exacte. Un code non nul ferait crier les scripts et les tâches planifiées sans rien apprendre à personne.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_autoupdate_system_mode.bats
#!/usr/bin/env bats
#
# Un updater destructif ne doit pas s'exécuter là où il détruirait autre
# chose que lui-même. Sur un arbre système, il écrirait en root, hors
# manifeste, dans le domaine root -- ou échouerait silencieusement chaque
# semaine dans le shell de chaque utilisateur.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    mkdir -p "$TMP/tree"
    cp -r "$ROOT/config" "$TMP/tree/"
    rm -f "$TMP"/tree/config/*.zwc
    printf 'origin=system\nchannel=selfhosted\nprefix=%s\nversion=3.1.4\n' "$TMP/tree" \
        > "$TMP/tree/.nivuus-origin"
}

teardown() { rm -rf "$TMP"; }

zsrc() { zsh -c "NIVUUS_SHELL_DIR='$TMP/tree' ENABLE_AUTOUPDATE=false
                 source '$TMP/tree/config/20-autoupdate.zsh'; $1"; }

@test "_nivuus_origin lit system dans le marqueur" {
    run zsrc 'print -r -- "$(_nivuus_origin)"'
    [ "${lines[-1]}" = "system" ]
}

@test "l'absence de marqueur vaut toujours source (aucune installation existante ne change)" {
    rm -f "$TMP/tree/.nivuus-origin"
    run zsrc 'print -r -- "$(_nivuus_origin)"'
    [ "${lines[-1]}" = "source" ]
}

@test "INVARIANT: aucune sonde de mise à jour dans un shell sur arbre système" {
    run zsh -c "NIVUUS_SHELL_DIR='$TMP/tree' ENABLE_AUTOUPDATE=true
                source '$TMP/tree/config/20-autoupdate.zsh'
                print -r -- done"
    [ "$status" -eq 0 ]
    # La sonde observable : le fichier d'horodatage n'est jamais écrit.
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "nivuus-update sort en 0 et donne la commande de l'administrateur" {
    run zsrc 'nivuus-update'
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo nivuus update"* ]]
    [[ "$output" == *"$TMP/tree"* ]]
}

@test "le message nomme aussi la sortie vers une installation personnelle" {
    run zsrc 'nivuus-update'
    [[ "$output" == *"install.sh"* ]]
}

@test "le message est DÉRIVÉ de origin, pas deviné : channel apparaît" {
    run zsrc 'print -r -- "$(_nivuus_origin_channel)"'
    [ "${lines[-1]}" = "selfhosted" ]
}

@test "en mode source, rien ne change (non-régression du chemin historique)" {
    rm -f "$TMP/tree/.nivuus-origin"
    run zsrc 'print -r -- "$(_nivuus_is_managed_install && print oui || print non)"'
    [ "${lines[-1]}" = "non" ]
}
```

```bash
# tests/integration/test_update_system_message.bats
#!/usr/bin/env bats
#
# bin/nivuus update doit répondre SANS déléguer à « zsh -ic », qui exige un
# shell interactif : un conteneur, une CI ou un cron n'en ont pas.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    export NIVUUS_SHELL_DIR="$TMP/usr/local/share/nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus update sur un arbre système sort en 0, sans shell interactif" {
    run env NIVUUS_UID=1000 "$ROOT/bin/nivuus" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo nivuus update"* ]]
}

@test "nivuus update ne télécharge rien" {
    # Un faux curl/wget qui journalise : s'il est appelé, le test le dit.
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\necho appelé >> %s/reseau\n' "$TMP" > "$TMP/bin/curl"
    cp "$TMP/bin/curl" "$TMP/bin/wget"; chmod +x "$TMP/bin/curl" "$TMP/bin/wget"
    PATH="$TMP/bin:$PATH" NIVUUS_UID=1000 "$ROOT/bin/nivuus" update >/dev/null
    [ ! -f "$TMP/reseau" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/unit/test_autoupdate_system_mode.bats tests/integration/test_update_system_message.bats`
Expected: FAIL — `_nivuus_is_managed_install` n'existe pas, `nivuus update` tente `exec zsh -ic`.

- [ ] **Step 3: Write minimal implementation**

Dans `config/20-autoupdate.zsh`, à côté de `_nivuus_is_package_install` (packaging A4) :

```zsh
# origin=system rejoint origin=package du côté de la DÉCISION (aucune
# mise à jour automatique) tout en gardant son propre MESSAGE : un
# administrateur a une commande à taper, un utilisateur de paquet a son
# gestionnaire. Une seule condition, deux messages.
_nivuus_is_managed_install() {
    [[ "$(_nivuus_origin)" != "source" ]]
}
```

Le troisième terme de la garde du bloc de démarrage devient `_nivuus_is_managed_install` (au lieu de `_nivuus_is_package_install`), et `nivuus-update` branche son message :

```zsh
    if _nivuus_is_managed_install; then
        local _o="$(_nivuus_origin)"
        if [[ "$_o" == "system" ]]; then
            print -r -- "Nivuus est installé pour la machine (${NIVUUS_SHELL_DIR}), en v$(_nivuus_installed_version)."
            print -r -- "Les mises à jour sont l'affaire de l'administrateur :"
            print -r -- ""
            print -r -- "    sudo nivuus update"
            print -r -- ""
            print -r -- "Pour repasser à une installation personnelle avec mises à jour automatiques :"
            print -r -- "    curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh"
        else
            …  # message du mode paquet (packaging A6), inchangé
        fi
        return 0
    fi
```

Dans `lib/origin.sh` (packaging A1) :

```sh
# Même décision, deux messages : voir config/20-autoupdate.zsh.
nivuus_origin_is_managed() {
    [ "$(nivuus_origin "$1")" != "source" ]
}
```

Dans `bin/nivuus`, `cmd_update`, **avant** le `exec zsh -ic 'nivuus-update'` :

```bash
    if [ "$(nivuus_origin "$dir")" = "system" ]; then
        # Répond SANS déléguer à un shell interactif : un conteneur, une CI
        # ou un cron n'en ont pas, et le message est le même.
        log_info "Nivuus est installé pour la machine ($dir)."
        log_info "Les mises à jour sont l'affaire de l'administrateur :"
        log_info "  sudo nivuus update"
        return 0
    fi
```

- [ ] **Step 4: Run test to verify it passes**

```bash
rm -f config/*.zwc .zshrc.zwc
bats tests/unit/test_autoupdate_system_mode.bats tests/integration/test_update_system_message.bats
bats tests/unit/test_autoupdate_*.bats            # le mode paquet n'a pas bougé
./bin/benchmark | sed -n '/^Average/p'            # < 300 ms
```
Expected: PASS (9 nouveaux tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add config/20-autoupdate.zsh bin/nivuus lib/origin.sh \
        tests/unit/test_autoupdate_system_mode.bats \
        tests/integration/test_update_system_message.bats tests/baseline-counts.tsv
git commit -m "feat(system): refuse auto-update on a system tree and answer with the admin command"
```

---

### Task 15: `tests/ci/run-system-target.sh` — deux utilisateurs réels, et les invariants 1, 2 et 4

**Files:**
- Create: `tests/ci/run-system-target.sh`
- Create: `tests/e2e/test_ci_system_target.bats` (marqué `docker`)

**Interfaces:**
- Consumes: `tests/helpers/users.bash` (Task 2), `tests/helpers/fingerprint.bash` (Task 1), `tests/ci/install-deps.sh`.
- Produces: les étapes **1 à 9** et **13 à 15** du tableau § 7.2 de la spec. Les étapes 10, 11 et 12 sont ajoutées par les Tasks 17, 19 et 20 — dans **ce même fichier**, jamais dans un second script.

**Le modèle est `tests/ci/run-target.sh`, et il est suivi à la lettre :** toute la logique de preuve dans le script, **rien** dans le YAML, rejouable en local avant tout push. C'est ce qui rend une matrice testable sans attendre une CI. Les conteneurs de `.github/matrix.json` tournent **déjà en root**, ce qui est exactement ce dont ce mode a besoin.

**Comment le rejouer en local, avant de pousser quoi que ce soit** — à faire au moins une fois sur Debian **et** une fois sur Alpine (les deux familles d'outils utilisateur) :

```bash
docker run --rm -v "$PWD:/src:ro" debian:12 sh -c '
  set -e
  cp -r /src /work && cd /work
  ./tests/ci/install-deps.sh >/dev/null
  ./tests/ci/run-system-target.sh'

docker run --rm -v "$PWD:/src:ro" alpine:3.20 sh -c '
  set -e
  cp -r /src /work && cd /work
  ./tests/ci/install-deps.sh >/dev/null
  ./tests/ci/run-system-target.sh'
```

Le montage est en **lecture seule** et le dépôt est recopié : le script installe pour de vrai dans `/usr/local` et `/etc` **du conteneur**, jamais du poste.

**Trois étapes portent un commentaire `INVARIANT:`** et la Task 16 les protège par un `grep` en CI : n° 1 (étape 3), n° 2 (étape 5), n° 4 (étape 13). L'invariant n° 3 arrive avec l'étape 12 (Task 20).

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_ci_system_target.bats
#!/usr/bin/env bats
#
# Rejoue, dans de vrais conteneurs, la preuve du mode système. Marqué
# `docker` : il crée des comptes et écrit dans /etc et /usr/local ; sa
# place est la matrice nightly, jamais une PR ni un poste.
#
# Les quatre images sont choisies, pas héritées : Fedora et Alpine sont
# exactement les cibles qu'aucun canal de paquet ne servira jamais (§ 1.1
# de la spec), donc le coeur du périmètre de --system.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

run_system_in() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c '
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-system-target.sh'
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur debian:12" {
    run run_system_in debian:12
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cible système OK"* ]]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur ubuntu:24.04" {
    run run_system_in ubuntu:24.04
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur fedora:41 (aucun canal de paquet)" {
    run run_system_in fedora:41
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur alpine:3.20 (musl, adduser BusyBox)" {
    run run_system_in alpine:3.20
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur archlinux:latest" {
    run run_system_in archlinux:latest
    [ "$status" -eq 0 ]
}

@test "le script est du sh valide (contrôle statique, sans docker)" {
    run sh -n "$ROOT/tests/ci/run-system-target.sh"
    [ "$status" -eq 0 ]
}

@test "les trois invariants de la phase 1 sont nommés dans le script" {
    # Garde-fou local, doublé en CI par la Task 16 : ces étapes ne doivent
    # pas pouvoir disparaître discrètement.
    grep -q "INVARIANT n° 1" "$ROOT/tests/ci/run-system-target.sh"
    grep -q "INVARIANT n° 2" "$ROOT/tests/ci/run-system-target.sh"
    grep -q "INVARIANT n° 4" "$ROOT/tests/ci/run-system-target.sh"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `NIVUUS_CI_DOCKER=1 bats tests/e2e/test_ci_system_target.bats`
Expected: FAIL — `tests/ci/run-system-target.sh` n'existe pas (`sh -n` échoue, et les conteneurs sortent en 127).

- [ ] **Step 3: Write minimal implementation**

```sh
#!/bin/sh
# =============================================================================
# La séquence « preuve » du mode système : deux utilisateurs réels.
# =============================================================================
# Exécuté à l'identique par .github/workflows/matrix.yml et par un rejeu
# local « docker run … ./tests/ci/run-system-target.sh ». Aucune logique de
# preuve ne vit dans le YAML : c'est ce qui rend la matrice testable avant
# tout push.
#
# EXIGE root et un conteneur JETABLE : ce script crée des comptes et écrit
# dans /etc et /usr/local. Il n'a rien à faire sur un runner ni sur un poste.
set -eu

. ./tests/helpers/users.bash
. ./tests/helpers/fingerprint.bash

users_require_root || exit 1
[ -f /.dockerenv ] || [ -n "${NIVUUS_ALLOW_UNSAFE_SYSTEM_TEST:-}" ] || {
    printf '%s\n' "Refus : ce script écrit dans /etc et /usr/local. Lance-le dans un conteneur." >&2
    exit 1
}

SRC="$(pwd)"
WORK="$(mktemp -d)"
TREE=/usr/local/share/nivuus-shell
fp() { fs_fingerprint "$1" > "$WORK/$2"; }
same() {
    if diff -u "$WORK/$1" "$WORK/$2" > "$WORK/diff.$1.$2"; then return 0; fi
    printf '%s\n' "DIVERGENCE entre $1 et $2 :" >&2
    cat "$WORK/diff.$1.$2" >&2
    exit 1
}

echo "== Étape 1 : deux utilisateurs réels et les empreintes de référence =="
mk_user alice
mk_user bob
ALICE="$(user_home alice)"; BOB="$(user_home bob)"
fp /etc            etc.0
fp /usr/local      local.0
fp /var/lib        var.0
fp "$ALICE"        alice.0
fp "$BOB"          bob.0

echo "== Étape 2 : installation système sous un umask hostile =="
# umask 077 : le cas qui produit un arbre que PERSONNE ne peut lire. Les
# modes doivent être imposés, pas hérités.
( umask 077; "$SRC/bin/nivuus" install --system --yes )
[ -d "$TREE" ] || { echo "arbre absent" >&2; exit 1; }
[ -L /usr/local/bin/nivuus ] || { echo "lien absent" >&2; exit 1; }
[ "$(fs_owner "$TREE")" = "0:0" ] || { echo "arbre non root:root" >&2; exit 1; }
[ "$(fs_perms "$TREE")" = "755" ] || { echo "arbre non 0755 (umask hérité)" >&2; exit 1; }
[ "$(fs_perms "$TREE/config/00-core.zsh")" = "644" ] || { echo "fichier non 0644" >&2; exit 1; }
[ "$(fs_perms "$TREE/bin/nivuus")" = "755" ] || { echo "exécutable non 0755" >&2; exit 1; }
[ "$(fs_perms /var/lib/nivuus/backups)" = "700" ] || { echo "backups trop ouverts" >&2; exit 1; }

echo "== Étape 3 : INVARIANT n° 1 -- l'installation machine ne touche AUCUN \$HOME =="
# C'est le point que l'ancien --system violait : il écrasait le ~/.zshrc de
# $SUDO_USER, sans sauvegarde.
fp "$ALICE" alice.1; same alice.0 alice.1
fp "$BOB"   bob.1;   same bob.0   bob.1

echo "== Étape 4 : alice active, et son shell démarre en silence =="
as_user alice "nivuus enable --yes"
as_user alice "zsh -i -c 'echo SHELL_ALICE_OK'" > "$WORK/alice.out" 2> "$WORK/alice.err"
grep -q SHELL_ALICE_OK "$WORK/alice.out"
[ -s "$WORK/alice.err" ] && { echo "stderr non vide :" >&2; cat "$WORK/alice.err" >&2; exit 1; }
as_user alice "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"

echo "== Étape 5 : INVARIANT n° 2 -- l'activation d'alice n'active pas bob =="
fp "$BOB" bob.2; same bob.0 bob.2

echo "== Étape 6 : « nivuus update » chez alice explique, et sort en 0 =="
as_user alice "nivuus update" > "$WORK/upd.out" 2>&1
grep -q "sudo nivuus update" "$WORK/upd.out"

echo "== Étape 7 : aucun updater ne s'est lancé dans les shells d'alice =="
as_user alice "zsh -i -c true"; as_user alice "zsh -i -c true"; as_user alice "zsh -i -c true"
[ -f "$ALICE/.nivuus-shell-last-update-check" ] && {
    echo "l'updater s'est exécuté sur un arbre système" >&2; exit 1; }

echo "== Étape 8 : un shell ROOT ne compile aucun .zwc dans l'arbre partagé =="
# Le cas où l'écriture RÉUSSIRAIT : root peut écrire dans /usr/local. Des
# .zwc orphelins seraient une trace qu'aucune désinstallation ne connaît.
NIVUUS_SHELL_DIR="$TREE" zsh -i -c true >/dev/null 2>&1 || true
sleep 2      # la compilation de config/99-cleanup.zsh est en arrière-plan (&!)
found="$(find "$TREE" -name '*.zwc' | head -n5)"
[ -n "$found" ] && { echo "des .zwc ont été écrits dans l'arbre système : $found" >&2; exit 1; }

echo "== Étape 9 : alice se désactive, son \$HOME redevient bit-identique =="
as_user alice "nivuus disable --yes"
fp "$ALICE" alice.9; same alice.0 alice.9

echo "== Étape 13 : INVARIANT n° 4 -- retrait bit-exact de /etc, /usr/local et /var/lib =="
as_user alice "nivuus enable --yes"      # une activation SURVIT au retrait : c'est voulu
fp "$ALICE" alice.pre13
fp "$BOB"   bob.pre13
"$SRC/bin/nivuus" uninstall --system --yes --purge
fp /etc       etc.13;   same etc.0   etc.13
fp /usr/local local.13; same local.0 local.13
fp /var/lib   var.13;   same var.0   var.13
# Et la commande n'a modifié aucun $HOME -- ni celui d'alice, encore activée.
fp "$ALICE" alice.13; same alice.pre13 alice.13
fp "$BOB"   bob.13;   same bob.pre13   bob.13

echo "== Étape 14 : le shell d'alice ne casse pas, alors que l'arbre a disparu =="
# C'est ce qui PAIE la garde « [ -r … ] && source » du bloc, et la
# contrepartie exacte de « on ne touche pas aux \$HOME ».
as_user alice "zsh -i -c 'echo APRES_RETRAIT_OK'" > "$WORK/a14.out" 2> "$WORK/a14.err"
grep -q APRES_RETRAIT_OK "$WORK/a14.out"
[ -s "$WORK/a14.err" ] && { echo "stderr non vide après retrait :" >&2; cat "$WORK/a14.err" >&2; exit 1; }

echo "== Étape 15 : doctor nomme « bloc présent, arbre absent » et donne la sortie =="
as_user alice "nivuus doctor" > "$WORK/doc.out" 2>&1 || true
grep -qi "arbre" "$WORK/doc.out"
grep -q "nivuus disable" "$WORK/doc.out"

rm -rf "$WORK"
rm_user alice; rm_user bob
echo "== Cible système OK =="
```

- [ ] **Step 4: Run test to verify it passes**

```bash
sh -n tests/ci/run-system-target.sh
NIVUUS_CI_DOCKER=1 bats tests/e2e/test_ci_system_target.bats
```
Expected: PASS (7 tests). Sur Alpine, vérifier en particulier que `adduser` et `su -l` de BusyBox se comportent comme attendu — c'est la cible qui casse en premier.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add tests/ci/run-system-target.sh tests/e2e/test_ci_system_target.bats tests/baseline-counts.tsv
git commit -m "test(ci): prove system mode with two real users in a container"
```

---

### Task 16: la CI exécute la preuve système et protège les invariants

**Files:**
- Modify: `.github/matrix.json` (clé `"system": true` sur les cibles concernées)
- Modify: `.github/workflows/matrix.yml` (job `system`, et la suite `docker` élargie)
- Modify: `.github/workflows/tests.yml` (couche PR non privilégiée, garde-fou `grep`)
- Create: `tests/unit/test_ci_system_matrix.bats`

**Interfaces:**
- Consumes: Task 15, `.github/actions/setup-tests`, `tests/ci/bats-run.sh`.
- Produces: exécution nightly + release, et l'interdiction mécanique de supprimer un invariant en silence.

**Le découpage, et son coût.** Le budget CI du projet est déjà arbitré : PR rapide, matrice la nuit. On le respecte sans exception.

| Quand | Ce qui tourne | Coût |
|---|---|---|
| **Sur PR** | `test_lib_system`, `test_system_privileges`, `test_manifest_modes`, `test_manifest_symlink`, `test_zshrc_reentrancy`, `test_system_package_notice`, `test_install_sh_system`, `test_autoupdate_system_mode`, `tests/integration/test_*system*`, plus `sh -n` sur le nouveau script | ~30 s, **aucun conteneur, aucun `useradd`** |
| **Nightly** | `run-system-target.sh` sur `debian:12`, `ubuntu:24.04`, `fedora:41`, `alpine:3.20`, `archlinux:latest` | 5 conteneurs, création de comptes et `su -l` : la partie lente |
| **Sur release** | les mêmes, bloquantes | — |
| **macOS** | rien de nouveau. `--system` y est techniquement possible mais aucun compte n'est créé sur le runner, et `/etc/skel` n'existe pas. Couverture **partielle et documentée**, à la manière du job « WSL simulé » | — |

**Pourquoi ces cinq images-là.** Fedora et Alpine sont **délibérées** : ce sont les cibles qu'aucun canal de paquet ne servira jamais, donc le cœur du périmètre de `--system` (§ 1.1). Debian et Ubuntu parce que ce sont les plateformes où l'on **recommande le `.deb`** — la recommandation doit être exercée là où elle s'affiche. Arch parce qu'elle est déjà là.

**Le garde-fou `grep` est étendu, jamais dupliqué.** `tests.yml` porte déjà l'étape « The two invariants must be present and green » pour la signature. Les quatre invariants du mode système la rejoignent. Un invariant qui peut disparaître sans que la CI le dise n'est pas un invariant : c'est un commentaire.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_ci_system_matrix.bats
#!/usr/bin/env bats
#
# Une preuve qui ne tourne nulle part est une preuve qui n'existe pas. Ces
# tests vérifient que le script de la Task 15 est réellement câblé, et que
# les invariants ne peuvent pas disparaître discrètement.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    MATRIX="$ROOT/.github/matrix.json"
    WF="$ROOT/.github/workflows"
}

@test "les cinq cibles système sont marquées dans matrix.json" {
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
    n="$(jq '[.containers[] | select(.system == true)] | length' "$MATRIX")"
    [ "$n" -eq 5 ]
    for id in debian-12 ubuntu-2404 fedora-41 alpine-320 arch; do
        jq -e --arg i "$id" '.containers[] | select(.id == $i and .system == true)' "$MATRIX" >/dev/null
    done
}

@test "la matrice nightly exécute run-system-target.sh" {
    grep -q "run-system-target.sh" "$WF/matrix.yml"
}

@test "le job système filtre sur la clé system, il ne rejoue pas toute la matrice" {
    grep -q "select(.system" "$WF/matrix.yml"
}

@test "la couche PR exécute les suites système SANS conteneur" {
    grep -q "test_lib_system.bats" "$WF/tests.yml"
    grep -q "test_system_privileges.bats" "$WF/tests.yml"
    grep -q "test_zshrc_reentrancy.bats" "$WF/tests.yml"
    # Aucun useradd ni docker dans le job de PR : la couche PR reste
    # entièrement non privilégiée.
    run grep -nE 'useradd|docker run' "$WF/tests.yml"
    [ "$status" -ne 0 ]
}

@test "tests.yml vérifie mécaniquement la présence des invariants système" {
    grep -q "INVARIANT n° 1" "$WF/tests.yml"
    grep -q "INVARIANT n° 2" "$WF/tests.yml"
    grep -q "INVARIANT n° 4" "$WF/tests.yml"
    grep -q "INVARIANT: la garde n'est PAS exportée" "$WF/tests.yml"
}

@test "le garde-fou de la signature n'a pas été remplacé, seulement étendu" {
    grep -q "a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" "$WF/tests.yml"
}

@test "le script système n'est pas exécuté sur un runner GitHub" {
    # Il écrit dans /etc et /usr/local : un runner n'est pas jetable.
    run grep -nE 'runs-on: (ubuntu|macos)-latest[^\n]*\n[^\n]*run-system-target' "$WF/matrix.yml"
    [ "$status" -ne 0 ]
    grep -q "container:" "$WF/matrix.yml"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_system_matrix.bats`
Expected: FAIL — aucune clé `system` dans `matrix.json`, aucune mention de `run-system-target.sh`.

- [ ] **Step 3: Write minimal implementation**

`.github/matrix.json` — la clé est **additive** ; `tests/unit/test_readme_badges.bats` ne lit que `.label`, rien ne casse :

```json
  "containers": [
    { "id": "ubuntu-2204", "image": "ubuntu:22.04",     "label": "Ubuntu 22.04" },
    { "id": "ubuntu-2404", "image": "ubuntu:24.04",     "label": "Ubuntu 24.04", "system": true },
    { "id": "debian-12",   "image": "debian:12",        "label": "Debian 12",    "system": true },
    { "id": "arch",        "image": "archlinux:latest", "label": "Arch Linux",   "system": true },
    { "id": "fedora-41",   "image": "fedora:41",        "label": "Fedora 41",    "system": true },
    { "id": "alpine-320",  "image": "alpine:3.20",      "label": "Alpine 3.20 (musl)", "system": true }
  ],
```

`.github/workflows/matrix.yml` — dans le job `prepare`, une sortie de plus ; puis un job dédié :

```yaml
            echo "system=$(jq -c '[.containers[] | select(.system == true)]' .github/matrix.json)"
```

```yaml
  system:
    name: Système — ${{ matrix.target.label }}
    needs: prepare
    runs-on: ubuntu-latest
    container:
      image: ${{ matrix.target.image }}
    strategy:
      fail-fast: false
      matrix:
        target: ${{ fromJSON(needs.prepare.outputs.system) }}
    steps:
      - name: BOOTSTRAP git before checkout on images that lack it
        shell: sh
        run: |
          command -v git >/dev/null 2>&1 && exit 0
          if   command -v apk     >/dev/null 2>&1; then apk add --no-cache git          # BOOTSTRAP
          elif command -v dnf     >/dev/null 2>&1; then dnf -y install git              # BOOTSTRAP
          elif command -v pacman  >/dev/null 2>&1; then pacman -Sy --noconfirm git      # BOOTSTRAP
          elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y git  # BOOTSTRAP
          fi
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      # Le conteneur EST la protection : le script refuse de tourner ailleurs.
      - name: Prove system install, activation and bit-exact removal
        run: ./tests/ci/run-system-target.sh
```

et le job `docker-tagged` ramasse la nouvelle suite :

```yaml
        run: ./tests/ci/bats-run.sh tests/e2e/test_ci_deps_script.bats \
                                    tests/e2e/test_ci_system_target.bats \
                                    tests/e2e/test_helper_users.bats
```

Ajouter `system` à la liste des `needs` du job `notify`.

`.github/workflows/tests.yml` — dans le job `e2e`, deux étapes :

```yaml
      - name: System-mode suites (unprivileged layer)
        run: |
          rm -f config/*.zwc .zshrc.zwc
          ./tests/ci/bats-run.sh tests/unit/test_lib_system.bats \
               tests/unit/test_system_privileges.bats \
               tests/unit/test_manifest_modes.bats \
               tests/unit/test_manifest_symlink.bats \
               tests/unit/test_zshrc_reentrancy.bats \
               tests/unit/test_system_package_notice.bats \
               tests/unit/test_install_sh_system.bats \
               tests/unit/test_autoupdate_system_mode.bats \
               tests/unit/test_ci_system_matrix.bats \
               tests/integration/test_install_system.bats \
               tests/integration/test_uninstall_system.bats \
               tests/integration/test_system_dry_run.bats \
               tests/integration/test_system_probe.bats \
               tests/integration/test_update_system_message.bats
          sh -n tests/ci/run-system-target.sh
```

et, dans l'étape « The two invariants must be present and green » **existante**, quatre lignes de plus :

```yaml
          # Mode système : les quatre invariants du chantier --system. Ils
          # vivent dans un script de conteneur et dans deux suites ; le grep
          # est ce qui empêche qu'on les retire pour faire passer la CI.
          grep -q "INVARIANT n° 1" tests/ci/run-system-target.sh
          grep -q "INVARIANT n° 2" tests/ci/run-system-target.sh
          grep -q "INVARIANT n° 4" tests/ci/run-system-target.sh
          grep -q "INVARIANT: la garde n'est PAS exportée" tests/unit/test_zshrc_reentrancy.bats
          grep -q "INVARIANT: une installation pour la machine ne touche AUCUN" \
            tests/integration/test_install_system.bats
          grep -q "INVARIANT: aucune ligne CHSH" tests/integration/test_install_system.bats
```

> **Note pour l'exécutant :** le grep de l'invariant n° 3 (`tests/ci/run-system-target.sh`, étape 12) est ajouté par la **Task 20**, en même temps que l'étape elle-même. Ne pas l'ajouter ici : un `grep` qui cherche une ligne qui n'existe pas encore rendrait la CI rouge sur `master`.

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/unit/test_ci_system_matrix.bats tests/unit/test_readme_badges.bats
python3 -c "import json;json.load(open('.github/matrix.json'))"
command -v actionlint >/dev/null && actionlint .github/workflows/matrix.yml .github/workflows/tests.yml
```
Expected: PASS (7 nouveaux tests), `matrix.json` valide, badges intacts.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add .github/matrix.json .github/workflows/matrix.yml .github/workflows/tests.yml \
        tests/unit/test_ci_system_matrix.bats tests/baseline-counts.tsv
git commit -m "ci(system): run the system proof nightly and guard its invariants"
```

---

# GROUPE 2 — `/etc/skel` (phase 2 de la spec)

Une seule tâche. Petite, sans risque, et dont l'essentiel du travail est **un message honnête**.

---

### Task 17: `--skel` — opt-in, et sans illusion

**Files:**
- Modify: `bin/nivuus` (`cmd_install`, `usage`)
- Modify: `lib/system.sh` (`nivuus_system_skel_supported`)
- Modify: `tests/ci/run-system-target.sh` (étape 10)
- Create: `tests/integration/test_system_skel.bats`

**Interfaces:**
- Consumes: `nivuus_zshrc_block` (packaging A3, garde comprise), `nivuus_write_file`, `count_regular_users` côté test.
- Produces: `nivuus install --system --skel`.

**Le piège, et il est historique.** `/etc/skel` n'est lu que par les outils de création de comptes (`useradd -m`, `adduser`, `pam_mkhomedir`) **au moment de la création**. Un administrateur qui provisionne une machine déjà peuplée n'obtient **rien** — et l'ancien `--system` compensait en écrasant le `~/.zshrc` de `$SUDO_USER`, sans sauvegarde. Il ne couvre pas non plus les comptes dont le `$HOME` est provisionné ailleurs : LDAP/AD avec home NFS pré-créé, `systemd-homed`, images de conteneur où les comptes existent déjà.

**D'où la décision : opt-in, et le message nomme la limite avec le nombre de comptes concernés.** Le nombre est lu dans `/etc/passwd` (uid ≥ 1000, shell non `nologin`), **jamais** en parcourant `/home` — lire un `$HOME` NFS déclenche l'automonteur, ce qui est un effet de bord réel sur un serveur.

**Le fichier obéit aux règles ordinaires du manifeste.** S'il n'existait pas : `CREATE`, supprimé au retrait seulement si son hash n'a pas bougé. S'il existait : `MODIFY` avec sauvegarde adressée par contenu et restauration à l'octet près. C'est déjà le comportement de `nivuus_write_file` : **rien à écrire de spécial**, et le test le vérifie plutôt que de le supposer.

**Sur macOS, `/etc/skel` n'existe pas.** `--skel` est **refusé avec un message**, jamais ignoré en silence : un drapeau qui ne fait rien sans le dire est la pire des réponses.

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_system_skel.bats
#!/usr/bin/env bats
#
# /etc/skel ne rattrape PAS les comptes existants. C'est le mode d'échec
# historique de cette fonctionnalité : un administrateur convaincu d'avoir
# déployé pour tout le monde alors qu'il n'a rien fait pour les quatorze
# comptes déjà là. Le message doit le dire, et le test doit le prouver.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/skel"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    # Quatorze comptes humains, comme dans l'exemple de la spec.
    : > "$TMP/passwd"
    i=1000; while [ "$i" -lt 1014 ]; do
        printf 'u%s:x:%s:%s::/home/u%s:/bin/bash\n' "$i" "$i" "$i" "$i" >> "$TMP/passwd"
        i=$((i + 1))
    done
    printf 'daemon:x:2:2::/:/usr/sbin/nologin\n' >> "$TMP/passwd"
    export NIVUUS_PASSWD_FILE="$TMP/passwd"
}

teardown() { rm -rf "$TMP"; }

@test "sans --skel, /etc/skel/.zshrc n'est PAS écrit" {
    "$ROOT/bin/nivuus" install --system --yes
    [ ! -f "$TMP/etc/skel/.zshrc" ]
}

@test "--skel écrit /etc/skel/.zshrc avec le bloc gardé" {
    "$ROOT/bin/nivuus" install --system --skel --yes
    [ -f "$TMP/etc/skel/.zshrc" ]
    grep -q ">>> nivuus shell >>>" "$TMP/etc/skel/.zshrc"
    grep -q "$TMP/usr/local/share/nivuus-shell" "$TMP/etc/skel/.zshrc"
    # La garde du chantier packaging : le shell ne casse pas si l'arbre part.
    grep -q '\[ -r ' "$TMP/etc/skel/.zshrc"
}

@test "le message NOMME la limite et donne le nombre de comptes non couverts" {
    run "$ROOT/bin/nivuus" install --system --skel --yes
    [[ "$output" == *"COMPTES CRÉÉS APRÈS"* ]]
    [[ "$output" == *"14"* ]]
    [[ "$output" == *"nivuus enable"* ]]
}

@test "le comptage lit /etc/passwd et ne parcourt JAMAIS /home" {
    # Un stat sur un $HOME NFS déclenche l'automonteur : lire n'est pas neutre.
    run grep -rnE 'ls .*/home|find .*/home' "$ROOT/bin/nivuus" "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}

@test "un /etc/skel/.zshrc préexistant est sauvegardé, puis restauré à l'octet près" {
    printf 'export SKEL_MAISON=1\n# fin\n' > "$TMP/etc/skel/.zshrc"
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --skel --yes
    grep -q "SKEL_MAISON" "$TMP/etc/skel/.zshrc"      # le contenu d'origine survit
    grep -q "nivuus shell" "$TMP/etc/skel/.zshrc"     # et le bloc s'ajoute
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "un /etc/skel/.zshrc créé par Nivuus disparaît au retrait" {
    "$ROOT/bin/nivuus" install --system --skel --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    [ ! -f "$TMP/etc/skel/.zshrc" ]
}

@test "sans /etc/skel (macOS), --skel est REFUSÉ, pas ignoré" {
    rm -rf "$TMP/etc/skel"
    run "$ROOT/bin/nivuus" install --system --skel --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"/etc/skel"* ]]
    [[ "$output" == *"n'existe pas"* ]]
    [ ! -d "$TMP/usr/local/share/nivuus-shell" ]     # refus AVANT écriture
}

@test "--skel n'écrit toujours dans AUCUN \$HOME" {
    fs_fingerprint "$HOME" > "$TMP/h.avant"
    "$ROOT/bin/nivuus" install --system --skel --yes
    fs_fingerprint "$HOME" > "$TMP/h.apres"
    diff "$TMP/h.avant" "$TMP/h.apres"
}
```

Et, dans `tests/ci/run-system-target.sh`, l'étape 10 :

```sh
echo "== Étape 10 : /etc/skel n'active QUE les comptes créés après =="
"$SRC/bin/nivuus" install --system --skel --yes
mk_user carol
CAROL="$(user_home carol)"
grep -q "nivuus shell" "$CAROL/.zshrc" || { echo "carol n'a pas hérité de /etc/skel" >&2; exit 1; }
as_user carol "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"
# Et bob, qui existait AVANT, n'a toujours rien : c'est la limite, et on
# ne prétend pas le contraire.
fp "$BOB" bob.10; same bob.0 bob.10
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/integration/test_system_skel.bats`
Expected: FAIL — `Option inconnue : --skel`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# /etc/skel n'existe pas sur macOS. Un drapeau qui ne fait rien sans le
# dire est la pire des réponses : on refuse, et on nomme le chemin.
nivuus_system_skel_supported() {
    [ -d "$(dirname "$(nivuus_system_skel)")" ]
}

# Comptes humains déjà présents : uid >= 1000, shell non nologin. Lu dans
# /etc/passwd, JAMAIS en parcourant /home -- un stat sur un $HOME NFS
# déclenche l'automonteur, ce qui est un effet de bord réel sur un serveur.
nivuus_system_existing_users() {
    awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { n++ } END { print n + 0 }' \
        "${NIVUUS_PASSWD_FILE:-/etc/passwd}" 2>/dev/null || printf '0\n'
}
```

Dans `bin/nivuus`, `cmd_install` : `--skel) SKEL=1 ;;`, un refus précoce (avec les autres refus, **avant** toute écriture) :

```bash
        if [ -n "${SKEL:-}" ] && ! nivuus_system_skel_supported; then
            log_error "$(dirname "$(nivuus_system_skel)") n'existe pas sur cette plateforme (macOS ?)."
            log_error "--skel est refusé plutôt qu'ignoré. Les comptes s'activent avec « nivuus enable »."
            return 1
        fi
```

puis, dans les étapes système, après le marqueur d'origine :

```bash
        if [ -n "${SKEL:-}" ]; then
            nivuus_zshrc_block "$prefix" '' | nivuus_write_file "$(nivuus_system_skel)" || {
                nivuus_manifest_abort; return 1; }
            log_ok "$(nivuus_system_skel) écrit."
            log_warn "Il ne s'applique QU'AUX COMPTES CRÉÉS APRÈS cette commande."
            log_warn "Les $(nivuus_system_existing_users) comptes déjà présents ne sont pas activés :"
            log_warn "chacun peut lancer « nivuus enable », ou utilise --activate-all pour toute la machine."
        fi
```

Et dans `usage()` : `--skel  (avec --system) pose /etc/skel/.zshrc : n'affecte QUE les comptes créés ensuite.`

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/integration/test_system_skel.bats
sh -n tests/ci/run-system-target.sh
NIVUUS_CI_DOCKER=1 bats tests/e2e/test_ci_system_target.bats -f debian
```
Expected: PASS (8 nouveaux tests, étape 10 verte dans le conteneur).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/nivuus lib/system.sh tests/ci/run-system-target.sh \
        tests/integration/test_system_skel.bats tests/baseline-counts.tsv
git commit -m "feat(system): opt-in --skel that names its own limitation"
```

---

# GROUPE 3 — Activation machine (phase 3 de la spec)

Trois tâches. C'est la seule partie du chantier qui touche un **fichier de la distribution**, et c'est pour cela qu'elle vient en troisième : la réversibilité d'abord, `/etc/skel` ensuite parce qu'il est sans risque, le conffile en dernier.

C'est aussi la réponse de ce chantier à la **question ouverte n° 6 du chantier packaging** (« drop-in `/etc/zsh/zshrc.d` pour l'activation par machine »). Position : le besoin est réel, mais ce n'est pas au `postinst` de le satisfaire — il n'a pas le consentement, l'utilisateur a tapé `apt install`, pas « change le shell de tout le monde ». Une commande d'administration explicite, elle, l'a. **Si l'arbitrage tranche l'inverse, ce groupe entier devient redondant et doit être retiré, pas dupliqué.**

---

### Task 18: le drop-in, et la ligne unique du rc global

**Files:**
- Modify: `lib/system.sh` (`nivuus_system_dropin_content`, `nivuus_system_rc_line`)
- Create: `tests/unit/test_dropin_content.bats`

**Interfaces:**
- Produces: le **contenu** du drop-in et la **ligne** ajoutée au rc global, testés comme du texte pur, sans rien écrire.
- Consumers: Task 19.

**Pourquoi le contenu est une tâche à part.** Il porte trois décisions qu'on doit pouvoir prouver sans conteneur, sans root et sans zsh installé : la cession à l'utilisateur, le fait que le fichier de la distribution ne reçoive **qu'une ligne**, et le marqueur qui rend l'activation vérifiable. Une tâche qui écrirait et testerait en même temps mélangerait la preuve du texte et celle de l'écriture.

**Le drop-in cède toujours à l'utilisateur.** Le `grep` sur `${ZDOTDIR:-$HOME}/.zshrc` est ce qui rend vraie la ligne « Système + install utilisateur ⇒ le bloc gagne » du tableau du § 4.3. Coût : un `grep` sur un fichier, et **seulement sur les machines qui ont opté**.

**Le fichier de la distribution ne reçoit qu'une ligne, et c'est une décision de réversibilité.** `/etc/zsh/zshrc` est un **conffile `dpkg`** : y ajouter du contenu provoquera un jour la question « conffile modifié » à une mise à jour de `zsh-common`. Retirer **une ligne connue** d'un conffile est réversible à l'octet près ; réécrire le conffile ne l'est pas. Le contenu vit donc dans un fichier à nous.

**`NIVUUS_ACTIVATED_BY=system` n'est pas décoratif** : c'est le marqueur que la sonde de la Task 19 cherche. Sans lui, « l'activation a-t-elle pris ? » ne serait pas une question qu'on peut poser à la machine.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_dropin_content.bats
#!/usr/bin/env bats
#
# Le contenu du drop-in porte trois décisions : il cède à l'utilisateur, il
# se déclare (pour être vérifiable), et il ne casse rien si l'arbre part.
# Toutes trois se prouvent sur du texte, sans root et sans zsh.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "le drop-in cède à l'utilisateur qui a son propre bloc" {
    run nivuus_system_dropin_content
    [[ "$output" == *">>> nivuus shell >>>"* ]]
    [[ "$output" == *"grep -qs"* ]]
    [[ "$output" == *'${ZDOTDIR:-$HOME}/.zshrc'* ]]
}

@test "le drop-in ne s'applique qu'aux shells interactifs" {
    run nivuus_system_dropin_content
    [[ "$output" == *"-o interactive"* ]]
}

@test "le drop-in se déclare : NIVUUS_ACTIVATED_BY=system" {
    run nivuus_system_dropin_content
    [[ "$output" == *"NIVUUS_ACTIVATED_BY=system"* ]]
}

@test "le drop-in porte la garde : un arbre absent ne casse aucun shell" {
    run nivuus_system_dropin_content
    [[ "$output" == *'[ -r '* ]]
}

@test "le drop-in pointe vers l'arbre système, jamais vers un \$HOME" {
    run nivuus_system_dropin_content
    [[ "$output" == *"$TMP/usr/local/share/nivuus-shell"* ]]
    [[ "$output" != *'/home/'* ]]
}

@test "le drop-in est du zsh valide" {
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    nivuus_system_dropin_content > "$TMP/dropin.zsh"
    run zsh -n "$TMP/dropin.zsh"
    [ "$status" -eq 0 ]
}

@test "la ligne du rc global est UNE ligne, et elle est reconnaissable" {
    run nivuus_system_rc_line
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *"10-nivuus.zsh"* ]]
    [[ "$output" == *"nivuus"* ]]
}

@test "la ligne du rc global est gardée elle aussi" {
    # Le drop-in peut disparaître (retrait partiel, image immuable) : la
    # ligne restée dans un conffile ne doit jamais casser un shell.
    run nivuus_system_rc_line
    [[ "$output" == *"[ -r "* ]]
}

@test "la ligne du rc global est du zsh valide" {
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    nivuus_system_rc_line > "$TMP/ligne.zsh"
    run zsh -n "$TMP/ligne.zsh"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_dropin_content.bats`
Expected: FAIL — `nivuus_system_dropin_content` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# Contenu du drop-in d'activation machine. Il CÈDE toujours à
# l'utilisateur : celui qui a son propre bloc dans ~/.zshrc gagne, sans
# ambiguïté. C'est ce qui rend vraie la ligne « système + installation
# utilisateur » du tableau § 4.3 de la spec.
#
# Coût : un grep sur un fichier, et SEULEMENT sur les machines qui ont
# opté pour l'activation machine. Il est mesuré par le test de budget des
# 300 ms, comme le reste.
nivuus_system_dropin_content() {
    cat <<EOF
# Activation machine de Nivuus Shell (posée par « nivuus enable --all »).
# Ne fait rien pour un utilisateur qui a sa propre activation : la sienne gagne.
if [[ -o interactive ]] && ! grep -qs '>>> nivuus shell >>>' "\${ZDOTDIR:-\$HOME}/.zshrc"; then
    export NIVUUS_SHELL_DIR="$(nivuus_system_tree)"
    export NIVUUS_ACTIVATED_BY=system
    [ -r "\$NIVUUS_SHELL_DIR/.zshrc" ] && source "\$NIVUUS_SHELL_DIR/.zshrc"
fi
EOF
}

# UNE ligne, et une seule, dans le fichier de la distribution. /etc/zsh/zshrc
# est un conffile dpkg : retirer une ligne CONNUE est réversible à l'octet
# près, réécrire le conffile ne l'est pas. Le contenu vit dans un fichier à
# nous ; ce fichier-ci ne reçoit qu'un pointeur, gardé lui aussi.
nivuus_system_rc_line() {
    printf '[ -r "%s" ] && source "%s"  # nivuus-shell (retirer avec: nivuus disable --all)\n' \
        "$(nivuus_system_dropin)" "$(nivuus_system_dropin)"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_dropin_content.bats`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add lib/system.sh tests/unit/test_dropin_content.bats tests/baseline-counts.tsv
git commit -m "feat(system): drop-in content that always yields to the user"
```

---

### Task 19: `--activate-all` — vérifiée empiriquement, ou annulée

**Files:**
- Modify: `bin/nivuus` (`cmd_install --activate-all`, `cmd_enable --all [--print]`, `cmd_disable --all`, `usage`)
- Modify: `lib/system.sh` (`nivuus_system_probe_activation`)
- Modify: `tests/ci/run-system-target.sh` (étape 11)
- Create: `tests/integration/test_system_activate_all.bats`

**Interfaces:**
- Consumes: Task 18, `nivuus_write_file`, `nivuus_manifest_abort`, `nivuus_zshrc_*`.
- Produces: `nivuus install --system --activate-all`, `nivuus enable --all [--print]`, `nivuus disable --all`.

**La décision qui structure la tâche : on ne devine pas le chemin, on le vérifie.** Après écriture, l'installeur lance un zsh **interactif** dans un environnement vierge et exige le marqueur :

```sh
probe="$(env -i HOME="$probe_home" PATH="$PATH" TERM=dumb \
         zsh -ic 'print -r -- "${NIVUUS_ACTIVATED_BY:-none}"' 2>/dev/null | tail -n1)"
[ "$probe" = "system" ] || { nivuus_manifest_abort; nivuus_die "…"; }
```

Si la preuve manque, **l'activation machine est défaite par le manifeste** et l'administrateur reçoit le chemin exact à ajouter à la main. La raison est courte : *un `/etc` modifié sans effet est pire qu'un refus — il fait croire que c'est fait.* C'est le même raisonnement que la sonde de la Task 11, appliqué à l'autre moitié du problème.

**La confirmation nomme le conffile.** Le drapeau est explicite, mais l'administrateur doit savoir **quel fichier de sa distribution** va recevoir une ligne, et que `dpkg` lui posera peut-être une question un jour. `--yes` ne supprime pas l'information : il supprime la question.

**`--print` est l'échappatoire, et elle est de premier ordre.** Ansible, images immuables, `dpkg-divert`, `/etc` sous git : beaucoup d'administrateurs veulent posséder `/etc` eux-mêmes. `nivuus enable --all --print` affiche le fichier et la ligne, **sans rien écrire**, et sort en 0. Ne pas l'offrir reviendrait à exiger qu'ils nous laissent leur `/etc`.

**`nivuus enable --all` fonctionne aussi sur un arbre posé par un paquet.** C'est le point qui fait de ce chantier le **porteur unique** de l'activation machine pour les quatre canaux : le paquet **affiche** la commande, `--system` la **porte**. Un seul code d'activation machine, testé une fois.

- [ ] **Step 1: Write the failing test**

```bash
# tests/integration/test_system_activate_all.bats
#!/usr/bin/env bats
#
# Un /etc modifié sans effet est pire qu'un refus : il fait croire que
# c'est fait. Cette suite exige la PREUVE, et l'annulation en son absence.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh"
    printf '# rc global de la distribution\n' > "$TMP/etc/zsh/zshrc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    # La sonde d'activation a besoin de lire NOTRE rc global, pas celui du
    # système hôte : ZDOTDIR ne suffit pas, on la neutralise ou on la
    # redirige selon le test (voir NIVUUS_SYSTEM_PROBE_RC).
    export NIVUUS_SYSTEM_PROBE_RC="$TMP/etc/zsh/zshrc"
}

teardown() { rm -rf "$TMP"; }

@test "sans --activate-all, ni drop-in ni ligne dans le rc global" {
    "$ROOT/bin/nivuus" install --system --yes
    [ ! -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
    run grep -c nivuus "$TMP/etc/zsh/zshrc"
    [ "$output" = "0" ]
}

@test "--activate-all pose le drop-in et UNE ligne dans le rc global" {
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
    n="$(grep -c '10-nivuus.zsh' "$TMP/etc/zsh/zshrc")"
    [ "$n" -eq 1 ]
    grep -q "rc global de la distribution" "$TMP/etc/zsh/zshrc"   # le contenu d'origine reste
}

@test "la confirmation NOMME le conffile de la distribution" {
    run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    [[ "$output" == *"conffile"* ]] || [[ "$output" == *"dpkg"* ]]
}

@test "l'activation est VÉRIFIÉE : le marqueur doit être posé pour de vrai" {
    run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"vérifi"* ]]
}

@test "sans preuve, l'activation est ANNULÉE et le rc global est rendu intact" {
    fs_fingerprint "$TMP/etc" > "$TMP/etc.avant"
    # On sabote la sonde : le drop-in ne sera jamais lu.
    run env NIVUUS_SYSTEM_PROBE_RC=/dev/null \
        "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"à la main"* ]]
    fs_fingerprint "$TMP/etc" > "$TMP/etc.apres"
    diff "$TMP/etc.avant" "$TMP/etc.apres"
}

@test "enable --all --print n'écrit RIEN et sort en 0" {
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    run "$ROOT/bin/nivuus" enable --all --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"10-nivuus.zsh"* ]]
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "enable --all fonctionne sur un arbre posé par un PAQUET" {
    # Le point qui fait de --system le porteur unique de l'activation
    # machine pour les quatre canaux.
    mkdir -p "$TMP/usr/share/nivuus-shell"
    cp -r "$ROOT/config" "$ROOT/.zshrc" "$TMP/usr/share/nivuus-shell/"
    printf 'origin=package\nchannel=deb\n' > "$TMP/usr/share/nivuus-shell/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$TMP/usr/share/nivuus-shell" "$ROOT/bin/nivuus" enable --all --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TMP/usr/share/nivuus-shell"* ]]
}

@test "disable --all retire la ligne et le drop-in, à l'octet près" {
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    "$ROOT/bin/nivuus" disable --all --yes
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "uninstall --system rend le rc global bit-identique" {
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "sans root, --activate-all refuse avant d'écrire dans /etc" {
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -ne 0 ]
    [ ! -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
}
```

Et l'étape 11 dans `tests/ci/run-system-target.sh` :

```sh
echo "== Étape 11 : activation machine -- bob est activé sans avoir rien fait =="
"$SRC/bin/nivuus" install --system --activate-all --yes
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"
# La sonde qui a servi est bien celle-là : le marqueur le prouve.
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_ACTIVATED_BY'" | grep -qx system
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/integration/test_system_activate_all.bats`
Expected: FAIL — `Option inconnue : --activate-all`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# La preuve, pas la promesse : un zsh INTERACTIF, dans un environnement
# vierge, doit voir le marqueur. Sans elle, l'écriture dans /etc est
# défaite -- un /etc modifié sans effet est pire qu'un refus, il fait
# croire que c'est fait.
#
# $NIVUUS_SYSTEM_PROBE_RC : crochet de test. En production, le zsh lancé
# lit le rc global de la machine, ce qui EST la chose à vérifier.
nivuus_system_probe_activation() {
    command -v zsh >/dev/null 2>&1 || { log_warn "zsh absent : activation non vérifiable."; return 1; }
    _probe_home="$(mktemp -d)" || return 1
    _rc_opt=''
    [ -n "${NIVUUS_SYSTEM_PROBE_RC:-}" ] && _rc_opt="ZDOTDIR=$_probe_home NIVUUS_PROBE_RC=$NIVUUS_SYSTEM_PROBE_RC"
    [ -n "${NIVUUS_SYSTEM_PROBE_RC:-}" ] && \
        printf 'source %s\n' "$NIVUUS_SYSTEM_PROBE_RC" > "$_probe_home/.zshrc"
    _out="$(env -i HOME="$_probe_home" PATH="$PATH" TERM=dumb ZDOTDIR="$_probe_home" \
            zsh -ic 'print -r -- "${NIVUUS_ACTIVATED_BY:-none}"' 2>/dev/null | tail -n1)"
    rm -rf "$_probe_home"
    [ "$_out" = "system" ]
}
```

Dans `bin/nivuus` : `--activate-all) ACTIVATE_ALL=1 ;;` dans `cmd_install`, et le bloc d'activation après les étapes système :

```bash
        if [ -n "${ACTIVATE_ALL:-}" ]; then
            rc="$(nivuus_system_global_rc)"
            log_warn "L'activation machine ajoute UNE ligne à $rc."
            log_warn "Sur Debian et Ubuntu, ce fichier est un conffile dpkg : une future mise à"
            log_warn "jour de zsh-common posera peut-être la question « conffile modifié »."
            log_warn "Pour gérer /etc toi-même :  nivuus enable --all --print"
            confirm "Activer Nivuus pour tous les shells zsh interactifs de la machine ?" \
                || { log_info "Activation machine ignorée. L'arbre reste installé."; ACTIVATE_ALL=''; }
        fi
        if [ -n "${ACTIVATE_ALL:-}" ]; then
            nivuus_system_dropin_content | nivuus_write_file "$(nivuus_system_dropin)" || {
                nivuus_manifest_abort; return 1; }
            { cat "$rc" 2>/dev/null; nivuus_system_rc_line; } | nivuus_write_file "$rc" || {
                nivuus_manifest_abort; return 1; }
            if [ -z "${NIVUUS_DRY_RUN:-}" ] && ! nivuus_system_probe_activation; then
                log_error "L'activation machine n'a produit AUCUN effet : le zsh de cette machine ne lit"
                log_error "pas $rc. Elle est annulée -- /etc est rendu tel qu'il était."
                log_error "Ajoute la ligne à la main dans le fichier que ton zsh lit réellement :"
                log_error "  $(nivuus_system_rc_line)"
                nivuus_manifest_abort
                return 1
            fi
            log_ok "Activation machine vérifiée (un zsh interactif voit NIVUUS_ACTIVATED_BY=system)."
        fi
```

`cmd_enable --all [--print]` et `cmd_disable --all` (le verbe vient du chantier packaging A9) rejouent exactement les mêmes primitives, sur un arbre déjà posé — **y compris un arbre de paquet** :

```bash
cmd_enable() {
    # … (--all / --print parsés ici ; le mode par utilisateur reste celui d'A9)
    if [ -n "${ALL:-}" ]; then
        tree="${NIVUUS_SHELL_DIR:-$(nivuus_system_tree)}"
        if [ -n "${PRINT:-}" ]; then
            # Pour Ansible, les images immuables, /etc sous git : on affiche,
            # on n'écrit pas. Exiger qu'ils nous laissent /etc serait de trop.
            printf '# %s\n' "$(nivuus_system_dropin)"
            nivuus_system_dropin_content
            printf '\n# à ajouter dans %s :\n' "$(nivuus_system_global_rc)"
            nivuus_system_rc_line
            return 0
        fi
        …
    fi
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
rm -f config/*.zwc .zshrc.zwc
bats tests/integration/test_system_activate_all.bats
sh -n tests/ci/run-system-target.sh
NIVUUS_CI_DOCKER=1 bats tests/e2e/test_ci_system_target.bats -f debian
./bin/benchmark | sed -n '/^Average/p'
```
Expected: PASS (10 nouveaux tests, étape 11 verte).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/nivuus lib/system.sh tests/ci/run-system-target.sh \
        tests/integration/test_system_activate_all.bats tests/baseline-counts.tsv
git commit -m "feat(system): machine-wide activation, empirically verified or rolled back"
```

---

### Task 20: INVARIANT n° 3 — une installation utilisateur par-dessus, et un seul `source`

**Files:**
- Modify: `tests/ci/run-system-target.sh` (étape 12)
- Modify: `.github/workflows/tests.yml` (le `grep` de l'invariant n° 3)
- Create: `tests/e2e/test_system_user_override.bats`

**Interfaces:**
- Consumes: la garde de réentrance (Task 12), le `grep` du drop-in (Task 18), `nivuus_zshrc_merge` (existant).
- Produces: l'invariant n° 3, prouvé **deux fois** — sans conteneur (PR) et avec deux utilisateurs réels (nightly).

**Pourquoi deux preuves et non une.** L'étape 12 du script est la preuve complète : bob, un vrai compte, une vraie installation utilisateur par-dessus une activation machine, un vrai shell interactif. Elle ne tourne que la nuit. Un invariant qui n'est vérifié que la nuit se casse le matin et se découvre le lendemain : on double donc par une preuve e2e **locale** — même mécanique, `$HOME` déplacé, drop-in simulé — qui tourne sur chaque PR en moins de trois secondes.

**Ce que l'invariant recouvre exactement**, tel que le tableau du § 4.3 le pose :

| Situation | `NIVUUS_SHELL_DIR` effectif | Nombre de `source` |
|---|---|---|
| Système seul + `nivuus enable` | l'arbre système | 1 (le bloc) |
| Système + activation machine, utilisateur sans bloc | l'arbre système | 1 (le drop-in) |
| Système + installation utilisateur | `~/.nivuus-shell` | 1 (le bloc, **remplacé** par `nivuus_zshrc_merge`) |
| Système + activation machine + installation utilisateur | `~/.nivuus-shell` | 1 — le drop-in **se retire** (`grep`), la garde couvre le reste |

Les quatre lignes sont des tests. La quatrième est celle qui justifie l'existence des deux mécanismes.

**L'installation de bob se fait hors ligne**, depuis une release servie par `file://` (`tests/helpers/release.bash`, chantier « porte d'entrée ») : le script de preuve ne doit dépendre d'aucun réseau.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_system_user_override.bats
#!/usr/bin/env bats
#
# L'utilisateur gagne, toujours -- et il gagne UNE FOIS. Deux mécanismes
# sont en jeu : le grep du drop-in CHOISIT, la garde de réentrance PROTÈGE.
# Le second existe parce que le premier ne peut pas tout voir : le drop-in
# est lu AVANT ~/.zshrc.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh/zshrc.d"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    rm -f "$ROOT"/config/*.zwc "$ROOT/.zshrc.zwc"
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    # Drop-in simulé : on le source à la main, comme le rc global le ferait.
    "$ROOT/bin/nivuus" enable --all --print | sed -n '2,$p' > "$TMP/dropin.zsh"
}

teardown() { rm -rf "$TMP"; }

# Charge le drop-in puis ~/.zshrc, dans l'ordre réel d'un shell interactif.
shell_like() {
    zsh -c "source '$TMP/dropin.zsh' >/dev/null 2>&1
            [ -f \"\$HOME/.zshrc\" ] && source \"\$HOME/.zshrc\" >/dev/null 2>&1
            print -r -- \"\$NIVUUS_SHELL_DIR|\$_nivuus_load_count|\$NIVUUS_ACTIVATED_BY\""
}

@test "système + activation machine, utilisateur sans bloc : l'arbre système, une fois" {
    run shell_like
    [[ "${lines[-1]}" == "$TMP/usr/local/share/nivuus-shell|1|system" ]]
}

@test "système + activation machine + installation utilisateur : l'utilisateur gagne" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run shell_like
    [[ "${lines[-1]}" == "$HOME/.nivuus-shell|1|"* ]]
}

@test "INVARIANT: jamais de double source, quelle que soit la combinaison" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run shell_like
    count="$(printf '%s' "${lines[-1]}" | cut -d'|' -f2)"
    [ "$count" = "1" ]
}

@test "une installation utilisateur REMPLACE le bloc, elle n'en ajoute pas un second" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    n="$(grep -c '>>> nivuus shell >>>' "$HOME/.zshrc")"
    [ "$n" -eq 1 ]
}

@test "même en sourçant Nivuus deux fois à la main, un seul chargement" {
    # Le cas que le grep du drop-in ne peut PAS voir : un source direct,
    # hors bloc délimité. C'est ce qui justifie la garde de réentrance.
    printf 'source "%s/.zshrc"\n' "$TMP/usr/local/share/nivuus-shell" > "$HOME/.zshrc"
    run shell_like
    count="$(printf '%s' "${lines[-1]}" | cut -d'|' -f2)"
    [ "$count" = "1" ]
}
```

Et l'étape 12 dans `tests/ci/run-system-target.sh` :

```sh
echo "== Étape 12 : INVARIANT n° 3 -- installation utilisateur par-dessus, un seul source =="
# Release servie par file:// : la preuve ne dépend d'aucun réseau.
. ./tests/helpers/release.bash
make_release "$SRC" "$WORK/rel" 9.9.9
make_release_api "$WORK/api" fake/nivuus 9.9.9
chmod -R a+rX "$WORK"
as_user bob "NIVUUS_RELEASE_BASE_URL=file://$WORK/rel NIVUUS_GITHUB_API=file://$WORK/api \
             NIVUUS_VERSION=9.9.9 sh $SRC/install.sh --non-interactive"
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -q "$BOB/.nivuus-shell"
# Le compteur de réentrance : un seul chargement, malgré le drop-in machine.
as_user bob "zsh -i -c 'print -r -- \$_nivuus_load_count'" | grep -qx 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f config/*.zwc && bats tests/e2e/test_system_user_override.bats`
Expected: FAIL — sans le drop-in (Task 18) et sans la garde (Task 12), le compteur vaut 2 ou est vide.
(Pour confirmer que le test mord : retirer temporairement la garde de `.zshrc`, constater `2`, remettre.)

- [ ] **Step 3: Write minimal implementation**

Aucune implémentation nouvelle : les deux mécanismes existent (Tasks 12 et 18) et `nivuus_zshrc_merge` remplace déjà le contenu du bloc. **Cette tâche est une tâche de preuve.** Si un test échoue, le défaut est dans l'un des trois, et c'est **là** qu'il se corrige.

Ajouter le `grep` manquant dans `.github/workflows/tests.yml`, à l'étape des invariants :

```yaml
          grep -q "INVARIANT n° 3" tests/ci/run-system-target.sh
          grep -q "INVARIANT: jamais de double source" tests/e2e/test_system_user_override.bats
```

- [ ] **Step 4: Run test to verify it passes**

```bash
rm -f config/*.zwc .zshrc.zwc
bats tests/e2e/test_system_user_override.bats
sh -n tests/ci/run-system-target.sh
NIVUUS_CI_DOCKER=1 bats tests/e2e/test_ci_system_target.bats
bats tests/unit/test_ci_system_matrix.bats
```
Expected: PASS (5 nouveaux tests, étape 12 verte sur les cinq images).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add tests/ci/run-system-target.sh tests/e2e/test_system_user_override.bats \
        .github/workflows/tests.yml tests/baseline-counts.tsv
git commit -m "test(system): the user always wins, and loads Nivuus exactly once"
```

---

# GROUPE 4 — Mise à jour et administration (phase 4 de la spec)

Trois tâches. Elles n'ont de sens qu'une fois qu'il y a quelque chose à mettre à jour et à diagnostiquer — d'où leur place en dernier.

---

### Task 21: `sudo nivuus update` — une réinstallation vérifiée, jamais `_nivuus_perform_update`

**Files:**
- Modify: `bin/nivuus` (`cmd_update`)
- Modify: `install.sh` (`NIVUUS_FORCE_BOOTSTRAP`)
- Create: `tests/e2e/test_system_update.bats`

**Interfaces:**
- Consumes: `nivuus_bootstrap` (`install.sh`), `nivuus install --system` (Task 7), `tests/helpers/release.bash`.
- Produces: `sudo nivuus update` sur un arbre `origin=system` → télécharge, **vérifie**, réinstalle par le manifeste.

**C'est la décision la plus importante de la phase, et elle est négative.** `_nivuus_perform_update` fait `find … -exec rm -rf` puis `cp -r` dans `$NIVUUS_SHELL_DIR` (`config/20-autoupdate.zsh:460-471`). Sur un arbre système, ce serait une écriture massive **hors manifeste**, dans le domaine root, invisible de l'inventaire. Le principe « le manifeste est la seule voie d'écriture » l'interdit — et un `grep` en CI le rend mécaniquement impossible à réintroduire.

**Réinstaller *est* la mise à jour.** `nivuus install --system` est déjà idempotent et différentiel : héritage du manifeste précédent, `SKIP` sur les fichiers conformes, remplacement atomique du manifeste (Task 7 le teste). La mise à jour reste donc réversible, et un fichier que l'administrateur aurait modifié à la main reste traité comme un fichier divergé, pas écrasé en silence.

**Pourquoi `NIVUUS_FORCE_BOOTSTRAP`.** `install.sh` bascule en mode **local** dès qu'un noyau existe à côté (`nivuus_local_root`) : lancé depuis l'arbre système, il réinstallerait la **même** version — une mise à jour qui ne met rien à jour. La variable force le mode d'amorçage : télécharger, vérifier l'empreinte (fail-closed, et la signature du chantier 2 par-dessus), extraire, déléguer. Aucun téléchargeur n'est réécrit ; c'est le silence de la spec le plus concret, comblé ici.

**Aucun ordonnanceur n'est fourni.** Ni timer systemd, ni cron. Un administrateur qui veut de l'automatisme appelle `sudo nivuus update` depuis **son** ordonnanceur : c'est ce que fait tout parc géré, et c'est une décision qui lui appartient. On fournit une commande idempotente à code de retour propre ; c'est tout ce qu'il faut pour l'appeler.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_system_update.bats
#!/usr/bin/env bats
#
# La mise à jour d'un arbre système passe par l'installeur, donc par le
# manifeste. Le chemin destructif de l'auto-update (rm -rf + cp -r) est
# interdit ici : il écrirait hors inventaire, en root.

load '../helpers/release'
load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    TREE="$TMP/usr/local/share/nivuus-shell"

    # Une « nouvelle version » : le dépôt, avec une marque reconnaissable.
    cp -r "$ROOT" "$TMP/src"; rm -rf "$TMP/src/.git"
    printf '9.9.9\n' > "$TMP/src/.version"
    printf '# marque de la v9.9.9\n' >> "$TMP/src/config/00-core.zsh"
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/rel" NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_VERSION=9.9.9

    "$ROOT/bin/nivuus" install --system --yes >/dev/null
}

teardown() { rm -rf "$TMP"; }

@test "sudo nivuus update remplace l'arbre par la nouvelle version" {
    run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -eq 0 ]
    grep -q "marque de la v9.9.9" "$TREE/config/00-core.zsh"
    [ "$(cat "$TREE/.version")" = "9.9.9" ]
}

@test "le manifeste système reste valide et décrit la NOUVELLE version" {
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    head -n1 "$TMP/var/lib/nivuus/manifest.tsv" | grep -q "mode=system"
    hash="$(awk -F'\t' -v p="$TREE/config/00-core.zsh" '$2==p{print $3; exit}' \
            "$TMP/var/lib/nivuus/manifest.tsv")"
    actual="$(fs_hash "$TREE/config/00-core.zsh")"
    [ "$hash" = "$actual" ]
}

@test "la mise à jour reste RÉVERSIBLE : uninstall rend /usr/local bit-identique" {
    fs_fingerprint "$TMP/usr/local" > "$TMP/pose"
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    [ ! -d "$TREE" ]
    [ ! -e "$TMP/usr/local/bin/nivuus" ]
}

@test "sans root, la mise à jour refuse avant d'écrire" {
    before="$(fs_hash "$TREE/config/00-core.zsh")"
    NIVUUS_UID=1000 run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -eq 0 ]                       # on informe, on ne crie pas
    [[ "$output" == *"sudo nivuus update"* ]]
    [ "$(fs_hash "$TREE/config/00-core.zsh")" = "$before" ]
}

@test "une archive corrompue est REFUSÉE : l'arbre n'est pas touché" {
    tamper_release "$TMP/rel" 9.9.9
    before="$(fs_hash "$TREE/config/00-core.zsh")"
    run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -ne 0 ]
    [ "$(fs_hash "$TREE/config/00-core.zsh")" = "$before" ]
}

@test "INVARIANT: la mise à jour système n'emprunte JAMAIS _nivuus_perform_update" {
    # Ce chemin fait rm -rf + cp -r dans $NIVUUS_SHELL_DIR : sur un arbre
    # système, une écriture massive hors manifeste, dans le domaine root.
    run grep -n "_nivuus_perform_update" "$ROOT/bin/nivuus"
    [ "$status" -ne 0 ]
    run grep -n "nivuus-update" "$ROOT/bin/nivuus"
    # Le seul appel restant est celui du mode SOURCE, et il est gardé.
    [[ "$output" != *"system"* ]]
}

@test "une activation utilisateur survit à la mise à jour système" {
    NIVUUS_UID=1000 NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" enable --yes >/dev/null
    cp "$HOME/.zshrc" "$TMP/zshrc.avant"
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    diff "$TMP/zshrc.avant" "$HOME/.zshrc"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_system_update.bats`
Expected: FAIL — `nivuus update` affiche seulement le message de la Task 14 et ne met rien à jour.

- [ ] **Step 3: Write minimal implementation**

Dans `install.sh`, une seule ligne dans le sélecteur de mode :

```sh
# $NIVUUS_FORCE_BOOTSTRAP : « sudo nivuus update » lance CE script depuis
# l'arbre système. Sans cette variable, nivuus_local_root le trouverait et
# réinstallerait la MÊME version -- une mise à jour qui ne met rien à jour.
if [ -n "${NIVUUS_FORCE_BOOTSTRAP:-}" ]; then
    ROOT=''
else
    ROOT="$(nivuus_local_root || true)"
fi
```

Dans `bin/nivuus`, `cmd_update`, remplacer le message de la Task 14 par :

```bash
    if [ "$(nivuus_origin "$dir")" = "system" ]; then
        if ! nivuus_system_is_root; then
            log_info "Nivuus est installé pour la machine ($dir)."
            log_info "Les mises à jour sont l'affaire de l'administrateur :"
            log_info "  sudo nivuus update"
            log_info "Pour une installation personnelle avec mises à jour automatiques :"
            log_info "  curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh"
            return 0
        fi
        # Réinstallation VÉRIFIÉE : télécharge, vérifie l'empreinte
        # (fail-closed) et la signature, extrait, puis délègue à
        # « install --system », qui est idempotent et différentiel et qui
        # passe par le manifeste. On n'emprunte JAMAIS
        # _nivuus_perform_update : rm -rf + cp -r dans le domaine root, hors
        # inventaire, est exactement ce que le manifeste existe pour éviter.
        log_info "Mise à jour de l'installation système : réinstallation depuis une release vérifiée."
        NIVUUS_FORCE_BOOTSTRAP=1 export NIVUUS_FORCE_BOOTSTRAP
        exec sh "$dir/install.sh" --system --non-interactive
    fi
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/e2e/test_system_update.bats
bats tests/e2e/test_bootstrap.bats tests/e2e/test_update_signature.bats
sh -n install.sh && dash -n install.sh
```
Expected: PASS (7 nouveaux tests), amorçage et signature intacts.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/nivuus install.sh tests/e2e/test_system_update.bats tests/baseline-counts.tsv
git commit -m "feat(system): sudo nivuus update reinstalls from a verified release"
```

---

### Task 22: `doctor` — origine, double installation, héritage, conffile, `--scan-users`

**Files:**
- Modify: `bin/healthcheck`
- Modify: `lib/system.sh` (`nivuus_system_scan_users`)
- Create: `tests/e2e/test_doctor_system.bats`

**Interfaces:**
- Consumes: `lib/origin.sh`, `lib/system.sh`, `doctor` enrichi par le chantier packaging (A10).
- Produces: cinq diagnostics de plus. **`doctor` diagnostique, il ne convertit ni ne répare.**

**C'est la contrepartie de tout ce qui précède.** La garde du bloc `.zshrc` **masque** une installation cassée au lieu de la signaler ; le refus de parcourir `/home` laisse des blocs orphelins ; l'activation machine modifie un conffile. Trois silences délibérés, qui doivent tous être payés par un diagnostic **à la demande**.

Les cinq cas, et ce que `doctor` en dit :

1. **Origine système** — l'arbre, sa version, l'état d'activation, et que les mises à jour sont l'affaire de l'administrateur.
2. **Double installation** (système + utilisateur) — **l'utilisateur gagne, toujours**, pour une raison structurelle : son `~/.zshrc` contient au plus un bloc, et ce bloc fixe `NIVUUS_SHELL_DIR`. `doctor` nomme les deux arbres et dit lequel est actif. Il **ne convertit pas** : convertir voudrait dire supprimer un arbre pour en poser un autre, et le manifeste d'origine deviendrait faux à mi-chemin.
3. **Héritage `/etc/nivuus-shell`** — nommé, jamais supprimé, avec le renvoi vers la procédure manuelle.
4. **Conffile modifié par Nivuus** — pour que la question `dpkg` ne soit pas une surprise dans six mois.
5. **`--scan-users`** — la seule lecture d'autrui, **opt-in, en lecture seule, jamais par défaut**. Deux raisons, dont une décisive et purement technique : un `stat` sur un `$HOME` NFS **déclenche l'automonteur** (montages en rafale, timeouts, entrées de journal) — lire n'est pas neutre. La seconde est de principe : l'administrateur doit taper quelque chose qui dit ce qu'il fait.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_doctor_system.bats
#!/usr/bin/env bats
#
# Le silence au démarrage se paie par un diagnostic à la demande. doctor
# est le seul endroit où les trois silences délibérés du mode système (bloc
# gardé, /home non parcouru, conffile modifié) redeviennent visibles.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    export NIVUUS_PASSWD_FILE="$TMP/passwd"
    printf 'alice:x:1000:1000::%s/alice:/bin/zsh\n' "$TMP" > "$TMP/passwd"
    printf 'bob:x:1001:1001::%s/bob:/bin/zsh\n' "$TMP" >> "$TMP/passwd"
    mkdir -p "$TMP/alice" "$TMP/bob"
    TREE="$TMP/usr/local/share/nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "doctor nomme l'origine système et l'arbre" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"système"* ]]
    [[ "$output" == *"$TREE"* ]]
    [[ "$output" == *"sudo nivuus update"* ]]
}

@test "double installation : doctor nomme les deux et dit lequel est actif" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run env NIVUUS_SHELL_DIR="$HOME/.nivuus-shell" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"$HOME/.nivuus-shell"* ]]
    [[ "$output" == *"$TREE"* ]]
    [[ "$output" == *"Actif"* ]] || [[ "$output" == *"actif"* ]]
}

@test "doctor ne convertit rien : aucune commande n'est exécutée à notre place" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    env NIVUUS_SHELL_DIR="$HOME/.nivuus-shell" "$ROOT/bin/nivuus" doctor >/dev/null
    [ -d "$TREE" ]                       # l'arbre système est toujours là
    [ -d "$HOME/.nivuus-shell" ]         # et l'arbre utilisateur aussi
}

@test "bloc présent, arbre absent : doctor le dit et donne la réparation" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" enable --yes >/dev/null
    rm -rf "$TREE"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"absent"* ]]
    [[ "$output" == *"nivuus disable"* ]]
}

@test "l'héritage /etc/nivuus-shell est nommé, jamais supprimé" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo legacy\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"/etc/nivuus-shell"* ]]
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]
}

@test "le conffile modifié par Nivuus est signalé par avance" {
    "$ROOT/bin/nivuus" install --system --activate-all --yes >/dev/null 2>&1 || skip "activation machine indisponible ici"
    run "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    [[ "$output" == *"dpkg"* ]] || [[ "$output" == *"conffile"* ]]
}

@test "INVARIANT: doctor ne lit AUCUN \$HOME d'autrui sans --scan-users" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    printf '# >>> nivuus shell >>>\n# <<< nivuus shell <<<\n' > "$TMP/alice/.zshrc"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" != *"$TMP/alice"* ]]
    [[ "$output" != *"alice"* ]]
}

@test "--scan-users liste les comptes activés, en lecture seule" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    printf '# >>> nivuus shell >>>\n# <<< nivuus shell <<<\n' > "$TMP/alice/.zshrc"
    printf 'export RIEN=1\n' > "$TMP/bob/.zshrc"
    cp "$TMP/alice/.zshrc" "$TMP/alice/.zshrc.temoin"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor --system --scan-users
    [[ "$output" == *"alice"* ]]
    [[ "$output" != *"bob"* ]]
    diff "$TMP/alice/.zshrc.temoin" "$TMP/alice/.zshrc"     # lecture seule
}

@test "--scan-users dit pourquoi il n'est pas automatique" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor --system --scan-users
    [[ "$output" == *"NFS"* ]] || [[ "$output" == *"automonteur"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_doctor_system.bats`
Expected: FAIL — `doctor` ne connaît ni l'origine système, ni `--scan-users`.

- [ ] **Step 3: Write minimal implementation**

Dans `lib/system.sh` :

```sh
# La SEULE lecture d'autrui du mode système. Opt-in, en lecture seule,
# jamais par défaut -- et pas seulement par principe : un stat sur un $HOME
# NFS déclenche l'automonteur (montages en rafale, timeouts, entrées de
# journal). Lire n'est pas neutre sur un serveur.
nivuus_system_scan_users() {
    log_warn "Lecture des \$HOME des comptes locaux. Sur un parc NFS, cela déclenche"
    log_warn "l'automonteur : c'est pour cela que ce n'est jamais automatique."
    awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { print $1 "\t" $6 }' \
        "${NIVUUS_PASSWD_FILE:-/etc/passwd}" |
    while IFS="$(printf '\t')" read -r _u _h; do
        [ -r "$_h/.zshrc" ] || continue
        grep -qF '>>> nivuus shell >>>' "$_h/.zshrc" 2>/dev/null && printf '%s\n' "  $_u"
    done
}
```

Dans `bin/healthcheck`, une section « Origine » qui branche sur `nivuus_origin`, et le traitement des cinq cas. Le format suit celui de la spec § 4.3 :

```
Origine        : source (utilisateur)      ~/.nivuus-shell           v3.2.0
Aussi présent  : système                   /usr/local/share/…        v3.1.4
Actif          : ~/.nivuus-shell  (c'est ton bloc ~/.zshrc qui décide)
Mises à jour   : automatiques (installation utilisateur)
                 L'arbre système est ignoré par ton shell. Pour l'utiliser :
                     nivuus uninstall && nivuus enable
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/e2e/test_doctor_system.bats tests/e2e/test_doctor_package.bats
bats tests/e2e/
```
Expected: PASS (9 nouveaux tests), le `doctor` du mode paquet inchangé.

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add bin/healthcheck lib/system.sh tests/e2e/test_doctor_system.bats tests/baseline-counts.tsv
git commit -m "feat(doctor): diagnose system origin, double install, legacy tree and conffile"
```

---

### Task 23: documentation d'administration, et fin des vestiges

**Files:**
- Modify: `doc/INSTALL.md` (section « Administration : installer pour toute une machine »)
- Modify: `doc/FEATURES.md` (lignes 453-460)
- Modify: `doc/CLAUDE.md` (lignes 50 et 235-237)
- Modify: `doc/TESTING.md` (ligne 89), `doc/TEST_PROGRESS.md` (ligne 64)
- Modify: `tests/e2e/test_docs_install.bats`
- Create: `tests/e2e/test_docs_system.bats`

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: une documentation d'administrateur **vérifiée par un test**, et zéro vestige.

**Ce qui est réécrit, et pourquoi c'est le dernier acte.** Une documentation en avance sur le code est plus coûteuse qu'une documentation absente : elle produit des commandes qui échouent. `doc/FEATURES.md:453-460` en est l'exemple exact — il publie `curl … | sudo bash -s -- --system` avec un démenti trois lignes plus bas, ce qui est le pire des deux mondes. On ne le corrige qu'une fois la commande vraie.

**Ce que la documentation doit dire, et que le test vérifie :**

| Point | Pourquoi il est testé |
|---|---|
| `--system` n'est **pas** la porte d'entrée : le one-liner utilisateur le reste, sur toutes les plateformes | c'est une décision de périmètre, elle se perd vite |
| Sur Debian et Ubuntu, **le `.deb` est recommandé en premier** | c'est la conclusion « redondant à ~90 % », et elle doit se lire au même endroit que la commande |
| `/etc/skel` **ne rattrape pas** les comptes existants | c'est le mode d'échec historique de la fonctionnalité |
| `uninstall --system` **ne touche à aucun `$HOME`**, et ce que ça laisse | c'est ce qu'un administrateur découvrirait sinon au pire moment |
| La procédure `/etc/nivuus-shell` hérité, **avec sa commande de retour en arrière** | on ne migre pas automatiquement : il faut donc que ce soit écrit |
| `sudo nivuus update`, et **aucun ordonnanceur fourni** | pour qu'un administrateur sache qu'il doit le brancher lui-même |
| Un extrait `Dockerfile` et un extrait Ansible | ce sont les deux usages nommés au § 1.1 ; un exemple faux serait pire que rien, d'où le test qui les exécute en `--dry-run` |

**La garde inverse de `test_docs_install.bats` est conservée et étendue.** Elle interdisait `sudo ./install.sh --system` ; elle interdit désormais **aussi** toute forme qui pipe du réseau dans un `sudo bash` (`curl … | sudo bash`) — la forme que `doc/FEATURES.md` publie encore aujourd'hui.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_docs_system.bats
#!/usr/bin/env bats
#
# Une documentation d'administration qui ment coûte plus cher qu'une
# documentation absente : elle produit des commandes qui échouent en root.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    INSTALL_DOC="$ROOT/doc/INSTALL.md"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "doc/INSTALL.md a une section d'administration" {
    run grep -nE '^#{2,3} .*(Administration|machine)' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "la doc recommande le .deb EN PREMIER sur Debian et Ubuntu" {
    grep -q "apt install" "$INSTALL_DOC"
    # La recommandation précède la commande --system dans le fichier.
    deb="$(grep -n 'apt install' "$INSTALL_DOC" | head -1 | cut -d: -f1)"
    sys="$(grep -n 'nivuus install --system' "$INSTALL_DOC" | head -1 | cut -d: -f1)"
    [ "$deb" -lt "$sys" ]
}

@test "la limite de /etc/skel est écrite noir sur blanc" {
    grep -qi "créés après" "$INSTALL_DOC"
}

@test "la doc dit que uninstall --system ne touche à aucun HOME" {
    grep -qi "aucun .*HOME" "$INSTALL_DOC" || grep -qi "n'écrit dans aucun" "$INSTALL_DOC"
    grep -q "nivuus disable" "$INSTALL_DOC"
}

@test "la procédure de l'héritage /etc/nivuus-shell donne le retour en arrière" {
    grep -q "/etc/nivuus-shell" "$INSTALL_DOC"
    grep -qi "revenir en arrière" "$INSTALL_DOC" || grep -qi "restaurer" "$INSTALL_DOC"
}

@test "aucun ordonnanceur n'est promis" {
    run grep -nE 'systemd.timer|crontab -e.*nivuus' "$INSTALL_DOC"
    [ "$status" -ne 0 ]
    grep -q "sudo nivuus update" "$INSTALL_DOC"
}

@test "toutes les commandes nivuus citées dans la section système existent" {
    aide="$("$ROOT/bin/nivuus" help)"
    for opt in --system --skel --activate-all; do
        grep -q -- "$opt" "$INSTALL_DOC" || { echo "option non documentée: $opt"; false; }
        printf '%s' "$aide" | grep -q -- "$opt" || { echo "option non offerte: $opt"; false; }
    done
}

@test "l'extrait Dockerfile de la doc est exécutable en --dry-run" {
    # Un exemple faux est pire que pas d'exemple. On extrait la ligne
    # nivuus du bloc Dockerfile et on l'exécute en mode audit.
    line="$(grep -oE 'nivuus install --system[^"]*' "$INSTALL_DOC" | head -1)"
    [ -n "$line" ]
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus" NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    mkdir -p "$TMP/etc/skel"
    run env NIVUUS_UID=1000 sh -c "$ROOT/bin/${line} --dry-run --yes"
    [ "$status" -eq 0 ]
}

@test "doc/FEATURES.md ne publie plus « curl … | sudo bash »" {
    run grep -n 'sudo bash' "$ROOT/doc/FEATURES.md"
    [ "$status" -ne 0 ]
}

@test "doc/CLAUDE.md décrit le modèle réel, pas /etc/nivuus-shell" {
    run grep -n "temporairement indisponible\|Temporarily unavailable" "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
    grep -q "/usr/local/share/nivuus-shell" "$ROOT/doc/CLAUDE.md"
}

@test "aucune doc ne mentionne plus un test_system_install qui n'a jamais existé" {
    run grep -rn "test_system_install" "$ROOT/doc/"
    [ "$status" -ne 0 ]
}
```

Et, dans `tests/e2e/test_docs_install.bats`, **étendre** la garde inverse existante :

```bash
@test "aucune documentation ne recommande de piper du réseau dans un sudo" {
    # La garde d'origine interdisait « sudo ./install.sh --system ». La
    # forme réellement publiée par doc/FEATURES.md était pire : un curl
    # dans un sudo bash. Les deux sont interdites.
    run grep -rn 'sudo ./install.sh --system' "$README" "$INSTALL_DOC" "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
    run grep -rnE 'curl[^|]*\|[[:space:]]*sudo' "$README" "$INSTALL_DOC" "$ROOT/doc/CLAUDE.md" "$ROOT/doc/FEATURES.md"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_docs_system.bats tests/e2e/test_docs_install.bats`
Expected: FAIL — pas de section d'administration, `doc/FEATURES.md` publie encore `sudo bash`, `doc/CLAUDE.md` dit « temporairement indisponible ».

- [ ] **Step 3: Write minimal implementation**

`doc/INSTALL.md`, nouvelle section (esquisse — le test en fixe les points obligatoires) :

```markdown
## Administration : installer pour toute une machine

**Sur Debian et Ubuntu, préfère le paquet.** `apt install ./nivuus-shell_<version>_all.deb`
est inventorié par `dpkg`, vérifiable par `dpkg -V` et retiré par `apt purge`. `--system`
refait ce travail lui-même ; le paquet le fait mieux.

Partout ailleurs — Fedora, RHEL, Rocky, openSUSE, Alpine, images de conteneur, machines
sans réseau sortant — il n'y a pas de paquet, et c'est ce que `--system` sert :

    sudo nivuus install --system

Ce que ça écrit, et rien d'autre :

| Chemin | Rôle |
|---|---|
| `/usr/local/share/nivuus-shell/` | l'arbre partagé, en lecture seule pour les utilisateurs |
| `/usr/local/bin/nivuus` | le point d'entrée |
| `/usr/local/share/man/man1/nivuus.1` | la page de manuel |
| `/var/lib/nivuus/manifest.tsv` | l'inventaire : ce qui a été écrit, et comment le défaire |

**Aucun `~/.zshrc` n'est touché. Aucun `chsh` n'est fait.** L'activation reste un acte
par utilisateur : chacun lance `nivuus enable`, sans privilège.

### Activer pour les comptes créés ensuite (`--skel`)

    sudo nivuus install --system --skel

`/etc/skel` **ne s'applique qu'aux comptes créés après** cette commande. Les comptes déjà
présents ne sont pas activés — c'est une limite du mécanisme, pas un défaut de Nivuus.

### Activer pour toute la machine (`--activate-all`)

    sudo nivuus enable --all

Ajoute un drop-in `/etc/zsh/zshrc.d/10-nivuus.zsh` et **une ligne** au fichier zsh global.
Sur Debian et Ubuntu ce fichier est un conffile `dpkg` : une future mise à jour de
`zsh-common` posera peut-être la question « conffile modifié ». `nivuus doctor` le signale
par avance. Pour gérer `/etc` toi-même (Ansible, image immuable) :

    nivuus enable --all --print      # affiche le fichier et la ligne, n'écrit rien

L'activation est **vérifiée** après écriture : si aucun zsh interactif ne voit le marqueur,
elle est annulée et le chemin exact à corriger est affiché.

### Mettre à jour

    sudo nivuus update

C'est une réinstallation depuis une release **vérifiée**, qui passe par le manifeste.
Les shells des utilisateurs ne se mettent jamais à jour tout seuls sur un arbre système.
**Aucun ordonnanceur n'est fourni** : branche cette commande sur le tien.

### Désinstaller

    sudo nivuus uninstall --system

Rejoue le manifeste système et **rien d'autre** : `/etc` et `/usr/local` redeviennent ce
qu'ils étaient. Les activations par utilisateur subsistent — elles appartiennent à chaque
compte, leurs shells ne cassent pas (le bloc est gardé), et chacun peut faire
`nivuus disable`.

### Une installation faite par l'ancien `--system`

Avant la v3.1, `--system` posait un arbre dans `/etc/nivuus-shell` **sans manifeste** :
il n'est pas réversible automatiquement, et l'installation actuelle refuse d'écrire
par-dessus. Procédure, et son retour en arrière :

    sudo mv /etc/nivuus-shell /etc/nivuus-shell.avant-migration
    sudo nivuus install --system
    # pour revenir en arrière :
    sudo mv /etc/nivuus-shell.avant-migration /etc/nivuus-shell

### Image de conteneur

```dockerfile
RUN sh install.sh --system --skel --non-interactive
```

### Ansible

```yaml
- name: Installer Nivuus pour la machine
  ansible.builtin.command: nivuus install --system --yes
  args: { creates: /usr/local/share/nivuus-shell/.nivuus-origin }
```
```

`doc/FEATURES.md` : la section « System-Wide Installation » est réécrite (plus de `curl | sudo bash`, un renvoi vers `doc/INSTALL.md`). `doc/CLAUDE.md` : `/etc/nivuus-shell` → `/usr/local/share/nivuus-shell`, et la mention « temporairement indisponible » disparaît. `doc/TESTING.md` et `doc/TEST_PROGRESS.md` : `test_system_install` (qui n'a jamais existé) est remplacé par les suites réelles.

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/e2e/test_docs_system.bats tests/e2e/test_docs_install.bats
grep -rn "test_system_install" doc/          # -> aucun résultat
grep -rn "sudo bash" doc/ README.md          # -> aucun résultat
```
Expected: PASS (11 nouveaux tests).

- [ ] **Step 5: Commit**

```bash
./bin/test-count --update
git add doc/ tests/e2e/test_docs_system.bats tests/e2e/test_docs_install.bats tests/baseline-counts.tsv
git commit -m "docs(system): administrator guide, and the end of the --system vestiges"
```

---

## Vérification finale du chantier

En local, sur un checkout propre (`git clean -xdf` d'abord — les `.zwc` locaux masquent des échecs réels) :

```bash
rm -f config/*.zwc .zshrc.zwc

bats tests/unit/           # >= 799 + ~70 nouveaux, 0 échec
bats tests/integration/    # >= 195 + ~45 nouveaux, 2 skips, 0 échec
bats tests/e2e/            # >= 181 + ~45 nouveaux (dont ~7 `docker` exclus par défaut), 4 skips
bats tests/performance/    # 10, 0 échec
./bin/test-count --check   # sort en 0
./bin/benchmark | sed -n '/^Average/p'    # < 300 ms (~35 ms attendu)
```

La preuve système, dans de vrais conteneurs — **à faire avant tout push**, au moins sur Debian (famille GNU/shadow) et sur Alpine (famille BusyBox), qui sont les deux qui cassent en premier :

```bash
for img in debian:12 ubuntu:24.04 fedora:41 alpine:3.20 archlinux:latest; do
  echo "=== $img"
  docker run --rm -v "$PWD:/src:ro" "$img" sh -c '
    set -e
    cp -r /src /work && cd /work
    ./tests/ci/install-deps.sh >/dev/null
    ./tests/ci/run-system-target.sh'
done
```

Contrôles mécaniques :

```bash
# Aucune écriture hors lib/manifest.sh, y compris dans /etc
grep -nE '^[[:space:]]*(mv|rm|cp|mkdir|chmod|chown|ln|touch|tee)[[:space:]]' \
  lib/system.sh lib/steps.sh lib/zshrc.sh lib/detect.sh lib/migrate.sh
# -> aucun résultat

# Aucun sudo implicite, aucune ré-exécution privilégiée
grep -rnE '(exec|sh|bash)[[:space:]]+sudo|sudo[[:space:]]+"?\$0' lib/ bin/nivuus install.sh
# -> aucun résultat

# La mise à jour système n'emprunte jamais le chemin destructif
grep -n "_nivuus_perform_update" bin/nivuus
# -> aucun résultat

# Les vestiges sont morts
grep -rn "system.mode" tests/ ; grep -rn "pas encore disponible" . ; grep -rn "test_system_install" doc/
# -> aucun résultat

# lib/ reste POSIX
bats tests/unit/test_lib_posix.bats && sh -n lib/system.sh && dash -n install.sh

# La matrice est du JSON valide et le README lui correspond toujours
python3 -c "import json;json.load(open('.github/matrix.json'))"
bats tests/unit/test_readme_badges.bats
```

**Les quatre invariants, et où ils vivent** — s'ils passent, la propriété existe ; s'ils manquent, le reste est décoratif. C'est ce que le `grep` de `tests.yml` protège :

| # | Énoncé | Porté par |
|---|---|---|
| 1 | Une installation pour la machine ne touche aucun `$HOME` | `tests/ci/run-system-target.sh` étape 3 + `tests/integration/test_install_system.bats` |
| 2 | L'activation d'alice n'active pas bob | `tests/ci/run-system-target.sh` étape 5 |
| 3 | Jamais de double `source` | `tests/ci/run-system-target.sh` étape 12 + `tests/e2e/test_system_user_override.bats` |
| 4 | Retrait bit-exact de `/etc` et `/usr/local` | `tests/ci/run-system-target.sh` étape 13 + `tests/integration/test_uninstall_system.bats` |

Critères de sortie, tels que la spec les pose :

1. **Phase 1** — étapes 1-9 et 13-15 vertes sur Debian **et** Fedora, avec deux utilisateurs réels ; `/etc` et `/usr/local` bit-identiques après retrait.
2. **Phase 2** — étape 10 verte : carol (créée après) est activée, bob (existant) ne l'est pas, et c'est écrit noir sur blanc dans la doc.
3. **Phase 3** — étapes 11 et 12 vertes : bob est activé sans rien faire, et une installation utilisateur par-dessus continue de gagner, avec un seul `source`.
4. **Phase 4** — une machine système passe de la v(n-1) à la v(n) sans perdre une activation, et le chantier packaging peut citer une commande qui existe (`nivuus enable --all`).

---

## Ce que ce plan ne livre pas

Délibérément hors périmètre, avec la raison :

- **Un ordonnanceur de mise à jour** (unité systemd, cron, `nivuus update --timer`). C'est la politique de l'administrateur, pas la nôtre. On fournit une commande idempotente à code de retour propre ; c'est tout ce qu'il faut pour l'appeler depuis le sien.
- **La configuration de site** (`/etc/nivuus-shell/site.zsh` chargé avant `~/.zsh_local`). C'est probablement la première chose qu'un administrateur demandera après avoir installé pour quatorze personnes, et c'est une vraie fonctionnalité — donc son propre spec. Le chemin `/etc/nivuus-shell` est **réservé** ici (l'installation refuse d'écrire par-dessus un arbre hérité, elle ne s'y installe jamais) pour ne pas le brûler.
- **Un dépôt APT ou RPM.** Chantier packaging, arbitré là-bas, et refusé là-bas.
- **La migration automatique** d'un `/etc/nivuus-shell` hérité, ou de système ↔ utilisateur ↔ paquet. `doctor` détecte et explique, il ne convertit pas : convertir voudrait dire supprimer un arbre pour en poser un autre, et le manifeste d'origine deviendrait faux à mi-chemin.
- **`--system` sur macOS au-delà du techniquement possible.** `enable`/`disable` fonctionnent sur un arbre posé à la main ; `--skel` est refusé (le répertoire n'existe pas) ; aucun compte n'est créé sur le runner. Couverture **partielle et documentée**, à la manière du job « WSL simulé ». Voir la question ouverte n° 4 de la spec, non tranchée.
- **Le comportement sur des `$HOME` NFS avec automonteur.** Aucun test ne le couvre, et c'est précisément le cas où `--scan-users` a des effets de bord. La spec le dit ; ce plan ne prétend pas mieux.
- **La question `dpkg` « conffile modifié ».** Elle n'apparaît qu'à une mise à jour de `zsh-common`, qu'on ne simule pas. `doctor` la signale par avance ; on ne la mitige pas au-delà.
- **`--system` comme installation recommandée.** Le one-liner utilisateur reste la porte d'entrée, sur toutes les plateformes. `--system` est documenté dans une section « administration », et pas dans le README.

---

## Silences de la spec, comblés par ce plan

Sept points que la spec ne tranche pas et qu'il fallait trancher pour écrire du code. Chacun est signalé ici pour pouvoir être rouvert sans avoir à relire les vingt-trois tâches.

1. **Ce que contient `NIVUUS_SYSTEM_PREFIX`** — l'arbre complet, ou le préfixe FHS ? Tranché : **le préfixe** (`/usr/local`), dont trois fonctions dérivent l'arbre, le lien et la page de manuel. Raison : les trois chemins doivent bouger **ensemble**, sinon un test déplacerait l'arbre sans le lien et prouverait une configuration qui n'existe pas. (Task 4)
2. **Comment `sudo nivuus update` obtient la nouvelle version** — la spec dit « relance l'installation système depuis une release vérifiée » sans dire par quel chemin. Tranché : `NIVUUS_FORCE_BOOTSTRAP=1 sh <arbre>/install.sh --system`, qui réutilise `nivuus_bootstrap` tel quel (téléchargement, empreinte fail-closed, signature, extraction, délégation). Sans cette variable, `nivuus_local_root` trouverait le noyau voisin et réinstallerait **la même version**. (Task 21)
3. **La journalisation d'un lien symbolique** — le manifeste n'avait aucune primitive de lien (le dépôt n'en créait aucun). Tranché : une action `SYMLINK` dont la **cible** tient lieu de hash, restaurée par la même règle que `CREATE` (retrait si intact, survie et signalement si détourné). (Task 6)
4. **Qui exécute la sonde de fin d'installation** — la spec exige « un environnement non privilégié » sans nommer le compte. Tranché : `nobody` s'il existe (c'est le cas sur les cinq cibles), l'utilisateur courant sinon, **en le disant** — sonder en root prouverait exactement ce qu'on ne cherche pas, puisque root lit un arbre `0700`. Crochet : `NIVUUS_SYSTEM_PROBE_USER`. (Task 11)
5. **Comment les modes imposés cohabitent avec « aucune écriture hors `lib/manifest.sh` »** — tranché : trois variables (`NIVUUS_INSTALL_DIR_MODE`, `NIVUUS_INSTALL_FILE_MODE`, `NIVUUS_INSTALL_OWNER`) lues par le **seul écrivain du projet**, vides par défaut. Une normalisation faite après coup depuis `lib/system.sh` violerait la règle centrale et laisserait une fenêtre pendant laquelle les fichiers sont dans le mauvais état. Elle ferme au passage un **bug réel** : `cp -p` en root préserve le propriétaire de la source. (Task 5)
6. **Le garde-fou « manifeste système décrivant un `$HOME` »** — la spec pose la règle (« il ne les lit même pas ») sans dire ce qu'on fait d'un manifeste trafiqué. Tranché : pré-scan et **refus en bloc** avant tout rejeu. Deux lignes d'`awk` contre la classe entière des scénarios « manifeste corrompu » et « bug d'une version future », au moment le plus dangereux. (Task 13)
7. **Où vivent les étapes 6 et 7 du script de preuve** — elles appartiennent à la sortie de la phase 1 mais exercent du code que la spec place en phase 4. Tranché : le **refus** d'auto-update et le **message** de `nivuus update` remontent en phase 1 (Task 14) ; seul le **contenu** de `sudo nivuus update` reste en phase 4 (Task 21). Écrire les étapes avant leur code aurait imposé des assertions vouées à échouer.

**Et un point que ce plan ne tranche pas :** les sept questions ouvertes du § 11 de la spec restent ouvertes. Ce plan applique les positions que la spec y défend (`/usr/local`, modification du rc global sous drapeau, `--scan-users` conservé, macOS partiel), mais **la question ouverte n° 6 est structurante** : si l'arbitrage décide que le paquet porte l'activation machine, le **groupe 3 entier** devient redondant et doit être **retiré, pas dupliqué**. C'est la seule décision extérieure qui peut invalider une partie de ce plan après son écriture.
