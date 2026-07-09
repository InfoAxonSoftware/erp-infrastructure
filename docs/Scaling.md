# Scaling Guide

## Current Baseline

The current deployment is intentionally small and demo-focused.

```text
Single Ubuntu 24.04 VPS
├── 1 vCPU
├── 2 GB RAM
├── 2 GB swap
├── Nginx for infoaxon.lk and www.infoaxon.lk
├── React company website
├── Odoo 18 Community demo
│   ├── one database: infoaxon_erp
│   └── workers = 1
└── PostgreSQL 16
```

This baseline is for demonstrating POS/ERP features to clients. It is not a multi-tenant SaaS capacity plan.

## Current Tuning

| Component | Current setting | Reason |
|-----------|-----------------|--------|
| Odoo workers | `1` | Matches 1 vCPU and reduces memory pressure |
| Odoo cron threads | `1` | Keeps background work modest |
| Odoo DB connections | `16` | Prevents unnecessary PostgreSQL connection pressure |
| PostgreSQL max connections | `50` | Enough for the demo without over-allocating memory |
| PostgreSQL shared buffers | `256MB` | Reasonable for 2 GB RAM |
| PostgreSQL effective cache | `1GB` | Assumes OS cache helps on the small VPS |

## When To Scale Up

Move to a larger server if any of these are consistently true:

- Odoo pages are slow during demos.
- The Odoo container is near its memory limit.
- The host is swapping heavily during normal use.
- CPU is saturated for long periods.
- Website availability is affected by ERP demo load.

## Future Vertical Scaling

For a larger single server, resize the VPS first, then retune Odoo and PostgreSQL.

| Future use | RAM | vCPU | Notes |
|------------|-----|------|-------|
| More comfortable demo server | 4 GB | 2 | Better Odoo responsiveness |
| Light internal ERP use | 8 GB | 4 | More workers and DB cache |
| Heavier internal use | 16 GB | 8 | Separate monitoring and stricter backups |

Odoo worker guidance for future larger hosts:

```text
workers = (2 * CPU cores) + 1
```

Do not apply that formula to the current 1 vCPU server; it is intentionally set to `workers = 1`.

PostgreSQL future tuning examples:

| Server RAM | shared_buffers | effective_cache_size |
|------------|----------------|----------------------|
| 4 GB | 256 MB | 1 GB |
| 8 GB | 512 MB | 2 GB |
| 16 GB | 1 GB | 4 GB |
| 32 GB | 4 GB | 12 GB |

## Future Multi-Tenant Hosting

Multi-tenant customer hosting is not active today. Before restoring it, plan for:

- More CPU and RAM
- Odoo hostname routing
- A reviewed `dbfilter` strategy
- Wildcard DNS and certificate strategy
- Per-customer backup and restore procedures
- Monitoring, alerting, and off-server backups

## Future Separate Database Server

For a larger deployment, PostgreSQL can move to a dedicated database server.

```text
App Server                 DB Server
├── Nginx                  ├── PostgreSQL 16
├── Odoo                   └── PgBouncer
└── React
```

Use a private network between servers, update Odoo's `HOST`, and migrate data using the backup/restore scripts or a planned PostgreSQL migration.

## Future Multiple Odoo App Servers

For high-concurrency use, put multiple Odoo app servers behind a load balancer and use a shared filestore.

Options for shared filestore:

- NFS
- S3-compatible object storage with an Odoo addon
- Another reviewed shared storage system

This is future guidance only and is outside the current VPS deployment.

## Monitoring

Useful checks as the deployment grows:

```bash
docker stats
docker logs -f erp-odoo
docker logs -f erp-postgres
```

For larger deployments, add external monitoring such as Netdata, Prometheus/Grafana, or a hosted uptime monitor.
