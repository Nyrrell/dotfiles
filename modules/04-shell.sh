#!/usr/bin/env bash
set -euo pipefail

SHELL_CHOICE="${SHELL_CHOICE:-}"
if [[ -z "$SHELL_CHOICE" ]]; then
    echo "Quel shell veux-tu configurer ? [fish/zsh/both]"
    read -r SHELL_CHOICE
fi

case "$SHELL_CHOICE" in
    fish)
        chsh -s /usr/bin/fish
        echo "Fish configuré."
        ;;
    zsh)
        chsh -s /usr/bin/zsh
        echo "Zsh configuré. Ton ~/.zshrc (depuis dotfiles) sera chargé au prochain login."
        ;;
    both)
        chsh -s /usr/bin/fish
        echo "Fish configuré (shell par défaut)."
        echo "Zsh disponible via dotfiles."
        ;;
    *)
        echo "Valeur invalide : '$SHELL_CHOICE'. Utilise fish, zsh ou both."
        exit 1
        ;;
esac