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
    echo "         Hors de chez toi : nmcli connection up \"${WG_CONN_NAME:-Maison}\" puis relance."
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

backup_steam_launchopts() {
    local count=0
    shopt -s nullglob
    for vdf in "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf; do
        local userid
        userid=$(basename "$(dirname "$(dirname "$vdf")")")
        echo "  → options de lancement Steam (user $userid)"
        # shellcheck disable=SC2029
        ssh "${BACKUP_USER}@${BACKUP_HOST}" \
            "mkdir -p '${BACKUP_DEST}/steam-launchopts/${userid}/config'"
        rsync "${RSYNC_OPTS[@]}" "$vdf" \
            "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-launchopts/${userid}/config/"
        count=$((count + 1))
    done
    shopt -u nullglob
    if [[ $count -eq 0 ]]; then
        echo "  [SKIP] aucun localconfig.vdf trouvé"
    fi
}

restore_steam_launchopts() {
    # shellcheck disable=SC2029
    if ! ssh "${BACKUP_USER}@${BACKUP_HOST}" \
            "test -d '${BACKUP_DEST}/steam-launchopts'" 2>/dev/null; then
        echo "  [SKIP] options de lancement Steam absent du NAS"
        return
    fi
    if pgrep -x steam >/dev/null 2>&1; then
        echo "  [WARN] Steam tourne — ferme-le complètement (icône systray > Quitter) avant de relancer le restore,"
        echo "         sinon le fichier restauré sera écrasé au prochain démarrage de Steam."
    fi
    local userids
    # shellcheck disable=SC2029
    userids=$(ssh "${BACKUP_USER}@${BACKUP_HOST}" \
        "ls -1 '${BACKUP_DEST}/steam-launchopts' 2>/dev/null") || return
    while IFS= read -r userid; do
        [[ -z "$userid" ]] && continue
        local dest="$HOME/.local/share/Steam/userdata/$userid/config"
        echo "  ← options de lancement Steam (user $userid)"
        mkdir -p "$dest"
        rsync "${RSYNC_OPTS[@]}" \
            "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_DEST}/steam-launchopts/${userid}/config/localconfig.vdf" \
            "$dest/"
    done <<< "$userids"
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
shopt -s nullglob
_steam_vdf_count=( "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf )
shopt -u nullglob
if [[ ${#_steam_vdf_count[@]} -gt 0 ]]; then
    ALL_ITEMS+=("steam-launchopts")
    ALL_LABELS+=("options de lancement Steam (localconfig.vdf)")
fi

# Menu de sélection — sans terminal (timer systemd), on prend tout
if [[ -t 0 ]]; then
    echo ""
    echo "  0) Tout"
    for i in "${!ALL_LABELS[@]}"; do
        echo "  $((i+1))) ${ALL_LABELS[$i]}"
    done
    echo ""
    read -rp "Choix [0-${#ALL_LABELS[@]}] : " choice
else
    choice=0
    echo "Mode non interactif : tous les éléments sont traités."
fi

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
            elif [[ "$item" == "steam-launchopts" ]]; then
                backup_steam_launchopts
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
            elif [[ "$item" == "steam-launchopts" ]]; then
                restore_steam_launchopts
            fi
        done
        echo "Restore terminé."
        ;;
    *)
        echo "Usage: $0 [backup|restore]"
        exit 1
        ;;
esac