defmodule Slapdash.Connections.ConnectionTest do
  use Slapdash.DataCase, async: true

  import Slapdash.Fixtures

  alias Slapdash.Connections

  defp attrs(tenant, overrides \\ %{}) do
    Map.merge(
      %{
        tenant_id: tenant.id,
        name: "Fake",
        provider: "fake",
        config: %{"account" => " 42 ", "url" => "https://fake.example/api/", "extra" => "x"},
        secrets: %{"token" => "s3cret"}
      },
      overrides
    )
  end

  setup do
    tenant = tenant()
    admin = user()
    member(admin, tenant, :administrator)
    %{tenant: tenant, admin: admin}
  end

  test "an administrator adds a connection, and the provider casts the settings", ctx do
    assert {:ok, connection} = Connections.add_connection(attrs(ctx.tenant), actor: ctx.admin)

    # Unknown keys go, values are cast, and the URL loses its trailing slash.
    assert connection.config == %{"account" => 42, "url" => "https://fake.example/api"}
    assert Connections.secrets(connection) == %{"token" => "s3cret"}
    refute inspect(connection) =~ "s3cret"

    %{rows: [[stored]]} = Repo.query!("SELECT encrypted_secrets FROM connections")
    refute stored =~ "s3cret"
  end

  test "a blank setting takes the field's default", ctx do
    {:ok, connection} =
      Connections.add_connection(attrs(ctx.tenant, %{config: %{"account" => "1", "url" => ""}}),
        actor: ctx.admin
      )

    assert connection.config["url"] == "https://fake.example"
  end

  test "the provider's fields are checked", ctx do
    assert {:error, error} =
             Connections.add_connection(
               attrs(ctx.tenant, %{config: %{"account" => "many"}, secrets: %{"token" => ""}}),
               actor: ctx.admin
             )

    messages = Enum.map(error.errors, &Exception.message/1) |> Enum.join("\n")
    assert messages =~ "Account number must be a whole number"
    assert messages =~ "API token is required"
  end

  test "the provider's own validation runs", ctx do
    assert {:error, error} =
             Connections.add_connection(attrs(ctx.tenant, %{secrets: %{"token" => "bad1"}}),
               actor: ctx.admin
             )

    assert Exception.message(error) =~ "API token is refused"
  end

  test "an unknown provider is refused", ctx do
    assert {:error, error} =
             Connections.add_connection(attrs(ctx.tenant, %{provider: "nope"}), actor: ctx.admin)

    assert Exception.message(error) =~ "is not known"
  end

  test "a reconfigure with a blank secret keeps the stored secret", ctx do
    connection = connection(ctx.tenant)

    {:ok, connection} =
      Connections.reconfigure_connection(
        connection,
        %{name: "Renamed", config: %{"account" => "9"}, secrets: %{"token" => ""}},
        actor: ctx.admin
      )

    assert connection.name == "Renamed"
    assert connection.config["account"] == 9
    assert Connections.secrets(connection) == %{"token" => "t0ken"}

    {:ok, connection} =
      Connections.reconfigure_connection(connection, %{secrets: %{"token" => "new"}},
        actor: ctx.admin
      )

    assert Connections.secrets(connection) == %{"token" => "new"}
  end

  test "nobody reads secrets through an action, root included", ctx do
    connection(ctx.tenant)

    for actor <- [ctx.admin, root()] do
      [connection] = Connections.list_connections!(actor: actor, load: [:secrets])
      assert %Ash.ForbiddenField{} = connection.secrets
    end
  end

  test "engineers read connections but do not change them", ctx do
    engineer = user()
    member(engineer, ctx.tenant, :engineer)
    connection = connection(ctx.tenant)

    assert [%{id: id}] = Connections.list_connections!(actor: engineer)
    assert id == connection.id

    assert {:error, %Ash.Error.Forbidden{}} =
             Connections.add_connection(attrs(ctx.tenant), actor: engineer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Connections.remove_connection(connection, actor: engineer)
  end

  test "a tenant role does not reach another tenant's connections", ctx do
    other = tenant()
    connection(other)

    assert Connections.list_connections!(actor: ctx.admin) == []

    assert {:error, %Ash.Error.Forbidden{}} =
             Connections.add_connection(attrs(other), actor: ctx.admin)
  end

  test "changes keep a version history without secrets", ctx do
    connection = connection(ctx.tenant)

    {:ok, _} =
      Connections.reconfigure_connection(connection, %{secrets: %{"token" => "v2"}},
        actor: ctx.admin
      )

    %{rows: rows} = Repo.query!("SELECT changes::text FROM connections_versions")
    assert length(rows) == 2
    refute Enum.any?(rows, fn [changes] -> changes =~ "t0ken" or changes =~ "v2" end)
  end
end
