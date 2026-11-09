#!/usr/bin/env bash
# make add PKG=nom [GROUP=groupe]
# Détecte la source du paquet (dépôts → AUR → Flathub), l'ajoute à la bonne liste
# et l'installe. Ne commit pas : c'est le rôle de `make save`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"

PKG="${1:-}"
GROUP="${2:-}"
if [[ -z "$PKG" ]]; then
    echo "Usage : make add PKG=nom [GROUP=$(basename -a -s .conf "$SCRIPT_DIR"/packages/groups/*.conf | paste -sd'|')]"
    exit 1
fi

declare -a PACKAGE_GROUPS=()
load_conf

if pacman -Si "$PKG" &>/dev/null; then
    src=pacman
elif paru -Si --aur "$PKG" &>/dev/null; then
    src=aur
elif command -v flatpak &>/dev/null && flatpak remote-info --user flathub "$PKG" &>/dev/null; then
    src=flatpak
else
    echo "[ERREUR] '$PKG' introuvable dans les dépôts, l'AUR ou Flathub (pour Flatpak, utiliser l'ID complet, ex: org.gimp.GIMP)."
    exit 1
fi
echo "Source détectée : $src"

# Si l'état était à jour avant l'ajout, on le remet à jour après
# (sinon on laisse make sync rattraper les autres changements en attente).
was_clean=0
[[ -f "$STATE_DIR/packages.sha" ]] && ! is_changed packages && was_clean=1

install_now=1
if [[ -n "$GROUP" ]]; then
    group_file="$SCRIPT_DIR/packages/groups/$GROUP.conf"
    [[ -f "$group_file" ]] || { echo "[ERREUR] groupe inconnu : $GROUP"; exit 1; }
    case "$src" in
        pacman) var=GROUP_PACMAN ;;
        aur) var=GROUP_AUR ;;
        flatpak) var=GROUP_FLATPAK ;;
    esac
    # SC2034 : tableaux remplis par le source ; SC1090 : fichier de groupe choisi à l'exécution
    # shellcheck disable=SC2034,SC1090
    current=$(GROUP_PACMAN=() GROUP_AUR=() GROUP_FLATPAK=(); source "$group_file"; declare -n arr="$var"; printf '%s\n' "${arr[@]}")
    if grep -qFx "$PKG" <<<"$current"; then
        echo "$PKG est déjà dans le groupe $GROUP ($var)."
    else
        # Tableaux sur une seule ligne : VAR=(a b) → VAR=(a b PKG)
        sed -i -E "s/^($var=\()(.*)\)/\1\2 $PKG)/; s/^($var=\() /\1/" "$group_file"
        echo "Ajouté à $var dans packages/groups/$GROUP.conf"
    fi
    if [[ " ${PACKAGE_GROUPS[*]} " != *" $GROUP "* ]]; then
        echo "  (groupe $GROUP non activé sur cette machine — pas d'installation)"
        install_now=0
    fi
else
    list="$SCRIPT_DIR/packages/$src.txt"
    if grep -qFx "$PKG" "$list"; then
        echo "$PKG est déjà dans packages/$src.txt."
    else
        # S'assurer que le fichier se termine par un retour à la ligne avant d'ajouter
        [[ -s "$list" && -n "$(tail -c1 "$list")" ]] && echo >> "$list"
        echo "$PKG" >> "$list"
        echo "Ajouté à packages/$src.txt"
    fi
fi

if [[ "$install_now" == 1 ]]; then
    case "$src" in
        pacman) paru -S --needed --noconfirm "$PKG" ;;
        aur) paru -S --needed --noconfirm --aur "$PKG" ;;
        flatpak) flatpak install --user -y flathub "$PKG" ;;
    esac
fi

[[ "$was_clean" == 1 ]] && mark_done packages
echo "OK — pense à 'make save' pour le partager avec tes autres machines."
