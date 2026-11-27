defmodule SlapdashWeb.Origin do
  @moduledoc """
  Checks the `Origin` of LiveView socket connections in production against
  the public URL root sets in `Slapdash.Instance.Settings`, so the host
  does not have to be known when the release is configured.

  When tenant subdomains are on, an origin on a subdomain of the public URL
  host is allowed too. Until the public URL is set, only `localhost`
  origins are allowed.
  """

  @doc false
  @spec allowed?(URI.t()) :: boolean()
  def allowed?(%URI{} = origin) do
    if Slapdash.Instance.public_url_set?() do
      public = URI.parse(Slapdash.Instance.public_url())

      origin.scheme == public.scheme and origin.port == public.port and
        (origin.host == public.host or tenant_host?(origin.host))
    else
      origin.host in ["localhost", "127.0.0.1", "::1"]
    end
  end

  defp tenant_host?(host), do: is_binary(Slapdash.Instance.tenant_slug_for_host(host))
end
