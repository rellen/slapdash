defmodule SlapdashWeb.Tenants.ConnectionsLive do
  @moduledoc """
  A tenant's connections to outside services. Members see the list; root
  and the tenant's administrators add, change and remove connections.

  The form for a connection comes from its provider's fields
  (`Slapdash.Connections.Provider`). Stored secrets are never shown: the
  form leaves secret fields blank, and a blank secret keeps the stored one.
  """
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents, only: [error_message: 1]
  import SlapdashWeb.TenantComponents

  alias Slapdash.Connections
  alias Slapdash.Connections.Provider
  alias Slapdash.Connections.Provider.Field

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    {:ok,
     assign(socket,
       providers: Provider.all(),
       manage?: Connections.can_add_connection?(actor, %{tenant_id: tenant.id})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(page_title: "#{socket.assigns.tenant.name} connections", connection: nil, form: nil)
    |> load_list()
  end

  defp apply_action(socket, :new, %{"provider" => key}) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    with true <- socket.assigns.manage?, {:ok, provider} <- Provider.fetch(key) do
      form =
        Connections.Connection
        |> AshPhoenix.Form.for_create(:add,
          actor: actor,
          prepare_source: fn changeset ->
            changeset
            |> Ash.Changeset.force_change_attribute(:tenant_id, tenant.id)
            |> Ash.Changeset.force_change_attribute(:provider, provider.key())
          end
        )
        |> to_form()

      assign(socket,
        page_title: "Add a #{provider.label()} connection",
        provider: provider,
        connection: nil,
        form: form
      )
    else
      _ -> back_to_list(socket, "You cannot add that kind of connection.")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    actor = socket.assigns.current_user

    with true <- socket.assigns.manage?,
         {:ok, connection} <- Connections.get_connection(id, actor: actor),
         {:ok, provider} <- Provider.fetch(connection.provider) do
      form =
        connection
        |> AshPhoenix.Form.for_update(:reconfigure, actor: actor)
        |> to_form()

      assign(socket,
        page_title: "Change #{connection.name}",
        provider: provider,
        connection: connection,
        form: form
      )
    else
      _ -> back_to_list(socket, "That connection does not exist, or you cannot change it.")
    end
  end

  defp back_to_list(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_patch(to: tenant_path(socket.assigns.tenant_prefix, ~p"/connections"))
  end

  defp load_list(socket) do
    %{current_user: actor, tenant: tenant} = socket.assigns

    connections =
      Connections.list_connections!(
        actor: actor,
        query: [filter: [tenant_id: tenant.id], sort: [name: :asc]]
      )

    assign(socket, connections: connections)
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, connection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved #{connection.name}.")
         |> push_patch(to: after_save_path(socket, connection))}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, connection} <- find(socket, id),
         :ok <- Connections.remove_connection(connection, actor: actor) do
      {:noreply, socket |> put_flash(:info, "Removed #{connection.name}.") |> load_list()}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  # A new connection that takes webhooks opens its change page, which shows
  # the webhook URL to give to the service.
  defp after_save_path(socket, connection) do
    prefix = socket.assigns.tenant_prefix

    if is_nil(socket.assigns.connection) and webhooks?(socket.assigns.provider),
      do: tenant_path(prefix, ~p"/connections/#{connection.id}"),
      else: tenant_path(prefix, ~p"/connections")
  end

  defp find(socket, id) do
    case Enum.find(socket.assigns.connections, &(&1.id == id)) do
      nil -> {:error, "That connection no longer exists."}
      connection -> {:ok, connection}
    end
  end

  defp webhooks?(provider), do: Provider.implements?(provider, Slapdash.Webhooks.Source)

  defp webhook_url(connection), do: Slapdash.Instance.url(~p"/webhooks/#{connection.id}")

  defp provider_label(key) do
    case Provider.fetch(key) do
      {:ok, provider} -> provider.label()
      :error -> key
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>{@tenant.name}</h1>
      <.tenant_nav tenant={@tenant} prefix={@tenant_prefix} current={:connections} />

      <.choose>
        <:when test={@form}>
          <.connection_form
            form={@form}
            provider={@provider}
            connection={@connection}
            prefix={@tenant_prefix}
          />
        </:when>
        <:otherwise>
          <.connection_list connections={@connections} manage?={@manage?} prefix={@tenant_prefix} />
          <section :if={@manage?} aria-labelledby="add-connection-heading">
            <h2 id="add-connection-heading">Add a connection</h2>
            <ul>
              <li :for={provider <- @providers}>
                <.link patch={tenant_path(@tenant_prefix, ~p"/connections/new/#{provider.key()}")}>
                  Add a {provider.label()} connection
                </.link>
              </li>
            </ul>
          </section>
        </:otherwise>
      </.choose>
    </Layouts.app>
    """
  end

  attr :connections, :list, required: true
  attr :manage?, :boolean, required: true
  attr :prefix, :string, required: true

  defp connection_list(assigns) do
    ~H"""
    <section aria-labelledby="connections-heading">
      <h2 id="connections-heading">Connections</h2>
      <p :if={@connections == []}>This tenant has no connections yet.</p>
      <table :if={@connections != []} id="connections">
        <thead>
          <tr>
            <th scope="col">Name</th>
            <th scope="col">Kind</th>
            <th :if={@manage?} scope="col"><span>Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={connection <- @connections} id={"connection-#{connection.id}"}>
            <th scope="row">{connection.name}</th>
            <td>{provider_label(connection.provider)}</td>
            <td :if={@manage?}>
              <.link patch={tenant_path(@prefix, ~p"/connections/#{connection.id}")}>
                Change <span>{connection.name}</span>
              </.link>
              <.button
                type="button"
                phx-click={event("remove")}
                phx-value-id={connection.id}
                data-confirm={"Remove #{connection.name}? Its repositories and their bots are removed too."}
              >
                Remove <span>{connection.name}</span>
              </.button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :provider, :atom, required: true
  attr :connection, :map, default: nil
  attr :prefix, :string, required: true

  defp connection_form(assigns) do
    assigns =
      assign(assigns,
        config_fields: Enum.filter(assigns.provider.fields(), &(Field.kind(&1) == :config)),
        secret_fields: Enum.filter(assigns.provider.fields(), &(Field.kind(&1) == :secrets)),
        config: config_values(assigns.form),
        help: Provider.setup_help(assigns.provider)
      )

    ~H"""
    <section aria-labelledby="connection-form-heading">
      <h2 id="connection-form-heading">
        {if @connection,
          do: "Change #{@connection.name}",
          else: "Add a #{@provider.label()} connection"}
      </h2>
      <p :for={paragraph <- @help}>{paragraph}</p>
      <p :if={@connection && webhooks?(@provider)}>
        Webhook URL for this connection: <code>{webhook_url(@connection)}</code>
      </p>
      <p :if={!@connection && webhooks?(@provider)}>
        After you save, this page shows the webhook URL for the service.
      </p>

      <.form
        for={@form}
        id="connection-form"
        phx-change={event("validate")}
        phx-submit={event("save")}
      >
        <.input field={@form[:name]} label="Name" autocomplete="off" />

        <fieldset :if={@config_fields != []}>
          <legend>Settings</legend>
          <.provider_input
            :for={field <- @config_fields}
            field={field}
            group="config"
            value={Map.get(@config, field.name)}
            errors={field_errors(@form, "config", field)}
          />
        </fieldset>

        <fieldset :if={@secret_fields != []}>
          <legend>Secrets</legend>
          <p :if={@connection}>Leave a secret blank to keep the stored one.</p>
          <.provider_input
            :for={field <- @secret_fields}
            field={field}
            group="secrets"
            value=""
            errors={field_errors(@form, "secrets", field)}
          />
        </fieldset>

        <p>
          <.button variant="primary" phx-disable-with="Saving…">Save connection</.button>
          <.link patch={tenant_path(@prefix, ~p"/connections")}>Cancel</.link>
        </p>
      </.form>
    </section>
    """
  end

  attr :field, Field, required: true
  attr :group, :string, required: true
  attr :value, :any, default: nil
  attr :errors, :list, default: []

  defp provider_input(assigns) do
    assigns =
      assign(assigns,
        type: input_type(assigns.field),
        id: "connection-#{assigns.group}-#{assigns.field.name}",
        name: "form[#{assigns.group}][#{assigns.field.name}]"
      )

    ~H"""
    <.input
      id={@id}
      name={@name}
      type={@type}
      label={if @field.required?, do: @field.label, else: "#{@field.label} (optional)"}
      value={@value}
      errors={@errors}
      autocomplete="off"
    />
    <p :if={@field.help}>{@field.help}</p>
    """
  end

  defp input_type(%Field{type: :text}), do: "textarea"
  defp input_type(%Field{secret?: true}), do: "password"
  defp input_type(%Field{type: :url}), do: "url"
  defp input_type(%Field{type: :integer}), do: "number"
  defp input_type(%Field{}), do: "text"

  # Slapdash.Connections.Changes.ApplyProvider puts each error on the field
  # `:"<group>.<name>"`.
  defp field_errors(form, group, field) do
    key = String.to_existing_atom(group <> "." <> field.name)
    Enum.map(form[key].errors, &translate_error/1)
  rescue
    ArgumentError -> []
  end

  # The submitted settings, so a rejected value stays in its input, or else
  # the stored ones.
  defp config_values(form) do
    case form.source.params["config"] || AshPhoenix.Form.value(form.source, :config) do
      config when is_map(config) -> Map.new(config, fn {k, v} -> {to_string(k), v} end)
      _ -> %{}
    end
  end
end
