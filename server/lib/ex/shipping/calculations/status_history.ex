defmodule Ex.Shipping.Calculations.StatusHistory do
  @moduledoc """
  The Shipment's Status Events as a list, oldest first (received, in transit, arrived, collected).
  JSON:API's `included` list is not ordered, so this gives the frontend a ready timeline.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    events =
      Ex.Shipping.StatusEvent
      |> Ash.Query.select([:seq, :status, :reason, :station_id, :inserted_at])
      |> Ash.Query.sort(seq: :asc)

    [status_events: events]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn shipment ->
      shipment.status_events
      |> Enum.sort_by(& &1.seq)
      |> Enum.map(fn e ->
        %{
          seq: e.seq,
          status: e.status,
          status_label_en: Ex.Shipping.Status.label_en(e.status),
          status_label_km: Ex.Shipping.Status.label_km(e.status),
          station_id: e.station_id,
          reason: e.reason,
          at: e.inserted_at
        }
      end)
    end)
  end
end
