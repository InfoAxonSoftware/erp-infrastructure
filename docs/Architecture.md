# Architecture

## Overview

This repository now targets the real small VPS development/demo deployment: the InfoAxon React company website plus Odoo 18 Community with multiple demo databases.

```text
                         Internet
                            |
             +--------------+--------------+
             |                             |
       Nginx :80/:443                 Odoo :8069
       infoaxon.lk                    temporary direct demo access
       www.infoaxon.lk                http://SERVER_IP:8069
             |
          React

       Odoo -> PostgreSQL :5432 on Docker backend network only
```

## Services

| Service | Role | Public ports |
|---------|------|--------------|
| `nginx` | Reverse proxy for the React website | `80`, `443` |
| `react` | Built static website from external React repository | none |
| `odoo` | Odoo 18 demo instance | `8069` temporarily |
| `postgres` | PostgreSQL 16 database server | none |

## Docker Networks

| Network | Services | Purpose |
|---------|----------|---------|
| `frontend` | `nginx`, `react`, `odoo` | Website proxying and optional internal Odoo proxying |
| `backend` | `odoo`, `postgres` | Private database traffic |

PostgreSQL has no published host port.

## Odoo Demo Databases

`config/odoo/odoo.conf` is intentionally configured for development and client demonstrations:

```ini
dbfilter = .*
list_db = True
proxy_mode = False
workers = 0
max_cron_threads = 1
db_maxconn = 16
limit_time_cpu = 600
limit_time_real = 1200
```

Multiple demo databases are allowed, and the Odoo database listing and database manager are enabled intentionally so administrators can create and switch databases during demos. This is not suitable for production without additional access controls.

`workers = 0` is intentional for this small direct-IP demo VPS. Odoo uses the normal HTTP server for websocket handling, which avoids the separate gevent/websocket reverse-proxy requirement and removes the need to expose port `8072`. Module installation can still take several minutes on 1 vCPU.

If a module installation times out in the browser, recover from the CLI by running Odoo once with longer limits and `--stop-after-init`, replacing `DATABASE_NAME` and `MODULE_NAME`:

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

PostgreSQL remains private on the Docker `backend` network. Odoo port `8069` is temporarily public for direct demo access, including `/web/database/manager`.

## React External Repository

The React source is not stored in this infrastructure repository. During deployment, `scripts/install/deploy.sh` clones or updates `REACT_REPO_URL` into:

```text
docker/react/app
```

The existing `docker/react/Dockerfile` then builds that source into a static Nginx image.

## SSL Scope

`scripts/install/setup-ssl.sh` configures HTTP-01 certificates only for:

- `infoaxon.lk`
- `www.infoaxon.lk`

Wildcard tenant routing and Odoo subdomain routing are disabled for now. They can be restored later from Git history if the project becomes multi-tenant again.
