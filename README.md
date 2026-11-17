# Express Cargo

Parcel counter system for Cambodia.

| Folder | What | Run |
| --- | --- | --- |
| `server/` | Phoenix + Ash JSON:API backend, Postgres | `cd server && mix setup && mix phx.server` (port 4000) |
| `client/` | Staff portal, TanStack Start + React | `cd client && pnpm install && pnpm dev` (port 3000, proxies `/api` to 4000) |

- Docker (app + Postgres): `cd server && docker compose up --build`
- Domain terms: `GLOSSARY.md`. Decisions and deploy notes: `docs/`.
