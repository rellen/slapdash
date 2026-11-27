defmodule Slapdash.Connections.Provider.Field do
  @moduledoc """
  One setting or secret of a provider. A field with `secret?: true` is
  stored encrypted and is never shown again after it is saved.

  Types:

  - `:string`: one line of text
  - `:text`: many lines of text, such as a key in PEM format
  - `:integer`: a whole number
  - `:url`: an `http` or `https` URL, stored without a trailing slash
  """

  @enforce_keys [:name, :label]
  defstruct [:name, :label, :help, type: :string, secret?: false, required?: true, default: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          help: String.t() | nil,
          type: :string | :text | :integer | :url,
          secret?: boolean(),
          required?: boolean(),
          default: term()
        }

  @doc "Whether the field is stored in `:config` or in `:secrets`."
  @spec kind(t()) :: :config | :secrets
  def kind(%__MODULE__{secret?: true}), do: :secrets
  def kind(%__MODULE__{}), do: :config

  @doc "Casts a submitted value. A blank value casts to the default."
  @spec cast(t(), term()) :: {:ok, term()} | {:error, String.t()}
  def cast(%__MODULE__{} = field, value) do
    case blank(value) do
      nil -> {:ok, field.default}
      value -> cast_type(field.type, value)
    end
  end

  defp blank(value) when is_binary(value), do: Shoddy.Strings.non_blank(value)
  defp blank(value), do: value

  defp cast_type(:integer, value) when is_integer(value), do: {:ok, value}

  defp cast_type(:integer, value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "must be a whole number"}
    end
  end

  defp cast_type(:url, value) when is_binary(value) do
    value = value |> String.trim() |> String.trim_trailing("/")

    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, value}

      _ ->
        {:error, "must be an http or https URL"}
    end
  end

  defp cast_type(:string, value) when is_binary(value), do: {:ok, String.trim(value)}
  defp cast_type(:text, value) when is_binary(value), do: {:ok, value}
  defp cast_type(_type, _value), do: {:error, "is not valid"}
end
