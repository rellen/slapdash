defmodule SlapdashWeb.GitHubGreeterTest do
  @moduledoc """
  The whole path with a fake GitHub API: a signed GitHub webhook for an
  opened pull request reaches the Greeter bot, and the bot's comment goes
  to the GitHub API one time.
  """
  use SlapdashWeb.ConnCase, async: true

  import Slapdash.Fixtures
  import Slapdash.Test.GitHubFixtures

  alias Slapdash.Bots

  setup do
    {_key, pem} = rsa_key()
    tenant = tenant()
    connection = github_connection(tenant, pem)
    repository = repository(connection, "octo/hello")
    enrollment(repository, "greeter")
    %{tenant: tenant, connection: connection}
  end

  defp deliver(conn, connection, delivery_id) do
    body =
      Jason.encode!(%{
        "action" => "opened",
        "number" => 9,
        "pull_request" => %{
          "number" => 9,
          "title" => "Add a feature",
          "user" => %{"login" => "mona"}
        },
        "repository" => %{"full_name" => "octo/hello"},
        "sender" => %{"login" => "mona"},
        "installation" => %{"id" => 777}
      })

    signature =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, "whsec", body) |> Base.encode16(case: :lower))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-delivery", delivery_id)
    |> put_req_header("x-github-event", "pull_request")
    |> put_req_header("x-hub-signature-256", signature)
    |> post(~p"/webhooks/#{connection.id}", body)
  end

  defp flush_github do
    receive do
      {:github, _, _, _} -> flush_github()
    after
      0 -> :ok
    end
  end

  defp drain do
    Oban.drain_queue(queue: :webhooks)
    Oban.drain_queue(queue: :bots)
  end

  test "an opened pull request gets the fixed comment", ctx do
    stub_github("octo/hello")

    assert response(deliver(ctx.conn, ctx.connection, "guid-1"), 202)
    drain()

    assert_received {:github, "POST", "/repos/octo/hello/issues/9/comments", body}

    assert Jason.decode!(body)["body"] ==
             Bots.Greeter.message() <> "\n\n<!-- slapdash:greeter -->"

    assert [%{status: :succeeded, bot: "greeter"}] =
             Bots.list_runs!(tenant: ctx.tenant, authorize?: false)
  end

  test "the same delivery again does not comment again", ctx do
    stub_github("octo/hello")

    deliver(ctx.conn, ctx.connection, "guid-1")
    drain()
    assert_received {:github, "POST", "/repos/octo/hello/issues/9/comments", _}
    flush_github()

    deliver(build_conn(), ctx.connection, "guid-1")
    drain()
    refute_received {:github, _, _, _}
    assert [_] = Bots.list_runs!(tenant: ctx.tenant, authorize?: false)
  end

  test "a new delivery for a pull request that has the comment does not comment again", ctx do
    stub_github("octo/hello", [
      %{"body" => "Hi\n\n<!-- slapdash:greeter -->", "performed_via_github_app" => %{"id" => 42}}
    ])

    deliver(ctx.conn, ctx.connection, "guid-2")
    drain()

    refute_received {:github, "POST", "/repos/octo/hello/issues/9/comments", _}

    assert [%{status: :succeeded, actions: [%{"result" => "exists"}]}] =
             Bots.list_runs!(tenant: ctx.tenant, authorize?: false)
  end
end
