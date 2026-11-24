defmodule Ramshackle.Repo do
  use AshPostgres.Repo,
    otp_app: :ramshackle

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions", "citext"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  @doc """
  The schema of every tenant, for running tenant migrations. See
  `Ramshackle.Tenancy.Tenant`.
  """
  @impl true
  def all_tenants do
    import Ecto.Query, only: [from: 2]

    all(from(t in "tenants", select: t.schema))
  end

  @impl true
  def min_pg_version do
    %Version{major: 17, minor: 0, patch: 0}
  end
end
