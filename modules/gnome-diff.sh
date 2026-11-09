#!/usr/bin/env bash
# make gnome-diff : compare la machine courante à gnome/settings.ini, sans rien modifier.
#   ≠  clé de settings.ini dont la valeur diffère sur cette machine
#   +  clé réglée sur cette machine, dans une section suivie, absente de settings.ini
#      (sections suivies : celles de settings.ini + celle de chaque extension de extensions.txt)
# Pour adopter un réglage : copier la ligne affichée dans settings.ini.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/gnome/settings.ini"
EXTENSIONS="$SCRIPT_DIR/gnome/extensions.txt"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
GNOME_EXTRA_EXTENSIONS=()
# shellcheck source=/dev/null
[[ -f "$LOCAL_CONF" ]] && source "$LOCAL_CONF"

if ! command -v dconf &>/dev/null; then
    echo "[SKIP] dconf introuvable — pas un système GNOME ?"
    exit 0
fi

# Clés volontairement propres à chaque machine, ou simple état interne : jamais signalées.
# Format : "section/clé"
IGNORE=(
    "org/gnome/desktop/interface/show-battery-percentage"    # laptop ≠ fixe
    "org/gnome/desktop/interface/text-scaling-factor"        # dépend de l'écran
    "org/gnome/desktop/input-sources/mru-sources"            # historique
    "org/gnome/nautilus/list-view/default-column-order"      # ordre interne
    "org/gnome/shell/extensions/Bluetooth-Battery-Meter/device-list"  # appareils + adresses MAC
    "org/gnome/shell/extensions/caffeine/user-enabled"       # état on/off courant
    "org/gnome/shell/extensions/caffeine/indicator-position-max"
    "org/gnome/shell/extensions/caffeine/cli-toggle"
    "org/gnome/shell/extensions/quick-settings-audio-panel/profiles-renames"  # cartes son de la machine
    "org/gnome/shell/extensions/quick-settings-audio-panel/version"           # migration interne
)
ignore=$(IFS='|'; echo "${IGNORE[*]}")

# Sections suivies
mapfile -t sections < <(
    {
        grep -oE '^\[[^]]+\]' "$SETTINGS" | tr -d '[]'
        # Section dconf d'une extension : org/gnome/shell/extensions/<uuid avant @>
        {
            sed -e 's/#.*//' -e 's/[[:space:]]//g' "$EXTENSIONS"
            printf '%s\n' "${GNOME_EXTRA_EXTENSIONS[@]}"
        } | grep -v '^$' | sed -E 's|@.*||; s|^|org/gnome/shell/extensions/|'
    } | awk '!seen[$0]++'
)

# Valeurs de la machine, au format "section<TAB>clé<TAB>valeur"
machine=$(
    for _s in "${sections[@]}"; do
        dconf dump "/$_s/" | awk -v s="$_s" '
            /^\[/ { sub_ = substr($0, 2, length($0) - 2); next }
            # Sous-sections ([/] = la section elle-même) : ignorées
            sub_ != "/" { next }
            /=/ { i = index($0, "="); printf "%s\t%s\t%s\n", s, substr($0, 1, i - 1), substr($0, i + 1) }'
    done
)

# Valeurs de settings.ini, même format
file=$(awk '
    /^[[:space:]]*(#|$)/ { next }
    /^\[/ { s = substr($0, 2, length($0) - 2); next }
    /=/ { i = index($0, "="); printf "%s\t%s\t%s\n", s, substr($0, 1, i - 1), substr($0, i + 1) }
' "$SETTINGS")

awk -F'\t' -v ignore="$ignore" '
    BEGIN { n = split(ignore, _i, "|"); for (i = 1; i <= n; i++) skip[_i[i]] = 1 }
    NR == FNR { want[$1 FS $2] = $3; next }
    {
        if (($1 "/" $2) in skip) next
        if (!($1 in seen)) { seen[$1] = 1; order[++ns] = $1 }
        k = $1 FS $2
        if (k in want) {
            if (want[k] != $3) diff[$1] = diff[$1] sprintf("  ≠ %s=%s\n      (settings.ini : %s)\n", $2, $3, want[k])
        } else {
            diff[$1] = diff[$1] sprintf("  + %s=%s\n", $2, $3)
        }
    }
    END {
        n = 0
        for (i = 1; i <= ns; i++) if (diff[order[i]] != "") { printf "[%s]\n%s\n", order[i], diff[order[i]]; n++ }
        if (n == 0) print "Aucun écart : la machine correspond à gnome/settings.ini."
    }
' <(printf '%s\n' "$file") <(printf '%s\n' "$machine")
