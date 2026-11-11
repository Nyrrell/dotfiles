#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Élévation des droits nécessaire pour la configuration système..."
    exec sudo bash "${BASH_SOURCE[0]}" "$@"
fi

USER_NAME="${SUDO_USER:-$(whoami)}"

# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"
load_conf

# --- Wake-on-LAN ---
echo "==> Wake-on-LAN"
detect_once ENABLE_WOL systemctl is-enabled --quiet wake-on-lan.service
ask_once ENABLE_WOL "Activer Wake-on-LAN ? (filaire uniquement)"
if is_yes ENABLE_WOL; then
    cp "$SCRIPT_DIR/systemd/system/wake-on-lan.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now wake-on-lan.service || true
else
    echo "  [SKIP] Wake-on-LAN ignoré"
fi

# --- Règle udev Keychron (Launcher / VIA) ---
echo "==> Clavier Keychron"
KEYCHRON_RULE=/etc/udev/rules.d/50-keychron.rules
detect_once ENABLE_KEYCHRON test -f "$KEYCHRON_RULE"
ask_once ENABLE_KEYCHRON "Installer la règle udev Keychron ? (config du clavier via Launcher/VIA)"
if is_yes ENABLE_KEYCHRON; then
    install -m 644 "$SCRIPT_DIR/udev/50-keychron.rules" "$KEYCHRON_RULE"
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=hidraw
    echo "  Règle installée : $KEYCHRON_RULE"
elif [[ -f "$KEYCHRON_RULE" ]]; then
    rm -f "$KEYCHRON_RULE"
    udevadm control --reload-rules
    echo "  Règle Keychron retirée (ENABLE_KEYCHRON=no)"
else
    echo "  [SKIP] Règle Keychron ignorée"
fi

# --- Disques additionnels (fstab) ---
echo "==> Disques additionnels"
FSTAB_BEGIN="# >>> dotfiles EXTRA_MOUNTS >>>"
FSTAB_END="# <<< dotfiles EXTRA_MOUNTS <<<"

if grep -qF "$FSTAB_BEGIN" /etc/fstab; then
    sed -i "/^# >>> dotfiles EXTRA_MOUNTS >>>$/,/^# <<< dotfiles EXTRA_MOUNTS <<<$/d" /etc/fstab
fi
sed -i -e :a -e '/^$/{$d;N;ba' -e '}' /etc/fstab

if [[ ${#EXTRA_MOUNTS[@]} -eq 0 ]]; then
    echo "  [SKIP] EXTRA_MOUNTS vide — rien à monter"
else
    cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
    NEW_BLOCK=$(mktemp)
    printf '\n%s\n' "$FSTAB_BEGIN" >> "$NEW_BLOCK"
    for entry in "${EXTRA_MOUNTS[@]}"; do
        IFS='|' read -r uuid mountpoint fstype options <<< "$entry"
        if [[ -z "$uuid" || -z "$mountpoint" || -z "$fstype" || -z "$options" ]]; then
            echo "  [WARN] Entrée invalide ignorée : $entry"
            continue
        fi
        if grep -qE "^[[:space:]]*UUID=$uuid\b" /etc/fstab; then
            echo "  [SKIP] UUID=$uuid déjà dans /etc/fstab (hors bloc géré)"
            continue
        fi
        mkdir -p "$mountpoint"
        printf 'UUID=%s\t%s\t%s\t%s\t0 0\n' "$uuid" "$mountpoint" "$fstype" "$options" >> "$NEW_BLOCK"
        echo "  + $mountpoint (UUID=$uuid)"
    done
    printf '%s\n' "$FSTAB_END" >> "$NEW_BLOCK"
    cat "$NEW_BLOCK" >> /etc/fstab
    rm -f "$NEW_BLOCK"
    systemctl daemon-reload
    mount -a || echo "  [WARN] mount -a a renvoyé une erreur"
fi

# --- Mount NAS (system automount) ---
echo "==> NAS automount"
NAS_HOST=$(eval echo "$BACKUP_HOST")
NAS_USER_VAL="$USER_NAME"
USER_HOME=$(eval echo "~$USER_NAME")
USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")
# Monté HORS du home : un point de montage FUSE mort dans $HOME casse le
# démarrage des apps Flatpak (bubblewrap parcourt $HOME au lancement).
# ~/nas reste dispo via un symlink vers /mnt/nas (voir plus bas).
NAS_MOUNT_PATH="/mnt/nas"
NAS_LINK="$USER_HOME/nas"
NAS_UNIT=$(systemd-escape --path "$NAS_MOUNT_PATH")
SSH_KEY="$USER_HOME/.ssh/id_ed25519"

if [[ "$NAS_HOST" == "CHANGEME" ]]; then
    echo "  [SKIP] BACKUP_HOST non configuré — définis-le dans local.conf"
else
    # Activer allow_other dans fuse pour les mounts système
    if [[ -f /etc/fuse.conf ]] && ! grep -q "^user_allow_other" /etc/fuse.conf; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    # Nettoyage de l'ancien montage dans le home (legacy ~/nas) + du montage courant
    LEGACY_UNIT=$(systemd-escape --path "$USER_HOME/nas")
    for unit in "$LEGACY_UNIT" "$NAS_UNIT"; do
        for ext in automount mount; do
            if systemctl is-active --quiet "${unit}.${ext}" 2>/dev/null; then
                systemctl stop "${unit}.${ext}" || true
            fi
            systemctl disable "${unit}.${ext}" 2>/dev/null || true
        done
    done
    # Supprimer les unités legacy si le montage a bougé hors du home
    if [[ "$LEGACY_UNIT" != "$NAS_UNIT" ]]; then
        rm -f "/etc/systemd/system/${LEGACY_UNIT}.mount" "/etc/systemd/system/${LEGACY_UNIT}.automount"
        # Remplacer l'ancien dossier ~/nas (vidé) par un symlink vers le nouveau point
        if [[ -d "$NAS_LINK" && ! -L "$NAS_LINK" ]]; then
            rmdir "$NAS_LINK" 2>/dev/null && echo "  Ancien dossier ~/nas supprimé"
        fi
    fi

    mkdir -p "$NAS_MOUNT_PATH"

    # Symlink de compat : ~/nas -> /mnt/nas
    if [[ ! -e "$NAS_LINK" || -L "$NAS_LINK" ]]; then
        ln -sfn "$NAS_MOUNT_PATH" "$NAS_LINK"
        chown -h "$USER_NAME:$USER_NAME" "$NAS_LINK"
    else
        echo "  [ATTENTION] $NAS_LINK existe et n'est pas vide — symlink non créé"
    fi

    if sudo -u "$USER_NAME" ssh -i "$SSH_KEY" \
            -o ConnectTimeout=5 -o BatchMode=yes \
            -o StrictHostKeyChecking=accept-new \
            "${NAS_USER_VAL}@${NAS_HOST}" true 2>/dev/null; then
        echo "  Clé SSH déjà autorisée sur ${NAS_USER_VAL}@${NAS_HOST}"
    else
        echo "  Clé SSH ($SSH_KEY.pub) non autorisée sur ${NAS_USER_VAL}@${NAS_HOST}"
        read -rp "  Lancer ssh-copy-id maintenant ? (mot de passe NAS requis) [Y/n] " _copy_answer
        if [[ "${_copy_answer,,}" != "n" ]]; then
            if ! sudo -u "$USER_NAME" ssh-copy-id -i "${SSH_KEY}.pub" \
                    -o StrictHostKeyChecking=accept-new \
                    "${NAS_USER_VAL}@${NAS_HOST}"; then
                echo "  [WARN] ssh-copy-id a échoué — l'automount sera créé mais ne fonctionnera pas tant que la clé n'est pas copiée"
            fi
        else
            echo "  [WARN] L'automount sera créé mais ne fonctionnera pas tant que la clé n'est pas copiée manuellement :"
            echo "    ssh-copy-id -i ${SSH_KEY}.pub ${NAS_USER_VAL}@${NAS_HOST}"
        fi
    fi

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

# --- Ancien fallback SSH WAN (retiré) ---
# Le NAS n'est plus exposé en SSH sur Internet : hors de chez soi, on passe par le
# VPN (nmcli connection up "$WG_CONN_NAME"). On nettoie le fichier des anciennes installs.
SSH_FALLBACK_FILE=/etc/ssh/ssh_config.d/40-nas-fallback.conf
if [[ -f "$SSH_FALLBACK_FILE" ]]; then
    rm -f "$SSH_FALLBACK_FILE"
    echo "==> Ancien fallback SSH WAN du NAS retiré ($SSH_FALLBACK_FILE) : passer par le VPN"
fi

# --- Pare-feu (ufw) ---
echo "==> Pare-feu"
LAN=$(eval echo "$LAN_SUBNET")

if ! command -v ufw &>/dev/null; then
    pacman -S --needed --noconfirm ufw
fi

# Règles et politiques appliquées à chaque run (idempotent : ufw ignore une règle
# existante), que ufw soit déjà actif ou non — y compris s'il était activé par
# défaut avec une autre config. Les règles passent avant les politiques pour ne
# jamais couper le SSH LAN. Les règles ajoutées à la main sont conservées.
ufw allow from "$LAN" to any port 22 proto tcp comment "SSH LAN"
ufw allow 22000/tcp comment "Syncthing sync"
ufw allow 22000/udp comment "Syncthing sync"
ufw allow 21027/udp comment "Syncthing découverte locale"
ufw default deny incoming
ufw default allow outgoing

ufw_active() { ufw status | grep -q "Status: active"; }
detect_once ENABLE_UFW ufw_active
ask_once ENABLE_UFW "Activer le pare-feu ufw ?"
if is_yes ENABLE_UFW; then
    ufw_active || ufw --force enable
    systemctl enable ufw
fi
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

# set_snapper_key FICHIER CLÉ VALEUR : remplace la clé, ou l'ajoute si absente
set_snapper_key() {
    if grep -q "^$2=" "$1"; then
        sed -i "s|^$2=.*|$2=\"$3\"|" "$1"
    else
        echo "$2=\"$3\"" >> "$1"
    fi
}

# root : snapshots pre/post pacman uniquement (hooks), 10 gardés
# home : timeline horaire contre les suppressions accidentelles. Rétention courte
#        car ~ bouge beaucoup (.cache, flatpak, Téléchargements) : un fichier
#        supprimé n'occupe plus de place après au plus 7 jours.
for config in root home; do
    cfg="/etc/snapper/configs/$config"
    [[ -f "$cfg" ]] || continue
    set_snapper_key "$cfg" ALLOW_USERS "$USER_NAME"
    if [[ "$config" == "root" ]]; then
        set_snapper_key "$cfg" TIMELINE_CREATE no
        set_snapper_key "$cfg" NUMBER_LIMIT 10
    else
        set_snapper_key "$cfg" TIMELINE_CREATE yes
        set_snapper_key "$cfg" TIMELINE_CLEANUP yes
        set_snapper_key "$cfg" TIMELINE_LIMIT_HOURLY 12
        set_snapper_key "$cfg" TIMELINE_LIMIT_DAILY 7
        set_snapper_key "$cfg" TIMELINE_LIMIT_WEEKLY 0
        set_snapper_key "$cfg" TIMELINE_LIMIT_MONTHLY 0
        set_snapper_key "$cfg" TIMELINE_LIMIT_QUARTERLY 0
        set_snapper_key "$cfg" TIMELINE_LIMIT_YEARLY 0
        set_snapper_key "$cfg" NUMBER_LIMIT 5
    fi
    echo "  config $config mise à jour"
done

mkdir -p /etc/pacman.d/hooks
install -m 644 "$SCRIPT_DIR/hooks/00-snapper-pre.hook"  /etc/pacman.d/hooks/
install -m 644 "$SCRIPT_DIR/hooks/zz-snapper-post.hook" /etc/pacman.d/hooks/

systemctl enable --now snapper-cleanup.timer
systemctl enable --now snapper-timeline.timer

echo ""
echo "Configuration système terminée."
