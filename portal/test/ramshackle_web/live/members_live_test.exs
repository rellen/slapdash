defmodule RamshackleWeb.Tenants.MembersLiveTest do
  use RamshackleWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ramshackle.Fixtures

  alias Ramshackle.Tenancy

  setup do
    acme = tenant("acme")
    admin = user("admin@example.com")
    engineer = user("engineer@example.com")
    member(admin, acme, :administrator)
    member(engineer, acme, :engineer)
    %{acme: acme, admin: admin, engineer: engineer}
  end

  test "an administrator adds a member and changes roles", %{
    conn: conn,
    admin: admin,
    engineer: engineer
  } do
    {:ok, view, html} = conn |> log_in(admin) |> live(~p"/tenants/acme/members")
    assert html =~ "engineer@example.com"

    view
    |> form("#member-form", form: %{email: "new@example.com", role: "engineer"})
    |> render_submit()

    assert render(view) =~ "Added new@example.com."
    assert render(view) =~ "new@example.com"

    [membership] =
      Tenancy.list_memberships!(authorize?: false, query: [filter: [user_id: engineer.id]])

    view
    |> form("#role-#{membership.id}", %{
      "membership_id" => membership.id,
      "role" => "administrator"
    })
    |> render_change()

    assert render(view) =~ "Role changed."

    assert [%{role: :administrator}] =
             Tenancy.list_memberships!(authorize?: false, query: [filter: [user_id: engineer.id]])
  end

  test "an engineer sees the members but no controls", %{conn: conn, engineer: engineer} do
    {:ok, _view, html} = conn |> log_in(engineer) |> live(~p"/tenants/acme/members")

    assert html =~ "admin@example.com"
    refute html =~ "Add a member"
    refute html =~ "Remove"
  end

  test "someone outside the tenant cannot open it", %{conn: conn} do
    tenant("globex")
    outsider = user()

    assert {:error, {:live_redirect, %{to: "/"}}} =
             conn |> log_in(outsider) |> live(~p"/tenants/acme/members")
  end
end
