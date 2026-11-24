defmodule Slapdash.Vault do
  @moduledoc """
  The Cloak vault behind every AshCloak-encrypted attribute.

  Its only key is the master key: `SLAPDASH_MASTER_KEY` in production (read
  in `config/runtime.exs`), and fixed local keys in `config/dev.exs` and
  `config/test.exs`. The key is 32 bytes, Base64-encoded. Generate one with:

      openssl rand -base64 32

  Values are encrypted with AES-256-GCM, which authenticates the ciphertext,
  so a tampered value fails to decrypt instead of decrypting to garbage.

  Losing the master key makes every encrypted value unreadable, including the
  generated `secret_key_base` and token signing secret. Back it up apart from
  the database.
  """
  use Cloak.Vault, otp_app: :slapdash

  @key_bytes 32

  @impl GenServer
  def init(config) do
    key = config |> Keyword.get(:key) |> decode_key!()

    config =
      config
      |> Keyword.delete(:key)
      |> Keyword.put(:ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}
      )

    {:ok, config}
  end

  # Cloak 1.1.4's AES.GCM cipher returns `{:ok, :error}` when the tag does
  # not verify, rather than an error. Turn that into a real error so a
  # tampered value can never decrypt to the atom :error.
  @impl Cloak.Vault
  def decrypt(ciphertext) do
    case super(ciphertext) do
      {:ok, :error} -> {:error, %Slapdash.Vault.TamperedError{}}
      other -> other
    end
  end

  @impl Cloak.Vault
  def decrypt!(ciphertext) do
    case decrypt(ciphertext) do
      {:ok, plaintext} -> plaintext
      {:error, error} -> raise error
    end
  end

  @doc """
  Decodes a Base64 master key, raising unless it is exactly 32 bytes.

  The error never includes the key itself.
  """
  @spec decode_key!(String.t() | nil) :: binary()
  def decode_key!(encoded) when is_binary(encoded) do
    case Base.decode64(String.trim(encoded)) do
      {:ok, <<_::binary-size(@key_bytes)>> = key} ->
        key

      _ ->
        raise ArgumentError,
              "the master key must be #{@key_bytes} random bytes, Base64-encoded. " <>
                "Generate one with: openssl rand -base64 32"
    end
  end

  def decode_key!(nil) do
    raise ArgumentError,
          "no master key is configured. Set SLAPDASH_MASTER_KEY in production"
  end

  @doc "Generates a new random master key, Base64-encoded."
  @spec generate_key() :: String.t()
  def generate_key, do: @key_bytes |> :crypto.strong_rand_bytes() |> Base.encode64()
end
