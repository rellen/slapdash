defmodule Ramshackle.Instance.Changes.KeepSecretWhenBlank do
  @moduledoc """
  Drops a blank cloaked-secret argument, so saving a form without retyping
  the secret keeps the stored one instead of erasing it.

  AshCloak encrypts the argument in a `before_action` hook, which runs after
  this change, so a deleted argument leaves the encrypted column alone.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if is_atom(opts[:argument]),
      do: {:ok, opts},
      else: {:error, "argument is required"}
  end

  @impl true
  def change(changeset, opts, _context) do
    argument = opts[:argument]

    case Ash.Changeset.fetch_argument(changeset, argument) do
      {:ok, value} ->
        if Shoddy.Strings.non_blank(value),
          do: changeset,
          else: Ash.Changeset.delete_argument(changeset, argument)

      :error ->
        changeset
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
