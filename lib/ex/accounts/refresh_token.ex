defmodule Ex.Accounts.RefreshToken do
  @moduledoc """
  A long-lived, single-use credential that is exchanged for a new access token.

  Only a SHA-256 hash of the secret is stored. Every refresh rotates the secret: the
  presented row is marked used and a new row is issued in the same `family_id`.
  Presenting a used or revoked secret again revokes the whole family, because that
  means the secret leaked. Written only through `Ex.Accounts.RefreshTokens`.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "refresh_tokens"
    repo Ex.Repo

    references do
      reference :user, on_delete: :delete, index?: true
    end

    custom_indexes do
      # Replay handling revokes every live token of a family (RefreshTokens.revoke_family_of/1).
      index [:family_id], where: "revoked_at IS NULL"
    end
  end

  actions do
    defaults [:read]

    create :issue do
      primary? true
      accept [:user_id, :token_hash, :family_id, :expires_at]
    end

    update :mark_used do
      require_atomic? false
      accept []
      change atomic_update(:used_at, expr(now()))
    end

    update :revoke do
      require_atomic? false
      accept []
      change atomic_update(:revoked_at, expr(now()))
    end
  end

  # No policies on purpose: this resource is not exposed over the API and is only
  # called with `authorize?: false` from Ex.Accounts.RefreshTokens.
  policies do
  end

  attributes do
    uuid_primary_key :id
    attribute :token_hash, :string, allow_nil?: false, sensitive?: true
    attribute :family_id, :uuid, allow_nil?: false
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :used_at, :utc_datetime_usec
    attribute :revoked_at, :utc_datetime_usec
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Ex.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_token_hash, [:token_hash]
  end
end
