defmodule ExWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Ex.Accounts],
    open_api: "/open_api"
end
