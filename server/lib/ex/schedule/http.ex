defmodule Ex.Schedule.Http do
  @moduledoc """
  Client for the external schedule service (ADR-0008). Switch it on with `config :ex, :schedule, Ex.Schedule.Http`
  and set `config :ex, Ex.Schedule.Http, base_url: ..., token: ...` (env `SCHEDULE_URL`, `SCHEDULE_TOKEN`).

  Their Stations are ours by `external_id`. A trip from or to a Station we do not know is skipped.
  Assumed, to confirm with the service: `GET {base}/trips?origin_id=&destination_id=&date=YYYY-MM-DD`
  and `GET {base}/trips/{id}`, both answering `{"data": ...}`, with a bearer token.
  """
  @behaviour Ex.Schedule

  alias Ex.Network.Station
  require Ash.Query

  @impl true
  def departures(origin_station_id, destination_station_id, %Date{} = date) do
    with {:ok, origin} <- station(origin_station_id),
         {:ok, destination} <- station(destination_station_id),
         {:ok, %{status: 200, body: %{"data" => trips}}} <-
           request("/trips",
             params: [
               origin_id: origin.external_id,
               destination_id: destination.external_id,
               date: date
             ]
           ) do
      {:ok,
       trips
       |> Enum.uniq_by(& &1["id"])
       |> Enum.flat_map(&(&1 |> parse() |> List.wrap()))}
    else
      {:ok, _bad_response} -> {:error, :bad_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(trip_id) do
    case request("/trips/#{URI.encode(trip_id, &URI.char_unreserved?/1)}") do
      {:ok, %{status: 200, body: %{"data" => %{} = trip}}} ->
        case parse(trip) do
          nil -> {:error, :not_found}
          departure -> {:ok, departure}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, _bad_response} ->
        {:error, :bad_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp station(id) do
    case Ash.get(Station, id, authorize?: false) do
      {:ok, %{external_id: external} = station} when is_binary(external) -> {:ok, station}
      _ -> {:error, :station_not_linked}
    end
  end

  defp parse(
         %{
           "id" => id,
           "departure_time" => departure,
           "origin" => %{"id" => origin},
           "destination" => %{"id" => destination}
         } = trip
       ) do
    with {:ok, departs_at, _offset} <- DateTime.from_iso8601(departure),
         %Station{id: origin_id} <- by_external(origin),
         %Station{id: destination_id} <- by_external(destination) do
      %{
        trip_id: id,
        origin_station_id: origin_id,
        destination_station_id: destination_id,
        departs_at: departs_at,
        departed: trip["is_departed"] == true,
        bus_label: get_in(trip, ["bus", "model"])
      }
    else
      _ -> nil
    end
  end

  defp parse(_other), do: nil

  defp by_external(external_id) do
    Station |> Ash.Query.filter(external_id == ^external_id) |> Ash.read_one!(authorize?: false)
  end

  defp request(path, opts \\ []) do
    config = Application.get_env(:ex, __MODULE__, [])

    [
      base_url: config[:base_url],
      url: path,
      auth: {:bearer, config[:token]},
      receive_timeout: 5_000,
      retry: false
    ]
    |> Keyword.merge(config[:req_options] || [])
    |> Keyword.merge(opts)
    |> Req.new()
    |> Req.get()
  end
end
