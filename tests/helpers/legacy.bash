# tests/helpers/legacy.bash
# Reproduit, depuis le dépôt lui-même, l'état qu'une installation v3.0.0
# laissait dans $HOME. Aucun binaire vendu dans tests/ : l'arbre vient du
# tag v3.0.0, et les effets de bord de l'ancien installeur sont recopiés
# depuis `git show v3.0.0:install.sh` -- références de lignes en commentaire
# pour que la reproduction reste vérifiable.

legacy_install() {
    local home="$1" prefix="$2" root="$3"

    if ! git -C "$root" rev-parse -q --verify refs/tags/v3.0.0 >/dev/null 2>&1; then
        printf '%s\n' "Le tag v3.0.0 est requis par ce test (git fetch --tags ; en CI : fetch-tags)." >&2
        return 1
    fi

    mkdir -p "$prefix" "$home"
    git -C "$root" archive --format=tar v3.0.0 | tar -x -C "$prefix"
    # install.sh:270 -- « Created version file »
    printf '3.0.0\n' > "$prefix/.version"

    # install.sh:257-261 -- « cat > $HOME/.zshrc », sans le moindre marqueur.
    cat > "$home/.zshrc" <<EOS
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="$prefix"
source "\$NIVUUS_SHELL_DIR/.zshrc"
EOS

    # install.sh:284+ -- « create_local_config », créé s'il n'existe pas.
    if [ ! -f "$home/.zsh_local" ]; then
        cat > "$home/.zsh_local" <<'EOS'
# Nivuus Shell - Local Configuration
# This file is for your personal customizations
EOS
    fi

    # install.sh:334-346 -- « init_git_repo », la cause du problème n° 8 du spec.
    ( cd "$prefix"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1

    # install.sh:419 -- horodatage de dernière vérification.
    date +%s > "$home/.nivuus-shell-last-update-check"
}
