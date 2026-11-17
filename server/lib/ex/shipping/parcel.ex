defmodule Ex.Shipping.Parcel do
  @moduledoc "One item in a Shipment, charged by weight or by Size Class. Created only with its Shipment."
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "parcels"
    repo Ex.Repo
    migration_types weight_kg: {:decimal, 8, 2}

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :size_class, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :measurement_type, "parcels_measurement_chk",
        check:
          "(measurement_type = 'kg' AND weight_kg IS NOT NULL AND size_class_id IS NULL) OR (measurement_type = 'size' AND size_class_id IS NOT NULL AND weight_kg IS NULL)",
        message: "a Parcel is by weight or by Size Class, not both"

      check_constraint :weight_kg, "parcels_weight_positive",
        check: "weight_kg IS NULL OR weight_kg > 0",
        message: "must be above 0"

      check_constraint :chargeable_amount, "parcels_chargeable_amount_whole_positive_khr",
        check:
          "(chargeable_amount).currency_code = 'KHR' AND (chargeable_amount).amount > 0 AND (chargeable_amount).amount = trunc((chargeable_amount).amount)",
        message: "must be a positive whole number of riel"
    end
  end

  json_api do
    type "parcel"
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:shipment_id, :measurement_type, :weight_kg, :size_class_id, :chargeable_amount]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :measurement_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:kg, :size]]

    attribute :weight_kg, :decimal, public?: true
    attribute :chargeable_amount, AshMoney.Types.Money, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :size_class, Ex.Pricing.SizeClass, public?: true
  end
end
