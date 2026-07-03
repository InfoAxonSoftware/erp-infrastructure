# Scaling Guide

## Current Architecture (Phase 1 — Single VPS)

Everything runs on one server. Suitable for 0–50 active tenants with moderate usage.

```
Single VPS (4–16 GB RAM)
├── Nginx
├── Odoo (4 workers)
├── PostgreSQL
└── React (static, very lightweight)
```

**Recommended VPS sizing:**

| Tenants | RAM | vCPU | Disk |
|---------|-----|------|------|
| 1–10    | 4 GB | 2 | 80 GB |
| 10–30   | 8 GB | 4 | 160 GB |
| 30–60   | 16 GB | 8 | 320 GB |
| 60–100  | 32 GB | 16 | 640 GB |

---

## Phase 2 — Vertical Scaling

The fastest short-term scaling strategy: resize the VPS.

```bash
# On DigitalOcean: Power off → Resize → Power on
# No code changes required — Docker starts cleanly on bigger hardware

# Tune Odoo workers for new CPU count
# In config/odoo/odoo.conf:
#   workers = (2 × CPU cores) + 1
```

**Also tune PostgreSQL:** The `command` in `compose.yml` sets `shared_buffers=256MB`. Update for more RAM:

| Server RAM | shared_buffers | effective_cache_size |
|------------|---------------|---------------------|
| 4 GB | 256 MB | 1 GB |
| 8 GB | 512 MB | 2 GB |
| 16 GB | 1 GB | 4 GB |
| 32 GB | 4 GB | 12 GB |

---

## Phase 3 — Separate Database Server

Move PostgreSQL to a dedicated database server for better isolation and independent scaling.

**New architecture:**
```
VPS-1 (App Server)         VPS-2 (DB Server)
├── Nginx                  ├── PostgreSQL 16
├── Odoo (8 workers)       └── PgBouncer (connection pooler)
└── React

Private network between VPS-1 and VPS-2 (DigitalOcean VPC)
```

**Steps:**
1. Provision a second VPS in the same data center
2. Enable DigitalOcean VPC between both droplets
3. Install PostgreSQL on VPS-2
4. Update `docker/compose.yml`:
   ```yaml
   # Remove postgres service from app server
   # Point Odoo at the DB server's private IP:
   environment:
     HOST: 10.100.0.2  # private IP of DB server
   ```
5. Migrate data: `pg_dumpall | psql` or use backup/restore scripts

---

## Phase 4 — Multiple Odoo App Servers + Load Balancer

For 100+ tenants or high-concurrency workloads:

```
                    Load Balancer (Nginx or HAProxy)
                   /          |          \
          Odoo-1          Odoo-2         Odoo-3
          (8 workers)     (8 workers)    (8 workers)
                   \          |          /
                    PostgreSQL (dedicated)

Shared volumes via NFS or S3-compatible object storage (filestore)
```

**Key challenge:** The Odoo filestore must be shared across all app servers.

Options:
1. **NFS mount** — Simple, works well for small clusters
2. **S3/Spaces** — Use [odoo-s3](https://github.com/xcg340122/odoo_s3) addon
3. **GlusterFS** — Distributed FS, more resilient

**Load balancer config (sticky sessions required):**
```nginx
upstream odoo_cluster {
    ip_hash;  # Sticky sessions by client IP
    server odoo-1:8069;
    server odoo-2:8069;
    server odoo-3:8069;
}
```

---

## Phase 5 — Database Replication (High Availability)

For zero-downtime requirements:

```
PostgreSQL Primary (read/write)
        │
        │ streaming replication
        ▼
PostgreSQL Replica (read-only)
        │
        │ failover via Patroni / pg_auto_failover
        ▼
    Standby (promoted to Primary on failure)
```

**Tools:**
- [Patroni](https://github.com/patroni/patroni) — HA PostgreSQL cluster manager
- [pgBackRest](https://pgbackrest.org/) — enterprise-grade backup with PITR
- [PgBouncer](https://www.pgbouncer.org/) — connection pooler (critical at scale)

---

## CDN Integration

Offload static assets from Nginx to a CDN:

1. **Cloudflare (Free tier):** Proxy your domain through Cloudflare
   - Enable caching for `/web/static/*`
   - DDoS protection is included
   - No config changes needed in Nginx

2. **DigitalOcean Spaces CDN:**
   - Store Odoo attachments in Spaces
   - Requires the `web_s3` Odoo addon

---

## Performance Monitoring

Recommended tools for tracking performance as you scale:

```bash
# Real-time container resource usage
docker stats

# PostgreSQL query analysis
docker exec -it erp-postgres psql -U odoo -c \
  "SELECT query, calls, total_exec_time, mean_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Enable pg_stat_statements in compose.yml:
# command: postgres -c shared_preload_libraries=pg_stat_statements
```

**External monitoring (recommended for production):**
- [Netdata](https://www.netdata.cloud/) — server-level monitoring
- [Prometheus + Grafana](https://grafana.com/) — full observability stack
- [Sentry](https://sentry.io/) — application error tracking for Odoo

---

## Scaling Decision Checklist

| Symptom | Action |
|---------|--------|
| Slow page loads (>3s) | Check Odoo workers (`workers` in odoo.conf), increase RAM |
| High DB CPU | Add indexes, enable `pg_stat_statements`, consider read replica |
| Odoo OOM kills | Increase `limit_memory_hard`, add more RAM or reduce workers |
| Nginx 502 errors | Check Odoo health, increase `proxy_read_timeout` |
| Disk filling up | Review filestore size, implement S3 offloading, clean old logs |
| >80% CPU sustained | Move to larger VPS or add second app server |
