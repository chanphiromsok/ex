# Sourced by deploy.sh and reset-db.sh. Runs from the folder holding the compose files.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# CI writes the decrypted env file to /etc/ex/ex.env. Without it, compose falls back to ./.env.
ENV_FILE="${ENV_FILE:-/etc/ex/ex.env}"

dc() {
  if [ -f "$ENV_FILE" ]; then
    docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f docker-compose.prod.yml "$@"
  else
    docker compose -f docker-compose.yml -f docker-compose.prod.yml "$@"
  fi
}

# Asks Traefik from inside its container, so the request goes through the real routing
# (temporary plain-HTTP router, Host localhost). Switch to the HTTPS router when that one is removed.
healthy() {
  for _ in $(seq 30); do
    dc exec -T traefik wget -q -O /dev/null --header "Host: localhost" http://127.0.0.1/health 2> /dev/null && return 0
    sleep 2
  done
  return 1
}
