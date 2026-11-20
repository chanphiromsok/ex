defmodule Ex.Accounts.RolePermission do
  @moduledoc "A Default Permission: this role holds this Permission unless a Station rule says otherwise."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :ex,
    domain: Ex.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "role_permissions"
    repo Ex.Repo

    references do
      reference :permission_definition, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :role, "role_values",
        check: "role IN ('staff', 'supervisor', 'admin')",
        message: "unknown role"
    end
  end

  json_api do
    type "role-permission"

    routes do
      base "/role-permissions"

      index :read do
        description "Which role holds which Permission by default. Pair with `/permissions` for what each one means."
        default_fields [:role, :permission]
      end
    end
  end

  actions do
    defaults [:destroy]

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
      accept [:role, :permission]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :destroy]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"user.manage"}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :role, Ex.Accounts.Role, allow_nil?: false, public?: true
    attribute :permission, Ex.Accounts.Permission, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :permission_definition, Ex.Accounts.PermissionDefinition do
      source_attribute :permission
      destination_attribute :name
      attribute_type Ex.Accounts.Permission
      define_attribute? false
    end
  end

  identities do
    identity :unique_role_permission, [:role, :permission]
  end
end
