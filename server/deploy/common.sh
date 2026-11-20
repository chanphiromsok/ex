# Sourced by deploy.sh and reset-db.sh. Runs from server/ (where .deployed-tag lives).
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Pick the environment: EX_ENV=uat (default) reads /etc/ex/uat.env, EX_ENV=prod reads /etc/ex/prod.env.
# ENV_FILE overrides the path, e.g. ENV_FILE=./.env for a by-hand test.
EX_ENV="${EX_ENV:-uat}"
ENV_FILE="$(realpath "${ENV_FILE:-/etc/ex/$EX_ENV.env}" 2> /dev/null || echo "${ENV_FILE:-/etc/ex/$EX_ENV.env}")"
[ -f "$ENV_FILE" ] || { echo "env file $ENV_FILE not found" >&2; return 1 2> /dev/null || exit 1; }
export ENV_FILE

# The env file must set real values; otherwise docker-compose.yml would fall back to the public local ones.
for v in SECRET_KEY_BASE TOKEN_SIGNING_SECRET RELEASE_COOKIE APP_HOST; do
  grep -Eq "^$v=[\"']?[^\"' ]" "$ENV_FILE" || { echo "$ENV_FILE: set $v" >&2; return 1 2> /dev/null || exit 1; }
done

# Server-only parts of docker-compose.yml: Traefik, and the app port on loopback only.
export COMPOSE_PROFILES="${COMPOSE_PROFILES:-proxy}" APP_BIND="${APP_BIND:-127.0.0.1:4001}"

dc() { docker compose --env-file "$ENV_FILE" -f docker-compose.yml "$@"; }

# Asks the app from the Traefik container, so it works for any host or entrypoint.
healthy() {
  for _ in $(seq 30); do
    dc exec -T traefik wget -q -O /dev/null http://app:4000/health 2> /dev/null && return 0
    sleep 2
  done
  return 1
}
