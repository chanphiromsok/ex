defmodule Ex.Accounts.PermissionDefinition do
  @moduledoc "One row per Permission the application can check. Rows come from migrations; a test keeps them equal to `Ex.Accounts.Permission`."
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "permissions"
    repo Ex.Repo
  end

  json_api do
    type "permission"

    routes do
      base "/permissions"
      index :read
    end
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 200,
                 countable: true
    end
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      authorize_if actor_present()
    end
  end

  attributes do
    attribute :name, Ex.Accounts.Permission, primary_key?: true, allow_nil?: false, public?: true
    attribute :station_bound, :boolean, allow_nil?: false, default: false, public?: true
    attribute :description, :string, allow_nil?: false, public?: true
  end
end
