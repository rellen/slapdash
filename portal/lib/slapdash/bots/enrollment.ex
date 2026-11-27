defmodule Slapdash.Bots.Enrollment do
  @moduledoc """
  A bot turned on for one repository of the tenant. A repository has each
  bot at most once. `settings` is a map that the bot reads from its
  context; its meaning is up to the bot.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Bots,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource, AshPaperTrail.Resource]

  authz do
    resource_name("enrollment")
  end

  postgres do
    table "enrollments"
    repo Slapdash.Repo

    references do
      # Repositories are in the public schema. A foreign key from a tenant
      # table to a public table makes each tenant migration lock that table,
      # so there is none. Slapdash.Bots.dispatch/2 finds enrollments by
      # repository, so an enrollment of a removed repository does nothing.
      reference :repository, ignore?: true
    end
  end

  paper_trail do
    mixin {Slapdash.Versions, :mixin, ["enrollment_version", [tenant?: true]]}

    version_extensions authorizers: [Ash.Policy.Authorizer],
                       extensions: [Slapdash.Authz.Resource]

    belongs_to_actor :actor, Slapdash.Accounts.User,
      domain: Slapdash.Accounts,
      define_attribute?: false

    store_action_name? true
    reference_source? false
    sensitive_attributes :ignore
    ignore_attributes [:inserted_at, :updated_at]
  end

  actions do
    defaults [:read]

    create :enroll do
      description "Turn a bot on for a repository."
      accept [:repository_id, :bot, :settings]
      change Slapdash.Bots.Changes.CheckEnrollment
    end

    destroy :unenroll do
      description "Turn a bot off for a repository."
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

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :bot, :string do
      description "The key of a bot in Slapdash.Bots.Catalogue"
      allow_nil? false
      public? true
    end

    attribute :settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :repository, Slapdash.Repositories.Repository do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_bot_and_repository, [:repository_id, :bot] do
      message "is already on for this repository"
    end
  end
end
