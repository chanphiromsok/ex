defmodule Ex.Schedule.HttpTest do
  @moduledoc "The real schedule client, against a stubbed service shaped like the sample the company sent."
  use Ex.DataCase, async: false
  import Ex.Fixtures

  @trip %{
    "id" => "92AVNA3w",
    "name" => "PNH → SR 07:30",
    "departure_time" => "2026-09-26T07:30:00+07:00",
    "arrival_time" => "2026-09-26T13:30:00+07:00",
    "is_departed" => false,
    "origin" => %{"id" => "XE85k7yx", "city" => "Phnom Penh"},
    "destination" => %{"id" => "2RBy5B0l", "city" => "Siem Reap"},
    "bus" => %{"id" => "qbA6VAxy", "model" => "Hyundai Universe"}
  }

  setup do
    previous = Application.get_env(:ex, Ex.Schedule.Http)

    Application.put_env(:ex, Ex.Schedule.Http,
      base_url: "http://schedule.test",
      token: "secret",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.put_env(:ex, Ex.Schedule.Http, previous || []) end)

    pp = station!("PP") |> link("XE85k7yx")
    sr = station!("SR") |> link("2RBy5B0l")
    %{pp: pp, sr: sr}
  end

  defp link(station, external_id),
    do: Ash.update!(station, %{external_id: external_id}, authorize?: false)

  test "lists trips, maps their Stations to ours, drops duplicates", %{pp: pp, sr: sr} do
    Req.Test.expect(Ex.Schedule.HttpTest, fn conn ->
      assert conn.request_path == "/trips"
      assert conn.query_string =~ "origin_id=XE85k7yx"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret"]
      Req.Test.json(conn, %{"data" => [@trip, @trip]})
    end)

    assert {:ok, [trip]} = Ex.Schedule.Http.departures(pp.id, sr.id, ~D[2026-09-26])
    assert trip.trip_id == "92AVNA3w"
    assert trip.origin_station_id == pp.id and trip.destination_station_id == sr.id
    assert trip.bus_label == "Hyundai Universe"
    assert trip.departed == false and is_nil(trip.driver_name)
    assert trip.departs_at == ~U[2026-09-26 00:30:00Z]
  end

  test "reads one trip; unknown trips and unlinked Stations are errors", %{pp: pp, sr: sr} do
    Req.Test.expect(Ex.Schedule.HttpTest, &Req.Test.json(&1, %{"data" => @trip}))
    assert {:ok, %{trip_id: "92AVNA3w"}} = Ex.Schedule.Http.get("92AVNA3w")

    Req.Test.expect(Ex.Schedule.HttpTest, &Plug.Conn.send_resp(&1, 404, ""))
    assert {:error, :not_found} = Ex.Schedule.Http.get("nope")

    other = station!("Unlinked")

    assert {:error, :station_not_linked} =
             Ex.Schedule.Http.departures(other.id, sr.id, ~D[2026-09-26])

    _ = pp
  end

  test "a service that is down is an error, not a crash", %{pp: pp, sr: sr} do
    Req.Test.expect(Ex.Schedule.HttpTest, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, _} = Ex.Schedule.Http.departures(pp.id, sr.id, ~D[2026-09-26])
  end
end
