#!/bin/bash
# Custom Odoo entrypoint that injects runtime secrets into the configuration
# before delegating to the official Odoo entrypoint.
#
# The mounted odoo.conf is read-only, so we copy it to a temp file,
# substitute the ODOO_ADMIN_PASSWORD placeholder, then point ODOO_RC at it.
# The official /entrypoint.sh respects the ODOO_RC environment variable.

set -e

# ── Inject admin password ─────────────────────────────────────────────────────
if [ -z "${ODOO_ADMIN_PASSWORD}" ]; then
    echo "ERROR: ODOO_ADMIN_PASSWORD environment variable is not set." >&2
    exit 1
fi

RUNTIME_CONF="$(mktemp /tmp/odoo-runtime-XXXXXX.conf)"
cp /etc/odoo/odoo.conf "${RUNTIME_CONF}"
sed -i "s|ODOO_ADMIN_PASSWORD_PLACEHOLDER|${ODOO_ADMIN_PASSWORD}|g" "${RUNTIME_CONF}"
export ODOO_RC="${RUNTIME_CONF}"

# ── Hand off to the official Odoo entrypoint ──────────────────────────────────
exec /entrypoint.sh "$@"
