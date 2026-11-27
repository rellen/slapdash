defmodule Slapdash.Webhooks.Source do
  @moduledoc """
  The behaviour for a provider that sends webhooks, such as GitHub, GitLab,
  Forgejo, Linear or Slack. A provider module implements it next to
  `Slapdash.Connections.Provider`.

  `Slapdash.Webhooks.receive/4` calls `verify_webhook/4` and then
  `parse_webhook/2` for each request. `Slapdash.Webhooks.ProcessDelivery`
  calls `to_events/3` later, in a job.
  """

  alias Slapdash.Bots.Event
  alias Slapdash.Connections.Connection

  @doc """
  Checks that the request comes from the service, for example with an HMAC
  signature over `raw_body` and a secret of the connection. Compare in
  constant time (`Plug.Crypto.secure_compare/2`).
  """
  @callback verify_webhook(
              Connection.t(),
              headers :: %{String.t() => String.t()},
              raw_body :: binary(),
              secrets :: map()
            ) :: :ok | {:error, term()}

  @doc """
  Reads the service's id for the delivery and the event name, such as
  `"pull_request"`. The delivery id must be the same when the service
  sends the same delivery again.
  """
  @callback parse_webhook(headers :: %{String.t() => String.t()}, params :: map()) ::
              {:ok, %{delivery_id: String.t(), event: String.t()}} | {:error, term()}

  @doc """
  Turns a stored delivery into bot events. Return no events for a delivery
  that no bot reacts to. Leave `id` as `nil`: the caller sets it.
  """
  @callback to_events(event :: String.t(), payload :: map(), Connection.t()) :: [Event.t()]
end
