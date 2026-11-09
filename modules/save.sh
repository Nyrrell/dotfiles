#!/usr/bin/env bash
# make save : commit + push de tout ce qui a changé.
# Les réglages GNOME ne sont plus exportés : gnome/settings.ini s'édite à la main (make gnome-diff).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=modules/lib.sh
source "$SCRIPT_DIR/modules/lib.sh"

cd "$SCRIPT_DIR"

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
