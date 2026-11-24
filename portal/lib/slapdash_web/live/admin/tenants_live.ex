defmodule SlapdashWeb.Admin.TenantsLive do
  @moduledoc "Root lists tenants and creates new ones."
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents

  alias Slapdash.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Tenants") |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    form = AshPhoenix.Form.for_create(Tenancy.Tenant, :create, actor: actor)

    assign(socket,
      tenants: Tenancy.list_tenants!(actor: actor, query: [sort: [name: :asc]]),
      form: to_form(form)
    )
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, tenant} ->
        {:noreply, socket |> put_flash(:info, "Created #{tenant.name}.") |> load()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>Admin</h1>
      <.admin_nav current={:tenants} />

      <section aria-labelledby="tenants-heading">
        <h2 id="tenants-heading">Tenants</h2>
        <p :if={@tenants == []}>There are no tenants yet.</p>
        <table :if={@tenants != []} id="tenants">
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Slug</th>
              <th scope="col">Database schema</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={tenant <- @tenants} id={"tenant-#{tenant.id}"}>
              <th scope="row">
                <.link navigate={~p"/tenants/#{tenant.slug}/members"}>{tenant.name}</.link>
              </th>
              <td>{tenant.slug}</td>
              <td><code>{tenant.schema}</code></td>
            </tr>
          </tbody>
        </table>
      </section>

      <section aria-labelledby="new-tenant-heading">
        <h2 id="new-tenant-heading">New tenant</h2>
        <.form
          for={@form}
          id="tenant-form"
          phx-change={event("validate")}
          phx-submit={event("create")}
        >
          <.input field={@form[:name]} label="Name" />
          <.input field={@form[:slug]} label="Slug" pattern="[a-z][a-z0-9_]{0,39}" />
          <p>
            Lowercase letters, digits and underscores. The slug names the tenant's database schema and cannot change later.
          </p>
          <p><.button variant="primary" phx-disable-with="Creating…">Create tenant</.button></p>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
