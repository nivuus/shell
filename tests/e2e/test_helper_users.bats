#!/usr/bin/env bats
#
# Le helper qui porte TOUTE la partie privilégiée de la preuve système.
# Marqué `docker` : il crée de vrais comptes, il n'a rien à faire sur un
# runner ni sur le poste de quelqu'un (voir tests/ci/bats-run.sh).

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

# Rejoue le helper dans un conteneur : c'est le seul contexte où créer un
# compte est acceptable.
in_image() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c "
        set -e
        cp -r /src /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null 2>&1 || true
        . ./tests/helpers/users.bash
        $2
    "
}

# bats test_tags=docker
@test "mk_user / as_user / rm_user sur debian:12 (useradd)" {
    run in_image debian:12 '
        mk_user alice
        test -d "$(user_home alice)"
        as_user alice "id -un" | grep -qx alice
        as_user alice "printf %s \"\$HOME\"" | grep -q "/home/alice"
        rm_user alice
        ! id alice >/dev/null 2>&1
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "mk_user / as_user / rm_user sur alpine:3.20 (adduser BusyBox)" {
    run in_image alpine:3.20 '
        mk_user bob
        test -d "$(user_home bob)"
        as_user bob "id -un" | grep -qx bob
        rm_user bob
        ! id bob >/dev/null 2>&1
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "mk_user est idempotent (rejouer un script de preuve ne doit pas échouer)" {
    run in_image debian:12 'mk_user alice; mk_user alice; rm_user alice'
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "as_user n'hérite PAS du HOME de root" {
    # Le piège qui invaliderait toute la preuve : su -c au lieu de su -l.
    run in_image debian:12 '
        mk_user alice
        as_user alice "printf %s \"\$HOME\"" | grep -qv "^/root$"
        rm_user alice
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "count_regular_users compte les comptes humains, sans lire /home" {
    run in_image debian:12 '
        avant="$(count_regular_users)"
        mk_user alice; mk_user bob
        apres="$(count_regular_users)"
        test "$apres" -eq "$((avant + 2))"
        rm_user alice; rm_user bob
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "users_require_root skippe proprement sans privilège" {
    run in_image debian:12 '
        useradd -m -s /bin/sh nobody2
        su -l nobody2 -c "cd /work && . ./tests/helpers/users.bash; users_require_root && echo NON_ATTENDU || echo REFUS_OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUS_OK"* ]]
}
