#!/bin/sh
# =============================================================================
# Lance une suite bats comme la CI le fait.
# =============================================================================
# - TAP13, pour que le plan (`1..N`) soit toujours lisible en tête de sortie.
# - --jobs seulement si GNU parallel est là ET si la suite y gagne (mesuré :
#   e2e 60s -> 26s ; unit 25s -> 30s, donc unit reste en série).
# - Les tests marqués `docker` sont exclus par défaut : ils tirent des images
#   entières et n'ont leur place que dans la matrice nightly.
set -eu

JOBS="${NIVUUS_BATS_JOBS:-4}"
ARGS="--formatter tap13"

# Une SEULE option --filter-tags : chez bats, deux occurrences se combinent
# en OU, ce qui n'exclurait plus rien. Les exclusions se cumulent par virgule.
EXCLUDE=''
if [ "${NIVUUS_CI_DOCKER:-}" != "1" ]; then
    EXCLUDE="!docker"
fi
if [ -n "$EXCLUDE" ]; then
    ARGS="$ARGS --filter-tags $EXCLUDE"
fi

# La parallélisation ne s'applique qu'aux suites où elle a été mesurée gagnante.
wants_jobs=no
for d in "$@"; do
    case "$d" in
        *e2e*) wants_jobs=yes ;;
    esac
done

if [ "$wants_jobs" = yes ] && command -v parallel >/dev/null 2>&1; then
    ARGS="$ARGS --jobs $JOBS"
fi

# shellcheck disable=SC2086
exec bats $ARGS "$@"
