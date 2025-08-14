#!/bin/bash
# Raspberry Pi Setup Script (SSD/SD friendly)
# Run with: sudo bash pi_setup.sh

set -euo pipefail

# =============================================================================
# Colors and Logging Functions
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Safety Check
# =============================================================================
if [ "$(id -u)" -ne 0 ]; then
    error "Run this script with sudo or as root."
fi

# =============================================================================
# Section 1: Update & Upgrade
# =============================================================================
log "Updating and upgrading packages..."
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt full-upgrade -y && apt autoremove -y && apt clean

# =============================================================================
# Section 2: Install Essential System Tools
# =============================================================================
log "Installing essential packages..."

# Network and monitoring tools
apt install -y \
    htop \
    iotop \
    nethogs \
    iftop \
    nload \
    vnstat \
    curl \
    wget \
    git \
    tree \
    tmux \
    screen \
    nano \
    vim \
    unzip \
    zip \
    rsync \
    sshfs \
    fail2ban \
    ufw \
    logwatch \
    procps \
    docker.io \
    docker-compose-plugin \
    libraspberrypi-bin

# Enable vnstat
systemctl enable --now vnstat

# =============================================================================
# Section 3: Configure Fail2ban
# =============================================================================
log "Configuring Fail2ban..."
cat >/etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

# =============================================================================
# Section 4: Configure UFW
# =============================================================================
log "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable

# =============================================================================
# Section 5: SSH Hardening (Safe)
# =============================================================================
if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
    if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
        log "Disabling SSH password authentication..."
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    else
        warn "SSH keys not found — keeping password authentication enabled."
    fi
    systemctl reload sshd
fi

# =============================================================================
# Section 6: System Optimization
# =============================================================================
log "Setting low swappiness..."
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf <<EOF

# Added by pi_setup.sh
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sysctl -p
fi

# =============================================================================
# Section 7: Swapfile Handling (Avoid Conflicts)
# =============================================================================
log "Checking swap configuration..."
if command -v dphys-swapfile &>/dev/null; then
    sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    systemctl restart dphys-swapfile
else
    if [ ! -f /swapfile ]; then
        log "Creating 2GB swapfile..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    else
        log "Swapfile already exists — skipping..."
    fi
fi

# =============================================================================
# Section 8: Install log2ram
# =============================================================================
log "Installing log2ram..."
if ! command -v log2ram &>/dev/null; then
    git clone https://github.com/azlux/log2ram.git /tmp/log2ram
    cd /tmp/log2ram
    chmod +x install.sh
    ./install.sh
    systemctl enable --now log2ram
    cd - >/dev/null
    rm -rf /tmp/log2ram
else
    log "log2ram already installed — skipping..."
fi

# =============================================================================
# Section 10: Summary
# =============================================================================
log "Setup complete!"
echo -e "${GREEN}Your Raspberry Pi is now configured with:${NC}"
echo "- Essential tools installed"
echo "- Firewall (UFW) enabled"
echo "- Fail2ban configured"
echo "- SSH hardened (if keys present)"
echo "- Low swappiness (10) for SSD/SD longevity"
echo "- log2ram active"
echo "- Swap configured safely"
