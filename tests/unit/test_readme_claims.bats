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
