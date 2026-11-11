# Keychron

Exports de configuration des claviers Keychron (keymap, réglages HE…), faits
depuis le Keychron Launcher (https://launcher.keychron.com) en filaire.

- `k2-he.json` — Keychron K2 HE

L'import est manuel : Launcher → Keymap → Import. À refaire après une mise à
jour du firmware ou un reset (Échap maintenu au branchement = reset usine).

Accès au clavier depuis Chromium : règle `udev/50-keychron.rules`, installée par
`make system` (`ENABLE_KEYCHRON=yes` dans local.conf).
