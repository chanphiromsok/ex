#!/usr/bin/env bash
# UAT only: deploy/reset-db.sh --yes
# Drops and recreates the database, migrates, seeds (SEED_ADMIN_* from the env file),
# then starts the image that was running. Use it when PR deploys leave the schema in a mixed state.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ "${1:-}" = "--yes" ] || { echo "This deletes all data. Run: deploy/reset-db.sh --yes" >&2; exit 2; }
TAG="$(cat .deployed-tag 2>/dev/null)" || { echo "no .deployed-tag: deploy once first" >&2; exit 1; }
export TAG

echo "==> stop app ($TAG)"
dc stop app
echo "==> recreate database"
dc exec -T db psql -U ex -d postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE IF EXISTS ex WITH (FORCE)' -c 'CREATE DATABASE ex OWNER ex'
echo "==> migrate and seed"
dc run --rm -l traefik.enable=false app /app/bin/migrate
dc run --rm -l traefik.enable=false app /app/bin/ex eval "Ex.Release.seed()"
echo "==> start"
dc up -d --no-build app
healthy && echo "==> UAT database reset, running $TAG"
