defmodule Ex.Accounts.Role do
  @moduledoc """
  The role of a user: Station Staff, Supervisor or Admin. A role selects the default Permissions.
  """

  use Ash.Type.Enum, values: [:staff, :supervisor, :admin]
end
