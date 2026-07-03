#!/usr/bin/env bash
# =============================================================================
# setup-ssl.sh — Obtain Let's Encrypt Wildcard Certificates
# =============================================================================
# Called by deploy.sh --ssl  or  run manually after DNS is configured.
#
# Usage:
#   bash scripts/install/setup-ssl.sh <domain>
#
# Requirements:
#   - certbot installed (done by install.sh)
#   - DNS A records pointing to this server:
#       yourerp.com           → <server-ip>
#       *.yourerp.com         → <server-ip>
#   - Ports 80 and 443 open in UFW
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

DOMAIN="${1:-}"
[[ -z "${DOMAIN}" ]] && { set -a; source "${REPO_ROOT}/.env"; set +a; DOMAIN="${DOMAIN:-}"; }
[[ -z "${DOMAIN}" ]] && error "Usage: $0 <domain>"

SSL_DIR="${REPO_ROOT}/ssl"
mkdir -p "${SSL_DIR}"

# ── Check if cert already exists and is valid ─────────────────────────────────
if certbot certificates --domain "${DOMAIN}" 2>/dev/null | grep -q "VALID"; then
    success "Certificate for ${DOMAIN} is already valid."
    info "Renewing certificate..."
    certbot renew --quiet --non-interactive
    success "Certificate renewed."
else
    info "Requesting certificate for ${DOMAIN} and *.${DOMAIN}..."
    info "This requires DNS validation. You will be prompted to create a TXT record."

    certbot certonly \
        --manual \
        --preferred-challenges dns \
        --agree-tos \
        --no-eff-email \
        -d "${DOMAIN}" \
        -d "*.${DOMAIN}"
fi

# ── Link certificates to the ssl/ directory expected by nginx ─────────────────
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"
ln -sfn "${CERT_PATH}" "${SSL_DIR}/live"

success "Certificates linked to ${SSL_DIR}/live/"

# ── Uncomment HTTPS server blocks in nginx templates ─────────────────────────
TEMPLATE_DIR="${REPO_ROOT}/config/nginx/templates"
for f in "${TEMPLATE_DIR}"/*.template; do
    # Uncomment SSL server block (lines between # server { ... # })
    sed -i 's/^# //' "${f}" 2>/dev/null || true
done

info "Nginx templates updated. Reloading nginx..."
docker exec erp-nginx nginx -t && docker exec erp-nginx nginx -s reload

success "SSL configured. Your site is now available at https://${DOMAIN}"

# ── Set up auto-renewal via cron ──────────────────────────────────────────────
CRON_JOB="0 3 * * * certbot renew --quiet --post-hook 'docker exec erp-nginx nginx -s reload'"
(crontab -l 2>/dev/null | grep -qF "certbot renew") \
    || (crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -

success "Auto-renewal cron job registered."
