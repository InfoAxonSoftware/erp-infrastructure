# Customer Provisioning

## Current Status

Multi-tenant customer provisioning is currently disabled.

The active deployment is a single Odoo 18 Community demo instance for client demonstrations:

- One Odoo database: `infoaxon_erp`
- Temporary direct access: `http://SERVER_IP:8069`
- No wildcard DNS routing
- No `*.infoaxon.lk` routing to Odoo
- No automated customer subdomain provisioning

The previous SaaS-style customer onboarding workflow is intentionally not documented as an active procedure because it no longer matches the running VPS.

## Why It Is Disabled

The current server has:

- 1 vCPU
- 2 GB RAM
- 2 GB swap

That is enough for a lightweight Odoo demo and the React company website, but it is not an appropriate baseline for active multi-tenant SaaS hosting.

## Legacy Script

The repository still contains:

```bash
scripts/customer/create-customer.sh
```

Treat it as legacy code only. Do not use it for the current deployment without first reintroducing and reviewing:

- Wildcard DNS
- Nginx Odoo hostname routing
- Odoo `dbfilter` strategy
- Backup and restore expectations per customer
- Capacity planning for more CPU and memory
- Security controls for database creation and database manager access

## Restoring The Old Guide

If multi-tenant hosting becomes a requirement again, restore the previous customer onboarding guide and related routing from Git history, then update it against the new target architecture before use.

Useful starting point:

```bash
git log -- docs/Customers.md config/nginx/templates scripts/customer/create-customer.sh
```
