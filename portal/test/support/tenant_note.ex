defmodule Slapdash.Test.TenantNote do
  @moduledoc """
  A test-only resource stored per tenant (`multitenancy strategy :context`)
  in ETS, so the authorization of tenant data can be tested without a
  tenant migration.
  """
  use Ash.Resource,
    domain: Slapdash.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource, AshPaperTrail.Resource]

  ets do
    private? false
  end

  authz do
    resource_name("tenant_note")
    scope(:own, expr(author_id == ^actor(:id)))
  end

  # Shows that versions of a `:context` resource stay in the tenant.
  paper_trail do
    belongs_to_actor :actor, Slapdash.Accounts.User, domain: Slapdash.Accounts
  end

  actions do
    defaults [:read, :destroy, create: [:body, :author_id]]
  end

  policies do
    policy action_type(:read) do
      authorize_if Slapdash.Authz.FilterCheck
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Slapdash.Authz.Check
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :author_id, :uuid, public?: true
  end
end
