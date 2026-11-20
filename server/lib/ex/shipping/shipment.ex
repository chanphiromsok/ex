defmodule Ex.Shipping.Shipment do
  @moduledoc """
  What a Sender hands over at a Station to be carried to another Station.

  Staff create it with the Parcels and Sale Items and the way the first Payment is made; the server
  decides every price, the Invoice Number and the origin Station. The Shipment Total is a snapshot:
  later price changes never alter it.
  """
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table("shipments")
    repo(Ex.Repo)
    migration_types(invoice_no: :bigserial)

    references do
      reference(:origin_station, on_delete: :restrict, index?: true)
      reference(:destination_station, on_delete: :restrict, index?: true)
      reference(:route, on_delete: :restrict, index?: true)
      reference(:manifest, on_delete: :restrict, index?: true)
      reference(:created_by, on_delete: :restrict, index?: true)
    end

    custom_indexes do
      index([:destination_station_id, :receiver_phone])
      index([:destination_station_id, :status])
      index([:origin_station_id, :status])
    end

    check_constraints do
      check_constraint(:sender_phone, "shipments_sender_phone_format",
        check: "sender_phone ~ '^855[1-9][0-9]{7,8}$'",
        message: "is not a valid Cambodian phone number"
      )

      check_constraint(:receiver_phone, "shipments_receiver_phone_format",
        check: "receiver_phone ~ '^855[1-9][0-9]{7,8}$'",
        message: "is not a valid Cambodian phone number"
      )

      check_constraint(:destination_station_id, "shipments_stations_differ",
        check: "origin_station_id <> destination_station_id",
        message: "must differ from your own Station"
      )

      check_constraint(:shipment_total, "shipments_total_whole_positive_khr",
        check:
          "(shipment_total).currency_code = 'KHR' AND (shipment_total).amount > 0 AND (shipment_total).amount = trunc((shipment_total).amount)",
        message: "must be a positive whole number of riel"
      )

      check_constraint(:declared_value, "shipments_declared_value_whole_khr",
        check:
          "declared_value IS NULL OR ((declared_value).currency_code = 'KHR' AND (declared_value).amount >= 0 AND (declared_value).amount = trunc((declared_value).amount))",
        message: "must be a whole number of riel, 0 or more"
      )
    end
  end

  json_api do
    type("shipment")

    includes([
      :parcels,
      :sale_items,
      :payments,
      :status_events,
      :notes,
      :receiver_corrections,
      :origin_station,
      :destination_station
    ])

    default_fields([
      :invoice_no,
      :origin_station_id,
      :destination_station_id,
      :route_id,
      :manifest_id,
      :sender_name,
      :sender_phone,
      :receiver_name,
      :receiver_phone,
      :current_receiver_name,
      :current_receiver_phone,
      :declared_value,
      :shipment_total,
      :inserted_at,
      :status,
      :status_label_en,
      :status_label_km,
      :status_history
    ])

    routes do
      base("/shipments")

      post :create do
        description("""
        Creates a Shipment at the signed-in user's own Station, with its Parcels, Sale Items and the first
        Payment, in one transaction. Send an `idempotency_key` (a UUID you generate once per attempt):
        repeating the request returns the same Shipment and never makes a second one. Prices, the Invoice
        Number and the origin Station are decided by the server. Needs the `shipment.create` permission.
        Add `?include=parcels,sale_items,payments,status_events` to get the full invoice back.
        """)

        relationship_arguments([])
      end

      get :read do
        description("Shows one Shipment (the invoice). Needs the `shipment.read` permission.")
      end

      index :overdue do
        route("/overdue")

        description(
          "Arrived Shipments waiting longer than their destination Station's Overdue Threshold (days since arrival). Staff and Supervisors see their own Station; an Admin sees all and may pass `destination_station_id`."
        )
      end

      index :list do
        description("""
        Lists Shipments, newest first, 50 per page (`page[limit]` up to 200). Follow `links.next`
        (or pass its `page[after]` cursor) for the next page. Filter with `filter[...]` and narrow with
        `search` (Invoice Number, name or phone). Needs the `shipment.read` permission.
        """)
      end

      patch :mark_in_transit do
        route("/:id/in-transit")

        description("""
        The origin Station hands the Shipment to the bus. Only from Received. Needs `shipment.mark_in_transit`,
        at the Shipment's origin Station.
        """)
      end

      patch :mark_arrived do
        route("/:id/arrived")

        description("""
        The destination Station records that the Shipment arrived. Only from In transit. Needs
        `shipment.mark_arrived`, at the Shipment's destination Station.
        """)
      end

      patch :collect do
        route("/:id/collect")

        description("""
        The destination Station hands the Shipment to the Receiver. Only from Arrived, once, and only when the
        `receiver_phone` given matches the Receiver phone. Needs `shipment.collect`, at the destination Station.
        """)
      end
    end
  end

  actions do
    defaults([:read])

    read :list do
      description("""
      Shipments, newest first, one page at a time. The first request returns the first page;
      `links.next` holds the cursor (`page[after]`) for the next page and is null on the last one.
      `search` matches an Invoice Number (`123` or `#123`), part of a Sender or Receiver name, or
      part of a phone number.
      """)

      argument(:search, :string)

      prepare(build(default_sort: [inserted_at: :desc]))
      prepare(Ex.Shipping.Preparations.SearchShipments)

      pagination(
        keyset?: true,
        offset?: false,
        required?: true,
        default_limit: 50,
        max_page_size: 200,
        countable: true
      )
    end

    read :overdue do
      description("""
      Arrived Shipments that have waited longer than the destination Station's Overdue Threshold (in days),
      counted from the moment they arrived. Station staff and Supervisors see only their own Station;
      an Admin sees every Station and can narrow it with `destination_station_id`.
      """)

      argument(:destination_station_id, :uuid)

      filter(
        expr(
          status == :arrived and
            arrived_at < ago(destination_station.overdue_threshold_days, :day) and
            (is_nil(^arg(:destination_station_id)) or
               destination_station_id == ^arg(:destination_station_id))
        )
      )

      pagination(
        keyset?: true,
        required?: false,
        default_limit: 50,
        max_page_size: 200,
        countable: true
      )
    end

    create :create do
      primary?(true)

      accept([
        :sender_name,
        :sender_phone,
        :receiver_name,
        :receiver_phone,
        :destination_station_id,
        :declared_value,
        :idempotency_key
      ])

      upsert?(true)
      upsert_identity(:unique_idempotency_key)
      upsert_fields([:idempotency_key])

      argument(:payment_method, Ex.Shipping.PaymentMethod, allow_nil?: false)

      argument :parcels, {:array, :map} do
        allow_nil?(false)

        constraints(
          min_length: 1,
          items: [
            fields: [
              measurement_type: [
                type: :atom,
                allow_nil?: false,
                constraints: [one_of: [:kg, :size]]
              ],
              weight_kg: [type: :decimal, allow_nil?: true],
              size_class_id: [type: :uuid, allow_nil?: true]
            ]
          ]
        )
      end

      argument :sale_items, {:array, :map} do
        default([])

        constraints(
          items: [
            fields: [
              sale_item_id: [type: :uuid, allow_nil?: false],
              quantity: [type: :integer, allow_nil?: false]
            ]
          ]
        )
      end

      validate({Ex.Pricing.Validations.WholeKhr, attribute: :declared_value, allow_zero: true})
      change(Ex.Shipping.Changes.NormalizePhones)
      change(Ex.Shipping.Changes.PlaceShipment)
    end

    # Internal: the Manifest scan puts a Shipment on a Manifest or takes it off. Not exposed over the API.
    update :set_manifest do
      require_atomic?(false)
      accept([:manifest_id])
    end

    update :mark_in_transit do
      require_atomic?(false)
      accept([])
      change({Ex.Shipping.Changes.AdvanceStatus, from: :received, to: :in_transit})
    end

    update :mark_arrived do
      require_atomic?(false)
      accept([])
      change({Ex.Shipping.Changes.AdvanceStatus, from: :in_transit, to: :arrived})
    end

    update :collect do
      require_atomic?(false)
      accept([])
      argument(:receiver_phone, :string, allow_nil?: false)
      change(Ex.Shipping.Changes.MatchReceiverPhone)
      change({Ex.Shipping.Changes.AdvanceStatus, from: :arrived, to: :collected})
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if({Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"})
    end

    # A Station sees only Shipments it sends or receives; an Admin has no Station and sees all.
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))

      authorize_if(
        expr(
          origin_station_id == ^actor(:station_id) or
            destination_station_id == ^actor(:station_id)
        )
      )
    end

    # The Overdue list is limited to the caller's own Station; an Admin has no Station and sees all.
    policy action(:overdue) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(expr(destination_station_id == ^actor(:station_id)))
    end

    policy action(:create) do
      authorize_if({Ex.Accounts.Checks.HasPermission, permission: :"shipment.create"})
    end

    # Each rule is its own policy, because Ash needs every policy to pass. Two checks in ONE policy stop at
    # the first that decides, so the Station check would never run after the permission check passed.
    policy action(:mark_in_transit) do
      authorize_if({Ex.Accounts.Checks.HasPermission, permission: :"shipment.mark_in_transit"})
    end

    policy action(:mark_in_transit) do
      authorize_if({Ex.Shipping.Checks.AtStation, side: :origin})
    end

    policy action(:mark_arrived) do
      authorize_if({Ex.Accounts.Checks.HasPermission, permission: :"shipment.mark_arrived"})
    end

    policy action(:mark_arrived) do
      authorize_if({Ex.Shipping.Checks.AtStation, side: :destination})
    end

    policy action(:collect) do
      authorize_if({Ex.Accounts.Checks.HasPermission, permission: :"shipment.collect"})
    end

    policy action(:collect) do
      authorize_if({Ex.Shipping.Checks.AtStation, side: :destination})
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:invoice_no, :integer,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true
    )

    attribute(:idempotency_key, :uuid, allow_nil?: false, public?: true)

    # Copy of the latest Status Event, kept by the `status_events_set_shipment_status` trigger in the same
    # transaction as each event, so lists can filter and index on it. The ledger stays the source of truth.
    attribute(:status, Ex.Shipping.Status,
      allow_nil?: false,
      default: :received,
      writable?: false,
      public?: true
    )

    attribute(:sender_name, :string,
      allow_nil?: true,
      public?: true,
      constraints: [min_length: 1]
    )

    attribute(:sender_phone, :string, allow_nil?: false, public?: true)

    attribute(:receiver_name, :string,
      allow_nil?: true,
      public?: true,
      constraints: [min_length: 1]
    )

    attribute(:receiver_phone, :string, allow_nil?: false, public?: true)
    attribute(:declared_value, AshMoney.Types.Money, public?: true)
    attribute(:shipment_total, AshMoney.Types.Money, allow_nil?: false, public?: true)
    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to(:origin_station, Ex.Network.Station, allow_nil?: false, public?: true)
    belongs_to(:destination_station, Ex.Network.Station, allow_nil?: false, public?: true)
    belongs_to(:route, Ex.Network.Route, allow_nil?: false, public?: true)
    belongs_to(:manifest, Ex.Shipping.Manifest, public?: true)
    belongs_to(:created_by, Ex.Accounts.User, allow_nil?: false, public?: true)

    has_many(:parcels, Ex.Shipping.Parcel, public?: true)
    has_many(:sale_items, Ex.Shipping.ShipmentSaleItem, public?: true)
    has_many(:payments, Ex.Shipping.Payment, public?: true)
    has_many(:status_events, Ex.Shipping.StatusEvent, public?: true, sort: [seq: :asc])
    has_many(:notes, Ex.Shipping.ShipmentNote, public?: true, sort: [inserted_at: :asc])

    has_many(:receiver_corrections, Ex.Shipping.ReceiverCorrection,
      public?: true,
      sort: [inserted_at: :asc]
    )
  end

  calculations do
    # The Receiver is the latest Receiver Correction, or the original Receiver when there is none.
    calculate(:current_receiver_phone, :string, expr(latest_correction_phone || receiver_phone),
      public?: true,
      filterable?: true
    )

    calculate(:current_receiver_name, :string, expr(latest_correction_name || receiver_name),
      public?: true
    )

    calculate(
      :status_label_en,
      :string,
      {Ex.Shipping.Calculations.StatusLabel, language: :en, field: :status}, public?: true)

    calculate(
      :status_label_km,
      :string,
      {Ex.Shipping.Calculations.StatusLabel, language: :km, field: :status}, public?: true)

    calculate(
      :status_history,
      {:array, :map},
      Ex.Shipping.Calculations.StatusHistory, public?: true)
  end

  aggregates do
    first :latest_correction_phone, :receiver_corrections, :phone do
      sort(inserted_at: :desc)
    end

    first :latest_correction_name, :receiver_corrections, :name do
      sort(inserted_at: :desc)
    end

    first :departed_at, :status_events, :inserted_at do
      public?(true)
      filter(expr(status == :in_transit))
    end

    first :arrived_at, :status_events, :inserted_at do
      public?(true)
      filter(expr(status == :arrived))
    end
  end

  identities do
    identity(:unique_idempotency_key, [:idempotency_key])
    identity(:unique_invoice_no, [:invoice_no])
  end
end
