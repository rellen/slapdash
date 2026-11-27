defmodule SlapdashWeb.Tenants.RunsLive do
  @moduledoc """
  The latest bot runs of a tenant, newest first. Every member can read
  them. Runs are written by Slapdash only, so this page has no controls.
  """
  use SlapdashWeb, :live_view

  import SlapdashWeb.TenantComponents

  alias Slapdash.Bots
  alias Slapdash.Bots.Catalogue

  @limit 50

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    runs =
      Bots.list_runs!(
        tenant: tenant,
        actor: actor,
        query: [sort: [inserted_at: :desc], limit: @limit]
      )

    {:ok, assign(socket, page_title: "#{tenant.name} bot runs", runs: runs, limit: @limit)}
  end

  defp bot_name(key) do
    case Catalogue.fetch(key) do
      {:ok, bot} -> bot.name()
      :error -> key
    end
  end

  defp event_label(%{"type" => "pull_request_opened", "subject" => %{"number" => number}}),
    do: "Pull request ##{number} opened"

  defp event_label(%{"type" => type}), do: Phoenix.Naming.humanize(type)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>{@tenant.name}</h1>
      <.tenant_nav tenant={@tenant} current={:runs} />

      <section aria-labelledby="runs-heading">
        <h2 id="runs-heading">Bot runs</h2>
        <p :if={@runs == []}>No bot has run yet.</p>
        <p :if={length(@runs) == @limit}>This page shows the latest {@limit} runs.</p>
        <table :if={@runs != []} id="runs">
          <thead>
            <tr>
              <th scope="col">Started</th>
              <th scope="col">Bot</th>
              <th scope="col">Repository</th>
              <th scope="col">Event</th>
              <th scope="col">Status</th>
              <th scope="col">Attempts</th>
              <th scope="col">Error</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={run <- @runs} id={"run-#{run.id}"}>
              <th scope="row">
                <time datetime={DateTime.to_iso8601(run.inserted_at)}>
                  {Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
                </time>
              </th>
              <td>{bot_name(run.bot)}</td>
              <td>{run.event["repository_path"]}</td>
              <td>{event_label(run.event)}</td>
              <td>{Phoenix.Naming.humanize(run.status)}</td>
              <td>{run.attempts}</td>
              <td>{run.error}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end
