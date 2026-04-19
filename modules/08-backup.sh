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

case "$MODE" in
    backup)
        echo "Backup → ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}"

        for dir in "${BACKUP_DIRS[@]}"; do
            backup_dir "$dir"
        done

        if [[ -n "${STEAM_LIBRARY_PATH:-}" && -d "${STEAM_LIBRARY_PATH}/steamapps" ]]; then
            echo "  → manifestes Steam (.acf)"
            # shellcheck disable=SC2029
            ssh "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${BACKUP_DEST}/steam-acf'"
            rsync "${RSYNC_OPTS[@]}" --include="*.acf" --exclude="*" \
                "${STEAM_LIBRARY_PATH}/steamapps/" \
                "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-acf/"
        fi

        if [[ -d "$HOME/.hyperhdr/db" ]]; then
            echo "  → HyperHDR config"
            # shellcheck disable=SC2029
            ssh "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${BACKUP_DEST}/.hyperhdr/db'"
            rsync "${RSYNC_OPTS[@]}" \
                "$HOME/.hyperhdr/db/" \
                "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/.hyperhdr/db/"
        fi

        echo "Backup terminé."
        ;;
    restore)
        echo "Restore ← ${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}"

        for dir in "${BACKUP_DIRS[@]}"; do
            restore_dir "$dir"
        done

        # shellcheck disable=SC2029
        if [[ -n "${STEAM_LIBRARY_PATH:-}" ]] && \
           ssh "${BACKUP_USER}@${BACKUP_HOST}" "test -d '${BACKUP_DEST}/steam-acf'" 2>/dev/null; then
            echo "  ← manifestes Steam (.acf)"
            mkdir -p "${STEAM_LIBRARY_PATH}/steamapps"
            rsync "${RSYNC_OPTS[@]}" \
                "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-acf/" \
                "${STEAM_LIBRARY_PATH}/steamapps/"
        fi

        # shellcheck disable=SC2029
        if ssh "${BACKUP_USER}@${BACKUP_HOST}" "test -d '${BACKUP_DEST}/.hyperhdr/db'" 2>/dev/null; then
            echo "  ← HyperHDR config"
            mkdir -p "$HOME/.hyperhdr/db"
            rsync "${RSYNC_OPTS[@]}" \
                "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/.hyperhdr/db/" \
                "$HOME/.hyperhdr/db/"
        fi

        echo "Restore terminé."
        ;;
    *)
        echo "Usage: $0 [backup|restore]"
        exit 1
        ;;
esac