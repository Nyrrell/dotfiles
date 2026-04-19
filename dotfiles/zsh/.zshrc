# ~/.zshrc — à compléter quand tu décideras de migrer vers Zsh
# Pour l'instant ce fichier est un squelette de base fonctionnel.

# Historique
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Complétion
autoload -Uz compinit && compinit

# Autosuggestions & syntax highlighting (installés via 02b-shell.sh)
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fnm
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

# Aliases
alias ll='ls -lah'
alias la='ls -A'
alias pacup='paru -Syu'

# Prompt minimal (remplace par starship si tu veux)
autoload -Uz promptinit && promptinit
prompt adam1
