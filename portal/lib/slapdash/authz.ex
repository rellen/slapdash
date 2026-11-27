defmodule Slapdash.Authz do
  @moduledoc """
  Slapdash's permission scheme, in the spirit of ash_grant but our own.

  An actor's roles resolve to *grants*: permission strings
  (`Slapdash.Authz.Permission`), each either install-wide or bound to one
  tenant. A resource opts in with the `authz` DSL section
  (`Slapdash.Authz.Resource`) and authorizes with
  `Slapdash.Authz.FilterCheck` (reads) and `Slapdash.Authz.Check`
  (creates, updates and destroys).

  For a resource and action, the grants that match become one filter:

      (allow_1 or allow_2 or ...) and not (deny_1 or deny_2 or ...)

  Each grant contributes its scope's filter. A tenant-bound grant (from a
  `Slapdash.Tenancy.Membership`) is further limited to its tenant:

  - on a `multitenancy strategy :context` resource, it applies only when the
    query runs in that tenant's schema;
  - on a public-schema resource with a `tenant_attribute`, it applies only to
    rows whose attribute is that tenant's id;
  - on any other resource, it does not apply.

  So a tenant role can never reach another tenant's data, whatever its
  permission strings say. Root's grants are install-wide.

  The role definitions are in `Slapdash.Authz.Roles`.
  """

  # Domains use the authz DSL at compile time, so this boundary must not
  # declare a dependency on them. `grants/1` reads users and memberships at
  # run time. These references are known exceptions until they move.
  use Boundary,
    top_level?: true,
    deps: [],
    exports: [Check, FilterCheck, Resource, Roles],
    dirty_xrefs: [Slapdash.Accounts.User, Slapdash.Tenancy.Membership]

  require Ash.Expr
  require Ash.Query

  alias Slapdash.Accounts.User
  alias Slapdash.Authz.{Grant, Permission, Resource, Roles}

  @doc """
  The grants an actor holds.

  Memberships are read from the actor when they are loaded (with their
  tenants), and from the database otherwise.
  """
  @spec grants(term()) :: [Grant.t()]
  def grants(%User{} = user) do
    install_wide =
      if(user.root, do: [:root, :signed_in], else: [:signed_in])
      |> Enum.flat_map(&Roles.permissions/1)
      |> Enum.map(&%Grant{permission: Permission.parse!(&1), tenant: nil})

    per_tenant =
      for membership <- memberships(user),
          permission <- Roles.permissions(membership.role) do
        %Grant{
          permission: Permission.parse!(permission),
          tenant: %{id: membership.tenant.id, schema: membership.tenant.schema}
        }
      end

    install_wide ++ per_tenant
  end

  def grants(_actor), do: []

  defp memberships(%User{memberships: memberships}) when is_list(memberships) do
    if Enum.all?(memberships, &match?(%{tenant: %{id: _}}, &1)),
      do: memberships,
      else: Ash.load!(memberships, :tenant, authorize?: false)
  end

  defp memberships(%User{id: id}) do
    Slapdash.Tenancy.Membership
    |> Ash.Query.filter(user_id == ^id)
    |> Ash.Query.load(:tenant)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  The filter an actor's grants allow for an action on a resource, given the
  tenant the action runs in. Returns `true`, `false` or an Ash expression.
  """
  @spec filter(term(), Ash.Resource.t(), %{name: atom()}, term()) :: boolean() | Ash.Expr.t()
  def filter(actor, resource, action, tenant) do
    name = Resource.resource_name(resource)
    schema = schema(resource, tenant)

    {denies, allows} =
      actor
      |> grants()
      |> Enum.filter(&Permission.matches?(&1.permission, name, action))
      |> Enum.split_with(& &1.permission.deny?)

    allow = any(Enum.map(allows, &grant_filter(&1, resource, schema)))
    deny = any(Enum.map(denies, &grant_filter(&1, resource, schema)))

    case {allow, deny} do
      {false, _} -> false
      {allow, false} -> allow
      {_, true} -> false
      {allow, deny} -> Ash.Expr.expr(^allow and not (^deny))
    end
  end

  defp grant_filter(%Grant{permission: permission, tenant: tenant}, resource, schema) do
    scope = Resource.scope_filter(resource, permission.scope)

    cond do
      # A permission naming a scope the resource does not declare grants nothing.
      is_nil(scope) ->
        false

      is_nil(tenant) ->
        scope

      context_multitenant?(resource) ->
        if schema == tenant.schema, do: scope, else: false

      attribute = Resource.tenant_attribute(resource) ->
        tenant_id = tenant.id
        both(Ash.Expr.expr(^Ash.Expr.ref(attribute) == ^tenant_id), scope)

      true ->
        false
    end
  end

  defp schema(resource, tenant) do
    if context_multitenant?(resource) and not is_nil(tenant),
      do: Ash.ToTenant.to_tenant(tenant, resource)
  end

  defp context_multitenant?(resource) do
    Ash.Resource.Info.multitenancy_strategy(resource) == :context
  end

  defp both(left, true), do: left
  defp both(_left, false), do: false
  defp both(left, right), do: Ash.Expr.expr(^left and ^right)

  defp any(filters) do
    filters
    |> Enum.reject(&(&1 == false))
    |> Enum.reduce_while(false, fn
      true, _acc -> {:halt, true}
      filter, false -> {:cont, filter}
      filter, acc -> {:cont, Ash.Expr.expr(^acc or ^filter)}
    end)
  end
end
