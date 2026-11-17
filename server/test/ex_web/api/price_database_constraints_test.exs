defmodule ExWeb.Api.PriceDatabaseConstraintsTest do
  @moduledoc """
  The money rules and the price history are enforced by Postgres itself, not
  only by Ash, so a script or a future code path cannot break them.
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp khr(amount), do: %{amount: to_string(amount), currency: "KHR"}

  defp insert_sale_item(amount, currency \\ "KHR") do
    Ex.Repo.query(
      """
      INSERT INTO sale_items (id, name_en, name_km, unit_price, active, inserted_at, updated_at)
      VALUES (gen_random_uuid(), 'Tape', 'កាវ', ROW($1, $2)::money_with_currency, true, now(), now())
      """,
      [currency, Decimal.new(amount)]
    )
  end

  describe "a price column in the database" do
    test "accepts a positive whole number of riel" do
      assert {:ok, _} = insert_sale_item("1500")
    end

    test "rejects a negative price" do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_sale_item("-5")
    end

    test "rejects a zero price" do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_sale_item("0")
    end

    test "rejects a fraction of a riel" do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_sale_item("10.5")
    end

    test "rejects a currency other than KHR" do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_sale_item("5", "USD")
    end
  end

  describe "the price history in the database" do
    defp insert_price_change(kind, size_class_id, sale_item_id, changed_by_id) do
      Ex.Repo.query(
        """
        INSERT INTO price_changes (id, kind, price, size_class_id, sale_item_id, changed_by_id, inserted_at)
        VALUES (gen_random_uuid(), $1, ROW('KHR', 100)::money_with_currency, $2, $3, $4, now())
        """,
        [kind, size_class_id, sale_item_id, changed_by_id]
      )
    end

    test "rejects a Size Class price that names no Size Class" do
      admin = user!(:admin)

      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_price_change("size_class", nil, nil, Ecto.UUID.dump!(admin.id))
    end

    test "rejects a price per kg that names a Sale Item" do
      admin = user!(:admin)

      {:ok, %{rows: [[sale_item_id]]}} =
        Ex.Repo.query("""
        INSERT INTO sale_items (id, name_en, name_km, unit_price, active, inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'Tape', 'កាវ', ROW('KHR', 1500)::money_with_currency, true, now(), now())
        RETURNING id
        """)

      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               insert_price_change("price_per_kg", nil, sale_item_id, Ecto.UUID.dump!(admin.id))
    end

    test "rejects a price with no one who set it" do
      assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} =
               insert_price_change("price_per_kg", nil, nil, nil)
    end

    test "cannot be changed or deleted, even by raw SQL", %{conn: conn} do
      admin = conn |> signed_in(user!(:admin))

      admin
      |> post("/api/v1/pricing/price-per-kg", %{
        data: %{type: "pricing-setting", attributes: %{price_per_kg: khr(4500)}}
      })
      |> json_response(201)

      assert_raise Postgrex.Error, ~r/cannot be changed or deleted/, fn ->
        Ex.Repo.query!("UPDATE price_changes SET price = price")
      end
    end

    test "cannot be deleted, even by raw SQL", %{conn: conn} do
      admin = conn |> signed_in(user!(:admin))

      admin
      |> post("/api/v1/pricing/price-per-kg", %{
        data: %{type: "pricing-setting", attributes: %{price_per_kg: khr(4500)}}
      })
      |> json_response(201)

      assert_raise Postgrex.Error, ~r/cannot be changed or deleted/, fn ->
        Ex.Repo.query!("DELETE FROM price_changes")
      end
    end
  end

  describe "price.manage is the only Permission Size Classes and Sale Items need" do
    setup %{conn: conn} do
      Ash.create!(
        Ex.Accounts.RolePermission,
        %{role: :supervisor, permission: :"price.manage"},
        authorize?: false
      )

      %{manager: conn |> signed_in(user!(:supervisor))}
    end

    test "such a user creates, renames, prices and deactivates a Size Class", %{manager: manager} do
      created =
        manager
        |> post("/api/v1/size-classes", %{
          data: %{
            type: "size-class",
            attributes: %{name_en: "Box", name_km: "ប្រអប់", price: khr(5000)}
          }
        })
        |> json_response(201)

      id = created["data"]["id"]

      assert manager
             |> patch("/api/v1/size-classes/#{id}", %{
               data: %{type: "size-class", id: id, attributes: %{name_en: "Big Box"}}
             })
             |> json_response(200)

      assert manager
             |> patch("/api/v1/size-classes/#{id}", %{
               data: %{type: "size-class", id: id, attributes: %{active: false}}
             })
             |> json_response(200)

      # Still able to price an inactive one, and to see it.
      assert manager
             |> patch("/api/v1/size-classes/#{id}/price", %{
               data: %{type: "size-class", id: id, attributes: %{price: khr(6000)}}
             })
             |> json_response(200)
    end

    test "such a user creates and renames a Sale Item", %{manager: manager} do
      created =
        manager
        |> post("/api/v1/sale-items", %{
          data: %{
            type: "sale-item",
            attributes: %{name_en: "Tape", name_km: "កាវ", unit_price: khr(1500)}
          }
        })
        |> json_response(201)

      id = created["data"]["id"]

      assert manager
             |> patch("/api/v1/sale-items/#{id}", %{
               data: %{type: "sale-item", id: id, attributes: %{name_en: "Wide Tape"}}
             })
             |> json_response(200)
    end

    test "Station Staff still cannot create one", %{conn: conn} do
      conn
      |> signed_in(user!(:staff))
      |> post("/api/v1/size-classes", %{
        data: %{
          type: "size-class",
          attributes: %{name_en: "Box", name_km: "ប្រអប់", price: khr(5000)}
        }
      })
      |> json_response(403)
    end
  end
end
