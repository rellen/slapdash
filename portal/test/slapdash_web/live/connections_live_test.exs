defmodule SlapdashWeb.Tenants.ConnectionsLiveTest do
  use SlapdashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slapdash.Fixtures

  alias Slapdash.Connections

  setup do
    acme = tenant("acme")
    admin = user("admin@example.com")
    engineer = user("engineer@example.com")
    member(admin, acme, :administrator)
    member(engineer, acme, :engineer)
    %{acme: acme, admin: admin, engineer: engineer}
  end

  test "an administrator adds a connection from the provider's fields", ctx do
    {:ok, view, html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/acme/connections")
    assert html =~ "This tenant has no connections yet."

    view |> element("a", "Add a Fake service connection") |> render_click()
    assert_patch(view, ~p"/acme/connections/new/fake")
    html = render(view)
    assert html =~ "Make a token in the fake service."
    assert html =~ "Note (optional)"

    html =
      view
      |> form("#connection-form",
        form: %{name: "Fake", config: %{account: "lots"}, secrets: %{token: ""}}
      )
      |> render_submit()

    assert html =~ "Account number must be a whole number"
    assert html =~ "API token is required"

    view
    |> form("#connection-form",
      form: %{name: "Fake", config: %{account: "12"}, secrets: %{token: "abc"}}
    )
    |> render_submit()

    [connection] = Connections.list_connections!(authorize?: false)
    assert_patch(view, ~p"/acme/connections/#{connection.id}")
    html = render(view)
    assert html =~ "Saved Fake."
    assert html =~ "/webhooks/#{connection.id}</code>"

    assert connection.tenant_id == ctx.acme.id
    assert connection.config["account"] == 12
    assert Connections.secrets(connection) == %{"token" => "abc"}
  end

  test "the change form never shows the stored secret", ctx do
    connection = connection(ctx.acme, %{secrets: %{"token" => "very-secret"}})

    {:ok, view, _html} =
      ctx.conn |> log_in(ctx.admin) |> live(~p"/acme/connections/#{connection.id}")

    html = render(view)
    assert html =~ "Leave a secret blank to keep the stored one."
    refute html =~ "very-secret"

    view
    |> form("#connection-form", form: %{name: "Renamed", secrets: %{token: ""}})
    |> render_submit()

    assert render(view) =~ "Saved Renamed."

    assert Connections.secrets(Connections.get_connection!(connection.id, authorize?: false)) ==
             %{"token" => "very-secret"}
  end

  test "an engineer sees connections but no controls", ctx do
    connection(ctx.acme, %{name: "Shared service"})

    {:ok, _view, html} =
      ctx.conn |> log_in(ctx.engineer) |> live(~p"/acme/connections")

    assert html =~ "Shared service"
    refute html =~ "Add a connection"
    refute html =~ "Remove"
  end

  test "an engineer cannot open the add form", ctx do
    assert {:error, {:live_redirect, %{flash: %{"error" => message}}}} =
             ctx.conn |> log_in(ctx.engineer) |> live(~p"/acme/connections/new/fake")

    assert message == "You cannot add that kind of connection."
  end

  test "a person outside the tenant is sent home", ctx do
    outsider = user()

    assert {:error, {:live_redirect, %{to: "/"}}} =
             ctx.conn |> log_in(outsider) |> live(~p"/acme/connections")
  end
end
