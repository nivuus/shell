#!/bin/sh
# =============================================================================
# La séquence « preuve » d'une cible de la matrice : niveaux 2, 3 et 4.
# =============================================================================
# Exécuté à l'identique par .github/workflows/matrix.yml et par un rejeu
# local `docker run … ./tests/ci/run-target.sh`. Aucune logique de preuve ne
# vit dans le YAML : c'est ce qui rend la matrice testable avant tout push.
set -eu

NIVUUS_SHELL_DIR="${NIVUUS_SHELL_DIR:-$(pwd)}"
export NIVUUS_SHELL_DIR

# openssl / ssh-keygen d'abord. Raison mesurée sur alpine:3.20 : sans eux,
# `nivuus install` émet l'avertissement « installe l'un des deux : sudo
# apt-get install openssl » du chantier signature, et cette ligne fait
# échouer l'assertion large de tests/e2e/test_with_deps.bats
# (« --minimal skips the extras », qui interdit toute occurrence de
# "apt-get install" dans la sortie). Une cible de la matrice doit refléter
# une machine ordinaire, qui a l'un des deux outils. Le cas « aucun outil »
# reste prouvé, et seulement là où il est réel : le job Alpine nu de tests.yml.
./tests/ci/install-verify-tools.sh

echo "== Niveau 2 : installation réelle puis shell interactif réel =="
./tests/ci/bats-run.sh \
    tests/e2e/test_nivuus_cli.bats \
    tests/e2e/test_install_sh_compat.bats \
    tests/e2e/test_minimal_mode.bats \
    tests/e2e/test_platform.bats

# Un shell réellement interactif, hors bats : la preuve que l'installation
# produit un shell utilisable et silencieux sur stderr.
work="$(mktemp -d)"
HOME="$work/home"; export HOME; mkdir -p "$HOME"
NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"; export NIVUUS_STATE_DIR

"$NIVUUS_SHELL_DIR/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell"
zsh -i -c 'echo REAL_SHELL_OK' 2> "$work/stderr"
if [ -s "$work/stderr" ]; then
    echo "stderr non vide au démarrage du shell :" >&2
    cat "$work/stderr" >&2
    exit 1
fi
"$NIVUUS_SHELL_DIR/bin/nivuus" uninstall --yes --purge
rm -rf "$work"
unset HOME NIVUUS_STATE_DIR || true

echo "== Niveau 3 : réversibilité (empreinte de HOME bit-exacte) =="
./tests/ci/bats-run.sh tests/e2e/test_reversibility.bats

echo "== Niveau 4 : dry-run, double install, oh-my-zsh, cohabitation =="
./tests/ci/bats-run.sh tests/e2e/test_with_deps.bats tests/e2e/test_shell_load.bats

echo "== Cible OK =="
