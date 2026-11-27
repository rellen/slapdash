defmodule Slapdash.Bots.Runners.InProcess do
  @moduledoc """
  The built-in runner. It runs bots inside the portal, as Oban jobs on the
  `bots` queue. Use it for deterministic bots that only need Elixir code.

  Oban keeps one job for each run while the job waits or runs, so a run
  that is dispatched again does not run two times. A failed attempt is
  retried with backoff, up to five attempts.
  """
  @behaviour Slapdash.Bots.Runner

  use Oban.Worker,
    queue: :bots,
    max_attempts: 5,
    unique: [keys: [:run_id], states: :incomplete]

  alias Slapdash.Bots
  alias Slapdash.Bots.Execution

  @impl Slapdash.Bots.Runner
  def dispatch(run, tenant) do
    %{"tenant_id" => tenant.id, "run_id" => run.id}
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_id" => tenant_id, "run_id" => run_id}}) do
    with {:ok, tenant} <- Slapdash.Tenancy.get_tenant(tenant_id, authorize?: false),
         {:ok, run} <- Bots.get_run(run_id, tenant: tenant, authorize?: false) do
      Execution.run(run, tenant)
    else
      {:error, _} -> {:cancel, "the run or its tenant no longer exists"}
    end
  end
end
