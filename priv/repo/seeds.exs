require Ash.Query

# Seeds are safe to run more than once.
#
#     mix run priv/repo/seeds.exs
#
# The first Admin is created here because self-registration is closed and only an
# Admin can create other users. Set SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD in
# production; the defaults are for local development only.

email = System.get_env("SEED_ADMIN_EMAIL", "admin@gmail.com")
password = System.get_env("SEED_ADMIN_PASSWORD", "12345678")

existing =
  Ex.Accounts.User
  |> Ash.Query.filter(email == ^email)
  |> Ash.read_one!(authorize?: false)

case existing do
  %{} = user ->
    IO.puts("Admin #{user.email} already exists")

  nil ->
    Ash.create!(
      Ex.Accounts.User,
      %{email: email, password: password, password_confirmation: password, role: :admin},
      action: :register_with_password,
      authorize?: false
    )

    IO.puts("Created Admin #{email}")
end
