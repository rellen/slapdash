defmodule Slapdash.Repositories do
  @moduledoc """
  Code repositories that a tenant has added to Slapdash.

  A repository belongs to a tenant and is reached through one of the
  tenant's connections (`Slapdash.Connections`). The connection's provider
  must implement `Slapdash.Repositories.Host`, which checks the repository
  path and does work on the repository, such as posting a comment.

  Repositories live in the `public` schema with a tenant id, so an incoming
  webhook can find the repository for a connection and a path without a
  visit to each tenant schema.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  boundary do
    deps [
      Slapdash.Authz,
      Slapdash.Accounts,
      Slapdash.Connections,
      Slapdash.Tenancy,
      Slapdash.Versions
    ]

    exports [Slapdash.Repositories.Host]
  end

  resources do
    resource Slapdash.Repositories.Repository do
      define :add_repository, action: :add
      define :remove_repository, action: :remove
      define :list_repositories, action: :read
      define :get_repository, action: :read, get_by: [:id]

      define :find_repository,
        action: :by_path,
        args: [:connection_id, :path],
        get?: true,
        not_found_error?: false
    end
  end

  paper_trail do
    include_versions? true
  end

  alias Slapdash.Connections
  alias Slapdash.Connections.Provider
  alias Slapdash.Repositories.Host

  @doc "Whether a connection can host repositories."
  @spec host?(Connections.Connection.t()) :: boolean()
  def host?(connection) do
    case Provider.fetch(connection.provider) do
      {:ok, provider} -> Provider.implements?(provider, Host)
      :error -> false
    end
  end

  @doc "The web address of a repository, for people."
  @spec web_url(Slapdash.Repositories.Repository.t()) :: String.t() | nil
  def web_url(%{connection: %Connections.Connection{} = connection, path: path}) do
    if host?(connection),
      do: Connections.provider(connection).web_url(connection, to_string(path))
  end
end
