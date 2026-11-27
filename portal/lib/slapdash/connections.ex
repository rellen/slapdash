defmodule Slapdash.Connections do
  @moduledoc """
  Connections to outside services, such as a GitHub App, a GitLab instance
  or a Slack workspace.

  A connection belongs to one tenant. Its `provider` names a module that
  implements `Slapdash.Connections.Provider`. That module declares the
  settings and secrets the connection needs and checks them. A provider can
  also implement other behaviours, for example to receive webhooks or to
  host repositories. Other domains ask `Slapdash.Connections.Provider` if a
  provider implements their behaviour.

  Connections live in the `public` schema, so an incoming webhook can find
  its connection, and so its tenant, by id alone.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  boundary do
    deps [Slapdash.Authz, Slapdash.Accounts, Slapdash.Tenancy, Slapdash.Versions]
    exports [Slapdash.Connections.Provider, Slapdash.Connections.Provider.Field]
  end

  resources do
    resource Slapdash.Connections.Connection do
      define :add_connection, action: :add
      define :reconfigure_connection, action: :reconfigure
      define :remove_connection, action: :remove
      define :list_connections, action: :read
      define :get_connection, action: :read, get_by: [:id]
    end
  end

  paper_trail do
    include_versions? true
  end

  alias Slapdash.Connections.Connection

  @doc """
  The decrypted secrets of a connection, for provider code that calls the
  service. Never show the result to a person or put it in a log, an error or
  job arguments.
  """
  @spec secrets(Connection.t()) :: map()
  def secrets(%Connection{} = connection) do
    connection
    |> Ash.load!(:secrets, authorize?: false)
    |> Map.fetch!(:secrets)
    |> Kernel.||(%{})
  end

  @doc "The provider module of a connection."
  @spec provider(Connection.t()) :: module()
  def provider(%Connection{provider: key}) do
    case Slapdash.Connections.Provider.fetch(key) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "no provider is registered for #{inspect(key)}"
    end
  end
end
