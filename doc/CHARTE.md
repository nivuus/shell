# Charte graphique appliquée au terminal

Nivuus suit la charte graphique commune (dépôt `nivuus/design`, socle 0.3.0).
Ce document dit ce qu'elle devient dans un terminal. La charte fait foi ; il
ne la répète pas, il la transpose.

- Spec : `docs/superpowers/specs/2026-08-24-charte-terminal-design.md`
- Source machine : `lib/charte.sh`

## Périmètre

La charte régit ce que Nivuus écrit **en son nom propre** : `lib/charte.sh`,
`lib/log.sh`, `lib/steps.sh`, `lib/manifest.sh`, `lib/zshrc.sh`,
`bin/nivuus`, `bin/healthcheck`, `bin/benchmark`, `bin/test`,
`config/09-ai-core.zsh`, `config/22-ai-errors.zsh` et
`config/24-ai-command-not-found.zsh`. La liste exacte est tenue par
`tests/unit/test_charte_no_grey.bats`, qui échoue si un fichier du périmètre
disparaît ou si un gris s'y réintroduit.

`config/09-ai-core.zsh` porte `_ai_charte_load`, le chargeur paresseux
partagé par `config/22-ai-errors.zsh` et `config/24-ai-command-not-found.zsh` :
`lib/charte.sh` n'est sourcé qu'au premier message d'erreur ou de commande
introuvable, jamais au démarrage. C'est pour ça qu'il figure dans le
périmètre alors qu'il ne produit lui-même aucune sortie colorée.

Elle ne régit **pas** le prompt (`config/05-prompt.zsh`), les thèmes
(`themes/*.zsh`), la complétion, le surlignage syntaxique, ni la colorisation
des outils tiers (`config/17-colorization.zsh`). Ces surfaces emploient la
couleur pour hiérarchiser — path, branche, type de fichier — ce que la charte
interdit mais dont leur lisibilité dépend entièrement. Elles restent sur la
palette du thème actif, et le contrat `THEME_*` (voir `doc/PROMPT.md`) ne
change pas.

Cette frontière est une décision, pas un provisoire. L'élargir est un projet
en soi.

## Les sept variables

`lib/charte.sh` expose sept variables et ne définit aucune fonction.

| Variable | Emploi |
|---|---|
| `NIVUUS_C_DANGER` | erreur |
| `NIVUUS_C_WARN` | avertissement |
| `NIVUUS_C_OK` | succès |
| `NIVUUS_C_BUSY` | traitement en cours |
| `NIVUUS_C_TEXT` | **toujours vide** — voir les dérogations |
| `NIVUUS_C_STRONG` | gras, pour le premier plan |
| `NIVUUS_C_OFF` | réinitialisation |

Deux règles portent tout le reste :

- **La couleur ne s'emploie jamais seule.** Toujours couleur *plus* glyphe
  *plus* libellé. Une sortie doit rester lisible en noir et blanc, pour une
  personne daltonienne comme pour un journal de CI.
- **Aucun gris.** Ni `dim`, ni code ANSI-256 achromatique. Le second plan
  passe par l'absence de gras, jamais par une atténuation. Un test le tient :
  `tests/unit/test_charte_no_grey.bats`.

## Réglage

| Variable | Effet |
|---|---|
| `NIVUUS_CHARTE_MODE` | `light` ou `dark`, force la paire de teintes |
| `NO_COLOR` | neutralise les sept variables |
| `COLORTERM` | `truecolor`/`24bit` active les hex exacts, sinon repli ANSI-256 |
| stdout (`[ -t 1 ]`) | si ce n'est pas un terminal, neutralise les sept variables, sauf si `NIVUUS_CHARTE_TTY` est posée |
| `NIVUUS_CHARTE_TTY` | force la détection TTY à vrai ; réservée aux tests, dont la sortie est toujours capturée |

Sans `NIVUUS_CHARTE_MODE`, le mode est déduit de `COLORFGBG`, et à défaut
sombre — le contexte du produit.

## Quand une couleur bouge dans `tokens.css`

1. Côté design : relancer `tools/check_contrast.py`, dont le code de sortie
   fait autorité.
2. Reporter la nouvelle valeur dans `lib/charte.sh`, hex et RGB décimal.
3. Recalculer le repli ANSI-256 si la teinte a bougé : l'entrée xterm-256 la
   plus proche **parmi celles qui tiennent 4,5:1** contre la surface du mode,
   entrées achromatiques exclues.
4. Relancer `bats tests/unit/test_charte_conformity.bats` — il compare
   directement à `tokens.css` et nomme le rôle qui diverge.

## Deux dérogations

Elles sont assumées et doivent être remontées à `docs/charte.md` côté design,
pas dissimulées. Toutes deux tiennent au même fait : un terminal n'est pas une
page.

**`NIVUUS_C_TEXT` n'émet aucune séquence.** La charte garantit ses ratios
contre `--surface`. Dans un terminal, la surface ne nous appartient pas :
écrire `#FFFFFF` sur le fond blanc de quelqu'un produirait exactement
l'illisibilité que la charte protège. On laisse l'avant-plan du terminal, que
son propriétaire a réglé contre son propre fond.

**L'épaisseur remplace la taille.** La charte remplace les gris par
« l'épaisseur, la taille, l'espacement ». Un terminal n'a qu'un seul corps de
texte. Des trois leviers, l'épaisseur est celui qui existe : le premier plan
passe en gras, le second reste en texte normal, de la même couleur.
