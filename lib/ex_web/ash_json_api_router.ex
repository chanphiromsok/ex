defmodule ExWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Ex.Accounts, Ex.Network],
    open_api: "/open_api"
end
