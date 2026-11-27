defmodule SlapdashWeb.WebhookControllerTest do
  use SlapdashWeb.ConnCase, async: true
  use Oban.Testing, repo: Slapdash.Repo

  import Slapdash.Fixtures

  alias Slapdash.Bots
  alias Slapdash.Bots.Runners.InProcess
  alias Slapdash.Test.FakeProvider
  alias Slapdash.Webhooks
  alias Slapdash.Webhooks.ProcessDelivery

  setup do
    tenant = tenant()
    connection = connection(tenant)
    repository = repository(connection)
    %{tenant: tenant, connection: connection, repository: repository}
  end

  defp payload(attrs \\ %{}) do
    Map.merge(
      %{
        "action" => "opened",
        "repository" => "acme/widgets",
        "number" => 12,
        "title" => "Make it work"
      },
      attrs
    )
  end

  defp post_webhook(conn, connection, payload, opts \\ []) do
    body = Jason.encode!(payload)
    token = Keyword.get(opts, :token, "t0ken")

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-fake-delivery", Keyword.get(opts, :delivery, "d-1"))
    |> put_req_header("x-fake-event", Keyword.get(opts, :event, "pull_request"))
    |> put_req_header("x-fake-signature", FakeProvider.sign(body, token))
    |> post(~p"/webhooks/#{connection.id}", body)
  end

  test "a signed delivery is stored and queued", ctx do
    conn = post_webhook(ctx.conn, ctx.connection, payload())
    assert response(conn, 202) == ""

    [delivery] = Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false)
    assert delivery.external_id == "d-1"
    assert delivery.event == "pull_request"
    assert delivery.payload["number"] == 12
    assert delivery.status == :received
    assert_enqueued(worker: ProcessDelivery, args: %{delivery_id: delivery.id})
  end

  test "the same delivery twice is stored once", ctx do
    assert response(post_webhook(ctx.conn, ctx.connection, payload()), 202)
    assert response(post_webhook(build_conn(), ctx.connection, payload()), 202)

    assert [_] = Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false)
    assert [_] = all_enqueued(worker: ProcessDelivery)
  end

  test "a bad signature is refused and nothing is stored", ctx do
    conn = post_webhook(ctx.conn, ctx.connection, payload(), token: "wrong")
    assert response(conn, 401)
    assert Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false) == []
  end

  test "an unknown or malformed connection id is not found", ctx do
    assert response(post_webhook(ctx.conn, %{id: Ecto.UUID.generate()}, payload()), 404)
    assert response(post_webhook(build_conn(), %{id: "not-a-uuid"}, payload()), 404)
  end

  test "a delivery without the provider's headers is a bad request", ctx do
    body = Jason.encode!(payload())

    conn =
      ctx.conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-fake-signature", FakeProvider.sign(body, "t0ken"))
      |> post(~p"/webhooks/#{ctx.connection.id}", body)

    assert response(conn, 400)
  end

  describe "processing" do
    test "an event on a repository with a bot starts a run", ctx do
      enrollment(ctx.repository)
      post_webhook(ctx.conn, ctx.connection, payload())
      [delivery] = Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false)

      assert :ok =
               perform_job(ProcessDelivery, %{delivery_id: delivery.id, tenant_id: ctx.tenant.id})

      assert %{status: :processed, event_count: 1} =
               Webhooks.get_delivery!(delivery.id, tenant: ctx.tenant, authorize?: false)

      [run] = Bots.list_runs!(tenant: ctx.tenant, authorize?: false)
      assert run.event_id == "webhook:#{delivery.id}:0"
      assert run.event["subject"]["number"] == 12
      assert_enqueued(worker: InProcess, args: %{run_id: run.id})

      # A second pass over the same delivery starts no new run.
      assert :ok =
               perform_job(ProcessDelivery, %{delivery_id: delivery.id, tenant_id: ctx.tenant.id})

      assert [_] = Bots.list_runs!(tenant: ctx.tenant, authorize?: false)
    end

    test "an event for a repository that was not added is ignored", ctx do
      enrollment(ctx.repository)
      post_webhook(ctx.conn, ctx.connection, payload(%{"repository" => "acme/unknown"}))
      [delivery] = Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false)

      assert :ok =
               perform_job(ProcessDelivery, %{delivery_id: delivery.id, tenant_id: ctx.tenant.id})

      assert %{status: :ignored} =
               Webhooks.get_delivery!(delivery.id, tenant: ctx.tenant, authorize?: false)

      assert Bots.list_runs!(tenant: ctx.tenant, authorize?: false) == []
    end

    test "an event that no bot reacts to is ignored", ctx do
      post_webhook(ctx.conn, ctx.connection, payload(), event: "ping")
      [delivery] = Webhooks.list_deliveries!(tenant: ctx.tenant, authorize?: false)

      assert :ok =
               perform_job(ProcessDelivery, %{delivery_id: delivery.id, tenant_id: ctx.tenant.id})

      assert %{status: :ignored} =
               Webhooks.get_delivery!(delivery.id, tenant: ctx.tenant, authorize?: false)
    end
  end
end
