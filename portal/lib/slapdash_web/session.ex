defmodule SlapdashWeb.Session do
  @moduledoc """
  `Plug.Session` with a cookie domain that follows the instance settings.

  When root turns tenant subdomains on, the session cookie is set for the
  public URL host, so the browser also sends it to each tenant subdomain.
  One sign-in then covers all tenants. Otherwise the cookie is for the
  request host only. The domain is read for each request, so a change to
  the settings needs no restart.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    opts =
      case Slapdash.Instance.tenant_parent_host() do
        nil -> opts
        host -> Keyword.put(opts, :domain, host)
      end

    Plug.Session.call(conn, Plug.Session.init(opts))
  end
end
