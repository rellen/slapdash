defmodule SlapdashWeb.Admin.MailLive do
  @moduledoc """
  Root chooses how Slapdash sends mail, and sends a test message to check it.
  """
  use SlapdashWeb, :live_view

  import SlapdashWeb.AdminComponents

  alias Slapdash.{Instance, Mailer}

  @adapters [
    {"SMTP server", "smtp"},
    {"Postmark", "postmark"},
    {"Mailgun", "mailgun"},
    {"SendGrid", "sendgrid"}
  ]

  @securities [
    {"STARTTLS (usually port 587)", "starttls"},
    {"TLS from the start (usually port 465)", "tls"},
    {"None (only on a trusted network)", "none"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Mail", adapters: @adapters, securities: @securities)
     |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    {provider, form} =
      case Instance.get_mail_provider(actor: actor, not_found_error?: false) do
        {:ok, %Instance.MailProvider{} = provider} ->
          {provider, AshPhoenix.Form.for_update(provider, :reconfigure, actor: actor)}

        _ ->
          {nil,
           AshPhoenix.Form.for_create(Instance.MailProvider, :configure,
             actor: actor,
             params: %{"adapter" => "smtp", "port" => "587"}
           )}
      end

    assign(socket, provider: provider, form: to_form(form))
  end

  defp adapter(form), do: to_string(AshPhoenix.Form.value(form.source, :adapter) || "smtp")

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _provider} ->
        {:noreply, socket |> put_flash(:info, "Mail settings saved.") |> load()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("remove", _params, socket) do
    case Instance.remove_mail_provider(socket.assigns.provider,
           actor: socket.assigns.current_user
         ) do
      :ok -> {:noreply, socket |> put_flash(:info, "Mail provider removed.") |> load()}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("send_test", _params, socket) do
    to = to_string(socket.assigns.current_user.email)

    email =
      Swoosh.Email.new(
        to: to,
        subject: "Slapdash test message",
        text_body: "Slapdash can send mail. You asked for this test from the admin pages."
      )

    case Mailer.deliver(email) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Sent a test message to #{to}.")}

      {:error, :mail_not_configured} ->
        {:noreply, put_flash(socket, :error, "Set up a mail provider first.")}

      {:error, _reason} ->
        # The reason can include provider responses; keep it out of the page.
        {:noreply,
         put_flash(
           socket,
           :error,
           "The test message could not be sent. Check the settings and try again."
         )}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :adapter, adapter(assigns.form))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1>Admin</h1>
      <.admin_nav current={:mail} />

      <section aria-labelledby="mail-heading">
        <h2 id="mail-heading">Mail</h2>
        <p :if={!@provider}>
          No mail provider is set up, so Slapdash cannot email sign-in links yet.
        </p>

        <.form for={@form} id="mail-form" phx-change={event("validate")} phx-submit={event("save")}>
          <.input field={@form[:adapter]} type="select" label="Provider" options={@adapters} />

          <.switch value={@adapter}>
            <:case value="smtp">
              <.input field={@form[:host]} label="Server" placeholder="smtp.example.com" />
              <.input field={@form[:port]} type="number" label="Port" min="1" max="65535" />
              <.input field={@form[:security]} type="select" label="Encryption" options={@securities} />
              <.input field={@form[:username]} label="User name" autocomplete="off" />
            </:case>
            <:case value="mailgun">
              <.input field={@form[:domain]} label="Sending domain" placeholder="mg.example.com" />
              <.input
                field={@form[:region]}
                type="select"
                label="Region"
                options={[{"US", "us"}, {"EU", "eu"}]}
              />
            </:case>
          </.switch>

          <.input
            field={@form[:secret]}
            type="password"
            label={secret_label(@adapter, @provider)}
            value=""
            autocomplete="new-password"
          />
          <p><.button variant="primary" phx-disable-with="Saving…">Save mail settings</.button></p>
        </.form>

        <p :if={@provider}>
          <.button type="button" phx-click={event("send_test")} phx-disable-with="Sending…">
            Send me a test message
          </.button>
          <.button
            type="button"
            phx-click={event("remove")}
            data-confirm="Remove the mail provider? Slapdash will not be able to email sign-in links."
          >
            Remove mail provider
          </.button>
        </p>
      </section>
    </Layouts.app>
    """
  end

  defp secret_label(adapter, provider) do
    base = if adapter == "smtp", do: "Password", else: "API key"
    if provider, do: base <> " (leave blank to keep the current one)", else: base
  end
end
