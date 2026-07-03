# Backup & Restore Guide

## Backup Strategy

| Component | What is backed up | Format | Frequency (recommended) |
|-----------|-------------------|--------|--------------------------|
| PostgreSQL | All tenant databases | Custom pg_dump | Daily |
| Odoo filestore | Attachments, documents, images | tar.gz | Daily |
| Configuration | `.env`, nginx templates, odoo.conf | Git (versioned) | On change |

**Retention:** 14 days of local backups by default (configurable via `BACKUP_RETENTION_DAYS` in `.env`).

---

## Running a Backup

### Manual backup

```bash
# Full backup (databases + filestore)
bash scripts/backup/backup.sh

# Databases only
bash scripts/backup/backup.sh --db-only

# Filestore only
bash scripts/backup/backup.sh --filestore-only
```

Backup output location:
```
backups/
└── 2025-01-15_02-00-00/
    ├── manifest.txt
    ├── postgres/
    │   ├── company1.dump
    │   ├── company2.dump
    │   └── _registry.dump
    └── filestore/
        └── filestore.tar.gz
```

### Automated daily backup (cron)

Add to the `erp` user crontab (`crontab -e`):

```cron
# Daily backup at 2:00 AM
0 2 * * * cd /opt/erp/repo && bash scripts/backup/backup.sh >> logs/backup.log 2>&1

# Weekly full backup with log rotation
0 3 * * 0 cd /opt/erp/repo && bash scripts/backup/backup.sh 2>&1 | logger -t erp-backup
```

---

## Off-Site Backup (S3)

Add to `.env`:
```dotenv
S3_BUCKET=my-erp-backups
BACKUP_RETENTION_DAYS=14
```

The backup script automatically uploads to `s3://my-erp-backups/erp-backups/<timestamp>/` if `aws` CLI is installed and `S3_BUCKET` is set.

**Install AWS CLI:**
```bash
sudo snap install aws-cli --classic
aws configure  # Enter access key, secret, region
```

**Required IAM permissions:**
```json
{
  "Effect": "Allow",
  "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
  "Resource": ["arn:aws:s3:::my-erp-backups/*"]
}
```

---

## Restore Procedure

### List available backups
```bash
ls -la backups/
```

### Restore a single tenant database

```bash
bash scripts/restore/restore.sh 2025-01-15_02-00-00 --db company1
```

### Restore all databases

```bash
bash scripts/restore/restore.sh 2025-01-15_02-00-00 --all-dbs
```

### Restore filestore

```bash
bash scripts/restore/restore.sh 2025-01-15_02-00-00 --filestore
```

### Full restore (databases + filestore)

```bash
bash scripts/restore/restore.sh 2025-01-15_02-00-00 --all-dbs --filestore
```

> **Warning:** The restore script will STOP Odoo, DROP and recreate databases, and overwrite the filestore volume. It prompts for confirmation before each destructive action.

---

## Testing Backups

Test your backups monthly to ensure they are valid:

```bash
# Verify a database dump can be read
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  pg_restore --list backups/2025-01-15_02-00-00/postgres/company1.dump | head -20

# Verify filestore archive integrity
tar -tzf backups/2025-01-15_02-00-00/filestore/filestore.tar.gz | head -20

# Test restore to a temporary database
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres -c "CREATE DATABASE company1_test;"

docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  pg_restore -U odoo -d company1_test --no-owner \
  < backups/2025-01-15_02-00-00/postgres/company1.dump

docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" erp-postgres \
  psql -U odoo -d postgres -c "DROP DATABASE company1_test;"
```

---

## Disaster Recovery

### Scenario: Complete server loss

1. Provision a new VPS
2. Run `install.sh` on the new server
3. Clone the repository
4. Copy `.env` from a secure location (password manager / vault)
5. Copy backups from S3 (or your remote storage) to `backups/`
6. Deploy the stack: `bash scripts/install/deploy.sh`
7. Restore all data: `bash scripts/restore/restore.sh <latest-timestamp> --all-dbs --filestore`
8. Update DNS to point to the new server IP
9. Re-request SSL certificates: `bash scripts/install/deploy.sh --ssl`

**Estimated RTO (Recovery Time Objective):** 30–60 minutes with good documentation and off-site backups.
