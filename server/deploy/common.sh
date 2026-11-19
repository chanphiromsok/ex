# Sourced by deploy.sh and reset-db.sh. Runs from server/ (where .deployed-tag lives).
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Pick the environment: EX_ENV=uat (default) reads /etc/ex/uat.env, EX_ENV=prod reads /etc/ex/prod.env.
# ENV_FILE overrides the path, e.g. ENV_FILE=./.env for a by-hand test.
EX_ENV="${EX_ENV:-uat}"
ENV_FILE="$(realpath "${ENV_FILE:-/etc/ex/$EX_ENV.env}" 2> /dev/null || echo "${ENV_FILE:-/etc/ex/$EX_ENV.env}")"
[ -f "$ENV_FILE" ] || { echo "env file $ENV_FILE not found" >&2; return 1 2> /dev/null || exit 1; }
export ENV_FILE

dc() { docker compose --env-file "$ENV_FILE" -f deploy/docker-compose.yml "$@"; }

# Asks the app from the Traefik container, so it works for any host or entrypoint.
healthy() {
  for _ in $(seq 30); do
    dc exec -T traefik wget -q -O /dev/null http://app:4000/health 2> /dev/null && return 0
    sleep 2
  done
  return 1
}
