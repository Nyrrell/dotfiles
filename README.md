# dotfiles

Scripts de post-installation et configs personnelles (Arch-based).

## Prérequis

- Distribution Arch-based
- `git` et `make` installés (`sudo pacman -S git make`)

## Démarrage rapide

```bash
git clone https://github.com/Nyrrell/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make help
```

## Vérifier les dépendances

```bash
make check
```

## Nouvelle installation

```bash
make install   # tout en une fois — sudo demandé automatiquement pour la config système
```

Pour rejouer une étape seule :

```bash
make ssh        # clé SSH ed25519 (à faire en premier, nécessaire pour GitHub et le NAS)
make packages   # paquets pacman + AUR + Flatpak + groupes interactifs (OBS, gaming…)
make dotfiles   # symlinks via GNU Stow + git user config
make fish       # shell par défaut
make dev        # fnm + Node.js LTS
make gnome      # settings GNOME (dconf)
make syncthing  # peers et folders (nécessite SYNC_INTRODUCERS dans local.conf)
make system     # wake-on-lan, pare-feu, snapper (sudo demandé automatiquement)
```

## Targets disponibles

| Commande         | Description                                                                    |
|------------------|--------------------------------------------------------------------------------|
| `make install`   | Installation complète : ssh, packages, dotfiles, dev, GNOME, syncthing, system |
| `make packages`  | Installe paquets pacman + AUR + Flatpak + groupes interactifs (OBS, gaming…)   |
| `make dotfiles`  | Déploie les configs via GNU Stow                                               |
| `make fish`      | Configure Fish comme shell par défaut                                          |
| `make zsh`       | Configure Zsh comme shell par défaut                                           |
| `make dev`       | Installe fnm + Node.js LTS + Corepack                                          |
| `make gnome`     | Restaure les settings GNOME via dconf                                          |
| `make syncthing` | Configure les folders Syncthing (peers + folders versionnés)                   |
| `make system`    | Config système : wake-on-lan, pare-feu, snapper (sudo automatique)             |
| `make ssh`       | Génère une clé SSH ed25519 si absente et affiche la clé publique               |
| `make backup`    | Sauvegarde les données personnelles sur le NAS via rsync                       |
| `make restore`   | Restaure les données personnelles depuis le NAS                                |
| `make update`    | Snapshot des settings GNOME → gnome/dconf-backup.ini                           |
| `make check`     | Vérifie que les dépendances système sont présentes                             |

## Structure

```
dotfiles/
├── Makefile                # Point d'entrée
├── modules/                # Un script bash par étape
├── systemd/
│   ├── system/             # Units systemd système
│   │   └── wake-on-lan.service
│   └── user/               # Templates units user (générés à l'install)
│       ├── nas.mount.tpl
│       └── nas.automount.tpl
├── dotfiles/               # Configs perso (GNU Stow)
│   ├── fish/   → ~/.config/fish/
│   ├── zsh/    → ~/.zshrc
│   ├── git/    → ~/.gitconfig
│   ├── environment/ → ~/.config/environment.d/
│   ├── profile/ → ~/.profile
│   ├── systemd/ → ~/.config/systemd/user/
│   ├── ssh/    → ~/.ssh/config
│   ├── mimeapps/ → ~/.config/mimeapps.list
│   └── bin/    → ~/.local/share/bin/
├── hooks/                  # Hooks pacman (copiés par make system)
├── packages/
│   ├── pacman.txt          # Paquets natifs
│   ├── aur.txt             # Paquets AUR
│   ├── flatpak.txt         # Apps Flatpak
│   └── groups/             # Groupes optionnels avec prompt interactif
│       ├── obs.conf        # OBS Studio (AUR + Flatpak)
│       └── gaming.conf     # Gaming : Steam, protonup-qt, steamtinkerlaunch
├── local.conf.example      # Template de config machine (copier en local.conf)
└── gnome/
    └── dconf-backup.ini    # Settings GNOME (whitelist : thème, extensions, clavier…)
```

## Configuration locale

Copier `local.conf.example` en `local.conf` et adapter les valeurs à la machine :

```bash
cp local.conf.example local.conf
```

`local.conf` est **obligatoire** pour les targets `packages`, `backup`, `restore`, `system` et `syncthing`.

## Mount NAS (`~/nas`)

`make dotfiles` génère automatiquement une unit systemd user qui monte le NAS via
SSHFS sur `~/nas` (automount, démontage après 5 min d'inactivité). La clé
`~/.ssh/id_ed25519` doit être autorisée sur le NAS.

## Dotfiles (GNU Stow)

Pour redéployer manuellement :
```bash
cd ~/dev/dotfiles/dotfiles
stow --target="$HOME" fish zsh git environment profile
```

## Syncthing

Les folders partagés sont déclarés dans `syncthing.conf` (versionné, identique
sur toutes les machines) au format `id|label|path|type`. Les peers distants
(`SYNC_INTRODUCERS`) sont déclarés par machine dans `local.conf`.

`make syncthing` démarre le service, affiche le device ID local, puis ajoute les
peers et folders de manière idempotente. La première fois, il faut **autoriser le
device ID affiché** sur le peer distant pour activer la connexion ; ensuite les
folders partagés sont acceptés automatiquement.

> **KeePass** : fermer KeePassXC avant de changer de machine pour éviter les conflits de sync.

## Snapshots Snapper

Chaque opération pacman crée automatiquement un snapshot avant et après (via hooks).

```bash
snapper -c root list                    # lister les snapshots
sudo snapper -c root undochange N..0   # rollback depuis le snapshot N
```

## Maintenance

Avant une réinstallation, sauvegarder les settings GNOME :

```bash
make update   # snapshot dconf → gnome/dconf-backup.ini
git add -A && git commit -m "update gnome settings" && git push
```

## Vérifications

```bash
make check              # dépendances système
make lint               # shellcheck sur modules/*.sh
make -n install         # dry-run : affiche ce que ferait make install sans exécuter
DRY_RUN=1 make backup   # rsync en dry-run, sans transfert
```