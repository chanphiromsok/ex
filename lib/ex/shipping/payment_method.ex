defmodule Ex.Shipping.PaymentMethod do
  @moduledoc "How a Sender paid at the counter."
  use Ash.Type.Enum, values: [:cash, :bank_transfer, :qr]
end
