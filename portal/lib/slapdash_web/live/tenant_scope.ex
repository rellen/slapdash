defmodule SlapdashWeb.TenantScope do
  @moduledoc """
  Loads the tenant named by the `:slug` route parameter into `@tenant` for
  the `/tenants/:slug/...` LiveViews.

  The tenant is read with the signed-in user as the actor, so a person who
  is not a member (and not root) is sent home with a message that does not
  tell if the tenant exists. Must come after `:live_user_required`.
  """
  use SlapdashWeb, :verified_routes

  alias Slapdash.Tenancy

  def on_mount(:default, %{"slug" => slug}, _session, socket) do
    actor = socket.assigns.current_user

    case Tenancy.get_tenant_by_slug(slug, actor: actor, not_found_error?: false) do
      {:ok, %Tenancy.Tenant{} = tenant} ->
        {:cont, Phoenix.Component.assign(socket, :tenant, tenant)}

      _ ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "That tenant does not exist, or you are not a member."
         )
         |> Phoenix.LiveView.push_navigate(to: ~p"/")}
    end
  end
end
