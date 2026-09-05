# Auto Backup Service

A scheduled pipeline running on the selrad-warehouse VPS that dumps the Postgres database nightly, offloads each dump to S3 for durability, and prunes local dumps weekly.

## Language

**Scheduled Task**:
A recurring job on the VPS driven by a systemd timer and service unit.
_Avoid_: Service worker, cron job, background worker

**Backup**:
A gzip'ed pg_dump artifact (`DD-MM-YYYY-gz.sql.gz`) produced nightly by `make pg_dumpdata_gz` in the warehouse repo.
_Avoid_: Dump file, snapshot

**Local Backup Store**:
The `backups/pg-data/` directory on the VPS that holds recent Backups.
_Avoid_: Backups dir, local storage

**Archive**:
A Backup that has been copied into S3 and now lives off the VPS.
_Avoid_: Cloud backup, S3 backup

**Offload**:
Copying a Backup from the Local Backup Store into S3.
_Avoid_: Upload, push to cloud

**Prune**:
Deleting a Backup from the Local Backup Store only after that Backup is confirmed present as an Archive in S3.
_Avoid_: Cleanup, delete backups

**Cold Storage**:
The long-term storage tier for Archives in S3, described by a storage-class policy on the bucket.
_Avoid_: The bucket itself

## Example Dialogue

Dev: "Do we delete nightly files?"
Domain expert: "We Offload them to S3 first and confirm they're there, then Prune them locally once a week. Never Prune a Backup that hasn't been confirmed as an Archive."

Dev: "Should the script also pick up `warehouse-17-07-2026-gz.sql.gz`?"
Domain expert: "No. The Backups we manage are the `DD-MM-YYYY-gz.sql.gz` files. Legacy files stay until we decide their fate."