#!/usr/bin/env bash
# VPN WireGuard (connexion NetworkManager) — facultatif : skip si WG_ENDPOINT est vide.
# Activation manuelle uniquement (autoconnect désactivé) : nmcli connection up "$WG_CONN_NAME".
# La clé privée ne passe jamais par le dépôt : elle est générée sur la machine
# (ou lue depuis WG_PRIVATE_KEY_FILE) puis stockée par NetworkManager.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
load_conf

if [[ -z "${WG_ENDPOINT:-}" ]]; then
    echo "==> WireGuard: skip (WG_ENDPOINT vide)"
    exit 0
fi

echo "==> WireGuard"
WG_CONN_NAME="${WG_CONN_NAME:-Maison}"
WG_IFACE="${WG_IFACE:-wg0}"
WG_KEEPALIVE="${WG_KEEPALIVE:-25}"

for _var in WG_ADDRESS WG_PEER_PUBKEY WG_ALLOWED_IPS; do
    if [[ -z "${!_var:-}" ]]; then
        echo "[ERREUR] $_var vide dans local.conf" >&2
        exit 1
    fi
done

PEER="$WG_PEER_PUBKEY allowed-ips=$WG_ALLOWED_IPS endpoint=$WG_ENDPOINT persistent-keepalive=$WG_KEEPALIVE"

# Paramètres non secrets, réappliqués à chaque run (idempotent)
apply_settings() {
    nmcli connection modify "$WG_CONN_NAME" \
        connection.interface-name "$WG_IFACE" \
        connection.autoconnect no \
        ipv4.method manual \
        ipv4.addresses "$WG_ADDRESS" \
        ipv4.dns "${WG_DNS:-}" \
        ipv4.dns-search "${WG_DNS_SEARCH:-}" \
        ipv6.method disabled \
        wireguard.peer-routes yes \
        wireguard.peers "$PEER"
}

if nmcli -t -f NAME connection show | grep -qxF "$WG_CONN_NAME"; then
    echo "  Connexion '$WG_CONN_NAME' déjà présente : mise à jour des paramètres (clé conservée)."
    apply_settings
    echo "  Prise en compte à la prochaine activation."
    exit 0
fi

# --- Clé privée ---
TMP_DIR=$(mktemp -d)
chmod 700 "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
KEY_FILE="$TMP_DIR/key"

if [[ -n "${WG_PRIVATE_KEY_FILE:-}" ]]; then
    _src=$(eval echo "$WG_PRIVATE_KEY_FILE")
    if [[ ! -r "$_src" ]]; then
        echo "[ERREUR] WG_PRIVATE_KEY_FILE illisible : $_src" >&2
        exit 1
    fi
    (umask 077; cp "$_src" "$KEY_FILE")
    echo "  Clé privée lue depuis $_src"
    NEW_KEY=0
else
    if ! command -v wg >/dev/null 2>&1; then
        echo "[ERREUR] wg introuvable — make add PKG=wireguard-tools" >&2
        exit 1
    fi
    (umask 077; wg genkey > "$KEY_FILE")
    echo "  Nouvelle clé privée générée pour cette machine."
    NEW_KEY=1
fi

# Import via un fichier wg-quick temporaire (0600) : la clé n'apparaît jamais
# en argument de commande. Le nom du fichier donne le nom de l'interface.
CONF="$TMP_DIR/$WG_IFACE.conf"
(
    umask 077
    {
        echo "[Interface]"
        echo "PrivateKey = $(cat "$KEY_FILE")"
        echo "Address = $WG_ADDRESS"
        echo ""
        echo "[Peer]"
        echo "PublicKey = $WG_PEER_PUBKEY"
        echo "AllowedIPs = ${WG_ALLOWED_IPS//;/, }"
        echo "Endpoint = $WG_ENDPOINT"
        echo "PersistentKeepalive = $WG_KEEPALIVE"
    } > "$CONF"
)

_uuid=$(nmcli -t connection import type wireguard file "$CONF" | grep -oE '[0-9a-f-]{36}' | head -n1)
# L'import active la connexion : on la coupe et on désactive l'autoconnect tout de suite
nmcli connection modify "$_uuid" connection.id "$WG_CONN_NAME" connection.autoconnect no
nmcli connection down "$_uuid" >/dev/null 2>&1 || true
apply_settings
echo "  Connexion '$WG_CONN_NAME' créée (activation manuelle : nmcli connection up \"$WG_CONN_NAME\")."

if [[ "$NEW_KEY" == 1 ]]; then
    echo ""
    echo "  Clé publique de cette machine, à ajouter comme peer sur le serveur"
    echo "  (AllowedIPs = $WG_ADDRESS) :"
    echo "    $(wg pubkey < "$KEY_FILE")"
fi
