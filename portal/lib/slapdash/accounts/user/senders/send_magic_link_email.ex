defmodule Slapdash.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Emails a magic sign-in link.

  The link opens a page with a "Sign in" button rather than signing in
  directly, so mail scanners that follow links cannot use up the token.
  """

  use AshAuthentication.Sender
  use SlapdashWeb, :verified_routes

  import Swoosh.Email
  alias Slapdash.Mailer

  @impl true
  def send(user_or_email, token, _opts) do
    # An existing user arrives as a record, a new one as a bare email.
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    link = Slapdash.Instance.url(~p"/magic_link/#{token}")

    new()
    |> to(to_string(email))
    |> subject("Your Slapdash sign-in link")
    |> text_body("""
    Use this link to sign in to Slapdash:

    #{link}

    If you did not ask to sign in, you can ignore this email.
    """)
    |> html_body("""
    <p>Use this link to sign in to Slapdash:</p>
    <p><a href="#{link}">#{link}</a></p>
    <p>If you did not ask to sign in, you can ignore this email.</p>
    """)
    |> Mailer.deliver!()
  end
end
