#!/usr/bin/env bash
set -euo pipefail

CONFIG=/etc/auto-backup/config
LOCK_DIR=/run/auto-backup
LOG_DIR=/var/log/auto-backup
PYTHON=/opt/auto-backup/venv/bin/python
OFFLOAD=/opt/auto-backup/service/offload.py
RETENTION_DAYS=7

mkdir -p "$LOCK_DIR" "$LOG_DIR"

[ -f "$CONFIG" ] && source "$CONFIG"

: "${WAREHOUSE_INFRA_DIR:?set WAREHOUSE_INFRA_DIR in $CONFIG}"
: "${BUCKET:?set BUCKET in $CONFIG}"
: "${REGION:?set REGION in $CONFIG}"
: "${S3_PREFIX:=warehouse}"
: "${ENDPOINT_URL:=}"

exec 9>"$LOCK_DIR/auto-backup.lock"
flock -n 9 || { echo "$(date -u +%FT%TZ) another task holds the lock, exiting" >>"$LOG_DIR/prune.log"; exit 0; }

log() { echo "$(date -u +%FT%TZ) $*" >>"$LOG_DIR/prune.log"; }
fail() { log "FAILED $*"; exit 1; }

BACKUP_DIR="$(cd "$WAREHOUSE_INFRA_DIR/../backups/pg-data" && pwd)"

log "weekly prune starting"

OFFLOAD_ARGS=(--bucket "$BUCKET" --region "$REGION" --prefix "$S3_PREFIX")
[ -n "$ENDPOINT_URL" ] && OFFLOAD_ARGS+=(--endpoint-url "$ENDPOINT_URL")

"$PYTHON" "$OFFLOAD" "${OFFLOAD_ARGS[@]}" "$BACKUP_DIR" \
  >>"$LOG_DIR/prune.log" 2>&1 || fail "sweep offload exited $?"

CUTOFF="$(date -d "$RETENTION_DAYS days ago" +%s)"

pruned=0
for FILE in "$BACKUP_DIR"/*-gz.sql.gz; do
  [ -f "$FILE" ] || continue
  NAME="$(basename "$FILE")"
  [[ "$NAME" =~ ^([0-9]{2})-([0-9]{2})-([0-9]{4})-gz\.sql\.gz$ ]] || continue
  FILE_EPOCH="$(date -d "${BASH_REMATCH[3]}-${BASH_REMATCH[2]}-${BASH_REMATCH[1]}" +%s 2>/dev/null || true)"
  if [ -n "$FILE_EPOCH" ] && [ "$FILE_EPOCH" -lt "$CUTOFF" ]; then
    rm -f "$FILE"
    log "PRUNED $NAME (Archive confirmed, older than $RETENTION_DAYS days)"
    pruned=$((pruned + 1))
  fi
done

log "weekly prune complete ($pruned Pruned)"