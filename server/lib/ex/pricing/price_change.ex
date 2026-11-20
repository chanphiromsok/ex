defmodule Ex.Pricing.PriceChange do
  @moduledoc """
  Append-only log of every price set: who set it, when, and for what (ADR-0005).

  Rows are written only by `Ex.Pricing.Changes.LogPrice`, inside the pricing action's transaction.
  """
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "price_changes"
    repo Ex.Repo

    check_constraints do
      check_constraint :kind, "price_changes_kind_matches_foreign_key",
        check:
          "(kind = 'size_class') = (size_class_id IS NOT NULL) AND (kind = 'sale_item') = (sale_item_id IS NOT NULL)",
        message: "the Size Class or Sale Item must match the kind of price"
    end

    references do
      reference :size_class, on_delete: :restrict, index?: true
      reference :sale_item, on_delete: :restrict, index?: true
      reference :changed_by, on_delete: :restrict, index?: true
    end
  end

  json_api do
    type "price-change"

    routes do
      base "/price-changes"

      index :read do
        description "The price history, every price ever set. Needs the `price.manage` permission."
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

    create :record do
      primary? true
      accept [:kind, :price, :size_class_id, :sale_item_id, :changed_by_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"price.manage"}
    end

    # No create policy on purpose: written only by Ex.Pricing.Changes.LogPrice.
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:price_per_kg, :size_class, :sale_item]]

    attribute :price, AshMoney.Types.Money, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :size_class, Ex.Pricing.SizeClass, public?: true
    belongs_to :sale_item, Ex.Pricing.SaleItem, public?: true
    belongs_to :changed_by, Ex.Accounts.User, allow_nil?: false, public?: true
  end
end
