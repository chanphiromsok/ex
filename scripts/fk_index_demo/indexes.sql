-- The 7 indexes the pgbot finding `fk_unindexed` asks for.
-- On a big live table use CREATE INDEX CONCURRENTLY (not allowed inside a transaction block).
CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_index ON refresh_tokens (user_id);
CREATE INDEX IF NOT EXISTS user_assignment_changes_user_id_inserted_at_index ON user_assignment_changes (user_id, inserted_at);
CREATE INDEX IF NOT EXISTS user_assignment_changes_station_id_index ON user_assignment_changes (station_id);
CREATE INDEX IF NOT EXISTS user_assignment_changes_changed_by_id_index ON user_assignment_changes (changed_by_id);
CREATE INDEX IF NOT EXISTS users_station_id_index ON users (station_id);
CREATE INDEX IF NOT EXISTS stations_location_id_index ON stations (location_id);
CREATE INDEX IF NOT EXISTS role_permissions_permission_index ON role_permissions (permission);
ANALYZE;
