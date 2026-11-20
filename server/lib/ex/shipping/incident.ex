defmodule Ex.Shipping.Incident do
  @moduledoc """
  Something went wrong with a Shipment after it left the origin Station: lost, damaged, to be returned to
  the sender, or to be redirected. Reported by staff at either Station; resolved by a Supervisor or Admin.
  """
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "incidents"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
      reference :resolved_by, on_delete: :restrict, index?: true
    end
  end

  json_api do
    type "incident"

    routes do
      base "/incidents"

      index :read
      post :report

      patch :resolve do
        route "/:id/resolve"
      end
    end
  end

  actions do
    read :read do
      primary? true
      prepare build(default_sort: [inserted_at: :desc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 200,
                 countable: true
    end

    create :report do
      primary? true
      accept [:shipment_id, :kind, :note]
      change {Ex.Shipping.Changes.RequireStatus, statuses: [:in_transit, :arrived]}
      change Ex.Shipping.Changes.StampActor
    end

    update :resolve do
      require_atomic? false
      accept [:resolution]
      validate present(:resolution)
      validate attribute_equals(:status, :open), message: "is already resolved"
      change set_attribute(:status, :resolved)
      change set_attribute(:resolved_at, &DateTime.utc_now/0)
      change relate_actor(:resolved_by)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end

    policy action(:report) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"incident.report"}
    end

    policy action(:report) do
      authorize_if {Ex.Shipping.Checks.AtShipmentStation, side: :either}
    end

    policy action(:resolve) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"incident.resolve"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:return_to_sender, :redirect, :lost, :damaged]]

    attribute :note, :string, public?: true, constraints: [max_length: 1000]

    attribute :status, :atom,
      allow_nil?: false,
      default: :open,
      writable?: false,
      public?: true,
      constraints: [one_of: [:open, :resolved]]

    attribute :resolution, :string, public?: true, constraints: [max_length: 1000]
    attribute :resolved_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, allow_nil?: false
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true
    belongs_to :resolved_by, Ex.Accounts.User
  end
end
