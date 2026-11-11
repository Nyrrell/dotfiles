.PHONY: install sync save add upgrade packages dotfiles fish zsh dev gnome gnome-diff goa syncthing system lan-ca wireguard ssh backup restore lint check help

ifeq ($(shell id -u),0)
$(error [ERREUR] Ne pas lancer avec sudo. Exécute simplement : make $(MAKECMDGOALS))
endif

DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

define CHECK_GIT
@git fetch origin --quiet 2>/dev/null || true; \
LOCAL=$$(git rev-parse HEAD 2>/dev/null); \
REMOTE=$$(git rev-parse @{u} 2>/dev/null); \
if [ -n "$$REMOTE" ] && [ "$$LOCAL" != "$$REMOTE" ]; then \
	echo "[WARN] Le dépôt n'est pas à jour avec origin"; \
	printf "  c) Continuer\n  u) Mettre à jour (git pull)\n  q) Abandonner\n"; \
	read -rp "Choix [c/u/q] : " _git_answer; \
	case "$$_git_answer" in \
		u) git pull ;; \
		q) exit 1 ;; \
	esac; \
fi
endef

install: ## Installation complète dans le bon ordre
	$(CHECK_GIT)
	@$(MAKE) ssh
	-@$(MAKE) packages
	@$(MAKE) upgrade
	@$(MAKE) dotfiles
	@$(MAKE) fish
	@$(MAKE) dev
	@$(MAKE) gnome
	@$(MAKE) goa
	@$(MAKE) syncthing
	@$(MAKE) system
	@$(MAKE) lan-ca
	@$(MAKE) wireguard
	@echo ""
	@echo "Installation terminée. Redémarre la session pour appliquer tous les changements."

sync: ## Au quotidien : git pull + relance seulement ce qui a changé (FORCE=1 pour tout)
	@bash $(DIR)modules/sync.sh

save: ## Au quotidien : commit + push
	@bash $(DIR)modules/save.sh

add: ## Ajoute un paquet à la bonne liste et l'installe : make add PKG=nom [GROUP=obs]
	@bash $(DIR)modules/add-pkg.sh "$(PKG)" "$(GROUP)"

upgrade: ## Mise à jour système (paru -Syu + flatpak update)
	@paru -Syu --noconfirm
	@if command -v flatpak >/dev/null 2>&1; then flatpak update --user -y; fi

packages: ## Installe les paquets déclarés (pacman, AUR, Flatpak, groupes) sans -Syu
	$(CHECK_GIT)
	@bash $(DIR)modules/02-packages.sh
	@bash $(DIR)modules/sync.sh --mark packages

dotfiles: ## Déploie les configs via GNU Stow
	$(CHECK_GIT)
	@bash $(DIR)modules/03-dotfiles.sh
	@bash $(DIR)modules/sync.sh --mark dotfiles

fish: ## Configure Fish comme shell par défaut
	$(CHECK_GIT)
	@SHELL_CHOICE=fish bash $(DIR)modules/04-shell.sh

zsh: ## Configure Zsh comme shell par défaut
	$(CHECK_GIT)
	@SHELL_CHOICE=zsh bash $(DIR)modules/04-shell.sh

dev: ## Installe fnm + Node.js LTS + Corepack
	$(CHECK_GIT)
	@bash $(DIR)modules/05-dev.sh

gnome: ## Applique gnome/settings.ini et installe gnome/extensions.txt
	$(CHECK_GIT)
	@bash $(DIR)modules/06-gnome.sh
	@bash $(DIR)modules/sync.sh --mark gnome

gnome-diff: ## Écarts entre les réglages GNOME de la machine et gnome/settings.ini
	@bash $(DIR)modules/gnome-diff.sh

goa: ## Configure un compte Cal+Card via GOA Nextcloud
	$(CHECK_GIT)
	@bash $(DIR)modules/10-goa.sh

system: ## Config système : wake-on-lan, udev Keychron, pare-feu, snapper (sudo demandé automatiquement)
	$(CHECK_GIT)
	@bash $(DIR)modules/07-system.sh
	@bash $(DIR)modules/sync.sh --mark system

syncthing: ## Configure les folders Syncthing (peers + KeePass, Documents...)
	$(CHECK_GIT)
	@bash $(DIR)modules/09-syncthing.sh
	@bash $(DIR)modules/sync.sh --mark syncthing

lan-ca: ## Certificat LAN du serveur (vhosts *.int) dans le magasin système (skip si LAN_CA_URL vide)
	$(CHECK_GIT)
	@bash $(DIR)modules/12-lan-ca.sh

wireguard: ## VPN WireGuard via NetworkManager, activation manuelle (skip si WG_ENDPOINT vide)
	$(CHECK_GIT)
	@bash $(DIR)modules/11-wireguard.sh

ssh: ## Génère une clé SSH ed25519 si absente et affiche la clé publique
	$(CHECK_GIT)
	@bash $(DIR)modules/01-ssh.sh

backup: ## Sauvegarde les données personnelles sur le NAS
	$(CHECK_GIT)
	@bash $(DIR)modules/08-backup.sh backup

restore: ## Restaure les données personnelles depuis le NAS
	$(CHECK_GIT)
	@bash $(DIR)modules/08-backup.sh restore

lint: ## Lance shellcheck sur les modules
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck introuvable — sudo pacman -S shellcheck"; exit 1; \
	fi; \
	shellcheck $(DIR)modules/*.sh && echo "shellcheck OK"

check: ## Vérifie que les dépendances système sont présentes
	@ok=0; fail=0; \
	check() { \
		if command -v "$$1" >/dev/null 2>&1; then \
			printf "\033[32m  ✓\033[0m %-20s\n" "$$1"; ok=$$((ok+1)); \
		else \
			printf "\033[31m  ✗\033[0m %-20s  \033[33m→ %s\033[0m\n" "$$1" "$$2"; fail=$$((fail+1)); \
		fi; \
	}; \
	echo "Dépendances :"; \
	check git          "sudo pacman -S git"; \
	check make         "sudo pacman -S make"; \
	check stow         "sudo pacman -S stow"; \
	check paru         "voir modules/02-packages.sh"; \
	check fnm          "make packages"; \
	check flatpak      "sudo pacman -S flatpak"; \
	check dconf        "sudo pacman -S dconf"; \
	check snapper      "sudo pacman -S snapper"; \
	check syncthing    "sudo pacman -S syncthing"; \
	check ethtool      "sudo pacman -S ethtool"; \
	check rsync        "sudo pacman -S rsync"; \
	check ufw          "sudo pacman -S ufw"; \
	check ssh-keygen   "sudo pacman -S openssh"; \
	check shellcheck   "sudo pacman -S shellcheck (pour make lint)"; \
	if [[ ! -f "$$HOME/.ssh/id_ed25519" ]]; then \
		printf "\033[31m  ✗\033[0m %-20s  \033[33m→ %s\033[0m\n" "clé SSH" "make ssh"; fail=$$((fail+1)); \
	else \
		printf "\033[32m  ✓\033[0m %-20s\n" "clé SSH"; ok=$$((ok+1)); \
	fi; \
	check systemd-escape "sudo pacman -S systemd"; \
	echo ""; \
	echo "$$ok ok, $$fail manquant(s)."

help: ## Affiche les targets disponibles
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'