defmodule Ex.Accounts do
  use Ash.Domain,
    otp_app: :ex,
    extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/users", Ex.Accounts.User do
        index :read
        get :read
      end
    end
  end

  resources do
    resource Ex.Accounts.Token
    resource Ex.Accounts.User
  end
end
