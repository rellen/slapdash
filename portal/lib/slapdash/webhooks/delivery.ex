defmodule Slapdash.Webhooks.Delivery do
  @moduledoc """
  One webhook request that a connection received, as the service sent it.

  A delivery starts `:received`. `Slapdash.Webhooks.ProcessDelivery` moves
  it to `:processed` when it gave events to bots, to `:ignored` when it had
  no events for a known repository, or to `:failed`. A connection has each
  delivery id at most once.

  Deliveries are written by Slapdash itself. People can only read them.
  """
  use Ash.Resource,
    otp_app: :slapdash,
    domain: Slapdash.Webhooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [Slapdash.Authz.Resource]

  @type t :: %__MODULE__{}

  authz do
    resource_name("delivery")
  end

  postgres do
    table "webhook_deliveries"
    repo Slapdash.Repo

    custom_indexes do
      index [:inserted_at]
    end
  end

  actions do
    defaults [:read]

    create :receive do
      description "Store a delivery, or return the one already stored with this id."
      accept [:connection_id, :external_id, :event, :payload]
      upsert? true
      upsert_identity :one_per_delivery_id
      upsert_fields []
    end

    update :processed do
      accept [:event_count]
      change set_attribute(:status, :processed)
      change set_attribute(:error, nil)
    end

    update :ignored do
      change set_attribute(:status, :ignored)
      change set_attribute(:error, nil)
    end

    update :failed do
      accept [:error]
      change set_attribute(:status, :failed)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Slapdash.Authz.FilterCheck
    end

    # Only Slapdash writes deliveries, with authorization off.
    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :connection_id, :uuid do
      description "The connection that received it. Connections are in the public schema."
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      description "The service's id for the delivery"
      allow_nil? false
      public? true
      constraints max_length: 255
    end

    attribute :event, :string do
      description "The service's event name, such as pull_request"
      allow_nil? false
      public? true
      constraints max_length: 255
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :received
      public? true
      constraints one_of: [:received, :processed, :ignored, :failed]
    end

    attribute :event_count, :integer do
      description "How many bot events the delivery gave"
      allow_nil? false
      default 0
      public? true
    end

    attribute :error, :string, public?: true

    timestamps()
  end

  identities do
    identity :one_per_delivery_id, [:connection_id, :external_id]
  end
end
