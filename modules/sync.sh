#!/usr/bin/env bash
# make sync : git pull, puis relance uniquement les modules dont les entrées ont changé.
#   FORCE=1   relance tous les modules
#   NO_PULL=1 saute le git pull
# sync.sh --mark <module>... : enregistre l'état courant comme appliqué (utilisé par le Makefile)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"

if [[ "${1:-}" == "--mark" ]]; then
    shift
    for _key in "$@"; do mark_done "$_key"; done
    exit 0
fi

declare -A MODULE_SCRIPT=(
    [packages]=02-packages.sh
    [dotfiles]=03-dotfiles.sh
    [gnome]=06-gnome.sh
    [system]=07-system.sh
    [syncthing]=09-syncthing.sh
)

cd "$SCRIPT_DIR"

# Modules jamais suivis sur cette machine (machine déjà installée avant make sync) :
# sans état enregistré, ils seraient tous relancés. On propose de considérer la
# version locale comme appliquée — avant le pull, pour que les nouveautés distantes
# soient bien détectées ensuite.
untracked=()
for _key in "${SYNC_MODULES[@]}"; do
    [[ -f "$STATE_DIR/$_key.sha" ]] || untracked+=("$_key")
done
if [[ ${#untracked[@]} -gt 0 && "${FORCE:-0}" != 1 ]]; then
    echo "Modules jamais suivis sur cette machine : ${untracked[*]}"
    read -rp "La version locale actuelle est-elle déjà appliquée pour ceux-là ? [Y/n] " _answer
    if [[ "${_answer,,}" != "n" ]]; then
        for _key in "${untracked[@]}"; do mark_done "$_key"; done
        echo "  État enregistré."
    fi
fi

if [[ "${NO_PULL:-0}" != 1 ]]; then
    echo "==> git pull"
    if ! git pull --ff-only; then
        echo "[ERREUR] git pull impossible (divergence ou modifs locales en conflit)."
        echo "         Résous la situation (make save, git stash…) puis relance make sync."
        exit 1
    fi
fi

ran=() unchanged=() failed=()
for _key in "${SYNC_MODULES[@]}"; do
    if [[ "${FORCE:-0}" != 1 ]] && ! is_changed "$_key"; then
        unchanged+=("$_key")
        continue
    fi
    echo ""
    echo "==> $_key"
    if bash "$SCRIPT_DIR/modules/${MODULE_SCRIPT[$_key]}"; then
        mark_done "$_key"
        ran+=("$_key")
    else
        failed+=("$_key")
    fi
done

echo ""
echo "── Récap sync ──"
echo "  relancé   : ${ran[*]:-aucun}"
echo "  inchangé  : ${unchanged[*]:-aucun}"
if [[ ${#failed[@]} -gt 0 ]]; then
    echo "  en échec  : ${failed[*]} (sera retenté au prochain make sync)"
    exit 1
fi
