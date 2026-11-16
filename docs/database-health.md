# Database health: pgbot, foreign-key indexes, MCP

How we check the Postgres schema for problems, why every foreign key gets an index, and how to
let an AI agent run the same checks.

## pgbot

`pgbot` is a read-only Postgres health scanner (`brew`-installed CLI; it never writes).

```bash
pgbot lint postgresql://postgres:postgres@localhost/ex_dev    # schema findings only, catalog-based
pgbot inspect postgresql://postgres:postgres@localhost/ex_dev --full
pgbot explain-finding fk_unindexed                            # explanation of one finding
```

`lint` needs no query history, so it works on a fresh or empty database and is suitable for CI
(`--fail-on-new <base.json>` reports only what a PR changed).

To scan a real environment, create its read-only role first. `pgbot init` only prints the SQL, it runs nothing:

```bash
pgbot init "postgres://admin@host/db"   # review it, set a password, then pipe it to psql yourself
```

## Rule: index every foreign key

Postgres does not index foreign key columns. Without an index on the child column, deleting or
re-keying a parent row scans the whole child table, and lookups by that column scan it too.

- **Default:** index every foreign key on a table that will grow (Shipments, Parcels, Payments, status events, logs, tokens).
- **Fine to skip, say why in the PR:** a column already leading a composite index (`(user_id, inserted_at)` covers `user_id`), or an FK to a parent that is never deleted or re-keyed and is never filtered on (e.g. `created_by_id` / `changed_by_id` pointing at users).
- **Tiny tables:** we index them anyway (`stations.location_id`, `role_permissions.permission`, ~16 kB each). It costs nothing and keeps `pgbot lint` at 100/100, so there is no exemption by size.
- **Also index non-FK columns you filter on.** pgbot cannot see these: e.g. `refresh_tokens.family_id` (see below).
- **Cost:** about 10 bytes per row per index plus a little write overhead.

In Ash, set `index?: true` on the `reference` in the resource's `postgres` block, then run
`mix ash.codegen <name>` and commit the migration.

### Current state

All foreign keys are indexed (`pgbot lint`: 100/100), added in migration `add_fk_indexes`:

| Child table | Column(s) |
|---|---|
| `refresh_tokens` | `user_id` |
| `user_assignment_changes` | `(user_id, inserted_at)`, `station_id`, `changed_by_id` |
| `users` | `station_id` |
| `stations` | `location_id` |
| `role_permissions` | `permission` |
| `refresh_tokens` | `family_id` where `revoked_at IS NULL` (not an FK; used by replay handling) |

`user_assignment_changes.user_id` is covered by the composite index, declared under `custom_indexes`
in the resource, which also serves the "latest assignment of a user" lookup.

### Caveats

- The delete speedups below are mostly theoretical today. Every user gets an append-only
  `user_assignment_changes` row with `ON DELETE RESTRICT`, so users cannot be deleted in the app, and the
  `refresh_tokens` cascade never fires. The indexes still pay off for lookups and future deletes.
- Nothing queries `user_assignment_changes` for a user's "latest" assignment yet. If it ever does, order by a
  tiebreaker as well as `inserted_at` (rows written in one transaction share a timestamp).
- `refresh_tokens.family_id` (partial index `WHERE revoked_at IS NULL`): replay revocation scans without it
  (69 ms at 2M rows, 0.04 ms with it). The partial predicate shrinks little, since used tokens are not revoked;
  the index was 60 MB on the demo's 2M distinct families. Expired tokens are never deleted yet, so the table grows
  without bound; a cleanup job is still to do.
- Insert cost, measured on the demo (100k single-row inserts): `refresh_tokens` +10 us/row (+35%),
  `user_assignment_changes` +7-13 us/row. Under 1% of a request.
- Before launch, plain `create index` is fine. Once there is production data, build indexes in their own
  migration with `@disable_ddl_transaction true`, `@disable_migration_lock true` and `concurrently: true`.

### Measured impact

`scripts/fk_index_demo/` builds a throwaway database (200k users, 1M assignment changes, 2M refresh
tokens) and benchmarks with and without these indexes. See its
[README](../scripts/fk_index_demo/README.md) for commands, data generation and dump/restore.

| Test | No indexes | 7 indexes |
|---|---|---|
| Delete an unreferenced user | 215-256 ms | 0.5 ms |
| Delete an unreferenced station | 59-62 ms | 0.1 ms |
| A user's refresh tokens | 43-47 ms | 0.05 ms |
| A user's latest assignment | 22 ms | 0.03 ms |
| Staff at one station | 8 ms | 0.08 ms |

Added size: about 49 MB on 824 MB (+6%). `pgbot lint`: 97/100 without, 100/100 with.

```bash
cd scripts/fk_index_demo && ./demo.sh reset && ./demo.sh run
```

## MCP: let an agent run pgbot

`pgbot mcp` serves two read-only tools over stdio: `inspect` (findings as JSON) and `unused_indexes`.
Register it in a **`.mcp.json`** at the repo root (leading dot; `mcp.json` is not read by Claude Code):

```json
{
  "mcpServers": {
    "pgbot": {
      "command": "pgbot",
      "args": ["mcp"],
      "env": { "DATABASE_URL": "${PGBOT_DATABASE_URL}" }
    }
  }
}
```

- Keep the credentials in your shell (`export PGBOT_DATABASE_URL=postgres://pgbot_ro:...@localhost:5432/ex_dev`), not in the file, so they are never committed.
- Use the read-only role from `pgbot init`, not a superuser.
- The app also exposes its own dev MCP endpoint (`AshAi.Mcp.Dev` at `/ash_ai/mcp`, see `lib/ex_web/endpoint.ex`).
