#!/usr/bin/env bash
#
# Copy local backups off the box to OCI Object Storage.
#
# Why this exists: ~/backups/mangavault lives on the same boot volume as the
# database and the cover archive it protects. A lost or corrupted volume takes
# the backups with it, which makes them useless for the failure they are most
# likely to be needed for. The vault is the only copy of this library — that is
# the entire premise of the project — so it needs a copy somewhere else.
#
# Auth is by **instance principal**: the VM proves its own identity to OCI via
# the metadata service, so there is no key, token or password stored anywhere on
# this machine. An attacker who takes the box can write backups (see the note on
# retention below) but cannot extract a credential that works from elsewhere.
#
# --- One-time setup in the OCI console (nothing here works until this is done) -
#   1. Object Storage -> Create Bucket
#        name: vm-backups        visibility: Private
#        (optionally enable Versioning — it defeats an attacker who overwrites)
#   2. Identity -> Domains -> Dynamic Groups -> Create
#        name: vm-backup-writers
#        rule: instance.id = '<this instance OCID>'
#   3. Identity -> Policies -> Create (in the root compartment)
#        Allow dynamic-group 'Default'/'vm-backup-writers' to manage object-family
#          in tenancy where target.bucket.name = 'vm-backups'
#   4. On the VM, create the rclone remote (no secrets — this is the whole file):
#        mkdir -p ~/.config/rclone
#        cat > ~/.config/rclone/rclone.conf <<'CONF'
#        [oci]
#        type = oracleobjectstorage
#        provider = instance_principal_auth
#        namespace = <your object storage namespace>
#        compartment = <compartment OCID>
#        region = <region, e.g. eu-marseille-1>
#        CONF
#      The namespace is shown on the bucket's detail page.
#   5. Prove it:  rclone lsd oci:
#
# Install on the VM:
#   cp ~/mangavault/scripts/oci-sync.sh ~/ops/mangavault/oci-sync.sh
#   chmod 700 ~/ops/mangavault/oci-sync.sh
#
# Config via env (all optional):
#   BACKUP_DIR    what to copy        (default: ~/backups/mangavault)
#   OCI_REMOTE    rclone destination  (default: oci:vm-backups/mangavault)
#   KEEP_DUMPS    remote dump age     (default: 14d)
#   KEEP_COVERS   remote cover age    (default: 30d)
#
# Not `set -e` on the transfers: a failed upload must never mask the fact that
# the local backup itself succeeded. It exits non-zero so cron mail shows it.
set -uo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/mangavault}"
OCI_REMOTE="${OCI_REMOTE:-oci:vm-backups/mangavault}"
KEEP_DUMPS="${KEEP_DUMPS:-14d}"
KEEP_COVERS="${KEEP_COVERS:-30d}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

command -v rclone >/dev/null 2>&1 || { log "rclone not installed; skipping off-box copy"; exit 0; }
[ -d "$BACKUP_DIR" ] || { log "ERROR: no $BACKUP_DIR"; exit 1; }

if ! rclone lsd "${OCI_REMOTE%%/*}" >/dev/null 2>&1; then
  log "ERROR: rclone remote '${OCI_REMOTE%%/*}' is not reachable."
  log "       The console setup at the top of this script is probably incomplete."
  exit 1
fi

rc=0

# `copy`, not `sync`. sync would mirror the local retention (3 dumps) onto the
# remote and delete everything older, which is the opposite of what an off-box
# copy is for — the remote is supposed to reach further back than the box does.
log "uploading -> $OCI_REMOTE"
if rclone copy "$BACKUP_DIR" "$OCI_REMOTE" \
     --include 'mangavault-*.dump' \
     --include 'mangavault-covers-*.tar.gz' \
     --transfers 2 --checkers 4 \
     --bwlimit 8M \
     --stats-one-line --stats 30s; then
  log "upload OK"
else
  log "WARN: upload failed; local backups are still good"
  rc=1
fi

# Remote-side retention. Deliberately longer than local: the point of the copy
# is depth the box does not have.
log "pruning remote: dumps older than $KEEP_DUMPS, covers older than $KEEP_COVERS"
rclone delete "$OCI_REMOTE" --include 'mangavault-*.dump'          --min-age "$KEEP_DUMPS"  || rc=1
rclone delete "$OCI_REMOTE" --include 'mangavault-covers-*.tar.gz' --min-age "$KEEP_COVERS" || rc=1

log "remote now holds:"
rclone lsl "$OCI_REMOTE" 2>/dev/null | tail -5 || true

exit "$rc"
