defmodule Slapdash.Providers do
  @moduledoc """
  The built-in providers: modules that implement
  `Slapdash.Connections.Provider` and its companion behaviours for one
  outside service. Register them with `config :slapdash, :providers`.

  - `Slapdash.Providers.GitHub.App`: a GitHub App on github.com or on
    GitHub Enterprise Server.
  """

  use Boundary,
    top_level?: true,
    deps: [Slapdash.Bots, Slapdash.Connections, Slapdash.Repositories, Slapdash.Webhooks],
    exports: [GitHub.App]
end
