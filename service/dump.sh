#!/usr/bin/env bash
set -euo pipefail

CONFIG=/etc/auto-backup/config
LOCK_DIR=/run/auto-backup
LOG_DIR=/var/log/auto-backup
PYTHON=/opt/auto-backup/venv/bin/python
OFFLOAD=/opt/auto-backup/service/offload.py

mkdir -p "$LOCK_DIR" "$LOG_DIR"

[ -f "$CONFIG" ] && source "$CONFIG"

: "${WAREHOUSE_INFRA_DIR:?set WAREHOUSE_INFRA_DIR in $CONFIG}"
: "${BUCKET:?set BUCKET in $CONFIG}"
: "${REGION:?set REGION in $CONFIG}"

exec 9>"$LOCK_DIR/auto-backup.lock"
flock -n 9 || { echo "$(date -u +%FT%TZ) another task holds the lock, exiting" >>"$LOG_DIR/dump.log"; exit 0; }

log() { echo "$(date -u +%FT%TZ) $*" >>"$LOG_DIR/dump.log"; }
fail() { log "FAILED $*"; echo failed >"$LOG_DIR/dump.status"; exit 1; }

BACKUP_DIR="$(cd "$WAREHOUSE_INFRA_DIR/../backups/pg-data" && pwd)"

log "nightly dump starting"

make -C "$WAREHOUSE_INFRA_DIR" pg_dumpdata_gz >>"$LOG_DIR/dump.log" 2>&1 \
  || fail "make pg_dumpdata_gz exited $?"

TODAY="$(date +%d-%m-%Y)"
FRESH="$BACKUP_DIR/$TODAY-gz.sql.gz"
if [ ! -f "$FRESH" ]; then
  FRESH="$(ls -t "$BACKUP_DIR"/*-gz.sql.gz 2>/dev/null | head -1 || true)"
fi
[ -n "${FRESH:-}" ] && [ -f "$FRESH" ] || fail "no fresh Backup found in $BACKUP_DIR"

log "Backup produced: $(basename "$FRESH")"

gzip -t "$FRESH" || fail "gzip integrity check failed for $FRESH"

docker compose -f "$WAREHOUSE_INFRA_DIR/docker-compose-dev.yml" exec -T db \
  pg_restore --list <"$FRESH" >/dev/null 2>&1 \
  || fail "pg_restore integrity check failed for $FRESH"

log "integrity checks passed"

"$PYTHON" "$OFFLOAD" --bucket "$BUCKET" --region "$REGION" "$BACKUP_DIR" \
  >>"$LOG_DIR/dump.log" 2>&1 || fail "offload exited $?"

echo ok >"$LOG_DIR/dump.status"
log "nightly dump complete"