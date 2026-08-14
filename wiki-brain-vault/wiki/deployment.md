# Deployment

Created: 2026-08-09 · Hardening pass 2026-08-14

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
| Backups | `~/ops/mangavault/backup.sh` nightly at **03:30** (Expensy's is 03:00), copied off-box to OCI Object Storage |
| App config | Entered per-device in the app's setup screen — nothing is compiled in ([[server-connection]]) |
| Ops scripts | `~/ops/mangavault/{backup,oci-sync,deploy,status}.sh`, sources in `scripts/` |

**One Caddy, two apps.** Only one process can hold ports 80/443, so Manga Vault does *not* get its
own reverse proxy. The existing Caddy gains a second site block and joins a shared network. That is
the only change to the running Expensy deployment, and it is called out below.

**The server tracks the `main` branch, not a tag.** App releases are tagged (`v1.2.3` triggers the
APK workflow in [[app-updates]]); the server ships independently. Tagging a release to pick up a
server-only fix would push every user an identical APK. `~/ops/mangavault/deploy.sh` does the
update; `REF=v1.1.0 deploy.sh` pins to a tag if a rollback is ever needed.

## Why Caddy and not Traefik (decided 2026-08-14)

Asked and answered once, so it does not get re-litigated. The pattern here — one ingress owning
80/443, apps reached over a shared external network, no published ports, one Postgres per app on
its own network — is the standard shape for this deployment and is implemented correctly.

Traefik's real advantage is Docker-label service discovery, which pays off at ~10+ services with
frequent churn. This box has two and gains one roughly never. Against that: the migration is paid
on the single component that is a SPOF for **both** apps; ACME state lives in the `caddy_data`
volume and does not transfer, so both certs get re-issued for no functional gain; Caddy idles at
12 MiB here against Traefik's 40–80; and a 12-line Caddyfile becomes static config plus dynamic
providers, entrypoints, routers and middlewares. Nginx Proxy Manager is worse again — a web UI and
its own database, both new attack surface.

The one honest argument for Traefik is its built-in rate-limit middleware (Caddy needs a plugin and
a custom image). With a 256-bit bearer token, credential brute force is not the threat model, and a
flood is better handled at Cloudflare if it ever matters. Not worth a migration.

## VM facts (verified 2026-08-14)

- Ubuntu 24.04.4 LTS, **aarch64** (Ampere A1), 1 OCPU / 12 GB, 77 GB disk (67 GB free), 2 GB swap.
- Docker with Compose v2; existing stack `expensy-prod` (db + api + caddy) on network
  `expensy-prod_default`.
- UFW active: 22, 80, 443 open. **No firewall or OCI Security List change is needed** — a new
  subdomain reuses 443.
- **UFW does not control container traffic.** Docker writes its own iptables rules and bypasses it,
  so `ufw status` is not the truth for a published container port — see *Firewall* below.
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

`deploy/prod/Caddyfile.example` is the **complete** file as deployed — both tenants, not just Manga
Vault's block. It lives in this repo because Expensy's prod config exists only on the VM, and a
shared ingress that only one of its two tenants has a copy of is a config nobody can rebuild.

Copy it over `~/deploy/prod/Caddyfile`, then reload **without restarting** (no Expensy downtime):

```bash
cd ~/deploy/prod
cp Caddyfile Caddyfile.bak-$(date -u +%Y%m%d-%H%M%S)
cp ~/mangavault/deploy/prod/Caddyfile.example Caddyfile
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile   # check before applying
docker compose exec caddy caddy reload   --config /etc/caddy/Caddyfile
```

`--config` is explicit on purpose: a bare `caddy reload` looks for a Caddyfile in the container's
working directory, not at the mounted path, and fails confusingly. `validate` first means a typo is
caught before it reaches the process serving Expensy — and it can be run inside the *running*
container against the new file before anything is applied.

> The two sites share a `(common)` snippet (gzip, HSTS, `-Server`, per-site access log), which must
> be defined exactly once. That is why this is a whole-file copy and no longer a `cat >>` append.

Caddy fetches the certificate for `vault.expensy-app.org` on the first request; give it a few
seconds. Watch it happen with `docker compose logs -f caddy`.

The reverse-proxy settings are not decoration — each fixes a real failure:

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

### Step 8 — Backups ⚠️ *this step was skipped at first launch; do not skip it*

For five days the vault held 2,014 titles / 190,284 chapters / 139 MB of archived covers with **no
backup of any kind**. Steps 1–7 leave a working site, which is exactly why it is easy to stop
there.

```bash
mkdir -p ~/ops/mangavault ~/backups/mangavault
for s in vm-backup:backup vm-status:status vm-deploy:deploy oci-sync:oci-sync; do
  cp ~/mangavault/scripts/${s%%:*}.sh ~/ops/mangavault/${s##*:}.sh
done
chmod 700 ~/ops/mangavault/*.sh
( crontab -l 2>/dev/null | grep -v 'ops/mangavault/backup.sh'; \
  echo "30 3 * * * bash \$HOME/ops/mangavault/backup.sh >> \$HOME/backups/mangavault/backup.log 2>&1" ) | crontab -
bash ~/ops/mangavault/backup.sh      # run once now to prove it works
```

03:**30**, deliberately — Expensy dumps at 03:00 and this box has one OCPU.

The script dumps Postgres every night (keeping 3) and tars the cover volume every 7th run (keeping
2). Covers are technically rebuildable by re-running archiving, but that re-downloads thousands of
images from sources that may no longer exist — which is the reason the archive exists at all.

> **The cover-archive path had a bug worth remembering.** It bind-mounted the backup dir and let a
> root container write the tarball, so the following `chmod 600` failed for `ubuntu` and `set -e`
> aborted the run — *after* a good dump, on every 7th night, silently. It now streams `tar czf -`
> to stdout so the calling shell owns the file. Any backup step that runs a container as root and
> then touches the result as a normal user has this bug.

#### Off-box copy (`oci-sync.sh`)

Local dumps share a boot volume with the data they protect: they cover "a row was deleted", not
"the volume is gone". `oci-sync.sh` copies them to an OCI Object Storage bucket using **instance
principal** auth — the VM proves its own identity through the metadata service, so no key or
password is stored on the machine.

The console setup (bucket, dynamic group, policy) and the exact `rclone.conf` are documented in the
header of `scripts/oci-sync.sh`. Two things that cost time:

- **Ubuntu's `rclone` package will not work.** The `1.60.1-dfsg` build strips the
  `oracleobjectstorage` backend. Install the upstream `.deb` from GitHub releases (verify against
  `SHA256SUMS`).
- **`rclone copy`, not `sync`.** `sync` would mirror local retention (3 dumps) onto the remote and
  delete everything older — the opposite of the point. Remote retention is separate and longer:
  14 days of dumps, 30 days of cover archives.

The sync runs as the last step of `backup.sh` and is **non-fatal**: a network problem at 03:30 must
not make a good local backup look like a failed run. When it is not configured, the run says so
loudly (`backups are LOCAL ONLY`) rather than passing quietly.

### Step 9 — Rehearse a restore

An unrehearsed backup is not a backup. Restore the newest dump into a throwaway container and count
rows against the live database — never into the live one:

```bash
newest=$(ls -1t ~/backups/mangavault/*.dump | head -1)
docker run -d --rm --name mv-restore-test \
  -e POSTGRES_USER=mangavault -e POSTGRES_PASSWORD=throwaway -e POSTGRES_DB=mangavault \
  postgres:16-alpine
docker cp "$newest" mv-restore-test:/tmp/r.dump
docker exec mv-restore-test pg_restore --no-owner -U mangavault -d mangavault /tmp/r.dump
docker exec mv-restore-test psql -U mangavault -d mangavault -tAc \
  "select (select count(*) from manga), (select count(*) from chapter)"
docker stop mv-restore-test
```

Verified 2026-08-14: 2014 / 190284, 14 tables, titles intact.

---

## Hardening baseline (applied 2026-08-14)

The state below is what "correctly deployed" means for this box. Everything here was missing at
first launch and is easy to regress.

### Containers

- **Neither app runs as root.** Manga Vault's image declares `USER node` ([[backend]]). Expensy's
  api gets `user: "1000:1000"` in its compose instead — its image still declares root, and its repo
  is on a branch the VM does not track, so folding `USER node` into `expensy/backend/Dockerfile` is
  a **known piece of drift** left for the next touch of that repo.
- **Memory and CPU ceilings on everything** (`deploy.resources.limits`, honoured by Compose v2
  outside Swarm): vault server 768M/0.6cpu, vault db 512M, expensy api 512M/0.5cpu, expensy db
  512M, caddy 256M. One OCPU is shared — an import archiving a thousand covers must not be able to
  starve `api.expensy-app.org`.
- **Healthchecks on both app containers.** `restart: always` cannot act on a process that is up but
  wedged. Expensy's image has no wget or curl, so its check uses node's global `fetch`.
- **Log rotation twice over**: `logging:` on every service, plus `/etc/docker/daemon.json`
  (`max-size 10m`, `max-file 3`) as the default for anything added later. The json-file driver is
  unbounded by default; the vault server's DEBUG log was the largest file on the box.

### Ingress

Both sites `import common`, which supplies `encode gzip`, HSTS, `-Server`, and a rolled JSON access
log per site into the `caddy_logs` volume. There was previously **no record anywhere of who called
what**. Caddy replaces (not appends) the HSTS header, so Expensy's helmet-set one does not double.

### Firewall

`UFW is not the firewall for containers.` Docker writes its own iptables rules and bypasses it —
this box proved it, when a stray dev compose published Postgres on `0.0.0.0:5433` while UFW showed
only 22/80/443 and *only OCI's Security List* (a second, independent firewall in the cloud console)
kept it unreachable.

`docker-user-firewall.service` → `/usr/local/sbin/docker-user-firewall.sh` installs a default-deny
in `DOCKER-USER`, the one chain Docker guarantees it will not overwrite. Order is load-bearing:

```
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN   # or container outbound breaks
-A DOCKER-USER -i enp0s6 -p tcp --dport 80  -j RETURN                 # Caddy's ports are forwarded
-A DOCKER-USER -i enp0s6 -p tcp --dport 443 -j RETURN                 # traffic too — a blanket
-A DOCKER-USER -i enp0s6 -j DROP                                      # DROP takes both apps down
```

Host services (SSH) are unaffected — they hit `INPUT`, not `FORWARD`. Note this is defence in depth
*behind* the OCI Security List, and cannot be fully proven from outside while that list already
blocks everything but 22/80/443.

### Host

`rpcbind` disabled (NFS leftover listening on `0.0.0.0:111`, no NFS mounts), `PermitRootLogin no`
via `/etc/ssh/sshd_config.d/99-hardening.conf`, journald capped at 200 MB (it had reached 368 MB),
and a weekly `docker builder prune` at Sunday 04:00 (build cache had reached 4.65 GB).

**Reboots are not optional.** `unattended-upgrades` installs security patches but never reboots, so
the box ran 39 days on a kernel with a pending update. Check `/var/run/reboot-required`; both
stacks are `restart: always` and come back unattended in ~60–90 s.

### Still open

- **No uptime monitoring.** Nothing tells you the vault is down. An external monitor
  (UptimeRobot / Better Stack) on both `/health` endpoints is the best value-per-effort item left.
- **No rate limiting** — deliberate, see the Traefik section.
- **fail2ban not installed** — deliberate; password auth is off, so it would buy log hygiene only.
- Expensy's prod compose and Caddyfile live **only on the VM**; its repo carries a dev compose.
  Backups of both are at `~/deploy/prod/*.bak-<timestamp>`.

---

## Updating the server later

```bash
bash ~/ops/mangavault/deploy.sh          # pull main, dump, rebuild, verify
REF=v1.1.0 bash ~/ops/mangavault/deploy.sh   # pin to a tag (rollback)
bash ~/ops/mangavault/status.sh          # one-glance health at any time
```

`deploy.sh` **refuses to run on a dirty checkout**, dumps the database before letting boot-time
migrations touch it, builds before stopping anything (`up -d --build` will happily stop the running
container and *then* discover the build is broken), waits for the healthcheck, and verifies the
public endpoint plus the 401. Migrations run on boot; `pgdata` and `storage` survive a rebuild.

> **Why the dirty-tree check exists.** The VM once built only because of untracked local edits to
> `server/Dockerfile` and `server/package-lock.json`. The documented update path at the time
> (`git checkout v<next>`) would have silently reverted them and broken the next deploy. A patch
> applied by hand on the box is a patch that exists nowhere else — the fix belongs upstream, and
> `.github/workflows/server.yml` now builds the real image on every server change so a broken build
> is caught before it can reach here.

## Gotchas

- **`docker compose down -v` deletes the vault.** `-v` removes `pgdata` and `storage`. Plain `down`
  is safe. There is no cloud copy — the whole point of this project is that the vault is the only
  copy.
- **Two Postgres containers now share one OCPU.** They idle fine, but do not run both backup jobs
  or a large import at the same minute.
- **A named volume keeps its old ownership.** Docker applies the image's ownership only to an
  *empty* volume, so switching the image to a non-root user does not fix an existing
  root-owned `storage`. Chown it once by hand — see [[backend]].
- **Caddy is a single point of failure for both apps.** Anything that stops that container takes
  Expensy down with Manga Vault. Prefer `caddy reload` over `up -d caddy` for Caddyfile edits.
- **The app requires no rebuild when the server moves.** URL and token are per-device runtime
  config ([[server-connection]]); a new address is a change in the app's setup screen, not a new
  APK.
- If `curl` to `/api/v1/health` returns Caddy's default page, Caddy resolved the hostname but has no
  matching site block — check the snippet actually landed in `~/deploy/prod/Caddyfile`.
- If it returns 502, Caddy has the block but cannot resolve `mangavault-server` — its container is
  not on `edge` (Step 3), or the Manga Vault stack is down.
