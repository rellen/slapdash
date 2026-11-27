defmodule Slapdash.Bots.Subject do
  @moduledoc """
  The item in a repository that an event is about, such as a pull request.
  `number` is the provider's number for the item in its repository.
  """

  @kinds [:pull_request]

  @enforce_keys [:kind, :number]
  defstruct [:kind, :number, :title, :url, :author]

  @type t :: %__MODULE__{
          kind: :pull_request,
          number: pos_integer(),
          title: String.t() | nil,
          url: String.t() | nil,
          author: String.t() | nil
        }

  @doc "Turns a subject into a map with string keys, for storage."
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = subject) do
    subject
    |> Map.from_struct()
    |> Map.update!(:kind, &Atom.to_string/1)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc "Reads a subject back from `dump/1`."
  @spec load(map()) :: t()
  def load(%{"kind" => kind} = map) do
    %__MODULE__{
      kind:
        Enum.find(@kinds, &(Atom.to_string(&1) == kind)) || raise("unknown subject kind #{kind}"),
      number: map["number"],
      title: map["title"],
      url: map["url"],
      author: map["author"]
    }
  end
end
