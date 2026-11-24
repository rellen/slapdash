defmodule Slapdash.Instance.Validations.BaseURL do
  @moduledoc """
  Accepts an `http` or `https` URL with a host and no path, query or
  fragment, for `:public_url`.
  """
  use Ash.Resource.Validation

  import Shoddy.Strings, only: [is_non_empty_string: 1]

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :public_url) do
      nil -> :ok
      url -> check(URI.parse(url))
    end
  end

  defp check(%URI{scheme: scheme, host: host, path: path, query: nil, fragment: nil})
       when scheme in ["http", "https"] and is_non_empty_string(host) and path in [nil, "", "/"],
       do: :ok

  defp check(_uri) do
    {:error,
     field: :public_url,
     message: "must be an http or https URL with no path, like https://bot.example.com"}
  end
end
