defmodule Slapdash.Fixtures do
  @moduledoc "Builds records for tests, skipping authorization."

  # Test support. It may reference every boundary.
  use Boundary, top_level?: true, check: [out: false]

  alias Slapdash.Accounts.User
  alias Slapdash.Tenancy

  def user(email \\ unique_email()) do
    {:ok, user} = Slapdash.Accounts.ensure_user(email)
    user
  end

  def root(email \\ unique_email()) do
    email |> user() |> Ash.update!(%{}, action: :make_root, authorize?: false)
  end

  def tenant(slug \\ unique_slug()) do
    Tenancy.create_tenant!("Tenant #{slug}", slug, authorize?: false)
  end

  def member(%User{} = user, tenant, role) do
    Tenancy.add_member!(tenant.id, to_string(user.email), role, authorize?: false)
  end

  def connection(tenant, attrs \\ %{}) do
    Slapdash.Connections.add_connection!(
      Map.merge(
        %{
          tenant_id: tenant.id,
          name: "Fake #{System.unique_integer([:positive])}",
          provider: "fake",
          config: %{"account" => "7"},
          secrets: %{"token" => "t0ken"}
        },
        attrs
      ),
      authorize?: false
    )
  end

  def repository(connection, path \\ "acme/widgets") do
    Slapdash.Repositories.add_repository!(
      %{tenant_id: connection.tenant_id, connection_id: connection.id, path: path},
      authorize?: false
    )
  end

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_slug, do: "t#{System.unique_integer([:positive])}"
end
