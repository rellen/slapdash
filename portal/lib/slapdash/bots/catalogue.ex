defmodule Slapdash.Bots.Catalogue do
  @moduledoc """
  The bots in this install. Register them in the application environment:

      config :slapdash, :bots, [Slapdash.Bots.Greeter]
  """

  @doc "The registered bot modules."
  @spec all() :: [module()]
  def all, do: Application.get_env(:slapdash, :bots, [])

  @doc "The bot module for a key."
  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(key) when is_binary(key) do
    case Enum.find(all(), &(&1.key() == key)) do
      nil -> :error
      bot -> {:ok, bot}
    end
  end

  def fetch(_key), do: :error

  @doc "The runner module of a bot."
  @spec runner(module()) :: module()
  def runner(bot) do
    if function_exported?(bot, :runner, 0),
      do: bot.runner(),
      else: Slapdash.Bots.Runners.InProcess
  end
end
