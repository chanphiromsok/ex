# Learning: Ash preparations (with our refresh token as the example)

A **preparation** is a module that changes a **read query** before it runs and/or its results after it runs. A **change** is the same idea for create, update and destroy actions. This page uses the two preparations in this project:

- `server/lib/ex/accounts/user/preparations/issue_refresh_token.ex` (small, runs after the read)
- `server/lib/ex/accounts/user/preparations/refresh_session.ex` (runs before and after)

## 1. Where a preparation sits

A read action runs in this order:

```
request → action arguments → policies → preparations (build the query)
        → before_action hooks → data layer (SQL) → after_action hooks → response
```

`prepare/3` runs while the query is being **built**. It does not touch the database; it registers work:

| Hook | Runs | Use it for |
|---|---|---|
| `Ash.Query.filter/2`, `sort`, `load`, `set_context` | at build time | shape the query |
| `Ash.Query.before_action/2` | just before SQL | work that must happen first, or can fail the query |
| `Ash.Query.after_action/2` | after SQL, with the records | enrich or replace results, put metadata on them |
| `Ash.Query.add_error/2` | anywhere | make the whole action fail with a proper error |

## 2. The minimal shape

```elixir
defmodule MyApp.Preparations.Example do
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, opts, context) do
    # return the query (possibly changed)
    query
  end
end
```

Use it in an action:

```elixir
read :sign_in_with_password do
  prepare AshAuthentication.Strategy.Password.SignInPreparation
  prepare Ex.Accounts.User.Preparations.IssueRefreshToken
end
```

Preparations run **in the order written**. The `after_action` hooks they register also run in that order.

## 3. Example 1: `IssueRefreshToken`

Goal: after a successful sign-in, hand the client a refresh token.

```elixir
def prepare(query, _opts, _context) do
  Ash.Query.after_action(query, fn _query, users ->
    {:ok,
     Enum.map(users, fn user ->
       Ash.Resource.put_metadata(user, :refresh_token, Ex.Accounts.RefreshTokens.issue(user))
     end)}
  end)
end
```

Reading it:
1. `prepare` does nothing to the query itself. It only registers an `after_action`.
2. The hook receives the records the query returned, here the one signed-in user. If the password was wrong, `SignInPreparation` has already failed the query, so there are no users and no token is issued.
3. `put_metadata/3` attaches a value to the record **without it being an attribute**. It lives in `user.__metadata__`.
4. The route copies it into the response:

```elixir
post :sign_in_with_password do
  route "/sign-in"
  metadata fn _subject, user, _request ->
    %{token: user.__metadata__.token, refresh_token: user.__metadata__.refresh_token}
  end
end
```

Rule: **every metadata key must be declared on the action** (`metadata :refresh_token, :string`), or Ash rejects it.

Order matters here: `IssueRefreshToken` is listed after `SignInPreparation`, so its hook runs after the token hook, and both values end up in `__metadata__`.

## 4. Example 2: `RefreshSession` (before and after, sharing data)

Goal: given a refresh token (an **argument**, not a user), find its user, and return a new access token and a new refresh token.

```elixir
query
|> Ash.Query.before_action(fn query -> ... end)
|> Ash.Query.after_action(fn query, users -> ... end)
```

**Step 1: before_action.** Look at the token and decide which user to read.

```elixir
case Ex.Accounts.RefreshTokens.rotate(Ash.Query.get_argument(query, :refresh_token)) do
  {:ok, user_id, new_secret} ->
    query
    |> Ash.Query.filter(id == ^user_id)                       # read only this user
    |> Ash.Query.set_context(%{new_refresh_token: new_secret}) # pass data forward

  :error ->
    Ash.Query.add_error(query, AuthenticationFailed.exception(...))
end
```

- The action had no filter of its own, so the hook **builds the filter** from the token. A refresh token never appears in SQL.
- `Ash.Query.set_context/2` is how a before hook hands data to the after hook. Context travels with the query.
- `add_error` fails the action. The client gets a `403`, the same as a wrong password, so the response doesn't reveal whether a token existed.

**Step 2: after_action.** Turn the user into a session.

```elixir
{:ok, token, _claims} = Jwt.token_for_user(user)

user
|> Ash.Resource.put_metadata(:token, token)
|> Ash.Resource.put_metadata(:refresh_token, query.context.new_refresh_token)
```

The new JWT is created here, and the rotated refresh secret is read back from the context.

## 5. Why a preparation and not a controller or a function?

- **Policies and errors still apply.** The action is a normal Ash action: the router, the OpenAPI spec, authorization and error formatting all come for free.
- **One place per rule.** `sign_in_with_password` lists its steps (`SignInPreparation`, then `IssueRefreshToken`), so you can read the sign-in flow top to bottom.
- **Reusable.** Any read action can add `prepare Ex.Accounts.User.Preparations.IssueRefreshToken`.
- **Testable through HTTP.** `server/test/ex_web/api/refresh_test.exs` exercises the whole thing through the API; no test calls the preparation directly.

## 6. Preparation vs change vs calculation vs validation

| Tool | For | Example here |
|---|---|---|
| Preparation | read actions: shape the query, post-process results | `IssueRefreshToken`, `RefreshSession` |
| Change | create / update / destroy: modify the changeset | `HashPasswordChange` (password hashing) |
| Validation | accept or reject input | `confirm(:password, :password_confirmation)` |
| Calculation | a computed field on every record, loadable on demand | `permissions` on `User` |
| Policy | who may run the action | `Ex.Accounts.Checks.HasPermission` |

Rule of thumb: if it needs the **result of the query**, use `after_action`; if it needs to **decide what to query**, use `before_action`; if it's a **field**, use a calculation.

## 7. Things that go wrong

- **Forgot to declare metadata.** `put_metadata(:foo, ...)` for a key the action doesn't declare is an error. Add `metadata :foo, :string` to the action.
- **After hook with no records.** An `after_action` gets an empty list when nothing matched; map over it, don't pattern-match one user.
- **Hooks run once per query.** A `get?` action returns one record, but the hook still receives a list.
- **Side effects in `after_action`.** `IssueRefreshToken` inserts a row. If a later step fails the query, that row stays. For all-or-nothing work use a transaction, or issue after everything else has succeeded.
- **Secrets in metadata.** Everything in `__metadata__` can reach the response. Never log it.
- **Order.** `prepare` lines run top to bottom; put `IssueRefreshToken` after the preparation that authenticates.

## 8. Try it

1. Read `server/test/ex_web/api/refresh_test.exs`, then sign in and refresh with curl or Scalar (`/api/docs`).
2. In `iex -S mix`, run an action without HTTP:

```elixir
Ex.Accounts.User
|> Ash.Query.for_read(:sign_in_with_password, %{email: "admin@gmail.com", password: "12345678"})
|> Ash.read_one!(authorize?: false)
|> Map.get(:__metadata__)
```

3. Exercise: write a preparation `StampLastSeen` that, after a successful sign-in, records the time on the user. Decide: before or after hook? attribute or metadata? (Answer: after, and an attribute, because it must be stored.)

## Further reading

- Ash guides: *Preparations*, *Changes*, *Actions: read* (hexdocs.pm/ash)
- AshAuthentication: `SignInPreparation` in `server/deps/ash_authentication/lib/ash_authentication/strategies/password/sign_in_preparation.ex`
- This project: `docs/adr/` for design decisions, `docs/schema.md` for the data model.
