#!/bin/sh
# =============================================================================
# Dépendances de la suite de tests Nivuus, pour toutes les cibles de la matrice.
# =============================================================================
# POSIX sh : ce script tourne dans un conteneur Alpine *avant* que bash n'existe.
# C'est le SEUL endroit du dépôt qui appelle un gestionnaire de paquets pour la
# CI ; les workflows passent par .github/actions/setup-tests.
#
# Note délibérée : openssl et ssh-keygen ne sont PAS installés ici. Le test
# « aucun outil de vérification » (tests/unit/test_lib_steps_verify_tools.bats)
# n'a de valeur que sur une image qui n'en a réellement aucun. Les suites de
# signature qui en ont besoin passent par tests/ci/install-verify-tools.sh.
set -eu

BATS_VERSION="${BATS_VERSION:-v1.11.1}"
PREFIX="${PREFIX:-/usr/local}"

# `sudo` seulement si nécessaire : dans un conteneur on est root et sudo n'existe pas.
SUDO=''
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO='sudo'
fi

# Best-effort : GNU parallel n'est pas dans tous les dépôts par défaut, et son
# absence ne fait que désactiver `bats --jobs` (voir tests/ci/bats-run.sh).
_optional() { "$@" >/dev/null 2>&1 || true; }

install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
            zsh git curl ca-certificates jq procps diffutils
        _optional env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq parallel
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache bash zsh git curl ca-certificates ncurses jq procps diffutils
        _optional $SUDO apk add --no-cache parallel
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm --needed zsh git curl jq procps-ng diffutils
        _optional $SUDO pacman -S --noconfirm --needed parallel
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf -y --setopt=install_weak_deps=False install \
            zsh git curl ca-certificates jq procps-ng diffutils
        _optional $SUDO dnf -y install parallel
    elif command -v brew >/dev/null 2>&1; then
        # macOS fournit déjà zsh, git, curl. jq est présent sur les runners GitHub.
        _optional brew install --quiet parallel
        command -v jq >/dev/null 2>&1 || brew install --quiet jq
    else
        echo "install-deps: aucun gestionnaire de paquets connu" >&2
        exit 1
    fi
}

# bats depuis le dépôt amont, à version épinglée : les paquets distro vont de
# 1.2.1 (Ubuntu 22.04) à 1.10, et n'ont ni --count, ni --filter-tags, ni --formatter.
install_bats() {
    if command -v bats >/dev/null 2>&1 &&
       bats --version 2>/dev/null | grep -q "${BATS_VERSION#v}"; then
        echo "install-deps: bats ${BATS_VERSION} déjà présent"
        return 0
    fi
    tmp="$(mktemp -d)"
    git clone --quiet --depth 1 --branch "$BATS_VERSION" \
        https://github.com/bats-core/bats-core.git "$tmp/bats-core"
    $SUDO "$tmp/bats-core/install.sh" "$PREFIX" >/dev/null
    rm -rf "$tmp"
}

install_packages
install_bats

echo "install-deps: $(zsh --version), $(bats --version), $(git --version)"
