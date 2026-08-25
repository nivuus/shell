# Couleur des sorties Nivuus. Applique la charte graphique (socle 0.3.0).
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.
#
# Spec : docs/superpowers/specs/2026-08-24-charte-terminal-design.md
# Doc  : doc/CHARTE.md
#
# N'expose que sept variables et ne définit aucune fonction. Il n'y a aucun
# gris ici, et il ne doit jamais y en avoir : la charte les a tous retirés, et
# ce qu'ils portaient passe par NIVUUS_C_STRONG.
#
# Les huit valeurs viennent de assets/tokens.css du dépôt design. Ne pas les
# retoucher sans relancer tests/unit/test_charte_conformity.bats.

# --- Mode : explicite, puis COLORFGBG, puis sombre (charte § 2.2). ---
case "${NIVUUS_CHARTE_MODE:-}" in
    light|dark) _nivuus_charte_mode="$NIVUUS_CHARTE_MODE" ;;
    *)
        # COLORFGBG vaut « avant-plan;fond » ou « avant-plan;défaut;fond » :
        # le champ utile est toujours le dernier.
        case "${COLORFGBG##*;}" in
            7|9|10|11|12|13|14|15) _nivuus_charte_mode=light ;;
            *)                     _nivuus_charte_mode=dark ;;
        esac
        ;;
esac

# --- Neutralisation : NO_COLOR, ou sortie qui n'est pas un terminal. ---
# NIVUUS_CHARTE_TTY force la détection ; il n'existe que pour les tests, dont
# la sortie est toujours capturée et donc jamais un TTY.
if [ -n "${NO_COLOR:-}" ] || { [ ! -t 1 ] && [ -z "${NIVUUS_CHARTE_TTY:-}" ]; }; then
    NIVUUS_C_DANGER=''
    NIVUUS_C_WARN=''
    NIVUUS_C_OK=''
    NIVUUS_C_BUSY=''
    NIVUUS_C_STRONG=''
    NIVUUS_C_OFF=''
else
    case "${COLORTERM:-}" in
        truecolor|24bit)
            if [ "$_nivuus_charte_mode" = light ]; then
                NIVUUS_C_DANGER=$'\033[38;2;193;31;46m'
                NIVUUS_C_WARN=$'\033[38;2;138;90;0m'
                NIVUUS_C_OK=$'\033[38;2;27;107;74m'
                NIVUUS_C_BUSY=$'\033[38;2;26;95;180m'
            else
                NIVUUS_C_DANGER=$'\033[38;2;255;122;133m'
                NIVUUS_C_WARN=$'\033[38;2;242;179;61m'
                NIVUUS_C_OK=$'\033[38;2;78;211;154m'
                NIVUUS_C_BUSY=$'\033[38;2;122;182;255m'
            fi
            ;;
        *)
            # Repli : l'entrée xterm-256 la plus proche parmi celles qui
            # tiennent le seuil de 4,5:1 de la charte (§ 2.3), les entrées
            # achromatiques exclues. En mode clair, --ok prend l'indice 22 et
            # non 23, numériquement plus proche mais qui vire au teal et se
            # confondrait avec --busy (spec § 3.4).
            if [ "$_nivuus_charte_mode" = light ]; then
                NIVUUS_C_DANGER=$'\033[38;5;124m'
                NIVUUS_C_WARN=$'\033[38;5;94m'
                NIVUUS_C_OK=$'\033[38;5;22m'
                NIVUUS_C_BUSY=$'\033[38;5;25m'
            else
                NIVUUS_C_DANGER=$'\033[38;5;210m'
                NIVUUS_C_WARN=$'\033[38;5;215m'
                NIVUUS_C_OK=$'\033[38;5;78m'
                NIVUUS_C_BUSY=$'\033[38;5;111m'
            fi
            ;;
    esac
    NIVUUS_C_STRONG=$'\033[1m'
    NIVUUS_C_OFF=$'\033[0m'
fi

# Jamais de séquence : le fond du terminal ne nous appartient pas, et son
# avant-plan a été réglé contre lui par la seule personne qui le connaît.
# Voir le § 6.1 de la spec.
NIVUUS_C_TEXT=''

unset _nivuus_charte_mode
NIVUUS_CHARTE_LOADED=1
