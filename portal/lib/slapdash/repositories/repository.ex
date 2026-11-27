defmodule Slapdash.Repositories.Repository do
  @moduledoc """
  A code repository that a tenant has added, reached through one of the
  tenant's connections. Its `path` is the provider's name for the
  repository (see `Slapdash.Repositories.Host`). A connection has each
  path at most once.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Repositories,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource, AshPaperTrail.Resource]

  @type t :: %__MODULE__{}

  authz do
    tenant_attribute(:tenant_id)
  end

  postgres do
    table "repositories"
    repo Slapdash.Repo

    references do
      reference :tenant, on_delete: :delete
      # Removing a connection removes the repositories reached through it.
      reference :connection, on_delete: :delete
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["repository_version"]}

    version_extensions authorizers: [Ash.Policy.Authorizer],
                       extensions: [Slapdash.Authz.Resource]

    belongs_to_actor :actor, Slapdash.Accounts.User,
      domain: Slapdash.Accounts,
      on_delete: :nilify

    store_action_name? true
    reference_source? false
    sensitive_attributes :ignore
    ignore_attributes [:inserted_at, :updated_at]
  end

  actions do
    defaults [:read]

    read :by_path do
      description "The repository with this path on a connection."
      argument :connection_id, :uuid, allow_nil?: false
      argument :path, :ci_string, allow_nil?: false
      get? true
      filter expr(connection_id == ^arg(:connection_id) and path == ^arg(:path))
    end

    create :add do
      description "Add a repository to a tenant, through one of its connections."
      accept [:tenant_id, :connection_id, :path]
      change Slapdash.Repositories.Changes.CheckHost
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

    attribute :path, :ci_string do
      description "The provider's name for the repository, such as owner/name"
      allow_nil? false
      public? true
      constraints max_length: 255
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Slapdash.Tenancy.Tenant do
      allow_nil? false
      public? true
    end

    belongs_to :connection, Slapdash.Connections.Connection do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_path_per_connection, [:connection_id, :path] do
      message "is already added"
    end
  end
end
