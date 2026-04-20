#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"

if ! command -v stow &>/dev/null; then
    echo "[ERREUR] stow n'est pas installé. Lance d'abord : make packages"
    exit 1
fi

cd "$DOTFILES_DIR"

# ~/.ssh doit exister avec 700 avant que stow y crée des symlinks
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Avant chaque stow, retirer les fichiers réguliers qui bloqueraient les symlinks
clear_stow_conflicts() {
    local pkg="$1"
    while IFS= read -r src; do
        local rel dest
        rel="${src#"$pkg"/}"
        dest="$HOME/$rel"
        if [[ -L "$dest" ]]; then
            [[ "$(readlink "$dest")" != "$DOTFILES_DIR"* ]] && rm "$dest"
        elif [[ -f "$dest" ]]; then
            rm "$dest"
        fi
    done < <(find "$pkg" -type f)
}

for pkg in fish zsh git environment profile systemd ssh mimeapps; do
    if [[ -d "$pkg" ]]; then
        echo "Stow: $pkg"
        clear_stow_conflicts "$pkg"
        stow --restow --no-folding --target="$HOME" "$pkg"
    fi
done

if command -v hyperhdr &>/dev/null; then
    echo "Stow: hyperhdr"
    clear_stow_conflicts hyperhdr
    stow --restow --no-folding --target="$HOME" hyperhdr
    systemctl --user enable hyperhdr.service 2>/dev/null || true
fi

[[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config"
chmod -R +x "$HOME/.local/share/bin/" 2>/dev/null || true

# Écrit le chemin réel du repo pour les services systemd
mkdir -p "$HOME/.config"
if ! echo "DOTFILES_DIR=$SCRIPT_DIR" > "$HOME/.config/dotfiles.env" 2>/dev/null; then
    echo "[WARN] Impossible d'écrire ~/.config/dotfiles.env"
    echo "       Lance : sudo chown -R $(whoami):$(whoami) ~/.config"
fi
systemctl --user enable --now backup.timer 2>/dev/null || true
systemctl --user enable --now syncthing.service 2>/dev/null || true

# Configuration git user si non définie (écrit dans ~/.gitconfig.local)
if [[ -z "$(git config --get user.name 2>/dev/null)" ]] || [[ -z "$(git config --get user.email 2>/dev/null)" ]]; then
    git_name=$(git config --get user.name 2>/dev/null || true)
    git_email=$(git config --get user.email 2>/dev/null || true)
    [[ -z "$git_name" ]]  && read -rp "Git user.name  : " git_name
    [[ -z "$git_email" ]] && read -rp "Git user.email : " git_email
    printf '[user]\n\tname = %s\n\temail = %s\n' "$git_name" "$git_email" > "$HOME/.gitconfig.local"
fi

echo "Dotfiles déployés."