defmodule Slapdash.Instance do
  @moduledoc """
  Install-wide configuration that the operator sets up after first boot:
  the public URL and sender address, the mail provider and the GitHub OAuth
  app. Also the secrets generated on first boot.

  Everything here lives in the `public` schema and is managed by root. See
  `Slapdash.Authz` for who may do what.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  boundary do
    deps [Slapdash.Authz, Slapdash.Versions]
    # `public_url/0` falls back to the endpoint URL. This is a known
    # exception until the fallback comes from configuration.
    dirty_xrefs [SlapdashWeb.Endpoint]
  end

  resources do
    resource Slapdash.Instance.BootSecrets

    resource Slapdash.Instance.Settings do
      define :get_settings, action: :current
      define :configure_settings, action: :configure
      define :reconfigure_settings, action: :reconfigure
    end

    resource Slapdash.Instance.MailProvider do
      define :get_mail_provider, action: :current
      define :configure_mail_provider, action: :configure
      define :reconfigure_mail_provider, action: :reconfigure
      define :remove_mail_provider, action: :remove
    end

    resource Slapdash.Instance.GitHubOAuthApp do
      define :get_github_oauth_app, action: :current
      define :configure_github_oauth_app, action: :configure
      define :reconfigure_github_oauth_app, action: :reconfigure
      define :remove_github_oauth_app, action: :remove
    end
  end

  paper_trail do
    include_versions? true
  end

  @doc """
  The base URL people reach Slapdash at, without a trailing slash.

  It comes from `Slapdash.Instance.Settings` and falls back to the
  endpoint's own URL (`http://localhost:4000` by default) until root sets it.
  """
  @spec public_url() :: String.t()
  def public_url do
    case get_settings(authorize?: false, not_found_error?: false) do
      {:ok, %{public_url: url}} when is_binary(url) -> url
      _ -> SlapdashWeb.Endpoint.url()
    end
  end

  @doc "Whether root has set the public URL yet."
  @spec public_url_set?() :: boolean()
  def public_url_set? do
    match?({:ok, %{public_url: url}} when is_binary(url), get_settings(authorize?: false))
  end

  @doc """
  The host that tenant subdomains sit under, or `nil` when root has not
  set the public URL or has not turned tenant subdomains on. With the public
  URL `https://slapdash.example.com`, tenant `acme` is at
  `acme.slapdash.example.com`.
  """
  @spec tenant_parent_host() :: String.t() | nil
  def tenant_parent_host do
    case get_settings(authorize?: false, not_found_error?: false) do
      {:ok, %{public_url: url, tenant_subdomains: true}} when is_binary(url) ->
        URI.parse(url).host

      _ ->
        nil
    end
  end

  @doc "The tenant slug that a request host names, or `nil`."
  @spec tenant_slug_for_host(String.t() | nil) :: String.t() | nil
  def tenant_slug_for_host(host) when is_binary(host) do
    host = String.downcase(host)

    with parent when is_binary(parent) <- tenant_parent_host(),
         suffix = "." <> parent,
         true <- String.ends_with?(host, suffix),
         slug = String.replace_suffix(host, suffix, ""),
         true <- slug != "" and not String.contains?(slug, ".") do
      slug
    else
      _ -> nil
    end
  end

  def tenant_slug_for_host(_host), do: nil

  @doc """
  The absolute URL of a page of a tenant, such as `tenant_url("acme",
  "/members")`. It is on the tenant subdomain when they are on, and under
  `/<slug>` on the public URL otherwise.
  """
  @spec tenant_url(String.t(), String.t()) :: String.t()
  def tenant_url(slug, "/" <> _ = path) do
    if tenant_parent_host() do
      uri = URI.parse(public_url())
      URI.to_string(%{uri | host: slug <> "." <> uri.host, path: path})
    else
      public_url() <> "/" <> slug <> path
    end
  end

  @doc "Builds an absolute URL for a path, such as `~p\"/sign-in\"`."
  @spec url(String.t()) :: String.t()
  def url("/" <> _ = path), do: public_url() <> path
end
