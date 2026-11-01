#!/usr/bin/env bash

if nmcli -t -f TYPE connection show --active 2>/dev/null |
    grep -Eq '^(vpn|wireguard)$'; then

    echo '{"text":"VPN","class":"connected","tooltip":"VPN connected"}'
else
    echo '{"text":"","class":"disconnected","tooltip":"VPN disconnected"}'
fi
