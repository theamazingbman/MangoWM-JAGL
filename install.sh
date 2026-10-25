#!/bin/bash

# Sway Setup Installer (Fedora Refactor)
# Based on JustAGuy Linux DWM Setup

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
CONFIG_DIR="$HOME/.config/sway"
TEMP_DIR="/tmp/sway_$$"
LOG_FILE="$HOME/sway-install.log"

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


# System validation for Fedora
if [ "$ONLY_CONFIG" = false ]; then
    . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release to verify OS"
    case " $ID ${ID_LIKE:-} " in
        *" fedora "*) ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. This refactored installer requires a Fedora Workstation or Spin base." ;;
    esac
fi

# Banner
clear
echo -e "${CYAN}"
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " |S|w|a|y| |S|e|t|u|p|    | "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " |W|a|y|l|a|n|d| |W|M|    | "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+ "
echo -e "${NC}\n"

read -p "Install Sway on Fedora? (y/n) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

# Setup Repositories and System Updates
if [ "$ONLY_CONFIG" = false ]; then
    # 1. Install RPM Fusion Repositories
    msg "Installing RPM Fusion (Free and Non-Free)..."
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        FEDORA_VERSION=$(rpm -E %fedora)
        sudo dnf install -y \
            "https://rpmfusion.org{FEDORA_VERSION}.noarch.rpm" \
            "https://rpmfusion.org{FEDORA_VERSION}.noarch.rpm"
    else
        echo "RPM Fusion is already installed."
    fi

    # 3. Update System DNF Repositories
    msg "Updating DNF system..."
    sudo dnf upgrade -y
else
    msg "Skipping repository updates (--only-config mode)"
fi

# Package groups reorganized for Fedora native repositories
PACKAGES_CORE=(
    sway swayidle swaybg waybar
    xorg-x11-server-Xwayland
)

PACKAGES_SWAY=(
    wmenu foot swaync fuzzel
    grim slurp wl-clipboard cliphist
    brightnessctl playerctl
    wlr-randr
    xdg-desktop-portal-wlr swappy wtype
)

PACKAGES_UI=(
    xsettingsd NetworkManager-tui lxpolkit
)

PACKAGES_FILE_MANAGER=(
    nautilus gvfs-smb gvfs-mtp dialog mtools unzip
)

PACKAGES_AUDIO=(
    pavucontrol pamixer pipewire-utils
)

PACKAGES_UTILITIES=(
    avahi acpi acpid upower power-profiles-daemon
    fd-find xdg-user-dirs-gtk
    kanshi eog
    gawk
    libnotify libnotify-devel libusb btop
)

PACKAGES_BUILD=(
    cmake meson ninja-build curl pkgconfig wget
)

PACKAGES_FONTS=(
    google-noto-color-emoji-fonts fontawesome-fonts
)

# Install packages by group
if [ "$ONLY_CONFIG" = false ]; then
    # Group development-tools installer fallback for build-essential
    msg "Installing base development group..."
    sudo dnf install -y @development-tools || die "Failed to install core build systems"

    msg "Installing core Sway packages..."
    sudo dnf install -y "${PACKAGES_CORE[@]}" || die "Failed to install core packages"

    msg "Installing Sway components..."
    sudo dnf install -y "${PACKAGES_SWAY[@]}" || die "Failed to install Sway packages"

    msg "Installing UI components..."
    sudo dnf install -y "${PACKAGES_UI[@]}" || die "Failed to install UI packages"

    msg "Installing file manager..."
    sudo dnf install -y "${PACKAGES_FILE_MANAGER[@]}" || die "Failed to install file manager"

    msg "Installing audio support..."
    sudo dnf install -y "${PACKAGES_AUDIO[@]}" || die "Failed to install audio packages"

    msg "Installing build tools..."
    sudo dnf install -y "${PACKAGES_BUILD[@]}" || die "Failed to install build tools"

    msg "Installing system utilities..."
    sudo dnf install -y --allowerasing "${PACKAGES_UTILITIES[@]}" || die "Failed to install utilities"

    msg "Installing default browser..."
    sudo dnf install -y firefox || msg "Note: firefox package execution skipped..."

    msg "Installing fonts..."
    sudo dnf install -y "${PACKAGES_FONTS[@]}" || die "Failed to install fonts"

    # 4. Swap to Full Multimedia Codecs (RPM Fusion)
    msg "Configuring Full Multimedia Codecs..."
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo dnf install -y gstreamer1-plugins-ugly gstreamer1-libav --allowerasing

    # Install Autotiling via Python dependencies natively
    msg "Installing autotiling layout engine via Python pipeline..."
    sudo dnf install -y python3-pip python3-i3ipc
    sudo pip3 install --prefix=/usr autotiling || {
        warn "Global pip block intercepted. Falling back to local standalone file binary install..."
        sudo wget -qO /usr/local/bin/autotiling "https://githubusercontent.com"
        sudo chmod +x /usr/local/bin/autotiling
    }

    # Enable Copr for nwg-look and compile desktop custom styling assets
    mkdir -p "$TEMP_DIR/themes"
    
    msg "Enabling ocsw/sway-extras Copr repository for nwg tools..."
    sudo dnf copr enable -y ocsw/sway-extras
    sudo dnf install -y nwg-look nwg-displays

    msg "Installing Orchis GTK Theme natively..."
    cd "$TEMP_DIR/themes"
    git clone --depth 1 https://github.com
    cd Orchis-theme
    ./install.sh -t all -s compact --dest "$HOME/.themes" || warn "Orchis theme extraction skipped"

    msg "Installing Colloid Icon Theme natively..."
    cd "$TEMP_DIR/themes"
    git clone --depth 1 https://github.com
    cd Colloid-icon-theme
    ./install.sh -t all --dest "$HOME/.icons" || warn "Colloid icon extraction skipped"
    
    # Return to script root context
    cd "$SCRIPT_DIR"

    # Enable Fedora services
    sudo systemctl enable avahi-daemon acpid
else
    msg "Skipping package installation (--only-config mode)"
fi

# Configure Adwaita-Dark GTK Theme
msg "Configuring Adwaita-Dark GTK theme..."
if [ "$ONLY_CONFIG" = false ]; then
    # Ensure Fedora's native adwaita theme engines are explicitly installed
    sudo dnf install -y adwaita-gtk2-theme adwaita-icon-theme dconf
fi

# Force system to use dark preference across GTK environments
msg "Setting theme preferences to Adwaita-dark..."
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

# Set GTK 3 Theme Default
cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF

# Set GTK 4 Theme Default
cat <<EOF > "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF

# Set global portal preference for Flatpaks (like Zed or Brave)
mkdir -p "$HOME/.config/xdg-desktop-portal"
cat <<EOF > "$HOME/.config/xdg-desktop-portal/settings.ini"
[org.freedesktop.appearance]
color-scheme=1
EOF

# Apply via dconf settings so background daemons capture it instantly
if command -v dconf &> /dev/null; then
    dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
    dconf write /org/gnome/desktop/interface/icon-theme "'Adwaita'"
fi

# Handle existing config
if [ -d "$CONFIG_DIR" ]; then
    clear
    read -p "Found existing Sway config. Backup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%s)"
        msg "Backed up existing config"
    else
        clear
        read -p "Overwrite without backup? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || die "Installation cancelled"
        rm -rf "$CONFIG_DIR"
    fi
fi

# Copy configs
msg "Setting up configuration..."
mkdir -p "$CONFIG_DIR"
cp -r "$SCRIPT_DIR"/config/* "$CONFIG_DIR"/ || die "Failed to copy configs"

# foot configurations symlinking
if [ -e ~/.config/foot ] && [ "$(readlink -f ~/.config/foot)" != "$(readlink -f "$CONFIG_DIR/foot")" ]; then
    mv ~/.config/foot ~/.config/foot.bak."$(date +%s)"
    msg "Backed up existing ~/.config/foot"
fi
ln -sfn "$CONFIG_DIR/foot" ~/.config/foot

# Ensure default directory handler associations target Nautilus over old setups
msg "Setting Nautilus as the default system directory explorer..."
xdg-mime default org.gnome.Nautilus.desktop inode/directory || warn "Failed to verify fallback xdg mime types"

# Drop old layouts references if left behind
if [ -L ~/.config/gtklock ] && [ "$(readlink ~/.config/gtklock)" = ~/.config/sway/gtklock ]; then
    rm ~/.config/gtklock
fi

# Setup default theme references
ln -sfn themes/github_dark "$CONFIG_DIR/current-theme"

# Setup default user structures
xdg-user-dirs-update
mkdir -p ~/Screenshots

if [ -f "$SCRIPT_DIR/QUICKSTART.md" ]; then
    cp "$SCRIPT_DIR/QUICKSTART.md" "$HOME/QUICKSTART-sway.md"
fi

if [ -f "$SCRIPT_DIR/nvidia-setup.sh" ]; then
    cp "$SCRIPT_DIR/nvidia-setup.sh" "$HOME/nvidia-setup.sh"
    chmod +x "$HOME/nvidia-setup.sh"
fi

# 2. Install Brave Browser (Origin) & 5. Flatpak Ecosystem
if [ "$ONLY_CONFIG" = false ]; then
    msg "Installing Brave Browser (Origin Mode)..."
    curl -fsS https://brave.com | FLAVOR=origin sh

msg "Configuring Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org || true
    flatpak update --appstream

    if [ -f "flatpak_packages.txt" ]; then
        msg "Installing Flatpak applications..."
        while IFS= read -r app || [ -n "$app" ]; do
            [[ -z "$app" || "$app" =~ ^# ]] && continue
            echo "Installing Flatpak: $app"
            flatpak install flathub "$app" -y --noninteractive || echo "Failed to install $app, skipping..."
        done < flatpak_packages.txt
    else
        warn "flatpak_packages.txt not found. Skipping Flatpak app installs."
    fi
fi

msg "Sway script environment updated for Fedora successfully!"
exit 0
