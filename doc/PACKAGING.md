# Empaquetage de Nivuus

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
`CREATE` pointant dans l'arbre partagé : rien n'y a été créé. La sûreté vient
de l'absence d'entrées, pas d'une exception dans le code. La seule entrée
`CREATE` possible est `~/.zshrc` lui-même, lorsqu'il n'existait pas encore —
c'est elle qui rend `nivuus disable` réversible à l'octet près.

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
2. `bin/nivuus install` **n'écrit jamais** la valeur `package` (un test
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


## Coût de démarrage sans bytecode

Un paquet ne livre aucun `.zwc` et n'en compile aucun (voir « Pourquoi »
ci-dessous). L'arbre partagé n'est donc **jamais** compilé, et le budget de
démarrage de 300 ms doit tenir sans bytecode.

**Mesure du 2026-08-21** (`./bin/benchmark`, moyenne de 5 démarrages) :

| Cible | Avec `.zwc` | Sans `.zwc` | Écart |
|---|---|---|---|
| poste de développement (Debian 13 trixie, zsh 5.9) | 29.7 ms | 33.7 ms | +4.0 ms |
| `debian:12` (zsh 5.9) | 19.3 ms | 22.9 ms | +3.6 ms |
| `ubuntu:22.04` (zsh 5.8.1) | 32.1 ms | 39.7 ms | +7.6 ms |
| `ubuntu:24.04` (zsh 5.9) | 24.6 ms | 27.7 ms | +3.1 ms |
| `archlinux:latest` (zsh 5.9.2) | 27.9 ms | 45.5 ms | +17.6 ms |
| `alpine:3.20` (zsh 5.9, musl) | 15.4 ms | 18.8 ms | +3.4 ms |
| `fedora:40` (zsh 5.9) | 20.1 ms | 25.0 ms | +4.9 ms |

Les conteneurs sont mesurés à la main (`docker run -v "$PWD:/src:ro"`), zsh
installé par le gestionnaire de l'image. Sur `alpine:3.20`, `bin/benchmark`
n'est pas exécutable (il est écrit en bash, absent de l'image nue) : la même
boucle de cinq démarrages est jouée directement en zsh.

**Décision prise sur ce chiffre :** le pire cas mesuré est **45.5 ms**
(`archlinux:latest`), soit **moins d'un tiers du seuil de 150 ms** de la règle
de décision. Branche « < 150 ms » : **rien à faire**. On ne livre pas de
`.zwc` dans les paquets, et on ne livre pas non plus le repli « cache par
utilisateur » décrit plus bas. La question ouverte n° 5 de la spec est close.

L'écart imputable à l'absence de bytecode va de +3 ms à +18 ms selon la
plateforme. La marge restante sous le budget de 300 ms est donc d'environ
**250 ms** dans le pire cas.

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

**Ce repli n'est pas livré** : la mesure ci-dessus ne le justifie pas. Il est
décrit ici pour que la décision reste rejouable si un futur module ajoutait
~250 ms au démarrage sans bytecode.
