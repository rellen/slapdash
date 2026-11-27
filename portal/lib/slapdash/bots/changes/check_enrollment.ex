defmodule Slapdash.Bots.Changes.CheckEnrollment do
  @moduledoc """
  Checks that the bot is in the catalogue and that the repository belongs
  to the tenant the enrollment is made in.
  """
  use Ash.Resource.Change

  alias Slapdash.Bots.Catalogue
  alias Slapdash.Repositories

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> check_bot()
    |> Ash.Changeset.before_action(&check_repository/1)
  end

  defp check_bot(changeset) do
    case Catalogue.fetch(Ash.Changeset.get_attribute(changeset, :bot)) do
      {:ok, _bot} -> changeset
      :error -> Ash.Changeset.add_error(changeset, field: :bot, message: "is not known")
    end
  end

  defp check_repository(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :repository_id)

    case Repositories.get_repository(id, authorize?: false, not_found_error?: false) do
      {:ok, %{tenant_id: tenant_id}} when tenant_id == changeset.tenant.id ->
        changeset

      _ ->
        Ash.Changeset.add_error(changeset, field: :repository_id, message: "is not valid")
    end
  end
end
