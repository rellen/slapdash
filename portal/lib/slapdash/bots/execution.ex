defmodule Slapdash.Bots.Execution do
  @moduledoc """
  Runs one bot run: it calls the bot, performs the actions the bot returns
  and records the result on the `Slapdash.Bots.Run`.

  Runners call `run/2`. A run that already succeeded is not run again, so a
  runner can call `run/2` again after a crash. Actions are idempotent (see
  `Slapdash.Bots.Action.Comment`), so a retry after a partial failure does
  not repeat the actions that were already done.
  """

  require Logger

  alias Slapdash.Bots.Action.Comment
  alias Slapdash.Bots.{Catalogue, Event, Run}
  alias Slapdash.Connections
  alias Slapdash.Repositories

  @doc """
  Runs a run. Returns `:ok` when the run succeeded or had succeeded before,
  `{:error, reason}` when this attempt failed and a retry can help, and
  `{:cancel, reason}` when a retry cannot help.
  """
  @spec run(Run.t(), Slapdash.Tenancy.Tenant.t()) ::
          :ok | {:error, String.t()} | {:cancel, String.t()}
  def run(%Run{status: :succeeded}, _tenant), do: :ok

  def run(%Run{} = run, tenant) do
    with {:ok, bot} <- fetch_bot(run),
         {:ok, settings} <- fetch_settings(run, tenant),
         {:ok, repository} <- fetch_repository(run) do
      run = update!(run, :begin, %{}, tenant)
      event = Event.load(run.event)

      case safely_perform(bot, event, repository, settings) do
        {:ok, summaries} ->
          update!(run, :succeed, %{actions: summaries}, tenant)
          :ok

        {:error, reason} ->
          message = describe(reason)
          Logger.warning("Bot run #{run.id} (#{run.bot}) failed: #{message}")
          update!(run, :fail, %{error: message}, tenant)
          {:error, message}
      end
    else
      {:cancel, message} ->
        run |> update!(:begin, %{}, tenant) |> update!(:fail, %{error: message}, tenant)
        {:cancel, message}
    end
  end

  defp fetch_settings(run, tenant) do
    case Ash.load!(run, :enrollment, tenant: tenant, authorize?: false).enrollment do
      %{settings: settings} -> {:ok, settings}
      nil -> {:cancel, "the bot was turned off for this repository"}
    end
  end

  defp fetch_bot(run) do
    case Catalogue.fetch(run.bot) do
      {:ok, bot} -> {:ok, bot}
      :error -> {:cancel, "the bot #{inspect(run.bot)} is not in this install"}
    end
  end

  defp fetch_repository(run) do
    case Repositories.get_repository(run.repository_id,
           authorize?: false,
           not_found_error?: false,
           load: [:connection]
         ) do
      {:ok, %{} = repository} -> {:ok, repository}
      _ -> {:cancel, "the repository was removed"}
    end
  end

  # A bot or provider that raises fails the attempt like an error does, so
  # the run does not stay `:running`.
  defp safely_perform(bot, event, repository, settings) do
    perform(bot, event, repository, settings)
  rescue
    exception -> {:error, exception}
  end

  defp perform(bot, event, repository, settings) do
    context = %{
      repository: %{path: to_string(repository.path), web_url: Repositories.web_url(repository)},
      settings: settings
    }

    with {:ok, actions} <- bot.handle(event, context) do
      Enum.reduce_while(actions, {:ok, []}, fn action, {:ok, done} ->
        case perform_action(action, event, repository) do
          {:ok, summary} -> {:cont, {:ok, done ++ [summary]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp perform_action(%Comment{key: key, body: body}, %Event{subject: %{number: number}}, repo) do
    connection = repo.connection
    provider = Connections.provider(connection)

    case provider.put_comment(connection, to_string(repo.path), number, key, body) do
      {:ok, result} ->
        {:ok, %{"action" => "comment", "key" => key, "result" => to_string(result)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_action(%Comment{}, _event, _repository),
    do: {:error, "the event has no subject to comment on"}

  defp perform_action(action, _event, _repository),
    do: {:error, "unknown action #{inspect(action.__struct__)}"}

  defp update!(run, action, params, tenant) do
    run
    |> Ash.Changeset.for_update(action, params, tenant: tenant, authorize?: false)
    |> Ash.update!()
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason) when is_exception(reason), do: Exception.message(reason)
  defp describe(reason), do: inspect(reason)
end
