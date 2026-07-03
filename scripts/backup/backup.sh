#!/usr/bin/env bash
# =============================================================================
# backup.sh — Full ERP Platform Backup
# =============================================================================
# Backs up:
#   1. All PostgreSQL tenant databases
#   2. Odoo filestore (attachments, documents)
#
# Usage:
#   bash scripts/backup/backup.sh [--db-only] [--filestore-only]
#
# Backups are stored in:
#   backups/
#     YYYY-MM-DD_HH-MM-SS/
#       postgres/   ← per-database .sql.gz dumps
#       filestore/  ← compressed odoo filestore
#
# Configure optional off-site upload via S3_BUCKET in .env.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Load environment ──────────────────────────────────────────────────────────
set -a; source "${REPO_ROOT}/.env"; set +a

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_BASE="${REPO_ROOT}/backups/${TIMESTAMP}"
POSTGRES_USER="${POSTGRES_USER:-odoo}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
S3_BUCKET="${S3_BUCKET:-}"
ODOO_VOLUME="erp-platform_odoo_filestore"

DB_ONLY=false
FILESTORE_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--db-only" ]]        && DB_ONLY=true
    [[ "$arg" == "--filestore-only" ]] && FILESTORE_ONLY=true
done

mkdir -p "${BACKUP_BASE}/postgres" "${BACKUP_BASE}/filestore"

# =============================================================================
if [[ "${FILESTORE_ONLY}" != "true" ]]; then
    info "Backing up PostgreSQL databases..."
    # =============================================================================

    # Get list of all user databases (excluding system dbs)
    DATABASES=$(docker exec erp-postgres \
        psql -U "${POSTGRES_USER}" -t -A \
        -c "SELECT datname FROM pg_database WHERE datistemplate=false AND datname NOT IN ('postgres','template0','template1');")

    if [[ -z "${DATABASES}" ]]; then
        warn "No tenant databases found to back up."
    else
        for DB in ${DATABASES}; do
            info "  Dumping database: ${DB}"
            docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
                pg_dump \
                    -U "${POSTGRES_USER}" \
                    --format=custom \
                    --compress=9 \
                    --no-privileges \
                    "${DB}" \
                > "${BACKUP_BASE}/postgres/${DB}.dump"
            success "  → ${BACKUP_BASE}/postgres/${DB}.dump"
        done
    fi

    # Also dump the tenant_registry from postgres DB
    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
        pg_dump \
            -U "${POSTGRES_USER}" \
            --format=custom \
            --compress=9 \
            --table=public.tenant_registry \
            postgres \
        > "${BACKUP_BASE}/postgres/_registry.dump" 2>/dev/null || true

    success "PostgreSQL backup complete."
fi

# =============================================================================
if [[ "${DB_ONLY}" != "true" ]]; then
    info "Backing up Odoo filestore..."
    # =============================================================================

    docker run --rm \
        -v "${ODOO_VOLUME}:/source:ro" \
        -v "${BACKUP_BASE}/filestore:/backup" \
        alpine \
        tar -czf /backup/filestore.tar.gz -C /source .

    success "Filestore backup: ${BACKUP_BASE}/filestore/filestore.tar.gz"
fi

# =============================================================================
info "Writing backup manifest..."
# =============================================================================
cat > "${BACKUP_BASE}/manifest.txt" <<EOF
ERP Platform Backup
===================
Timestamp : ${TIMESTAMP}
Host      : $(hostname)
DB User   : ${POSTGRES_USER}

Databases backed up:
$(ls "${BACKUP_BASE}/postgres/" 2>/dev/null | sed 's/^/  - /' || echo "  (none)")

Filestore : $(du -sh "${BACKUP_BASE}/filestore/filestore.tar.gz" 2>/dev/null | cut -f1 || echo "skipped")
EOF

# =============================================================================
info "Cleanup: removing backups older than ${RETENTION_DAYS} days..."
# =============================================================================
find "${REPO_ROOT}/backups" -maxdepth 1 -mindepth 1 -type d \
    -mtime "+${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true
success "Old backups cleaned up."

# =============================================================================
if [[ -n "${S3_BUCKET}" ]]; then
    info "Uploading backup to S3: s3://${S3_BUCKET}/erp-backups/${TIMESTAMP}/"
    if command -v aws &>/dev/null; then
        aws s3 cp "${BACKUP_BASE}" "s3://${S3_BUCKET}/erp-backups/${TIMESTAMP}/" \
            --recursive --quiet
        success "Uploaded to S3."
    else
        warn "aws CLI not found. Skipping S3 upload. Install with: sudo snap install aws-cli --classic"
    fi
fi
# =============================================================================

BACKUP_SIZE="$(du -sh "${BACKUP_BASE}" | cut -f1)"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Backup complete: ${TIMESTAMP}${NC}"
echo -e "${GREEN}  Size: ${BACKUP_SIZE}${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
