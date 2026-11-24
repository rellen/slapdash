defmodule Ramshackle.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RamshackleWeb.Telemetry,
      Ramshackle.Repo,
      Ramshackle.Vault,
      # Loads (or on first boot, generates) secret_key_base and the token
      # signing secret, so it must start before the endpoint.
      Ramshackle.Instance.Boot,
      {Phoenix.PubSub, name: Ramshackle.PubSub},
      # Start a worker by calling: Ramshackle.Worker.start_link(arg)
      # {Ramshackle.Worker, arg},
      {AshAuthentication.Supervisor, [otp_app: :ramshackle]},
      # Start to serve requests, typically the last entry
      RamshackleWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ramshackle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RamshackleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
