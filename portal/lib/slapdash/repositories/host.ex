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

  @doc """
  Puts a comment on item `number` of a repository, such as a pull request
  or a merge request, at most one time for each `key`.

  Return `{:ok, :created}` when the comment is new, and `{:ok, :exists}`
  when a comment with this key is already there. Mark the comment with the
  key in a way that people do not see, for example in an HTML comment.
  """
  @callback put_comment(
              Connection.t(),
              path :: String.t(),
              number :: pos_integer(),
              key :: String.t(),
              body :: String.t()
            ) :: {:ok, :created | :exists} | {:error, term()}
end
