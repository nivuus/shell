# Sortie utilisateur. Aucune connaissance du métier.
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _C_RED=$'\033[0;31m'; _C_GREEN=$'\033[0;32m'
    _C_YELLOW=$'\033[0;33m'; _C_BLUE=$'\033[0;34m'
    _C_DIM=$'\033[2m'; _C_OFF=$'\033[0m'
else
    _C_RED=''; _C_GREEN=''; _C_YELLOW=''; _C_BLUE=''; _C_DIM=''; _C_OFF=''
fi

log_info()  { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_BLUE}·${_C_OFF} $*"; }
log_ok()    { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_GREEN}✓${_C_OFF} $*"; }
log_warn()  { printf '%s\n' "${_C_YELLOW}!${_C_OFF} $*" >&2; }
log_error() { printf '%s\n' "${_C_RED}✗${_C_OFF} $*" >&2; }
log_dry()   { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${_C_DIM}[dry-run]${_C_OFF} $*"; }
