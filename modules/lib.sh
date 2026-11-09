# shellcheck shell=bash
# Helpers partagés entre les modules.
# Usage : source "$SCRIPT_DIR/modules/lib.sh"

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CONF="$DOTFILES_ROOT/local.conf"
# État par machine (hors dépôt) : hash des entrées de chaque module déjà appliqué
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
# Modules suivis par `make sync`, dans l'ordre d'exécution (utilisé par sync.sh)
# shellcheck disable=SC2034
SYNC_MODULES=(packages dotfiles gnome system syncthing)

# --- local.conf ---------------------------------------------------------------

# À appeler au niveau global du script (pas dans une fonction) pour que les
# variables restent visibles partout.
load_conf() {
    if [[ ! -f "$LOCAL_CONF" ]]; then
        echo "[ERREUR] local.conf absent — copie local.conf.example et adapte les valeurs" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$LOCAL_CONF"
}

# Ajoute une ligne bash à la fin de local.conf (mémorise une réponse).
conf_append() {
    # Le fichier peut ne pas finir par un retour à la ligne
    [[ -s "$LOCAL_CONF" && -n "$(tail -c1 "$LOCAL_CONF")" ]] && echo >> "$LOCAL_CONF"
    printf '%s  # auto %s\n' "$1" "$(date +%F)" >> "$LOCAL_CONF"
}

# ask_once VAR "question" [y|n]
# Si VAR est déjà défini dans local.conf, ne demande rien. Sinon pose la question
# une seule fois et mémorise VAR="yes"|"no" dans local.conf.
ask_once() {
    local var="$1" question="$2" default="${3:-n}" hint answer
    [[ -n "${!var:-}" ]] && return 0
    if [[ "$default" == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
    if ! read -rp "  $question $hint " answer; then
        # Pas d'entrée (stdin fermé) : défaut pour ce run, sans le mémoriser
        echo ""
        if [[ "$default" == y ]]; then printf -v "$var" yes; else printf -v "$var" no; fi
        return 0
    fi
    answer="${answer:-$default}"
    if [[ "${answer,,}" == y* ]]; then answer=yes; else answer=no; fi
    printf -v "$var" '%s' "$answer"
    conf_append "$var=\"$answer\""
    echo "  → $var=$answer mémorisé dans local.conf"
}

# detect_once VAR commande... : si VAR n'est pas encore défini et que la commande
# réussit (ex : service déjà activé), mémorise VAR="yes" sans poser de question.
# À appeler juste avant ask_once.
detect_once() {
    local var="$1"
    shift
    [[ -n "${!var:-}" ]] && return 0
    if "$@" &>/dev/null; then
        printf -v "$var" yes
        conf_append "$var=\"yes\""
        echo "  → déjà actif sur cette machine : $var=yes mémorisé dans local.conf"
    fi
}

# is_yes VAR → vrai si VAR vaut "yes"
is_yes() { [[ "${!1:-}" == yes ]]; }

# --- Détection des changements -------------------------------------------------

# Contenu dont dépend chaque module : si son hash change, `make sync` le relance.
module_inputs() {
    cd "$DOTFILES_ROOT" || return 1
    case "$1" in
        packages)
            cat packages/*.txt packages/groups/*.conf modules/02-packages.sh
            declare -p OPTIONAL_PACMAN_PACKAGES OPTIONAL_AUR_PACKAGES \
                OPTIONAL_PREBUILT_PACKAGES OPTIONAL_FLATPAK_PACKAGES \
                PACKAGE_GROUPS PACKAGE_GROUPS_SKIP 2>/dev/null || true
            ;;
        dotfiles)
            # Le contenu suit déjà via les symlinks : seule la liste des fichiers compte
            find dotfiles \( -type f -o -type l \) | LC_ALL=C sort
            cat modules/03-dotfiles.sh
            ;;
        gnome)
            cat gnome/dconf-backup.ini modules/06-gnome.sh
            ;;
        system)
            cat systemd/system/* hooks/* ssh/*.tpl modules/07-system.sh
            declare -p LAN_SUBNET EXTRA_MOUNTS BACKUP_HOST NAS_REMOTE_PATH \
                NAS_WAN_HOST NAS_WAN_PORT ENABLE_WOL ENABLE_UFW 2>/dev/null || true
            ;;
        syncthing)
            cat modules/09-syncthing.sh
            declare -p SYNC_FOLDERS SYNC_INTRODUCERS 2>/dev/null || true
            ;;
        *)
            echo "[ERREUR] module inconnu : $1" >&2
            return 1
            ;;
    esac
}

module_hash() {
    ( load_conf; module_inputs "$1" ) | sha256sum | cut -d' ' -f1
}

# Vrai si les entrées du module ont changé depuis sa dernière application
is_changed() {
    [[ "$(module_hash "$1")" != "$(cat "$STATE_DIR/$1.sha" 2>/dev/null)" ]]
}

# Enregistre l'état courant du module comme appliqué
mark_done() {
    mkdir -p "$STATE_DIR"
    module_hash "$1" > "$STATE_DIR/$1.sha"
}
