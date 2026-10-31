#!/bin/bash

# Autostart applications
## Notification daemon
pkill -x swaync 2>/dev/null || true
swaync &

## Status bar
pkill -x waybar 2>/dev/null || true
sleep 1

WAYBAR_DIR="$HOME/.config/sway/waybar"
WAYBAR_LOG="$HOME/.cache/waybar.log"

mkdir -p "$HOME/.cache"

if [[ -f "$WAYBAR_DIR/config" && -f "$WAYBAR_DIR/style.css" ]]; then
    waybar \
        -c "$WAYBAR_DIR/config" \
        -s "$WAYBAR_DIR/style.css" \
        > "$WAYBAR_LOG" 2>&1 &
else
    echo "Waybar config or stylesheet missing." >> "$WAYBAR_LOG"
fi

## System tray / polkit
lxpolkit &

## Clipboard history watcher
wl-paste --watch cliphist store &

## systemd / D-Bus environment for portals
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
systemctl --user start xdg-desktop-portal-wlr

## GTK / GNOME Interface Preferences
gnome_schema="org.gnome.desktop.interface"
gsettings set "$gnome_schema" gtk-theme 'Adwaita'
gsettings set "$gnome_schema" icon-theme 'Adwaita'
gsettings set "$gnome_schema" cursor-theme 'Adwaita'
gsettings set "$gnome_schema" font-name 'Adwaita Sans Regular 11'
gsettings set "$gnome_schema" color-scheme 'prefer-dark'

# First-login welcome (shown once, dismissable)
if [ ! -f "$HOME/.cache/sway/welcomed" ]; then
	mkdir -p "$HOME/.cache/sway"
	touch "$HOME/.cache/sway/welcomed"
	(sleep 3; notify-send -u normal -t 15000 \
		"Welcome to Sway" \
		"Press Super + / anytime to see all keybindings.&#10;See ~/QUICKSTART-sway.md for a cheat sheet.&#10;NVIDIA users: run ~/nvidia-setup.sh if needed.") &
fi
