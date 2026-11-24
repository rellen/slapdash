defmodule Ramshackle.Tenancy.Tenant do
  @moduledoc """
  A tenant: an isolated part of one Ramshackle install, with its own
  PostgreSQL schema.

  Creating a tenant creates the schema `tenant_<slug>` and runs the tenant
  migrations in it (`priv/repo/tenant_migrations`). The slug, and so the
  schema, never change. Pass a tenant as `tenant:` to actions on resources
  that use `multitenancy strategy :context`; `Ash.ToTenant` turns it into
  the schema name.

  There is no destroy action yet: dropping a schema loses data for good, so
  it needs its own careful flow.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Tenancy,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Ramshackle.Authz.Resource]

  defimpl Ash.ToTenant do
    def to_tenant(%{schema: schema, id: id}, resource) do
      if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
        schema
      else
        id
      end
    end
  end

  authz do
    tenant_attribute(:id)
  end

  postgres do
    table "tenants"
    repo Ramshackle.Repo

    manage_tenant do
      template [:schema]
      create? true
      update? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :slug]

      validate match(:slug, ~r/\A[a-z][a-z0-9_]{0,39}\z/) do
        message "must start with a letter and use only lowercase letters, digits and underscores, up to 40 characters"
      end

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :slug) do
          slug when is_binary(slug) ->
            Ash.Changeset.force_change_attribute(changeset, :schema, "tenant_" <> slug)

          _ ->
            changeset
        end
      end
    end

    update :rename do
      accept [:name]
    end
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
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 120
    end

    attribute :slug, :string do
      description "Short, permanent name used in URLs and in the schema name"
      allow_nil? false
      public? true
    end

    attribute :schema, :string do
      description "The PostgreSQL schema holding this tenant's data"
      allow_nil? false
      public? true
      writable? false
    end

    timestamps()
  end

  relationships do
    has_many :memberships, Ramshackle.Tenancy.Membership do
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
