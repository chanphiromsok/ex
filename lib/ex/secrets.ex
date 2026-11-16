defmodule Ex.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Ex.Accounts.User, _opts, _context) do
    Application.fetch_env(:ex, :token_signing_secret)
  end
end
