defmodule Slapdash.Tenancy.Validations.NotReserved do
  @moduledoc """
  Refuses a tenant slug that is also the first part of a portal route, or a
  subdomain with a common meaning of its own. Tenant pages are at
  `/<slug>/...` and at `<slug>.<public URL host>`, so such a slug would hide
  a route or confuse people.

  Add the first part of each new top-level route to `@reserved`.
  """
  use Ash.Resource.Validation

  @reserved ~w(
    admin api app assets auth connections dev docs favicon fonts help images
    live login logout magic_link mail members phoenix repositories runs
    settings sign_in sign_out static status support tenants webhooks www
  )

  @doc "The reserved slugs."
  def reserved, do: @reserved

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]), do: {:ok, opts}, else: {:error, "attribute is required"}
  end

  @impl true
  def validate(changeset, opts, _context) do
    value = Ash.Changeset.get_attribute(changeset, opts[:attribute])

    if value in @reserved,
      do: {:error, field: opts[:attribute], message: "is reserved for Slapdash itself"},
      else: :ok
  end
end
