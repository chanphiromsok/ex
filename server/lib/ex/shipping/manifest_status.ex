defmodule Ex.Shipping.ManifestStatus do
  @moduledoc "Where a Manifest is: open for loading, departed with the bus, or arrived at the destination."
  use Ash.Type.Enum, values: [:open, :departed, :arrived]
end
