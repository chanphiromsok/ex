defmodule Ex.Accounts.User.Preparations.SignInByLogin do
  @moduledoc """
  Sign-in that accepts a phone number or an email as the login.

  The login is read from the `login` argument, or from `email` for older clients. A value that is a valid
  Cambodian phone number (`012 345 678`, `+855 12 345 678`) is matched against `users.phone` in its 855…
  form; anything else is matched against `users.email`. The password check, the token and the failure
  message are the same as AshAuthentication's own sign-in, so a wrong login and a wrong password look alike.
  """
  use Ash.Resource.Preparation

  alias AshAuthentication.{Errors.AuthenticationFailed, Info, Jwt}
  alias Ash.Query

  require Ash.Query

  @impl true
  def prepare(query, _opts, context) do
    {:ok, strategy} = Info.strategy(query.resource, :password)
    login = Query.get_argument(query, :login) || Query.get_argument(query, :email)

    query
    |> filter_by_login(login)
    |> Query.before_action(&Query.ensure_selected(&1, [strategy.hashed_password_field]))
    |> Query.after_action(fn
      query, [record] ->
        password = Query.get_argument(query, :password)

        if strategy.hash_provider.valid?(password, record.hashed_password) do
          {:ok, [put_token(record, Ash.Context.to_opts(context))]}
        else
          {:error, failure(strategy, query, "Password is not valid")}
        end

      query, _none_or_many ->
        strategy.hash_provider.simulate()
        {:error, failure(strategy, query, "Query returned no single user")}
    end)
  end

  defp filter_by_login(query, nil), do: Query.filter(query, false)

  defp filter_by_login(query, login) do
    login = login |> to_string() |> String.trim()

    query =
      case Ex.Shipping.Phone.normalize(login) do
        {:ok, phone} -> Query.filter(query, phone == ^phone)
        :error -> Query.filter(query, email == ^login)
      end

    Query.filter(query, not is_nil(hashed_password))
  end

  defp put_token(record, opts) do
    {:ok, token, _claims} = Jwt.token_for_user(record, %{"purpose" => "user"}, opts)
    Ash.Resource.put_metadata(record, :token, token)
  end

  defp failure(strategy, query, message) do
    AuthenticationFailed.exception(
      strategy: strategy,
      query: query,
      caused_by: %{module: __MODULE__, strategy: strategy, action: :sign_in, message: message}
    )
  end
end
