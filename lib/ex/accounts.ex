defmodule Ex.Accounts do
  use Ash.Domain,
    otp_app: :ex

  resources do
    resource Ex.Accounts.Token
    resource Ex.Accounts.User
  end
end
