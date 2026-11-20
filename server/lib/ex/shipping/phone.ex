defmodule Ex.Shipping.Phone do
  @moduledoc """
  The one place a Cambodian phone number is normalised: digits only, with country code 855 and no
  leading zero (`012 345 678` and `+855 12 345 678` both become `85512345678`). The database holds the same
  rule as a CHECK, so a number that gets past here is always valid there too.
  """

  @valid ~r/^855[1-9][0-9]{7,8}$/

  @spec normalize(term()) :: {:ok, String.t()} | :error
  def normalize(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/[\s\-\.\(\)]/, "")

    candidate =
      case digits do
        "+" <> rest -> rest
        "00" <> rest -> rest
        "0" <> rest -> "855" <> rest
        other -> other
      end

    if Regex.match?(@valid, candidate), do: {:ok, candidate}, else: :error
  end

  def normalize(_), do: :error
end
