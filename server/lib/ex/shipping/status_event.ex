defmodule Ex.Shipping.StatusEvent do
  @moduledoc """
  One step in a Shipment's life (received, in transit, arrived, collected, cancelled).

  Append-only (ADR-0005): there is no update or destroy action and Postgres rejects UPDATE and
  DELETE. `seq` counts 1, 2, 3 per Shipment, so two writers racing for the same step cannot both win.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "status_events"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :seq, "status_events_seq_positive",
        check: "seq > 0",
        message: "must be above 0"

      check_constraint :status, "status_events_status_values",
        check: "status IN ('received','in_transit','arrived','collected','cancelled')",
        message: "unknown status"
    end

    custom_indexes do
      index [:shipment_id, :status],
        unique: true,
        where: "status IN ('received', 'collected', 'cancelled')",
        name: "status_events_once_idx"
    end

    custom_statements do
      statement :append_only do
        up """
        CREATE TRIGGER status_events_append_only
        BEFORE UPDATE OR DELETE ON status_events
        FOR EACH ROW EXECUTE FUNCTION reject_change()
        """

        down "DROP TRIGGER IF EXISTS status_events_append_only ON status_events"
      end

      # Keep shipments.status equal to the newest event, in the same transaction as the insert.
      statement :set_shipment_status_function do
        up """
        CREATE FUNCTION status_events_set_shipment_status() RETURNS trigger AS $$
        BEGIN
          UPDATE shipments SET status = NEW.status WHERE id = NEW.shipment_id;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql
        """

        down "DROP FUNCTION IF EXISTS status_events_set_shipment_status()"
      end

      statement :set_shipment_status do
        up """
        CREATE TRIGGER status_events_set_shipment_status
        AFTER INSERT ON status_events
        FOR EACH ROW EXECUTE FUNCTION status_events_set_shipment_status()
        """

        down "DROP TRIGGER IF EXISTS status_events_set_shipment_status ON status_events"
      end
    end
  end

  json_api do
    type "status-event"

    default_fields [
      :seq,
      :status,
      :status_label_en,
      :status_label_km,
      :station_id,
      :reason,
      :inserted_at
    ]
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:shipment_id, :seq, :status, :station_id, :created_by_id, :reason]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :seq, :integer, allow_nil?: false, public?: true
    attribute :status, Ex.Shipping.Status, allow_nil?: false, public?: true
    attribute :reason, :string, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, allow_nil?: false, public?: true
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true
  end

  calculations do
    calculate :status_label_en,
              :string,
              {Ex.Shipping.Calculations.StatusLabel, language: :en, field: :status}, public?: true

    calculate :status_label_km,
              :string,
              {Ex.Shipping.Calculations.StatusLabel, language: :km, field: :status}, public?: true
  end

  identities do
    identity :unique_seq_per_shipment, [:shipment_id, :seq]
  end
end
