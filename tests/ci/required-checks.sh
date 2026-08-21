#!/bin/sh
# =============================================================================
# Les checks qui doivent être exigés sur `master`.
# =============================================================================
# Ce fichier est la déclaration ; `--apply` la pousse sur GitHub. Il existe
# pour une raison précise : un badge n'est bloquant que si le check qui le
# nourrit est requis. Sinon le badge dit « rouge » pendant qu'on merge quand même.
#
# POSIX sh, sans tableau : tout tests/ci/*.sh doit passer `sh -n`, et le job
# de lint le vérifie. C'est aussi ce qui permet de le lire dans un conteneur.
set -eu

REPO="${NIVUUS_REPO:-maximeallanic/nivuus-shell}"
BRANCH="${NIVUUS_BRANCH:-master}"

# Un check par ligne. Le commentaire dit quel workflow le produit ;
# tests/unit/test_ci_workflows.bats vérifie que chaque nom existe vraiment.
checks() {
    cat <<'LIST'
Unit + integration
Installation E2E (Ubuntu)
Installation E2E (macOS)
Installation E2E (Alpine / musl)
Syntax validation
Reversibility (Ubuntu)
Reversibility (macOS)
Reversibility (Alpine / musl)
LIST
}
# tests.yml            : Unit + integration, Installation E2E (…), Syntax validation
# uninstall-verified.yml : Reversibility (…)

if [ "${1:-}" != "--apply" ]; then
    checks
    echo
    echo "Pour appliquer sur $REPO@$BRANCH : $0 --apply  (nécessite gh + droits admin)"
    exit 0
fi

contexts="$(checks | sed 's/.*/"&",/' | tr -d '\n' | sed 's/,$//')"
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - <<EOF2
{
  "required_status_checks": { "strict": true, "contexts": [$contexts] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF2
echo "Checks requis appliqués sur $REPO@$BRANCH"
