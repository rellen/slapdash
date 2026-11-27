defmodule Slapdash.Bots.Action.Comment do
  @moduledoc """
  An action: put a comment on the event's subject, such as a pull request.

  `key` makes the comment idempotent. The provider posts at most one
  comment for each key on a subject, so a retried run does not post the
  comment two times. Use a key that names the bot and the purpose, such as
  `"greeter"`.
  """

  @enforce_keys [:key, :body]
  defstruct [:key, :body]

  @type t :: %__MODULE__{key: String.t(), body: String.t()}
end
