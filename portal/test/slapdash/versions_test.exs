defmodule Slapdash.VersionsTest do
  use Slapdash.DataCase, async: true

  import Slapdash.Fixtures

  alias Slapdash.{Instance, Tenancy}
  alias Slapdash.Instance.{GitHubOAuthApp, MailProvider}
  alias Slapdash.Test.TenantNote

  require Ash.Query

  defp versions(record, actor) do
    record
    |> Ash.load!(:paper_trail_versions, actor: actor)
    |> Map.fetch!(:paper_trail_versions)
    |> Enum.sort_by(& &1.version_inserted_at, DateTime)
  end

  defp versions_of(version_resource, id) do
    version_resource
    |> Ash.Query.filter(version_source_id == ^id)
    |> Ash.read!(authorize?: false)
  end

  test "a create and an update each record a version with the action and the actor" do
    root = root()
    {:ok, tenant} = Tenancy.create_tenant("Acme", "acme", actor: root)
    {:ok, tenant} = Tenancy.rename_tenant(tenant, "Acme Ltd", actor: root)

    assert [created, renamed] = versions(tenant, root)

    assert created.version_action_type == :create
    assert created.version_action_name == :create
    assert created.actor_id == root.id
    assert created.changes["name"] == "Acme"
    assert created.changes["schema"] == "tenant_acme"
    refute Map.has_key?(created.changes, "inserted_at")

    assert renamed.version_action_type == :update
    assert renamed.version_action_name == :rename
    assert renamed.actor_id == root.id
    assert renamed.changes["name"] == "Acme Ltd"
  end

  test "a user created by adding a member records who added them" do
    root = root()
    tenant = tenant()

    {:ok, membership} =
      Tenancy.add_member(tenant.id, "new@example.com", :engineer, actor: root)

    assert [%{version_action_name: :add, actor_id: actor_id}] = versions(membership, root)
    assert actor_id == root.id

    {:ok, user} = Slapdash.Accounts.get_user_by_email("new@example.com", authorize?: false)
    assert [%{version_action_name: :create_by_email, actor_id: ^actor_id}] = versions(user, root)
  end

  test "mail provider versions do not hold the secret, encrypted or not" do
    root = root()

    {:ok, provider} =
      Instance.configure_mail_provider(
        %{adapter: :postmark, secret: "postmark-api-key"},
        actor: root
      )

    {:ok, provider} =
      Instance.reconfigure_mail_provider(provider, %{secret: "new-api-key"}, actor: root)

    assert [created, _updated] = versions(provider, root)
    assert created.changes["adapter"] == "postmark"

    stored = Repo.query!("SELECT changes::text FROM mail_provider_versions")
    assert length(stored.rows) == 2

    for [changes] <- stored.rows do
      refute changes =~ "api-key"
      refute changes =~ "secret"
    end
  end

  test "GitHub OAuth app versions do not hold the client secret, and outlive the app" do
    root = root()

    {:ok, app} =
      Instance.configure_github_oauth_app(
        %{client_id: "Iv1.abc", client_secret: "github-client-secret"},
        actor: root
      )

    :ok = Instance.remove_github_oauth_app(app, actor: root)

    assert [created, removed] =
             GitHubOAuthApp.Version
             |> versions_of(app.id)
             |> Enum.sort_by(& &1.version_inserted_at, DateTime)

    assert created.changes["client_id"] == "Iv1.abc"
    assert removed.version_action_type == :destroy
    assert removed.actor_id == root.id

    %{rows: rows} = Repo.query!("SELECT changes::text FROM github_oauth_app_versions")

    for [changes] <- rows do
      refute changes =~ "github-client-secret"
      refute changes =~ "client_secret"
    end
  end

  test "only root reads versions of install-wide resources" do
    root = root()
    tenant = tenant()
    admin = user()
    member(admin, tenant, :administrator)

    {:ok, _} = Instance.configure_mail_provider(%{adapter: :postmark, secret: "k"}, actor: root)

    assert [_] = Ash.read!(MailProvider.Version, actor: root)
    assert [] = Ash.read!(MailProvider.Version, actor: admin)
    assert [] = Ash.read!(Tenancy.Tenant.Version, actor: admin)
    assert [] = Ash.read!(Tenancy.Tenant.Version, actor: user())
    assert [] = Ash.read!(Tenancy.Tenant.Version)
  end

  test "nobody writes versions through the version resource" do
    root = root()

    assert {:error, %Ash.Error.Forbidden{}} =
             MailProvider.Version
             |> Ash.Changeset.for_create(:create, %{
               version_action_type: :create,
               version_action_name: :configure,
               version_source_id: 1,
               changes: %{}
             })
             |> Ash.create(actor: root)
  end

  test "versions of a tenant's data stay in that tenant" do
    root = root()
    acme = tenant()
    other = tenant()

    note =
      TenantNote
      |> Ash.Changeset.for_create(:create, %{body: "hello"}, tenant: acme)
      |> Ash.create!(authorize?: false, actor: root)

    assert [%{actor_id: actor_id}] =
             Ash.read!(TenantNote.Version, tenant: acme, authorize?: false)

    assert actor_id == root.id
    assert note.id

    assert [] = Ash.read!(TenantNote.Version, tenant: other, authorize?: false)
  end
end
