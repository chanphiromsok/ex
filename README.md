# Express Cargo

Parcel counter system for Cambodia.

| Folder | What | Run |
| --- | --- | --- |
| `server/` | Phoenix + Ash JSON:API backend, Postgres | `cd server && mix setup && mix phx.server` (port 4000) |
| `client/` | Staff portal, TanStack Start + React | `cd client && pnpm install && pnpm dev` (port 3000, proxies `/api` to 4000) |

- Domain terms: `GLOSSARY.md`. Decisions and deploy notes: `docs/`.

## Docker

There is one compose file, `server/docker-compose.yml`, for your Mac and every server. Only the env file changes.

**On your Mac** (Postgres + app, built from your code):

```sh
cd server
docker compose up --build        # API on http://localhost:4001
docker compose logs -f app       # follow logs
docker compose down              # stop (data is kept)
docker compose down -v           # stop and delete the database
```

No setup needed: it uses local-only secrets. To seed an admin or turn on `/ops`, put these in `server/.env` (git-ignored):

```sh
SEED_ADMIN_EMAIL=admin@example.com
SEED_ADMIN_PASSWORD=change-me
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=change-me
```

**On a server** (Traefik + Postgres + app, image pulled from GHCR). Always use the deploy scripts, never a bare `docker compose up`: the scripts add Traefik, keep the app port on `127.0.0.1`, and refuse to run without real secrets.

```sh
cd server
./deploy/deploy.sh sha-3c94736              # UAT, reads /etc/ex/uat.env
EX_ENV=prod ./deploy/deploy.sh 1.0.0        # prod, reads /etc/ex/prod.env
./deploy/reset-db.sh --yes                  # UAT only: wipe and reseed the database
```

| | Mac | Server |
| --- | --- | --- |
| Image | built from source (`:local`) | `ghcr.io/chanphiromsok/ex:<tag>` |
| Traefik | off | on, ports 80/443 |
| App port | `localhost:4001` | `127.0.0.1:4001` (SSH tunnel only) |
| Env | optional `server/.env` | `/etc/ex/<env>.env` (from `server/.env.uat`, encrypted) |

To run compose commands by hand on a server (logs, shell), load the same settings first:

```sh
cd server
bash -c 'source deploy/common.sh && dc ps && dc logs --tail 50 app'
```

## CI: build and deploy images

Pushes to a PR only run tests. An image is built only when you ask for one:

| You want | Do this | Image tag |
| --- | --- | --- |
| Build the latest commit of a branch | `gh workflow run server.yml --ref release/1.0.0 -f action=build` | `sha-<commit>` |
| Build and deploy to UAT | `gh workflow run server.yml --ref release/1.0.0 -f action=build-deploy` | `sha-<commit>` |
| Deploy an existing image to UAT | `gh workflow run server.yml --ref release/1.0.0 -f action=deploy -f tag=sha-71206b4` | |
| Build from a PR | add the label `build` to the PR (remove and re-add it to build again) | `pr-<n>-<commit>` |
| Build and deploy from a PR | add the label `deploy:uat` | `pr-<n>-<commit>` |
| Release (no rebuild: re-tags the `sha-<commit>` image, so build that commit first) | `git tag v1.0.0 && git push origin v1.0.0` | `1.0.0`, `1.0`, `latest` |

On GitHub: **Actions → server → Run workflow**, pick the branch and the action.

**Re-run** on an old run rebuilds that run's old commit, and a re-run of a plain push run only tests again. For a new commit use **Run workflow** or the label.

Watch a run: `gh run watch` · images: GitHub → Packages → `ex`.

Full guide: `docs/deployment.md`.
