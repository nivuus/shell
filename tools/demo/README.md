# tools/demo — la démo du README

La source de vérité est `docs/assets/demo.cast` : du texte, diffable, auditable
en revue. Tout le reste en dérive.

## Format de l'artefact

**Vérifié le 2026-08-21.** La vérification prévue par le plan (pousser une
branche jetable et regarder le README rendu) a été **remplacée par une
vérification équivalente et sans écriture distante** : le chantier n'a pas le
droit de pousser. On observe donc un README public **déjà rendu par GitHub**
qui affiche un SVG produit par `svg-term-cli` — `marionebl/svg-term-cli` — et
on mesure ce que GitHub en fait réellement.

| Question | Réponse observée | Comment |
|---|---|---|
| Le SVG s'affiche-t-il dans un README rendu par GitHub ? | **Oui.** Servi en `image/svg+xml` par le proxy `camo.githubusercontent.com`, dans un `<img>`, en HTTP 200. | `curl` non authentifié sur la page puis sur l'URL camo |
| Les animations survivent-elles à la sanitisation du proxy ? | **Oui.** Les octets servis par camo contiennent toujours `@keyframes`, `animation-name`, `animation-duration`, `animation-iteration-count`. | `grep` sur la réponse de camo |
| S'anime-t-il vraiment dans un navigateur ? | **Oui.** Deux captures de l'élément `<img>`, à 1,5 s d'intervalle, sur la page GitHub réelle, donnent deux images différentes (contenu et couleurs différents). | Chromium piloté par Playwright, session anonyme |
| Reste-t-il lisible en thème sombre et sur mobile ? | **NON VÉRIFIÉ.** Seul le thème clair, en viewport de bureau, a été observé. `svg-term` embarque son propre fond de fenêtre, donc le risque est faible — mais il n'est pas mesuré. | — |

Deux limites assumées de cette vérification : elle porte sur un SVG **hébergé
hors dépôt** (rawgit) et non sur un fichier versionné référencé en lien
relatif. Le pipeline est le même — GitHub réécrit le lien relatif vers
`raw.githubusercontent.com` puis le proxie par camo — mais cela reste une
inférence, pas une observation. Elle a aussi été faite **déconnecté**, ce qui
est le cas le plus défavorable, et le seul qui compte pour un visiteur.

**Verdict : `format=svg`.**

Le format retenu est écrit dans `docs/assets/demo.stamp` (`format=`), et
`tests/e2e/test_demo_scenario.bats` applique le budget de poids correspondant :
250 Ko pour un SVG, 2 Mo pour un GIF. Changer de format se fait en changeant
`NIVUUS_DEMO_FORMAT` et en relançant `render.sh` — le `.cast` ne bouge pas.

## Régénérer la démo

```bash
tools/demo/record.sh          # rejoue scenario.txt dans le conteneur → demo.cast
tools/demo/render.sh          # demo.cast → demo.svg (ou .gif) + demo.stamp
```

Jamais en CI. Trois raisons : un diff binaire par PR que personne ne relit ;
un artefact de vitrine doit passer devant un humain une fois (le timing et la
lisibilité ne sont pas testables) ; le risque de fuite est faible mais réel.

## Le backend IA est un stub, et il est déclaré

`tools/demo/stub/agy` est un faux Antigravity CLI qui renvoie des réponses
figées. Il est posé sur le `PATH` du conteneur de tournage, avec
`GEMINI_AUTH_MODE=cli` — le chemin de production existant, sans un seul
crochet ajouté dans `config/`. Aucune clé réelle n'entre jamais dans un
enregistrement. La légende sous l'image du README le dit ; un test l'exige.
