defmodule Slapdash.Repositories.Changes.CheckHost do
  @moduledoc """
  Checks that a new repository's connection belongs to the same tenant and
  can host repositories, and lets the provider check and cast the path.
  """
  use Ash.Resource.Change

  alias Slapdash.Connections
  alias Slapdash.Repositories

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &check/1)
  end

  defp check(changeset) do
    tenant_id = Ash.Changeset.get_attribute(changeset, :tenant_id)
    connection_id = Ash.Changeset.get_attribute(changeset, :connection_id)

    case Connections.get_connection(connection_id, authorize?: false, not_found_error?: false) do
      {:ok, %{tenant_id: ^tenant_id} = connection} -> check_path(changeset, connection)
      _ -> Ash.Changeset.add_error(changeset, field: :connection_id, message: "is not valid")
    end
  end

  defp check_path(changeset, connection) do
    if Repositories.host?(connection) do
      path = changeset |> Ash.Changeset.get_attribute(:path) |> to_string()

      case Connections.provider(connection).cast_path(path) do
        {:ok, path} -> Ash.Changeset.force_change_attribute(changeset, :path, path)
        {:error, message} -> Ash.Changeset.add_error(changeset, field: :path, message: message)
      end
    else
      Ash.Changeset.add_error(changeset,
        field: :connection_id,
        message: "cannot host repositories"
      )
    end
  end
end
