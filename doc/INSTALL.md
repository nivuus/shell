# Installer Nivuus Shell

## En une ligne (recommandé)

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

Ce que ça fait : télécharge l'archive de la dernière release, **vérifie son empreinte SHA-256**,
l'installe dans `~/.nivuus-shell`, ajoute un bloc délimité à ton `~/.zshrc`, et supprime son
répertoire temporaire. Aucun dépôt git n'est créé, rien n'est installé avec `sudo`.

Sans `curl`, `wget` fait l'affaire :

```bash
wget -qO- https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

Pour figer la version installée, préfixe la commande de `NIVUUS_VERSION=x.y.z`. La forme épinglée
de l'URL (`.../v<version>/install.sh`) reste valide elle aussi.

### Ce que le one-liner ne garantit PAS

Le script, l'archive et les sommes de contrôle viennent tous de **la même origine** — GitHub. La
vérification d'empreinte protège d'un transfert corrompu ou d'un cache CDN empoisonné ; elle ne
protège pas d'une origine compromise, qui pourrait remplacer les trois de façon cohérente. C'est le
problème d'**amorçage**, et il n'a pas de solution interne au one-liner. On ne le maquille pas.

La seule réponse est un canal secondaire. Obtiens l'empreinte du jeu de clés de signature ailleurs
que sur GitHub (voir [SECURITY.md](../SECURITY.md)), puis :

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh \
  | sh -s -- --verify-key <empreinte>
```

L'installation est refusée **avant la moindre écriture** si l'empreinte ne correspond pas.

Il n'existe aucune option pour désactiver la vérification d'empreinte de l'archive : ce qui n'est
pas vérifiable n'est pas installé. Si la machine n'a ni `sha256sum` ni `shasum`, l'amorçage refuse
d'installer plutôt que de faire semblant.

### Options

```bash
| sh -s -- --dry-run        # n'écrit rien, montre ce qui serait fait
| sh -s -- --minimal        # serveur / container : pas de chsh, pas d'extras
| sh -s -- --with-deps      # propose UNE commande groupée pour les outils recommandés
| sh -s -- --prefix DIR     # installe ailleurs que dans ~/.nivuus-shell
```

Variables d'environnement : `NIVUUS_VERSION` fige la version installée ;
`NIVUUS_RELEASE_BASE_URL` et `NIVUUS_GITHUB_API` pointent vers un miroir interne (ou, en test,
vers un `file://`). Un miroir en `http://` est accepté délibérément — c'est l'empreinte, pas le
transport, qui fait foi ici.

## Sans piper du réseau dans un shell

```bash
VERSION=$(curl -fsSL https://api.github.com/repos/maximeallanic/nivuus-shell/releases/latest \
          | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
BASE=https://github.com/maximeallanic/nivuus-shell/releases/download/v$VERSION
curl -fLO $BASE/nivuus-shell-v$VERSION.tar.gz
curl -fLO $BASE/SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS      # macOS : shasum -a 256 -c
mkdir nivuus && tar -xzf nivuus-shell-v$VERSION.tar.gz -C nivuus
./nivuus/install.sh
```

La vérification fait partie de la procédure : une méthode « plus sûre » sans étape de vérification
serait surtout plus longue.

## Pour développer

```bash
git clone https://github.com/maximeallanic/nivuus-shell.git
cd nivuus-shell && ./install.sh
```

C'est le seul cas où `~/.nivuus-shell` est légitimement un dépôt git — et la mise à jour par
release y est alors désactivée, volontairement (`git pull` la remplace).

## Par plateforme

| Plateforme | Prérequis | Remarque |
|---|---|---|
| Ubuntu / Debian | `apt-get install zsh curl` | rien de plus |
| Fedora | `dnf install zsh curl` | |
| Arch | `pacman -S zsh curl` | |
| Alpine | `apk add zsh curl bash tar` | `bash` est requis par l'installeur, pas par le shell |
| macOS | `brew install zsh` | si zsh vient de brew, `chsh` demande d'ajouter le chemin à `/etc/shells` — la commande exacte est affichée, jamais exécutée |
| WSL | `apt-get install zsh curl` | détecté automatiquement |
| Container / serveur / SSH | idem distribution | `--minimal` est activé tout seul |

`git` **n'est pas requis** : il n'est utilisé que pour le prompt git, qui se désactive proprement
en son absence. L'installation **sans git** est un cas testé, pas une tolérance.

## Installation par un gestionnaire de paquets

Quand Nivuus est installé par un paquet, l'arbre appartient au gestionnaire
et **l'activation reste un acte par utilisateur** :

    nivuus enable      # ajoute le bloc à ~/.zshrc (et propose chsh)
    nivuus disable     # retire le bloc, sans toucher à l'arbre

Les mises à jour automatiques sont alors désactivées : c'est le gestionnaire
qui les gère. `nivuus update` affiche sa commande exacte et sort en 0.

`nivuus install` fait la même chose que `nivuus enable` dans ce mode, et le
dit — il n'y a rien à copier, le paquet a déjà tout posé.

Le bloc écrit dans `~/.zshrc` est **gardé** :

    [ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"

Si le paquet est retiré alors que le bloc subsiste, le shell démarre sans la
moindre erreur. `nivuus doctor` nomme ce cas et donne la commande de
réparation.

Aucun canal n'est encore publié : cette section décrit le comportement de
Nivuus face à un paquet, pas une commande d'installation disponible
aujourd'hui. Voir `doc/PACKAGING.md`.

## Désinstaller

```bash
nivuus uninstall              # retire tout ce que Nivuus a écrit, restaure ton .zshrc
nivuus uninstall --purge      # retire aussi l'état interne (manifeste, sauvegardes)
nivuus uninstall --dry-run    # montre ce qui serait retiré, sans rien faire
```

La désinstallation restaure chaque fichier modifié à partir de la sauvegarde enregistrée à
l'installation, à l'octet près. `~/.zsh_local` et `~/.zsh_history` ne sont jamais supprimés.

## Mettre à jour, et le cas des anciennes installations

```bash
nivuus update
```

Si Nivuus a été installé avant la v3.1 par l'ancien one-liner, un dépôt git a été créé dans
`~/.nivuus-shell` et **bloque toutes les mises à jour** depuis. Pour le débloquer :

```bash
nivuus migrate
```

Le dépôt est **déplacé** (jamais supprimé) sous `~/.local/state/nivuus/migration/`, et le chemin
est affiché, avec la commande pour revenir en arrière. `nivuus migrate` ne touche jamais à un vrai
dépôt de développement : au moindre doute, il n'agit pas.

## Diagnostic

```bash
nivuus doctor
```

`nivuus doctor` signale le dépôt git hérité s'il est présent, sans jamais y toucher.
