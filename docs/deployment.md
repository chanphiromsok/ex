# Deployment runbook

How the API is built, configured and deployed. Why it is set up this way: `docs/system-design.md` and ADR-0009 to ADR-0012. The client is deployed separately to Cloudflare Workers and is not covered here.

Phase A (test, now): one DigitalOcean droplet in Singapore, reached at `159-223-95-98.sslip.io`. Phase B (launch) changes are marked **Phase B**.

> Status: this runbook describes the agreed setup. Items in `docs/system-design.md` section 10 (CI workflow, droplet compose, CORS and so on) must be built before every step here works as written.

## Image

The `Dockerfile` builds a Mix release in one stage and copies only the release into a slim Debian runner. The image listens on `$PORT` (default 4000) and runs `bin/server`. Images are built only by GitHub Actions, for `linux/amd64`, and pushed to `ghcr.io/<owner>/ex:<git SHA>`. The droplet never builds.

## Environment variables

Set by hand in `/opt/ex/server/.env` on the droplet. CI never sees them. Keep a copy in a password manager; it is needed to rebuild the droplet.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST:PORT/DB` |
| `DATABASE_SSL` | **Phase B** | `true` on Managed Postgres; use `verify_peer` with DO's CA certificate |
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `TOKEN_SIGNING_SECRET` | yes | signs access tokens; changing it signs everyone out |
| `PHX_HOST` | yes | `159-223-95-98.sslip.io` in Phase A |
| `PORT` | no | default 4000 |
| `POOL_SIZE` | no | Phase A: 3. Phase B: keep `pool x containers` inside the database's connection limit, leaving room for `bin/migrate` |
| `CORS_ORIGINS` | Phase A | comma-separated exact client origins (worker URL, preview URLs). Name to be fixed when the plug is built |
| `CLIENT_IP_SOURCE` | no | `x-forwarded-for` (Phase A) or `cf-connecting-ip` (Phase B). Name to be fixed when the plug is built |
| `API_DOCS` | no | `true` on test, unset in prod. Name to be fixed when built |
| `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD` | first deploy only | no defaults; remove from `.env` after seeding |
| `DASHBOARD_USER`, `DASHBOARD_PASSWORD` | optional | no defaults; the dashboard answers 404 until both are set |

## One-time droplet setup

1. Create the droplet: Ubuntu 24.04, 1 GB, Singapore, SSH key only.
2. DO cloud firewall: inbound 22 and 443 only. **Phase B:** 443 from Cloudflare IP ranges only.
3. As root:
   - add 2 GB swap;
   - install Docker Engine and the compose plugin;
   - enable `unattended-upgrades`;
   - set `PermitRootLogin no` and `PasswordAuthentication no` in `sshd_config`;
   - write `/etc/docker/daemon.json` with `{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}` and restart Docker.
4. Create the `deploy` user and add it to the `docker` group. The `docker` group is effectively root; this user limits mistakes, it is not a security boundary.
5. As `deploy`: clone the repo to `/opt/ex` (it is private, so use a deploy key or a token) and write `/opt/ex/server/.env` (`chmod 600`, git-ignored) with at least `SECRET_KEY_BASE` and `TOKEN_SIGNING_SECRET`; the prod overlay refuses to start without them.
6. Log the droplet in to GHCR once. The image is private (it belongs to a private repo), so create a classic GitHub token with only the `read:packages` scope, then:

       echo <token> | docker login ghcr.io -u <github user> --password-stdin

7. Add a free uptime check on `/health` that alerts to Telegram.

If the stack already runs from another checkout, stop it there first (`docker compose down`, without `-v`). The compose project is named `ex` everywhere, so the new checkout takes over the same `ex_pgdata` volume.

## Build (CI)

`.github/workflows/server.yml`:

| Trigger | Jobs |
|---|---|
| Pull request touching `server/` | test |
| Push to `release/**` touching `server/`, or a manual run | test, build |

1. **test:** `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` against a Postgres 17 service.
2. **build:** `linux/amd64` image pushed to `ghcr.io/<owner>/ex:<SHA>` and `:latest`.

CI does not deploy (yet). The SHA of a build is on the run page in the Actions tab, or `git rev-parse HEAD` after pulling.

## Every deploy (by hand, on the droplet)

    cd /opt/ex && git pull          # compose files, Traefik config, deploy script
    cd server
    ./deploy/deploy.sh <SHA>        # or: ./deploy/deploy.sh latest

`deploy/deploy.sh <tag>`: pull the image, run `/app/bin/migrate` in a one-off container, `up -d`, then ask Traefik for `/health` for up to a minute. On success it writes the tag to `.deployed-tag`. On failure it prints the app logs, starts the previous tag again and exits 1.

Prefer the SHA: `.deployed-tag` then names the exact build, so a rollback (`./deploy/deploy.sh <older SHA>`) is precise. `latest` is the newest build from any `release/**` branch.

Rules:
- Migrations are additive (add, switch over, drop later). The old container serves traffic while `bin/migrate` runs, and a rollback does not undo a migration.
- API changes stay compatible with the live client; ship the API before the client that needs it.
- **Phase B:** prod is deployed by hand with a SHA that has already passed on staging. Tags are never reused.

## First deploy only

Create the first Admin (idempotent; running it again does nothing). Put `SEED_ADMIN_EMAIL` and `SEED_ADMIN_PASSWORD` in `.env` first, then remove them afterwards:

    cd /opt/ex/server
    TAG=$(cat .deployed-tag) docker compose -f docker-compose.yml -f docker-compose.prod.yml \
      run --rm -l traefik.enable=false app /app/bin/ex eval "Ex.Release.seed()"

## Checks before the first real deploy

- No container except Traefik publishes a host port.
- The temporary droplet-IP entries in `server/config/prod.exs` are gone; `force_ssl` trusts `x-forwarded-proto`.
- Traefik serves a valid Let's Encrypt certificate (Phase A) or the Cloudflare Origin Certificate with Full (strict) (Phase B).
- The migrations also create the permission and role data, so no extra seeding is needed for them.
- After launch, build new indexes `concurrently` in their own migration (see `docs/database-health.md`).

## Ops dashboard

LiveDashboard is at `/ops/dashboard` (in dev: `/dev/dashboard`), behind HTTP basic auth, and answers 404 until both `DASHBOARD_USER` and `DASHBOARD_PASSWORD` are set. It is not routed through Traefik. Open it through an SSH tunnel to the app container's port, for example:

    ssh -L 4000:<app container IP>:4000 deploy@<droplet>
    # then browse http://localhost:4000/ops/dashboard

## Diagnosing a live node

The release includes [recon](https://github.com/ferd/recon) (loaded, never started). Connect to the running app and call it:

    docker compose exec app /app/bin/ex remote

| Question | Call |
|---|---|
| Which processes use the most memory? | `:recon.proc_count(:memory, 10)` |
| Which use the most CPU? | `:recon.proc_count(:reductions, 10)` |
| Binary leak? (runs a GC and shows what was freed) | `:recon.bin_leak(10)` |
| Details of one process | `:recon.info(pid)` |
| VM memory by allocator, fragmentation | `:recon_alloc.memory(:used)`, `:recon_alloc.fragmentation(:current)` |
| Rate-limited tracing | `:recon_trace.calls({Mod, :fun, :return_trace}, 10)` |

Leave the shell with Ctrl+C twice. `:recon_trace` is rate limited, but still stop a trace with `:recon_trace.clear()` when done.

## Phase B additions

- Managed Postgres: PITR on, `DATABASE_SSL=true` with `verify_peer`, nightly `pg_dump` copied to object storage at a different provider, one restore drill before launch.
- Cloudflare: proxy on, Full (strict), Workers route `app.domain/api/*` with no worker; remove `CORS_ORIGINS`; set `CLIENT_IP_SOURCE=cf-connecting-ip`.
- Sentry DSN, alerts on 5xx rate, DB connections and disk.
- Rebuild a droplet from scratch: create it with the steps above, restore `.env` from the password manager, deploy the last good SHA. Target: back up within about 2 hours.
