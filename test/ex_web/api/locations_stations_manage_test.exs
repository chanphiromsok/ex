defmodule ExWeb.Api.LocationsStationsManageTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp patch_body(type, id, attributes),
    do: %{data: %{type: type, id: id, attributes: attributes}}

  describe "locations" do
    test "an admin renames one and staff see the new name", %{conn: conn} do
      location = location!("Kampot")

      conn
      |> signed_in(user!(:admin))
      |> patch(
        "/api/v1/locations/#{location.id}",
        patch_body("location", location.id, %{name_en: "Kampot City"})
      )
      |> json_response(200)

      shown =
        conn
        |> signed_in(user!(:staff))
        |> get("/api/v1/locations/#{location.id}")
        |> json_response(200)

      assert shown["data"]["attributes"]["name_en"] == "Kampot City"
    end

    test "staff cannot rename one", %{conn: conn} do
      location = location!("Kep")

      conn =
        conn
        |> signed_in(user!(:staff))
        |> patch(
          "/api/v1/locations/#{location.id}",
          patch_body("location", location.id, %{name_en: "Nope"})
        )

      assert json_response(conn, 403)
    end
  end

  describe "stations" do
    test "an admin deactivates one and staff see it inactive", %{conn: conn} do
      station = station!("Old Market")

      conn
      |> signed_in(user!(:admin))
      |> patch(
        "/api/v1/stations/#{station.id}",
        patch_body("station", station.id, %{active: false})
      )
      |> json_response(200)

      shown =
        conn
        |> signed_in(user!(:staff))
        |> get("/api/v1/stations/#{station.id}")
        |> json_response(200)

      assert shown["data"]["attributes"]["active"] == false
    end

    test "a Station cannot be moved to another Location", %{conn: conn} do
      station = station!("Fixed")
      other = location!("Elsewhere")

      conn
      |> signed_in(user!(:admin))
      |> patch(
        "/api/v1/stations/#{station.id}",
        patch_body("station", station.id, %{location_id: other.id})
      )
      |> json_response(400)

      assert Ash.get!(Ex.Network.Station, station.id, authorize?: false).location_id ==
               station.location_id
    end

    test "names are unique per Location, not globally", %{conn: conn} do
      admin = conn |> signed_in(user!(:admin))
      pp = location!("PP Unique")
      sr = location!("SR Unique")

      create = fn location, name ->
        post(admin, "/api/v1/stations", %{
          data: %{
            type: "station",
            attributes: %{name_en: name, name_km: "km " <> name, location_id: location.id}
          }
        })
      end

      assert create.(pp, "Central") |> json_response(201)
      assert create.(sr, "Central") |> json_response(201)
      assert create.(pp, "Central") |> json_response(400)
    end

    test "staff cannot change one", %{conn: conn} do
      station = station!("Locked")

      conn =
        conn
        |> signed_in(user!(:staff))
        |> patch(
          "/api/v1/stations/#{station.id}",
          patch_body("station", station.id, %{active: false})
        )

      assert json_response(conn, 403)
    end
  end

  describe "deleting" do
    test "an admin deletes an unused Location", %{conn: conn} do
      location = location!("Unused")
      admin = conn |> signed_in(user!(:admin))

      assert admin |> delete("/api/v1/locations/#{location.id}") |> response(200)
      assert admin |> get("/api/v1/locations/#{location.id}") |> json_response(404)
    end

    test "a Location with a Station cannot be deleted", %{conn: conn} do
      station = station!("Pinned")

      conn =
        conn |> signed_in(user!(:admin)) |> delete("/api/v1/locations/#{station.location_id}")

      assert conn.status in [400, 409]
    end

    test "staff cannot delete a Station", %{conn: conn} do
      station = station!("Kept")
      conn = conn |> signed_in(user!(:staff)) |> delete("/api/v1/stations/#{station.id}")
      assert json_response(conn, 403)
    end

    test "a Station with staff cannot be deleted", %{conn: conn} do
      station = station!("Staffed")
      user!(:staff, station)
      conn = conn |> signed_in(user!(:admin)) |> delete("/api/v1/stations/#{station.id}")
      assert conn.status in [400, 409]
    end
  end
end
