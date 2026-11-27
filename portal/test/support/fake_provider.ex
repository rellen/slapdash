defmodule Slapdash.Test.FakeProvider do
  @moduledoc """
  A test-only provider with one setting of each kind and one secret. Tests
  use it to check the connection code without a real outside service.
  """
  @behaviour Slapdash.Connections.Provider

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

  @impl true
  def setup_help, do: ["Make a token in the fake service."]
end
