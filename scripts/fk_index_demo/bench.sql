\pset pager off
\timing off
-- Every write is rolled back, so the data is unchanged. Deleted rows are inserted first and
-- have nothing pointing at them: the delete succeeds, but Postgres must still prove that
-- by checking each child table, which is exactly where a missing FK index hurts.

\echo '=== 1. DELETE an unreferenced user (checks refresh_tokens, user_assignment_changes x2) ==='
BEGIN;
INSERT INTO users (id, email, hashed_password, role) VALUES ('00000000-0000-0000-0000-0000000000d1', 'bench@example.com', 'x', 'admin');
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) DELETE FROM users WHERE id = '00000000-0000-0000-0000-0000000000d1';
ROLLBACK;

\echo '=== 2. DELETE an unreferenced station (checks users, user_assignment_changes) ==='
BEGIN;
INSERT INTO locations (id, name_en, name_km) VALUES ('00000000-0000-0000-0000-0000000000a1', 'Bench Location', 'បេនឆ៍');
INSERT INTO stations (id, name_en, name_km, location_id) VALUES ('00000000-0000-0000-0000-0000000000e1', 'Bench Station', 'បេនឆ៍', '00000000-0000-0000-0000-0000000000a1');
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) DELETE FROM stations WHERE id = '00000000-0000-0000-0000-0000000000e1';
ROLLBACK;

\echo '=== 3. DELETE an unreferenced location (checks stations) ==='
BEGIN;
INSERT INTO locations (id, name_en, name_km) VALUES ('00000000-0000-0000-0000-0000000000f1', 'Bench Location 2', 'បេនឆ៍');
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) DELETE FROM locations WHERE id = '00000000-0000-0000-0000-0000000000f1';
ROLLBACK;

\echo '=== 4. Everyday query: refresh tokens of one user ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT * FROM refresh_tokens WHERE user_id = (SELECT id FROM users WHERE email = 'staff777@example.com');

\echo '=== 5. Everyday query: current assignment of one user (latest row) ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT * FROM user_assignment_changes WHERE user_id = (SELECT id FROM users WHERE email = 'staff777@example.com') ORDER BY inserted_at DESC LIMIT 1;

\echo '=== 6. Everyday query: staff at one station ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT count(*) FROM users WHERE station_id = (SELECT id FROM stations ORDER BY name_en LIMIT 1);
