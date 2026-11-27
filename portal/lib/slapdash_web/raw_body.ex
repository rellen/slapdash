defmodule SlapdashWeb.RawBody do
  @moduledoc """
  A body reader for `Plug.Parsers` that keeps the raw body of webhook
  requests in `conn.private[:raw_body]`. Webhook signatures are computed
  over the exact bytes that the service sent, so the decoded params are not
  enough. Other requests are read as usual, and their bodies are not kept.
  """

  @doc "Reads the body, and keeps it for paths under `/webhooks/`."
  def read_body(%Plug.Conn{path_info: ["webhooks" | _]} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, append(conn, body)}
      {:more, body, conn} -> {:more, body, append(conn, body)}
      other -> other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp append(conn, body) do
    Plug.Conn.put_private(conn, :raw_body, (conn.private[:raw_body] || "") <> body)
  end
end
