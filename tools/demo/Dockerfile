# Le conteneur de tournage de la démo. Reproductible, épinglé, sans clé.
#
# debian:12 plutôt qu'ubuntu : c'est la cible la plus neutre de la matrice, et
# celle dont le gestionnaire de paquets produit la suggestion la plus lisible
# à l'écran (« sudo apt-get install -y ncdu »).
FROM debian:12

# ncdu est VOLONTAIREMENT absent : c'est la commande introuvable du plan
# t=13-19s. Ne pas l'ajouter ici, même « pour confort » -- le test
# « toute commande unknown est réellement introuvable » ne le verrait pas,
# mais la démo, elle, cesserait de montrer quoi que ce soit.
#
# asciinema et expect servent au TOURNAGE (record.sh) ; le rejeu
# (replay-check.sh) n'en a pas besoin, mais une seule image vaut mieux que
# deux qui divergent.
RUN apt-get update && apt-get install -y --no-install-recommends \
        zsh curl ca-certificates jq git procps expect asciinema \
    && rm -rf /var/lib/apt/lists/*

# Nom d'hôte fixe : un prompt qui change à chaque tournage rend le .cast
# non diffable, donc non auditable en revue -- c'est-à-dire sans intérêt.
RUN echo demo > /etc/hostname

RUN useradd -m -s /bin/zsh demo && mkdir -p /home/demo/work \
    && chown -R demo:demo /home/demo

# Un vrai dépôt git : le plan t=25-28s montre la branche et l'état dans le
# prompt. Sans dépôt, le segment git ne s'affiche pas et le plan ne prouve
# rien. Nom d'utilisateur git fixe, pour la même raison que le nom d'hôte.
USER demo
# Un ~/.zshrc vide : c'est l'état d'un poste AVANT Nivuus. Sans lui, zsh lance
# zsh-newuser-install au premier démarrage et le tournage s'arrête sur un menu.
RUN : > /home/demo/.zshrc
RUN git config --global user.email demo@example.invalid \
    && git config --global user.name  demo \
    && git config --global init.defaultBranch main \
    && mkdir -p /home/demo/work/nivuus-shell \
    && cd /home/demo/work/nivuus-shell \
    && git init -q && echo hello > README.md && git add README.md \
    && git commit -q -m "initial" && echo "work in progress" >> README.md
USER root

# Le stub IA, sur le PATH, avec le mode d'authentification qui l'emprunte.
# C'est le chemin de PRODUCTION (config/09-ai-backend-gemini.zsh) : aucun
# crochet n'est ajouté au produit pour tourner la démo.
COPY stub/agy /usr/local/bin/agy
COPY bin/home-fingerprint /usr/local/bin/home-fingerprint
RUN chmod +x /usr/local/bin/agy /usr/local/bin/home-fingerprint
ENV GEMINI_AUTH_MODE=cli \
    AGY_DAEMON_ENABLED=false \
    NIVUUS_DEMO_ROOT=/opt/nivuus-src \
    ENABLE_AUTOUPDATE=false \
    TERM=xterm-256color

WORKDIR /home/demo
USER demo
