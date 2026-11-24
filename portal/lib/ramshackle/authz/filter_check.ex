defmodule Ramshackle.Authz.FilterCheck do
  @moduledoc """
  Authorizes reads by filtering to the rows the actor's grants reach. See
  `Ramshackle.Authz`.

      policy action_type(:read) do
        authorize_if Ramshackle.Authz.FilterCheck
      end
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "the actor holds a permission that reaches the record"

  @impl true
  def filter(actor, %{resource: resource, action: action} = authorizer, _opts) do
    Ramshackle.Authz.filter(actor, resource, action, tenant(authorizer))
  end

  defp tenant(%{subject: %{tenant: tenant}}), do: tenant
  defp tenant(_authorizer), do: nil
end
