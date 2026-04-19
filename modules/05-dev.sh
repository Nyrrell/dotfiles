#!/usr/bin/env bash
set -euo pipefail

if ! command -v fnm &>/dev/null; then
    echo "[ERREUR] fnm n'est pas installé. Lance d'abord : make packages"
    exit 1
fi

eval "$(fnm env --shell bash)"

echo "Installation de Node.js LTS..."
fnm install --lts
fnm default "$(fnm current)"

echo "Node $(node -v) / npm $(npm -v) installés."

corepack enable
echo "Corepack activé."