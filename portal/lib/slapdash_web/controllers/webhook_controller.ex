defmodule SlapdashWeb.WebhookController do
  @moduledoc """
  Receives webhooks for a connection (`Slapdash.Webhooks.receive/4`).

  The answers do not tell why a connection id is not found, and they never
  contain tenant data. A repeated delivery gets the same answer as the
  first one.
  """
  use SlapdashWeb, :controller

  def receive(conn, %{"connection_id" => connection_id}) do
    headers = Map.new(conn.req_headers)
    raw_body = conn.private[:raw_body] || ""
    params = Map.delete(conn.body_params, "connection_id")

    case Slapdash.Webhooks.receive(connection_id, headers, raw_body, params) do
      {:ok, _delivery} -> send_resp(conn, :accepted, "")
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :unauthorized} -> send_resp(conn, :unauthorized, "")
      {:error, :bad_request} -> send_resp(conn, :bad_request, "")
    end
  end
end
