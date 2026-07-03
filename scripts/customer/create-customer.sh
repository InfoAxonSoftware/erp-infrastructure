#!/usr/bin/env bash
# =============================================================================
# create-customer.sh — Provision a New Tenant
# =============================================================================
# Creates a new Odoo tenant (separate database) with its own subdomain.
#
# Usage:
#   bash scripts/customer/create-customer.sh <subdomain> <company-name> <admin-email>
#
# Example:
#   bash scripts/customer/create-customer.sh acmecorp "Acme Corporation" admin@acmecorp.com
#
# This script will:
#   1. Validate inputs
#   2. Check the subdomain/database doesn't already exist
#   3. Create the PostgreSQL database
#   4. Initialize the Odoo database via the admin API
#   5. Register the tenant in the registry table
#   6. Print connection details
#
# Pre-requisites:
#   - ERP stack is running (docker compose up -d)
#   - DNS: <subdomain>.yourerp.com → server IP  (wildcard *.yourerp.com works)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Load environment ──────────────────────────────────────────────────────────
set -a; source "${REPO_ROOT}/.env"; set +a

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Argument validation ───────────────────────────────────────────────────────
SUBDOMAIN="${1:-}"
COMPANY_NAME="${2:-}"
ADMIN_EMAIL="${3:-}"

[[ -z "${SUBDOMAIN}" || -z "${COMPANY_NAME}" || -z "${ADMIN_EMAIL}" ]] && {
    echo "Usage: $0 <subdomain> <company-name> <admin-email>"
    echo "Example: $0 acmecorp \"Acme Corporation\" admin@acmecorp.com"
    exit 1
}

# Sanitize subdomain: lowercase alphanumeric + hyphens only
SUBDOMAIN="${SUBDOMAIN,,}"
if [[ ! "${SUBDOMAIN}" =~ ^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$ ]]; then
    error "Invalid subdomain '${SUBDOMAIN}'. Use lowercase letters, numbers, and hyphens only."
fi

# Database name = subdomain (matches dbfilter = ^%d$)
DB_NAME="${SUBDOMAIN}"
DOMAIN="${DOMAIN:-yourerp.com}"
TENANT_URL="http://${SUBDOMAIN}.${DOMAIN}"
POSTGRES_USER="${POSTGRES_USER:-odoo}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD}"
ODOO_ADMIN_PASSWORD="${ODOO_ADMIN_PASSWORD:?Missing ODOO_ADMIN_PASSWORD}"

# ── Check for required tools ──────────────────────────────────────────────────
command -v curl   &>/dev/null || error "curl is required."
command -v docker &>/dev/null || error "docker is required."

# ── Verify stack is running ───────────────────────────────────────────────────
docker inspect erp-odoo &>/dev/null || error "ERP stack is not running. Run: bash scripts/install/deploy.sh"

# =============================================================================
info "Checking if tenant '${SUBDOMAIN}' already exists..."
# =============================================================================
EXISTING=$(docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
    psql -U "${POSTGRES_USER}" -d postgres -t -A \
    -c "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" 2>/dev/null || echo "")

if [[ "${EXISTING}" == "1" ]]; then
    error "Database '${DB_NAME}' already exists. Tenant '${SUBDOMAIN}' is already provisioned."
fi

# =============================================================================
info "Creating PostgreSQL database: ${DB_NAME}"
# =============================================================================
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
    psql -U "${POSTGRES_USER}" -d postgres \
    -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${POSTGRES_USER}\" ENCODING 'UTF8';"

success "Database '${DB_NAME}' created."

# =============================================================================
info "Initializing Odoo database for tenant: ${SUBDOMAIN}"
# =============================================================================
# Generate a secure random password for the tenant's admin user
TENANT_ADMIN_PASSWORD="$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | head -c 16)"

# Use Odoo's database manager RPC to initialize the database
HTTP_RESPONSE=$(curl -sS --max-time 120 \
    -X POST "http://localhost:8069/web/database/create" \
    -H "Content-Type: application/json" \
    -d "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"call\",
        \"id\": 1,
        \"params\": {
            \"fields\": [
                {\"name\": \"master_pwd\",    \"value\": \"${ODOO_ADMIN_PASSWORD}\"},
                {\"name\": \"name\",          \"value\": \"${DB_NAME}\"},
                {\"name\": \"login\",         \"value\": \"${ADMIN_EMAIL}\"},
                {\"name\": \"password\",      \"value\": \"${TENANT_ADMIN_PASSWORD}\"},
                {\"name\": \"lang\",          \"value\": \"en_US\"},
                {\"name\": \"country_code\",  \"value\": \"us\"},
                {\"name\": \"demo\",          \"value\": \"false\"}
            ]
        }
    }" 2>&1) || true

# Check for error in response
if echo "${HTTP_RESPONSE}" | grep -q '"error"'; then
    ERROR_MSG=$(echo "${HTTP_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('data',{}).get('message','Unknown error'))" 2>/dev/null || echo "${HTTP_RESPONSE}")
    # Clean up the database we just created
    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        psql -U "${POSTGRES_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS \"${DB_NAME}\";" >/dev/null 2>&1 || true
    error "Odoo database initialization failed: ${ERROR_MSG}"
fi

success "Odoo database initialized for tenant '${SUBDOMAIN}'."

# =============================================================================
info "Registering tenant in the registry table..."
# =============================================================================
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
    psql -U "${POSTGRES_USER}" -d postgres \
    -c "INSERT INTO public.tenant_registry (tenant_name, db_name, subdomain, admin_email)
        VALUES ('${COMPANY_NAME}', '${DB_NAME}', '${SUBDOMAIN}', '${ADMIN_EMAIL}')
        ON CONFLICT (subdomain) DO NOTHING;" >/dev/null

success "Tenant registered in registry."

# =============================================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Tenant '${COMPANY_NAME}' provisioned successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  URL           : ${TENANT_URL}"
echo "  Database      : ${DB_NAME}"
echo "  Admin login   : ${ADMIN_EMAIL}"
echo "  Admin password: ${TENANT_ADMIN_PASSWORD}"
echo ""
echo -e "${YELLOW}  IMPORTANT: Save the admin password above — it is only shown once.${NC}"
echo ""
echo "  DNS: Ensure ${SUBDOMAIN}.${DOMAIN} → $(curl -sf ifconfig.me 2>/dev/null || echo '<server-ip>')"
echo ""
