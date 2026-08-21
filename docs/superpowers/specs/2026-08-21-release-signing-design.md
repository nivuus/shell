# Signature cryptographique des releases — Design

**Date :** 2026-08-21
**Statut :** proposé, en attente d'arbitrage sur les questions ouvertes (§ 9)
**Chantier :** 2/4 du programme d'adoption — « Preuve & confiance »
(voir `2026-08-20-installation-friction-zero-design.md`, § Contexte)

## Contexte

Le chantier 1 a rendu l'installation auditable et réversible : manifeste,
`--dry-run`, `uninstall` vérifié en CI. Il a explicitement renvoyé la
**signature des releases** à ce document (§ « Hors périmètre »).

La distribution de Nivuus repose sur GitHub Releases : `release.yml` produit
`nivuus-shell-vX.Y.Z.tar.gz`, une archive de docs et un fichier `SHA256SUMS`,
puis `gh release create` publie le tout. Côté client,
`config/20-autoupdate.zsh` télécharge l'archive, télécharge `SHA256SUMS`,
compare les empreintes, puis **écrase `$NIVUUS_SHELL_DIR`** avec le contenu de
l'archive.

Deux propriétés du code existant définissent l'enjeu :

1. La mise à jour est **non supervisée**. `_nivuus_check_update_async` part en
   arrière-plan au démarrage du shell, tous les `AUTOUPDATE_CHECK_FREQUENCY_DAYS`
   (7 par défaut), appelle `_nivuus_perform_update` et **installe sans demander**.
2. Ce qui est installé est du **code exécuté à chaque ouverture de shell**
   (`config/*.zsh` est sourcé par `.zshrc`).

Autrement dit : le canal de mise à jour est un canal d'exécution de code
arbitraire, automatique, sur toutes les machines des utilisateurs, indéfiniment.
C'est la surface la plus critique du projet — plus que l'installation, qui n'a
lieu qu'une fois et sous les yeux de l'utilisateur.

## Problème

### Le SHA256 actuel ne prouve pas l'authenticité

`_nivuus_download_release()` télécharge :

```zsh
archive_url="https://github.com/$REPO/releases/download/v${version}/nivuus-shell-v${version}.tar.gz"
checksums_url="https://github.com/$REPO/releases/download/v${version}/SHA256SUMS"
```

**L'archive et la somme viennent de la même origine, du même dépôt, du même
acte de publication.** Quiconque peut publier l'archive publie aussi le
`SHA256SUMS` qui la décrit. La vérification actuelle démontre donc exactement
une chose : que l'octet reçu est l'octet publié. Elle protège de la corruption
en transit et d'un CDN défaillant. Elle ne dit **rien** sur l'identité de qui a
publié.

Le commentaire du code est d'ailleurs correct et honnête sur ce qu'il fait
(« fail CLOSED », « MITM failure cannot be used to silently skip
verification ») — il ne prétend pas à l'authenticité. Le problème n'est pas un
bug, c'est une propriété manquante.

### Ce qu'un attaquant peut faire aujourd'hui

| Capacité obtenue | Conséquence actuelle |
|---|---|
| Jeton avec `contents: write` (PAT fuité, Action tierce compromise dans un workflow, `GITHUB_TOKEN` d'un autre job) | Remplace l'asset de la dernière release **et** son `SHA256SUMS` → exécution de code sur toutes les installations sous 7 jours, silencieusement |
| Compte GitHub du mainteneur | Idem, plus la possibilité de publier une version supérieure |
| MITM avec une CA de confiance (proxy d'entreprise, poste managé) | Substitution des deux fichiers → idem |
| Re-hébergement par un tiers (miroir, package downstream) | Aucun moyen pour l'utilisateur de vérifier l'origine |

Aucun de ces scénarios n'exige la clé de signature qu'on va introduire. C'est
précisément ce que la signature déplace : elle transforme « qui peut écrire sur
le dépôt » en « qui détient la clé ».

### Défauts collatéraux constatés dans le code de vérification

À corriger dans le même chantier, car ils vivent dans la fonction qu'on
modifie :

- `_nivuus_download_release` appelle **`sha256sum` sans repli** :
  ```zsh
  local actual_sum=$(sha256sum "$temp_dir/nivuus-shell.tar.gz" | awk '{print $1}')
  ```
  `sha256sum` n'existe pas par défaut sur macOS (`shasum` y est l'outil
  disponible). `lib/manifest.sh` gère déjà les deux cas dans
  `nivuus_hash_file()` ; l'updater non. Sur macOS, `actual_sum` est vide, ne
  correspond jamais et **toute mise à jour échoue** — la vérification y est
  aujourd'hui un déni de service, pas une garantie.
- `NIVUUS_VERIFY_CHECKSUMS=false` désactive globalement la vérification, y
  compris sur le chemin automatique non supervisé.
- La vérification est **imbriquée dans le téléchargement** : impossible de la
  tester sans réseau. C'est la raison pour laquelle il n'existe aucun test de
  cette logique aujourd'hui.

## Approche retenue

**Signer `SHA256SUMS`, pas chaque archive** — un artefact signé unique couvre
tous les assets, et la comparaison d'empreinte existante reste le second maillon
de la chaîne. Le client fait donc :

```
1. télécharger SHA256SUMS + sa signature
2. vérifier la signature contre une clé publique embarquée dans l'installation
3. si et seulement si valide : comparer l'empreinte de l'archive à SHA256SUMS
4. si et seulement si valide : installer
```

C'est la structure classique (Debian `InRelease`, la plupart des projets), et
c'est celle qui minimise le delta dans `20-autoupdate.zsh` : on **insère** une
étape avant la comparaison existante, on ne réécrit pas la fonction.

**Mécanisme : signature vérifiable avec un outil déjà présent sur la machine**,
et non avec un binaire à installer. Voir § 1, qui est la décision structurante
du document.

## 1. Choix du mécanisme

### Contrainte dominante : la dépendance côté client

Nivuus s'installe sur des machines minimales (Alpine, containers, macOS
fraîchement sorti de boîte) et le chantier 1 a posé une règle explicite :
**« Nivuus n'exécute jamais un `sudo` que l'utilisateur n'a pas explicitement
demandé »**, avec trois dépendances requises et trois seulement : `zsh`, `git`,
`curl` (`nivuus_step_check_required_deps`).

Un mécanisme de signature qui exige un quatrième binaire transforme la
vérification en obstacle, et un obstacle produit toujours la même chose : un
contournement. Soit on dégrade vers le SHA256 (et la signature ne sert à rien),
soit on refuse de mettre à jour (et on casse le produit). Le choix du mécanisme
est donc d'abord un choix de disponibilité.

### Options évaluées

**GPG détaché (`gpg --verify`)** — le titre du chantier. Rejeté comme chemin
client :

- `gnupg` n'est présent par défaut ni sur macOS, ni sur Alpine, ni sur la
  plupart des images de base Debian/Ubuntu « slim ». L'installer demande
  `sudo` : exactement ce que le projet refuse.
- Le modèle de confiance de GPG (trousseaux, web of trust, `--trust-model`,
  sous-clés, expiration) est **hors sujet** ici : on veut vérifier une seule
  signature contre une seule clé épinglée. Utiliser GPG pour ça oblige à des
  contorsions (`--no-default-keyring --keyring ./nivuus.gpg
  --trust-model always`) faciles à mal écrire — les CVE de vérification GPG
  en scripts shell sont un genre littéraire à elles seules.
- Poids : ~10 Mo d'installation pour vérifier 64 octets de signature.

**cosign / Sigstore keyless (OIDC GitHub)** — la meilleure option côté
production, la pire côté client :

- Propriété remarquable : **aucune clé privée à garder**. L'identité signataire
  est le workflow GitHub lui-même, l'attestation est publiée dans un journal de
  transparence (Rekor). Le problème « et si la clé est perdue ? » disparaît.
- Mais la vérification exige le binaire `cosign` (~50 Mo, absent de tous les
  gestionnaires de paquets par défaut du périmètre) **et** un accès réseau aux
  racines Fulcio/Rekor. Inacceptable pour un updater de framework zsh.
- Conclusion : on l'adopte **en plus**, jamais **à la place** — voir § 1.3.

**minisign / signify** — Ed25519, format minimal, une clé publique de 32 octets,
implémentation simple à auditer. Techniquement idéal, mais le binaire est absent
partout par défaut : même impasse que GPG, sans son écosystème.

**`openssl dgst -verify`** — retenu comme chemin primaire. `openssl(1)` est
présent sur macOS (`/usr/bin/openssl`, LibreSSL) et dans la quasi-totalité des
images Linux, y compris parce que `curl` — dépendance déjà requise — en tire
généralement la bibliothèque. La vérification tient en une ligne, sans
trousseau ni modèle de confiance :

```sh
openssl dgst -sha256 -verify "$pubkey_pem" -signature "$sigfile" "$sumsfile"
```

Algorithme : **ECDSA P-256 / SHA-256**, et non Ed25519, pour une raison
d'implémentation précise : Ed25519 via la CLI OpenSSL passe par
`openssl pkeyutl -rawin`, dont le support est récent et inégal sur LibreSSL —
c'est-à-dire précisément sur macOS. ECDSA P-256 avec `dgst -verify` fonctionne
sur OpenSSL 1.0.2+ **et** sur LibreSSL. On choisit l'algorithme le plus
largement vérifiable, pas le plus élégant.

**`ssh-keygen -Y verify`** (format SSHSIG, OpenSSH 8.2+) — retenu comme chemin
de repli. Là où `openssl` manque mais où OpenSSH est présent (cas fréquent sur
les serveurs), la vérification reste possible :

```sh
ssh-keygen -Y verify -f "$allowed_signers" -I nivuus-release \
    -n nivuus-release -s "$sigfile" < "$sumsfile"
```

### 1.1 Décision

| Rôle | Artefact | Outil client | Statut |
|---|---|---|---|
| Chemin primaire | `SHA256SUMS.sig` (ECDSA P-256/SHA-256, DER) | `openssl` | **requis pour mettre à jour** |
| Chemin de repli | `SHA256SUMS.sshsig` (Ed25519 SSHSIG) | `ssh-keygen` | **requis pour mettre à jour** |
| Écosystème | `SHA256SUMS.asc` (GPG détaché, armuré) | `gpg` | publié, **jamais** sur le chemin client |
| Provenance | attestation Sigstore/GitHub | `gh attestation verify` | publiée, pour audit |

Le client tente `openssl`, puis `ssh-keygen`, et s'arrête là. **Deux formats de
signature suffisent** à couvrir le périmètre sans jamais demander une
installation.

Le titre du chantier disait « GPG » ; la conclusion est **GPG conservé, mais
déplacé**. Une signature GPG reste attendue par les mainteneurs de paquets
(Homebrew, AUR — chantier 4) et par les auditeurs humains qui ont déjà `gpg` et
un trousseau. Elle est donc produite et publiée. Elle n'est simplement pas ce
que la machine de l'utilisateur exécute, parce qu'elle exigerait d'installer
`gnupg` sur une machine qui n'en a pas.

### 1.2 Coût du double format

Deux formats = deux clés = deux fois la gestion. Le coût est assumé pour une
raison mesurable : sans repli SSHSIG, toute machine sans `openssl` perd
l'auto-update (§ 4, refus dur). Signer deux fois coûte quatre lignes de CI et
un second secret ; perdre l'auto-update sur une classe entière de machines
coûte des utilisateurs.

**Les deux clés forment un jeu unique** : générées ensemble, tournées ensemble,
révoquées ensemble, référencées par un seul « identifiant de jeu de clés »
(`nivuus-release-2026`). Il n'existe jamais une clé valide et l'autre non — un
état où les deux chemins de vérification divergeraient serait pire que pas de
signature du tout.

### 1.3 Sigstore en complément

`actions/attest-build-provenance` est ajouté au workflow de release. Coût
client : **zéro** (rien à vérifier côté machine utilisateur). Gain : une
attestation publique et horodatée liant chaque archive au commit, au workflow et
au runner qui l'ont produite, vérifiable par n'importe qui avec
`gh attestation verify`. C'est la pièce qui documente *comment* l'artefact a été
construit, là où la signature documente *qui* l'a approuvé. Les deux répondent à
des questions différentes ; aucune ne remplace l'autre.

## 2. Gestion de la clé privée

### Où elle vit

- **Génération hors CI**, sur la machine du mainteneur, jamais dans un runner.
  Une clé générée en CI est une clé qui a existé dans un journal.
- Stockage : **secrets d'un GitHub Environment nommé `release`**, pas des
  secrets de dépôt. La distinction est le cœur du dispositif : les secrets
  d'environnement ne sont lisibles que par un job qui déclare
  `environment: release`, et un environnement peut porter des règles de
  protection (réviseurs requis, branches/tags autorisés).
  → Un attaquant qui obtient `contents: write` ou qui injecte une Action tierce
  dans un *autre* job **ne peut pas lire la clé**. C'est ce qui fait que la
  signature déplace réellement le problème au lieu de le décorer.
- Secrets : `NIVUUS_SIGNING_KEY_ECDSA` (PEM PKCS#8), `NIVUUS_SIGNING_KEY_SSH`
  (clé privée OpenSSH Ed25519), `NIVUUS_SIGNING_KEY_GPG` (bloc armuré) —
  **sans passphrase**, un runner ne pouvant pas en saisir une. La protection
  n'est pas la passphrase, c'est le périmètre de lecture de l'environnement.
- **Sauvegarde hors ligne** des trois clés privées (gestionnaire de mots de
  passe + copie froide). Sans sauvegarde, une perte du secret GitHub rend la
  rotation impossible par le canal normal (§ 2.2).

### 2.1 Ce qui n'existe pas et qu'on n'invente pas

Une clé brute n'a **ni date d'expiration, ni liste de révocation**. C'est un
inconvénient réel de l'approche « clé épinglée » face à GPG. On ne simule pas
ces mécanismes par du métadonnée maison : ça donnerait l'illusion d'une
propriété sans la propriété. À la place, deux dispositifs concrets :

- **Rotation planifiée** (annuelle) plutôt qu'expiration subie.
- **Anti-rétrogradation** : elle existe déjà, gratuitement. La mise à jour
  n'est déclenchée que si `_nivuus_version_greater` est vraie ; un attaquant ne
  peut donc pas rejouer une release **antérieure** signée par une clé
  compromise puis révoquée. À documenter comme propriété de sécurité, pas
  seulement comme confort.

### 2.2 Rotation

Le mécanisme repose sur le fait que la clé publique de confiance **est livrée
par le canal signé lui-même** :

```
release N     signée par le jeu K1   → l'arbre installé contient {K1, K2}
release N+1   signée par le jeu K1   → l'arbre installé contient {K1, K2}
release N+2   signée par le jeu K2   → l'arbre installé contient {K2, K3}
```

Le client accepte **toute signature valide de l'une des clés embarquées**.
Une nouvelle clé est donc toujours pré-distribuée par une release signée avec
l'ancienne, au moins une release avant son premier usage. La rotation est
invisible pour l'utilisateur et ne demande aucune action.

Conséquence de conception : le client doit accepter **plusieurs clés de
confiance** dès la première version signée, sinon la rotation exigerait un jour
un flag day. C'est structurant et c'est le moment de le décider.

### 2.3 Révocation

Il n'y a pas de miracle : une clé compromise ayant déjà signé une release
malveillante ne peut pas être « dé-signée » chez les utilisateurs déjà mis à
jour. Ce qui est faisable :

1. Retirer la clé compromise du jeu embarqué dans la release suivante, signée
   par la clé de secours restante (d'où l'obligation de garder K+1 en réserve).
2. Publier une entrée de dénylist (empreinte de la clé) dans l'arbre installé :
   une signature de la clé révoquée est refusée même si un autre chemin la
   présentait encore.
3. Annoncer hors bande (SECURITY.md, release notes, canaux publics).
4. **Dire ce que ça ne répare pas** : les machines déjà compromises ne sont pas
   récupérables par une mise à jour, puisque le code malveillant contrôle la
   mise à jour. La procédure de récupération est une réinstallation.

### 2.4 Perte de la clé

Sans sauvegarde et sans clé de succession pré-distribuée, il n'existe **aucun
chemin propre** : tous les clients refusent tout ce qui n'est pas signé par une
clé qu'ils connaissent, et personne ne peut plus signer. La sortie serait une
réinstallation manuelle par chaque utilisateur — un événement d'extinction pour
le canal de mise à jour.

D'où deux règles non négociables, qui sont la contrepartie du choix « clé
épinglée » :

- La clé de succession K+1 est générée **en même temps** que K et embarquée dès
  la première release signée.
- Les clés privées sont sauvegardées hors ligne avant la première release
  signée, et cette sauvegarde est vérifiée (restaurer, signer un fichier
  témoin, vérifier) — une sauvegarde jamais testée n'est pas une sauvegarde.

## 3. Distribution de la clé publique et amorçage

### Où vivent les clés publiques

Nouveau répertoire versionné, copié dans l'installation :

```
keys/
├── nivuus-release-2026.pem            # ECDSA P-256, chemin openssl
├── nivuus-release-2027.pem            # succession, pré-distribuée
├── allowed_signers                    # format ssh-keygen -Y, mêmes jeux
└── revoked                            # empreintes révoquées (vide au départ)
```

`nivuus_step_copy_tree` (dans `lib/steps.sh`) itère aujourd'hui sur
`config themes bin plugins lib` : **`keys` doit y être ajouté**, sinon
l'installeur ne pose pas la clé et la vérification échoue systématiquement.
C'est le point de rupture le plus probable de tout ce chantier.

Le client lit la clé depuis `$NIVUUS_SHELL_DIR/keys/`, **avant** l'extraction —
donc jamais depuis l'archive qu'il est en train de vérifier. Le nouveau jeu de
clés arrive avec l'arbre vérifié, ce qui est exactement le mécanisme de
rotation du § 2.2.

### Le problème d'amorçage, nommé honnêtement

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

Ce one-liner télécharge **l'installeur et la clé publique depuis la même
origine**. Un attaquant qui contrôle cette origine à cet instant sert son
installeur et sa clé. **La signature ne résout pas la première installation.**
Aucune signature ne le peut : c'est le problème de la racine de confiance, et
il se termine toujours par « quelque chose doit être connu à l'avance ».

Ce que la solution résout malgré tout, et qui est l'essentiel :

| | Avant | Après |
|---|---|---|
| Compromission des assets de release seuls (jeton, Action tierce, job voisin) | exécution de code chez tous les utilisateurs | **bloquée** : pas de signature valide sans l'environnement `release` |
| MITM avec CA de confiance sur le chemin de mise à jour | réussit | **bloquée** |
| Miroir / re-hébergement tiers | invérifiable | **vérifiable** |
| Corruption en transit | déjà couverte | couverte |
| Première installation via `curl \| sh` | vulnérable | **toujours vulnérable** |
| Compromission de la clé de signature | — | non couverte (§ 2.3) |
| Mainteneur malveillant | — | non couverte, par construction |

La bonne façon de mesurer le gain : la première installation est **un instant,
sous les yeux de l'utilisateur, une fois**. La mise à jour est **récurrente,
automatique, invisible, sur toutes les machines, pour toujours**. Signer déplace
la fenêtre d'attaque de « permanente et silencieuse » à « ponctuelle et
observable ». C'est un gain de plusieurs ordres de grandeur, et ce n'est pas
une preuve d'origine absolue. Le README doit le dire dans ces termes, sans
badge « signed & secure » qui laisserait croire l'inverse.

### Ancrage hors bande

Pour les utilisateurs qui veulent fermer la fenêtre d'amorçage :

- **Empreinte publiée hors du dépôt** : README, `SECURITY.md`, profil GitHub du
  mainteneur, et — si un domaine est disponible (§ 9) — une page servie
  ailleurs que sur GitHub. Plusieurs origines indépendantes, non pas parce que
  chacune est sûre, mais parce que les compromettre toutes simultanément est un
  autre ordre de difficulté.
- **`install.sh --verify-key <empreinte>`** : l'utilisateur colle l'empreinte
  obtenue par un canal de son choix ; l'installeur refuse de continuer si le
  jeu de clés embarqué ne correspond pas. Coût : ~15 lignes. C'est la seule
  réponse honnête possible à « et si GitHub est compromis pendant mon
  install ? ».

## 4. Comportement du client en cas d'échec

**Position tranchée : refus dur dans tous les cas, sur le chemin automatique.
Aucune dégradation vers SHA256, jamais, sous aucune condition.**

Une dégradation silencieuse ramène exactement à la situation d'aujourd'hui —
tout en affichant à l'utilisateur qu'il est protégé. C'est pire que ne rien
faire, parce que ça consomme le budget d'attention : un avertissement affiché
au démarrage d'un shell, dans un processus d'arrière-plan dont la sortie part
dans un `mktemp`, n'est lu par personne.

| Situation | Comportement |
|---|---|
| Signature invalide | **Abandon**. Rien n'est extrait, rien n'est écrit. Message explicite : archive potentiellement altérée, ne pas contourner, vérifier la page de release. |
| Fichier de signature absent | **Abandon**. Un client de l'ère signée exige une signature, point. (Traité comme invalide : c'est la défense contre le retrait de la signature par l'attaquant.) |
| Ni `openssl` ni `ssh-keygen` | **Abandon de la mise à jour**, message une fois, non répété. Détecté et signalé dès `install` et dans `nivuus doctor` — le problème est annoncé au moment où l'utilisateur peut agir, pas six mois plus tard en arrière-plan. |
| Empreinte SHA256 non conforme après signature valide | **Abandon** (comportement actuel conservé). |
| Aucun outil sha256 (`sha256sum`/`shasum`) | **Abandon**, avec le repli `shasum` ajouté (§ Problème). |

### Pourquoi ne pas exiger de signature *serait* défendable, et pourquoi on le refuse

L'argument adverse : un bug dans la vérification casse l'auto-update de tous les
utilisateurs, qui n'ont alors plus de canal pour recevoir le correctif — une
panne auto-aggravante. Il est sérieux. Il est traité par de la **prévention**,
pas par de la permissivité :

- Un job CI nocturne vérifie la **vraie release publiée** avec la **vraie clé
  publique commitée** (§ 6). Une dérive clé/asset est détectée en <24 h, côté
  mainteneur, avant qu'un utilisateur ne la rencontre.
- L'étape « vérifier avant publier » du workflow (§ 5) rend structurellement
  impossible la publication d'une release que le client refuserait.
- Le chemin de récupération existe et est documenté : réinstallation via
  l'installeur, qui ne dépend pas de l'updater.

Une phase « avertir sans bloquer » aurait été le compromis confortable. Elle
livre zéro sécurité pendant sa durée et crée une seconde migration à faire plus
tard. On ne la fait pas.

### Une seule échappatoire, étroite

`NIVUUS_ALLOW_UNVERIFIED_UPDATE=1` n'a d'effet que sur `nivuus-update` invoqué
**manuellement dans un terminal interactif**, et affiche alors une confirmation
explicite. Elle est **sans effet** sur `_nivuus_check_update_async`. Motif : un
utilisateur qui tape la commande et confirme prend une décision consciente ; un
processus d'arrière-plan ne peut pas prendre de décision consciente à sa place.

`NIVUUS_VERIFY_CHECKSUMS=false` est restreint à l'étape d'empreinte et **ne
désactive plus rien** du chemin de signature. (Alternative — suppression pure
et simple — voir § 9.)

## 5. Impacts sur le code

### `config/20-autoupdate.zsh`

Le changement structurant est une **séparation** : la vérification sort du
téléchargement pour devenir une fonction pure, testable sans réseau. C'est ce
qui rend le § 7 possible.

```zsh
# Pure : ne télécharge rien, ne dépend d'aucun état global.
# 0 = signature valide contre l'un des jeux de clés de confiance.
_nivuus_verify_signature() {
    local sums_file=$1 sig_dir=$2 keys_dir=${3:-$NIVUUS_SHELL_DIR/keys}
    ...
}

# Pure également : repli shasum, corrige le cas macOS.
_nivuus_sha256_of() { ... }
```

`_nivuus_download_release` télécharge en plus `SHA256SUMS.sig` et
`SHA256SUMS.sshsig`, appelle `_nivuus_verify_signature`, et **retourne 1 avant
toute écriture** en cas d'échec. L'ordre importe : signature d'abord, empreinte
ensuite — vérifier l'empreinte contre un `SHA256SUMS` non authentifié n'a aucun
sens.

Le rejeu inter-versions est déjà bloqué sans effort supplémentaire : le client
cherche la ligne `nivuus-shell-v${version}.tar.gz` dans `SHA256SUMS`, et ce nom
versionné fait partie du contenu signé. Une signature valide de la release 3.1.0
ne valide pas l'archive 3.2.0. À conserver explicitement (ne pas « simplifier »
le `grep` en `head -n1` un jour).

### `.github/workflows/release.yml`

Le job `release` est scindé : la partie qui touche la clé déclare
`environment: release` et ne fait que signer.

```yaml
  sign:
    needs: build
    environment: release      # secrets + règle de protection
    steps:
      - name: Sign SHA256SUMS
        env:
          KEY_ECDSA: ${{ secrets.NIVUUS_SIGNING_KEY_ECDSA }}
        run: |
          umask 077
          keyfile="$(mktemp)"; trap 'shred -u "$keyfile" 2>/dev/null || rm -f "$keyfile"' EXIT
          printf '%s' "$KEY_ECDSA" > "$keyfile"
          openssl dgst -sha256 -sign "$keyfile" \
              -out release-assets/SHA256SUMS.sig release-assets/SHA256SUMS
      # idem ssh-keygen -Y sign  → SHA256SUMS.sshsig
      # idem gpg --detach-sign  → SHA256SUMS.asc   (écosystème, hors chemin client)

      - name: Verify before publishing        # ← étape la plus importante du job
        run: |
          openssl dgst -sha256 -verify keys/nivuus-release-2026.pem \
              -signature release-assets/SHA256SUMS.sig release-assets/SHA256SUMS
```

L'étape « vérifier avant publier » utilise la **clé publique commitée dans le
dépôt**, pas celle dérivée du secret. Elle attrape le scénario opérationnel le
plus probable de tout ce chantier : rotation du secret sans commit de la clé
publique correspondante, c'est-à-dire une release que plus aucun client
n'accepte.

Autres modifications : `permissions: id-token: write, attestations: write` pour
`actions/attest-build-provenance` ; `gh release create release-assets/*`
n'a pas besoin d'être touché (il ramasse les nouveaux fichiers) ; la signature
de l'annotation de tag (`git tag -s` avec `gpg.format=ssh`) est ajoutée en
phase 4 comme second ancrage pour les auditeurs.

### Installeur (`bin/nivuus`, `lib/steps.sh`, `install.sh`)

- `nivuus_step_copy_tree` : ajouter `keys` à la liste des répertoires copiés.
  **Sans ça, rien ne fonctionne.**
- Nouvelle étape consultative `nivuus_step_check_verify_tools` : avertit — sans
  bloquer — si ni `openssl` ni `ssh-keygen` n'est présent, en disant clairement
  que l'auto-update sera inactif sur cette machine et comment y remédier.
  Avertir à l'installation, pas au moment de l'échec.
- `install.sh --verify-key <empreinte>` (§ 3).
- Bootstrap piped (phase 5 du chantier 1, qui télécharge le tarball de release)
  : vérifie la signature avec la clé téléchargée en même temps. C'est un
  contrôle de **cohérence**, pas d'origine — même origine, cf. § 3. Il vaut
  quand même d'être fait : il couvre le cas « assets compromis mais dépôt
  intact », qui est le scénario réaliste. À documenter comme tel, sans
  survendre.
- `nivuus doctor` : affiche les empreintes des clés de confiance, l'outil de
  vérification retenu sur cette machine, et l'état de la dernière vérification.

## 6. Tests et CI

### La vraie clé n'est jamais dans un test

Chaque test génère son propre jeu de clés éphémère dans son `setup()` :

```bash
setup() {
    TESTKEYS="$(mktemp -d)"
    openssl ecparam -name prime256v1 -genkey -noout -out "$TESTKEYS/priv.pem"
    openssl ec -in "$TESTKEYS/priv.pem" -pubout -out "$TESTKEYS/nivuus-test.pem"
    ssh-keygen -q -t ed25519 -N '' -f "$TESTKEYS/id" -C nivuus-test
}
```

Le chemin du répertoire de clés est un **paramètre** de
`_nivuus_verify_signature` (§ 5), pas une constante — c'est ce qui permet aux
tests d'injecter le jeu éphémère sans variable d'environnement de contournement
en production. (Le fait qu'un attaquant contrôlant l'environnement du shell
puisse de toute façon désactiver l'auto-update est vrai, mais n'est pas une
raison d'ajouter une porte : on n'en ajoute pas.)

### `tests/unit/test_release_signature.bats`

Le test qui compte est le **négatif**. Une suite qui ne prouve que le cas
nominal ne prouve rien : elle passerait aussi avec une fonction
`return 0`.

| # | Cas | Attendu |
|---|---|---|
| 1 | `SHA256SUMS` intact, signature valide | acceptée |
| 2 | **`SHA256SUMS` modifié d'un octet, signature d'origine** | **refusée** |
| 3 | **Archive falsifiée, `SHA256SUMS` régénéré et signé par une clé d'attaquant** | **refusée** — le test central : c'est le scénario réel |
| 4 | Archive falsifiée, `SHA256SUMS` authentique signé | refusée (empreinte) |
| 5 | Fichier `.sig` absent | refusée (pas de repli SHA256) |
| 6 | `.sig` tronqué / vide / non binaire | refusée, sans erreur zsh parasite |
| 7 | Signature valide d'un *autre* `SHA256SUMS` (rejeu inter-versions) | refusée |
| 8 | `openssl` absent du `PATH`, `ssh-keygen` présent | acceptée via SSHSIG |
| 9 | Les deux absents | **refusée** — vérifie explicitement l'absence de dégradation |
| 10 | Clé retirée du jeu (révocation) | refusée |
| 11 | Deux clés de confiance, signature de la seconde | acceptée (rotation) |
| 12 | `sha256sum` absent, `shasum` présent | acceptée (régression macOS) |

Cas 3 et 9 sont les invariants du chantier. S'ils passent, la propriété
recherchée existe. S'ils manquent, tout le reste est décoratif.

### End-to-end

Une fausse release servie localement (fixture + serveur HTTP éphémère,
`NIVUUS_GITHUB_REPO`/`NIVUUS_GITHUB_API` étant déjà surchargeables) :

- Chemin nominal : `nivuus-update` installe, `.version` progresse.
- **Chemin falsifié : l'archive est modifiée après signature → la mise à jour
  est refusée ET l'installation existante est intacte**, vérifié par
  l'empreinte `$HOME` de `tests/helpers/fingerprint.bash` (déjà écrit pour le
  test de réversibilité du chantier 1 — on le réutilise, on n'en écrit pas un
  second).
- Client sans outil de vérification : refus, installation intacte.

### Jobs CI

- **Sur PR** : suite unitaire de signature (rapide, aucun réseau).
- **Sur release** : « vérifier avant publier » (§ 5), bloquant.
- **Nocturne, en production** : télécharger la dernière release réelle et la
  vérifier avec la clé publique commitée. C'est le canari qui rend le refus dur
  du § 4 tenable.
- **Sonde de disponibilité** (une fois, en phase 1) : dans chaque image cible de
  la matrice du chantier 1 (Ubuntu, Debian, Alpine, Arch, Fedora, macOS),
  exécuter `command -v openssl ssh-keygen` et publier le tableau. La hiérarchie
  primaire/repli du § 1 est une **hypothèse argumentée** ; cette sonde la
  transforme en fait, ou la corrige avant que du code n'en dépende.

## 7. Périmètre

### Inclus

Signature de `SHA256SUMS` en trois formats, vérification client à deux chemins,
jeu de clés versionné et rotation par pré-distribution, refus dur, correction du
repli `shasum`, extraction de la vérification en fonction pure, `--verify-key`,
diagnostics `doctor`, attestation de provenance, `SECURITY.md` (modèle de
menace, empreintes, procédure de signalement), documentation honnête du
problème d'amorçage.

### Hors périmètre

- **TUF / journal de transparence côté client** — la bonne réponse au problème
  de rotation et de révocation à grande échelle, disproportionnée pour un
  updater de framework zsh.
- **cosign en vérification client** (§ 1) ; l'attestation reste publiée.
- **Builds reproductibles** — propriété voisine et souhaitable (elle permettrait
  à un tiers de recalculer l'archive), spec distincte du chantier 2.
- **Notarisation Apple / Gatekeeper** — n'intervient pas pour des scripts shell.
- **Signature des paquets brew/AUR/.deb** — chantier 4, qui consommera les
  artefacts produits ici.
- **Signature des `.zwc` ou des fichiers individuels** — l'archive est l'unité
  de distribution.
- **Récupération d'une machine déjà compromise** — impossible par mise à jour
  (§ 2.3), la réponse est la réinstallation.

## 8. Séquence de livraison

Quatre phases, chacune mergeable seule.

1. **Produire** — clés générées hors ligne et sauvegardées (sauvegarde
   *testée*), secrets posés dans l'environnement `release` protégé, `keys/`
   commité (jeu courant **et** succession), CI qui signe et vérifie avant de
   publier, attestation de provenance, sonde de disponibilité des outils.
   *Aucun changement client.* Les installations existantes ne voient rien.
   *Sortie : une release porte `.sig`, `.sshsig`, `.asc` ; le canari nocturne
   est vert ; les anciens clients continuent de se mettre à jour normalement.*

2. **Vérifier** — extraction de `_nivuus_verify_signature` et
   `_nivuus_sha256_of` (correction macOS), refus dur, suite unitaire complète
   dont les cas 3 et 9, e2e avec archive falsifiée.
   *Sortie : cas négatifs verts ; une archive falsifiée ne s'installe pas et ne
   dégrade pas l'installation existante.*

3. **Installer** — `keys` copié par `nivuus_step_copy_tree`, avertissement à
   l'installation si aucun outil de vérification, `--verify-key`, `doctor`
   enrichi, vérification du bootstrap piped.
   *Sortie : une installation neuve sur chaque cible de la matrice possède la
   clé et se met à jour ; Alpine sans `openssl` avertit à l'install.*

4. **Gouverner** — `SECURITY.md`, publication multi-origines des empreintes,
   procédure de rotation écrite **et répétée en blanc** sur une release de test,
   dénylist, tag git signé.
   *Sortie : une rotation complète a été exécutée une fois, de bout en bout,
   avant d'en avoir besoin.*

## 9. Risques et questions ouvertes

### Risques

**Perte ou compromission de la clé** — risque principal, § 2.4. Mitigation :
succession pré-distribuée dès la phase 1, sauvegarde hors ligne testée avant la
première release signée. Non mitigeable au-delà : c'est le coût du modèle à clé
épinglée, assumé sciemment.

**Rotation du secret sans commit de la clé publique** — panne la plus probable
en pratique, et totalement silencieuse jusqu'à ce que les clients refusent tout.
Mitigation structurelle : l'étape « vérifier avant publier » du § 5 rend la
publication impossible dans ce cas.

**`keys/` oublié dans `nivuus_step_copy_tree`** — casse toutes les
installations neuves. Mitigation : test e2e de phase 3 sur installation neuve.

**Refus dur qui casse l'auto-update en masse** — § 4 ; mitigé par le canari
nocturne, la vérification pré-publication, et un chemin de récupération
documenté qui ne passe pas par l'updater.

**Faux sentiment de sécurité** — un badge « signé » laissant croire que le
`curl | sh` est authentifié serait une régression de confiance, pas un progrès.
Mitigation : la formulation du § 3 est reprise telle quelle dans le README et
`SECURITY.md` ; pas de badge « secure ».

### Questions ouvertes (arbitrage requis)

1. **Approbation manuelle des releases.** Une règle de protection avec
   réviseur requis sur l'environnement `release` est ce qui empêche un dépôt
   compromis de produire une signature valide — c'est la moitié du bénéfice du
   § 2. Elle impose un clic humain à chaque release. Acceptable, ou signature
   automatique (bénéfice réduit) ?
2. **Support matériel.** Une YubiKey rendrait la clé non exfiltrable, mais un
   runner GitHub ne peut pas s'en servir : il faudrait signer depuis une machine
   locale et publier les signatures ensuite, ce qui change entièrement le
   workflow. Hors périmètre proposé — à confirmer.
3. **Ancrage hors bande.** Existe-t-il un domaine contrôlé par le mainteneur
   (type `nivuus.dev`) pour publier les empreintes hors de GitHub ? Sans lui,
   l'ancrage hors bande reste intra-GitHub et le § 3 est plus faible.
4. **Identité GPG.** Le mainteneur possède-t-il déjà une clé GPG publiée et
   liée à son identité GitHub ? Si non, faut-il vraiment produire le `.asc`
   avant qu'un mainteneur de paquet ne le demande (chantier 4) ?
5. **`NIVUUS_VERIFY_CHECKSUMS`** — restreinte à l'empreinte (proposition du
   § 4) ou supprimée purement et simplement ? La supprimer est plus propre et
   casse une option publiquement documentée dans le README.
6. **Ordre primaire/repli `openssl` vs `ssh-keygen`** — à trancher sur les
   données de la sonde de disponibilité (§ 6) plutôt que sur l'hypothèse du
   § 1, si elles la contredisent.
7. **Cadence de rotation.** Annuelle proposée ; à confirmer, sachant que chaque
   rotation est un exercice à risque et qu'en tourner trop souvent est
   contre-productif.
