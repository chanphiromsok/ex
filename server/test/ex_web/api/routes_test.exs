defmodule ExWeb.Api.RoutesTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp create_route(conn, origin_id, destination_id) do
    post(conn, "/api/v1/routes", %{
      data: %{
        type: "route",
        attributes: %{origin_location_id: origin_id, destination_location_id: destination_id}
      }
    })
  end

  setup do
    %{pp: location!("Phnom Penh"), sr: location!("Siem Reap")}
  end

  test "an admin creates a Route and staff can read it", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    created = admin |> create_route(pp.id, sr.id) |> json_response(201)
    id = created["data"]["id"]

    shown = conn |> signed_in(user!(:staff)) |> get("/api/v1/routes/#{id}") |> json_response(200)
    assert shown["data"]["attributes"]["origin_location_id"] == pp.id
    assert shown["data"]["attributes"]["destination_location_id"] == sr.id
  end

  test "a Route is one way: Siem Reap to Phnom Penh is separate", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> create_route(pp.id, sr.id) |> json_response(201)
    assert admin |> create_route(sr.id, pp.id) |> json_response(201)
  end

  test "a duplicate Route is rejected", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> create_route(pp.id, sr.id) |> json_response(201)
    assert admin |> create_route(pp.id, sr.id) |> json_response(400)
  end

  test "a Route from a Location to itself is rejected", %{conn: conn, pp: pp} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> create_route(pp.id, pp.id) |> json_response(400)
  end

  test "staff cannot create or delete a Route", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    id = admin |> create_route(pp.id, sr.id) |> json_response(201) |> get_in(["data", "id"])
    staff = conn |> signed_in(user!(:staff))

    assert staff |> create_route(sr.id, pp.id) |> json_response(403)
    assert staff |> delete("/api/v1/routes/#{id}") |> json_response(403)
  end

  test "a Location a Route uses cannot be deleted", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> create_route(pp.id, sr.id) |> json_response(201)

    body = admin |> delete("/api/v1/locations/#{pp.id}") |> json_response(400)
    assert [%{"detail" => "is still used by a Route"}] = body["errors"]
  end

  test "an admin deletes a Route", %{conn: conn, pp: pp, sr: sr} do
    admin = conn |> signed_in(user!(:admin))
    id = admin |> create_route(pp.id, sr.id) |> json_response(201) |> get_in(["data", "id"])
    assert admin |> delete("/api/v1/routes/#{id}") |> response(200)
    assert admin |> get("/api/v1/routes/#{id}") |> json_response(404)
  end
end
