defmodule Slapdash.Tenancy.Membership.Changes.SetUserByEmail do
  @moduledoc """
  Finds the user with the `:email` argument, creating them if needed, and
  sets the membership's `user_id`.

  It runs in a `before_action` hook, after authorization, so a caller who may
  not add members cannot create users either.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      email = Ash.Changeset.get_argument(changeset, :email)

      case Slapdash.Accounts.ensure_user(email, actor: context.actor) do
        {:ok, user} -> Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
