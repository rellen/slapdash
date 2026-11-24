defmodule Slapdash.Tenancy do
  @moduledoc """
  Tenants and who belongs to them.

  Each tenant gets its own PostgreSQL schema (`tenant_<slug>`), created with
  the tenant, for resources that use `multitenancy strategy :context`. The
  tenant registry and memberships live in the `public` schema, so Slapdash
  can list a user's tenants without visiting every schema.
  """
  use Ash.Domain,
    otp_app: :slapdash

  resources do
    resource Slapdash.Tenancy.Tenant do
      define :create_tenant, action: :create, args: [:name, :slug]
      define :rename_tenant, action: :rename, args: [:name]
      define :list_tenants, action: :read
      define :get_tenant_by_slug, action: :read, get_by: [:slug]
    end

    resource Slapdash.Tenancy.Membership do
      define :add_member, action: :add, args: [:tenant_id, :email, :role]
      define :change_member_role, action: :change_role, args: [:role]
      define :remove_member, action: :remove
      define :list_memberships, action: :read
    end
  end
end
