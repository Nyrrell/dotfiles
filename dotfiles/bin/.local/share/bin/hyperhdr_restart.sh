#!/usr/bin/env bash
SERVICE="hyperhdr.service"
API="http://localhost:8090/json-rpc"

if systemctl --user is-active --quiet "$SERVICE"; then
    notify-send -u low -i camera-video "HyperHDR" "Redémarrage de l'instance..."
    # Toggle SYSTEMGRABBER pour forcer le rechargement de la config sans redémarrer le service
    curl -sX POST -H "Content-Type: application/json" \
        -d '{"command":"componentstate","componentstate":{"component":"SYSTEMGRABBER","state":false}}' \
        "$API" > /dev/null
    curl -sX POST -H "Content-Type: application/json" \
        -d '{"command":"componentstate","componentstate":{"component":"SYSTEMGRABBER","state":true}}' \
        "$API" > /dev/null
else
    notify-send -u normal -i camera-video "HyperHDR" "Démarrage du service..."
    systemctl --user start "$SERVICE"
fi