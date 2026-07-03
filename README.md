# ERP Infrastructure

Production-ready, multi-tenant SaaS ERP platform built on **Odoo 17 Community**, **PostgreSQL 16**, **React**, and **Nginx** — fully containerized with Docker Compose and deployable on any Ubuntu 24.04 VPS.

---

## Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| ERP Backend | Odoo Community | 17.0 |
| Database | PostgreSQL | 16 |
| Frontend Website | React + Vite | 18 / 5 |
| Reverse Proxy | Nginx | 1.25 |
| Container Runtime | Docker + Compose | Latest |
| OS Target | Ubuntu | 24.04 LTS |

---

## Architecture

```
Internet → Nginx (80/443) → React (yourerp.com)
                         → Odoo  (erp.yourerp.com, *.yourerp.com)
                              └── PostgreSQL (internal only)
```

Multi-tenant: each customer = isolated PostgreSQL database + subdomain.
`company1.yourerp.com` → database `company1` (via `dbfilter = ^%d$`).

---

## Quick Start (Production)

```bash
# 1. Set up a fresh Ubuntu 24.04 VPS
curl -fsSL https://raw.githubusercontent.com/yourorg/erp-infrastructure/main/scripts/install/install.sh \
  | sudo bash

# 2. Clone and configure
git clone https://github.com/yourorg/erp-infrastructure.git /opt/erp/repo
cd /opt/erp/repo
cp .env.example .env
nano .env   # Set DOMAIN, POSTGRES_PASSWORD, ODOO_ADMIN_PASSWORD

# 3. Deploy
bash scripts/install/deploy.sh

# 4. Add a customer tenant
bash scripts/customer/create-customer.sh acmecorp "Acme Corporation" admin@acmecorp.com
```

---

## Repository Structure

```
erp-infrastructure/
├── docker/
│   ├── compose.yml           # Base service definitions
│   ├── compose.prod.yml      # Production overrides (restart, resource limits)
│   ├── nginx/Dockerfile
│   ├── odoo/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh     # Runtime secret injection
│   ├── postgres/
│   │   └── init/01-init.sql  # DB init + tenant registry table
│   └── react/                # Full Vite+React landing page + Dockerfile
├── config/
│   ├── nginx/
│   │   ├── nginx.conf        # Global nginx settings
│   │   └── templates/        # envsubst templates (DOMAIN substituted at start)
│   └── odoo/odoo.conf        # Multi-tenant Odoo config
├── scripts/
│   ├── install/
│   │   ├── install.sh        # Fresh VPS setup (Docker, UFW, Fail2Ban, SSH)
│   │   ├── deploy.sh         # Build images + start stack + health checks
│   │   └── setup-ssl.sh      # Let's Encrypt certificate setup
│   ├── backup/backup.sh      # DB + filestore backup with S3 support
│   ├── restore/restore.sh    # Selective restore (per-DB or full)
│   └── customer/
│       └── create-customer.sh # Provision a new tenant in ~30 seconds
├── docs/
│   ├── Architecture.md
│   ├── Deployment.md         # Step-by-step VPS deployment guide
│   ├── Security.md           # Firewall, SSL, SSH, Docker hardening
│   ├── Backup.md             # Backup/restore procedures
│   ├── Scaling.md            # Single VPS → multi-server growth path
│   └── Customers.md          # Tenant lifecycle management
├── backups/                  # Local backup storage (gitignored)
├── logs/                     # Runtime logs (gitignored)
├── ssl/                      # TLS certificates (gitignored)
└── .env.example              # Environment variable template
```

---

## Key Features

- **Multi-tenant SaaS** — subdomain-based database routing with Odoo `dbfilter`
- **Zero-touch SSL** — Let's Encrypt wildcard certificates via `setup-ssl.sh`
- **Automated backups** — per-database pg_dump + filestore tar with S3 upload
- **One-command tenant provisioning** — `create-customer.sh` handles DB creation + Odoo init
- **Production hardened** — UFW, Fail2Ban, SSH key-only, nginx rate limiting, security headers
- **Scalable** — designed to grow from 1 to 100+ tenants; scaling guide included

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/install/install.sh` | Prepare a fresh Ubuntu 24.04 server |
| `scripts/install/deploy.sh` | Build + launch the full stack |
| `scripts/install/setup-ssl.sh` | Obtain and configure Let's Encrypt SSL |
| `scripts/backup/backup.sh` | Back up all databases and filestore |
| `scripts/restore/restore.sh` | Restore from a backup |
| `scripts/customer/create-customer.sh` | Provision a new tenant |

---

## Documentation

- [Architecture](docs/Architecture.md)
- [Deployment Guide](docs/Deployment.md)
- [Security](docs/Security.md)
- [Backup & Restore](docs/Backup.md)
- [Scaling](docs/Scaling.md)
- [Customer Onboarding](docs/Customers.md)

---

## Requirements

- Docker Engine 24+
- Docker Compose v2
- Ubuntu 24.04 VPS (min 4 GB RAM / 2 vCPU)
- A domain with wildcard DNS support

---

## License

See [LICENSE](LICENSE).
