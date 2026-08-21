# Trousseau de confiance des releases Nivuus

Ce répertoire contient **uniquement du matériel public**. Toute clé privée qui
y apparaîtrait serait une compromission, pas une erreur de rangement.

| Fichier | Rôle |
|---|---|
| `nivuus-release-<année>.pem` | Clé publique ECDSA P-256, chemin de vérification `openssl` |
| `allowed_signers` | Clés publiques Ed25519 au format `ssh-keygen -Y`, chemin de repli |
| `revoked` | Empreintes révoquées, une par ligne. Une clé listée ici est refusée même si elle est encore présente ci-dessus. |

Le trousseau contient toujours **au moins deux jeux** : le jeu courant, qui
signe les releases d'aujourd'hui, et le jeu de succession, pré-distribué pour
que la rotation ne demande jamais d'action à l'utilisateur (voir
`doc/SIGNING.md`).

Le client accepte une release si sa signature est valide contre **l'un
quelconque** des jeux présents et non révoqués.
