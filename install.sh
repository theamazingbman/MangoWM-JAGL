#!/bin/bash

# MangoWC Setup Installer
# Based on JustAGuy Linux Sway Setup

set -e

# Command line options
ONLY_CONFIG=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --only-config)
            ONLY_CONFIG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --only-config      Only copy config files (skip packages)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
KEPT_NEW=()
TEMP_DIR="/tmp/mango_$$"
LOG_FILE="$HOME/mango-install.log"

# Logging and cleanup
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}" >&2; }
msg() { echo -e "${CYAN}$*${NC}"; }


# Package names target Debian 13 (trixie); newer releases (forky/sid) and Ubuntu differ.
# mangowc itself comes from butterrepo: it needs wlroots 0.19 + scenefx 0.4, which
# trixie does not ship, and butterrepo carries all three as .debs.
if [ "$ONLY_CONFIG" = false ]; then
    . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release to verify OS"
    case " $ID ${ID_LIKE:-} " in
        *" ubuntu "*) die "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu-based systems are not supported." ;;
    esac
    DEBIAN_BASE=$(cat /etc/debian_version 2>/dev/null || true)
    case "$DEBIAN_BASE" in
        13|13.*) ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer requires a Debian 13 (trixie) base (found: ${DEBIAN_BASE:-no /etc/debian_version})." ;;
    esac
fi

# Banner
clear 2>/dev/null || true
echo -e "${CYAN}"
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " |M|a|n|g|o| |S|e|t|u|p|  | "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " |W|a|y|l|a|n|d| |W|M|    | "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo -e "${NC}\n"

# Update system
# A machine with no login screen yet (a minimal Debian) needs a reboot at
# the end, not a logout: remembered now, before one gets installed
DM_AT_START=$(systemctl is-active display-manager 2>/dev/null || true)

if [ "$ONLY_CONFIG" = false ]; then
    msg "Updating system..."
    sudo apt-get update && sudo apt-get upgrade -y

    # Add butterrepo for mangowc (+ wlroots 0.19 / scenefx 0.4), quickshell and rofi
    msg "Checking butterrepo..."
    wget -qO- "https://justaguy.dev/drew/butterscripts/raw/branch/main/setup/add_butterrepo.sh" | bash \
        || die "butterrepo could not be set up - see the messages above"

    # Fail here, with the reason, rather than at the first apt install with
    # "Unable to locate package mangowc".
    if ! apt-cache policy mangowc 2>/dev/null | grep -q 'apt.justaguy.dev'; then
        die "apt can't see mangowc in butterrepo. Check /etc/apt/sources.list.d/butterrepo.list, then run 'sudo apt-get update' and look for errors mentioning justaguy.dev"
    fi
else
    msg "Skipping system update (--only-config mode)"
fi

# Package groups for better organization
# awww: animated wallpaper daemon (butterrepo; formerly swww)
PACKAGES_CORE=(
    mangowc xwayland awww
    build-essential
)

# quickshell pulls its qml6 modules in through Recommends
# bluez, pulseaudio-utils, xdg-utils, pkexec and python3 back features
# of the bar (Bluetooth rows, the timer chime, opening links, the
# Tailscale grant, restoring a kept display layout); a full Debian
# usually has them, a minimal one doesn't
PACKAGES_BAR=(
    quickshell rofi dunst libnotify-bin btop
    pamixer playerctl brightnessctl wlsunset power-profiles-daemon
    network-manager-gnome network-manager-config-connectivity-debian qrencode
    bluez pulseaudio-utils xdg-utils pkexec python3
)

PACKAGES_WAYLAND=(
    grim slurp swappy wl-clipboard cliphist
    wlr-randr swayidle wlopm qml6-module-qtquick-effects
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    x11-xserver-utils
)

PACKAGES_UI=(
    # gtk + icon themes (butterrepo: prebuilt vinceliuice selections, see deb-builders)
    orchis-gtk-theme-butter colloid-icon-theme-butter
    nwg-look xsettingsd lxpolkit
)

PACKAGES_FILE_MANAGER=(
    thunar thunar-archive-plugin thunar-volman
    gvfs-backends gvfs-fuse dialog mtools smbclient cifs-utils unzip
)

PACKAGES_AUDIO=(
    pavucontrol pulsemixer pipewire-audio
)

PACKAGES_UTILITIES=(
    avahi-daemon acpi acpid upower
    fd-find xdg-user-dirs-gtk
    loupe fastfetch
    gawk curl wget
)

PACKAGES_FONTS=(
    fonts-recommended fonts-font-awesome fonts-noto-color-emoji
)

# Install packages by group
if [ "$ONLY_CONFIG" = false ]; then
    msg "Installing MangoWC (from butterrepo)..."
    sudo apt-get install -y "${PACKAGES_CORE[@]}" || die "Failed to install core packages"

    msg "Installing bar and desktop shell..."
    sudo apt-get install -y "${PACKAGES_BAR[@]}" || die "Failed to install bar packages"

    msg "Installing Wayland components..."
    sudo apt-get install -y "${PACKAGES_WAYLAND[@]}" || die "Failed to install Wayland packages"

    msg "Installing UI components..."
    sudo apt-get install -y "${PACKAGES_UI[@]}" || die "Failed to install UI packages"

    msg "Installing file manager..."
    sudo apt-get install -y "${PACKAGES_FILE_MANAGER[@]}" || die "Failed to install file manager"

    msg "Installing audio support..."
    sudo apt-get install -y "${PACKAGES_AUDIO[@]}" || die "Failed to install audio packages"

    msg "Installing system utilities..."
    sudo apt-get install -y "${PACKAGES_UTILITIES[@]}" || die "Failed to install utilities"

    sudo apt-get install -y firefox-esr 2>/dev/null || msg "Note: firefox-esr not available, skipping..."

    msg "Installing fonts..."
    sudo apt-get install -y "${PACKAGES_FONTS[@]}" || die "Failed to install fonts"

    # Enable services
    sudo systemctl enable avahi-daemon acpid

    # GPU access. scenefx (mango's renderer) opens the render node directly at
    # startup and has no fallback if that fails. logind normally grants the
    # active session an ACL on it, but that can land a moment after the
    # session starts; the render group makes access unconditional.
    if ! id -nG "$USER" | grep -qw render; then
        msg "Adding $USER to the render group (GPU render node access)..."
        sudo usermod -aG render "$USER"
    fi

    # Seat management. mango talks to the seat through libseat, which prefers
    # a running seatd over logind. With a display manager (lightdm) the seat
    # already belongs to logind, and two seat managers fighting over the GPU
    # leaves mango unable to become DRM master (blank session, then a hung
    # greeter). Nothing here needs seatd; make sure it isn't running.
    if systemctl is-active --quiet seatd 2>/dev/null; then
        warn "seatd is running alongside logind — disabling it (mango uses logind for the seat)"
        sudo systemctl disable --now seatd
    fi
else
    msg "Skipping package installation (--only-config mode)"
fi

# Three folders, by owner (see README, "Making it yours"):
#   $SHARE_DIR   the setup's files: bar, scripts, defaults, templates —
#                replaced wholesale on every update, nothing of yours lives here
#   $CONFIG_DIR  the user's: config.conf, autostart.conf, keybinds.conf,
#                local.conf, env, wallpaper/ — never replaced; the files follow dpkg's
#                conffile rule (updated silently if never edited, otherwise
#                kept with ours beside as FILE.new, said once)
#   $STATE_DIR   generated files (palette, theme.conf, themed dunst, kitty
#                colours) and the settings the bar keeps — survive untouched
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mango"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
mkdir -p "$SHARE_DIR" "$CONFIG_DIR" "$STATE_DIR/shipped"

# An install from before 2026-10 kept everything in $CONFIG_DIR. Move it
# aside whole and carry over what is the user's; the share folder takes
# over the rest.
BACKUP_DIR=""
if [ -d "$CONFIG_DIR/quickshell" ]; then
    BACKUP_DIR="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    while [ -e "$BACKUP_DIR" ]; do BACKUP_DIR="$BACKUP_DIR-1"; done
    msg "Config from before the layout change found - moving it to $BACKUP_DIR and carrying yours over"
    mv "$CONFIG_DIR" "$BACKUP_DIR"
    mkdir -p "$CONFIG_DIR"
    # the user's files, as they were
    for f in keybinds.conf local.conf env; do
        [ -f "$BACKUP_DIR/$f" ] && cp "$BACKUP_DIR/$f" "$CONFIG_DIR/$f"
    done
    [ -d "$BACKUP_DIR/wallpaper" ] && mv "$BACKUP_DIR/wallpaper" "$CONFIG_DIR/wallpaper"
    # generated files and settings go to the state folder
    for f in theme.conf polybar/colors.ini rofi/colors.rasi dunst/dunstrc \
             bar-height bar-scale popup-scale tag-icons mango-gaps mango-effects \
             lock-idle lock-style pomodoro weather-location weather-units \
             launcher-history displays.conf; do
        [ -f "$BACKUP_DIR/$f" ] && [ ! -e "$STATE_DIR/$(basename "$f")" ] && cp "$BACKUP_DIR/$f" "$STATE_DIR/$(basename "$f")"
    done
    [ -f "$BACKUP_DIR/kitty/current-theme.conf" ] && [ ! -e "$STATE_DIR/kitty-theme.conf" ] && cp "$BACKUP_DIR/kitty/current-theme.conf" "$STATE_DIR/kitty-theme.conf"
    # the wallpaper line lived in config.conf before; theme.conf carries it now
    if [ -f "$STATE_DIR/theme.conf" ] && ! grep -q '^exec-once=awww img' "$STATE_DIR/theme.conf"; then
        grep '^exec-once=awww img' "$BACKUP_DIR/config.conf" >> "$STATE_DIR/theme.conf" 2>/dev/null || true
    fi
    # keybinds and env from that layout name the old script paths
    for f in keybinds.conf env; do
        [ -f "$CONFIG_DIR/$f" ] && sed -i 's|\.config/mango/scripts/|.local/share/mango/scripts/|g; s|\.config/mango/quickshell|.local/share/mango/quickshell|g; s|^KITTY_CONFIG_DIRECTORY=.*|KITTY_CONFIG_DIRECTORY=${XDG_DATA_HOME:-$HOME/.local/share}/mango/kitty|' "$CONFIG_DIR/$f"
    done
fi

# The setup's own files: replaced wholesale
msg "Setting up configuration..."
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR"
cp -r "$SCRIPT_DIR"/share/* "$SHARE_DIR"/ || die "Failed to copy the setup's files"
chmod +x "$SHARE_DIR"/scripts/*

# The user's files, dpkg's way. "Never edited" is known from the copy of
# what was shipped last time, kept in the state folder.
for f in config.conf autostart.conf keybinds.conf rules.conf local.conf env; do
    ours="$SCRIPT_DIR/config/$f"; theirs="$CONFIG_DIR/$f"; prev="$STATE_DIR/shipped/$f"
    if [ ! -f "$theirs" ]; then
        cp "$ours" "$theirs"                              # first time: ours
    elif cmp -s "$theirs" "$ours"; then
        :                                                 # identical already
    elif [ -f "$prev" ] && cmp -s "$theirs" "$prev"; then
        cp "$ours" "$theirs"                              # never edited: ours, silently
    elif [ -f "$prev" ] && cmp -s "$ours" "$prev"; then
        :                                                 # edited, ours unchanged: theirs
    elif [ -f "$theirs.new" ] && cmp -s "$theirs.new" "$ours"; then
        :                                                 # same .new as last time, said already
    else
        cp "$ours" "$theirs.new"                          # edited and ours changed: theirs stays
        KEPT_NEW+=("$f")
    fi
done
if [ ${#KEPT_NEW[@]} -gt 0 ]; then
    msg "Kept your ${KEPT_NEW[*]}; the new defaults are beside as .new"
fi
# remember what was shipped this time (see above)
cp "$SCRIPT_DIR"/config/{config.conf,autostart.conf,keybinds.conf,rules.conf,local.conf,env} "$STATE_DIR/shipped/"
# and where it came from, for scripts/setup-update (the command menu's
# "Update setup"); a zip download has no record and the entry says so
if git -C "$SCRIPT_DIR" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$SCRIPT_DIR" rev-parse HEAD > "$STATE_DIR/shipped/commit"
    git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD > "$STATE_DIR/shipped/branch"
    git -C "$SCRIPT_DIR" remote get-url origin > "$STATE_DIR/shipped/remote" 2>/dev/null || echo "" > "$STATE_DIR/shipped/remote"
    echo "$SCRIPT_DIR" > "$STATE_DIR/shipped/source"
else
    rm -f "$STATE_DIR/shipped/commit" "$STATE_DIR/shipped/branch" "$STATE_DIR/shipped/remote" "$STATE_DIR/shipped/source"
fi
# rules.conf is new in 2026-10; a config.conf kept from before needs to read it
grep -q 'rules\.conf' "$CONFIG_DIR/config.conf" || sed -i '/^source=.*keybinds\.conf/a source=~/.config/mango/rules.conf' "$CONFIG_DIR/config.conf"
# MANGO_STATE_DIR in env is new in 2026-10; an env kept from before needs it
grep -q '^MANGO_STATE_DIR=' "$CONFIG_DIR/env" || printf '\nMANGO_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/mango\n' >> "$CONFIG_DIR/env"

# Generated files: the defaults for the default wallpaper, only where
# nothing exists yet (a wallpaper pick regenerates them all)
for f in "$SCRIPT_DIR"/state/*; do
    [ -e "$STATE_DIR/$(basename "$f")" ] || cp "$f" "$STATE_DIR/"
done
[ -e "$STATE_DIR/dunstrc" ] || cp "$SHARE_DIR/dunst/dunstrc" "$STATE_DIR/dunstrc"

# Session environment ($CONFIG_DIR/env, just copied) is sourced by
# mango-session, the login wrapper the mangowc package's session entry runs
# from 0.14.4-4 on — that's how KITTY_CONFIG_DIRECTORY reaches the terminals
# mango spawns, under any display manager. Older packages start the bare
# binary and ignore the file. The session kitty config itself
# ($SHARE_DIR/kitty, same layout as the dwm/bspwm/openbox setups) came in
# with the config copy above.
MANGO_VER=$(dpkg-query -W -f='${Version}' mangowc 2>/dev/null || true)
if [ -z "$MANGO_VER" ]; then
    [ "$ONLY_CONFIG" = true ] && warn "mangowc is not installed - $CONFIG_DIR/env needs mangowc 0.14.4-4 or newer (butterrepo)"
elif ! dpkg --compare-versions "$MANGO_VER" ge 0.14.4-4; then
    warn "mangowc $MANGO_VER is older than 0.14.4-4: $CONFIG_DIR/env won't be sourced at login (kitty theming stays global) - update mangowc from butterrepo"
fi

# Inside a VM, virtio-gpu renders the hardware cursor upside down or not at
# all. Switch mango to a software cursor via the session env file (the line
# is shipped commented out). Not a supported target, just not broken.
if systemd-detect-virt -q 2>/dev/null; then
    msg "Virtual machine detected ($(systemd-detect-virt)) - enabling software cursor"
    sed -i 's|^#WLR_NO_HARDWARE_CURSORS=1$|WLR_NO_HARDWARE_CURSORS=1|' "$CONFIG_DIR/env"
fi

# dunst is started with -config from defaults.conf; the symlink covers the
# D-Bus-activated case (a notification arriving before autostart ran).
mkdir -p ~/.config/dunst
ln -sfn "$STATE_DIR/dunstrc" ~/.config/dunst/dunstrc
# swappy (screenshot annotate) saves where the other screenshots go; a
# swappy config of the user's own is left alone
if [ ! -e ~/.config/swappy/config ] || [ -L ~/.config/swappy/config ]; then
    mkdir -p ~/.config/swappy
    ln -sfn "$SHARE_DIR/swappy/config" ~/.config/swappy/config
fi

# Setup directories
xdg-user-dirs-update
# thunar handles folders: the bar's wallpaper picker opens one via xdg-open,
# and with no default set it falls to whichever .desktop sorts first
command -v xdg-mime >/dev/null && xdg-mime default thunar.desktop inode/directory
mkdir -p ~/Screenshots

# Drop quickstart cheatsheet in $HOME (user can delete once read)
if [ -f "$SCRIPT_DIR/QUICKSTART.md" ]; then
    cp "$SCRIPT_DIR/QUICKSTART.md" "$HOME/QUICKSTART-mango.md"
fi

# Copy nvidia-setup.sh to $HOME so NVIDIA users can re-run it after install
if [ -f "$SCRIPT_DIR/nvidia-setup.sh" ]; then
    cp "$SCRIPT_DIR/nvidia-setup.sh" "$HOME/nvidia-setup.sh"
    chmod +x "$HOME/nvidia-setup.sh"
fi

# Butterscript helper: get_script <path> [args passed to the script]
get_script() {
    wget -qO- "https://justaguy.dev/drew/butterscripts/raw/branch/main/$1" | bash -s -- "${@:2}"
}

# Install essential components
if [ "$ONLY_CONFIG" = false ]; then
    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"

    # --no-config: the session-local kitty config is vendored in
    # $SHARE_DIR/kitty (like the dwm/bspwm/openbox setups); ~/.config/kitty
    # is left alone
    msg "Installing kitty..."
    get_script "kitty/install_kitty.sh" --no-config \
        || warn "Kitty installation failed - you can install it manually later"

    # the editor Super+E and the keybinds viewer open (config.conf, scripts/keybinds)
    msg "Installing geany..."
    get_script "geany/install_geany.sh" \
        || warn "Geany installation failed - Super+E and editing from the keybinds viewer need an editor called geany"

    msg "Installing fonts..."
    get_script "theming/install_nerdfonts.sh" || warn "Font installation failed - you can install fonts manually later"

    msg "Installing themes..."
    get_script "theming/install_wallpaper_theme.sh" || warn "Theme installation failed - you can install themes manually later"

    msg "Downloading wallpaper directory..."
    if [ ! -d "$CONFIG_DIR/wallpaper" ]; then
        git clone --depth 1 --progress https://github.com/drewgrif/wallpapers.git "$CONFIG_DIR/wallpaper" || die "Failed to clone wallpapers"
        rm -rf "$CONFIG_DIR/wallpaper/.git"
    else
        msg "Wallpaper directory already exists, skipping..."
    fi

    msg "Downloading display manager installer..."
    wget -O "$TEMP_DIR/install_lightdm.sh" "https://justaguy.dev/drew/butterscripts/raw/branch/main/system/install_lightdm.sh"
    chmod +x "$TEMP_DIR/install_lightdm.sh"
    msg "Running display manager installer..."
    # Run in current terminal session to preserve interactivity
    bash "$TEMP_DIR/install_lightdm.sh"

    # NVIDIA setup (auto-detects GPU and drivers)
    # Skip in chroot (no GPU access) or if running as root (e.g., during butterknife install)
    if [ "$EUID" -ne 0 ] && [ ! -f /run/host/container-manager ] && [ -d /sys/class/drm ]; then
        msg "Checking for NVIDIA GPU configuration..."
        bash "$SCRIPT_DIR/nvidia-setup.sh" || warn "NVIDIA setup skipped"
    else
        msg "Skipping NVIDIA setup (chroot or root environment)"
    fi

    # Optional tools
    clear 2>/dev/null || true
    read -p "Install optional tools (browsers, editors, etc)? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        msg "Downloading optional tools installer..."
        wget -O "$TEMP_DIR/optional_tools.sh" "https://justaguy.dev/drew/butterscripts/raw/branch/main/setup/optional_tools.sh"
        chmod +x "$TEMP_DIR/optional_tools.sh"
        msg "Running optional tools installer..."
        if bash "$TEMP_DIR/optional_tools.sh"; then
            msg "Optional tools completed successfully"
        else
            msg "Optional tools exited (this is normal if cancelled by user)"
        fi
    fi
else
    msg "Skipping external tool installation (--only-config mode)"
fi

# Done
echo -e "\n${GREEN}Installation complete!${NC}"
if [ "$DM_AT_START" = active ] || [ "$ONLY_CONFIG" = true ]; then
    echo "1. Log out (fully — the render group applies at next login) and select 'Mango' from your display manager"
    echo "   (no sound or screen sharing afterwards? reboot once: services installed just now start with a fresh login)"
else
    echo "1. Reboot, then select 'Mango' at the login screen"
    echo "   (a reboot, not a logout: the login screen, sound and screen sharing all start with it)"
fi
echo "2. Press Super + / for keybindings"
echo "3. Super + Space for application launcher"
echo "4. Super + Shift + p for the wallpaper picker (re-themes the desktop from the image)"
echo "5. Super + Shift + m for the command menu"
echo "6. See ~/QUICKSTART-mango.md for a quick reference"
echo "To update later: 'Update setup' in the command menu (or cd $SCRIPT_DIR && git pull && ./install.sh)"
echo "Installation log: $LOG_FILE"

# NetworkManager leaves alone any interface Debian's installer wrote into
# /etc/network/interfaces, which a netinst without a desktop does for the
# wired one. The connection works but the bar can't see it. Say so, with
# the fix: changing a machine's network setup is its owner's call.
# The test is narrow on purpose: the interface carrying the default route
# is the one NetworkManager calls unmanaged. A second, unused port listed
# in that file is nobody's problem.
dev=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
if [ -n "$dev" ] \
   && nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -qx "$dev:unmanaged" \
   && grep -qsE "^[[:space:]]*iface[[:space:]]+${dev}[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/*; then
    echo
    warn "Network: $dev is set up in /etc/network/interfaces, so NetworkManager leaves it alone."
    echo "  Your connection works, but the bar's network icon will show offline and the"
    echo "  network app will be empty. To hand a DHCP interface over to NetworkManager:"
    echo "    sudo sed -i -E '/^(auto|allow-hotplug|iface) +$dev( |\$)/ s/^/#/' /etc/network/interfaces"
    echo "    sudo reboot"
    echo "  (a static address you set by hand belongs in NetworkManager first: nmtui)"
fi
