defmodule Ex.Shipping.ShipmentSaleItem do
  @moduledoc "A Sale Item sold with a Shipment (for example tape), with its unit price as it was at the time."
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "shipment_sale_items"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :sale_item, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :quantity, "shipment_sale_items_quantity_positive",
        check: "quantity > 0",
        message: "must be above 0"

      check_constraint :unit_price, "shipment_sale_items_unit_price_whole_positive_khr",
        check:
          "(unit_price).currency_code = 'KHR' AND (unit_price).amount > 0 AND (unit_price).amount = trunc((unit_price).amount)",
        message: "must be a positive whole number of riel"
    end
  end

  json_api do
    type "shipment-sale-item"
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:shipment_id, :sale_item_id, :quantity, :unit_price]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, allow_nil?: false, public?: true
    attribute :unit_price, AshMoney.Types.Money, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :sale_item, Ex.Pricing.SaleItem, allow_nil?: false, public?: true
  end
end
