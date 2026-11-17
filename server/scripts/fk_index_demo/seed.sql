-- Generates test data for the FK-index demo. Run through demo.sh (it passes the sizes).
-- Variables (psql -v): locations_n, stations_n, users_n, changes_n, tokens_n
-- Default scale (see demo.sh): 25 / 500 / 200000 / 1000000 / 2000000  (~870 MB with indexes, ~1 min)
-- All ids come from the table defaults; emails look like staff<N>@example.com.

INSERT INTO locations (name_en, name_km)
SELECT 'Location ' || g, 'ទីតាំង ' || g FROM generate_series(1, :locations_n) g;

CREATE TEMP TABLE loc AS SELECT id, row_number() OVER (ORDER BY name_en) - 1 AS n FROM locations;

INSERT INTO stations (name_en, name_km, location_id)
SELECT 'Station ' || g, 'ស្ថានី ' || g, (SELECT id FROM loc WHERE n = g % :locations_n)
FROM generate_series(1, :stations_n) g;

CREATE TEMP TABLE st AS SELECT id, row_number() OVER (ORDER BY name_en) - 1 AS n FROM stations;
CREATE INDEX ON st (n);

INSERT INTO users (email, hashed_password, role, station_id)
SELECT 'staff' || g || '@example.com', 'not-a-real-hash', 'staff', (SELECT id FROM st WHERE n = g % :stations_n)
FROM generate_series(1, :users_n) g;

INSERT INTO users (email, hashed_password, role) VALUES ('admin@example.com', 'not-a-real-hash', 'admin');

CREATE TEMP TABLE us AS SELECT id, row_number() OVER (ORDER BY email) - 1 AS n FROM users WHERE role = 'staff';
CREATE INDEX ON us (n);

INSERT INTO user_assignment_changes (role, user_id, station_id, changed_by_id)
SELECT 'staff', u.id, s.id, (SELECT id FROM users WHERE role = 'admin')
FROM generate_series(1, :changes_n) g
JOIN us u ON u.n = g % :users_n
JOIN st s ON s.n = g % :stations_n;

INSERT INTO refresh_tokens (token_hash, family_id, expires_at, user_id)
SELECT md5(g::text) || md5((g + 1)::text), gen_random_uuid(), now() + interval '30 days', u.id
FROM generate_series(1, :tokens_n) g
JOIN us u ON u.n = g % :users_n;

ANALYZE;
