defmodule Slapdash.Tenancy.TenantTest do
  use Slapdash.DataCase, async: true

  import Slapdash.Fixtures

  alias Slapdash.Test.TenantNote

  defp schema_exists?(schema) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM information_schema.schemata WHERE schema_name = $1", [
        schema
      ])

    count == 1
  end

  test "creating a tenant creates its schema, with migration bookkeeping" do
    tenant = tenant("acme")

    assert tenant.schema == "tenant_acme"
    assert schema_exists?("tenant_acme")
    assert %{rows: [[_]]} = Repo.query!("SELECT count(*) FROM tenant_acme.schema_migrations")
    assert "tenant_acme" in Repo.all_tenants()
  end

  test "the slug must be a safe identifier" do
    for bad <- [
          "Acme",
          "1acme",
          "ac-me",
          "acme\"; DROP SCHEMA public; --",
          String.duplicate("a", 41)
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Slapdash.Tenancy.create_tenant("Bad", bad, authorize?: false)
    end
  end

  test "the slug is unique" do
    tenant("acme")

    assert {:error, %Ash.Error.Invalid{}} =
             Slapdash.Tenancy.create_tenant("Again", "acme", authorize?: false)
  end

  test "a tenant converts to its schema only for context-multitenant resources" do
    tenant = tenant("acme")

    assert Ash.ToTenant.to_tenant(tenant, TenantNote) == "tenant_acme"
    assert Ash.ToTenant.to_tenant(tenant, Slapdash.Tenancy.Membership) == tenant.id
  end

  describe "tenant data" do
    setup do
      acme = tenant("acme")
      globex = tenant("globex")
      engineer = user()
      member(engineer, acme, :engineer)
      %{acme: acme, globex: globex, engineer: engineer}
    end

    test "a tenant role reaches its own tenant's data and no other", %{
      acme: acme,
      globex: globex,
      engineer: engineer
    } do
      admin = user()
      member(admin, acme, :administrator)

      for tenant <- [acme, globex] do
        Ash.create!(TenantNote, %{body: tenant.slug}, tenant: tenant, authorize?: false)
      end

      assert [%{body: "acme"}] = Ash.read!(TenantNote, tenant: acme, actor: admin)
      assert [] = Ash.read!(TenantNote, tenant: globex, actor: admin)

      assert {:ok, _} = Ash.create(TenantNote, %{body: "new"}, tenant: acme, actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(TenantNote, %{body: "new"}, tenant: globex, actor: admin)

      # Engineers hold no tenant_note permission.
      assert [] = Ash.read!(TenantNote, tenant: acme, actor: engineer)

      # Root reaches every tenant.
      root = root()
      assert [_] = Ash.read!(TenantNote, tenant: globex, actor: root)
    end
  end
end
