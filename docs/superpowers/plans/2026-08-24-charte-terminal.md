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
| `bin/healthcheck`, `bin/benchmark`, `bin/test` | **Modifiés.** Perdent leurs trois copies de `RED/GREEN/YELLOW/BLUE/NC`. | 4 |
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
  - `NIVUUS_CHARTE_LOADED` — vaut `1` après chargement. Sert de garde au chargement paresseux en tâche 5 et 6.
- Lit en entrée : `NO_COLOR`, `COLORTERM`, `COLORFGBG`, `NIVUUS_CHARTE_MODE`.

- [ ] **Step 1: Écrire le test qui échoue**

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

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bats tests/unit/test_lib_charte.bats`
Expected: FAIL — les 15 tests échouent, `lib/charte.sh` n'existe pas.

- [ ] **Step 3: Écrire `lib/charte.sh`**

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

- [ ] **Step 4: Lancer le test pour vérifier qu'il passe**

Run: `bats tests/unit/test_lib_charte.bats`
Expected: PASS — 15 tests.

Si « le fichier est sourcable par zsh » échoue : vérifier que `zsh` est installé (`command -v zsh`). Le fichier n'emploie que `case`, l'expansion `##`, et `$'...'`, tous trois supportés par `bash`, `zsh` et `dash`.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Écrire le test**

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

- [ ] **Step 2: Lancer le test**

Run: `bats tests/unit/test_charte_conformity.bats`
Expected: PASS — 3 tests, si `~/Projects/Nivuus/design` est présent à côté du dépôt.

Vérifier explicitement qu'il ne passe pas *par accident* en étant skippé :

Run: `bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped`
Expected: `0`. Si les tests sont skippés, le chemin par défaut est faux — corriger `DESIGN` ou lancer avec `NIVUUS_DESIGN_DIR=~/Projects/Nivuus/design`.

- [ ] **Step 3: Vérifier que le test détecte bien une divergence**

Un garde-fou qu'on n'a pas vu échouer ne garde rien.

```bash
sed -i 's/38;2;78;211;154m/38;2;78;211;155m/' lib/charte.sh
bats tests/unit/test_charte_conformity.bats
```
Expected: FAIL sur `--ok sombre : charte.sh dit 78;211;155, tokens.css dit 78;211;154`.

Puis restaurer : `git checkout lib/charte.sh` et relancer, Expected: PASS.

- [ ] **Step 4: Commit**

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

- [ ] **Step 1: Écrire les tests qui échouent**

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

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `bats tests/unit/test_lib_log.bats`
Expected: FAIL — les 6 tests de teinte et les 2 tests de gras/dim échouent (`log.sh` emploie encore ses propres codes et `_C_DIM`). Les 7 tests d'origine passent toujours.

- [ ] **Step 3: Réécrire `lib/log.sh`**

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

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `bats tests/unit/test_lib_log.bats`
Expected: PASS — 15 tests (7 d'origine + 8 ajoutés).

- [ ] **Step 5: Vérifier que les consommateurs n'ont pas bougé**

Run: `bats tests/e2e/test_install_sh_compat.bats tests/e2e/test_reversibility.bats tests/e2e/test_nivuus_cli.bats`
Expected: PASS. Ces suites exercent `lib/steps.sh`, `lib/manifest.sh` et `bin/nivuus`, qui consomment `log_*` sans être modifiés.

- [ ] **Step 6: Commit**

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

- [ ] **Step 1: Constater l'état de départ**

```bash
grep -c '\\033\[' bin/healthcheck bin/benchmark bin/test
bats tests/e2e/test_healthcheck.bats tests/e2e/test_benchmark.bats
```
Expected: des occurrences dans les trois fichiers, et les suites e2e au vert. Ce vert est la référence : il doit être identique à la fin.

- [ ] **Step 2: `bin/healthcheck`**

Remplacer les lignes 10 à 21 (le bloc `# Colors` et le bloc `# Symbols`) par :

```bash
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_HERE/../lib/charte.sh" ] && . "$_HERE/../lib/charte.sh"

RED="${NIVUUS_C_DANGER:-}"
GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
BLUE="${NIVUUS_C_BUSY:-}"
NC="${NIVUUS_C_OFF:-}"

# Symboles — la couleur ne s'emploie jamais seule (charte § 2.4).
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"
INFO="${BLUE}ℹ${NC}"
```

Les 19 sites d'appel qui suivent emploient déjà `${RED}`/`${GREEN}`/`${YELLOW}`/`${BLUE}`/`${NC}` : ils ne changent pas. `echo -e` continue de fonctionner, les séquences étant désormais déjà réelles plutôt qu'échappées.

Attention : `bin/healthcheck` fixe `set -e` en ligne 8. Le `[ -f … ] && . …` renvoie faux si le fichier manque, ce qui tuerait le script. L'écrire en `if` si le `&&` pose problème :

```bash
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi
```

C'est la forme à employer dans les trois fichiers, tous sous `set -e`.

- [ ] **Step 3: Lancer la suite healthcheck**

Run: `bats tests/e2e/test_healthcheck.bats`
Expected: PASS, à l'identique du step 1.

- [ ] **Step 4: `bin/benchmark`**

Remplacer les lignes 15 à 20 (le bloc `# Colors`) par le même bloc, en conservant l'ordre de déclaration d'origine :

```bash
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi

BLUE="${NIVUUS_C_BUSY:-}"
GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
RED="${NIVUUS_C_DANGER:-}"
NC="${NIVUUS_C_OFF:-}"
```

- [ ] **Step 5: Lancer la suite benchmark**

Run: `bats tests/e2e/test_benchmark.bats`
Expected: PASS.

- [ ] **Step 6: `bin/test`**

Ce fichier est en `zsh`, pas en `bash` : `BASH_SOURCE` n'existe pas. Remplacer les lignes 8 à 13 par :

```zsh
# Couleurs — lib/charte.sh est la source unique (doc/CHARTE.md).
_HERE="${0:A:h}"
if [ -f "$_HERE/../lib/charte.sh" ]; then . "$_HERE/../lib/charte.sh"; fi

RED="${NIVUUS_C_DANGER:-}"
GREEN="${NIVUUS_C_OK:-}"
YELLOW="${NIVUUS_C_WARN:-}"
BLUE="${NIVUUS_C_BUSY:-}"
NC="${NIVUUS_C_OFF:-}"
```

- [ ] **Step 7: Vérifier que le lanceur de tests fonctionne encore**

`bin/test` est l'outil qui lance les tests : le casser rendrait tout le reste invisible.

Run: `./bin/test --unit`
Expected: la suite unitaire s'exécute et passe, sortie colorée intacte.

- [ ] **Step 8: Vérifier qu'aucun code ANSI en dur ne subsiste**

Run: `grep -n '\\033\[' bin/healthcheck bin/benchmark bin/test`
Expected: aucune sortie (code 1).

- [ ] **Step 9: Commit**

```bash
git add bin/healthcheck bin/benchmark bin/test
git commit -m "refactor(bin): trois palettes ANSI dupliquees remplacees par charte.sh

healthcheck, benchmark et test declaraient chacun leur propre
RED/GREEN/YELLOW/BLUE. Les 62 sites d'appel sont inchanges."
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

- [ ] **Step 1: Corriger le test d'intégration qui exige des codes Nord**

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

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bats tests/integration/test_ai_workflow.bats --filter "charte colors"`
Expected: FAIL — le fichier contient encore des `%F{`.

- [ ] **Step 3: Ajouter le chargement paresseux**

Insérer cette fonction avant `_ai_explain_error_widget` (celle qui contient la ligne 178) :

```zsh
# Charge lib/charte.sh à la demande, jamais au chargement du module : la
# cible de démarrage <300 ms de .zshrc ne doit rien payer pour une sortie
# qui n'apparaît qu'en cas d'erreur.
_ai_charte_load() {
    [[ -n "${NIVUUS_CHARTE_LOADED:-}" ]] && return 0
    local charte="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/lib/charte.sh"
    [[ -f "$charte" ]] && source "$charte"
    return 0
}
```

- [ ] **Step 4: Convertir les appels**

Appeler `_ai_charte_load` en tête de `_ai_explain_error_widget`, juste après le `return 0` du cas « pas d'erreur », puis remplacer chaque `print -P` par `print -r --`.

Table de décision — les rôles ne sont pas devinés, ils suivent le § 4.3 de la spec :

| Ligne | Avant | Après | Pourquoi |
|---|---|---|---|
| 178 | `%F{167}⚠  AI Error Analysis%f` | `danger` | une erreur est un état |
| 181 | `%F{246}Command:%f` | `STRONG` | libellé de second plan, pas un état — le gris devient du gras |
| 182 | `%F{246}Exit Code:%f` | `STRONG` | idem |
| 194 | `%F{143}💾 From cache:%f` | `STRONG` | « depuis le cache » n'est pas un succès |
| 197 | `%F{110}🤖 Analyzing with AI...%f` | `busy` | traitement en cours |
| 213 | `%F{167}Failed to analyze error…%f` | `danger` | échec |
| 230 | `%F{167}⚠  No error to explain…%f` | `warn` | avertissement, pas une erreur |

Les remplacements, un par un :

```zsh
    print -r -- "${NIVUUS_C_DANGER:-}⚠  AI Error Analysis${NIVUUS_C_OFF:-}"
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

- [ ] **Step 5: Lancer les tests**

Run: `bats tests/integration/test_ai_workflow.bats`
Expected: PASS, y compris le test réécrit.

Run: `grep -n '%F{' config/22-ai-errors.zsh`
Expected: aucune sortie.

- [ ] **Step 6: Vérifier le coût au démarrage**

Le chargement paresseux ne vaut que s'il est réellement paresseux.

Run: `zsh -c 'source .zshrc; print -r -- "charte chargee: ${NIVUUS_CHARTE_LOADED:-non}"'`
Expected: `charte chargee: non`.

Run: `bats tests/performance/test_startup.bats`
Expected: PASS, cible <300 ms tenue.

- [ ] **Step 7: Commit**

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
- Consumes: les sept variables de la tâche 1. `_ai_charte_load` est **redéfinie ici**, à l'identique de la tâche 5 : les deux modules se chargent indépendamment l'un de l'autre et aucun ne peut supposer que l'autre est présent.

- [ ] **Step 1: Constater le vert de départ**

Run: `bats tests/unit/test_ai_command_not_found.bats`
Expected: PASS. Ces tests assertent du texte (`Package:`, `Nivuus AI Package Assistant`, `cowsay`) et non des couleurs : ils doivent rester verts sans être modifiés. C'est le filet de cette tâche.

- [ ] **Step 2: Ajouter le chargement paresseux**

Insérer avant `_ai_cnf_render_box` :

```zsh
# Charge lib/charte.sh à la demande. Identique au module 22 : chaque module
# se charge seul et ne suppose pas l'autre présent.
_ai_charte_load() {
    [[ -n "${NIVUUS_CHARTE_LOADED:-}" ]] && return 0
    local charte="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/lib/charte.sh"
    [[ -f "$charte" ]] && source "$charte"
    return 0
}
```

- [ ] **Step 3: Dépeindre le cadre**

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

- [ ] **Step 4: Convertir le bloc d'installation**

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

- [ ] **Step 5: Lancer les tests**

Run: `bats tests/unit/test_ai_command_not_found.bats`
Expected: PASS, inchangé par rapport au step 1.

Run: `grep -n '%F{' config/24-ai-command-not-found.zsh`
Expected: aucune sortie.

- [ ] **Step 6: Vérifier le rendu à l'œil**

Les tests assertent le texte, pas l'apparence. Regarder une fois la vraie sortie :

```bash
zsh -c 'NIVUUS_SHELL_DIR="$PWD" source config/24-ai-command-not-found.zsh
_ai_cnf_render_box "cowsay" "Configurable cow" "cowsay" "sudo apt install cowsay" ""' 2>&1
```
Expected: le cadre est de la couleur du terminal, les quatre libellés sont en gras, aucune valeur n'est colorée. Si quoi que ce soit apparaît en couleur dans ce cadre, c'est une décoration qui a survécu.

- [ ] **Step 7: Commit**

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

- [ ] **Step 1: Écrire le test**

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

- [ ] **Step 2: Lancer le test**

Run: `bats tests/unit/test_charte_no_grey.bats`
Expected: PASS — 4 tests. S'il échoue, c'est qu'une des tâches 3 à 6 a laissé un gris : le corriger là-bas plutôt qu'assouplir le test.

- [ ] **Step 3: Vérifier que le cliquet mord**

```bash
printf "\n_UNUSED=\$'\\\\033[2m'\n" >> lib/log.sh
bats tests/unit/test_charte_no_grey.bats
```
Expected: FAIL sur « aucun dim (SGR 2) dans le perimetre ».

Restaurer : `git checkout lib/log.sh`, relancer, Expected: PASS.

- [ ] **Step 4: Lancer la suite complète**

Run: `./bin/test`
Expected: PASS — unitaires, intégration, performance et e2e.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Écrire `doc/CHARTE.md`**

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

- [ ] **Step 2: Référencer depuis `doc/README.md`**

Ajouter une ligne à la liste des documents, dans le style des entrées voisines (les lire avant d'écrire, pour suivre leur forme) :

```markdown
- [CHARTE.md](CHARTE.md) — la charte graphique appliquée aux sorties de Nivuus : périmètre, sept variables, réglage.
```

- [ ] **Step 3: Documenter `NIVUUS_CHARTE_MODE` dans `.zshrc`**

Ajouter au bloc de commentaires des variables de thème (`.zshrc:38-56`), après les lignes `NIVUUS_PROMPT_FORMAT` :

```zsh
# NIVUUS_CHARTE_MODE: 'light' ou 'dark' — force la paire de teintes des
#   sorties propres à Nivuus (installeur, healthcheck, messages IA). Sans
#   valeur, le mode est déduit de COLORFGBG, à défaut sombre. N'affecte ni le
#   prompt ni les thèmes. Voir doc/CHARTE.md.
```

Ne pas `export` de valeur par défaut : `lib/charte.sh` traite l'absence, et poser une valeur ici priverait `COLORFGBG` de son rôle.

- [ ] **Step 4: Vérifier que le démarrage n'a pas régressé**

Run: `bats tests/performance/test_startup.bats`
Expected: PASS. Le step 3 n'ajoute que des commentaires, mais `.zshrc` est le chemin chaud.

- [ ] **Step 5: Lancer la suite complète une dernière fois**

Run: `./bin/test`
Expected: PASS sur les quatre suites.

- [ ] **Step 6: Commit**

```bash
git add doc/CHARTE.md doc/README.md .zshrc
git commit -m "docs(charte): documenter le perimetre, les variables et les deux derogations

doc/CHARTE.md dit ce que la charte graphique devient dans un terminal,
ce qu'elle ne regit pas et pourquoi, et la marche a suivre quand une
couleur bouge dans tokens.css."
```

---

## Vérification finale

- [ ] `./bin/test` — les quatre suites au vert.
- [ ] `bats tests/unit/test_charte_conformity.bats 2>&1 | grep -c skipped` renvoie `0` avec le dépôt design présent.
- [ ] `grep -rn '%F{' config/22-ai-errors.zsh config/24-ai-command-not-found.zsh` ne renvoie rien.
- [ ] `grep -rn '\\033\[' bin/healthcheck bin/benchmark bin/test lib/log.sh` ne renvoie rien.
- [ ] `git diff master --stat -- config/05-prompt.zsh themes/ doc/PROMPT.md config/17-colorization.zsh config/98-syntax.zsh config/18-autosuggestions.zsh config/03-completion.zsh` ne renvoie rien : le hors-périmètre est intact.
- [ ] Un `nivuus doctor` et un `./install.sh --non-interactive --prefix /tmp/essai` lancés à l'œil, pour voir les vraies couleurs une fois.
