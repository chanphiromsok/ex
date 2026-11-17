-- Express cargo v1 table design (PREVIEW ONLY, not a migration).
-- Shaped the way `mix ash.codegen` would emit it from Ash resources (see docs/schema.md):
--   uuid pks via gen_random_uuid(), enums as text (Ash.Type.Enum), *_id foreign keys,
--   timestamp(6) UTC columns, bigserial for generated integers, ash_money composite type.
-- Self-contained: defines a stand-in for ash_money's money_with_currency type.

BEGIN;

CREATE EXTENSION IF NOT EXISTS citext;

DO $$ BEGIN
  CREATE TYPE money_with_currency AS (currency_code varchar, amount numeric);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- Enum values are plain text in Ash; the allowed values are also enforced by CHECKs
-- (declared with check_constraints in the resources):
--   users.role: staff|supervisor|admin       measurement_type: kg|size
--   status_events.status: received|in_transit|arrived|collected|cancelled
--   incidents.type: return_to_sender|redirect|lost|damaged     payments.kind: payment|refund
--   payments.method: cash|bank_transfer|qr

-- KHR only, whole riel (no decimals). Used by CHECKs on every money column.
CREATE FUNCTION is_whole_khr(m money_with_currency) RETURNS boolean
  LANGUAGE sql IMMUTABLE AS
$$ SELECT m IS NULL OR ((m).currency_code = 'KHR' AND (m).amount = trunc((m).amount)) $$;

-- Reference data ---------------------------------------------------------
CREATE TABLE locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en text NOT NULL UNIQUE,
  name_km text NOT NULL UNIQUE
);

CREATE TABLE stations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id uuid NOT NULL REFERENCES locations,
  name_en text NOT NULL,
  name_km text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (location_id, name_en),
  UNIQUE (location_id, name_km)
);

CREATE TABLE routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_location_id uuid NOT NULL REFERENCES locations,
  destination_location_id uuid NOT NULL REFERENCES locations,
  UNIQUE (origin_location_id, destination_location_id),
  CHECK (origin_location_id <> destination_location_id)
);

CREATE TABLE size_classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en text NOT NULL UNIQUE,
  name_km text NOT NULL UNIQUE,
  price money_with_currency NOT NULL CHECK (is_whole_khr(price) AND (price).amount > 0),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en text NOT NULL UNIQUE,
  name_km text NOT NULL UNIQUE,
  unit_price money_with_currency NOT NULL CHECK (is_whole_khr(unit_price) AND (unit_price).amount > 0),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE pricing_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton boolean NOT NULL DEFAULT true UNIQUE CHECK (singleton),  -- single row (identity on a constant)
  price_per_kg money_with_currency NOT NULL CHECK (is_whole_khr(price_per_kg) AND (price_per_kg).amount > 0),
  -- Cancellation fee kept on refund = min(round(Shipment Total * percent / 100), cap)
  cancellation_fee_percent integer NOT NULL DEFAULT 0 CHECK (cancellation_fee_percent BETWEEN 0 AND 100),
  cancellation_fee_cap money_with_currency NOT NULL CHECK (is_whole_khr(cancellation_fee_cap) AND (cancellation_fee_cap).amount >= 0)
);

CREATE TABLE station_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id uuid NOT NULL UNIQUE REFERENCES stations,
  cancel_requires_approval boolean NOT NULL DEFAULT true,
  overdue_threshold_days integer NOT NULL CHECK (overdue_threshold_days > 0)
);

-- Users ------------------------------------------------------------------
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  hashed_password text NOT NULL,
  confirmed_at timestamp(6),
  role text NOT NULL CHECK (role IN ('staff','supervisor','admin')),
  station_id uuid REFERENCES stations,
  CHECK ((role = 'admin' AND station_id IS NULL) OR (role <> 'admin' AND station_id IS NOT NULL))
);

-- Shipments --------------------------------------------------------------
CREATE TABLE shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_no bigserial NOT NULL UNIQUE,         -- own generator (Ash: integer, generated? true, writable? false)
  idempotency_key uuid NOT NULL UNIQUE,         -- client-generated; a double submit cannot create two Shipments
  origin_station_id uuid NOT NULL REFERENCES stations,
  destination_station_id uuid NOT NULL REFERENCES stations,
  route_id uuid NOT NULL REFERENCES routes,
  sender_name text,
  sender_phone text NOT NULL CHECK (sender_phone ~ '^855[1-9][0-9]{7,8}$'),  -- normalised by one shared function
  receiver_name text,
  receiver_phone text NOT NULL CHECK (receiver_phone ~ '^855[1-9][0-9]{7,8}$'),  -- normalised digits + country code
  declared_value money_with_currency CHECK (is_whole_khr(declared_value) AND (declared_value).amount >= 0),
  shipment_total money_with_currency NOT NULL CHECK (is_whole_khr(shipment_total) AND (shipment_total).amount > 0),
  created_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  CHECK (origin_station_id <> destination_station_id)
);
CREATE INDEX shipments_destination_receiver_idx ON shipments (destination_station_id, receiver_phone);

CREATE TABLE parcels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  measurement_type text NOT NULL CHECK (measurement_type IN ('kg','size')),
  weight_kg numeric(8,2) CHECK (weight_kg > 0),
  size_class_id uuid REFERENCES size_classes,
  chargeable_amount money_with_currency NOT NULL CHECK (is_whole_khr(chargeable_amount) AND (chargeable_amount).amount > 0)
);
-- measurement_type = 'kg' requires weight_kg; 'size' requires size_class_id
ALTER TABLE parcels ADD CONSTRAINT parcels_measurement_chk CHECK (
  (measurement_type = 'kg' AND weight_kg IS NOT NULL AND size_class_id IS NULL) OR
  (measurement_type = 'size' AND size_class_id IS NOT NULL AND weight_kg IS NULL));

CREATE TABLE shipment_sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  sale_item_id uuid NOT NULL REFERENCES sale_items,
  quantity integer NOT NULL CHECK (quantity > 0),
  unit_price money_with_currency NOT NULL CHECK (is_whole_khr(unit_price) AND (unit_price).amount > 0)  -- snapshot
);

-- Append-only ------------------------------------------------------------
CREATE TABLE status_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  seq integer NOT NULL CHECK (seq > 0),          -- 1, 2, 3 ... per Shipment; a second writer with the same seq fails
  status text NOT NULL CHECK (status IN ('received','in_transit','arrived','collected','cancelled')),
  station_id uuid NOT NULL REFERENCES stations,  -- Station where it happened
  created_by_id uuid NOT NULL REFERENCES users,
  reason text,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  UNIQUE (shipment_id, seq)
);
-- received, collected and cancelled can each happen only once per Shipment
CREATE UNIQUE INDEX status_events_once_idx ON status_events (shipment_id, status)
  WHERE status IN ('received', 'collected', 'cancelled');
CREATE INDEX status_events_cancelled_idx ON status_events (created_by_id, inserted_at) WHERE status = 'cancelled';
CREATE INDEX status_events_status_idx ON status_events (status, inserted_at);

CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  kind text NOT NULL DEFAULT 'payment' CHECK (kind IN ('payment','refund')),
  method text NOT NULL CHECK (method IN ('cash','bank_transfer','qr')),
  amount money_with_currency NOT NULL CHECK (is_whole_khr(amount)),  -- refund = negative
  cancellation_event_id uuid REFERENCES status_events,  -- the cancelled event a refund belongs to
  station_id uuid NOT NULL REFERENCES stations,
  created_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  CHECK ((kind = 'payment' AND (amount).amount > 0 AND cancellation_event_id IS NULL) OR
         (kind = 'refund'  AND (amount).amount < 0 AND cancellation_event_id IS NOT NULL))
);
CREATE UNIQUE INDEX payments_one_refund_idx ON payments (shipment_id) WHERE kind = 'refund';
CREATE INDEX payments_station_time_idx ON payments (station_id, inserted_at);
CREATE INDEX payments_staff_time_idx ON payments (created_by_id, inserted_at);

CREATE TABLE notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  station_id uuid NOT NULL REFERENCES stations,
  text text NOT NULL,
  created_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE TABLE receiver_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  receiver_name text NOT NULL,
  receiver_phone text NOT NULL CHECK (receiver_phone ~ '^855[1-9][0-9]{7,8}$'),
  reason text NOT NULL,
  station_id uuid NOT NULL REFERENCES stations,  -- origin Station; only its Supervisor may add one
  created_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);  -- the Receiver of a Shipment is its latest correction, else the original

CREATE TABLE price_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('price_per_kg', 'size_class', 'sale_item', 'cancellation_fee')),
  size_class_id uuid REFERENCES size_classes,
  sale_item_id uuid REFERENCES sale_items,
  price money_with_currency NOT NULL,           -- price set by this change (cap for cancellation_fee)
  percent integer CHECK (percent BETWEEN 0 AND 100),  -- only for cancellation_fee
  changed_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  CHECK ((kind = 'size_class') = (size_class_id IS NOT NULL)),
  CHECK ((kind = 'sale_item') = (sale_item_id IS NOT NULL)),
  CHECK ((kind = 'cancellation_fee') = (percent IS NOT NULL))
);

CREATE TABLE station_setting_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id uuid NOT NULL REFERENCES stations,
  field text NOT NULL,
  value text NOT NULL,                          -- value set by this change
  changed_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE TABLE user_assignment_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users,
  role text NOT NULL CHECK (role IN ('staff','supervisor','admin')),
  station_id uuid REFERENCES stations,
  changed_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- Permissions (data, editable by an Admin; see docs/adr/0006) --------------
-- Names are also an Ash enum in code (policies name them); rows come from migrations,
-- and a test checks the two lists match.
CREATE TABLE permissions (
  name text PRIMARY KEY,                        -- 'shipment.create', 'cancellation.approve', ...
  station_bound boolean NOT NULL,               -- acts on a Shipment/Payment/Cancellation at a Station; never effective for an Admin
  description text NOT NULL
);

-- Default Permissions of a role. Roles stay an enum on users.
CREATE TABLE role_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text NOT NULL CHECK (role IN ('staff','supervisor','admin')),
  permission text NOT NULL REFERENCES permissions,
  UNIQUE (role, permission)
);

-- Per-user override. No row = the role default applies. Delete the row to reset.
CREATE TABLE user_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users,
  permission text NOT NULL REFERENCES permissions,
  granted boolean NOT NULL,                     -- true = grant, false = deny (deny beats the role default)
  UNIQUE (user_id, permission)
);

-- Effective permission = COALESCE(user override, role default), minus station_bound ones for users with no Station.
-- Computed in one SQL calculation on User and loaded onto the actor (see docs/schema.md).

-- One append-only log for both tables above, written in the same transaction as the change.
CREATE TABLE permission_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text CHECK (role IN ('staff','supervisor','admin')),
  user_id uuid REFERENCES users,
  permission text NOT NULL REFERENCES permissions,
  effect text NOT NULL CHECK (effect IN ('grant','deny','clear')),  -- clear = row removed (role default again / default removed)
  changed_by_id uuid NOT NULL REFERENCES users,
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  CHECK (num_nonnulls(role, user_id) = 1)       -- a role change or a user change, never both
);
CREATE INDEX permission_changes_user_idx ON permission_changes (user_id, inserted_at DESC);

-- Resolvable -------------------------------------------------------------
CREATE TABLE incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  type text NOT NULL CHECK (type IN ('return_to_sender','redirect','lost','damaged')),
  reason text NOT NULL,
  created_by_id uuid NOT NULL REFERENCES users,
  resolved_by_id uuid REFERENCES users,
  resolved_at timestamp(6),
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE TABLE cancellation_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES shipments,
  requested_by_id uuid NOT NULL REFERENCES users,
  approved_by_id uuid REFERENCES users,
  decided_at timestamp(6),
  inserted_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  CHECK (approved_by_id IS NULL OR approved_by_id <> requested_by_id)
);

-- Append-only enforcement (ADR-0005) -------------------------------------
CREATE FUNCTION reject_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION '% cannot be changed or deleted', TG_TABLE_NAME; END $$;

CREATE TRIGGER payments_append_only BEFORE UPDATE OR DELETE ON payments
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER status_events_append_only BEFORE UPDATE OR DELETE ON status_events
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER notes_append_only BEFORE UPDATE OR DELETE ON notes
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER receiver_corrections_append_only BEFORE UPDATE OR DELETE ON receiver_corrections
  FOR EACH ROW EXECUTE FUNCTION reject_change();
-- Shipment, Parcels and Sale Item lines are written once, in the create transaction
CREATE TRIGGER shipments_immutable BEFORE UPDATE OR DELETE ON shipments
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER parcels_immutable BEFORE UPDATE OR DELETE ON parcels
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER shipment_sale_items_immutable BEFORE UPDATE OR DELETE ON shipment_sale_items
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER price_changes_append_only BEFORE UPDATE OR DELETE ON price_changes
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER station_setting_changes_append_only BEFORE UPDATE OR DELETE ON station_setting_changes
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER permission_changes_append_only BEFORE UPDATE OR DELETE ON permission_changes
  FOR EACH ROW EXECUTE FUNCTION reject_change();
CREATE TRIGGER user_assignment_changes_append_only BEFORE UPDATE OR DELETE ON user_assignment_changes
  FOR EACH ROW EXECUTE FUNCTION reject_change();

COMMIT;
