# Foreign-key index demo

Builds a large throwaway Postgres database from this project's schema, then measures what
the missing foreign-key indexes cost (and what adding them buys). It exists to reproduce the
`pgbot` finding **"7 foreign key(s) without a supporting index"**.

Postgres does not index foreign key columns automatically. Without an index on the child
column, every `DELETE`/key `UPDATE` of a parent row scans the whole child table to check
references, and lookups like "this user's refresh tokens" scan it too.

Nothing here touches your real databases: it only creates and drops `ex_fk_demo`
(`DEMO_DB` to change it). `ex_dev` is only read, to copy its schema.

## Prerequisites

- Postgres running on `localhost` with user/password `postgres`/`postgres` (override with `PGHOST`, `PGUSER`, `PGPASSWORD`).
- `ex_dev` created and migrated (`mix ecto.setup`), since the schema is copied from it (`SOURCE_DB` to change).
- `psql`, `pg_dump`, `pg_restore` on the PATH.
- Optional: `pgbot` (`brew`-installed CLI) for `./demo.sh lint`.

## Quick start

```bash
cd scripts/fk_index_demo
./demo.sh reset     # create ex_fk_demo + generate the data (about a minute)
./demo.sh run       # benchmark without indexes, add the 7 indexes, benchmark again
```

`run` leaves the database with the indexes in place. Run it again any time: it drops them first.

## Commands

| Command | What it does |
|---|---|
| `setup` | Create `ex_fk_demo`, copy the schema (and permission reference data) from `ex_dev`. |
| `seed` | Generate the test data with `seed.sql`. |
| `reset` | `setup` + `seed`: a fresh database. |
| `run` | Drop indexes, benchmark, create indexes, benchmark, print both. Full plans are saved to the temp files it prints. |
| `bench` | Benchmark the database in its current state, with full `EXPLAIN` plans. |
| `index` / `drop-indexes` | Create / remove the 7 FK indexes (`indexes.sql`, `drop_indexes.sql`). |
| `sizes` | Row counts and table/index sizes. |
| `lint` | `pgbot lint` of the demo database (97/100 without indexes, 100/100 with). |
| `dump` / `restore` | Save the database to `ex_fk_demo.dump` and load it back without re-seeding. |
| `drop` | Delete the demo database. |

## Generating the data

`seed.sql` takes its volumes from environment variables:

| Variable | Default | Table |
|---|---|---|
| `LOCATIONS` | 25 | `locations` |
| `STATIONS` | 500 | `stations` |
| `USERS` | 200000 | `users` (staff, spread over the stations) |
| `CHANGES` | 1000000 | `user_assignment_changes` |
| `TOKENS` | 2000000 | `refresh_tokens` |

Quick run at a tenth of the size:

```bash
USERS=20000 CHANGES=100000 TOKENS=200000 ./demo.sh reset
```

`bench.sql` times three deletes and three everyday queries. Each delete first inserts its own
row that nothing references (a user, a station, a location) inside a transaction, then
`EXPLAIN ANALYZE`s the delete and rolls back. The delete succeeds, but Postgres still has to prove
no child row points at it, which is where a missing FK index hurts. Because every write is rolled
back, re-running leaves the data unchanged. The query tests look up `staff777@example.com`,
so `USERS` must be at least 778.

## Dump for later testing

Generating the full data takes about a minute. To keep a copy and skip that next time:

```bash
./demo.sh dump       # writes ex_fk_demo.dump (custom format, compressed)
./demo.sh restore    # recreates ex_fk_demo from it
```

The dump is git-ignored (`*.dump`) because it is large and reproducible with `./demo.sh seed`.
The scaled-down data (`USERS=20000 ...`) dumps to about 19 MB; the default volumes are
considerably larger. Share it out of band if you need to hand it to someone, or have them run `reset`.

Restore with plain tools instead of the script:

```bash
createdb ex_fk_demo
pg_restore -d ex_fk_demo --no-owner ex_fk_demo.dump
```

## Results at the default volumes

200,002 users, 1,000,001 assignment changes, 2,000,000 refresh tokens (Postgres 18, laptop):

| Test | No indexes | 7 indexes |
|---|---|---|
| Delete an unreferenced user | 215-256 ms | 0.5 ms |
| Delete an unreferenced station | 59-62 ms | 0.1 ms |
| Delete an unreferenced location | 0.1 ms | 0.03 ms |
| A user's refresh tokens | 43-47 ms | 0.05 ms |
| A user's latest assignment | 22 ms | 0.03 ms |
| Staff at one station | 8 ms | 0.08 ms |

Cost: the 7 indexes add about 49 MB (824 MB to 873 MB, +6%), mostly
`refresh_tokens (user_id)` at 20 MB and `user_assignment_changes (user_id, inserted_at)` at 15 MB.
The two tiny tables (`stations.location_id`, `role_permissions.permission`) cost 16 kB each.
Insert cost on the indexed tables was not measured.

Timings vary run to run with caching; the orders of magnitude do not.

## The 7 indexes

| Child table | Column(s) |
|---|---|
| `refresh_tokens` | `user_id` |
| `user_assignment_changes` | `(user_id, inserted_at)`, `station_id`, `changed_by_id` |
| `users` | `station_id` |
| `stations` | `location_id` |
| `role_permissions` | `permission` |

They are in the project's migrations (`add_fk_indexes`), declared with `index?: true` on each `reference`
(plus a `custom_indexes` entry for the composite). The demo's `indexes.sql` / `drop_indexes.sql` mirror them
so you can still measure the difference on the demo database. If a migration changes them, update both files.
