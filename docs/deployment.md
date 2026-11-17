# Deployment (Docker, DigitalOcean)

The `Dockerfile` builds a Mix release (`mix release`) in one image stage and copies only the release into a slim Debian runner. The image listens on `$PORT` (default 4000) and runs `bin/server`.

## Environment variables

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST:PORT/DB` |
| `DATABASE_SSL` | for managed DB | `true` on DigitalOcean Managed PostgreSQL (encrypts, does not verify the certificate) |
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `TOKEN_SIGNING_SECRET` | yes | signs access tokens; changing it signs everyone out. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | yes | public hostname, used to build URLs |
| `PORT` | no | default 4000; App Platform sets it for you |
| `POOL_SIZE` | no | default 10; keep `pool_size x instances` below the database's connection limit |
| `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD` | first deploy | read by the seed command; the dev defaults must never reach production |

## Every deploy

1. Build and push the image.
2. Run `/app/bin/migrate` before the new version takes traffic (App Platform: a *pre-deploy job*; Droplet: `docker run --rm --env-file .env IMAGE bin/migrate`).
3. Start the container (`bin/server`). Health check: `GET /health` (200 when the database answers; excluded from the HTTPS redirect).

## First deploy only

Create the first Admin (idempotent, so running it again does nothing):

    /app/bin/ex eval "Ex.Release.seed()"

## Checks before the first real deploy

- TLS terminates at the load balancer; `force_ssl` trusts `x-forwarded-proto`.
- The migrations in `priv/repo/migrations` also create the permission and role tables' data, so no extra seeding is needed for them.
- While the table has little data a plain index build is fine. After launch, build new indexes `concurrently` in their own migration (see `docs/database-health.md`).
- Expired refresh tokens are never deleted yet.

## Verified locally (without Docker)

`MIX_ENV=prod mix assets.deploy && mix release`, then `bin/migrate`, `Ex.Release.seed()`, `PHX_SERVER=true bin/ex start`: `/health` 200, admin sign-in works, `/api/v1/open_api` 200. The `Dockerfile` itself has not been built, because Docker is not installed on this machine.
