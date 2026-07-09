#!/usr/bin/env bash
# =============================================================================
# setup-ssl.sh - Let's Encrypt SSL for the React company website
# =============================================================================
# Obtains/renews HTTP-01 certificates for infoaxon.lk and www.infoaxon.lk only.
# Odoo is intentionally left on temporary direct IP access at port 8069.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENV_FILE="${REPO_ROOT}/.env"
[[ -f "${ENV_FILE}" ]] || error ".env file not found."

set -a
source "${ENV_FILE}"
set +a

DOMAIN="${1:-${DOMAIN:-}}"
[[ -z "${DOMAIN}" ]] && error "Usage: $0 infoaxon.lk"
[[ "${DOMAIN}" == "infoaxon.lk" ]] || error "This deployment only configures SSL for infoaxon.lk and www.infoaxon.lk."

command -v certbot &>/dev/null || error "certbot is not installed. Run scripts/install/install.sh first."
command -v docker &>/dev/null || error "docker is required."

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
else
    command -v sudo &>/dev/null || error "sudo is required to read Let's Encrypt certificates."
    SUDO=(sudo)
fi

COMPOSE_CMD=(docker compose --env-file "${ENV_FILE}" -f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml")
WEBROOT="${REPO_ROOT}/ssl/certbot/www"
NGINX_CERT_DIR="${REPO_ROOT}/ssl/live/${DOMAIN}"
LE_CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"

mkdir -p "${WEBROOT}" "${NGINX_CERT_DIR}"

set_env_value() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "${ENV_FILE}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
    else
        printf '\n%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
    fi
    export "${key}=${value}"
}

copy_certs() {
    [[ -f "${LE_CERT_DIR}/fullchain.pem" ]] || error "Certificate not found at ${LE_CERT_DIR}/fullchain.pem"
    "${SUDO[@]}" install -m 0644 "${LE_CERT_DIR}/fullchain.pem" "${NGINX_CERT_DIR}/fullchain.pem"
    "${SUDO[@]}" install -m 0640 "${LE_CERT_DIR}/privkey.pem" "${NGINX_CERT_DIR}/privkey.pem"
    "${SUDO[@]}" chown "$(id -u):$(id -g)" "${NGINX_CERT_DIR}/fullchain.pem" "${NGINX_CERT_DIR}/privkey.pem" 2>/dev/null || true
}

info "Ensuring Nginx is running with the HTTP challenge webroot..."
set_env_value "NGINX_TEMPLATE_PROFILE" "http"
"${COMPOSE_CMD[@]}" up -d nginx

info "Requesting/renewing HTTP-01 certificate for ${DOMAIN} and www.${DOMAIN}..."
"${SUDO[@]}" certbot certonly \
    --webroot \
    --webroot-path "${WEBROOT}" \
    --cert-name "${DOMAIN}" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    --email "admin@${DOMAIN}" \
    -d "${DOMAIN}" \
    -d "www.${DOMAIN}"

info "Copying certificates into the repository ssl/ directory for the Nginx container..."
copy_certs

info "Enabling HTTPS Nginx template profile..."
set_env_value "NGINX_TEMPLATE_PROFILE" "https"
"${COMPOSE_CMD[@]}" up -d nginx
docker exec erp-nginx nginx -t
docker exec erp-nginx nginx -s reload

HOOK="/etc/letsencrypt/renewal-hooks/deploy/infoaxon-nginx-copy.sh"
info "Installing renewal deploy hook..."
"${SUDO[@]}" mkdir -p "$(dirname "${HOOK}")"
"${SUDO[@]}" tee "${HOOK}" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
install -m 0644 "${LE_CERT_DIR}/fullchain.pem" "${NGINX_CERT_DIR}/fullchain.pem"
install -m 0640 "${LE_CERT_DIR}/privkey.pem" "${NGINX_CERT_DIR}/privkey.pem"
docker exec erp-nginx nginx -t
docker exec erp-nginx nginx -s reload
EOF
"${SUDO[@]}" chmod +x "${HOOK}"

success "SSL configured for https://${DOMAIN} and https://www.${DOMAIN}."
warn "Renewal uses Certbot's normal renewal timer plus the deploy hook above. No wildcard DNS renewal is configured or needed."
