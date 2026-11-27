defmodule Slapdash.Repositories.Host do
  @moduledoc """
  The behaviour for a provider that hosts code repositories, such as
  GitHub, GitLab or Forgejo. A provider module implements it next to
  `Slapdash.Connections.Provider`.

  A repository path is the provider's own name for a repository, for
  example `owner/name` on GitHub or `group/subgroup/project` on GitLab.
  """

  alias Slapdash.Connections.Connection

  @doc """
  Checks a path that a person typed, and returns it in its stored form.
  Do not call the service here: the check must work offline.
  """
  @callback cast_path(path :: String.t()) :: {:ok, String.t()} | {:error, String.t()}

  @doc "The web address of a repository, for people."
  @callback web_url(Connection.t(), path :: String.t()) :: String.t()
end
