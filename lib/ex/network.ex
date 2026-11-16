defmodule Ex.Network do
  @moduledoc "Where goods are sent from and to: Locations, the Stations in them and the Routes between Locations."
  use Ash.Domain,
    otp_app: :ex,
    extensions: [AshJsonApi.Domain]

  resources do
    resource Ex.Network.Location
    resource Ex.Network.Station
    resource Ex.Network.Route
  end
end
