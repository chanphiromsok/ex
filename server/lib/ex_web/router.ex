defmodule ExWeb.Router do
  use ExWeb, :router
  import AshAuthentication.Plug.Helpers

  pipeline :api do
    plug ExWeb.Plugs.RateLimit
    plug :accepts, ["json"]
    plug :retrieve_from_bearer, :ex
    plug :set_actor, :user
  end

  pipeline :require_actor do
    plug ExWeb.Plugs.RequireActor
  end

  scope "/api/v1" do
    pipe_through [:api, :require_actor]

    forward "/", ExWeb.AshJsonApiRouter
  end

  # Load balancer probe: no session, no pipeline, excluded from force_ssl in config/prod.exs.
  scope "/", ExWeb do
    get "/health", HealthController, :show
  end
end
