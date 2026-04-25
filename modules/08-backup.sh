#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$SCRIPT_DIR/local.conf" ]]; then
    echo "[ERREUR] local.conf absent — copie local.conf.example et adapte les valeurs"
    exit 1
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

BACKUP_HOST=$(eval echo "$BACKUP_HOST")
BACKUP_USER=$(eval echo "$BACKUP_USER")
BACKUP_DEST=$(eval echo "$BACKUP_DEST")

MODE="${1:-backup}"

if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${BACKUP_USER}@${BACKUP_HOST}" true 2>/dev/null; then
    echo "[ERREUR] Impossible de joindre ${BACKUP_USER}@${BACKUP_HOST} — NAS inaccessible ou clé SSH manquante."
    exit 1
fi

RSYNC_OPTS=(
    --archive
    --compress
    --partial
    --human-readable
    --info=progress2
    --exclude="*.cache"
    --exclude="__pycache__"
    --exclude="shader_cache"
    --exclude="shadercache"
)

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY_RUN] aucune donnée ne sera transférée"
    RSYNC_OPTS+=(--dry-run)
fi

backup_dir() {
    local src="$1"
    local rel="${src#/}"
    rel="${rel#home/*/}"
    [[ "$src" == "$HOME"* ]] && rel="${src#"$HOME"/}"
    if [[ ! -d "$src" ]]; then
        echo "  [SKIP] $src (introuvable)"
        return
    fi
    echo "  → $rel"
    # shellcheck disable=SC2029
    ssh "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${BACKUP_DEST}/${rel}'"
    rsync "${RSYNC_OPTS[@]}" "$src/" "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/${rel}/"
}

restore_dir() {
    local dest="$1"
    local rel="${dest#/}"
    rel="${rel#home/*/}"
    [[ "$dest" == "$HOME"* ]] && rel="${dest#"$HOME"/}"
    echo "  ← $rel"
    mkdir -p "$dest"
    rsync "${RSYNC_OPTS[@]}" "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/${rel}/" "$dest/" || \
        echo "  [SKIP] $rel (absent du NAS)"
}

backup_localconf() {
    echo "  → local.conf"
    # shellcheck disable=SC2029
    ssh "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${BACKUP_DEST}/dotfiles'"
    rsync "${RSYNC_OPTS[@]}" "$SCRIPT_DIR/local.conf" \
        "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/dotfiles/local.conf"
}

restore_localconf() {
    # shellcheck disable=SC2029
    if ssh "${BACKUP_USER}@${BACKUP_HOST}" "test -f '${BACKUP_DEST}/dotfiles/local.conf'" 2>/dev/null; then
        echo "  ← local.conf"
        rsync "${RSYNC_OPTS[@]}" \
            "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/dotfiles/local.conf" \
            "$SCRIPT_DIR/local.conf"
    else
        echo "  [SKIP] local.conf (absent du NAS)"
    fi
}

backup_steam() {
    if [[ -n "${STEAM_LIBRARY_PATH:-}" && -d "${STEAM_LIBRARY_PATH}/steamapps" ]]; then
        echo "  → manifestes Steam (.acf)"
        # shellcheck disable=SC2029
        ssh "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${BACKUP_DEST}/steam-acf'"
        rsync "${RSYNC_OPTS[@]}" --include="*.acf" --exclude="*" \
            "${STEAM_LIBRARY_PATH}/steamapps/" \
            "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-acf/"
    fi
}

restore_steam() {
    # shellcheck disable=SC2029
    if [[ -n "${STEAM_LIBRARY_PATH:-}" ]] && \
       ssh "${BACKUP_USER}@${BACKUP_HOST}" "test -d '${BACKUP_DEST}/steam-acf'" 2>/dev/null; then
        echo "  ← manifestes Steam (.acf)"
        mkdir -p "${STEAM_LIBRARY_PATH}/steamapps"
        rsync "${RSYNC_OPTS[@]}" \
            "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-acf/" \
            "${STEAM_LIBRARY_PATH}/steamapps/"
    fi
}

# Construire la liste des items
declare -a ALL_ITEMS=()
declare -a ALL_LABELS=()
for dir in "${BACKUP_DIRS[@]}"; do
    ALL_ITEMS+=("dir:$dir")
    ALL_LABELS+=("${dir#"$HOME"/}")
done
ALL_ITEMS+=("localconf")
ALL_LABELS+=("local.conf")
if [[ -n "${STEAM_LIBRARY_PATH:-}" ]]; then
    ALL_ITEMS+=("steam")
    ALL_LABELS+=("manifestes Steam (.acf)")
fi

# Menu de sélection
echo ""
echo "  0) Tout"
for i in "${!ALL_LABELS[@]}"; do
    echo "  $((i+1))) ${ALL_LABELS[$i]}"
done
echo ""
read -rp "Choix [0-${#ALL_LABELS[@]}] : " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice > ${#ALL_ITEMS[@]} )); then
    echo "[ERREUR] Choix invalide"
    exit 1
fi

declare -a SELECTED_ITEMS=()
if [[ "$choice" == "0" ]]; then
    SELECTED_ITEMS=("${ALL_ITEMS[@]}")
else
    SELECTED_ITEMS=("${ALL_ITEMS[$((choice-1))]}")
fi

case "$MODE" in
    backup)
        echo "Backup → ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}"
        for item in "${SELECTED_ITEMS[@]}"; do
            if [[ "$item" == dir:* ]]; then
                backup_dir "${item#dir:}"
            elif [[ "$item" == "localconf" ]]; then
                backup_localconf
            elif [[ "$item" == "steam" ]]; then
                backup_steam
            fi
        done
        echo "Backup terminé."
        ;;
    restore)
        echo "Restore ← ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}"
        for item in "${SELECTED_ITEMS[@]}"; do
            if [[ "$item" == dir:* ]]; then
                restore_dir "${item#dir:}"
            elif [[ "$item" == "localconf" ]]; then
                restore_localconf
            elif [[ "$item" == "steam" ]]; then
                restore_steam
            fi
        done
        echo "Restore terminé."
        ;;
    *)
        echo "Usage: $0 [backup|restore]"
        exit 1
        ;;
esac