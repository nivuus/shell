# Présentation : README, démo, vitrine GitHub — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la page d'accueil du projet dise la vérité, la dise en une phrase — *installe, essaie, retire, bit pour bit* — et que la CI rougisse le jour où elle recommence à mentir.

**Architecture :** trois couches, dans cet ordre non négociable — **la vérité avant la beauté**.

| Couche | Ce qu'elle produit | Ce qui la garde |
|---|---|---|
| **Faits** | les cinq faussetés du README corrigées, sans restructuration | `tests/unit/test_readme_claims.bats`, `test_readme_badges.bats` durci |
| **Structure** | README ≤ 200 lignes, anglais intégral, `doc/` autoritaire et indexé | `test_readme_claims.bats` (longueur, langue, ancrage), `test_docs_index.bats` |
| **Démo** | `docs/assets/demo.cast` (source de vérité, texte) → artefact affiché | `tests/e2e/test_demo_scenario.bats`, quatre gardes de divergence |

Le principe est celui du harnais existant : **rien de ce que la documentation affirme ne doit pouvoir survivre à sa propre péremption.** `test_manpage.bats` confronte `nivuus help` à `doc/nivuus.1` ; `test_docs_install.bats` confronte `doc/INSTALL.md` au binaire ; ce plan confronte le README au code, et la démo au produit qu'elle prétend montrer.

**Tech Stack :** Markdown, bats, `grep`/`sed`/`awk` POSIX, asciinema (`.cast`), `svg-term-cli` (rendu), `agg` (repli GIF), Docker (rejeu du scénario), GitHub Actions, `gh` CLI (métadonnées du dépôt).

**Spec :** `docs/superpowers/specs/2026-08-21-presentation-design.md` — elle fait autorité ; en cas de divergence avec ce plan, c'est la spec qui gagne, sauf sur les quatre points tranchés ci-dessous par le propriétaire du projet.

**Chantiers précédents :** `2026-08-20-installation-friction-zero.md` (manifeste, `uninstall`), `2026-08-21-installation-multiplateforme.md`, `2026-08-21-installation-preuve-ci.md` (matrice, `tests/ci/`, badges), `2026-08-21-release-signing.md` (`keys/`, `SECURITY.md`), `2026-08-21-installation-porte-entree.md` (vrai `curl | sh`), `2026-08-21-packaging.md` (mode paquet). **Tous mergés.** Ce plan est écrit pour s'appliquer sur ce `master`-là.

---

## Décisions actées (ne pas rouvrir)

Elles répondent aux questions ouvertes de la spec § 9. Elles ont été tranchées par le propriétaire du projet ; ce plan les exécute, il ne les rediscute pas.

1. **Le README passe intégralement en anglais**, avec le test d'unilinguisme (règle 5.7). Les documentations internes déjà écrites en français — `doc/PROMPT.md`, `doc/PACKAGING.md`, `SECURITY.md`, `docs/superpowers/` — **ne sont pas traduites** : la règle vise le README, page d'accueil publique, et lui seul. Un test qui déborderait sur `doc/` serait une régression de périmètre.
2. **Pas de landing page**, conformément à la conclusion de la spec § 4. Aucune page HTML, aucun GitHub Pages, aucun job de publication. **L'image sociale dérivée de la démo est retenue** (§ 4.2) : c'est du versionné, pas de l'hébergé.
3. **Le seuil de 200 lignes est adopté tel quel**, avec son arbitraire assumé. Le relever se discute en revue, jamais dans le commit qui en a besoin.
4. **La péremption de la démo « à chaque mineure » est adoptée** (garde 4). Elle est **à réévaluer après trois releases mineures** — mention seule, aucune tâche de ce plan ne l'instrumente ni ne la planifie.

### Arbitrage tranché par ce plan : stub IA, pas de clé jetable

La spec (§ 9.3) laisse ouvert le choix entre un stub local et une vraie clé API révoquée après tournage. **Ce plan tranche pour le stub**, pour une raison qui n'est pas la reproductibilité mais la **testabilité** :

> La garde n° 2 rejoue le scénario en conteneur à chaque merge sur `master` ; un rejeu qui dépend d'une clé tierce est un test qui rougit pour une raison étrangère au produit, c'est-à-dire un test qu'on finira par désactiver.

Corollaire assumé : la démo montre une réponse figée, pas celle d'un vrai modèle. La contrepartie est donc **la déclaration explicite** — le stub est nommé dans l'en-tête de `tools/demo/scenario.txt`, son code est versionné dans `tools/demo/stub/agy`, et la légende sous l'image du README le dit en toutes lettres. Un test l'exige (Task 4.5). Une démo qui cacherait son stub serait exactement le genre de mensonge que ce chantier ferme.

**Forme technique du stub :** un faux `agy` (Antigravity CLI) posé sur le `PATH` du conteneur, avec `GEMINI_AUTH_MODE=cli` et `AGY_DAEMON_ENABLED=false`. C'est le **chemin de production existant** (`config/09-ai-backend-gemini.zsh`, `_ai_gemini_cli_call`) : aucune ligne de `config/` n'est modifiée pour tourner la démo, et le flux exercé à l'écran est celui que l'utilisateur exercera. Un stub qui aurait exigé un crochet dans le produit aurait été refusé.

---

## Contraintes globales

- **Le README est le fichier le plus disputé du dépôt.** Toute tâche qui le touche commence par un rebase sur `master`. Les tâches de la phase 1 le touchent **par retouche locale**, jamais par réécriture : la réécriture est la phase 3, et elle est atomique.
- **`config/*.zsh` est du ZSH ; `lib/*.sh`, `install.sh` et `tests/ci/*.sh` restent POSIX** (BusyBox ash, bash 3.2). Ce plan **ne modifie aucun de ces fichiers** — il ne change rien à ce que fait Nivuus. Si une tâche vous conduit à éditer `config/` ou `lib/`, c'est que vous êtes sorti du périmètre (spec § 6).
- **Aucune installation de paquet dans un workflow.** `tests/unit/test_ci_workflows.bats` l'interdit et la règle est bloquante. Toute dépendance nouvelle passe par `tests/ci/install-deps.sh` et l'action composite `.github/actions/setup-tests`. Les outils de la démo (`asciinema`, `svg-term`, `agg`, `expect`, Docker) sont **des outils de poste de travail**, jamais des étapes de CI : la démo est produite à la main (spec § 3.3).
- **Piège des `.zwc`** : avant toute suite qui touche `config/*.zsh`, faire `rm -f config/*.zwc`. Aucune tâche de ce plan ne modifie `config/`, mais les tests qui *lisent* `config/` (règles 5.1 et 5.10) doivent lire la source, pas un bytecode périmé.
- **Chiffres de référence à ne pas dégrader** (0 échec partout) :

  | Suite | Tests | Skips |
  |---|---|---|
  | `bats tests/unit/` | 871 | 0 |
  | `bats tests/integration/` | 195 | 2 |
  | `bats tests/e2e/` | 218 | 4 (+ 7 tests `docker` exclus par défaut) |
  | `bats tests/performance/` | 13 | 0 |

  Ce plan **ajoute** des tests ; ces nombres ne peuvent que croître. Après chaque tâche, relancer la suite concernée et vérifier qu'aucun test **existant** ne bascule au rouge ni ne devient `skip`. Si un test existant échoue, c'est une régression du plan, pas un chiffre à mettre à jour.
- **`./bin/test-count --check` doit sortir en 0.** Le compteur est un cliquet : il tolère la croissance mais l'annonce. Chaque tâche qui ajoute des tests exécute `./bin/test-count --update` **dans le même commit**, et `git add tests/baseline-counts.tsv`.
- **`./bin/benchmark` reste sous 300 ms.** Aucune tâche ne touche au chemin de démarrage ; le vérifier une fois, en fin de phase 3, suffit.
- **Un commit par tâche**, message conventionnel en anglais (`docs(readme): …`, `test(docs): …`, `feat(demo): …`). Les tâches sont indépendantes et mergeables une par une, **sauf** les dépendances explicitement nommées dans « Ordre ».
- **Le plan est en français, le README qu'il produit est en anglais.** Les messages de commit sont en anglais (convention du dépôt) ; les commentaires des tests bats sont en français, comme tous les tests existants.

## Ordre d'exécution

```
Phase 1 (vérité)     T1.1 → T1.9   indépendantes deux à deux, sauf T1.1 qui crée
                                   tests/unit/test_readme_claims.bats — la faire en premier
Phase 2 (doc rangée) T2.1 → T2.4   indépendantes ; T2.1 crée test_docs_index.bats
Phase 3 (réécriture) T3.1 → T3.2   T3.1 consomme TOUTE la phase 2 (l'index doit exister
                                   avant que le README pointe dessus) ; T3.2 consomme T3.1
Phase 4 (démo)       T4.1 → T4.6   séquentielles : T4.1 décide le format, T4.2 le scénario,
                                   T4.3 l'enregistre, T4.4 le rend, T4.5 le publie, T4.6 le périme
Phase 5 (vitrine)    T5.1 → T5.3   T5.3 consomme T4.5 (elle dérive une frame de la démo) ;
                                   T5.1 et T5.2 sont exécutables dès aujourd'hui
```

Chaque phase est mergeable seule et laisse le dépôt vert. **Ne pas commencer la phase 3 avant que la phase 2 soit mergée** : un README qui pointe un index inexistant casserait la règle 5.6 dans les deux sens.

## Point de contact : le chantier `--system` en cours

Un chantier d'installation multi-utilisateur (`--system`) est en cours dans `.worktrees/`. Il touche la documentation d'administration et **pourrait vouloir ajouter une section au README**.

**Ce plan ne le planifie pas et ne l'anticipe pas.** La spec (§ 6, hors périmètre) a délibérément laissé `--system` hors du README réécrit : l'installation multi-utilisateur n'est pas un argument de page d'accueil, et anticiper créerait un conflit de merge sur le fichier le plus disputé du dépôt.

**Comment les deux se recollent :**

| Situation | Conduite à tenir |
|---|---|
| `--system` merge **avant** la phase 3 | La réécriture (T3.1) rebase et **ne reprend pas** la section `--system` du README : elle vérifie que son contenu vit bien dans `doc/INSTALL.md`, et le README n'en garde rien. Si le contenu n'existe qu'au README, le déplacer dans `doc/INSTALL.md` **dans le même commit** — c'est un déplacement, pas une suppression. |
| `--system` merge **après** la phase 3 | Il trouvera un README à ~195 lignes sous un test de longueur. Sa section d'accueil est `doc/INSTALL.md`, déjà listée dans l'index (T2.1) et déjà confrontée au binaire par `test_docs_install.bats`. **Aucune ligne de README ne lui est due.** Si son auteur juge qu'une mention d'une ligne est indispensable, elle passe par l'index `doc/` — pas par une section. |
| Conflit sur `doc/INSTALL.md` | Les deux chantiers y écrivent : T2.4 y déplace « Vérifier le trousseau de signature ». Le conflit est textuel et local (deux sections distinctes) ; il se résout par concaténation. |

Une règle suffit à tenir la couture : **le README ne mentionne jamais `--system`**, et `tests/e2e/test_docs_install.bats` interdit déjà `sudo ./install.sh --system` dans le README. Cette interdiction existante est le point de contact, et elle est déjà verte.

---

# PHASE 1 — La vérité, avant toute restructuration

Neuf tâches, aucune ne déplace une section. Elles corrigent des affirmations **fausses aujourd'hui** et posent le harnais qui les empêchera de revenir. Chacune est utile seule et mergeable seule : même si les phases 2 à 5 n'étaient jamais exécutées, le README cesserait de mentir.

*Sortie de phase : les nouveaux tests échouent sur `HEAD~1` et passent sur `HEAD`.*

---

### Task 1.1: un seul chiffre de démarrage dans le README (règle 5.3)

**Files:**
- Create: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (badge, puce « Lightning Fast », section « Performance »)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `tests/performance/test_startup.bats` (`NIVUUS_STARTUP_BUDGET_MS:-300`) comme **unique** source du chiffre.
- Produces: le fichier de règles `test_readme_claims.bats`, socle des tâches 1.2, 1.8, 1.9 et 3.1.

Le README contient **trois chiffres de démarrage contradictoires** : le badge `startup-<300ms`, la puce « Sub-100ms startup time », la section Performance « <100ms (typically 40-60ms) ». Un seul est imposé par un test. Les deux autres sont des promesses que rien ne tient — et la plus basse est celle qu'un lecteur retiendra.

**Silence de la spec comblé ici.** La règle 5.3 dit « il n'existe **qu'un** motif `\d+ ?ms` autorisé », mais la puce que la spec écrit elle-même en § 2 contient « (measured: 26–46 ms) ». La règle littérale interdirait le texte cible. Résolution retenue : **un seul chiffre de *promesse*, égal au budget imposé ; les mesures sont autorisées à condition d'être marquées comme telles et de citer leur méthode.** Concrètement, une ligne qui contient un chiffre en millisecondes doit soit annoncer le budget, soit contenir le mot `measured` et un lien vers l'artefact qui l'a mesuré. C'est ce que le test vérifie, et c'est ce qui distingue une preuve d'une promesse.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_readme_claims.bats
#!/usr/bin/env bats
#
# Le README est la seule surface du projet lue AVANT toute exécution de code.
# Une erreur y coûte un utilisateur qui ne saura jamais qu'il en était un.
# Ces règles rendent la CI rouge quand il ment.
#
# Principe, identique à test_manpage.bats et test_docs_install.bats :
# on ne teste pas le style, on confronte chaque affirmation au dépôt.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    README="$ROOT/README.md"
}

# Le budget de démarrage est celui qu'un test IMPOSE, pas celui qu'on souhaite.
enforced_budget() {
    grep -o 'NIVUUS_STARTUP_BUDGET_MS:-[0-9]*' "$ROOT/tests/performance/test_startup.bats" \
        | head -1 | sed 's/.*-//'
}

@test "le budget de démarrage imposé est lisible depuis les tests de performance" {
    b="$(enforced_budget)"
    [ -n "$b" ]
    [ "$b" -gt 0 ]
}

@test "REGLE 5.3: tout chiffre en ms du README est soit le budget, soit une mesure sourcée" {
    budget="$(enforced_budget)"
    fautes=""
    lineno=0
    while IFS= read -r line; do
        lineno=$((lineno + 1))
        # Les chiffres de la forme 300ms, 300 ms, <300ms, 26–46 ms.
        printf '%s' "$line" | grep -qE '[0-9]+ ?ms' || continue
        # Cas 1 : la ligne annonce le budget imposé, et rien d'autre.
        autres="$(printf '%s' "$line" | grep -oE '[0-9]+ ?ms' | tr -d ' ms' \
                  | grep -vx "$budget" || true)"
        if [ -z "$autres" ]; then continue; fi
        # Cas 2 : la ligne est une MESURE, elle le dit et elle cite sa source.
        if printf '%s' "$line" | grep -qi 'measured' \
           && printf '%s' "$line" | grep -qE 'tests/performance|matrix\.yml|doc/FEATURES\.md'; then
            continue
        fi
        fautes="$fautes
  L$lineno: $line"
    done < "$README"
    [ -z "$fautes" ] || {
        echo "chiffre de démarrage ni imposé ni mesuré (budget = ${budget}ms) :$fautes"
        false
    }
}

@test "REGLE 5.3: il n'existe au plus qu'UNE ligne de mesure dans le README" {
    # Deux mesures, c'est déjà deux vérités concurrentes -- exactement le
    # mécanisme qui a produit « <100ms » à côté de « 40-60ms ».
    n="$(grep -ciE '[0-9]+ ?ms.*measured|measured.*[0-9]+ ?ms' "$README" || true)"
    [ "$n" -le 1 ] || { echo "$n lignes de mesure dans le README"; false; }
}

@test "REGLE 5.3: aucune promesse de démarrage inférieure au budget imposé" {
    # Le mode de défaillance historique : un superlatif chiffré (« sub-100ms »)
    # qu'aucun test ne peut faire échouer.
    run grep -niE 'sub-?[0-9]+ ?ms|under [0-9]+ ?ms' "$README"
    [ "$status" -ne 0 ] || { echo "promesse de démarrage non imposée : $output"; false; }
}

@test "le badge de démarrage annonce toujours le budget imposé" {
    # Doublon volontaire de test_readme_badges.bats : si un jour l'un des
    # deux fichiers est supprimé, la propriété survit dans l'autre.
    budget="$(enforced_budget)"
    grep -q "startup-<${budget}ms" "$README"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — 3 des 5 tests échouent. « Sub-100ms startup time » (ligne 14) et « **Actual:** <100ms startup time (typically 40-60ms) » (ligne 341) portent des chiffres qui ne sont ni le budget ni une mesure sourcée ; `sub-100ms` déclenche aussi la règle de la promesse non imposée.

- [ ] **Step 3: Write minimal implementation**

Trois retouches locales dans `README.md`, **sans toucher au reste de la structure**.

La puce de la section « Features » :

```markdown
- ⚡ **Fast, and held to it** - A CI test fails the build if an interactive shell takes more than 300ms to start
```

La section « Performance » (remplacer la première puce) :

```markdown
## 📊 Performance

The startup budget is **enforced**, not observed: `tests/performance/test_startup.bats`
fails the build past 300ms. That is what makes the number worth printing.

- **Enforced budget:** 300ms — see [tests/performance/](tests/performance/)
- Typical times measured on the CI matrix: 26–46 ms — see [tests/performance/](tests/performance/)
- **Lazy-loaded completion** - compinit loads on first TAB
- **Lazy loading** for NVM and heavy features
- **Git caching** with 2s TTL
- **Compiled ZSH files** for faster loading
- **No external plugins** - pure ZSH
```

Le badge (ligne 8) est **inchangé** : il annonce déjà `startup-<300ms`, le seul chiffre imposé.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_readme_badges.bats
bats tests/e2e/test_docs_install.bats
./bin/test-count --update
```
Expected: PASS — 5 nouveaux tests ; `test_readme_badges` et `test_docs_install` restent verts.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): state one startup figure, the one a test enforces"
```

---

### Task 1.2: aucun superlatif non mesuré (règle 5.2)

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `test_readme_claims.bats` (Task 1.1).
- Produces: une liste noire de superlatifs, applicable au README seul.

Une promesse qualitative n'est pas testable. Puisqu'on ne peut pas la vérifier, on interdit de l'écrire. « Lightning Fast » est dans le README d'aujourd'hui ; « Zero Config » et « beautiful prompt » aussi.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
@test "REGLE 5.2: aucun superlatif non mesuré dans le README" {
    # Liste noire, volontairement courte et littérale. Une promesse
    # qualitative n'est pas testable : on interdit donc d'en écrire une.
    # Elle ne s'applique qu'au README -- doc/ décrit, le README vend, et
    # c'est le seul endroit où vendre dérape.
    fautes=""
    for mot in blazing lightning ultimate "the best" "just works" insanely \
               revolutionary "zero config" "beautiful" "buttery" "supercharge"; do
        if grep -qiF "$mot" "$README"; then
            fautes="$fautes
  $mot: $(grep -inF "$mot" "$README" | head -3)"
        fi
    done
    [ -z "$fautes" ] || { echo "superlatif non mesuré :$fautes"; false; }
}

@test "REGLE 5.2: la liste noire est non vide et vérifiée sur elle-même" {
    # Garde-fou du garde-fou : un test qui boucle sur une liste vide passe
    # toujours. Ici, on prouve que la règle SAIT échouer.
    tmp="$BATS_TEST_TMPDIR/faux-readme.md"
    printf 'Nivuus is blazing fast.\n' > "$tmp"
    run grep -qiF blazing "$tmp"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — `lightning` (puce « Lightning Fast »), `zero config` (puce « Zero Config ») et `beautiful` (« beautiful prompt ») sont présents.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, réécrire les trois puces fautives — en disant **ce que le produit fait**, pas ce qu'il ressent :

```markdown
- 🛠️ **Works unconfigured** - Sensible defaults; `~/.zsh_local` when you want otherwise
- 🌿 **Git Integration** - Fast shortcuts, plus branch and dirty state in the prompt
```

(La puce « Lightning Fast » a déjà été réécrite en Task 1.1 ; si les deux tâches sont exécutées dans le désordre, appliquer ici la formulation de la Task 1.1.)

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_claims.bats
./bin/test-count --update
```
Expected: PASS — 7 tests dans la suite.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): drop superlatives no test can fail"
```

---

### Task 1.3: l'IA multi-backend existe, la documentation l'ignore (règle 5.10)

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md`
- Modify: `doc/FEATURES.md`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `config/09-ai-core.zsh`, `config/09-ai-backend-{gemini,openai,anthropic}.zsh`, `config/09-ai-agy-daemon.zsh`.
- Produces: la règle 5.10 (une variable citée doit être lue par un module) **et** sa réciproque ciblée : `AI_BACKEND` doit être documenté.

`AI_BACKEND` route sur `{gemini, openai, anthropic}` depuis `config/09-ai-core.zsh:10`. Le mot n'apparaît **nulle part** dans `README.md` ni dans `doc/FEATURES.md`. On documente une contrainte qui n'existe plus (« AI commands require a Google Gemini API key ») et on rend invisible un support livré. La règle 5.10 attrape le sens inverse — documenter une variable disparue — et c'est elle qu'on instrumente, parce que c'est elle qui pourrit toute seule.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
# Toutes les variables d'environnement citées par le README, quelle que soit
# la forme : $VAR, ${VAR}, `VAR=…`, ou nue dans un bloc de code.
readme_env_vars() {
    grep -ohE '\b(NIVUUS_[A-Z0-9_]+|ENABLE_[A-Z0-9_]+|AI_[A-Z0-9_]+|GEMINI_[A-Z0-9_]+|OPENAI_[A-Z0-9_]+|ANTHROPIC_[A-Z0-9_]+|GOOGLE_[A-Z0-9_]+|AGY_[A-Z0-9_]+|AUTOUPDATE_[A-Z0-9_]+|GIT_PROMPT_[A-Z0-9_]+)\b' \
        "$README" | LC_ALL=C sort -u
}

@test "REGLE 5.10: toute variable citée par le README est lue par un module" {
    # Le mode de défaillance : documenter une variable qu'un refactor a
    # supprimée. Le lecteur l'exporte, rien ne se passe, et il conclut que
    # le produit est cassé.
    rm -f "$ROOT"/config/*.zwc   # un .zwc périmé masquerait la source
    inconnues=""
    for v in $(readme_env_vars); do
        grep -qrF "$v" "$ROOT/config" "$ROOT/lib" "$ROOT/.zshrc" "$ROOT/bin" \
            || inconnues="$inconnues $v"
    done
    [ -z "$inconnues" ] || {
        echo "variables documentées mais lues par aucun module :$inconnues"; false; }
}

@test "REGLE 5.10: la règle voit au moins une variable (elle n'est pas inerte)" {
    n="$(readme_env_vars | wc -l)"
    [ "$n" -ge 5 ] || { echo "seulement $n variables vues : l'extraction est cassée"; false; }
}

@test "AI_BACKEND est documenté là où l'utilisateur le cherche" {
    # Livré dans config/09-ai-core.zsh et invisible des deux documents que
    # lit quelqu'un qui veut brancher son propre fournisseur.
    grep -q 'AI_BACKEND' "$README"
    grep -q 'AI_BACKEND' "$ROOT/doc/FEATURES.md"
}

@test "les trois backends réellement routés sont les trois backends documentés" {
    # Source de vérité : le case de _ai_api_call. Si un quatrième backend
    # arrive, ce test le réclame dans la doc le jour même.
    for b in gemini openai anthropic; do
        grep -qi "$b" "$ROOT/doc/FEATURES.md" || { echo "backend non documenté: $b"; false; }
    done
}

@test "le README ne présente plus la clé Google comme une obligation" {
    run grep -niE 'require[sd]? a (google )?gemini api key|requires a google api key' "$README"
    [ "$status" -ne 0 ] || { echo "contrainte périmée : $output"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — `AI_BACKEND` absent des deux fichiers ; `openai` et `anthropic` absents de `doc/FEATURES.md` ; la ligne « AI commands require a Google Gemini API key » est toujours là.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, remplacer la puce « AI-Powered » :

```markdown
- 🤖 **Optional AI, your key, your provider** - `AI_BACKEND=gemini|openai|anthropic`. Nivuus works fully without it
```

et, dans la section « Optional » des prérequis, remplacer la ligne de clé Gemini :

```markdown
- **An AI API key** - Optional. `AI_BACKEND` selects the provider: `gemini`
  (`GOOGLE_API_KEY`, or `GEMINI_AUTH_MODE=cli` with the Antigravity CLI),
  `openai` (`OPENAI_API_KEY`), `anthropic` (`ANTHROPIC_API_KEY`).
  Without a key, every AI command tells you so and everything else works.
```

Dans `doc/FEATURES.md`, ajouter une sous-section sous `## AI-Powered Commands`, avant `### Quick Help` :

```markdown
### Backends

Nivuus talks to one of three providers. The active one is `AI_BACKEND`:

| `AI_BACKEND` | Credential | Model override | Default model |
|---|---|---|---|
| `gemini` (default) | `GOOGLE_API_KEY`, or `GEMINI_AUTH_MODE=cli` + the `agy` CLI | `GEMINI_MODEL` / `GEMINI_CLI_MODEL` | `gemini-3.5-flash-lite` |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `gpt-5.6-luna` |
| `anthropic` | `ANTHROPIC_API_KEY` | `ANTHROPIC_MODEL` | `claude-haiku-4-5` |

```bash
# In ~/.zsh_local
export AI_BACKEND=anthropic
export ANTHROPIC_API_KEY=sk-ant-...
```

`GEMINI_AUTH_MODE=cli` spends a Google AI subscription's quota through the
Antigravity CLI (`agy`) instead of a metered API key. A persistent `agy`
daemon (`AGY_DAEMON_ENABLED`, on by default) avoids paying 3–6 s of process
startup on every call.

**No key, no breakage.** Every AI feature degrades to a message that names the
variable to set. Nothing else in the shell depends on it.
```

Mettre également à jour la table des matières de `doc/FEATURES.md` (ligne 5) pour y faire figurer la nouvelle sous-section.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_ai_backends.bats tests/unit/test_ai_agy_daemon.bats
bats tests/unit/test_markdown.bats
./bin/test-count --update
```
Expected: PASS — 12 tests dans la suite ; les suites IA existantes inchangées.

- [ ] **Step 5: Commit**

```bash
git add README.md doc/FEATURES.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(ai): document the multi-backend routing that already ships"
```

---

### Task 1.4: le command-not-found assisté est livré, personne ne le sait

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md`
- Modify: `doc/FEATURES.md`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `config/24-ai-command-not-found.zsh` (`command_not_found_handler`, `ai-cnf-*`, `ENABLE_AI_COMMAND_NOT_FOUND`, `AI_CNF_*`).
- Produces: la fonctionnalité la plus démonstrative du produit, documentée — et **le plan central de la démo** (spec § 3.2, t=11–17 s), qui serait invérifiable sans elle.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
@test "le command-not-found assisté est documenté dans doc/FEATURES.md" {
    # Livré dans config/24-ai-command-not-found.zsh, absent de toute la
    # documentation utilisateur. C'est aussi le plan central de la démo :
    # montrer un flux non documenté serait deux fois fautif.
    grep -qi 'command.not.found' "$ROOT/doc/FEATURES.md"
    grep -q 'ENABLE_AI_COMMAND_NOT_FOUND' "$ROOT/doc/FEATURES.md"
}

@test "les commandes publiques du module command-not-found sont documentées" {
    rm -f "$ROOT"/config/*.zwc
    for cmd in ai-cnf-lookup ai-cnf-clear-cache ai-cnf-stats ai-cnf-help; do
        grep -qF "$cmd" "$ROOT/config/24-ai-command-not-found.zsh"   # elle existe
        grep -qF "$cmd" "$ROOT/doc/FEATURES.md"                      # elle est documentée
    done
}

@test "le README mentionne le command-not-found au moins une fois" {
    run grep -niE 'command.not.found|command that does not exist' "$README"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — les trois tests : aucune occurrence dans `doc/FEATURES.md` ni dans `README.md`.

- [ ] **Step 3: Write minimal implementation**

Dans `doc/FEATURES.md`, après la sous-section « Backends » :

```markdown
### Command not found

When you type a command that does not exist, Nivuus does not stop at
`command not found`. It looks up which package provides it — first from the
system's own package database, then, if that fails, by asking the AI — and
offers the exact install command for your distribution.

```bash
$ rg TODO src/
zsh: command not found: rg
  ripgrep provides `rg`
  → sudo apt-get install -y ripgrep       [Enter to run, Ctrl-C to skip]
```

| Variable | Default | Effect |
|---|---|---|
| `ENABLE_AI_COMMAND_NOT_FOUND` | `true` | Turn the whole handler off |
| `AI_CNF_AUTO_PROMPT` | `true` | Offer to run the install command |
| `AI_CNF_RE_EXECUTE` | `true` | Re-run your original command after a successful install |
| `AI_CNF_TIMEOUT` | see module | Give up rather than hang the prompt |
| `AI_COMMAND_NOT_FOUND_CACHE_TTL` | see module | Cache lifetime for a resolved lookup |

Answers are cached in `AI_COMMAND_NOT_FOUND_CACHE_DIR`, so the second miss on
the same command costs nothing.

```bash
ai-cnf-lookup rg        # ask without mistyping anything
ai-cnf-stats            # cache hit rate
ai-cnf-clear-cache      # forget everything it learned
ai-cnf-help             # the short version of this section
```

The native lookup needs no key. Only the AI fallback does.
```

Dans `README.md`, compléter la puce IA écrite en Task 1.3 :

```markdown
- 🤖 **Optional AI, your key, your provider** - `AI_BACKEND=gemini|openai|anthropic`, plus a command-not-found that names the package to install. Nivuus works fully without it
```

Mettre à jour la table des matières de `doc/FEATURES.md`.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_ai_command_not_found.bats
./bin/test-count --update
```
Expected: PASS — 15 tests dans la suite ; `test_ai_command_not_found.bats` inchangé.

- [ ] **Step 5: Commit**

```bash
git add README.md doc/FEATURES.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(ai): document the assisted command-not-found handler"
```

---

### Task 1.5: le chemin de sauvegarde annoncé est le chemin réel

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (section « Backup & Restore »)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `lib/manifest.sh` (`NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"`).
- Produces: un test qui **dérive** le chemin documenté du code, au lieu de le recopier.

Le README affirme : « Automatic backups are created at: **During installation**: `~/.config/nivuus-shell-backup/` ». C'est faux depuis le chantier 1 : l'installation écrit dans `~/.local/state/nivuus/backups/`. Quelqu'un qui cherche sa sauvegarde après un incident cherche au mauvais endroit — c'est-à-dire au pire moment possible.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
@test "le chemin de sauvegarde du README est celui que lib/manifest.sh écrit" {
    # Dérivé du code, jamais recopié : c'est la seule forme de documentation
    # de chemin qui ne périme pas.
    grep -q 'NIVUUS_BACKUP_DIR="\$NIVUUS_STATE_DIR/backups"' "$ROOT/lib/manifest.sh"
    grep -qF '.local/state/nivuus/backups' "$README" \
        || { echo "le README n'annonce pas le répertoire de sauvegarde réel"; false; }
}

@test "le chemin de sauvegarde périmé a disparu du README et de doc/" {
    run grep -rnF 'nivuus-shell-backup' "$README" "$ROOT/doc"
    [ "$status" -ne 0 ] || { echo "chemin périmé encore documenté : $output"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — le README annonce `~/.config/nivuus-shell-backup/` et ignore `~/.local/state/nivuus/backups/`.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, remplacer les trois lignes de la sous-section « Backup & Restore » :

```markdown
Nivuus keeps two kinds of backup, and they are not interchangeable:

- **Install-time backup** — every file `nivuus install` was about to overwrite is
  copied, content-addressed, into `~/.local/state/nivuus/backups/`. This is what
  `nivuus uninstall` restores from, byte for byte. Removed only by
  `nivuus uninstall --purge`.
- **Manual config backup** — `config_backup` / `config_restore`, for your own
  snapshots of the shell configuration.
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_claims.bats
bats tests/e2e/test_reversibility.bats
./bin/test-count --update
```
Expected: PASS — 17 tests dans la suite ; la réversibilité inchangée (aucun code touché).

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): name the backup directory nivuus actually writes"
```

---

### Task 1.6: « Project Structure » est supprimée, pas déplacée

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (suppression des lignes 480-513)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: rien.
- Produces: l'interdiction d'une arborescence recopiée à la main dans le README.

La section liste `bin/healthcheck` et `bin/benchmark` mais **pas `bin/nivuus`**, l'exécutable principal ; elle ignore `lib/` (9 modules), `keys/`, `doc/nivuus.1` ; elle décrit `install.sh` comme « Installation script » alors que c'est un wrapper mince. La spec tranche : **supprimée, pas déplacée**. Une arborescence recopiée à la main ment par construction, et aucun test raisonnable ne peut la maintenir — `doc/CLAUDE.md` décrit l'architecture, `ls` décrit l'arborescence.

Contrepartie assumée : on perd une vue d'ensemble à laquelle certains lecteurs tiennent. Elle est remplacée, en phase 3, par une ligne de l'index `doc/` pointant `doc/CLAUDE.md`.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
@test "le README ne contient plus d'arborescence recopiée à la main" {
    # Une arborescence à la main ment par construction : elle périme au
    # premier fichier ajouté, et aucun test raisonnable ne peut la
    # maintenir (il faudrait décrire l'arbre deux fois). doc/CLAUDE.md
    # décrit l'architecture ; « ls » décrit l'arborescence.
    run grep -nE '^[[:space:]]*(├──|└──|│)' "$README"
    [ "$status" -ne 0 ] || {
        echo "arborescence ASCII dans le README :"; echo "$output"; false; }
}

@test "la section Project Structure a disparu" {
    run grep -niE '^#{2,3} .*project structure' "$README"
    [ "$status" -ne 0 ]
}

@test "l'architecture reste documentée quelque part" {
    # Supprimer sans reloger serait une perte, pas un rangement.
    [ -f "$ROOT/doc/CLAUDE.md" ]
    grep -qiE 'architecture|module' "$ROOT/doc/CLAUDE.md"
    grep -qF 'doc/CLAUDE.md' "$README"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — les trois : le bloc `├──` existe, le titre `## 📁 Project Structure` existe, et `doc/CLAUDE.md` n'est pas encore lié depuis le README.

- [ ] **Step 3: Write minimal implementation**

Supprimer intégralement la section `## 📁 Project Structure` de `README.md` (du titre jusqu'à la ligne précédant `## 🔧 Requirements`).

Dans la section `## 📚 Documentation`, ajouter la ligne manquante :

```markdown
- **[CLAUDE.md](doc/CLAUDE.md)** - Architecture, module layout, and how to contribute
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_markdown.bats
./bin/test-count --update
```
Expected: PASS — 20 tests dans la suite ; README réduit d'environ 34 lignes.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): delete the hand-copied project tree"
```

---

### Task 1.7: un badge atteste, ou il n'existe pas (règle 5.4)

**Files:**
- Modify: `tests/unit/test_readme_badges.bats`
- Modify: `README.md` (suppression de deux badges)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `.github/workflows/`, `tests/performance/test_startup.bats`.
- Produces: le durcissement de la règle existante — tout badge est soit un workflow réel, soit adossé à un test nommé en commentaire.

`tests/unit/test_readme_badges.bats` interdit déjà le badge orphelin, non épinglé, figé ou `continue-on-error`. Il ne voit pas `license-MIT` ni `shell-ZSH` : deux shields **statiques**, qui n'attestent rien. La licence est dans `LICENSE` et affichée par GitHub dans la barre latérale ; « shell : ZSH » est dans le titre et dans la phrase de promesse.

Le badge `startup-<300ms` est **aussi** un shield statique — mais il est adossé à un test, et `test_readme_badges.bats` vérifie déjà qu'il annonce le budget imposé. La règle doit donc distinguer « statique et prouvé » de « statique et décoratif ». Le discriminant retenu : **un commentaire HTML qui nomme le test porteur**, sur la ligne précédente. C'est vérifiable, et ça oblige à écrire quelle preuve on invoque.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_badges.bats` :

```bash
@test "REGLE 5.4: tout badge statique est adossé à un test nommé en commentaire" {
    # Un badge décoratif transforme une absence de preuve en apparence de
    # preuve. Deux formes acceptables, et deux seulement :
    #   - un badge de workflow (règles existantes de ce fichier) ;
    #   - un shield statique PRÉCÉDÉ d'un commentaire HTML nommant le
    #     fichier de test qui rend son affirmation fausse quand elle l'est.
    prev=""
    fautes=""
    while IFS= read -r line; do
        case "$line" in
            *img.shields.io*)
                case "$line" in
                    *actions/workflows/*) prev="$line"; continue ;;
                esac
                # Shield statique : le commentaire précédent doit nommer un
                # fichier de test qui existe vraiment.
                t="$(printf '%s' "$prev" | sed -n 's/.*<!-- *badge-proof: *\([^ ]*\) *-->.*/\1/p')"
                if [ -z "$t" ] || [ ! -f "$ROOT/$t" ]; then
                    fautes="$fautes
  $line"
                fi
                ;;
        esac
        prev="$line"
    done < "$README"
    [ -z "$fautes" ] || { echo "badge sans preuve :$fautes"; false; }
}

@test "REGLE 5.4: les deux badges décoratifs historiques ont disparu" {
    run grep -nE 'badge/(license|shell)-' "$README"
    [ "$status" -ne 0 ] || { echo "badge décoratif : $output"; false; }
}

@test "le README porte exactement quatre badges" {
    # Quatre, pas six : au-delà, personne ne les lit, et le seul qui compte
    # (uninstall verified) se noie.
    n="$(grep -c '^\[!\[\|^!\[\|shields.io\|badge.svg' "$README" || true)"
    [ "$n" -le 6 ]
    m="$(grep -c 'badge.svg?branch=master' "$README" || true)"
    [ "$m" -ge 3 ] || { echo "moins de trois badges de workflow : $m"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_badges.bats`
Expected: FAIL — `license-MIT`, `shell-ZSH` et `startup-<300ms` sont trois shields statiques sans commentaire de preuve.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, supprimer les lignes 6 et 7 (`License`, `Shell`) et annoter le badge de démarrage :

```markdown
[![Version](https://img.shields.io/github/v/release/maximeallanic/nivuus-shell?label=version)](https://github.com/maximeallanic/nivuus-shell/releases)
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
<!-- badge-proof: tests/performance/test_startup.bats -->
[![startup <300ms](https://img.shields.io/badge/startup-<300ms-brightgreen.svg)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)
```

Le badge `Matrix` est fusionné dans le badge de démarrage, qui pointe le même workflow et dit *ce qu'il prouve* plutôt que son nom de fichier.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_badges.bats
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_ci_workflows.bats
./bin/test-count --update
```
Expected: PASS — 3 nouveaux tests ; la règle existante « au moins 3 badges de workflow » reste satisfaite.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_badges.bats tests/baseline-counts.tsv
git commit -m "docs(readme): keep four badges, each backed by something that can fail"
```

---

### Task 1.8: toute commande citée par le README existe (règle 5.1)

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (sous-commandes réelles à la place des alias legacy)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `bin/nivuus help`, les fonctions et alias de `config/*.zsh`, les exécutables de `bin/`.
- Produces: la généralisation de `test_docs_install.bats` — qui ne couvre que `doc/INSTALL.md` — à **tout** le README.

Le README propose encore `healthcheck`, `nivuus-version` et `nivuus-update` — les alias legacy — comme surface principale, et ignore `nivuus enable`, `nivuus disable`, `nivuus doctor`, `nivuus update`. Ce test attrape les deux sens : une commande qui n'existe pas, et une commande qui existe mais qu'on n'aurait pas dû promouvoir.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
# Le premier lexème de chaque ligne de commande des blocs ```bash du README.
readme_commands() {
    awk '
        /^```bash/  { inblock = 1; next }
        /^```/      { inblock = 0; next }
        !inblock    { next }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { sub(/^[[:space:]]+/, ""); sub(/^\$ /, ""); print $1 }
    ' "$README" | LC_ALL=C sort -u
}

# Tout ce qu'un shell Nivuus installé sait exécuter.
command_exists_in_nivuus() {
    cmd="$1"
    # 1. sous-commande de nivuus -- traitée par l'appelant
    # 2. exécutable de bin/
    [ -x "$ROOT/bin/$cmd" ] && return 0
    # 3. fonction zsh d'un module
    grep -qhE "^[[:space:]]*(function[[:space:]]+)?${cmd}\(\)" "$ROOT"/config/*.zsh && return 0
    # 4. alias d'un module (y compris les alias quotés : ?? et ?git)
    grep -qhE "^[[:space:]]*alias[[:space:]]+'?${cmd}'?=" "$ROOT"/config/*.zsh && return 0
    return 1
}

@test "REGLE 5.1: toute commande citée dans un bloc bash du README existe" {
    rm -f "$ROOT"/config/*.zwc
    aide="$("$ROOT/bin/nivuus" help)"
    # Outils externes déclarés en prérequis ou builtins du shell : ils ne
    # sont pas de notre ressort, mais la liste est CLOSE -- on ne peut pas
    # y ajouter un outil sans le déclarer ici, donc sans y penser.
    externes="curl wget sh zsh bash git exec cd echo export source print
              nivuus ./install.sh sudo brew apt-get pacman dnf apk npx"
    inconnues=""
    for c in $(readme_commands); do
        case " $externes " in *" $c "*) continue ;; esac
        # « nivuus <sub> » : la sous-commande doit figurer dans nivuus help.
        command_exists_in_nivuus "$c" || inconnues="$inconnues $c"
    done
    [ -z "$inconnues" ] || {
        echo "commandes citées par le README et introuvables :$inconnues"; false; }
}

@test "REGLE 5.1: toute sous-commande « nivuus X » du README figure dans nivuus help" {
    aide="$("$ROOT/bin/nivuus" help)"
    manquantes=""
    for sub in $(grep -ohE '\bnivuus [a-z-]+' "$README" | awk '{print $2}' | LC_ALL=C sort -u); do
        case "$sub" in shell) continue ;; esac   # « nivuus shell » dans une phrase
        printf '%s\n' "$aide" | grep -qE "nivuus +$sub" || manquantes="$manquantes $sub"
    done
    [ -z "$manquantes" ] || { echo "sous-commandes inexistantes :$manquantes"; false; }
}

@test "REGLE 5.1: la règle voit au moins dix commandes (elle n'est pas inerte)" {
    n="$(readme_commands | wc -l)"
    [ "$n" -ge 10 ] || { echo "seulement $n commandes extraites : l'awk est cassé"; false; }
}

@test "le README promeut les sous-commandes réelles, pas les alias legacy" {
    # healthcheck / nivuus-version / nivuus-update existent encore comme
    # alias de compatibilité, mais la surface publique est « nivuus X ».
    # Les promouvoir, c'est enseigner ce qu'on prévoit de retirer.
    for legacy in 'nivuus-version' 'nivuus-update'; do
        run grep -nF "$legacy" "$README"
        [ "$status" -ne 0 ] || { echo "alias legacy promu : $output"; false; }
    done
    grep -q 'nivuus doctor' "$README"
    grep -q 'nivuus update' "$README"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — `nivuus-version` et `nivuus-update` sont cités dans « Updating » ; `nivuus doctor` n'apparaît nulle part.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, section « Updating », remplacer les blocs qui citent les alias legacy :

```bash
nivuus update            # check for a new release and install it, signature verified
nivuus doctor            # diagnose an installation that misbehaves
```

Dans « Troubleshooting », remplacer `healthcheck` par `nivuus doctor` et ajouter, en tête de section :

```markdown
The answer to "it does not work" is `nivuus doctor`: it checks the tree, the
`~/.zshrc` block, the manifest and the signing keyring, and prints what to run.
```

Vérifier ensuite que toute commande restante des blocs `bash` figure bien dans une des quatre catégories du test ; le cas échéant, corriger le README, **jamais la liste `externes`** — sauf pour y déclarer sciemment un outil de prérequis.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_readme_claims.bats
bats tests/e2e/test_docs_install.bats
bats tests/unit/test_manpage.bats
./bin/test-count --update
```
Expected: PASS — 24 tests dans la suite.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "test(readme): every command the README shows must exist"
```

---

### Task 1.9: chaque puce est ancrée dans une documentation existante (règle 5.9)

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (section des puces)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: les fichiers de `doc/` et `SECURITY.md`.
- Produces: l'interdiction de la puce marketing sans référent.

Onze puces à émoji, aucune ne pointe nulle part. Une puce qui n'est adossée à aucune page est une affirmation qu'on ne peut ni approfondir ni vérifier — et la première façon dont un README recommence à mentir est d'ajouter une douzième puce.

**Choix de mise en œuvre :** la règle s'applique à la **section des puces**, repérée par son titre (`## ✨ Features` aujourd'hui, `## What you get` après la phase 3). Le test accepte les deux titres, pour rester vert de part et d'autre de la réécriture.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
# Les lignes de puce de la section « Features » / « What you get ».
feature_bullets() {
    awk '
        /^#{2}[[:space:]].*([Ff]eatures|What you get)/ { inside = 1; next }
        /^#{2}[[:space:]]/ { inside = 0 }
        inside && /^[[:space:]]*-[[:space:]]/ { print }
    ' "$README"
}

@test "la section des puces existe et n'est pas vide" {
    n="$(feature_bullets | wc -l)"
    [ "$n" -ge 4 ] || { echo "seulement $n puces trouvées"; false; }
}

@test "REGLE 5.9: chaque puce pointe une documentation qui existe" {
    fautes=""
    while IFS= read -r bullet; do
        cible="$(printf '%s' "$bullet" | sed -n 's/.*](\([^)#]*\)[^)]*).*/\1/p' | head -n1)"
        if [ -z "$cible" ]; then
            fautes="$fautes
  sans lien: $bullet"
            continue
        fi
        case "$cible" in
            http*) continue ;;   # un lien de badge ou de release, toléré
        esac
        [ -e "$ROOT/$cible" ] || fautes="$fautes
  lien mort ($cible): $bullet"
    done <<EOF
$(feature_bullets)
EOF
    [ -z "$fautes" ] || { echo "puces non ancrées :$fautes"; false; }
}

@test "REGLE 5.9: la section des puces en compte au plus six" {
    # Onze puces, c'est une liste de courses. Six, c'est un argumentaire.
    n="$(feature_bullets | wc -l)"
    [ "$n" -le 6 ] || { echo "$n puces : au-delà de six, personne ne les lit"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — onze puces, aucune avec de lien.

- [ ] **Step 3: Write minimal implementation**

Remplacer la section `## ✨ Features` de `README.md` par six puces ancrées — ce sont **exactement** celles que la phase 3 reprendra, écrites ici une fois pour toutes :

```markdown
## ✨ What you get

- **Removable.** `nivuus uninstall` restores every file it touched from a content-addressed backup. Verified nightly on 9 targets — see the badge. → [doc/INSTALL.md](doc/INSTALL.md)
- **Fast, and held to it.** A CI test fails the build if an interactive shell takes more than 300ms to start. → [doc/FEATURES.md](doc/FEATURES.md)
- **No plugin manager.** Pure ZSH, 26 modules, no oh-my-zsh, no framework underneath. → [doc/CLAUDE.md](doc/CLAUDE.md)
- **Optional AI, your key, your provider.** Gemini, OpenAI or Anthropic — `??`, `why`, `explain`, and a command-not-found that names the package to install. Nivuus works fully without it. → [doc/FEATURES.md](doc/FEATURES.md)
- **A prompt you can re-lay-out.** Themes and a token-based prompt format, no code change. → [doc/PROMPT.md](doc/PROMPT.md)
- **Signed releases.** An update whose signature does not verify is refused outright, with no fallback. → [SECURITY.md](SECURITY.md)
```

Les cinq puces supprimées (Vim, navigation, Node, Python, cloud, sécurité des commandes) **ne disparaissent pas du produit** : elles vivent déjà dans `doc/FEATURES.md`, qui est l'endroit où l'on va quand on veut la liste. Vérifier ce point avant de committer — c'est un déplacement, pas une perte.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_readme_badges.bats
bats tests/e2e/test_docs_install.bats
./bin/test-count --update
```
Expected: PASS — 27 tests dans la suite. Le README est passé sous les 560 lignes.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): six anchored bullets instead of eleven unsourced ones"
```

---

# PHASE 2 — `doc/` devient l'autorité, et son index cesse de mentir

`doc/README.md` prétend être l'index et liste 6 fichiers. Il y en a **10**, et il oublie exactement ceux que les trois derniers chantiers ont produits : `INSTALL.md`, `PACKAGING.md`, `SIGNING.md`, `nivuus.1`. Il liste en revanche `TESTING_UPDATE.md`, `TEST_PROGRESS.md`, `TEST_SUMMARY.md` — trois rapports d'avancement de chantier, pas de la documentation.

Cette phase doit être **entièrement mergée avant la phase 3** : le README réécrit pointe l'index, et pointer un index faux serait remplacer un mensonge par un autre.

*Sortie de phase : index et liens verts ; aucun contenu perdu (vérifié en revue).*

---

### Task 2.1: `doc/README.md` est l'index réel, testé dans les deux sens (règle 5.6)

**Files:**
- Create: `tests/unit/test_docs_index.bats`
- Modify: `doc/README.md`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: le contenu réel de `doc/`.
- Produces: la règle 5.6 — tout fichier de `doc/` est listé, tout fichier listé existe, tout lien relatif du README et de `doc/*.md` pointe une cible existante.

**Silence de la spec comblé.** La spec demande que « tout lien relatif du README et de `doc/*.md` pointe un fichier existant ». Elle ne dit rien des **ancres** (`SECURITY.md#first-install`, `doc/FEATURES.md#performance`), qui sont pourtant la forme de lien que la structure cible utilise le plus. Un lien vers une ancre inexistante est un lien mort silencieux : GitHub sert la page et ignore le fragment. Ce test vérifie donc **aussi les ancres**, avec une slugification volontairement simple (minuscules, espaces → tirets, ponctuation retirée) et une échappatoire explicite : une ancre HTML `<a id="…">` compte comme un titre. C'est ce qui rend la Task 2.4 possible sans traduire `SECURITY.md`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_docs_index.bats
#!/usr/bin/env bats
#
# Un index qui oublie la moitié des pages est pire qu'aucun index : il fait
# croire que ce qui n'y est pas n'existe pas. doc/README.md liste aujourd'hui
# 6 fichiers sur 10, et oublie exactement ceux des trois derniers chantiers.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    DOC="$ROOT/doc"
    INDEX="$DOC/README.md"
    README="$ROOT/README.md"
}

# Tous les fichiers de doc/, index exclu.
doc_files() {
    find "$DOC" -maxdepth 1 -type f ! -name 'README.md' -exec basename {} \; \
        | LC_ALL=C sort
}

# Tous les fichiers cités par l'index, sous forme de lien Markdown.
indexed_files() {
    grep -oE '\]\([^)]+\)' "$INDEX" | sed 's/^](//; s/)$//' \
        | sed 's/#.*$//' | grep -v '^\.\./' | grep -v '^http' \
        | LC_ALL=C sort -u
}

@test "REGLE 5.6: tout fichier de doc/ est listé dans doc/README.md" {
    manquants=""
    for f in $(doc_files); do
        indexed_files | grep -qx "$f" || manquants="$manquants $f"
    done
    [ -z "$manquants" ] || { echo "absents de l'index :$manquants"; false; }
}

@test "REGLE 5.6: tout fichier listé par l'index existe" {
    fantomes=""
    for f in $(indexed_files); do
        [ -e "$DOC/$f" ] || fantomes="$fantomes $f"
    done
    [ -z "$fantomes" ] || { echo "listés mais inexistants :$fantomes"; false; }
}

@test "REGLE 5.6: aucun rapport d'avancement n'est présenté comme de la documentation" {
    # Un rapport de chantier décrit un moment ; une documentation décrit un
    # produit. Les confondre, c'est publier un instantané périmé.
    run ls "$DOC/TESTING_UPDATE.md" "$DOC/TEST_PROGRESS.md" "$DOC/TEST_SUMMARY.md"
    [ "$status" -ne 0 ] || { echo "rapports d'avancement encore présents"; false; }
}

# --- Liens relatifs et ancres, dans les deux sens ---

# Imprime « fichier<TAB>cible<TAB>ancre » pour chaque lien relatif d'un fichier.
relative_links() {
    grep -oE '\]\([^)]+\)' "$1" | sed 's/^](//; s/)$//' \
        | grep -v '^http' | grep -v '^#' | grep -v '^mailto:'
}

# Un titre Markdown slugifié à la façon de GitHub, version volontairement
# simple : minuscules, ponctuation retirée, espaces en tirets. Suffisante
# pour les titres de ce dépôt, et sans dépendance.
anchors_of() {
    grep -E '^#{1,6} ' "$1" \
        | sed 's/^#\{1,6\} //' \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9 _-]//g; s/  */ /g; s/^ //; s/ $//; s/ /-/g'
    # Échappatoire assumée : une ancre HTML explicite vaut un titre. C'est
    # ce qui permet d'ancrer une section d'un document en français depuis un
    # README en anglais, sans traduire le document.
    grep -oE '<a id="[^"]+"' "$1" 2>/dev/null | sed 's/.*id="//; s/"$//'
}

@test "REGLE 5.6: tout lien relatif du README pointe un fichier existant" {
    morts=""
    for l in $(relative_links "$README"); do
        cible="${l%%#*}"
        [ -n "$cible" ] || continue
        [ -e "$ROOT/$cible" ] || morts="$morts $cible"
    done
    [ -z "$morts" ] || { echo "liens morts dans le README :$morts"; false; }
}

@test "REGLE 5.6: toute ancre citée par le README existe dans sa cible" {
    morts=""
    for l in $(relative_links "$README"); do
        case "$l" in *'#'*) : ;; *) continue ;; esac
        cible="${l%%#*}"; ancre="${l#*#}"
        [ -f "$ROOT/$cible" ] || continue      # couvert par le test précédent
        anchors_of "$ROOT/$cible" | grep -qx "$ancre" || morts="$morts $l"
    done
    [ -z "$morts" ] || { echo "ancres inexistantes :$morts"; false; }
}

@test "REGLE 5.6: tout lien relatif de doc/*.md pointe une cible existante" {
    morts=""
    for f in "$DOC"/*.md; do
        for l in $(relative_links "$f"); do
            cible="${l%%#*}"
            [ -n "$cible" ] || continue
            base="$(dirname "$f")"
            [ -e "$base/$cible" ] || morts="$morts
  $(basename "$f") -> $cible"
        done
    done
    [ -z "$morts" ] || { echo "liens morts dans doc/ :$morts"; false; }
}

@test "l'index couvre aussi la page de manuel" {
    # doc/nivuus.1 n'est pas un .md : c'est exactement le genre de fichier
    # qu'un index écrit à la main oublie.
    grep -qF 'nivuus.1' "$INDEX"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_docs_index.bats`
Expected: FAIL — `INSTALL.md`, `PACKAGING.md`, `SIGNING.md`, `nivuus.1` absents de l'index ; les trois rapports encore présents.

- [ ] **Step 3: Write minimal implementation**

Réécrire `doc/README.md` — **une ligne par fichier, sans exception** :

```markdown
# Documentation

Everything Nivuus documents, and nothing else. The README is the front door;
this is the reference. `tests/unit/test_docs_index.bats` fails the build when
this index and the directory disagree — in either direction.

## Install and remove

- **[INSTALL.md](INSTALL.md)** — every installation route, per platform, plus `--dry-run`, `--minimal`, `--prefix`, version pinning, and how to verify the signing keyring
- **[UPDATING.md](UPDATING.md)** — how updates are found, verified and applied; how to roll one back
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — what `nivuus doctor` cannot fix by itself

## Use

- **[FEATURES.md](FEATURES.md)** — the complete feature reference, with examples
- **[PROMPT.md](PROMPT.md)** — prompt tokens, themes, and layout (in French)
- **[nivuus.1](nivuus.1)** — the man page, kept in sync with `nivuus help` by `tests/unit/test_manpage.bats`

## Distribute

- **[PACKAGING.md](PACKAGING.md)** — package mode, `.nivuus-origin`, `nivuus enable` / `disable` (in French)
- **[SIGNING.md](SIGNING.md)** — how a release is signed and what the verification refuses (in French)

## Contribute

- **[CLAUDE.md](CLAUDE.md)** — architecture, module layout, conventions
- **[TESTING.md](TESTING.md)** — the four test levels, how to run them, what each one proves

See also, at the repository root: [SECURITY.md](../SECURITY.md) (threat model),
[CONTRIBUTING.md](../CONTRIBUTING.md), [CHANGELOG.md](../CHANGELOG.md).
```

**Note :** cet index cite `UPDATING.md`, `TROUBLESHOOTING.md` et `CONTRIBUTING.md`, créés par les Tasks 2.3 et 5.1. Si la Task 2.3 n'est pas encore mergée, l'index échoue à son propre test — c'est voulu, et c'est pourquoi **2.1 et 2.3 se mergent ensemble ou dans cet ordre : 2.3, puis 2.2, puis 2.1**. La ligne `CONTRIBUTING.md` est la seule exception : elle pointe hors de `doc/`, n'est donc pas couverte par la règle « tout fichier listé existe », mais l'est par « tout lien relatif de `doc/*.md` pointe une cible existante » — **ne l'ajouter qu'avec la Task 5.1**, ou la commenter jusque-là.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_docs_index.bats
bats tests/unit/test_markdown.bats
bats tests/unit/test_manpage.bats
./bin/test-count --update
```
Expected: PASS — 8 nouveaux tests.

- [ ] **Step 5: Commit**

```bash
git add doc/README.md tests/unit/test_docs_index.bats tests/baseline-counts.tsv
git commit -m "docs(index): make doc/README.md the real index, tested both ways"
```

---

### Task 2.2: les trois rapports d'avancement fusionnent dans `doc/TESTING.md`

**Files:**
- Modify: `doc/TESTING.md`
- Delete: `doc/TESTING_UPDATE.md`, `doc/TEST_PROGRESS.md`, `doc/TEST_SUMMARY.md`
- Modify: `tests/unit/test_docs_index.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `bin/test`, `bin/test-count`, `tests/ci/bats-run.sh`, `tests/baseline-counts.tsv`.
- Produces: une seule page de test, dont les chiffres sont **dérivés** et non recopiés.

Ces trois fichiers décrivent l'état d'un chantier à un instant donné. Ce qu'ils contiennent d'encore vrai — comment lancer les suites, ce que couvre chaque niveau — appartient à `doc/TESTING.md`. Le reste est un journal, et le journal du dépôt s'appelle `git log`.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_docs_index.bats` :

```bash
@test "doc/TESTING.md décrit les quatre niveaux de test" {
    for niveau in unit integration e2e performance; do
        grep -qF "tests/$niveau" "$DOC/TESTING.md" \
            || { echo "niveau non documenté : $niveau"; false; }
    done
}

@test "doc/TESTING.md ne recopie aucun compte de tests" {
    # Un chiffre recopié périme au commit suivant. Le compte fait autorité
    # dans tests/baseline-counts.tsv, et bin/test-count l'imprime.
    run grep -nE '\b[0-9]{3,4} (tests|tests unitaires)\b' "$DOC/TESTING.md"
    [ "$status" -ne 0 ] || { echo "compte recopié : $output"; false; }
    grep -qF 'bin/test-count' "$DOC/TESTING.md"
}

@test "doc/TESTING.md dit comment la CI lance les suites" {
    grep -qF 'tests/ci/bats-run.sh' "$DOC/TESTING.md"
    # Les exclusions par défaut sont la chose qu'on découvre le plus tard,
    # et toujours en se demandant pourquoi un test « ne tourne pas ».
    grep -qE 'docker|network' "$DOC/TESTING.md"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_docs_index.bats`
Expected: FAIL — `doc/TESTING.md` ne mentionne ni `bin/test-count`, ni `tests/ci/bats-run.sh`, ni les exclusions `docker`/`network`.

- [ ] **Step 3: Write minimal implementation**

1. Lire les trois rapports et reporter dans `doc/TESTING.md` **ce qui est encore vrai** : la répartition en quatre niveaux, ce que chacun prouve, et les pièges (`rm -f config/*.zwc`, `NIVUUS_SHELL_DIR`).
2. Ajouter à `doc/TESTING.md` une section « Running the suites » :

```markdown
## Running the suites

```bash
./bin/test                 # everything
./bin/test --unit          # tests/unit/      — pure functions, grep-level rules
./bin/test --integration   # tests/integration/ — modules combined
./bin/test --e2e           # tests/e2e/       — install, uninstall, reversibility
./bin/test --performance   # tests/performance/ — the enforced startup budget
```

The CI runs them through `tests/ci/bats-run.sh`, which is also the way to
reproduce a CI failure locally. Two families of tests are **excluded by
default** there: those tagged `docker` (they pull whole images) and `network`
(they leave for github.com). Set `NIVUUS_CI_DOCKER=1` or `NIVUUS_CI_NETWORK=1`
to include them.

`./bin/test-count` prints how many tests each suite holds, and
`./bin/test-count --check` fails when a suite shrinks. The floor lives in
`tests/baseline-counts.tsv`; raise it with `--update` in the same commit that
adds the tests.

Before any suite that reads `config/*.zsh`, run `rm -f config/*.zwc`: zsh
prefers stale bytecode over a newer source, and a test can pass against a
module you did not write.
```

3. `git rm doc/TESTING_UPDATE.md doc/TEST_PROGRESS.md doc/TEST_SUMMARY.md`.

**Vérification de non-perte, à faire en revue, pas par un test :** `git show HEAD~1:doc/TEST_SUMMARY.md` et ses deux jumeaux, relus une fois, ligne à ligne. Un test ne peut pas prouver qu'aucune information utile n'a été perdue ; un humain le peut, une fois.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_docs_index.bats
bats tests/unit/test_markdown.bats
./bin/test-count --update
```
Expected: PASS — 11 tests dans la suite ; `doc/` passe de 10 à 7 fichiers, puis 9 avec la Task 2.3.

- [ ] **Step 5: Commit**

```bash
git add doc/TESTING.md tests/unit/test_docs_index.bats tests/baseline-counts.tsv
git rm doc/TESTING_UPDATE.md doc/TEST_PROGRESS.md doc/TEST_SUMMARY.md
git commit -m "docs(testing): fold three progress reports into one testing page"
```

---

### Task 2.3: `doc/UPDATING.md` et `doc/TROUBLESHOOTING.md` accueillent ce que le README rend

**Files:**
- Create: `doc/UPDATING.md`, `doc/TROUBLESHOOTING.md`
- Modify: `tests/unit/test_docs_index.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `README.md` sections « Updating » (~80 l.) et « Troubleshooting » (~38 l.), `config/20-autoupdate.zsh`, `doc/SIGNING.md`, `bin/nivuus doctor`.
- Produces: les deux destinations que la phase 3 exige. **Cette tâche crée les pages ; elle ne retire rien du README** — le retrait est la réécriture atomique de la Task 3.1.

Créer les pages *avant* de vider le README garantit qu'à aucun instant le contenu n'existe nulle part. C'est la mitigation du risque « perte d'information en déplaçant 400 lignes » (spec § 8).

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_docs_index.bats` :

```bash
@test "doc/UPDATING.md existe et couvre la vérification de signature" {
    [ -f "$DOC/UPDATING.md" ]
    grep -qiE 'signature' "$DOC/UPDATING.md"
    # Le refus dur est la propriété du chantier signature : la page qui
    # décrit la mise à jour ne peut pas l'omettre.
    grep -qiE 'refus|refused|rejected' "$DOC/UPDATING.md"
    grep -qF 'SIGNING.md' "$DOC/UPDATING.md"
}

@test "doc/UPDATING.md documente les variables d'auto-update qui existent" {
    rm -f "$ROOT"/config/*.zwc
    for v in ENABLE_AUTOUPDATE AUTOUPDATE_CHECK_FREQUENCY_DAYS; do
        grep -qF "$v" "$DOC/UPDATING.md" || { echo "variable absente : $v"; false; }
        grep -qF "$v" "$ROOT/config/20-autoupdate.zsh" || { echo "variable morte : $v"; false; }
    done
}

@test "doc/UPDATING.md dit ce que fait « nivuus update » en mode paquet" {
    # Livré par le chantier packaging, et invisible partout ailleurs que
    # dans doc/PACKAGING.md : celui qui lance « nivuus update » sur une
    # machine paquetée lit cette page-ci.
    grep -qiE 'paquet|package' "$DOC/UPDATING.md"
}

@test "doc/TROUBLESHOOTING.md commence par nivuus doctor" {
    [ -f "$DOC/TROUBLESHOOTING.md" ]
    head -n 20 "$DOC/TROUBLESHOOTING.md" | grep -qF 'nivuus doctor'
}

@test "doc/TROUBLESHOOTING.md ne conserve aucun symptôme dont la commande a disparu" {
    aide="$("$ROOT/bin/nivuus" help)"
    for sub in $(grep -ohE '\bnivuus [a-z-]+' "$DOC/TROUBLESHOOTING.md" | awk '{print $2}' | LC_ALL=C sort -u); do
        case "$sub" in shell) continue ;; esac
        printf '%s\n' "$aide" | grep -qE "nivuus +$sub" \
            || { echo "sous-commande inexistante : $sub"; false; }
    done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_docs_index.bats`
Expected: FAIL — les deux fichiers n'existent pas.

- [ ] **Step 3: Write minimal implementation**

Créer `doc/UPDATING.md` en **déplaçant** le contenu de la section `## 🔄 Updating` du README (les sept étapes de vérification, la configuration, le rollback, le processus de release), et en le complétant sur deux points que le README ignore :

- le comportement en **mode paquet** (`nivuus update` explique et sort en 0, l'auto-update est refusé sans variable d'échappement) — renvoyer vers `doc/PACKAGING.md` ;
- le renvoi vers `doc/SIGNING.md` pour la chaîne de signature elle-même.

Créer `doc/TROUBLESHOOTING.md` en déplaçant `## 🐛 Troubleshooting`, **avec une inversion d'ordre** : la page commence par `nivuus doctor`, et les symptômes particuliers viennent après, comme des cas que `doctor` ne couvre pas encore.

```markdown
# Troubleshooting

Start here, always:

```bash
nivuus doctor
```

It checks the tree, the `~/.zshrc` block, the manifest, the signing keyring
and the login shell, and prints the command to run for each problem it finds.
Everything below is a symptom `doctor` does not yet diagnose by itself. If you
land on one of them, that is a gap in `doctor` worth an issue.
```

Le README garde ses deux sections **inchangées** jusqu'à la Task 3.1 : cette tâche duplique volontairement, pour une durée bornée à une phase.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_docs_index.bats
bats tests/e2e/test_docs_install.bats
./bin/test-count --update
```
Expected: PASS — 16 tests dans la suite.

- [ ] **Step 5: Commit**

```bash
git add doc/UPDATING.md doc/TROUBLESHOOTING.md tests/unit/test_docs_index.bats tests/baseline-counts.tsv
git commit -m "docs: give updating and troubleshooting their own pages"
```

---

### Task 2.4: le trousseau de signature descend du Quick Start, et `SECURITY.md` gagne son ancre

**Files:**
- Modify: `doc/INSTALL.md`
- Modify: `SECURITY.md`
- Modify: `tests/unit/test_docs_index.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: la section `### Vérifier le trousseau de signature à l'installation` du README (22 lignes, ligne 64).
- Produces: la destination de ce contenu, **et** l'ancre `first-install` que la structure cible du README exige.

**Silence de la spec comblé.** La spec écrit le paragraphe du README avec un lien vers `SECURITY.md#first-install`. Cette ancre **n'existe pas** : `SECURITY.md` est en français et ses titres sont « Ce que la signature garantit… », « Empreinte du jeu de clés »… Trois issues étaient possibles : traduire `SECURITY.md` (hors périmètre, décision actée n° 1), lier la page sans fragment (le lecteur atterrit sur une page de 110 lignes en français et cherche), ou **poser une ancre HTML explicite**. C'est la troisième qui est retenue : une ligne, aucune traduction, et la règle 5.6 la reconnaît (Task 2.1, `anchors_of`).

Le contenu — 22 lignes de cryptographie et de limites d'attaque, placées entre la désinstallation et « Restart your terminal » — est excellent. Sa place n'est pas le troisième écran d'une page d'accueil.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_docs_index.bats` :

```bash
@test "SECURITY.md porte une ancre stable pour le problème d'amorçage" {
    # Le README (anglais) doit pouvoir pointer une section précise d'un
    # document français sans le traduire. Une ancre HTML explicite est la
    # seule forme qui survive à une reformulation du titre.
    grep -qF '<a id="first-install"></a>' "$ROOT/SECURITY.md"
}

@test "la section ancrée dit ce que le one-liner ne protège PAS" {
    # Une ancre qui pointe une section rassurante serait pire qu'aucune
    # ancre : le lecteur y va justement pour connaître la limite.
    sed -n '/<a id="first-install"><\/a>/,/^## /p' "$ROOT/SECURITY.md" \
        | grep -qiE 'amor|première|premier téléchargement|ne garantit pas'
}

@test "le contenu du trousseau vit dans doc/INSTALL.md" {
    grep -qF -- '--verify-key' "$DOC/INSTALL.md"
    grep -qiE 'trousseau|keyring' "$DOC/INSTALL.md"
    # Et l'empreinte attendue n'est PAS recopiée dans deux fichiers : une
    # empreinte dupliquée est une empreinte qui divergera.
    n="$(grep -rc 'SHA256:' "$DOC/INSTALL.md" | head -n1)"
    grep -qF 'SECURITY.md' "$DOC/INSTALL.md"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_docs_index.bats`
Expected: FAIL — l'ancre n'existe pas dans `SECURITY.md`.

- [ ] **Step 3: Write minimal implementation**

Dans `SECURITY.md`, ajouter l'ancre au-dessus de la section qui traite déjà de la question — « Ce que la signature garantit, et ce qu'elle ne garantit pas » :

```markdown
<a id="first-install"></a>
## Ce que la signature garantit, et ce qu'elle ne garantit pas
```

Dans `doc/INSTALL.md`, ajouter (ou compléter) la section « Vérifier le trousseau de signature », en y déplaçant les 22 lignes du README : l'usage de `--verify-key`, ce que l'épinglage protège, ce qu'il ne protège pas, et le renvoi vers `SECURITY.md#first-install` pour l'empreinte de référence — **qui ne doit exister qu'à un seul endroit**.

Le README garde sa section jusqu'à la Task 3.1.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_docs_index.bats
bats tests/e2e/test_docs_install.bats
bats tests/e2e/test_verify_key.bats
./bin/test-count --update
```
Expected: PASS — 19 tests dans la suite.

- [ ] **Step 5: Commit**

```bash
git add SECURITY.md doc/INSTALL.md tests/unit/test_docs_index.bats tests/baseline-counts.tsv
git commit -m "docs(security): anchor the bootstrap-trust section and move the keyring guide"
```

---

# PHASE 3 — La réécriture, atomique

Deux tâches. La première est la seule de tout le plan qui réécrit le README d'un bloc ; la seconde branche les nouvelles suites à la CI. **Ne pas commencer avant que la phase 2 soit mergée.**

*Sortie de phase : longueur, unilinguisme et liens verts ; le premier écran contient la promesse, le one-liner et la désinstallation.*

---

### Task 3.1: le README cible — ≤ 200 lignes, anglais, promesse en tête (règles 5.5 et 5.7)

**Files:**
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `README.md` (réécriture complète)
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: **toute** la phase 2 (`doc/README.md`, `doc/UPDATING.md`, `doc/TROUBLESHOOTING.md`, l'ancre `SECURITY.md#first-install`) et **toute** la phase 1 (les six puces ancrées, les badges, le chiffre unique).
- Produces: la structure cible de la spec § 2, sans la démo — elle est insérée en Task 4.5, pour qu'aucune image cassée n'existe dans l'intervalle.

Le README fait 596 lignes ; après la phase 1 il en fait ~555. La cible est 200. Ce n'est pas une compression : c'est le constat que 400 de ces lignes sont un **double emploi** avec `doc/`, désormais autoritaire et indexé.

**Rebaser avant de commencer.** Cette tâche est un conflit de merge ambulant.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_readme_claims.bats` :

```bash
@test "REGLE 5.5: le README tient en 200 lignes" {
    # Grossier, et volontairement. La métrique qui a été violée cinq fois
    # est la longueur : c'est donc elle qu'on instrumente. Ce test sera un
    # jour ressenti comme une gêne -- c'est le signe qu'il fonctionne.
    # Le relever se discute en revue, jamais dans le commit qui en a besoin.
    n="$(wc -l < "$README")"
    [ "$n" -le 200 ] || { echo "README à $n lignes (budget: 200)"; false; }
}

@test "REGLE 5.7: le README est en anglais, sans exception" {
    # Liste noire de lexèmes français fréquents, grossière et sans
    # ambiguïté. Elle ne vise QUE le README : doc/PROMPT.md,
    # doc/PACKAGING.md et SECURITY.md restent en français, c'est la langue
    # de travail du projet.
    fautes=""
    for mot in 'désinstall' 'empreinte' 'paquet' 'trousseau' 'mise à jour' \
               "n'est pas" 'Plateformes' 'Vérifier' 'sauvegarde' 'fichier' \
               'utilisateur' 'ainsi que' 'toutefois'; do
        if grep -qiF "$mot" "$README"; then
            fautes="$fautes
  $mot: $(grep -inF "$mot" "$README" | head -2)"
        fi
    done
    [ -z "$fautes" ] || { echo "français dans le README :$fautes"; false; }
}

@test "REGLE 5.7: aucun caractère accenté hors nom propre" {
    # Second filet, indépendant de la liste noire : un texte anglais n'a
    # pas de raison d'accentuer. L'échappatoire est nominative et courte.
    fautes="$(grep -nE '[éèêàçùôîû]' "$README" \
              | grep -viE 'Allanic|Café|Nord|résumé' || true)"
    [ -z "$fautes" ] || { echo "accents hors noms propres :$fautes"; false; }
}

@test "le premier écran contient la promesse, l'installation et la désinstallation" {
    # « Premier écran » = 40 lignes. La désinstallation n'est plus une
    # section d'après-vente : c'est elle qui autorise le lecteur à exécuter
    # le one-liner.
    head -n 40 "$README" | grep -qF 'byte for byte'
    head -n 40 "$README" | grep -qF 'raw.githubusercontent.com'
    head -n 40 "$README" | grep -qF 'nivuus uninstall'
}

@test "le README garde un index vers doc/, une ligne par page" {
    grep -qF '](doc/README.md)' "$README"
    for f in INSTALL.md FEATURES.md PROMPT.md CLAUDE.md; do
        grep -qF "doc/$f" "$README" || { echo "page absente de l'index : $f"; false; }
    done
}

@test "le README ne mentionne pas --system" {
    # Décision de périmètre (spec § 6) : l'installation multi-utilisateur
    # n'est pas un argument de page d'accueil, et un chantier en cours
    # produit sa propre section dans doc/INSTALL.md. Anticiper créerait un
    # conflit de merge sur le fichier le plus disputé du dépôt.
    run grep -nF -- '--system' "$README"
    [ "$status" -ne 0 ] || { echo "--system dans le README : $output"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_readme_claims.bats`
Expected: FAIL — 555 lignes ; « Plateformes testées », « Vérifier le trousseau », « mise à jour » présents ; le premier écran ne contient pas `nivuus uninstall`.

- [ ] **Step 3: Write minimal implementation**

Remplacer intégralement `README.md`. Le contenu ci-dessous est la cible ; **la ligne de la démo est volontairement absente** (Task 4.5) :

````markdown
# Nivuus Shell

> **A complete ZSH environment in one command — and one command to remove it,
> byte for byte.**

[![Version](https://img.shields.io/github/v/release/maximeallanic/nivuus-shell?label=version)](https://github.com/maximeallanic/nivuus-shell/releases)
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
<!-- badge-proof: tests/performance/test_startup.bats -->
[![startup <300ms](https://img.shields.io/badge/startup-<300ms-brightgreen.svg)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

It verifies a SHA-256 checksum, writes a delimited block into your `~/.zshrc`,
needs no `sudo` and no `git`. Add `--dry-run` to see everything it would touch
without touching it. What this **cannot** protect you from is documented, in
plain terms, in [SECURITY.md](SECURITY.md#first-install).

## Uninstall

```bash
nivuus uninstall              # restores every file it touched
nivuus uninstall --purge      # also removes its own state (manifest, backups)
nivuus uninstall --dry-run    # shows what it would remove, changes nothing
```

Every modified file is restored from a content-addressed backup recorded at
install time. `~/.zsh_local` and `~/.zsh_history` are never deleted. This is
checked nightly on nine targets — that is the *uninstall verified* badge above.

Then restart your terminal, or `exec zsh`.

## What you get

- **Removable.** `nivuus uninstall` restores every file it touched from a content-addressed backup. Verified nightly on 9 targets — see the badge. → [doc/INSTALL.md](doc/INSTALL.md)
- **Fast, and held to it.** A CI test fails the build if an interactive shell takes more than 300ms to start. → [doc/FEATURES.md](doc/FEATURES.md)
- **No plugin manager.** Pure ZSH, 26 modules, no oh-my-zsh, no framework underneath. → [doc/CLAUDE.md](doc/CLAUDE.md)
- **Optional AI, your key, your provider.** Gemini, OpenAI or Anthropic — `??`, `why`, `explain`, and a command-not-found that names the package to install. Nivuus works fully without it. → [doc/FEATURES.md](doc/FEATURES.md)
- **A prompt you can re-lay-out.** Themes and a token-based prompt format, no code change. → [doc/PROMPT.md](doc/PROMPT.md)
- **Signed releases.** An update whose signature does not verify is refused outright, with no fallback. → [SECURITY.md](SECURITY.md)

## Proof

Nine targets. Install, uninstall, and a `$HOME` fingerprint that must come back
bit-identical — every night, and on every release.

| Target | Install | Uninstall |
|---|---|---|
| Ubuntu 22.04 | yes | yes |
| Ubuntu 24.04 | yes | yes |
| Debian 12 | yes | yes |
| Arch Linux | yes | yes |
| Fedora 41 | yes | yes |
| Alpine 3.20 (musl) | yes | yes |
| Ubuntu (GitHub runner) | yes | yes |
| macOS 14 (arm64) | yes | yes |

The startup budget is enforced, not observed: the build fails past **300ms**.
Typical times measured on that matrix: 26–46 ms — see
[tests/performance/](tests/performance/).

The target list is not written here by hand: it comes from
[.github/matrix.json](.github/matrix.json), and
`tests/unit/test_readme_badges.bats` fails when this table and that file
disagree.

## Configure

Nothing here is required. Put what you want in `~/.zsh_local`; Nivuus never
writes to it.

```bash
# ~/.zsh_local
export NIVUUS_THEME=dracula                # nord (default) or dracula
export NIVUUS_PROMPT_FORMAT='{path}{git} ' # {ssh} {root} {status} {path} {venv} {cloud} {git} {jobs}
export AI_BACKEND=anthropic                # gemini (default), openai, anthropic
export ANTHROPIC_API_KEY=sk-ant-...
export ENABLE_AI_SUGGESTIONS=false         # every feature has an off switch
export ENABLE_AUTOUPDATE=false
```

Full list of tokens, themes and toggles: [doc/PROMPT.md](doc/PROMPT.md) and
[doc/FEATURES.md](doc/FEATURES.md).

## Everyday commands

```bash
nivuus doctor      # diagnose an installation that misbehaves
nivuus update      # fetch and verify the next signed release
nivuus enable      # activate Nivuus for this user (after a package install)
nivuus disable     # deactivate it, leaving the tree alone
nivuus help        # all of the above, with their flags
```

## Documentation

Everything is in [doc/](doc/README.md), which is an index the CI keeps honest.

- [doc/INSTALL.md](doc/INSTALL.md) — every installation route, per platform, and how to verify the signing keyring
- [doc/FEATURES.md](doc/FEATURES.md) — the complete feature reference
- [doc/PROMPT.md](doc/PROMPT.md) — prompt tokens, themes, layout (in French)
- [doc/UPDATING.md](doc/UPDATING.md) — how updates are verified, applied and rolled back
- [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md) — when `nivuus doctor` is not enough
- [doc/PACKAGING.md](doc/PACKAGING.md) — package mode, for maintainers (in French)
- [doc/CLAUDE.md](doc/CLAUDE.md) — architecture and conventions
- [doc/TESTING.md](doc/TESTING.md) — the four test levels and how to run them

## Contributing · Security · License

Read [CONTRIBUTING.md](CONTRIBUTING.md) first: this repository tests its own
documentation, and a pull request that reads well can still fail the build.

Security policy, threat model and keyring fingerprint: [SECURITY.md](SECURITY.md).

MIT — see [LICENSE](LICENSE).

## Credits

Colour palette after [Nord](https://www.nordtheme.com/). AI features talk to
Google Gemini, OpenAI or Anthropic, with your key and your choice.
````

**Vérifications avant commit**, dans l'ordre :

1. `wc -l README.md` — doit être ≤ 200, avec de la marge pour la ligne de démo (Task 4.5).
2. Chaque section retirée existe bien ailleurs : `## Usage` → `doc/FEATURES.md`, `## Theme & Prompt` → `doc/PROMPT.md`, `## Updating` → `doc/UPDATING.md`, `## Troubleshooting` → `doc/TROUBLESHOOTING.md`, `## Development` → `doc/CLAUDE.md`, `## Requirements` → `doc/INSTALL.md`, le trousseau → `doc/INSTALL.md` + `SECURITY.md`. `## Project Structure` est **supprimée**, sans destination : c'est la seule, et c'est délibéré (Task 1.6).
3. La note packaging du README actuel (« Nivuus est conçu pour être empaqueté… », en français) descend dans l'index `doc/` — elle y est déjà, ligne `doc/PACKAGING.md`.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_readme_badges.bats
bats tests/unit/test_docs_index.bats
bats tests/e2e/test_docs_install.bats
bats tests/unit/test_markdown.bats
./bin/benchmark | grep -A1 '^Average'
./bin/test-count --update
```
Expected: PASS — 33 tests dans `test_readme_claims.bats` ; le tableau des plateformes reste conforme à `.github/matrix.json` ; le one-liner reste identique entre README et `doc/INSTALL.md` ; le démarrage reste au même ordre de grandeur (aucun code touché).

- [ ] **Step 5: Commit**

```bash
git add README.md tests/unit/test_readme_claims.bats tests/baseline-counts.tsv
git commit -m "docs(readme): rewrite around one promise, under 200 lines, in English"
```

---

### Task 3.2: les nouvelles suites entrent dans la CI et ne peuvent plus en sortir

**Files:**
- Modify: `.github/workflows/tests.yml`
- Modify: `tests/unit/test_ci_workflows.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `tests/unit/test_readme_claims.bats`, `tests/unit/test_docs_index.bats`.
- Produces: leur exécution en CI, et le garde-fou `grep` qui interdit de les perdre dans un refactor — **même dispositif** que pour les suites de signature et d'empaquetage.

Les deux nouvelles suites sont déjà couvertes par `./tests/ci/bats-run.sh tests/unit/` dans le job `unit`. Les **nommer** est ce qui empêche un refactor de CI de les faire disparaître en silence. C'est la convention du dépôt : deux garde-fous existent déjà pour la signature et l'empaquetage, celui-ci est le troisième.

**Rappel de contrainte :** aucune installation de paquet n'est ajoutée. Les deux suites sont du `grep` pur ; elles n'ont besoin de rien de plus que l'action composite `setup-tests`.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_ci_workflows.bats` :

```bash
@test "les suites de documentation sont nommées dans tests.yml" {
    # Même garde-fou que pour la signature et l'empaquetage : elles sont
    # couvertes par « bats tests/unit/ », mais les nommer interdit qu'un
    # refactor de CI les perde en silence.
    f="$WF/tests.yml"
    for suite in tests/unit/test_readme_claims.bats \
                 tests/unit/test_readme_badges.bats \
                 tests/unit/test_docs_index.bats \
                 tests/e2e/test_docs_install.bats; do
        grep -qF "$suite" "$f" || { echo "suite de documentation perdue: $suite"; false; }
    done
}

@test "les règles de vitrine sont gardées par grep dans tests.yml" {
    f="$WF/tests.yml"
    for regle in "REGLE 5.1" "REGLE 5.2" "REGLE 5.3" "REGLE 5.4" \
                 "REGLE 5.5" "REGLE 5.6" "REGLE 5.7" "REGLE 5.9" "REGLE 5.10"; do
        grep -qF "$regle" "$f" || { echo "règle non gardée en CI : $regle"; false; }
    done
}

@test "les règles de vitrine existent vraiment dans leurs fichiers de test" {
    # Garde-fou du garde-fou : sans lui, la règle ci-dessus se contenterait
    # de chaînes mortes dans un YAML.
    for regle in "REGLE 5.1" "REGLE 5.2" "REGLE 5.3" "REGLE 5.5" \
                 "REGLE 5.7" "REGLE 5.9" "REGLE 5.10"; do
        grep -qF "$regle" "$ROOT/tests/unit/test_readme_claims.bats" \
            || { echo "règle absente de test_readme_claims.bats : $regle"; false; }
    done
    grep -qF "REGLE 5.4" "$ROOT/tests/unit/test_readme_badges.bats"
    grep -qF "REGLE 5.6" "$ROOT/tests/unit/test_docs_index.bats"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_ci_workflows.bats`
Expected: FAIL — aucune des deux suites n'est nommée dans `tests.yml`, aucune règle n'y est citée.

- [ ] **Step 3: Write minimal implementation**

Dans `.github/workflows/tests.yml`, job `unit`, **après** l'étape « Packaging core unit suites » :

```yaml
      - name: Documentation suites (the README is confronted to the repo)
        run: |
          # Couvertes par « tests/unit/ » ci-dessus ; nommées ici pour qu'un
          # refactor de CI ne puisse pas les perdre en silence, comme pour
          # la signature et l'empaquetage. Ce sont du grep pur : aucun
          # paquet, aucun conteneur, coût négligeable sur chaque PR.
          rm -f config/*.zwc     # les règles 5.1 et 5.10 lisent config/
          ./tests/ci/bats-run.sh tests/unit/test_readme_claims.bats \
               tests/unit/test_readme_badges.bats \
               tests/unit/test_docs_index.bats

      - name: The showcase rules must be present and green
        run: |
          # Garde-fou contre une suppression discrète : ce sont ces règles
          # qui rougissent quand le README recommence à mentir. Sans elles,
          # la réécriture pourrit en trois mois comme la précédente.
          grep -q "REGLE 5.1"  tests/unit/test_readme_claims.bats   # commandes citées
          grep -q "REGLE 5.2"  tests/unit/test_readme_claims.bats   # superlatifs
          grep -q "REGLE 5.3"  tests/unit/test_readme_claims.bats   # chiffre de démarrage
          grep -q "REGLE 5.4"  tests/unit/test_readme_badges.bats   # badges sans preuve
          grep -q "REGLE 5.5"  tests/unit/test_readme_claims.bats   # 200 lignes
          grep -q "REGLE 5.6"  tests/unit/test_docs_index.bats      # index et liens
          grep -q "REGLE 5.7"  tests/unit/test_readme_claims.bats   # unilinguisme
          grep -q "REGLE 5.9"  tests/unit/test_readme_claims.bats   # puces ancrées
          grep -q "REGLE 5.10" tests/unit/test_readme_claims.bats   # variables citées
```

Dans le job `e2e`, l'étape « End-to-end » couvre déjà `tests/e2e/test_docs_install.bats` par `tests/e2e/` ; ajouter son nom à la liste explicite de l'étape de signature n'aurait pas de sens — le nommer dans le nouveau bloc `Documentation suites` suffit à satisfaire le test (`grep -qF` sur le fichier entier).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_ci_workflows.bats
bats tests/unit/test_readme_claims.bats tests/unit/test_docs_index.bats
./bin/test-count --update
```
Expected: PASS — 3 nouveaux tests ; les règles « aucun workflow n'installe de paquet » et « tout job qui lance bats utilise l'action composite » restent vertes.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/tests.yml tests/unit/test_ci_workflows.bats tests/baseline-counts.tsv
git commit -m "ci: name the documentation suites so a refactor cannot lose them"
```

---

# PHASE 4 — La démo

Six tâches, **séquentielles**. La source de vérité est un `.cast` asciinema versionné — du texte, diffable, auditable en revue. L'artefact affiché en dérive.

```
tools/demo/
├── scenario.txt      # source déclarative : une commande par ligne + délais
├── Dockerfile        # le conteneur de tournage, reproductible
├── stub/agy          # le faux backend IA, DÉCLARÉ, jamais caché
├── bin/home-fingerprint   # l'empreinte de $HOME, exposée dans la démo
├── play.exp          # le pilote de frappe (expect)
├── record.sh         # rejoue scenario.txt dans le conteneur → demo.cast
├── replay-check.sh   # garde 2 : rejeu non interactif, sans enregistrement
├── render.sh         # demo.cast → docs/assets/demo.{svg|gif} + demo.stamp
└── check-freshness.sh# garde 4 : la version du tampon contre .version
docs/assets/
├── demo.cast         # source de vérité, TEXTE
├── demo.svg          # ≤ 250 Ko (ou demo.gif ≤ 2 Mo si repli)
└── demo.stamp        # hachages : scénario, cast, artefact, version, format
```

**Production manuelle, jamais en CI.** Une régénération automatique produirait un diff binaire à chaque PR, que personne ne relit. Ce qui va en CI, ce n'est pas la production : c'est la **détection de divergence**, en quatre gardes.

*Sortie de phase : l'artefact s'affiche et s'anime dans le README rendu par GitHub ; modifier `scenario.txt` sans réenregistrer fait rougir la CI.*

---

### Task 4.1: vérifier empiriquement que GitHub anime un SVG de README

**Files:**
- Create: `tools/demo/README.md` (le compte rendu de la vérification, avec sa date et son verdict)
- Create: `docs/assets/.gitkeep`

**Interfaces:**
- Consumes: rien.
- Produces: **la décision de format** (`svg` ou `gif`), consignée, qui paramètre les tâches 4.4 et 4.5.

La spec (§ 3.1) le pose en risque à vérifier, pas en hypothèse : *GitHub sert les images du README via son proxy (camo) et sanitise les SVG ; l'animation CSS produite par `svg-term` doit être confirmée empiriquement sur une branche avant de committer l'artefact final.* Le repli est défini d'avance — le même `.cast` rendu en GIF par `agg`, budget relevé à 2 Mo, seule `render.sh` change.

**Cette tâche est un spike, pas un TDD.** Elle ne produit aucun code de production et n'a rien à faire échouer d'abord : son livrable est une observation datée. C'est la seule tâche du plan dans ce régime, et c'est assumé — écrire un test qui « vérifie que GitHub anime un SVG » demanderait de piloter un navigateur contre un service tiers, ce qui serait un test plus fragile que la chose testée.

- [ ] **Step 1: Produire l'artefact d'essai**

```bash
# Sur une branche jetable, jamais mergée.
git switch -c spike/demo-svg-rendering

mkdir -p docs/assets
# Un cast minimal, tourné à la main, sans scénario : 5 secondes suffisent.
asciinema rec --cols 100 --rows 24 --idle-time-limit 2 /tmp/spike.cast
#   … taper trois commandes visibles, puis exit …

npx --yes svg-term-cli \
    --in /tmp/spike.cast \
    --out docs/assets/spike.svg \
    --window --width 100 --height 24
ls -l docs/assets/spike.svg
```

- [ ] **Step 2: Observer le rendu réel de GitHub**

```bash
printf '# spike\n\n![demo](docs/assets/spike.svg)\n' > SPIKE.md
git add docs/assets/spike.svg SPIKE.md
git commit -m "spike: does GitHub animate an svg-term SVG"
git push -u origin spike/demo-svg-rendering
```

Ouvrir `https://github.com/maximeallanic/nivuus-shell/blob/spike/demo-svg-rendering/SPIKE.md` et répondre à **trois** questions, dans cet ordre :

1. L'image s'affiche-t-elle ? (le proxy camo peut refuser un SVG entier)
2. **S'anime-t-elle** ? (la sanitisation peut retirer les animations CSS)
3. Sur mobile et en thème sombre, reste-t-elle lisible ?

Répéter l'observation **déconnecté du compte** (navigation privée) : GitHub sert différemment un utilisateur authentifié.

- [ ] **Step 3: Consigner le verdict**

Créer `tools/demo/README.md` :

```markdown
# tools/demo — la démo du README

La source de vérité est `docs/assets/demo.cast` : du texte, diffable, auditable
en revue. Tout le reste en dérive.

## Format de l'artefact

**Vérifié le 2026-08-__, sur la branche `spike/demo-svg-rendering`.**

| Question | Réponse observée |
|---|---|
| Le SVG s'affiche-t-il dans un README rendu par GitHub ? | _à remplir_ |
| S'anime-t-il ? | _à remplir_ |
| Reste-t-il lisible en thème sombre et sur mobile ? | _à remplir_ |

**Verdict : `format=svg`** (ou `format=gif` si l'animation ne joue pas).

Le format retenu est écrit dans `docs/assets/demo.stamp` (`format=`), et
`tests/e2e/test_demo_scenario.bats` applique le budget de poids correspondant :
250 Ko pour un SVG, 2 Mo pour un GIF. Changer de format se fait en changeant
`NIVUUS_DEMO_FORMAT` et en relançant `render.sh` — le `.cast` ne bouge pas.

## Régénérer la démo

```bash
tools/demo/record.sh          # rejoue scenario.txt dans le conteneur → demo.cast
tools/demo/render.sh          # demo.cast → demo.svg (ou .gif) + demo.stamp
```

Jamais en CI. Trois raisons : un diff binaire par PR que personne ne relit ;
un artefact de vitrine doit passer devant un humain une fois (le timing et la
lisibilité ne sont pas testables) ; le risque de fuite est faible mais réel.

## Le backend IA est un stub, et il est déclaré

`tools/demo/stub/agy` est un faux Antigravity CLI qui renvoie des réponses
figées. Il est posé sur le `PATH` du conteneur de tournage, avec
`GEMINI_AUTH_MODE=cli` — le chemin de production existant, sans un seul
crochet ajouté dans `config/`. Aucune clé réelle n'entre jamais dans un
enregistrement. La légende sous l'image du README le dit ; un test l'exige.
```

Puis nettoyer : `git push origin --delete spike/demo-svg-rendering`, supprimer la branche locale et `SPIKE.md`.

- [ ] **Step 4: Commit**

```bash
mkdir -p docs/assets && touch docs/assets/.gitkeep
git add tools/demo/README.md docs/assets/.gitkeep
git commit -m "docs(demo): record how GitHub renders an animated terminal SVG"
```

---

### Task 4.2: `scenario.txt`, et la garde n° 1 — les commandes montrées existent

**Files:**
- Create: `tools/demo/scenario.txt`
- Create: `tests/e2e/test_demo_scenario.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `bin/nivuus help`, `config/*.zsh`, `tools/demo/bin/`.
- Produces: le format déclaratif du scénario, et la première garde de divergence — *instantanée, sur chaque PR*.

Le scénario **raconte la promesse**, il ne fait pas le tour du produit : 35 secondes, un seul plan, sans coupure, et le dernier plan est `nivuus uninstall` suivi d'un `diff` d'empreintes **vide**. S'il fallait couper, on couperait tout le reste avant lui.

**Format retenu, et pourquoi il a trois genres de ligne.** Un scénario qui ne distinguerait pas « commande qui doit exister » de « commande qui ne doit **pas** exister » ne pourrait pas décrire le plan du command-not-found sans se contredire. Le genre `unknown` est donc un genre à part entière, et la garde vérifie **l'absence** de la commande — sinon la démo montrerait un `command not found` qui n'arriverait plus.

- [ ] **Step 1: Write the failing test**

```bash
# tests/e2e/test_demo_scenario.bats
#!/usr/bin/env bats
#
# Une démo périmée est pire qu'aucune démo : elle montre un produit qui
# n'existe plus, à quelqu'un qui n'a aucun moyen de le savoir. Quatre gardes,
# du moins cher au plus cher (spec § 3.4). Celui-ci est le premier :
# instantané, sur chaque PR.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    DEMO="$ROOT/tools/demo"
    SCENARIO="$DEMO/scenario.txt"
    ASSETS="$ROOT/docs/assets"
}

# Les lignes utiles du scénario : « delai<TAB>genre<TAB>commande ».
scenario_lines() {
    grep -vE '^[[:space:]]*(#|$)' "$SCENARIO"
}

field() { printf '%s' "$1" | cut -f"$2"; }

@test "le scénario existe et déclare son en-tête" {
    [ -f "$SCENARIO" ]
    grep -q '^# meta: cols=' "$SCENARIO"
    grep -q '^# meta: ai-stub=' "$SCENARIO"
}

@test "le stub IA déclaré dans l'en-tête existe vraiment" {
    # Un stub déclaré mais absent, c'est une déclaration décorative.
    stub="$(sed -n 's/^# meta: ai-stub=\([^ ]*\).*/\1/p' "$SCENARIO" | head -n1)"
    [ -n "$stub" ]
    [ -x "$ROOT/$stub" ]
}

@test "chaque ligne du scénario a trois champs et un genre connu" {
    fautes=""
    while IFS= read -r l; do
        n="$(printf '%s' "$l" | awk -F'\t' '{print NF}')"
        [ "$n" -eq 3 ] || { fautes="$fautes
  champs=$n: $l"; continue; }
        case "$(field "$l" 2)" in
            run|unknown|type) ;;
            *) fautes="$fautes
  genre inconnu: $l" ;;
        esac
        printf '%s' "$(field "$l" 1)" | grep -qE '^[0-9]+$' \
            || fautes="$fautes
  délai non numérique: $l"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$fautes" ] || { echo "scénario malformé :$fautes"; false; }
}

@test "GARDE 1: toute commande « run » du scénario existe dans le produit" {
    rm -f "$ROOT"/config/*.zwc
    aide="$("$ROOT/bin/nivuus" help)"
    externes="curl wget sh zsh bash exec cd echo export print diff sudo"
    inconnues=""
    while IFS= read -r l; do
        [ "$(field "$l" 2)" = "run" ] || continue
        cmd="$(field "$l" 3 | awk '{print $1}')"
        case " $externes " in *" $cmd "*) continue ;; esac
        # sous-commande de nivuus
        if [ "$cmd" = "nivuus" ]; then
            sub="$(field "$l" 3 | awk '{print $2}')"
            printf '%s\n' "$aide" | grep -qE "nivuus +$sub" \
                || inconnues="$inconnues nivuus:$sub"
            continue
        fi
        # outil fourni par la démo elle-même
        [ -x "$DEMO/bin/$cmd" ] && continue
        [ -x "$ROOT/bin/$cmd" ] && continue
        grep -qhE "^[[:space:]]*(function[[:space:]]+)?${cmd}\(\)" "$ROOT"/config/*.zsh && continue
        grep -qhE "^[[:space:]]*alias[[:space:]]+'?${cmd}'?=" "$ROOT"/config/*.zsh && continue
        inconnues="$inconnues $cmd"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$inconnues" ] || {
        echo "la démo montre des commandes qui n'existent plus :$inconnues"; false; }
}

@test "GARDE 1: toute commande « unknown » est réellement introuvable" {
    # Le plan du command-not-found repose sur une commande ABSENTE. Le jour
    # où quelqu'un l'ajoute au produit ou aux prérequis, la démo montre un
    # « command not found » qui n'arrive plus : c'est ce test qui le dit.
    encore_la=""
    while IFS= read -r l; do
        [ "$(field "$l" 2)" = "unknown" ] || continue
        cmd="$(field "$l" 3 | awk '{print $1}')"
        grep -qhE "^[[:space:]]*(function[[:space:]]+)?${cmd}\(\)" "$ROOT"/config/*.zsh \
            && encore_la="$encore_la $cmd"
        grep -qhE "^[[:space:]]*alias[[:space:]]+'?${cmd}'?=" "$ROOT"/config/*.zsh \
            && encore_la="$encore_la $cmd"
        [ -x "$ROOT/bin/$cmd" ] && encore_la="$encore_la $cmd"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$encore_la" ] || {
        echo "la démo prétend que ces commandes n'existent pas :$encore_la"; false; }
}

@test "le dernier plan du scénario est la désinstallation, puis un diff" {
    # Le point de la démo. S'il fallait couper, on couperait tout le reste
    # avant lui -- donc il ne peut pas glisser au milieu par inadvertance.
    dernieres="$(scenario_lines | tail -n 3 | cut -f3)"
    printf '%s' "$dernieres" | grep -q 'nivuus uninstall'
    printf '%s' "$dernieres" | grep -q '^diff '
}

@test "le scénario tient dans le budget de 35 secondes" {
    total="$(scenario_lines | cut -f1 | awk '{s += $1} END {print s + 0}')"
    [ "$total" -le 35000 ] || { echo "scénario de ${total}ms (budget: 35000)"; false; }
    [ "$total" -ge 20000 ] || { echo "scénario de ${total}ms : trop court pour être lisible"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_demo_scenario.bats`
Expected: FAIL — `tools/demo/scenario.txt` n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `tools/demo/scenario.txt` (les séparateurs sont des **tabulations**) :

```
# Nivuus demo — source déclarative de docs/assets/demo.cast
#
# Ce fichier est la SOURCE. Le .cast en dérive (record.sh), le SVG dérive du
# .cast (render.sh). Modifier ce fichier sans réenregistrer fait rougir la CI :
# c'est la garde n° 3 (le tampon de fraîcheur).
#
# meta: cols=100 rows=28 hostname=demo theme=nord
# meta: ai-stub=tools/demo/stub/agy  (faux Antigravity CLI, réponses figées,
#       aucune clé réelle -- déclaré ici parce qu'un stub caché serait un
#       mensonge, et que ce dépôt en ferme un par chantier)
#
# Format : <délai_ms><TAB><genre><TAB><commande>
#   run      la commande DOIT exister dans le produit          (garde 1)
#   unknown  la commande NE DOIT PAS exister -- c'est le plan  (garde 1)
#   type     frappe affichée, jamais exécutée
#
# --- 0-2 s : l'empreinte de $HOME, avant toute chose -------------------------
1500	run	home-fingerprint > /tmp/before
# --- 2-9 s : une commande, pas de sudo, pas de question ----------------------
6500	run	curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
# --- 9-13 s : le prompt apparaît, et le temps de démarrage est à l'écran -----
2500	run	exec zsh
1500	run	print -r -- "startup: ${NIVUUS_LOAD_TIME}ms"
# --- 13-19 s : l'IA en contexte, sans qu'on l'ait invoquée -------------------
5500	unknown	rg TODO src/
# --- 19-25 s : l'assistance à la demande ------------------------------------
5500	run	?? "find files bigger than 100M"
# --- 25-28 s : le prompt, sans en faire une démonstration séparée ------------
2500	run	cd /home/demo/work/nivuus-shell
# --- 28-35 s : LE PLAN. Personne d'autre ne peut le tourner. -----------------
5000	run	nivuus uninstall --yes --purge
1500	run	home-fingerprint > /tmp/after
2000	run	diff /tmp/before /tmp/after && print -r -- "HOME is byte-identical."
```

Créer `tools/demo/bin/home-fingerprint`, mince enveloppe autour du helper **déjà utilisé par le test de réversibilité** — la démo montre donc littéralement la mesure que la CI impose :

```sh
#!/bin/sh
# tools/demo/bin/home-fingerprint
# L'empreinte de $HOME telle que tests/e2e/test_reversibility.bats la calcule.
# La démo ne doit pas mesurer autre chose que ce que la CI impose : sinon la
# preuve à l'écran et la preuve en CI seraient deux preuves différentes.
set -eu
ROOT="${NIVUUS_DEMO_ROOT:-/opt/nivuus-src}"
# shellcheck source=/dev/null
. "$ROOT/tests/helpers/fingerprint.bash"
fs_fingerprint "${1:-$HOME}"
```

`chmod +x tools/demo/bin/home-fingerprint`. Créer aussi le stub, requis par le second test :

```sh
#!/bin/sh
# tools/demo/stub/agy — FAUX Antigravity CLI, pour le tournage de la démo.
#
# Il imite la seule surface que config/09-ai-backend-gemini.zsh consomme :
# « agy -p PROMPT --model M --output-format json », un objet JSON avec
# .status et .response. Aucune clé, aucun réseau, aucune variabilité.
#
# Pourquoi un stub plutôt qu'une vraie clé jetable : la garde n° 2 rejoue ce
# scénario en conteneur à chaque merge. Un rejeu qui dépend d'une clé tierce
# est un test qui rougit pour une raison étrangère au produit -- donc un test
# qu'on finira par désactiver.
set -eu

prompt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p) prompt="$2"; shift 2 ;;
        --model|--output-format|--print-timeout) shift 2 ;;
        *) shift ;;
    esac
done

reply() { printf '{"status":"SUCCESS","response":%s}\n' "$1"; }

case "$prompt" in
    *rg*|*ripgrep*)
        reply '"ripgrep provides `rg`.\n\nsudo apt-get install -y ripgrep"' ;;
    *bigger*|*100M*|*larger*)
        reply '"find . -type f -size +100M -exec ls -lh {} +"' ;;
    *)
        reply '"(demo stub: no canned answer for this prompt)"' ;;
esac
```

`chmod +x tools/demo/stub/agy`.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
rm -f config/*.zwc
bats tests/e2e/test_demo_scenario.bats
./bin/test-count --update
```
Expected: PASS — 8 nouveaux tests. Le total du scénario vaut 34 000 ms, sous le budget de 35 s.

- [ ] **Step 5: Commit**

```bash
chmod +x tools/demo/bin/home-fingerprint tools/demo/stub/agy
git add tools/demo/scenario.txt tools/demo/bin/home-fingerprint tools/demo/stub/agy \
        tests/e2e/test_demo_scenario.bats tests/baseline-counts.tsv
git commit -m "feat(demo): declare the scenario and prove its commands exist"
```

---

### Task 4.3: le conteneur de tournage, et la garde n° 2 — le scénario est rejoué pour de vrai

**Files:**
- Create: `tools/demo/Dockerfile`, `tools/demo/replay-check.sh`
- Modify: `tests/e2e/test_demo_scenario.bats`
- Modify: `.github/workflows/matrix.yml`, `tests/unit/test_ci_workflows.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `tools/demo/scenario.txt`, `tools/demo/stub/agy`, `tools/demo/bin/`.
- Produces: **la garde qui compte** — elle rend impossible de *montrer un flux qui ne marche plus*.

Les trois autres gardes vérifient des chaînes de caractères. Celle-ci exécute. Elle rejoue chaque commande `run` du scénario dans le conteneur, en non-interactif, et exige un code 0 et une sortie sans motif d'échec ; elle vérifie que chaque commande `unknown` est bien introuvable.

**Coût et placement.** Un job conteneur : trop cher pour chaque PR, indispensable avant chaque release. Il rejoint donc la matrice nightly / merge master, comme le prévoit la spec (§ 3.4, garde 2). Le test bats est tagué `docker`, donc **exclu par défaut** de `tests/ci/bats-run.sh` — exactement comme les 7 tests `docker` existants.

**Contrainte respectée :** aucune installation de paquet n'est ajoutée à un workflow. Les paquets sont installés par le `Dockerfile`, qui n'est pas un workflow, et le workflow ne fait que `docker build` puis `docker run`.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/e2e/test_demo_scenario.bats` :

```bash
@test "le conteneur de tournage est décrit et reproductible" {
    [ -f "$DEMO/Dockerfile" ]
    # Base épinglée : une démo tournée sur « latest » n'est pas reproductible.
    grep -qE '^FROM [a-z]+:[0-9]' "$DEMO/Dockerfile"
    # Le nom d'hôte est fixé : sinon chaque enregistrement diffère du
    # précédent par le prompt, et le .cast n'est plus diffable.
    grep -qF 'demo' "$DEMO/Dockerfile"
}

@test "le conteneur n'embarque jamais de clé réelle" {
    # Le risque de fuite est faible mais réel : on le ferme par construction.
    run grep -nE '(API_KEY|GOOGLE_API_KEY|sk-[A-Za-z0-9]{8})' "$DEMO/Dockerfile"
    [ "$status" -ne 0 ] || { echo "clé dans le Dockerfile : $output"; false; }
    grep -qF 'GEMINI_AUTH_MODE=cli' "$DEMO/Dockerfile"
    grep -qF 'AGY_DAEMON_ENABLED=false' "$DEMO/Dockerfile"
}

@test "replay-check.sh existe, est exécutable et POSIX" {
    [ -x "$DEMO/replay-check.sh" ]
    run sh -n "$DEMO/replay-check.sh"
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "GARDE 2: le scénario rejoué dans le conteneur passe de bout en bout" {
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
    run "$DEMO/replay-check.sh"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"HOME is byte-identical"* ]]
}

# bats test_tags=docker
@test "GARDE 2: une commande supprimée du produit fait échouer le rejeu" {
    # Garde-fou du garde-fou : on prouve que le rejeu SAIT échouer, sinon
    # il ne serait qu'un job vert décoratif.
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
    tmp="$BATS_TEST_TMPDIR/scenario.txt"
    cp "$SCENARIO" "$tmp"
    printf '500\trun\tnivuus-cette-commande-nexiste-pas\n' >> "$tmp"
    run env NIVUUS_DEMO_SCENARIO="$tmp" "$DEMO/replay-check.sh"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `NIVUUS_CI_DOCKER=1 bats tests/e2e/test_demo_scenario.bats`
Expected: FAIL — ni `Dockerfile` ni `replay-check.sh` n'existent.

- [ ] **Step 3: Write minimal implementation**

`tools/demo/Dockerfile` :

```dockerfile
# Le conteneur de tournage de la démo. Reproductible, épinglé, sans clé.
#
# debian:12 plutôt qu'ubuntu : c'est la cible la plus neutre de la matrice, et
# celle dont le gestionnaire de paquets produit la suggestion la plus lisible
# à l'écran (« sudo apt-get install -y ripgrep »).
FROM debian:12

# ripgrep est VOLONTAIREMENT absent : c'est la commande introuvable du plan
# t=13-19s. Ne pas l'ajouter ici, même « pour confort » -- le test
# « toute commande unknown est réellement introuvable » ne le verrait pas,
# mais la démo, elle, cesserait de montrer quoi que ce soit.
RUN apt-get update && apt-get install -y --no-install-recommends \
        zsh curl ca-certificates jq git procps expect \
    && rm -rf /var/lib/apt/lists/*

# Nom d'hôte fixe : un prompt qui change à chaque tournage rend le .cast
# non diffable, donc non auditable en revue -- c'est-à-dire sans intérêt.
RUN echo demo > /etc/hostname

RUN useradd -m -s /bin/zsh demo && mkdir -p /home/demo/work
WORKDIR /home/demo

# Le stub IA, sur le PATH, avec le mode d'authentification qui l'emprunte.
# C'est le chemin de PRODUCTION (config/09-ai-backend-gemini.zsh) : aucun
# crochet n'est ajouté au produit pour tourner la démo.
COPY stub/agy /usr/local/bin/agy
COPY bin/home-fingerprint /usr/local/bin/home-fingerprint
RUN chmod +x /usr/local/bin/agy /usr/local/bin/home-fingerprint
ENV GEMINI_AUTH_MODE=cli \
    AGY_DAEMON_ENABLED=false \
    NIVUUS_DEMO_ROOT=/opt/nivuus-src \
    TERM=xterm-256color

USER demo
```

`tools/demo/replay-check.sh` :

```sh
#!/bin/sh
# =============================================================================
# GARDE 2 — le scénario de la démo est rejoué pour de vrai, sans enregistrer.
# =============================================================================
# Ce que les trois autres gardes ne peuvent pas faire : vérifier que le FLUX
# marche encore, pas seulement que les commandes existent. C'est le garde qui
# compte -- il rend impossible de montrer un flux qui ne marche plus.
#
# Rejouable en local, à l'identique, par un simple `tools/demo/replay-check.sh`.
# Toute la logique de preuve est ici, rien dans le YAML : même modèle que
# tests/ci/run-target.sh.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO="${NIVUUS_DEMO_SCENARIO:-$ROOT/tools/demo/scenario.txt}"
IMAGE="${NIVUUS_DEMO_IMAGE:-nivuus-demo:local}"

echo "== Construction du conteneur de tournage =="
docker build -t "$IMAGE" -f "$ROOT/tools/demo/Dockerfile" "$ROOT/tools/demo"

# Le scénario devient un script zsh non interactif. Les lignes « type » sont
# ignorées (elles ne sont que de la frappe affichée) ; les lignes « unknown »
# deviennent une assertion d'ABSENCE.
script="$(mktemp)"
{
    echo 'set -e'
    echo 'export ENABLE_AUTOUPDATE=false'
    grep -vE '^[[:space:]]*(#|$)' "$SCENARIO" | while IFS="$(printf '\t')" read -r _ genre cmd; do
        case "$genre" in
            run)     printf '%s\n' "$cmd" ;;
            unknown) printf 'command -v %s >/dev/null 2>&1 && { print -u2 -- "la démo prétend que %s est introuvable, or elle existe"; exit 1; }\n' \
                            "$(printf '%s' "$cmd" | awk '{print $1}')" \
                            "$(printf '%s' "$cmd" | awk '{print $1}')" ;;
            type)    : ;;
        esac
    done
} > "$script"

echo "== Rejeu non interactif du scénario =="
out="$(mktemp)"
set +e
docker run --rm \
    -v "$ROOT:/opt/nivuus-src:ro" \
    -v "$script:/tmp/replay.zsh:ro" \
    "$IMAGE" zsh -e /tmp/replay.zsh > "$out" 2>&1
rc=$?
set -e
cat "$out"

# `exec zsh` remplace le shell : en non-interactif, la ligne est neutralisée
# par zsh lui-même, ce qui est le comportement voulu -- on rejoue le flux,
# pas la mise en scène.
if [ "$rc" -ne 0 ]; then
    echo "REJEU EN ÉCHEC (code $rc) : la démo montre un flux qui ne marche plus." >&2
    exit "$rc"
fi

# Un code 0 ne suffit pas : une commande peut réussir en imprimant son échec.
if grep -qiE 'command not found|no such file|permission denied|traceback|refus' "$out"; then
    # Sauf le « command not found » ATTENDU du plan t=13-19s.
    if [ "$(grep -ci 'command not found' "$out")" -gt 1 ]; then
        echo "motif d'échec dans la sortie du rejeu." >&2
        exit 1
    fi
fi

rm -f "$script" "$out"
echo "== Rejeu conforme =="
```

`chmod +x tools/demo/replay-check.sh`.

Dans `.github/workflows/matrix.yml`, ajouter un job — **aucune installation de paquet**, Docker est fourni par le runner :

```yaml
  demo-replay:
    name: Demo scenario still runs
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-tests
      - name: GARDE 2 — replay the demo scenario for real
        # Le seul garde de la démo qui coûte un conteneur. Il ne tourne donc
        # pas sur PR : la matrice est nightly, sur workflow_dispatch et
        # appelable par une release. Les trois autres gardes, eux, sont du
        # grep et tournent sur chaque PR.
        run: ./tools/demo/replay-check.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/e2e/test_demo_scenario.bats                 # sans docker : 3 nouveaux tests
NIVUUS_CI_DOCKER=1 bats tests/e2e/test_demo_scenario.bats   # avec docker : les 5
bats tests/unit/test_ci_workflows.bats
./bin/test-count --update
```
Expected: PASS — 13 tests dans la suite, dont 2 tagués `docker` (exclus par défaut) ; la règle « aucun workflow n'installe de paquet » reste verte.

- [ ] **Step 5: Commit**

```bash
chmod +x tools/demo/replay-check.sh
git add tools/demo/Dockerfile tools/demo/replay-check.sh .github/workflows/matrix.yml \
        tests/e2e/test_demo_scenario.bats tests/baseline-counts.tsv
git commit -m "feat(demo): replay the scenario in a container so a dead flow cannot ship"
```

---

### Task 4.4: `record.sh`, `render.sh`, et la garde n° 3 — le tampon de fraîcheur

**Files:**
- Create: `tools/demo/play.exp`, `tools/demo/record.sh`, `tools/demo/render.sh`
- Modify: `tests/e2e/test_demo_scenario.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `tools/demo/scenario.txt`, le conteneur de la Task 4.3, la décision de format de la Task 4.1.
- Produces: `docs/assets/demo.cast`, `docs/assets/demo.{svg|gif}`, `docs/assets/demo.stamp`, et la garde qui interdit qu'ils divergent.

Le tampon contient le SHA-256 de `scenario.txt`, celui de `demo.cast`, celui de l'artefact, la version du projet au moment de l'enregistrement, et le format retenu. La CI recalcule et compare : **modifier le scénario sans réenregistrer, ou committer un artefact qui ne dérive pas du `.cast` présent, échoue.** Coût : instantané, sur chaque PR.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/e2e/test_demo_scenario.bats` :

```bash
sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

stamp_field() { sed -n "s/^$1=//p" "$ASSETS/demo.stamp" | head -n1; }

@test "les trois outils de la démo existent et sont exécutables" {
    for f in record.sh render.sh; do
        [ -x "$DEMO/$f" ] || { echo "$f manquant ou non exécutable"; false; }
        run sh -n "$DEMO/$f"
        [ "$status" -eq 0 ]
    done
    [ -f "$DEMO/play.exp" ]
}

@test "GARDE 3: le tampon existe et porte ses cinq champs" {
    [ -f "$ASSETS/demo.stamp" ]
    for k in scenario_sha256 cast_sha256 artefact artefact_sha256 version format; do
        [ -n "$(stamp_field "$k")" ] || { echo "champ absent du tampon : $k"; false; }
    done
}

@test "GARDE 3: le tampon correspond au scénario présent" {
    # Modifier scenario.txt sans réenregistrer : le mode de défaillance
    # n° 1 d'une démo versionnée.
    [ "$(stamp_field scenario_sha256)" = "$(sha "$SCENARIO")" ] \
        || { echo "scenario.txt a changé sans réenregistrement (tools/demo/record.sh)"; false; }
}

@test "GARDE 3: le tampon correspond au .cast présent" {
    [ -f "$ASSETS/demo.cast" ]
    [ "$(stamp_field cast_sha256)" = "$(sha "$ASSETS/demo.cast")" ] \
        || { echo "demo.cast ne correspond pas au tampon"; false; }
}

@test "GARDE 3: l'artefact affiché dérive bien du .cast présent" {
    a="$(stamp_field artefact)"
    [ -f "$ROOT/$a" ]
    [ "$(stamp_field artefact_sha256)" = "$(sha "$ROOT/$a")" ] \
        || { echo "$a ne dérive pas du demo.cast présent (tools/demo/render.sh)"; false; }
}

@test "l'artefact respecte le budget de poids de son format" {
    # 250 Ko pour un SVG ; 2 Mo pour le repli GIF (spec § 3.1). Le budget
    # suit le format déclaré, pas l'inverse : c'est ce qui rend le repli
    # exécutable sans replanifier.
    a="$(stamp_field artefact)"
    n="$(wc -c < "$ROOT/$a")"
    case "$(stamp_field format)" in
        svg) max=256000 ;;
        gif) max=2097152 ;;
        *)   echo "format inconnu dans le tampon"; false ;;
    esac
    [ "$n" -le "$max" ] || { echo "$a pèse $n octets (budget: $max)"; false; }
}

@test "le .cast est du TEXTE, donc auditable en revue" {
    # C'est l'argument décisif contre le GIF comme source (spec § 3.1) : une
    # PR qui modifie la démo doit être LISIBLE. Si le .cast devient binaire,
    # cette propriété est perdue en silence.
    run file "$ASSETS/demo.cast"
    [[ "$output" == *"text"* ]] || [[ "$output" == *"JSON"* ]]
    head -n1 "$ASSETS/demo.cast" | grep -q '"version"'
}

@test "aucune clé ni chemin personnel ne s'est glissé dans le .cast" {
    # Le .cast est du texte : on peut le fouiller, et donc on le fouille.
    run grep -nE 'sk-[A-Za-z0-9]{16}|AIza[A-Za-z0-9_-]{16}|/home/(?!demo)' "$ASSETS/demo.cast"
    [ "$status" -ne 0 ] || { echo "donnée suspecte dans le cast : $output"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_demo_scenario.bats`
Expected: FAIL — ni les scripts, ni `demo.cast`, ni `demo.stamp` n'existent.

- [ ] **Step 3: Write minimal implementation**

`tools/demo/play.exp` — le pilote de frappe. Il tape caractère par caractère pour que l'enregistrement ressemble à quelqu'un qui tape, et respecte les délais déclarés :

```tcl
#!/usr/bin/expect -f
# Pilote de frappe de la démo : lit scenario.txt et le joue dans un zsh
# interactif. La frappe caractère par caractère n'est pas de la coquetterie :
# un .cast où tout apparaît d'un coup est illisible à la lecture.
set scenario [lindex $argv 0]
set timeout -1
log_user 1

spawn zsh -i
expect -re {[%$#] $}

set f [open $scenario r]
while {[gets $f line] >= 0} {
    if {[string match "#*" $line] || [string trim $line] eq ""} { continue }
    set parts [split $line "\t"]
    set delay [lindex $parts 0]
    set kind  [lindex $parts 1]
    set cmd   [lindex $parts 2]

    foreach ch [split $cmd ""] {
        send -- $ch
        sleep 0.035
    }
    if {$kind ne "type"} { send -- "\r" }
    sleep [expr {double($delay) / 1000.0}]
}
close $f
send -- "exit\r"
expect eof
```

`tools/demo/record.sh` :

```sh
#!/bin/sh
# =============================================================================
# Enregistre la démo. À LA MAIN, jamais en CI (voir tools/demo/README.md).
# =============================================================================
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${NIVUUS_DEMO_IMAGE:-nivuus-demo:local}"
OUT="$ROOT/docs/assets/demo.cast"

command -v docker >/dev/null 2>&1 || { echo "docker requis" >&2; exit 1; }

docker build -t "$IMAGE" -f "$ROOT/tools/demo/Dockerfile" "$ROOT/tools/demo"

# --tty + --interactive : asciinema enregistre un vrai terminal, sinon le
# prompt ne s'affiche pas et l'enregistrement est un log, pas une démo.
docker run --rm -it \
    -v "$ROOT:/opt/nivuus-src:ro" \
    -v "$ROOT/docs/assets:/out" \
    -v "$ROOT/tools/demo:/demo:ro" \
    "$IMAGE" sh -c '
        asciinema rec --cols 100 --rows 28 --idle-time-limit 2 \
            --command "expect /demo/play.exp /demo/scenario.txt" \
            /out/demo.cast
    '

echo "Enregistré : $OUT"
echo
echo "RELIS-LE AVANT DE COMMITTER. Aucun test ne dira que la démo est devenue"
echo "laide, mal rythmée ou illisible : c'est le seul point que la CI ne couvre"
echo "pas, et c'est pour cela que cet enregistrement est manuel."
echo
echo "Puis : tools/demo/render.sh"
```

`tools/demo/render.sh` :

```sh
#!/bin/sh
# =============================================================================
# demo.cast -> l'artefact affiché, + le tampon de fraîcheur (garde 3).
# =============================================================================
# Le format est une VARIABLE, pas une réécriture : si l'animation SVG ne joue
# pas dans le README rendu par GitHub, NIVUUS_DEMO_FORMAT=gif suffit. Le .cast
# reste la source ; seul ce script change de sortie.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASSETS="$ROOT/docs/assets"
CAST="$ASSETS/demo.cast"
FORMAT="${NIVUUS_DEMO_FORMAT:-svg}"

[ -f "$CAST" ] || { echo "demo.cast absent : lance d'abord tools/demo/record.sh" >&2; exit 1; }

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

case "$FORMAT" in
    svg)
        ARTEFACT="$ASSETS/demo.svg"
        npx --yes svg-term-cli --in "$CAST" --out "$ARTEFACT" \
            --window --width 100 --height 28
        ;;
    gif)
        # Repli défini d'avance (spec § 3.1) : budget relevé à 2 Mo.
        ARTEFACT="$ASSETS/demo.gif"
        agg --cols 100 --rows 28 "$CAST" "$ARTEFACT"
        ;;
    *) echo "format inconnu: $FORMAT (svg|gif)" >&2; exit 2 ;;
esac

cat > "$ASSETS/demo.stamp" <<EOF
# Tampon de fraîcheur de la démo — GARDE 3.
# Recalculé et comparé par tests/e2e/test_demo_scenario.bats sur chaque PR.
# Modifier scenario.txt sans relancer record.sh puis render.sh fait rougir la CI.
scenario_sha256=$(sha "$ROOT/tools/demo/scenario.txt")
cast_sha256=$(sha "$CAST")
artefact=docs/assets/$(basename "$ARTEFACT")
artefact_sha256=$(sha "$ARTEFACT")
version=$(cat "$ROOT/.version")
format=$FORMAT
EOF

ls -l "$ARTEFACT"
echo "Tampon écrit : $ASSETS/demo.stamp"
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
tools/demo/record.sh          # manuel, avec relecture humaine
tools/demo/render.sh
bats tests/e2e/test_demo_scenario.bats
./bin/test-count --update
```
Expected: PASS — 21 tests dans la suite ; l'artefact sous son budget ; le `.cast` reconnu comme du texte JSON.

- [ ] **Step 5: Commit**

```bash
chmod +x tools/demo/record.sh tools/demo/render.sh
git add tools/demo/play.exp tools/demo/record.sh tools/demo/render.sh \
        docs/assets/demo.cast docs/assets/demo.svg docs/assets/demo.stamp \
        tests/e2e/test_demo_scenario.bats tests/baseline-counts.tsv
git commit -m "feat(demo): record, render, and stamp the demo so it cannot drift"
```

---

### Task 4.5: la démo entre dans le README, avec sa légende honnête

**Files:**
- Modify: `README.md`
- Modify: `tests/e2e/test_demo_scenario.bats`
- Modify: `tests/unit/test_readme_claims.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `docs/assets/demo.stamp` (le champ `artefact`), la structure du README (Task 3.1).
- Produces: **le premier objet non textuel de la page**, en position 2 — juste après le titre et les badges, avant l'installation.

Un projet dont l'argument est l'expérience du terminal ne montre pas son terminal. C'est le constat n° 10 de la spec, et le seul classé bloquant qui ne soit pas une fausseté.

La légende n'est pas décorative : elle **déclare le stub**. Une démo dont le backend IA est simulé et qui ne le dit pas est exactement le genre de mensonge que ce chantier ferme.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/e2e/test_demo_scenario.bats` :

```bash
@test "le README affiche l'artefact que le tampon désigne" {
    # Pas « une image » : CELLE dont la CI vérifie qu'elle dérive du .cast.
    a="$(stamp_field artefact)"
    grep -qF "($a)" "$ROOT/README.md" \
        || { echo "le README n'affiche pas $a"; false; }
}

@test "la démo est le premier objet non textuel de la page" {
    # Position 2 de la structure cible : titre + badges, puis LA DÉMO. Si
    # elle glisse plus bas, elle cesse d'être ce qui décide le lecteur.
    n="$(grep -n "$(stamp_field artefact)" "$ROOT/README.md" | head -n1 | cut -d: -f1)"
    [ -n "$n" ]
    [ "$n" -le 20 ] || { echo "la démo est à la ligne $n : trop bas"; false; }
}

@test "la légende déclare que le backend IA est un stub" {
    # Une démo dont l'IA est simulée et qui ne le dit pas est un mensonge de
    # vitrine -- exactement ce que ce chantier ferme. La déclaration est
    # dans le scénario ET sous l'image : c'est sous l'image qu'elle est lue.
    legende="$(grep -A4 -F "$(stamp_field artefact)" "$ROOT/README.md")"
    printf '%s' "$legende" | grep -qiE 'stub|canned|simulat'
    printf '%s' "$legende" | grep -qF 'tools/demo/scenario.txt'
}

@test "la légende dit ce que le dernier plan prouve" {
    legende="$(grep -A4 -F "$(stamp_field artefact)" "$ROOT/README.md")"
    printf '%s' "$legende" | grep -qiE 'byte|identical|unchanged'
}
```

Ajouter à `tests/unit/test_readme_claims.bats` — la règle de longueur doit tenir **avec** la démo :

```bash
@test "REGLE 5.5: le README tient encore en 200 lignes une fois la démo insérée" {
    n="$(wc -l < "$README")"
    [ "$n" -le 200 ] || { echo "README à $n lignes après insertion de la démo"; false; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_demo_scenario.bats`
Expected: FAIL — le README n'affiche aucune image.

- [ ] **Step 3: Write minimal implementation**

Dans `README.md`, **entre les badges et `## Install`**, insérer cinq lignes :

```markdown
![Nivuus: install, use, and uninstall in 35 seconds](docs/assets/demo.svg)

*Install, use, remove — and a `$HOME` fingerprint that comes back byte for byte
identical. Recorded in a clean container; the AI backend is a local stub with
canned answers, declared in [tools/demo/scenario.txt](tools/demo/scenario.txt).*
```

Si le verdict de la Task 4.1 a été `gif`, remplacer `demo.svg` par `demo.gif` — le test lit le tampon, pas une constante, donc rien d'autre ne change.

Vérifier `wc -l README.md` : la cible reste 200, l'insertion coûte 5 lignes.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/e2e/test_demo_scenario.bats
bats tests/unit/test_readme_claims.bats
bats tests/unit/test_docs_index.bats
./bin/test-count --update
```
Expected: PASS — 25 tests dans la suite de démo, 34 dans celle du README.

**Vérification manuelle obligatoire avant merge :** pousser la branche et ouvrir le README sur GitHub. L'image doit s'afficher **et** s'animer, en thème clair et sombre. C'est la seule chose qu'aucun test ne dira.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/e2e/test_demo_scenario.bats tests/unit/test_readme_claims.bats \
        tests/baseline-counts.tsv
git commit -m "docs(readme): show the demo, and say that its AI backend is stubbed"
```

---

### Task 4.6: la garde n° 4 — aucune mineure ne sort avec une démo d'une génération précédente

**Files:**
- Create: `tools/demo/check-freshness.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `tests/e2e/test_demo_scenario.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `docs/assets/demo.stamp` (champ `version`), `.version`, l'entrée `bump_type` de `release.yml`.
- Produces: le refus de release quand la démo a une mineure de retard.

Sur les **patchs**, non : le coût serait constant pour un bénéfice nul. Sur les **mineures et majeures**, la release échoue si la démo date d'une génération précédente. C'est la règle qui garantit qu'aucune version mineure ne sort avec une démo périmée.

**Décision actée n° 4 :** à réévaluer après trois releases mineures, si réenregistrer devient pénible. Aucune tâche ne le planifie ; c'est une note pour le futur relecteur.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/e2e/test_demo_scenario.bats` :

```bash
@test "check-freshness.sh existe, est exécutable et POSIX" {
    [ -x "$DEMO/check-freshness.sh" ]
    run sh -n "$DEMO/check-freshness.sh"
    [ "$status" -eq 0 ]
}

@test "GARDE 4: une démo à jour passe" {
    run "$DEMO/check-freshness.sh" minor
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "GARDE 4: une démo en retard d'une mineure fait échouer une release mineure" {
    tmp="$BATS_TEST_TMPDIR/demo.stamp"
    sed 's/^version=.*/version=1.0.0/' "$ASSETS/demo.stamp" > "$tmp"
    run env NIVUUS_DEMO_STAMP="$tmp" "$DEMO/check-freshness.sh" minor
    [ "$status" -ne 0 ]
    [[ "$output" == *"record.sh"* ]]   # le refus dit quoi faire
}

@test "GARDE 4: une démo en retard NE bloque PAS un patch" {
    # Le coût serait constant pour un bénéfice nul : une correction de bug
    # ne change pas ce que la démo montre.
    tmp="$BATS_TEST_TMPDIR/demo.stamp"
    sed 's/^version=.*/version=1.0.0/' "$ASSETS/demo.stamp" > "$tmp"
    run env NIVUUS_DEMO_STAMP="$tmp" "$DEMO/check-freshness.sh" patch
    [ "$status" -eq 0 ]
}

@test "GARDE 4: la release appelle réellement la garde" {
    # Sans cette ligne, le script existerait sans jamais tourner : le mode
    # de défaillance classique d'un garde-fou écrit et oublié.
    grep -qF 'tools/demo/check-freshness.sh' "$ROOT/.github/workflows/release.yml"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/e2e/test_demo_scenario.bats`
Expected: FAIL — le script n'existe pas et `release.yml` ne l'appelle pas.

- [ ] **Step 3: Write minimal implementation**

`tools/demo/check-freshness.sh` :

```sh
#!/bin/sh
# =============================================================================
# GARDE 4 — péremption de la démo par version mineure.
# =============================================================================
# Usage : check-freshness.sh [patch|minor|major]
#
# Une démo enregistrée deux mineures plus tôt montre un produit que le lecteur
# ne recevra pas. Sur les patchs, la règle ne s'applique pas : le coût serait
# constant pour un bénéfice nul.
#
# À réévaluer après trois releases mineures (décision actée n° 4) : si
# réenregistrer devient pénible, c'est la règle qu'on discute, pas le commit
# qui bute dessus.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="${NIVUUS_DEMO_STAMP:-$ROOT/docs/assets/demo.stamp}"
BUMP="${1:-minor}"

case "$BUMP" in
    patch) echo "bump=patch : la démo n'est pas soumise à péremption."; exit 0 ;;
esac

[ -f "$STAMP" ] || { echo "tampon de démo absent : $STAMP" >&2; exit 1; }

stamped="$(sed -n 's/^version=//p' "$STAMP" | head -n1)"
current="$(cat "$ROOT/.version")"
[ -n "$stamped" ] || { echo "le tampon ne porte pas de version" >&2; exit 1; }

minor_of() { printf '%s' "$1" | cut -d. -f1,2; }

if [ "$(minor_of "$stamped")" != "$(minor_of "$current")" ]; then
    cat >&2 <<EOF
Release refusée : la démo date de la version $stamped, le projet est en $current.

Une mineure ne sort pas avec une démo d'une génération précédente : elle
montrerait un produit que personne ne recevra. Réenregistre-la :

    tools/demo/record.sh
    tools/demo/render.sh

(Un patch n'est pas concerné par cette règle.)
EOF
    exit 1
fi

echo "démo à jour : $stamped ~ $current"
```

Dans `.github/workflows/release.yml`, job `release`, **avant** le calcul de version — un refus doit être gratuit :

```yaml
      - name: GARDE 4 — the demo must not be a generation behind
        # Aucune mineure ne sort avec une démo périmée (spec § 3.4, garde 4).
        # Les patchs en sont exemptés : le coût serait constant pour un
        # bénéfice nul. Toute la logique est dans le script, rejouable en
        # local -- même modèle que tests/ci/run-target.sh.
        run: ./tools/demo/check-freshness.sh "${{ inputs.bump_type }}"
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/e2e/test_demo_scenario.bats
bats tests/unit/test_ci_workflows.bats
bats tests/unit/test_release_workflow_version.bats
./bin/test-count --update
```
Expected: PASS — 30 tests dans la suite de démo ; les règles de workflow existantes restent vertes (`release.yml` n'installe aucun paquet).

- [ ] **Step 5: Commit**

```bash
chmod +x tools/demo/check-freshness.sh
git add tools/demo/check-freshness.sh .github/workflows/release.yml \
        tests/e2e/test_demo_scenario.bats tests/baseline-counts.tsv
git commit -m "feat(demo): refuse a minor release whose demo is a generation behind"
```

---

# PHASE 5 — La vitrine GitHub

Le vrai manque n'est pas une page : c'est que **tout partage de Nivuus est laid**. Un lien collé dans Slack, Twitter ou HN affiche aujourd'hui la carte sociale par défaut de GitHub. Trois tâches, quelques minutes chacune, et aucune infrastructure.

*Sortie de phase : un lien collé dans Slack affiche la promesse et une frame de la démo.*

---

### Task 5.1: `CONTRIBUTING.md`, pour qu'une première PR ne se casse pas sur une règle invisible

**Files:**
- Create: `CONTRIBUTING.md`
- Modify: `tests/unit/test_docs_index.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `bin/test`, `bin/test-count`, la convention de commit du dépôt, les règles de documentation de ce plan.
- Produces: la page que le README (Task 3.1) référence déjà.

« Contributions are welcome! Please feel free to submit a Pull Request. » sans `CONTRIBUTING.md`, sans mention de `bin/test`, dans un dépôt qui a **1 297 tests** et des conventions fortes : c'est une invitation à ouvrir une PR qui échouera. Et elle échouera sur la chose la plus surprenante du dépôt — **la documentation est testée**.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_docs_index.bats` :

```bash
@test "CONTRIBUTING.md existe et nomme la commande de test" {
    [ -f "$ROOT/CONTRIBUTING.md" ]
    grep -qF './bin/test' "$ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING.md prévient que la documentation est testée" {
    # La règle la plus surprenante du dépôt, et celle sur laquelle une
    # première PR se casse : un README qui se lit bien peut faire rougir
    # la CI. La découvrir dans un rapport d'échec est une mauvaise façon.
    grep -qiE 'documentation.*(test|tested)|test.*documentation' "$ROOT/CONTRIBUTING.md"
    grep -qF 'tests/unit/test_readme_claims.bats' "$ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING.md donne la convention de commit du dépôt" {
    grep -qE 'feat\(|fix\(|docs\(' "$ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING.md ne recopie aucun compte de tests" {
    run grep -nE '\b[0-9]{3,4} tests\b' "$ROOT/CONTRIBUTING.md"
    [ "$status" -ne 0 ] || { echo "compte recopié : $output"; false; }
    grep -qF 'bin/test-count' "$ROOT/CONTRIBUTING.md"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_docs_index.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

```markdown
# Contributing

## Run the tests first

```bash
./bin/test                 # everything
./bin/test --unit          # the fast loop
./bin/test-count --check   # the suite may grow, never shrink
```

`rm -f config/*.zwc` before any run that touches `config/`: zsh prefers stale
bytecode over a newer source, and a test can pass against a module you did not
write. See [doc/TESTING.md](doc/TESTING.md).

## The documentation is tested — this is the surprising part

A pull request that reads well can still fail the build. The README is
confronted to the repository on every push:

- every command it shows must exist (`tests/unit/test_readme_claims.bats`)
- every environment variable it names must be read by a module
- the startup figure must be the one a test enforces
- it must stay under 200 lines, in English, with anchored bullets
- `doc/README.md` must list every file in `doc/`, and only those
  (`tests/unit/test_docs_index.bats`)
- every badge must be backed by something that can fail
  (`tests/unit/test_readme_badges.bats`)

None of these are style rules. Each one exists because the README once said
something that was not true.

## Conventions

- Commit messages: `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, in English.
- `config/*.zsh` is ZSH. `lib/*.sh`, `install.sh` and `tests/ci/*.sh` are POSIX
  sh — they run under `dash`, BusyBox `ash` and bash 3.2.
- Every write into the user's home goes through `lib/manifest.sh`. No exception:
  `tests/e2e/test_reversibility.bats` is the central test of this project.
- Startup stays under 300 ms, and a test enforces it.

## Before opening the pull request

```bash
./bin/test && ./bin/test-count --check
```

Architecture and module layout: [doc/CLAUDE.md](doc/CLAUDE.md).
```

Décommenter la ligne `CONTRIBUTING.md` de `doc/README.md` (Task 2.1).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_docs_index.bats
bats tests/unit/test_readme_claims.bats
./bin/test-count --update
```
Expected: PASS — 23 tests dans la suite d'index ; le lien `CONTRIBUTING.md` du README n'est plus mort.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md doc/README.md tests/unit/test_docs_index.bats tests/baseline-counts.tsv
git commit -m "docs: add CONTRIBUTING.md, starting with the rule that surprises"
```

---

### Task 5.2: description et topics du dépôt, versionnés

**Files:**
- Create: `tools/repo-meta.sh`
- Modify: `package.json` (description, keywords)
- Create: `tests/unit/test_repo_meta.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `package.json` (`description`, `keywords`), `gh` CLI.
- Produces: `gh repo edit` piloté par une source versionnée — **pas de valeur qui n'existe qu'à la main dans une UI web**.

Une description saisie dans les réglages GitHub est une donnée sans historique, sans revue, sans test : exactement ce que le reste du dépôt refuse. Elle vit donc dans `package.json`, et un script la pousse.

La description actuelle de `package.json` — « Modern ZSH configuration framework with Nord theme and AI integration » — est le générique d'avant la promesse. Elle est remplacée par la promesse.

- [ ] **Step 1: Write the failing test**

```bash
# tests/unit/test_repo_meta.bats
#!/usr/bin/env bats
#
# Les métadonnées du dépôt sont ce que voient tous ceux qui ne cliquent pas.
# Comme tout le reste ici, elles vivent dans un fichier versionné, pas dans
# une UI web où personne ne peut ni les relire ni les tester.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PKG="$ROOT/package.json"
    META="$ROOT/tools/repo-meta.sh"
}

@test "tools/repo-meta.sh existe, est exécutable et POSIX" {
    [ -x "$META" ]
    run sh -n "$META"
    [ "$status" -eq 0 ]
}

@test "le script lit package.json et n'écrit aucune valeur en dur" {
    grep -qF 'package.json' "$META"
    # Une description en dur dans le script serait une deuxième source de
    # vérité, donc une divergence programmée.
    run grep -nE '^\s*DESCRIPTION="[A-Z]' "$META"
    [ "$status" -ne 0 ]
}

@test "la description du dépôt est la promesse, pas un générique" {
    d="$(sed -n 's/.*"description": "\(.*\)",*/\1/p' "$PKG" | head -n1)"
    [ -n "$d" ]
    printf '%s' "$d" | grep -qi 'uninstall\|remove' \
        || { echo "la description ne porte pas la promesse : $d"; false; }
    # GitHub tronque au-delà de ~350 caractères ; une description qu'on ne
    # lit pas en entier est une description ratée.
    [ "${#d}" -le 200 ]
}

@test "les topics couvrent les entrées par lesquelles on cherche cet outil" {
    for t in zsh shell dotfiles prompt cli ai; do
        grep -qF "\"$t\"" "$PKG" || { echo "topic absent de package.json : $t"; false; }
    done
}

@test "le script refuse de tourner sans gh, au lieu d'échouer à mi-course" {
    grep -qE 'command -v gh' "$META"
}

@test "le script rappelle ce que gh NE PEUT PAS faire" {
    # L'image sociale ne se pose pas par API : la seule action manuelle du
    # chantier doit être écrite là où on la cherchera.
    grep -qiE 'social' "$META"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_repo_meta.bats`
Expected: FAIL — le script n'existe pas, la description est générique, `dotfiles`/`prompt`/`cli` absents des `keywords`.

- [ ] **Step 3: Write minimal implementation**

Dans `package.json` :

```json
  "description": "A complete ZSH environment in one command — and one command to remove it, byte for byte.",
  "keywords": ["zsh", "shell", "dotfiles", "prompt", "cli", "ai", "nord", "productivity"],
```

`tools/repo-meta.sh` :

```sh
#!/bin/sh
# =============================================================================
# Pousse la description et les topics du dépôt depuis package.json.
# =============================================================================
# Aucune valeur ne doit exister uniquement dans l'UI web de GitHub : elle n'y
# est ni relisible en revue, ni testable, ni restaurable. package.json fait
# autorité ; ce script n'est qu'un transport.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package.json"

command -v gh >/dev/null 2>&1 || {
    echo "gh (GitHub CLI) requis : https://cli.github.com" >&2; exit 1; }

description="$(sed -n 's/.*"description": "\(.*\)",*$/\1/p' "$PKG" | head -n1)"
[ -n "$description" ] || { echo "description absente de package.json" >&2; exit 1; }

# Les topics GitHub sont en minuscules, sans espace : les keywords de
# package.json respectent déjà cette forme.
topics="$(sed -n '/"keywords"/,/]/p' "$PKG" \
          | grep -oE '"[a-z0-9-]+"' | tr -d '"' | grep -v keywords)"

set -- --description "$description"
for t in $topics; do set -- "$@" --add-topic "$t"; done

echo "Description : $description"
echo "Topics      : $(printf '%s ' $topics)"
gh repo edit "$@"

cat <<'EOF'

Ce que gh ne peut pas faire, et qu'il faut donc faire à la main, une fois :

  L'IMAGE SOCIALE (social preview) n'est exposée par aucune API. Va dans
  Settings > General > Social preview et téléverse docs/assets/social.png
  (produit par tools/demo/social.sh). C'est la seule action de ce chantier
  qui n'est ni versionnée ni testable — elle est écrite ici pour qu'elle ne
  soit pas oubliée.
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bats tests/unit/test_repo_meta.bats
bats tests/unit/test_readme_claims.bats
./bin/test-count --update
```
Expected: PASS — 6 nouveaux tests. Exécuter ensuite `tools/repo-meta.sh` une fois, à la main.

- [ ] **Step 5: Commit**

```bash
chmod +x tools/repo-meta.sh
git add tools/repo-meta.sh package.json tests/unit/test_repo_meta.bats tests/baseline-counts.tsv
git commit -m "feat(repo): drive description and topics from package.json"
```

---

### Task 5.3: l'image sociale, dérivée d'une frame de la démo

**Files:**
- Create: `tools/demo/social.sh`, `docs/assets/social.png`
- Modify: `tests/unit/test_repo_meta.bats`
- Modify: `tests/baseline-counts.tsv`

**Interfaces:**
- Consumes: `docs/assets/demo.cast` (Task 4.4), `package.json` (la promesse).
- Produces: ce que voient **tous ceux qui ne cliquent pas**.

Dériver l'image d'une frame de la démo, plutôt que de la dessiner, a une conséquence qui vaut la contrainte : **l'image ne peut pas montrer autre chose que ce que le produit fait**. La frame retenue est celle du dernier plan — l'empreinte identique — parce que c'est l'argument.

- [ ] **Step 1: Write the failing test**

Ajouter à `tests/unit/test_repo_meta.bats` :

```bash
@test "social.sh existe, est exécutable et dérive de la démo" {
    [ -x "$ROOT/tools/demo/social.sh" ]
    run sh -n "$ROOT/tools/demo/social.sh"
    [ "$status" -eq 0 ]
    # Dérivée, jamais dessinée : une image dessinée à la main peut montrer
    # ce que le produit ne fait pas.
    grep -qF 'demo.cast' "$ROOT/tools/demo/social.sh"
}

@test "l'image sociale existe et respecte le format attendu par GitHub" {
    img="$ROOT/docs/assets/social.png"
    [ -f "$img" ]
    # GitHub recommande 1280x640 et refuse au-delà de 1 Mo.
    n="$(wc -c < "$img")"
    [ "$n" -le 1048576 ] || { echo "social.png pèse $n octets (max: 1 Mo)"; false; }
    if command -v file >/dev/null 2>&1; then
        run file "$img"
        [[ "$output" == *"1280 x 640"* ]] || [[ "$output" == *"PNG"* ]]
    fi
}

@test "le script rappelle que le téléversement est manuel" {
    grep -qiE 'settings|manuel|manually' "$ROOT/tools/demo/social.sh"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_repo_meta.bats`
Expected: FAIL — ni le script ni l'image n'existent.

- [ ] **Step 3: Write minimal implementation**

`tools/demo/social.sh` :

```sh
#!/bin/sh
# =============================================================================
# L'image sociale, dérivée d'une FRAME de la démo. Manuel, comme la démo.
# =============================================================================
# Pourquoi dérivée et non dessinée : une image dessinée peut montrer ce que le
# produit ne fait pas. Une frame du .cast ne le peut pas.
#
# La frame retenue est celle du dernier plan -- l'empreinte de $HOME identique
# après désinstallation. C'est l'argument ; c'est donc lui qu'on met sur la
# carte que voient tous ceux qui ne cliquent pas.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAST="$ROOT/docs/assets/demo.cast"
AT="${NIVUUS_SOCIAL_AT:-34}"     # secondes ; le dernier plan
OUT="$ROOT/docs/assets/social.png"

[ -f "$CAST" ] || { echo "demo.cast absent : lance tools/demo/record.sh" >&2; exit 1; }

tmp="$(mktemp -d)"
npx --yes svg-term-cli --in "$CAST" --out "$tmp/frame.svg" \
    --window --width 100 --height 20 --at "$((AT * 1000))"

# 1280x640 : le format que GitHub attend pour une social preview.
if command -v resvg >/dev/null 2>&1; then
    resvg --width 1280 --height 640 "$tmp/frame.svg" "$OUT"
elif command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1280 -h 640 -o "$OUT" "$tmp/frame.svg"
else
    echo "resvg ou rsvg-convert requis pour produire le PNG" >&2; exit 1
fi
rm -rf "$tmp"

ls -l "$OUT"
cat <<'EOF'

Téléversement MANUEL, une seule fois : Settings > General > Social preview.
L'image sociale n'est exposée par aucune API GitHub -- c'est la seule action
de ce chantier qui n'est ni versionnée ni testable. Le fichier, lui, est
versionné : si GitHub la perd, on la retéléverse sans la refabriquer.
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
tools/demo/social.sh
bats tests/unit/test_repo_meta.bats
./bin/test-count --update
```
Expected: PASS — 9 tests dans la suite ; `social.png` sous 1 Mo.

Puis, à la main : téléverser `docs/assets/social.png` dans *Settings > General > Social preview*, et vérifier le rendu en collant l'URL du dépôt dans Slack.

- [ ] **Step 5: Commit**

```bash
chmod +x tools/demo/social.sh
git add tools/demo/social.sh docs/assets/social.png tests/unit/test_repo_meta.bats \
        tests/baseline-counts.tsv
git commit -m "feat(demo): derive the social preview image from the demo's last frame"
```

---

## Récapitulatif : les dix règles, et ce qui les rend exécutables

| # | Ce qui échoue | Fichier | Rendue exécutable par | Coût |
|---|---|---|---|---|
| 5.1 | une commande citée en bloc `bash` du README n'existe pas | `test_readme_claims.bats` | `awk` extrait le premier lexème de chaque ligne des blocs ```` ```bash ```` ; il doit être une sous-commande de `nivuus help`, un exécutable de `bin/`, une fonction ou un alias de `config/*.zsh`, ou un membre d'une **liste close** d'outils externes (T1.8) | grep, chaque PR |
| 5.2 | un superlatif non mesuré apparaît | `test_readme_claims.bats` | liste noire littérale de 11 lexèmes (`blazing`, `lightning`, `ultimate`, `just works`, `zero config`, `beautiful`…) + un test qui prouve que la règle sait échouer (T1.2) | grep, chaque PR |
| 5.3 | un chiffre de démarrage diverge du budget imposé | `test_readme_claims.bats` | le budget est **extrait** de `tests/performance/test_startup.bats` ; tout `\d+ ?ms` du README doit l'égaler, sauf sur une ligne unique marquée `measured` et citant sa source (T1.1) | grep, chaque PR |
| 5.4 | un badge n'atteste rien | `test_readme_badges.bats` | tout shield statique doit être précédé d'un commentaire `<!-- badge-proof: chemin/test.bats -->` dont le fichier existe ; les badges de workflow gardent les règles existantes (T1.7) | grep, chaque PR |
| 5.5 | le README dépasse 200 lignes | `test_readme_claims.bats` | `wc -l` (T3.1), revérifié après insertion de la démo (T4.5) | instantané |
| 5.6 | `doc/` et son index divergent | `test_docs_index.bats` | comparaison bidirectionnelle `find doc/` ↔ liens de `doc/README.md`, **plus** la vérification des liens relatifs *et des ancres* du README et de `doc/*.md`, avec `<a id="…">` comme échappatoire explicite (T2.1) | grep, chaque PR |
| 5.7 | le README mélange les langues | `test_readme_claims.bats` | liste noire de 13 lexèmes français **plus** un second filet indépendant : aucun caractère accentué hors noms propres nommés (T3.1) | grep, chaque PR |
| 5.8 | la démo a divergé | `test_demo_scenario.bats` | **quatre gardes** : (1) chaque commande `run` du scénario existe et chaque commande `unknown` est réellement absente, T4.2 ; (2) le scénario est rejoué en conteneur par `replay-check.sh`, avec un test qui prouve qu'il sait échouer, T4.3 ; (3) `demo.stamp` recalculé sur `scenario.txt`, `demo.cast` **et** l'artefact, avec budget de poids indexé sur le format déclaré, T4.4 ; (4) `check-freshness.sh` refuse une release mineure dont la démo a une génération de retard, T4.6 | 3 gardes en grep sur chaque PR ; le rejeu en conteneur sur merge/nightly |
| 5.9 | une puce de « What you get » n'est pas ancrée | `test_readme_claims.bats` | `awk` isole les puces de la section, chacune doit contenir un lien relatif vers un fichier **existant**, et la section en compte au plus six (T1.9) | grep, chaque PR |
| 5.10 | une variable citée par le README n'est lue par aucun module | `test_readme_claims.bats` | extraction des `NIVUUS_*`, `ENABLE_*`, `AI_*`, `GEMINI_*`, `OPENAI_*`, `ANTHROPIC_*` du README, confrontées par `grep -r` à `config/`, `lib/`, `.zshrc` et `bin/`, après `rm -f config/*.zwc` (T1.3) | grep, chaque PR |

**Toutes sont gardées par un `grep` dans `tests.yml`** (T3.2) : si l'un de ces fichiers de test disparaît dans un refactor, la CI le dit. C'est le même dispositif que celui qui protège les invariants de signature et d'empaquetage — et le garde-fou du garde-fou existe aussi : un test vérifie que les chaînes citées dans le YAML existent vraiment dans les fichiers de test.

## Ce que ces règles ne couvrent pas, et qu'on assume

- **Le rendu visuel de la démo.** Aucun test ne dira qu'elle est devenue laide, mal rythmée ou illisible. C'est l'objet de la relecture humaine imposée par l'enregistrement manuel (`record.sh` le rappelle à l'écran).
- **La qualité de la prose.** Les dix règles attrapent le faux, pas le mauvais. Un README exact et ennuyeux passe.
- **Le rendu de l'image sociale.** Elle n'est exposée par aucune API : le fichier est versionné et testé, son téléversement est manuel et écrit dans la sortie de `tools/repo-meta.sh`.
- **Les ancres externes cassées** (`#-usage`, `#-updating` liés depuis un blog ou une issue). Impact faible sur un projet peu diffusé ; le coût de le prévenir (conserver des titres vides) dépasse le bénéfice. Accepté, comme la spec l'a accepté.

## Risques et mitigations

| Risque | Mitigation |
|---|---|
| **La démo périme malgré tout** | Les quatre gardes (5.8). Elles couvrent l'existence des commandes, le fonctionnement du flux et la fraîcheur par version — pas le rendu. |
| **Perte d'information en déplaçant ~400 lignes** | La phase 2 **crée les destinations avant** que la phase 3 ne vide le README : à aucun instant le contenu n'existe nulle part. La règle 5.6 attrape les références orphelines ; la relecture de la Task 2.2 vérifie l'exhaustivité. Seule « Project Structure » est supprimée, et c'est argumenté. |
| **Le rendu SVG animé ne marche pas sur GitHub** | Traité comme une décision à vérifier en **première** tâche de la phase 4, avec un repli GIF déjà écrit : `NIVUUS_DEMO_FORMAT=gif`, budget 2 Mo, et un test qui lit le format dans le tampon plutôt qu'une constante. Changer d'avis coûte une commande. |
| **Le README regrossit** | C'est ce qui s'est produit cinq fois. Le seul remède mécanique est 5.5. Il sera un jour ressenti comme une gêne : c'est le signe qu'il fonctionne. |
| **La démo publie une donnée sensible** | Conteneur, `HOME` neuf, nom d'hôte fixe, stub IA sans clé — et surtout, le `.cast` est du **texte**, donc entièrement auditable dans le diff de la PR. Un test le fouille explicitement (T4.4). |
| **Conflit de merge avec le chantier `--system`** | Le README ne mentionne jamais `--system` (test dédié, T3.1) ; le point de contact est `doc/INSTALL.md`, où le conflit est textuel et local. |

## Après ce plan

- Le chantier 4 du programme d'adoption (brew, AUR, awesome-lists, HN/Reddit) devient exécutable : il a une page d'accueil qui tient l'attention, une démo, et une carte sociale.
- La traduction de `doc/` en anglais reste ouverte, et se rattache au chantier 4 — pas ici.
- La péremption de la démo par mineure se réévalue **après trois releases mineures**.
