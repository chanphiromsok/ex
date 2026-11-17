defmodule Ex.Network.Location do
  @moduledoc """
  A Location: a city or province a Station is in. Reference data, edited by users with `reference_data.manage`.
  """

  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "locations"
    repo Ex.Repo

    foreign_key_names [
      {:id, "stations_location_id_fkey", "is still used by a Station"},
      {:id, "routes_origin_location_id_fkey", "is still used by a Route"},
      {:id, "routes_destination_location_id_fkey", "is still used by a Route"}
    ]
  end

  json_api do
    type "location"

    routes do
      base "/locations"

      index :read do
        description "Lists Locations (cities and provinces). Any signed-in user."
      end

      get :read do
        description "Shows one Location. Any signed-in user."
      end

      post :create do
        description "Creates a Location. Needs the `reference_data.manage` permission."
      end

      patch :update do
        description "Renames a Location. Needs the `reference_data.manage` permission."
      end

      delete :destroy do
        description "Deletes a Location with no Stations. Needs the `reference_data.manage` permission."
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name_en, :name_km]
    end

    update :update do
      primary? true
      accept [:name_en, :name_km]
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
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name_en, [:name_en]
    identity :unique_name_km, [:name_km]
  end
end
