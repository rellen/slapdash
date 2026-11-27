defmodule SlapdashWeb.Tenants.MembersLive do
  @moduledoc """
  A tenant's members. Anyone in the tenant sees the list; root and the
  tenant's administrators add people, change roles and remove members.
  Policies decide all of this (`Slapdash.Authz`); the page only hides
  controls the viewer cannot use.
  """
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents, only: [error_message: 1]
  import SlapdashWeb.TenantComponents

  alias Slapdash.Authz.Roles
  alias Slapdash.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    {:ok,
     socket
     |> assign(
       page_title: "#{tenant.name} members",
       roles: Enum.map(Roles.tenant_roles(), &{Roles.describe(&1), Atom.to_string(&1)}),
       manage?:
         Tenancy.can_add_member?(actor, tenant.id, "someone@example.com", :engineer,
           reuse_values?: true
         )
     )
     |> load()}
  end

  defp load(socket) do
    %{tenant: tenant, current_user: actor} = socket.assigns

    members =
      Tenancy.list_memberships!(
        actor: actor,
        load: [:user],
        query: [filter: [tenant_id: tenant.id], sort: [inserted_at: :asc]]
      )

    form =
      Tenancy.Membership
      |> AshPhoenix.Form.for_create(:add,
        actor: actor,
        prepare_source: &Ash.Changeset.force_change_attribute(&1, :tenant_id, tenant.id)
      )
      |> to_form()

    assign(socket, members: members, form: form)
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("add", %{"form" => params}, socket) do
    params = Map.put(params, "tenant_id", socket.assigns.tenant.id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "Added #{params["email"]}.") |> load()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("change_role", %{"membership_id" => id, "role" => role}, socket) do
    with {:ok, membership} <- find(socket, id),
         {:ok, _} <-
           Tenancy.change_member_role(membership, role, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Role changed.") |> load()}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("remove", %{"membership_id" => id}, socket) do
    with {:ok, membership} <- find(socket, id),
         :ok <- Tenancy.remove_member(membership, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Member removed.") |> load()}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp find(socket, id) do
    case Enum.find(socket.assigns.members, &(&1.id == id)) do
      nil -> {:error, "That member is no longer in this tenant."}
      membership -> {:ok, membership}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>{@tenant.name}</h1>
      <.tenant_nav tenant={@tenant} current={:members} />

      <section aria-labelledby="members-heading">
        <h2 id="members-heading">Members</h2>
        <p :if={@members == []}>Nobody belongs to this tenant yet.</p>
        <table :if={@members != []} id="members">
          <thead>
            <tr>
              <th scope="col">Email</th>
              <th scope="col">Role</th>
              <th :if={@manage?} scope="col"><span>Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={member <- @members} id={"member-#{member.id}"}>
              <th scope="row">{member.user.email}</th>
              <td>
                <.choose>
                  <:when test={@manage?}>
                    <form phx-change={event("change_role")} id={"role-#{member.id}"}>
                      <input type="hidden" name="membership_id" value={member.id} />
                      <label for={"role-select-#{member.id}"}>Role for {member.user.email}</label>
                      <select id={"role-select-#{member.id}"} name="role">
                        {Phoenix.HTML.Form.options_for_select(@roles, Atom.to_string(member.role))}
                      </select>
                    </form>
                  </:when>
                  <:otherwise>
                    {Phoenix.Naming.humanize(member.role)}
                  </:otherwise>
                </.choose>
              </td>
              <td :if={@manage?}>
                <.button
                  type="button"
                  phx-click={event("remove")}
                  phx-value-membership_id={member.id}
                  data-confirm={"Remove #{member.user.email} from #{@tenant.name}?"}
                >
                  Remove <span>{member.user.email}</span>
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :if={@manage?} aria-labelledby="add-member-heading">
        <h2 id="add-member-heading">Add a member</h2>
        <.form for={@form} id="member-form" phx-change={event("validate")} phx-submit={event("add")}>
          <.input field={@form[:email]} type="email" label="Email address" autocomplete="off" />
          <.input field={@form[:role]} type="select" label="Role" options={@roles} />
          <p>
            They can sign in with this address straight away, by magic link or GitHub.
          </p>
          <p><.button variant="primary" phx-disable-with="Adding…">Add member</.button></p>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
