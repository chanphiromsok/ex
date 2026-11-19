# Client runs on Cloudflare Workers; CORS now, same origin at launch

The TanStack Start client is built and deployed on its own to Cloudflare Workers. The droplet serves only the API, so the two deploy separately.

**Phase A:** the client is on `*.workers.dev` and the API on the sslip.io hostname, so the API answers CORS. The plug sits in `server/lib/ex_web/endpoint.ex` before the router, so preflight requests are answered before the rate limiter. Allowed origins are an exact list from runtime config (worker URL, preview URLs, localhost). It allows the `Authorization` header with `max_age` 7200 and no credentials mode, because auth uses bearer tokens.

**Phase B:** one hostname. A Workers route sends `app.domain/*` to the client worker and a second route `app.domain/api/*` to the origin with no worker. Requests are same-origin and CORS is removed. The JSON:API content type `application/vnd.api+json` forces a preflight per URL and method, and URLs carry ids, so preflight caching barely helps; on mobile links in Cambodia the extra round trip is worth removing.

Rejected: a Workers Custom Domain (it sends every path, `/api` included, to the worker). Rejected: the worker proxying `/api` to the origin (an extra hop, and every API call counts against the Workers request quota). Rejected: Phoenix serving the client (the client deploys on its own schedule; Traefik cannot serve files).

## Consequences

- An API change the client needs ships first, and the API stays compatible with the client version that is live.
- The client's API URL is set at build time, so each environment gets its own client build.
