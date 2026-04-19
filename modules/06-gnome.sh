#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DCONF_BACKUP="$SCRIPT_DIR/gnome/dconf-backup.ini"

if ! command -v dconf &>/dev/null; then
    echo "[SKIP] dconf introuvable — pas un système GNOME ?"
    exit 0
fi
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    echo "[SKIP] XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-inconnu} — pas GNOME"
    exit 0
fi

# Restaure les settings GNOME
if [[ -f "$DCONF_BACKUP" ]]; then
    echo "Restauration des settings GNOME depuis le backup..."
    sed "s|/home/[^/]*/|$HOME/|g" "$DCONF_BACKUP" | dconf load /
    echo "Settings GNOME restaurés."
else
    echo "[WARN] $DCONF_BACKUP introuvable, rien restauré."
fi

# Installation des extensions listées dans dconf
if command -v gext &>/dev/null; then
    echo "Installation des extensions GNOME..."
    while IFS= read -r _ext; do
        [[ -z "$_ext" ]] && continue
        gext install "$_ext" 2>/dev/null || true
    done < <(dconf read /org/gnome/shell/enabled-extensions \
        | tr -d "[]'" | tr ',' '\n' | tr -d ' ')
fi