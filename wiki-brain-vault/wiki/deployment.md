# Deployment

Created: 2026-08-09

Related: [[index]] · [[backend]] · [[database]] · [[server-connection]] · [[app-updates]]

Manga Vault's server runs as a **second tenant on the Oracle Cloud VM that already hosts
Expensy**. The box is far from busy — 858 MiB of 11 GiB used, load 0.05, 67 GB free — so a second
Postgres and a Node API fit comfortably.

## The end state

| Piece | Where |
| --- | --- |
| Public URL | `https://vault.expensy-app.org` |
| TLS + ingress | The **existing** Caddy container (`expensy-prod-caddy-1`) — it already owns :80/:443 |
| API | `mangavault-prod-server-1`, no host port, reached over a shared `edge` Docker network |
| Database | `mangavault-prod-db-1`, Postgres 16, internal to its own stack |
| Cover storage | Docker volume `mangavault-prod_storage` → `/data/storage` |
| Backups | `~/ops/mangavault/backup.sh` nightly at **03:30** (Expensy's is 03:00) |
| App config | Entered per-device in the app's setup screen — nothing is compiled in ([[server-connection]]) |

**One Caddy, two apps.** Only one process can hold ports 80/443, so Manga Vault does *not* get its
own reverse proxy. The existing Caddy gains a second site block and joins a shared network. That is
the only change to the running Expensy deployment, and it is called out below.

## VM facts (verified 2026-08-09)

- Ubuntu 24.04.4 LTS, **aarch64** (Ampere A1), 1 OCPU / 12 GB, 77 GB disk (67 GB free), 2 GB swap.
- Docker with Compose v2; existing stack `expensy-prod` (db + api + caddy) on network
  `expensy-prod_default`.
- UFW active: 22, 80, 443 open. **No firewall or OCI Security List change is needed** — a new
  subdomain reuses 443.
- `api.expensy-app.org` resolves to `84.235.231.208`, the VM's real IP. **Cloudflare is DNS-only
  (grey cloud), not proxied.** That matters — see the DNS step.
- Existing layout: `~/expensy` (source), `~/deploy/prod` (config), `~/backups/prod`, `~/ops`.
  Manga Vault mirrors it as `~/mangavault`, `~/deploy/mangavault`, `~/backups/mangavault`,
  `~/ops/mangavault`.

---

## Prerequisites

### 1. DNS — Cloudflare A record

In Cloudflare → `expensy-app.org` → DNS → Add record:

| Field | Value |
| --- | --- |
| Type | `A` |
| Name | `vault` |
| IPv4 | `84.235.231.208` |
| Proxy status | **DNS only (grey cloud)** |
| TTL | Auto |

> **The grey cloud is load-bearing.** Caddy gets its certificate over the ACME HTTP-01 challenge,
> which requires Let's Encrypt to reach *this box* on port 80. With the orange cloud on, Cloudflare
> terminates TLS itself and the challenge never arrives, so Caddy retries forever and the site
> serves a bad certificate. `api.expensy-app.org` is already grey for exactly this reason — match it.

Verify before going further; propagation is usually seconds:

```bash
nslookup vault.expensy-app.org 1.1.1.1     # must return 84.235.231.208
```

### 2. Secrets to generate

Two, both on the VM, both new (do **not** reuse Expensy's):

```bash
openssl rand -hex 24    # POSTGRES_PASSWORD
openssl rand -hex 32    # API_TOKEN
```

`API_TOKEN` is the single credential for the entire archive — the auth guard is fail-closed, so
every route except `/api/v1/health` rejects a request without it. It is what you type into the
app's setup screen. It is **not** in the APK; see [[server-connection]].

### 3. Environment the server needs

`~/deploy/mangavault/server.env` (template: `deploy/prod/server.env.example` in the repo):

| Var | Value | Notes |
| --- | --- | --- |
| `NODE_ENV` | `production` | |
| `PORT` | `3000` | |
| `DATABASE_URL` | `postgres://mangavault:<pw>@db:5432/mangavault` | `db` is the Compose service; paste the **literal** password — an `env_file` is not interpolated by Compose |
| `STORAGE_DIR` | `/data/storage` | matches the `storage` volume mount |
| `API_TOKEN` | the 32-byte hex above | fail-closed if unset |

`~/deploy/mangavault/.env` (Compose-level only): `COMPOSE_PROJECT_NAME=mangavault-prod` and
`POSTGRES_PASSWORD=<pw>`. Both files `chmod 600`.

No SMTP, no third-party API keys — the server talks to Postgres, the filesystem, and (for cover
archiving) the manga sources.

---

## Runbook

### Step 1 — Clone the repo on the VM

```bash
ssh -i ./ssh-key-2026-07-05.key ubuntu@84.235.231.208
git clone https://github.com/Raderne/mangaVault.git ~/mangavault
cd ~/mangavault && git checkout v1.0.0
```

### Step 2 — Create the shared `edge` network

```bash
docker network create edge
```

Idempotent-ish: if it already exists Docker errors harmlessly.

### Step 3 — Put Caddy on `edge` ⚠️ *touches the running Expensy stack*

Edit `~/deploy/prod/docker-compose.yml` — add the two marked blocks:

```yaml
  caddy:
    image: caddy:2-alpine
    # …unchanged…
    networks:                 # ← add
      - default               # ← add (keeps `reverse_proxy api:3000` working)
      - edge                  # ← add

networks:                     # ← add at the top level
  edge:                       # ← add
    external: true            # ← add
```

> **Naming both networks is mandatory.** Compose attaches a service to `default` only when it
> declares no `networks:` key. The moment you add one, `default` must be listed explicitly or Caddy
> loses `api` and the Expensy API 502s.

Then:

```bash
cd ~/deploy/prod
docker compose up -d caddy      # recreates ONLY caddy
```

**Expect ~2–3 seconds of downtime on `api.expensy-app.org`** while the container is replaced. The
Expensy database and API containers are untouched. Confirm recovery immediately:

```bash
curl -fsS https://api.expensy-app.org/health     # {"status":"ok","db":"up"}
```

### Step 4 — Deploy config

```bash
mkdir -p ~/deploy/mangavault
cp ~/mangavault/deploy/prod/docker-compose.yml   ~/deploy/mangavault/
cp ~/mangavault/deploy/prod/.env.example         ~/deploy/mangavault/.env
cp ~/mangavault/deploy/prod/server.env.example   ~/deploy/mangavault/server.env
chmod 600 ~/deploy/mangavault/.env ~/deploy/mangavault/server.env
```

Fill in both files with the secrets from *Prerequisites §2*. The password appears twice — in `.env`
as `POSTGRES_PASSWORD` and inside `server.env`'s `DATABASE_URL` — and they must match.

### Step 5 — Build and start

```bash
cd ~/deploy/mangavault
docker compose up -d --build
docker compose logs -f server        # watch migrations run, then "Nest application successfully started"
```

The schema is created by raw-SQL migrations that run automatically on boot (`migrationsRun: true`
— see [[migration]]). There is no separate migrate step.

> **Build on the VM, never push an image to it.** The base images are multi-arch, but this machine
> is ARM64 and `sharp` resolves a platform-specific binary at install time. An image built on an
> x86 laptop or a GitHub runner will not start here.

### Step 6 — Add the Caddy site block

Append `deploy/prod/Caddyfile.snippet` to `~/deploy/prod/Caddyfile`, then reload **without
restarting** (no Expensy downtime this time):

```bash
cat ~/mangavault/deploy/prod/Caddyfile.snippet >> ~/deploy/prod/Caddyfile
cd ~/deploy/prod
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile   # check before applying
docker compose exec caddy caddy reload   --config /etc/caddy/Caddyfile
```

`--config` is explicit on purpose: a bare `caddy reload` looks for a Caddyfile in the container's
working directory, not at the mounted path, and fails confusingly. `validate` first means a typo
is caught before it reaches the process serving Expensy.

Caddy fetches the certificate for `vault.expensy-app.org` on the first request; give it a few
seconds. Watch it happen with `docker compose logs -f caddy`.

The snippet is not decoration — its three settings each fix a real failure:

- `request_body max_size 200MB` — matches the server's `MAX_UPLOAD_BYTES`. A `.tachibk` is uploaded
  whole.
- `flush_interval -1` — the import progress feed is **server-sent events**. Buffered, the app's
  live ticker shows nothing until the import finishes.
- `read_timeout 30m` — importing a large backup and archiving a thousand covers both hold the
  connection well past Caddy's 30-second default.

### Step 7 — Smoke test

```bash
# Public, unauthenticated — proves DNS, TLS and routing.
curl -fsS https://vault.expensy-app.org/api/v1/health
# {"status":"ok","service":"mangavault-server"}

# Guarded — proves the token.
curl -fsS -H "Authorization: Bearer $API_TOKEN" \
  https://vault.expensy-app.org/api/v1/categories

# Should be rejected.
curl -s -o /dev/null -w '%{http_code}\n' https://vault.expensy-app.org/api/v1/categories   # 401
```

Then in the app: install the APK, and on the setup screen enter `vault.expensy-app.org` and the
token. The app probes exactly those two endpoints in that order, so if both curls pass, setup will.

### Step 8 — Backups

```bash
mkdir -p ~/ops/mangavault ~/backups/mangavault
cp ~/mangavault/scripts/vm-backup.sh ~/ops/mangavault/backup.sh
chmod 700 ~/ops/mangavault/backup.sh
( crontab -l 2>/dev/null | grep -v 'ops/mangavault/backup.sh'; \
  echo "30 3 * * * bash \$HOME/ops/mangavault/backup.sh >> \$HOME/backups/mangavault/backup.log 2>&1" ) | crontab -
bash ~/ops/mangavault/backup.sh      # run once now to prove it works
```

03:**30**, deliberately — Expensy dumps at 03:00 and this box has one OCPU.

The script dumps Postgres every night (keeping 3) and tars the cover volume every 7th run (keeping
2). Covers are technically rebuildable by re-running archiving, but that re-downloads thousands of
images from sources that may no longer exist — which is the reason the archive exists at all.

---

## Updating the server later

```bash
cd ~/mangavault && git fetch --tags && git checkout v<next>
cd ~/deploy/mangavault && docker compose up -d --build server
```

Migrations run on boot. The `pgdata` and `storage` volumes are untouched by a rebuild.

## Gotchas

- **`docker compose down -v` deletes the vault.** `-v` removes `pgdata` and `storage`. Plain `down`
  is safe. There is no cloud copy — the whole point of this project is that the vault is the only
  copy.
- **Two Postgres containers now share one OCPU.** They idle fine, but do not run both backup jobs
  or a large import at the same minute.
- **Caddy is a single point of failure for both apps.** Anything that stops that container takes
  Expensy down with Manga Vault. Prefer `caddy reload` over `up -d caddy` for Caddyfile edits.
- **The app requires no rebuild when the server moves.** URL and token are per-device runtime
  config ([[server-connection]]); a new address is a change in the app's setup screen, not a new
  APK.
- If `curl` to `/api/v1/health` returns Caddy's default page, Caddy resolved the hostname but has no
  matching site block — check the snippet actually landed in `~/deploy/prod/Caddyfile`.
- If it returns 502, Caddy has the block but cannot resolve `mangavault-server` — its container is
  not on `edge` (Step 3), or the Manga Vault stack is down.
