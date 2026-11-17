defmodule Ex.Network.Route do
  @moduledoc """
  A Route: the ordered origin Location to destination Location pair a Shipment travels on.

  A Route owns no price. An Admin creates the Routes the company runs; a Shipment can only be made
  between Stations whose Locations form an existing Route. Phnom Penh to Siem Reap does not imply
  Siem Reap to Phnom Penh: each direction is its own Route.
  """

  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "routes"
    repo Ex.Repo

    references do
      reference :origin_location, on_delete: :restrict, index?: true
      reference :destination_location, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :destination_location_id, "routes_locations_differ",
        check: "origin_location_id <> destination_location_id",
        message: "a Route must connect two different Locations"
    end
  end

  json_api do
    type "route"

    routes do
      base "/routes"

      index :read do
        description "Lists Routes (origin Location to destination Location). Any signed-in user."
      end

      get :read do
        description "Shows one Route. Any signed-in user."
      end

      post :create do
        description "Creates a Route between two different Locations. Needs the `reference_data.manage` permission."
      end

      delete :destroy do
        description "Deletes a Route no Shipment has used. Needs the `reference_data.manage` permission."
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:origin_location_id, :destination_location_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :destroy]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"reference_data.manage"}
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :origin_location, Ex.Network.Location, allow_nil?: false, public?: true
    belongs_to :destination_location, Ex.Network.Location, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_origin_destination, [:origin_location_id, :destination_location_id],
      message: "this Route already exists"
  end
end
