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

Configure `DOMAIN`, `POSTGRES_PASSWORD`, `ODOO_ADMIN_PASSWORD`, `WEBSITE_DB_PASSWORD`, `REACT_REPO_URL`, and `REACT_BRANCH` in `.env` before deployment. Also run:

```bash
cp docker/company-backend/.env.production.example docker/company-backend/.env.production
chmod 600 docker/company-backend/.env.production
nano docker/company-backend/.env.production
```

The backend env file is gitignored. Configure `JWT_SECRET`, `JWT_EXPIRES_IN`, `CLIENT_URL`, `INITIAL_ADMIN_USERNAME`, `INITIAL_ADMIN_PASSWORD`, and `UPLOAD_MAX_SIZE`. Compose supplies `DATABASE_URL`, `NODE_ENV=production`, and `PORT=5000`. The backend is not published on a host port.

The external website repository must provide `package.json` and `package-lock.json` at its root, plus `server/index.js`, `server/prisma/schema.prisma`, committed production migrations under `server/prisma/migrations/`, and an idempotent seed script if seeding is supported. Backend source lives under `server/`, but dependencies are installed from the repository root. The backend image starts with `node server/index.js`. The persistent `website_uploads` volume is mounted at `/app/server/uploads`, matching middleware that writes to `server/uploads` relative to the repository root. Its frontend production configuration must call relative `/api` and `/uploads` URLs; it must not bake `localhost:5000` into the production bundle.

## Normal Update

```bash
cd /opt/erp/repo
git pull origin main
bash scripts/install/deploy.sh
```

The deploy pulls the external repository, builds both images, creates/updates the separate `infoaxon_web` role and `infoaxon_website` database, runs `prisma migrate deploy`, and recreates only changed containers. It never runs `down -v` or deletes named volumes.

## Website Backend Operations

Apply committed migrations manually:

```bash
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml run --rm company-backend npx prisma migrate deploy --schema=server/prisma/schema.prisma
```

Run the external repo's seed only after confirming it is idempotent (upsert/skip-existing behavior):

```bash
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml run --rm company-backend npx prisma db seed --schema=server/prisma/schema.prisma
```

The deploy intentionally does not seed automatically. To create or rotate the production admin password, update `INITIAL_ADMIN_PASSWORD` in `docker/company-backend/.env.production`, then run the external server's documented idempotent admin seed/CLI command. If its seed consumes `INITIAL_ADMIN_PASSWORD`, run the seed command above, remove the plaintext value afterward if the app no longer needs it at runtime, and recreate the backend with `docker compose ... up -d --force-recreate company-backend`. Rotating this env value alone does not change an already-hashed database password unless the external app explicitly implements that behavior. The seed must use create-if-missing/upsert behavior and must not overwrite an existing administrator password on routine deployment.

Logs and status:

```bash
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml ps
docker logs --tail 100 -f erp-company-backend
docker logs --tail 100 -f erp-nginx
```

Rollback: check out the previous infrastructure revision and the previous external website revision, then run the deploy script. Prisma migrations are forward-only in normal production use; before a destructive migration, take a database backup and write/test an explicit compensating migration. Do not use `prisma migrate dev`, delete `postgres_data`/`website_uploads`, or run `docker compose down -v`.

## Backup

```bash
bash scripts/backup/backup.sh
```

## Restore

```bash
bash scripts/restore/restore.sh <timestamp> --all-dbs --filestore
```

## Third-Party Odoo Addons

Before installing third-party modules, take a backup:

```bash
bash scripts/backup/backup.sh
```

Copy or extract the Odoo 18 addon directory into `custom-addons/`. For example, `base_accounting_kit` should end up as:

```text
custom-addons/base_accounting_kit/__manifest__.py
```

Do not commit downloaded third-party module code unless its license permits redistribution.

Redeploy so Odoo sees the mounted addon path:

```bash
bash scripts/install/deploy.sh
```

Then open Odoo, enable developer mode if needed, update the Apps List, search for the module in Apps, and install it from there.

## Database Manager

Open:

```text
http://SERVER_IP:8069/web/database/manager
```

The Odoo master password is the `ODOO_ADMIN_PASSWORD` value from `.env`.

`list_db = True` and `dbfilter = .*` are intentional for development and client demonstration use. They allow administrators to create, list, and switch between multiple Odoo databases.

Warning: port `8069` and the Odoo database manager are publicly reachable in this demo configuration. Keep `ODOO_ADMIN_PASSWORD` strong, share access carefully, and do not use this exposure pattern for production.

## Odoo Module Recovery

This small direct-IP demo VPS intentionally uses `workers = 0`. Odoo handles websocket traffic through the normal HTTP server on `8069`, avoiding the separate gevent/websocket reverse-proxy requirement.

Module installation can still take several minutes on 1 vCPU. If a browser installation times out, recover from the CLI:

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

## Verification Commands

```bash
docker ps
docker stats --no-stream
docker compose --env-file .env -f docker/compose.yml -f docker/compose.prod.yml config
docker logs --tail 50 erp-odoo
docker logs --tail 50 erp-postgres
docker logs --tail 50 erp-company-backend
```
