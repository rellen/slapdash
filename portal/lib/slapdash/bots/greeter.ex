defmodule Slapdash.Bots.Greeter do
  @moduledoc """
  A deterministic bot with no language model. It puts one fixed comment on
  each pull request that is opened on a repository it is enrolled on.

  The comment has the key `"greeter"`, so the bot comments at most one time
  on each pull request, also when GitHub sends the event again.
  """
  @behaviour Slapdash.Bots.Bot

  alias Slapdash.Bots.Action.Comment

  @message """
  Hello! ShoddyBot saw this pull request.

  This is an automatic comment from a Slapdash bot. It is the same on each new pull request.
  """

  @doc "The fixed comment text."
  def message, do: String.trim(@message)

  @impl true
  def key, do: "greeter"

  @impl true
  def name, do: "Greeter"

  @impl true
  def description, do: "Puts a fixed comment on each new pull request."

  @impl true
  def events, do: [:pull_request_opened]

  @impl true
  def handle(%{type: :pull_request_opened}, _context),
    do: {:ok, [%Comment{key: "greeter", body: message()}]}
end
