defmodule Ramshackle.Authz.Resource do
  @moduledoc """
  The `authz` DSL section, which names a resource for permission strings and
  declares its scopes.

      authz do
        resource_name "membership"
        tenant_attribute :tenant_id
        scope :own, expr(user_id == ^actor(:id))
      end

  - `resource_name` is the first segment of permission strings. It defaults
    to the module's last segment in snake case (`Membership` → `membership`).
  - `tenant_attribute` is for public-schema resources that belong to a
    tenant by a foreign key. A tenant role's permission only reaches rows
    whose attribute equals that tenant's id. Resources using
    `multitenancy strategy :context` need no attribute: a tenant role's
    permission reaches them only when the query runs in that tenant.
  - `scope` declares a named row filter. `always` is built in.

  Then authorize with the checks:

      policies do
        policy action_type(:read) do
          authorize_if Ramshackle.Authz.FilterCheck
        end

        policy action_type([:create, :update, :destroy]) do
          authorize_if Ramshackle.Authz.Check
        end
      end
  """

  @scope %Spark.Dsl.Entity{
    name: :scope,
    describe: "A named row filter that permission strings can refer to.",
    target: Ramshackle.Authz.Resource.Scope,
    args: [:name, :filter],
    schema: [
      name: [type: :atom, required: true, doc: "The scope's name, as used in permission strings."],
      filter: [type: :any, required: true, doc: "An Ash expression, or a boolean."]
    ]
  }

  @authz %Spark.Dsl.Section{
    name: :authz,
    describe: "How `Ramshackle.Authz` names this resource and filters its rows.",
    imports: [Ash.Expr],
    entities: [@scope],
    schema: [
      resource_name: [
        type: :string,
        doc: "The resource segment of permission strings."
      ],
      tenant_attribute: [
        type: :atom,
        doc: "For public-schema resources: the attribute holding the owning tenant's id."
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@authz]

  @doc "The name permission strings use for a resource."
  @spec resource_name(Ash.Resource.t()) :: String.t()
  def resource_name(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:authz], :resource_name, nil) ||
      resource |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc "The attribute tying a public-schema row to a tenant, if any."
  @spec tenant_attribute(Ash.Resource.t()) :: atom() | nil
  def tenant_attribute(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:authz], :tenant_attribute, nil)
  end

  @doc "The filter for a named scope, or `nil` if the resource does not declare it."
  @spec scope_filter(Ash.Resource.t(), String.t()) :: term() | nil
  def scope_filter(_resource, "always"), do: true

  def scope_filter(resource, name) do
    resource
    |> Spark.Dsl.Extension.get_entities([:authz])
    |> Enum.find_value(fn %Ramshackle.Authz.Resource.Scope{name: scope, filter: filter} ->
      if Atom.to_string(scope) == name, do: filter
    end)
  end
end
