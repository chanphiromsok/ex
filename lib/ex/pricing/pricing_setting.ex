defmodule Ex.Pricing.PricingSetting do
  @moduledoc """
  The one global pricing row: today only the price per kg (cancellation fee settings arrive with ticket #8).

  There is at most one row: `singleton` is a constant with a unique identity, so setting the price upserts it.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "pricing_settings"
    repo Ex.Repo
  end

  json_api do
    type "pricing-setting"

    routes do
      base "/pricing"

      get :current do
        route "/current"
        description "The current global pricing (price per kg). Any signed-in user."
      end

      post :set_price_per_kg do
        route "/price-per-kg"

        description "Sets the global price per kg in KHR and logs it. Needs the `price.manage` permission."
      end
    end
  end

  actions do
    defaults [:read]

    read :current do
      get? true
      filter expr(singleton == true)
    end

    create :set_price_per_kg do
      accept [:price_per_kg]
      upsert? true
      upsert_identity :only_one
      upsert_fields [:price_per_kg]
      validate {Ex.Pricing.Validations.WholeKhr, attribute: :price_per_kg}
      change {Ex.Pricing.Changes.LogPrice, kind: :price_per_kg, attribute: :price_per_kg}
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action(:set_price_per_kg) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"price.manage"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :singleton, :boolean,
      allow_nil?: false,
      default: true,
      writable?: false,
      public?: false

    attribute :price_per_kg, AshMoney.Types.Money, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :only_one, [:singleton]
  end
end
