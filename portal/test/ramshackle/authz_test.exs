defmodule Ramshackle.AuthzTest do
  use Ramshackle.DataCase, async: true

  import Ramshackle.Fixtures

  alias Ramshackle.{Accounts, Instance, Tenancy}

  setup do
    acme = tenant("acme")
    globex = tenant("globex")

    admin = user("admin@example.com")
    engineer = user("engineer@example.com")
    outsider = user("outsider@example.com")

    member(admin, acme, :administrator)
    member(engineer, acme, :engineer)
    member(outsider, globex, :engineer)

    %{
      acme: acme,
      globex: globex,
      admin: admin,
      engineer: engineer,
      outsider: outsider,
      root: root()
    }
  end

  defp slugs(tenants), do: tenants |> Enum.map(& &1.slug) |> Enum.sort()

  describe "tenants" do
    test "root sees every tenant", %{root: root} do
      assert slugs(Tenancy.list_tenants!(actor: root)) == ["acme", "globex"]
    end

    test "members see only their own tenants", %{admin: admin, outsider: outsider} do
      assert slugs(Tenancy.list_tenants!(actor: admin)) == ["acme"]
      assert slugs(Tenancy.list_tenants!(actor: outsider)) == ["globex"]
    end

    test "nobody signed in sees nothing" do
      assert Tenancy.list_tenants!(actor: nil) == []
    end

    test "only root creates tenants", %{root: root, admin: admin} do
      assert {:ok, _} = Tenancy.create_tenant("Initech", "initech", actor: root)
      assert {:error, %Ash.Error.Forbidden{}} = Tenancy.create_tenant("X", "x", actor: admin)
    end

    test "an administrator renames their tenant, not another", %{
      admin: admin,
      acme: acme,
      globex: globex
    } do
      assert {:ok, %{name: "ACME"}} = Tenancy.rename_tenant(acme, "ACME", actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.rename_tenant(globex, "Nope", actor: admin)
    end

    test "an engineer cannot rename their tenant", %{engineer: engineer, acme: acme} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.rename_tenant(acme, "Nope", actor: engineer)
    end
  end

  describe "memberships" do
    test "an administrator adds members to their tenant only", %{
      admin: admin,
      acme: acme,
      globex: globex
    } do
      assert {:ok, membership} =
               Tenancy.add_member(acme.id, "new@example.com", :engineer, actor: admin)

      assert membership.tenant_id == acme.id
      assert {:ok, _user} = Accounts.get_user_by_email("new@example.com", authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.add_member(globex.id, "sneaky@example.com", :administrator, actor: admin)

      # Refused before the user was created.
      assert {:ok, nil} =
               Accounts.get_user_by_email("sneaky@example.com",
                 authorize?: false,
                 not_found_error?: false
               )
    end

    test "an engineer reads the tenant's members but cannot add any", %{
      engineer: engineer,
      acme: acme
    } do
      emails =
        Tenancy.list_memberships!(actor: engineer, load: [:user])
        |> Enum.map(&to_string(&1.user.email))
        |> Enum.sort()

      assert emails == ["admin@example.com", "engineer@example.com"]

      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.add_member(acme.id, "x@example.com", :engineer, actor: engineer)
    end

    test "a user with no role in a tenant sees only their own memberships", %{outsider: outsider} do
      assert [%{user_id: id}] = Tenancy.list_memberships!(actor: outsider)
      assert id == outsider.id
    end

    test "an administrator changes roles and removes members in their tenant", %{
      admin: admin,
      engineer: engineer,
      outsider: outsider
    } do
      [engineer_membership] =
        Tenancy.list_memberships!(authorize?: false, query: [filter: [user_id: engineer.id]])

      [outsider_membership] =
        Tenancy.list_memberships!(authorize?: false, query: [filter: [user_id: outsider.id]])

      assert {:ok, %{role: :administrator}} =
               Tenancy.change_member_role(engineer_membership, :administrator, actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.change_member_role(outsider_membership, :administrator, actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Tenancy.remove_member(outsider_membership, actor: admin)

      assert :ok = Tenancy.remove_member(engineer_membership, actor: admin)
    end
  end

  describe "users" do
    test "people see themselves and colleagues, root sees everyone", %{
      admin: admin,
      outsider: outsider,
      root: root
    } do
      emails = fn actor ->
        Ramshackle.Accounts.User
        |> Ash.read!(actor: actor)
        |> Enum.map(&to_string(&1.email))
        |> Enum.sort()
      end

      assert emails.(admin) == ["admin@example.com", "engineer@example.com"]
      assert emails.(outsider) == ["outsider@example.com"]
      assert "outsider@example.com" in emails.(root)
      assert to_string(root.email) in emails.(root)
    end
  end

  describe "instance settings" do
    test "only root reads and changes them", %{root: root, admin: admin} do
      assert {:ok, settings} =
               Instance.configure_settings(%{public_url: "https://bot.example.com/"}, actor: root)

      assert settings.public_url == "https://bot.example.com"
      assert {:ok, %{public_url: "https://bot.example.com"}} = Instance.get_settings(actor: root)

      assert {:error, _} = Instance.get_settings(actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Instance.reconfigure_settings(settings, %{public_url: "https://evil.example"},
                 actor: admin
               )
    end

    test "the public URL must be a bare http or https URL", %{root: root} do
      for bad <- [
            "ftp://x.example",
            "https://x.example/path",
            "not a url",
            "https://x.example?q=1"
          ] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Instance.configure_settings(%{public_url: bad}, actor: root)
      end
    end
  end
end
