# Deployment Guide

## Prerequisites

- DigitalOcean (or any Ubuntu 24.04) VPS — minimum **4 GB RAM / 2 vCPU / 80 GB SSD**
- A domain name with DNS management access
- SSH access to the server as `root`
- Git installed locally

---

## Step 1 — Provision the VPS

**DigitalOcean:**
1. Create → Droplet → Ubuntu 24.04 LTS
2. Plan: `Basic / Regular` 4 GB RAM (scale up later)
3. Authentication: SSH Key (recommended)
4. Enable backups: optional (we handle our own)
5. Note the server IP address

**DNS Setup** — create these records before requesting SSL:

| Type | Name | Value |
|------|------|-------|
| A | `yourerp.com` | `<server-ip>` |
| A | `www.yourerp.com` | `<server-ip>` |
| A | `erp.yourerp.com` | `<server-ip>` |
| A | `*.yourerp.com` | `<server-ip>` |

> Wildcard `*.yourerp.com` covers all tenant subdomains automatically.

---

## Step 2 — Run the Server Setup Script

SSH into the server and run the installer:

```bash
ssh root@<server-ip>

# Download and run the install script
curl -fsSL https://raw.githubusercontent.com/yourorg/erp-infrastructure/main/scripts/install/install.sh \
  | sudo bash
```

The installer handles:
- System update and essential packages
- Docker Engine + Docker Compose v2
- Deploy user `erp` with Docker access
- UFW firewall (ports 22, 80, 443 open; 5432, 8069 blocked)
- Fail2Ban (SSH brute-force, Nginx rate-limit banning)
- SSH hardening (key-only auth, disable root password)
- Kernel tuning (`sysctl`)
- Certbot for Let's Encrypt

---

## Step 3 — Clone the Repository

```bash
# Switch to the deploy user
su - erp

# Clone the repo
git clone https://github.com/yourorg/erp-infrastructure.git /opt/erp/repo
cd /opt/erp/repo
```

---

## Step 4 — Configure Environment

```bash
cp .env.example .env
nano .env
```

Set these values:

```dotenv
# Your actual domain
DOMAIN=yourerp.com

# Strong random passwords (use: openssl rand -base64 32)
POSTGRES_PASSWORD=<strong-random-password>
ODOO_ADMIN_PASSWORD=<strong-random-password>
```

> **Security:** Never commit `.env` to version control. It is listed in `.gitignore`.

---

## Step 5 — Deploy (HTTP First)

```bash
bash scripts/install/deploy.sh
```

This will:
1. Build all Docker images
2. Start all containers
3. Wait for health checks to pass
4. Print access URLs

Verify the deployment:
```bash
docker compose -f docker/compose.yml -f docker/compose.prod.yml ps
curl http://yourerp.com/health
curl http://erp.yourerp.com/health
```

---

## Step 6 — Configure SSL (Let's Encrypt)

Once DNS is propagated (verify with `dig yourerp.com`):

```bash
bash scripts/install/deploy.sh --ssl
```

This runs `certbot` in manual DNS-challenge mode. Follow the prompts to add TXT records in your DNS panel.

After certificates are issued:
1. The SSL server blocks in nginx templates are uncommented automatically
2. Nginx reloads with HTTPS enabled
3. A cron job for auto-renewal is registered

**Verify SSL:**
```bash
curl -I https://yourerp.com
curl -I https://erp.yourerp.com
```

---

## Step 7 — First Odoo Login

Navigate to `https://erp.yourerp.com` (or `http://` if SSL not yet configured).

> The database manager is **disabled** in production (`list_db = False`). Use `create-customer.sh` to provision tenants.

---

## Step 8 — Add Your First Customer Tenant

```bash
bash scripts/customer/create-customer.sh acmecorp "Acme Corporation" admin@acmecorp.com
```

See [Customers.md](Customers.md) for full details.

---

## Useful Commands

```bash
# View running containers
docker compose -f docker/compose.yml ps

# View Odoo logs
docker logs -f erp-odoo

# View Nginx logs
docker logs -f erp-nginx

# Restart a service
docker compose -f docker/compose.yml restart odoo

# Full restart
docker compose -f docker/compose.yml -f docker/compose.prod.yml restart

# Update and redeploy
git pull
bash scripts/install/deploy.sh
```

---

## Automated Backups (Cron)

Add to the `erp` user's crontab (`crontab -e`):

```cron
# Daily backup at 2 AM
0 2 * * * cd /opt/erp/repo && bash scripts/backup/backup.sh >> logs/backup.log 2>&1
```

---

## Troubleshooting

| Issue | Command |
|-------|---------|
| Container not starting | `docker logs erp-odoo` |
| Nginx 502 Bad Gateway | `docker inspect erp-odoo` (check health status) |
| DB connection error | `docker exec erp-postgres pg_isready -U odoo` |
| Permission error on volumes | `docker exec erp-odoo chown -R odoo:odoo /var/lib/odoo` |
| Nginx config test | `docker exec erp-nginx nginx -t` |
