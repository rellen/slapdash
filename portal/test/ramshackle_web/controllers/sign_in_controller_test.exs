defmodule RamshackleWeb.SignInControllerTest do
  use RamshackleWeb.ConnCase

  import Swoosh.TestAssertions

  describe "GET /sign-in" do
    test "offers a magic link form, and GitHub only once it is configured", %{conn: conn} do
      html = conn |> get(~p"/sign-in") |> html_response(200)

      assert html =~ ~s(action="/auth/user/magic_link/request")
      assert html =~ ~s(<label for="user_email">)
      refute html =~ ~s(href="/auth/user/github")

      Ramshackle.Instance.configure_github_oauth_app!(%{client_id: "id", client_secret: "secret"},
        authorize?: false
      )

      html = build_conn() |> get(~p"/sign-in") |> html_response(200)
      assert html =~ ~s(href="/auth/user/github")
    end
  end

  describe "magic link sign-in" do
    test "emails a link to an invited user, and the link signs them in", %{conn: conn} do
      {:ok, _user} = Ramshackle.Accounts.ensure_user("rob@example.com")

      conn =
        post(conn, ~p"/auth/user/magic_link/request", %{
          "user" => %{"email" => "operator@example.com"}
        })

      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "we sent it a sign-in link"

      assert_email_sent(fn email ->
        assert email.to == [{"", "operator@example.com"}]
        send(self(), {:magic_link_body, email.text_body})
      end)

      assert_received {:magic_link_body, body}
      [_, path, token] = Regex.run(~r{https?://[^/]+(/magic_link/([^\s]+))}, body)

      # Following the link only shows a button; it does not sign in.
      page = build_conn() |> get(path) |> html_response(200)
      assert page =~ ~s(action="/auth/user/magic_link")
      assert page =~ token

      conn = post(build_conn(), ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "user_token")

      assert {:ok, user} =
               Ramshackle.Accounts.User
               |> Ash.Query.for_read(:get_by_email, %{email: "operator@example.com"})
               |> Ash.read_one(authorize?: false)

      assert to_string(user.email) == "operator@example.com"

      # The token is single use.
      conn = post(build_conn(), ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired or has already been used"
    end

    test "sends nothing to an email without an account, and does not say so", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/user/magic_link/request", %{
          "user" => %{"email" => "stranger@example.com"}
        })

      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "we sent it a sign-in link"
      assert_no_email_sent()
      assert [] = Ash.read!(Ramshackle.Accounts.User, authorize?: false)
    end

    test "a forged token does not sign in", %{conn: conn} do
      conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => "not-a-token"}})

      assert redirected_to(conn) == ~p"/sign-in"
      refute get_session(conn, "user_token")
    end
  end

  describe "DELETE /sign-out" do
    test "signs out", %{conn: conn} do
      conn = delete(conn, ~p"/sign-out")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "signed out"
    end
  end
end
