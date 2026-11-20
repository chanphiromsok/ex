defmodule Ex.Shipping.Status do
  @moduledoc "Shipment status as a code, with English and Khmer labels. The labels live here, not in the database."

  use Ash.Type.Enum, values: [:received, :in_transit, :arrived, :collected, :cancelled]

  @labels %{
    received: {"Received", "បានទទួល"},
    in_transit: {"In transit", "កំពុងដឹកជញ្ជូន"},
    arrived: {"Arrived", "បានមកដល់"},
    collected: {"Collected", "បានទទួលយកអីវ៉ាន់"},
    cancelled: {"Cancelled", "បានលុបចោល"}
  }

  def label_en(status), do: @labels |> Map.fetch!(status) |> elem(0)
  def label_km(status), do: @labels |> Map.fetch!(status) |> elem(1)
end
