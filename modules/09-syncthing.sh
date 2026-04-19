#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v syncthing &>/dev/null; then
    echo "[ERREUR] syncthing n'est pas installé. Lance d'abord : make packages"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/local.conf" ]]; then
    echo "[ERREUR] local.conf absent — copie local.conf.example et adapte les valeurs"
    exit 1
fi
declare -a SYNC_INTRODUCERS=()
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

# 1. Démarrer le service (idempotent)
mkdir -p "$HOME/.config/systemd/user/default.target.wants"
systemctl --user enable --now syncthing.service || true

# 2. Attendre que le daemon ait généré sa config et que l'API réponde (max 60s)
_syncthing_ready=0
printf "En attente de l'API Syncthing"
for _ in {1..60}; do
    if syncthing cli show system &>/dev/null; then
        _syncthing_ready=1
        break
    fi
    printf "."
    sleep 1
done
echo ""

if [[ "$_syncthing_ready" -eq 0 ]]; then
    echo "[WARN] L'API Syncthing ne répond pas après 60s."
    echo "       Lance 'make syncthing' manuellement une fois en session graphique."
    exit 0
fi

# 3. Afficher le device ID local
MY_ID=$(syncthing cli show system | grep -oP '"myID":\s*"\K[^"]+')
echo "Device ID local : $MY_ID"

# 4. Ajouter chaque introducer déclaré dans local.conf
EXISTING_DEVICES=$(syncthing cli config devices list)
for entry in "${SYNC_INTRODUCERS[@]}"; do
    IFS='|' read -r name id <<<"$entry"
    if grep -qFx "$id" <<<"$EXISTING_DEVICES"; then
        echo "  device $name déjà présent"
    else
        echo "  ajout device $name"
        syncthing cli config devices add \
            --device-id "$id" \
            --name "$name" \
            --introducer \
            --auto-accept-folders
    fi
done

# 5. Créer les dossiers locaux + déclarer les folders + les partager avec chaque introducer
EXISTING_FOLDERS=$(syncthing cli config folders list)
for entry in "${SYNC_FOLDERS[@]}"; do
    IFS='|' read -r fid label path ftype rescan <<<"$entry"
    rescan="${rescan:-3600}"
    path=$(eval echo "$path")
    mkdir -p "$path"

    if grep -qFx "$fid" <<<"$EXISTING_FOLDERS"; then
        echo "  folder $fid déjà présent"
        continue
    fi

    echo "  ajout folder $fid ($path)"
    syncthing cli config folders add \
        --id "$fid" \
        --label "$label" \
        --path "$path" \
        --type "$ftype" \
        --rescan-intervals "$rescan"

    for entry2 in "${SYNC_INTRODUCERS[@]}"; do
        IFS='|' read -r _ peer_id <<<"$entry2"
        syncthing cli config folders "$fid" devices add --device-id "$peer_id"
    done
done

echo ""
echo "Syncthing configuré."
if [[ ${#SYNC_INTRODUCERS[@]} -eq 0 ]]; then
    echo "  (Aucun introducer déclaré dans local.conf)"
else
    echo "  Sur le peer distant : autoriser le device ID ci-dessus une fois pour activer la connexion."
fi