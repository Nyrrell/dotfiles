# Auto-généré par dotfiles — fallback WAN pour le NAS.
# Si @NAS_HOST@ est injoignable sur le port 22 LAN, on bascule vers @NAS_WAN_HOST@:@NAS_WAN_PORT@.
Match host @NAS_HOST@ exec "! timeout 1 bash -c '</dev/tcp/%h/22' 2>/dev/null"
    HostName @NAS_WAN_HOST@
    Port @NAS_WAN_PORT@
