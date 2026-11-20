defmodule Ex.Shipping.Pricing do
  @moduledoc """
  Prices a Shipment once. Returns every priced line and the Shipment Total, all whole KHR.

  A kg Parcel costs `weight_kg * price per kg`, rounded half up to a whole riel; a Size Class Parcel
  costs that Size Class's price; a Sale Item line costs `quantity * unit price`. The create action
  stores exactly these numbers, so the total always equals the sum of its lines.
  """

  @max_weight Decimal.new("999999.99")

  @type parcel_line :: %{
          measurement_type: :kg | :size,
          weight_kg: Decimal.t() | nil,
          size_class_id: String.t() | nil,
          chargeable_amount: Money.t()
        }

  @spec price(list(map()), list(map())) ::
          {:ok, %{parcels: [parcel_line()], sale_items: [map()], total: Money.t()}}
          | {:error, {atom(), String.t()}}
  def price(parcels, sale_items) do
    with {:ok, per_kg} <- price_per_kg(),
         {:ok, parcel_lines} <- map_while(parcels, &parcel_line(&1, per_kg)),
         {:ok, item_lines} <- map_while(sale_items, &sale_item_line/1) do
      amounts =
        Enum.map(parcel_lines, & &1.chargeable_amount) ++ Enum.map(item_lines, & &1.line_total)

      total = Enum.reduce(amounts, Money.new(:KHR, 0), &Money.add!(&1, &2))
      {:ok, %{parcels: parcel_lines, sale_items: item_lines, total: total}}
    end
  end

  defp price_per_kg do
    case Ex.Pricing.PricingSetting |> Ash.read_one(action: :current, authorize?: false) do
      {:ok, %{price_per_kg: %Money{} = price}} -> {:ok, price}
      _ -> {:error, {:parcels, "the price per kg has not been set"}}
    end
  end

  defp parcel_line(%{measurement_type: :kg} = parcel, per_kg) do
    weight = parcel[:weight_kg]

    cond do
      is_nil(weight) or Decimal.compare(weight, 0) != :gt ->
        {:error, {:parcels, "a kg Parcel needs a weight above 0"}}

      Decimal.compare(weight, @max_weight) == :gt or Decimal.scale(weight) > 2 ->
        {:error, {:parcels, "weight must be at most 999999.99 kg with at most 2 decimals"}}

      not is_nil(parcel[:size_class_id]) ->
        {:error, {:parcels, "a kg Parcel cannot also have a Size Class"}}

      true ->
        amount = per_kg.amount |> Decimal.mult(weight) |> Decimal.round(0, :half_up)

        if Decimal.compare(amount, 0) == :gt,
          do: {:ok, line(parcel, Money.new(:KHR, amount))},
          else: {:error, {:parcels, "a Parcel must cost at least 1 riel"}}
    end
  end

  defp parcel_line(%{measurement_type: :size} = parcel, _per_kg) do
    with :ok <- no_weight(parcel),
         {:ok, size_class} <-
           active(Ex.Pricing.SizeClass, parcel[:size_class_id], :parcels, "Size Class") do
      {:ok, line(parcel, size_class.price)}
    end
  end

  defp parcel_line(_, _),
    do: {:error, {:parcels, "each Parcel needs a measurement_type of kg or size"}}

  defp no_weight(%{weight_kg: nil}), do: :ok

  defp no_weight(%{weight_kg: _}),
    do: {:error, {:parcels, "a Size Class Parcel cannot also have a weight"}}

  defp no_weight(_), do: :ok

  defp line(parcel, amount) do
    %{
      measurement_type: parcel.measurement_type,
      weight_kg: parcel[:weight_kg],
      size_class_id: parcel[:size_class_id],
      chargeable_amount: amount
    }
  end

  defp sale_item_line(%{quantity: quantity} = item) when is_integer(quantity) and quantity > 0 do
    with {:ok, sale_item} <-
           active(Ex.Pricing.SaleItem, item[:sale_item_id], :sale_items, "Sale Item") do
      {:ok,
       %{
         sale_item_id: sale_item.id,
         quantity: quantity,
         unit_price: sale_item.unit_price,
         line_total: Money.mult!(sale_item.unit_price, quantity)
       }}
    end
  end

  defp sale_item_line(_), do: {:error, {:sale_items, "quantity must be a whole number above 0"}}

  defp active(resource, id, field, label) do
    case id && Ash.get(resource, id, authorize?: false) do
      {:ok, %{active: true} = record} -> {:ok, record}
      {:ok, _inactive} -> {:error, {field, "that #{label} is no longer active"}}
      _ -> {:error, {field, "that #{label} does not exist"}}
    end
  end

  defp map_while(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
