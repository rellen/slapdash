defmodule RamshackleWeb.Admin.SettingsLive do
  @moduledoc "Root edits the install-wide settings: public URL and mail sender."
  use RamshackleWeb, :live_view

  import RamshackleWeb.AdminComponents

  alias Ramshackle.Instance

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Settings") |> assign_form()}
  end

  defp assign_form(socket) do
    actor = socket.assigns.current_user

    form =
      case Instance.get_settings(actor: actor, not_found_error?: false) do
        {:ok, %Instance.Settings{} = settings} ->
          AshPhoenix.Form.for_update(settings, :reconfigure, actor: actor)

        _ ->
          AshPhoenix.Form.for_create(Instance.Settings, :configure, actor: actor)
      end

    assign(socket, :form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _settings} ->
        {:noreply, socket |> put_flash(:info, "Settings saved.") |> assign_form()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>Admin</h1>
      <.admin_nav current={:settings} />

      <section aria-labelledby="settings-heading">
        <h2 id="settings-heading">Settings</h2>
        <.form
          for={@form}
          id="settings-form"
          phx-change={event("validate")}
          phx-submit={event("save")}
        >
          <.input
            field={@form[:public_url]}
            type="url"
            label="Public URL"
            placeholder="https://bot.example.com"
          />
          <p>
            The address people use to reach Ramshackle. Sign-in links and GitHub sign-in are built from it.
          </p>
          <.input field={@form[:mail_from_name]} label="Mail sender name" />
          <.input
            field={@form[:mail_from_address]}
            type="email"
            label="Mail sender address"
            placeholder="noreply@bot.example.com"
          />
          <p><.button variant="primary" phx-disable-with="Saving…">Save settings</.button></p>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
