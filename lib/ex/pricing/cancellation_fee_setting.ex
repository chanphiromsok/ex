defmodule Ex.Pricing.CancellationFeeSetting do
  @moduledoc """
  The one global Cancellation Fee rule: a percentage of the Shipment Total, optionally capped.
  Fee = min(Total x percent, cap), rounded half-up to whole riel. Admin-only; every change is logged
  in `Ex.Pricing.SettingChange`.

  There is at most one row (`singleton` has a unique identity), so setting the rule upserts it.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "cancellation_fee_settings"
    repo Ex.Repo

    check_constraints do
      check_constraint :percent, "cancellation_fee_percent_range",
        check: "percent BETWEEN 0 AND 100",
        message: "must be between 0 and 100"

      check_constraint :cap, "cancellation_fee_cap_whole_positive_khr",
        check:
          "cap IS NULL OR ((cap).currency_code = 'KHR' AND (cap).amount > 0 AND (cap).amount = trunc((cap).amount))",
        message: "must be a positive whole number of riel"
    end
  end

  json_api do
    type "cancellation-fee-setting"

    routes do
      base "/pricing/cancellation-fee"

      index :current do
        description "The current Cancellation Fee rule. Any signed-in user."
      end

      post :set do
        description "Sets the Cancellation Fee percent and optional cap, and logs it. Needs `price.manage`."
      end
    end
  end

  actions do
    defaults [:read]

    read :current do
      filter expr(singleton == true)
    end

    create :set do
      accept [:percent, :cap]
      upsert? true
      upsert_identity :only_one
      upsert_fields [:percent, :cap]

      # An omitted cap means "no cap": it must overwrite a cap set earlier, not keep it.
      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :cap,
          Ash.Changeset.get_attribute(changeset, :cap)
        )
      end

      validate {Ex.Pricing.Validations.WholeKhr, attribute: :cap}
      change {Ex.Pricing.Changes.LogSetting, kind: :cancellation_fee}
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action(:set) do
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

    attribute :percent, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 100]

    attribute :cap, AshMoney.Types.Money, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :only_one, [:singleton]
  end
end
