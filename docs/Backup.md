# Backup and Restore

## Important Warning

Backups stored only under this server's local `backups/` directory are not disaster recovery. They help with quick rollback, but a lost VPS means lost local backups. Copy backup folders to off-server storage such as S3, another VPS, or a secured archive.

Do not commit backups, `.env`, passwords, or certificates to Git.

## What Is Backed Up

| Component | Method |
|-----------|--------|
| Odoo databases | One custom-format `pg_dump` per non-template PostgreSQL database except maintenance `postgres` |
| Registry table | `_registry.dump` if `public.tenant_registry` exists in `postgres` |
| Odoo filestore | `filestore.tar.gz` from the `erp-platform_odoo_filestore` volume |
| Manifest | `manifest.txt` with timestamp, host, and backup contents |

## Run a Backup

```bash
bash scripts/backup/backup.sh
```

Optional modes:

```bash
bash scripts/backup/backup.sh --db-only
bash scripts/backup/backup.sh --filestore-only
```

Backup layout:

```text
backups/
  2026-07-09_02-00-00/
    manifest.txt
    postgres/
      infoaxon_erp.dump
      _registry.dump
    filestore/
      filestore.tar.gz
```

## Recommended Cron

```cron
0 2 * * * cd /opt/erp/repo && bash scripts/backup/backup.sh >> logs/backup.log 2>&1
```

Also configure off-server copy. If `S3_BUCKET` is set and the AWS CLI is installed/configured, the script uploads the backup folder.

## Emergency Restore

For a full server recovery:

1. Provision a new Ubuntu 24.04 VPS.
2. Run `scripts/install/install.sh`.
3. Clone this repository into `/opt/erp/repo`.
4. Restore `.env` from a secure password manager or vault.
5. Copy the required backup folder into `backups/`.
6. Run `bash scripts/install/deploy.sh`.
7. Restore data:

```bash
bash scripts/restore/restore.sh <timestamp> --all-dbs --filestore
```

8. Point DNS to the new server.
9. Run `bash scripts/install/deploy.sh --ssl`.

## Restore Options

Restore everything:

```bash
bash scripts/restore/restore.sh <timestamp> --all-dbs --filestore
```

Restore one database:

```bash
bash scripts/restore/restore.sh <timestamp> --db infoaxon_erp
```

Restore filestore only:

```bash
bash scripts/restore/restore.sh <timestamp> --filestore
```

When `--all-dbs` is used, `_registry.dump` is restored automatically if it exists.
