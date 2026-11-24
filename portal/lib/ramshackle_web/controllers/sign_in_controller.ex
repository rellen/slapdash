defmodule RamshackleWeb.SignInController do
  @moduledoc """
  The sign-in pages: ask for a magic link or sign in with GitHub, and confirm a
  magic link.

  These are plain controller pages. The forms post to the strategy routes from
  `auth_routes`, whose results land in `RamshackleWeb.AuthController`.
  """
  use RamshackleWeb, :controller

  def new(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/")
    else
      render(conn, :new,
        page_title: "Sign in",
        github?: Ramshackle.Secrets.github_configured?()
      )
    end
  end

  # The emailed link lands here. Signing in needs a button press, so mail
  # scanners that follow links cannot use up the token.
  def magic_link(conn, %{"token" => token}) do
    render(conn, :magic_link, page_title: "Sign in", token: token)
  end
end
