# Signature des releases Nivuus

Ce document est la référence opérationnelle du chantier « signature des
releases » : quels outils sont disponibles où, comment les clés sont
générées, tournées et révoquées.

Pour ce que la signature garantit — et surtout pour ce qu'elle **ne**
garantit **pas** — voir [`SECURITY.md`](../SECURITY.md).

## Disponibilité des outils de vérification (mesuré le 2026-08-21)

La sonde `.github/workflows/verify-tools-probe.yml` mesure la présence **et
le fonctionnement réel** de `openssl dgst -verify` et de
`ssh-keygen -Y verify`. Trouver le binaire ne suffit pas : la version doit
savoir faire l'opération (`ssh-keygen -Y` exige OpenSSH ≥ 8.2, et macOS
livre LibreSSL sous le nom `openssl`).

**Mesure effectuée en local avec Docker**, sur les mêmes images que la
sonde, le workflow lui-même n'ayant pas pu être déclenché (`workflow_dispatch`
exige que le fichier soit poussé sur le dépôt). La ligne macOS n'a donc pas
pu être mesurée du tout — elle est marquée comme telle, pas devinée.

### Image de base non modifiée

| Image | `openssl` | `dgst -verify` | `ssh-keygen` | `-Y verify` | `sha256sum` | `shasum` |
|---|---|---|---|---|---|---|
| ubuntu:22.04 | absent | — | absent | — | oui | absent |
| ubuntu:24.04 | absent | — | absent | — | oui | absent |
| debian:12-slim | absent | — | absent | — | oui | absent |
| alpine:3.20 | absent | — | absent | — | oui (busybox) | absent |
| archlinux | **présent** | **OK** | absent | — | oui | absent |
| fedora:40 | absent | — | absent | — | oui | absent |
| macos-latest | non mesuré | non mesuré | non mesuré | non mesuré | absent (attendu) | non mesuré |

### Après installation des trois dépendances requises de Nivuus (`zsh git curl`)

C'est **l'état réel d'une machine où Nivuus tourne** : c'est cette table qui
tranche, pas la précédente.

| Image | `openssl` | `dgst -verify` | `ssh-keygen` | `-Y verify` | `sha256sum` | `shasum` |
|---|---|---|---|---|---|---|
| ubuntu:24.04 | présent (3.0.13) | **OK** | présent (OpenSSH 9.6) | **OK** | oui | oui |
| debian:12-slim | présent (3.0.20) | **OK** | présent (OpenSSH 9.2) | **OK** | oui | oui |
| alpine:3.20 | **absent** | — | **absent** | — | oui (busybox) | absent |
| archlinux | présent (3.6.3) | **OK** | **absent** | — | oui | absent |
| fedora:40 | **absent** | — | présent (OpenSSH 9.6) | **OK** | oui | absent |
| macos-latest | non mesuré | non mesuré | non mesuré | non mesuré | absent (attendu) | non mesuré |
| poste de dev (Debian 13) | présent (3.5.6) | OK | présent (OpenSSH 10.0) | OK | oui | oui |

**Décision d'ordre : primaire = `openssl` (ECDSA P-256), repli = `ssh-keygen`
(Ed25519 SSHSIG).**

**Motif :** égalité stricte sur les images mesurées — `openssl` est
fonctionnel sur 3 des 5 (ubuntu, debian, arch), `ssh-keygen` sur 3 des 5
(ubuntu, debian, fedora). La règle de départage du plan est « celui qui
fonctionne sur macOS », et macOS n'a pas pu être mesuré ici. À égalité et
sans donnée de départage, **on conserve l'ordre du spec** (`openssl`
primaire) plutôt que de l'inverser sur une intuition. Le contrat de
`_nivuus_verify_signature` (codes 0/1/2, trousseau en paramètre) est de
toute façon indépendant de cet ordre : l'inverser un jour ne coûte que
d'échanger deux blocs.

**Ce que la mesure change vraiment**, et qui compte davantage que l'ordre :

1. **Le repli SSHSIG n'est pas décoratif.** Sur Fedora, `openssl` est absent
   et `ssh-keygen` présent : le repli y porte **100 %** du trafic de
   vérification. Sur Arch, c'est l'inverse. Supprimer l'un des deux chemins
   couperait l'auto-update d'une distribution entière.
2. **Alpine n'a ni l'un ni l'autre**, même après `zsh git curl`. Une
   installation Nivuus sur Alpine minimale renvoie donc `rc=2` (« aucun
   outil ») et l'auto-update y reste **inactive** — jamais dégradée. C'est
   exactement le cas que l'avertissement d'installation
   (`nivuus_deps_check_verify_tools`) et `nivuus doctor` doivent nommer.
3. **`shasum` n'existe que sur Debian/Ubuntu** parmi les Linux mesurés, et
   `sha256sum` est partout : le repli `shasum` de `_nivuus_sha256_of` sert
   macOS, pas Linux — ce qui confirme le diagnostic de la Task 3.

### Piège mesuré : collision de `SHA256SUMS.sig`

`openssl dgst -out X.sig` et `ssh-keygen -Y sign X` produisent **le même
nom de fichier**. La première version de cette sonde signait les deux vers
`/tmp/p.sig` et rapportait `ssh-keygen -Y verify: KO` sur *toutes* les
images où `openssl` était présent — un faux négatif complet, qui aurait
inversé la décision d'ordre si on l'avait cru.

Conséquence directe pour le job de signature en CI : la signature SSHSIG
doit se faire **depuis une copie**, puis être renommée en
`SHA256SUMS.sshsig`. Ne jamais laisser les deux commandes viser le même
répertoire de travail sans renommage explicite.

## Mise en service du trousseau réel — PROCÉDURE HUMAINE, À FAIRE À LA MAIN

> **Cette section n'a pas été exécutée, et ne doit pas l'être par un agent.**
> Une clé privée générée par un agent est une clé qui a existé dans un
> environnement qui n'est pas celui du mainteneur. Tout le reste du chantier
> a été construit pour que cette étape se réduise à du copier-coller.
>
> **Rien n'est cassé tant qu'elle n'est pas faite** : `keys/` ne contient
> aucun `.pem`, les tests qui l'exigent se marquent `skip` d'eux-mêmes, et
> le job de release **refuse de publier** plutôt que de sortir une release
> non signée. Le skip et le refus se lèvent seuls le jour où les `.pem`
> sont committées — il n'y a aucun garde-fou à retirer à la main, donc
> aucun garde-fou à oublier.

### État actuel

| Élément | État |
|---|---|
| `keys/revoked`, `keys/README.md`, `keys/.gitignore` | committés |
| `keys/nivuus-release-2026.pem`, `keys/nivuus-release-2027.pem` | **manquants — étape 4 ci-dessous** |
| `keys/allowed_signers` | **manquant — étape 4 ci-dessous** |
| Environnement GitHub `release` et ses deux secrets | **manquants — étape 3 ci-dessous** |
| Empreinte du jeu publiée dans `SECURITY.md` | **à coller — étape 5 ci-dessous** |

### Étape 1 — Générer les deux jeux, hors CI

```bash
# Sur la machine du mainteneur, JAMAIS dans un runner : une clé générée
# en CI est une clé qui a existé dans un journal.
umask 077
mkdir -p ~/nivuus-signing && cd ~/nivuus-signing

for year in 2026 2027; do
    openssl ecparam -name prime256v1 -genkey -noout -out "priv-$year.pem"
    openssl pkcs8 -topk8 -nocrypt -in "priv-$year.pem" -out "priv-$year.pk8.pem"
    openssl ec -in "priv-$year.pem" -pubout -out "nivuus-release-$year.pem"
    ssh-keygen -q -t ed25519 -N '' -f "id-$year" -C "nivuus-release-$year"
done
```

Pas de passphrase : un runner ne peut pas en saisir une. **La protection
n'est pas la passphrase, c'est le périmètre de lecture de l'environnement
`release`.**

Le jeu de succession **2027** est généré **maintenant**, en même temps que
2026, et embarqué dès la première release signée. Sans successeur
pré-distribué, une perte de clé est un événement d'extinction pour le canal
de mise à jour : les clients n'accepteraient plus jamais rien.

### Étape 2 — Sauvegarder hors ligne, puis VÉRIFIER la sauvegarde

Une sauvegarde jamais testée n'est pas une sauvegarde.

```bash
# 1. Déposer priv-2026.pk8.pem, priv-2027.pk8.pem, id-2026, id-2027 dans
#    le gestionnaire de mots de passe ET sur un support froid.
# 2. Restaurer depuis la sauvegarde dans un répertoire neuf.
# 3. Signer un fichier témoin avec la copie RESTAURÉE.
echo "témoin de sauvegarde $(date)" > /tmp/witness
openssl dgst -sha256 -sign /chemin/restauré/priv-2026.pk8.pem -out /tmp/witness.sig /tmp/witness
openssl dgst -sha256 -verify ~/nivuus-signing/nivuus-release-2026.pem \
    -signature /tmp/witness.sig /tmp/witness
# Doit imprimer « Verified OK ». Sinon : la sauvegarde n'existe pas.
```

### Étape 3 — Poser les secrets dans l'environnement protégé

```bash
# L'environnement, PAS les secrets de dépôt : c'est toute la différence.
# Un attaquant qui obtient contents: write, ou qui injecte une Action
# tierce dans un autre job, ne peut pas lire un secret d'environnement.
gh api -X PUT repos/maximeallanic/nivuus-shell/environments/release

gh secret set NIVUUS_SIGNING_KEY_ECDSA --env release < ~/nivuus-signing/priv-2026.pk8.pem
gh secret set NIVUUS_SIGNING_KEY_SSH   --env release < ~/nivuus-signing/id-2026
```

Les **noms** des secrets sont ceux que `.github/workflows/release.yml`
attend déjà : `NIVUUS_SIGNING_KEY_ECDSA` et `NIVUUS_SIGNING_KEY_SSH`. Ne
pas activer de règle « réviseur requis » : décision actée n° 1, signature
automatique. L'environnement sert au cloisonnement ; l'approbation manuelle
pourra être activée plus tard dans les réglages GitHub, sans toucher au
code.

### Étape 4 — Committer le matériel PUBLIC (et lui seul)

```bash
cd /chemin/du/dépôt
cp ~/nivuus-signing/nivuus-release-2026.pem keys/
cp ~/nivuus-signing/nivuus-release-2027.pem keys/
{
  printf 'nivuus-release %s\n' "$(cat ~/nivuus-signing/id-2026.pub)"
  printf 'nivuus-release %s\n' "$(cat ~/nivuus-signing/id-2027.pub)"
} > keys/allowed_signers

# Le garde-fou doit rester vert : il interdit toute clé PRIVÉE dans le dépôt.
bats tests/unit/test_keys_repo.bats

# Les suites qui étaient « skip » deviennent actives toutes seules :
bats tests/e2e/test_verify_key.bats tests/e2e/test_install_keys.bats
```

**Ne jamais committer** : `priv-*.pem`, `priv-*.pk8.pem`, `id-2026`,
`id-2027` (les fichiers SANS `.pub`). `keys/.gitignore` en attrape déjà la
plupart ; le test `test_keys_repo.bats` est la vérification réelle.

### Étape 5 — Publier l'empreinte du jeu

```bash
source lib/log.sh; source lib/manifest.sh; source lib/keys.sh
nivuus_keyset_fingerprint keys
```

Coller cette empreinte dans `SECURITY.md`, sous « Empreinte du jeu de
clés », à la place du gabarit. C'est elle que les utilisateurs comparent
avec `./install.sh --verify-key <empreinte>`.

### Étape 6 — Committer

```bash
git add keys SECURITY.md
git commit -m "feat(keys): add the 2026 release keyset and its pre-distributed 2027 successor"
```

### Étape 7 — Première release signée, puis canari

1. Lancer le workflow `Release`. L'étape « Verify before publishing »
   utilise les clés **publiques committées**, jamais celles dérivées du
   secret : si l'étape 3 et l'étape 4 ne portent pas sur le même jeu, la
   release **ne sort pas**. C'est la panne opérationnelle la plus probable
   du chantier, et elle est bloquée là.
2. `gh workflow run verify-latest-release.yml && gh run watch`. Le canari
   est **rouge tant qu'aucune release signée n'existe** — c'est correct.
   Il doit passer au vert avec la première release signée.
3. **Seulement ensuite**, publier une release contenant le refus dur côté
   client. Voir « Contrainte de publication » ci-dessous.

## Contrainte de publication (à ne pas contourner)

Le client de cette branche **refuse** une release dont la signature n'est
pas valide. Tant qu'aucune release signée n'existe :

- **Les utilisateurs déjà installés ne risquent rien.** Leur client est
  l'ancien : il ne connaît ni `.sig` ni `.sshsig`, il continue de vérifier
  l'empreinte SHA256 comme avant. Rien de ce chantier ne peut leur refuser
  une mise à jour, parce que rien de ce chantier ne tourne chez eux.
- **Aucune release ne peut sortir non signée.** Le job de release échoue en
  l'absence de `keys/*.pem` (garde explicite) et échoue à la vérification
  avant publication si les clés ne correspondent pas. Fail-closed : on ne
  publie pas, plutôt que de publier quelque chose que les clients
  refuseraient.
- **La règle qui reste à la charge d'un humain** est la dernière :
  ne pas publier de release embarquant le refus dur (Task 7) tant que la
  première release signée n'a pas été produite et que le canari n'est pas
  vert. Le merge n'est pas contraint ; la *publication* l'est.

## Rotation annuelle

Voir « Répétition en blanc de la rotation » plus bas — la procédure y est
consignée telle qu'elle a été réellement exécutée.

## Secrets, environnement et sauvegardes

| Élément | Emplacement | Qui peut le lire |
|---|---|---|
| `NIVUUS_SIGNING_KEY_ECDSA` | secret de l'**environnement** GitHub `release` | le seul job `release` de `.github/workflows/release.yml` |
| `NIVUUS_SIGNING_KEY_SSH` | idem | idem |
| Clés privées ECDSA/Ed25519 (`priv-*.pk8.pem`, `id-*`) | gestionnaire de mots de passe du mainteneur **et** support froid hors ligne | le mainteneur seul |
| Clés publiques (`keys/*.pem`, `keys/allowed_signers`) | dans le dépôt, versionnées | tout le monde, par construction |
| Liste de révocation (`keys/revoked`) | dans le dépôt | tout le monde |

Un secret d'**environnement** (et non de dépôt) est le point qui porte tout
le modèle : un attaquant qui obtient `contents: write`, ou qui injecte une
Action tierce dans un autre job du même dépôt, **ne peut pas** le lire.

**L'emplacement exact des sauvegardes hors ligne n'est pas consigné ici** —
seulement le fait qu'il y en a deux, et l'obligation de les tester
(doc/SIGNING.md, étape 2). Écrire « la clé froide est dans le tiroir du
bureau » dans un dépôt public annulerait l'intérêt du support froid.

## Révocation

Une clé se révoque en ajoutant son empreinte à `keys/revoked`, une par
ligne, puis en publiant une release. Deux formats, selon le chemin :

```
sha256:<sha256 hexadécimal du fichier .pem>          # chemin openssl
SHA256:<empreinte ssh-keygen -lf de la clé publique>  # chemin SSHSIG
```

Obtenir l'une et l'autre :

```bash
printf 'sha256:%s\n' "$(sha256sum keys/nivuus-release-2026.pem | awk '{print $1}')"
ssh-keygen -lf keys/allowed_signers | awk '{print $2}'
```

Une clé listée dans `revoked` est refusée **même si elle est encore
présente** dans `keys/` : c'est délibéré, la révocation ne demande pas de
supprimer le fichier et reste donc auditable.

**Ce que la révocation ne peut pas faire :** annuler une release
malveillante déjà installée. Le code malveillant contrôle alors la mise à
jour. La récupération d'une machine compromise est une réinstallation.
