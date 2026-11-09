#!/usr/bin/env bash
# make gnome : applique gnome/settings.ini puis installe/active gnome/extensions.txt.
# Rien n'est exporté depuis la machine : les deux fichiers sont écrits à la main
# (make gnome-diff pour voir les écarts). Ce qui n'y figure pas n'est jamais touché.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/gnome/settings.ini"
EXTENSIONS="$SCRIPT_DIR/gnome/extensions.txt"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
# local.conf facultatif ici : seulement pour GNOME_EXTRA_EXTENSIONS
GNOME_EXTRA_EXTENSIONS=()
# shellcheck source=/dev/null
[[ -f "$LOCAL_CONF" ]] && source "$LOCAL_CONF"

if ! command -v dconf &>/dev/null; then
    echo "[SKIP] dconf introuvable — pas un système GNOME ?"
    exit 0
fi
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    echo "[SKIP] XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-inconnu} — pas GNOME"
    exit 0
fi

echo "==> Réglages GNOME (gnome/settings.ini)"
dconf load / < "$SETTINGS"
echo "  Réglages appliqués."

echo "==> Extensions GNOME (gnome/extensions.txt + GNOME_EXTRA_EXTENSIONS)"
if ! command -v gext &>/dev/null; then
    echo "  [WARN] gext introuvable (gnome-extensions-cli) — extensions non installées"
    exit 0
fi
failed=0
while IFS= read -r _ext; do
    if ! gnome-extensions info "$_ext" &>/dev/null; then
        echo "  + installation de $_ext"
        gext install "$_ext" >/dev/null 2>&1 || { echo "  [WARN] installation impossible : $_ext"; failed=1; continue; }
    fi
    gext enable "$_ext" >/dev/null 2>&1 || gnome-extensions enable "$_ext" 2>/dev/null \
        || { echo "  [WARN] activation impossible : $_ext"; failed=1; continue; }
    echo "  ✓ $_ext"
done < <(
    {
        sed -e 's/#.*//' -e 's/[[:space:]]//g' "$EXTENSIONS"
        printf '%s\n' "${GNOME_EXTRA_EXTENSIONS[@]}"
    } | grep -v '^$' | awk '!seen[$0]++'
)

if [[ "$failed" == 1 ]]; then
    echo "  Une nouvelle extension n'apparaît parfois qu'après une reconnexion de session."
fi
