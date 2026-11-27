defmodule Slapdash.Repositories.RepositoryTest do
  use Slapdash.DataCase, async: true

  import Slapdash.Fixtures

  alias Slapdash.Repositories

  setup do
    tenant = tenant()
    admin = user()
    member(admin, tenant, :administrator)
    %{tenant: tenant, admin: admin, connection: connection(tenant)}
  end

  defp add(ctx, path, opts \\ []) do
    connection = Keyword.get(opts, :connection, ctx.connection)

    Repositories.add_repository(
      %{tenant_id: ctx.tenant.id, connection_id: connection.id, path: path},
      actor: Keyword.get(opts, :actor, ctx.admin)
    )
  end

  test "an administrator adds a repository, and it is found by path", ctx do
    assert {:ok, repository} = add(ctx, "Acme/Widgets")

    assert {:ok, found} =
             Repositories.find_repository(ctx.connection.id, "acme/widgets", authorize?: false)

    assert found.id == repository.id

    assert Repositories.web_url(Ash.load!(repository, :connection, authorize?: false)) ==
             "https://fake.example/Acme/Widgets"
  end

  test "the provider checks the path", ctx do
    assert {:error, error} = add(ctx, "not a path")
    assert Exception.message(error) =~ "must look like owner/name"
  end

  test "a path is added at most once for each connection", ctx do
    assert {:ok, _} = add(ctx, "acme/widgets")
    assert {:error, error} = add(ctx, "ACME/widgets")
    assert Exception.message(error) =~ "is already added"
  end

  test "the connection must belong to the same tenant", ctx do
    other_connection = connection(tenant())

    # Root passes authorization, so this checks the connection rule itself.
    assert {:error, error} = add(ctx, "acme/widgets", connection: other_connection, actor: root())
    assert Exception.message(error) =~ "is not valid"
  end

  test "engineers read repositories but do not add them", ctx do
    engineer = user()
    member(engineer, ctx.tenant, :engineer)
    repository(ctx.connection)

    assert [_] = Repositories.list_repositories!(actor: engineer)
    assert {:error, %Ash.Error.Forbidden{}} = add(ctx, "acme/other", actor: engineer)
  end

  test "removing a connection removes its repositories", ctx do
    repository(ctx.connection)
    :ok = Slapdash.Connections.remove_connection(ctx.connection, actor: ctx.admin)
    assert Repositories.list_repositories!(authorize?: false) == []
  end
end
