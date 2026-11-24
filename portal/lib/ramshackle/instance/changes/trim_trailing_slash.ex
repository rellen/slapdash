defmodule Ramshackle.Instance.Changes.TrimTrailingSlash do
  @moduledoc "Stores `:public_url` without a trailing slash, so paths can be appended."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :public_url) do
      url when is_binary(url) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :public_url,
          String.trim_trailing(url, "/")
        )

      _ ->
        changeset
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
