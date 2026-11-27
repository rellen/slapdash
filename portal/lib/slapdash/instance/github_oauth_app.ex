defmodule Slapdash.Instance.GitHubOAuthApp do
  @moduledoc """
  The GitHub OAuth app used for "Sign in with GitHub". There is at most one.

  Until root configures it, the sign-in page does not offer GitHub. The
  client secret is encrypted with the master key and is never shown again
  after it is saved; leaving it blank when reconfiguring keeps the old one.
  `Slapdash.Secrets` hands these values to AshAuthentication.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Instance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak, Slapdash.Authz.Resource, AshPaperTrail.Resource]

  authz do
    resource_name("github_oauth_app")
  end

  cloak do
    vault Slapdash.Vault
    attributes [:client_secret]
    encrypt_nil? false
  end

  postgres do
    table "github_oauth_app"
    repo Slapdash.Repo

    check_constraints do
      check_constraint :id, "github_oauth_app_singleton", check: "id = 1"
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["github_oauth_app_version"]}

    version_extensions authorizers: [Ash.Policy.Authorizer],
                       extensions: [Slapdash.Authz.Resource]

    belongs_to_actor :actor, Slapdash.Accounts.User,
      domain: Slapdash.Accounts,
      on_delete: :nilify

    store_action_name? true
    reference_source? false
    sensitive_attributes :ignore
    ignore_attributes [:encrypted_client_secret, :inserted_at, :updated_at]
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
      change {Slapdash.Instance.Changes.KeepSecretWhenBlank, argument: :client_secret}
    end

    destroy :remove
  end

  policies do
    policy action_type(:read) do
      authorize_if Slapdash.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Slapdash.Authz.Check
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
