defmodule Ex.Accounts.RefreshTokens do
  @moduledoc """
  Issues and rotates refresh tokens (see `Ex.Accounts.RefreshToken`).

  The secret handed to the client is random and opaque; the database holds only its hash.
  """
  alias Ex.Accounts.RefreshToken
  require Ash.Query

  @default_days 30

  @doc "Starts a new family for `user` and returns the secret to give the client."
  @spec issue(Ash.Resource.record()) :: String.t()
  def issue(user), do: issue(user.id, Ash.UUID.generate())

  @doc """
  Exchanges a secret for a new one. Returns `{:ok, user_id, new_secret}`, or `:error` when the
  secret is unknown, expired, revoked or already used (a reused secret revokes its family).
  """
  @spec rotate(String.t()) :: {:ok, Ash.UUID.t(), String.t()} | :error
  def rotate(secret) when is_binary(secret) do
    hash = hash(secret)

    claimed =
      RefreshToken
      |> Ash.Query.filter(
        token_hash == ^hash and is_nil(used_at) and is_nil(revoked_at) and expires_at > now()
      )
      |> Ash.bulk_update!(:mark_used, %{},
        strategy: :atomic,
        return_records?: true,
        authorize?: false
      )

    case claimed.records do
      [%{user_id: user_id, family_id: family_id}] ->
        {:ok, user_id, issue(user_id, family_id)}

      _ ->
        revoke_family_of(hash)
        :error
    end
  end

  def rotate(_), do: :error

  defp issue(user_id, family_id) do
    secret = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    Ash.create!(
      RefreshToken,
      %{
        user_id: user_id,
        family_id: family_id,
        token_hash: hash(secret),
        expires_at: DateTime.add(DateTime.utc_now(), lifetime_days() * 86_400, :second)
      },
      authorize?: false
    )

    secret
  end

  # A secret we have seen before but can no longer use was replayed: kill the family.
  defp revoke_family_of(hash) do
    case RefreshToken
         |> Ash.Query.filter(token_hash == ^hash)
         |> Ash.read_one!(authorize?: false) do
      nil ->
        :ok

      %{family_id: family_id} ->
        RefreshToken
        |> Ash.Query.filter(family_id == ^family_id and is_nil(revoked_at))
        |> Ash.bulk_update!(:revoke, %{}, strategy: :atomic, authorize?: false)

        :ok
    end
  end

  defp hash(secret), do: Base.encode16(:crypto.hash(:sha256, secret), case: :lower)

  defp lifetime_days, do: Application.get_env(:ex, :refresh_token_days, @default_days)
end
