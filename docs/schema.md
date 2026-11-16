# Table design (v1 draft, agreed in grilling)

Money columns use ash_money (KHR). All `inserted_at` are server UTC. Status and balance are derived, never stored. Station latitude/longitude are deferred.

## Reference data
- locations: id, name
- stations: id, location_id, name, active
- routes: id, origin_location_id, destination_location_id (unique pair)
- size_classes: id, name, price, active
- pricing_settings: price_per_kg (single row)
- price_changes: kind (price_per_kg|size_class|sale_item), size_class_id, sale_item_id, price, changed_by, inserted_at (append-only; every price set is a row, current = latest)
