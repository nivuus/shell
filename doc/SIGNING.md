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

## Rotation, révocation et secrets

Voir la section « Procédure de mise en service du trousseau » ci-dessous
(à compléter par le mainteneur lors de la génération du trousseau réel).
