defmodule Slapdash.Webhooks do
  @moduledoc """
  Webhook intake: outside services send events to Slapdash over HTTP.

  Each connection whose provider implements `Slapdash.Webhooks.Source` has
  its own endpoint, `POST /webhooks/<connection id>`. `receive/4` checks
  the request with the provider, stores it as a `Slapdash.Webhooks.Delivery`
  and queues `Slapdash.Webhooks.ProcessDelivery`. That job turns the
  delivery into bot events (`Slapdash.Bots.Event`) and dispatches them to
  the bots enrolled on the repository (`Slapdash.Bots.dispatch/2`).

  A delivery is stored at most once for each delivery id of a connection,
  so a service that sends the same delivery again does not start new bot
  runs. Deliveries are tenant data, so they live in the tenant's schema.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshBoundary]

  boundary do
    deps [
      Slapdash.Authz,
      Slapdash.Bots,
      Slapdash.Connections,
      Slapdash.Repositories,
      Slapdash.Tenancy
    ]

    exports [Slapdash.Webhooks.Source]
  end

  resources do
    resource Slapdash.Webhooks.Delivery do
      define :list_deliveries, action: :read
      define :get_delivery, action: :read, get_by: [:id]
    end
  end

  alias Slapdash.Connections
  alias Slapdash.Connections.Provider
  alias Slapdash.Webhooks.{Delivery, ProcessDelivery, Source}

  @typedoc "Request headers with lower-case names, as Plug gives them."
  @type headers :: %{String.t() => String.t()}

  @doc """
  Receives one webhook request for a connection.

  `raw_body` is the request body as it arrived, for the signature check.
  `params` is the decoded body. Returns:

  - `{:ok, delivery}` when the delivery is stored, also for a repeat
  - `{:error, :not_found}` when no connection with this id takes webhooks
  - `{:error, :unauthorized}` when the provider refuses the signature
  - `{:error, :bad_request}` when the request is not a valid delivery
  """
  @spec receive(String.t(), headers(), binary(), map()) ::
          {:ok, Delivery.t()} | {:error, :not_found | :unauthorized | :bad_request}
  def receive(connection_id, headers, raw_body, params) do
    with {:ok, connection, source} <- fetch_source(connection_id),
         :ok <- verify(source, connection, headers, raw_body),
         {:ok, %{delivery_id: delivery_id, event: event}} <- parse(source, headers, params) do
      tenant = Slapdash.Tenancy.get_tenant!(connection.tenant_id, authorize?: false)

      delivery =
        Delivery
        |> Ash.Changeset.for_create(
          :receive,
          %{
            connection_id: connection.id,
            external_id: delivery_id,
            event: event,
            payload: params
          },
          tenant: tenant,
          authorize?: false
        )
        |> Ash.create!()

      if delivery.status == :received, do: ProcessDelivery.enqueue!(delivery, tenant)
      {:ok, delivery}
    end
  end

  defp fetch_source(connection_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(connection_id),
         {:ok, %Connections.Connection{} = connection} <-
           Connections.get_connection(connection_id, authorize?: false, not_found_error?: false),
         {:ok, provider} <- Provider.fetch(connection.provider),
         true <- Provider.implements?(provider, Source) do
      {:ok, connection, provider}
    else
      _ -> {:error, :not_found}
    end
  end

  defp verify(source, connection, headers, raw_body) do
    case source.verify_webhook(connection, headers, raw_body, Connections.secrets(connection)) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp parse(source, headers, params) do
    case source.parse_webhook(headers, params) do
      {:ok, %{delivery_id: id, event: event} = parsed} when is_binary(id) and is_binary(event) ->
        {:ok, parsed}

      _ ->
        {:error, :bad_request}
    end
  end
end
