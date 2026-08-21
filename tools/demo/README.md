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

## Ce que la garde 2 a trouvé le jour de sa naissance

Le premier rejeu du scénario a échoué sur `??`, et la cause n'est pas la démo :

`config/20-terminal-title.zsh` accroche un hook `chpwd` qui écrit une séquence
OSC sur la **sortie standard**. `_ai_gemini_cli_call`
(`config/09-ai-backend-gemini.zsh`) capture `$(cd "$workspace" && agy …)` : la
séquence se retrouve donc dans la réponse, `jq` échoue à la parser, et l'appel
est rapporté comme `agy call failed (status: unknown)`. Le chemin one-shot de
`GEMINI_AUTH_MODE=cli` est cassé dès que `$TERM` supporte les titres — c'est-à-dire
partout. Il ne se voit pas parce que le daemon (`AGY_DAEMON_ENABLED=true` par
défaut) prend le pas ; la démo, elle, désactive le daemon, et l'a donc exposé.

Corriger cela demande de toucher `config/`, ce que ce chantier s'interdit
(spec § 6). En attendant, `replay-check.sh` rejoue avec `TERM=dumb`, ce qui
désactive le module de titre par son propre mécanisme. **Conséquence assumée :
ce garde ne verra pas une régression de ce défaut-là.**

## Pourquoi `docs/assets/demo.cast` n'est pas encore là

L'outillage est complet et exercé (`record.sh` produit bien un `.cast` dans le
conteneur), mais **aucun enregistrement publiable n'a été committé**. Trois
obstacles, tous constatés, aucun deviné :

1. **Pas de vrai terminal.** L'enregistrement a été tenté sans TTY sur l'hôte :
   asciinema écrit alors tous les événements avec le même horodatage. Le `.cast`
   est syntaxiquement valide et sémantiquement inutile — rendu en SVG, il
   n'anime rien. Une démo doit être tournée depuis un terminal.
2. **Le one-liner du scénario installe la MASTER PUBLIÉE, pas cet arbre.**
   Celle-ci commence encore par `set -euo pipefail` et échoue donc sous `sh`
   (`sh: 5: set: Illegal option -o pipefail`) : le `install.sh` POSIX vit dans
   ce dépôt, pas encore dans la release. Tourner la démo aujourd'hui filmerait
   cet échec. Elle est donc à tourner **après** la publication d'une master qui
   contient l'installeur POSIX.
3. **La relecture humaine est obligatoire** (spec § 3.3) : rythme, lisibilité,
   absence de bruit à l'écran ne sont pas testables. Committer un artefact de
   vitrine qu'aucun humain n'a regardé serait exactement la faute que ce
   chantier ferme.

En attendant, l'état du dépôt est **cohérent et non menteur** :

- `tests/e2e/test_demo_scenario.bats` impose « tout ou rien » : `demo.stamp` et
  `demo.cast` sont présents tous les deux, ou aucun des deux ;
- un test interdit au README d'afficher un artefact absent, donc aucune image
  cassée ne peut atteindre la page d'accueil ;
- les gardes 3 et 4 se déclarent `skip` tant qu'il n'y a rien à comparer, et
  redeviennent bloquantes à la seconde où un enregistrement est committé ;
- la garde 2, elle, **tourne déjà** : le flux de la démo est vérifié en
  conteneur, contre cet arbre, à chaque nightly.

Pour finir le travail : publier une release contenant l'installeur POSIX, puis,
depuis un terminal, `tools/demo/record.sh` && `tools/demo/render.sh`, relire, et
insérer l'image en tête du README avec sa légende (tâche 4.5 du plan).
