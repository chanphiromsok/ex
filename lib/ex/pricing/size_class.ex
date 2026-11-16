defmodule Ex.Pricing.SizeClass do
  @moduledoc """
  A Size Class: a named parcel size with one global price in KHR (ADR-0003).

  Staff only see active ones; an Admin sees all. Changing a price never affects existing Shipments.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "size_classes"
    repo Ex.Repo

    check_constraints do
      check_constraint :price, "size_classes_price_whole_positive_khr",
        check:
          "(price).currency_code = 'KHR' AND (price).amount > 0 AND (price).amount = trunc((price).amount)",
        message: "must be a positive whole number of riel"
    end
  end

  json_api do
    type "size-class"

    routes do
      base "/size-classes"

      index :read do
        description "Lists Size Classes. Staff see only active ones; an Admin sees all."
      end

      get :read do
        description "Shows one Size Class."
      end

      post :create do
        description "Creates a Size Class with a KHR price. Needs `price.manage`."
      end

      patch :set_price do
        route "/:id/price"
        description "Sets the KHR price of a Size Class and logs it. Needs `price.manage`."
      end

      patch :update do
        description "Renames or (de)activates a Size Class. Needs `price.manage`."
      end
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name_en, :name_km, :price, :active]
      validate {Ex.Pricing.Validations.WholeKhr, attribute: :price}

      change {Ex.Pricing.Changes.LogPrice,
              kind: :size_class, attribute: :price, foreign_key: :size_class_id}
    end

    update :set_price do
      accept [:price]
      require_atomic? false
      validate {Ex.Pricing.Validations.WholeKhr, attribute: :price}

      change {Ex.Pricing.Changes.LogPrice,
              kind: :size_class, attribute: :price, foreign_key: :size_class_id}
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
    attribute :price, AshMoney.Types.Money, allow_nil?: false, public?: true
    attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name_en, [:name_en]
    identity :unique_name_km, [:name_km]
  end
end
