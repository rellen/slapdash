defmodule SlapdashWeb.Admin.GitHubLive do
  @moduledoc "Root sets up, changes or removes the GitHub OAuth app for sign-in."
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents

  alias Slapdash.Instance

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "GitHub sign-in") |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    {app, form} =
      case Instance.get_github_oauth_app(actor: actor, not_found_error?: false) do
        {:ok, %Instance.GitHubOAuthApp{} = app} ->
          {app, AshPhoenix.Form.for_update(app, :reconfigure, actor: actor)}

        _ ->
          {nil, AshPhoenix.Form.for_create(Instance.GitHubOAuthApp, :configure, actor: actor)}
      end

    assign(socket,
      app: app,
      form: to_form(form),
      callback_url: Instance.url(~p"/auth/user/github/callback")
    )
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _app} ->
        {:noreply, socket |> put_flash(:info, "GitHub sign-in saved.") |> load()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("remove", _params, socket) do
    case Instance.remove_github_oauth_app(socket.assigns.app, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "GitHub sign-in removed.") |> load()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>Admin</h1>
      <.admin_nav current={:github} />

      <section aria-labelledby="github-heading">
        <h2 id="github-heading">GitHub sign-in</h2>
        <p :if={!@app}>GitHub sign-in is off. The sign-in page offers it once this is saved.</p>
        <p>
          In GitHub, create an OAuth app under Settings, Developer settings, OAuth Apps. Set its
          authorization callback URL to <code>{@callback_url}</code>.
        </p>

        <.form for={@form} id="github-form" phx-change={event("validate")} phx-submit={event("save")}>
          <.input field={@form[:client_id]} label="Client ID" autocomplete="off" />
          <.input
            field={@form[:client_secret]}
            type="password"
            label={
              if @app,
                do: "Client secret (leave blank to keep the current one)",
                else: "Client secret"
            }
            value=""
            autocomplete="new-password"
          />
          <p><.button variant="primary" phx-disable-with="Saving…">Save GitHub sign-in</.button></p>
        </.form>

        <p :if={@app}>
          <.button
            type="button"
            phx-click={event("remove")}
            data-confirm="Turn off GitHub sign-in? People who use it will need a magic link."
          >
            Remove GitHub sign-in
          </.button>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
