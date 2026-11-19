# Two-phase rollout: test on an sslip.io hostname, launch on a real domain

There is no usable domain yet (the free domain is waiting for Cloudflare approval, and a real one will be bought later). Testing goes ahead now instead of waiting.

**Phase A (test):** one 1 GB DigitalOcean droplet in Singapore running Traefik, the API and a Postgres container. Traefik gets a Let's Encrypt certificate for `159-223-95-98.sslip.io` with the TLS-ALPN-01 challenge, so testing is over real HTTPS on port 443 alone. Testers only; no real customer data, so no backups. Firewall 22 and 443.

**Phase B (launch):** real domain behind Cloudflare (Full strict, Origin Certificate on Traefik), firewall 443 to Cloudflare ranges only, DO Managed Postgres with point-in-time recovery plus a nightly dump at another provider, Sentry. The Phase A droplet becomes staging; prod is deployed by hand with a SHA proven on staging. Load numbers, budget and the first departure time are collected before Phase B and size it.

Rejected: plain HTTP on the droplet IP (passwords and tokens in clear text, and it needed temporary exceptions in `server/config/prod.exs`). Rejected: a self-signed certificate (every tester has to click through warnings).

## Consequences

- The temporary droplet-IP exceptions in `server/config/prod.exs` are removed.
- `acme.json` is kept on a volume; sslip.io shares Let's Encrypt rate limits with all its users, so re-issuing on each restart could fail.
- Any real data entered in Phase A is not backed up.
