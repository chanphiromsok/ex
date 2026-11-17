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

    foreign_key_names [
      {:id, "users_station_id_fkey", "still has staff assigned"},
      {:id, "user_assignment_changes_station_id_fkey", "appears in assignment history"}
    ]

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

      get :read do
        description "Shows one Station. Any signed-in user."
      end

      post :create do
        description "Creates a Station in a Location. Needs the `reference_data.manage` permission."
      end

      patch :update do
        description "Renames or (de)activates a Station (it cannot move to another Location). Needs the `reference_data.manage` permission."
      end

      patch :set_cancellation_approval do
        route "/:id/cancellation-approval"

        description """
        Sets whether cancelling a Shipment sent from this Station needs a Supervisor's approval, and logs it.
        Needs the `station_setting.manage` permission (Admin).
        """
      end

      patch :set_overdue_threshold do
        route "/:id/overdue-threshold"

        description "Sets how many hours after departure a Shipment is Overdue at this destination Station, and logs it. Needs `station_setting.manage`."
      end

      delete :destroy do
        description "Deletes a Station nothing refers to. Needs the `reference_data.manage` permission."
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name_en, :name_km, :location_id, :external_id]
    end

    update :update do
      primary? true
      accept [:name_en, :name_km, :active, :external_id]
    end

    update :set_cancellation_approval do
      require_atomic? false
      accept [:cancellation_requires_approval]
      change {Ex.Pricing.Changes.LogSetting, kind: :station_cancellation_approval}
    end

    update :set_overdue_threshold do
      require_atomic? false
      accept [:overdue_threshold_days]
      change {Ex.Pricing.Changes.LogSetting, kind: :station_overdue_threshold}
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action([:set_cancellation_approval, :set_overdue_threshold]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"station_setting.manage"}
    end

    policy action([:create, :update, :destroy]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"reference_data.manage"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name_en, :string, allow_nil?: false, public?: true
    attribute :name_km, :string, allow_nil?: false, public?: true

    attribute :overdue_threshold_days, :integer,
      allow_nil?: false,
      default: 2,
      public?: true,
      constraints: [min: 1, max: 90]

    # This Station's id in the external schedule service; null until an admin sets it.
    attribute :external_id, :string, public?: true

    attribute :active, :boolean, allow_nil?: false, default: true, public?: true

    attribute :cancellation_requires_approval, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :location, Ex.Network.Location, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_external_id, [:external_id]
    identity :unique_name_en_per_location, [:location_id, :name_en]
    identity :unique_name_km_per_location, [:location_id, :name_km]
  end
end
