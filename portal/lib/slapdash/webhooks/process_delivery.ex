defmodule Slapdash.Webhooks.ProcessDelivery do
  @moduledoc """
  The Oban job that turns a stored delivery into bot events and dispatches
  them. Its arguments hold ids only.

  An event goes to bots only when its repository is one of the connection's
  repositories. The job is safe to run again: `Slapdash.Bots.dispatch/2`
  starts at most one run for each event id, and event ids come from the
  delivery id.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [keys: [:delivery_id], states: :incomplete]

  alias Slapdash.Bots
  alias Slapdash.Connections
  alias Slapdash.Repositories
  alias Slapdash.Webhooks

  @doc "Queues the job for a delivery."
  def enqueue!(delivery, tenant) do
    %{"tenant_id" => tenant.id, "delivery_id" => delivery.id} |> new() |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_id" => tenant_id, "delivery_id" => delivery_id}}) do
    with {:ok, tenant} <- Slapdash.Tenancy.get_tenant(tenant_id, authorize?: false),
         {:ok, delivery} <- Webhooks.get_delivery(delivery_id, tenant: tenant, authorize?: false),
         {:ok, connection} <-
           Connections.get_connection(delivery.connection_id, authorize?: false) do
      process(delivery, connection, tenant)
    else
      {:error, _} -> {:cancel, "the delivery, its connection or its tenant no longer exists"}
    end
  end

  defp process(delivery, connection, tenant) do
    source = Connections.provider(connection)

    dispatched =
      delivery.event
      |> source.to_events(delivery.payload, connection)
      |> Enum.with_index()
      |> Enum.flat_map(fn {event, index} ->
        event = %{event | id: "webhook:#{delivery.id}:#{index}", connection_id: connection.id}

        case Repositories.find_repository(connection.id, event.repository_path, authorize?: false) do
          {:ok, %{tenant_id: tenant_id} = repository} when tenant_id == connection.tenant_id ->
            [Bots.dispatch(event, repository)]

          _ ->
            []
        end
      end)

    case Enum.find(dispatched, &match?({:error, _}, &1)) do
      nil when dispatched == [] ->
        update!(delivery, :ignored, %{}, tenant)
        :ok

      nil ->
        update!(delivery, :processed, %{event_count: length(dispatched)}, tenant)
        :ok

      {:error, error} ->
        message = if is_exception(error), do: Exception.message(error), else: inspect(error)
        update!(delivery, :failed, %{error: message}, tenant)
        {:error, message}
    end
  end

  defp update!(delivery, action, params, tenant) do
    delivery
    |> Ash.Changeset.for_update(action, params, tenant: tenant, authorize?: false)
    |> Ash.update!()
  end
end
