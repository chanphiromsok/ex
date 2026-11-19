# Client always reaches the API same-origin; no CORS

The TanStack Start client is built and deployed on its own. The droplet serves only the API, so the two deploy separately. The browser never calls the API on another origin, so the API has no CORS plug in any phase.

**Phase A (UAT, now):** the client runs on a developer's machine with the Vite dev server. `client/vite.config.ts` proxies `/api` to `API_URL` (`http://159.223.95.98`) with `changeOrigin: true`, so the browser sees one origin (`localhost`) and Traefik sees `Host: 159.223.95.98`, which matches its router. Testers who are not developers run the client the same way or wait for Phase B.

**Phase B (launch):** the client is deployed to Cloudflare Workers on one hostname with the API. A Workers route sends `app.domain/*` to the client worker and a second route `app.domain/api/*` to the origin with no worker, so requests stay same-origin. This also avoids preflights: the JSON:API content type `application/vnd.api+json` forces one per URL and method, URLs carry ids so preflight caching barely helps, and on mobile links in Cambodia the extra round trip is worth removing.

Rejected: a hosted client on `*.workers.dev` during Phase A. It is served over HTTPS, so the browser blocks its calls to the HTTP-only API on the droplet IP (mixed content), and it would need a CORS allow-list that Phase B removes again. Rejected: a Workers Custom Domain in Phase B (it sends every path, `/api` included, to the worker). Rejected: the worker proxying `/api` to the origin (an extra hop, and every API call counts against the Workers request quota). Rejected: Phoenix serving the client (the client deploys on its own schedule; Traefik cannot serve files).

## Consequences

- No CORS code or `CORS_ORIGINS` setting on the server.
- Until Phase B there is no hosted client; UAT needs a local client checkout with `client/.env` pointing `API_URL` at the droplet.
- If a hosted client is wanted before the domain exists, it needs HTTPS on the API first, and this decision is revisited.
- An API change the client needs ships first, and the API stays compatible with the client version that is live.
