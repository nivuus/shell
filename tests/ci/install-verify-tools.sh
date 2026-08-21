#!/bin/sh
# =============================================================================
# openssl et ssh-keygen, pour les suites de signature qui GÉNÈRENT leurs clés.
# =============================================================================
# Délibérément séparé de install-deps.sh, et ce n'est pas une commodité :
# tests/unit/test_lib_steps_verify_tools.bats ne prouve le code de retour 2
# (« aucun outil de vérification ») que sur une image qui n'en a réellement
# aucun -- alpine:3.20 est la seule. Ce script s'appelle donc APRÈS ce test,
# jamais avant. Voir doc/SIGNING.md et .github/workflows/tests.yml (e2e-alpine).
set -eu

SUDO=''
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO='sudo'
fi

if command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache openssl openssh-keygen
elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq openssl openssh-client
elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm --needed openssl openssh
elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf -y --setopt=install_weak_deps=False install openssl openssh
elif command -v openssl >/dev/null 2>&1 || command -v ssh-keygen >/dev/null 2>&1; then
    : # macOS : les deux sont fournis par le système.
else
    echo "install-verify-tools: aucun gestionnaire de paquets connu" >&2
    exit 1
fi

echo "install-verify-tools: openssl=$(command -v openssl || echo ABSENT), ssh-keygen=$(command -v ssh-keygen || echo ABSENT)"
