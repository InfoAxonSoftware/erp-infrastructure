#!/usr/bin/env bash
# =============================================================================
# restore.sh — ERP Platform Restore from Backup
# =============================================================================
# Restores one or all databases and/or the Odoo filestore from a backup
# created by backup.sh.
#
# Usage:
#   bash scripts/restore/restore.sh <backup-timestamp> [--db <dbname>] [--all-dbs] [--filestore]
#
# Examples:
#   Restore all databases + filestore from a backup:
#     bash scripts/restore/restore.sh 2025-01-15_02-00-00 --all-dbs --filestore
#
#   Restore only a single tenant database:
#     bash scripts/restore/restore.sh 2025-01-15_02-00-00 --db company1
#
#   Restore only the filestore:
#     bash scripts/restore/restore.sh 2025-01-15_02-00-00 --filestore
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
confirm() {
    local prompt="${1:-Are you sure?}"
    read -r -p "$(echo -e "${YELLOW}[CONFIRM]${NC} ${prompt} [y/N]: ")" reply
    [[ "${reply}" =~ ^[Yy]$ ]] || error "Aborted by user."
}

# ── Argument parsing ──────────────────────────────────────────────────────────
TIMESTAMP="${1:-}"
[[ -z "${TIMESTAMP}" ]] && error "Usage: $0 <backup-timestamp> [--db <name>] [--all-dbs] [--filestore]"

BACKUP_DIR="${REPO_ROOT}/backups/${TIMESTAMP}"
[[ -d "${BACKUP_DIR}" ]] || error "Backup directory not found: ${BACKUP_DIR}"

RESTORE_DB=""
RESTORE_ALL_DBS=false
RESTORE_FILESTORE=false

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)           RESTORE_DB="${2:-}"; shift 2 ;;
        --all-dbs)      RESTORE_ALL_DBS=true; shift ;;
        --filestore)    RESTORE_FILESTORE=true; shift ;;
        *)              error "Unknown option: $1" ;;
    esac
done

[[ "${RESTORE_ALL_DBS}" == "false" && -z "${RESTORE_DB}" && "${RESTORE_FILESTORE}" == "false" ]] \
    && error "Specify at least one of: --db <name>, --all-dbs, --filestore"

POSTGRES_USER="${POSTGRES_USER:-odoo}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD}"
ODOO_VOLUME="erp-platform_odoo_filestore"

# =============================================================================
info "Backup selected: ${TIMESTAMP}"
cat "${BACKUP_DIR}/manifest.txt" 2>/dev/null || true
echo ""
confirm "This will OVERWRITE existing data. Continue?"
# =============================================================================

# =============================================================================
# Stop Odoo to prevent writes during restore
# =============================================================================
info "Stopping Odoo container to prevent write conflicts..."
docker compose -f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml" stop odoo

# =============================================================================
restore_database() {
    local DB="$1"
    local DUMP_FILE="${BACKUP_DIR}/postgres/${DB}.dump"
    [[ -f "${DUMP_FILE}" ]] || error "Dump file not found: ${DUMP_FILE}"

    info "Restoring database: ${DB}"

    # Drop existing DB and recreate
    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        psql -U "${POSTGRES_USER}" -d postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB}' AND pid <> pg_backend_pid();" \
        >/dev/null 2>&1 || true

    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        psql -U "${POSTGRES_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS \"${DB}\";" >/dev/null

    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        psql -U "${POSTGRES_USER}" -d postgres \
        -c "CREATE DATABASE \"${DB}\" OWNER \"${POSTGRES_USER}\";" >/dev/null

    # Restore from custom-format dump
    docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        pg_restore \
            -U "${POSTGRES_USER}" \
            -d "${DB}" \
            --no-owner \
            --role="${POSTGRES_USER}" \
            --exit-on-error \
        < "${DUMP_FILE}"

    success "Database '${DB}' restored."
}
# =============================================================================

# ── Restore databases ─────────────────────────────────────────────────────────
if [[ -n "${RESTORE_DB}" ]]; then
    restore_database "${RESTORE_DB}"
fi

if [[ "${RESTORE_ALL_DBS}" == "true" ]]; then
    for DUMP_FILE in "${BACKUP_DIR}/postgres/"*.dump; do
        DB="$(basename "${DUMP_FILE}" .dump)"
        [[ "${DB}" == "_registry" ]] && continue
        restore_database "${DB}"
    done
fi

# ── Restore filestore ─────────────────────────────────────────────────────────
if [[ "${RESTORE_FILESTORE}" == "true" ]]; then
    FILESTORE_ARCHIVE="${BACKUP_DIR}/filestore/filestore.tar.gz"
    [[ -f "${FILESTORE_ARCHIVE}" ]] || error "Filestore archive not found: ${FILESTORE_ARCHIVE}"

    info "Restoring Odoo filestore..."
    confirm "This will REPLACE the entire filestore volume. Continue?"

    docker run --rm \
        -v "${ODOO_VOLUME}:/target" \
        -v "${BACKUP_DIR}/filestore:/backup:ro" \
        alpine \
        sh -c "rm -rf /target/* && tar -xzf /backup/filestore.tar.gz -C /target"

    success "Filestore restored."
fi

# =============================================================================
info "Restarting Odoo..."
# =============================================================================
docker compose -f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml" start odoo
success "Odoo restarted."

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Restore complete from: ${TIMESTAMP}${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
