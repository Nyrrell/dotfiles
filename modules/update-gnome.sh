#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v dconf &>/dev/null; then
    echo "[SKIP] dconf introuvable — pas un système GNOME ?"
    exit 0
fi
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    echo "[SKIP] XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-inconnu} — pas GNOME"
    exit 0
fi

# Extensions dont la config est machine-specific
EXTENSIONS_EXCLUDE=(
    "executor"   # commandes shell + chemins locaux
)
exclude_pattern=$(IFS='|'; echo "${EXTENSIONS_EXCLUDE[*]}")

dconf dump / | awk -v excl="$exclude_pattern" '
BEGIN { keep=0; in_shell_root=0 }
/^\[/ {
    s = substr($0, 2, length($0)-2)
    in_shell_root = (s == "org/gnome/shell")
    keep = (in_shell_root ||
            index(s, "org/gnome/shell/extensions") == 1 ||
            index(s, "org/gnome/shell/keybindings") == 1 ||
            index(s, "org/gnome/desktop/interface") == 1 ||
            index(s, "org/gnome/desktop/wm/preferences") == 1 ||
            index(s, "org/gnome/desktop/input-sources") == 1 ||
            index(s, "org/gnome/desktop/session") == 1 ||
            index(s, "org/gnome/tweaks") == 1 ||
            index(s, "org/gnome/settings-daemon/plugins/color") == 1 ||
            index(s, "org/gnome/nautilus/icon-view") == 1 ||
            index(s, "org/gnome/nautilus/list-view") == 1)
    # Exclure les extensions machine-specific
    if (keep && excl != "" && s ~ ("^org/gnome/shell/extensions/(" excl ")")) keep=0
}
keep {
    # Clés machine-specific dans [org/gnome/shell]
    if (in_shell_root && /^(app-picker-layout|command-history|last-selected-power-profile|welcome-dialog-last-shown-version)=/) next
    # Historique BT avec MAC addresses
    if (/^device-list=/) next
    print
}
' | sed "s|/home/$(whoami)/|/home/USER/|g" \
  > "$SCRIPT_DIR/gnome/dconf-backup.ini"

echo "dconf-backup.ini mis à jour ($(wc -l < "$SCRIPT_DIR/gnome/dconf-backup.ini") lignes)."