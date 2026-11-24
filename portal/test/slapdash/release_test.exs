defmodule Slapdash.ReleaseTest do
  use SlapdashWeb.ConnCase, async: false

  import ExUnit.CaptureIO

  alias Slapdash.{Accounts, Instance, Release}

  test "create_root needs the public URL the first time" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, message} = Release.create_root("root@example.com")
        assert message =~ "public URL is not set"
      end)

    assert output =~ "public URL is not set"
  end

  test "create_root makes a root user and prints a link that signs them in" do
    {result, output} =
      with_io(fn ->
        Release.create_root("root@example.com", public_url: "https://bot.example.com")
      end)

    assert {:ok, "https://bot.example.com/magic_link/" <> token = link} = result
    assert output =~ link

    assert {:ok, %{root: true}} =
             Accounts.get_user_by_email("root@example.com", authorize?: false)

    assert Instance.public_url() == "https://bot.example.com"

    conn = post(build_conn(), ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "user_token")
  end

  test "sign_in_link prints a link for an existing user and refuses unknown ones" do
    capture_io(fn ->
      Release.create_root("root@example.com", public_url: "https://bot.example.com")
    end)

    capture_io(fn ->
      assert {:ok, "https://bot.example.com/magic_link/" <> _} =
               Release.sign_in_link("root@example.com")
    end)

    capture_io(:stderr, fn ->
      assert {:error, message} = Release.sign_in_link("nobody@example.com")
      assert message =~ "no user"
    end)
  end
end
