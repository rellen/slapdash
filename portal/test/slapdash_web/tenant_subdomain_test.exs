defmodule SlapdashWeb.TenantSubdomainTest do
  use SlapdashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slapdash.Fixtures

  alias Slapdash.Instance

  defp configure(subdomains?) do
    Instance.configure_settings!(
      %{public_url: "https://example.com", tenant_subdomains: subdomains?},
      authorize?: false
    )
  end

  setup do
    acme = tenant("acme")
    admin = user()
    member(admin, acme, :administrator)
    %{acme: acme, admin: admin}
  end

  describe "with tenant subdomains on" do
    setup do
      configure(true)
      :ok
    end

    test "the host names the tenant" do
      assert Instance.tenant_parent_host() == "example.com"
      assert Instance.tenant_slug_for_host("acme.example.com") == "acme"
      assert Instance.tenant_slug_for_host("ACME.Example.com") == "acme"
      assert Instance.tenant_slug_for_host("example.com") == nil
      assert Instance.tenant_slug_for_host("a.b.example.com") == nil
      assert Instance.tenant_slug_for_host("acme.example.org") == nil
      assert Instance.tenant_url("acme", "/members") == "https://acme.example.com/members"
    end

    test "tenant pages are at the root of the tenant subdomain", ctx do
      conn = %{log_in(ctx.conn, ctx.admin) | host: "acme.example.com"}
      {:ok, view, html} = live(conn, "/connections")

      assert html =~ "This tenant has no connections yet."
      assert html =~ ~s|href="/members"|
      assert has_element?(view, ~s|a[href="/connections/new/fake"]|)
    end

    test "the path form works on the subdomain host too", ctx do
      conn = %{log_in(ctx.conn, ctx.admin) | host: "acme.example.com"}
      {:ok, _view, html} = live(conn, "/acme/members")
      assert html =~ ~s|href="/acme/connections"|
    end

    test "an unknown subdomain sends the person home", ctx do
      conn = %{log_in(ctx.conn, ctx.admin) | host: "nope.example.com"}
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/members")
    end

    test "the session cookie covers the subdomains", ctx do
      conn = ctx.conn |> init_test_session(%{}) |> get(~p"/sign-in")
      cookie = conn |> get_resp_header("set-cookie") |> Enum.join("\n")
      assert cookie =~ "domain=example.com"
    end

    test "LiveView accepts origins on tenant subdomains" do
      assert SlapdashWeb.Origin.allowed?(URI.parse("https://acme.example.com"))
      assert SlapdashWeb.Origin.allowed?(URI.parse("https://example.com"))
      refute SlapdashWeb.Origin.allowed?(URI.parse("https://acme.example.org"))
      refute SlapdashWeb.Origin.allowed?(URI.parse("http://acme.example.com"))
    end
  end

  describe "with tenant subdomains off" do
    setup do
      configure(false)
      :ok
    end

    test "hosts do not name tenants, and URLs use the path" do
      assert Instance.tenant_slug_for_host("acme.example.com") == nil
      assert Instance.tenant_url("acme", "/members") == "https://example.com/acme/members"
      refute SlapdashWeb.Origin.allowed?(URI.parse("https://acme.example.com"))
    end

    test "the root form of a tenant page needs a tenant subdomain", ctx do
      conn = %{log_in(ctx.conn, ctx.admin) | host: "acme.example.com"}
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/members")
    end
  end
end
