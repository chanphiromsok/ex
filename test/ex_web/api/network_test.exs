defmodule ExWeb.Api.NetworkTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp body(type, attributes) do
    %{data: %{type: type, attributes: attributes}}
  end

  describe "locations" do
    test "an admin creates one and any signed-in user lists it", %{conn: conn} do
      admin_conn = signed_in(conn, user!(:admin))

      created =
        admin_conn
        |> post("/api/v1/locations", body("location", %{name_en: "Siem Reap", name_km: "សៀមរាប"}))
        |> json_response(201)

      id = created["data"]["id"]

      ids =
        conn
        |> signed_in(user!(:staff))
        |> get("/api/v1/locations")
        |> json_response(200)
        |> get_in(["data", Access.all(), "id"])

      assert id in ids
    end

    test "staff cannot create one", %{conn: conn} do
      conn = signed_in(conn, user!(:staff))
      conn = post(conn, "/api/v1/locations", body("location", %{name_en: "X", name_km: "ក"}))
      assert json_response(conn, 403)
    end

    test "anonymous callers see none", %{conn: conn} do
      location!("Hidden")
      conn = put_req_header(conn, "accept", "application/vnd.api+json")
      assert json_response(get(conn, "/api/v1/locations"), 200)["data"] == []
    end
  end

  describe "stations" do
    test "an admin creates one in a Location", %{conn: conn} do
      location = location!("Battambang")

      created =
        conn
        |> signed_in(user!(:admin))
        |> post(
          "/api/v1/stations",
          body("station", %{name_en: "BB Main", name_km: "បា", location_id: location.id})
        )
        |> json_response(201)

      assert created["data"]["attributes"]["name_en"] == "BB Main"
    end

    test "staff cannot create one", %{conn: conn} do
      location = location!("Kampot")

      conn =
        conn
        |> signed_in(user!(:staff))
        |> post(
          "/api/v1/stations",
          body("station", %{name_en: "K", name_km: "ក", location_id: location.id})
        )

      assert json_response(conn, 403)
    end
  end

  describe "OpenAPI spec (rendered by Scalar)" do
    setup %{conn: conn} do
      spec = conn |> get("/api/v1/open_api") |> then(&Jason.decode!(&1.resp_body))
      %{spec: spec}
    end

    test "has the title, intro and tag descriptions", %{spec: spec} do
      assert spec["info"]["title"] == "Express Cargo API"
      assert spec["info"]["description"] =~ "Getting started"
      assert Enum.any?(spec["tags"], &(&1["name"] == "location" and &1["description"] != nil))
    end

    test "documents the Network endpoints", %{spec: spec} do
      assert spec["paths"]["/api/v1/locations"]["get"]["description"] =~ "Lists Locations"
      assert spec["paths"]["/api/v1/stations"]["post"]["description"] =~ "reference_data.manage"
    end

    test "sign-in and refresh are public, everything else needs the bearer token", %{spec: spec} do
      assert spec["paths"]["/api/v1/users/sign-in"]["post"]["security"] == []
      assert spec["paths"]["/api/v1/users/refresh"]["post"]["security"] == []
      refute Map.has_key?(spec["paths"]["/api/v1/locations"]["get"], "security")
    end
  end
end
