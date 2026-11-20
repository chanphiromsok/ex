#!/usr/bin/env bash
# Runs on the droplet: deploy/deploy.sh <image tag>   (e.g. sha-4a2fab2, pr-18-c3f9a1b, 1.0.0)
# Pulls the image, runs migrations, swaps the app container, checks /health,
# and goes back to the previous tag if the check fails. CI calls it; it also works by hand.
set -euo pipefail
source "$(dirname "$0")/common.sh"

new="${1:?usage: deploy.sh <image tag>}"
prev="$(cat .deployed-tag 2>/dev/null || true)"

export TAG="$new"
echo "==> pull $TAG"
# Plain docker pull: fails hard on a missing tag (compose would try to build the app instead).
docker pull -q "ghcr.io/chanphiromsok/ex:$TAG"
echo "==> migrate"
# The old container keeps serving while this runs, so migrations must be additive.
# The label keeps Traefik from routing to the one-off container.
dc run --rm -l traefik.enable=false app /app/bin/migrate
echo "==> start"
dc up -d --no-build --remove-orphans

if healthy; then
  echo "$new" > .deployed-tag
  docker image prune -f > /dev/null
  echo "==> deployed $new"
  exit 0
fi

echo "==> /health failed for $new" >&2
dc logs --tail 50 app >&2 || true
if [ -n "$prev" ] && [ "$prev" != "$new" ]; then
  echo "==> rolling back to $prev" >&2
  TAG="$prev" dc up -d --no-build
  healthy && echo "==> rolled back to $prev" >&2
fi
exit 1
