defmodule Ex.Pricing.SaleItem do
  @moduledoc """
  A Sale Item: something extra sold with a Shipment (e.g. a box or tape), with one global unit price in KHR.

  Staff only see active ones; an Admin sees all. Changing a price never affects existing Shipments.
  """
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "sale_items"
    repo Ex.Repo

    check_constraints do
      check_constraint :unit_price, "sale_items_unit_price_whole_positive_khr",
        check:
          "(unit_price).currency_code = 'KHR' AND (unit_price).amount > 0 AND (unit_price).amount = trunc((unit_price).amount)",
        message: "must be a positive whole number of riel"
    end
  end

  json_api do
    type "sale-item"

    routes do
      base "/sale-items"

      index :read do
        description "Lists Sale Items. Staff see only active ones; an Admin sees all."
      end

      get :read do
        description "Shows one Sale Item."
      end

      post :create do
        description "Creates a Sale Item with a KHR unit price. Needs `price.manage`."
      end

      patch :set_price do
        route "/:id/price"
        description "Sets the KHR price of a Sale Item and logs it. Needs `price.manage`."
      end

      patch :update do
        description "Renames or (de)activates a Sale Item. Needs `price.manage`."
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

    create :create do
      primary? true
      accept [:name_en, :name_km, :unit_price, :active]
      validate {Ex.Pricing.Validations.WholeKhr, attribute: :unit_price}

      change {Ex.Pricing.Changes.LogPrice,
              kind: :sale_item, attribute: :unit_price, foreign_key: :sale_item_id}
    end

    update :set_price do
      accept [:unit_price]
      require_atomic? false
      validate {Ex.Pricing.Validations.WholeKhr, attribute: :unit_price}

      change {Ex.Pricing.Changes.LogPrice,
              kind: :sale_item, attribute: :unit_price, foreign_key: :sale_item_id}
    end

    update :update do
      primary? true
      accept [:name_en, :name_km, :active]
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless actor_present()
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"price.manage"}
      authorize_if expr(active == true)
    end

    policy action([:create, :update, :set_price]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"price.manage"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name_en, :string, allow_nil?: false, public?: true
    attribute :name_km, :string, allow_nil?: false, public?: true
    attribute :unit_price, AshMoney.Types.Money, allow_nil?: false, public?: true
    attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name_en, [:name_en]
    identity :unique_name_km, [:name_km]
  end
end
