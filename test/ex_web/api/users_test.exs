defmodule ExWeb.Api.UsersTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp create_body(attrs) do
    %{
      data: %{
        type: "user",
        attributes:
          Map.merge(
            %{
              email: "new-#{System.unique_integer([:positive])}@example.com",
              password: "password123",
              password_confirmation: "password123"
            },
            attrs
          )
      }
    }
  end

  describe "signing in" do
    test "returns a token, the role and the Station", %{conn: conn} do
      staff = user!(:staff)

      body =
        conn
        |> sign_in(staff.email, "password123")
        |> json_response(201)

      assert body["data"]["attributes"]["role"] == "staff"
      assert body["data"]["attributes"]["station_id"] == staff.station_id
      assert is_binary(body["meta"]["token"])
    end

    test "rejects a wrong password", %{conn: conn} do
      staff = user!(:staff)
      conn = sign_in(conn, staff.email, "nope-nope")
      assert json_response(conn, 403)
    end
  end

  describe "sparse fields" do
    test "the fields listed as default in the OpenAPI spec are accepted", %{conn: conn} do
      admin = user!(:admin)
      conn = signed_in(conn, admin)

      body =
        get(conn, "/api/v1/users/#{admin.id}",
          fields: %{user: "email,role,station_id,inserted_at,permissions"}
        )
        |> json_response(200)

      assert body["data"]["attributes"]["inserted_at"]
    end
  end

  describe "creating users" do
    test "an Admin creates Station Staff with a Station", %{conn: conn} do
      station = station!()
      conn = signed_in(conn, user!(:admin))

      body =
        post(conn, "/api/v1/users", create_body(%{role: "staff", station_id: station.id}))
        |> json_response(201)

      assert body["data"]["attributes"]["role"] == "staff"
    end

    test "an Admin creates a Supervisor with a Station", %{conn: conn} do
      station = station!()
      conn = signed_in(conn, user!(:admin))

      assert post(
               conn,
               "/api/v1/users",
               create_body(%{role: "supervisor", station_id: station.id})
             )
             |> json_response(201)
    end

    test "Staff without a Station is rejected", %{conn: conn} do
      conn = signed_in(conn, user!(:admin))
      assert post(conn, "/api/v1/users", create_body(%{role: "staff"})) |> json_response(400)
    end

    test "Admin with a Station is rejected", %{conn: conn} do
      station = station!()
      conn = signed_in(conn, user!(:admin))

      assert post(conn, "/api/v1/users", create_body(%{role: "admin", station_id: station.id}))
             |> json_response(400)
    end

    test "a role is required", %{conn: conn} do
      station = station!()
      conn = signed_in(conn, user!(:admin))

      assert post(conn, "/api/v1/users", create_body(%{station_id: station.id}))
             |> json_response(400)
    end

    for role <- [:staff, :supervisor] do
      test "a #{role} cannot create users", %{conn: conn} do
        actor = user!(unquote(role))
        conn = signed_in(conn, actor)

        conn =
          post(
            conn,
            "/api/v1/users",
            create_body(%{role: "staff", station_id: actor.station_id})
          )

        assert conn.status in [401, 403]
      end
    end

    test "an anonymous caller cannot create users", %{conn: conn} do
      station = station!()

      conn =
        conn
        |> put_req_header("accept", "application/vnd.api+json")
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post("/api/v1/users", create_body(%{role: "staff", station_id: station.id}))

      assert conn.status in [401, 403]
    end
  end

  describe "changing a user's role or Station" do
    test "an Admin moves Staff to another Station and the change is logged", %{conn: conn} do
      staff = user!(:staff)
      other = station!("Siem Reap")
      admin = user!(:admin)
      conn = signed_in(conn, admin)

      body =
        patch(conn, "/api/v1/users/#{staff.id}", %{
          data: %{
            type: "user",
            id: staff.id,
            attributes: %{role: "supervisor", station_id: other.id}
          }
        })
        |> json_response(200)

      assert body["data"]["attributes"]["role"] == "supervisor"

      changes =
        Ex.Accounts.UserAssignmentChange
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.user_id == staff.id))

      assert length(changes) == 2
      assert Enum.any?(changes, &(&1.station_id == other.id and &1.changed_by_id == admin.id))
    end

    test "a Supervisor cannot change a user", %{conn: conn} do
      supervisor = user!(:supervisor)

      staff =
        user!(:staff, Ash.get!(Ex.Network.Station, supervisor.station_id, authorize?: false))

      conn = signed_in(conn, supervisor)

      conn =
        patch(conn, "/api/v1/users/#{staff.id}", %{
          data: %{
            type: "user",
            id: staff.id,
            attributes: %{role: "supervisor", station_id: staff.station_id}
          }
        })

      assert conn.status in [401, 403, 404]
    end

    test "the assignment log cannot be edited in the database" do
      staff = user!(:staff)

      assert_raise Postgrex.Error, ~r/cannot be changed or deleted/, fn ->
        Ex.Repo.query!("UPDATE user_assignment_changes SET role = 'admin' WHERE user_id = $1", [
          Ecto.UUID.dump!(staff.id)
        ])
      end
    end
  end

  describe "reading users" do
    test "staff can read only themselves", %{conn: conn} do
      staff = user!(:staff)
      _other = user!(:staff)
      conn = signed_in(conn, staff)

      ids =
        get(conn, "/api/v1/users")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert ids == [staff.id]
    end

    test "an Admin reads everyone", %{conn: conn} do
      admin = user!(:admin)
      staff = user!(:staff)
      conn = signed_in(conn, admin)

      ids =
        get(conn, "/api/v1/users")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert admin.id in ids
      assert staff.id in ids
    end
  end
end
