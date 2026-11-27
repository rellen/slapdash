defmodule Slapdash.Providers.GitHub.Client do
  @moduledoc """
  The GitHub REST API calls that `Slapdash.Providers.GitHub.App` needs.

  Each call signs a JSON Web Token (JWT) with the app's private key, finds
  the app's installation on the repository and gets an installation token.
  The token is valid for one hour and is not stored. Tokens and keys never
  go into logs or errors.

  Tests replace the HTTP layer with `Req.Test`:

      config :slapdash, Slapdash.Providers.GitHub.Client,
        req_options: [plug: {Req.Test, Slapdash.Providers.GitHub.Client}, retry: false]
  """

  alias Slapdash.Connections

  @api_version "2022-11-28"
  @page_size 100
  @max_pages 10

  @doc "Reads an RSA private key in PEM format, as GitHub makes it."
  @spec decode_private_key(String.t()) :: {:ok, tuple()} | :error
  def decode_private_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] ->
        case :public_key.pem_entry_decode(entry) do
          key when elem(key, 0) == :RSAPrivateKey -> {:ok, key}
          _ -> :error
        end

      [] ->
        :error
    end
  rescue
    _ -> :error
  end

  def decode_private_key(_pem), do: :error

  @doc """
  Makes the app's JWT for `app_id`, valid from one minute before `now` to
  nine minutes after it. GitHub accepts at most ten minutes.
  """
  @spec app_jwt(pos_integer(), tuple(), integer()) :: String.t()
  def app_jwt(app_id, private_key, now \\ System.os_time(:second)) do
    header = encode(%{"alg" => "RS256", "typ" => "JWT"})
    claims = encode(%{"iat" => now - 60, "exp" => now + 540, "iss" => to_string(app_id)})
    signing_input = header <> "." <> claims
    signature = :public_key.sign(signing_input, :sha256, private_key)
    signing_input <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  @doc """
  Puts a comment on issue or pull request `number`, unless the app already
  put a comment with this key there. The key goes into an HTML comment at
  the end of the body, which GitHub does not show.
  """
  @spec put_comment(Connections.Connection.t(), String.t(), pos_integer(), String.t(), String.t()) ::
          {:ok, :created | :exists} | {:error, String.t()}
  def put_comment(connection, path, number, key, body) do
    marker = "<!-- slapdash:#{key} -->"
    app_id = connection.config["app_id"]

    with {:ok, token} <- installation_token(connection, path),
         {:ok, comments} <- list_comments(connection, token, path, number) do
      if Enum.any?(comments, &ours?(&1, marker, app_id)) do
        {:ok, :exists}
      else
        create_comment(connection, token, path, number, body <> "\n\n" <> marker)
      end
    end
  end

  # Only a comment by the app counts, so a person cannot stop the bot by
  # copying the marker into a comment.
  defp ours?(comment, marker, app_id) do
    String.contains?(comment["body"] || "", marker) and
      (get_in(comment, ["performed_via_github_app", "id"]) == app_id or
         get_in(comment, ["user", "type"]) == "Bot")
  end

  @doc "Gets an installation token for the app's installation on a repository."
  @spec installation_token(Connections.Connection.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def installation_token(connection, path) do
    secrets = Connections.secrets(connection)

    with {:ok, key} <- decode_key(secrets),
         jwt = app_jwt(connection.config["app_id"], key),
         {:ok, %{"id" => id}} <- request(connection, jwt, :get, "/repos/#{path}/installation"),
         {:ok, %{"token" => token}} <-
           request(connection, jwt, :post, "/app/installations/#{id}/access_tokens") do
      {:ok, token}
    else
      {:error, _} = error -> error
      _ -> {:error, "GitHub gave an unexpected answer for the app installation"}
    end
  end

  defp decode_key(%{"private_key" => pem}) do
    case decode_private_key(pem) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, "the connection's private key is not valid"}
    end
  end

  defp decode_key(_secrets), do: {:error, "the connection has no private key"}

  defp list_comments(connection, token, path, number, page \\ 1, acc \\ []) do
    url = "/repos/#{path}/issues/#{number}/comments"

    case request(connection, token, :get, url, params: [per_page: @page_size, page: page]) do
      {:ok, comments} when is_list(comments) ->
        acc = acc ++ comments

        if length(comments) == @page_size and page < @max_pages,
          do: list_comments(connection, token, path, number, page + 1, acc),
          else: {:ok, acc}

      {:ok, _} ->
        {:error, "GitHub gave an unexpected answer for the comments"}

      error ->
        error
    end
  end

  defp create_comment(connection, token, path, number, body) do
    case request(connection, token, :post, "/repos/#{path}/issues/#{number}/comments",
           json: %{"body" => body}
         ) do
      {:ok, _comment} -> {:ok, :created}
      error -> error
    end
  end

  defp request(connection, credential, method, url, opts \\ []) do
    [
      method: method,
      base_url: connection.config["api_url"],
      url: url,
      auth: {:bearer, credential},
      headers: [
        {"accept", "application/vnd.github+json"},
        {"x-github-api-version", @api_version},
        {"user-agent", "slapdash"}
      ]
    ]
    |> Keyword.merge(opts)
    |> Keyword.merge(Application.get_env(:slapdash, __MODULE__, [])[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "GitHub answered #{status} for #{method_name(method)} #{url}#{message(body)}"}

      {:error, exception} ->
        {:error, "the request to GitHub failed: #{Exception.message(exception)}"}
    end
  end

  defp method_name(method), do: method |> Atom.to_string() |> String.upcase()

  defp message(%{"message" => message}) when is_binary(message), do: ": " <> message
  defp message(_body), do: ""
end
