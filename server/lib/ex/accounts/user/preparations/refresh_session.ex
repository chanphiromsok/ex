defmodule Ex.Accounts.User.Preparations.RefreshSession do
  @moduledoc """
  Exchanges the `refresh_token` argument for the User it belongs to, a new access token
  (`meta.token`) and a rotated refresh token (`meta.refresh_token`).
  """
  use Ash.Resource.Preparation
  require Ash.Query

  alias AshAuthentication.{Errors.AuthenticationFailed, Jwt}

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> Ash.Query.before_action(fn query ->
      case Ex.Accounts.RefreshTokens.rotate(Ash.Query.get_argument(query, :refresh_token)) do
        {:ok, user_id, new_secret} ->
          query
          |> Ash.Query.filter(id == ^user_id)
          |> Ash.Query.set_context(%{new_refresh_token: new_secret})

        :error ->
          Ash.Query.add_error(
            query,
            AuthenticationFailed.exception(
              caused_by: %{module: __MODULE__, action: :refresh, message: "invalid refresh token"}
            )
          )
      end
    end)
    |> Ash.Query.after_action(fn query, users ->
      {:ok,
       Enum.map(users, fn user ->
         {:ok, token, _claims} = Jwt.token_for_user(user)

         user
         |> Ash.Resource.put_metadata(:token, token)
         |> Ash.Resource.put_metadata(:refresh_token, query.context.new_refresh_token)
       end)}
    end)
  end
end
