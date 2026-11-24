defmodule Ramshackle.Tenancy.Membership do
  @moduledoc """
  A user's role in one tenant: `:administrator` or `:engineer` (see
  `Ramshackle.Authz.Roles`). A user has at most one membership per tenant.

  Adding a member is how a person is invited: sign-in is by invitation only,
  so this is the only place, apart from `Ramshackle.Release.create_root/2`,
  that creates users. Adding a member by email creates the user if needed;
  they can then sign in with a magic link or GitHub using that address.
  """
  use Ash.Resource,
    otp_app: :ramshackle,
    domain: Ramshackle.Tenancy,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Ramshackle.Authz.Resource]

  authz do
    tenant_attribute(:tenant_id)
    scope(:own, expr(user_id == ^actor(:id)))
  end

  postgres do
    table "memberships"
    repo Ramshackle.Repo

    references do
      reference :tenant, on_delete: :delete
      reference :user, on_delete: :delete
    end

    custom_indexes do
      # Resolving a user's grants looks up their memberships by user.
      index [:user_id]
    end
  end

  actions do
    defaults [:read]

    create :add do
      description "Give a person, by email, a role in a tenant."
      accept [:tenant_id, :role]

      argument :email, :ci_string do
        allow_nil? false
      end

      validate match(:email, ~r/\A[^@\s]+@[^@\s]+\z/), message: "must be an email address"
      change Ramshackle.Tenancy.Membership.Changes.SetUserByEmail
    end

    update :change_role do
      accept [:role]
    end

    destroy :remove
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

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:administrator, :engineer]
    end

    timestamps()
  end

  relationships do
    belongs_to :tenant, Ramshackle.Tenancy.Tenant do
      allow_nil? false
      public? true
    end

    belongs_to :user, Ramshackle.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_role_per_tenant, [:tenant_id, :user_id] do
      message "already belongs to this tenant"
    end
  end
end
