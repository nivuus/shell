# Installation système (`--system`) — Design

**Date :** 2026-08-21
**Statut :** proposé, en attente d'arbitrage (§ 11)
**Rattachement :** prolongement du chantier 1 (« friction zéro »), **dépendant de la
phase 0 du chantier 4** (« noyau paquet », voir
`2026-08-21-packaging-design.md` § 8). Ce document ne rouvre aucune décision de
ces deux chantiers ; il en applique une à un canal de plus.

## Contexte

`install.sh --system` **sort en erreur** depuis le commit `8261f77` (« refactor(install):
turn install.sh into a thin nivuus wrapper ») :

```
L'installation système (--system) n'est pas encore disponible dans cette version.
Utilise l'installation utilisateur (sans --system) en attendant.
```

L'ancien chemin, tel qu'il existait avant ce commit (`git show 8261f77^:install.sh`),
faisait quatre choses : installer l'arbre dans `/etc/nivuus-shell`, écrire un
`/etc/skel/.zshrc` de trois lignes, **écraser le `~/.zshrc` de `$SUDO_USER`** avec ces
mêmes trois lignes, et désactiver l'auto-update (« System-wide installation:
auto-update not configured »). Il n'avait ni manifeste, ni désinstallation, ni test.
Autrement dit : il violait trois des cinq principes que le chantier 1 a posés
ensuite. Il ne s'agit donc pas de le « réactiver » mais de le **réécrire dans le
modèle actuel**.

Entre-temps, le chantier 4 a tranché un problème de forme presque identique pour
brew / AUR / deb : *un arbre partagé, possédé par autre chose que l'utilisateur,
plus une activation par utilisateur, et deux inventaires qui ne se recouvrent
jamais*. La question qui structure ce document est donc :

> `--system` est-il un quatrième canal de ce modèle, ou lui faut-il autre chose ?

**Réponse retenue et démontrée au § 1 : c'est le même modèle, avec un gestionnaire
de paquets en moins — et c'est cette absence, et elle seule, qui justifie du code
supplémentaire.**

## Problème

| # | Fait | Conséquence | Gravité |
|---|---|---|---|
| 1 | `--system` sort en erreur ; aucun code de mode système ne subsiste dans `bin/nivuus` ni `lib/` | Aucune installation partagée n'est possible là où aucun gestionnaire de paquets n'est visé (Fedora/RHEL, openSUSE, Alpine, images de conteneur, machines hors ligne) | élevée |
| 2 | L'ancien `--system` s'appuyait sur `/etc/skel` | `/etc/skel` **ne s'applique qu'aux comptes créés après**. Un administrateur qui provisionne une machine déjà peuplée n'obtenait **rien** — sauf pour `$SUDO_USER`, dont le `.zshrc` était écrasé sans sauvegarde | bloquante (correction de fond) |
| 3 | Le manifeste garantit une réversibilité bit-exacte **par utilisateur** ; en mode système, l'écriture est en root dans `/etc`, l'activation est dans des `$HOME` appartenant à d'autres | Sans décision explicite, `uninstall --system` en root est tenté de parcourir `/home` — ce que le chantier 4 a qualifié d'aussi grave qu'un `sudo` non demandé | bloquante |
| 4 | Le chantier 4 a écrit : « **Pas de manifeste système** (`/var/lib/nivuus/`) […] Un paquet n'en a aucun besoin : sa base **est** son manifeste » | Vrai pour un paquet. Faux pour `--system`, qui n'a **aucune** base. Sans inventaire, l'arbre partagé devient exactement ce que le chantier 1 a supprimé : des fichiers écrits sans journal, donc non réversibles | bloquante |
| 5 | `config/99-cleanup.zsh` compile les `.zsh` **à côté des sources** ; `_nivuus_perform_update` fait `rm -rf` + extraction dans `$NIVUUS_SHELL_DIR` | Sur un arbre système : écriture qui échoue silencieusement pour les utilisateurs, et **qui réussit** pour un shell root — laissant des orphelins qu'aucune désinstallation ne connaît | élevée |
| 6 | Aucune infrastructure de test ne sait faire tourner du root avec plusieurs utilisateurs : zéro `useradd`, zéro `su` dans `tests/`, et `fs_fingerprint` **ne capture ni propriétaire, ni groupe, ni liens symboliques** | Le mode dont l'intérêt entier est « plusieurs utilisateurs » ne serait prouvé par rien. Et une empreinte sans uid/gid laisserait passer un `chown` sur `/etc` | bloquante |
| 7 | Vestiges contradictoires : `tests/e2e/test_installation.bats:60` (« Install script supports `--system` flag ») ne fait qu'un `grep` sur `install.sh` et **ne passe au vert que grâce au message de refus** ; `doc/FEATURES.md:455` publie encore la commande `sudo bash -s -- --system` avec une note de démenti trois lignes plus bas | Un test sans valeur qui deviendra faussement rassurant, et une documentation qui recommande une commande qui échoue | hygiène |

## Approche retenue

**`--system` est le modèle du chantier 4, appliqué au canal « aucun gestionnaire » :
un arbre partagé en lecture seule, une activation qui reste un acte par
utilisateur — plus un inventaire de l'arbre partagé, puisqu'il n'existe pas de
`dpkg` pour le tenir.**

```
┌─ domaine de l'administrateur (root) ────────────────────────┐
│  /usr/local/share/nivuus-shell/{config,themes,lib,bin,keys} │  copie de l'arbre de release
│  /usr/local/bin/nivuus                                      │
│  /usr/local/share/man/man1/nivuus.1                         │
│  /etc/skel/.zshrc                    (opt-in, § 2.2)        │
│  /etc/zsh/zshrc.d/10-nivuus.zsh      (opt-in, § 2.3)        │
│  → inventaire : /var/lib/nivuus/manifest.tsv  (root)        │
│  → mise à jour : sudo nivuus update  (§ 5)                  │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ lecture seule, jamais réécrit par un shell utilisateur
┌─ domaine de CHAQUE utilisateur ─┴───────────────────────────┐
│  ~/.zshrc  bloc délimité → MODIFY au manifeste de CE user   │
│  ~/.zsh_local, ~/.cache/nivuus-shell, chsh                  │
│  ~/.local/state/nivuus/{manifest.tsv,backups/}              │
│  → inventaire : lib/manifest.sh, inchangé                   │
│  → activation : nivuus enable  /  retrait : nivuus disable  │
└─────────────────────────────────────────────────────────────┘
```

Les deux inventaires ne se recouvrent **jamais**, exactement comme au chantier 4.
La seule différence : l'inventaire du haut est tenu par nous au lieu de l'être par
`dpkg`. Il obéit au même format TSV, aux mêmes quatre règles de restauration
(`CREATE` par hash, `MODIFY` par sauvegarde, `MKDIR` si vide, `CHSH`), au même
`--dry-run`, au même contrat « aucun module n'écrit hors du manifeste ».

**Ce qui n'est donc PAS réinventé** — et c'est l'essentiel du travail économisé :
`.nivuus-origin` et `lib/origin.sh`, `nivuus enable` / `nivuus disable`, la garde
`[ -r … ] && source` du bloc `.zshrc`, la résolution des liens symboliques dans
`bin/nivuus`, la non-compilation `.zwc` hors arbre possédé, `doctor` enrichi,
`nivuus.1`. Tout cela est la **phase 0 du chantier 4**, dont ce chantier est un
consommateur et non un contributeur.

Approches écartées :

- **Déclarer `--system` redondant et le supprimer définitivement.** Défendable sur
  Debian/Ubuntu/Arch/macOS, faux ailleurs (§ 1). Supprimer l'option laisserait sans
  réponse Fedora, RHEL, Rocky, openSUSE, Alpine, les images de base et les machines
  sans réseau sortant — dont deux figurent déjà dans la matrice de test. On garde
  l'option, en la recommandant **en second** là où un paquet existe.
- **Un second modèle, propre au système** (activation machine par défaut, `/etc/skel`
  comme mécanisme principal). C'est l'ancien `--system`. Il ne couvre pas les comptes
  existants, il écrase des fichiers personnels, et il crée un deuxième comportement à
  tester. Rejeté.
- **Faire porter l'activation machine au `.deb`** (question ouverte n° 6 du
  chantier 4). Un `postinst` n'a pas le consentement nécessaire ; une ligne de
  commande d'administrateur l'a. Voir § 2.3 : ce document **répond** à cette question
  ouverte en plaçant l'activation machine dans `--system`, et en donnant au paquet la
  commande à afficher.
- **Réutiliser `/etc/nivuus-shell` comme racine de l'arbre.** `/etc` est de la
  configuration, pas du code (FHS 3.0 § 3.7 et § 4.11). Et sur Debian/Arch,
  `/usr/share/nivuus-shell` est le territoire du futur `.deb` : y poser un arbre non
  empaqueté organiserait la collision qu'on cherche à éviter. `/usr/local` est
  précisément la zone « installé localement, hors gestionnaire ». Voir § 4.4 pour
  l'héritage.

## 1. À quoi sert `--system` que le reste ne couvre pas

### 1.1 Le périmètre, nommé précisément

`--system` a de la valeur exactement à l'intersection de deux conditions :
**(a)** l'administrateur veut un arbre partagé plutôt que N copies dans N `$HOME`,
et **(b)** aucun des trois canaux du chantier 4 n'est disponible ou acceptable.

Ce que cela recouvre concrètement :

| Cas | Pourquoi les paquets ne couvrent pas |
|---|---|
| Fedora, RHEL, Rocky, AlmaLinux, openSUSE | **RPM est explicitement hors périmètre** du chantier 4 (« nommé pour être écarté »). Fedora est pourtant déjà dans la matrice de test. |
| Alpine, images de base minimales | Pas d'`apk` visé ; souvent pas de gestionnaire du tout dans l'image finale. |
| Image de conteneur multi-utilisateur (CI mutualisée, poste de dev distant, JupyterHub, bastion SSH) | On veut **une** copie de l'arbre pour N comptes, figée à une version, sans réseau au runtime. Le one-liner par utilisateur donne N copies et N updaters. |
| Machine sans accès sortant, avec miroir interne | `NIVUUS_RELEASE_BASE_URL` existe déjà ; un dépôt APT interne n'existe pas (et le chantier 4 a refusé d'en créer un). |
| Poste d'entreprise géré par Ansible/Salt | Le `.deb` conviendrait — mais il ne sait ni poser `/etc/skel`, ni activer pour la machine, **par principe** (§ 2.3). `--system` le sait, parce qu'un humain a tapé le drapeau. |

### 1.2 Est-ce redondant avec le `.deb` ? En partie, oui — et on le dit

**Sur Debian et Ubuntu, `apt install ./nivuus-shell_*.deb` couvre 90 % de ce que
`--system` apporte, et le couvre mieux** : inventaire tenu par `dpkg`, vérification
`dpkg -V`, retrait transactionnel, `apt purge`. La documentation doit le recommander
en premier sur ces plateformes, et `nivuus install --system` doit le **dire** quand il
détecte une distribution où un canal existe :

```
· Nivuus est disponible en paquet sur cette distribution :
      apt install ./nivuus-shell_3.2.0_all.deb      (release GitHub)
  Le paquet est inventorié par dpkg, ce que --system doit refaire lui-même.
  Continuer avec --system quand même ? [Y/n]
```

Ce n'est pas un refus : un administrateur peut légitimement préférer un arbre sous
`/usr/local` qu'aucune mise à jour de distribution ne touchera. C'est une information,
affichée une fois, avant toute écriture.

Les 10 % restants ne sont pas résiduels, ce sont **les deux surfaces d'activation
qu'un paquet refuse de porter** (`/etc/skel`, activation machine) : elles exigent un
consentement explicite d'administrateur, qu'un `postinst` n'a jamais et qu'une ligne
de commande a toujours.

**Conclusion assumée :** `--system` n'est pas un concurrent des canaux de paquets,
c'est le **repli universel du même modèle** — celui qui n'exige aucun écosystème — et
le **porteur des opérations d'activation machine** pour les quatre canaux, y compris
les trois qui passent par un gestionnaire.

### 1.3 Ce que `--system` ne fera jamais

Écrit ici pour n'avoir pas à le redécouvrir en revue : `--system` ne parcourt pas
`/home`, ne modifie le `.zshrc` d'aucun utilisateur (pas même celui de `$SUDO_USER`,
contrairement à l'ancien code), ne fait de `chsh` pour personne, ne s'installe pas
lui-même dans un ordonnanceur, et n'active rien pour la machine sans un drapeau
explicite.

## 2. Les trois surfaces d'activation, et le piège `/etc/skel`

Installer l'arbre et activer Nivuus sont **deux opérations distinctes**. `nivuus
install --system` ne fait que la première. L'activation dispose de trois surfaces,
une seule par défaut.

### 2.1 `nivuus enable`, par utilisateur — la seule activée par défaut

Inchangée par rapport au chantier 4 : écrit le bloc délimité dans `~/.zshrc` (avec sa
garde `[ -r … ] && source`), journalisé en `MODIFY` dans le manifeste **de cet
utilisateur**, sans aucun privilège. `nivuus disable` le retire, bit pour bit.

C'est la seule surface qui : couvre les comptes existants, demande le consentement de
la personne concernée, fonctionne sur des `$HOME` NFS, et se défait sans root.

### 2.2 `/etc/skel` — utile, opt-in, et sans illusion

**Le piège :** `/etc/skel` n'est lu que par les outils de création de comptes
(`useradd -m`, `adduser`) **au moment de la création**. Un administrateur qui
provisionne une machine déjà peuplée n'obtient **rien**. Il ne couvre pas non plus les
comptes dont le `$HOME` est provisionné ailleurs : LDAP/AD avec home NFS pré-créé,
`systemd-homed`, images de conteneur où les comptes existent déjà, `pam_mkhomedir`
(qui, lui, honore bien `/etc/skel`, mais seulement à la première connexion).

Décision : **`--skel` est un drapeau explicite, jamais le défaut**, et le message
d'installation nomme la limite au lieu de la taire :

```
✓ /etc/skel/.zshrc écrit.
! Il ne s'applique QU'AUX COMPTES CRÉÉS APRÈS cette commande.
  Les 14 comptes déjà présents ne sont pas activés : chacun peut lancer
  « nivuus enable », ou utilise --activate-all pour toute la machine (§ doc).
```

(Le nombre de comptes existants est lu dans `/etc/passwd` — uid ≥ 1000, shell non
`nologin` — **jamais** en parcourant `/home`.)

Le fichier obéit aux règles ordinaires du manifeste : s'il n'existait pas, `CREATE`
(supprimé au retrait seulement si son hash n'a pas bougé) ; s'il existait, `MODIFY`
avec sauvegarde adressée par contenu et restauration à l'octet près. Sur macOS,
`/etc/skel` n'existe pas : `--skel` est refusé avec un message, pas ignoré en silence.

### 2.3 Activation machine — opt-in, vérifiée empiriquement, ou annulée

`nivuus install --system --activate-all` (ou `nivuus enable --all` sur un arbre déjà
posé, y compris posé par un **paquet**) active Nivuus pour tous les shells zsh
interactifs de la machine.

C'est la réponse de ce document à la **question ouverte n° 6 du chantier 4**
(« Drop-in `/etc/zsh/zshrc.d` pour l'activation par machine »). Position : l'école qui
soutient qu'« un paquet système *doit* pouvoir activer pour tous » a raison sur le
besoin et tort sur le porteur. Le besoin est réel ; ce n'est pas au `postinst` de le
satisfaire, parce qu'il n'a pas le consentement — l'utilisateur a tapé `apt install`,
pas « change le shell de tout le monde ». Une commande d'administration explicite,
elle, l'a. Le paquet **affiche** la commande, `--system` la **porte**. Un seul code
d'activation machine pour les quatre canaux, et le § 2.3 du chantier 4 (« le paquet ne
touche pas au `.zshrc` ») reste vrai mot pour mot.

**Il n'existe pas de `zshrc.d` standard.** Le fichier lu par tout zsh interactif dépend
du `--enable-etcdir` de compilation : `/etc/zsh/zshrc` (Debian, Ubuntu, Arch),
`/etc/zshrc` (Fedora, RHEL, macOS), variable ailleurs. Et sur Debian, `/etc/zsh/zshrc`
est un **conffile `dpkg`** : y ajouter une ligne provoquera un jour la question
« conffile modifié » lors d'une mise à jour de `zsh-common`.

Conséquence, en trois décisions :

1. **On ne devine pas le chemin, on le vérifie.** Après écriture, l'installeur exécute
   un zsh interactif dans un environnement vierge et vérifie que le marqueur est bien
   posé :
   ```sh
   probe="$(env -i HOME="$probe_home" PATH="$PATH" TERM=dumb \
            zsh -ic 'print -r -- "${NIVUUS_ACTIVATED_BY:-none}"' 2>/dev/null | tail -n1)"
   [ "$probe" = "system" ] || { nivuus_manifest_abort; nivuus_die "…"; }
   ```
   Si la preuve manque, **l'activation machine est défaite par le manifeste** et
   l'administrateur reçoit le chemin exact à ajouter à la main. Un `/etc` modifié sans
   effet est pire qu'un refus : il fait croire que c'est fait.
2. **Le contenu vit dans un fichier à nous** (`/etc/zsh/zshrc.d/10-nivuus.zsh`,
   répertoire créé si absent), et le fichier de la distribution ne reçoit **qu'une
   ligne**, journalisée en `MODIFY`. Retirer une ligne connue d'un conffile est
   réversible ; réécrire le conffile ne l'est pas.
3. **Le drapeau exige une confirmation qui nomme le conffile**, même avec `--yes`
   absent/présent explicité, et `doctor` signale ensuite l'état « conffile modifié par
   Nivuus » pour que la question `dpkg` ne soit pas une surprise. Pour les
   administrateurs qui préfèrent posséder `/etc` eux-mêmes (Ansible, image
   immuable), `nivuus enable --all --print` affiche le fichier et la ligne sans rien
   écrire.

Contenu du drop-in — **il cède toujours à l'utilisateur** :

```zsh
# Activation machine de Nivuus Shell (posée par « nivuus enable --all »).
# Ne fait rien pour un utilisateur qui a sa propre activation : la sienne gagne.
if [[ -o interactive ]] && ! grep -qs '>>> nivuus shell >>>' "${ZDOTDIR:-$HOME}/.zshrc"; then
    export NIVUUS_SHELL_DIR="/usr/local/share/nivuus-shell"
    export NIVUUS_ACTIVATED_BY=system
    [ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"
fi
```

Coût : un `grep` sur un fichier, et **seulement sur les machines qui ont opté**. Il est
mesuré par le test de budget des 300 ms, comme le reste.

### 2.4 Anti-double-`source` : deux mécanismes, deux rôles

Le `grep` ci-dessus **choisit** qui gagne (l'utilisateur, toujours). Il ne suffit pas :
un `.zshrc` peut sourcer Nivuus par un autre chemin, et le drop-in est lu **avant**
`~/.zshrc`. On ajoute donc une garde de réentrance en tête de `.zshrc`, qui **protège** :

```zsh
# Une seule fois par processus. Nivuus enregistre des hooks, des widgets et des
# précmd : les charger deux fois les double.
[[ -n "${_nivuus_sourced:-}" ]] && return 0
typeset -g _nivuus_sourced=1
```

**Variable non exportée, délibérément.** `NIVUUS_SHELL_LOADED` (posée par
`config/99-cleanup.zsh`) est `export`ée : s'en servir comme garde désactiverait Nivuus
dans tout zsh imbriqué dans une session Nivuus. La garde doit être locale au processus.

## 3. Réversibilité à travers la frontière de privilège

### 3.1 La règle

**`nivuus uninstall --system`, lancé en root, ne touche à aucun `$HOME`. Jamais.
Il ne les lit même pas.**

Il rejoue le manifeste système, et rien d'autre : l'arbre sous `/usr/local/share`, le
lien `/usr/local/bin/nivuus`, la page de manuel, `/etc/skel/.zshrc`, le drop-in, la
ligne ajoutée au rc global. Chacun avec les règles existantes — un fichier divergé
survit et est signalé, un répertoire non vide survit, une sauvegarde absente bloque la
restauration au lieu de l'improviser.

C'est **exactement** la position du chantier 4 (« Parcourir `/home/*` en root pour
éditer des fichiers personnels est précisément ce que la règle "aucun `sudo` que
l'utilisateur n'a pas demandé" interdit, vue depuis l'autre bout »), sans divergence à
justifier. Le fait que ce soit un humain qui ait tapé `sudo` ne change rien : il a
consenti pour **sa** machine, pas au nom des quatorze personnes qui y ont un compte.

### 3.2 Ce que ça laisse derrière, et pourquoi ce n'est pas une trace

Des blocs `.zshrc` chez les utilisateurs activés, pointant vers un arbre qui n'existe
plus. Trois raisons pour lesquelles c'est acceptable :

1. **Ce ne sont pas nos fichiers.** Ils appartiennent à chaque utilisateur, sont
   inscrits à **son** manifeste, et `nivuus disable` les retire à l'octet près. La
   propriété « aucune trace après désinstallation » est vérifiée **par domaine** :
   root défait le domaine root, chaque utilisateur défait le sien.
2. **La garde du bloc les rend inoffensifs** (`[ -r … ] && source`) : aucun shell ne
   casse, pour personne — c'est l'invariant n° 2 du chantier 4, et il est ici la
   contrepartie exacte du refus de parcourir `/home`.
3. **`doctor` les nomme.** Chaque utilisateur voit « bloc présent, arbre absent » avec
   la commande de réparation. Le silence au démarrage, le diagnostic à la demande.

`uninstall --system` le dit, sans compter ni scanner :

```
✓ Arbre système retiré (/usr/local/share/nivuus-shell), rien d'autre n'a été touché.
✓ /etc/skel/.zshrc restauré (contenu d'origine, à l'octet près).

Les activations par utilisateur subsistent — elles appartiennent à chaque compte.
Leurs shells ne casseront pas (le bloc est gardé). Chacun peut faire : nivuus disable
```

### 3.3 La seule exception, en lecture seule et sur demande

`nivuus doctor --system --scan-users` liste les comptes dont le `~/.zshrc` contient un
bloc Nivuus. **Jamais par défaut, jamais en écriture.** Deux raisons de ne pas
l'activer d'office, dont une purement technique et décisive : un `stat` sur un `$HOME`
NFS **déclenche l'automonteur**, ce qui est un effet de bord réel sur un serveur
(montages en rafale, timeouts, entrées de journal) — lire n'est pas neutre. La seconde
est de principe : l'admin doit taper quelque chose qui dit ce qu'il fait.

## 4. Le manifeste système

### 4.1 Emplacement et permissions

```
/var/lib/nivuus/
├── manifest.tsv        root:root 0644   (chemins et hashes — aucun secret)
└── backups/<sha256>    root:root 0700   (contenu de fichiers /etc sauvegardés)
```

- **`/var/lib`, pas `/etc/nivuus-shell`** : même raison qu'au chantier 1 pour
  `~/.local/state` — le journal ne doit pas vivre dans ce qu'il doit pouvoir
  supprimer, sinon une installation cassée est irréparable. Et FHS : `/var/lib` est
  l'état variable d'une application, `/etc` est de la configuration éditable par
  l'administrateur.
- **Manifeste lisible par tous** : un utilisateur non privilégié doit pouvoir lancer
  `nivuus doctor` et comprendre d'où vient son arbre partagé. Il ne contient que des
  chemins et des empreintes.
- **`backups/` en 0700** : il peut contenir la copie d'un fichier de `/etc` dont le
  mode d'origine était restrictif. Le store est adressé par contenu ; élargir ses
  droits élargirait ceux du contenu sauvegardé. Refusé.
- En-tête : `#nivuus-manifest v1 installed_at=… mode=system dir=/usr/local/share/nivuus-shell`.
  Le champ `mode=` existe **depuis le chantier 1** (`nivuus_manifest_begin "$mode"`,
  aujourd'hui appelé en dur avec `user`) : rien à inventer dans le format.
- `NIVUUS_STATE_DIR` est déjà le crochet qui déplace l'état (utilisé par les tests) ;
  le mode système le fixe à `/var/lib/nivuus`. Aucune nouvelle variable.

### 4.2 Pourquoi ce manifeste rouvre une décision du chantier 4, et pourquoi c'est cohérent

Le chantier 4 a écrit : « **Pas de manifeste système** (`/var/lib/nivuus/`). Il était
prévu par le chantier 1 pour un `--system` qui n'a jamais été livré. Un paquet n'en a
aucun besoin : sa base **est** son manifeste, et elle est meilleure que la nôtre. »

Cette phrase est exacte et on la garde **telle quelle pour les paquets**. Elle dit :
*un inventaire, jamais deux*. En mode `--system`, le nombre d'inventaires disponibles
est zéro ; en créer un porte le total à un. La règle est respectée, pas contournée.

Corollaire opérationnel : **`/var/lib/nivuus/manifest.tsv` et un paquet Nivuus ne
coexistent jamais légitimement**. Si `doctor` trouve les deux, il le dit et nomme celui
qui est actif (§ 4.3). Les préfixes distincts (`/usr/local/share` vs `/usr/share`) font
que la cohabitation est confuse, pas destructrice.

### 4.3 Double installation : qui gagne, ce que dit `doctor`

Le cas est fréquent et doit être traité, pas évité : un administrateur installe pour
la machine, un utilisateur avancé lance le one-liner pour lui-même.

**Qui gagne : l'utilisateur, toujours, et sans ambiguïté possible.** La raison est
structurelle, pas conventionnelle : le `~/.zshrc` d'un utilisateur contient **au plus
un** bloc Nivuus (`nivuus_zshrc_merge` remplace le contenu du bloc au lieu d'en ajouter
un second — comportement déjà implémenté et testé), et ce bloc fixe `NIVUUS_SHELL_DIR`.
Une installation utilisateur par-dessus une activation système ne fait que repointer la
variable vers `~/.nivuus-shell`. Il n'y a donc **jamais deux `source`** :

| Situation | `NIVUUS_SHELL_DIR` effectif | Nombre de `source` |
|---|---|---|
| Système seul, `nivuus enable` | `/usr/local/share/nivuus-shell` | 1 (le bloc) |
| Système + activation machine, utilisateur sans bloc | idem | 1 (le drop-in) |
| Système + install utilisateur | `~/.nivuus-shell` | 1 (le bloc remplacé) |
| Système + activation machine + install utilisateur | `~/.nivuus-shell` | 1 — le drop-in se retire (`grep`, § 2.3) et la garde de réentrance couvre le reste |

Ce que `doctor` affiche dans le cas double :

```
Origine        : source (utilisateur)      ~/.nivuus-shell           v3.2.0
Aussi présent  : système                   /usr/local/share/…        v3.1.4
Actif          : ~/.nivuus-shell  (c'est ton bloc ~/.zshrc qui décide)
Mises à jour   : automatiques (installation utilisateur)
                 L'arbre système est ignoré par ton shell. Pour l'utiliser :
                     nivuus uninstall && nivuus enable
```

`doctor` **diagnostique, il ne convertit pas** — reprise mot pour mot de la position du
chantier 4 sur la migration source↔paquet, pour la même raison : convertir voudrait
dire supprimer un arbre pour en poser un autre, et le manifeste d'origine deviendrait
faux à mi-chemin.

### 4.4 L'héritage `/etc/nivuus-shell`

Une installation faite par l'ancien `--system` (avant `8261f77`) a laissé un arbre
complet dans `/etc/nivuus-shell` et un `/etc/skel/.zshrc`, **sans manifeste**, donc
sans réversibilité possible. Décision, alignée sur `nivuus migrate` : `doctor` le
**détecte et le nomme**, `install --system` refuse de s'installer par-dessus, et rien
n'est supprimé automatiquement — on ne peut pas restaurer ce qu'on n'a pas sauvegardé.
La procédure manuelle (déplacer l'arbre, retirer `/etc/skel/.zshrc` si son contenu est
exactement les trois lignes connues) est documentée dans `doc/INSTALL.md`, avec la
commande de retour en arrière.

`/etc/nivuus-shell` reste **réservé** pour ce qu'il aurait dû être : une future
configuration de site (`/etc/nivuus-shell/site.zsh`, hors périmètre, § 8).

## 5. Auto-update en mode système

### 5.1 Décision

**Dans les shells des utilisateurs : désactivé, sans exception — mêmes raisons qu'en
mode paquet. Pour l'administrateur : `sudo nivuus update`, une commande explicite, qui
passe par l'installeur et donc par le manifeste.**

Mécanique : `.nivuus-origin` gagne une troisième valeur, `origin=system` :

```
origin=system
channel=selfhosted
prefix=/usr/local/share/nivuus-shell
version=3.2.0
```

- `_nivuus_is_package_install` du chantier 4 devient `_nivuus_origin != source`, ce qui
  couvre `package` et `system` d'un seul test — un `stat` au démarrage, inchangé.
- Le **garde-fou secondaire** du chantier 4 (« refuser toute mise à jour destructive si
  l'arbre n'est pas inscriptible ») s'applique tel quel et couvre le cas d'un tiers qui
  poserait un arbre système sans marqueur.
- Le message de `nivuus update` est dérivé de `origin`, pas deviné, et sort en **0** :

```
Nivuus est installé pour la machine (/usr/local/share/nivuus-shell), en v3.1.4.
Les mises à jour sont l'affaire de l'administrateur :

    sudo nivuus update

Pour repasser à une installation personnelle avec mises à jour automatiques :
    curl -fsSL https://…/install.sh | sh
```

### 5.2 Pourquoi l'administrateur, lui, a le droit

Les trois arguments du chantier 4 contre l'auto-update en mode paquet sont examinés un
par un, et deux seulement s'appliquent ici :

| Argument | En mode système |
|---|---|
| « Sans root, échec silencieux hebdomadaire » | **S'applique**. D'où la désactivation dans les shells utilisateurs. |
| « Avec root, ça réussit — et `dpkg -V` diverge, la mise à jour suivante écrase » | **Ne s'applique pas.** Aucun gestionnaire ne revendique `/usr/local`. Il n'y a pas de seconde autorité à contredire. |
| « Le gestionnaire fait déjà ce travail, mieux » | **Ne s'applique pas** : il n'y en a pas. C'est précisément la raison d'être de ce mode. |

Un administrateur qui installe sans gestionnaire n'a **aucun** chemin de mise à jour si
on refuse les deux. Ce serait la situation que le chantier 4 nomme lui-même comme son
risque le plus grave (« un canal abandonné est pire que pas de canal […] figé sur une
version, sans mise à jour de sécurité »). On ne la crée pas volontairement.

### 5.3 Ce que `sudo nivuus update` fait exactement

**Il relance l'installation système depuis une release vérifiée. Il n'appelle jamais
`_nivuus_perform_update`.** C'est la décision la plus importante de cette section :

- `_nivuus_perform_update` fait `rm -rf` puis extraction dans `$NIVUUS_SHELL_DIR`
  (`config/20-autoupdate.zsh:468-471`). Sur un arbre système, ce serait une écriture
  massive **hors manifeste**, dans le domaine root, invisible de l'inventaire. Le
  principe « le manifeste est la seule voie d'écriture » l'interdit.
- `nivuus install --system` est **déjà** idempotent et différentiel (héritage du
  manifeste précédent, `SKIP` sur les fichiers conformes, remplacement atomique du
  manifeste). Réinstaller *est* la mise à jour, et elle reste réversible.
- La vérification de signature du chantier 2 s'applique inchangée, avec le même refus
  dur : ce qui n'est pas vérifiable n'est pas installé.

Aucun timer, aucune unité systemd, aucun cron n'est fourni (§ 8). Un administrateur qui
veut de l'automatisme appelle `sudo nivuus update` depuis **son** ordonnanceur — c'est
ce que fait déjà tout parc géré, et c'est une décision qui lui appartient.

### 5.4 Péremption

Aucune sonde réseau au démarrage des shells, comme au chantier 4 § 1.4.
`sudo nivuus doctor --system` compare, **à la demande**, la version installée à la
dernière release. C'est une commande d'administrateur, pas un comportement de shell.

## 6. Privilèges — « aucun `sudo` surprise » quand le mode entier suppose du root

La règle du chantier 1 est « Nivuus n'exécute jamais un `sudo` que l'utilisateur n'a
pas explicitement demandé ». Elle n'interdit pas de *nécessiter* du root ; elle
interdit d'en *acquérir* tout seul. D'où :

| Opération | Exige | Sans le privilège |
|---|---|---|
| `install --system`, `--skel`, `--activate-all` | `id -u = 0` | **Refus avant toute écriture**, avec la commande exacte : `sudo nivuus install --system`. Jamais de `exec sudo "$0"`. |
| `uninstall --system`, `update` en mode système | `id -u = 0` | idem |
| `install --system --dry-run` | **rien** | **Fonctionne sans root** et produit le rapport complet. C'est le pendant exact de « `curl … \| sh --dry-run` sans jamais demander de privilège » : on doit pouvoir auditer avant de décider d'élever. Conséquence de conception : `nivuus_manifest_begin` en `--dry-run` écrit déjà dans un `mktemp` et ne crée pas l'état — le chemin est donc déjà non privilégié, il ne doit pas être régressé. |
| `enable` / `disable` / `doctor` | rien | fonctionnent en utilisateur ordinaire, sur un arbre en lecture seule |
| `--with-deps` en mode système | root déjà présent | la commande groupée est **affichée puis confirmée** comme en mode utilisateur ; le fait d'être root ne supprime pas la confirmation |
| `chsh` | — | **jamais** en mode système, pour personne. Root changeant le shell de connexion d'autrui est hors de question ; l'admin dispose de `usermod -s` et `useradd -s`. Aucune ligne `CHSH` dans un manifeste système. |

Deux pièges de privilège à traiter explicitement, tous deux invisibles en test
non-root :

- **`umask`.** Un `sudo` avec `umask 077` produirait un arbre `/usr/local/share` que
  **personne** ne peut lire : une installation « réussie » qui casse tous les shells.
  Le mode système impose les modes finaux (`0755` répertoires, `0644` fichiers, `0755`
  exécutables, `root:root`) au lieu de laisser l'umask décider. C'est un test.
- **Écriture sûre dans `/etc`.** Les cibles sont créées sans suivre un lien symbolique
  préexistant et le remplacement reste atomique (`write` dans un temporaire du même
  système de fichiers + `mv`), comportement déjà celui de `nivuus_write_file`. Sur
  SELinux, `restorecon -F` est appliqué sur les chemins créés s'il est disponible, et
  son absence est signalée sans être fatale.

## 7. Tests et CI

Même exigence que partout : **installer pour de vrai, vérifier, désinstaller, prouver
l'absence de trace.** Avec ici une contrainte propre : *plusieurs utilisateurs
distincts*, sinon le mode n'est pas testé du tout.

### 7.1 Prérequis d'outillage (à livrer en phase 1)

- **`fs_fingerprint` doit capturer le propriétaire, le groupe et les liens
  symboliques.** Aujourd'hui (`tests/helpers/fingerprint.bash`) elle capture
  `DIR/FILE`, chemin relatif, mode octal et sha256 — et `find -type d|-type f`
  **ignore les liens** (limite déjà commentée dans le fichier). Sur `/etc` et
  `/usr/local`, un `chown` ou un lien remplacé passerait inaperçu. Deux colonnes
  (`uid`, `gid`) et une branche `-type l` (dont la cible fait office de « hash »).
  L'ajout est neutre pour les tests existants : la comparaison est un `diff` entre deux
  empreintes produites par la même version.
- **Un utilisateur jetable.** `tests/helpers/users.bash` : `mk_user <nom>`
  (`useradd -m -s /bin/zsh`), `as_user <nom> <cmd…>` (via `su -l`), `rm_user <nom>`.
  Le dépôt n'a **aucun** `useradd`, `su` ni test root aujourd'hui : c'est une brique
  nouvelle, et elle est petite.
- **Crochets d'environnement pour la couche unitaire**, dans la lignée des existants
  (`NIVUUS_ETC_SHELLS`, `NIVUUS_LOGIN_SHELL_FILE`, `NIVUUS_STATE_DIR`) :
  `NIVUUS_SYSTEM_PREFIX`, `NIVUUS_SYSTEM_STATE_DIR`, `NIVUUS_ETC_DIR`. Ils rendent
  testable **sans privilège et sur PR** toute la logique de `lib/system.sh` (choix des
  chemins, refus sans root, contenu du drop-in, contenu de `/etc/skel/.zshrc`, garde
  anti-double-`source`).

### 7.2 Le script de preuve : `tests/ci/run-system-target.sh`

Même modèle que `run-target.sh` (et `run-package-target.sh` du chantier 4) : toute la
logique dans le script, rien dans le YAML, rejouable en local par
`docker run … ./tests/ci/run-system-target.sh`. Les conteneurs de la matrice tournent
déjà en root, ce qui est exactement ce dont ce mode a besoin.

| # | Étape | Assertion |
|---|---|---|
| 1 | `mk_user alice`, `mk_user bob` ; empreintes de `/etc`, `/usr/local`, `/var/lib`, `~alice`, `~bob` | référence |
| 2 | `nivuus install --system --yes` (root) | code 0 ; arbre sous `/usr/local/share/nivuus-shell`, `root:root`, modes `0755/0644` **quel que soit l'umask** (le script force `umask 077` pour l'exercer) |
| 3 | Empreintes de `~alice` et `~bob` | **égalité stricte** avec l'étape 1. **INVARIANT n° 1 : une installation pour la machine ne touche aucun `$HOME`.** C'est le point que l'ancien `--system` violait (`$SUDO_USER`). |
| 4 | `as_user alice nivuus enable` puis `as_user alice zsh -i -c 'echo OK'` | stderr **vide**, `NIVUUS_SHELL_DIR` = arbre système |
| 5 | Empreinte de `~bob` | **inchangée**. **INVARIANT n° 2 : l'activation d'alice n'active pas bob.** C'est tout l'objet du mode par utilisateur. |
| 6 | `as_user alice nivuus update` | affiche `sudo nivuus update`, **sort en 0**, ne télécharge rien |
| 7 | Trois shells interactifs d'alice, puis `~alice/.nivuus-shell-last-update-check` | **le fichier n'existe pas** — preuve observable que l'updater ne s'est jamais lancé (même sonde qu'au chantier 4) |
| 8 | Shell **root** interactif, puis `find /usr/local/share/nivuus-shell -name '*.zwc'` | **aucun** (§ Problème n° 5) |
| 9 | `as_user alice nivuus disable` ; empreinte de `~alice` | **égalité stricte** avec l'étape 1 |
| 10 | `nivuus install --system --skel --yes`, puis `mk_user carol` | `zsh -i` de carol charge Nivuus ; `~bob` **toujours inchangé** — preuve que `/etc/skel` ne rattrape pas les comptes existants, et qu'on ne le prétend pas |
| 11 | `nivuus enable --all --yes` ; shell interactif de bob | Nivuus chargé **sans** que bob ait rien fait ; la sonde `NIVUUS_ACTIVATED_BY=system` est bien celle qui a servi |
| 12 | `as_user bob` installe pour lui-même (one-liner hors ligne, `file://`), puis shell interactif | `NIVUUS_SHELL_DIR` = `~bob/.nivuus-shell` et **un seul chargement** (compteur de réentrance exposé en debug). **INVARIANT n° 3 : jamais de double `source`.** |
| 13 | `nivuus uninstall --system --yes` (alice ré-activée au préalable) | `/usr/local`, `/etc`, `/var/lib` **bit-identiques** à l'étape 1 ; `~alice` et `~bob` **non modifiés** par la commande |
| 14 | Shell interactif d'alice après le retrait | stderr **vide** — c'est ce qui paie la garde du bloc, et la contrepartie de « on ne touche pas aux `$HOME` » |
| 15 | `nivuus doctor` en tant qu'alice | nomme « bloc présent, arbre absent » et donne la commande de réparation |

Les étapes **3, 5, 12 et 13** portent un commentaire `INVARIANT:` et sont protégées par
le même garde-fou `grep` que celui déjà en place pour la signature dans `tests.yml` :
si elles disparaissent, la CI le dit.

### 7.3 Où ça tourne, et à quel coût

Réutilisation stricte de ce qui existe : `.github/matrix.json`,
`.github/actions/setup-tests`, `tests/ci/bats-run.sh`, `tests/ci/install-deps.sh`,
`tests/helpers/fingerprint.bash`.

**Réserve factuelle importante :** `tests/ci/`, `.github/matrix.json` et `bin/test-count`
**n'existent pas sur `master`** — ils vivent sur la branche non fusionnée
`feat/install-preuve-ci`. Le chantier 4 les suppose disponibles ; ce chantier aussi.
La fusion de cette branche est donc un **prérequis explicite**, pas un détail.

- **Sur PR (~30 s)** : couche unitaire seulement — `test_lib_system.bats`,
  `test_system_privileges.bats` (refus sans root, `--dry-run` sans root),
  `test_zshrc_reentrancy.bats`, `test_dropin_content.bats`, `sh -n` sur le nouveau
  script CI. Aucun conteneur, aucun `useradd`.
- **Nightly** : `run-system-target.sh` sur `debian:12`, `ubuntu:24.04`,
  `fedora:41`, `alpine:3.20` — les deux dernières délibérément, parce que ce sont les
  cibles que les canaux de paquets **ne** couvrent pas et donc le cœur du périmètre
  (§ 1.1). Arch en plus, puisqu'il est déjà là.
- **Sur release** : les mêmes, bloquantes.
- **macOS** : `enable`/`disable` sur un arbre système posé à la main uniquement ; pas
  de `--skel` (n'existe pas), pas de création d'utilisateur sur le runner. Documenté
  comme couverture partielle, à la manière du job WSL « simulé ».

### 7.4 Ce que ces tests ne prouvent pas

- Le comportement sur des `$HOME` **NFS** avec automonteur : aucun test ne le couvre,
  et c'est précisément le cas où `--scan-users` a des effets de bord (§ 3.3).
- Le comportement d'un vrai LDAP/AD/`pam_mkhomedir` : `/etc/skel` est exercé via
  `useradd -m`, ce qui est le chemin le plus favorable.
- La question `dpkg` « conffile modifié » après `--activate-all` : elle n'apparaît qu'à
  une mise à jour de `zsh-common`, qu'on ne simule pas. `doctor` la signale par avance.

## 8. Périmètre

### Inclus

`origin=system` dans `.nivuus-origin` et `lib/origin.sh` ; nouveau module
`lib/system.sh` (chemins, refus de privilège, `/etc/skel`, drop-in, sonde de
vérification) ; `nivuus install/uninstall/update --system` avec manifeste
`/var/lib/nivuus` ; `--skel` et `--activate-all`/`nivuus enable --all` (+ `--print`) en
opt-in ; garde de réentrance dans `.zshrc` ; normalisation umask/propriétaire/modes et
`restorecon` best-effort ; `doctor` système (origine, double installation, héritage
`/etc/nivuus-shell`, conffile modifié, `--scan-users` opt-in) ; extension de
`fs_fingerprint` (uid/gid, liens) et `tests/helpers/users.bash` ;
`tests/ci/run-system-target.sh` et sa place dans la matrice ; nettoyage des vestiges
(§ Annexe) ; documentation administrateur dans `doc/INSTALL.md` (dont un extrait
`Dockerfile` et un extrait Ansible) et mise à jour de `doc/CLAUDE.md`.

### Hors périmètre

- **Ordonnancement des mises à jour** (unité systemd, cron, `nivuus update --timer`) :
  c'est la politique de l'administrateur, pas la nôtre. On fournit une commande
  idempotente à code de retour propre ; c'est tout ce qu'il faut pour l'appeler.
- **Configuration de site** (`/etc/nivuus-shell/site.zsh` chargé avant `~/.zsh_local`) :
  probablement la première demande d'un administrateur, et une vraie fonctionnalité —
  donc son propre spec. Le chemin est **réservé** ici pour ne pas le brûler.
- **Dépôt APT / RPM / canal supplémentaire** : chantier 4, arbitré là-bas.
- **Migration automatique** d'un `/etc/nivuus-shell` hérité, ou de système ↔ utilisateur
  ↔ paquet : `doctor` détecte et explique, il ne convertit pas (§ 4.3, § 4.4).
- **Windows / non-zsh** : inchangé.
- **`--system` comme installation par défaut recommandée** : le one-liner utilisateur
  reste la porte d'entrée, sur toutes les plateformes. `--system` est documenté dans
  une section « administration », pas dans le README.

## 9. Séquence de livraison

Quatre phases mergeables, plus un prérequis qui n'appartient pas à ce chantier.

**Prérequis (chantier 4, phase 0)** — `.nivuus-origin`, `lib/origin.sh`,
`enable`/`disable`, garde du bloc `.zshrc`, résolution des liens symboliques,
`.zwc` hors arbre possédé, `doctor` enrichi. **Plus la fusion de
`feat/install-preuve-ci`** (§ 7.3). Rien de ce document ne démarre avant.

1. **Arbre système et réversibilité** — `lib/system.sh`, chemins `/usr/local`,
   manifeste `/var/lib/nivuus`, `install`/`uninstall --system`, refus sans root,
   `--dry-run` non privilégié, umask/modes/propriétaire, `origin=system`, garde de
   réentrance, `doctor` de base. **Aucune activation automatique, ni `skel`, ni
   machine.**
   *Sortie : `run-system-target.sh` étapes 1-9 et 13-15 vertes sur Debian et Fedora,
   avec deux utilisateurs réels ; `/etc` et `/usr/local` bit-identiques après retrait.*
2. **`/etc/skel`** — drapeau `--skel`, message qui nomme la limite, comptage via
   `/etc/passwd`, refus sur macOS.
   *Sortie : étape 10 verte — carol (créée après) est activée, bob (existant) ne l'est
   pas, et c'est écrit noir sur blanc dans la doc.*
3. **Activation machine** — drop-in, ligne dans le rc global, sonde de vérification
   avec annulation par le manifeste, `--print`, diagnostic « conffile modifié ».
   *Sortie : étapes 11 et 12 vertes — bob est activé sans rien faire, et une
   installation utilisateur par-dessus continue de gagner, avec un seul `source`.*
4. **Mise à jour et administration** — `sudo nivuus update` via réinstallation
   vérifiée, `doctor --system` (péremption à la demande, `--scan-users`),
   documentation administrateur, et la ligne d'activation machine reprise par les
   `caveats`/`postinst` des trois canaux de paquets.
   *Sortie : une machine système passe de la v(n-1) à la v(n) sans perdre une
   activation, et le chantier 4 peut citer une commande qui existe.*

Ordre défendu : la réversibilité d'abord parce que c'est la propriété qui rend le reste
publiable ; `/etc/skel` ensuite parce qu'il est petit et sans risque ; l'activation
machine en troisième parce que c'est la seule qui touche un fichier de la
distribution ; l'update en dernier parce qu'il n'a de sens qu'une fois qu'il y a
quelque chose à mettre à jour.

## 10. Risques

**Toucher un conffile de la distribution** (phase 3) — le risque le plus tangible.
`/etc/zsh/zshrc` est un conffile `dpkg` ; notre ligne provoquera une question à une
future mise à jour de `zsh-common`. Mitigations : opt-in explicite, une seule ligne
(le contenu vit dans un fichier à nous), journalisation `MODIFY` avec restauration
bit-exacte, `--print` pour ceux qui préfèrent gérer `/etc` eux-mêmes, et signalement par
`doctor`. Ce qu'on ne mitige pas : la question `dpkg` elle-même. On la documente.

**Une installation système réussie mais illisible** — `umask` restrictif sous `sudo`,
SELinux sans `restorecon`, `/usr/local` monté `noexec` : trois façons d'obtenir un
arbre en place que les shells ne peuvent pas charger. Mitigation : modes imposés et
non hérités, et une **vérification de fin d'installation** qui charge réellement
l'arbre depuis un environnement non privilégié — la même sonde que celle de
l'activation machine. Une installation qui ne peut pas être prouvée est annulée.

**Réintroduire un deuxième inventaire** que le chantier 4 avait supprimé — le risque
conceptuel. Mitigation : préfixes disjoints (`/usr/local/share` vs `/usr/share`),
`origin=system` distinct de `origin=package`, et un `doctor` qui refuse de laisser la
situation implicite. Reste vrai : une machine qui a les deux est une machine mal
administrée, et on ne peut que la diagnostiquer.

**L'illusion `/etc/skel`** — un administrateur convaincu d'avoir déployé pour tout le
monde alors qu'il n'a rien fait pour les comptes existants. C'est le mode d'échec
historique de cette fonctionnalité. Mitigation : ce n'est pas le défaut, le message
nomme la limite avec le nombre de comptes concernés, et le test (étape 10) prouve
l'absence d'effet sur bob autant que la présence sur carol.

**Aucune expérience de test root/multi-utilisateur dans le dépôt** — toute la suite est
conçue pour tourner sans privilège, avec `$HOME` déplacé. Le nouveau script est le
premier à créer des comptes. Mitigation : il est isolé dans un script unique, ne tourne
que dans des conteneurs jetables (jamais sur les runners), et la couche PR reste
entièrement non privilégiée grâce aux crochets d'environnement (§ 7.1).

**Coût CI** — quatre cibles nocturnes de plus, chacune plus lente (création de comptes,
shells `su -l`). Mitigé par le découpage PR (statique) / nightly / release déjà en
vigueur.

**Charge de maintenance d'un quatrième canal** — assumée, mais bien moindre qu'un canal
de paquet : pas de recette externe, pas de revue tierce, pas de `.SRCINFO` à
synchroniser, et le même arbre bit-pour-bit que partout ailleurs.

## 11. Questions ouvertes (arbitrage requis)

1. **`/usr/local/share/nivuus-shell` comme défaut, contre le `/etc/nivuus-shell`
   historique.** Tranché ici en faveur de `/usr/local` (FHS, non-collision avec le
   futur `.deb`), mais cela **casse le chemin** des installations `--system` faites
   avant `8261f77`. Combien y en a-t-il ? Aucune télémétrie, donc indécidable seul.
   Si la réponse est « beaucoup », la migration mérite plus qu'un paragraphe de doc.
2. **Modifier automatiquement le rc global sous `--activate-all`**, ou seulement
   afficher la ligne ? Tranché ici pour « modifier, sous drapeau explicite et
   confirmation nommant le conffile », avec `--print` en échappatoire. Un packageur
   Debian défendrait l'inverse ; c'est un jugement de culture, pas de technique.
3. **`doctor --system --scan-users`** — lire les `$HOME` d'autrui en root, même en
   lecture seule et sur demande explicite, reste une lecture d'autrui. Acceptable, ou à
   supprimer entièrement au profit d'un « nous ne savons pas, demandez à vos
   utilisateurs » ?
4. **macOS.** `--system` y est techniquement possible (`/usr/local/share`,
   `/etc/zshrc`), mais un parc macOS d'entreprise passe par un MDM et un poste
   personnel par brew. Vaut-il la couverture, ou faut-il refuser `--system` sur macOS
   et le dire une bonne fois ?
5. **Configuration de site.** Écartée du périmètre, mais c'est la première chose qu'un
   administrateur demandera après avoir installé pour quatorze personnes. Faut-il la
   traiter dans ce chantier plutôt que d'y revenir dans trois mois ?
6. **Dépendance croisée avec la question ouverte n° 6 du chantier 4.** Ce document y
   répond (l'activation machine appartient à `--system`, le paquet l'affiche). Si
   l'arbitrage tranche l'inverse — le paquet active pour la machine — la phase 3 d'ici
   devient redondante et doit être retirée, pas dupliquée.
7. **Ordre de fusion.** Ce chantier dépend de la phase 0 du chantier 4 **et** de la
   fusion de `feat/install-preuve-ci`. Si le chantier 4 démarre par Homebrew comme
   prévu, `--system` attend. Est-ce l'ordre voulu, sachant que `--system` sert des
   plateformes (Fedora, Alpine) qu'aucune phase du chantier 4 ne servira jamais ?

## Annexe — État réel des vestiges de `--system` dans le code

Constaté, pas supposé (commit `ced7e05`, branche `master`) :

| Emplacement | État |
|---|---|
| `install.sh:44` et `:268-271` | Seul code vivant : l'option est reconnue, affiche deux lignes et sort en 1. |
| `bin/nivuus`, `lib/*.sh` | **Aucune trace.** Pas de `INSTALL_MODE`, pas de `/etc/skel`, pas de `/etc/nivuus-shell`. `nivuus_manifest_begin` est appelé en dur avec `user` (`bin/nivuus`, `cmd_install`) — le paramètre `mode` du format existe et n'attend qu'une seconde valeur. |
| `lib/manifest.sh:33-35` | `NIVUUS_STATE_DIR` est déjà le seul point qui décide où vit l'état : le mode système n'a pas besoin d'un second mécanisme. |
| `tests/e2e/test_install_sh_compat.bats:24-27` | Test **utile** : vérifie que `--system` échoue avec un message explicite. À transformer en test du nouveau comportement, pas à supprimer. |
| `tests/e2e/test_installation.bats:60-63` | **Vestige à supprimer.** `grep -E '(--system\|system.mode)' install.sh` : il ne passe au vert que parce que le mot figure dans le message de refus. Aucune valeur, et il deviendra faussement rassurant. |
| `tests/e2e/test_docs_install.bats:48-49` | Garde inverse : aucune doc ne doit recommander `sudo ./install.sh --system`. À **conserver** et à étendre à la nouvelle forme (`sudo nivuus install --system`) une fois celle-ci réelle. |
| `doc/FEATURES.md:453-460` | Publie encore `curl … \| sudo bash -s -- --system` avec un démenti trois lignes plus bas. À réécrire (et c'est le seul endroit du dépôt qui recommande encore la commande). |
| `doc/CLAUDE.md:50` et `:236-237` | Décrivent le mode historique (`/etc/nivuus-shell`, `/etc/skel`) comme « temporairement indisponible ». À réécrire vers `/usr/local/share` et le modèle d'activation. |
| `doc/TESTING.md:89`, `doc/TEST_PROGRESS.md:64` | Mentionnent un `test_system_install` qui n'a jamais existé. À nettoyer. |
| `README.md` | **Ne mentionne plus `--system`** (contrairement à ce qu'on pourrait croire) : la seule occurrence vit dans `doc/FEATURES.md`. |
| `config/99-cleanup.zsh:27-33` | Compile les `.zsh` **à côté des sources**, sans condition d'inscriptibilité ni d'origine — le correctif appartient à la phase 0 du chantier 4, et ce chantier en dépend. |
| `config/20-autoupdate.zsh:460-471` | `rm -rf` + extraction dans `$NIVUUS_SHELL_DIR`, protégé du seul cas « dépôt git ». C'est ce chemin que le § 5.3 interdit d'emprunter sur un arbre système. |
