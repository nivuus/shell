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

# Imprime chaque lien relatif d'un fichier.
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
    grep -qF 'SECURITY.md' "$DOC/INSTALL.md"
}

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
