# Présentation : README, démo, landing page — Design

**Date :** 2026-08-21
**Statut :** proposé, en attente d'approbation
**Chantier :** 3/4 du programme d'adoption (voir
`2026-08-20-installation-friction-zero-design.md` § Contexte)

## Contexte

Le programme d'adoption comptait quatre chantiers. Trois sont livrés ou en
cours :

1. **Friction zéro : install / uninstall** — livré (manifeste, `nivuus
   uninstall`, matrice CI, `curl | sh` réel).
2. **Preuve & confiance** — livré (releases signées avec refus dur,
   `SECURITY.md` avec modèle de menace, budget de démarrage imposé en CI).
3. **Vitrine : README, démo, landing page** — le présent document.
4. Distribution & lancement (brew, AUR, awesome-lists, HN/Reddit).

C'est le dernier élément du programme sans design. Il est aussi le seul dont
le livrable est lu avant toute exécution de code : c'est le seul endroit où
une erreur coûte un utilisateur qui ne saura jamais qu'il en était un.

Ce que le produit sait faire aujourd'hui, constaté dans le code et non dans la
documentation :

| Capacité | Où c'est prouvé |
|---|---|
| Démarrage sous budget | `tests/performance/test_startup.bats` (`NIVUUS_STARTUP_BUDGET_MS:-300`), ~26–46 ms mesurés |
| Prompt et thèmes pluggables | `themes/nord.zsh`, `themes/dracula.zsh`, `NIVUUS_PROMPT_FORMAT`, `NIVUUS_RPROMPT_FORMAT` |
| IA multi-backend | `config/09-ai-core.zsh` route sur `AI_BACKEND` ∈ {gemini, openai, anthropic} + daemon `agy` |
| IA en contexte | `??`, `?git`, `why`, `explain`, `ask`, suggestions inline (`19-`), erreurs (`22-`), command-not-found (`24-`) |
| Installation réversible | `lib/manifest.sh`, `tests/e2e/test_reversibility.bats`, badge *uninstall verified* |
| Mode paquet | `lib/origin.sh`, `nivuus enable` / `disable`, `doc/PACKAGING.md` |
| Multi-plateforme | `.github/matrix.json` : 6 conteneurs + 2 runners |
| Couverture de test | ~871 unitaires, 195 intégration, 218 e2e |

## Problème

### Le README ne décrit plus le produit

Il fait **596 lignes**. Il a été écrit pour l'état du produit d'il y a cinq
chantiers, puis amendé cinq fois par insertion locale. Le résultat n'est pas
« un peu daté » : il est faux sur des points vérifiables.

| # | Constat | Gravité |
|---|---|---|
| 1 | Trois chiffres de démarrage contradictoires **dans le même fichier** : badge `startup-<300ms`, puce « Sub-100ms startup », section Performance « <100ms (typically 40-60ms) ». Le seul chiffre imposé par un test est 300 ; les deux autres sont des promesses que rien ne tient. | bloquant |
| 2 | « **AI-Powered** — Command suggestions via the Gemini API » et « AI commands require a Google Gemini API key ». `AI_BACKEND` n'apparaît **nulle part** dans `README.md` ni dans `doc/FEATURES.md` : le support OpenAI et Anthropic, livré, est invisible. On documente une contrainte (clé Google) qui n'existe plus. | bloquant |
| 3 | Le **command-not-found assisté** (`config/24-…`, livré la veille) est absent de toute la documentation utilisateur. La fonctionnalité la plus démonstrative du produit n'est mentionnée nulle part. | élevée |
| 4 | La section « Project Structure » liste `bin/healthcheck` et `bin/benchmark` mais **pas `bin/nivuus`**, l'exécutable principal ; elle ignore `lib/` (9 modules), `keys/`, `doc/nivuus.1` ; elle décrit `install.sh` comme « Installation script » alors que c'est un wrapper. Une arborescence recopiée à la main est condamnée à mentir. | élevée |
| 5 | « Automatic backups are created at: **During installation**: `~/.config/nivuus-shell-backup/` » — faux depuis le chantier 1 : l'installation écrit dans `~/.local/state/nivuus/backups/` (`lib/manifest.sh`). Ce chemin ne sert plus qu'à `config_backup` et à l'auto-update. Un utilisateur qui cherche son backup après un incident cherche au mauvais endroit. | élevée |
| 6 | **Quatre langues de section en alternance.** Un README anglais dans lequel ont été insérés, en français : la note packaging, « Vérifier le trousseau de signature », « Plateformes testées », deux puces de la section Updating. C'est le symptôme visible de l'amendement par couches. | élevée |
| 7 | **~160 lignes de cookbook** (`## Usage` → `### System Monitoring`) qui dupliquent `doc/FEATURES.md` (494 lignes) sans le remplacer. Idem « Theme & Prompt » vs `doc/PROMPT.md` (506 lignes), « Updating » vs `doc/SIGNING.md` (377 lignes). Deux sources, aucune autorité. | élevée |
| 8 | La section « Vérifier le trousseau de signature » — **22 lignes de cryptographie et de limites d'attaque** — est placée dans le *Quick Start*, entre la désinstallation et « Restart your terminal ». Le contenu est excellent et doit vivre ; sa place n'est pas le troisième écran d'une page d'accueil. | moyenne |
| 9 | Sous-commandes réelles absentes du README : `nivuus enable`, `nivuus disable`, `nivuus doctor`, `nivuus update`. Le README propose encore `healthcheck`, `nivuus-version`, `nivuus-update` — les alias legacy — comme surface principale. | moyenne |
| 10 | **Aucun visuel.** Pas de capture, pas de démo, pas d'image sociale. Un projet dont l'argument est l'expérience du terminal ne montre pas son terminal. | bloquant |
| 11 | Deux badges décoratifs (`license-MIT`, `shell-ZSH`) : des shields statiques qui n'attestent rien. `tests/unit/test_readme_badges.bats` interdit déjà le badge de workflow figé ou menteur, mais ne voit pas ceux-là. | moyenne |
| 12 | « Contributions are welcome! Please feel free to submit a Pull Request. » sans `CONTRIBUTING.md`, sans mention de `bin/test`, dans un dépôt qui a **1 284 tests** et des conventions fortes. C'est une invitation à ouvrir une PR qui échouera. | moyenne |

### Ce que voit un visiteur en dix secondes

Aujourd'hui, dans l'ordre : un titre, six badges dont deux vides de sens, une
phrase générique (« modern, fast, AI-powered ZSH shell »), puis onze puces à
émoji dont la première est un superlatif faux. Rien de tout cela ne le
distingue de oh-my-zsh, de starship, ou des quatre cents dotfiles-frameworks
de GitHub.

Ce qui rend Nivuus différent — **la désinstallation prouvée bit pour bit,
vérifiée en continu sur neuf cibles** — apparaît à la ligne 52, sous un titre
`### Uninstall`, formulé comme une formalité d'après-vente.

**Le produit enterre son propre argument.**

### `doc/` a grossi sans index

`doc/README.md` prétend être l'index et liste 6 fichiers. Il y en a **10**, et
il oublie exactement ceux que les trois derniers chantiers ont produits :
`INSTALL.md`, `PACKAGING.md`, `SIGNING.md`, `nivuus.1`. Il liste en revanche
`TESTING_UPDATE.md`, `TEST_PROGRESS.md`, `TEST_SUMMARY.md` — trois rapports
d'avancement de chantier, pas de la documentation.

## Approche retenue

**Le README est repositionné autour d'un seul argument, et la démo devient
l'objet qui le porte.** Trois décisions structurent tout le reste :

1. **La promesse est la réversibilité, pas la vitesse.** (§ 1)
2. **Le README descend à ≤ 200 lignes** et cesse d'être une seconde
   documentation ; `doc/` devient l'autorité, avec un index réel. (§ 2)
3. **Une démo asciinema versionnée en texte**, régénérée à la main, dont la
   CI vérifie qu'elle n'a pas divergé du produit. (§ 3)

Et une décision négative, argumentée en § 4 : **pas de landing page.**

Approches écartées :

- **Amender le README une sixième fois.** C'est ce qui a produit les douze
  constats ci-dessus. Le mode de défaillance est l'insertion locale sans vue
  d'ensemble ; il faut une réécriture et un garde-fou de taille.
- **Un site de documentation généré (mkdocs, Docusaurus).** Engagement
  d'infrastructure et de maintenance disproportionné pour dix pages
  Markdown, et incohérent avec la position prise au chantier packaging
  (§ 4.3 : « un job de plus et une clé de plus, pas une infrastructure »).
- **Une vidéo (YouTube/Loom).** Hébergement tiers, non versionnable, non
  diffable en revue, non indexable, illisible sans son ni réseau. Écartée
  sans hésitation.

## 1. Public et promesse

### À qui on parle

**Le développeur qui vit dans un terminal, sur plusieurs machines qui ne lui
appartiennent pas toutes.** Un poste de travail, des serveurs en SSH, des
conteneurs. Il a déjà un `.zshrc`, souvent accumulé sur des années. Il a
peut-être déjà essayé oh-my-zsh et l'a retiré ; il se souvient de ce que
« retirer » lui avait coûté.

Ce n'est **pas** le débutant qui n'a jamais configuré de shell (il installera
ce que son collègue lui dit d'installer), ni le bricoleur de dotfiles qui
tient à ses 900 lignes (il ne veut pas d'un framework, et c'est légitime).

### Le crochet : l'engagement réversible

Le frein n° 1 à l'essai d'un framework de shell n'est pas le manque de
fonctionnalités. C'est **la peur d'abîmer un environnement qui marche**. Un
`.zshrc` est un fichier qu'on a mis dix ans à écrire et qu'on ne sait plus
reconstituer.

Nivuus est, à notre connaissance, le seul de sa catégorie à pouvoir répondre :
*installe, essaie, et si tu n'aimes pas, `nivuus uninstall` rend ton `$HOME`
identique bit pour bit — et ce n'est pas une promesse, c'est un test qui tourne
chaque nuit sur neuf cibles et qui rougit le badge quand il échoue.*

**Promesse en une phrase (texte du sous-titre, à reprendre tel quel) :**

> **A complete ZSH environment in one command — and one command to remove it,
> byte for byte.**

### Ce qui est preuve, et non crochet

| Axe | Rôle | Pourquoi |
|---|---|---|
| **Réversibilité prouvée** | **crochet** | Personne d'autre ne l'offre, et c'est le frein réel à l'essai. |
| Vitesse (<300 ms imposé, ~30 ms réels) | preuve | *Tout le monde* promet un shell rapide. Ce qui distingue n'est pas le chiffre, c'est qu'un test le fasse échouer. La vitesse devient intéressante **parce qu'elle est imposée**, pas parce qu'elle est basse. |
| Zéro plugin, ZSH pur | preuve | C'est un mécanisme, pas un bénéfice. Il explique la vitesse et l'absence de dépendances ; il ne fait envie à personne en soi. |
| Assistance IA | preuve, en second | Différenciant, mais il exige une clé tierce et un réseau. En faire le crochet, c'est faire dépendre le premier argument d'un service qu'on ne contrôle pas — et perdre tous ceux qui ne veulent pas d'IA dans leur shell. |
| Multi-plateforme, releases signées | preuve | Rassure celui qui est déjà convaincu ; ne convainc personne. |

**Corollaire de structure :** la désinstallation cesse d'être une section
d'après-vente. Elle est **dans le premier écran, à trois lignes du
one-liner**, parce que c'est elle qui autorise le lecteur à exécuter le
one-liner.

## 2. Structure cible du README

Le README est la page d'accueil GitHub. On le traite comme telle : ce qui
n'aide pas à décider *dans le premier écran* descend ou sort.

### Plan

```
1. Titre + une phrase (la promesse) + 4 badges de preuve
2. LA DÉMO                                    ← premier objet non textuel
3. Install (one-liner) — Uninstall (3 lignes) — une phrase sur curl|sh + lien SECURITY.md
4. What you get         — 6 puces max, chacune avec un lien vers doc/
5. Proof                — tableau des plateformes + budget de démarrage + liens CI
6. Configure            — ~12 lignes de ~/.zsh_local + lien doc/PROMPT.md
7. Documentation        — index vers doc/, une ligne par fichier
8. Contributing · Security · License
```

**Budget : 200 lignes, imposé par un test** (§ 5). C'est un garde-fou grossier
et assumé comme tel : la métrique qui a été violée cinq fois est la longueur,
c'est donc elle qu'on instrumente.

### Ce qui reste, et sous quelle forme

**Les badges : quatre, tous adossés à une preuve.**

```markdown
[![Version](…/releases)]  [![Tests](…/tests.yml/badge.svg?branch=master)]
[![uninstall verified](…/uninstall-verified.yml/badge.svg?branch=master)]
[![startup <300ms](…/matrix.yml/badge.svg?branch=master)]
```

`license-MIT` et `shell-ZSH` sont supprimés. Ils n'attestent rien : la licence
est dans `LICENSE` et affichée par GitHub dans la barre latérale ; « shell:
ZSH » est déjà dans le titre et dans la phrase de promesse.

**« What you get » — six puces, pas onze, sans émoji décoratif ni superlatif.**
Chaque puce cite un artefact vérifiable et pointe la doc qui l'explique :

```markdown
- **Removable.** `nivuus uninstall` restores every file it touched from a
  content-addressed backup. Verified nightly on 9 targets — see the badge.
- **Fast, and held to it.** A CI test fails the build if an interactive
  shell takes more than 300 ms to start (measured: 26–46 ms). → [Performance](doc/FEATURES.md#performance)
- **No plugin manager.** Pure ZSH, 24 modules, no oh-my-zsh, no framework
  underneath. → [doc/CLAUDE.md](doc/CLAUDE.md)
- **Optional AI, your key, your provider.** Gemini, OpenAI or Anthropic —
  `??`, `why`, `explain`, and a command-not-found that suggests the package
  to install. Nivuus works fully without it. → [doc/FEATURES.md](doc/FEATURES.md#ai)
- **A prompt you can re-lay-out.** Themes and a token-based prompt format,
  no code change. → [doc/PROMPT.md](doc/PROMPT.md)
- **Signed releases.** An update whose signature does not verify is refused
  outright, with no fallback. → [SECURITY.md](SECURITY.md)
```

**Le `curl | sh` reste honnête, en une phrase, pas en vingt-deux lignes :**

Le bloc de code contient le one-liner inchangé (déjà vérifié par
`test_docs_install.bats`), suivi de ce paragraphe et de rien d'autre :

> It verifies a SHA-256 checksum, writes a delimited block into your
> `~/.zshrc`, needs no `sudo` and no `git`. Add `--dry-run` to see everything
> it would touch without touching it. What this **cannot** protect you from is
> documented, in plain terms, in [SECURITY.md](SECURITY.md#first-install).

Le pointeur vers le problème d'amorçage est **conservé et rendu plus
visible** (il est sous le one-liner, pas trois sections plus bas), mais son
développement — le pourquoi, l'épinglage `--verify-key`, ce que la signature
protège et ce qu'elle ne protège pas — descend dans `doc/INSTALL.md` et
`SECURITY.md`. Raccourcir n'est pas édulcorer : c'est déplacer l'argument là
où il sera lu par celui qui se pose la question, au lieu d'être sauté par tous
les autres.

### Ce qui part

| Section actuelle | Destination | Justification |
|---|---|---|
| `## Usage` (~160 l.) | `doc/FEATURES.md`, complété | Double emploi pur. `FEATURES.md` est déjà l'endroit, il est déjà plus complet. |
| `## Theme & Prompt` (détail) | `doc/PROMPT.md` | Idem. Le README garde 12 lignes de `~/.zsh_local`. |
| `## Updating` (~80 l.) | **`doc/UPDATING.md`** (nouveau) + `doc/SIGNING.md` | Le détail des 7 étapes de vérification n'aide personne à décider d'installer. Le README garde une phrase. |
| `### Vérifier le trousseau` | `doc/INSTALL.md` + `SECURITY.md` | Voir ci-dessus. |
| `## Development` + `dev.sh` | `doc/CLAUDE.md` | C'est un guide contributeur, il en existe un. |
| `## Project Structure` | **supprimée, pas déplacée** | Une arborescence recopiée à la main ment par construction, et aucun test raisonnable ne peut la maintenir. `doc/CLAUDE.md` décrit l'architecture ; `ls` décrit l'arborescence. |
| `## Requirements` | `doc/INSTALL.md` | Y figure déjà, par plateforme, ce qui est plus utile. |
| `## Troubleshooting` | **`doc/TROUBLESHOOTING.md`** (nouveau) | Et surtout : la réponse à « ça ne marche pas » est `nivuus doctor`. Le README cite la commande, pas quatre symptômes arbitraires. |
| `## Credits` | conservée, 2 lignes | Nord et les backends IA. Obligation morale, coût nul. |

### Rangement de `doc/`

- `doc/README.md` devient l'index **réel et exhaustif** de `doc/`, testé dans
  les deux sens (§ 5.6).
- `TESTING_UPDATE.md`, `TEST_PROGRESS.md`, `TEST_SUMMARY.md` sont
  **supprimés** : ce sont des rapports d'avancement de chantier, pas de la
  documentation. Ce qu'ils contiennent d'encore vrai (comment lancer les
  suites, ce que couvre chaque niveau) est fusionné dans `doc/TESTING.md`.
- `doc/FEATURES.md` est complété sur les deux trous constatés : **IA
  multi-backend** (`AI_BACKEND`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
  `GEMINI_AUTH_MODE`, le daemon `agy`) et **command-not-found**.
- `CONTRIBUTING.md` minimal à la racine : `bin/test`, la convention de
  commit, et le fait que la documentation est testée — pour qu'une première
  PR ne se casse pas sur une règle invisible.

### Langue

**Le README passe intégralement en anglais.** Le chantier 4 vise
awesome-lists, HN et Reddit ; un README à moitié français y perd la moitié de
son lectorat, et l'alternance actuelle est lue comme un défaut de soin. Les
specs internes (`docs/superpowers/`) et la doc technique restent en français —
c'est la langue de travail du projet, et le changer n'est pas dans ce
chantier. Un test interdit le mélange **dans le README seul** (§ 5.7).

## 3. La démo

### Format

**Source de vérité : un enregistrement asciinema (`.cast`) versionné.**
Artefact affiché : un **SVG animé** produit par `svg-term-cli`.

```
tools/demo/
├── scenario.txt      # source déclarative : une commande par ligne + délais
├── record.sh         # rejoue le scénario dans le conteneur CI, produit le .cast
└── render.sh         # .cast → docs/assets/demo.svg (+ demo.stamp)
docs/assets/
├── demo.cast         # source de vérité, TEXTE, diffable
├── demo.svg          # ≤ 250 Ko, affiché par le README
└── demo.stamp        # hachages : scénario, cast, version — voir § 3.4
```

**Pourquoi asciinema plutôt qu'un GIF enregistré à l'écran :** le `.cast` est
du texte. Une PR qui modifie la démo est **lisible en revue** — on voit la
commande ajoutée, la sortie qui a changé. Un GIF est un blob de 3 Mo qu'aucun
relecteur ne peut auditer, et qui grossit le dépôt à chaque itération. Pour un
projet dont tout le harnais de test consiste à confronter la documentation au
binaire, une démo non auditable serait une régression de méthode.

**Pourquoi SVG plutôt que GIF pour l'affichage :** poids (dizaines de Ko contre
plusieurs Mo), texte net à toute échelle, pas de recompression.

**Risque assumé et à vérifier :** GitHub sert les images du README via son
proxy et sanitise les SVG ; l'animation CSS produite par `svg-term` doit être
confirmée empiriquement sur une branche avant de committer l'artefact final.
**Critère de repli explicite :** si l'animation ne joue pas dans le README
rendu par GitHub, on rend le même `.cast` en GIF via `agg` (budget relevé à
2 Mo) — le `.cast` reste la source, seule `render.sh` change. Cette
vérification est la première tâche de la phase 4 (§ 6), pas une découverte de
fin de chantier.

### Ce qu'elle montre — 35 secondes, un seul plan, sans coupure

Le scénario **raconte la promesse**, il ne fait pas le tour du produit.

| t | Ce qui se passe | Ce que ça prouve |
|---|---|---|
| 0–7 s | Conteneur vierge. `curl -fsSL … \| sh` → l'installation se termine. | Une commande, pas de `sudo`, pas de question. |
| 7–11 s | `exec zsh` → le prompt apparaît. Le temps de démarrage réel est affiché. | La vitesse, mesurée à l'écran plutôt qu'affirmée. |
| 11–17 s | Une commande qui n'existe pas → le command-not-found propose le paquet et la commande d'installation. | L'IA en contexte, sans qu'on l'ait invoquée. |
| 17–23 s | `?? "find files bigger than 100M"` → la suggestion s'affiche. | L'assistance à la demande. |
| 23–27 s | `cd` dans un dépôt git → le prompt affiche branche et état. | Le prompt, sans en faire une démonstration séparée. |
| 27–34 s | `nivuus uninstall`, puis le `diff` des empreintes de `$HOME` avant/après : **vide**. | **Le crochet.** C'est le plan que personne d'autre ne peut tourner. |

**Le plan final est le point de la démo.** S'il fallait couper, on couperait
tout le reste avant lui.

Contraintes de tournage, pour que l'enregistrement soit reproductible et
publiable : conteneur, `HOME` neuf, nom d'hôte fixé à `demo`, `PS1` du shell
hôte neutre, aucune clé API réelle (le backend IA est servi par un stub local
au conteneur, qui renvoie une réponse figée — **fait apparaître dans le
scénario, pas caché**), largeur 100 colonnes, thème `nord` par défaut.

### Comment on la régénère

```bash
tools/demo/record.sh          # rejoue scenario.txt dans le conteneur, écrit demo.cast
tools/demo/render.sh          # demo.cast → demo.svg + demo.stamp
```

**Production manuelle, jamais en CI.** Trois raisons :

1. Une régénération automatique produit un **diff binaire à chaque PR**, que
   personne ne relit — c'est exactement la situation qu'on veut éviter.
2. Un artefact de vitrine doit passer devant un humain une fois. Le timing,
   la lisibilité, l'absence de bruit à l'écran ne sont pas testables.
3. Le risque de fuite (chemin, nom d'hôte, jeton) est faible mais réel ; on
   ne veut pas qu'un artefact publié soit produit sans regard.

**Ce qui va en CI, ce n'est pas la production : c'est la détection de
divergence.**

### Comment on détecte qu'elle a divergé

Une démo périmée est pire qu'aucune démo. Quatre gardes, du moins cher au plus
cher (§ 5.8 pour les tests) :

1. **Les commandes du scénario existent.** Chaque première lexie de
   `scenario.txt` est confrontée à `nivuus help`, aux fonctions et alias des
   modules `config/`, ou à `command -v`. Une démo qui montre une commande
   supprimée fait rougir la CI. *Coût : instantané, tourne sur chaque PR.*
2. **Le scénario est rejoué pour de vrai.** Dans le conteneur d'installation
   déjà utilisé par `tests/e2e/`, en non-interactif : chaque commande doit
   sortir en 0 et la sortie ne doit contenir aucun motif d'échec. C'est le
   garde qui compte : il rend impossible de *montrer un flux qui ne marche
   plus*. *Coût : un job conteneur, sur merge master et nightly.*
3. **Le tampon de fraîcheur.** `demo.stamp` contient le SHA-256 de
   `scenario.txt`, celui de `demo.cast`, et la version du projet au moment de
   l'enregistrement. La CI recalcule et compare : modifier le scénario sans
   réenregistrer, ou committer un SVG qui ne dérive pas du `.cast` présent,
   échoue. *Coût : instantané.*
4. **Péremption par version.** Sur tag de release, si la version de
   `demo.stamp` est antérieure à la **mineure** courante, le workflow de
   release échoue. Sur les patchs, non : le coût serait constant pour un
   bénéfice nul. C'est la règle qui garantit qu'aucune version mineure ne
   sort avec une démo d'une génération précédente.

Ce que ces gardes **ne** couvrent pas, et qu'on assume : le rendu visuel
lui-même (couleurs, alignement, rythme). Aucun test ne dira que la démo est
devenue laide. C'est l'objet de la relecture humaine au moment de
l'enregistrement, et c'est écrit ici pour que ce ne soit pas une surprise.

## 4. La landing page : non

**Conclusion : on ne fait pas de landing page.** Ce n'est pas un report
poli, c'est un refus argumenté.

### Pourquoi

1. **Le README *est* la landing page de ce public.** Un développeur qui
   découvre un outil de terminal arrive par une awesome-list, un commentaire
   HN ou un `awesome-zsh` — c'est-à-dire **par un lien GitHub**. Une page
   séparée n'ajoute pas une entrée : elle ajoute un saut entre l'endroit où
   il atterrit et l'endroit où il décide.
2. **Elle serait la seule surface non testable du projet.** Tout le reste
   est confronté au binaire : `nivuus help` contre la page de manuel,
   `doc/INSTALL.md` contre les sous-commandes réelles, les badges contre les
   workflows. Une page HTML échapperait à ce harnais — et c'est précisément
   le contenu qui pourrit le plus vite, parce qu'il est le plus éloigné du
   code. On introduirait volontairement le seul endroit du dépôt où il est
   possible de mentir sans qu'un test s'en aperçoive.
3. **Elle contredirait une position déjà prise deux fois.** Le chantier
   signature a refusé l'hébergement dédié ; le chantier packaging a écarté le
   dépôt APT tant qu'il n'était pas « un job de plus et une clé de plus, pas
   une infrastructure ». Une page à maintenir est un engagement permanent
   pour un gain ponctuel.
4. **Ce qu'elle apporterait de plus n'existe pas.** Une bonne landing page
   apporte : une démo au-dessus de la ligne de flottaison (→ elle y sera,
   dans le README) ; un comparatif (→ on n'en a pas d'honnête à écrire : le
   seul axe où on domine sans discussion est la réversibilité, et il tient
   en une puce) ; des témoignages (→ il n'y en a pas) ; du SEO (→ un dépôt
   GitHub bien nommé, avec description et topics, se référence mieux qu'une
   page neuve sans backlink).

### Ce qu'on fait à la place

Le vrai manque n'est pas une page : c'est que **tout partage de Nivuus est
laid**. Un lien collé dans Slack, Twitter ou HN affiche aujourd'hui la carte
sociale par défaut de GitHub. On corrige ça, pour un coût de quelques minutes :

- **Description et topics du dépôt** (`zsh`, `shell`, `dotfiles`, `prompt`,
  `cli`, `ai`), source versionnée dans `package.json`, poussée par
  `tools/repo-meta.sh` (`gh repo edit`) — pas de valeur qui n'existe qu'à
  la main dans une UI web.
- **Social preview image** : une image OG dérivée d'une frame de la démo, la
  promesse en une ligne. C'est ce que voient tous ceux qui ne cliquent pas.

### Le critère de réouverture

Pour que ce refus ne devienne pas un dogme, il est daté par des conditions.
On rouvre la question dès que **l'une** est vraie :

- un canal d'installation tiers existe (brew tap, AUR) et a besoin d'une URL
  courte et stable comme point d'ancrage documentaire ;
- `doc/` dépasse ~15 pages et devient non navigable sans recherche ;
- un contenu non-Markdown devient nécessaire (comparateur, playground).

**Et l'architecture est décidée d'avance**, parce que c'est elle qui empêche
le pourrissement : **GitHub Pages, généré depuis `doc/`**, avec une règle non
négociable — *aucun contenu qui n'existe que sur la page*. Tout ce que la page
affiche doit être un `.md` du dépôt, donc soumis aux mêmes tests. Une page qui
ne peut pas diverger est une page qui ne peut pas pourrir.

## 5. Tests : ce qui doit échouer quand le README ment

Le projet teste déjà sa documentation : `test_readme_badges.bats` (badge
orphelin, non épinglé, figé, `continue-on-error`, tableau des plateformes
contre `.github/matrix.json`, budget de démarrage), `test_manpage.bats`
(`nivuus help` contre `doc/nivuus.1`), `test_docs_install.bats` (one-liner
identique entre README et `doc/INSTALL.md`, sous-commandes citées qui
existent), `test_docs_packaging.bats` (aucune commande de canal promise avant
que le canal existe).

**On étend le principe à la vitrine.** Nouveaux fichiers :
`tests/unit/test_readme_claims.bats`, `tests/unit/test_docs_index.bats`,
`tests/e2e/test_demo_scenario.bats`.

| # | Ce qui échoue | Fichier |
|---|---|---|
| 5.1 | **Une commande citée en bloc `bash` dans le README n'existe pas** — généralise `test_docs_install.bats` du seul `doc/INSTALL.md` à tout le README : chaque première lexie est une sous-commande de `nivuus help`, une fonction ou un alias d'un module `config/`, un binaire de `bin/`, ou un outil déclaré en prérequis. | `test_readme_claims.bats` |
| 5.2 | **Un superlatif non mesuré apparaît** — liste noire : `blazing`, `lightning`, `ultimate`, `the best`, `just works`, `insanely`, `revolutionary`. Une promesse qualitative n'est pas testable ; on interdit donc d'en écrire. (« Lightning Fast » est dans le README d'aujourd'hui.) | `test_readme_claims.bats` |
| 5.3 | **Un chiffre de démarrage diverge du budget imposé** — il n'existe **qu'un** motif `\d+ ?ms` autorisé dans le README, et il vaut `NIVUUS_STARTUP_BUDGET_MS`. Les mesures indicatives sont autorisées ailleurs, avec leur méthode. Ce test, seul, aurait tué le constat n° 1. | `test_readme_claims.bats` |
| 5.4 | **Un badge n'atteste rien** — durcit l'existant : tout badge est soit un workflow réel (règles actuelles), soit adossé à un autre test nommé en commentaire. Les shields statiques décoratifs sont refusés. | `test_readme_badges.bats` |
| 5.5 | **Le README dépasse 200 lignes.** Grossier, volontairement. C'est la seule contrainte qui résiste à l'amendement par couches. | `test_readme_claims.bats` |
| 5.6 | **`doc/` et son index divergent** — tout fichier de `doc/` est listé dans `doc/README.md` et réciproquement ; tout lien relatif du README et de `doc/*.md` pointe un fichier existant. | `test_docs_index.bats` |
| 5.7 | **Le README mélange les langues** — liste noire de lexèmes français fréquents (`désinstall`, `empreinte`, `paquet`, `trousseau`, `mise à jour`, `n'est pas`). Grossier et sans ambiguïté. | `test_readme_claims.bats` |
| 5.8 | **La démo a divergé** — les quatre gardes du § 3.4 : commandes du scénario existantes (PR), scénario rejoué en conteneur (merge/nightly), `demo.stamp` cohérent avec `scenario.txt`/`demo.cast` (PR), version du stamp ≥ mineure courante (release). Plus : `demo.svg` ≤ 250 Ko. | `test_demo_scenario.bats` |
| 5.9 | **Une puce de « What you get » n'est pas ancrée** — chaque puce contient un lien vers un fichier existant de `doc/` ou `SECURITY.md`. Empêche la puce marketing sans référent. | `test_readme_claims.bats` |
| 5.10 | **Une variable d'environnement citée dans le README n'est lue par aucun module** — `grep` des `NIVUUS_*`, `ENABLE_*`, `AI_*` du README contre `config/` et `lib/`. Aurait tué le constat n° 2 dans l'autre sens (documenter une variable disparue). | `test_readme_claims.bats` |

Budget CI : 5.1 à 5.7, 5.9 et 5.10 sont du `grep`, coût négligeable, sur
chaque PR. Seul le rejeu du scénario (5.8, garde 2) demande un conteneur : il
rejoint le job d'installation existant sur merge master et nightly.

## 6. Périmètre

### Inclus

- Réécriture complète du `README.md` selon le § 2, ≤ 200 lignes, en anglais.
- Redistribution du contenu déplacé ; création de `doc/UPDATING.md`,
  `doc/TROUBLESHOOTING.md`, `CONTRIBUTING.md`.
- `doc/README.md` refait en index exhaustif ; suppression de
  `TESTING_UPDATE.md`, `TEST_PROGRESS.md`, `TEST_SUMMARY.md` après fusion
  dans `doc/TESTING.md`.
- Complément de `doc/FEATURES.md` : IA multi-backend et command-not-found.
- Outillage de démo (`tools/demo/`), scénario, `.cast`, `.svg`, tampon.
- Les dix tests du § 5.
- Métadonnées du dépôt : description, topics, image sociale,
  `tools/repo-meta.sh`.

### Hors périmètre

- **La landing page** — refusée au § 4, avec critères de réouverture.
- **La traduction de `doc/` en anglais** — seul le README est normé ici ; le
  reste est un chantier en soi, à rattacher au chantier 4.
- **La documentation de `--system`** — un chantier est en cours dessus et
  produira sa propre section dans `doc/INSTALL.md`. Le README réécrit **ne
  mentionne pas `--system`** : l'installation multi-utilisateur n'est pas un
  argument de page d'accueil, et anticiper créerait un conflit de merge sur
  le fichier le plus disputé du dépôt.
- **Chantier 4** : brew, AUR, awesome-lists, soumission HN/Reddit.
- **Toute nouvelle fonctionnalité shell.**

Ce chantier ne change rien à ce que fait Nivuus — seulement à ce qu'on en dit,
et à ce qui rougit quand on en dit trop.

## 7. Séquence de livraison

Cinq phases, chacune mergeable seule. L'ordre n'est pas négociable sur un
point : **la vérité avant la beauté**. On arrête de mentir avant de
restructurer, et on restructure avant d'illustrer.

1. **Vérité** — correction des faussetés du README *sans* le restructurer :
   chiffres de démarrage, IA multi-backend, chemin des backups, sous-commandes
   legacy, arborescence supprimée. Plus les tests 5.1–5.4, 5.9, 5.10.
   *Sortie : les nouveaux tests échouent sur `HEAD~1` et passent sur `HEAD`.*
2. **Doc rangée** — index réel, suppression des trois rapports,
   `doc/UPDATING.md`, `doc/TROUBLESHOOTING.md`, `doc/FEATURES.md` complété,
   test 5.6.
   *Sortie : index et liens verts ; aucun contenu perdu (vérifié en revue).*
3. **README réécrit** — structure cible, anglais, ≤ 200 lignes, sans démo
   (aucune image cassée pendant l'intervalle). Tests 5.5, 5.7.
   *Sortie : longueur, unilinguisme et liens verts ; le premier écran contient
   la promesse, le one-liner et la désinstallation.*
4. **Démo** — d'abord la vérification du rendu SVG animé sur GitHub (§ 3.1),
   puis l'outillage, le scénario, l'enregistrement, l'insertion en tête du
   README, et les gardes 5.8.
   *Sortie : `demo.svg` affiché et animé dans le README rendu par GitHub ;
   modifier `scenario.txt` sans réenregistrer fait rougir la CI.*
5. **Vitrine GitHub** — description, topics, image sociale dérivée de la
   démo, `CONTRIBUTING.md`, `tools/repo-meta.sh`.
   *Sortie : un lien collé dans Slack affiche la promesse et une frame de la
   démo.*

## 8. Risques

**La démo périme malgré tout.** Risque principal, et raison d'être du § 3.4.
Les gardes couvrent l'existence des commandes, le fonctionnement du flux et la
fraîcheur par version. Ils ne couvrent **pas** le rendu visuel : une démo peut
rester exacte et devenir laide ou illisible. Mitigation résiduelle : la
régénération manuelle impose un regard humain à chaque enregistrement.

**Perte d'information en déplaçant 400 lignes.** Mitigation : le déplacement
est un transfert de contenu, pas une suppression — sauf « Project Structure »,
supprimée délibérément et argumentée. Le test 5.6 (liens) attrape les
références orphelines, et la revue de la phase 2 vérifie l'exhaustivité.

**Le raccourcissement casse des ancres externes** (`#-usage`, `#-updating`
peuvent être liés depuis des blogs ou des issues). Impact faible sur un projet
peu diffusé, et le coût de le prévenir (conserver des titres vides) dépasse le
bénéfice. Accepté.

**Le rendu SVG animé ne fonctionne pas sur GitHub.** Traité comme une décision
à vérifier en début de phase 4, avec un repli GIF déjà défini, plutôt que comme
une hypothèse.

**Le README regrossit.** C'est exactement ce qui s'est produit cinq fois. Le
seul remède mécanique est le test de longueur (5.5). Il sera un jour ressenti
comme une gêne : c'est le signe qu'il fonctionne. Le relever se discute en
revue, pas dans le commit qui en a besoin.

**La démo publie une donnée sensible.** Mitigation : tournage en conteneur,
nom d'hôte fixe, backend IA remplacé par un stub local déclaré dans le
scénario, et surtout — le `.cast` est du texte, donc entièrement auditable
dans le diff de la PR qui l'introduit. C'est l'argument décisif contre le GIF.

## 9. Questions ouvertes

1. **Anglais intégral du README** — tranché ici (§ 2), mais c'est une décision
   de goût autant que de portée : si l'auteur préfère un README français, la
   structure et tous les tests restent valides, seul 5.7 change de liste noire.
2. **Rendu SVG animé sur GitHub** — à vérifier empiriquement (§ 3.1) ; le
   repli est défini, la décision finale ne peut pas être prise sur document.
3. **Le stub IA de la démo** — un stub garantit un enregistrement
   reproductible et sans clé, mais montre une réponse qui n'est pas celle
   d'un vrai modèle. Alternative : une vraie clé jetable, révoquée après
   l'enregistrement, au prix d'une démo non reproductible à l'identique.
   Question de préférence entre reproductibilité et authenticité, non
   tranchée.
4. **Le seuil de 200 lignes** — choisi comme « environ deux fois plus court
   que le double emploi actuel avec `doc/` ». Il n'est pas dérivé d'une
   mesure ; il est arbitraire et devra sans doute être ajusté une fois la
   structure cible écrite.
5. **La péremption par mineure (§ 3.4, garde 4)** — si le rythme de release
   s'accélère, réenregistrer à chaque mineure peut devenir pénible. Aucune
   donnée pour trancher aujourd'hui ; à réévaluer après trois releases.
