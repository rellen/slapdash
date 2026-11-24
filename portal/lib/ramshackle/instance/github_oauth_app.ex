defmodule Ramshackle.Instance.GitHubOAuthApp do
  @moduledoc """
  The GitHub OAuth app used for "Sign in with GitHub". There is at most one.

  Until root configures it, the sign-in page does not offer GitHub. The
  client secret is encrypted with the master key and is never shown again
  after it is saved; leaving it blank when reconfiguring keeps the old one.
  `Ramshackle.Secrets` hands these values to AshAuthentication.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak, Ramshackle.Authz.Resource]

  authz do
    resource_name("github_oauth_app")
  end

  cloak do
    vault Ramshackle.Vault
    attributes [:client_secret]
    encrypt_nil? false
  end

  postgres do
    table "github_oauth_app"
    repo Ramshackle.Repo

    check_constraints do
      check_constraint :id, "github_oauth_app_singleton", check: "id = 1"
    end
  end

  actions do
    defaults [:read]

    read :current do
      get? true
      filter expr(id == 1)
    end

    create :configure do
      accept [:client_id, :client_secret]
      validate present(:client_secret), message: "is required"
    end

    update :reconfigure do
      accept [:client_id, :client_secret]
      require_atomic? false
      change {Ramshackle.Instance.Changes.KeepSecretWhenBlank, argument: :client_secret}
    end

    destroy :remove
  end

  policies do
    policy action_type(:read) do
      authorize_if Ramshackle.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Ramshackle.Authz.Check
    end
  end

  attributes do
    attribute :id, :integer do
      primary_key? true
      allow_nil? false
      default 1
      writable? false
      public? true
    end

    attribute :client_id, :string do
      allow_nil? false
      public? true
    end

    attribute :client_secret, :string do
      sensitive? true
      public? true
    end

    timestamps()
  end
end
