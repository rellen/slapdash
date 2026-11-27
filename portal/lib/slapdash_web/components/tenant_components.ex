defmodule SlapdashWeb.TenantComponents do
  @moduledoc """
  Markup and paths shared by the tenant pages. Styled by the
  `data-tenant-nav` rules in `assets/css/components.css`.
  """
  use SlapdashWeb, :html

  @doc """
  The path of a tenant page in the form of the current page (see
  `SlapdashWeb.TenantScope`). Give the page in its subdomain form, as a
  verified route:

      tenant_path(@tenant_prefix, ~p"/connections")
  """
  @spec tenant_path(String.t(), String.t()) :: String.t()
  def tenant_path(prefix, "/" <> _ = path) when is_binary(prefix), do: prefix <> path

  @doc "The tenant section's navigation, marking the current page."
  attr :tenant, :map, required: true
  attr :prefix, :string, required: true
  attr :current, :atom, required: true

  def tenant_nav(assigns) do
    assigns =
      assign(assigns, :pages, [
        {:members, "Members", tenant_path(assigns.prefix, ~p"/members")},
        {:connections, "Connections", tenant_path(assigns.prefix, ~p"/connections")},
        {:repositories, "Repositories", tenant_path(assigns.prefix, ~p"/repositories")},
        {:runs, "Bot runs", tenant_path(assigns.prefix, ~p"/runs")}
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
