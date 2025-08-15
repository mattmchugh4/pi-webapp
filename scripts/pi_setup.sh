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
    ca-certificates \
    gnupg \
    libraspberrypi-bin

# Enable vnstat idempotently
systemctl enable vnstat
systemctl is-active --quiet vnstat || systemctl start vnstat

# =============================================================================
# Section 2.1: Install Docker Engine + Compose v2 (official repo)
# =============================================================================
log "Installing Docker Engine and Compose v2..."

# Remove Debian docker.io if present to avoid conflicts with Docker's repo
if dpkg -l | grep -q '^ii\s\+docker\.io\b'; then
    apt remove -y docker.io || true
fi

# Ensure keyring directory exists
install -m 0755 -d /etc/apt/keyrings

# Install Docker's official GPG key if missing
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Add Docker apt repository if missing
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
    apt update -y
fi

# Install Docker Engine and plugins (Compose v2 as plugin)
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable --now docker

# Add invoking user to docker group for non-root usage
if id -nG "${SUDO_USER:-}" 2>/dev/null | grep -qw docker; then
    :
else
    USER_TO_ADD="${SUDO_USER:-$(logname 2>/dev/null || echo pi)}"
    if id "$USER_TO_ADD" >/dev/null 2>&1; then
        usermod -aG docker "$USER_TO_ADD" || true
        warn "User '$USER_TO_ADD' added to 'docker' group. Log out and back in for it to take effect."
    fi
fi



# =============================================================================
# Section 3: Configure Fail2ban
# =============================================================================
log "Configuring Fail2ban..."
jail_content=$(cat <<'EOF'
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h
EOF
)

fail2ban_changed=0
if [ -f /etc/fail2ban/jail.local ]; then
    if printf "%s\n" "$jail_content" | cmp -s - /etc/fail2ban/jail.local; then
        log "Fail2ban jail.local already up to date."
    else
        printf "%s\n" "$jail_content" > /etc/fail2ban/jail.local
        log "Updated /etc/fail2ban/jail.local"
        fail2ban_changed=1
    fi
else
    printf "%s\n" "$jail_content" > /etc/fail2ban/jail.local
    log "Created /etc/fail2ban/jail.local"
    fail2ban_changed=1
fi

systemctl enable --now fail2ban
if [ "$fail2ban_changed" -eq 1 ]; then
    systemctl reload fail2ban || systemctl restart fail2ban
fi

# =============================================================================
# Section 4: Configure UFW
# =============================================================================
log "Configuring UFW firewall..."

# Enable only if not already active
if ufw status | grep -q "Status: active"; then
    ufw_active=1
else
    ufw_active=0
fi

# Set defaults only if different (falls back to setting when unknown)
if ufw status verbose 2>/dev/null | grep -i "^Default:" >/dev/null; then
    defaults_line=$(ufw status verbose 2>/dev/null | grep -i "^Default:")
    echo "$defaults_line" | grep -qi "deny (incoming)" || ufw default deny incoming
    echo "$defaults_line" | grep -qi "allow (outgoing)" || ufw default allow outgoing
else
    ufw default deny incoming
    ufw default allow outgoing
fi

# Add SSH rule only if not already present
if ! ufw status | grep -qiE '(^|\b)(22/tcp|ssh)\b.*ALLOW'; then
    ufw allow ssh
fi

if [ "$ufw_active" -eq 0 ]; then
    ufw --force enable
fi

# =============================================================================
# Section 5: SSH Hardening (Safe & Idempotent)
# =============================================================================
if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
    log "Ensuring SSH password authentication is disabled..."
    if grep -Eq '^\s*PasswordAuthentication\s+no\s*$' /etc/ssh/sshd_config; then
        log "PasswordAuthentication already disabled."
    else
        if grep -Eq '^[#[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config; then
            sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        else
            echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
        fi
        systemctl reload sshd
    fi
else
    warn "SSH keys not found — keeping password authentication enabled."
fi

# =============================================================================
# Section 6: System Optimization
# =============================================================================
log "Setting low swappiness..."
sysctl_needs_reload=0

# Ensure vm.swappiness = 10
if grep -Eq '^\s*vm\.swappiness\s*=\s*10\s*$' /etc/sysctl.conf; then
    :
else
    if grep -Eq '^\s*vm\.swappiness\s*=' /etc/sysctl.conf; then
        sed -i 's/^\s*vm\.swappiness\s*=.*/vm.swappiness = 10/' /etc/sysctl.conf
    else
        printf "\n# Added by pi_setup.sh\nvm.swappiness = 10\n" >> /etc/sysctl.conf
    fi
    sysctl_needs_reload=1
fi

# Ensure vm.vfs_cache_pressure = 50
if grep -Eq '^\s*vm\.vfs_cache_pressure\s*=\s*50\s*$' /etc/sysctl.conf; then
    :
else
    if grep -Eq '^\s*vm\.vfs_cache_pressure\s*=' /etc/sysctl.conf; then
        sed -i 's/^\s*vm\.vfs_cache_pressure\s*=.*/vm.vfs_cache_pressure = 50/' /etc/sysctl.conf
    else
        printf "vm.vfs_cache_pressure = 50\n" >> /etc/sysctl.conf
    fi
    sysctl_needs_reload=1
fi

if [ "$sysctl_needs_reload" -eq 1 ]; then
    sysctl -p
else
    sysctl -w vm.swappiness=10 vm.vfs_cache_pressure=50 >/dev/null
fi

# =============================================================================
# Section 7: Swapfile Handling (Avoid Conflicts)
# =============================================================================
log "Checking swap configuration..."
if command -v dphys-swapfile &>/dev/null; then
    sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    systemctl enable --now dphys-swapfile
else
    if [ ! -f /swapfile ]; then
        log "Creating 2GB swapfile..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        # Ensure fstab entry exists
        if ! grep -qE '^/swapfile\s' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    else
        # Ensure correct permissions
        chmod 600 /swapfile
        # Ensure fstab entry exists
        if ! grep -qE '^/swapfile\s' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    fi
    # Ensure swap is active (without duplicating)
    if ! swapon --show | grep -qE '^/swapfile\b'; then
        swapon /swapfile || true
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
