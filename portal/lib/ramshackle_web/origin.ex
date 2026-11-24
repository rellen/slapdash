defmodule RamshackleWeb.Origin do
  @moduledoc """
  Checks the `Origin` of LiveView socket connections in production against
  the public URL root sets in `Ramshackle.Instance.Settings`, so the host
  does not have to be known when the release is configured.

  Until the public URL is set, only `localhost` origins are allowed.
  """

  @doc false
  @spec allowed?(URI.t()) :: boolean()
  def allowed?(%URI{} = origin) do
    if Ramshackle.Instance.public_url_set?() do
      public = URI.parse(Ramshackle.Instance.public_url())

      origin.scheme == public.scheme and origin.host == public.host and
        origin.port == public.port
    else
      origin.host in ["localhost", "127.0.0.1", "::1"]
    end
  end
end
