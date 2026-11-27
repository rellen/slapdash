defmodule SlapdashWeb.TenantComponents do
  @moduledoc """
  Markup shared by the tenant pages. Styled by the `data-tenant-nav` rules
  in `assets/css/components.css`.
  """
  use SlapdashWeb, :html

  @doc "The tenant section's navigation, marking the current page."
  attr :tenant, :map, required: true
  attr :current, :atom, required: true

  def tenant_nav(assigns) do
    assigns =
      assign(assigns, :pages, [
        {:members, "Members", ~p"/tenants/#{assigns.tenant.slug}/members"},
        {:connections, "Connections", ~p"/tenants/#{assigns.tenant.slug}/connections"},
        {:repositories, "Repositories", ~p"/tenants/#{assigns.tenant.slug}/repositories"}
      ])

    ~H"""
    <nav aria-label={"#{@tenant.name} sections"} data-tenant-nav>
      <ul>
        <li :for={{key, label, path} <- @pages}>
          <.link navigate={path} aria-current={key == @current && "page"}>{label}</.link>
        </li>
      </ul>
    </nav>
    """
  end
end
