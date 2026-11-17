defmodule Ex.Schedule do
  @moduledoc """
  The bus schedule. The company keeps its departures in an external service (ADR-0008); this module is
  the only place that talks to it. Which implementation runs is set by `config :ex, :schedule`.

  A departure is a map: `%{trip_id, origin_location_id, destination_location_id, departs_at, bus_plate,
  driver_name}`. Until the real service is connected, `Ex.Schedule.Mock` answers.
  """

  @type departure :: %{
          trip_id: String.t(),
          origin_location_id: Ecto.UUID.t(),
          destination_location_id: Ecto.UUID.t(),
          departs_at: DateTime.t(),
          bus_plate: String.t() | nil,
          driver_name: String.t() | nil
        }

  @callback departures(
              origin_location_id :: Ecto.UUID.t(),
              destination_location_id :: Ecto.UUID.t(),
              Date.t()
            ) ::
              {:ok, [departure]} | {:error, term}
  @callback get(trip_id :: String.t()) :: {:ok, departure} | {:error, :not_found | term}

  def departures(origin, destination, date), do: impl().departures(origin, destination, date)
  def get(trip_id), do: impl().get(trip_id)

  defp impl, do: Application.get_env(:ex, :schedule, Ex.Schedule.Mock)
end
