defmodule SlapdashWeb.AuthController do
  @moduledoc """
  Handles the results of the magic link and GitHub strategies, and signing out.

  The routes that reach `success/4` and `failure/3` come from `auth_routes` in
  the router.
  """
  use SlapdashWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @impl true
  def success(conn, {:magic_link, :request}, _user, _token) do
    conn
    # The same message whether or not the email has an account, so the page
    # does not show who is invited.
    |> put_flash(:info, "If that email address has an account, we sent it a sign-in link.")
    |> redirect(to: ~p"/sign-in")
  end

  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, "You are now signed in.")
    |> redirect(to: return_to)
  end

  @impl true
  def failure(conn, activity, _reason) do
    conn
    |> put_flash(:error, failure_message(activity))
    |> redirect(to: ~p"/sign-in")
  end

  # The reason is not shown, so the page does not reveal which emails have
  # accounts or why a provider sign-in was refused.
  defp failure_message({:magic_link, :request}),
    do: "We could not send a sign-in link. Check the email address and try again."

  defp failure_message({:magic_link, _phase}),
    do: "That sign-in link has expired or has already been used. Ask for a new one."

  defp failure_message({:github, _phase}),
    do:
      "Signing in with GitHub failed. You can sign in only after an administrator invites your " <>
        "email address, and your GitHub account must have that address as its verified primary email."

  defp failure_message(_activity), do: "Signing in failed."

  @impl true
  def sign_out(conn, _params) do
    conn
    |> clear_session(:slapdash)
    |> put_flash(:info, "You are now signed out.")
    |> redirect(to: ~p"/")
  end
end
