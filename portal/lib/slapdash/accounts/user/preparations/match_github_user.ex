defmodule Slapdash.Accounts.User.Preparations.MatchGithubUser do
  @moduledoc """
  Finds the existing user for a GitHub sign-in, and drops the GitHub OAuth
  tokens.

  Sign-in is by invitation only, so a GitHub sign-in never creates a user.
  The query matches the user whose GitHub identity is already linked, or else
  the user whose email is the GitHub primary email. When the GitHub user id
  is not linked yet, `AshAuthentication.Strategy.OAuth2.SignInPreparation`
  links it only if GitHub says that email is verified. Otherwise someone
  could add an invited person's address to their own GitHub account and sign
  in as that person.

  Slapdash only uses GitHub to sign people in, so it does not keep the OAuth
  access token. The argument is replaced with an empty map before the user
  identity is stored, so no token is written to the database.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  import Shoddy.Strings, only: [is_non_empty_string: 1]

  alias Ash.Query
  alias AshAuthentication.Strategy.OAuth2

  @impl true
  def prepare(query, _opts, _context) do
    user_info = Query.get_argument(query, :user_info) || %{}
    query = Query.set_argument(query, :oauth_tokens, %{})

    case {OAuth2.uid_from_user_info(user_info), user_info["email"]} do
      {uid, email} when is_non_empty_string(uid) and is_non_empty_string(email) ->
        Query.filter(
          query,
          exists(identities, strategy == "github" and uid == ^uid) or email == ^email
        )

      {uid, _email} when is_non_empty_string(uid) ->
        Query.filter(query, exists(identities, strategy == "github" and uid == ^uid))

      _ ->
        Query.do_filter(query, false)
    end
  end
end
