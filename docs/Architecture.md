# Architecture

## System Overview

```
                              Internet
                                 │
                         ┌───────▼───────┐
                         │    Cloudflare  │  (optional CDN/DDoS)
                         └───────┬───────┘
                                 │ :80 / :443
                         ┌───────▼───────┐
                         │     Nginx      │  Reverse Proxy + SSL Termination
                         │  (nginx:1.25)  │  Rate limiting, gzip, security headers
                         └───┬───────┬───┘
                             │       │
              yourerp.com    │       │   *.yourerp.com / erp.yourerp.com
                             │       │
                   ┌─────────▼──┐  ┌─▼──────────────┐
                   │   React    │  │      Odoo 17     │
                   │  Website   │  │  (Community)     │
                   │  :80 (SPA) │  │  :8069 / :8072   │
                   └────────────┘  └────────┬─────────┘
                    [frontend net]   [frontend + backend nets]
                                            │
                                   ┌────────▼────────┐
                                   │  PostgreSQL 16   │
                                   │  [backend net]   │
                                   └─────────────────┘
```

## Components

| Component | Image | Role |
|-----------|-------|------|
| **Nginx** | `nginx:1.25-alpine` | Reverse proxy, SSL termination, rate limiting |
| **Odoo 17** | `odoo:17.0` (custom) | ERP application server |
| **PostgreSQL 16** | `postgres:16-alpine` | Relational database (multi-tenant) |
| **React** | `node:20-alpine` → `nginx:alpine` | Marketing/landing page website |

## Docker Networks

| Network | Services | Purpose |
|---------|----------|---------|
| `frontend` | nginx, odoo, react | Public-facing traffic |
| `backend` | odoo, postgres | Internal DB communication only |

PostgreSQL is **not** exposed on the frontend network and has no published ports.

## Docker Volumes

| Volume | Contents | Backup |
|--------|----------|--------|
| `postgres_data` | All tenant databases | ✅ Yes |
| `odoo_data` | Odoo sessions, internal data | ✅ Yes |
| `odoo_filestore` | Attachments, documents, images | ✅ Yes |

## Multi-Tenant Architecture

Each customer is an isolated Odoo database:

```
company1.yourerp.com  ──► Nginx ──► Odoo (dbfilter=^%d$) ──► company1 DB
company2.yourerp.com  ──► Nginx ──► Odoo (dbfilter=^%d$) ──► company2 DB
company3.yourerp.com  ──► Nginx ──► Odoo (dbfilter=^%d$) ──► company3 DB
```

The `dbfilter = ^%d$` in `odoo.conf` extracts the first subdomain component from the `Host` header and filters to only that database. This means:
- Each tenant sees **only their own database**
- The Odoo database selector is disabled (`list_db = False`)
- A single Odoo process serves all tenants (resource-efficient)

## Request Flow

```
1. Browser → company1.yourerp.com
2. DNS resolves to VPS IP
3. Nginx matches server_name ~^(?P<tenant>[^.]+)\.yourerp\.com$
4. Nginx proxies to Odoo with Host header preserved
5. Odoo reads Host header → extracts "company1" → dbfilter matches "company1" DB
6. Odoo serves the request using company1's data
```

## Port Exposure

| Port | Exposed | Service | Notes |
|------|---------|---------|-------|
| 80 | ✅ Public | Nginx | HTTP, redirects to HTTPS in production |
| 443 | ✅ Public | Nginx | HTTPS + HTTP/2 |
| 8069 | ❌ Internal | Odoo | Blocked by UFW |
| 8072 | ❌ Internal | Odoo | Longpolling, internal only |
| 5432 | ❌ Internal | PostgreSQL | Blocked by UFW |

## File Structure

```
erp-infrastructure/
├── docker/
│   ├── compose.yml           # Base service definitions
│   ├── compose.prod.yml      # Production overrides (restart, resource limits)
│   ├── nginx/Dockerfile      # Custom nginx with curl for health checks
│   ├── odoo/
│   │   ├── Dockerfile        # Odoo 17 + custom entrypoint
│   │   └── entrypoint.sh     # Injects ODOO_ADMIN_PASSWORD at runtime
│   ├── postgres/init/        # Runs on first DB init
│   └── react/                # Full React SPA + multi-stage Dockerfile
├── config/
│   ├── nginx/
│   │   ├── nginx.conf        # Global nginx settings
│   │   └── templates/        # envsubst templates (DOMAIN substituted at startup)
│   └── odoo/odoo.conf        # Odoo configuration (no secrets)
├── scripts/
│   ├── install/              # Server setup, SSL
│   ├── backup/               # Automated backups
│   ├── restore/              # Restore procedure
│   └── customer/             # Tenant provisioning
├── docs/                     # This documentation
├── backups/                  # Local backup storage
├── logs/                     # Nginx and Odoo logs (gitignored)
└── ssl/                      # TLS certificates (gitignored)
```
