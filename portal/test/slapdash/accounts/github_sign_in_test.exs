defmodule Slapdash.Accounts.GithubSignInTest do
  use Slapdash.DataCase, async: true

  alias AshAuthentication.{Info, Strategy}
  alias Slapdash.Accounts.{User, UserIdentity}

  # Shaped like the claims Assent's GitHub strategy returns.
  defp user_info(overrides \\ %{}) do
    Map.merge(
      %{
        "sub" => 1_234_567,
        "preferred_username" => "octocat",
        "email" => "octocat@example.com",
        "email_verified" => true
      },
      overrides
    )
  end

  defp oauth_tokens, do: %{"access_token" => "gho_secret", "token_type" => "bearer"}

  defp sign_in(user_info) do
    {:ok, strategy} = Info.strategy(User, :github)

    Strategy.action(strategy, :sign_in, %{
      "user_info" => user_info,
      "oauth_tokens" => oauth_tokens()
    })
  end

  defp invite(email \\ "octocat@example.com") do
    {:ok, user} = Slapdash.Accounts.ensure_user(email)
    user
  end

  defp identities do
    Ash.read!(UserIdentity, authorize?: false)
  end

  test "does not create a user for someone who was not invited" do
    assert {:error, _} = sign_in(user_info())
    assert [] = Ash.read!(User, authorize?: false)
    assert [] = identities()
  end

  test "signs in an invited user with the same verified email and links GitHub" do
    invited = invite()

    assert {:ok, user} = sign_in(user_info())
    assert user.id == invited.id
    assert user.__metadata__.token

    assert [identity] = identities()
    assert identity.user_id == invited.id
    assert identity.strategy == "github"
    assert identity.uid == "1234567"
  end

  test "does not store GitHub's OAuth tokens" do
    invite()
    assert {:ok, _user} = sign_in(user_info())

    assert [identity] = identities()
    assert is_nil(identity.access_token)
    assert is_nil(identity.refresh_token)
  end

  test "refuses an unverified GitHub email, even for an invited user" do
    invite()

    assert {:error, _} = sign_in(user_info(%{"email_verified" => false}))
    assert [] = identities()
  end

  test "refuses a GitHub account without an email" do
    invite()
    assert {:error, _} = sign_in(user_info(%{"email" => nil, "email_verified" => false}))
  end

  test "a returning GitHub user keeps their account when their GitHub email changes" do
    invited = invite()
    {:ok, _user} = sign_in(user_info())

    assert {:ok, user} = sign_in(user_info(%{"email" => "new@example.com"}))
    assert user.id == invited.id
    assert to_string(user.email) == "octocat@example.com"
  end

  test "a different GitHub account with the same email is refused" do
    invite()
    {:ok, _user} = sign_in(user_info())

    assert {:error, _} = sign_in(user_info(%{"sub" => 7_654_321}))
  end
end
