defmodule SlapdashWeb.Tenants.RepositoriesLiveTest do
  use SlapdashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slapdash.Fixtures

  setup do
    acme = tenant("acme")
    admin = user("admin@example.com")
    member(admin, acme, :administrator)
    %{acme: acme, admin: admin}
  end

  test "the page asks for a connection first", ctx do
    {:ok, _view, html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/tenants/acme/repositories")
    assert html =~ "Add a connection that can host repositories first"
  end

  test "an administrator adds and removes a repository", ctx do
    connection = connection(ctx.acme, %{name: "Fake host"})
    {:ok, view, _html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/tenants/acme/repositories")

    html =
      view
      |> form("#repository-form", form: %{connection_id: connection.id, path: "no"})
      |> render_submit()

    assert html =~ "must look like owner/name"

    view
    |> form("#repository-form", form: %{connection_id: connection.id, path: "acme/widgets"})
    |> render_submit()

    html = render(view)
    assert html =~ "Added acme/widgets."
    assert html =~ ~s|href="https://fake.example/acme/widgets"|
    assert html =~ "Fake host"

    [repository] = Slapdash.Repositories.list_repositories!(authorize?: false)
    view |> element("#repository-#{repository.id} button", "Remove") |> render_click()
    assert render(view) =~ "This tenant has no repositories yet."
  end

  test "an administrator turns a bot on and off for a repository", ctx do
    repository = repository(connection(ctx.acme))
    {:ok, view, html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/tenants/acme/repositories")
    assert html =~ "Echo: off"

    view |> element("button", "Turn on Echo for acme/widgets") |> render_click()
    assert render(view) =~ "Echo: on"
    assert [_] = Slapdash.Bots.list_enrollments!(tenant: ctx.acme, authorize?: false)

    view |> element("#repository-#{repository.id} button", "Turn off") |> render_click()
    assert render(view) =~ "Echo: off"
    assert [] = Slapdash.Bots.list_enrollments!(tenant: ctx.acme, authorize?: false)
  end
end
