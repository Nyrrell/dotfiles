#!/usr/bin/env bash
set -euo pipefail

KEY="$HOME/.ssh/id_ed25519"

mkdir -p "$HOME/.ssh"
if ! chmod 700 "$HOME/.ssh" 2>/dev/null; then
    echo "[WARN] Impossible de corriger les permissions de ~/.ssh"
    echo "       Lance : sudo chown -R $(whoami):$(whoami) ~/.ssh"
fi

if [[ -f "$KEY" ]]; then
    echo "Clé SSH existante détectée : $KEY"
else
    echo "Génération d'une nouvelle clé SSH ed25519..."
    echo "Une passphrase est recommandée — elle sera demandée une seule fois par session grâce à ssh-agent."
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$KEY"
    echo "Clé générée."
fi

chmod 600 "$KEY" "${KEY}.pub" 2>/dev/null || true
[[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config"

echo ""
echo "Clé publique :"
echo "─────────────────────────────────────────────────────"
cat "${KEY}.pub"
echo "─────────────────────────────────────────────────────"
echo ""
echo "Ajoute cette clé aux services nécessaires :"
echo "  GitHub   : https://github.com/settings/keys"
echo "  Serveur  : ssh-copy-id -i ${KEY}.pub $(whoami)@<host>"