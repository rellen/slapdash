defmodule Slapdash.Accounts do
  @moduledoc """
  Users and how they sign in. Roles are in `Slapdash.Authz`; tenant
  memberships are in `Slapdash.Tenancy`.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshPaperTrail.Domain]

  resources do
    resource Slapdash.Accounts.Token
    resource Slapdash.Accounts.UserIdentity

    resource Slapdash.Accounts.User do
      define :get_user_by_email, action: :get_by_email, args: [:email]
    end
  end

  paper_trail do
    include_versions? true
  end

  alias Slapdash.Accounts.User

  @doc """
  Returns the user with this email, creating them if they do not exist yet.

  This is internal plumbing that skips authorization: callers must have
  authorized the operation that needs the user (such as adding a member).

  Pass `actor:` so that the version history records who created the user.
  The actor is not authorized.
  """
  @spec ensure_user(String.t() | Ash.CiString.t(), keyword()) ::
          {:ok, User.t()} | {:error, term()}
  def ensure_user(email, opts \\ []) do
    case get_user_by_email(email, authorize?: false, not_found_error?: false) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:ok, nil} ->
        User
        |> Ash.Changeset.for_create(:create_by_email, %{email: email})
        |> Ash.create(authorize?: false, actor: Keyword.get(opts, :actor))

      {:error, error} ->
        {:error, error}
    end
  end
end
