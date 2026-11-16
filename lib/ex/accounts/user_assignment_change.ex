defmodule Ex.Accounts.UserAssignmentChange do
  @moduledoc "Append-only log of a User's role and Station. The current assignment is the latest row."
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "user_assignment_changes"
    repo Ex.Repo

    references do
      reference :user, on_delete: :restrict
      reference :station, on_delete: :restrict
      reference :changed_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:user_id, :role, :station_id, :changed_by_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"user.manage"}
    end

    # No create policy on purpose: rows are written only by
    # Ex.Accounts.User.Changes.RecordAssignment, inside the User action's transaction.
  end

  attributes do
    uuid_primary_key :id
    attribute :role, Ex.Accounts.Role, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Ex.Accounts.User, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, public?: true
    belongs_to :changed_by, Ex.Accounts.User, public?: true
  end
end
