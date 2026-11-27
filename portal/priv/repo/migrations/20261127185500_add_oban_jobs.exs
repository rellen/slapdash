defmodule Slapdash.Repo.Migrations.AddObanJobs do
  @moduledoc """
  Creates the Oban job tables in the `public` schema. Oban owns these tables,
  so this migration is written by hand and is not made by `mix ash.codegen`.
  A later Oban release that needs a new table version gets a new migration
  that calls `Oban.Migration.up(version: N)`.
  """
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  # Version 1 is the lowest, so going down to it drops all of Oban's tables.
  def down, do: Oban.Migration.down(version: 1)
end
