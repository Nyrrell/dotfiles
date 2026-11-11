# Rappel à l'ouverture d'un terminal : état du dépôt ~/.dotfiles par rapport à origin.
# Rien n'est affiché si tout est à jour. La comparaison utilise les refs déjà connues
# (instantané) ; un git fetch part ensuite en arrière-plan, au plus toutes les 10 min,
# pour que l'info soit à jour au terminal suivant.
status is-interactive; or return

function __dotfiles_warn
    set_color yellow
    echo "dotfiles : $argv"
    set_color normal
end

function __dotfiles_status
    set -l repo ~/.dotfiles
    test -d $repo/.git; or return

    set -l counts (command git -C $repo rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null | string split \t)
    if test (count $counts) -eq 2
        set -l ahead $counts[1]
        set -l behind $counts[2]
        if test $ahead -gt 0 -a $behind -gt 0
            __dotfiles_warn "divergé ($ahead local, $behind distant) → git pull --rebase puis git push"
        else if test $behind -gt 0
            __dotfiles_warn "$behind commit(s) à récupérer → make sync"
        else if test $ahead -gt 0
            __dotfiles_warn "$ahead commit(s) non poussé(s) → git push"
        end
    end

    if test -n "$(command git -C $repo status --porcelain 2>/dev/null)"
        __dotfiles_warn "modifications non commitées → make save"
    end

    # Fetch en arrière-plan, sans jamais demander d'identifiants
    set -l age (path mtime --relative $repo/.git/FETCH_HEAD 2>/dev/null)
    if test -z "$age"; or test $age -gt 600
        GIT_TERMINAL_PROMPT=0 command git -C $repo fetch --quiet origin &>/dev/null &
        disown
    end
end

__dotfiles_status
functions -e __dotfiles_status __dotfiles_warn
