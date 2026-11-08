#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
load_conf

if [[ -z "${GOA_USERNAME:-}" ]] || [[ -z "${GOA_URL:-}" ]]; then
    echo "==> GOA Cal+Card: skip (GOA_USERNAME ou GOA_URL vide)"
    exit 0
fi

echo "==> GOA Cal+Card"
GOA_CONF="$HOME/.config/goa-1.0/accounts.conf"
if [[ -f "$GOA_CONF" ]] && grep -q "Identity=$GOA_USERNAME" "$GOA_CONF"; then
    echo "  Compte déjà présent."
    exit 0
fi

cat <<EOF
  Saisie manuelle requise (provider WebDAV) :
    URL               : $GOA_URL
    Nom d'utilisateur : $GOA_USERNAME
    Mot de passe      : mot de passe d'application (cf. fournisseur)
  Astuce : décocher 'Fichiers' pour éviter le mount Nautilus inutile.
EOF
read -rp "  Ouvrir Paramètres > Comptes en ligne ? [y/N] " _open
[[ "${_open,,}" == "y" ]] && (gnome-control-center online-accounts &) || true
