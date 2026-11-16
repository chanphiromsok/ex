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
- **Fine to skip:** a tiny, stable table (e.g. `stations.location_id`), a parent that is never deleted or re-keyed, or a column already leading a composite index (`(user_id, inserted_at)` covers `user_id`). Say why in the PR.
- **Cost:** about 10 bytes per row per index plus a little write overhead.

In Ash, set `index?: true` on the `reference` in the resource's `postgres` block, then run
`mix ash.codegen <name>` and commit the migration.

### Current state

`pgbot lint` reports **7 foreign key(s) without a supporting index** on the real schema; they are
**not yet fixed in the migrations**:

| Child table | Column(s) |
|---|---|
| `refresh_tokens` | `user_id` |
| `user_assignment_changes` | `(user_id, inserted_at)`, `station_id`, `changed_by_id` |
| `users` | `station_id` |
| `stations` | `location_id` |
| `role_permissions` | `permission` |

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
