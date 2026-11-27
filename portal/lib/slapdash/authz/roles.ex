defmodule Slapdash.Authz.Roles do
  @moduledoc """
  What each role may do, as permission strings (see
  `Slapdash.Authz.Permission`).

  - **root** is install-wide and held by users with `root: true`. It can do
    everything, in every tenant.
  - **administrator** and **engineer** are held per tenant, through
    `Slapdash.Tenancy.Membership`. Their permissions only ever reach that
    tenant's data: rows in the tenant's schema, or public-schema rows whose
    tenant attribute points at the tenant. See `Slapdash.Authz`.
  - Every signed-in user also gets the `signed_in` permissions, which are
    install-wide but limited to their own rows by scope.

  Roles live in code, not the database, so they change through review. A
  role that needs a new permission gets it here.
  """

  @roles %{
    root: ["*:*:*:always"],
    # Everything, but only ever inside their own tenant: see Slapdash.Authz.
    administrator: ["*:*:*:always"],
    engineer: [
      "tenant:*:read:always",
      "membership:*:read:always",
      "connection:*:read:always",
      "repository:*:read:always",
      "enrollment:*:read:always",
      "run:*:read:always",
      "delivery:*:read:always"
    ],
    signed_in: [
      "user:*:read:own",
      "user:*:read:colleague",
      "membership:*:read:own"
    ]
  }

  @tenant_roles [:administrator, :engineer]

  @doc "The roles a membership can hold in a tenant."
  @spec tenant_roles() :: [atom()]
  def tenant_roles, do: @tenant_roles

  @doc "The permission strings for a role."
  @spec permissions(atom()) :: [String.t()]
  def permissions(role), do: Map.fetch!(@roles, role)

  @doc "A short, human description of a tenant role, for the UI."
  @spec describe(atom()) :: String.t()
  def describe(:administrator), do: "Administrator: manages the tenant and its members"
  def describe(:engineer), do: "Engineer: works in the tenant"
end
