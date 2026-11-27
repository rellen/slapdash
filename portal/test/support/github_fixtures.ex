defmodule Slapdash.Test.GitHubFixtures do
  @moduledoc """
  A test RSA key, a GitHub App connection and a fake GitHub API on
  `Req.Test`, for tests of `Slapdash.Providers.GitHub.App`.
  """

  alias Slapdash.Providers.GitHub.Client

  @doc "A new RSA private key, and the same key in PEM format."
  def rsa_key do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    {key, pem}
  end

  @doc "A GitHub App connection for a tenant, with app id 42."
  def github_connection(tenant, pem, attrs \\ %{}) do
    Slapdash.Connections.add_connection!(
      Map.merge(
        %{
          tenant_id: tenant.id,
          name: "GitHub #{System.unique_integer([:positive])}",
          provider: "github_app",
          config: %{"app_id" => "42"},
          secrets: %{"private_key" => pem, "webhook_secret" => "whsec"}
        },
        attrs
      ),
      authorize?: false
    )
  end

  @doc """
  Stubs the GitHub API for one repository. `comments` are the comments
  that are already on the pull request. Each request is sent to the test
  process as `{:github, method, path, body}`.
  """
  def stub_github(path, comments \\ []) do
    test = self()

    Req.Test.stub(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:github, conn.method, conn.request_path, body})

      case {conn.method, conn.request_path} do
        {"GET", "/repos/" <> rest} when rest == path <> "/installation" ->
          Req.Test.json(conn, %{"id" => 777})

        {"POST", "/app/installations/777/access_tokens"} ->
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"token" => "ghs_installation"})

        {"GET", "/repos/" <> _} ->
          Req.Test.json(conn, comments)

        {"POST", "/repos/" <> _} ->
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 1})
      end
    end)
  end
end
