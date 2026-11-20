defmodule Ex.Shipping.Preparations.SearchShipments do
  @moduledoc """
  Narrows a Shipment list to the `search` argument: an Invoice Number (`123` or `#123`), part of a
  Sender or Receiver name (any case), or part of a phone number typed the local way (`012 345…`) or
  with the country code. Phones are stored as `855…`, so a leading `0` is read as `855`.
  """
  use Ash.Resource.Preparation
  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    case query |> Ash.Query.get_argument(:search) |> clean() do
      nil -> query
      term -> Ash.Query.filter(query, ^match(term))
    end
  end

  defp clean(nil), do: nil

  defp clean(term) do
    case String.trim(term) do
      "" -> nil
      t -> t
    end
  end

  defp match(term) do
    like = "%" <> escape_like(term) <> "%"

    names =
      Ash.Expr.expr(
        ilike(sender_name, ^like) or ilike(receiver_name, ^like) or
          ilike(current_receiver_name, ^like)
      )

    names
    |> or_phone(phone_digits(term))
    |> or_invoice(invoice_no(term))
  end

  defp or_phone(expr, nil), do: expr

  defp or_phone(expr, digits) do
    like = "%" <> digits <> "%"

    Ash.Expr.expr(
      ^expr or like(sender_phone, ^like) or like(receiver_phone, ^like) or
        like(current_receiver_phone, ^like)
    )
  end

  defp or_invoice(expr, nil), do: expr
  defp or_invoice(expr, no), do: Ash.Expr.expr(^expr or invoice_no == ^no)

  # Three or more digits, ignoring spaces, dashes, dots, brackets and a leading "+".
  defp phone_digits(term) do
    stripped = String.replace(term, ~r/[\s\-\.\(\)\+]/, "")

    if Regex.match?(~r/^\d{3,}$/, stripped) do
      case stripped do
        "00" <> rest -> rest
        "0" <> rest -> "855" <> rest
        other -> other
      end
    end
  end

  defp invoice_no(term) do
    case Regex.run(~r/^#?(\d{1,9})$/, term) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp escape_like(term), do: String.replace(term, ~r/([\\%_])/, "\\\\\\1")
end
