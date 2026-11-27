defmodule Slapdash.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SlapdashWeb.Telemetry,
      Slapdash.Repo,
      Slapdash.Vault,
      # Loads (or on first boot, generates) secret_key_base and the token
      # signing secret, so it must start before the endpoint.
      Slapdash.Instance.Boot,
      {Phoenix.PubSub, name: Slapdash.PubSub},
      {Oban, Application.fetch_env!(:slapdash, Oban)},
      {AshAuthentication.Supervisor, [otp_app: :slapdash]},
      # Start to serve requests, typically the last entry
      SlapdashWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Slapdash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SlapdashWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
