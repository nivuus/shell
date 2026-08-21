# Politique de sécurité

## Ce que la signature garantit, et ce qu'elle ne garantit pas

Le fichier `SHA256SUMS` de chaque release est signé. Le client refuse
d'installer une mise à jour dont la signature n'est pas valide contre une
clé publique livrée avec l'installation. Il n'existe **aucune** dégradation
vers la simple empreinte SHA256.

| Scénario | Avant | Après |
|---|---|---|
| Compromission des assets de release seuls (jeton fuité, Action tierce, job voisin) | exécution de code chez tous les utilisateurs | **bloquée** |
| MITM avec une CA de confiance sur le chemin de mise à jour | réussit | **bloquée** |
| Miroir ou re-hébergement tiers | invérifiable | **vérifiable** |
| Corruption en transit | couverte | couverte |
| Première installation via `curl \| sh` | vulnérable | **toujours vulnérable** |
| Compromission de la clé de signature | — | non couverte |
| Mainteneur malveillant | — | non couverte, par construction |

**La signature ne résout pas la première installation.** Le one-liner
`curl … | sh` télécharge l'installeur et la clé publique depuis la même
origine : qui contrôle cette origine à cet instant sert son installeur et sa
clé. Aucune signature ne peut résoudre ça — c'est le problème de la racine de
confiance, et il se termine toujours par « quelque chose doit être connu à
l'avance ».

Ce que la signature déplace est ailleurs, et c'est l'essentiel : la première
installation est **un instant, sous les yeux de l'utilisateur, une fois**. La
mise à jour est **récurrente, automatique, invisible, sur toutes les machines,
pour toujours**. Signer fait passer la fenêtre d'attaque de « permanente et
silencieuse » à « ponctuelle et observable ».

## Empreinte du jeu de clés

    <à renseigner par le mainteneur : sortie de « nivuus_keyset_fingerprint keys »
     une fois le trousseau réel généré — voir doc/SIGNING.md, étape 5>

Vérifie-la avant d'installer :

```bash
./install.sh --verify-key <empreinte>
```

L'installeur refuse de continuer si le jeu de clés embarqué ne correspond pas,
et n'écrit rien.

Pour lire l'empreinte de ton installation existante :

```bash
nivuus doctor      # section « Update signing »
```

**Limite honnête de l'ancrage :** cette empreinte est publiée sur GitHub
(ce fichier, le README, le profil du mainteneur). Le projet ne dispose
aujourd'hui d'aucun domaine hors GitHub pour la publier ailleurs. L'ancrage
hors bande est donc **intra-GitHub**, et un attaquant qui contrôlerait
l'ensemble du compte GitHub pourrait modifier simultanément l'empreinte et les
clés. Cette limite est réelle et assumée ; elle sera levée le jour où un
domaine indépendant existera.

## Outils requis pour vérifier

La vérification utilise `openssl` (chemin primaire, ECDSA P-256) ou, à
défaut, `ssh-keygen -Y verify` (repli, Ed25519 SSHSIG). **Aucun des deux
n'est une dépendance d'installation** — Nivuus s'installe sans. Mais sur une
machine qui n'a ni l'un ni l'autre (mesuré : Alpine minimale), la mise à jour
automatique reste **inactive** : elle n'installera jamais une release qu'elle
ne peut pas authentifier. `nivuus doctor` le dit explicitement.

## Anti-rétrogradation

Une mise à jour n'est déclenchée que vers une version **supérieure**. Un
attaquant ne peut donc pas rejouer une release antérieure signée par une clé
depuis révoquée. C'est une propriété de sécurité, pas seulement du confort.

De même, le nom **versionné** de l'archive fait partie du contenu signé : une
signature authentique de la release X ne vaut pas pour la release Y.

## Rotation et révocation

Voir [`doc/SIGNING.md`](doc/SIGNING.md). En résumé : le trousseau installé
contient toujours le jeu courant **et** son successeur, pré-distribué au moins
une release avant son premier usage — la rotation est invisible et ne demande
aucune action.

Une clé compromise ayant déjà signé une release malveillante ne peut pas être
« dé-signée » chez les utilisateurs déjà mis à jour : **le code malveillant
contrôle la mise à jour**. La procédure de récupération d'une machine
compromise est une réinstallation, pas une mise à jour.

## Signaler une vulnérabilité

<adresse ou canal privé — à renseigner par le mainteneur>
Ne pas ouvrir d'issue publique pour une vulnérabilité de la chaîne de
distribution.
