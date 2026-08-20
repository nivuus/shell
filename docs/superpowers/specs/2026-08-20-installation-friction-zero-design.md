# Installation « friction zéro » — Design

**Date :** 2026-08-20
**Statut :** approuvé, prêt pour plan d'implémentation
**Chantier :** 1/4 du programme d'adoption (voir « Contexte »)

## Contexte

Objectif porteur : faire adopter Nivuus Shell largement. Positionnement retenu :
**shell zéro-config premium** — un environnement de développement complet qui
fonctionne immédiatement, pour les personnes qui ne veulent pas passer trois
jours dans leurs dotfiles.

Le programme d'adoption se décompose en quatre chantiers indépendants, chacun
avec son propre spec et son propre plan :

1. **Friction zéro : install / uninstall** — le présent document
2. Preuve & confiance (releases signées, benchmarks reproductibles, politique de sécurité)
3. Vitrine (README, démo asciinema, landing page)
4. Distribution & lancement (brew, AUR, awesome-lists, HN/Reddit)

Périmètre plateforme de la v1 publique : **macOS + Linux + WSL/containers**.
Modèle de distribution : **installeur canonique + wrappers de packages natifs**
appelant le même noyau (les wrappers eux-mêmes relèvent du chantier 4).

## Problème

L'installeur actuel (`install.sh`, 590 lignes) empêche l'adoption :

| # | Problème | Gravité |
|---|---|---|
| 1 | `cat > "$HOME/.zshrc"` écrase le `.zshrc` existant sans fusion | bloquant |
| 2 | Aucun `--uninstall` : le backup existe mais rien ne le restaure | bloquant |
| 3 | `sudo apt-get install -y fzf` déclenché en mode *user*, sans demander | bloquant |
| 4 | `chsh` sans vérifier `/etc/shells` → échoue sur macOS + Homebrew zsh | élevée |
| 5 | Aucune détection macOS / WSL / container / headless | élevée |
| 6 | Pas de `--dry-run` : impossible d'auditer avant exécution | élevée |
| 7 | Le « one-liner » du README est un `git clone /tmp` + `rm -rf` | élevée |
| 8 | `init_git_repo()` crée un dépôt git dans `~/.nivuus-shell`, que l'updater interprète comme un « dev checkout » et refuse alors de mettre à jour — **toute installation via le one-liner a l'auto-update silencieusement désactivé** | bloquant |
| 9 | CI `ubuntu-latest` uniquement, aucun test d'installation réelle : `tests/e2e/test_installation.bats` ne fait que vérifier l'existence de fichiers et `--help`, et les suites `e2e/` et `integration/` ne sont **jamais exécutées** par la CI | bloquant |
| 10 | Fichiers `.zwc` compilés commités, provoquant des erreurs de permission masquées par `grep -v "Permission denied"` | hygiène |

## Approche retenue

CLI `nivuus` adossée à un noyau de bibliothèques à responsabilité unique, plus
une matrice de tests d'installation réelle. Deux pièces portent la valeur :

- **Un manifeste d'installation** qui journalise chaque mutation avec le hash de
  l'original, rendant la désinstallation exacte et vérifiable.
- **Des tests d'installation en containers** qui prouvent, à chaque commit, que
  l'installation fonctionne et que la désinstallation ne laisse aucune trace.

Approches écartées : patch incrémental de `install.sh` (ne résout pas l'absence
de preuve, n° 9) ; bootstrap avec release signée et hébergement dédié
(prématuré, relève du chantier 4).

## 1. Architecture et surface CLI

### Modules

Extraction de `install.sh` en bibliothèques sous `lib/`, chacune sourçable et
testable isolément :

| Module | Rôle unique | Ne connaît pas |
|---|---|---|
| `lib/log.sh` | Sortie : couleurs, niveaux, `--quiet`, non-TTY | le métier |
| `lib/detect.sh` | Plateforme : OS, distro, WSL, container, headless, TTY, préfixe brew | le système de fichiers cible |
| `lib/manifest.sh` | Journal des écritures et restauration | ce qu'on installe |
| `lib/zshrc.sh` | Lire / fusionner / retirer le bloc Nivuus d'un `.zshrc` | le reste de l'install |
| `lib/deps.sh` | Constater les dépendances, proposer une commande — jamais l'exécuter | l'UX |
| `lib/steps.sh` | Étapes d'installation, chacune idempotente | l'ordonnancement CLI |

**Contrat commun :** aucun module n'écrit sur disque directement. Toute mutation
passe par `manifest.sh`, qui journalise avant d'écrire et respecte
`NIVUUS_DRY_RUN`. `--dry-run` est ainsi fiable par construction : un module qui
appelle `cp` directement est un bug détectable en test.

### Commandes

Exécutable unique `bin/nivuus` :

```
nivuus install     [--system] [--dry-run] [--yes] [--no-backup] [--minimal] [--with-deps]
nivuus uninstall   [--dry-run] [--purge]
nivuus update                          # remplace nivuus-update (alias conservé)
nivuus doctor                          # remplace bin/healthcheck (alias conservé)
```

`install.sh` reste à la racine comme wrapper d'environ 20 lignes déléguant à
`bin/nivuus install`, traduisant les anciens flags (`--non-interactive` →
`--yes`, `--health-check` → post-hook `doctor`). Aucune rupture pour les URLs,
scripts et installations existants.

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

Détecte l'exécution via pipe (pas de checkout local), télécharge le tarball de
la release, délègue au noyau. Supprime le `git clone /tmp` et le dépôt git
parasite dans `~/.nivuus-shell` — l'auto-update refonctionne.

### Décisions

- **Bash, pas POSIX sh strict**, pour `install.sh` et `bin/nivuus` : le code
  existant et `bin/healthcheck` sont déjà en bash, présent partout dans le
  périmètre visé. Cible **bash 3.2** pour ne pas casser macOS. Seul le
  bootstrap piped est en POSIX sh pur.
- **`--minimal`** : nouveau mode pour SSH / containers / headless — pas de
  `chsh`, pas de nerd fonts, pas de fzf, pas de glyphes dans le prompt.
  Détecté automatiquement, forçable manuellement.

## 2. Manifeste et réversibilité

### Emplacement

`~/.local/state/nivuus/` (XDG), **hors** de `~/.nivuus-shell/` : sinon la
désinstallation supprimerait le journal dont elle a besoin, et une installation
cassée serait irréparable. En mode `--system` : `/var/lib/nivuus/`.

```
~/.local/state/nivuus/
├── manifest.tsv          # journal des mutations
└── backups/<sha256>      # store adressé par contenu (dédupliqué)
```

### Format

TSV, une mutation par ligne, parsable en bash 3.2 sans `jq` :

```
#nivuus-manifest v1  installed_at=2026-08-20T18:04:11Z  mode=user  dir=/home/x/.nivuus-shell
CREATE  /home/x/.nivuus-shell/config/00-core.zsh  9f2a…  -
MODIFY  /home/x/.zshrc                            4c81…  a30e…
MKDIR   /home/x/.nivuus-shell                     -      -
CHSH    /home/x                                   -      /bin/bash
PKG     fzf                                       -      apt-get
```

Colonnes : `action`, `chemin`, `hash après écriture`, `référence backup ou
valeur d'origine`.

### Règles de désinstallation

1. **`CREATE`** — suppression seulement si le hash actuel correspond au hash
   enregistré. Si le fichier a divergé, l'utilisateur l'a édité : on le laisse
   et on le signale. Jamais de suppression silencieuse d'un travail humain.
2. **`MODIFY`** — restauration depuis `backups/<sha>`, après vérification que
   le contenu actuel est bien celui qu'on avait écrit. Sinon on ne touche à
   rien et on indique où trouver le backup.
3. **`MKDIR`** — `rmdir` seulement si vide. Un répertoire contenant des
   fichiers étrangers survit.
4. **`CHSH`** — restauration du shell de connexion d'origine enregistré.

### Données intouchables

`~/.zsh_history` n'est **jamais** supprimé, même avec `--purge`. L'historique
shell est une donnée personnelle irremplaçable. `--purge` étend la suppression
à `~/.zsh_local`, au cache et au state — rien d'autre.

Les paquets système installés via `--with-deps` sont journalisés en action
`PKG` (colonne 4 : le gestionnaire utilisé) à des fins de diagnostic pour
`nivuus doctor`. Ils ne sont **jamais désinstallés** : on ne présume pas qu'ils
étaient là pour nous. `PKG` est donc la seule action que la désinstallation
ignore délibérément.

### Idempotence et réinstallation

`install` sur une installation existante lit le manifeste précédent et le traite
comme un différentiel : les fichiers déjà conformes sont marqués `SKIP` sans
réécriture, et `~/.zshrc` n'est pas re-sauvegardé — sinon le backup « original »
serait écrasé au second passage par une version déjà nivuusée. Le nouveau
manifeste remplace l'ancien atomiquement (`write` + `mv`) ; le store de backups
est conservé.

## 3. Fusion du `.zshrc` et politique de dépendances

### Bloc délimité

```zsh
# >>> nivuus shell >>>
# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.
# Mets tes personnalisations dans ~/.zsh_local
export NIVUUS_SHELL_DIR="$HOME/.nivuus-shell"
source "$NIVUUS_SHELL_DIR/.zshrc"
# <<< nivuus shell <<<
```

Quatre cas, tous idempotents :

- **Pas de `.zshrc`** → création avec le bloc seul.
- **`.zshrc` existant sans bloc** → insertion **en tête**. Placement délibéré :
  ce qui vient après gagne, donc la config de l'utilisateur écrase toujours
  Nivuus.
- **Bloc présent** → remplacement du seul contenu du bloc ; le reste du fichier
  n'est pas touché.
- **Marqueurs corrompus** (ouvrant sans fermant) → arrêt, explication, pointeur
  vers le backup. Aucune réparation heuristique : elle pourrait laisser
  l'utilisateur sans shell fonctionnel.

### Frameworks concurrents

`detect.sh` repère oh-my-zsh, prezto, zinit, starship, powerlevel10k dans le
`.zshrc` existant. On n'y touche pas et on ne les désactive pas ; on avertit
explicitement, en indiquant la ligne concernée. En `--yes`, l'avertissement est
journalisé et l'installation continue.

### Dépendances

**Principe : Nivuus n'exécute jamais un `sudo` que l'utilisateur n'a pas
explicitement demandé.**

| Niveau | Paquets | Comportement |
|---|---|---|
| Requis | `zsh`, `git`, `curl` | Constatés. Si absents : commande exacte pour la plateforme détectée, puis sortie en code 1. On n'installe pas. |
| Recommandé | `fzf` (+ fzf-tab) | Dégradation gracieuse si absent. Proposé, jamais imposé. |
| Optionnel | `grc`, `bat`, `eza`, nerd fonts | Suggestion en fin d'installation. |

Les niveaux 2 et 3 s'installent uniquement via `--with-deps`, qui **affiche la
commande privilégiée exacte et demande confirmation avant exécution** — une
seule fois, groupée. Sans ce flag : une ligne copiable, et on continue. En
`--minimal`, niveaux 2 et 3 sautés sans question.

`chsh` suit la même règle : vérification préalable que `zsh` figure dans
`/etc/shells` (le cas qui casse macOS + Homebrew zsh), ajout de l'entrée
seulement avec consentement, shell d'origine enregistré au manifeste. Pas de
`chsh` en `--minimal`.

**Conséquence recherchée :** `curl … | sh --dry-run` produit un rapport lisible
de tout ce qui sera touché, sans jamais demander de privilège — la réponse à
l'objection `curl | bash`.

## 4. Tests et CI

### Quatre niveaux

**1. Unitaire sur `lib/`** — fusion `.zshrc` sur douze fichiers d'entrée
artificiels (vide, avec bloc, bloc corrompu, oh-my-zsh, CRLF, sans newline
finale) ; détection de plateforme sur `/proc/version` et `uname` simulés ;
manifeste sur des scénarios de divergence de hash.

*Décision (corrigée le 2026-08-20) :* les tests s'écrivent en **bats**, déjà
dépendance du projet (`tests/unit/*.bats`, installé par la CI et requis par
`bin/test`). Une version antérieure de ce spec prévoyait un framework maison
`tests/framework.sh` pour éviter d'ajouter un écosystème — c'était fondé sur
une lecture incomplète : bats est déjà là, et il teste nativement du bash, donc
il couvre `lib/` sans adaptation. `tests/framework.zsh` reste utilisé par le
seul fichier legacy `tests/unit/test_prompt.zsh` ; on n'y touche pas.

**2. Installation réelle en containers** — container vierge → `install` →
`zsh -i -c` réel → vérification du prompt, des fonctions clés, et de l'absence
d'erreur sur stderr.

| Cible | Support |
|---|---|
| Ubuntu 22.04 / 24.04, Debian 12 | Docker |
| Arch, Fedora 41 | Docker |
| Alpine | Docker — valide le chemin sans GNU coreutils |
| macOS 14 | runner `macos-latest`, réactivé |
| WSL2 | container Ubuntu + marqueurs WSL injectés (`/proc/version`, `WSL_DISTRO_NAME`) |
| Headless / container | mode `--minimal` sans TTY |

Le job WSL est une **simulation**, pas un vrai WSL2 : il valide la branche de
code, pas l'environnement. Documenté comme tel, sans prétendre à une couverture
qu'on n'a pas.

**3. Réversibilité** — empreinte de `$HOME` (chemins, hashes, permissions,
shell de login) → `install` → `uninstall` → empreinte → **égalité stricte
exigée**. L'allowlist d'exceptions est vide par défaut ; toute entrée ajoutée
porte un commentaire justificatif.

**4. Bout en bout** — `--dry-run` ne produit aucune mutation (vérifié par la
même empreinte) ; installation de la release précédente puis `update` vers
HEAD ; double installation successive ; installation par-dessus une config
oh-my-zsh existante, qui doit survivre.

### Budget CI

- **Sur PR** : unitaires + install/uninstall Ubuntu et macOS (~4 min)
- **Sur merge master et nightly** : matrice complète, quatre niveaux
- **Sur tag de release** : matrice complète, bloquante — aucune release ne sort
  si un uninstall laisse une trace

Badges du README pointant sur les workflows réels : plateformes testées, et un
badge dédié **« uninstall verified »**.

## 5. Périmètre

### Inclus, en plus de ce qui précède

- **Suppression de `init_git_repo()`**, avec migration : `nivuus update` détecte
  le cas « `.git` sans remote de travail » dans `~/.nivuus-shell` et propose de
  le nettoyer, pour débloquer les installations existantes.
- **`bin/healthcheck` → `nivuus doctor`** (alias conservé), enrichi de ce que le
  manifeste permet : installation partielle, `.zshrc` divergent, bloc corrompu.
- **`.zwc` retirés du dépôt** et ajoutés au `.gitignore` ; suppression du
  `grep -v "Permission denied"` qui masquait le symptôme.

### Hors périmètre

Chacun avec son propre spec ultérieur : formules **brew / AUR / .deb**
(chantier 4 — le noyau est conçu pour, mais on ne les écrit pas ici) ; **README,
démo, landing page** (chantier 3) ; **signature GPG des releases** (chantier 2) ;
**support bash/fish** ; toute **nouvelle fonctionnalité shell** ou refonte des
24 modules de `config/`.

Ce chantier ne change pas ce que fait Nivuus — seulement comment il s'installe,
se prouve et se retire.

## 6. Séquence de livraison

Cinq phases, chacune mergeable seule :

1. **Socle** — `lib/` extrait, manifeste, `--dry-run`, `install.sh` en wrapper.
   Comportement utilisateur identique, mais tracé et auditable.
   *Sortie : tests existants verts, `--dry-run` ne touche rien.*
2. **Réversibilité** — `nivuus uninstall`, fusion `.zshrc` par bloc délimité,
   fin de l'écrasement.
   *Sortie : test d'empreinte `$HOME` vert sur Ubuntu.*
3. **Multi-plateforme** — `detect.sh`, macOS, WSL, `--minimal`, `chsh` sûr,
   politique de dépendances sans sudo surprise.
   *Sortie : installation vérifiée sur macOS et Alpine.*
4. **Preuve** — matrice CI complète, quatre niveaux, badges.
   *Sortie : toutes les cibles vertes, badge « uninstall verified » actif.*
5. **Porte d'entrée** — vrai `curl | sh`, suppression de `init_git_repo` avec
   migration, documentation d'installation.
   *Sortie : le one-liner installe et désinstalle proprement depuis zéro sur
   chaque cible.*

## 7. Risques

**Casser les installations existantes** (phases 1 et 5) — principal risque.
Mitigation : `install.sh` conserve tous ses anciens flags, et la phase 5 inclut
un test explicite « installation v3.0.0 en place → nouvelle installation
par-dessus → tout fonctionne ».

**Coût CI** de la matrice complète — atténué par le découpage PR / nightly /
release de la section 4.
