defmodule Ex.Pricing.SettingChange do
  @moduledoc """
  The log of every Cancellation Fee rule and Station approval setting ever set. Append-only (ADR-0005):
  no update or destroy action, and Postgres rejects UPDATE and DELETE.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "setting_changes"
    repo Ex.Repo

    references do
      reference :station, on_delete: :restrict, index?: true
      reference :changed_by, on_delete: :restrict, index?: true
    end

    custom_statements do
      statement :append_only do
        up """
        CREATE TRIGGER setting_changes_append_only
        BEFORE UPDATE OR DELETE ON setting_changes
        FOR EACH ROW EXECUTE FUNCTION reject_change()
        """

        down "DROP TRIGGER IF EXISTS setting_changes_append_only ON setting_changes"
      end
    end
  end

  json_api do
    type "setting-change"

    routes do
      base "/setting-changes"

      index :read do
        description "The log of Cancellation Fee and Station approval settings, newest first. Needs `price.manage`."

        default_fields [
          :kind,
          :station_id,
          :percent,
          :cap,
          :requires_approval,
          :changed_by_id,
          :inserted_at
        ]
      end
    end
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, default_limit: 50, max_page_size: 200, required?: false
    end

    create :record do
      primary? true
      accept [:kind, :station_id, :percent, :cap, :requires_approval, :changed_by_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"price.manage"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:cancellation_fee, :station_cancellation_approval]]

    attribute :percent, :integer, public?: true
    attribute :cap, AshMoney.Types.Money, public?: true
    attribute :requires_approval, :boolean, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :station, Ex.Network.Station, public?: true
    belongs_to :changed_by, Ex.Accounts.User, allow_nil?: false, public?: true
  end
end
