defmodule SlapdashWeb.Tenants.RepositoriesLive do
  @moduledoc """
  A tenant's repositories. Members see the list; root and the tenant's
  administrators add and remove repositories. A repository is reached
  through one of the tenant's connections that can host repositories.
  """
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents, only: [error_message: 1]
  import SlapdashWeb.TenantComponents

  alias Slapdash.Bots
  alias Slapdash.Bots.Catalogue
  alias Slapdash.Connections
  alias Slapdash.Repositories

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    hosts =
      [actor: actor, query: [filter: [tenant_id: tenant.id], sort: [name: :asc]]]
      |> Connections.list_connections!()
      |> Enum.filter(&Repositories.host?/1)

    {:ok,
     socket
     |> assign(
       page_title: "#{tenant.name} repositories",
       hosts: hosts,
       bots: Catalogue.all(),
       manage?: Repositories.can_add_repository?(actor, %{tenant_id: tenant.id})
     )
     |> load()}
  end

  defp load(socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    repositories =
      Repositories.list_repositories!(
        actor: actor,
        load: [:connection],
        query: [filter: [tenant_id: tenant.id], sort: [path: :asc]]
      )

    form =
      Repositories.Repository
      |> AshPhoenix.Form.for_create(:add,
        actor: actor,
        prepare_source: &Ash.Changeset.force_change_attribute(&1, :tenant_id, tenant.id)
      )
      |> to_form()

    enrollments =
      Bots.list_enrollments!(tenant: tenant, actor: actor)
      |> Map.new(&{{&1.repository_id, &1.bot}, &1})

    assign(socket, repositories: repositories, enrollments: enrollments, form: form)
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("add", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, repository} ->
        {:noreply, socket |> put_flash(:info, "Added #{repository.path}.") |> load()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("toggle_bot", %{"id" => id, "bot" => bot}, socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    result =
      case Map.fetch(socket.assigns.enrollments, {id, bot}) do
        {:ok, enrollment} -> Bots.unenroll(enrollment, tenant: tenant, actor: actor)
        :error -> Bots.enroll(id, bot, tenant: tenant, actor: actor)
      end

    case result do
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
      _ok -> {:noreply, socket |> put_flash(:info, "Bot changed.") |> load()}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with {:ok, repository} <- find(socket, id),
         :ok <- Repositories.remove_repository(repository, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Removed #{repository.path}.") |> load()}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp find(socket, id) do
    case Enum.find(socket.assigns.repositories, &(&1.id == id)) do
      nil -> {:error, "That repository is no longer in this tenant."}
      repository -> {:ok, repository}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>{@tenant.name}</h1>
      <.tenant_nav tenant={@tenant} current={:repositories} />

      <section aria-labelledby="repositories-heading">
        <h2 id="repositories-heading">Repositories</h2>
        <p :if={@repositories == []}>This tenant has no repositories yet.</p>
        <table :if={@repositories != []} id="repositories">
          <thead>
            <tr>
              <th scope="col">Repository</th>
              <th scope="col">Connection</th>
              <th :if={@bots != []} scope="col">Bots</th>
              <th :if={@manage?} scope="col"><span>Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={repository <- @repositories} id={"repository-#{repository.id}"}>
              <th scope="row">
                <.wrap_if test={Repositories.web_url(repository)}>
                  <:wrapper :let={inner}>
                    <a href={Repositories.web_url(repository)}>{render_slot(inner)}</a>
                  </:wrapper>
                  {repository.path}
                </.wrap_if>
              </th>
              <td>{repository.connection.name}</td>
              <td :if={@bots != []}>
                <ul>
                  <li :for={bot <- @bots}>
                    <.bot_toggle
                      bot={bot}
                      repository={repository}
                      on?={Map.has_key?(@enrollments, {repository.id, bot.key()})}
                      manage?={@manage?}
                    />
                  </li>
                </ul>
              </td>
              <td :if={@manage?}>
                <.button
                  type="button"
                  phx-click={event("remove")}
                  phx-value-id={repository.id}
                  data-confirm={"Remove #{repository.path}? Its bots stop."}
                >
                  Remove <span>{repository.path}</span>
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :if={@manage?} aria-labelledby="add-repository-heading">
        <h2 id="add-repository-heading">Add a repository</h2>
        <.choose>
          <:when test={@hosts == []}>
            <p>
              Add a connection that can host repositories first, on the <.link navigate={
                ~p"/tenants/#{@tenant.slug}/connections"
              }>connections page</.link>.
            </p>
          </:when>
          <:otherwise>
            <.form
              for={@form}
              id="repository-form"
              phx-change={event("validate")}
              phx-submit={event("add")}
            >
              <.input
                field={@form[:connection_id]}
                type="select"
                label="Connection"
                options={Enum.map(@hosts, &{&1.name, &1.id})}
              />
              <.input field={@form[:path]} label="Repository path" autocomplete="off" />
              <p><.button variant="primary" phx-disable-with="Adding…">Add repository</.button></p>
            </.form>
          </:otherwise>
        </.choose>
      </section>
    </Layouts.app>
    """
  end

  attr :bot, :atom, required: true
  attr :repository, :map, required: true
  attr :on?, :boolean, required: true
  attr :manage?, :boolean, required: true

  # The state is in the text, and the button names the change it makes.
  defp bot_toggle(assigns) do
    ~H"""
    {@bot.name()}: {if @on?, do: "on", else: "off"}
    <.button
      :if={@manage?}
      type="button"
      phx-click={event("toggle_bot")}
      phx-value-id={@repository.id}
      phx-value-bot={@bot.key()}
    >
      {if @on?, do: "Turn off", else: "Turn on"} <span>{@bot.name()} for {@repository.path}</span>
    </.button>
    """
  end
end
