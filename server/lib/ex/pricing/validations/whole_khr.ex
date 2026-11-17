defmodule Ex.Pricing.Validations.WholeKhr do
  @moduledoc "Rejects a money attribute that is not a positive whole number of riel (KHR)."
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]), do: {:ok, opts}, else: {:error, "attribute must be an atom"}
  end

  @impl true
  def validate(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil ->
        :ok

      %Money{currency: :KHR, amount: amount} ->
        if above_floor?(amount, opts) and Decimal.integer?(amount) do
          :ok
        else
          {:error, field: attribute, message: message(opts)}
        end

      _ ->
        {:error, field: attribute, message: "must be in KHR"}
    end
  end

  defp above_floor?(amount, opts) do
    if opts[:allow_zero],
      do: Decimal.compare(amount, 0) != :lt,
      else: Decimal.compare(amount, 0) == :gt
  end

  defp message(opts) do
    if opts[:allow_zero],
      do: "must be a whole number of riel, 0 or more",
      else: "must be a positive whole number of riel"
  end

  @impl true
  def atomic(changeset, opts, context), do: validate(changeset, opts, context)
end
