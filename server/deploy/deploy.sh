#!/usr/bin/env bash
# Runs on the droplet, from /opt/ex/deploy/: deploy.sh <image tag>
# Pulls the image, runs migrations, swaps the app container, checks /health,
# and goes back to the previous tag if the check fails. CI calls it; it also works by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

new="${1:?usage: deploy.sh <image tag>}"
prev="$(cat .deployed-tag 2>/dev/null || true)"

dc() { docker compose -f docker-compose.yml -f docker-compose.prod.yml "$@"; }

# Asks Traefik from inside its container, so the request goes through the real routing
# (temporary plain-HTTP router, Host localhost). Switch to the HTTPS router when that one is removed.
healthy() {
  for _ in $(seq 30); do
    dc exec -T traefik wget -q -O /dev/null --header "Host: localhost" http://127.0.0.1/health 2> /dev/null && return 0
    sleep 2
  done
  return 1
}

export TAG="$new"
echo "==> pull $TAG"
# Tags are git SHAs and never reused, so an image already on the host is the right one.
dc pull --policy missing app
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
