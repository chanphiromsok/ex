defmodule Ex.Shipping.Checks.AtStation do
  @moduledoc """
  Passes when the actor works at the Shipment's origin or destination Station.
  Usage: `{Ex.Shipping.Checks.AtStation, side: :origin}` or `side: :destination`.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor works at the Shipment's #{opts[:side]} Station"

  @impl true
  def match?(%{station_id: station_id}, %{changeset: %{data: shipment}}, opts)
      when not is_nil(station_id) do
    station_id == Map.fetch!(shipment, :"#{opts[:side]}_station_id")
  end

  def match?(_actor, _context, _opts), do: false
end
