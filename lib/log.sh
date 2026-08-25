# Sortie utilisateur. Aucune connaissance du métier.
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.
#
# Les couleurs viennent de lib/charte.sh et de nulle part ailleurs : ne pas
# réintroduire de code ANSI ici. Aucun gris — le second plan passe par le
# gras (charte § 2.2). Chaque helper porte un glyphe qui se lit en noir et
# blanc, parce que la couleur ne s'emploie jamais seule (charte § 2.4).

_nivuus_log_here="$(dirname -- "${BASH_SOURCE[0]:-$0}")"
[ -f "$_nivuus_log_here/charte.sh" ] && . "$_nivuus_log_here/charte.sh"
unset _nivuus_log_here

log_info()  { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_BUSY:-}·${NIVUUS_C_OFF:-} $*"; }
log_ok()    { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_OK:-}✓${NIVUUS_C_OFF:-} $*"; }
log_warn()  { printf '%s\n' "${NIVUUS_C_WARN:-}!${NIVUUS_C_OFF:-} $*" >&2; }
log_error() { printf '%s\n' "${NIVUUS_C_DANGER:-}✗${NIVUUS_C_OFF:-} $*" >&2; }
log_dry()   { [ -n "${NIVUUS_QUIET:-}" ] && return 0; printf '%s\n' "${NIVUUS_C_STRONG:-}[dry-run]${NIVUUS_C_OFF:-} $*"; }
