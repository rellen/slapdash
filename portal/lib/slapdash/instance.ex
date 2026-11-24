defmodule Slapdash.Instance do
  @moduledoc """
  Install-wide configuration that the operator sets up after first boot:
  the public URL and sender address, the mail provider and the GitHub OAuth
  app. Also the secrets generated on first boot.

  Everything here lives in the `public` schema and is managed by root. See
  `Slapdash.Authz` for who may do what.
  """
  use Ash.Domain,
    otp_app: :slapdash

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

  @doc "Builds an absolute URL for a path, such as `~p\"/sign-in\"`."
  @spec url(String.t()) :: String.t()
  def url("/" <> _ = path), do: public_url() <> path
end
