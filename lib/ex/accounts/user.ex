defmodule Ex.Accounts.User do
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshJsonApi.Resource]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Ex.Accounts.Token
      signing_secret Ex.Secrets
      # Short, because clients renew it with a refresh token (Ex.Accounts.RefreshTokens).
      token_lifetime {1, :hours}
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider
      end

      remember_me :remember_me
    end
  end

  postgres do
    table "users"
    repo Ex.Repo

    references do
      reference :station, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :station_id, "station_matches_role",
        check:
          "(role = 'admin' AND station_id IS NULL) OR (role <> 'admin' AND station_id IS NOT NULL)",
        message: "Admin has no Station; Station Staff and Supervisor need one"

      check_constraint :role, "role_values",
        check: "role IN ('staff', 'supervisor', 'admin')",
        message: "unknown role"
    end
  end

  json_api do
    type "user"
    default_fields [:email, :role, :station_id, :inserted_at, :permissions]

    routes do
      base "/users"

      index :read do
        description "Lists users. Needs the `user.manage` permission."
      end

      get :read do
        description "Gets one user by id."
      end

      post :register_with_password do
        route "/"

        description "Creates a user with a role (and a Station for staff and supervisors). Needs `user.manage`."
      end

      patch :update_assignment do
        description "Changes a user's role and Station. The change is recorded in the assignment log."
      end

      post :sign_in_with_password do
        route "/sign-in"

        description """
        Signs in with email and password. Public.

        Returns `meta.token` (access token, valid 1 hour) and `meta.refresh_token` (single use, 30 days).
        Send the access token as `Authorization: Bearer <token>`.
        """

        metadata fn _subject, user, _request ->
          %{token: user.__metadata__.token, refresh_token: user.__metadata__.refresh_token}
        end
      end

      post :refresh do
        route "/refresh"

        description """
        Exchanges a refresh token for a new access token and a new refresh token. Public.

        Each refresh token works once. Presenting one a second time revokes the whole session.
        """

        metadata fn _subject, user, _request ->
          %{token: user.__metadata__.token, refresh_token: user.__metadata__.refresh_token}
        end
      end
    end
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
      prepare build(load: [:permissions])
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      prepare Ex.Accounts.User.Preparations.IssueRefreshToken

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end

      metadata :refresh_token, :string do
        description "A single-use secret to exchange for a new token via /users/refresh."
        allow_nil? false
      end
    end

    read :refresh do
      description "Exchange a refresh token for a new access token and a new refresh token."
      get? true

      argument :refresh_token, :string do
        allow_nil? false
        sensitive? true
      end

      prepare Ex.Accounts.User.Preparations.RefreshSession

      metadata :token, :string, allow_nil?: false
      metadata :refresh_token, :string, allow_nil?: false
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Create a user with an email, password, role and Station. Admin only."
      accept [:role, :station_id]

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      validate Ex.Accounts.User.Validations.StationMatchesRole
      change Ex.Accounts.User.Changes.RecordAssignment

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    update :update_assignment do
      description "Change a user's role and Station. Admin only."
      accept [:role, :station_id]
      require_atomic? false

      validate Ex.Accounts.User.Validations.StationMatchesRole
      change Ex.Accounts.User.Changes.RecordAssignment
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # The action itself checks the password; anyone may attempt to sign in.
    policy action([:sign_in_with_password, :refresh]) do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"user.manage"}
      authorize_if expr(id == ^actor(:id))
    end

    policy action([:register_with_password, :update_assignment]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"user.manage"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    # Required, no default: every user must be given a role on purpose.
    attribute :role, Ex.Accounts.Role, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :station, Ex.Network.Station, public?: true
  end

  calculations do
    # Role defaults, minus Station-bound Permissions for a user with no Station.
    calculate :permissions,
              {:array, :string},
              expr(
                fragment(
                  "ARRAY(SELECT p.name FROM permissions p WHERE (NOT p.station_bound OR ? IS NOT NULL) AND EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role = ? AND rp.permission = p.name) ORDER BY p.name)",
                  station_id,
                  role
                )
              ),
              public?: true
  end

  identities do
    identity :unique_email, [:email]
  end
end
