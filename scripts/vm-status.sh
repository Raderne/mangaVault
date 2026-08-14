#!/usr/bin/env bash
#
# Operational snapshot for the Manga Vault stack on the Oracle VM. Mirrors
# Expensy's ~/ops/status.sh so both tenants of this box answer the same
# questions the same way: containers, health, row counts, resources, TLS,
# backups.
#
# Install on the VM:
#   cp ~/mangavault/scripts/vm-status.sh ~/ops/mangavault/status.sh
#   chmod 700 ~/ops/mangavault/status.sh
#
# Run it:
#   bash ~/ops/mangavault/status.sh
#
# Config via env (all optional):
#   DEPLOY_DIR  compose project dir  (default: ~/deploy/mangavault)
#   BACKUP_DIR  backup directory     (default: ~/backups/mangavault)
#   DOMAIN      public hostname      (default: vault.expensy-app.org)
#
# Not `set -e`: every section should run even if a previous one fails — a
# status tool that stops at the first problem is the opposite of useful.
set -uo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-$HOME/deploy/mangavault}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/mangavault}"
DOMAIN="${DOMAIN:-vault.expensy-app.org}"

hr() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

cd "$DEPLOY_DIR" 2>/dev/null || { echo "no $DEPLOY_DIR"; exit 1; }

hr "Containers"
docker compose ps

hr "Health (public, no token needed)"
curl -fsS --max-time 10 "https://$DOMAIN/api/v1/health" 2>/dev/null && echo \
  || echo "UNREACHABLE"

hr "Auth guard is fail-closed (expect 401)"
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 \
  "https://$DOMAIN/api/v1/categories" 2>/dev/null || echo "unreachable"

hr "Library size"
docker compose exec -T db psql -U mangavault -d mangavault -c \
  'SELECT (SELECT count(*) FROM manga)    AS titles,
          (SELECT count(*) FROM chapter)  AS chapters,
          (SELECT count(*) FROM category) AS categories;' 2>/dev/null \
  || echo "db query failed"

hr "Cover archive"
docker compose exec -T server sh -c \
  'echo "files: $(ls -1 /data/storage/covers 2>/dev/null | wc -l)"; du -sh /data/storage 2>/dev/null' \
  || echo "server unreachable"

hr "Per-container resources"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' \
  2>/dev/null | grep -E 'NAME|mangavault' || echo "stats unavailable"

hr "Disk / memory / swap"
df -h / | awk 'NR==1 || /\/$/'
free -h 2>/dev/null | awk 'NR==1 || /Mem|Swap/'

hr "TLS certificate ($DOMAIN)"
echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -issuer -enddate 2>/dev/null \
  || echo "could not read certificate for $DOMAIN"

hr "Recent backups ($BACKUP_DIR)"
ls -lh "$BACKUP_DIR"/mangavault-*.dump 2>/dev/null | tail -3 || echo "NO DATABASE BACKUPS"
ls -lh "$BACKUP_DIR"/mangavault-covers-*.tar.gz 2>/dev/null | tail -2 || echo "no cover archives yet"

hr "Off-box copies"
if command -v rclone >/dev/null 2>&1 && [ -n "${OCI_REMOTE:-}" ]; then
  rclone lsl "${OCI_REMOTE}" 2>/dev/null | tail -3 || echo "remote unreachable"
else
  echo "rclone/OCI_REMOTE not configured — backups are LOCAL ONLY"
fi
