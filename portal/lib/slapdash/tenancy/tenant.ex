defmodule Slapdash.Tenancy.Tenant do
  @moduledoc """
  A tenant: an isolated part of one Slapdash install, with its own
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
    otp_app: :slapdash,
    domain: Slapdash.Tenancy,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource, AshPaperTrail.Resource]

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
    repo Slapdash.Repo

    manage_tenant do
      template [:schema]
      create? true
      update? false
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["tenant_version"]}

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

    create :create do
      accept [:name, :slug]

      validate match(:slug, ~r/\A[a-z][a-z0-9_]{0,39}\z/) do
        message "must start with a letter and use only lowercase letters, digits and underscores, up to 40 characters"
      end

      # Tenant pages are at /<slug>/..., after the other routes, and a
      # subdomain such as www has a meaning of its own.
      validate {Slapdash.Tenancy.Validations.NotReserved, attribute: :slug}

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
    has_many :memberships, Slapdash.Tenancy.Membership do
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
