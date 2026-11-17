defmodule Ex.Shipping.Manifest do
  @moduledoc """
  One Manifest per Trip (ADR-0008): the Shipments loaded on one bus departure. The Trip itself lives in the
  external schedule; we keep its id and a snapshot (departure time, bus plate, driver) and record what only
  we know: who opened it, which Shipments were scanned on, and how many have arrived.

  Open at the origin Station, scan Shipments on, depart (every Shipment becomes In transit), then at the
  destination Station scan them off (each becomes Arrived) and close it. Shipments not scanned off stay
  In transit and show in `remaining_count`.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "manifests"
    repo Ex.Repo

    references do
      reference :origin_station, on_delete: :restrict, index?: true
      reference :destination_station, on_delete: :restrict, index?: true
      reference :route, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
    end

    custom_indexes do
      index [:origin_station_id, :status]
      index [:destination_station_id, :status]
    end
  end

  json_api do
    type "manifest"

    includes [:shipments]

    default_fields [
      :external_trip_id,
      :origin_station_id,
      :destination_station_id,
      :route_id,
      :departs_at,
      :bus_label,
      :driver_name,
      :status,
      :departed_at,
      :arrived_at,
      :inserted_at,
      :shipment_count,
      :arrived_count,
      :remaining_count
    ]

    routes do
      base "/manifests"

      route :get, "/departures", :departures_for_route do
        query_params [:destination_station_id, :date]

        description """
        Departures from the external schedule for one `date` (YYYY-MM-DD) from the signed-in user's Station
        to `destination_station_id`. Needs `shipment.mark_in_transit`.
        """
      end

      index :read do
        description "Lists Manifests at the caller's Station (as origin or destination). Needs `shipment.read`."
      end

      get :read

      post :open do
        description """
        Opens the Manifest for a Trip from the schedule (`external_trip_id`) going to `destination_station_id`.
        Opening the same Trip again returns the existing Manifest. Needs `shipment.mark_in_transit`.
        """
      end

      patch :scan do
        route "/:id/scan"

        description """
        Scans one Shipment by `invoice_no`. While the Manifest is open (origin Station) it loads the Shipment;
        once departed (destination Station) it marks the Shipment Arrived. Scanning twice is harmless.
        """
      end

      patch :depart do
        route "/:id/depart"

        description "Departs the Manifest at its origin Station: every loaded Shipment becomes In transit."
      end

      patch :arrive do
        route "/:id/arrive"

        description "Closes the Manifest at its destination Station. Unscanned Shipments stay In transit."
      end
    end
  end

  actions do
    defaults [:read]

    create :open do
      accept [:external_trip_id, :destination_station_id]
      upsert? true
      upsert_identity :one_per_trip
      upsert_fields []
      change Ex.Shipping.Changes.OpenManifest
    end

    update :scan do
      require_atomic? false
      accept []
      argument :invoice_no, :integer, allow_nil?: false
      change Ex.Shipping.Changes.ScanManifest
    end

    update :depart do
      require_atomic? false
      accept []
      change {Ex.Shipping.Changes.MoveManifest, to: :departed}
    end

    update :arrive do
      require_atomic? false
      accept []
      change {Ex.Shipping.Changes.MoveManifest, to: :arrived}
    end

    action :departures_for_route, {:array, :map} do
      argument :destination_station_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, %{actor: actor} ->
        with {:ok, origin} <- Ash.get(Ex.Network.Station, actor.station_id, authorize?: false),
             {:ok, destination} <-
               Ash.get(Ex.Network.Station, input.arguments.destination_station_id,
                 authorize?: false
               ),
             {:ok, trips} <-
               Ex.Schedule.departures(origin.id, destination.id, input.arguments.date) do
          {:ok,
           for t <- trips do
             %{
               trip_id: t.trip_id,
               departs_at: t.departs_at,
               bus_label: t.bus_label,
               departed: t.departed,
               driver_name: t.driver_name
             }
           end}
        else
          _ -> {:error, "could not list departures for that Station and date"}
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)

      authorize_if expr(
                     origin_station_id == ^actor(:station_id) or
                       destination_station_id == ^actor(:station_id)
                   )
    end

    policy action(:open) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.mark_in_transit"}
    end

    policy action(:departures_for_route) do
      forbid_unless actor_present()
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.mark_in_transit"}
    end

    # Scan, depart and arrive check their own permission and Station inside the change, because the right
    # Station depends on the Manifest's status (origin while open, destination once departed).
    policy action([:scan, :depart, :arrive]) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :external_trip_id, :string, allow_nil?: false, public?: true
    attribute :departs_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :bus_label, :string, public?: true
    attribute :driver_name, :string, public?: true

    attribute :status, Ex.Shipping.ManifestStatus,
      allow_nil?: false,
      default: :open,
      writable?: false,
      public?: true

    attribute :departed_at, :utc_datetime_usec, public?: true
    attribute :arrived_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :origin_station, Ex.Network.Station, allow_nil?: false, public?: true
    belongs_to :destination_station, Ex.Network.Station, allow_nil?: false, public?: true
    belongs_to :route, Ex.Network.Route, allow_nil?: false, public?: true
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true

    has_many :shipments, Ex.Shipping.Shipment, public?: true
  end

  calculations do
    calculate :remaining_count, :integer, expr(shipment_count - arrived_count), public?: true
  end

  aggregates do
    count :shipment_count, :shipments, public?: true

    count :arrived_count, :shipments do
      public? true
      filter expr(status in [:arrived, :collected])
    end
  end

  identities do
    identity :one_per_trip, [:external_trip_id, :origin_station_id, :destination_station_id]
  end
end
