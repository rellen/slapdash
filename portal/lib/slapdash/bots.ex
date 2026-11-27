defmodule Slapdash.Bots do
  @moduledoc """
  The bot framework: bots, the events they react to, the actions they ask
  for, and the runs that record each reaction.

  - A bot is a module that implements `Slapdash.Bots.Bot`. Its `handle/2`
    takes a `Slapdash.Bots.Event` and returns a list of actions, such as
    `Slapdash.Bots.Action.Comment`. Bots do not call outside services
    themselves, so a bot is easy to test and its effects are recorded.
  - `Slapdash.Bots.Catalogue` lists the bots in this install.
  - A `Slapdash.Bots.Enrollment` turns a bot on for one repository.
  - `dispatch/2` makes one `Slapdash.Bots.Run` for each enrolled bot that
    reacts to an event, and gives the run to the bot's runner
    (`Slapdash.Bots.Runner`). The built-in runner runs bots in the portal
    with Oban (`Slapdash.Bots.Runners.InProcess`). Other runners, for
    example on remote machines, implement the same behaviour.
  - `Slapdash.Bots.Execution` runs a bot and performs its actions through
    the repository's provider (`Slapdash.Repositories.Host`).

  Enrollments and runs are tenant data, so they live in the tenant's schema.
  """
  use Ash.Domain,
    otp_app: :slapdash,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  boundary do
    deps [
      Slapdash.Authz,
      Slapdash.Accounts,
      Slapdash.Connections,
      Slapdash.Repositories,
      Slapdash.Tenancy,
      Slapdash.Versions
    ]

    exports [
      Slapdash.Bots.Action.Comment,
      Slapdash.Bots.Bot,
      Slapdash.Bots.Catalogue,
      Slapdash.Bots.Event,
      Slapdash.Bots.Runner,
      Slapdash.Bots.Subject
    ]
  end

  resources do
    resource Slapdash.Bots.Enrollment do
      define :enroll, action: :enroll, args: [:repository_id, :bot]
      define :unenroll, action: :unenroll
      define :list_enrollments, action: :read
    end

    resource Slapdash.Bots.Run do
      define :list_runs, action: :read
      define :get_run, action: :read, get_by: [:id]
    end
  end

  paper_trail do
    include_versions? true
  end

  require Ash.Query

  alias Slapdash.Bots.{Catalogue, Enrollment, Event, Run}

  @doc """
  Starts a run for each bot that is enrolled on `repository` and reacts to
  `event`, and gives each new run to its runner.

  This is safe to call again for the same event: a bot gets one run for each
  event id. A run that is still queued is given to its runner again, and the
  runner must not run it twice.
  """
  @spec dispatch(Event.t(), Slapdash.Repositories.Repository.t()) ::
          {:ok, [Run.t()]} | {:error, term()}
  def dispatch(%Event{} = event, repository) do
    tenant = Slapdash.Tenancy.get_tenant!(repository.tenant_id, authorize?: false)

    Enrollment
    |> Ash.Query.filter(repository_id == ^repository.id)
    |> Ash.read!(tenant: tenant, authorize?: false)
    |> Enum.flat_map(fn enrollment ->
      case Catalogue.fetch(enrollment.bot) do
        {:ok, bot} -> if event.type in bot.events(), do: [{enrollment, bot}], else: []
        :error -> []
      end
    end)
    |> Enum.reduce_while({:ok, []}, fn {enrollment, bot}, {:ok, runs} ->
      case start_run(enrollment, bot, event, tenant) do
        {:ok, run} -> {:cont, {:ok, [run | runs]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, runs} -> {:ok, Enum.reverse(runs)}
      error -> error
    end
  end

  defp start_run(enrollment, bot, event, tenant) do
    runner = Catalogue.runner(bot)

    with {:ok, run} <-
           Run
           |> Ash.Changeset.for_create(
             :start,
             %{
               enrollment_id: enrollment.id,
               repository_id: enrollment.repository_id,
               bot: enrollment.bot,
               event_id: event.id,
               event: Event.dump(event),
               runner: inspect(runner)
             },
             tenant: tenant,
             authorize?: false
           )
           |> Ash.create(),
         :ok <- if(run.status == :queued, do: runner.dispatch(run, tenant), else: :ok) do
      {:ok, run}
    end
  end
end
