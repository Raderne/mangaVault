#!/usr/bin/env bash
#
# Update the Manga Vault server on the Oracle VM. Replaces the hand-typed
# sequence in wiki-brain-vault/wiki/deployment.md § "Updating the server later",
# which was easy to get half-right.
#
# The server tracks the `main` branch, NOT a tag. App releases are tagged
# (v1.2.3 triggers the APK workflow); the server ships independently, and
# tagging a release just to pick up a server fix would push every user a
# pointless APK update.
#
# Install on the VM:
#   cp ~/mangavault/scripts/vm-deploy.sh ~/ops/mangavault/deploy.sh
#   chmod 700 ~/ops/mangavault/deploy.sh
#
# Run it:
#   bash ~/ops/mangavault/deploy.sh            # pull main and rebuild
#   REF=v1.1.0 bash ~/ops/mangavault/deploy.sh # pin to a tag instead
#
# Config via env (all optional):
#   REPO_DIR    source checkout      (default: ~/mangavault)
#   DEPLOY_DIR  compose project dir  (default: ~/deploy/mangavault)
#   REF         branch or tag        (default: main)
#   DOMAIN      public hostname      (default: vault.expensy-app.org)
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/mangavault}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/deploy/mangavault}"
REF="${REF:-main}"
DOMAIN="${DOMAIN:-vault.expensy-app.org}"

hr() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

hr "Pre-flight"
[ -d "$REPO_DIR/.git" ]              || { echo "no git checkout at $REPO_DIR"; exit 1; }
[ -f "$DEPLOY_DIR/docker-compose.yml" ] || { echo "no compose in $DEPLOY_DIR"; exit 1; }

cd "$REPO_DIR"
# A dirty tree means someone patched the box by hand. That patch is about to be
# either silently reverted or silently kept — both are worse than stopping.
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: $REPO_DIR has local modifications:" >&2
  git status --short >&2
  echo "Commit them upstream or 'git checkout -- .' before deploying." >&2
  exit 1
fi

hr "Back up before changing anything"
# Migrations run automatically on boot and are not reversible in general. A
# dump taken now is the only way back from a bad one.
bash "$HOME/ops/mangavault/backup.sh"

hr "Fetch $REF"
before="$(git rev-parse --short HEAD)"
git fetch origin --tags --prune
git checkout "$REF"
git pull --ff-only origin "$REF" 2>/dev/null || true   # a tag has nothing to pull
after="$(git rev-parse --short HEAD)"
echo "$before -> $after"
if [ "$before" = "$after" ]; then
  echo "already up to date; rebuilding anyway (base image may have moved)"
fi

hr "Build and restart"
cd "$DEPLOY_DIR"
# Build first, restart second. `up -d --build` in one step will happily stop the
# running container and then discover the build is broken.
docker compose build server
docker compose up -d

hr "Wait for health"
for i in $(seq 1 30); do
  state="$(docker inspect --format '{{.State.Health.Status}}' mangavault-prod-server-1 2>/dev/null || echo starting)"
  [ "$state" = "healthy" ] && break
  sleep 2
done
echo "container health: ${state:-unknown}"

hr "Verify from outside"
curl -fsS --max-time 15 "https://$DOMAIN/api/v1/health" && echo || {
  echo "PUBLIC HEALTH CHECK FAILED — check 'docker compose logs server'" >&2
  exit 1
}
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/api/v1/categories")"
[ "$code" = "401" ] && echo "auth guard fail-closed: OK" || echo "WARN: expected 401, got $code"

hr "Done"
echo "deployed $after from $REF"
