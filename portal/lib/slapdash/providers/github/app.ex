defmodule Slapdash.Providers.GitHub.App do
  @moduledoc """
  A connection to a GitHub App, on github.com or on GitHub Enterprise
  Server.

  - As a `Slapdash.Repositories.Host`, it posts comments as the app, with
    an installation token (`Slapdash.Providers.GitHub.Client`). The app must
    be installed on the repository.
  - As a `Slapdash.Webhooks.Source`, it checks the `X-Hub-Signature-256`
    header with the webhook secret and turns `pull_request` deliveries with
    the action `opened` into `:pull_request_opened` events.
  """
  @behaviour Slapdash.Connections.Provider
  @behaviour Slapdash.Repositories.Host
  @behaviour Slapdash.Webhooks.Source

  alias Slapdash.Bots.{Event, Subject}
  alias Slapdash.Connections.Provider.Field
  alias Slapdash.Providers.GitHub.Client

  @impl Slapdash.Connections.Provider
  def key, do: "github_app"

  @impl Slapdash.Connections.Provider
  def label, do: "GitHub App"

  @impl Slapdash.Connections.Provider
  def fields do
    [
      %Field{
        name: "app_id",
        label: "App ID",
        type: :integer,
        help: "The number on the app's settings page, under About."
      },
      %Field{
        name: "web_url",
        label: "GitHub web URL",
        type: :url,
        default: "https://github.com",
        help: "Change it only for GitHub Enterprise Server."
      },
      %Field{
        name: "api_url",
        label: "GitHub API URL",
        type: :url,
        default: "https://api.github.com",
        help: "For GitHub Enterprise Server, this is https://<host>/api/v3."
      },
      %Field{
        name: "private_key",
        label: "Private key",
        type: :text,
        secret?: true,
        help: "The whole .pem file that GitHub gives when you make a private key."
      },
      %Field{name: "webhook_secret", label: "Webhook secret", secret?: true}
    ]
  end

  @impl Slapdash.Connections.Provider
  def validate(_config, %{"private_key" => pem}) do
    case Client.decode_private_key(pem) do
      {:ok, _key} -> :ok
      :error -> {:error, [{"private_key", "is not an RSA private key in PEM format"}]}
    end
  end

  def validate(_config, _secrets), do: :ok

  @impl Slapdash.Connections.Provider
  def setup_help do
    [
      "In GitHub, open Settings, Developer settings, GitHub Apps, and make a new app.",
      "Set its webhook URL to the URL that this page shows after you save, and set a webhook secret.",
      "Give it read and write access to pull requests, and subscribe it to pull request events.",
      "Make a private key for it, and install it on the repositories you add here."
    ]
  end

  # Repository host

  @owner ~S"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})"
  @name ~S"[A-Za-z0-9._-]{1,100}"

  @impl Slapdash.Repositories.Host
  def cast_path(path) do
    path =
      path
      |> String.trim()
      |> String.replace(~r{\Ahttps?://[^/]+/}, "")
      |> String.replace_suffix(".git", "")
      |> String.trim_trailing("/")

    if path =~ ~r{\A#{@owner}/#{@name}\z} and Path.basename(path) not in [".", ".."],
      do: {:ok, path},
      else: {:error, "must be owner/name, for example octo-org/hello-world"}
  end

  @impl Slapdash.Repositories.Host
  def web_url(connection, path), do: connection.config["web_url"] <> "/" <> path

  @impl Slapdash.Repositories.Host
  def put_comment(connection, path, number, key, body) do
    Client.put_comment(connection, path, number, key, body)
  end

  # Webhook source

  @impl Slapdash.Webhooks.Source
  def verify_webhook(_connection, headers, raw_body, %{"webhook_secret" => secret}) do
    expected =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(Map.get(headers, "x-hub-signature-256", ""), expected),
      do: :ok,
      else: {:error, :bad_signature}
  end

  def verify_webhook(_connection, _headers, _raw_body, _secrets), do: {:error, :no_secret}

  @impl Slapdash.Webhooks.Source
  def parse_webhook(%{"x-github-delivery" => id, "x-github-event" => event}, _params)
      when id != "" and event != "",
      do: {:ok, %{delivery_id: id, event: event}}

  def parse_webhook(_headers, _params), do: {:error, :missing_headers}

  @impl Slapdash.Webhooks.Source
  def to_events(
        "pull_request",
        %{
          "action" => "opened",
          "pull_request" => %{"number" => number} = pull_request,
          "repository" => %{"full_name" => full_name}
        } = payload,
        connection
      ) do
    [
      %Event{
        id: nil,
        type: :pull_request_opened,
        connection_id: connection.id,
        repository_path: full_name,
        subject: %Subject{
          kind: :pull_request,
          number: number,
          title: pull_request["title"],
          url: pull_request["html_url"],
          author: get_in(pull_request, ["user", "login"])
        },
        sender: get_in(payload, ["sender", "login"])
      }
    ]
  end

  def to_events(_event, _payload, _connection), do: []
end
