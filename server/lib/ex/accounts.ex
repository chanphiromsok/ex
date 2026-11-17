defmodule Ex.Accounts do
  use Ash.Domain,
    otp_app: :ex,
    extensions: [AshJsonApi.Domain]

  resources do
    resource Ex.Accounts.Token
    resource Ex.Accounts.RefreshToken
    resource Ex.Accounts.User
    resource Ex.Accounts.UserAssignmentChange
    resource Ex.Accounts.PermissionDefinition
    resource Ex.Accounts.RolePermission
  end
end
