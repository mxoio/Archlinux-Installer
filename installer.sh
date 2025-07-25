#!/bin/bash

# Automated Arch Linux Installation Script with KDE Plasma
# For networking and system administration development
# Run this script from the Arch Linux live environment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Configuration variables (modify these as needed)
TIMEZONE="Europe/London"  # Change to your timezone
LOCALE="en_US.UTF-8"
KEYMAP="us"
HOSTNAME="arch-dev"
USERNAME="developer"
MAIN_DRIVE="/dev/sda"  # Change to your main drive (check with lsblk)

log "Starting Automated Arch Linux Installation"
log "Target drive: $MAIN_DRIVE"
warn "This will WIPE ALL DATA on $MAIN_DRIVE"
echo "Press Enter to continue or Ctrl+C to abort..."
read

# Update system clock
log "Updating system clock..."
timedatectl set-ntp true

# Connect to WiFi
log "Setting up WiFi connection..."
wifi_setup() {
    # Enable wireless interface
    ip link set wlan0 up 2>/dev/null || true
    
    # Scan for networks
    log "Scanning for WiFi networks..."
    iwctl station wlan0 scan
    sleep 3
    
    # List available networks
    echo -e "${BLUE}Available networks:${NC}"
    iwctl station wlan0 get-networks
    
    # Get WiFi credentials
    echo -n "Enter WiFi network name (SSID): "
    read WIFI_SSID
    echo -n "Enter WiFi password: "
    read -s WIFI_PASSWORD
    echo
    
    # Connect to WiFi
    log "Connecting to $WIFI_SSID..."
    iwctl --passphrase "$WIFI_PASSWORD" station wlan0 connect "$WIFI_SSID"
    sleep 5
    
    # Test connection
    if ping -c 3 archlinux.org &>/dev/null; then
        log "WiFi connection successful!"
    else
        error "WiFi connection failed!"
    fi
}

# Check if we have internet, if not setup WiFi
if ! ping -c 1 archlinux.org &>/dev/null; then
    wifi_setup
else
    log "Internet connection detected"
fi

# Update mirrors for faster downloads
log "Updating pacman mirrors..."
reflector --country GB,DE,NL --age 12 --protocol https --sort rate --timeout 10 --save /etc/pacman.d/mirrorlist || echo "Mirror update failed, using default mirrors"

# Partition the disk
log "Partitioning disk $MAIN_DRIVE..."
parted $MAIN_DRIVE --script mklabel gpt
parted $MAIN_DRIVE --script mkpart ESP fat32 1MiB 512MiB
parted $MAIN_DRIVE --script set 1 esp on
parted $MAIN_DRIVE --script mkpart primary ext4 512MiB 100%

# Format partitions
log "Formatting partitions..."
mkfs.fat -F32 ${MAIN_DRIVE}1
mkfs.ext4 ${MAIN_DRIVE}2

# Mount partitions
log "Mounting partitions..."
mount ${MAIN_DRIVE}2 /mnt
mkdir -p /mnt/boot
mount ${MAIN_DRIVE}1 /mnt/boot

# Install base system
log "Installing base system..."
pacstrap /mnt base linux linux-firmware base-devel

# Generate fstab
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Create chroot configuration script
log "Creating chroot configuration script..."
cat > /mnt/chroot_config.sh << 'CHROOT_EOF'
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/TIMEZONE_PLACEHOLDER /etc/localtime
hwclock --systohc

# Set locale
echo "LOCALE_PLACEHOLDER UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=LOCALE_PLACEHOLDER" > /etc/locale.conf

# Set keymap
echo "KEYMAP=KEYMAP_PLACEHOLDER" > /etc/vconsole.conf

# Set hostname
echo "HOSTNAME_PLACEHOLDER" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	HOSTNAME_PLACEHOLDER.localdomain	HOSTNAME_PLACEHOLDER
EOF

# Install essential packages
pacman -S --noconfirm grub efibootmgr networkmanager network-manager-applet \
    wireless_tools wpa_supplicant dialog os-prober mtools dosfstools \
    reflector git curl wget vim nano sudo zsh fish tmux htop neofetch \
    firefox chromium code nodejs npm python python-pip docker docker-compose \
    wireshark-qt nmap tcpdump netcat traceroute iperf3 openssh \
    plasma-meta kde-applications sddm sddm-kcm packagekit-qt5

# Enable services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable docker

# Configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Create user
useradd -m -G wheel,docker,wireshark -s /bin/zsh USERNAME_PLACEHOLDER
echo "Set password for USERNAME_PLACEHOLDER:"
passwd USERNAME_PLACEHOLDER

# Configure sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Set root password
echo "Set root password:"
passwd

# Configure SDDM theme
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/kde_settings.conf << EOF
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze

[Users]
MaximumUid=60000
MinimumUid=1000
EOF

echo "Chroot configuration completed!"
CHROOT_EOF

# Replace placeholders in chroot script
sed -i "s/TIMEZONE_PLACEHOLDER/$TIMEZONE/g" /mnt/chroot_config.sh
sed -i "s/LOCALE_PLACEHOLDER/$LOCALE/g" /mnt/chroot_config.sh
sed -i "s/KEYMAP_PLACEHOLDER/$KEYMAP/g" /mnt/chroot_config.sh
sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /mnt/chroot_config.sh
sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" /mnt/chroot_config.sh

# Make script executable
chmod +x /mnt/chroot_config.sh

# Run chroot configuration
log "Entering chroot environment..."
arch-chroot /mnt ./chroot_config.sh

# Create post-installation script for user
log "Creating post-installation script..."
cat > /mnt/home/$USERNAME/post_install.sh << 'POST_EOF'
#!/bin/bash

# Install AUR helper (yay)
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ~

# Install additional AUR packages
yay -S --noconfirm visual-studio-code-bin discord slack-desktop \
    google-chrome postman-bin wireshark-qt nerd-fonts-complete

# Configure Git (you'll need to set your own values)
echo "Configure Git with your details:"
echo 'git config --global user.name "Your Name"'
echo 'git config --global user.email "your.email@example.com"'

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install useful zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Configure .zshrc
cat > ~/.zshrc << 'ZSH_EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git docker docker-compose npm node python pip sudo zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# Aliases for networking and sysadmin
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias ports='netstat -tulanp'
alias myip='curl http://ipecho.net/plain; echo'
alias dockerclean='docker system prune -af'
alias sysinfo='inxi -Fxz'
alias diskusage='df -h'
alias meminfo='free -m -l -t'
alias psgrep='ps aux | grep -v grep | grep -i -E'
alias netgrep='netstat -tulanp | grep'
alias path='echo -e ${PATH//:/\\n}'

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"
ZSH_EOF

echo "Post-installation script completed!"
echo "Reboot the system and log in with your user account."
echo "Run this script again after first login to complete AUR package installation."
POST_EOF

# Make post-install script executable
arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/post_install.sh
arch-chroot /mnt chmod +x /home/$USERNAME/post_install.sh

# Create network configuration script
log "Creating network configuration helper..."
cat > /mnt/home/$USERNAME/network_setup.sh << 'NET_EOF'
#!/bin/bash

echo "Network Configuration Helper"
echo "=============================="

# Enable NetworkManager if not already enabled
sudo systemctl enable --now NetworkManager

# Show network interfaces
echo "Available network interfaces:"
ip link show

# WiFi connection helper
echo ""
echo "To connect to WiFi networks, use:"
echo "nmcli device wifi list"
echo "nmcli device wifi connect 'SSID' password 'PASSWORD'"

# Show current connections
echo ""
echo "Current network connections:"
nmcli connection show

echo ""
echo "Network setup helper completed!"
NET_EOF

arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/network_setup.sh
arch-chroot /mnt chmod +x /home/$USERNAME/network_setup.sh

# Cleanup
rm /mnt/chroot_config.sh

# Final message
log "Installation completed successfully!"
echo ""
echo -e "${GREEN}=== Installation Summary ===${NC}"
echo "• Arch Linux installed on $MAIN_DRIVE"
echo "• KDE Plasma desktop environment"
echo "• User: $USERNAME"
echo "• Hostname: $HOSTNAME"
echo "• Timezone: $TIMEZONE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Unmount partitions: umount -R /mnt"
echo "2. Reboot: reboot"
echo "3. After first login, run: ~/post_install.sh"
echo "4. Configure network: ~/network_setup.sh"
echo ""
echo -e "${BLUE}Installed development tools:${NC}"
echo "• VS Code, Git, Docker, Node.js, Python"
echo "• Networking tools: Wireshark, nmap, tcpdump, netcat"
echo "• System admin tools: htop, tmux, zsh with Oh My Zsh"
echo ""
warn "Don't forget to:"
echo "• Set up Git with your credentials"
echo "• Configure SSH keys for GitHub/GitLab"
echo "• Install additional packages as needed"

echo ""
echo "Press Enter to continue with unmounting and reboot preparation..."
read

# Unmount partitions
log "Unmounting partitions..."
umount -R /mnt

log "Ready to reboot! Type 'reboot' when ready."
