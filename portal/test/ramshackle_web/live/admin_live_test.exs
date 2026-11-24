defmodule RamshackleWeb.AdminLiveTest do
  use RamshackleWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ramshackle.Fixtures

  alias Ramshackle.{Instance, Secrets}

  describe "access" do
    test "signed-out visitors are sent to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/admin")
    end

    test "people who are not root are turned away", %{conn: conn} do
      user = user()
      member(user, tenant(), :administrator)

      assert {:error, {:redirect, %{to: "/", flash: %{"error" => message}}}} =
               conn |> log_in(user) |> live(~p"/admin")

      assert message =~ "Only root"
    end
  end

  describe "as root" do
    setup %{conn: conn} do
      %{conn: log_in(conn, root("root@example.com"))}
    end

    test "saves the settings", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")
      assert html =~ "Public URL"

      view
      |> form("#settings-form", form: %{public_url: "https://bot.example.com/"})
      |> render_submit()

      assert render(view) =~ "Settings saved."
      assert Instance.public_url() == "https://bot.example.com"
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      html =
        view
        |> form("#settings-form", form: %{public_url: "ftp://nope"})
        |> render_submit()

      assert html =~ "must be an http or https URL"
      assert html =~ ~s(aria-invalid="true")
    end

    test "sets up GitHub sign-in without showing the secret again", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/github")
      assert html =~ "GitHub sign-in is off"

      view
      |> form("#github-form", form: %{client_id: "Iv1.abc", client_secret: "very-secret"})
      |> render_submit()

      html = render(view)
      assert html =~ "GitHub sign-in saved."
      refute html =~ "very-secret"
      assert Secrets.github_configured?()

      view |> element("button", "Remove GitHub sign-in") |> render_click()
      refute Secrets.github_configured?()
    end

    test "sets up mail and sends a test message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/mail")

      view
      |> form("#mail-form", form: %{adapter: "postmark"})
      |> render_change()

      html = render(view)
      refute html =~ "Server"
      assert html =~ "API key"

      view
      |> form("#mail-form", form: %{adapter: "postmark", secret: "pm-key"})
      |> render_submit()

      assert render(view) =~ "Mail settings saved."
      refute render(view) =~ "pm-key"

      {:ok, provider} = Instance.get_mail_provider(authorize?: false)
      assert provider.adapter == :postmark
    end

    test "creates a tenant", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/tenants")
      assert html =~ "There are no tenants yet."

      view
      |> form("#tenant-form", form: %{name: "Acme", slug: "acme"})
      |> render_submit()

      html = render(view)
      assert html =~ "Created Acme."
      assert html =~ "tenant_acme"
    end
  end
end
