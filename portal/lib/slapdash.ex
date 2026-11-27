defmodule Slapdash do
  @moduledoc """
  Slapdash keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # The application boundary: the supervision tree, the repo, the vault and
  # the release tasks. It sits above the domains and the web layer.
  use Boundary,
    deps: [
      Slapdash.Accounts,
      Slapdash.Authz,
      Slapdash.Instance,
      Slapdash.Mailer,
      Slapdash.Secrets,
      Slapdash.Tenancy,
      SlapdashWeb
    ]
end
