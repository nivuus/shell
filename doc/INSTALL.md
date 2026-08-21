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

### Vérifier le trousseau de signature à l'installation (optionnel)

Les mises à jour sont authentifiées par des clés publiques livrées avec
l'installation. Tu peux épingler ce trousseau au moment de l'installer, avec
`--verify-key` (ci-dessus). L'empreinte de référence est publiée dans
[SECURITY.md](../SECURITY.md#first-install), et **n'est recopiée nulle part
ailleurs** : une empreinte dupliquée est une empreinte qui divergera.

Si le trousseau embarqué ne correspond pas à l'empreinte fournie,
l'installation est refusée **avant** la moindre écriture.

**Limite honnête** : cela ne résout pas la **première installation**. Le dépôt
et la clé publique viennent de la même origine — qui contrôle cette origine à
cet instant sert son installeur *et* sa clé. Aucune signature ne peut résoudre
ça. Ce que la signature protège, c'est le canal de **mise à jour** : récurrent,
automatique, invisible, sur toutes les machines, pour toujours.

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

## Administration : installer pour toute une machine

**Sur Debian et Ubuntu, préfère le paquet.** `apt install ./nivuus-shell_<version>_all.deb`
est inventorié par `dpkg`, vérifiable par `dpkg -V` et retiré par `apt purge`. `--system`
refait ce travail lui-même ; le paquet le fait mieux. L'installeur te le rappelle avant
d'écrire quoi que ce soit — c'est une information, pas un refus.

Partout ailleurs — Fedora, RHEL, Rocky, openSUSE, Alpine, images de conteneur, machines
sans réseau sortant — il n'y a pas de paquet, et c'est ce que `--system` sert :

```bash
sudo nivuus install --system
```

Ce que ça écrit, et rien d'autre :

| Chemin | Rôle |
|---|---|
| `/usr/local/share/nivuus-shell/` | l'arbre partagé, en lecture seule pour les utilisateurs |
| `/usr/local/bin/nivuus` | le point d'entrée (un lien vers l'arbre) |
| `/usr/local/share/man/man1/nivuus.1` | la page de manuel |
| `/var/lib/nivuus/manifest.tsv` | l'inventaire : ce qui a été écrit, et comment le défaire |

**Aucun `~/.zshrc` n'est touché. Aucun `chsh` n'est fait**, pour personne. L'activation
reste un acte par utilisateur : chacun lance `nivuus enable`, sans privilège.

Pour auditer avant de décider d'élever les privilèges — la commande fonctionne
**sans root** et n'écrit rien :

```bash
nivuus install --system --dry-run
```

L'installation se termine par une **sonde** : un zsh non privilégié charge réellement
l'arbre. Si aucun shell ne peut le lire (umask hostile, SELinux sans `restorecon`,
`/usr/local` monté `noexec`), l'installation est **annulée** plutôt que laissée en place.

### Activer pour les comptes créés ensuite (`--skel`)

```bash
sudo nivuus install --system --skel
```

`/etc/skel` ne s'applique qu'aux comptes **créés après** cette commande. Les comptes déjà
présents ne sont pas activés — c'est une limite du mécanisme, pas un défaut de Nivuus, et
le message de succès te donne le nombre exact de comptes non couverts. Là où `/etc/skel`
n'existe pas (macOS, Alpine), `--skel` est **refusé**, jamais ignoré en silence.

### Activer pour toute la machine (`nivuus enable --all`)

```bash
sudo nivuus enable --all
```

Ajoute un drop-in `/etc/zsh/zshrc.d/10-nivuus.zsh` et **une seule ligne** au fichier zsh
global. Le drop-in cède toujours à l'utilisateur : qui a son propre bloc dans `~/.zshrc`
garde son installation. Sur Debian et Ubuntu, le fichier zsh global est un conffile `dpkg` :
une future mise à jour de `zsh-common` posera peut-être la question « conffile modifié ».
`nivuus doctor` le signale par avance. Pour gérer `/etc` toi-même (Ansible, image
immuable, `/etc` sous git) :

```bash
nivuus enable --all --print      # affiche le fichier et la ligne, n'écrit rien
```

La même activation peut être demandée dès l'installation, en une seule commande :

```bash
sudo nivuus install --system --activate-all
```

L'activation est **vérifiée** après écriture : si aucun zsh interactif ne voit le marqueur,
elle est annulée et le chemin exact à corriger est affiché. Pour la retirer :

```bash
sudo nivuus disable --all
```

### Mettre à jour

```bash
sudo nivuus update
```

C'est une réinstallation depuis une release **vérifiée** (empreinte SHA-256 fail-closed,
puis signature), qui passe par le manifeste et reste donc réversible. Les shells des
utilisateurs ne se mettent jamais à jour tout seuls sur un arbre système : `nivuus update`
leur répond quoi taper, et sort en 0. **Aucun ordonnanceur n'est fourni** — ni unité
systemd, ni cron : branche cette commande sur le tien.

### Diagnostiquer

```bash
nivuus doctor
sudo nivuus doctor --system --scan-users
```

`--scan-users` liste les comptes locaux dont le `~/.zshrc` porte le bloc Nivuus. Il est
**opt-in et en lecture seule** : sur un parc NFS, lire un `$HOME` déclenche l'automonteur,
donc ce n'est jamais automatique.

### Désinstaller

```bash
sudo nivuus uninstall --system
```

Rejoue le manifeste système et **rien d'autre** : `/etc`, `/usr/local` et `/var/lib`
redeviennent bit-identiques à ce qu'ils étaient. La commande n'écrit dans **aucun `$HOME`**
et ne les lit même pas. Les activations par utilisateur subsistent — elles appartiennent à
chaque compte, leurs shells ne cassent pas (le bloc `.zshrc` est gardé, il teste l'arbre
avant de le charger), et chacun peut faire `nivuus disable`.

### Une installation faite par l'ancien `--system`

Avant la v3.1, `--system` posait un arbre dans `/etc/nivuus-shell` **sans manifeste** :
il n'est pas réversible automatiquement, et l'installation actuelle refuse d'écrire
par-dessus plutôt que de rendre la situation irréparable. Procédure, et comment
revenir en arrière :

```bash
sudo mv /etc/nivuus-shell /etc/nivuus-shell.avant-migration
sudo nivuus install --system
# pour revenir en arrière :
sudo mv /etc/nivuus-shell.avant-migration /etc/nivuus-shell
```

### Image de conteneur

```dockerfile
RUN sh install.sh --system --skel --non-interactive
```

### Ansible

```yaml
- name: Installer Nivuus pour la machine
  ansible.builtin.command: nivuus install --system --yes
  args: { creates: /usr/local/share/nivuus-shell/.nivuus-origin }
```
