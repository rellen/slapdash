defmodule SlapdashWeb.TenantScope do
  @moduledoc """
  Loads the tenant of a tenant page into `@tenant`, and the path prefix of
  its pages into `@tenant_prefix`.

  A tenant page has one of two forms:

  - `/<slug>/members` on any host. `@tenant_prefix` is `"/<slug>"`.
  - `/members` on the tenant subdomain `<slug>.<public URL host>`, when root
    has turned tenant subdomains on (`Slapdash.Instance.Settings`).
    `@tenant_prefix` is `""`.

  Build links between tenant pages with
  `SlapdashWeb.TenantComponents.tenant_path/2`, so that they keep the form.

  The tenant is read with the signed-in user as the actor, so a person who
  is not a member (and not root) is sent away with a message that does not
  tell if the tenant exists. Must come after `:live_user_required`.
  """
  use SlapdashWeb, :verified_routes

  alias Slapdash.Tenancy

  def on_mount(:default, params, _session, socket) do
    {slug, prefix} =
      case params do
        %{"slug" => slug} -> {slug, "/" <> slug}
        _ -> {Slapdash.Instance.tenant_slug_for_host(socket.host_uri.host), ""}
      end

    actor = socket.assigns.current_user

    with slug when is_binary(slug) <- slug,
         {:ok, %Tenancy.Tenant{} = tenant} <-
           Tenancy.get_tenant_by_slug(slug, actor: actor, not_found_error?: false) do
      {:cont, Phoenix.Component.assign(socket, tenant: tenant, tenant_prefix: prefix)}
    else
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
