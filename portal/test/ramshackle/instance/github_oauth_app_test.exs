defmodule Ramshackle.Instance.GitHubOAuthAppTest do
  use Ramshackle.DataCase, async: true

  import Ramshackle.Fixtures

  alias Ramshackle.{Instance, Secrets}
  alias Ramshackle.Accounts.User

  defp secret(key),
    do: Secrets.secret_for([:authentication, :strategies, :github, key], User, [], %{})

  test "GitHub sign-in is off until root configures it" do
    refute Secrets.github_configured?()
    assert secret(:client_id) == :error
    assert secret(:client_secret) == :error
  end

  test "root configures it, and the secret is encrypted at rest" do
    root = root()

    assert {:ok, app} =
             Instance.configure_github_oauth_app(
               %{client_id: "Iv1.abc", client_secret: "shh-secret"},
               actor: root
             )

    assert Secrets.github_configured?()
    assert secret(:client_id) == {:ok, "Iv1.abc"}
    assert secret(:client_secret) == {:ok, "shh-secret"}

    %{rows: [[stored]]} = Repo.query!("SELECT encrypted_client_secret FROM github_oauth_app")
    refute stored =~ "shh-secret"

    # The secret is not part of the record unless asked for.
    refute inspect(app) =~ "shh-secret"
  end

  test "reconfiguring with a blank secret keeps the stored one" do
    root = root()

    {:ok, app} =
      Instance.configure_github_oauth_app(%{client_id: "a", client_secret: "one"}, actor: root)

    {:ok, _} =
      Instance.reconfigure_github_oauth_app(app, %{client_id: "b", client_secret: ""},
        actor: root
      )

    assert secret(:client_id) == {:ok, "b"}
    assert secret(:client_secret) == {:ok, "one"}

    {:ok, app} = Instance.get_github_oauth_app(actor: root)
    {:ok, _} = Instance.reconfigure_github_oauth_app(app, %{client_secret: "two"}, actor: root)
    assert secret(:client_secret) == {:ok, "two"}
  end

  test "the redirect URI follows the public URL" do
    Instance.configure_settings!(%{public_url: "https://bot.example.com"}, authorize?: false)
    assert secret(:redirect_uri) == {:ok, "https://bot.example.com/auth"}
  end

  test "only root may configure it" do
    admin = user()
    member(admin, tenant(), :administrator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Instance.configure_github_oauth_app(%{client_id: "a", client_secret: "b"},
               actor: admin
             )
  end
end
