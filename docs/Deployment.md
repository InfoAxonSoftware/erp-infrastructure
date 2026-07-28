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
- Blocked: PostgreSQL `5432`

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

`docker/compose.yml` gates services behind Compose `profiles`: `postgres` is shared and unprofiled; `react`, `company-backend`, and `nginx` are in the `website` profile; `odoo` is in the `odoo-community` profile. Compose renders the full file for every command, so an inactive profiled service (e.g. `odoo` when only `website` is selected) may be interpolated with an empty default for its stack-specific secret — that service is simply not started. `scripts/install/deploy.sh` is the supported deployment entrypoint and is the actual enforcement point: it validates that a required variable is present *before* invoking Compose, for whichever stack was selected. Raw, unflagged `docker compose up` is not the supported deployment method and starts only the unprofiled `postgres` service.

The official deployment command is:

```bash
bash scripts/install/deploy.sh
```

`--stack` is optional. When omitted it defaults to `website,odoo-community` — the full current stack, deployed exactly as before. Supported values:

```bash
bash scripts/install/deploy.sh --stack website
bash scripts/install/deploy.sh --stack odoo-community
bash scripts/install/deploy.sh --stack website,odoo-community
```

`--stack odoo-community,website` (reversed order) is equivalent to `--stack website,odoo-community`. Unknown stack names, empty values, duplicate entries, and `odoo-enterprise` are rejected before anything is changed.

Deploying a subset never stops, removes, or recreates containers for a stack that wasn't selected — `--stack website` leaves an already-running `erp-odoo` untouched, and `--stack odoo-community` leaves `erp-react`/`erp-company-backend`/`erp-nginx` untouched. PostgreSQL is shared by both stacks and always starts regardless of selection, since Odoo and the website use it as a common database server with separate databases. Odoo continues to use direct port `8069` access in this phase; Nginx does not proxy Odoo. All existing volume names, container names, ports, and SSL behavior are unchanged.

For the selected stack, the script:

- The deployment script validates only the variables required by the selected stack before starting any service.
- When `website` is selected: clones or updates the external React repo into `docker/react/app`, provisions the website database/role, builds `company-backend`/`react`/`nginx`, and runs Prisma migrations.
- When `odoo-community` is selected: builds `odoo` and fixes the Odoo log bind-mount permissions using the Odoo container UID/GID.
- Validates the Compose config for the selected profile(s).
- Creates required log/SSL directories for the selected stack.
- Starts/updates only the selected stack's services using both Compose files, without removing volumes.

## 4. Access

After deployment:

- Website: `http://infoaxon.lk`
- Odoo demo: `http://SERVER_IP:8069`

Odoo is intentionally not configured with a domain or SSL yet.

This small direct-IP demo VPS intentionally uses `workers = 0`. In this mode Odoo handles websocket traffic through the normal HTTP server on `8069`, which avoids a separate gevent/websocket reverse-proxy requirement. Module installation can still take several minutes on 1 vCPU.

If a browser-based module installation times out, recover from the CLI:

```bash
docker compose \
  --env-file .env \
  -f docker/compose.yml \
  -f docker/compose.prod.yml \
  run --rm odoo \
  odoo -d DATABASE_NAME -i MODULE_NAME \
  --stop-after-init \
  --no-http \
  --limit-time-real=1200 \
  --limit-time-cpu=600
```

## 5. Configure Website SSL

After DNS `A` records for `infoaxon.lk` and `www.infoaxon.lk` point at the server:

```bash
bash scripts/install/deploy.sh --stack website,odoo-community --ssl
```

`--ssl` requires the `website` stack to be selected (directly or via the default); it is rejected up front with a clear error if used with `--stack odoo-community` alone. This uses HTTP-01 validation, copies certificates into `ssl/live/infoaxon.lk/`, switches `NGINX_TEMPLATE_PROFILE=https`, and reloads Nginx.

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
