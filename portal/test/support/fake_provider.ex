defmodule Slapdash.Test.FakeProvider do
  @moduledoc """
  A test-only provider with one setting of each kind and one secret. It
  also hosts repositories with `owner/name` paths. Tests
  use it to check the connection code without a real outside service.
  """
  @behaviour Slapdash.Connections.Provider
  @behaviour Slapdash.Repositories.Host

  alias Slapdash.Connections.Provider.Field

  @impl true
  def key, do: "fake"

  @impl true
  def label, do: "Fake service"

  @impl true
  def fields do
    [
      %Field{name: "url", label: "Service URL", type: :url, default: "https://fake.example"},
      %Field{name: "account", label: "Account number", type: :integer},
      %Field{name: "note", label: "Note", required?: false},
      %Field{name: "token", label: "API token", secret?: true}
    ]
  end

  @impl true
  def validate(_config, %{"token" => "bad" <> _}), do: {:error, [{"token", "is refused"}]}
  def validate(_config, _secrets), do: :ok

  @impl Slapdash.Repositories.Host
  def cast_path(path) do
    if path =~ ~r{\A[\w.-]+\/[\w.-]+\z},
      do: {:ok, path},
      else: {:error, "must look like owner/name"}
  end

  @impl Slapdash.Repositories.Host
  def web_url(connection, path), do: connection.config["url"] <> "/" <> path

  @impl true
  def setup_help, do: ["Make a token in the fake service."]
end
