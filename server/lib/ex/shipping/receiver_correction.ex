defmodule Ex.Shipping.ReceiverCorrection do
  @moduledoc """
  A change of who receives the Shipment (name and phone), with the reason. Append-only: the latest row is
  the Receiver (see Shipment `current_receiver_phone`), older rows stay as history.
  Only a Supervisor at the origin Station can add one, and only after departure and before Collection.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "receiver_corrections"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :phone, "receiver_corrections_phone_format",
        check: "phone ~ '^855[1-9][0-9]{7,8}$'",
        message: "must be a Cambodian phone number"
    end

    custom_statements do
      statement :append_only do
        up """
        CREATE TRIGGER receiver_corrections_append_only
        BEFORE UPDATE OR DELETE ON receiver_corrections
        FOR EACH ROW EXECUTE FUNCTION reject_change()
        """

        down "DROP TRIGGER IF EXISTS receiver_corrections_append_only ON receiver_corrections"
      end
    end
  end

  json_api do
    type "receiver-correction"

    routes do
      base "/receiver-corrections"

      post :correct do
        description """
        Changes the Receiver name and phone after departure, with a reason. Needs `receiver.correct`
        (Supervisor), at the Shipment's origin Station. Only while the Shipment is In transit or Arrived.
        The latest correction is the Receiver; earlier ones stay as history.
        """
      end

      index :read
    end
  end

  actions do
    defaults [:read]

    create :correct do
      primary? true
      accept [:shipment_id, :name, :phone, :reason]
      change {Ex.Shipping.Changes.NormalizePhones, fields: [:phone]}
      change {Ex.Shipping.Changes.RequireStatus, statuses: [:in_transit, :arrived]}
      change Ex.Shipping.Changes.StampActor
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end

    policy action(:correct) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"receiver.correct"}
    end

    policy action(:correct) do
      authorize_if {Ex.Shipping.Checks.AtShipmentStation, side: :origin}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 120]

    attribute :phone, :string, allow_nil?: false, public?: true

    attribute :reason, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 500]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, allow_nil?: false
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true
  end
end
