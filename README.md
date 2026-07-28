# ERP Infrastructure

Docker Compose infrastructure for the InfoAxon company website and a small Odoo 18 Community demo instance on an Ubuntu 24.04 VPS.

## Current Target

| Item | Current deployment |
|------|--------------------|
| VPS | 1 vCPU, 2 GB RAM, 2 GB swap recommended |
| Website | React app cloned from `REACT_REPO_URL` into `docker/react/app` during deploy |
| ERP demo | Odoo 18 Community, multiple demo databases allowed |
| Database | PostgreSQL 16, Docker-network only |
| Reverse proxy | Nginx for `infoaxon.lk` and `www.infoaxon.lk` |

## Network Shape

```text
Internet
  -> Nginx :80/:443 -> React website
  -> Odoo :8069     -> temporary direct demo access

Odoo -> PostgreSQL :5432 over the private Docker backend network
Odoo workers=0 handles websocket traffic through :8069
```

PostgreSQL is never published publicly. Port `8072` is not published or required for this direct-IP demo mode.

## Official Deployment Command

Docker Compose services are gated behind `profiles`: `postgres` is always shared and unprofiled; `react`, `company-backend`, and `nginx` are in the `website` profile; `odoo` is in the `odoo-community` profile. A raw, unflagged `docker compose up` no longer starts the full stack — it only starts `postgres`. Always deploy through `scripts/install/deploy.sh`, which selects the correct profile(s) for you.

On a prepared server, use:

```bash
bash scripts/install/deploy.sh
```

This is equivalent to `--stack website,odoo-community` and remains the default — it deploys the full current stack exactly as before.

To deploy a single stack:

```bash
bash scripts/install/deploy.sh --stack website
bash scripts/install/deploy.sh --stack odoo-community
```

Deploying a subset does **not** stop or remove containers for a stack that isn't selected. For example, `--stack website` never touches an already-running `erp-odoo` container, and vice versa. PostgreSQL is shared by both stacks and always starts regardless of selection. Odoo continues to use direct port `8069` access in this phase (nginx does not proxy Odoo). Existing volume names (`postgres_data`, `odoo_data`, `odoo_filestore`, `website_uploads`) are unchanged.

For website SSL after DNS for `infoaxon.lk` and `www.infoaxon.lk` points at the server (`--ssl` requires the website stack to be selected):

```bash
bash scripts/install/deploy.sh --stack website,odoo-community --ssl
```

The deploy script always uses:

```bash
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml
```

See [Deployment](docs/Deployment.md) for the full `--stack` reference.

## Fresh Server Flow

```bash
sudo bash scripts/install/install.sh
git clone https://github.com/InfoAxonSoftware/erp-infrastructure.git /opt/erp/repo
cd /opt/erp/repo
cp .env.example .env
nano .env
bash scripts/install/deploy.sh
```

Set strong values for `POSTGRES_PASSWORD`, `ODOO_ADMIN_PASSWORD`, and the real `REACT_REPO_URL`.

## Access

- Website: `http://infoaxon.lk` or `https://infoaxon.lk` after SSL setup.
- Odoo demo: `http://SERVER_IP:8069`.

Odoo does not currently have a public domain or SSL certificate in this deployment.

## Backups

```bash
bash scripts/backup/backup.sh
bash scripts/restore/restore.sh <timestamp> --all-dbs --filestore
```

Local backups under `backups/` are not disaster recovery. Copy them off the VPS.

## Documentation

- [Architecture](docs/Architecture.md)
- [Quick Deploy](docs/QuickDeploy.md)
- [Deployment](docs/Deployment.md)
- [Backup and Restore](docs/Backup.md)
- [Customer Provisioning](docs/Customers.md)
- [Scaling](docs/Scaling.md)
- [Security](docs/Security.md)
