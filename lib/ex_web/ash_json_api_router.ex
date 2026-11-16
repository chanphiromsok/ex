defmodule ExWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Ex.Accounts, Ex.Network],
    open_api: "/open_api",
    open_api_title: "Express Cargo API",
    open_api_version: "1.0.0",
    modify_open_api: {ExWeb.OpenApi, :modify, []}
end
