defmodule Ramshackle.Accounts.User do
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, Ramshackle.Authz.Resource]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Ramshackle.Accounts.Token
      signing_secret Ramshackle.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      # Sign-in is by invitation only: a user exists only after root or a
      # tenant administrator adds them (see `Ramshackle.Accounts.ensure_user/1`).
      # A sign-in link request for an unknown email sends nothing, and the
      # response does not show whether the email has an account.
      magic_link do
        identity_field :email
        registration_enabled? false
        require_interaction? true

        sender Ramshackle.Accounts.User.Senders.SendMagicLinkEmail
      end

      github do
        client_id Ramshackle.Secrets
        client_secret Ramshackle.Secrets
        redirect_uri Ramshackle.Secrets
        identity_resource Ramshackle.Accounts.UserIdentity
        registration_enabled? false
        # GitHub's `email_verified` claim is trusted only to link a first
        # GitHub sign-in to the invited user with the same email.
        trust_email_verified? true
      end

      remember_me :remember_me
    end
  end

  authz do
    scope(:own, expr(id == ^actor(:id)))

    # People who share a tenant with the actor, so members can see who else
    # belongs.
    scope(:colleague, expr(exists(memberships.tenant.memberships, user_id == ^actor(:id))))
  end

  postgres do
    table "users"
    repo Ramshackle.Repo
  end

  actions do
    defaults [:read]

    create :create_by_email do
      description "Create a user who has not signed in yet, so they can be given roles."
      accept [:email]
    end

    update :make_root do
      description "Make the user root. Only reachable from the console, see Ramshackle.Release."
      accept []
      change set_attribute(:root, true)
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    read :sign_in_with_magic_link do
      description "Sign in an existing user with a magic link."
      get? true

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      prepare AshAuthentication.Strategy.MagicLink.SignInPreparation

      prepare {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenPreparation,
               strategy_name: :remember_me}

      metadata :token, :string do
        allow_nil? false
      end
    end

    read :sign_in_with_github do
      description "Sign in an existing user with GitHub."

      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true

      prepare Ramshackle.Accounts.User.Preparations.MatchGithubUser
      prepare AshAuthentication.Strategy.OAuth2.SignInPreparation
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Ramshackle.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Ramshackle.Authz.Check
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :root, :boolean do
      description "Root can do everything, install-wide. Granted from the console only."
      allow_nil? false
      default false
      public? true
    end
  end

  relationships do
    has_many :memberships, Ramshackle.Tenancy.Membership do
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
