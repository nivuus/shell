# Charte Nivuus appliquée au terminal — design

> Décidé le 24 août 2026. Applique `docs/charte.md` du dépôt `nivuus/design`
> (socle 0.3.0) aux sorties de `nivuus-shell`.
> La charte fait foi. Ce document ne redit pas ses règles : il décide comment
> elles se transposent dans un terminal, et consigne les deux points où le
> terminal ne permet pas de les appliquer à la lettre (§ 6).

## 1. Intention

Les sorties que Nivuus écrit lui-même parlent aujourd'hui trois dialectes de
couleur sans rapport entre eux : `lib/log.sh`, `bin/healthcheck` et
`bin/benchmark` redéfinissent chacun leur propre `RED/GREEN/YELLOW/BLUE`, et
les modules IA emploient des codes ANSI-256 choisis au cas par cas, gris de
second plan compris.

L'objectif est une source unique, alignée sur les quatre sémantiques de la
charte, et vérifiable contre `assets/tokens.css`.

## 2. Périmètre

### 2.1 Dans le périmètre

Les surfaces non interactives que Nivuus produit :

| Fichier | Nature |
|---|---|
| `lib/log.sh` | helpers `log_info/ok/warn/error/dry` |
| `lib/steps.sh`, `lib/manifest.sh`, `lib/zshrc.sh` | consommateurs de `log_*` |
| `bin/nivuus` | consommateur de `log_*` |
| `bin/healthcheck`, `bin/benchmark`, `bin/test` | codes ANSI définis localement |
| `config/22-ai-errors.zsh` | analyse d'erreur IA |
| `config/24-ai-command-not-found.zsh` | assistant de paquets IA |

### 2.2 Hors périmètre, et pourquoi

`config/05-prompt.zsh`, `config/03-completion.zsh`, `config/17-colorization.zsh`,
`config/98-syntax.zsh`, `config/18-autosuggestions.zsh`, `themes/*.zsh`.

Le contrat `THEME_*` et `doc/PROMPT.md` ne sont pas touchés.

Le prompt et la colorisation des outils tiers emploient la couleur pour
hiérarchiser — path en cyan, venv en magenta, AWS en orange, dossier en bleu —
ce que le § 2.4 de la charte interdit. Les y soumettre reviendrait à retirer la
distinction par teinte des sorties de `ls`, `fzf`, `bat` et du surlignage
syntaxique, dont la lisibilité repose entièrement dessus. La décision est de
laisser ces surfaces sur la palette du thème actif (Nord par défaut) et de
n'appliquer la charte qu'à ce que Nivuus énonce en son nom propre. Cette
frontière est la décision structurante de ce document ; l'élargir est un autre
projet, pas un ajustement.

## 3. `lib/charte.sh`

### 3.1 Forme

Un unique fichier compatible `bash` et `zsh`, sourcé indifféremment par
l'installeur (`bash`) et par les modules `zsh` — pas du `sh` POSIX : le fichier
emploie `$'...'` pour les séquences ANSI, une extension `bash`/`zsh` absente de
POSIX. Sous `dash`, `$'...'` n'est pas interprété et se retrouve reproduit tel
quel dans les variables `NIVUUS_C_*`, ce qui corromprait silencieusement toute
sortie qui les consomme. Tous les consommateurs réels sont `bash` ou `zsh`
(`install.sh`, `bin/nivuus`, `bin/healthcheck`, `bin/benchmark` en `bash`,
`bin/test` en `zsh`) ; le fichier n'est donc jamais sourcé sous `dash`, mais ne
prétend plus l'être compatible. Il est déployé chez l'utilisateur par
`nivuus_step_copy_tree`, qui copie déjà `lib/` (`lib/steps.sh`).

Il n'expose que sept variables, et ne définit aucune fonction :

    NIVUUS_C_DANGER  NIVUUS_C_WARN  NIVUUS_C_OK  NIVUUS_C_BUSY
    NIVUUS_C_TEXT    NIVUUS_C_STRONG  NIVUUS_C_OFF

Il pose `NIVUUS_CHARTE_LOADED=1` en fin de fichier, qui signale que le fichier
a été sourcé (§ 4.3) — ce n'est plus une garde de rechargement depuis que
`_ai_charte_load` resource à chaque appel.

### 3.2 Vecteur

`NO_COLOR` posé, ou sortie non-TTY : les sept variables valent la chaîne vide.
C'est le comportement actuel de `lib/log.sh` et il ne change pas.

Sinon, `COLORTERM` valant `truecolor` ou `24bit` : `\033[38;2;R;G;Bm`, avec les
hex exacts de `tokens.css`. À défaut, repli `\033[38;5;Nm` (§ 3.4).

### 3.3 Mode clair / mode sombre

Dans l'ordre :

1. `NIVUUS_CHARTE_MODE` valant `dark` ou `light` tranche.
2. Sinon `COLORFGBG` : le champ après le dernier `;` est l'indice de fond ;
   0–6 et 8 valent sombre, 7 et 9–15 valent clair.
3. Sinon, sombre — c'est le contexte du produit au § 2.2 de la charte.

### 3.4 Valeurs

Mode sombre :

| Rôle | Hex | Repli 256 | Contraste sur `#0A0A0A` |
|---|---|---|---|
| `--danger` | `#FF7A85` | 210 | 8,55:1 |
| `--warn` | `#F2B33D` | 215 | 10,89:1 |
| `--ok` | `#4ED39A` | 78 | 10,90:1 |
| `--busy` | `#7AB6FF` | 111 | 9,06:1 |

Mode clair :

| Rôle | Hex | Repli 256 | Contraste sur `#FFFFFF` |
|---|---|---|---|
| `--danger` | `#C11F2E` | 124 | 7,44:1 |
| `--warn` | `#8A5A00` | 94 | 5,73:1 |
| `--ok` | `#1B6B4A` | 22 | 8,07:1 |
| `--busy` | `#1A5FB4` | 25 | 6,45:1 |

Les replis sont les entrées de la palette xterm-256 les plus proches de la
valeur de charte parmi celles qui tiennent le seuil de 4,5:1 du § 2.3, les
entrées achromatiques étant exclues.

Une exception, décidée et non subie : en mode clair, le voisin numériquement le
plus proche de `--ok` est l'indice 23, `(0,95,95)`. C'est un teal, qui se
confondrait avec `--busy` (indice 25) et ne se lirait plus comme un succès.
L'indice 22, `(0,95,0)`, est retenu à sa place. L'argument est celui que le
§ 2.4 de la charte emploie pour l'ambre de `--warn` : la convention que le grand
public lit instantanément prime sur la fidélité chromatique.

`NIVUUS_C_TEXT` vaut la chaîne vide et `NIVUUS_C_STRONG` vaut `\033[1m` — voir
§ 6.1 et § 6.2.

## 4. Surfaces réécrites

### 4.1 `lib/log.sh`

Source `charte.sh` et perd ses six définitions ANSI, `_C_DIM` compris. Aucune
signature ne change.

| Helper | Glyphe | Rôle |
|---|---|---|
| `log_info` | `·` | `busy` |
| `log_ok` | `✓` | `ok` |
| `log_warn` | `!` | `warn` |
| `log_error` | `✗` | `danger` |
| `log_dry` | `[dry-run]` | `STRONG`, sans couleur |

La règle « jamais la couleur seule » du § 2.4 est satisfaite sans travail
supplémentaire : chaque helper porte un glyphe distinguable en noir et blanc et
le message qui nomme l'état.

`lib/steps.sh`, `lib/manifest.sh`, `lib/zshrc.sh` et `bin/nivuus` passent tous
par ces helpers et ne changent pas. Point vérifié et clos : `lib/steps.sh`
n'appelle aucun `log_*` et n'a donc aucun libellé d'étape à passer en `STRONG`
— la hiérarchie du § 6.2 ne s'y applique pas faute de matière.

### 4.2 `bin/healthcheck`, `bin/benchmark`, `bin/test`

Suppriment leurs définitions locales et sourcent `charte.sh`. Substitution
mécanique sur 62 sites d'appel :

    RED → NIVUUS_C_DANGER    GREEN → NIVUUS_C_OK
    YELLOW → NIVUUS_C_WARN   BLUE  → NIVUUS_C_BUSY
    NC → NIVUUS_C_OFF

### 4.3 `config/22-ai-errors.zsh` et `config/24-ai-command-not-found.zsh`

Deux changements de fond.

**Les gris disparaissent.** Les libellés en `%F{244}` et `%F{246}`
(`Command:`, `Exit Code:`, `Package:`, `Install:`) passent en `STRONG` — gras,
sans couleur — et leurs valeurs en texte nu.

**La couleur décorative tombe.** Le cadre `╭─ … ╰─` de l'assistant de paquets
est aujourd'hui entièrement bleu sans signaler aucun état : il passe en texte
nu. Le nom de commande en vert et le nom de paquet en jaune de même — un paquet
n'est ni un succès ni un avertissement. Ne restent colorés que les événements :

| Sortie | Rôle |
|---|---|
| `🤖 Analyzing with AI…`, `⚙ Installing …`, `▶ Running: …` | `busy` |
| `✓ Successfully installed …` | `ok` |
| `✗ AI Error Analysis`, `✗ Installation failed …`, échec d'analyse | `danger` |
| Invite `Install package now …? [y/N]` | `STRONG`, sans couleur |
| Tout le reste | texte nu |

Dans ce module, l'invariant glyphe ↔ rôle est : `✓` = `ok`, `⚠` = `warn`,
`✗` = `danger`. Un même glyphe ne change jamais de rôle d'un message à
l'autre dans `config/22-ai-errors.zsh`/`config/24-ai-command-not-found.zsh` —
c'est ce qui permet de lire une sortie en noir et blanc. `AI Error Analysis`
porte donc `✗`, pas `⚠` : le glyphe `⚠` de ce module est déjà pris par
l'avertissement « No error to explain » (`explain-error`), et `danger` exige
`✗`. (`lib/log.sh`, § 4.1, a sa propre table de glyphes — `!` y porte `warn` —
et n'est pas concerné par cet invariant.)

**Conversion technique.** Ces modules emploient `print -P "%F{110}…"`.
`charte.sh` fournit des séquences brutes et non des codes `%F` : les appels
concernés passent à `print -r --`. Aucun n'exploite d'autre expansion de
`print -P` que `%F`/`%f`, la conversion est donc sûre. Les appels doivent être
relus un par un, la substitution n'étant pas mécanique ici.

**Chargement paresseux.** Le `source` de `charte.sh` se fait dans la fonction
d'affichage (`_ai_charte_load`), et non au chargement du module : la cible de
démarrage <300 ms de `.zshrc` ne doit rien payer pour une sortie qui n'apparaît
qu'en cas d'erreur. `_ai_charte_load` resource `charte.sh` à chaque appel, sans
garde sur `NIVUUS_CHARTE_LOADED` : la décision `[ -t 1 ]` de `charte.sh` porte
sur le descripteur de sortie du moment, qui peut changer d'un appel à l'autre
(pipe, redirection) ; la geler à la première évaluation figerait la session
entière sur cette première décision.

### 4.4 Dégradation

Chaque `source` est gardé par `[ -f "$charte" ]` et chaque usage s'écrit
`${NIVUUS_C_OK:-}`. Une installation partielle où `lib/charte.sh` manquerait
sort en noir et blanc, jamais en erreur.

## 5. Tests

### 5.1 `tests/unit/test_lib_charte.bats` (nouveau)

- `NO_COLOR=1` : les sept variables sont vides.
- Sortie redirigée (non-TTY) : les sept variables sont vides.
- `COLORTERM=truecolor` : les sémantiques contiennent `38;2;`.
- `COLORTERM` absent : elles contiennent `38;5;`.
- `NIVUUS_CHARTE_MODE=light` : `NIVUUS_C_DANGER` porte la valeur claire.
- `COLORFGBG=15;0` : mode sombre retenu.
- Sans aucun indice : mode sombre retenu.

### 5.2 `tests/unit/test_charte_conformity.bats` (nouveau)

Lit `assets/tokens.css` du dépôt design — chemin par défaut `../../design` depuis la racine du dépôt,
réglable par `NIVUUS_DESIGN_DIR` — en extrait les blocs `:root` et
`[data-mode="dark"]`, et compare les quatre sémantiques × deux modes aux hex
de `lib/charte.sh`. Si le dépôt est absent, le test est `skip` : le shell
reste installable et testable seul.

C'est le garde-fou qui remplace un générateur : la divergence n'est pas
empêchée, elle est détectée.

### 5.3 Test anti-gris (nouveau)

Sur les fichiers du § 2.1 uniquement, échoue à la présence de `\033[2m`, de
`%F{8}`, ou d'un code ANSI-256 achromatique (232–255).

C'est le § 2.2 de la charte rendu exécutable. Sans lui, un gris revient au
premier correctif pressé.

### 5.4 Régression

`tests/unit/test_lib_log.bats`, `tests/e2e/test_healthcheck.bats`,
`tests/e2e/test_benchmark.bats` et `tests/e2e/test_install_sh_compat.bats`
couvrent déjà ces surfaces et doivent passer sans modification.
`tests/performance/test_startup.bats` garde la cible <300 ms.

## 6. Les deux dérogations

Elles sont écrites ici pour être remontées à `docs/charte.md`, pas dissimulées.
Toutes deux tiennent au même fait : un terminal n'est pas une page.

### 6.1 `--text` n'émet aucune séquence

La charte garantit ses ratios *contre `--surface`*. Dans un terminal,
`--surface` ne nous appartient pas. Écrire `#FFFFFF` sur le fond blanc de
quelqu'un produirait exactement l'illisibilité que le § 2.3 protège.

`NIVUUS_C_TEXT` est donc vide et laisse la couleur d'avant-plan du terminal,
que son propriétaire a réglée contre son propre fond. Le terminal fournit déjà
la paire achromatique de la charte ; nous n'imposons que les quatre
sémantiques, et le choix de paire du § 3.3 existe pour qu'elles y tiennent
leur seuil dans les deux cas.

### 6.2 L'épaisseur remplace la taille

Le § 2.2 de la charte remplace les gris par « l'épaisseur, la taille,
l'espacement et le mouvement ». Un terminal n'a qu'un seul corps de texte : la
taille n'y existe pas.

Des trois leviers restants, l'épaisseur est celui que la charte nomme et qui
existe réellement. Le primaire passe donc en gras (`\033[1m`) et le secondaire
reste en texte normal, **de la même couleur**. La hiérarchie ne passe jamais
par une atténuation : `dim` est précisément le « plus pâle » que la charte
interdit, et son rendu varie trop d'un terminal à l'autre pour porter quoi que
ce soit.

## 7. Documentation

`doc/CHARTE.md` (nouveau), court : le périmètre du § 2 et son exclusion
motivée, les sept variables, `NIVUUS_CHARTE_MODE`, les deux dérogations du § 6,
et la procédure quand une couleur bouge dans `tokens.css` (§ 12.3 de la
charte : relancer `tools/check_contrast.py` côté design, reporter dans
`lib/charte.sh`, relancer `test_charte_conformity.bats`, recalculer le repli
256 si la teinte a bougé).

Mention dans `doc/README.md` et dans le bloc de variables d'environnement de
`.zshrc`.
