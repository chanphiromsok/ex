-- Back to the "before" state: no FK indexes.
DROP INDEX IF EXISTS
  refresh_tokens_user_id_index,
  user_assignment_changes_user_id_inserted_at_index,
  user_assignment_changes_station_id_index,
  user_assignment_changes_changed_by_id_index,
  users_station_id_index,
  stations_location_id_index,
  role_permissions_permission_index;
ANALYZE;
