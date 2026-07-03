# Security Guide

## Overview

This document covers the security measures implemented in the ERP infrastructure and the steps required to maintain a hardened production environment.

---

## 1. Firewall (UFW)

The install script configures UFW with a default-deny policy:

```bash
# View current rules
ufw status verbose

# Allow an additional port (e.g., for monitoring)
ufw allow 9090/tcp comment 'Prometheus'

# Check if a port is blocked
ufw status | grep 5432
```

**Blocked by default:**
- Port 5432 (PostgreSQL) — accessible only within the `backend` Docker network
- Port 8069 (Odoo) — accessible only through Nginx
- Port 8072 (Odoo longpolling) — internal only

---

## 2. Fail2Ban

Fail2Ban monitors log files and bans IPs after repeated failures.

```bash
# View banned IPs
fail2ban-client status sshd
fail2ban-client status nginx-limit-req

# Unban an IP
fail2ban-client set sshd unbanip <ip-address>

# Reload config after changes
fail2ban-client reload
```

**Active jails:**
| Jail | Max retries | Ban time |
|------|------------|----------|
| `sshd` | 3 | 24 hours |
| `nginx-http-auth` | 5 | 1 hour |
| `nginx-limit-req` | 10 | 10 minutes |

---

## 3. SSH Hardening

Applied by `install.sh`:

```
PermitRootLogin        prohibit-password
PasswordAuthentication no
MaxAuthTries           3
LoginGraceTime         30s
X11Forwarding          no
AllowTcpForwarding     no
```

**Best practices:**
- Use Ed25519 SSH keys: `ssh-keygen -t ed25519 -C "deploy@yourdomain.com"`
- Rotate keys annually
- Consider changing the SSH port (update UFW rule and `SSH_PORT` var in install.sh)
- Use `AllowUsers erp` to restrict SSH to only the deploy user

---

## 4. Docker Security

### No privileged containers
All containers run as non-root users:
- Odoo: runs as user `odoo` (uid 101)
- Nginx: runs as user `nginx`
- PostgreSQL: runs as user `postgres`

### Network isolation
- PostgreSQL is only accessible from the `backend` network
- React and Nginx are only on the `frontend` network
- Odoo bridges both networks but is not directly exposed

### Read-only config mounts
```yaml
- ./config/odoo/odoo.conf:/etc/odoo/odoo.conf:ro
- ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
```

### No secrets in images
- All secrets passed via environment variables from `.env`
- `.env` is in `.gitignore` and never committed
- `ODOO_ADMIN_PASSWORD` is injected at runtime via `entrypoint.sh`

### Resource limits (compose.prod.yml)
Memory and CPU limits prevent a single container from exhausting the server:
```yaml
deploy:
  resources:
    limits:
      cpus: '4.0'
      memory: 4G
```

---

## 5. Nginx Security Headers

Applied to all server blocks:

```nginx
add_header X-Frame-Options           "SAMEORIGIN"                     always;
add_header X-Content-Type-Options    "nosniff"                        always;
add_header X-XSS-Protection          "1; mode=block"                  always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=()" always;
```

When HTTPS is enabled, also add:
```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

**Rate limiting:**
- General requests: 20 req/s with burst of 30
- Login endpoint: 5 req/min (prevents brute-force)
- Connection limit: 20 concurrent per IP

---

## 6. SSL/TLS

Configuration in `nginx.conf`:

```nginx
ssl_protocols             TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_session_cache         shared:SSL:10m;
ssl_session_timeout       1d;
ssl_session_tickets       off;
ssl_stapling              on;
ssl_stapling_verify       on;
```

**Achieves an A+ rating on SSL Labs.**

Let's Encrypt certificates auto-renew via cron (registered by `setup-ssl.sh`).

---

## 7. Odoo Security Settings

| Setting | Value | Reason |
|---------|-------|--------|
| `list_db = False` | Disabled | Prevents enumeration of tenant databases |
| `proxy_mode = True` | Enabled | Trusts X-Forwarded-For from Nginx |
| `admin_passwd` | Random 32+ chars | Protects database manager |
| `/web/database/manager` | Blocked in Nginx | Additional layer of protection |

**Nginx blocks direct access to the DB manager:**
```nginx
location = /web/database/manager  { deny all; return 403; }
location = /web/database/selector { deny all; return 403; }
```

---

## 8. PostgreSQL Security

- Not exposed to any public network or port
- Accessible only from within the Docker `backend` network
- Odoo user has only the permissions needed (CREATEDB for tenant provisioning)
- Connection logging enabled: `log_min_duration_statement=1000ms`

**Connection security:**
```bash
# Connect securely from within the stack
docker exec -it erp-postgres psql -U odoo
```

---

## 9. Secret Management

**For production, consider using Docker Secrets or a vault:**

```bash
# Example: use Docker secrets instead of env vars
echo "my-strong-password" | docker secret create postgres_password -
```

Or integrate with **HashiCorp Vault** or **AWS Secrets Manager** for enterprise deployments.

**Minimum password requirements:**
- POSTGRES_PASSWORD: 32+ character random string
- ODOO_ADMIN_PASSWORD: 32+ character random string

Generate secure passwords:
```bash
openssl rand -base64 32
```

---

## 10. Security Checklist

Before going to production, verify:

- [ ] `.env` is not committed to git
- [ ] SSH password authentication is disabled
- [ ] UFW is enabled with correct rules
- [ ] Fail2Ban is running
- [ ] SSL certificates are valid (`curl -I https://yourerp.com`)
- [ ] HSTS header is present
- [ ] Odoo DB manager is inaccessible from browser
- [ ] PostgreSQL port 5432 is not reachable from outside
- [ ] Backups are running and tested
- [ ] Docker images are up to date (`docker compose pull`)
- [ ] OS is up to date (`apt upgrade`)
