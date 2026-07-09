#!/usr/bin/env bash
# =============================================================================
# create-customer.sh - Legacy multi-tenant provisioning placeholder
# =============================================================================
# Multi-tenant customer provisioning is disabled in the current deployment.
# The active system runs one Odoo demo database, infoaxon_erp, with temporary
# direct access on SERVER_IP:8069.
#
# Restore the previous implementation from Git history only after reintroducing
# and reviewing Odoo hostname routing, database filtering, wildcard DNS,
# certificate strategy, backups, and server capacity.
# =============================================================================
set -euo pipefail

cat >&2 <<'EOF'
Customer provisioning is disabled for the current deployment.

The active VPS runs one Odoo demo database:
  infoaxon_erp

Do not create customer databases with this script. See docs/Customers.md for
the current status and the checklist required before restoring multi-tenant
hosting from Git history.
EOF

exit 1
