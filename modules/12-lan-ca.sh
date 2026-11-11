#!/usr/bin/env bash
# Certificat LAN du serveur (racine des vhosts internes *.int) — facultatif : skip si
# LAN_CA_URL est vide. Ancre p11-kit système : sur Arch, curl, Chrome ET Firefox (NSS
# système, libnssckbi = p11-kit-trust) la lisent. À lancer depuis le LAN ou le VPN :
# l'URL n'est servie qu'aux IP privées.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
load_conf

if [[ -z "${LAN_CA_URL:-}" ]]; then
    echo "==> Certificat LAN: skip (LAN_CA_URL vide)"
    exit 0
fi

echo "==> Certificat LAN"
ANCHOR=/etc/ca-certificates/trust-source/anchors/nrl-srv-lan-ca.crt
# Ancien CA « Caddy Local Authority » importé à la main (non contraint : sa clé
# pouvait signer n'importe quel site). Remplacé par celui-ci.
OLD_ANCHOR=/etc/ca-certificates/trust-source/anchors/caddy-internal.crt

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Téléchargé en HTTPS vérifié : l'URL est sur un nom en Let's Encrypt.
if ! curl -fsS --max-time 15 -o "$TMP" "$LAN_CA_URL"; then
    echo "[ERREUR] téléchargement impossible : $LAN_CA_URL (hors LAN/VPN ?)" >&2
    exit 1
fi
# Une page vide ou HTML (serveur pas encore à jour) n'est pas un certificat.
if ! openssl x509 -in "$TMP" -noout 2>/dev/null \
    || ! openssl x509 -in "$TMP" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE'; then
    echo "[ERREUR] $LAN_CA_URL ne renvoie pas un certificat d'autorité" >&2
    exit 1
fi
echo "  $(openssl x509 -in "$TMP" -noout -subject), expire $(openssl x509 -in "$TMP" -noout -enddate | cut -d= -f2)"
echo "  $(openssl x509 -in "$TMP" -noout -fingerprint -sha256)"

changed=0
if cmp -s "$TMP" "$ANCHOR" 2>/dev/null; then
    echo "  Déjà installé."
else
    sudo install -m 644 "$TMP" "$ANCHOR"
    echo "  Installé : $ANCHOR"
    changed=1
fi
if [[ -f "$OLD_ANCHOR" ]]; then
    sudo rm -f "$OLD_ANCHOR"
    echo "  Ancien CA Caddy retiré : $OLD_ANCHOR"
    changed=1
fi
[[ "$changed" == 1 ]] && sudo update-ca-trust

# Vérification sur un vhost interne toujours présent (lldap), sans -k.
_host=${LAN_CA_URL#https://}
_host=${_host%%/*}
if curl -fsS --max-time 10 -o /dev/null "https://lldap.int.$_host/"; then
    echo "  Vérifié : https://lldap.int.$_host accepté sans -k."
else
    echo "  [WARN] https://lldap.int.$_host refusé : serveur pas encore à jour, ou hors LAN/VPN."
fi
echo "  Navigateurs déjà ouverts : les redémarrer pour qu'ils relisent le magasin."
