# Distribution par gestionnaires de paquets — Design

**Date :** 2026-08-21
**Statut :** proposé, en attente d'arbitrage sur les questions ouvertes (§ 10)
**Chantier :** 4/4 du programme d'adoption — « Distribution & lancement »
(voir `2026-08-20-installation-friction-zero-design.md`, § Contexte)

## Contexte

Les deux chantiers précédents sont implémentés et mergés :

- **Chantier 1 (friction zéro)** a produit `bin/nivuus`
  (`install`/`uninstall`/`update`/`doctor`/`migrate`), un `install.sh` bimodal
  (voisin + amorçage `curl | sh`, POSIX sh strict), sept modules dans `lib/`, un
  **manifeste** (`lib/manifest.sh`) qui est la seule voie d'écriture et la
  garantie de réversibilité bit-exacte, et une matrice CI qui prouve
  install/uninstall sur six conteneurs et deux runners.
- **Chantier 2 (preuve & confiance)** a produit `keys/`, la signature de
  `SHA256SUMS` en ECDSA P-256 et SSHSIG dans `release.yml` sous
  `environment: release`, la vérification client dans `config/20-autoupdate.zsh`
  avec **refus dur**, `--verify-key`, `SECURITY.md` et `doc/SIGNING.md`.

Le chantier 1 renvoyait explicitement à ce document : « formules **brew / AUR /
.deb** (chantier 4 — *le noyau est conçu pour*, mais on ne les écrit pas ici) ».
Le chantier 2 aussi : « **Signature des paquets brew/AUR/.deb** — chantier 4,
qui consommera les artefacts produits ici ».

Ce document écrit ces trois canaux. Il consomme les artefacts signés du
chantier 2 et il **n'affaiblit aucune propriété** posée par les chantiers 1 et 2 :
réversibilité prouvée, refus dur, aucun `sudo` non demandé, aucun fichier
touché qui n'ait été journalisé.

## Problème

Un paquet système et un logiciel qui se met à jour tout seul sont **deux
autorités qui revendiquent les mêmes fichiers**. Nivuus a aujourd'hui les deux
propriétés qui rendent la collision certaine :

| # | Propriété actuelle | Ce qu'elle casse en mode paquet | Gravité |
|---|---|---|---|
| 1 | `_nivuus_check_update_async` part au démarrage tous les 7 jours et `_nivuus_perform_update` **écrase `$NIVUUS_SHELL_DIR`** (`rm -rf` + extraction) | Réécrit des fichiers appartenant à `dpkg`/`pacman`/`brew`. La base du gestionnaire devient fausse (`dpkg -V` diverge, `pacman -Qkk` signale des altérations), et la mise à jour système suivante écrase silencieusement Nivuus. Si l'utilisateur n'est pas root, l'update échoue chaque semaine, en arrière-plan, dans un `mktemp` que personne ne lit. | **bloquant** |
| 2 | `lib/manifest.sh` journalise chaque écriture avec le hash de l'original ; `uninstall` restaure à l'octet près | Un paquet installe ses fichiers **hors manifeste**. Un `uninstall` qui prétendrait les retirer soit ne trouverait rien, soit supprimerait des fichiers appartenant au gestionnaire. | **bloquant** |
| 3 | Le bloc délimité de `~/.zshrc` est écrit à l'installation | Un `postinst` s'exécute **une fois, en root, pour la machine**. Le bloc est **par utilisateur**. Un paquet ne peut pas parcourir `/home` pour éditer le `.zshrc` de chacun — homes NFS, comptes créés après coup, consentement absent. | **bloquant** |
| 4 | `config/99-cleanup.zsh` compile `$NIVUUS_SHELL_DIR/config/*.zsh` en `.zwc` **à côté des sources** | Sous `/usr/share`, l'écriture échoue silencieusement (`&>/dev/null`) pour un utilisateur normal ; pour un shell root elle **réussit** et laisse des fichiers inconnus du gestionnaire, qui survivent au `purge`. Le projet exige « aucune trace après désinstallation » : c'en serait une. | élevée |
| 5 | `bin/nivuus` calcule sa racine par `cd "$(dirname "${BASH_SOURCE[0]}")/.."` | Un `/usr/bin/nivuus` **symlink** vers `/usr/share/nivuus-shell/bin/nivuus` donne `BASH_SOURCE=/usr/bin/nivuus`, donc racine `/usr` — et `. /usr/lib/log.sh` échoue. C'est exactement ce que produisent `bin.install_symlink` (Homebrew) et le `ln -s` usuel d'un `PKGBUILD`. | élevée |
| 6 | Le bloc `.zshrc` fait `source "$NIVUUS_SHELL_DIR/.zshrc"` sans garde | `brew uninstall` / `apt purge` retire l'arbre partagé alors que des utilisateurs ont encore le bloc → **erreur zsh à chaque ouverture de shell**, pour tout le monde, sans rapport visible avec l'action faite. | élevée |
| 7 | Aucun canal n'est régénéré automatiquement | Trois formules écrites à la main pourrissent en deux releases. Un canal figé est **pire** qu'un canal absent : l'auto-update y est désactivé par conception (§ 1), donc l'utilisateur n'a plus aucun chemin de mise à jour. | élevée |

Les points 1 à 3 sont la décision structurante de ce chantier ; les points 4 à 6
sont du travail de noyau qui doit précéder **tout** format ; le point 7 est ce
qui décide si le chantier a une valeur à douze mois.

## Approche retenue

**Un paquet installe un arbre partagé en lecture seule ; l'activation reste un
acte par utilisateur, et c'est le seul acte journalisé au manifeste.**

```
┌─ domaine du gestionnaire de paquets ────────────────────────┐
│  /usr/share/nivuus-shell/{config,themes,lib,bin,keys,...}   │  copie bit-pour-bit
│  /usr/bin/nivuus                                            │  de l'arbre de release
│  → inventaire : la base dpkg / pacman / brew                │
│  → mise à jour : brew upgrade / pacman -Syu / apt upgrade   │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ lecture seule, jamais réécrit par Nivuus
┌─ domaine de l'utilisateur ──┴───────────────────────────────┐
│  ~/.zshrc            bloc délimité → MODIFY au manifeste    │
│  ~/.zsh_local, ~/.cache/nivuus-shell, chsh                  │
│  ~/.local/state/nivuus/{manifest.tsv,backups/}              │
│  → inventaire : lib/manifest.sh, inchangé                   │
│  → activation : nivuus enable   /  retrait : nivuus disable │
└─────────────────────────────────────────────────────────────┘
```

Les deux inventaires ne se recouvrent **jamais**. C'est ce qui rend les deux
garanties compatibles au lieu de concurrentes : le gestionnaire est
autoritatif et bit-exact sur son domaine (c'est son métier), le manifeste reste
autoritatif et bit-exact sur le sien. Aucune des deux ne doit être enseignée à
l'autre.

Approches écartées :

- **Le paquet écrit le `.zshrc` de chaque utilisateur depuis `postinst`.**
  Parcourir `/home/*` en root pour éditer des fichiers personnels est
  précisément ce que la règle « aucun `sudo` que l'utilisateur n'a pas demandé »
  interdit, vue depuis l'autre bout. Casse les homes NFS, ne couvre pas les
  comptes créés ensuite, et n'a aucun chemin de retour propre.
- **Le paquet active pour toute la machine via `/etc/zsh/zshrc`.** Techniquement
  le seul fichier lu par tout zsh interactif sur Debian. Mais imposer un prompt,
  des alias et une intégration IA à tous les comptes d'une machine parce qu'un
  administrateur a tapé `apt install` est un abus. Reste **disponible en
  opt-in** (§ 4.3), jamais par défaut.
- **Faire cohabiter l'auto-update et le paquet** (mise à jour dans un
  sur-dossier utilisateur qui masque l'arbre système). Doublerait le nombre
  d'états possibles, rendrait `doctor` indécidable, et la version affichée ne
  correspondrait plus à celle du gestionnaire. Rejeté : la source de vérité doit
  rester unique.
- **Le manifeste absorbe les fichiers du paquet.** Reviendrait à réimplémenter
  `dpkg` moins bien, et à créer le cas « uninstall Nivuus supprime des fichiers
  que `dpkg` croit toujours présents ».

## 1. Le conflit paquet / auto-update — décision structurante

### 1.1 Règle

**Quand l'installation provient d'un paquet, la mise à jour automatique est
désactivée. Sans exception, sans variable d'échappement.**

Ce n'est pas une préférence de packager, c'est la seule position tenable :

- Sans privilège root, `_nivuus_perform_update` échoue chaque semaine dans un
  processus d'arrière-plan dont la sortie va dans un `mktemp`. C'est un échec
  silencieux permanent — la catégorie de bug que le chantier 2 a explicitement
  refusée (« un avertissement affiché au démarrage d'un shell, dans un processus
  d'arrière-plan, n'est lu par personne »).
- **Avec** privilège root, elle réussit — et c'est pire : `dpkg -V nivuus-shell`
  signale alors des fichiers altérés, `pacman -Qkk` aussi, et le prochain
  `apt upgrade` / `pacman -Syu` écrase le travail de l'updater sans prévenir.
  L'utilisateur revient en arrière sans comprendre pourquoi.
- Le gestionnaire **fait déjà** ce travail, mieux : transactions, dépendances,
  rollback, journal.

Corollaire assumé : la règle **l'emporte sur `ENABLE_AUTOUPDATE=true`** posé par
l'utilisateur dans `~/.zsh_local`. Motif : il n'existe aucune façon d'honorer ce
réglage qui ne produise pas un système incohérent. Le message le dit et propose
l'alternative en une commande (`brew uninstall` puis le one-liner). C'est la
même logique que le refus dur du chantier 2 : quand les deux issues sont
« casser » et « faire semblant », on refuse et on explique.

### 1.2 Détection : un marqueur écrit par le packager, pas une devinette

Quatre mécanismes possibles, un seul retenu comme source de vérité.

| Mécanisme | Verdict |
|---|---|
| Interroger le gestionnaire (`dpkg -S`, `pacman -Qo`, `brew --prefix`) | **Rejeté.** Un `fork`+`exec` d'un binaire lent (`dpkg -S` sur une base complète coûte des dizaines de ms) sur le **chemin de démarrage du shell**, dont le budget total est de 300 ms et vérifié en CI. Et ça échoue quand le gestionnaire n'est pas installé (conteneur dérivé, image `--no-install-recommends`). |
| Heuristique de chemin (`/usr/share`, `/opt/homebrew`) | **Rejeté.** `--prefix` accepte n'importe quel chemin depuis le chantier 1 ; un utilisateur qui installe dans `/opt/nivuus` par le one-liner serait classé « paquet » et perdrait ses mises à jour. Faux positif silencieux. |
| Arbre non inscriptible par l'utilisateur courant | **Retenu comme garde-fou secondaire, pas comme source de vérité.** Vrai pour tout paquet, mais aussi vrai pour un montage en lecture seule, et **faux** pour un shell root sur une machine paquetée — c'est-à-dire faux exactement dans le cas dangereux. |
| **Fichier marqueur posé par la recette de paquet** | **Retenu.** Un `[[ -r ]]` et une lecture de quatre lignes. Aucun processus, aucun réseau, exact par construction : c'est celui qui installe qui déclare comment il installe. |

**Marqueur : `$NIVUUS_SHELL_DIR/.nivuus-origin`**, fichier texte `clé=valeur`,
posé par la recette au même titre que n'importe quel autre fichier du paquet
(donc inventorié par le gestionnaire, donc supprimé avec lui) :

```
origin=package
channel=homebrew          # homebrew | aur | deb
package=nivuus-shell
version=3.2.0
```

Trois règles qui le rendent sûr :

1. **L'absence du fichier vaut `origin=source`.** C'est le comportement
   d'aujourd'hui, mot pour mot. Toutes les installations existantes, et toutes
   les futures installations par `install.sh`, ne voient strictement aucun
   changement. Une régression de ce chantier ne peut donc pas atteindre le canal
   principal.
2. `bin/nivuus install` **n'écrit jamais** `origin=package`. Le seul producteur
   de cette valeur est une recette de paquet. Une valeur inconnue est traitée
   comme `source` (permissif) *sauf* si le garde-fou d'inscriptibilité dit le
   contraire (voir 3).
3. **Garde-fou secondaire, indépendant du marqueur** : `_nivuus_perform_update`
   refuse toute mise à jour destructive si `$NIVUUS_SHELL_DIR` n'est pas
   inscriptible par l'utilisateur courant. Il couvre le cas « un tiers a
   empaqueté Nivuus sans poser le marqueur » — qui arrivera, parce que l'AUR et
   les taps sont ouverts à tous. Le marqueur porte le **message** ; le garde-fou
   porte la **sûreté**. Aucun des deux ne suffit seul.

Lecture côté sh : nouveau module `lib/origin.sh`, cohérent avec la convention
« un module, une responsabilité » du chantier 1 :

```sh
# lib/origin.sh — d'où vient cette installation ? Ne connaît rien d'autre.
nivuus_origin_field() {          # $1 = répertoire d'installation, $2 = clé
    [ -r "$1/.nivuus-origin" ] || return 1
    sed -n "s/^$2=//p" "$1/.nivuus-origin" | head -n1
}
nivuus_origin_is_package() { [ "$(nivuus_origin_field "$1" origin)" = "package" ]; }
```

Lecture côté zsh, dans `config/20-autoupdate.zsh` : **parsée en ligne, sans
sourcer `lib/origin.sh`**. Aucun module de `config/` ne source `lib/*.sh` sur le
chemin de démarrage aujourd'hui (`nivuus-update` le fait pour `lib/migrate.sh`,
mais seulement à l'appel manuel), et le budget de 300 ms est un test qui bloque
les PR. Le coût ajouté au démarrage est **un `stat`** :

```zsh
_nivuus_origin() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin"
    [[ -r "$f" ]] || { print -r -- source; return }
    print -r -- "${$(sed -n 's/^origin=//p' "$f"):-source}"
}
```

Le bloc de démarrage devient :

```zsh
if [[ "$ENABLE_AUTOUPDATE" == "true" ]] \
   && ! _nivuus_is_dev_checkout \
   && ! _nivuus_is_package_install; then
    ...
fi
```

`_nivuus_is_package_install` rejoint `_nivuus_is_dev_checkout` : deux gardes de
même nature, au même endroit, pour la même raison (« l'updater est destructif,
il ne doit pas s'exécuter là où il détruirait autre chose que lui-même »). La
symétrie n'est pas cosmétique : elle garantit qu'on ne peut pas corriger l'une
en oubliant l'autre.

### 1.3 Ce qu'on répond à `nivuus update`

Le message est la moitié de la décision. Un refus sans issue est un bug d'UX.

```
$ nivuus update
Nivuus a été installé par Homebrew ; c'est lui qui gère les mises à jour.

    brew upgrade nivuus-shell

Version installée : 3.2.0
Pour repasser aux mises à jour automatiques de Nivuus :
    brew uninstall nivuus-shell
    curl -fsSL https://raw.githubusercontent.com/.../install.sh | sh
```

**Code de sortie 0.** L'utilisateur a posé une question légitime et a reçu la
réponse exacte ; ce n'est pas un échec. Un code non nul ferait crier les scripts
et les tâches planifiées qui appellent `nivuus update`, sans rien apprendre à
personne. (Le seul cas d'erreur conservé reste le dépôt git hérité, où quelque
chose est réellement cassé.)

La commande affichée est dérivée du champ `channel=`, pas devinée :
`homebrew` → `brew upgrade nivuus-shell`, `aur` → `<votre assistant AUR> -Syu`
(on ne présume pas de `yay` plutôt que `paru`, on nomme les deux),
`deb` → `apt upgrade nivuus-shell` ou, pour un `.deb` téléchargé à la main, le
lien vers la page de release.

### 1.4 Et la péremption ? Aucune sonde réseau par défaut

Un canal paquet retarde. Nivuus **pourrait** vérifier la dernière version et le
signaler sans rien installer. On ne le fait pas par défaut :

- Un paquet Debian ou Arch qui contacte une API tierce sans consentement est un
  rapport de bug, et à raison. C'est le genre de comportement qui fait rejeter
  une soumission et qui, à juste titre, abîme la réputation d'un projet.
- Le gestionnaire prévient déjà l'utilisateur des mises à jour disponibles.
  C'est son travail, il le fait mieux, et il ne le fait qu'à la demande.

`NIVUUS_PACKAGE_UPDATE_NOTIFY=1` active une notification **sans installation**
pour qui la veut. Le défaut est le silence réseau complet.

La péremption d'un canal est surveillée **côté projet** et non côté machine
utilisateur : `packaging-drift.yml` (§ 6.3) échoue bruyamment si un canal n'a pas
la dernière version. C'est au mainteneur de le savoir, pas à chaque shell de
chaque utilisateur de le découvrir.

## 2. Le conflit paquet / manifeste

### 2.1 Ce que devient le manifeste

**Il ne change pas.** Il reste par utilisateur, dans
`~/.local/state/nivuus/manifest.tsv`, et il ne contient que ce que Nivuus a
effectivement écrit dans le domaine de l'utilisateur :

```
#nivuus-manifest v1  installed_at=…  mode=user  dir=/usr/share/nivuus-shell
MODIFY  /home/x/.zshrc          4c81…  a30e…
MKDIR   /home/x/.local/state/nivuus  -  -
CHSH    /home/x                 -      /bin/bash
```

Aucune ligne `CREATE` : rien n'a été créé dans l'arbre partagé. C'est le point
qui rend la cohabitation sûre **sans écrire une ligne de code défensif** — la
règle existante « `CREATE` : suppression seulement si le hash correspond » n'a
même pas l'occasion de s'exécuter sur un fichier du gestionnaire, puisque aucune
entrée `CREATE` ne le désigne. La sûreté vient de l'absence d'entrées, pas d'une
exception.

Le champ d'en-tête `dir=` pointe l'arbre partagé : `doctor` en a besoin, et
c'est une information, pas une revendication de propriété.

**Pas de manifeste système** (`/var/lib/nivuus/`). Il était prévu par le
chantier 1 pour un `--system` qui n'a jamais été livré (`install.sh --system`
sort en erreur aujourd'hui). Un paquet n'en a aucun besoin : sa base **est** son
manifeste, et elle est meilleure que la nôtre.

### 2.2 Ce que fait `nivuus uninstall` en mode paquet

Il fait exactement ce qu'il fait aujourd'hui — rejouer le manifeste — et il
**ajoute une phrase** :

```
$ nivuus uninstall
✓ Bloc Nivuus retiré de ~/.zshrc (contenu d'origine restauré, à l'octet près).
✓ Shell de connexion restauré : /bin/bash

Les fichiers partagés appartiennent à Homebrew et n'ont pas été touchés.
Pour les retirer aussi :  brew uninstall nivuus-shell
```

Trois propriétés à conserver explicitement :

1. `uninstall` **ne supprime jamais** un fichier du domaine du gestionnaire et
   n'appelle jamais le gestionnaire à la place de l'utilisateur. Appeler
   `sudo apt remove` depuis `nivuus uninstall` violerait la règle du chantier 1
   au moment exact où l'utilisateur est le moins attentif.
2. La règle existante « les paquets journalisés en `PKG` ne sont jamais
   désinstallés » s'étend naturellement : on ne présume pas qu'ils étaient là
   pour nous.
3. `--purge` garde son périmètre : état Nivuus de l'utilisateur, jamais
   `~/.zsh_history`, jamais `~/.zsh_local` non créé par Nivuus, et évidemment
   jamais `/usr/share`.

### 2.3 Qui possède le bloc `.zshrc` : `nivuus enable` / `nivuus disable`

**L'utilisateur, toujours.** Le paquet ne le touche pas.

Deux nouveaux verbes, plus une surcharge :

| Commande | En mode source | En mode paquet |
|---|---|---|
| `nivuus install` | inchangé (copie l'arbre + écrit le bloc) | **équivaut à `enable`** : n'écrit que le bloc, et le dit |
| `nivuus enable` | alias de `install` sans copie d'arbre | écrit le bloc `.zshrc` (+ `chsh` optionnel), journalisé |
| `nivuus disable` | retire le bloc, laisse l'arbre | retire le bloc |
| `nivuus uninstall` | inchangé | équivaut à `disable` + la phrase du § 2.2 |

Pourquoi surcharger `install` plutôt qu'exiger le nouveau verbe : un utilisateur
qui vient de taper `brew install nivuus-shell` tapera `nivuus install`. Lui
répondre « commande invalide » serait une friction gratuite, dans un chantier
dont le nom est « friction zéro ». Les verbes explicites existent pour les
scripts, la documentation et les `caveats`, où l'ambiguïté coûte plus que la
verbosité.

Le `postinst` / `caveats` / `.install` de chaque format ne fait qu'**afficher**
la ligne :

```
Nivuus est installé pour la machine. Pour l'activer dans ton shell :
    nivuus enable
```

Rien d'autre. Pas de `chsh` automatique, pas d'écriture dans un `$HOME`, pas de
`systemctl`.

### 2.4 Le bloc doit survivre à la disparition de l'arbre

Le paquet peut partir alors que le bloc reste — c'est le cas normal, pas le cas
dégradé (`brew uninstall` n'a aucun moyen de savoir qui a activé quoi). Le bloc
actuel casserait tous les shells :

```zsh
source "$NIVUUS_SHELL_DIR/.zshrc"          # aujourd'hui : erreur à chaque prompt
```

Décision : **`nivuus_zshrc_block` émet une garde, dans tous les modes**, pas
seulement en mode paquet.

```zsh
# >>> nivuus shell >>>
export NIVUUS_SHELL_DIR="/usr/share/nivuus-shell"
[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"
# <<< nivuus shell <<<
```

Trois raisons de généraliser au lieu de brancher sur le mode :

1. Elle couvre aussi le `rm -rf ~/.nivuus-shell` à la main, qui arrive déjà
   aujourd'hui et produit le même shell cassé.
2. Un bloc identique dans les quatre canaux est un bloc dont le comportement est
   prouvé une fois. Une variante par canal est une variante non testée.
3. Coût : un `[ -r ]` par ouverture de shell, sous le seuil de mesure.

Contrepartie honnête : la garde **masque** une installation cassée au lieu de la
signaler. C'est pour ça que `nivuus doctor` doit détecter le cas « bloc présent,
arbre absent » et le nommer, avec la commande de réparation. Le silence au
démarrage, le diagnostic à la demande.

## 3. Travail de noyau préalable, commun aux trois formats

Cette phase ne livre aucun paquet et doit être mergée avant tout format. Elle
est utile seule.

### 3.1 `bin/nivuus` doit résoudre les liens symboliques

Aujourd'hui :

```bash
NIVUUS_SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

Sous `/usr/bin/nivuus -> /usr/share/nivuus-shell/bin/nivuus`, `BASH_SOURCE`
vaut le **lien**, pas la cible : la racine calculée est `/usr`, et le premier
`. "$NIVUUS_SRC_ROOT/lib/log.sh"` échoue. C'est le mode d'installation par
défaut d'un `PKGBUILD` et de `bin.install_symlink`, donc ça casserait deux
formats sur trois dès le premier essai.

`readlink -f` n'est pas une option : absent en BSD/macOS avant coreutils. Boucle
de résolution POSIX (bornée, pour ne pas boucler sur un cycle) :

```sh
_self="${BASH_SOURCE[0]}"
_n=0
while [ -L "$_self" ] && [ "$_n" -lt 32 ]; do
    _link="$(ls -ld -- "$_self" | sed 's/.*-> //')"
    case "$_link" in
        /*) _self="$_link" ;;
        *)  _self="$(dirname -- "$_self")/$_link" ;;
    esac
    _n=$((_n + 1))
done
NIVUUS_SRC_ROOT="$(cd -- "$(dirname -- "$_self")/.." && pwd)"
```

Testable sans paquet : `tests/unit/test_lib_selfpath.bats` crée un lien, un lien
de lien et un lien relatif dans un `mktemp -d` et vérifie la racine obtenue.
C'est un test unitaire pur, il tourne sur PR, et il attrape la régression avant
qu'un packager ne la découvre.

### 3.2 Ne pas écrire de `.zwc` dans un arbre qu'on ne possède pas

`config/99-cleanup.zsh` compile `$NIVUUS_SHELL_DIR/config/*.zsh` sur place.
Condition ajoutée : **ne compiler que si l'arbre est inscriptible ET que
l'origine est `source`**. Deux conditions plutôt qu'une : l'inscriptibilité
protège l'utilisateur normal, l'origine protège le shell root sur machine
paquetée — le cas où l'écriture réussirait et laisserait des orphelins que
`apt purge` ne nettoie pas.

Et le coût en démarrage ? L'arbre partagé n'est alors **jamais** compilé.

Décision : **on ne livre pas de `.zwc` dans les paquets, et on mesure avant de
décider d'une compensation.** Motifs :

- Un `.zwc` porte une version de format ; compilé sur le runner de build avec
  une version de zsh, il peut être inutilisable sur la machine cible. Un
  bytecode ignoré est au mieux inutile, au pire une source de bug rapporté comme
  « Nivuus ne charge pas mon module ». Le chantier 1 a déjà rencontré ce genre
  d'effet (un `.zwc` périmé masquant le source, d'où les `rm -f config/*.zwc`
  dans la CI).
- Un paquet dont le contenu dépend de la version de zsh du runner de build
  n'est plus `Architecture: all` en pratique.

Repli **conçu mais non livré**, si la mesure montre que le budget de 300 ms
saute : compiler dans un cache par utilisateur
(`${XDG_CACHE_HOME:-~/.cache}/nivuus-shell/zwc/`) et **sourcer explicitement le
`.zwc`** — zsh sait sourcer un `.zwc` directement, ce qui contourne la règle
« le bytecode doit être à côté du source ». Le cache par utilisateur est
inscriptible, versionné par la version de zsh et par celle de Nivuus, et sa
suppression est déjà couverte par `uninstall --purge`. On ne l'écrit que si le
chiffre le demande.

**Livrable de mesure de la phase 0** : le temps de démarrage sur les six
conteneurs de la matrice, avec et sans `.zwc`. La performance est un test
bloquant dans ce projet ; elle ne se traite pas à l'estime.

### 3.3 Un seul arbre, aucune disposition spécifique à un canal

**Le contenu d'un paquet est une copie bit-pour-bit de l'arbre de release**,
plus le seul `.nivuus-origin`. Pas de `.zshrc` renommé, pas de `lib/` déplacé,
pas de chemins réécrits par `sed` au moment du build.

C'est la règle qui rend ce chantier maintenable : une divergence de disposition
par canal, c'est trois comportements à tester, trois façons de casser, et un
`doctor` qui doit connaître les trois. Avec un arbre identique, **un seul script
de preuve** (§ 6) couvre les trois formats, et un bug reproduit sur Debian se
reproduit sur Arch.

Conséquence acceptée : `/usr/share/nivuus-shell/.zshrc` est un fichier caché
dans `/usr/share`. C'est inhabituel et parfaitement légal. Le renommer coûterait
une divergence permanente pour un gain esthétique.

### 3.4 `doctor` apprend le mode paquet

`nivuus doctor` affiche l'origine, le canal, la version du paquet, l'état de
l'activation, et sait diagnostiquer les trois nouveaux cas :
« bloc présent, arbre absent » (§ 2.4), « paquet installé, jamais activé »,
« arbre paquet altéré » (le hash d'un fichier diverge → renvoie vers
`dpkg -V` / `pacman -Qkk` / `brew reinstall`, sans réparer soi-même).

## 4. Ce que chaque écosystème exige

### 4.1 Homebrew — tap dédié

**Tap dédié `maximeallanic/homebrew-tap`, pas `homebrew-core`.** Arguments :

- `homebrew-core` impose des critères de notoriété (étoiles, forks, âge) que le
  projet n'a pas encore et qui ne dépendent pas de la qualité du code ; une
  soumission prématurée est refusée et coûte du temps.
- Chaque version passe par une PR dans `homebrew-core` avec sa file d'attente et
  sa CI ; le canal deviendrait le facteur limitant de la cadence de release.
- Le fichier de formule est **le même dans les deux cas**. Migrer vers `core`
  plus tard, si la notoriété le permet, est un déplacement de fichier — la
  décision d'aujourd'hui ne ferme rien.

Installation : `brew install maximeallanic/tap/nivuus-shell` — et
`brew tap maximeallanic/tap && brew install nivuus-shell` pour la forme longue.
La même formule sert **macOS et Linuxbrew** : c'est le meilleur rapport
couverture/travail des trois formats.

```ruby
class NivuusShell < Formula
  desc "Modern zero-config ZSH environment"
  homepage "https://github.com/maximeallanic/nivuus-shell"
  url "https://github.com/maximeallanic/nivuus-shell/releases/download/v3.2.0/nivuus-shell-v3.2.0.tar.gz"
  sha256 "…"                 # repris de SHA256SUMS **vérifié par signature**
  license "MIT"

  # macOS fournit zsh ; sur Linux, brew l'installe. C'est exactement le
  # primitif prévu pour ça — un depends_on "zsh" inconditionnel imposerait
  # un zsh brew aux macOS, donc le problème /etc/shells + chsh que le
  # chantier 1 a passé du temps à rendre inoffensif.
  uses_from_macos "zsh"

  def install
    libexec.install Dir["*"]           # arbre bit-pour-bit
    (libexec/".nivuus-origin").write <<~EOS
      origin=package
      channel=homebrew
      package=nivuus-shell
      version=#{version}
    EOS
    # write_env_script et non install_symlink : le script fixe
    # NIVUUS_SHELL_DIR et évite de dépendre de la résolution de lien
    # (qu'on corrige par ailleurs, § 3.1 — ceinture et bretelles, parce
    # que ce chemin-là est celui que brew audit exerce).
    (bin/"nivuus").write_env_script libexec/"bin/nivuus",
                                    NIVUUS_SHELL_DIR: libexec
  end

  def caveats
    <<~EOS
      Pour activer Nivuus dans ton shell :
          nivuus enable
      Les mises à jour passent par Homebrew : brew upgrade nivuus-shell
    EOS
  end

  test do
    assert_match "Nivuus", shell_output("#{bin}/nivuus help")
    assert_match "package", (libexec/".nivuus-origin").read
    system "zsh", "-c", "NIVUUS_SHELL_DIR=#{libexec} source #{libexec}/.zshrc"
  end
end
```

- **Versionnement** : `url` sur l'asset de release versionné + `sha256`. Pas de
  `head do` (une formule `HEAD` sur un projet qui se met à jour tout seul est un
  piège : `origin=package` y serait faux ou absent).
- `fzf`, `git`, `bat`, `eza`, `grc` **ne sont pas** des dépendances de formule.
  La politique du chantier 1 est la dégradation gracieuse ; en faire des
  `depends_on` transformerait `brew install nivuus-shell` en installation de
  cinq paquets non demandés. Ils sont mentionnés dans les `caveats`.
- Qualité : `brew style` et `brew audit --strict` dans la CI du tap.

### 4.2 AUR — un seul paquet, `nivuus-shell`

**Pas de couple `nivuus-shell` / `nivuus-shell-bin`.** La convention `-bin`
existe pour distinguer une compilation locale d'un binaire précompilé. Nivuus
n'a pas de binaire : le tarball de release et les « sources » sont le même
fichier. Publier les deux, ce serait deux paquets identiques, deux `.SRCINFO` à
tenir, et une question récurrente sur le forum. Un seul paquet, construit depuis
le tarball de release signé.

Fait notable : Nivuus a malgré tout une **vraie étape de build** — la
compilation `.zwc` — mais le § 3.2 a décidé de ne pas l'exécuter. Le `build()`
reste donc vide, et c'est documenté dans le `PKGBUILD` plutôt que caché.

```bash
pkgname=nivuus-shell
pkgver=3.2.0
pkgrel=1
pkgdesc="Modern zero-config ZSH environment"
arch=('any')
url="https://github.com/maximeallanic/nivuus-shell"
license=('MIT')
depends=('zsh')
optdepends=('fzf: complétion et recherche d'historique interactives'
            'git: segment git du prompt'
            'bat: coloration de cat'
            'eza: coloration de ls'
            'grc: coloration de commandes')
source=("$pkgname-$pkgver.tar.gz::$url/releases/download/v$pkgver/nivuus-shell-v$pkgver.tar.gz"
        "$pkgname-$pkgver.tar.gz.asc::$url/releases/download/v$pkgver/nivuus-shell-v$pkgver.tar.gz.asc")
sha256sums=('…' 'SKIP')
validpgpkeys=('<empreinte longue de la clé GPG de release>')
install=nivuus-shell.install

package() {
  install -d "$pkgdir/usr/share/nivuus-shell"
  cp -a "$srcdir/"* "$pkgdir/usr/share/nivuus-shell/"   # arbre bit-pour-bit
  printf 'origin=package\nchannel=aur\npackage=%s\nversion=%s\n' \
      "$pkgname" "$pkgver" > "$pkgdir/usr/share/nivuus-shell/.nivuus-origin"
  install -d "$pkgdir/usr/bin"
  ln -s /usr/share/nivuus-shell/bin/nivuus "$pkgdir/usr/bin/nivuus"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

- **`validpgpkeys` impose une décision au chantier 2.** `makepkg` vérifie
  nativement une signature GPG **de l'archive elle-même**, alors que le
  chantier 2 ne signe que `SHA256SUMS`. Deux issues : se contenter de
  `sha256sums=()` (courant, et l'empreinte est lue dans le `PKGBUILD` que
  l'utilisateur peut inspecter), ou **publier en plus un
  `nivuus-shell-vX.Y.Z.tar.gz.asc`**. On choisit la seconde : c'est une étape de
  quatre lignes dans un job qui manipule déjà la clé GPG, c'est le mécanisme
  natif que les utilisateurs Arch attendent, et cela **répond concrètement à la
  question ouverte n° 4 du chantier 2** (« faut-il produire le `.asc` avant
  qu'un mainteneur de paquet ne le demande ? » — oui : ce mainteneur, c'est
  nous, et c'est maintenant).
- `.SRCINFO` est régénéré par `makepkg --printsrcinfo > .SRCINFO` et commité :
  l'AUR le refuse s'il diverge du `PKGBUILD`. C'est la panne n° 1 des paquets
  AUR automatisés, donc la CI **compare** le `.SRCINFO` régénéré à celui commité
  avant de pousser.
- `nivuus-shell.install` : `post_install()` et `post_upgrade()` affichent la
  ligne `nivuus enable`. Rien d'autre — un `.install` qui touche à `$HOME` est
  contraire aux règles de packaging Arch.
- `namcap PKGBUILD` et `namcap *.pkg.tar.zst` dans la CI.
- **`nivuus-shell-git`** (paquet VCS suivant `master`) : hors périmètre. Cible
  mouvante, invérifiable en CI, et il attirerait des rapports de bug sur du code
  non publié. Ajoutable plus tard sans rien changer.
- Action de phase 1, indépendante du code : **réserver le nom `nivuus-shell` sur
  l'AUR**. Le nom est premier arrivé, premier servi ; se le faire prendre par un
  tiers bien intentionné coûte bien plus cher que dix minutes aujourd'hui.

### 4.3 Debian — un `.deb` attaché à la release, pas de dépôt APT

**Arbitrage explicite : `.deb` attaché à la release GitHub.** Un vrai dépôt APT
est un engagement d'infrastructure permanent :

- une **seconde** clé de signature, distincte de celle des releases (un dépôt
  APT signe son `InRelease`, pas les artefacts), donc un second cycle de
  rotation, de sauvegarde et de révocation à tenir — alors que le chantier 2 a
  documenté à quel point ce cycle est coûteux et risqué ;
- un paquet `nivuus-shell-keyring` à publier et à maintenir, sous peine
  d'apprendre à des utilisateurs à `curl | apt-key add` (déprécié et
  dangereux) ;
- la régénération de `Packages`, `Release`, `InRelease` à chaque publication,
  et surtout la **promesse implicite que l'URL vivra des années** : un
  `sources.list` cassé produit une erreur à chaque `apt update` de chaque
  machine, indéfiniment. C'est la dette la plus longue du chantier.

Ce qu'on perd en s'en passant : la mise à jour automatique côté Debian. C'est
acceptable ici précisément parce que **le mode paquet désactive de toute façon
l'auto-update** (§ 1) : l'utilisateur qui choisit le `.deb` choisit un canal
manuel, et `nivuus update` le lui dit avec le lien exact. L'utilisateur
Debian/Ubuntu qui veut des mises à jour automatiques a déjà le one-liner, qui le
sert parfaitement — le `.deb` sert un autre besoin : le déploiement par
configuration système (Ansible, image de base, poste managé), où l'automatisme
est justement indésirable.

**Chemin d'évolution costé, non engagé** : un dépôt APT **statique sur GitHub
Pages** (`apt-ftparchive` en CI, aucun serveur, hébergement déjà payé). C'est un
job de plus et une clé de plus, pas une infrastructure. À rouvrir quand les
compteurs de téléchargement du `.deb` le justifient, pas avant. **Debian
officiel** (parrainage par un Debian Developer, `mentors.debian.net`) est hors
périmètre : plusieurs mois, un mainteneur externe, et des contraintes de
politique qui piloteraient nos choix de code.

Construction : **arbre de staging + `dpkg-deb --build --root-owner-group`**,
sans `debhelper` ni `debian/rules`. Motif : la cérémonie d'un paquet source
Debian n'achète quelque chose *que* si l'on vise l'archive officielle. Pour un
`.deb` binaire `Architecture: all` sans compilation, elle ajoute une chaîne
d'outils dans la CI et zéro garantie. Décision à revisiter si l'archive
officielle devient un objectif — et alors c'est une réécriture du job, pas du
produit.

```
debian/control (contenu du champ, staging)
    Package: nivuus-shell
    Version: 3.2.0
    Architecture: all
    Section: shells
    Priority: optional
    Depends: zsh
    Recommends: git, curl, fzf
    Suggests: bat, eza, grc
    Maintainer: Maxime Allanic <…>
    Description: Modern zero-config ZSH environment
     …
```

`Depends: zsh` seul. `curl` est en `Recommends` et non en `Depends` : depuis le
chantier 1 il n'est requis que par l'installeur et l'updater, tous deux
inutilisés en mode paquet. Faire de `fzf` une dépendance dure contredirait la
dégradation gracieuse.

`postinst` :

```sh
#!/bin/sh
set -e
case "$1" in
  configure)
    echo "Nivuus est installé pour la machine."
    echo "Pour l'activer dans ton shell :  nivuus enable"
    ;;
esac
exit 0
```

Aucune écriture, aucun parcours de `/home`, aucun `chsh`, aucun `update-shells`
(le paquet `zsh` s'en charge déjà). Idempotent, et il ne peut pas échouer —
un `postinst` qui échoue laisse le paquet en état `half-configured` et bloque
`apt`, ce qui est une bien plus grosse panne que l'absence du message.

`prerm` : rappelle que l'activation par utilisateur subsiste et indique
`nivuus disable`. Il ne la retire **pas** — c'est le § 2.4 (bloc gardé) qui rend
l'oubli inoffensif. `postrm purge` : rien à faire, aucun fichier de conf sous
`/etc`.

Qualité : **`lintian` en CI**. Il signalera `binary-without-manpage` ; on écrit
donc un `nivuus.1` minimal, dérivé de `nivuus help` qui existe déjà, installé
dans `/usr/share/man/man1/` par les trois formats. C'est le seul fichier
réellement nouveau que ce chantier ajoute à l'arbre.

**RPM (Fedora / openSUSE)** : hors périmètre, nommé pour qu'on n'ait pas à s'en
demander. Fedora est déjà couvert par la matrice de test et par le one-liner ;
un quatrième canal avant que les trois premiers n'aient fait leurs preuves
serait de la surface pour rien.

## 5. Automatisation de la publication

### 5.1 Le principe : les canaux ne sont jamais écrits à la main

Un canal mis à jour à la main n'est mis à jour qu'une fois. Les trois formules
sont **générées** à partir d'une source unique — la release publiée — et
poussées par la CI.

Nouveau workflow **`packaging.yml`**, déclenché par `workflow_run` à la fin d'un
`release.yml` réussi, et aussi par `workflow_dispatch` avec une **entrée
`version`** : republier un canal pour une version passée doit être une opération
d'une minute. Les taps et l'AUR cassent pour des raisons qui ne sont pas les
nôtres ; la re-jouabilité n'est pas un luxe.

```yaml
jobs:
  verify:            # commun aux trois : rien n'est empaqueté sans preuve
  homebrew:  { needs: verify, environment: packaging }
  aur:       { needs: verify, environment: packaging }
  deb:       { needs: verify, environment: packaging }
```

### 5.2 Réutilisation de la signature du chantier 2

Le job `verify` est le pivot. Il fait, avec les clés publiques **commitées dans
le dépôt** :

```sh
gh release download "v$VERSION" -p 'nivuus-shell-v*.tar.gz' -p 'SHA256SUMS*'
# 1. authenticité : la même vérification que le client utilisateur
openssl dgst -sha256 -verify keys/nivuus-release-2026.pem \
    -signature SHA256SUMS.sig SHA256SUMS
# 2. intégrité : et seulement ensuite
grep "nivuus-shell-v$VERSION.tar.gz" SHA256SUMS | sha256sum -c -
```

Ordre non négociable, identique à celui du client : **signature d'abord,
empreinte ensuite**. Le `sha256` recopié dans la formule Homebrew et dans le
`PKGBUILD` provient de ce `SHA256SUMS` **authentifié**, jamais d'un
`sha256sum` recalculé sur un fichier retéléchargé sans vérification. Sinon le
packager devient le maillon faible du dispositif que le chantier 2 a construit :
un attaquant qui substitue l'asset entre la release et le job de packaging
verrait son empreinte publiée dans trois formules signées de notre nom.

Si `verify` échoue, **aucun canal n'est publié**. Fail-closed, comme partout
ailleurs dans ce projet.

Debian a en plus sa signature propre si le dépôt APT est un jour ouvert
(`InRelease`, clé distincte, § 4.3). Un `.deb` isolé n'est pas signé en soi —
`dpkg-sig` existe mais n'est plus utilisé en pratique ; l'authenticité du `.deb`
attaché repose sur `SHA256SUMS` de la release, qui est signé. On le documente
ainsi plutôt que d'ajouter un mécanisme que personne ne vérifie.

### 5.3 Cloisonnement des secrets

Les trois canaux ont besoin d'écrire ailleurs : un jeton pour le tap, une clé
SSH pour l'AUR, un jeton pour l'upload d'asset.

**Environnement `packaging`, distinct de `release`.** Le chantier 2 a fait de
l'environnement `release` le cœur du dispositif : seuls les jobs qui le
déclarent lisent la clé de signature. Mettre les jetons de packaging dans le
même environnement dissoudrait cette propriété — un canal compromis pourrait
alors signer. Avec deux environnements, la compromission d'un jeton de tap
permet de publier une **mauvaise formule**, ce qui est grave, mais **pas** de
produire une release signée, ce qui serait fatal.

Secrets : `HOMEBREW_TAP_TOKEN` (write sur le seul dépôt du tap), `AUR_SSH_KEY`
(clé de déploiement du seul dépôt AUR), `GITHUB_TOKEN` du dépôt pour
`gh release upload`.

### 5.4 Politique d'échec : un canal rouge ne rétracte pas une release

Si le job `aur` échoue, la release **reste publiée**. Elle est signée, vérifiée,
et les utilisateurs du one-liner en dépendent déjà. Faire échouer une release
parce qu'un push SSH vers `aur.archlinux.org` a expiré serait échanger une panne
mineure contre une panne majeure.

Le job échoué : ouvre (ou met à jour) une issue avec l'étiquette `packaging`,
marque le résumé du workflow en rouge, et reste re-jouable seul via
`workflow_dispatch`.

Distinction à garder claire avec le chantier 2 : « aucune release ne sort si un
test est rouge » porte sur ce qui est **pré-publication**. La synchronisation
des canaux est **post-publication** ; ce n'est pas la même transaction.

### 5.5 Anti-pourrissement : `packaging-drift.yml`

Nocturne, sans secret, lecture seule :

- version de la dernière release GitHub ;
- version dans la formule du tap (lecture brute du fichier) ;
- version dans l'AUR (RPC `https://aur.archlinux.org/rpc/v5/info?arg=nivuus-shell`) ;
- présence du `.deb` de cette version dans les assets.

Toute divergence de plus de 24 h fait échouer le job. C'est le pendant exact du
« canari nocturne » du chantier 2 : le mainteneur apprend la panne, pas
l'utilisateur.

## 6. Tests

Même exigence de preuve que le reste du projet : **installer pour de vrai,
vérifier, désinstaller, prouver l'absence de trace**.

### 6.1 Un seul script de preuve, trois formats

`tests/ci/run-package-target.sh`, du même modèle que
`tests/ci/run-target.sh` : toute la logique de preuve dans le script, rien dans
le YAML, donc rejouable en local par `docker run … ./tests/ci/run-package-target.sh deb`.
Le § 3.3 (arbre identique) est ce qui permet un script unique paramétré par le
format.

Séquence, identique pour les trois :

| # | Étape | Assertion |
|---|---|---|
| 1 | Construire le paquet depuis une release **fixture** servie en `file://` (mécanisme déjà utilisé par `tests/e2e/test_update_signature.bats` et `tests/helpers/release.bash`) | le paquet se construit sans réseau |
| 2 | Installer avec le vrai gestionnaire : `apt-get install ./nivuus-shell_*.deb` / `pacman -U` / `brew install --formula ./Formula/nivuus-shell.rb` | code 0 |
| 3 | `command -v nivuus`, `nivuus doctor` | trouvé, diagnostic sain, **origine `package` et canal correct** |
| 4 | `nivuus update` | affiche la commande du gestionnaire, **sort en 0**, ne télécharge rien |
| 5 | Ouvrir **trois** shells interactifs réels, puis inspecter `~/.nivuus-shell-last-update-check` | **le fichier n'existe pas** — preuve observable que `_nivuus_check_update_async` ne s'est jamais exécuté. C'est l'invariant n° 1 du chantier. |
| 6 | Empreinte de `$HOME` (`tests/helpers/fingerprint.bash`) → `nivuus enable` → `zsh -i -c 'echo OK'` | stderr **vide**, prompt fonctionnel |
| 7 | `nivuus disable` → empreinte de `$HOME` | **égalité stricte** avec l'empreinte de l'étape 6 |
| 8 | Retirer le paquet : `apt-get purge` / `pacman -Rns` / `brew uninstall` | plus aucun fichier sous le préfixe, base du gestionnaire cohérente (`dpkg -V` muet, `pacman -Qkk` muet) |
| 9 | **Paquet retiré alors que l'activation subsiste** : réactiver, retirer le paquet, ouvrir un shell interactif | **aucune erreur sur stderr** — c'est ce qui paie la garde du § 2.4. Invariant n° 2. |
| 10 | Sur `deb` et `aur` : lancer un shell **root** sur la machine paquetée, vérifier `/usr/share/nivuus-shell/config/` | **aucun `.zwc` créé** (§ 3.2) |

Les étapes 5 et 9 sont aux paquets ce que les cas 3 et 9 du chantier 2 sont à la
signature : si elles passent, la propriété existe ; si elles manquent, le reste
est décoratif. Elles portent donc un commentaire `INVARIANT:` et `tests.yml`
vérifie par `grep` qu'elles n'ont pas disparu — le garde-fou anti-suppression
existe déjà dans ce dépôt pour la signature, on l'étend.

### 6.2 Où ça tourne

Ce que la CI sait déjà faire est réutilisé tel quel : `.github/matrix.json`
fournit déjà `debian:12`, `ubuntu:22.04`, `ubuntu:24.04`, `archlinux:latest` et
le runner `macos-latest`. `.github/actions/setup-tests`, `tests/ci/bats-run.sh`
et `tests/helpers/fingerprint.bash` sont réutilisés sans modification.

| Cible | Format | Support | Fréquence |
|---|---|---|---|
| `debian:12`, `ubuntu:24.04` | `.deb` | conteneur de la matrice | nightly + release |
| `archlinux:latest` | AUR | conteneur de la matrice (`makepkg` exige un utilisateur non-root : un compte `builder` est créé dans le script) | nightly + release |
| `macos-latest` | Homebrew | runner, `brew` préinstallé | nightly + release |
| Linuxbrew | Homebrew | conteneur `homebrew/brew` | **nightly seulement** — image lourde, et le chemin est déjà couvert par macOS |

**Budget CI.** Le chantier 1 a posé la règle : PR rapide, matrice la nuit,
tout au moment de la release. On la respecte.

- **Sur PR** : uniquement la couche statique et rapide (~30 s) — `shellcheck`
  sur `postinst`/`prerm`/`PKGBUILD`, `lintian` sur un `.deb` construit
  localement, contrôle que `.SRCINFO` correspond au `PKGBUILD`, `brew style` sur
  la formule, et les tests unitaires nouveaux (`test_lib_origin.bats`,
  `test_lib_selfpath.bats`, `test_zshrc_block_guard.bats`, `test_autoupdate_package_mode.bats`).
  Aucun conteneur n'est tiré.
- **Nightly** : `run-package-target.sh` sur les quatre cibles.
- **Sur release** : les quatre cibles, **bloquantes pour la publication du
  canal** (pas pour la release elle-même, § 5.4).

### 6.3 Ce que les tests ne prouvent pas

À dire, comme la CI dit déjà que le job WSL est une simulation :

- Installer une formule **localement** (`brew install --formula ./…rb`) ne prouve
  pas que le tap est correctement publié ni que `brew install user/tap/nivuus-shell`
  fonctionne. Ce dernier point est couvert par `packaging-drift.yml` (§ 5.5) et
  par un test hebdomadaire qui installe **depuis le vrai tap**.
- Un `makepkg` local ne prouve pas que l'AUR a accepté le push. Idem, c'est le
  rôle de la sonde de dérive.
- Aucun test ne prouve le comportement sur une machine où un **autre**
  gestionnaire a déjà installé Nivuus. Le cas « deux installations
  concurrentes » est traité par `doctor` (diagnostic), pas par la CI.

## 7. Périmètre

### Inclus

Mode paquet du noyau (marqueur `.nivuus-origin`, `lib/origin.sh`, refus de
l'auto-update, garde-fou d'inscriptibilité, message de `nivuus update`) ;
`nivuus enable` / `nivuus disable` et la surcharge d'`install`/`uninstall` en
mode paquet ; garde du bloc `.zshrc` ; résolution des liens symboliques dans
`bin/nivuus` ; non-compilation `.zwc` hors arbre possédé, avec mesure du coût ;
formule Homebrew et tap ; `PKGBUILD` + `.SRCINFO` + `.install` AUR ; `.deb`
attaché à la release avec `postinst`/`prerm` ; page de manuel `nivuus.1` ;
signature GPG détachée **de l'archive** ajoutée à `release.yml` pour
`validpgpkeys` ; `packaging.yml` et `packaging-drift.yml` ; `run-package-target.sh`
et sa place dans la matrice ; documentation d'installation par canal dans
`doc/INSTALL.md` et politique de canal dans un `doc/PACKAGING.md`.

### Hors périmètre

- **Dépôt APT** (et la clé de dépôt, le paquet keyring, `apt-ftparchive`) —
  arbitré au § 4.3, chemin d'évolution documenté et costé, non engagé.
- **Debian officiel / Ubuntu PPA / homebrew-core** — dépendent de tiers et de
  seuils de notoriété ; à rouvrir quand les compteurs le justifient.
- **RPM, Nix, Snap, Flatpak, MacPorts, Scoop, Chocolatey** — nommés pour être
  écartés. Trois canaux non pourris valent mieux que sept canaux morts.
- **`nivuus-shell-git`** sur l'AUR (§ 4.2).
- **Installation système multi-utilisateur activée par défaut** (`--system`,
  `/etc/zsh/zshrc`) — reste indisponible ; le drop-in administrateur est
  documenté, pas automatisé.
- **Builds reproductibles** des paquets — souhaitable, hors sujet ici (et déjà
  hors périmètre du chantier 2).
- **Migration automatique d'une installation source vers un paquet** (et retour).
  `doctor` détecte et explique ; il ne convertit pas. Convertir signifierait
  supprimer un arbre pour en poser un autre, et le manifeste d'origine
  deviendrait faux à mi-chemin.

## 8. Séquence de livraison

Cinq phases, chacune mergeable seule.

0. **Noyau paquet** — `.nivuus-origin`, `lib/origin.sh`, refus de l'auto-update
   et garde-fou d'inscriptibilité, `nivuus enable`/`disable`, message de
   `nivuus update`, garde du bloc `.zshrc`, résolution des liens symboliques,
   `.zwc` non écrits hors arbre possédé + **mesure du coût de démarrage**,
   `doctor` enrichi, `nivuus.1`. **Aucun paquet livré.**
   *Sortie : les tests unitaires nouveaux sont verts ; un arbre posé à la main
   sous `/usr/share` avec un `.nivuus-origin` se comporte déjà correctement —
   c'est un test e2e, sans aucun gestionnaire de paquets ; et les installations
   par le one-liner sont bit-pour-bit inchangées.*

1. **Homebrew** — tap créé, formule générée, job `homebrew` de `packaging.yml`,
   `run-package-target.sh` sur `macos-latest`, `verify` réutilisant la signature.
   *Sortie : `brew install maximeallanic/tap/nivuus-shell` puis `nivuus enable`
   fonctionne sur macOS ; la désinstallation ne laisse aucune trace ; la release
   suivante met le tap à jour toute seule.*

2. **AUR** — nom réservé, `PKGBUILD`, `.SRCINFO`, `.install`, `.asc` de
   l'archive ajouté à `release.yml`, job `aur`, cible Arch de la matrice.
   *Sortie : `makepkg -si` depuis l'AUR installe, `namcap` est muet, la
   signature GPG est vérifiée par `makepkg` lui-même.*

3. **Debian** — staging + `dpkg-deb`, `postinst`/`prerm`, `lintian`, job `deb`,
   cibles Debian/Ubuntu.
   *Sortie : `apt install ./nivuus-shell_*.deb` puis `apt purge` laissent la
   base `dpkg` cohérente et `$HOME` bit-identique.*

4. **Gouvernance des canaux** — `packaging-drift.yml`, test hebdomadaire
   d'installation **depuis les vrais canaux**, `doc/PACKAGING.md` (dont la
   politique d'abandon du § 9), README et `doc/INSTALL.md` par canal.
   *Sortie : une dérive de canal est détectée en moins de 24 h, et la procédure
   d'abandon est écrite avant d'en avoir besoin.*

**Pourquoi Homebrew en premier.** Trois raisons, dans l'ordre :

1. **L'audience est là où vise le produit.** « Shell zéro-config premium pour
   qui ne veut pas passer trois jours dans ses dotfiles » décrit d'abord un
   développeur macOS ; `brew install` est le premier réflexe et la première
   demande qui arrivera.
2. **Meilleure couverture par unité de travail** : une seule formule sert macOS
   **et** Linuxbrew, et elle exerce d'emblée le chemin le plus fragile
   (`libexec` + wrapper, § 3.1) sur la plateforme la plus contrainte.
3. Un tap est un simple dépôt git : aucun compte à obtenir, aucune revue
   externe, publication immédiate et rétractable.

**Contre-argument assumé** : l'AUR est plus rapide à livrer (un `PKGBUILD` de
trente lignes, un conteneur Arch déjà dans la matrice, des utilisateurs
tolérants) et exerce plus durement les contraintes « ne touche pas à `$HOME` » et
« construis depuis la source signée ». Si la phase 0 déborde, échanger les
phases 1 et 2 est sans conséquence : elles ne dépendent que de la phase 0, pas
l'une de l'autre. Debian reste en dernier dans les deux cas — c'est le canal au
plus faible rapport valeur/travail, puisqu'il n'apporte pas de mise à jour
automatique et que son public est exactement celui que le one-liner sert déjà
le mieux.

## 9. Risques

**Trois canaux à maintenir pour toujours** — le risque dominant, et il est
structurel, pas technique. Chaque canal a sa culture de revue, ses conventions,
ses ruptures unilatérales (Homebrew a déjà déprécié `depends_on :optional`, les
règles de l'AUR bougent, la politique Debian aussi). Mitigation : génération
automatique depuis une source unique (§ 5), sonde de dérive (§ 5.5), un script
de preuve unique rendu possible par l'arbre identique (§ 3.3). Ce qu'on ne
mitige pas : le temps d'attention du mainteneur. C'est le vrai coût, et il est
assumé en connaissance de cause.

**Un canal abandonné est pire que pas de canal** — parce que le mode paquet
désactive délibérément l'auto-update. Un utilisateur sur un canal mort est figé
sur une version, sans mise à jour de sécurité, et **sans avertissement**.
C'est le risque le plus grave du chantier, et il est créé par sa décision
centrale. Trois mitigations, toutes nécessaires :

1. `.nivuus-origin` enregistre le canal, donc `doctor` peut nommer précisément
   la situation et donner la sortie (retirer le paquet, lancer le one-liner).
2. **Politique d'abandon écrite avant le premier abandon** (`doc/PACKAGING.md`) :
   un canal est annoncé mort **deux releases à l'avance**, et le dernier paquet
   publié affiche la migration dans son `postinst` / ses `caveats` — c'est le
   seul canal de communication qui atteigne réellement l'utilisateur d'un
   paquet.
3. Le one-liner ne bouge jamais. Il reste la porte de sortie universelle, et
   c'est une raison de plus de ne pas laisser les canaux dicter des changements
   d'architecture.

**Régression du chemin principal** — la phase 0 touche `bin/nivuus`,
`config/20-autoupdate.zsh`, `config/99-cleanup.zsh` et `lib/zshrc.sh`, c'est-à-dire
le cœur de deux chantiers déjà prouvés. Mitigation : « marqueur absent =
comportement d'aujourd'hui » (§ 1.2), la matrice existante tourne inchangée, et
`bin/test-count --check` interdit une régression du nombre de tests.

**`.SRCINFO` désynchronisé du `PKGBUILD`** — panne n° 1 des paquets AUR
automatisés, silencieuse jusqu'à ce que l'AUR refuse le push ou, pire, l'accepte
avec des métadonnées fausses. Mitigation : la CI régénère et **compare** avant
de pousser (§ 4.2), même dispositif que le « vérifier avant publier » du
chantier 2.

**Empreinte recopiée depuis une source non authentifiée** — un packager qui
recalcule un `sha256` sur un fichier retéléchargé sans vérifier la signature
annule tout le chantier 2 en trois lignes de YAML. Mitigation : le job `verify`
est l'unique producteur des empreintes consommées par les trois recettes (§ 5.2),
et il est `needs:` de chacune.

**Fuite d'un jeton de packaging** — permettrait de publier une formule
malveillante pointant vers une autre archive. Mitigation : environnement
`packaging` séparé de `release` (§ 5.3), donc la signature reste hors de portée ;
jetons portés au plus étroit (un dépôt chacun) ; et l'utilisateur d'un paquet
compromis reste protégé par… rien, honnêtement. C'est la limite du modèle : un
canal de distribution tiers est un point de confiance supplémentaire, et
l'ajouter **augmente** la surface d'attaque. Le dire dans `SECURITY.md` plutôt
que de laisser croire que trois canaux valent mieux qu'un du point de vue de la
sécurité.

**Budget CI** — quatre cibles de plus, avec `docker` et `brew`. Mitigé par le
découpage PR (statique seulement) / nightly / release du § 6.2.

## 10. Questions ouvertes (arbitrage requis)

1. **Verbes `enable` / `disable`** (§ 2.3) : retenus comme noms explicites, avec
   surcharge d'`install`/`uninstall` en mode paquet. Alternative : n'exposer que
   `install`/`uninstall` et rendre le comportement entièrement implicite (moins
   de surface CLI, message de `caveats` moins clair). À trancher avant la
   phase 0, car c'est une API publique difficile à renommer ensuite.
2. **Comptes et dépôts** : le dépôt `maximeallanic/homebrew-tap` existe-t-il ?
   Un compte AUR avec une clé SSH est-il disponible pour réserver
   `nivuus-shell` ? Ce sont les deux seules dépendances non techniques du
   chantier, et elles bloquent respectivement les phases 1 et 2.
3. **Identité GPG** — le § 4.2 conclut qu'un `.asc` détaché **de l'archive** est
   nécessaire pour `validpgpkeys`. Cela ferme la question ouverte n° 4 du
   chantier 2 sur le *besoin*, pas sur l'*identité* : quelle clé, publiée où,
   liée à quelle identité vérifiable ? Sans réponse, `validpgpkeys` est retiré du
   `PKGBUILD` et on se rabat sur `sha256sums` seul — dégradation acceptable mais
   à décider consciemment.
4. **Dépôt APT sur GitHub Pages** — écarté pour l'instant (§ 4.3). Le
   rouvrir dépend de la même réponse que la question n° 3 du chantier 2
   (existe-t-il un domaine contrôlé ?), puisque l'ancrage hors bande et
   l'hébergement du dépôt partagent la contrainte.
5. **Coût de démarrage sans `.zwc`** (§ 3.2) — non tranché : la décision de
   livrer ou non le repli « cache par utilisateur » dépend d'une mesure qui
   n'existe pas encore. C'est le seul point du document délibérément laissé
   ouvert sur une donnée plutôt que sur une préférence.
6. **Drop-in `/etc/zsh/zshrc.d` pour l'activation par machine** — proposé
   « documenté, jamais automatique ». Une école soutiendra qu'un paquet système
   *doit* pouvoir activer pour tous ; à confirmer, sachant que l'automatiser
   contredirait le § 2.3.
7. **Notification de version en mode paquet** — proposée à l'arrêt par défaut
   (§ 1.4). Si l'on juge la péremption des canaux plus dangereuse que la
   politique « pas de réseau », le défaut s'inverse — mais alors il faudra le
   défendre auprès des revues Debian et Arch.
