defmodule Ramshackle.Authz.Permission do
  @moduledoc """
  A parsed permission string: `[!]resource:instance:action:scope`.

  The format follows ash_grant's, so a later move to that library is
  mostly mechanical:

  - `!` in front makes it a deny. A matching deny always wins over allows.
  - `resource` is a resource's `authz` name, such as `membership`, or `*`.
  - `instance` is reserved for per-record grants. Only `*` (every record)
    is supported today; anything else raises.
  - `action` is an action name, `*`, or a prefix ending in `*`, such as
    `reconfigure*`.
  - `scope` names a row filter declared in the resource's `authz` block.
    `always` (no filter) is built in.

  For example `membership:*:read:always` reads every membership the grant
  reaches, and `!tenant:*:*:always` denies everything on tenants.
  """

  @enforce_keys [:resource, :action, :scope]
  defstruct deny?: false, resource: "*", instance: "*", action: "*", scope: "always", source: nil

  @type t :: %__MODULE__{
          deny?: boolean(),
          resource: String.t(),
          instance: String.t(),
          action: String.t(),
          scope: String.t(),
          source: String.t()
        }

  @doc "Parses a permission string, raising on a malformed one."
  @spec parse!(String.t()) :: t()
  def parse!(string) when is_binary(string) do
    {deny?, body} =
      case string do
        "!" <> rest -> {true, rest}
        rest -> {false, rest}
      end

    case String.split(body, ":") do
      [resource, "*", action, scope]
      when resource != "" and action != "" and scope != "" ->
        %__MODULE__{
          deny?: deny?,
          resource: resource,
          action: action,
          scope: scope,
          source: string
        }

      [_resource, instance, _action, _scope] ->
        raise ArgumentError,
              "per-record permissions are not supported yet: #{inspect(string)} names instance #{inspect(instance)}"

      _ ->
        raise ArgumentError,
              "malformed permission #{inspect(string)}, expected [!]resource:instance:action:scope"
    end
  end

  @doc "Whether the permission covers this resource name and action."
  @spec matches?(t(), String.t(), %{name: atom()}) :: boolean()
  def matches?(%__MODULE__{} = permission, resource_name, %{name: action_name}) do
    segment_matches?(permission.resource, resource_name) and
      segment_matches?(permission.action, Atom.to_string(action_name))
  end

  defp segment_matches?("*", _value), do: true

  defp segment_matches?(pattern, value) do
    if String.ends_with?(pattern, "*") do
      String.starts_with?(value, String.trim_trailing(pattern, "*"))
    else
      pattern == value
    end
  end
end
