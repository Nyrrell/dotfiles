#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Élévation des droits nécessaire pour la configuration système..."
    exec sudo bash "${BASH_SOURCE[0]}" "$@"
fi

USER_NAME="${SUDO_USER:-$(whoami)}"

if [[ ! -f "$SCRIPT_DIR/local.conf" ]]; then
    echo "[ERREUR] local.conf absent — copie local.conf.example et adapte les valeurs"
    exit 1
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

# --- Wake-on-LAN ---
echo "==> Wake-on-LAN"
read -rp "  Activer Wake-on-LAN ? (filaire uniquement) [y/N] " _wol_answer
if [[ "${_wol_answer,,}" == "y" ]]; then
    cp "$SCRIPT_DIR/systemd/system/wake-on-lan.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now wake-on-lan.service || true
else
    echo "  [SKIP] Wake-on-LAN ignoré"
fi

# --- Mount NAS (system automount) ---
echo "==> NAS automount"
NAS_HOST=$(eval echo "$BACKUP_HOST")
NAS_USER_VAL="$USER_NAME"
USER_HOME=$(eval echo "~$USER_NAME")
USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")
NAS_MOUNT_PATH="$USER_HOME/nas"
NAS_UNIT=$(systemd-escape --path "$NAS_MOUNT_PATH")
SSH_KEY="$USER_HOME/.ssh/id_ed25519"

if [[ "$NAS_HOST" == "CHANGEME" ]]; then
    echo "  [SKIP] BACKUP_HOST non configuré — définis-le dans local.conf"
else
    # Activer allow_other dans fuse pour les mounts système
    if [[ -f /etc/fuse.conf ]] && ! grep -q "^user_allow_other" /etc/fuse.conf; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    if systemctl is-active --quiet "${NAS_UNIT}.automount" 2>/dev/null; then
        systemctl stop "${NAS_UNIT}.automount" || true
        systemctl disable "${NAS_UNIT}.automount" || true
    fi
    if systemctl is-active --quiet "${NAS_UNIT}.mount" 2>/dev/null; then
        systemctl stop "${NAS_UNIT}.mount" || true
    fi

    mkdir -p "$NAS_MOUNT_PATH"
    chown "$USER_NAME:$USER_NAME" "$NAS_MOUNT_PATH"

    for ext in mount automount; do
        sed \
            -e "s|@MOUNT_PATH@|$NAS_MOUNT_PATH|g" \
            -e "s|@NAS_HOST@|$NAS_HOST|g" \
            -e "s|@NAS_USER@|$NAS_USER_VAL|g" \
            -e "s|@NAS_REMOTE_PATH@|${NAS_REMOTE_PATH:-/}|g" \
            -e "s|@USER_UID@|$USER_UID|g" \
            -e "s|@USER_GID@|$USER_GID|g" \
            -e "s|@SSH_KEY@|$SSH_KEY|g" \
            "$SCRIPT_DIR/systemd/system/nas.${ext}.tpl" \
            > "/etc/systemd/system/${NAS_UNIT}.${ext}"
    done
    systemctl daemon-reload
    systemctl enable --now "${NAS_UNIT}.automount"
    echo "  Automount NAS activé sur $NAS_MOUNT_PATH"
fi

# --- NAS WAN fallback (optionnel) ---
SSH_FALLBACK_FILE=/etc/ssh/ssh_config.d/40-nas-fallback.conf
if [[ -n "${NAS_WAN_HOST:-}" ]] && [[ "$NAS_HOST" != "CHANGEME" ]]; then
    echo "==> NAS fallback WAN"
    NAS_WAN_HOST_VAL=$(eval echo "$NAS_WAN_HOST")
    NAS_WAN_PORT_VAL="${NAS_WAN_PORT:-22}"

    if [[ -f /etc/ssh/ssh_config ]] && ! grep -qE '^\s*Include\s+/etc/ssh/ssh_config\.d/' /etc/ssh/ssh_config; then
        echo "Include /etc/ssh/ssh_config.d/*.conf" >> /etc/ssh/ssh_config
    fi

    mkdir -p /etc/ssh/ssh_config.d
    sed \
        -e "s|@NAS_HOST@|$NAS_HOST|g" \
        -e "s|@NAS_WAN_HOST@|$NAS_WAN_HOST_VAL|g" \
        -e "s|@NAS_WAN_PORT@|$NAS_WAN_PORT_VAL|g" \
        "$SCRIPT_DIR/ssh/nas-fallback.conf.tpl" \
        > "$SSH_FALLBACK_FILE"
    chmod 644 "$SSH_FALLBACK_FILE"
    echo "  Fallback: $NAS_HOST → $NAS_WAN_HOST_VAL:$NAS_WAN_PORT_VAL (si LAN injoignable)"
elif [[ -f "$SSH_FALLBACK_FILE" ]]; then
    rm -f "$SSH_FALLBACK_FILE"
    echo "==> NAS fallback WAN désactivé (NAS_WAN_HOST vide) — fichier nettoyé"
fi

# --- Pare-feu (ufw) ---
echo "==> Pare-feu"
LAN=$(eval echo "$LAN_SUBNET")

if ! command -v ufw &>/dev/null; then
    pacman -S --needed --noconfirm ufw
fi

if ufw status | grep -q "Status: inactive" && [[ $(ufw show added 2>/dev/null | wc -l) -eq 0 ]]; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
fi
ufw allow from "$LAN" to any port 22 proto tcp comment "SSH LAN"
ufw allow 22000/tcp comment "Syncthing sync"
ufw allow 22000/udp comment "Syncthing sync"
ufw allow 21027/udp comment "Syncthing découverte locale"
if ufw status | grep -q "Status: inactive"; then
    read -rp "  ufw est inactif — l'activer maintenant ? [y/N] " _answer
    [[ "${_answer,,}" == "y" ]] && ufw --force enable
fi
systemctl enable ufw
ufw status verbose

# --- Snapper ---
echo "==> Snapper"
if ! command -v snapper &>/dev/null; then
    pacman -S --needed --noconfirm snapper
fi

if ! snapper -c root list &>/dev/null 2>&1; then
    snapper -c root create-config /
fi
if ! snapper -c home list &>/dev/null 2>&1; then
    snapper -c home create-config /home
fi

for config in root home; do
    cfg="/etc/snapper/configs/$config"
    [[ -f "$cfg" ]] || continue
    sed -i "s|^TIMELINE_CREATE=.*|TIMELINE_CREATE=\"no\"|" "$cfg"
    sed -i "s|^ALLOW_USERS=.*|ALLOW_USERS=\"$USER_NAME\"|" "$cfg"
    limit="10"; [[ "$config" == "home" ]] && limit="5"
    sed -i "s|^NUMBER_LIMIT=.*|NUMBER_LIMIT=\"$limit\"|" "$cfg"
    echo "  config $config mise à jour"
done

mkdir -p /etc/pacman.d/hooks
install -m 644 "$SCRIPT_DIR/hooks/00-snapper-pre.hook"  /etc/pacman.d/hooks/
install -m 644 "$SCRIPT_DIR/hooks/zz-snapper-post.hook" /etc/pacman.d/hooks/

systemctl enable --now snapper-cleanup.timer

echo ""
echo "Configuration système terminée."
