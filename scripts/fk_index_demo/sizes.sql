\pset pager off
SELECT i.indexrelid::regclass AS index, i.indrelid::regclass AS "table", pg_size_pretty(pg_relation_size(i.indexrelid)) AS size
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relname IN (
  'refresh_tokens_user_id_index', 'user_assignment_changes_user_id_inserted_at_index',
  'user_assignment_changes_station_id_index', 'user_assignment_changes_changed_by_id_index',
  'users_station_id_index', 'stations_location_id_index', 'role_permissions_permission_index')
ORDER BY pg_relation_size(i.indexrelid) DESC;

SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
SELECT relname AS "table", reltuples::bigint AS est_rows, pg_size_pretty(pg_relation_size(oid)) AS data, pg_size_pretty(pg_indexes_size(oid)) AS indexes
FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace ORDER BY pg_relation_size(oid) DESC;
