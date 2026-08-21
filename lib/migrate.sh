# lib/migrate.sh
# Reconnaît le dépôt git que l'ancien init_git_repo() (v3.0.0,
# install.sh:334-346) créait dans ~/.nivuus-shell -- et que
# config/20-autoupdate.zsh prend pour un checkout de développement, ce qui
# désactive silencieusement l'auto-update de toutes les installations
# issues du one-liner historique.
#
# Ce module ne fait que CONSTATER. Il n'écrit rien, jamais : le
# déplacement passe par lib/manifest.sh, seule bibliothèque autorisée à
# toucher au système de fichiers.
# POSIX / bash 3.2 : sourcé par bin/nivuus, bin/healthcheck et, à la
# demande, par config/20-autoupdate.zsh.

NIVUUS_LEGACY_COMMIT_SUBJECT='Initial Nivuus Shell installation'
# Les deux formes sous lesquelles l'amont a pu être enregistré. v3.0.0
# écrivait la forme SSH ; la forme HTTPS est acceptée parce qu'un
# utilisateur a pu la corriger à la main en tentant de réparer sa mise à
# jour -- ce qui ne fait pas de son répertoire un dépôt de travail.
NIVUUS_LEGACY_REMOTES='git@github.com:maximeallanic/nivuus-shell.git
https://github.com/maximeallanic/nivuus-shell.git
https://github.com/maximeallanic/nivuus-shell'

# Imprime exactement un mot : none | legacy | dev | unknown.
# En cas de doute, « dev » -- c'est-à-dire : on ne touche à rien.
nivuus_git_state() {
    local dir="$1" subject remotes url branches

    if [ -f "$dir/.git" ]; then
        # Fichier et non répertoire : worktree lié ou submodule. Jamais le nôtre.
        printf 'dev\n'; return 0
    fi
    if [ ! -d "$dir/.git" ]; then
        printf 'none\n'; return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        printf 'unknown\n'; return 0
    fi

    # (2) exactement un commit
    [ "$(git -C "$dir" rev-list --count HEAD 2>/dev/null || printf 0)" = "1" ] \
        || { printf 'dev\n'; return 0; }

    # (3) le message de l'installeur, mot pour mot
    subject="$(git -C "$dir" log -1 --format=%s 2>/dev/null || printf '')"
    [ "$subject" = "$NIVUUS_LEGACY_COMMIT_SUBJECT" ] || { printf 'dev\n'; return 0; }

    # (4) aucun remote, ou « origin » seul et pointant sur l'amont
    remotes="$(git -C "$dir" remote 2>/dev/null || printf '')"
    if [ -n "$remotes" ]; then
        [ "$remotes" = "origin" ] || { printf 'dev\n'; return 0; }
        url="$(git -C "$dir" remote get-url origin 2>/dev/null || printf '')"
        printf '%s\n' "$NIVUUS_LEGACY_REMOTES" | grep -qxF "$url" \
            || { printf 'dev\n'; return 0; }
    fi

    # (5) aucun fichier SUIVI modifié. Les non-suivis (*.zwc compilés par
    # zsh à l'exécution) sont tolérés : ce n'est pas du travail.
    [ -z "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null || printf x)" ] \
        || { printf 'dev\n'; return 0; }

    # (6) aucun stash
    [ -z "$(git -C "$dir" stash list 2>/dev/null || printf x)" ] \
        || { printf 'dev\n'; return 0; }

    # (7) exactement une branche locale
    branches="$(git -C "$dir" for-each-ref --format='%(refname)' refs/heads 2>/dev/null | wc -l | tr -d ' ')"
    [ "$branches" = "1" ] || { printf 'dev\n'; return 0; }

    printf 'legacy\n'
}

# Ce que l'utilisateur a le droit de voir avant de décider. Lecture seule.
nivuus_git_report() {
    local dir="$1"
    [ -d "$dir/.git" ] || { printf 'Aucun dépôt git dans %s\n' "$dir"; return 0; }
    command -v git >/dev/null 2>&1 || { printf 'git indisponible : impossible de décrire %s/.git\n' "$dir"; return 0; }
    printf 'Dépôt git dans %s :\n' "$dir"
    printf '  commits            : %s\n' "$(git -C "$dir" rev-list --count HEAD 2>/dev/null || printf '?')"
    printf '  dernier message    : %s\n' "$(git -C "$dir" log -1 --format=%s 2>/dev/null || printf '?')"
    printf '  remotes            : %s\n' "$(git -C "$dir" remote -v 2>/dev/null | tr '\n' ' ' || printf 'aucun')"
    printf '  branches locales   : %s\n' "$(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | tr '\n' ' ')"
    printf '  fichiers modifiés  : %s\n' "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
    printf '  fichiers non suivis: %s\n' "$(git -C "$dir" status --porcelain --untracked-files=all 2>/dev/null | grep -c '^??' || printf 0)"
    printf '  stash              : %s\n' "$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')"
}
