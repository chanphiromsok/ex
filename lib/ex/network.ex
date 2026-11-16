defmodule Ex.Network do
  @moduledoc "Where goods are sent from and to: Locations and the Stations in them."
  use Ash.Domain, otp_app: :ex

  resources do
    resource Ex.Network.Location
    resource Ex.Network.Station
  end
end
