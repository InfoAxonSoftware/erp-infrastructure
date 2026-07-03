#!/usr/bin/env bash
# =============================================================================
# install.sh — Fresh Ubuntu 24.04 VPS Setup
# =============================================================================
# Run as root on a brand-new DigitalOcean (or compatible) Ubuntu 24.04 droplet.
# This script is idempotent: re-running it is safe.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yourorg/erp-infrastructure/main/scripts/install.sh | sudo bash
#   — or —
#   sudo bash scripts/install.sh
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "This script must be run as root. Use: sudo bash $0"

# ── Configuration ─────────────────────────────────────────────────────────────
DEPLOY_USER="${DEPLOY_USER:-erp}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/erp}"
SSH_PORT="${SSH_PORT:-22}"

# =============================================================================
info "Step 1/9 — System update"
# =============================================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q \
    curl wget git unzip gnupg ca-certificates lsb-release \
    htop iotop ncdu ufw fail2ban logrotate \
    apt-transport-https software-properties-common

# =============================================================================
info "Step 2/9 — Install Docker Engine"
# =============================================================================
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    success "Docker installed: $(docker --version)"
else
    success "Docker already installed: $(docker --version)"
fi

# =============================================================================
info "Step 3/9 — Create deploy user: ${DEPLOY_USER}"
# =============================================================================
if ! id "${DEPLOY_USER}" &>/dev/null; then
    useradd -m -s /bin/bash -G docker,sudo "${DEPLOY_USER}"
    success "User '${DEPLOY_USER}' created and added to docker + sudo groups."
else
    usermod -aG docker,sudo "${DEPLOY_USER}" 2>/dev/null || true
    success "User '${DEPLOY_USER}' already exists — groups updated."
fi

# Set up SSH for deploy user (copy root's authorized_keys if present)
DEPLOY_HOME="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
if [[ -f /root/.ssh/authorized_keys ]] && [[ ! -f "${DEPLOY_HOME}/.ssh/authorized_keys" ]]; then
    mkdir -p "${DEPLOY_HOME}/.ssh"
    cp /root/.ssh/authorized_keys "${DEPLOY_HOME}/.ssh/authorized_keys"
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
    chmod 700 "${DEPLOY_HOME}/.ssh"
    chmod 600 "${DEPLOY_HOME}/.ssh/authorized_keys"
    success "Copied root SSH authorized_keys to '${DEPLOY_USER}'."
fi

# =============================================================================
info "Step 4/9 — Create directory structure"
# =============================================================================
mkdir -p "${DEPLOY_DIR}"/{backups,logs/{nginx,odoo},ssl}
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_DIR}"
success "Deploy directory: ${DEPLOY_DIR}"

# =============================================================================
info "Step 5/9 — Configure UFW firewall"
# =============================================================================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 80/tcp   comment 'HTTP'
ufw allow 443/tcp  comment 'HTTPS'

# Docker internal networks (do NOT expose Odoo/Postgres ports directly)
ufw deny 5432/tcp  comment 'Block direct PostgreSQL access'
ufw deny 8069/tcp  comment 'Block direct Odoo access'

ufw --force enable
ufw status verbose
success "UFW firewall configured."

# =============================================================================
info "Step 6/9 — Configure Fail2Ban"
# =============================================================================
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /opt/erp/logs/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /opt/erp/logs/nginx/error.log
maxretry = 10
findtime = 60
bantime  = 600
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban
success "Fail2Ban configured and started."

# =============================================================================
info "Step 7/9 — SSH hardening"
# =============================================================================
SSHD_CONFIG=/etc/ssh/sshd_config

# Back up original
cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak.$(date +%Y%m%d)"

# Apply hardened settings
declare -A SSH_SETTINGS=(
    [PermitRootLogin]="prohibit-password"
    [PasswordAuthentication]="no"
    [PubkeyAuthentication]="yes"
    [X11Forwarding]="no"
    [MaxAuthTries]="3"
    [LoginGraceTime]="30"
    [ClientAliveInterval]="300"
    [ClientAliveCountMax]="2"
    [AllowTcpForwarding]="no"
    [PermitEmptyPasswords]="no"
)

for key in "${!SSH_SETTINGS[@]}"; do
    value="${SSH_SETTINGS[$key]}"
    if grep -q "^#*${key}" "${SSHD_CONFIG}"; then
        sed -i "s|^#*${key}.*|${key} ${value}|" "${SSHD_CONFIG}"
    else
        echo "${key} ${value}" >> "${SSHD_CONFIG}"
    fi
done

sshd -t && systemctl reload sshd
success "SSH hardened. Root password login disabled."

# =============================================================================
info "Step 8/9 — System performance tuning"
# =============================================================================
cat >> /etc/sysctl.conf <<'EOF'

# ERP Infrastructure tuning
net.core.somaxconn            = 65535
net.ipv4.tcp_max_syn_backlog  = 65535
net.ipv4.ip_local_port_range  = 1024 65535
net.ipv4.tcp_tw_reuse         = 1
vm.swappiness                 = 10
vm.overcommit_memory          = 1
fs.file-max                   = 1000000
EOF

sysctl -p &>/dev/null
success "Kernel parameters tuned."

# Increase file descriptor limits
cat >> /etc/security/limits.conf <<'EOF'
*    soft nofile 65535
*    hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# =============================================================================
info "Step 9/9 — Install certbot (Let's Encrypt)"
# =============================================================================
if ! command -v certbot &>/dev/null; then
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
    success "Certbot installed."
else
    success "Certbot already installed."
fi

# =============================================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Server setup complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo "  1. Clone the repository:"
echo "       git clone https://github.com/yourorg/erp-infrastructure.git ${DEPLOY_DIR}/repo"
echo ""
echo "  2. Configure environment:"
echo "       cd ${DEPLOY_DIR}/repo"
echo "       cp .env.example .env"
echo "       nano .env  # Set DOMAIN, POSTGRES_PASSWORD, ODOO_ADMIN_PASSWORD"
echo ""
echo "  3. Deploy:"
echo "       bash scripts/deploy.sh"
echo ""
echo "  WARNING: Ensure your DNS records point to this server's IP before"
echo "           requesting SSL certificates."
echo ""
