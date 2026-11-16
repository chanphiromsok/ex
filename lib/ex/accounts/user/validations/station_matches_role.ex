defmodule Ex.Accounts.User.Validations.StationMatchesRole do
  @moduledoc "Admin has no Station; Station Staff and Supervisor must have exactly one."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    role = Ash.Changeset.get_attribute(changeset, :role)
    station_id = Ash.Changeset.get_attribute(changeset, :station_id)

    cond do
      is_nil(role) ->
        :ok

      role == :admin and not is_nil(station_id) ->
        {:error, field: :station_id, message: "Admin has no Station"}

      role != :admin and is_nil(station_id) ->
        {:error, field: :station_id, message: "is required for this role"}

      true ->
        :ok
    end
  end
end
