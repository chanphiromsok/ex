defmodule Ex.Network.Station do
  @moduledoc """
  A Station: a physical office in a Location where Station Staff receive and hand over Shipments.
  """

  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "stations"
    repo Ex.Repo

    references do
      reference :location, on_delete: :restrict, index?: true
    end
  end

  json_api do
    type "station"

    routes do
      base "/stations"

      index :read do
        description "Lists Stations with the Location each is in. Any signed-in user."
      end

      post :create do
        description "Creates a Station in a Location. Needs the `reference_data.manage` permission."
      end
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name_en, :name_km, :location_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"reference_data.manage"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name_en, :string, allow_nil?: false, public?: true
    attribute :name_km, :string, allow_nil?: false, public?: true
    attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :location, Ex.Network.Location, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_name_en, [:name_en]
    identity :unique_name_km, [:name_km]
  end
end
