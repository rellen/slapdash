defmodule RamshackleWeb.AdminComponents do
  @moduledoc """
  Markup shared by the admin pages. Styled by the `data-admin-nav` rules in
  `assets/css/components.css`.
  """
  use RamshackleWeb, :html

  @pages [
    {:settings, "Settings", "/admin"},
    {:mail, "Mail", "/admin/mail"},
    {:github, "GitHub sign-in", "/admin/github"},
    {:tenants, "Tenants", "/admin/tenants"}
  ]

  @doc "The admin section's navigation, marking the current page."
  attr :current, :atom, required: true

  def admin_nav(assigns) do
    assigns = assign(assigns, :pages, @pages)

    ~H"""
    <nav aria-label="Admin" data-admin-nav>
      <ul>
        <li :for={{key, label, path} <- @pages}>
          <.link navigate={path} aria-current={key == @current && "page"}>{label}</.link>
        </li>
      </ul>
    </nav>
    """
  end

  @doc "Human text for an Ash error that came back from a form-less action."
  def error_message(%{errors: [_ | _] = errors}),
    do: Enum.map_join(errors, " ", &Exception.message/1)

  def error_message(error) when is_exception(error), do: Exception.message(error)
  def error_message(error), do: inspect(error)
end
