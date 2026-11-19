# Deployment runbook

How the API is built, configured and deployed. Why it is set up this way: `docs/system-design.md` and ADR-0009 to ADR-0012. The client is deployed separately to Cloudflare Workers and is not covered here.

Phase A (UAT, now): one DigitalOcean droplet in Singapore, reached at `159-223-95-98.sslip.io`. Phase B (launch) changes are marked **Phase B**.

> Status: CI/CD, UAT deploys and encrypted env are built. CORS, the client-IP source and the Phase B items in `docs/system-design.md` section 10 are not.

## Image

The `Dockerfile` builds a Mix release in one stage and copies only the release into a slim Debian runner. The image listens on `$PORT` (default 4000) and runs `bin/server`. Images are built only by GitHub Actions, for `linux/amd64`, and pushed to `ghcr.io/<owner>/ex`. The droplet never builds. Tags:

| Tag | Made by | Example |
|---|---|---|
| `pr-<n>-<sha7>` | PR with the `build` or `deploy:uat` label | `pr-18-c3f9a1b` |
| `sha-<sha7>` | push to `release/**`, or Run workflow | `sha-4a2fab2` |
| `release-<x.y.z>` | push to `release/x.y.z` (moves with the branch) | `release-1.0.0` |
| `1.2.3`, `1.2`, `latest` | git tag `v1.2.3`: renames the existing `sha-` image, no rebuild | `1.0.0` |

`latest` only moves to the highest stable version; a pre-release (`v1.1.0-rc.1`) gets only its own name. The `ghcr cleanup` workflow (run by hand for now) keeps the newest 30 images and never deletes version tags, `latest` or `release-*`.

## Environment variables

Local Docker (`server/docker-compose.yml` alone) has no default credentials either. Put `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD`, `DASHBOARD_USER` and `DASHBOARD_PASSWORD` in the git-ignored `server/.env` if you want an Admin seeded and the dashboard on. Only the signing secrets have local-only defaults, and the prod overlay rejects running without real ones.

UAT values live encrypted in `server/.env.uat`, committed ([dotenvx](https://dotenvx.com)). Only the private key `DOTENV_PRIVATE_KEY_UAT` can read them; it is in the git-ignored `server/.env.keys`, the `uat` GitHub Environment secret, and your password manager. On every deploy CI decrypts the file and writes it to `/etc/ex/uat.env` on the droplet (`chmod 600`).

### One compose file, switch the env

The droplet runs `server/deploy/docker-compose.yml` only (Traefik, Postgres, app). Nothing in it changes between environments; the env file does:

| | `/etc/ex/uat.env` (from `server/.env.uat`) | `/etc/ex/prod.env` (later, from `server/.env.prod`) |
|---|---|---|
| `APP_HOST` | `159.223.95.98` | the domain |
| `APP_ENTRYPOINT` | `web` (plain HTTP) | `websecure` (HTTPS, Let's Encrypt certificate for `APP_HOST`) |
| secrets | own values | own values, own `DOTENV_PRIVATE_KEY_PROD` |

`deploy/*.sh` pick the file with `EX_ENV` (default `uat` → `/etc/ex/uat.env`, `EX_ENV=prod` → `/etc/ex/prod.env`) or a path in `ENV_FILE`, and pass it to compose as `--env-file` and to the app as `env_file`. `server/docker-compose.yml` stays the local-dev file.

    cd server
    dotenvx set API_DOCS true -f .env.uat --plain     # non-secret
    dotenvx set DASHBOARD_PASSWORD "$(openssl rand -hex 16)" -f .env.uat
    dotenvx get -f .env.uat                           # read (needs the key)

Commit the change; the next deploy applies it. The repo is public, so the ciphertext is public forever: if the private key ever leaks, rotate every value in the file, not just the key.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | set by the compose file | `ecto://ex:ex@db/ex` (the Postgres container). Phase B: Managed Postgres URL |
| `DATABASE_SSL` | **Phase B** | `true` on Managed Postgres; use `verify_peer` with DO's CA certificate |
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `TOKEN_SIGNING_SECRET` | yes | signs access tokens; changing it signs everyone out |
| `APP_HOST` | yes | host Traefik routes to the app |
| `APP_ENTRYPOINT` | no | `web` or `websecure` (default) |
| `TRAEFIK_ACME_EMAIL` | no | Let's Encrypt account email (optional) |
| `PHX_HOST` | no | default `ex.pongpong.eu.org`; the host the app puts in URLs |
| `PORT` | no | default 4000 |
| `POOL_SIZE` | no | Phase A: 3. Phase B: keep `pool x containers` inside the database's connection limit, leaving room for `bin/migrate` |
| `CORS_ORIGINS` | Phase A | comma-separated exact client origins (worker URL, preview URLs). Name to be fixed when the plug is built |
| `CLIENT_IP_SOURCE` | no | `x-forwarded-for` (Phase A) or `cf-connecting-ip` (Phase B). Name to be fixed when the plug is built |
| `RELEASE_COOKIE` | yes | Erlang distribution cookie, `openssl rand -hex 32`. The one built into the image is public |
| `API_DOCS` | no | `true` serves `/api/docs` and `/api/v1/open_api`; anything else answers 404 |
| `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD` | for seeding | no defaults; without them the seed creates nothing. Used by the first deploy and by `uat reset db` |
| `DASHBOARD_USER`, `DASHBOARD_PASSWORD` | optional | no defaults; the dashboard answers 404 until both are set |

## One-time droplet setup

1. Create the droplet: Ubuntu 24.04, 1 GB, Singapore, SSH key only.
2. DO cloud firewall: inbound 22, 80 (temporary, while UAT runs on the IP) and 443. **Phase B:** 443 from Cloudflare IP ranges only.
3. As root:
   - add 2 GB swap;
   - install Docker Engine and the compose plugin;
   - enable `unattended-upgrades`;
   - set `PermitRootLogin no` and `PasswordAuthentication no` in `sshd_config`;
   - write `/etc/docker/daemon.json` with `{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}` and restart Docker.
4. Create the `deploy` user and add it to the `docker` group. The `docker` group is effectively root; this user limits mistakes, it is not a security boundary.
5. As root: `install -d -o deploy -g deploy -m 700 /etc/ex /opt/ex` (CI writes `/etc/ex/uat.env` and copies `deploy/` to `/opt/ex/server`). The stack keeps the compose project name `ex`, so the first CI deploy takes over containers started by hand and keeps the `ex_pgdata` volume.
6. Give CI an SSH key for `deploy` (on your laptop):

       ssh-keygen -t ed25519 -N '' -C ci-deploy -f ci_deploy
       ssh-copy-id -i ci_deploy.pub deploy@159.223.95.98
       ssh-keyscan -t ed25519 159.223.95.98          # output = DEPLOY_KNOWN_HOSTS

7. GitHub → Settings → Environments → `uat` → secrets:

   | Secret | Value |
   |---|---|
   | `DEPLOY_HOST` | `159.223.95.98` |
   | `DEPLOY_USER` | `deploy` |
   | `DEPLOY_SSH_KEY` | contents of `ci_deploy` (then delete the local file) |
   | `DEPLOY_KNOWN_HOSTS` | the `ssh-keyscan` line |
   | `DOTENV_PRIVATE_KEY_UAT` | the value from `server/.env.keys` |

   In the Environment's **Deployment branches** setting choose **No restriction**: PR deploys run on `refs/pull/<n>/merge`, which a "protected branches only" rule rejects.

   Optional variable `DEPLOY_PATH`: the folder holding the compose files (default `/opt/ex/server`).
8. Add a free uptime check on `/health` that alerts to Telegram.

The droplet needs no registry login: each deploy logs in with the job's short-lived token and logs out after.

If the stack already runs from another folder, stop it there first (`docker compose down`, without `-v`). The compose project is named `ex` everywhere, so the new checkout takes over the same `ex_pgdata` volume.

## CI/CD

`.github/workflows/server.yml`:

| What you do | test | build | deploy to UAT |
|---|---|---|---|
| Open or push a PR (no label) | ✅ | · | · |
| PR label `build` | ✅ | ✅ `pr-<n>-<sha>` | · |
| PR label `deploy:uat` (new commits redeploy) | ✅ | ✅ `pr-<n>-<sha>` | ✅ |
| Push or merge to `release/**` | ✅ | ✅ `sha-<sha>`, `release-x.y.z` | · |
| Push git tag `v1.2.3` | · | renames `sha-<sha>` | · |
| Actions → server → Run workflow: `build` | ✅ | ✅ `sha-<sha>` | · |
| Run workflow: `build-deploy` | ✅ | ✅ `sha-<sha>` | ✅ |
| Run workflow: `deploy` + tag (rollback, redeploy) | · | · | ✅ that tag |

From the terminal: `gh workflow run server.yml --ref <branch> -f action=build` (or `-f action=deploy -f tag=sha-4a2fab2`).

- **One PR owns UAT.** When a `deploy:uat` PR deploys, CI removes the label from any other PR and comments on both. Deploys queue one at a time.
- **Fork PRs** get tests only; labels on them do nothing.
- **Build once.** Adding `deploy:uat` after `build` on the same commit reuses the image.
- **Tag a tested commit.** `git tag v1.0.0 <sha> && git push origin v1.0.0` fails if that commit was never built on `release/**`.

A deploy job: checks the image exists, decrypts `server/.env.uat` to `/etc/ex/uat.env`, copies `deploy/` to the droplet, then runs `deploy/deploy.sh <tag>`.

`deploy/deploy.sh <tag>`: pull the image, run `/app/bin/migrate` in a one-off container, `up -d`, then ask the app for `/health` (from the Traefik container) for up to a minute. On success it writes the tag to `.deployed-tag`. On failure it prints the app logs, starts the previous tag again and exits 1, which fails the job.

### Reset the UAT database

PR branches can leave migrations the next PR doesn't have. **Actions → uat reset db → Run workflow**, type `RESET`: stops the app, drops and recreates the database, migrates, seeds the Admin from `SEED_ADMIN_*`, and starts the same image again. On the droplet: `deploy/reset-db.sh --yes`.

### By hand (CI down)

    cd /opt/ex/server
    ./deploy/deploy.sh sha-4a2fab2                  # /etc/ex/uat.env
    EX_ENV=prod ./deploy/deploy.sh 1.0.0            # /etc/ex/prod.env
    ENV_FILE=./.env ./deploy/deploy.sh sha-4a2fab2  # any file

Rules:
- Migrations are additive (add, switch over, drop later). The old container serves traffic while `bin/migrate` runs, and a rollback does not undo a migration.
- API changes stay compatible with the live client; ship the API before the client that needs it.
- **Phase B:** prod deploys a version tag (`1.2.3`) that already ran on UAT, after an approval in a `production` GitHub Environment. Tags are never reused.

## First deploy only

Create the first Admin from `SEED_ADMIN_*` (idempotent; running it again does nothing):

    cd /opt/ex/server
    source deploy/common.sh && TAG=$(cat .deployed-tag) \
      dc run --rm -l traefik.enable=false app /app/bin/ex eval "Ex.Release.seed()"

The seed only creates the admin if it doesn't exist; it never changes an existing password. After a seed into an empty database (or `uat reset db`), the password is `dotenvx get SEED_ADMIN_PASSWORD -f server/.env.uat`. An admin created before that keeps its old password.

## Checks before the first real deploy

- No container except Traefik publishes a host port.
- The temporary droplet-IP entries in `server/config/prod.exs` are gone; `force_ssl` trusts `x-forwarded-proto`.
- Traefik serves a valid Let's Encrypt certificate (Phase A) or the Cloudflare Origin Certificate with Full (strict) (Phase B).
- The migrations also create the permission and role data, so no extra seeding is needed for them.
- After launch, build new indexes `concurrently` in their own migration (see `docs/database-health.md`).

## Ops dashboard

LiveDashboard is at `/ops/dashboard` (in dev: `/dev/dashboard`), behind HTTP basic auth, and answers 404 until both `DASHBOARD_USER` and `DASHBOARD_PASSWORD` are set. Traefik never routes `/ops` or `/live`, so it is not reachable from the internet. Open it through an SSH tunnel to the app container's port, for example:

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
- Rebuild a droplet from scratch: create it with the steps above, add the private key from the password manager to the GitHub Environment, run `deploy` with the last good tag. Target: back up within about 2 hours.
