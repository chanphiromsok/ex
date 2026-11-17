defmodule Ex.Shipping.Changes.OpenManifest do
  @moduledoc """
  Opens a Manifest for one Trip from the schedule. The origin is the signed-in user's own Station; the
  Trip must run between that Station's Location and the destination Station's Location, on an existing
  Route. The Trip's departure time, bus label are copied onto the Manifest (ADR-0008).
  """
  use Ash.Resource.Change

  alias Ex.Network.{Route, Station}
  require Ash.Query

  @impl true
  def change(changeset, _opts, %{actor: %{station_id: origin_id} = actor})
      when not is_nil(origin_id) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      trip_id = Ash.Changeset.get_attribute(changeset, :external_trip_id)
      destination_id = Ash.Changeset.get_attribute(changeset, :destination_station_id)

      with {:ok, origin} <- Ash.get(Station, origin_id, authorize?: false),
           {:ok, destination} <- fetch_station(destination_id),
           {:ok, trip} <- fetch_trip(trip_id, origin, destination) do
        changeset
        |> Ash.Changeset.force_change_attribute(:origin_station_id, origin.id)
        |> Ash.Changeset.force_change_attribute(:created_by_id, actor.id)
        |> Ash.Changeset.force_change_attribute(:departs_at, trip.departs_at)
        |> Ash.Changeset.force_change_attribute(:bus_label, trip.bus_label)
      else
        {:error, field, message} ->
          Ash.Changeset.add_error(changeset, field: field, message: message)
      end
    end)
  end

  def change(changeset, _opts, _context) do
    Ash.Changeset.add_error(changeset,
      field: :origin_station_id,
      message: "you must work at a Station to open a Manifest"
    )
  end

  defp fetch_station(nil), do: {:error, :destination_station_id, "is required"}

  defp fetch_station(id) do
    case Ash.get(Station, id, authorize?: false) do
      {:ok, station} -> {:ok, station}
      _ -> {:error, :destination_station_id, "is not a Station"}
    end
  end

  defp fetch_trip(trip_id, origin, destination) do
    case Ex.Schedule.get(trip_id) do
      {:ok, %{departed: true}} ->
        {:error, :external_trip_id, "has already departed"}

      {:ok, %{origin_station_id: o, destination_station_id: d} = trip}
      when o == origin.id and d == destination.id ->
        {:ok, trip}

      {:ok, _other_route} ->
        {:error, :external_trip_id, "does not run from your Station to that Station"}

      {:error, :not_found} ->
        {:error, :external_trip_id, "is not a known Trip"}

      {:error, _unavailable} ->
        {:error, :external_trip_id, "could not be checked: the schedule is unavailable"}
    end
  end
end
