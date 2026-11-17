defmodule Ex.Shipping.ShipmentNote do
  @moduledoc """
  A Note a Station adds to a Shipment (for example "box damaged on arrival"). Append-only: never edited or
  deleted. The destination Station adds Notes once the Shipment is on its way; Notes cannot change weight,
  size, price or phones.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "shipment_notes"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
    end

    custom_statements do
      statement :append_only do
        up """
        CREATE TRIGGER shipment_notes_append_only
        BEFORE UPDATE OR DELETE ON shipment_notes
        FOR EACH ROW EXECUTE FUNCTION reject_change()
        """

        down "DROP TRIGGER IF EXISTS shipment_notes_append_only ON shipment_notes"
      end
    end
  end

  json_api do
    type "shipment-note"

    routes do
      base "/shipment-notes"

      post :add do
        description """
        Adds a Note to a Shipment that is In transit or Arrived. Needs `shipment.add_note`, at the Shipment's
        destination Station. Notes are never edited or deleted.
        """
      end

      index :read
    end
  end

  actions do
    defaults [:read]

    create :add do
      primary? true
      accept [:shipment_id, :body]
      change {Ex.Shipping.Changes.RequireStatus, statuses: [:in_transit, :arrived]}
      change Ex.Shipping.Changes.StampActor
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end

    policy action(:add) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.add_note"}
    end

    policy action(:add) do
      authorize_if {Ex.Shipping.Checks.AtShipmentStation, side: :destination}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 1000]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, allow_nil?: false
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true
  end
end
