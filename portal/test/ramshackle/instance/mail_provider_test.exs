defmodule Ramshackle.Instance.MailProviderTest do
  use Ramshackle.DataCase, async: true

  import Ramshackle.Fixtures
  import Swoosh.TestAssertions

  alias Ramshackle.{Instance, Mailer}
  alias Ramshackle.Instance.MailProvider

  test "without a provider, mail goes to the fallback adapter from the config" do
    assert Mailer.configured?()

    {:ok, _} =
      Swoosh.Email.new(to: "a@example.com", subject: "Hi", text_body: "x") |> Mailer.deliver()

    assert_email_sent(subject: "Hi", from: {"Ramshackle", "noreply@localhost"})
  end

  test "the sender comes from the instance settings" do
    Instance.configure_settings!(%{public_url: "https://bot.example.com"}, authorize?: false)
    assert Mailer.from() == {"Ramshackle", "noreply@bot.example.com"}

    {:ok, settings} = Instance.get_settings(authorize?: false)

    Instance.reconfigure_settings!(
      settings,
      %{mail_from_name: "Bot", mail_from_address: "bot@example.org"},
      authorize?: false
    )

    assert Mailer.from() == {"Bot", "bot@example.org"}
  end

  test "an SMTP provider verifies the server certificate" do
    root = root()

    {:ok, _} =
      Instance.configure_mail_provider(
        %{adapter: :smtp, host: "smtp.example.com", port: 587, username: "me", secret: "pw"},
        actor: root
      )

    {:ok, provider} = Instance.get_mail_provider(actor: root, load: [:secret])
    config = MailProvider.swoosh_config(provider)

    assert config[:adapter] == Swoosh.Adapters.SMTP
    assert config[:relay] == "smtp.example.com"
    assert config[:tls] == :always
    assert config[:auth] == :always
    assert config[:password] == "pw"
    assert config[:tls_options][:verify] == :verify_peer
  end

  test "API providers need a key, and Mailgun a domain" do
    root = root()

    assert {:error, %Ash.Error.Invalid{}} =
             Instance.configure_mail_provider(%{adapter: :postmark}, actor: root)

    assert {:error, %Ash.Error.Invalid{}} =
             Instance.configure_mail_provider(%{adapter: :mailgun, secret: "k"}, actor: root)

    assert {:ok, _} =
             Instance.configure_mail_provider(
               %{adapter: :mailgun, secret: "k", domain: "mg.example.com", region: :eu},
               actor: root
             )

    {:ok, provider} = Instance.get_mail_provider(actor: root, load: [:secret])

    assert MailProvider.swoosh_config(provider) == [
             adapter: Swoosh.Adapters.Mailgun,
             api_key: "k",
             domain: "mg.example.com",
             base_url: "https://api.eu.mailgun.net/v3"
           ]
  end

  test "only root may configure mail" do
    assert {:error, %Ash.Error.Forbidden{}} =
             Instance.configure_mail_provider(%{adapter: :postmark, secret: "k"}, actor: user())
  end
end
