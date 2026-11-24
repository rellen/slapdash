defmodule Ramshackle.Instance.Boot do
  @moduledoc """
  Loads the generated secrets into the application environment at startup,
  generating them on first boot.

  It runs as a child of the application supervisor after `Ramshackle.Repo`
  and `Ramshackle.Vault`, and before the endpoint, so the endpoint starts with
  the stored `secret_key_base`. It does its work in `start_link/1` and then
  returns `:ignore`, leaving no process behind.

  `config :ramshackle, :boot_secrets` picks the source: `:database` (the
  default, and production) or `:config`, which leaves the values in
  `config/dev.exs` and `config/test.exs` alone.
  """

  alias Ramshackle.Instance.BootSecrets

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc false
  def start_link(_opts) do
    load!()
    :ignore
  end

  @doc """
  Puts the generated secrets into the application environment, generating
  them first if this is the first boot. Does nothing when the source is
  `:config`.
  """
  @spec load!() :: :ok
  def load! do
    case Application.get_env(:ramshackle, :boot_secrets, :database) do
      :config ->
        :ok

      :database ->
        fetch_or_generate!() |> apply_secrets()
    end
  end

  defp fetch_or_generate! do
    case fetch() do
      %BootSecrets{} = secrets ->
        secrets

      nil ->
        Logger.info("First boot: generating secret_key_base and the token signing secret")

        case Ash.create(
               BootSecrets,
               %{
                 secret_key_base: BootSecrets.random_secret(),
                 token_signing_secret: BootSecrets.random_secret()
               },
               action: :generate,
               authorize?: false
             ) do
          {:ok, _} -> :ok
          # Another node won the race to generate them. Use theirs.
          {:error, _} -> :ok
        end

        fetch() || raise "could not generate or load the boot secrets"
    end
  end

  defp fetch do
    BootSecrets
    |> Ash.Query.for_read(:current)
    |> Ash.Query.load([:secret_key_base, :token_signing_secret])
    |> Ash.read_one!(authorize?: false)
  end

  defp apply_secrets(%BootSecrets{} = secrets) do
    endpoint = Application.get_env(:ramshackle, RamshackleWeb.Endpoint, [])

    Application.put_env(
      :ramshackle,
      RamshackleWeb.Endpoint,
      Keyword.put(endpoint, :secret_key_base, secrets.secret_key_base)
    )

    Application.put_env(:ramshackle, :token_signing_secret, secrets.token_signing_secret)

    Application.put_env(
      :ash,
      :keyset_signing_secret,
      :crypto.mac(:hmac, :sha256, secrets.secret_key_base, "ash keyset signing")
    )

    :ok
  end
end
