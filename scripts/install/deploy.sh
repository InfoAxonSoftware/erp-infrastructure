#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Full ERP Platform Deployment
# =============================================================================
# Run from the repository root on the VPS after install.sh has been executed.
#
# Usage:
#   bash scripts/install/deploy.sh [--ssl]
#
# Options:
#   --ssl   Request Let's Encrypt certificates after bringing up services.
#           Requires DNS to be pointed at this server before running.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENABLE_SSL=false
for arg in "$@"; do [[ "$arg" == "--ssl" ]] && ENABLE_SSL=true; done

cd "${REPO_ROOT}"

# =============================================================================
info "Checking prerequisites..."
# =============================================================================
command -v docker &>/dev/null || error "Docker is not installed. Run scripts/install/install.sh first."
docker compose version &>/dev/null || error "Docker Compose v2 is required."

[[ -f .env ]] || error ".env file not found. Copy .env.example to .env and fill in all values."

# Validate required env vars
set -a; source .env; set +a
: "${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD in .env}"
: "${ODOO_ADMIN_PASSWORD:?Missing ODOO_ADMIN_PASSWORD in .env}"
: "${DOMAIN:?Missing DOMAIN in .env}"
: "${REACT_REPO_URL:?Missing REACT_REPO_URL in .env — set it to your React website repo URL}"

success "All prerequisites satisfied."

# =============================================================================
info "Creating required directories..."
# =============================================================================
mkdir -p logs/nginx logs/odoo ssl

# =============================================================================
info "Cloning / updating React frontend from: ${REACT_REPO_URL}"
# =============================================================================
REACT_APP_DIR="${REPO_ROOT}/docker/react/app"

if [[ -d "${REACT_APP_DIR}/.git" ]]; then
    info "  React repo already cloned — pulling latest changes..."
    git -C "${REACT_APP_DIR}" fetch --all --prune
    git -C "${REACT_APP_DIR}" reset --hard origin/HEAD
    success "  React repo updated."
else
    info "  Cloning React repo for the first time..."
    rm -rf "${REACT_APP_DIR}"
    git clone "${REACT_REPO_URL}" "${REACT_APP_DIR}"
    success "  React repo cloned → docker/react/app/"
fi

# Optional: checkout a specific branch or tag from .env
if [[ -n "${REACT_BRANCH:-}" ]]; then
    info "  Checking out branch/tag: ${REACT_BRANCH}"
    git -C "${REACT_APP_DIR}" checkout "${REACT_BRANCH}"
fi

# =============================================================================
info "Building Docker images..."
# =============================================================================
docker compose \
    -f "${REPO_ROOT}/docker/compose.yml" \
    -f "${REPO_ROOT}/docker/compose.prod.yml" \
    build --pull --no-cache

success "Images built."

# =============================================================================
info "Stopping existing containers (if any)..."
# =============================================================================
docker compose \
    -f "${REPO_ROOT}/docker/compose.yml" \
    -f "${REPO_ROOT}/docker/compose.prod.yml" \
    down --remove-orphans 2>/dev/null || true

# =============================================================================
info "Starting services..."
# =============================================================================
docker compose \
    -f "${REPO_ROOT}/docker/compose.yml" \
    -f "${REPO_ROOT}/docker/compose.prod.yml" \
    up -d

success "Services started. Waiting for health checks..."

# =============================================================================
info "Waiting for Odoo to become healthy (max 3 min)..."
# =============================================================================
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

# =============================================================================
if [[ "${ENABLE_SSL}" == "true" ]]; then
    info "Requesting Let's Encrypt SSL certificates..."
    bash "${SCRIPT_DIR}/setup-ssl.sh" "${DOMAIN}"
fi
# =============================================================================

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Services:"
docker compose -f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml" ps
echo ""
echo "  Access:"
echo "    Website : http://${DOMAIN}"
echo "    Odoo    : http://erp.${DOMAIN}"
echo ""
echo "  To add a customer tenant:"
echo "    bash scripts/customer/create-customer.sh <subdomain> <company-name> <admin-email>"
echo ""
echo "  To set up SSL:"
echo "    bash scripts/install/deploy.sh --ssl"
echo ""
