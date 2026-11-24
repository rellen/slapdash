defmodule RamshackleWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RamshackleWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar. Its landmarks are styled in `assets/css/layout.css`.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the signed-in user, if any"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#main">{gettext("Skip to content")}</a>
    <header>
      <nav aria-label={gettext("Main")}>
        <a href={~p"/"}>Ramshackle</a>
        <a :if={@current_user && @current_user.root} href={~p"/admin"}>Admin</a>
        <.theme_toggle />
      </nav>
    </header>

    <main id="main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" data-flash-group>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end

  @doc """
  Provides the system, light and dark theme toggle.

  The script in the `<head>` of root.html.heex applies the theme before the
  page renders and keeps each button's `aria-pressed` in sync with the
  current choice. `phx-update="ignore"` stops LiveView patches from
  resetting `aria-pressed` to the server-rendered value.
  """
  def theme_toggle(assigns) do
    ~H"""
    <fieldset id="theme-toggle" phx-update="ignore" data-theme-toggle>
      <legend>{gettext("Theme")}</legend>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-pressed="false"
      >
        {gettext("System")}
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-pressed="false"
      >
        {gettext("Light")}
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-pressed="false"
      >
        {gettext("Dark")}
      </button>
    </fieldset>
    """
  end
end
