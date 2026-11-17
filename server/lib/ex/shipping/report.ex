defmodule Ex.Shipping.Report do
  @moduledoc """
  Read-only reports. A Supervisor sees only their own Station; an Admin sees the whole company.

  * Cash: per staff member, cash taken minus cash refunded, over any start/end time (UTC instants, so a
    window crossing midnight is just two timestamps).
  * Cancellations: per staff member who asked, requests by outcome and the fee and refund totals.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "report-row"

    routes do
      base "/reports"

      route :get, "/cash", :cash do
        query_params [:from, :to]
        description "Cash per staff member between `from` and `to`. Needs `report.cash`."
      end

      route :get, "/cancellations", :cancellations do
        query_params [:from, :to]

        description "Cancellation requests per staff member between `from` and `to`. Needs `report.cancellation`."
      end
    end
  end

  actions do
    action :cash, {:array, :map} do
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      run fn input, context ->
        rows =
          query(
            """
            SELECT p.created_by_id, u.email,
                   COALESCE(SUM((p.amount).amount) FILTER (WHERE p.kind = 'payment'), 0),
                   COALESCE(SUM(-(p.amount).amount) FILTER (WHERE p.kind = 'refund'), 0),
                   COALESCE(SUM((p.amount).amount), 0)
            FROM payments p JOIN users u ON u.id = p.created_by_id
            WHERE p.method = 'cash' AND p.inserted_at >= $1 AND p.inserted_at < $2
              AND ($3::uuid IS NULL OR p.station_id = $3::uuid)
            GROUP BY p.created_by_id, u.email ORDER BY u.email
            """,
            input,
            context
          )

        {:ok,
         for [id, email, taken, refunded, net] <- rows do
           %{
             staff_id: id,
             email: email,
             cash_taken: to_string(taken),
             cash_refunded: to_string(refunded),
             net_cash: to_string(net),
             currency: "KHR"
           }
         end}
      end
    end

    action :cancellations, {:array, :map} do
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      run fn input, context ->
        rows =
          query(
            """
            SELECT c.requested_by_id, u.email,
                   COUNT(*) FILTER (WHERE c.status = 'pending'),
                   COUNT(*) FILTER (WHERE c.status = 'approved'),
                   COUNT(*) FILTER (WHERE c.status = 'rejected'),
                   COALESCE(SUM((c.fee).amount) FILTER (WHERE c.status = 'approved'), 0),
                   COALESCE(SUM((c.refund_amount).amount) FILTER (WHERE c.status = 'approved'), 0)
            FROM cancellation_requests c JOIN users u ON u.id = c.requested_by_id
            WHERE c.inserted_at >= $1 AND c.inserted_at < $2
              AND ($3::uuid IS NULL OR c.station_id = $3::uuid)
            GROUP BY c.requested_by_id, u.email ORDER BY u.email
            """,
            input,
            context
          )

        {:ok,
         for [id, email, pending, approved, rejected, fees, refunds] <- rows do
           %{
             staff_id: id,
             email: email,
             pending: pending,
             approved: approved,
             rejected: rejected,
             fees_kept: to_string(fees),
             refunded: to_string(refunds),
             currency: "KHR"
           }
         end}
      end
    end
  end

  policies do
    policy action(:cash) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"report.cash"}
    end

    policy action(:cancellations) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"report.cancellation"}
    end
  end

  # An Admin has no Station, so the Station filter is NULL (everything); a Supervisor is limited to theirs.
  defp query(sql, input, %{actor: actor}) do
    station = actor.station_id && Ecto.UUID.dump!(actor.station_id)

    %{rows: rows} =
      Ex.Repo.query!(sql, [input.arguments.from, input.arguments.to, station])

    Enum.map(rows, fn [id | rest] -> [Ecto.UUID.load!(id) | rest] end)
  end
end
