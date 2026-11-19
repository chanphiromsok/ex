# Images are built by CI; secrets are set by hand on the droplet

GitHub Actions tests, builds a `linux/amd64` image and pushes it to GHCR tagged by git SHA, then deploys over SSH as a `deploy` user: pull, `bin/migrate` as a one-off container, `up -d`, check `/health`, and redeploy the previous SHA if the check fails. The droplet never compiles; a 1 GB droplet cannot build the release reliably, and the same image then runs everywhere.

Secrets stay in `/opt/ex/.env` on the droplet (owned by `deploy`, mode 600), written by hand, with a copy in a password manager. CI holds only the SSH key and a GHCR token, so a leaked CI secret does not leak the database password or signing secrets.

Rejected: building on the droplet with systemd (the old `docs/deploy-droplet.md`): slow, needs swap to survive, and the build is not reproducible. Rejected: pushing `.env` from GitHub Environment secrets on each deploy: makes the droplet disposable, but the user preferred to keep app secrets off GitHub.

## Consequences

- Rebuilding a droplet needs the `.env` copy from the password manager.
- Seeding is not part of startup; the first Admin is created once by hand, and no default credentials exist in any compose file.
- Migrations and API changes must be additive, because the old container serves traffic while migrations run and a rollback does not undo them.
