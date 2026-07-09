# Quick Deploy

## Fresh Server

```bash
sudo bash scripts/install/install.sh
git clone https://github.com/InfoAxonSoftware/erp-infrastructure.git /opt/erp/repo
cd /opt/erp/repo
cp .env.example .env
nano .env
bash scripts/install/deploy.sh
```

Configure `DOMAIN`, `POSTGRES_PASSWORD`, `ODOO_ADMIN_PASSWORD`, `REACT_REPO_URL`, and `REACT_BRANCH` in `.env` before deployment.

## Normal Update

```bash
cd /opt/erp/repo
git pull origin main
bash scripts/install/deploy.sh
```

## Backup

```bash
bash scripts/backup/backup.sh
```

## Restore

```bash
bash scripts/restore/restore.sh <timestamp> --all-dbs --filestore
```

## Database Manager

Open:

```text
http://SERVER_IP:8069/web/database/manager
```

The Odoo master password is the `ODOO_ADMIN_PASSWORD` value from `.env`.

`list_db = True` and `dbfilter = .*` are intentional for development and client demonstration use. They allow administrators to create, list, and switch between multiple Odoo databases.

Warning: port `8069` and the Odoo database manager are publicly reachable in this demo configuration. Keep `ODOO_ADMIN_PASSWORD` strong, share access carefully, and do not use this exposure pattern for production.

## Verification Commands

```bash
docker ps
docker stats --no-stream
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml config
docker logs --tail 50 erp-odoo
docker logs --tail 50 erp-postgres
```
