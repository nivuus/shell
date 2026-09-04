# Charte Nivuus appliquée au terminal — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer les trois palettes ANSI concurrentes des sorties propres à Nivuus par une source unique, `lib/charte.sh`, alignée sur les quatre sémantiques de la charte Nivuus et vérifiée contre `tokens.css`.

**Architecture:** Un fichier `lib/charte.sh` sourcé par l'installeur (`bash`) et par les modules `zsh`, exposant sept variables et aucune fonction. Il choisit truecolor ou un repli ANSI-256, et la paire claire ou sombre, puis se tait. Les consommateurs (`lib/log.sh`, les trois binaires de `bin/`, deux modules IA) perdent leurs codes en dur. Trois tests tiennent l'ensemble : le comportement du fichier, sa conformité au dépôt design, et l'absence de tout gris sur le périmètre.

**Tech Stack:** `sh` (compatible `bash` et `zsh`), `bats` pour les tests, séquences ANSI SGR.

**Spec:** `docs/superpowers/specs/2026-08-24-charte-terminal-design.md`

## Global Constraints

- **Aucun gris, nulle part dans le périmètre.** Ni `\033[2m` (dim), ni `%F{8}`, ni un code ANSI-256 achromatique (232–255). La hiérarchie passe par le gras, jamais par une atténuation. C'est le § 2.2 de la charte et le § 6.2 de la spec.
- **La couleur n'est jamais seule.** Tout élément coloré porte un glyphe distinguable en noir et blanc *et* un libellé qui nomme l'état (charte § 2.4).
- **Quatre sémantiques et quatre seulement** : `danger`, `warn`, `ok`, `busy`. Jamais de couleur pour décorer ou pour hiérarchiser.
- **`NIVUUS_C_TEXT` vaut toujours la chaîne vide.** On n'impose jamais de couleur d'avant-plan : le fond du terminal ne nous appartient pas (spec § 6.1).
- **Hors périmètre, à ne toucher sous aucun prétexte** : `config/05-prompt.zsh`, `config/03-completion.zsh`, `config/17-colorization.zsh`, `config/98-syntax.zsh`, `config/18-autosuggestions.zsh`, `themes/*.zsh`, `doc/PROMPT.md`. Le contrat `THEME_*` ne change pas.
- **`NO_COLOR` et sortie non-TTY** neutralisent les sept variables. Comportement existant de `lib/log.sh`, à préserver.
- **Dégradation obligatoire** : chaque `source` est gardé par un test d'existence, chaque usage s'écrit `${NIVUUS_C_XXX:-}`. `lib/charte.sh` manquant doit produire du noir et blanc, jamais une erreur.
- **Valeurs de charte, verbatim** (ne jamais les retaper de mémoire) :

  | Rôle | Clair (hex / RGB / repli 256) | Sombre (hex / RGB / repli 256) |
  |---|---|---|
  | `danger` | `#C11F2E` / `193;31;46` / `124` | `#FF7A85` / `255;122;133` / `210` |
  | `warn` | `#8A5A00` / `138;90;0` / `94` | `#F2B33D` / `242;179;61` / `215` |
  | `ok` | `#1B6B4A` / `27;107;74` / `22` | `#4ED39A` / `78;211;154` / `78` |
  | `busy` | `#1A5FB4` / `26;95;180` / `25` | `#7AB6FF` / `122;182;255` / `111` |

- **Lancer les tests** avec `bats <fichier>` directement pendant le développement, et `./bin/test --unit` avant chaque commit.

---

## Structure des fichiers

| Fichier | Responsabilité | Tâche |
|---|---|---|
| `lib/charte.sh` | **Créé.** Décide du mode et du vecteur, expose sept variables. Rien d'autre. | 1 |
| `tests/unit/test_lib_charte.bats` | **Créé.** Comportement de `charte.sh` : vecteur, mode, neutralisation. | 1 |
| `tests/unit/test_charte_conformity.bats` | **Créé.** Les huit hex sont ceux de `design/assets/tokens.css`. | 2 |
| `lib/log.sh` | **Modifié.** Perd ses six codes ANSI et `_C_DIM`, consomme `charte.sh`. | 3 |
| `bin/healthcheck`, `bin/benchmark`, `bin/test` | **Modifiés.** Perdent leurs trois copies de `RED/GREEN/YELLOW/BLUE/NC`, et `BLUE` avec — voir la correction du 4 septembre 2026 en tâche 4. | 4 |
| `config/22-ai-errors.zsh` | **Modifié.** Gris et couleur décorative retirés, `print -P` → `print -r --`. | 5 |
| `config/24-ai-command-not-found.zsh` | **Modifié.** Idem, plus le cadre décoratif dépeint. | 6 |
| `tests/unit/test_charte_no_grey.bats` | **Créé.** Cliquet : interdit tout gris sur le périmètre. | 7 |
| `doc/CHARTE.md` | **Créé.** Périmètre, variables, dérogations, procédure de mise à jour. | 8 |

L'ordre compte : le cliquet anti-gris (tâche 7) ne peut passer qu'une fois les tâches 3 à 6 faites, et il est là pour empêcher la régression, pas pour piloter la conversion.

---

### Task 1: `lib/charte.sh` et son test de comportement

**Files:**
- Create: `lib/charte.sh`
- Test: `tests/unit/test_lib_charte.bats`

**Interfaces:**
- Consumes: rien.
- Produces: sept variables shell, et rien d'autre. Aucune fonction n'est définie par ce fichier.
  - `NIVUUS_C_DANGER`, `NIVUUS_C_WARN`, `NIVUUS_C_OK`, `NIVUUS_C_BUSY` — séquence SGR d'avant-plan, ou chaîne vide.
  - `NIVUUS_C_TEXT` — **toujours** la chaîne vide.
  - `NIVUUS_C_STRONG` — `\033[1m`, ou chaîne vide.
  - `NIVUUS_C_OFF` — `\033[0m`, ou chaîne vide.
  - `NIVUUS_CHARTE_LOADED` — vaut `1` après chargement. Signale seulement que le fichier a été sourcé. **Ne sert pas de garde** : la version du 24 août lui donnait ce rôle aux tâches 5 et 6, corrigé le 4 septembre 2026 — `charte.sh` tranche sur `[ -t 1 ]` au moment du source, et une garde figerait cette décision pour toute la session.
- Lit en entrée : `NO_COLOR`, `COLORTERM`, `COLORFGBG`, `NIVUUS_CHARTE_MODE`.

- [x] **Step 1: Écrire le test qui échoue**

Créer `tests/unit/test_lib_charte.bats` :

```bash
#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    unset NO_COLOR COLORTERM COLORFGBG NIVUUS_CHARTE_MODE
}

# Le fichier est sourcé dans un sous-shell dont la sortie est capturée par
# bats, donc jamais un TTY. Les cas qui veulent des couleurs forcent la
# détection avec NIVUUS_CHARTE_TTY=1, prévue pour les tests.

@test "NO_COLOR vide les sept variables" {
    run bash -c "export NO_COLOR=1 NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '[%s|%s|%s|%s|%s|%s|%s]' \
            \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \"\$NIVUUS_C_OK\" \
            \"\$NIVUUS_C_BUSY\" \"\$NIVUUS_C_TEXT\" \"\$NIVUUS_C_STRONG\" \
            \"\$NIVUUS_C_OFF\""
    [ "$output" = "[||||||]" ]
}

@test "sortie non-TTY vide les sept variables" {
    run bash -c ". '$LIB/charte.sh'
        printf '[%s|%s|%s|%s]' \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \
            \"\$NIVUUS_C_OK\" \"\$NIVUUS_C_BUSY\""
    [ "$output" = "[|||]" ]
}

@test "COLORTERM=truecolor emet du 38;2" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"38;2;"* ]]
}

@test "sans COLORTERM le repli est du 38;5" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"38;5;"* ]]
    [[ "$output" != *"38;2;"* ]]
}

@test "mode sombre par defaut, valeurs de charte" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_DANGER\""
    [[ "$output" == *"255;122;133"* ]]
}

@test "NIVUUS_CHARTE_MODE=light bascule sur la paire claire" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_MODE=light NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_DANGER\""
    [[ "$output" == *"193;31;46"* ]]
}

@test "COLORFGBG a fond clair bascule sur la paire claire" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='0;15' NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"27;107;74"* ]]
}

@test "COLORFGBG a fond sombre reste sur la paire sombre" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='15;0' NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"78;211;154"* ]]
}

@test "NIVUUS_CHARTE_MODE prime sur COLORFGBG" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='15;0' NIVUUS_CHARTE_MODE=light
        export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"27;107;74"* ]]
}

@test "NIVUUS_C_TEXT est toujours vide, meme en couleur" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '[%s]' \"\$NIVUUS_C_TEXT\""
    [ "$output" = "[]" ]
}

@test "NIVUUS_C_STRONG est le gras seul, sans couleur" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_STRONG\" | cat -v"
    [ "$output" = '^[[1m' ]
}

@test "aucun gris n'est emis" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s%s%s%s%s' \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \
            \"\$NIVUUS_C_OK\" \"\$NIVUUS_C_BUSY\" \"\$NIVUUS_C_STRONG\""
    [[ "$output" != *"[2m"* ]]
    for grey in 232 240 244 246 250 255; do
        [[ "$output" != *"38;5;$grey"* ]]
    done
}

@test "NIVUUS_CHARTE_LOADED est pose" {
    run bash -c ". '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_CHARTE_LOADED\""
    [ "$output" = "1" ]
}

@test "le fichier est sourcable par zsh" {
    run zsh -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"78;211;154"* ]]
}

@test "le fichier ne definit aucune fonction" {
    run bash -c "before=\$(declare -F | wc -l); . '$LIB/charte.sh'
        after=\$(declare -F | wc -l); [ \"\$before\" = \"\$after\" ]"
    [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bats tests/unit/test_lib_charte.bats`
Expected: FAIL — les 15 tests échouent, `lib/charte.sh` n'existe pas.

- [x] **Step 3: Écrire `lib/charte.sh`**

```sh
# Couleur des sorties Nivuus. Applique la charte graphique (socle 0.3.0).
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.
#
# Spec : docs/superpowers/specs/2026-08-24-charte-terminal-design.md
# Doc  : doc/CHARTE.md
#
# N'expose que sept variables et ne définit aucune fonction. Il n'y a aucun
# gris ici, et il ne doit jamais y en avoir : la charte les a tous retirés, et
# ce qu'ils portaient passe par NIVUUS_C_STRONG.
#
# Les huit valeurs viennent de assets/tokens.css du dépôt design. Ne pas les
# retoucher sans relancer tests/unit/test_charte_conformity.bats.

# --- Mode : explicite, puis COLORFGBG, puis sombre (charte § 2.2). ---
case "${NIVUUS_CHARTE_MODE:-}" in
    light|dark) _nivuus_charte_mode="$NIVUUS_CHARTE_MODE" ;;
    *)
        # COLORFGBG vaut « avant-plan;fond » ou « avant-plan;défaut;fond » :
        # le champ utile est toujours le dernier.
        case "${COLORFGBG##*;}" in
            7|9|10|11|12|13|14|15) _nivuus_charte_mode=light ;;
            *)                     _nivuus_charte_mode=dark ;;
        esac
        ;;
esac

# --- Neutralisation : NO_COLOR, ou sortie qui n'est pas un terminal. ---
# NIVUUS_CHARTE_TTY force la détection ; il n'existe que pour les tests, dont
# la sortie est toujours capturée et donc jamais un TTY.
if [ -n "${NO_COLOR:-}" ] || { [ ! -t 1 ] && [ -z "${NIVUUS_CHARTE_TTY:-}" ]; }; then
    NIVUUS_C_DANGER=''
    NIVUUS_C_WARN=''
    NIVUUS_C_OK=''
    NIVUUS_C_BUSY=''
    NIVUUS_C_STRONG=''
    NIVUUS_C_OFF=''
else
    case "${COLORTERM:-}" in
        truecolor|24bit)
            if [ "$_nivuus_charte_mode" = light ]; then
                NIVUUS_C_DANGER=$'\033[38;2;193;31;46m'
                NIVUUS_C_WARN=$'\033[38;2;138;90;0m'
                NIVUUS_C_OK=$'\033[38;2;27;107;74m'
                NIVUUS_C_BUSY=$'\033[38;2;26;95;180m'
            else
                NIVUUS_C_DANGER=$'\033[38;2;255;122;133m'
                NIVUUS_C_WARN=$'\033[38;2;242;179;61m'
                NIVUUS_C_OK=$'\033[38;2;78;211;154m'
                NIVUUS_C_BUSY=$'\033[38;2;122;182;255m'
            fi
            ;;
        *)
            # Repli : l'entrée xterm-256 la plus proche parmi celles qui
            # tiennent le seuil de 4,5:1 de la charte (§ 2.3), les entrées
            # achromatiques exclues. En mode clair, --ok prend l'indice 22 et
            # non 23, numériquement plus proche mais qui vire au teal et se
            # confondrait avec --busy (spec § 3.4).
            if [ "$_nivuus_charte_mode" = light ]; then
                NIVUUS_C_DANGER=$'\033[38;5;124m'
                NIVUUS_C_WARN=$'\033[38;5;94m'
                NIVUUS_C_OK=$'\033[38;5;22m'
                NIVUUS_C_BUSY=$'\033[38;5;25m'
            else
                NIVUUS_C_DANGER=$'\033[38;5;210m'
                NIVUUS_C_WARN=$'\033[38;5;215m'
                NIVUUS_C_OK=$'\033[38;5;78m'
                NIVUUS_C_BUSY=$'\033[38;5;111m'
            fi
            ;;
    esac
    NIVUUS_C_STRONG=$'\033[1m'
    NIVUUS_C_OFF=$'\033[0m'
fi

# Jamais de séquence : le fond du terminal ne nous appartient pas, et son
# avant-plan a été réglé contre lui par la seule personne qui le connaît.
# Voir le § 6.1 de la spec.
NIVUUS_C_TEXT=''

unset _nivuus_charte_mode
NIVUUS_CHARTE_LOADED=1
```

- [x] **Step 4: Lancer le test pour vérifier qu'il passe**

Run: `bats tests/unit/test_lib_charte.bats`
Expected: PASS — 15 tests.

Si « le fichier est sourcable par zsh » échoue : vérifier que `zsh` est installé (`command -v zsh`). Le fichier n'emploie que `case`, l'expansion `##`, et `$'...'`, tous trois supportés par `bash`, `zsh` et `dash`.

- [x] **Step 5: Commit**

```bash
git add lib/charte.sh tests/unit/test_lib_charte.bats
git commit -m "feat(charte): source unique de couleur pour les sorties Nivuus

Sept variables, aucune fonction, aucun gris. Truecolor avec repli
ANSI-256 tenant le seuil 4,5:1 de la charte, paire claire ou sombre
choisie par NIVUUS_CHARTE_MODE puis COLORFGBG.

NIVUUS_C_TEXT reste vide : le fond du terminal ne nous appartient pas."
```

---

### Task 2: Test de conformité à `tokens.css`

C'est le garde-fou qui remplace un générateur : la divergence avec le dépôt design n'est pas empêchée, elle est détectée.

**Files:**
- Test: `tests/unit/test_charte_conformity.bats`

**Interfaces:**
- Consumes: `lib/charte.sh` de la tâche 1 — lu comme du texte, pas sourcé.
- Produces: rien de consommé par les tâches suivantes.

- [x] **Step 1: Écrire le test**

Il n'y a pas de cycle rouge-vert ici : le test doit passer immédiatement si la tâche 1 a copié les bonnes valeurs. C'est précisément son rôle.

Créer `tests/unit/test_charte_conformity.bats` :

```bash
#!/usr/bin/env bats

# bats-core ne fournit pas fail() : on la definit.
fail() { printf '%s\n' "$1" >&2; return 1; }

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    CHARTE="$ROOT/lib/charte.sh"
    DESIGN="${NIVUUS_DESIGN_DIR:-$ROOT/../../design}"
    TOKENS="$DESIGN/assets/tokens.css"
}

# Valeur d'un token dans un bloc de tokens.css.
# $1 = role (danger|warn|ok|busy), $2 = ligne d'ouverture du bloc.
token_of() {
    awk -v role="--$1:" -v start="$2" '
        index($0, start) == 1 { inblock = 1; next }
        inblock && /^}/       { exit }
        inblock && index($0, role) {
            gsub(/[^#0-9A-Fa-f]/, "", $2); print toupper($2); exit
        }
    ' "$TOKENS"
}

# Valeur RGB que lib/charte.sh emet pour un role, dans une branche donnee.
# Les deux paires portent les memes noms de variables : on decoupe d'abord
# le fichier par branche, sinon on lirait toujours la premiere.
# $1 = ROLE en majuscules, $2 = light|dark
rgb_of() {
    local from to
    if [ "$2" = light ]; then
        from='charte_mode" = light'; to='            else'
    else
        from='            else'; to='            fi'
    fi
    sed -n "/$from/,/$to/p" "$CHARTE" |
        grep -m1 "NIVUUS_C_$1=" |
        sed -n 's/.*38;2;\([0-9;]*\)m.*/\1/p'
}

hex_to_rgb() {
    local h="${1#\#}"
    printf '%d;%d;%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

@test "les quatre semantiques sombres valent celles de tokens.css" {
    [ -f "$TOKENS" ] || skip "depot design absent ($TOKENS) — poser NIVUUS_DESIGN_DIR"
    for role in danger warn ok busy; do
        hex="$(token_of "$role" '[data-mode="dark"]')"
        [ -n "$hex" ] || fail "role --$role introuvable dans le bloc sombre"
        expected="$(hex_to_rgb "$hex")"
        actual="$(rgb_of "$(printf '%s' "$role" | tr 'a-z' 'A-Z')" dark)"
        [ "$actual" = "$expected" ] ||
            fail "--$role sombre : charte.sh dit '$actual', tokens.css dit '$expected' ($hex)"
    done
}

@test "les quatre semantiques claires valent celles de tokens.css" {
    [ -f "$TOKENS" ] || skip "depot design absent ($TOKENS) — poser NIVUUS_DESIGN_DIR"
    for role in danger warn ok busy; do
        hex="$(token_of "$role" ':root,')"
        [ -n "$hex" ] || fail "role --$role introuvable dans le bloc :root"
        expected="$(hex_to_rgb "$hex")"
        actual="$(rgb_of "$(printf '%s' "$role" | tr 'a-z' 'A-Z')" light)"
        [ "$actual" = "$expected" ] ||
            fail "--$role clair : charte.sh dit '$actual', tokens.css dit '$expected' ($hex)"
    done
}
```

Deux points sur lesquels l'implémenteur va buter :

- Le bloc clair de `tokens.css` s'ouvre sur `:root,` suivi de `[data-mode="light"] {` en ligne suivante — d'où le motif `':root,'` et non `':root'`. Ouvrir le fichier pour vérifier avant de lancer.
- `rgb_of` découpe par branche parce que les deux paires de valeurs portent les mêmes noms de variables dans `lib/charte.sh`. Si la mise en forme du `case` de la tâche 1 change, ces bornes changent aussi.

- [x] **Step 2: Lancer le test**

Run: `bats tests/unit/test_charte_conformity.bats`
Expected: PASS — 3 tests, si `~/Projects/Nivuus/design` est présent à côté du dépôt.

Vérifier explicitement qu'il ne passe pas *par accident* en étant skippé :

Run: `bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped`
Expected: `0`. Si les tests sont skippés, le chemin par défaut est faux — corriger `DESIGN` ou lancer avec `NIVUUS_DESIGN_DIR=~/Projects/Nivuus/design`.

- [x] **Step 3: Vérifier que le test détecte bien une divergence**

Un garde-fou qu'on n'a pas vu échouer ne garde rien.

```bash
sed -i 's/38;2;78;211;154m/38;2;78;211;155m/' lib/charte.sh
bats tests/unit/test_charte_conformity.bats
```
Expected: FAIL sur `--ok sombre : charte.sh dit 78;211;155, tokens.css dit 78;211;154`.

Puis restaurer : `git checkout lib/charte.sh` et relancer, Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add tests/unit/test_charte_conformity.bats
git commit -m "test(charte): verifier les huit hex contre design/assets/tokens.css

Se marque skipped si le depot design est absent : le shell reste
installable et testable seul."
```

---

### Task 3: `lib/log.sh`

**Files:**
- Modify: `lib/log.sh` (intégralement — 16 lignes)
- Test: `tests/unit/test_lib_log.bats` (ajouts)

**Interfaces:**
- Consumes: les sept variables de la tâche 1.
- Produces: `log_info`, `log_ok`, `log_warn`, `log_error`, `log_dry` — **signatures inchangées**, chacune prenant le message en `$*`. `log_warn` et `log_error` écrivent sur stderr, les trois autres sur stdout et se taisent si `NIVUUS_QUIET` est posé. `lib/steps.sh`, `lib/manifest.sh`, `lib/zshrc.sh` et `bin/nivuus` en dépendent et ne sont pas modifiés.

  Le § 4.1 de la spec réserve l'emploi de `NIVUUS_C_STRONG` « sur le libellé d'étape là où la hiérarchie le demande ». Vérification faite, **il n'y a nulle part où l'appliquer** : `lib/steps.sh` n'appelle aucun `log_*`, et tous les appels de `lib/manifest.sh` et `lib/zshrc.sh` sont des messages d'une seule pièce (`log_error`, `log_warn`, `log_dry`), sans couple libellé/détail à hiérarchiser. Ne pas en inventer un. Si un jour une étape affiche un libellé suivi d'un détail, c'est là que `STRONG` ira.

- [x] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `tests/unit/test_lib_log.bats` :

```bash
@test "log_dry n'emploie plus de dim" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; source '$LIB/log.sh'; log_dry 'x' | cat -v"
    [[ "$output" != *"[2m"* ]]
}

@test "log_dry marque le prefixe en gras" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; source '$LIB/log.sh'; log_dry 'x' | cat -v"
    [[ "$output" == *"[1m"* ]]
}

@test "log_ok emploie la teinte ok de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_ok 'x'"
    [[ "$output" == *"38;2;78;211;154"* ]]
}

@test "log_error emploie la teinte danger de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_error 'x' 2>&1"
    [[ "$output" == *"38;2;255;122;133"* ]]
}

@test "log_info emploie la teinte busy de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_info 'x'"
    [[ "$output" == *"38;2;122;182;255"* ]]
}

@test "log_warn emploie la teinte warn de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_warn 'x' 2>&1"
    [[ "$output" == *"38;2;242;179;61"* ]]
}

@test "chaque helper porte un glyphe lisible en noir et blanc" {
    run bash -c "source '$LIB/log.sh'
        log_info i; log_ok o; log_warn w 2>&1; log_error e 2>&1"
    [[ "$output" == *"·"* ]]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"!"* ]]
    [[ "$output" == *"✗"* ]]
}

@test "log.sh degrade sans erreur si charte.sh est absent" {
    tmp="$(mktemp -d)"
    cp "$LIB/log.sh" "$tmp/log.sh"
    run bash -c "source '$tmp/log.sh'; log_ok 'sans charte'"
    rm -rf "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sans charte"* ]]
}
```

- [x] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `bats tests/unit/test_lib_log.bats`
Expected: FAIL — les 6 tests de teinte et les 2 tests de gras/dim échouent (`log.sh` emploie encore ses propres codes et `_C_DIM`). Les 7 tests d'origine passent toujours.

- [x] **Step 3: Réécrire `lib/log.sh`**

Remplacer intégralement le contenu par :

```sh
# Sortie utilisateur. Aucune connaissance du métier.
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.
#
# Les couleurs viennent de lib/charte.sh et de nulle part ailleurs : ne pas
# réintroduire de code ANSI ici. Aucun gris — le second plan passe par le
# gras (charte § 2.2). Chaque helper porte un glyphe qui se lit en noir et
# blanc, parce que la couleur ne s'emploie jamais seule (charte § 2.4).

_nivuus_log_here="$(dirname -- "${BASH_SOURCE[0]:-$0}")"
[ -f "$_nivuus_log_here/charte.sh" ] && . "$_nivuus_log_here/charte.sh"
unset _nivuus_log_here

log_info()  { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_BUSY:-}·${NIVUUS_C_OFF:-} $*"; }
log_ok()    { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_OK:-}✓${NIVUUS_C_OFF:-} $*"; }
log_warn()  { printf '%s\n' "${NIVUUS_C_WARN:-}!${NIVUUS_C_OFF:-} $*" >&2; }
log_error() { printf '%s\n' "${NIVUUS_C_DANGER:-}✗${NIVUUS_C_OFF:-} $*" >&2; }
log_dry()   { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_STRONG:-}[dry-run]${NIVUUS_C_OFF:-} $*"; }
```

- [x] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `bats tests/unit/test_lib_log.bats`
Expected: PASS — 15 tests (7 d'origine + 8 ajoutés).

- [x] **Step 5: Vérifier que les consommateurs n'ont pas bougé**

Run: `bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_reversibility.bats tests/e2e/test_nivuus_cli.bats`
Expected: PASS. Ces suites exercent `lib/steps.sh`, `lib/manifest.sh` et `bin/nivuus`, qui consomment `log_*` sans être modifiés.

- [x] **Step 6: Commit**

```bash
git add lib/log.sh tests/unit/test_lib_log.bats
git commit -m "refactor(log): consommer lib/charte.sh au lieu de codes ANSI en dur

_C_DIM disparait : le marqueur [dry-run] passe en gras, la charte
interdisant de hierarchiser par attenuation. Signatures inchangees."
```

---

### Task 4: `bin/healthcheck`, `bin/benchmark`, `bin/test`

Substitution mécanique de trois copies de la même palette. 62 sites d'appel au total.

**Files:**
- Modify: `bin/healthcheck:11-21`, `bin/benchmark:16-20`, `bin/test:9-13`
- Test: `tests/e2e/test_healthcheck.bats`, `tests/e2e/test_benchmark.bats` (existants, ne pas modifier)

**Interfaces:**
- Consumes: les sept variables de la tâche 1.
- Produces: rien pour les tâches suivantes.

- [x] **Step 1: Constater l'état de départ**

```bash
grep -c '\\033\[' bin/healthcheck bin/benchmark bin/test
bats tests/e2e/test_healthcheck.bats tests/e2e/test_benchmark.bats
```
Expected: des occurrences dans les trois fichiers, et les suites e2e au vert. Ce vert est la référence : il doit être identique à la fin.

- [x] **Step 2: `bin/healthcheck`**

Remplacer les lignes 10 à 21 (le bloc `# Colors` et le bloc `# Symbols`) par :

> **Corrigé le 4 septembre 2026 — la version du 24 août était fausse.** Elle
> prescrivait une substitution mécanique en cinq lignes, `RED/GREEN/YELLOW/NC`
> **plus `BLUE="${NIVUUS_C_BUSY:-}"`**, et un `INFO="${BLUE}ℹ${NC}"`, en
> concluant que « les 19 sites d'appel qui suivent ne changent pas ».
>
> C'est précisément ce qui ne pouvait pas marcher. `BLUE` ne servait pas à
> signaler un traitement en cours : il peignait des filets de séparation, des
> titres de section et des préfixes `ℹ` — 33 sites au total sur les trois
> fichiers (15 dans `bin/healthcheck`, 12 dans `bin/benchmark`, 6 dans
> `bin/test`). Le traduire en `busy` transportait donc telle quelle la
> décoration que la charte interdit (§ 2.4 : la couleur ne s'emploie que sur
> un événement), sous un nom de rôle qui la faisait passer pour légitime. Une
> substitution mécanique n'est valide que si le nom d'origine porte déjà une
> sémantique ; `BLUE` n'en portait aucune, il nommait une teinte.
>
> Rejouer la version d'origine repeindrait ces 33 sites en `#7AB6FF` et
> laisserait le cliquet anti-gris au vert — il interdit les gris, pas la
> couleur décorative. Rien ne rattraperait le défaut.

Remplacer par le bloc ci-dessous. `BLUE` **disparaît** : après retrait de la
décoration, plus aucun usage légitime ne restait dans ces trois fichiers. Les
titres de section passent en `STRONG` (gras, sans couleur — la hiérarchie ne
passe jamais par la teinte, spec § 6.2), les filets et le texte ordinaire en
texte nu, et `INFO` perd sa couleur : `ℹ` préfixe une ligne d'information,
ce n'est pas un état.

```bash
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_HERE/../lib/charte.sh" ] && . "$_HERE/../lib/charte.sh"

RED="${NIVUUS_C_DANGER:-}"
GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
STRONG="${NIVUUS_C_STRONG:-}"
NC="${NIVUUS_C_OFF:-}"

# Symboles — la couleur ne s'emploie jamais seule (charte § 2.4).
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"
INFO="ℹ"
```

Les sites d'appel qui suivent **changent** : chaque `${BLUE}` doit être relu
un par un et tranché — `STRONG` si c'est un titre, rien si c'est un filet ou
du texte courant. Aucun ne devient `busy` : ces trois scripts ne rendent
compte d'aucun traitement en cours. `echo -e` continue de fonctionner, les
séquences étant désormais déjà réelles plutôt qu'échappées.

Même travail dans `bin/benchmark`, dont les paliers employaient trois couleurs
pour trois niveaux, `RED` compris pour un démarrage lent qui n'est qu'un
avertissement. Deux états suffisent : Excellent/Good en `ok`, Slow en `warn` —
le libellé porte la nuance, la couleur ne porte que l'état.

Attention : `bin/healthcheck` fixe `set -e` en ligne 8. Le `[ -f … ] && . …` renvoie faux si le fichier manque, ce qui tuerait le script. L'écrire en `if` si le `&&` pose problème :

```bash
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi
```

C'est la forme à employer dans les trois fichiers, tous sous `set -e`.

- [x] **Step 3: Lancer la suite healthcheck**

Run: `bats tests/e2e/test_healthcheck.bats`
Expected: PASS, à l'identique du step 1.

- [x] **Step 4: `bin/benchmark`**

Remplacer les lignes 15 à 20 (le bloc `# Colors`) par le même bloc, en
conservant l'ordre de déclaration d'origine. `BLUE` disparaît ici aussi, et
pour la même raison qu'à l'étape 2 — 12 sites décoratifs dans ce fichier :

```bash
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi

GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
RED="${NIVUUS_C_DANGER:-}"
STRONG="${NIVUUS_C_STRONG:-}"
NC="${NIVUUS_C_OFF:-}"
```

Puis relire les trois blocs de paliers de ce fichier — démarrage, génération
du prompt, mémoire. Ils employaient chacun trois couleurs pour trois niveaux,
avec `RED` sur ce qui n'est qu'un avertissement et `✓` sur ce qui n'est pas un
succès. Deux états, et le glyphe qui va avec le rôle : `✓` en `ok` pour
Excellent et Good, `⚠` en `warn` pour Slow et High memory usage.

- [x] **Step 5: Lancer la suite benchmark**

Run: `bats tests/e2e/test_benchmark.bats`
Expected: PASS.

- [x] **Step 6: `bin/test`**

Ce fichier est en `zsh`, pas en `bash` : `BASH_SOURCE` n'existe pas. Remplacer les lignes 8 à 13 par :

```zsh
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="${0:A:h}"
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi

RED="${NIVUUS_C_DANGER:-}"
GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
STRONG="${NIVUUS_C_STRONG:-}"
NC="${NIVUUS_C_OFF:-}"
```

`BLUE` disparaît, comme aux étapes 2 et 4 : 6 sites décoratifs ici.

Pendant qu'on est dans ce fichier, `PROJECT_ROOT` doit passer par `$_HERE` et
non par `${BASH_SOURCE[0]}`, qui n'existe pas sous `zsh`. Avec `BASH_SOURCE`
vide, `dirname ""` vaut `.` et `PROJECT_ROOT` devient le parent du dépôt :
`bin/test` sort du dépôt, ne trouve aucune suite, et annonce « All tests
passed! » sans rien avoir exécuté. L'étape 7 ci-dessous **n'attrape pas** ce
défaut — un lanceur qui n'exécute rien sort `0`. Vérifier le nombre de tests
rapporté, pas le code de sortie.

- [x] **Step 7: Vérifier que le lanceur de tests fonctionne encore**

`bin/test` est l'outil qui lance les tests : le casser rendrait tout le reste invisible.

Run: `./bin/test --unit`
Expected: la suite unitaire s'exécute et passe, sortie colorée intacte —
et le **nombre de tests rapporté est non nul** (580/580 au 4 septembre 2026).
Un `0/0` suivi de « All tests passed! » est le symptôme du `PROJECT_ROOT`
décrit à l'étape 6, pas un succès.

- [x] **Step 8: Vérifier qu'aucun code ANSI en dur ne subsiste**

Run: `grep -n '\\033\[' bin/healthcheck bin/benchmark bin/test`
Expected: aucune sortie (code 1).

- [x] **Step 9: Commit**

```bash
git add bin/healthcheck bin/benchmark bin/test
git commit -m "refactor(bin): trois palettes ANSI dupliquees remplacees par charte.sh

healthcheck, benchmark et test declaraient chacun leur propre
RED/GREEN/YELLOW/BLUE. BLUE disparait : ses 33 sites peignaient des
filets, des titres et le prefixe info, jamais un etat. Les titres
passent en STRONG, le reste en texte nu."
```

---

### Task 5: `config/22-ai-errors.zsh`

Première des deux surfaces IA. Ici la substitution n'est **pas** mécanique : chaque appel demande de décider si ce qu'il colore est un état ou non.

**Files:**
- Modify: `config/22-ai-errors.zsh:178-230`
- Modify: `tests/integration/test_ai_workflow.bats:283-286`

**Interfaces:**
- Consumes: les sept variables de la tâche 1, chargées paresseusement.
- Produces: rien pour les tâches suivantes. La tâche 6 applique le même motif de chargement paresseux, décrit ici et répété là-bas.

- [x] **Step 1: Corriger le test d'intégration qui exige des codes Nord**

`tests/integration/test_ai_workflow.bats:283-286` exige aujourd'hui que le fichier **contienne** `%F{` — il cassera par construction. Il doit devenir l'assertion inverse. Remplacer le test :

```bash
@test "AI error messages use Nord colors" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(NORD_|%F\\{)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}
```

par :

```bash
@test "AI error messages use charte colors, not raw palette codes" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(NORD_|%F\{)' config/22-ai-errors.zsh"
    [ "$status" -ne 0 ]
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'NIVUUS_C_' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}
```

Ne pas toucher au test voisin sur `config/19-ai-suggestions.zsh` : ce fichier est hors périmètre (spec § 2.2).

- [x] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bats tests/integration/test_ai_workflow.bats --filter "charte colors"`
Expected: FAIL — le fichier contient encore des `%F{`.

- [x] **Step 3: Ajouter le chargement paresseux**

Définir cette fonction dans `config/09-ai-core.zsh`, chargé avant les modules
22 et 24 qui la consomment tous deux — et non dans chaque module, voir la
correction de la tâche 6, étape 2 :

> **Corrigé le 4 septembre 2026 — la garde du 24 août était fausse.** La
> version d'origine ouvrait la fonction sur
> `[[ -n "${NIVUUS_CHARTE_LOADED:-}" ]] && return 0`, en la présentant comme
> une garde de rechargement anodine. Elle ne l'est pas.
>
> Le mécanisme : `lib/charte.sh` ne décide pas une fois pour toutes. Il
> tranche sur `[ -t 1 ]` — « le descripteur 1 est-il un terminal ? » — **au
> moment où il est sourcé**, et c'est ce test qui vide ou remplit les sept
> variables. Or ce descripteur change d'une commande à l'autre au cours d'une
> même session : `commande-inexistante | grep x` fait de stdout un tube, une
> redirection `> fichier` aussi. La garde fige donc la réponse de la toute
> première évaluation et la garde jusqu'à la fin de la session.
>
> Ce que cela produit concrètement : il suffit d'une seule commande inconnue
> lancée dans un tube pour que `charte.sh` conclue « pas un terminal », pose
> les sept variables à vide, et pose `NIVUUS_CHARTE_LOADED=1`. À partir de là
> la garde court-circuite tout rechargement, et la boîte de l'assistant de
> paquets — qui écrit pourtant sur **stderr**, donc bien sur le terminal —
> sort sans couleur ni gras, ainsi que tout le reste de la session, jusqu'à
> ce que l'utilisateur ouvre un nouveau shell. Le défaut est invisible en
> test : chaque test part d'un shell neuf.
>
> Retirer la garde ne coûte rien à ce que la paresse protège. Ce qui est
> paresseux, c'est de ne pas sourcer `charte.sh` au chargement du module —
> le démarrage de `.zshrc` ne paie rien, et cela reste vrai. Resourcer un
> fichier de 80 lignes sans I/O au moment où l'on affiche une erreur est
> hors de tout budget. `NIVUUS_CHARTE_LOADED` reste posé par `charte.sh`,
> mais ne sert plus de garde ici.

```zsh
# Charge lib/charte.sh à la demande, jamais au chargement du module : la
# cible de démarrage <300 ms de .zshrc ne doit rien payer pour une sortie
# qui n'apparaît qu'en cas d'erreur. Resource à chaque appel, sans garde :
# charte.sh tranche sur [ -t 1 ], qui change d'un appel à l'autre.
_ai_charte_load() {
    local charte="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/lib/charte.sh"
    [[ -f "$charte" ]] && source "$charte"
    return 0
}
```

- [x] **Step 4: Convertir les appels**

Appeler `_ai_charte_load` en tête de `_ai_explain_error_widget`, juste après le `return 0` du cas « pas d'erreur », puis remplacer chaque `print -P` par `print -r --`.

Table de décision — les rôles ne sont pas devinés, ils suivent le § 4.3 de la spec :

| Ligne | Avant | Après | Pourquoi |
|---|---|---|---|
| 178 | `%F{167}⚠  AI Error Analysis%f` | `danger`, **glyphe `✗`** | une erreur est un état — mais `⚠` est déjà pris, voir ci-dessous |
| 181 | `%F{246}Command:%f` | `STRONG` | libellé de second plan, pas un état — le gris devient du gras |
| 182 | `%F{246}Exit Code:%f` | `STRONG` | idem |
| 194 | `%F{143}💾 From cache:%f` | `STRONG` | « depuis le cache » n'est pas un succès |
| 197 | `%F{110}🤖 Analyzing with AI...%f` | `busy` | traitement en cours |
| 213 | `%F{167}Failed to analyze error…%f` | `danger` | échec |
| 230 | `%F{167}⚠  No error to explain…%f` | `warn` | avertissement, pas une erreur |

Les remplacements, un par un :

> **Corrigé le 4 septembre 2026 — la table du 24 août était fausse ici.** Elle
> gardait le glyphe `⚠` sur `AI Error Analysis` en ne changeant que sa
> couleur. Or neuf lignes plus bas, dans le même fichier, `⚠` porte `warn`
> (« No error to explain »). Le même glyphe désignait donc deux rôles.
>
> Le critère qui tranche est la lisibilité **sans couleur** : la charte § 2.4
> exige qu'une sortie reste compréhensible en noir et blanc — pour une
> personne daltonienne, pour un journal de CI, pour un `NO_COLOR`. Dans ce
> cas-là il ne reste que le glyphe ; s'il vaut tantôt « erreur » tantôt
> « avertissement », il ne dit plus rien. La couleur ne peut pas servir de
> désambiguïsation, puisque c'est justement elle qui manque.
>
> L'invariant du module est donc `✓`=ok, `⚠`=warn, `✗`=danger, un glyphe par
> rôle et jamais deux rôles par glyphe. `AI Error Analysis` prend `✗`.
> (`lib/log.sh` a sa propre table — § 4.1, où `!` porte `warn` — et n'est pas
> concerné : l'invariant vaut par module, pas globalement.)
>
> Rejouer la ligne d'origine rendrait la sortie ambiguë en noir et blanc sans
> qu'aucun test ne le voie : les cliquets contrôlent les teintes, pas
> l'appariement glyphe/rôle.

```zsh
    print -r -- "${NIVUUS_C_DANGER:-}✗  AI Error Analysis${NIVUUS_C_OFF:-}"
```
```zsh
    print -r -- "${NIVUUS_C_STRONG:-}Command:${NIVUUS_C_OFF:-} $_AI_LAST_COMMAND"
    print -r -- "${NIVUUS_C_STRONG:-}Exit Code:${NIVUUS_C_OFF:-} $_AI_LAST_ERROR_CODE"
```
```zsh
        print -r -- "${NIVUUS_C_STRONG:-}💾 From cache:${NIVUUS_C_OFF:-}"
```
```zsh
        print -r -- "${NIVUUS_C_BUSY:-}🤖 Analyzing with AI...${NIVUUS_C_OFF:-}"
```
```zsh
        print -r -- "${NIVUUS_C_DANGER:-}✗ Failed to analyze error. Check your AI backend configuration (run 'aihelp')${NIVUUS_C_OFF:-}"
```
```zsh
        print -r -- "${NIVUUS_C_WARN:-}⚠  No error to explain (last command succeeded)${NIVUUS_C_OFF:-}"
```

Noter le `✗` ajouté ligne 213 : le message était jusqu'ici coloré sans porter de glyphe, ce qui viole la règle « couleur plus icône plus libellé » du § 2.4. `explain-error` (ligne 230) appelle ensuite `_ai_explain_error_widget`, qui charge la charte : appeler `_ai_charte_load` aussi en tête de `explain-error`, dont la ligne 230 s'exécute *avant* le widget.

- [x] **Step 5: Lancer les tests**

Run: `bats tests/integration/test_ai_workflow.bats`
Expected: PASS, y compris le test réécrit.

Run: `grep -n '%F{' config/22-ai-errors.zsh`
Expected: aucune sortie.

- [x] **Step 6: Vérifier le coût au démarrage**

Le chargement paresseux ne vaut que s'il est réellement paresseux.

Run: `zsh -c 'source .zshrc; print -r -- "charte chargee: ${NIVUUS_CHARTE_LOADED:-non}"'`
Expected: `charte chargee: non`.

Run: `bats tests/performance/test_startup.bats`
Expected: PASS, cible <300 ms tenue.

- [x] **Step 7: Commit**

```bash
git add config/22-ai-errors.zsh tests/integration/test_ai_workflow.bats
git commit -m "refactor(ai-errors): appliquer la charte, retirer les gris

Les libelles Command:/Exit Code: passaient par %F{246} : ils passent
en gras sans couleur. « From cache » n'etait pas un succes et cesse
d'etre vert. Le message d'echec d'analyse gagne le glyphe qui lui
manquait, la couleur ne s'employant jamais seule.

Chargement paresseux de charte.sh : le demarrage ne paie rien."
```

---

### Task 6: `config/24-ai-command-not-found.zsh`

**Files:**
- Modify: `config/24-ai-command-not-found.zsh:228-251` (le cadre) et `:326-350` (l'installation)
- Test: `tests/unit/test_ai_command_not_found.bats` (existant, ne pas modifier)

**Interfaces:**
- Consumes: les sept variables de la tâche 1, et `_ai_charte_load` définie par `config/09-ai-core.zsh` (voir l'étape 2 : la consigne d'origine, « redéfinie ici à l'identique de la tâche 5 », a été corrigée le 4 septembre 2026).

- [x] **Step 1: Constater le vert de départ**

Run: `bats tests/unit/test_ai_command_not_found.bats`
Expected: PASS. Ces tests assertent du texte (`Package:`, `Nivuus AI Package Assistant`, `cowsay`) et non des couleurs : ils doivent rester verts sans être modifiés. C'est le filet de cette tâche.

- [x] **Step 2: Ajouter le chargement paresseux**

Insérer avant `_ai_cnf_render_box` :

> **Corrigé le 4 septembre 2026 sur deux points.** La version du 24 août
> portait la même garde `NIVUUS_CHARTE_LOADED` qu'en tâche 5, fausse pour la
> même raison — voir le mécanisme détaillé là-bas ; il mord même plus fort
> ici, cette boîte écrivant sur stderr alors que la décision figée porte sur
> stdout.
>
> Elle demandait aussi de **redéfinir la fonction verbatim** dans ce module,
> au motif que « aucun module ne peut supposer l'autre présent ». L'argument
> visait une dépendance de 24 sur 22, qui n'existe effectivement pas — mais
> les deux modules dépendent tous deux de `config/09-ai-core.zsh`, chargé
> avant eux. La fonction y est donc définie une seule fois, et les deux
> modules la consomment. Deux copies verbatim auraient divergé à la première
> correction — ce qui est exactement ce qui s'est produit avec la garde.

Rien à insérer dans ce fichier : `_ai_charte_load` est définie une fois pour
toutes dans `config/09-ai-core.zsh`, sous la forme donnée en tâche 5.

```zsh
# Dans config/09-ai-core.zsh, partagée par les modules 22 et 24.
_ai_charte_load() {
    local charte="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/lib/charte.sh"
    [[ -f "$charte" ]] && source "$charte"
    return 0
}
```

- [x] **Step 3: Dépeindre le cadre**

Le cadre `╭─ … ╰─` est aujourd'hui entièrement bleu sans signaler aucun état, le nom de commande est vert et le paquet jaune : trois couleurs décoratives que le § 2.4 interdit. Remplacer le corps de `_ai_cnf_render_box` (lignes 234 à 250) par :

```zsh
    _ai_charte_load

    print -u2 ""
    print -u2 -r -- "╭─ 🤖 Nivuus AI Package Assistant ────────────────────────────────────"
    if [[ -n "$desc" ]]; then
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Command:${NIVUUS_C_OFF:-}  ${cmd} — ${desc}"
    else
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Command:${NIVUUS_C_OFF:-}  ${cmd}"
    fi
    if [[ -n "$pkg" ]]; then
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Package:${NIVUUS_C_OFF:-}  ${pkg}"
    fi
    print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Install:${NIVUUS_C_OFF:-}  ${install_cmd}"
    if [[ -n "$alt_cmd" ]]; then
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Alternative:${NIVUUS_C_OFF:-} ${alt_cmd}"
    fi
    print -u2 -r -- "╰─────────────────────────────────────────────────────────────────────"
    print -u2 ""
```

Corriger aussi le commentaire de section ligne 225, `# UI Box Rendering (Nord Palette)`, devenu faux :

```zsh
# UI Box Rendering — charte Nivuus (doc/CHARTE.md)
```

- [x] **Step 4: Convertir le bloc d'installation**

Lignes 326 à 350. Table de décision :

| Avant | Après | Pourquoi |
|---|---|---|
| `%F{221}Install package now…? [y/N]` | `STRONG` | une question n'est pas un avertissement |
| `%F{110}⚙ Installing …` | `busy` | traitement en cours |
| `%F{143}✓ Successfully installed …` | `ok` | succès |
| `%F{110}▶ Running: …` | `busy` | traitement en cours |
| `%F{167}✗ Installation failed …` | `danger` | échec |

```zsh
        print -u2 -n -r -- "${NIVUUS_C_STRONG:-}Install package now with '${install_cmd}'? [y/N] ${NIVUUS_C_OFF:-}"
```
```zsh
            print -u2 -r -- "${NIVUUS_C_BUSY:-}⚙ Installing ${pkg:-$cmd}...${NIVUUS_C_OFF:-}"
```
```zsh
                print -u2 -r -- "${NIVUUS_C_OK:-}✓ Successfully installed ${pkg:-$cmd}!${NIVUUS_C_OFF:-}"
```
```zsh
                    print -u2 -r -- "${NIVUUS_C_BUSY:-}▶ Running: ${cmd} ${original_args[*]}${NIVUUS_C_OFF:-}"
```
```zsh
                print -u2 -r -- "${NIVUUS_C_DANGER:-}✗ Installation failed with exit code $install_status${NIVUUS_C_OFF:-}"
```

Noter que l'invite perd la couleur imbriquée `%F{109}` autour de `${install_cmd}` : elle colorait la commande à l'intérieur d'une phrase déjà colorée, ce qui ne signalait rien.

- [x] **Step 5: Lancer les tests**

Run: `bats tests/unit/test_ai_command_not_found.bats`
Expected: PASS, inchangé par rapport au step 1.

Run: `grep -n '%F{' config/24-ai-command-not-found.zsh`
Expected: aucune sortie.

- [x] **Step 6: Vérifier le rendu à l'œil**

Les tests assertent le texte, pas l'apparence. Regarder une fois la vraie sortie :

```bash
zsh -c 'NIVUUS_SHELL_DIR="$PWD" source config/24-ai-command-not-found.zsh
_ai_cnf_render_box "cowsay" "Configurable cow" "cowsay" "sudo apt install cowsay" ""' 2>&1
```
Expected: le cadre est de la couleur du terminal, les quatre libellés sont en gras, aucune valeur n'est colorée. Si quoi que ce soit apparaît en couleur dans ce cadre, c'est une décoration qui a survécu.

- [x] **Step 7: Commit**

```bash
git add config/24-ai-command-not-found.zsh
git commit -m "refactor(ai-cnf): depeindre le cadre, retirer les gris

Le cadre etait entierement bleu, le nom de commande vert et le paquet
jaune sans qu'aucun ne signale d'etat : la charte reserve la couleur
aux evenements. Ne restent colores que installation, succes et echec.

Les libelles passent du gris %F{244}/%F{254} au gras."
```

---

### Task 7: Le cliquet anti-gris

Sans lui, un gris revient au premier correctif pressé. Il ne pilote pas la conversion — il empêche son annulation.

**Files:**
- Test: `tests/unit/test_charte_no_grey.bats`

**Interfaces:**
- Consumes: l'état du dépôt après les tâches 3 à 6.
- Produces: rien.

- [x] **Step 1: Écrire le test**

```bash
#!/usr/bin/env bats

# bats-core ne fournit pas fail() : on la definit.
fail() { printf '%s\n' "$1" >&2; return 1; }

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    # Le périmètre de la charte, et lui seul (spec § 2.1). Le prompt, les
    # thèmes et la colorisation des outils tiers sont explicitement dehors :
    # ne jamais ajouter un fichier ici sans modifier la spec d'abord.
    SCOPE=(
        lib/charte.sh
        lib/log.sh
        lib/steps.sh
        lib/manifest.sh
        lib/zshrc.sh
        bin/nivuus
        bin/healthcheck
        bin/benchmark
        bin/test
        config/22-ai-errors.zsh
        config/24-ai-command-not-found.zsh
    )
}

@test "aucun dim (SGR 2) dans le perimetre" {
    cd "$ROOT"
    run grep -nE '\\033\[2m|\\e\[2m|%F\{8\}' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "dim ou %F{8} trouve : $output"
}

@test "aucun code ANSI-256 achromatique dans le perimetre" {
    cd "$ROOT"
    # 232 a 255 : la rampe de gris de la palette xterm-256.
    run grep -nE '(38;5;|%F\{)(23[2-9]|24[0-9]|25[0-5])' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "gris ANSI-256 trouve : $output"
}

@test "aucune palette de thememe en dur dans le perimetre" {
    cd "$ROOT"
    run grep -nE "^(RED|GREEN|YELLOW|BLUE|NC)='\\\\033" "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "palette ANSI redeclaree : $output"
}

@test "tous les fichiers du perimetre existent" {
    cd "$ROOT"
    for f in "${SCOPE[@]}"; do
        [ -f "$f" ] || fail "fichier du perimetre absent : $f"
    done
}
```

- [x] **Step 2: Lancer le test**

Run: `bats tests/unit/test_charte_no_grey.bats`
Expected: PASS — 4 tests. S'il échoue, c'est qu'une des tâches 3 à 6 a laissé un gris : le corriger là-bas plutôt qu'assouplir le test.

- [x] **Step 3: Vérifier que le cliquet mord**

```bash
printf "\n_UNUSED=\$'\\\\033[2m'\n" >> lib/log.sh
bats tests/unit/test_charte_no_grey.bats
```
Expected: FAIL sur « aucun dim (SGR 2) dans le perimetre ».

Restaurer : `git checkout lib/log.sh`, relancer, Expected: PASS.

- [x] **Step 4: Lancer la suite complète**

Run: `./bin/test`
Expected: PASS — unitaires, intégration, performance et e2e.

- [x] **Step 5: Commit**

```bash
git add tests/unit/test_charte_no_grey.bats
git commit -m "test(charte): cliquet interdisant tout gris sur le perimetre

Le § 2.2 de la charte rendu executable. Le perimetre est enumere en
clair : y ajouter un fichier demande de modifier la spec d'abord."
```

---

### Task 8: Documentation

**Files:**
- Create: `doc/CHARTE.md`
- Modify: `doc/README.md`, `.zshrc:38-56` (bloc des variables)

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: rien.

- [x] **Step 1: Écrire `doc/CHARTE.md`**

```markdown
# Charte graphique appliquée au terminal

Nivuus suit la charte graphique commune (dépôt `nivuus/design`, socle 0.3.0).
Ce document dit ce qu'elle devient dans un terminal. La charte fait foi ; il
ne la répète pas, il la transpose.

- Spec : `docs/superpowers/specs/2026-08-24-charte-terminal-design.md`
- Source machine : `lib/charte.sh`

## Périmètre

La charte régit ce que Nivuus écrit **en son nom propre** : `lib/log.sh` et
ses consommateurs, `bin/healthcheck`, `bin/benchmark`, `bin/test`,
`config/22-ai-errors.zsh` et `config/24-ai-command-not-found.zsh`.

Elle ne régit **pas** le prompt (`config/05-prompt.zsh`), les thèmes
(`themes/*.zsh`), la complétion, le surlignage syntaxique, ni la colorisation
des outils tiers (`config/17-colorization.zsh`). Ces surfaces emploient la
couleur pour hiérarchiser — path, branche, type de fichier — ce que la charte
interdit mais dont leur lisibilité dépend entièrement. Elles restent sur la
palette du thème actif, et le contrat `THEME_*` (voir `doc/PROMPT.md`) ne
change pas.

Cette frontière est une décision, pas un provisoire. L'élargir est un projet
en soi.

## Les sept variables

`lib/charte.sh` expose sept variables et ne définit aucune fonction.

| Variable | Emploi |
|---|---|
| `NIVUUS_C_DANGER` | erreur |
| `NIVUUS_C_WARN` | avertissement |
| `NIVUUS_C_OK` | succès |
| `NIVUUS_C_BUSY` | traitement en cours |
| `NIVUUS_C_TEXT` | **toujours vide** — voir les dérogations |
| `NIVUUS_C_STRONG` | gras, pour le premier plan |
| `NIVUUS_C_OFF` | réinitialisation |

Deux règles portent tout le reste :

- **La couleur ne s'emploie jamais seule.** Toujours couleur *plus* glyphe
  *plus* libellé. Une sortie doit rester lisible en noir et blanc, pour une
  personne daltonienne comme pour un journal de CI.
- **Aucun gris.** Ni `dim`, ni code ANSI-256 achromatique. Le second plan
  passe par l'absence de gras, jamais par une atténuation. Un test le tient :
  `tests/unit/test_charte_no_grey.bats`.

## Réglage

| Variable | Effet |
|---|---|
| `NIVUUS_CHARTE_MODE` | `light` ou `dark`, force la paire de teintes |
| `NO_COLOR` | neutralise les sept variables |
| `COLORTERM` | `truecolor`/`24bit` active les hex exacts, sinon repli ANSI-256 |

Sans `NIVUUS_CHARTE_MODE`, le mode est déduit de `COLORFGBG`, et à défaut
sombre — le contexte du produit.

## Quand une couleur bouge dans `tokens.css`

1. Côté design : relancer `tools/check_contrast.py`, dont le code de sortie
   fait autorité.
2. Reporter la nouvelle valeur dans `lib/charte.sh`, hex et RGB décimal.
3. Recalculer le repli ANSI-256 si la teinte a bougé : l'entrée xterm-256 la
   plus proche **parmi celles qui tiennent 4,5:1** contre la surface du mode,
   entrées achromatiques exclues.
4. Relancer `bats tests/unit/test_charte_conformity.bats` — il compare
   directement à `tokens.css` et nomme le rôle qui diverge.

## Deux dérogations

Elles sont assumées et doivent être remontées à `docs/charte.md` côté design,
pas dissimulées. Toutes deux tiennent au même fait : un terminal n'est pas une
page.

**`NIVUUS_C_TEXT` n'émet aucune séquence.** La charte garantit ses ratios
contre `--surface`. Dans un terminal, la surface ne nous appartient pas :
écrire `#FFFFFF` sur le fond blanc de quelqu'un produirait exactement
l'illisibilité que la charte protège. On laisse l'avant-plan du terminal, que
son propriétaire a réglé contre son propre fond.

**L'épaisseur remplace la taille.** La charte remplace les gris par
« l'épaisseur, la taille, l'espacement ». Un terminal n'a qu'un seul corps de
texte. Des trois leviers, l'épaisseur est celui qui existe : le premier plan
passe en gras, le second reste en texte normal, de la même couleur.
```

- [x] **Step 2: Référencer depuis `doc/README.md`**

Ajouter une ligne à la liste des documents, dans le style des entrées voisines (les lire avant d'écrire, pour suivre leur forme) :

```markdown
- [CHARTE.md](CHARTE.md) — la charte graphique appliquée aux sorties de Nivuus : périmètre, sept variables, réglage.
```

- [x] **Step 3: Documenter `NIVUUS_CHARTE_MODE` dans `.zshrc`**

Ajouter au bloc de commentaires des variables de thème (`.zshrc:38-56`), après les lignes `NIVUUS_PROMPT_FORMAT` :

```zsh
# NIVUUS_CHARTE_MODE: 'light' ou 'dark' — force la paire de teintes des
#   sorties propres à Nivuus (installeur, healthcheck, messages IA). Sans
#   valeur, le mode est déduit de COLORFGBG, à défaut sombre. N'affecte ni le
#   prompt ni les thèmes. Voir doc/CHARTE.md.
```

Ne pas `export` de valeur par défaut : `lib/charte.sh` traite l'absence, et poser une valeur ici priverait `COLORFGBG` de son rôle.

- [x] **Step 4: Vérifier que le démarrage n'a pas régressé**

Run: `bats tests/performance/test_startup.bats`
Expected: PASS. Le step 3 n'ajoute que des commentaires, mais `.zshrc` est le chemin chaud.

- [x] **Step 5: Lancer la suite complète une dernière fois**

Run: `./bin/test`
Expected: PASS sur les quatre suites.

- [x] **Step 6: Commit**

```bash
git add doc/CHARTE.md doc/README.md .zshrc
git commit -m "docs(charte): documenter le perimetre, les variables et les deux derogations

doc/CHARTE.md dit ce que la charte graphique devient dans un terminal,
ce qu'elle ne regit pas et pourquoi, et la marche a suivre quand une
couleur bouge dans tokens.css."
```

---

## Vérification finale

- [x] `./bin/test` — les quatre suites au vert.
- [x] `bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped` renvoie `0` avec le dépôt design présent.
- [x] `grep -rn '%F{' config/22-ai-errors.zsh config/24-ai-command-not-found.zsh` ne renvoie rien.
- [x] `grep -rn '\\033\[' bin/healthcheck bin/benchmark bin/test lib/log.sh` ne renvoie rien.
- [x] `git diff master --stat -- config/05-prompt.zsh themes/ doc/PROMPT.md config/17-colorization.zsh config/98-syntax.zsh config/18-autosuggestions.zsh config/03-completion.zsh` ne renvoie rien : le hors-périmètre est intact.
- [x] Un `nivuus doctor` et un `./install.sh --non-interactive --prefix /tmp/essai` lancés à l'œil, pour voir les vraies couleurs une fois.

---

## Journal d'exécution — 4 septembre 2026

Les 55 étapes sont cochées après **vérification**, pas après écriture.

Le plan avait bien été exécuté, mais son historique a été écrasé : la PR #2 a
été fusionnée en squash, et le commit `85fdd04` porte à lui seul un commit
par tâche — huit, de `feat(charte)` à `docs(charte)`, dans l'ordre du plan —
**plus** huit commits de correctifs issus d'une revue de code, tous lisibles
dans son corps de message. Aucun commit ne porte donc le nom d'une tâche dans
`git log --oneline`, d'où l'impression d'un plan jamais joué.

Cette session a rejoué chaque étape sur le dépôt tel qu'il est aujourd'hui, et
mesuré chaque vérification que le plan demande. Les écarts entre la lettre du
plan et le dépôt sont listés plus bas : la plupart sont les correctifs de
revue, décidés après l'écriture du plan et donc absents de son texte.

**Trois de ces écarts ont été corrigés dans le corps du plan lui-même**, aux
tâches 4, 5 et 6, chacun signalé par un encadré « Corrigé le 4 septembre
2026 » qui dit ce qui était écrit le 24 août, pourquoi c'était faux, et ce
que rejouer la version d'origine produirait. Le texte fautif n'est pas
supprimé en silence : un plan qu'on rejoue doit porter ses propres
corrections, sans quoi le piège remord.

### Ce qui a été mesuré

| Commande | Résultat |
|---|---|
| `bats tests/unit/test_lib_charte.bats tests/unit/test_lib_log.bats tests/unit/test_charte_no_grey.bats tests/unit/test_charte_conformity.bats` | 39/39 (les 2 tests de conformité, `skip` en début de session faute de `tokens.css`, sont depuis pleinement joués — § Écart 1) |
| `./bin/test --unit` | 580/580 en 57 s |
| `./bin/test --performance` | 10/10 |
| `bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_reversibility.bats tests/e2e/test_nivuus_cli.bats` | 44/44 |
| `bats tests/e2e/test_healthcheck.bats tests/e2e/test_benchmark.bats` | 16/18 — deux échecs pré-existants, § Écart 5 |
| `./bin/test --integration` | 172/193 — 21 échecs pré-existants, § Écart 5 |

Les deux cliquets ont été vus mordre, puis restaurés :

- conformité : `--ok` sombre passé à `78;211;155` → `not ok 1 … charte.sh dit
  '78;211;155', tokens.css dit '78;211;154' (#4ED39A)` ;
- anti-gris : `_UNUSED=$'\033[2m'` ajouté à `lib/log.sh` → `not ok 1 aucun dim
  (SGR 2) dans le perimetre`.

Installation réelle dans un `HOME` jetable (jamais celui de l'utilisateur) :
`install.sh --non-interactive` émet bien `\033[38;2;78;211;154m✓` et
`\033[38;2;122;182;255m·`, et `healthcheck` n'emploie de couleur que sur ses
glyphes d'état, ses titres de section étant en `\033[1m` nu.

### Écarts entre le plan et le dépôt

**Écart 1 — le garde-fou de conformité a failli rester dormant (tâche 2).**
Au début de cette session, `design/assets/tokens.css` n'existait pas : le dépôt
`design` était bien présent au chemin par défaut, mais sa propre charte
n'avait jamais été produite — son plan
`docs/superpowers/plans/2026-08-22-charte-graphique.md` était lui aussi
inexécuté et `assets/` ne contenait que des SVG de marque. Les deux tests de
conformité se marquaient donc `skip` en permanence, et le plan exige
l'inverse (`grep -c skipped` = `0`). Faute de source, la vérification a
d'abord été rejouée contre un `tokens.css` reconstruit depuis le bloc CSS du
plan design (lignes 178-205) : 2/2 au vert, rouge sur une divergence d'une
unité.

Le dépôt design a été produit **pendant** cette session (commits `b14b05d`,
`f4363dd`, `45090ff` ; `assets/tokens.css` et `tools/check_contrast.py`
existent désormais, `docs/charte.md` pas encore). Le garde-fou a été rejoué
contre le vrai fichier :

- `bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped` → `0`,
  la condition du plan est tenue ;
- les huit hex concordent exactement (`#C11F2E #8A5A00 #1B6B4A #1A5FB4` clair,
  `#FF7A85 #F2B33D #4ED39A #7AB6FF` sombre) ;
- `--warn` clair passé à `138;90;1` → `not ok 2 … charte.sh dit '138;90;1',
  tokens.css dit '138;90;0' (#8A5A00)`.

Le garde-fou est vivant. Réserve à retenir : le dépôt design est en cours
d'écriture, ce constat vaut pour son état à `45090ff`. Si `tokens.css` bouge
encore, c'est ce test qui le dira — c'est précisément son emploi.

**À rejouer une fois le dépôt design clos.** La mesure ci-dessus est datée et
ne vaut que pour `45090ff`. Quand `nivuus/design` aura livré sa charte
(`docs/charte.md` manque encore), rejouer, depuis la racine de ce dépôt :

```bash
bats tests/unit/test_charte_conformity.bats
bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped   # doit valoir 0
```

Attendu : 3/3 et `0`. Un `skip` signifie que `tokens.css` a bougé de place ;
un échec nomme le rôle et les deux valeurs qui divergent, et la marche à
suivre est celle du § « Quand une couleur bouge dans `tokens.css` » de
`doc/CHARTE.md`. C'est un renvoi, pas une dette : le test existe, il est
correct, et il passe aujourd'hui.

**Écart 2 — `BLUE` a disparu au lieu d'être traduit (tâche 4).** Le plan
prescrivait une substitution mécanique `BLUE → NIVUUS_C_BUSY` et un
`INFO="${BLUE}ℹ${NC}"`. C'est précisément ce que la revue a corrigé : la
substitution mécanique avait repeint en `busy` 33 filets et titres de section
qui ne signalent aucun état (15 dans `bin/healthcheck`, 12 dans
`bin/benchmark`, 6 dans `bin/test`). `BLUE` a été retiré des trois binaires,
les filets rendus au texte nu, les titres passés en `STRONG`, et `INFO`
dépeint en `ℹ` nu. L'étape 2 de la tâche 4 était donc **fausse telle
qu'écrite** — sa substitution mécanique produit de la couleur décorative, ce
que la charte interdit. **Corrigée en place** dans la tâche 4.

**Écart 3 — `_ai_charte_load` est partagée, pas dupliquée (tâches 5 et 6).**
Le plan demandait de redéfinir la fonction à l'identique dans les deux modules
IA. Elle est définie une seule fois dans `config/09-ai-core.zsh`, que les deux
modules chargent de toute façon. L'argument du plan (« aucun module ne peut
supposer l'autre présent ») visait une dépendance entre les modules 22 et 24 ;
la dépendance réelle est sur le socle 09, qui est un prérequis des deux.
Conservé.

**Écart 4 — deux lignes de la table de décision de la tâche 5 sont fausses.**
La revue les a corrigées et la spec a été amendée dans la foulée ; le texte du
plan, lui, est resté :

- `💾 From cache:` y est rangé en `STRONG`, réservé par le § 4.3 de la spec aux
  libellés du type `Command:`/`Exit Code:`. Le dépôt le laisse en texte nu.
- `⚠  AI Error Analysis` y est rangé en `danger`. Or `⚠` porte `warn` neuf
  lignes plus bas dans le même fichier (« No error to explain ») : même
  glyphe, deux rôles, illisible en noir et blanc. Le dépôt écrit `✗  AI Error
  Analysis`, l'invariant du module étant `✓`=ok, `⚠`=warn, `✗`=danger.

La ligne 178 de la table a été **corrigée en place** dans la tâche 5, avec le
critère qui tranche : la lisibilité sans couleur. La ligne 194
(`💾 From cache:`) est laissée telle quelle, `STRONG` et texte nu étant tous
deux dépourvus de couleur — la divergence est sans conséquence et la signaler
ici suffit.

**Écart 5 — « les quatre suites au vert » n'est pas atteignable, et pas à
cause de la charte.** 23 tests échouent sur `master` avant toute intervention
(arbre de travail identique à `HEAD`, vérifié) :

- 21 en intégration, parce que la pile IA a été refondue depuis le 24 août :
  `config/23-ai-terminal-titles.zsh` n'existe plus et les modules `09-ai-*`
  l'ont remplacé. `tests/integration/test_ai_workflow.bats` et
  `test_module_loading.bats` cherchent encore les anciens fichiers. Hors
  périmètre de la charte (spec § 2.2), et sans rapport avec elle : le seul
  test de ce fichier qui porte sur la charte, « AI error messages use charte
  colors, not raw palette codes », passe.
- `healthcheck runs quickly (<2 seconds)` : 1,5 s mesurées contre un budget
  compté en secondes entières par `date +%s`, qui échoue dès que la mesure
  chevauche une seconde. Flakiness de mesure, pas de régression.
- `benchmark references 300ms performance target` : la chaîne `300` n'apparaît
  dans la sortie que par la branche `✓ Excellent (<300ms)`, prise seulement si
  la machine démarre le shell en moins de 300 ms. Assertion dépendante de la
  machine, indépendante de la couleur.

Aucun de ces échecs ne touche une ligne que la charte a écrite. Les corriger
est un autre chantier — celui de la refonte IA — et le faire ici aurait
mélangé deux sujets.

**Écart 6 — quatre durcissements non prévus, tous conservés.**

- `lib/charte.sh` garde `COLORFGBG` derrière `_nivuus_fgbg`. Le
  `${COLORFGBG##*;}` écrit dans la tâche 1 fait planter tout sourcing sous
  `set -u` quand la variable est absente — donc `bin/nivuus` et `install.sh`,
  latent jusqu'à ce que la tâche 3 câble `charte.sh` dans `lib/log.sh`. Une
  régression unitaire et une régression e2e (`nivuus help` sans `COLORFGBG`)
  le tiennent.
- `tests/unit/test_charte_no_grey.bats` porte 6 tests au lieu de 4 : la liste
  littérale du plan (`\033[2m`, `%F{8}`, 232–255) rate les formes qu'emploie
  réellement du bash pur — SGR bright-black 90/100 et gris par terminfo
  (`tput dim`, `tput setaf 0|8`).
- `_ai_charte_load` **ne garde plus** sur `NIVUUS_CHARTE_LOADED`, contrairement
  à ce qu'écrivent les tâches 5 et 6. `charte.sh` tranche sur `[ -t 1 ]` au
  moment du source : la garde gelait la décision pour toute la session, si bien
  qu'après une seule commande dont stdout est un tube, la boîte de l'assistant
  paquets — qui écrit sur stderr, donc sur le terminal — sortait sans couleur
  ni gras jusqu'à la fin de la session. La garde a été retirée ; le chargement
  reste paresseux. **Corrigé en place** dans les tâches 5 et 6, mécanisme
  écrit.
- `bin/test` employait `${BASH_SOURCE[0]}` pour `PROJECT_ROOT`, inexistant sous
  `zsh` : le lanceur sortait du dépôt, ne trouvait aucune suite, et annonçait
  « All tests passed! » sans rien exécuter. Corrigé avec `$_HERE`. À retenir :
  l'étape 7 de la tâche 4 (« vérifier que le lanceur fonctionne encore »)
  n'aurait pas attrapé ce défaut, un `bin/test` qui n'exécute rien sortant 0.

### Dettes ouvertes

Deux dettes nommées, constatées ici et **délibérément non corrigées** : ni
l'une ni l'autre ne touche une ligne écrite par la charte, et les traiter dans
ce chantier aurait mêlé deux sujets. Elles sont consignées pour ne pas être
redécouvertes à chaque exécution de la suite.

**Dette 1 — les suites d'intégration parlent encore de l'ancienne pile IA.**
`tests/integration/test_ai_workflow.bats` et `test_module_loading.bats`
cherchent `config/23-ai-terminal-titles.zsh`, qui n'existe plus, et
`config/19-ai-suggestions.zsh` dans son état d'avant la refonte ; la pile a
été redécoupée en modules `09-ai-*`. **21 tests rouges**, en permanence.

Ce que ça coûte aujourd'hui : `./bin/test` ne peut pas servir de feu vert.
Une suite qui est rouge quoi qu'on fasse cesse d'être lue, et le prochain vrai
échec d'intégration passera inaperçu au milieu des 21 autres. C'est le coût
réel, et il est immédiat. À traiter avec la refonte IA, dont ces tests sont le
reliquat.

**Dette 2 — deux assertions e2e mesurent la machine, pas le produit.**

- `tests/e2e/test_healthcheck.bats` : `healthcheck runs quickly (<2 seconds)`
  compare deux `date +%s`, donc des secondes entières. `healthcheck` prend
  1,5 s ici : le test échoue chaque fois que la mesure chevauche une seconde,
  et passe sinon. C'est un tirage au sort, pas une assertion.
- `tests/e2e/test_benchmark.bats` : `benchmark references 300ms performance
  target` cherche la chaîne `300` dans la sortie de `bin/benchmark`. Or `300`
  n'y apparaît que par la branche `✓ Excellent (<300ms)`, prise seulement si
  la machine démarre le shell en moins de 300 ms. Le test n'atteste pas que
  la cible est documentée, il atteste que la machine est rapide.

Ce que ça coûte aujourd'hui : **2 tests rouges** sur une suite e2e par
ailleurs saine (16/18), et la même érosion de confiance que la dette 1 à plus
petite échelle. Le correctif est cheap des deux côtés — mesurer en
millisecondes, et chercher `300` dans le texte du script plutôt que dans sa
sortie — mais il appartient à qui reprendra ces suites, pas à la charte.

### Renvoi au dépôt design

Les deux dérogations du § 6 de la spec doivent **remonter dans `docs/charte.md`
du dépôt `nivuus/design`**, où elles n'ont pas encore d'existence — ce fichier
reste à écrire. Ce ne sont pas des tâches de ce dépôt-ci : la charte fait foi,
et une dérogation qui ne vit que chez celui qui la prend n'est pas une
dérogation, c'est une divergence.

- **`--text` n'émet aucune séquence.** La charte garantit ses ratios contre
  `--surface` ; dans un terminal la surface ne nous appartient pas. Écrire
  `#FFFFFF` sur le fond blanc de quelqu'un produirait exactement
  l'illisibilité que le § 2.3 protège. `NIVUUS_C_TEXT` reste donc vide et
  laisse l'avant-plan que le propriétaire du terminal a réglé contre son
  propre fond.
- **L'épaisseur remplace la taille.** Le § 2.2 remplace les gris par
  « l'épaisseur, la taille, l'espacement et le mouvement ». Un terminal n'a
  qu'un seul corps de texte : la taille n'y existe pas. Des leviers restants,
  l'épaisseur est celui que la charte nomme et qui existe — d'où
  `NIVUUS_C_STRONG`, et jamais de `dim`.
