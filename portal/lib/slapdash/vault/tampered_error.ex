defmodule Slapdash.Vault.TamperedError do
  @moduledoc """
  Raised when a ciphertext fails authentication: it was changed, or it was
  encrypted with another master key.
  """
  defexception message: "the encrypted value failed authentication"
end
