# Nivuus Shell - Prompt Format

Documentation du format exact du prompt shell.

> Le thème (couleurs) et le format (ordre/présence des segments) du prompt
> sont **entièrement configurables** via `~/.zshrc` / `~/.zsh_local`, sans
> modifier le code. Voir [Thème & Format Configurables](#thème--format-configurables)
> plus bas. Le format visuel ci-dessous décrit le rendu **par défaut**.

## Format Visuel

### Local (succès)
```
> ~/projects/myapp git:(main)●
```

### Local (erreur)
```
> ~/projects/myapp git:(main)○
```

### SSH (succès)
```
[hostname] > ~/projects/myapp git:(feature-branch)●
```

### Root
```
# > /root git:(main)●
```

### Avec Python venv
```
> ~/projects/myapp (venv) git:(main)●
> ~/projects/myapp (conda:myenv) git:(main)●
> ~/projects/myapp (poetry) git:(main)●
```

### Avec Cloud Context
```
> ~/projects/myapp aws:production git:(main)●
> ~/projects/myapp gcp:my-project git:(main)●
> ~/projects/myapp az:subscription git:(main)●
```

### Avec Firebase
```
> ~/projects/myapp [my-firebase-project] git:(main)●
```

### Avec Background Jobs (RPROMPT)
```
> ~/projects/myapp git:(main)●                                    [▶ vim ⏸ npm]
> ~/projects/myapp git:(main)●                                         [▶ 3 ⏸ 1]
```

---

## Composants du Prompt (Main)

### 1. Indicateur SSH
**Format:** `[hostname]`
**Couleur:** Gris (brackets) + Bleu (hostname)
**Condition:** Affiché uniquement si connexion SSH
**Détection:** Variables `$SSH_CLIENT`, `$SSH_TTY`, ou `$SESSION_TYPE`

### 2. Indicateur Root
**Format:** `#`
**Couleur:** Rouge
**Condition:** Affiché uniquement si utilisateur root
**Détection:** `$EUID == 0` ou `whoami == "root"`

### 3. Indicateur de Status
**Format:** `>`
**Couleurs:**
- **Vert (gras)** - Dernière commande réussie (exit code 0)
- **Rouge (gras)** - Dernière commande échouée (exit code ≠ 0)

### 4. Chemin Actuel
**Format:** `~/path/to/directory`
**Couleur:** Cyan
**Comportement:**
- Affiche `~` pour le home directory
- Chemin relatif depuis ~
- Chemin complet si hors du home

### 5. Python Virtual Environment (Optionnel)
**Format:** `(venv)`, `(conda:name)`, ou `(poetry)`
**Couleur:** `$THEME_COLORS[magenta]` du thème actif
**Condition:**
- Variable `ENABLE_PYTHON_VENV=true` (défaut)
- Environnement virtuel actif détecté

**Types supportés:**
- **venv/virtualenv** - Affiche `(venv)`
- **Conda** - Affiche `(conda:env-name)`
- **Poetry** - Affiche `(poetry)`

**Désactiver:**
```bash
export ENABLE_PYTHON_VENV=false
```

### 6. Cloud Provider Context (Optionnel)
**Format:** `aws:profile`, `gcp:project`, ou `az:subscription`
**Couleurs:**
- **AWS** - `$THEME_COLORS[orange]`
- **GCP** - `$THEME_GIT_PREFIX`
- **Azure** - `$THEME_SSH`

**Condition:**
- Variable `ENABLE_CLOUD_PROMPT=true` (défaut)
- Context cloud actif détecté

**Détection:**
- **AWS:** `$AWS_PROFILE` (sauf "default")
- **GCP:** `$CLOUDSDK_CORE_PROJECT` (si Firebase prompt désactivé)
- **Azure:** `$AZURE_SUBSCRIPTION_ID` ou subscription name

**Désactiver:**
```bash
export ENABLE_CLOUD_PROMPT=false
```

### 7. Projet Firebase (Optionnel)
**Format:** `[project-name]`
**Couleur:** `$THEME_COLORS[orange]`
**Condition:**
- Projet Firebase actif dans le répertoire courant
- Fichier `~/.config/configstore/firebase-tools.json` existe
- Variable `ENABLE_FIREBASE_PROMPT=true` (défaut)

**Désactiver:**
```bash
export ENABLE_FIREBASE_PROMPT=false
```

### 8. Information Git
**Format:** `git:(branch)●` ou `git:(branch)○`
**Couleurs:**
- `git:(` - `$THEME_GIT_PREFIX`
- `branch` - `$THEME_GIT_BRANCH`
- `)` - `$THEME_GIT_PREFIX`
- `●` - `$THEME_SUCCESS` (repo propre)
- `○` - `$THEME_ERROR` (modifications non commitées)

**Comportement:**
- Affiché uniquement dans un dépôt git
- Cache de 2 secondes pour les performances (configurable)
- `○` (cercle vide) indique des fichiers modifiés/staged/untracked
- `●` (cercle plein) indique un repo propre

---

## Composants du Prompt (Right - RPROMPT)

### Background Jobs
**Format:** `[▶ name1 ⏸ name2]` ou `[▶ 3 ⏸ 1]`
**Couleurs:**
- `▶` + running jobs - `$THEME_SUCCESS`
- `⏸` + stopped jobs - `$THEME_ERROR`

**Comportement:**
- Affiche les jobs en arrière-plan automatiquement
- ≤ 2 jobs: Affiche les noms des commandes
- \> 2 jobs: Affiche les comptes numériques
- Utilise les variables ZSH natives: `${(kv)jobstates}` et `${jobtexts}`
- Mise à jour automatique à chaque prompt

---

## Configuration des Couleurs

### Palette Utilisée

Le prompt ne code plus aucune couleur en dur : chaque segment lit une
variable sémantique (`$THEME_*`) ou une entrée de `$THEME_COLORS[...]`,
toutes deux définies par le thème actuellement chargé (`themes/nord.zsh` par
défaut). Changer de thème change donc automatiquement toutes ces couleurs.

| Élément | Variable |
|---------|----------|
| SSH hostname | `$THEME_SSH` |
| SSH brackets | `$THEME_COLORS[comment]` |
| Root indicator | `$THEME_ROOT` |
| Success status | `$THEME_SUCCESS` |
| Error status | `$THEME_ERROR` |
| Path | `$THEME_PATH` |
| Firebase project | `$THEME_COLORS[orange]` |
| Git prefix | `$THEME_GIT_PREFIX` |
| Git branch | `$THEME_GIT_BRANCH` |
| Git clean (●) | `$THEME_SUCCESS` |
| Git dirty (○) | `$THEME_ERROR` |
| Python venv | `$THEME_COLORS[magenta]` |
| AWS context | `$THEME_COLORS[orange]` |
| GCP context | `$THEME_GIT_PREFIX` |
| Azure context | `$THEME_SSH` |
| RPROMPT running | `$THEME_SUCCESS` |
| RPROMPT stopped | `$THEME_ERROR` |

Valeurs par défaut (thème `nord`) dans `themes/nord.zsh`; un second thème
livré, `dracula`, sert d'exemple pour écrire vos propres thèmes.

---

## Optimisations Performance

### Cache Git (2 secondes)
Le prompt utilise un cache pour éviter les appels git répétés :

**Variables de cache:**
- `_GIT_PROMPT_CACHE_DIR` - Répertoire en cache
- `_GIT_PROMPT_CACHE_TIME` - Timestamp du cache
- `_GIT_PROMPT_CACHE_VALUE` - Valeur en cache

**Configuration du TTL:**
```bash
export GIT_PROMPT_CACHE_TTL=5  # Cache pendant 5 secondes
```

### Désactiver Firebase
Pour améliorer les performances (gain ~10-20ms) :
```bash
export ENABLE_FIREBASE_PROMPT=false
```

---

## Structure Technique

### Ordre de Construction

```
[SSH] [ROOT] STATUS PATH (VENV) CLOUD [FIREBASE] GIT      [JOBS]
                                                           (RPROMPT)
```

**Exemple complet (main prompt):**
```
[myserver] # > ~/project (venv) aws:prod [firebase-app] git:(main)○
```

**Exemple complet (avec RPROMPT):**
```
[myserver] > ~/project gcp:myapp git:(main)●                    [▶ vim ⏸ npm]
```

### Fonctions du Prompt

#### `is_ssh()`
Détecte si la session est en SSH.

#### `prompt_python_venv()`
Détecte et affiche l'environnement virtuel Python actif.

#### `prompt_cloud_context()`
Détecte et affiche le contexte cloud (AWS/GCP/Azure).

#### `prompt_firebase()`
Génère l'information Firebase (optionnel).

#### `git_prompt_info()`
Génère l'information git avec cache et indicateur de statut (●/○).

#### `background_jobs_info()`
Affiche les jobs en arrière-plan pour le RPROMPT.

#### `build_prompt()`
Construit le prompt final en combinant tous les composants.

---

## Variables d'Environnement

### Configuration

```bash
# Cache git (défaut: 2 secondes)
export GIT_PROMPT_CACHE_TTL=2

# Python venv dans le prompt (défaut: true)
export ENABLE_PYTHON_VENV=true

# Auto-activation de venv au cd (défaut: false)
export ENABLE_PYTHON_AUTO_ACTIVATE=false

# Cloud context dans le prompt (défaut: true)
export ENABLE_CLOUD_PROMPT=true

# Firebase dans le prompt (défaut: true)
export ENABLE_FIREBASE_PROMPT=true

# Désactiver la modification du prompt par environnements virtuels
export VIRTUAL_ENV_DISABLE_PROMPT=1
export CONDA_CHANGEPS1=false
```

---

## Exemples de Scénarios

### Développement Local
```bash
> ~/projects/myapp git:(main)●
> ~/projects/myapp git:(feature-auth)○
```

### Serveur SSH
```bash
[production] > ~/apps/backend git:(main)●
[staging] > ~/apps/backend git:(develop)○
```

### Root sur Serveur
```bash
[server] # > /etc/nginx git:(main)●
```

### Python Development avec venv
```bash
> ~/projects/myapp (venv) git:(main)●
> ~/projects/data-science (conda:ml) git:(develop)○
> ~/projects/web (poetry) git:(main)●
```

### Cloud Provider Context
```bash
> ~/projects/backend aws:production git:(main)●
> ~/projects/infra gcp:my-project git:(terraform)○
> ~/projects/webapp az:my-subscription git:(main)●
```

### Projet Firebase + Git
```bash
> ~/projects/webapp [my-app-prod] git:(main)●
> ~/projects/webapp [my-app-dev] git:(feature)○
```

### Avec Background Jobs
```bash
> ~/projects/myapp git:(main)●                                      [▶ vim]
> ~/projects/myapp git:(main)●                                   [▶ npm ⏸ git]
> ~/projects/myapp git:(main)●                                      [▶ 3 ⏸ 1]
```

### Erreur de Commande
```bash
> ~/projects/myapp git:(main)●
❯ invalid-command
zsh: command not found: invalid-command
> ~/projects/myapp git:(main)○
```

---

## Comportement Synchrone

Le prompt est **entièrement synchrone** pour garantir la fiabilité :

✅ **Avantages:**
- Information toujours à jour et précise
- Pas de "flash" ou de rafraîchissement visuel
- État git fiable à 100%
- Pas de race conditions

⚡ **Optimisations:**
- Cache git de 2 secondes
- Opérations git optimisées (--porcelain, --short)
- Firebase optionnel et configurable
- Pas d'appels externes inutiles

---

## Thème & Format Configurables

Le thème (couleurs) et le format du prompt (quels segments, dans quel
ordre) se configurent **sans toucher au code**, via des variables
d'environnement définies dans `~/.zshrc` ou `~/.zsh_local` (chargé avant les
modules `config/*.zsh`, donc avant que le thème et le prompt ne se
construisent).

### Changer de thème

```bash
# Thèmes livrés: nord (défaut), dracula
export NIVUUS_THEME="dracula"

# Ou un thème custom, dans un répertoire dédié
export NIVUUS_THEME_DIR="$HOME/.config/nivuus-shell/themes"
export NIVUUS_THEME="mon-theme"   # cherche $NIVUUS_THEME_DIR/mon-theme.zsh

# Ou un fichier de thème explicite (prioritaire sur NIVUUS_THEME)
export NIVUUS_THEME_FILE="$HOME/mon-theme.zsh"
```

Un thème inconnu déclenche un avertissement et un repli automatique sur
`nord`. Pour écrire un thème custom, copiez `themes/nord.zsh` ou
`themes/dracula.zsh` : chaque thème doit définir `THEME_COLORS` (assoc,
codes ANSI-256), `THEME_HEX` (assoc, codes hex), les variables sémantiques
`THEME_PATH`/`THEME_SUCCESS`/`THEME_ERROR`/`THEME_SSH`/`THEME_ROOT`/
`THEME_GIT_PREFIX`/`THEME_GIT_BRANCH`/`THEME_ACCENT`/`THEME_MUTED`/
`THEME_RESET`, `THEME_BAT_NAME`/`THEME_DELTA_SYNTAX` (thèmes bat/delta), et
`LS_COLORS`/`GREP_COLORS`.

### Changer le format du prompt

`NIVUUS_PROMPT_FORMAT` (prompt gauche) et `NIVUUS_RPROMPT_FORMAT` (prompt
droit) sont des templates : chaque `{token}` est remplacé par le rendu du
segment correspondant. Tokens disponibles :

| Token | Segment |
|-------|---------|
| `{ssh}` | Indicateur SSH `[hostname]` |
| `{root}` | Indicateur root `#` |
| `{status}` | `>` coloré selon le dernier exit code |
| `{path}` | Répertoire courant |
| `{venv}` | Environnement Python actif |
| `{cloud}` | Contexte cloud (AWS/GCP/Azure) |
| `{firebase}` | Projet Firebase actif |
| `{git}` | Branche + statut git |
| `{jobs}` | Jobs en arrière-plan (utilisé par défaut dans `NIVUUS_RPROMPT_FORMAT`) |

Défauts (reproduisent le format actuel) :
```bash
export NIVUUS_PROMPT_FORMAT='{ssh}{root}{status} {path}{venv}{cloud}{firebase}{git} '
export NIVUUS_RPROMPT_FORMAT='{jobs}'
```

Exemple minimal (juste le chemin et le git) :
```bash
export NIVUUS_PROMPT_FORMAT='{path}{git} '
```

Les tokens inconnus restent affichés tels quels (texte littéral), aucune
erreur n'est levée. L'évaluation des segments reste paresseuse (via
`PROMPT_SUBST`), donc pas de perte de performance par rapport au prompt
figé précédent.

### Fichier de Configuration
**Emplacement:** `config/05-prompt.zsh` (moteur de template + segments),
`themes/*.zsh` (couleurs)

### Recharger le Prompt
```bash
source ~/.zshrc
```

---

## Compatibilité

### Shells Supportés
- ✅ **ZSH** - Support complet
- ❌ **Bash** - Non supporté (utilise syntaxe ZSH spécifique)

### Environnements
- ✅ Local terminal
- ✅ SSH remote
- ✅ VS Code integrated terminal
- ✅ Web terminals (Codespaces, Gitpod)
- ✅ Tmux / Screen

### Outils Respectés
Le prompt désactive automatiquement la modification par :
- Python virtualenv (`VIRTUAL_ENV_DISABLE_PROMPT=1`)
- Conda (`CONDA_CHANGEPS1=false`)

---

## Dépannage

### Le prompt n'affiche pas git
**Vérifier:**
```bash
# Dans un dépôt git
git rev-parse --git-dir

# Vérifier le cache
echo $_GIT_PROMPT_CACHE_DIR
echo $_GIT_PROMPT_CACHE_TIME
```

### Le prompt est lent
**Solutions:**
```bash
# Augmenter le cache git
export GIT_PROMPT_CACHE_TTL=5

# Désactiver Firebase
export ENABLE_FIREBASE_PROMPT=false
```

### Les couleurs ne s'affichent pas
**Vérifier:**
```bash
# Support des couleurs
echo $TERM

# Forcer les couleurs
export TERM=xterm-256color
```

---

**Fichiers source:** `config/05-prompt.zsh`, `themes/*.zsh`
**Dernière mise à jour:** Août 2026
