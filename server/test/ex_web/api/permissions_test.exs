defmodule ExWeb.Api.PermissionsTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp permissions_after_sign_in(conn, user) do
    conn
    |> sign_in(user.email, "password123")
    |> json_response(201)
    |> get_in(["data", "attributes", "permissions"])
  end

  describe "role defaults" do
    test "sign-in lists the Permissions of the role", %{conn: conn} do
      staff = permissions_after_sign_in(conn, user!(:staff))
      assert "shipment.create" in staff
      refute "cancellation.approve" in staff
      refute "user.manage" in staff

      supervisor = permissions_after_sign_in(conn, user!(:supervisor))
      assert "cancellation.approve" in supervisor
      assert "report.cash" in supervisor

      admin = permissions_after_sign_in(conn, user!(:admin))
      assert "user.manage" in admin
      assert "shipment.read" in admin
      refute "shipment.create" in admin
    end

    test "a user shows their effective Permissions", %{conn: conn} do
      staff = user!(:staff)
      admin = user!(:admin)

      body =
        conn
        |> signed_in(admin)
        |> get("/api/v1/users/#{staff.id}")
        |> json_response(200)

      assert "shipment.create" in body["data"]["attributes"]["permissions"]
      refute "user.manage" in body["data"]["attributes"]["permissions"]
    end

    test "role defaults are data: removing a row removes the Permission", %{conn: conn} do
      row =
        Ex.Accounts.RolePermission
        |> Ash.read!(authorize?: false)
        |> Enum.find(&(&1.role == :staff and &1.permission == :"incident.report"))

      staff = user!(:staff)
      assert "incident.report" in permissions_after_sign_in(conn, staff)

      # Sandbox transaction: undone at the end of the test.
      Ash.destroy!(row, authorize?: false)
      refute "incident.report" in permissions_after_sign_in(build_conn(), staff)
    end

    test "a Station-bound Permission never takes effect without a Station", %{conn: conn} do
      Ash.create!(
        Ex.Accounts.RolePermission,
        %{role: :admin, permission: :"shipment.create"},
        authorize?: false
      )

      refute "shipment.create" in permissions_after_sign_in(conn, user!(:admin))
    end
  end

  describe "the Permission list" do
    test "any signed-in user can read it and it matches the application's names", %{conn: conn} do
      body =
        conn
        |> signed_in(user!(:staff))
        |> get("/api/v1/permissions")
        |> json_response(200)

      table_names = body["data"] |> Enum.map(& &1["id"]) |> Enum.sort()
      code_names = Ex.Accounts.Permission.values() |> Enum.map(&to_string/1) |> Enum.sort()
      assert table_names == code_names
    end

    test "unauthenticated callers are refused", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/vnd.api+json")
        |> get("/api/v1/permissions")

      assert conn.status in [401, 403]
    end
  end
end
