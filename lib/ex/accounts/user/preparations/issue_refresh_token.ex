defmodule Ex.Accounts.User.Preparations.IssueRefreshToken do
  @moduledoc "After a successful sign-in, starts a refresh token family and returns the secret as `meta.refresh_token`."
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn _query, users ->
      {:ok,
       Enum.map(users, fn user ->
         Ash.Resource.put_metadata(user, :refresh_token, Ex.Accounts.RefreshTokens.issue(user))
       end)}
    end)
  end
end
