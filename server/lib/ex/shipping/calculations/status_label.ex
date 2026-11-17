defmodule Ex.Shipping.Calculations.StatusLabel do
  @moduledoc "Turns a status code (read from `field`) into its English or Khmer label."
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    if opts[:language] in [:en, :km] and is_atom(opts[:field]),
      do: {:ok, opts},
      else: {:error, "needs language: :en | :km and field: atom"}
  end

  @impl true
  def load(_query, opts, _context), do: [opts[:field]]

  @impl true
  def calculate(records, opts, _context) do
    label =
      if opts[:language] == :en,
        do: &Ex.Shipping.Status.label_en/1,
        else: &Ex.Shipping.Status.label_km/1

    Enum.map(records, fn record ->
      case Map.get(record, opts[:field]) do
        nil -> nil
        status -> label.(status)
      end
    end)
  end
end
