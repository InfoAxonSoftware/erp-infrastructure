# Customer Onboarding Guide

## Overview

Each customer gets:
- A dedicated Odoo database
- A unique subdomain: `<company>.yourerp.com`
- Complete data isolation from other tenants
- Full Odoo Community feature set

---

## Prerequisites

1. The ERP stack is running (`docker compose ps` shows all healthy)
2. DNS wildcard record `*.yourerp.com → <server-ip>` is configured
3. The customer's subdomain is chosen (lowercase, alphanumeric + hyphens)

---

## Provisioning a New Tenant

Run the `create-customer.sh` script:

```bash
bash scripts/customer/create-customer.sh <subdomain> "<company-name>" <admin-email>
```

### Example

```bash
bash scripts/customer/create-customer.sh acmecorp "Acme Corporation" ceo@acmecorp.com
```

**Output:**
```
[INFO]  Checking if tenant 'acmecorp' already exists...
[INFO]  Creating PostgreSQL database: acmecorp
[OK]    Database 'acmecorp' created.
[INFO]  Initializing Odoo database for tenant: acmecorp
[OK]    Odoo database initialized for tenant 'acmecorp'.
[INFO]  Registering tenant in the registry table...
[OK]    Tenant registered in registry.

════════════════════════════════════════════════════════════
  Tenant 'Acme Corporation' provisioned successfully!
════════════════════════════════════════════════════════════

  URL           : http://acmecorp.yourerp.com
  Database      : acmecorp
  Admin login   : ceo@acmecorp.com
  Admin password: xK9mP2qR7nL4wA6s

  IMPORTANT: Save the admin password above — it is only shown once.
```

---

## What the Script Does

1. **Validates** the subdomain format (lowercase, alphanumeric, hyphens only)
2. **Creates** a new PostgreSQL database named `<subdomain>`
3. **Initializes** the Odoo database via the Odoo admin API (installs base modules)
4. **Registers** the tenant in `public.tenant_registry` on the postgres database
5. **Prints** login credentials (admin password shown only once)

---

## Subdomain Naming Rules

| Rule | Example |
|------|---------|
| Lowercase letters, numbers, hyphens | ✅ `acme-corp` |
| Must not start or end with a hyphen | ❌ `-acme`, `acme-` |
| 2–63 characters | ✅ `ac` to `acme-corporation-ltd` |
| No dots or underscores | ❌ `acme.corp`, `acme_corp` |

The subdomain becomes the **database name** (required for `dbfilter = ^%d$`).

---

## DNS Requirements

The wildcard DNS record `*.yourerp.com → <server-ip>` covers all tenants automatically. No DNS change is needed per tenant if the wildcard is in place.

To verify DNS for a new tenant:
```bash
dig acmecorp.yourerp.com
# Should return your server's IP
```

---

## After Provisioning — Tenant Setup Checklist

Share these steps with the customer or complete them as part of the onboarding:

1. **Login:** Go to `https://acmecorp.yourerp.com` and log in with the provided credentials
2. **Change password:** Settings → Preferences → Change Password
3. **Company info:** Settings → General Settings → Companies → Update name, logo, address, currency
4. **Timezone:** Settings → General Settings → Localization → Set timezone
5. **Install modules:** Settings → Apps → install needed modules (Sales, Inventory, Accounting, etc.)
6. **Add users:** Settings → Users → Create additional users
7. **Configure email:** Settings → Technical → Email → Outgoing Mail Servers

---

## Managing Existing Tenants

### List all tenants

```bash
docker exec erp-postgres psql -U odoo -d postgres \
  -c "SELECT subdomain, tenant_name, admin_email, created_at, is_active FROM public.tenant_registry ORDER BY created_at;"
```

### Deactivate a tenant (soft delete)

```bash
docker exec erp-postgres psql -U odoo -d postgres \
  -c "UPDATE public.tenant_registry SET is_active = FALSE WHERE subdomain = 'acmecorp';"
```

To prevent login, rename or drop the database:
```bash
# Rename (safer — data preserved)
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres \
  -c "ALTER DATABASE acmecorp RENAME TO acmecorp_suspended;"
```

### Permanently delete a tenant

> ⚠️ **Irreversible.** Take a backup first.

```bash
# 1. Backup first
bash scripts/backup/backup.sh --db-only

# 2. Drop the database
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='acmecorp';"

docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres -c "DROP DATABASE acmecorp;"

# 3. Remove from registry
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres \
  -c "DELETE FROM public.tenant_registry WHERE subdomain = 'acmecorp';"

# 4. Remove filestore data for that tenant
docker exec erp-odoo rm -rf /var/lib/odoo/filestore/acmecorp
```

### Reset tenant admin password

```bash
# Generate new password
NEW_PASS="$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)"

# Reset via Odoo shell (runs inside the container)
docker exec -it erp-odoo odoo shell -d acmecorp --no-http <<EOF
user = env['res.users'].browse(2)
user.write({'password': '${NEW_PASS}'})
env.cr.commit()
print(f"Password reset to: ${NEW_PASS}")
EOF
```

---

## Backup a Single Tenant

```bash
bash scripts/backup/backup.sh --db-only
# or directly:
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  pg_dump -U odoo --format=custom --compress=9 acmecorp \
  > backups/acmecorp_manual_$(date +%Y%m%d).dump
```

---

## Migrate a Tenant to a Different Server

```bash
# 1. Dump on source server
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  pg_dump -U odoo --format=custom acmecorp > /tmp/acmecorp.dump

# 2. Copy to destination server
scp /tmp/acmecorp.dump erp@<new-server>:/tmp/

# 3. Restore on destination server
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres -c "CREATE DATABASE acmecorp OWNER odoo;"

docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  pg_restore -U odoo -d acmecorp --no-owner < /tmp/acmecorp.dump

# 4. Copy filestore
docker run --rm \
  -v erp-platform_odoo_filestore:/source:ro \
  alpine tar -czf - -C /source/acmecorp . \
  | ssh erp@<new-server> \
    "docker run --rm -i -v erp-platform_odoo_filestore:/target alpine tar -xzf - -C /target/acmecorp"
```
