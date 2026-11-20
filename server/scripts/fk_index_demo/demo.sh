#!/usr/bin/env bash
# FK-index demo: build a big throwaway database, measure with and without foreign-key indexes.
# Usage: ./demo.sh <command>      (run ./demo.sh help)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}" PGPASSWORD="${PGPASSWORD:-postgres}"
DEMO_DB="${DEMO_DB:-ex_fk_demo}"   # the throwaway database
SOURCE_DB="${SOURCE_DB:-ex_dev}"   # a migrated dev database the schema is copied from
DUMP="${DUMP:-$HERE/$DEMO_DB.dump}"

# Data volume. Scale down for a quick run, e.g.  USERS=20000 CHANGES=100000 TOKENS=200000 ./demo.sh reset
LOCATIONS="${LOCATIONS:-25}" STATIONS="${STATIONS:-500}" USERS="${USERS:-200000}"
CHANGES="${CHANGES:-1000000}" TOKENS="${TOKENS:-2000000}"

demo() { psql -q -v ON_ERROR_STOP=1 -d "$DEMO_DB" "$@"; }

bench_summary() { # prints "test name ... time" from a bench output file
  grep -E '^=== |Execution Time' "$1" | sed -E 's/^=== //; s/ ===$//; s/^ Execution Time: /      -> /'
}

cmd_setup() { # create the database and copy the schema (and reference data) from SOURCE_DB
  psql -d postgres -qc "DROP DATABASE IF EXISTS $DEMO_DB" -c "CREATE DATABASE $DEMO_DB"
  pg_dump -s "$SOURCE_DB" | demo -f - >/dev/null
  pg_dump -a -t permissions -t role_permissions -t schema_migrations "$SOURCE_DB" | demo -f - >/dev/null
  echo "created $DEMO_DB from the schema of $SOURCE_DB"
}
cmd_seed() { # generate the test data
  demo -v locations_n="$LOCATIONS" -v stations_n="$STATIONS" -v users_n="$USERS" \
       -v changes_n="$CHANGES" -v tokens_n="$TOKENS" -f "$HERE/seed.sql"
  echo "seeded: $LOCATIONS locations, $STATIONS stations, $USERS users, $CHANGES assignment changes, $TOKENS refresh tokens"
}
cmd_bench()        { demo -f "$HERE/bench.sql"; }
cmd_index()        { demo -f "$HERE/indexes.sql"; echo "7 FK indexes created"; }
cmd_drop_indexes() { demo -f "$HERE/drop_indexes.sql"; echo "FK indexes dropped"; }
cmd_sizes()        { demo -f "$HERE/sizes.sql"; }
cmd_lint()         { pgbot lint "postgresql://$PGUSER:$PGPASSWORD@$PGHOST/$DEMO_DB" --no-color; }
cmd_reset()        { cmd_setup; cmd_seed; }

cmd_run() { # drop indexes -> bench -> create indexes -> bench -> compare
  local out; out="$(mktemp -d)"
  demo -f "$HERE/drop_indexes.sql"; cmd_bench > "$out/before.txt"
  demo -f "$HERE/indexes.sql";      cmd_bench > "$out/after.txt"
  echo "######## BEFORE (no FK indexes)"; bench_summary "$out/before.txt"
  echo; echo "######## AFTER (7 FK indexes)"; bench_summary "$out/after.txt"
  echo; echo "full query plans: $out/before.txt  $out/after.txt"
}

cmd_dump()    { pg_dump -Fc -d "$DEMO_DB" -f "$DUMP"; echo "dump written: $DUMP ($(du -h "$DUMP" | cut -f1))"; }
cmd_restore() { # load a dump instead of regenerating (faster than seed)
  [ -f "$DUMP" ] || { echo "no dump at $DUMP — run: ./demo.sh dump" >&2; exit 1; }
  psql -d postgres -qc "DROP DATABASE IF EXISTS $DEMO_DB" -c "CREATE DATABASE $DEMO_DB"
  pg_restore -d "$DEMO_DB" --no-owner "$DUMP"; echo "restored $DEMO_DB from $DUMP"
}
cmd_drop() { psql -d postgres -qc "DROP DATABASE IF EXISTS $DEMO_DB"; echo "dropped $DEMO_DB"; }

cmd_help() { cat <<H
./demo.sh <command>
  setup          create $DEMO_DB and copy the schema from $SOURCE_DB
  seed           generate the test data (see LOCATIONS/STATIONS/USERS/CHANGES/TOKENS)
  reset          setup + seed (fresh database)
  run            drop indexes, benchmark, add indexes, benchmark, print both
  bench          benchmark in the current state (full query plans)
  index          create the 7 FK indexes          drop-indexes   remove them
  sizes          index and table sizes            lint           pgbot lint of the demo database
  dump           pg_dump the database to a file   restore        load it back (skips seeding)
  drop           delete $DEMO_DB
H
}

case "${1:-help}" in
  setup) cmd_setup ;; seed) cmd_seed ;; reset) cmd_reset ;; run) cmd_run ;; bench) cmd_bench ;;
  index) cmd_index ;; drop-indexes) cmd_drop_indexes ;; sizes) cmd_sizes ;; lint) cmd_lint ;;
  dump) cmd_dump ;; restore) cmd_restore ;; drop) cmd_drop ;; help|-h|--help) cmd_help ;;
  *) echo "unknown command: $1" >&2; cmd_help >&2; exit 1 ;;
esac
