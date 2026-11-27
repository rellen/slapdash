defmodule Slapdash.Connections.Provider do
  @moduledoc """
  The behaviour for a kind of connection, and the registry of providers.

  A provider module declares the settings (`config`) and the secrets
  (`secrets`) that a connection of its kind holds, as a list of
  `Slapdash.Connections.Provider.Field`. The admin UI builds its form from
  this list. `Slapdash.Connections.Connection` stores the settings as a map
  and the secrets as a map encrypted with `Slapdash.Vault`.

  Register providers in the application environment:

      config :slapdash, :providers, [Slapdash.Providers.GitHub.App]

  A provider can also implement other behaviours, such as
  `Slapdash.Webhooks.Source` or `Slapdash.Repositories.Host`. Use
  `implements?/2` to find out.
  """

  alias Slapdash.Connections.Provider.Field

  @typedoc "Field errors: the field name and a message."
  @type errors :: [{String.t(), String.t()}]

  @doc "The permanent key stored in `Connection.provider`, such as `\"github_app\"`."
  @callback key() :: String.t()

  @doc "A short, human name for the provider, for the UI."
  @callback label() :: String.t()

  @doc "The settings and secrets a connection of this kind holds."
  @callback fields() :: [Field.t()]

  @doc """
  Checks settings and secrets after each field was cast and checked on its
  own. Use it for rules that cross fields or need parsing, such as a key in
  PEM format.
  """
  @callback validate(config :: map(), secrets :: map()) :: :ok | {:error, errors()}

  @doc "Setup steps for the operator, as plain text paragraphs."
  @callback setup_help() :: [String.t()]

  @optional_callbacks validate: 2, setup_help: 0

  @doc "The registered provider modules."
  @spec all() :: [module()]
  def all, do: Application.get_env(:slapdash, :providers, [])

  @doc "The provider module for a key."
  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(key) when is_binary(key) do
    case Enum.find(all(), &(&1.key() == key)) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_key), do: :error

  @doc "Whether a provider module implements a behaviour."
  @spec implements?(module(), module()) :: boolean()
  def implements?(module, behaviour) do
    behaviours =
      if Code.ensure_loaded?(module),
        do: module.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten(),
        else: []

    behaviour in behaviours
  end

  @doc "The setup steps of a provider, or none."
  @spec setup_help(module()) :: [String.t()]
  def setup_help(module) do
    if function_exported?(module, :setup_help, 0), do: module.setup_help(), else: []
  end

  @doc """
  Casts and checks settings or secrets against a provider's fields.

  `kind` is `:config` or `:secrets`. Keys that are not fields are dropped.
  Blank values become absent. Returns the cast map and the errors.
  """
  @spec cast(module(), :config | :secrets, map()) :: {map(), errors()}
  def cast(module, kind, values) when is_map(values) do
    values = Map.new(values, fn {key, value} -> {to_string(key), value} end)

    module.fields()
    |> Enum.filter(&(Field.kind(&1) == kind))
    |> Enum.reduce({%{}, []}, fn field, {acc, errors} ->
      case Field.cast(field, Map.get(values, field.name)) do
        {:ok, nil} -> {acc, errors}
        {:ok, value} -> {Map.put(acc, field.name, value), errors}
        {:error, message} -> {acc, [{field.name, message} | errors]}
      end
    end)
    |> then(fn {acc, errors} -> {acc, Enum.reverse(errors)} end)
  end

  @doc "Errors for required fields of `kind` that have no value in `values`."
  @spec missing(module(), :config | :secrets, map()) :: errors()
  def missing(module, kind, values) do
    for field <- module.fields(),
        Field.kind(field) == kind,
        field.required?,
        not Map.has_key?(values, field.name),
        do: {field.name, "is required"}
  end
end
