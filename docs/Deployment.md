# Deployment Guide

## Target Server

- Ubuntu 24.04 VPS
- 1 vCPU
- 2 GB RAM
- 2 GB swap configured by `install.sh`
- Docker Compose v2

## 1. Prepare the Server

Run as `root` on a fresh server:

```bash
sudo bash scripts/install/install.sh
```

The installer configures Docker, a deploy user, SSH key authentication, Fail2Ban, UFW, Certbot, basic kernel tuning, and a 2 GB swap file.

Firewall policy:

- Open: SSH, `80`, `443`, temporary Odoo demo port `8069`
- Blocked: PostgreSQL `5432`, Odoo gevent `8072`

## 2. Clone and Configure

```bash
git clone https://github.com/InfoAxonSoftware/erp-infrastructure.git /opt/erp/repo
cd /opt/erp/repo
cp .env.example .env
nano .env
```

Set at least:

```dotenv
DOMAIN=infoaxon.lk
POSTGRES_PASSWORD=<strong-random-password>
ODOO_ADMIN_PASSWORD=<strong-random-password>
REACT_REPO_URL=<react-website-repository-url>
NGINX_TEMPLATE_PROFILE=http
```

Never commit `.env`.

## 3. Deploy

The official deployment command is:

```bash
bash scripts/install/deploy.sh
```

The script:

- Loads root `.env` explicitly.
- Clones or updates the external React repo into `docker/react/app`.
- Validates the combined Compose config.
- Builds images.
- Creates required log and SSL directories.
- Fixes the Odoo log bind-mount permissions using the Odoo container UID/GID.
- Starts the stack using both Compose files.

## 4. Access

After deployment:

- Website: `http://infoaxon.lk`
- Odoo demo: `http://SERVER_IP:8069`

Odoo is intentionally not configured with a domain or SSL yet.

## 5. Configure Website SSL

After DNS `A` records for `infoaxon.lk` and `www.infoaxon.lk` point at the server:

```bash
bash scripts/install/deploy.sh --ssl
```

This uses HTTP-01 validation, copies certificates into `ssl/live/infoaxon.lk/`, switches `NGINX_TEMPLATE_PROFILE=https`, and reloads Nginx.

No wildcard certificate is requested. No `*.infoaxon.lk` routing is configured.

## Repeatable Redeployment

For updates:

```bash
cd /opt/erp/repo
git pull
bash scripts/install/deploy.sh
```

Use the same command after changing `.env`, Odoo config, Nginx templates, or the external React repo branch.

## Useful Checks

```bash
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml config
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml ps
docker logs -f erp-odoo
docker logs -f erp-nginx
```
