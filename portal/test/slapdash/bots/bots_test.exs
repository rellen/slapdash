defmodule Slapdash.BotsTest do
  use Slapdash.DataCase, async: true
  use Oban.Testing, repo: Slapdash.Repo

  import Slapdash.Fixtures

  alias Slapdash.Bots
  alias Slapdash.Bots.Runners.InProcess
  alias Slapdash.Test.FakeProvider

  setup do
    tenant = tenant()
    admin = user()
    member(admin, tenant, :administrator)
    connection = connection(tenant)
    repository = repository(connection)
    %{tenant: tenant, admin: admin, connection: connection, repository: repository}
  end

  describe "enrollment" do
    test "an administrator turns a known bot on for a repository", ctx do
      assert {:ok, enrollment} =
               Bots.enroll(ctx.repository.id, "echo", tenant: ctx.tenant, actor: ctx.admin)

      assert [%{id: id}] = Bots.list_enrollments!(tenant: ctx.tenant, actor: ctx.admin)
      assert id == enrollment.id

      assert {:error, error} =
               Bots.enroll(ctx.repository.id, "echo", tenant: ctx.tenant, actor: ctx.admin)

      assert Exception.message(error) =~ "is already on for this repository"
    end

    test "an enrollment keeps a version with its actor", ctx do
      {:ok, _} = Bots.enroll(ctx.repository.id, "echo", tenant: ctx.tenant, actor: ctx.admin)

      %{rows: [[actor_id]]} =
        Repo.query!("SELECT actor_id FROM #{ctx.tenant.schema}.enrollments_versions")

      assert Ecto.UUID.cast!(actor_id) == ctx.admin.id
    end

    test "an unknown bot is refused", ctx do
      assert {:error, error} =
               Bots.enroll(ctx.repository.id, "nope", tenant: ctx.tenant, actor: ctx.admin)

      assert Exception.message(error) =~ "is not known"
    end

    test "a repository of another tenant is refused", ctx do
      other = repository(connection(tenant()), "other/repo")

      assert {:error, error} =
               Bots.enroll(other.id, "echo", tenant: ctx.tenant, actor: root())

      assert Exception.message(error) =~ "is not valid"
    end

    test "engineers cannot turn bots on", ctx do
      engineer = user()
      member(engineer, ctx.tenant, :engineer)

      assert {:error, %Ash.Error.Forbidden{}} =
               Bots.enroll(ctx.repository.id, "echo", tenant: ctx.tenant, actor: engineer)
    end
  end

  describe "dispatch and the in-process runner" do
    test "an event starts one queued run for each enrolled bot", ctx do
      enrollment(ctx.repository)
      event = pull_request_opened(ctx.repository)

      assert {:ok, [run]} = Bots.dispatch(event, ctx.repository)
      assert run.status == :queued
      assert run.bot == "echo"
      assert run.runner == inspect(InProcess)
      assert_enqueued(worker: InProcess, args: %{run_id: run.id, tenant_id: ctx.tenant.id})
    end

    test "a repository with no enrolled bot starts no run", ctx do
      assert {:ok, []} = Bots.dispatch(pull_request_opened(ctx.repository), ctx.repository)
      refute_enqueued(worker: InProcess)
    end

    test "the same event twice gives one run and one job", ctx do
      enrollment(ctx.repository)
      event = pull_request_opened(ctx.repository)

      {:ok, [run]} = Bots.dispatch(event, ctx.repository)
      {:ok, [again]} = Bots.dispatch(event, ctx.repository)

      assert again.id == run.id
      assert [_job] = all_enqueued(worker: InProcess)
    end

    test "the runner runs the bot and performs its actions", ctx do
      enrollment(ctx.repository, "echo", %{"prefix" => "Seen"})
      {:ok, [run]} = Bots.dispatch(pull_request_opened(ctx.repository), ctx.repository)

      assert :ok = perform_job(InProcess, %{run_id: run.id, tenant_id: ctx.tenant.id})

      assert_received {:fake_comment, "acme/widgets", 7, "echo",
                       "Seen: Add a thing in acme/widgets"}

      run = Bots.get_run!(run.id, tenant: ctx.tenant, authorize?: false)
      assert run.status == :succeeded
      assert run.attempts == 1
      assert run.actions == [%{"action" => "comment", "key" => "echo", "result" => "created"}]
    end

    test "a second attempt does not comment again", ctx do
      enrollment(ctx.repository)
      {:ok, [run]} = Bots.dispatch(pull_request_opened(ctx.repository), ctx.repository)

      # The first attempt comments; a crash before it records success is the
      # same as a repeated run that has not succeeded.
      :ok = Bots.Execution.run(run, ctx.tenant)
      :ok = Bots.Execution.run(%{run | status: :failed}, ctx.tenant)

      assert [{"acme/widgets", 7, "echo", _body}] = FakeProvider.comments(ctx.connection)
      run = Bots.get_run!(run.id, tenant: ctx.tenant, authorize?: false)
      assert [%{"result" => "exists"}] = run.actions
    end

    @tag :capture_log
    test "a failed action fails the run, and a retry can follow", ctx do
      connection = connection(ctx.tenant, %{config: %{"account" => "1", "note" => "fail"}})
      repository = repository(connection, "acme/broken")
      enrollment(repository)
      {:ok, [run]} = Bots.dispatch(pull_request_opened(repository), repository)

      assert {:error, "the fake service refused the comment"} =
               perform_job(InProcess, %{run_id: run.id, tenant_id: ctx.tenant.id})

      run = Bots.get_run!(run.id, tenant: ctx.tenant, authorize?: false)
      assert run.status == :failed
      assert run.error == "the fake service refused the comment"
    end

    @tag :capture_log
    test "a bot that raises fails the run", ctx do
      enrollment(ctx.repository)
      event = pull_request_opened(ctx.repository, %{subject: nil})
      {:ok, [run]} = Bots.dispatch(event, ctx.repository)

      assert {:error, _message} =
               perform_job(InProcess, %{run_id: run.id, tenant_id: ctx.tenant.id})

      assert %{status: :failed, error: error} =
               Bots.get_run!(run.id, tenant: ctx.tenant, authorize?: false)

      assert error =~ "expected a map"
    end

    test "a run is cancelled when the bot was turned off", ctx do
      enrollment = enrollment(ctx.repository)
      {:ok, [run]} = Bots.dispatch(pull_request_opened(ctx.repository), ctx.repository)
      :ok = Bots.unenroll(enrollment, tenant: ctx.tenant, actor: ctx.admin)

      assert {:cancel, "the bot was turned off for this repository"} =
               perform_job(InProcess, %{run_id: run.id, tenant_id: ctx.tenant.id})

      assert %{status: :failed, enrollment_id: nil} =
               Bots.get_run!(run.id, tenant: ctx.tenant, authorize?: false)
    end
  end

  test "engineers read runs, and nobody writes them through actions", ctx do
    engineer = user()
    member(engineer, ctx.tenant, :engineer)
    enrollment(ctx.repository)
    {:ok, [run]} = Bots.dispatch(pull_request_opened(ctx.repository), ctx.repository)

    assert [%{id: id}] = Bots.list_runs!(tenant: ctx.tenant, actor: engineer)
    assert id == run.id

    assert {:error, %Ash.Error.Forbidden{}} =
             run
             |> Ash.Changeset.for_update(:fail, %{error: "x"}, tenant: ctx.tenant, actor: root())
             |> Ash.update()
  end
end
