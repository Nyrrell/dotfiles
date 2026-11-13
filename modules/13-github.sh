#!/usr/bin/env bash
# make github : réglages de gh (télémétrie coupée, pager, éditeur, alias) + connexion au compte.
# Idempotent : relançable sans risque, la connexion n'est demandée que si gh n'est pas connecté.
set -euo pipefail

if ! command -v gh &>/dev/null; then
    echo "[ERREUR] gh (github-cli) n'est pas installé. Lance d'abord : make packages"
    exit 1
fi

# GH_TELEMETRY=false est aussi posé dans environment.d (actif après reconnexion) ;
# la config couvre la session en cours et les contextes sans cet environnement.
gh config set telemetry disabled
gh config set git_protocol https    # cohérent avec les remotes HTTPS + git-credential-libsecret
gh config set pager delta           # comme core.pager dans .gitconfig
gh config set editor nano
gh alias set --clobber co 'pr checkout' >/dev/null
gh alias set --clobber prs 'pr list --author @me' >/dev/null
echo "Config gh appliquée (télémétrie désactivée, pager delta, éditeur nano, alias co/prs)."

if gh auth status --hostname github.com &>/dev/null; then
    echo "gh déjà connecté à GitHub."
else
    echo "Connexion de gh à GitHub (un code s'affiche, à valider dans le navigateur)..."
    # Token stocké dans le trousseau GNOME ; git garde son helper libsecret (pas de setup-git)
    gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
fi

echo ""
gh auth status --hostname github.com
