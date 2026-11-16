# Table design (v1 draft, agreed in grilling)

Money columns use ash_money (KHR). All `inserted_at` are server UTC. Status and balance are derived, never stored. Station latitude/longitude are deferred.

## Reference data
- locations: id, name
- stations: id, location_id, name, active
- routes: id, origin_location_id, destination_location_id (unique pair)
- size_classes: id, name, active
- sale_items: id, name, unit_price, active
- price_list_versions: id, effective_from
- price_list_weight_rates: id, version_id, route_id, price_per_kg
- price_list_size_rates: id, version_id, route_id, size_class_id, price
- station_settings: station_id (unique), cancel_requires_approval, overdue_threshold_days
- station_setting_changes (append-only): station_id, field, value, changed_by, inserted_at (current value = latest row per field; first row written when the Station is created)

## Users
- users: + role (staff|supervisor|admin), station_id (required for staff/supervisor, null for admin)
- user_assignment_changes (append-only): user_id, role, station_id, changed_by, inserted_at (current = latest row per user)

## Shipments
- shipments: id, waybill (unique), origin_station_id, destination_station_id, route_id, price_list_version_id, sender_name, sender_phone, receiver_name, receiver_phone (normalised digits with country code, indexed), declared_value, collection_code_hash, shipment_total, created_by, inserted_at
- parcels: id, shipment_id, weight_kg, size_class_id, length_cm, width_cm, height_cm, chargeable_amount
- shipment_sale_items: id, shipment_id, sale_item_id, quantity, unit_price (snapshot)

## Append-only
- payments: shipment_id, method, payer, amount (negative = refund), station_id, created_by
- status_events: shipment_id, status, station_id, created_by, reason, collector_name, collector_id_number
- notes: shipment_id, station_id, text, created_by

## Resolvable
- incidents: shipment_id, type, reason, created_by, resolved_by, resolved_at
- fraud_flags: shipment_id, kind, resolved_by, resolved_at
- cancellation_requests: shipment_id, requested_by, approved_by, decided_at

## Other
- waybill_counters: date, last_seq
