defmodule Slapdash.Bots.Event do
  @moduledoc """
  Something that happened on a repository, in a form that does not depend
  on the provider. Webhook sources (`Slapdash.Webhooks.Source`) make events
  from deliveries.

  Event types:

  - `:pull_request_opened`: somebody opened a pull request (GitHub,
    Forgejo) or a merge request (GitLab).

  `id` is unique for each occurrence, for example the delivery id and a
  position. A bot gets at most one run for each event id.
  """

  alias Slapdash.Bots.Subject

  @types [:pull_request_opened]

  @enforce_keys [:id, :type, :connection_id, :repository_path]
  defstruct [:id, :type, :connection_id, :repository_path, :subject, :sender]

  @type type :: :pull_request_opened

  @type t :: %__MODULE__{
          id: String.t(),
          type: type(),
          connection_id: Ecto.UUID.t(),
          repository_path: String.t(),
          subject: Subject.t() | nil,
          sender: String.t() | nil
        }

  @doc "The known event types."
  @spec types() :: [type()]
  def types, do: @types

  @doc "Turns an event into a map with string keys, for storage."
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = event) do
    %{
      "id" => event.id,
      "type" => Atom.to_string(event.type),
      "connection_id" => event.connection_id,
      "repository_path" => event.repository_path,
      "subject" => event.subject && Subject.dump(event.subject),
      "sender" => event.sender
    }
  end

  @doc "Reads an event back from `dump/1`."
  @spec load(map()) :: t()
  def load(%{"type" => type} = map) do
    %__MODULE__{
      id: map["id"],
      type:
        Enum.find(@types, &(Atom.to_string(&1) == type)) || raise("unknown event type #{type}"),
      connection_id: map["connection_id"],
      repository_path: map["repository_path"],
      subject: map["subject"] && Subject.load(map["subject"]),
      sender: map["sender"]
    }
  end
end
