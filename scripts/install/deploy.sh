#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Full ERP Platform Deployment
# =============================================================================
# Run from the repository root on the VPS after install.sh has been executed.
#
# Usage:
#   bash scripts/install/deploy.sh [--ssl]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENABLE_SSL=false
for arg in "$@"; do
    case "$arg" in
        --ssl) ENABLE_SSL=true ;;
        *) error "Unknown option: $arg" ;;
    esac
done

cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_FILES=(-f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml")
COMPOSE_CMD=(docker compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}")

info "Checking prerequisites..."
command -v docker &>/dev/null || error "Docker is not installed. Run scripts/install/install.sh first."
docker compose version &>/dev/null || error "Docker Compose v2 is required."
command -v git &>/dev/null || error "git is required."

[[ -f "${ENV_FILE}" ]] || error ".env file not found. Copy .env.example to .env and fill in all values."

set -a
source "${ENV_FILE}"
set +a

: "${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD in .env}"
: "${ODOO_ADMIN_PASSWORD:?Missing ODOO_ADMIN_PASSWORD in .env}"
: "${DOMAIN:?Missing DOMAIN in .env}"
: "${REACT_REPO_URL:?Missing REACT_REPO_URL in .env}"
: "${WEBSITE_DB_PASSWORD:?Missing WEBSITE_DB_PASSWORD in .env}"

if [[ "${POSTGRES_PASSWORD}" == "CHANGE_ME" || "${ODOO_ADMIN_PASSWORD}" == "CHANGE_ME" || "${WEBSITE_DB_PASSWORD}" == "CHANGE_ME" ]]; then
    error "Replace CHANGE_ME secrets in .env before deploying."
fi

success "Prerequisites satisfied."

info "Creating required directories..."
mkdir -p \
    "${REPO_ROOT}/logs/nginx" \
    "${REPO_ROOT}/logs/odoo" \
    "${REPO_ROOT}/ssl/certbot/www" \
    "${REPO_ROOT}/ssl/live/${DOMAIN}"

info "Cloning or updating React frontend from: ${REACT_REPO_URL}"
REACT_APP_DIR="${REPO_ROOT}/docker/react/app"

ensure_react_app_git_access() {
    local deploy_uid_gid
    deploy_uid_gid="$(id -u):$(id -g)"

    git config --global --get-all safe.directory | grep -Fxq "${REACT_APP_DIR}" || \
        git config --global --add safe.directory "${REACT_APP_DIR}"

    if [[ -d "${REACT_APP_DIR}" ]]; then
        if [[ "${EUID}" -eq 0 ]]; then
            chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
        elif command -v sudo &>/dev/null; then
            sudo chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
        else
            chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
        fi
    fi
}

if [[ -d "${REACT_APP_DIR}/.git" ]]; then
    ensure_react_app_git_access
    info "React repo already cloned; fetching latest refs..."
    git -C "${REACT_APP_DIR}" fetch --all --prune
    if [[ -n "${REACT_BRANCH:-}" ]]; then
        git -C "${REACT_APP_DIR}" checkout "${REACT_BRANCH}"
        git -C "${REACT_APP_DIR}" pull --ff-only origin "${REACT_BRANCH}" || true
    else
        DEFAULT_BRANCH="$(git -C "${REACT_APP_DIR}" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||' || true)"
        if [[ -n "${DEFAULT_BRANCH}" ]]; then
            git -C "${REACT_APP_DIR}" checkout "${DEFAULT_BRANCH}"
            git -C "${REACT_APP_DIR}" pull --ff-only origin "${DEFAULT_BRANCH}" || true
        fi
    fi
else
    rm -rf "${REACT_APP_DIR}"
    if [[ -n "${REACT_BRANCH:-}" ]]; then
        git clone --branch "${REACT_BRANCH}" "${REACT_REPO_URL}" "${REACT_APP_DIR}"
    else
        git clone "${REACT_REPO_URL}" "${REACT_APP_DIR}"
    fi
fi
success "React source is ready at docker/react/app."

[[ -f "${REACT_APP_DIR}/package.json" ]] || error "External repo must contain package.json at its root."
[[ -f "${REACT_APP_DIR}/package-lock.json" ]] || error "External repo must contain package-lock.json at its root."
[[ -f "${REACT_APP_DIR}/server/index.js" ]] || error "External repo must contain server/index.js."
[[ -f "${REACT_APP_DIR}/server/prisma/schema.prisma" ]] || error "External repo must contain server/prisma/schema.prisma."
[[ -f "${REPO_ROOT}/docker/company-backend/.env.production" ]] || \
    error "Create docker/company-backend/.env.production from .env.production.example."

info "Starting PostgreSQL and ensuring the website database/user exist..."
"${COMPOSE_CMD[@]}" up -d --wait postgres
"${COMPOSE_CMD[@]}" exec -T postgres psql \
    --username "${POSTGRES_USER:-odoo}" --dbname postgres \
    --set=website_user="${WEBSITE_DB_USER:-infoaxon_web}" \
    --set=website_db="${WEBSITE_DB_NAME:-infoaxon_website}" \
    --set=website_password="${WEBSITE_DB_PASSWORD}" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'website_user', :'website_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'website_user') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'website_user', :'website_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'website_db', :'website_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'website_db') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'website_db', :'website_user') \gexec
SQL
success "Website database is ready."

info "Validating Docker Compose configuration..."
"${COMPOSE_CMD[@]}" config >/dev/null
success "Compose configuration is valid."

info "Building Docker images..."
"${COMPOSE_CMD[@]}" build --pull
success "Images built."

info "Applying Prisma production migrations..."
"${COMPOSE_CMD[@]}" run --rm --no-deps company-backend npx prisma migrate deploy --schema=server/prisma/schema.prisma
success "Prisma migrations applied."

info "Fixing Odoo log directory ownership..."
ODOO_UID_GID="$("${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint sh odoo -c 'printf "%s:%s" "$(id -u)" "$(id -g)"')"
if command -v sudo &>/dev/null; then
    sudo chown -R "${ODOO_UID_GID}" "${REPO_ROOT}/logs/odoo"
else
    chown -R "${ODOO_UID_GID}" "${REPO_ROOT}/logs/odoo" 2>/dev/null || \
        warn "Could not chown logs/odoo to ${ODOO_UID_GID}; trying writable permissions instead."
fi
chmod -R u+rwX,g+rwX "${REPO_ROOT}/logs/odoo"

info "Starting/recreating changed services without removing volumes..."
"${COMPOSE_CMD[@]}" up -d --remove-orphans

info "Checking Nginx configuration..."
"${COMPOSE_CMD[@]}" exec -T nginx nginx -t
success "Nginx configuration is valid."

info "Waiting for Odoo to become healthy (max 3 minutes)..."
timeout=180
elapsed=0
interval=10
until docker inspect --format='{{.State.Health.Status}}' erp-odoo 2>/dev/null | grep -q "healthy"; do
    if [[ $elapsed -ge $timeout ]]; then
        error "Odoo did not become healthy in ${timeout}s. Check: docker logs erp-odoo"
    fi
    echo "  ... waiting (${elapsed}s / ${timeout}s)"
    sleep $interval
    elapsed=$((elapsed + interval))
done
success "Odoo is healthy."

if [[ "${ENABLE_SSL}" == "true" ]]; then
    info "Configuring Let's Encrypt SSL for ${DOMAIN} and www.${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-ssl.sh" "${DOMAIN}"
fi

SERVER_IP="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '<server-ip>')"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Deployment complete${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
"${COMPOSE_CMD[@]}" ps
echo ""
echo "Access:"
echo "  Website HTTP : http://${DOMAIN}"
if [[ -f "${REPO_ROOT}/ssl/live/${DOMAIN}/fullchain.pem" ]]; then
    echo "  Website HTTPS: https://${DOMAIN}"
fi
echo "  Odoo demo    : http://${SERVER_IP}:8069"
echo ""
echo "Redeploy with:"
echo "  bash scripts/install/deploy.sh"
echo ""
