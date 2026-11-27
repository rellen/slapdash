defmodule Slapdash.Connections.Connection do
  @moduledoc """
  A tenant's connection to an outside service, of the kind its `provider`
  names (see `Slapdash.Connections.Provider`).

  `config` holds the provider's plain settings and `secrets` holds its
  secrets, encrypted with `Slapdash.Vault`. Nobody can read `secrets`
  through an action; provider code reads them with
  `Slapdash.Connections.secrets/1`. A blank secret in a reconfigure keeps
  the stored value.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Connections,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak, Slapdash.Authz.Resource, AshPaperTrail.Resource]

  @type t :: %__MODULE__{}

  authz do
    tenant_attribute(:tenant_id)
  end

  cloak do
    vault Slapdash.Vault
    attributes [:secrets]
    encrypt_nil? false
  end

  field_policies do
    # Secrets leave the database only through Slapdash.Connections.secrets/1.
    field_policy :secrets do
      forbid_if always()
    end

    field_policy :* do
      authorize_if always()
    end
  end

  postgres do
    table "connections"
    repo Slapdash.Repo

    references do
      # A tenant is never destroyed yet. When it is, its connections go too.
      reference :tenant, on_delete: :delete
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["connection_version"]}

    version_extensions authorizers: [Ash.Policy.Authorizer],
                       extensions: [Slapdash.Authz.Resource]

    belongs_to_actor :actor, Slapdash.Accounts.User,
      domain: Slapdash.Accounts,
      on_delete: :nilify

    store_action_name? true
    reference_source? false
    sensitive_attributes :ignore
    ignore_attributes [:encrypted_secrets, :inserted_at, :updated_at]
  end

  actions do
    defaults [:read]

    create :add do
      description "Connect a tenant to an outside service."
      accept [:tenant_id, :name, :provider, :config, :secrets]
      change Slapdash.Connections.Changes.ApplyProvider
    end

    update :reconfigure do
      description "Change the name, settings or secrets. A blank secret keeps the stored one."
      accept [:name, :config, :secrets]
      require_atomic? false
      change Slapdash.Connections.Changes.ApplyProvider
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
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 120
    end

    attribute :provider, :string do
      description "The key of a registered Slapdash.Connections.Provider"
      allow_nil? false
      public? true
    end

    attribute :config, :map do
      description "The provider's plain settings"
      allow_nil? false
      default %{}
      public? true
    end

    attribute :secrets, :map do
      description "The provider's secrets, encrypted at rest"
      sensitive? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Slapdash.Tenancy.Tenant do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_name_per_tenant, [:tenant_id, :name] do
      message "is already used in this tenant"
    end
  end
end
