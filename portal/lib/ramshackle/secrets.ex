defmodule Ramshackle.Secrets do
  @moduledoc """
  Supplies authentication secrets to AshAuthentication.

  The token signing secret comes from the application environment, where
  `Ramshackle.Instance.Boot` puts the generated one in production
  (`config/dev.exs` and `config/test.exs` hold local values).

  The GitHub client ID and secret come from `Ramshackle.Instance.GitHubOAuthApp`,
  read on each use so root can change them without a restart. The redirect
  URI is the public URL followed by `/auth`.
  """
  use AshAuthentication.Secret

  import Shoddy.Strings, only: [is_non_empty_string: 1]

  alias Ramshackle.Accounts.User
  alias Ramshackle.Instance

  def secret_for([:authentication, :tokens, :signing_secret], User, _opts, _context) do
    Application.fetch_env(:ramshackle, :token_signing_secret)
  end

  def secret_for([:authentication, :strategies, :github, :redirect_uri], User, _opts, _context) do
    {:ok, Instance.url("/auth")}
  end

  def secret_for([:authentication, :strategies, :github, key], User, _opts, _context)
      when key in [:client_id, :client_secret] do
    with {:ok, %Instance.GitHubOAuthApp{} = app} <- github_app(),
         value when is_non_empty_string(value) <- Map.get(app, key) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  @doc "Whether GitHub sign-in is configured, so the sign-in page can offer it."
  @spec github_configured?() :: boolean()
  def github_configured? do
    match?({:ok, %Instance.GitHubOAuthApp{}}, github_app())
  end

  defp github_app do
    Instance.get_github_oauth_app(
      authorize?: false,
      load: [:client_secret],
      not_found_error?: false
    )
  end
end
