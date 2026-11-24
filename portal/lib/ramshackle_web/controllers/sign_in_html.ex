defmodule RamshackleWeb.SignInHTML do
  @moduledoc """
  Pages rendered by `RamshackleWeb.SignInController`.

  The markup is semantic and classless. Styling comes from the application's
  stylesheet, not from classes on these elements.
  """
  use RamshackleWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Sign in</h1>
      <p>
        Ramshackle is invitation only. If you do not have an account, ask an
        administrator to invite your email address.
      </p>

      <section aria-labelledby="magic-link-heading">
        <h2 id="magic-link-heading">Email me a sign-in link</h2>
        <.form for={%{}} as={:user} action={~p"/auth/user/magic_link/request"}>
          <p>
            <label for="user_email">Email address</label>
            <input
              type="email"
              id="user_email"
              name="user[email]"
              autocomplete="email"
              required
            />
          </p>
          <p><button type="submit">Send sign-in link</button></p>
        </.form>
      </section>

      <section :if={@github?} aria-labelledby="github-heading">
        <h2 id="github-heading">Use GitHub</h2>
        <p><a href={~p"/auth/user/github"}>Sign in with GitHub</a></p>
      </section>
    </Layouts.app>
    """
  end

  def magic_link(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Sign in</h1>
      <.form for={%{}} as={:user} action={~p"/auth/user/magic_link"}>
        <input type="hidden" name="user[token]" value={@token} />
        <p><button type="submit">Sign in to Ramshackle</button></p>
      </.form>
    </Layouts.app>
    """
  end
end
