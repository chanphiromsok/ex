# Two-phase rollout: UAT on the droplet IP over HTTP, launch on a real domain

There is no usable domain yet (the free domain is waiting for Cloudflare approval, and a real one will be bought later). Testing goes ahead now instead of waiting.

**Phase A (UAT, now):** one 1 GB DigitalOcean droplet in Singapore running `server/docker-compose.yml` (the same file used locally): Traefik, the API and a Postgres container. `/etc/ex/uat.env` sets `APP_HOST=159.223.95.98` and `APP_ENTRYPOINT=web`, so Traefik serves the API over plain HTTP on port 80 at the droplet IP. `/ops` and `/live` are not routed; reach them through an SSH tunnel. The client runs on a developer's machine, and its Vite dev server proxies `/api` to the droplet, so the browser never talks to the IP directly. Testers only; no real customer data, so no backups. Firewall 22 and 80.

**Phase B (launch):** real domain behind Cloudflare. The same compose file with `/etc/ex/prod.env`: `APP_HOST=<domain>`, `APP_ENTRYPOINT=websecure`, Let's Encrypt certificate (HTTP-01, so port 80 stays open), Cloudflare SSL mode Full (strict), 443 open to Cloudflare ranges only, Traefik trusts forwarded headers from those ranges. DO Managed Postgres with point-in-time recovery plus a nightly dump at another provider, Sentry. The Phase A droplet becomes staging; prod is deployed by hand with an image tag proven on staging. Load numbers, budget and the first departure time are collected before Phase B and size it.

Rejected: Let's Encrypt on a `159-223-95-98.sslip.io` hostname for Phase A (real HTTPS, but a hostname nobody keeps, shared Let's Encrypt rate limits, and the client runs locally anyway). Rejected: a self-signed certificate (every tester has to click through warnings). Rejected: a Cloudflare Origin Certificate for Phase B (needs a Traefik file provider and certificate files on the droplet again; Let's Encrypt needs only flags in the compose file).

## Consequences

- Passwords and tokens cross the internet in clear text during Phase A. Acceptable for test data only; testers must not reuse real passwords.
- `server/config/prod.exs` keeps TEMPORARY droplet-IP entries (`check_origin`, `force_ssl` host exclusions) until Phase B, and they are removed then.
- Moving to Phase B is an env-file change plus DNS, not a compose change: a new `server/.env.prod` with its own secrets and key.
- `acme.json` is kept on the `letsencrypt` volume so restarts do not re-issue certificates.
- Any real data entered in Phase A is not backed up.
