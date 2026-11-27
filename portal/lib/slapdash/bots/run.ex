defmodule Slapdash.Bots.Run do
  @moduledoc """
  One reaction of one enrolled bot to one event: what triggered it, where it
  ran, what it did and how it ended.

  A run starts `:queued`. Its runner moves it to `:running`, and then to
  `:succeeded` or `:failed`. A failed run can run again on a retry. A bot
  has at most one run for each event id on an enrollment, so a repeated
  webhook does not start a second run.

  Runs are written by Slapdash itself. People can only read them.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Bots,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource]

  @type t :: %__MODULE__{}

  authz do
    resource_name("run")
  end

  postgres do
    table "runs"
    repo Slapdash.Repo

    references do
      # Turning a bot off keeps its run history.
      reference :enrollment, on_delete: :nilify
    end

    custom_indexes do
      # The runs page lists the latest runs first.
      index [:inserted_at]
    end
  end

  actions do
    defaults [:read]

    create :start do
      description "Record a queued run, or return the run that already exists for this event."
      accept [:enrollment_id, :repository_id, :bot, :event_id, :event, :runner]
      upsert? true
      upsert_identity :one_per_event
      # Keep the existing run as it is.
      upsert_fields []
    end

    update :begin do
      change set_attribute(:status, :running)
      change set_attribute(:error, nil)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change atomic_update(:attempts, expr(attempts + 1))
    end

    update :succeed do
      accept [:actions]
      change set_attribute(:status, :succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error]
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Slapdash.Authz.FilterCheck
    end

    # Only Slapdash writes runs, with authorization off.
    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :bot, :string do
      allow_nil? false
      public? true
    end

    attribute :repository_id, :uuid do
      description "The repository the event was on. It is in the public schema."
      allow_nil? false
      public? true
    end

    attribute :event_id, :string do
      description "The id of the event that started the run"
      allow_nil? false
      public? true
    end

    attribute :event, :map do
      description "The event, as Slapdash.Bots.Event.dump/1 made it"
      allow_nil? false
      public? true
    end

    attribute :runner, :string do
      description "The runner module that the run was given to"
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :queued
      public? true
      constraints one_of: [:queued, :running, :succeeded, :failed]
    end

    attribute :attempts, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :actions, {:array, :map} do
      description "A summary of each action the run performed"
      allow_nil? false
      default []
      public? true
    end

    attribute :error, :string do
      description "Why the last attempt failed. It never contains secrets."
      public? true
    end

    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :finished_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, Slapdash.Bots.Enrollment do
      description "The enrollment that started the run. It is nil after the bot is turned off."
      public? true
    end
  end

  identities do
    identity :one_per_event, [:enrollment_id, :event_id]
  end
end
