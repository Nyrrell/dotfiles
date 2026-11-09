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
make packages   # paquets pacman + AUR + Flatpak + groupes (OBS, gaming…, choix mémorisé)
make dotfiles   # symlinks via GNU Stow + git user config
make fish       # shell par défaut
make dev        # fnm + Node.js LTS
make gnome      # settings GNOME (dconf)
make syncthing  # peers et folders (nécessite SYNC_INTRODUCERS dans local.conf)
make system     # wake-on-lan, pare-feu, snapper (sudo demandé automatiquement)
make wireguard  # VPN WireGuard facultatif (nécessite WG_ENDPOINT dans local.conf)
```

## Au quotidien

```bash
make save               # sur la machine où tu as modifié quelque chose : export GNOME + commit + push
make sync               # sur l'autre machine : git pull + relance seulement les modules concernés
make add PKG=htop       # ajoute un paquet à la bonne liste (pacman/AUR/Flathub) et l'installe
make add PKG=obs-vkcapture-git GROUP=obs   # … ou à un groupe optionnel
make upgrade            # mise à jour système (paru -Syu + flatpak update)
```

`make sync` compare un hash des entrées de chaque module (listes de paquets,
`dconf-backup.ini`, units systemd, clés de `local.conf`…) à celui enregistré dans
`~/.local/state/dotfiles/` et ne relance que ce qui a changé. `make sync FORCE=1`
relance tout.

Les choix propres à chaque machine (groupes `PACKAGE_GROUPS`, `ENABLE_WOL`,
`ENABLE_UFW`) sont demandés **une seule fois** puis mémorisés dans `local.conf`.

## Targets disponibles

| Commande         | Description                                                                    |
|------------------|--------------------------------------------------------------------------------|
| `make install`   | Installation complète : ssh, packages, dotfiles, dev, GNOME, syncthing, system |
| `make sync`      | `git pull` + relance seulement les modules dont les entrées ont changé         |
| `make save`      | Export GNOME + commit + push                                                   |
| `make add`       | `make add PKG=nom [GROUP=obs]` : ajoute un paquet à la bonne liste et l'installe |
| `make upgrade`   | Mise à jour système (`paru -Syu` + `flatpak update`)                           |
| `make packages`  | Installe paquets pacman + AUR + Flatpak + groupes interactifs (OBS, gaming…)   |
| `make dotfiles`  | Déploie les configs via GNU Stow                                               |
| `make fish`      | Configure Fish comme shell par défaut                                          |
| `make zsh`       | Configure Zsh comme shell par défaut                                           |
| `make dev`       | Installe fnm + Node.js LTS + Corepack                                          |
| `make gnome`     | Restaure les settings GNOME via dconf                                          |
| `make syncthing` | Configure les folders Syncthing (peers + folders versionnés)                   |
| `make system`    | Config système : wake-on-lan, pare-feu, snapper (sudo automatique)             |
| `make wireguard` | VPN WireGuard via NetworkManager, activation manuelle (skip si `WG_ENDPOINT` vide) |
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
│   └── bin/    → ~/.local/share/bin/
├── hooks/                  # Hooks pacman (copiés par make system)
├── packages/
│   ├── pacman.txt          # Paquets natifs
│   ├── aur.txt             # Paquets AUR
│   ├── flatpak.txt         # Apps Flatpak
│   └── groups/             # Groupes optionnels (choix mémorisé par machine dans local.conf)
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

## VPN WireGuard

Facultatif : `make wireguard` ne fait rien tant que `WG_ENDPOINT` est vide dans
`local.conf`. Il crée une connexion NetworkManager **sans autoconnect**, à activer
à la main depuis l'extérieur :

```bash
nmcli connection up Maison     # nmcli connection down Maison pour couper
```

Ne pas l'activer à la maison : `WG_ALLOWED_IPS` contient le LAN (192.168.1.0/24),
qui serait routé dans le tunnel et deviendrait injoignable.

La clé privée n'est jamais dans le dépôt. Sur une nouvelle machine, une clé est
générée et sa clé publique affichée : l'ajouter comme peer sur le serveur, avec
une `WG_ADDRESS` propre à la machine. Pour réutiliser une clé existante, renseigner
`WG_PRIVATE_KEY_FILE`. Si la connexion existe déjà, seuls les paramètres non secrets
sont réappliqués.

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

- **root** : un snapshot avant et après chaque opération pacman (hooks), 10 gardés.
- **home** : timeline horaire, 12 horaires + 7 journaliers gardés (contre les suppressions accidentelles dans `~`).

> Les snapshots sont sur le même disque : ce n'est **pas** un backup (voir `make backup`).

```bash
snapper -c root list                    # lister les snapshots
snapper -c home list
sudo snapper -c root undochange N..0    # annuler les changements depuis le snapshot N (système qui boote)
snapper -c home undochange N..0 ~/Documents/fichier   # restaurer un fichier de ~
```

### Restaurer quand le système ne boote plus

Spécificités de ce setup :
- **systemd-boot, `/boot` sur l'ESP (vfat)** : pas d'entrée « booter un snapshot », et le noyau n'est
  **pas** dans les snapshots → après restauration, il faut réinstaller le noyau correspondant.
- **`subvol=/@` est en dur dans fstab** : `snapper rollback` est sans effet, ne pas l'utiliser.

**0. D'abord** : choisir l'entrée **linux-cachyos-lts** dans le menu systemd-boot. Si c'est le noyau
principal qui casse, ça suffit pour redémarrer et corriger depuis le système.

**Sinon, depuis une clé live CachyOS :**

```bash
# 1. Monter la racine btrfs (top-level)
mount -o subvolid=5 /dev/nvme1n1p2 /mnt

# 2. Choisir le snapshot N (date + description pre-pacman/post-pacman)
grep -h -A1 '<num>\|<date>\|<description>' /mnt/@/.snapshots/*/info.xml

# 3. Mettre l'actuel de côté, recréer @ depuis le snapshot N
mv /mnt/@ /mnt/@broken
btrfs subvolume snapshot /mnt/@broken/.snapshots/N/snapshot /mnt/@
rmdir /mnt/@/.snapshots                     # dossier vide laissé par le snapshot
mv /mnt/@broken/.snapshots /mnt/@/          # récupère l'historique des snapshots

# 4. Remettre le noyau en accord avec le snapshot
umount /mnt
mount -o subvol=/@ /dev/nvme1n1p2 /mnt
mount /dev/nvme1n1p1 /mnt/boot
arch-chroot /mnt
pacman -S linux-cachyos linux-cachyos-nvidia-open
# sans réseau : pacman -U /var/cache/pacman/pkg/linux-cachyos-<version>…  (@cache n'est pas restauré)
exit
reboot

# 5. Quand tout marche : supprimer l'ancien système
mount -o subvolid=5 /dev/nvme1n1p2 /mnt && btrfs subvolume delete /mnt/@broken
```

`/home` (`@home`) n'est pas touché par cette procédure. Les noms de partitions (`nvme1n1p2` = btrfs,
`nvme1n1p1` = ESP) sont ceux de nrl-dev : vérifier avec `lsblk -f` depuis la clé live.

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