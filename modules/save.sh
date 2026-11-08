#!/usr/bin/env bash
# make save : exporte les settings GNOME, puis commit + push de tout ce qui a changé.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"

cd "$SCRIPT_DIR"

echo "==> Export GNOME"
bash "$SCRIPT_DIR/modules/update-gnome.sh"
# Les settings viennent de cette machine : inutile de les recharger au prochain sync
[[ -f "$STATE_DIR/gnome.sha" ]] && mark_done gnome

if [[ -z "$(git status --porcelain)" ]]; then
    echo "Rien à sauver, le dépôt est à jour."
    exit 0
fi

echo ""
echo "Changements :"
git status --short
echo ""
read -rp "Tout commiter et pousser ? [Y/n] " _answer
if [[ "${_answer,,}" == "n" ]]; then
    echo "Abandon — rien n'a été commité."
    exit 0
fi

_default_msg="save: $(hostname) $(date '+%F %H:%M')"
read -rp "Message [$_default_msg] : " _msg
git add -A
git commit -m "${_msg:-$_default_msg}"
git push
