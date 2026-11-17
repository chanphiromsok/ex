defmodule Ex.Schedule.Mock do
  @moduledoc """
  Stand-in for the external schedule service: four departures a day (Cambodia time) on every pair of
  Stations, with a fixed bus plate and driver per slot. A trip id carries everything needed to rebuild
  the departure, so `get/1` needs no storage. Replace with the real client when the service is known.
  """
  @behaviour Ex.Schedule

  @times ["0730", "1000", "1300", "1600"]
  @plates ["2A-1234", "2B-5678", "3C-9012", "2D-3456"]
  @drivers ["Sok Vibol", "Chea Sophal", "Meas Rith", "Kong Dara"]
  # Cambodia is UTC+7 all year.
  @utc_offset_seconds 7 * 3600

  @impl true
  def departures(origin, destination, %Date{} = date) do
    {:ok, Enum.map(@times, &build(origin, destination, date, &1))}
  end

  @impl true
  def get("mock:" <> rest) do
    with [origin, destination, ymd, hhmm] when hhmm in @times <- String.split(rest, ":"),
         {:ok, date} <- Date.from_iso8601(ymd) do
      {:ok, build(origin, destination, date, hhmm)}
    else
      _ -> {:error, :not_found}
    end
  end

  def get(_other), do: {:error, :not_found}

  defp build(origin, destination, date, <<h::binary-size(2), m::binary-size(2)>> = hhmm) do
    slot = :erlang.phash2({origin, destination, hhmm}, length(@plates))

    departs_at =
      date
      |> NaiveDateTime.new!(Time.new!(String.to_integer(h), String.to_integer(m), 0))
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-@utc_offset_seconds)

    %{
      trip_id: "mock:#{origin}:#{destination}:#{Date.to_iso8601(date)}:#{hhmm}",
      origin_station_id: origin,
      destination_station_id: destination,
      departs_at: departs_at,
      departed: false,
      bus_label: Enum.at(@plates, slot),
      driver_name: Enum.at(@drivers, slot)
    }
  end
end
