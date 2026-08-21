# Empaquetage de Nivuus

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
