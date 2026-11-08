#!/usr/bin/env bash
# Installe les paquets déclarés (pacman, AUR, pré-compilés, Flatpak, groupes).
# Ne fait PAS de mise à jour système : c'est le rôle de `make upgrade`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"

declare -a OPTIONAL_PACMAN_PACKAGES=() OPTIONAL_AUR_PACKAGES=() \
    OPTIONAL_PREBUILT_PACKAGES=() OPTIONAL_FLATPAK_PACKAGES=() \
    PACKAGE_GROUPS=() PACKAGE_GROUPS_SKIP=()
load_conf

FAILED=()
fail() {
    FAILED+=("$1")
    echo "  [WARN] échec : $1"
}

in_list() {
    local needle="$1" x
    shift
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

flatpak_install() {
    local app
    command -v flatpak &>/dev/null || return 0
    for app in "$@"; do
        if flatpak info --user "$app" &>/dev/null; then
            continue
        fi
        echo "  -> $app"
        flatpak install --user -y flathub "$app" || fail "$app (flatpak)"
    done
}

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
paru -S --needed --noconfirm - < "$SCRIPT_DIR/packages/pacman.txt" || fail "paquets natifs (pacman.txt)"

echo "Installation des paquets AUR..."
paru -S --needed --noconfirm --aur - < "$SCRIPT_DIR/packages/aur.txt" || fail "paquets AUR (aur.txt)"

if [[ ${#OPTIONAL_PACMAN_PACKAGES[@]} -gt 0 ]]; then
    echo "Installation des paquets natifs optionnels..."
    paru -S --needed --noconfirm "${OPTIONAL_PACMAN_PACKAGES[@]}" || fail "OPTIONAL_PACMAN_PACKAGES"
fi
if [[ ${#OPTIONAL_AUR_PACKAGES[@]} -gt 0 ]]; then
    echo "Installation des paquets AUR optionnels..."
    paru -S --needed --noconfirm --aur "${OPTIONAL_AUR_PACKAGES[@]}" || fail "OPTIONAL_AUR_PACKAGES"
fi
if [[ ${#OPTIONAL_PREBUILT_PACKAGES[@]} -gt 0 ]]; then
    echo "Installation des paquets pré-compilés optionnels..."
    _tmpdir=$(mktemp -d)
    for _entry in "${OPTIONAL_PREBUILT_PACKAGES[@]}"; do
        _pkgname="${_entry%%|*}"
        _pkgurl="${_entry##*|}"
        if pacman -Qq | grep -qixF "$_pkgname"; then  # insensible à la casse (ex: HyperHDR)
            echo "  -> $_pkgname déjà installé, ignoré"
            continue
        fi
        _pkgfile="$_tmpdir/${_pkgurl##*/}"
        echo "  -> Téléchargement $_pkgname..."
        curl -fL --progress-bar -o "$_pkgfile" "$_pkgurl" || { fail "$_pkgname (téléchargement)"; continue; }
        echo "  -> Installation $_pkgname..."
        sudo pacman -U --noconfirm "$_pkgfile" || fail "$_pkgname (pré-compilé)"
    done
    rm -rf "$_tmpdir"
fi

# Flatpak
if command -v flatpak &>/dev/null; then
    echo "Ajout du dépôt Flathub (user)..."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    echo "Installation des apps Flatpak..."
    _flatpak_apps=()
    while IFS= read -r _app || [[ -n "$_app" ]]; do
        [[ -z "$_app" || "$_app" == \#* ]] && continue
        _flatpak_apps+=("$_app")
    done < "$SCRIPT_DIR/packages/flatpak.txt"
    flatpak_install "${_flatpak_apps[@]}" "${OPTIONAL_FLATPAK_PACKAGES[@]}"
else
    echo "[WARN] flatpak introuvable — apps Flatpak ignorées"
fi

# Groupes optionnels : le choix est mémorisé par machine dans local.conf
# (PACKAGE_GROUPS / PACKAGE_GROUPS_SKIP). Seul un groupe jamais vu déclenche une question.
install_group() {
    if [[ ${#GROUP_PACMAN[@]} -gt 0 ]]; then
        paru -S --needed --noconfirm "${GROUP_PACMAN[@]}" || fail "groupe $1 (pacman)"
    fi
    if [[ ${#GROUP_AUR[@]} -gt 0 ]]; then
        paru -S --needed --noconfirm --aur "${GROUP_AUR[@]}" || fail "groupe $1 (AUR)"
    fi
    if [[ ${#GROUP_FLATPAK[@]} -gt 0 ]]; then
        flatpak_install "${GROUP_FLATPAK[@]}"
    fi
    if [[ -n "$GROUP_POST_INSTALL_MSG" ]]; then
        echo "  → $GROUP_POST_INSTALL_MSG"
    fi
}

# Vrai si tous les paquets du groupe chargé sont déjà installés (groupe non vide)
group_installed() {
    local p
    [[ $(( ${#GROUP_PACMAN[@]} + ${#GROUP_AUR[@]} + ${#GROUP_FLATPAK[@]} )) -gt 0 ]] || return 1
    for p in "${GROUP_PACMAN[@]}" "${GROUP_AUR[@]}"; do
        pacman -Q "$p" &>/dev/null || return 1
    done
    for p in "${GROUP_FLATPAK[@]}"; do
        flatpak info --user "$p" &>/dev/null || return 1
    done
}

echo ""
echo "Groupes optionnels :"
for _group_file in "$SCRIPT_DIR/packages/groups/"*.conf; do
    [[ -f "$_group_file" ]] || continue
    _group=$(basename "$_group_file" .conf)
    # shellcheck disable=SC2034
    GROUP_LABEL="" GROUP_PACMAN=() GROUP_AUR=() GROUP_FLATPAK=() GROUP_POST_INSTALL_MSG=""
    # shellcheck source=/dev/null
    source "$_group_file"

    if in_list "$_group" "${PACKAGE_GROUPS[@]}"; then
        echo "  [$_group] $GROUP_LABEL"
        install_group "$_group"
    elif in_list "$_group" "${PACKAGE_GROUPS_SKIP[@]}"; then
        echo "  [$_group] ignoré (PACKAGE_GROUPS_SKIP)"
    elif group_installed; then
        PACKAGE_GROUPS+=("$_group")
        conf_append "PACKAGE_GROUPS+=($_group)"
        echo "  [$_group] déjà installé : mémorisé dans local.conf"
    else
        if ! read -rp "  Installer $GROUP_LABEL ? (choix mémorisé dans local.conf) [y/N] " _answer; then
            echo "  [SKIP] pas d'entrée — question reposée au prochain run"
        elif [[ "${_answer,,}" == "y" ]]; then
            PACKAGE_GROUPS+=("$_group")
            conf_append "PACKAGE_GROUPS+=($_group)"
            install_group "$_group"
        else
            PACKAGE_GROUPS_SKIP+=("$_group")
            conf_append "PACKAGE_GROUPS_SKIP+=($_group)"
        fi
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "[ERREUR] ${#FAILED[@]} échec(s) :"
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
echo "Paquets OK."
