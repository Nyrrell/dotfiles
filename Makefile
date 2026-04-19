.PHONY: install packages dotfiles fish zsh dev gnome syncthing system ssh backup restore update lint check help

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
	@$(MAKE) packages
	@$(MAKE) dotfiles
	@$(MAKE) fish
	@$(MAKE) dev
	@$(MAKE) gnome
	@$(MAKE) syncthing
	@$(MAKE) system
	@echo ""
	@echo "Installation terminée. Redémarre la session pour appliquer tous les changements."

packages: ## Installe tous les paquets pacman + AUR
	$(CHECK_GIT)
	@bash $(DIR)modules/02-packages.sh

dotfiles: ## Déploie les configs via GNU Stow
	$(CHECK_GIT)
	@bash $(DIR)modules/03-dotfiles.sh

fish: ## Configure Fish comme shell par défaut
	$(CHECK_GIT)
	@SHELL_CHOICE=fish bash $(DIR)modules/04-shell.sh

zsh: ## Configure Zsh comme shell par défaut
	$(CHECK_GIT)
	@SHELL_CHOICE=zsh bash $(DIR)modules/04-shell.sh

dev: ## Installe fnm + Node.js LTS + Corepack
	$(CHECK_GIT)
	@bash $(DIR)modules/05-dev.sh

gnome: ## Restaure les settings GNOME via dconf
	$(CHECK_GIT)
	@bash $(DIR)modules/06-gnome.sh

system: ## Config système : wake-on-lan, pare-feu, snapper (sudo demandé automatiquement)
	$(CHECK_GIT)
	@bash $(DIR)modules/07-system.sh

syncthing: ## Configure les folders Syncthing (peers + KeePass, Documents...)
	$(CHECK_GIT)
	@bash $(DIR)modules/09-syncthing.sh

ssh: ## Génère une clé SSH ed25519 si absente et affiche la clé publique
	$(CHECK_GIT)
	@bash $(DIR)modules/01-ssh.sh

backup: ## Sauvegarde les données personnelles sur le NAS
	$(CHECK_GIT)
	@bash $(DIR)modules/08-backup.sh backup

restore: ## Restaure les données personnelles depuis le NAS
	$(CHECK_GIT)
	@bash $(DIR)modules/08-backup.sh restore

update: ## Sauvegarde les settings GNOME utiles (thème, extensions, clavier…)
	$(CHECK_GIT)
	@bash $(DIR)modules/update-gnome.sh

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