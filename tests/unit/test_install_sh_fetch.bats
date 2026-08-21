#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin" "$TMP/www"
    printf 'contenu servi\n' > "$TMP/www/fichier.txt"
    LOG="$TMP/appels.log"
}

teardown() { rm -rf "$TMP"; }

# Exécute une fonction d'install.sh sans déclencher l'installation : le
# fichier ne fait rien tant que NIVUUS_SOURCE_ONLY est posée.
sh_fn() {
    env NIVUUS_SOURCE_ONLY=1 "${TEST_SHELL:-sh}" -c ". '$SH'; $*"
}

# Faux curl / faux wget : ils journalisent leur ligne de commande puis
# écrivent le contenu attendu. C'est la SÉLECTION qu'on teste, pas le
# téléchargement.
fake_downloader() {
    cat > "$TMP/bin/$1" <<EOS
#!/bin/sh
printf '%s %s\n' "$1" "\$*" >> "$LOG"
dest=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -o|-O) shift; dest="\$1" ;;
    esac
    shift
done
[ -n "\$dest" ] || exit 3
printf 'contenu servi\n' > "\$dest"
EOS
    chmod +x "$TMP/bin/$1"
}

@test "file:// est servi par copie, sans client HTTP du tout" {
    run env PATH="$TMP/bin:/usr/bin:/bin" NIVUUS_SOURCE_ONLY=1 sh -c \
        ". '$SH'; nivuus_fetch 'file://$TMP/www/fichier.txt' '$TMP/out'"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/out")" = "contenu servi" ]
    [ ! -f "$LOG" ]
}

@test "file:// inexistant échoue au lieu de produire un fichier vide" {
    run sh_fn "nivuus_fetch 'file://$TMP/www/absent.txt' '$TMP/out'"
    [ "$status" -ne 0 ]
    [ ! -f "$TMP/out" ]
}

@test "curl est préféré quand les deux sont là" {
    fake_downloader curl; fake_downloader wget
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -eq 0 ]
    run cat "$LOG"
    [[ "$output" == curl* ]]
    [[ "$output" != *wget* ]]
}

@test "wget prend le relais quand curl est absent" {
    fake_downloader wget
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -eq 0 ]
    run cat "$LOG"
    [[ "$output" == wget* ]]
}

@test "curl est invoqué en échec-dur (-f) et en suivant les redirections (-L)" {
    fake_downloader curl
    env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    run cat "$LOG"
    [[ "$output" == *"-fsSL"* ]]
}

@test "ni curl ni wget : refus explicite, avec la marche à suivre" {
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c \
        ". '$SH'; nivuus_fetch 'https://exemple.invalide/x' '$TMP/out'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"wget"* ]]
    [ ! -f "$TMP/out" ]
}

@test "nivuus_sha256 donne la même somme que l'outil du système" {
    printf 'abc\n' > "$TMP/f"
    expected="$( { sha256sum "$TMP/f" 2>/dev/null || shasum -a 256 "$TMP/f"; } | awk '{print $1}')"
    run sh_fn "nivuus_sha256 '$TMP/f'"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "aucun outil sha256 : refus, jamais de contournement" {
    printf 'abc\n' > "$TMP/f"
    run env PATH="$TMP/bin" NIVUUS_SOURCE_ONLY=1 /bin/sh -c ". '$SH'; nivuus_sha256 '$TMP/f'"
    [ "$status" -ne 0 ]
}
