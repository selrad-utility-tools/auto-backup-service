#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUTOBACKUP_DIR=/opt/auto-backup
VENV_DIR="$AUTOBACKUP_DIR/venv"
CONFIG=/etc/auto-backup/config

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0"; exit 1; }

install -d "$AUTOBACKUP_DIR" /etc/auto-backup

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "creating venv at $VENV_DIR"
  python3 -m venv "$VENV_DIR" || { echo "python3-venv not available: apt install python3-venv"; exit 1; }
fi

echo "installing boto3"
"$VENV_DIR/bin/pip" install --upgrade boto3

ln -sfn "$REPO_DIR/service" "$AUTOBACKUP_DIR/service"
chmod +x "$AUTOBACKUP_DIR/service"/*.sh

if [ ! -f "$CONFIG" ]; then
  cat >"$CONFIG" <<EOF
# Path to the selrad-warehouse infra directory (contains docker-compose-dev.yml and the Makefile)
WAREHOUSE_INFRA_DIR=/opt/selrad-warehouse/infra
# S3 bucket that holds Archives
BUCKET=CHANGE_ME
# AWS region
REGION=CHANGE_ME
# Key prefix inside the bucket
S3_PREFIX=warehouse
# Custom S3-compatible endpoint (empty = default AWS endpoint)
ENDPOINT_URL=
EOF
  chmod 600 "$CONFIG"
  echo "wrote $CONFIG - edit it before starting"
else
  echo "$CONFIG already exists, leaving it alone"
fi

install -m 644 "$REPO_DIR"/systemd/*.timer "$REPO_DIR"/systemd/*.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now auto-backup-dump.timer
systemctl enable --now auto-backup-prune.timer

echo
echo "installed. next:"
echo "  1. edit $CONFIG"
echo "  2. create /etc/auto-backup/aws.env (see docs/AWS-SETUP.md)"
echo "  3. run one dump manually: systemctl start auto-backup-dump.service"