defmodule Slapdash.Bots.Bot do
  @moduledoc """
  The behaviour for a bot.

  A bot reacts to events (`Slapdash.Bots.Event`) on the repositories it is
  enrolled on. `handle/2` returns the actions that the bot asks for, and
  `Slapdash.Bots.Execution` performs them. A deterministic bot returns the
  same actions for the same event and context.

  Register bots in `Slapdash.Bots.Catalogue`.
  """

  alias Slapdash.Bots.Action.Comment
  alias Slapdash.Bots.Event

  @typedoc "An action that a bot asks for."
  @type action :: Comment.t()

  @typedoc """
  What a bot knows when it handles an event:

  - `:repository`: a map with the repository `:path` and `:web_url`.
  - `:settings`: the enrollment's settings map.
  """
  @type context :: %{repository: %{path: String.t(), web_url: String.t() | nil}, settings: map()}

  @doc "The permanent key stored in enrollments and runs, such as `\"greeter\"`."
  @callback key() :: String.t()

  @doc "A short, human name for the bot."
  @callback name() :: String.t()

  @doc "One sentence that tells what the bot does."
  @callback description() :: String.t()

  @doc "The event types the bot reacts to."
  @callback events() :: [Event.type()]

  @doc "Returns the actions for an event."
  @callback handle(Event.t(), context()) :: {:ok, [action()]} | {:error, term()}

  @doc "The runner module. The default is `Slapdash.Bots.Runners.InProcess`."
  @callback runner() :: module()

  @optional_callbacks runner: 0
end
