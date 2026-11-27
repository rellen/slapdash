defmodule Slapdash.Test.EchoBot do
  @moduledoc """
  A test-only bot. On each opened pull request it comments with the pull
  request's title, and with the `prefix` setting when its enrollment has
  one.
  """
  @behaviour Slapdash.Bots.Bot

  alias Slapdash.Bots.Action.Comment

  @impl true
  def key, do: "echo"

  @impl true
  def name, do: "Echo"

  @impl true
  def description, do: "Repeats the title of each new pull request."

  @impl true
  def events, do: [:pull_request_opened]

  @impl true
  def handle(event, context) do
    prefix = Map.get(context.settings, "prefix", "Echo")

    {:ok,
     [
       %Comment{
         key: "echo",
         body: "#{prefix}: #{event.subject.title} in #{context.repository.path}"
       }
     ]}
  end
end
