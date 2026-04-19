#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Installe paru si absent
if ! command -v paru &>/dev/null; then
    echo "Installation de paru..."
    sudo pacman -S --needed base-devel git
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
    (cd "$tmpdir/paru" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

echo "Installation des paquets natifs..."
paru -S --needed --noconfirm - < "$SCRIPT_DIR/packages/pacman.txt" || true

echo "Installation des paquets AUR..."
paru -S --needed --noconfirm --aur - < "$SCRIPT_DIR/packages/aur.txt" || true

# Paquets optionnels définis dans local.conf
declare -a OPTIONAL_PACMAN_PACKAGES=()
declare -a OPTIONAL_AUR_PACKAGES=()
declare -a OPTIONAL_FLATPAK_PACKAGES=()
if [[ ! -f "$SCRIPT_DIR/local.conf" ]]; then
    echo "[ERREUR] local.conf absent — copie local.conf.example et adapte les valeurs"
    exit 1
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

if [[ ${#OPTIONAL_PACMAN_PACKAGES[@]} -gt 0 ]]; then
    echo "Installation des paquets natifs optionnels..."
    paru -S --needed --noconfirm "${OPTIONAL_PACMAN_PACKAGES[@]}" || true
fi
if [[ ${#OPTIONAL_AUR_PACKAGES[@]} -gt 0 ]]; then
    echo "Installation des paquets AUR optionnels..."
    paru -S --needed --noconfirm --aur "${OPTIONAL_AUR_PACKAGES[@]}" || true
fi

# Flatpak
if command -v flatpak &>/dev/null; then
    echo "Ajout du dépôt Flathub (user)..."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    echo "Installation des apps Flatpak..."
    while IFS= read -r _app || [[ -n "$_app" ]]; do
        [[ -z "$_app" || "$_app" == \#* ]] && continue
        echo "  -> $_app"
        flatpak install --user -y flathub "$_app" || echo "  [WARN] $_app non installé"
    done < "$SCRIPT_DIR/packages/flatpak.txt"

    if [[ ${#OPTIONAL_FLATPAK_PACKAGES[@]} -gt 0 ]]; then
        echo "Installation des apps Flatpak optionnelles..."
        for _app in "${OPTIONAL_FLATPAK_PACKAGES[@]}"; do
            echo "  -> $_app"
            flatpak install --user -y flathub "$_app" || echo "  [WARN] $_app non installé"
        done
    fi
else
    echo "[WARN] flatpak introuvable — apps Flatpak ignorées"
fi

# Groupes interactifs (pacman + AUR + flatpak)
echo ""
echo "Groupes optionnels :"
for _group_file in "$SCRIPT_DIR/packages/groups/"*.conf; do
    [[ -f "$_group_file" ]] || continue
    # shellcheck disable=SC2034
    GROUP_LABEL="" GROUP_PACMAN=() GROUP_AUR=() GROUP_FLATPAK=() GROUP_POST_INSTALL_MSG=""
    # shellcheck source=/dev/null
    source "$_group_file"
    read -rp "  Installer $GROUP_LABEL ? [y/N] " _answer
    if [[ "${_answer,,}" == "y" ]]; then
        if [[ ${#GROUP_PACMAN[@]} -gt 0 ]]; then
            paru -S --needed --noconfirm "${GROUP_PACMAN[@]}" || true
        fi
        if [[ ${#GROUP_AUR[@]} -gt 0 ]]; then
            paru -S --needed --noconfirm --aur "${GROUP_AUR[@]}" || true
        fi
        if [[ ${#GROUP_FLATPAK[@]} -gt 0 ]] && command -v flatpak &>/dev/null; then
            for _app in "${GROUP_FLATPAK[@]}"; do
                echo "  -> $_app"
                flatpak install --user -y flathub "$_app" || echo "  [WARN] $_app non installé"
            done
        fi
        if [[ -n "$GROUP_POST_INSTALL_MSG" ]]; then
            echo "  → $GROUP_POST_INSTALL_MSG"
        fi
    fi
done

echo "Mise à jour complète du système..."
paru -Syu --noconfirm