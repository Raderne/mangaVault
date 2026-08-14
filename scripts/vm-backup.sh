#!/usr/bin/env bash
#
# Nightly backup for the Manga Vault stack on the Oracle VM. Mirrors the shape
# of Expensy's ~/ops/expensy/backup.sh so both apps behave the same way.
#
# Backs up TWO things, because the vault is not only its database:
#   * Postgres  — the library, reading progress, import history. Irreplaceable.
#   * storage/  — archived cover art. Rebuildable by re-running cover archiving,
#                 but that re-downloads thousands of images from sources that
#                 may be gone, which is the whole point of archiving them.
#
# Install on the VM:
#   mkdir -p ~/ops/mangavault ~/backups/mangavault
#   cp ~/mangavault/scripts/vm-backup.sh ~/ops/mangavault/backup.sh
#   chmod 700 ~/ops/mangavault/backup.sh
#   ( crontab -l 2>/dev/null | grep -v 'ops/mangavault/backup.sh'; \
#     echo "30 3 * * * bash \$HOME/ops/mangavault/backup.sh >> \$HOME/backups/mangavault/backup.log 2>&1" ) | crontab -
#
# 03:30, half an hour after Expensy's 03:00, so two pg_dumps never contend for
# the same single OCPU.
#
# Config via env (all optional):
#   DEPLOY_DIR   compose project dir           (default: ~/deploy/mangavault)
#   BACKUP_DIR   where dumps land              (default: ~/backups/mangavault)
#   KEEP_COUNT   newest dumps to keep          (default: 3)
#   COVERS_EVERY back up covers every N runs   (default: 7 — they change slowly
#                and the tarball is far larger than the dump)
#
# Restore the database into the running stack:
#   cd ~/deploy/mangavault
#   docker compose cp <file>.dump db:/tmp/r.dump
#   docker compose exec -T db pg_restore --clean --if-exists --no-owner \
#     -U mangavault -d mangavault /tmp/r.dump
#
# Restore covers:
#   docker run --rm -v mangavault-prod_storage:/dst -v "$HOME/backups/mangavault":/src \
#     alpine sh -c 'cd /dst && tar xzf /src/<file>.tar.gz'
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-$HOME/deploy/mangavault}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/mangavault}"
KEEP_COUNT="${KEEP_COUNT:-3}"
COVERS_EVERY="${COVERS_EVERY:-7}"

[ -f "$DEPLOY_DIR/docker-compose.yml" ] || {
  echo "ERROR: no docker-compose.yml in $DEPLOY_DIR" >&2
  exit 1
}
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cd "$DEPLOY_DIR"

ts="$(date -u +%Y%m%d-%H%M%SZ)"
out="$BACKUP_DIR/mangavault-$ts.dump"

echo "[$(date -u +%FT%TZ)] dumping mangavault -> $out"
docker compose exec -T db pg_dump -U mangavault -Fc mangavault > "$out"
chmod 600 "$out"

# Guard against a truncated dump (the DB was down mid-run).
if [ ! -s "$out" ]; then
  rm -f "$out"
  echo "ERROR: backup is empty — removed $out" >&2
  exit 1
fi
echo "[$(date -u +%FT%TZ)] wrote $(du -h "$out" | cut -f1) -> $out (mode 600)"

# Covers, occasionally. Read straight off the named volume with a throwaway
# container so this works whether or not the server is running.
counter="$BACKUP_DIR/.covers-counter"
n=$(( ( $(cat "$counter" 2>/dev/null || echo 0) + 1 ) % COVERS_EVERY ))
echo "$n" > "$counter"
if [ "$n" -eq 0 ]; then
  covers="$BACKUP_DIR/mangavault-covers-$ts.tar.gz"
  echo "[$(date -u +%FT%TZ)] archiving covers -> $covers"
  # Stream the tar to stdout and let *this* shell create the file, rather than
  # bind-mounting BACKUP_DIR and writing from inside. The container runs as root
  # (it has to — the cover tree is root-owned), so a file it creates on a bind
  # mount is root-owned too, and the `chmod 600` below then fails for ubuntu.
  # Under `set -e` that aborted the whole run *after* a good dump had been
  # written, which is exactly the kind of failure a backup script must not have.
  #
  # postgres:16-alpine rather than `alpine`: it is already on the box because
  # the stack runs it, so 03:30 never depends on Docker Hub being reachable.
  if docker run --rm \
    -v "${COMPOSE_PROJECT_NAME:-mangavault-prod}_storage":/src:ro \
    postgres:16-alpine tar czf - -C /src . > "$covers"; then
    chmod 600 "$covers"
    echo "[$(date -u +%FT%TZ)] wrote $(du -h "$covers" | cut -f1)"
  else
    # The redirect above created the file regardless of how docker exited, so a
    # partial archive has to be removed explicitly or it looks like a good one.
    rm -f "$covers"
    echo "WARN: cover archive failed; the database dump above is still good" >&2
  fi
  # Keep only the newest two cover archives — they are large and rebuildable.
  mapfile -t tars < <(ls -1t "$BACKUP_DIR"/mangavault-covers-*.tar.gz 2>/dev/null || true)
  if ((${#tars[@]} > 2)); then
    for old in "${tars[@]:2}"; do rm -f -- "$old"; done
  fi
fi

# Retention for the dumps.
mapfile -t dumps < <(ls -1t "$BACKUP_DIR"/mangavault-*.dump 2>/dev/null || true)
pruned=0
if ((${#dumps[@]} > KEEP_COUNT)); then
  for old in "${dumps[@]:KEEP_COUNT}"; do
    rm -f -- "$old"
    pruned=$((pruned + 1))
  done
fi
echo "[$(date -u +%FT%TZ)] pruned ${pruned} dump(s); keeping up to ${KEEP_COUNT}"

# Copy off the box. Local dumps share a boot volume with the data they protect,
# so on their own they only cover "someone deleted a row", not "the volume is
# gone". Deliberately last and deliberately non-fatal: a network problem at
# 03:30 must not make a good local backup look like a failed run.
sync_script="${OCI_SYNC:-$HOME/ops/mangavault/oci-sync.sh}"
if [ -x "$sync_script" ]; then
  bash "$sync_script" || echo "WARN: off-box copy failed; local backups above are still good" >&2
else
  echo "[$(date -u +%FT%TZ)] no off-box sync configured — backups are LOCAL ONLY"
fi
